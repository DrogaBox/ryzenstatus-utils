#!/usr/bin/env python3 -I
"""Checks AMDCCDScheduler's byte signature against a kernel file, without booting it.

Reads kSigHead / kCallOff / kSigMore / kSmtSig straight from AMDCCDScheduler.cpp, finds
_choose_starting_pset, _get_threadtask and _choose_processor_smt in the kernel's symbol table (nm), and
applies the same test the kext does at load.

Usage: check_layout.py [kernel, default /System/Library/Kernels/kernel]
Exit status 0 = the hook would install on this kernel.
"""
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
kernel = sys.argv[1] if len(sys.argv) > 1 else "/System/Library/Kernels/kernel"
src = open(os.path.join(HERE, "AMDCCDScheduler.cpp")).read()

head = re.search(r"kSigHead\[\] = \{(.*?)\n\};", src, re.S).group(1)
head = [int(x, 16) for x in re.findall(r"0x[0-9a-fA-F]+", re.sub(r"//[^\n]*", "", head))]
call_off = int(re.search(r"kCallOff = (0x[0-9a-fA-F]+)", src).group(1), 16)
more = []
for off, body, ln in re.findall(r"\{ (0x[0-9a-fA-F]+),\s*\{([^}]*)\}, (\d+) \}", src):
    more.append((int(off, 16), bytes(int(x, 16) for x in re.findall(r"0x[0-9a-fA-F]+", body)), int(ln)))
smt_off = int(re.search(r"kSmtSigOff = (0x[0-9a-fA-F]+)", src).group(1), 16)
smt_sig = bytes(int(x, 16) for x in re.findall(r"0x[0-9a-fA-F]+", re.search(r"kSmtSig\[\] = \{(.*?)\};", src, re.S).group(1)))

syms = {}
for line in subprocess.run(["nm", kernel], capture_output=True, text=True, check=True).stdout.splitlines():
    parts = line.split()
    if len(parts) == 3 and parts[2] in ("_choose_starting_pset", "_get_threadtask", "_choose_processor_smt"):
        syms[parts[2]] = int(parts[0], 16)
if len(syms) != 3:
    sys.exit(f"symbols missing: {syms}")

# Map the function's vmaddr to a file offset through the __TEXT_EXEC / __TEXT segments (otool -l).
segs = []
cur = {}
for line in subprocess.run(["otool", "-l", kernel], capture_output=True, text=True, check=True).stdout.splitlines():
    line = line.strip()
    if line.startswith("cmd LC_SEGMENT_64"):
        cur = {}
        segs.append(cur)
    for k in ("vmaddr", "vmsize", "fileoff", "filesize"):
        if line.startswith(k + " "):
            cur[k] = int(line.split()[1], 0)

def file_off(va):
    for s in segs:
        if s.get("vmaddr", 0) <= va < s.get("vmaddr", 0) + s.get("filesize", 0):
            return va - s["vmaddr"] + s["fileoff"]
    sys.exit(f"0x{va:x} not in a file-backed segment")

data = open(kernel, "rb").read()
fn = syms["_choose_starting_pset"]
p = data[file_off(fn):file_off(fn) + 0x240]
ok = True
for i, b in enumerate(head):
    if b <= 0xff and p[i] != b:
        print(f"head byte 0x{i:x}: {p[i]:02x} != {b:02x}"); ok = False
rel = int.from_bytes(p[call_off + 1:call_off + 5], "little", signed=True)
target = fn + call_off + 5 + rel
if target != syms["_get_threadtask"]:
    print(f"call target 0x{target:x} != get_threadtask 0x{syms['_get_threadtask']:x}"); ok = False
for off, b, ln in more:
    if len(b) != ln or p[off:off + ln] != b:
        print(f"bytes at 0x{off:x} differ: {p[off:off + ln].hex()} vs {b.hex()}"); ok = False
smt = syms["_choose_processor_smt"]
q = data[file_off(smt) + smt_off:file_off(smt) + smt_off + len(smt_sig)]
if q != smt_sig:
    print(f"choose_processor_smt bytes at 0x{smt_off:x} differ: {q.hex()} vs {smt_sig.hex()}"); ok = False
uuid = subprocess.run(["dwarfdump", "--uuid", kernel], capture_output=True, text=True).stdout.split()[1]
print(f"{kernel} {uuid}: head {len(head)} bytes, {len(more)} extra checks, choose_processor_smt {len(smt_sig)} bytes, "
      f"call -> get_threadtask: "
      + ("MATCH, the hook installs" if ok else "MISMATCH, the hook stays off"))
sys.exit(0 if ok else 1)
