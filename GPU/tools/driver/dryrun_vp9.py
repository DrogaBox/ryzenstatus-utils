"""lldb dry run for VP9. Apple's driver has no VP9 path, so nothing here is compared with an
Apple message: the script dumps what vcnvp9.c built and kills the process before the VP9
command can reach the kernel. Read the dumps with vcnmsg.py.

  lldb --batch -o "command script import tools/driver/dryrun_vp9.py" \\
       -o "dryrun_vp9 <session|decode> <out_dir> <decode_vp9> <file> [more decode_vp9 arguments]"

<decode_vp9> is decode/build/gpu/decode_vp9, built by decode/tests/gpu/build.sh.

  session  VCNVP9_SESSION=vp9. Dumps the VP9 create message to create_msg.bin and kills the
           process before it is submitted. Nothing VP9 reaches the GPU.
  decode   VCNVP9_SESSION=av1. The only thing that goes out is a normal AV1 create on the
           first VCN instance, checked here before it is allowed. Then the first VP9 decode
           message is dumped (vcn_msg.bin, it_probs.bin, ctx_probs.bin) and the process is
           killed before it is submitted.

How it stays safe:
  - VCNVP9_ALLOW_GPU is removed from the environment. decode_vp9 only opens the driver here
    because it sees a debugger, and VCNVP9_SESSION=av1 is refused without one;
  - decode_vp9 calls vcnvp9_dryrun_checkpoint() before it creates the session (phase 1) and
    before every decode command (phase 2). There the script checks that its trap on the
    driver's submit function is in place, and kills the process if it is not;
  - any error inside the script, and any stop it did not expect, kills the process. The
    process is never resumed from a stop.
It refuses to start when decode_vp9 lacks one of its hook functions or the dump helper, or
when the output folder has a character the dump helper does not take.

The trap is the function VAContext::submitDataBuffers. On a new driver build, compare that
function and its callers with dscdiff.py first: a driver that submits some other way would
not be stopped.
"""
import os
import re
import shlex
import traceback

import lldb

STATE = {
    "mode": None,
    "out": None,
    "phase": 0,
    "session_msg": None,
    "session_seen": False,
    "data": None,
    "dumped": False,
    "killed": False,
    "trap": None,
}

VCN_CODEC_AV1 = 0x13
VCN_CODEC_VP9 = 0x11
HOOKS = (
    ("vcnvp9_dryrun_checkpoint", "on_checkpoint"),
    ("vcnvp9_session_message", "on_session_message"),
    ("vcnvp9_message_built", "on_message_built"),
)


def _kill(frame, why):
    print(f"[dryrun] KILL: {why}", flush=True)
    STATE["killed"] = True
    frame.GetThread().GetProcess().Kill()


def _u32(proc, addr):
    err = lldb.SBError()
    v = proc.ReadUnsignedFromMemory(addr, 4, err)
    return v if err.Success() else None


def _dump(frame, addr, size, name):
    path = os.path.join(STATE["out"], name)
    opts = lldb.SBExpressionOptions()
    opts.SetIgnoreBreakpoints(True)
    opts.SetTryAllThreads(False)
    v = frame.EvaluateExpression(f'(int)vcnvp9_dump((void*){addr:#x}, {size}, "{path}")', opts)
    print(f"[dryrun] dump {name}: {v.GetValue()} bytes ({v.GetError()})", flush=True)
    return v.GetValueAsSigned() == size


def safe(fn):
    """A callback that raises would leave the process stopped at the breakpoint with nothing
    decided. Kill it instead."""

    def wrapped(frame, bp_loc, extra, d):
        try:
            return fn(frame, bp_loc, extra, d)
        except Exception:
            traceback.print_exc()
            _kill(frame, f"exception in {fn.__name__}")
            return True

    return wrapped


@safe
def on_checkpoint(frame, bp_loc, extra, d):
    phase = frame.FindRegister("rdi").GetValueAsUnsigned() & 0xFFFFFFFF
    n = STATE["trap"].GetNumResolvedLocations()
    print(f"[dryrun] checkpoint {phase}: submit trap locations = {n}", flush=True)
    if n < 1:
        _kill(frame, "kernel submission trap not armed")
        return True
    STATE["phase"] = phase
    return False


@safe
def on_session_message(frame, bp_loc, extra, d):
    proc = frame.GetThread().GetProcess()
    msg = frame.FindRegister("rdi").GetValueAsUnsigned()
    STATE["session_msg"] = msg
    STATE["session_seen"] = True
    stream = _u32(proc, msg + 40)
    print(
        f"[dryrun] create message at {msg:#x}: msg_type={_u32(proc, msg + 12)} "
        f"stream_type={stream if stream is None else hex(stream)} "
        f"{_u32(proc, msg + 48)}x{_u32(proc, msg + 52)}",
        flush=True,
    )
    want = VCN_CODEC_VP9 if STATE["mode"] == "session" else VCN_CODEC_AV1
    if stream != want:
        _kill(frame, f"create message has stream type {stream}, this mode needs {want:#x}")
        return True
    return False


@safe
def on_message_built(frame, bp_loc, extra, d):
    STATE["data"] = frame.FindRegister("rdi").GetValueAsUnsigned()
    print(f"[dryrun] decode message built, driver data block {STATE['data']:#x}", flush=True)
    return False


