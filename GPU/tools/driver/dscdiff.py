#!/usr/bin/env python3
"""Compare one image between two dyld shared caches, to validate a new macOS build.

  dscdiff.py info <cache> <image-substring>...
      LC_UUID and a hash of every section of each matching image.
  dscdiff.py diff <cacheA> <cacheB> <image-substring> [-v]
      Function-level diff. Each function is disassembled; RIP-relative displacements and branch
      targets outside the function are masked, so code or data that only moved does not count.

<cache> is the main cache file. On a running Mac:
    /System/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_x86_64h
For a macOS build that is not installed, unpack the update's cryptex image with rawpatch
(decode/build/gpu/rawpatch), mount it read-only, and use the same path inside it. The numbered
subcaches are picked up from the same folder. It only reads the cache files.

Use it on AMDRadeonVADriver2 when a macOS update comes out:
  - info gives the driver's UUID. The same UUID as a build in kValidatedDrivers
    (decode/av1/vcnav1.c, decode/vp9/vcnvp9.c) means the same binary.
  - a new UUID: run diff against a validated cache, and review every changed function on the
    decode path before the UUID is added anywhere.
The output describes Apple's code: keep it out of this repository.

diff needs the capstone Python module (pip install capstone).
"""
import difflib
import glob
import hashlib
import mmap
import struct
import sys


class Cache:
    def __init__(self, main):
        self.maps, self.mm, self.handles = [], {}, []
        files = [main] + sorted(f for f in glob.glob(main + ".*") if f.rsplit(".", 1)[1].isdigit())
        for f in files:
            fh = open(f, "rb")
            self.handles.append(fh)
            m = mmap.mmap(fh.fileno(), 0, prot=mmap.PROT_READ)
            self.mm[f] = m
            moff, mcnt = struct.unpack_from("<II", m, 0x10)
            for k in range(mcnt):
                addr, size, foff = struct.unpack_from("<QQQ", m, moff + 32 * k)
                self.maps.append((addr, size, foff, f))
        self.main = self.mm[main]

    def rd(self, addr, n):
        for a, size, off, f in self.maps:
            if a <= addr < a + size:
                return self.mm[f][off + addr - a:off + addr - a + n]
        raise KeyError(hex(addr))

    def images(self, subs):
        m = self.main
        ioff, icnt = struct.unpack_from("<II", m, 0x18)
        if ioff == 0:
            ioff, icnt = struct.unpack_from("<II", m, 0x1C0)
        for k in range(icnt):
            addr, _, _, poff, _ = struct.unpack_from("<QQQII", m, ioff + 32 * k)
            path = m[poff:m.find(b"\0", poff)].decode()
            if any(s in path for s in subs):
                yield addr, path


def load(cache, base):
    """Parse the Mach-O header at base: uuid, sections, function starts, symbol names."""
    ncmds, szc = struct.unpack_from("<II", cache.rd(base, 32), 16)
    lc = cache.rd(base + 32, szc)
    p, uuid, sects, le, fs, st, tbase = 0, "", [], None, None, None, base
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", lc, p)
        if cmd == 0x1B:
            uuid = lc[p + 8:p + 24].hex().upper()
        elif cmd == 0x19:
            name = lc[p + 8:p + 24].rstrip(b"\0").decode()
            vm, _, fo = struct.unpack_from("<QQQ", lc, p + 24)
            if name == "__LINKEDIT":
                le = (vm, fo)
            if name == "__TEXT":
                tbase = vm
            for i in range(struct.unpack_from("<I", lc, p + 64)[0]):
                q = p + 72 + 80 * i
                sa, ss = struct.unpack_from("<QQ", lc, q + 32)
                sects.append((name, lc[q:q + 16].rstrip(b"\0").decode(), sa, ss))
        elif cmd == 0x26:
            fs = struct.unpack_from("<II", lc, p + 8)
        elif cmd == 0x2:
            st = struct.unpack_from("<IIII", lc, p + 8)
        p += size
    return uuid, sects, le, fs, st, tbase


def cmd_info(cache_path, subs):
    cache = Cache(cache_path)
    for base, path in cache.images(subs):
        uuid, sects, *_ = load(cache, base)
        print(path)
        print("  UUID %s base %#x" % (uuid, base))
        for seg, sect, sa, ss in sects:
            try:
                data = cache.rd(sa, ss)
            except KeyError:
                data = b""
            print("   %-12s %-18s size %8x sha1 %s" % (seg, sect, ss, hashlib.sha1(data).hexdigest()[:16]))


