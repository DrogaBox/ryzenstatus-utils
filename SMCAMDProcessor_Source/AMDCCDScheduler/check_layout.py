#!/usr/bin/env python3 -I
"""Checks AMDCCDScheduler's byte signatures against a kernel file, without booting it.

Reads the layout table (kHead*/kMore*/kPick* and kLayouts) straight from AMDCCDScheduler.cpp, finds the
functions in the kernel's own symbol table and applies the same test the kext does at load, for every
layout. Takes a kernel Mach-O (/System/Library/Kernels/kernel) or a kernel collection from an installer
(BootKernelExtensions.kc: its com.apple.kernel entry is used).

Usage: check_layout.py [kernel or kc, default /System/Library/Kernels/kernel]
Exit status 0 = one layout matches, so the hook would install on this kernel.
"""
import os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
path = sys.argv[1] if len(sys.argv) > 1 else "/System/Library/Kernels/kernel"
src = open(os.path.join(HERE, "AMDCCDScheduler.cpp")).read()


def hexbytes(text):
    return [int(x, 16) for x in re.findall(r"0x[0-9a-fA-F]+", re.sub(r"//[^\n]*", "", text))]


layouts = []
for m in re.finditer(r'\{ "([^"]+)", ((?:0x[0-9a-f]+,\s*){8})kHead(\w+), arrsize\(kHead\w+\), (0x[0-9a-f]+), '
                     r'kMore\w+, arrsize\(kMore\w+\), "(\w+)", (0x[0-9a-f]+), kPick\w+', src):
    name, offs, tag, call_off, picker, pick_off = m.groups()
    head = hexbytes(re.search(r"kHead%s\[\] = \{(.*?)\n\};" % tag, src, re.S).group(1))
    more_src = re.search(r"kMore%s\[\] = \{(.*?)\n\};" % tag, src, re.S).group(1)
    more = [(int(o, 16), bytes(hexbytes(b)), int(n))
            for o, b, n in re.findall(r"\{ (0x[0-9a-fA-F]+),\s*\{([^}]*)\}, (\d+) \}", more_src)]
    pick = bytes(hexbytes(re.search(r"kPick%s\[\] = \{(.*?)\};" % tag, src, re.S).group(1)))
    layouts.append(dict(name=name, head=head, call_off=int(call_off, 16), more=more, picker=picker,
                        pick_off=int(pick_off, 16), pick=pick))
if not layouts:
    sys.exit("no layouts parsed from AMDCCDScheduler.cpp")

data = open(path, "rb").read()


def macho(base):
    """File type, segments (vmaddr, filesize, fileoff), symbols, UUID and fileset entries of the header at `base`."""
    magic, _, _, ftype, ncmds, _, _, _ = struct.unpack_from("<IiiIIIII", data, base)
    if magic != 0xFEEDFACF:
        sys.exit(f"{path}: not a 64-bit Mach-O")
    p, segs, syms, uuid, entries = base + 32, [], {}, "?", {}
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, p)
        if cmd == 0x19:  # LC_SEGMENT_64
            vmaddr, _, fileoff, filesize = struct.unpack_from("<QQQQ", data, p + 24)
            segs.append((vmaddr, filesize, fileoff))
        elif cmd == 0x2:  # LC_SYMTAB
            symoff, nsyms, stroff, _ = struct.unpack_from("<IIII", data, p + 8)
            for i in range(nsyms):
                strx, ntype, _, _, val = struct.unpack_from("<IBBHQ", data, symoff + 16 * i)
                if ntype & 0x0e == 0x0e and val:
                    e = data.index(b"\0", stroff + strx)
                    syms[data[stroff + strx:e].decode(errors="replace")] = val
        elif cmd == 0x1B:  # LC_UUID
            u = data[p + 8:p + 24].hex().upper()
            uuid = f"{u[:8]}-{u[8:12]}-{u[12:16]}-{u[16:20]}-{u[20:]}"
        elif cmd == 0x80000035:  # LC_FILESET_ENTRY
            _, fileoff, name_off = struct.unpack_from("<QQI", data, p + 8)
            entries[data[p + name_off:data.index(b"\0", p + name_off)].decode()] = fileoff
        p += size
    return ftype, segs, syms, uuid, entries


ftype, segs, syms, uuid, entries = macho(0)
if ftype == 0xC:  # MH_FILESET: a kernel collection
    if "com.apple.kernel" not in entries:
        sys.exit(f"{path}: kernel collection without com.apple.kernel")
    _, segs, syms, uuid, _ = macho(entries["com.apple.kernel"])


def file_off(va):
    for vm, fs, fo in segs:
        if vm <= va < vm + fs:
            return va - vm + fo
    sys.exit(f"0x{va:x} not in a file-backed segment")


def check(L):
    for n in ("_choose_starting_pset", "_get_threadtask", L["picker"]):
        if n not in syms:
            return f"no {n[1:]}"
    fn = syms["_choose_starting_pset"]
    p = data[file_off(fn):file_off(fn) + 0x400]
    for i, b in enumerate(L["head"]):
        if b <= 0xff and p[i] != b:
            return f"byte 0x{i:x} is {p[i]:02x}, expected {b:02x}"
    c = L["call_off"]
    if fn + c + 5 + int.from_bytes(p[c + 1:c + 5], "little", signed=True) != syms["_get_threadtask"]:
        return f"call at 0x{c:x} is not get_threadtask"
    for off, b, n in L["more"]:
        if len(b) != n or p[off:off + n] != b:
            return f"bytes at 0x{off:x} differ"
    q = file_off(syms[L["picker"]]) + L["pick_off"]
    if data[q:q + len(L["pick"])] != L["pick"]:
        return f"{L['picker'][1:]} bytes at 0x{L['pick_off']:x} differ"
    return None


count = "sched_num_psets" if "_sched_num_psets" in syms else ("pset_node0" if "_pset_node0" in syms else None)
print(f"{path} (kernel UUID {uuid})")
match = None
for L in layouts:
    why = check(L)
    print(f"  {L['name']}: " + ("MATCH" if why is None else why))
    if why is None and match is None:
        match = L
if match and count:
    print(f"  -> the hook installs with the {match['name']} layout (pset count from {count})")
elif match:
    print("  -> layout matches but neither sched_num_psets nor pset_node0 exists: the hook stays off")
else:
    print("  -> no layout matches: the hook stays off")
sys.exit(0 if match and count else 1)
