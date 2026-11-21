"""lldb dry run for AV1: lets AMDRadeonVADriver2 build the VCN decode command for the first
frame of a file, writes that command to <out_dir>/vcn_msg.bin, and kills the process BEFORE
VAContext::submitDataBuffers hands it to the kernel. Read the dump with vcnmsg.py.

  lldb --batch -o "command script import tools/driver/dryrun.py" \\
       -o "dryrun <out_dir> <decode_ivf> <file.ivf> [more decode_ivf arguments]"

<decode_ivf> is decode/build/gpu/decode_ivf, built by decode/tests/gpu/build.sh.

What still reaches the GPU: the driver's own AV1 session setup, the same one it sends for
any AV1 context. What never does: a decode command built from our parameters.

How it stays safe:
  - the script arms decode_ivf itself (VCNAV1_ALLOW_GPU), so nothing has to be armed by hand;
  - decode_ivf calls vcnav1_dryrun_checkpoint() right before its first decode command. There
    the script checks that its trap on the driver's submit function is in place, and kills
    the process if it is not;
  - any error inside the script, and any stop it did not expect, kills the process. The
    process is never resumed from a stop.
It refuses to start when decode_ivf lacks the checkpoint or the dump helper, or when the
output folder has a character the dump helper does not take.

The trap is the function VAContext::submitDataBuffers. On a new driver build, compare that
function and its callers with dscdiff.py first: a driver that submits some other way would
not be stopped.
"""
import os
import re
import shlex
import traceback

import lldb

ARM = "VCNAV1_ALLOW_GPU=yes-i-know-it-can-hang"
STATE = {"msg": None, "out": None, "trap": None, "trap_ok": False, "dumped": False, "killed": False}


def _kill(frame, why):
    print(f"[dryrun] KILL: {why}", flush=True)
    STATE["killed"] = True
    frame.GetThread().GetProcess().Kill()


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
    n = STATE["trap"].GetNumResolvedLocations()
    print(f"[dryrun] checkpoint: submit trap resolved locations = {n}", flush=True)
    if n < 1:
        _kill(frame, "kernel-submission trap not armed")
        return True
    STATE["trap_ok"] = True
    return False


@safe
def on_setmsg(frame, bp_loc, extra, d):
    proc = frame.GetThread().GetProcess()
    err = lldb.SBError()
    this = frame.FindRegister("rdi").GetValueAsUnsigned()
    # this -> +16 -> +88 -> +224 is the message buffer. A read that fails leaves the message
    # unknown: the submit is then stopped without a dump.
    addr = this
    for off in (16, 88, 224):
        addr = proc.ReadPointerFromMemory(addr + off, err)
        if not err.Success() or not addr:
            print(f"[dryrun] SetDecodeMessageFields this={this:#x}: message buffer not found", flush=True)
            STATE["msg"] = None
            return False
    STATE["msg"] = addr
    print(f"[dryrun] SetDecodeMessageFields this={this:#x} msgbuf={addr:#x}", flush=True)
    return False


@safe
def on_submit(frame, bp_loc, extra, d):
    if STATE["killed"]:
        return True
    if not STATE["trap_ok"]:
        th = frame.GetThread()
        bt = " <- ".join(
            (th.GetFrameAtIndex(i).GetFunctionName() or "?") for i in range(1, min(7, th.GetNumFrames()))
        )
        print(f"[dryrun] setup-phase submit allowed: {bt}", flush=True)
        return False
    # Past the checkpoint: this is our decode command. Whatever happens to the dump, the
    # process dies here.
    try:
        if STATE["msg"]:
            path = os.path.join(STATE["out"], "vcn_msg.bin")
            expr = f'(int)vcnav1_dump((void*){STATE["msg"]:#x}, 4096, "{path}")'
            opts = lldb.SBExpressionOptions()
            opts.SetIgnoreBreakpoints(True)
            opts.SetTryAllThreads(False)
            v = frame.EvaluateExpression(expr, opts)
            print(f"[dryrun] in-process dump wrote {v.GetValue()} bytes ({v.GetError()}) -> {path}", flush=True)
            STATE["dumped"] = v.GetValueAsSigned() == 4096
        else:
            print("[dryrun] submit reached but message pointer unknown", flush=True)
    finally:
        _kill(frame, "stopping before kernel submission (dry run)")
    return True


def _refuse(why):
    print(f"[dryrun] not started: {why}", flush=True)


def dryrun(debugger, command, result, d):
    args = shlex.split(command)
    if len(args) < 3:
        _refuse("usage: dryrun <out_dir> <decode_ivf> <file.ivf> [arguments]")
        return
    out = os.path.abspath(args[0])
    exe, prog_args = args[1], args[2:]
    # The same rule as vcnav1_dump(), checked before anything runs.
    if not re.fullmatch(r"[A-Za-z0-9._/-]+", out) or ".." in out:
        _refuse(f"the output folder {out!r} may only hold letters, digits and . _ / -")
        return
    os.makedirs(out, exist_ok=True)
    STATE["out"] = out
    target = debugger.CreateTarget(exe)
    if not target.IsValid():
        _refuse(f"cannot open {exe}")
        return
    # Our own two functions are in the executable, so they must resolve before the launch.
    checkpoint = target.BreakpointCreateByName("vcnav1_dryrun_checkpoint")
    if checkpoint.GetNumLocations() < 1:
        _refuse(f"{exe} has no vcnav1_dryrun_checkpoint: nothing would arm the trap")
        return
    if target.FindFunctions("vcnav1_dump").GetSize() < 1:
        _refuse(f"{exe} has no vcnav1_dump: build it with decode/tests/gpu/build.sh")
        return
    checkpoint.SetScriptCallbackFunction(f"{__name__}.on_checkpoint")
    # The driver is not loaded yet: these two resolve when it is, and the checkpoint checks.
    STATE["trap"] = target.BreakpointCreateByRegex(r"^VAContext::submitDataBuffers")
    STATE["trap"].SetScriptCallbackFunction(f"{__name__}.on_submit")
    setmsg = target.BreakpointCreateByRegex(r"^AvdVcnAv1DecDataProcessor::SetDecodeMessageFields")
    setmsg.SetScriptCallbackFunction(f"{__name__}.on_setmsg")
    env = [f"{k}={v}" for k, v in os.environ.items() if k != "VCNAV1_ALLOW_GPU"] + [ARM]
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
        print(f"[dryrun] DRY RUN OK: {os.path.join(out, 'vcn_msg.bin')} written, nothing was submitted", flush=True)
    else:
        print("[dryrun] DRY RUN FAILED: no decode command was dumped", flush=True)


def __lldb_init_module(debugger, d):
    debugger.HandleCommand(f"command script add -f {__name__}.dryrun dryrun")
