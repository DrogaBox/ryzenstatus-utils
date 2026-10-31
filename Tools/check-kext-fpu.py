#!/usr/bin/env python3
"""Fail if code that runs in interrupt context uses the FPU.

mp_rendezvous handlers and the pmRyzen idle hook run on top of whatever
thread each CPU was executing, and xnu does not save that thread's FPU/XMM
state for them. Any SSE or x87 instruction there silently corrupts the
registers of the interrupted program. The kext is built with SSE enabled, so
a single float in one of these paths compiles without a warning; this check
reads the disassembly instead.

Roots: every lambda converted to a `void (*)(void *)` (the only signature
mp_rendezvous takes) plus the pmRyzen idle/P-state handlers. Every function
of the kext they call, directly or not, is checked too.

Usage: Tools/check-kext-fpu.py path/to/AMDRyzenCPUPowerManagement
"""
import re
import subprocess
import sys

FPU = re.compile(
    r"%[xy]mm\d|%st\b|\bf(ld|st|stp|ild|istp|mul|add|div|sub|xch|chs|abs|comi?p?)\b"
    r"|\bcvt|\bmovs[sd]\b|\bmovap|\bmovup|\bmovd\b|\bmovq\s+%xmm|[ls]dmxcsr|\bfx(save|rstor)"
)
ROOTS = re.compile(r"__invokeEPv$|^_pmRyzen_doPState_reset$|^_pmRyzen_machine_idle$")


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
    roots = [name for name in funcs if ROOTS.search(name)]
    if not roots:
        sys.exit("no rendezvous handlers found; is this the AMDRyzenCPUPowerManagement binary?")

    seen, stack, bad = set(), list(roots), []
    while stack:
        name = stack.pop()
        if name in seen or name not in funcs:
            continue
        seen.add(name)
        body = funcs[name]
        hits = [line.strip() for line in body if FPU.search(line)]
        if hits:
            bad.append((name, hits))
        for callee in re.findall(r"callq\s+(\S+)", "\n".join(body)):
            if callee in funcs:
                stack.append(callee)

    print(f"{len(roots)} interrupt-context roots, {len(seen)} functions checked")
    for name, hits in bad:
        print(f"FPU in {name}:")
        for hit in hits[:5]:
            print(f"    {hit}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