def functions(cache_path, sub):
    try:
        import capstone
        from capstone import x86 as cx
    except ImportError:
        sys.exit("dscdiff.py diff needs the capstone Python module (pip install capstone)")

    cache = Cache(cache_path)
    found = list(cache.images([sub]))
    if not found:
        sys.exit("image not found: " + sub)
    base, path = found[0]
    uuid, sects, le, fs, st, tbase = load(cache, base)
    lea = lambda off: le[0] + off - le[1]
    ta, ts = next((sa, ss) for seg, sect, sa, ss in sects if seg == "__TEXT" and sect == "__text")
    code = cache.rd(ta, ts)

    data, starts, addr, i = cache.rd(lea(fs[0]), fs[1]), [], tbase, 0
    while i < len(data):
        v = shift = 0
        while True:
            b = data[i]
            i += 1
            v |= (b & 0x7F) << shift
            shift += 7
            if not b & 0x80:
                break
        if v == 0:
            break
        addr += v
        if ta <= addr < ta + ts:
            starts.append(addr)

    names = {}
    symoff, nsyms, stroff, strsize = st
    syms, strs = cache.rd(lea(symoff), nsyms * 16), cache.rd(lea(stroff), strsize)
    for k in range(nsyms):
        strx, typ, _, _, val = struct.unpack_from("<IBBHQ", syms, 16 * k)
        if typ & 0xE0 or (typ & 0x0E) != 0x0E:
            continue
        names.setdefault(val, strs[strx:strs.find(b"\0", strx)].decode("utf-8", "replace"))

    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = True
    out = []
    for k, lo in enumerate(starts):
        hi = starts[k + 1] if k + 1 < len(starts) else ta + ts
        lines = []
        for ins in md.disasm(code[lo - ta:hi - ta], lo):
            ops = []
            branch = cx.X86_GRP_JUMP in ins.groups or cx.X86_GRP_CALL in ins.groups
            for o in ins.operands:
                if o.type == cx.X86_OP_IMM and branch:
                    ops.append("+%x" % (o.imm - lo) if lo <= o.imm < hi else "EXT")
                elif o.type == cx.X86_OP_MEM and o.mem.base == cx.X86_REG_RIP:
                    ops.append("[rip+X]")
                elif o.type == cx.X86_OP_MEM:
                    ops.append("[%d+%d*%d+%x]" % (o.mem.base, o.mem.index, o.mem.scale, o.mem.disp & (2**64 - 1)))
                elif o.type == cx.X86_OP_IMM:
                    ops.append("%x" % (o.imm & (2**64 - 1)))
                else:
                    ops.append("r%d" % o.reg)
            lines.append(ins.mnemonic + " " + ",".join(ops))
        out.append((hashlib.sha1("\n".join(lines).encode()).hexdigest(), lo, hi - lo, names.get(lo, ""), lines))
    return path, uuid, out


def cmd_diff(a, b, sub, verbose):
    pa, ua, fa = functions(a, sub)
    pb, ub, fb = functions(b, sub)
    print(pa)
    print("UUID A %s\nUUID B %s" % (ua, ub))
    print("functions: A %d, B %d" % (len(fa), len(fb)))
    sm = difflib.SequenceMatcher(None, [f[0] for f in fa], [f[0] for f in fb], autojunk=False)
    same = blocks = 0
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            same += i2 - i1
            continue
        blocks += 1
        print("%s A[%d:%d] B[%d:%d]" % (tag, i1, i2, j1, j2))
        for f in fa[i1:i2]:
            print("   A %x size %5x %s" % (f[1], f[2], f[3]))
        for f in fb[j1:j2]:
            print("   B %x size %5x %s" % (f[1], f[2], f[3]))
        if verbose and i2 - i1 == 1 and j2 - j1 == 1:
            for line in difflib.unified_diff(fa[i1][4], fb[j1][4], lineterm="", n=2):
                print("      " + line)
    print("identical functions: %d, changed blocks: %d" % (same, blocks))


if len(sys.argv) >= 4 and sys.argv[1] == "info":
    cmd_info(sys.argv[2], sys.argv[3:])
elif len(sys.argv) >= 5 and sys.argv[1] == "diff":
    cmd_diff(sys.argv[2], sys.argv[3], sys.argv[4], "-v" in sys.argv)
else:
    sys.exit(__doc__)
