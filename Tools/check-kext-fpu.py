#!/usr/bin/env python3
"""Fail if code that runs in interrupt context uses the FPU.

mp_rendezvous handlers and the pmRyzen scheduler hooks run on top of
whatever thread each CPU was executing, and xnu does not save that thread's
FPU/SSE state for them. Any SSE, AVX or x87 instruction there silently
corrupts the registers of the interrupted program. The kext is built with SSE
enabled, so a single float in one of these paths compiles without a warning;
this check reads the disassembly instead.

Roots: every function whose address is loaded (`leaq sym(%rip)`) between the
previous call and a call or tail call to mp_rendezvous /
mp_rendezvous_no_intrs / mp_cpus_call, read from the call sites themselves so
a handler is found however its name is mangled, plus the pmRyzen hooks xnu
calls through its dispatch table (machine idle, choose CPU). A call site
whose handler cannot be identified fails the check. Every function of this
binary the roots reach through direct calls and tail calls is checked too.

Limits: indirect calls (function pointers, such as the kernel's
wrmsr_carefully) are not followed and are only counted, and code outside this
binary (the kernel, other kexts) is not checked.

Usage: Tools/check-kext-fpu.py path/to/AMDRyzenCPUPowerManagement
Exit status: 0 clean, 1 FPU use or an unidentified cross-CPU call site.
"""
import re
import subprocess
import sys

FPU = re.compile(
    r"%[xyz]mm\d|%mm\d|%st\b"
    r"|\bf(ld|st|stp|ild|istp|mul|add|div|sub|xch|chs|abs|comi?p?|ucomi?p?)\b"
    r"|\bfn?(ldcw|stcw|init|save|rstor|stsw|clex|wait)\b|\bemms\b|\bvzero(upper|all)\b"
    r"|\bcvt|\bmovs[sd]\b|\bmovap|\bmovup|\bmovd\b|[ls]dmxcsr|\bfx(save|rstor)|\bx(save|rstor)"
)
CROSS_CALL = re.compile(r"\b(callq|jmp|jmpq)\s+_(mp_rendezvous|mp_rendezvous_no_intrs|mp_cpus_call\w*)\b")
DIRECT = re.compile(r"\b(callq|jmp|jmpq)\s+(_\S+)")
INDIRECT = re.compile(r"\b(callq|jmp|jmpq)\s+\*")
LOAD_ADDR = re.compile(r"leaq\s+(\S+)\(%rip\)")
FIXED_ROOTS = ("_pmRyzen_machine_idle", "_pmRyzen_choose_cpu")


def handler_roots(funcs):
    """Functions handed to a cross-CPU call, or an error per unresolved site."""
    roots, unresolved = set(), []
    for caller, body in funcs.items():
        for i, line in enumerate(body):
            if not CROSS_CALL.search(line):
                continue
            found = set()
            for prev in reversed(body[:i]):
                if "callq" in prev:
                    break
                m = LOAD_ADDR.search(prev)
                if m and m.group(1) in funcs:
                    found.add(m.group(1))
            if found:
                roots |= found
            else:
                unresolved.append(f"{caller}: {line.strip()}")
    roots |= {name for name in FIXED_ROOTS if name in funcs}
    return roots, unresolved


def functions(binary):
    out = subprocess.run(["otool", "-tvV", binary], capture_output=True, text=True, check=True).stdout
    funcs, cur = {}, None
    for line in out.splitlines():
        if line.endswith(":") and not line[:1].isdigit() and not line.startswith(("\t", " ")):
            cur = line[:-1]
            funcs[cur] = []
        elif cur is not None:
            funcs[cur].append(line)
    return funcs


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    funcs = functions(sys.argv[1])
    roots, unresolved = handler_roots(funcs)
    if unresolved:
        print("cross-CPU calls whose handler could not be identified:")
        for site in unresolved:
            print(f"    {site}")
        sys.exit(1)
    if not roots:
        sys.exit("no rendezvous handlers found; is this the AMDRyzenCPUPowerManagement binary?")

    seen, stack, bad, indirect = set(), list(roots), [], 0
    while stack:
        name = stack.pop()
        if name in seen or name not in funcs:
            continue
        seen.add(name)
        body = funcs[name]
        hits = [line.strip() for line in body if FPU.search(line)]
        if hits:
            bad.append((name, hits))
        for line in body:
            if INDIRECT.search(line):
                indirect += 1
            m = DIRECT.search(line)
            if m and m.group(2) in funcs:
                stack.append(m.group(2))

    print(f"{len(roots)} interrupt-context roots, {len(seen)} functions checked, "
          f"{indirect} indirect calls not followed")
    for name, hits in bad:
        print(f"FPU in {name}:")
        for hit in hits[:5]:
            print(f"    {hit}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