@safe
def on_submit(frame, bp_loc, extra, d):
    if STATE["killed"]:
        return True
    proc = frame.GetThread().GetProcess()
    err = lldb.SBError()
    th = frame.GetThread()
    bt = " <- ".join((th.GetFrameAtIndex(i).GetFunctionName() or "?") for i in range(1, min(6, th.GetNumFrames())))
    if STATE["phase"] == 0:
        print(f"[dryrun] driver setup submit allowed: {bt}", flush=True)
        return False
    if STATE["mode"] == "session":
        if not STATE["session_seen"]:
            print(f"[dryrun] submit before the create message allowed: {bt}", flush=True)
            return False
        try:
            STATE["dumped"] = _dump(frame, STATE["session_msg"], 4096, "create_msg.bin")
        finally:
            _kill(frame, "stopping before the VP9 create message reaches the kernel")
        return True
    # decode mode
    if STATE["phase"] == 1:
        if STATE["session_seen"]:
            stream = _u32(proc, STATE["session_msg"] + 40)
            if stream != VCN_CODEC_AV1:
                _kill(frame, f"create message changed to {stream}")
                return True
        print(f"[dryrun] AV1 session submit allowed: {bt}", flush=True)
        return False
    # Phase 2: our decode command. Whatever happens to the dumps, the process dies here.
    try:
        data = STATE["data"]
        if not data:
            print("[dryrun] decode submit reached without our message builder running", flush=True)
            return True
        msg = proc.ReadPointerFromMemory(data + 224, err)
        it = proc.ReadPointerFromMemory(data + 632, err)
        ctx_tex = proc.ReadPointerFromMemory(data + 464, err)
        ctx = proc.ReadPointerFromMemory(ctx_tex + 152, err) if ctx_tex else 0
        ok = _dump(frame, msg, 4096, "vcn_msg.bin")
        ok = _dump(frame, it, 2560, "it_probs.bin") and ok
        if ctx:
            ok = _dump(frame, ctx, 2304, "ctx_probs.bin") and ok
        STATE["dumped"] = ok
    finally:
        _kill(frame, "stopping before the VP9 decode message reaches the kernel")
    return True


def _refuse(why):
    print(f"[dryrun] not started: {why}", flush=True)


def dryrun_vp9(debugger, command, result, d):
    args = shlex.split(command)
    if len(args) < 4 or args[0] not in ("session", "decode"):
        _refuse("usage: dryrun_vp9 <session|decode> <out_dir> <decode_vp9> <file> [arguments]")
        return
    out = os.path.abspath(args[1])
    exe, prog_args = args[2], args[3:]
    # The same rule as vcnvp9_dump(), checked before anything runs.
    if not re.fullmatch(r"[A-Za-z0-9._/-]+", out) or ".." in out:
        _refuse(f"the output folder {out!r} may only hold letters, digits and . _ / -")
        return
    os.makedirs(out, exist_ok=True)
    STATE["mode"], STATE["out"] = args[0], out
    target = debugger.CreateTarget(exe)
    if not target.IsValid():
        _refuse(f"cannot open {exe}")
        return
    # Our own functions are in the executable, so they must resolve before the launch.
    hooks = []
    for name, fn in HOOKS:
        b = target.BreakpointCreateByName(name)
        if b.GetNumLocations() < 1:
            _refuse(f"{exe} has no {name}: build it with decode/tests/gpu/build.sh")
            return
        hooks.append((b, fn))
    if target.FindFunctions("vcnvp9_dump").GetSize() < 1:
        _refuse(f"{exe} has no vcnvp9_dump: build it with decode/tests/gpu/build.sh")
        return
    for b, fn in hooks:
        b.SetScriptCallbackFunction(f"{__name__}.{fn}")
    # The driver is not loaded yet: the trap resolves when it is, and the checkpoint checks.
    trap = target.BreakpointCreateByRegex(r"^VAContext::submitDataBuffers")
    trap.SetScriptCallbackFunction(f"{__name__}.on_submit")
    STATE["trap"] = trap
    session = "vp9" if STATE["mode"] == "session" else "av1"
    env = [f"{k}={v}" for k, v in os.environ.items() if k not in ("VCNVP9_ALLOW_GPU", "VCNVP9_SESSION", "VCNVP9_DRYRUN")]
    env.append(f"VCNVP9_SESSION={session}")
    env.append("VCNVP9_DRYRUN=1")  # the decoder opens the driver under a debugger only with this
    li = lldb.SBLaunchInfo(prog_args)
    li.SetEnvironmentEntries(env, False)
    err = lldb.SBError()
    debugger.SetAsync(False)
    proc = target.Launch(li, err)
    print(f"[dryrun] launch: {err}", flush=True)
    # Every breakpoint above continues on its own or kills. A stop that comes back here was
    # not handled by its callback (it could not be found, or lldb stopped for a crash), so
    # nothing is known about the trap: never resume.
    if not STATE["killed"] and proc.IsValid() and proc.GetState() == lldb.eStateStopped:
        why = "; ".join(t.GetStopDescription(120) for t in proc if t.GetStopReason() != lldb.eStopReasonNone)
        print(f"[dryrun] KILL: unexpected stop ({why or 'no reason given'})", flush=True)
        STATE["killed"] = True
        proc.Kill()
    print(
        f"[dryrun] final state={proc.GetState()} exit={proc.GetExitStatus()} "
        f"dumped={STATE['dumped']} killed={STATE['killed']}",
        flush=True,
    )
    if STATE["dumped"]:
        print(f"[dryrun] DRY RUN OK: messages written to {out}, nothing VP9 was submitted", flush=True)
    else:
        print("[dryrun] DRY RUN FAILED: no message was dumped", flush=True)


def __lldb_init_module(debugger, d):
    debugger.HandleCommand(f"command script add -f {__name__}.dryrun_vp9 dryrun_vp9")
