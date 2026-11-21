#!/usr/bin/env python3
"""Prints the LC_UUID and a SHA-256 for every section of a 64-bit Mach-O file.

Two builds of the same code have the same section hashes even when the files differ as a
whole (a code signature, a version string).

  macho_sections.py <file>             one line per section
  macho_sections.py <file> <other>     compares the two; exit status 1 when a section that
                                       holds code or constants differs

Zero-fill sections (bss, common) have no bytes in the file: only their size is compared.
"""
import hashlib
import struct
import sys

MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
LC_UUID = 0x1B
S_ZEROFILL_TYPES = {0x1, 0xC, 0x12}  # zerofill, gb_zerofill, thread_local_zerofill


def read(path):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 32 or struct.unpack_from("<I", data)[0] != MH_MAGIC_64:
        sys.exit(f"{path}: not a thin 64-bit Mach-O file")
    ncmds = struct.unpack_from("<I", data, 16)[0]
    off = 32
    uuid = None
    sections = {}
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, off)
        if cmd == LC_UUID:
            uuid = data[off + 8:off + 24].hex().upper()
        elif cmd == LC_SEGMENT_64:
            nsects = struct.unpack_from("<I", data, off + 64)[0]
            for i in range(nsects):
                s = off + 72 + 80 * i
                sect = data[s:s + 16].rstrip(b"\0").decode()
                seg = data[s + 16:s + 32].rstrip(b"\0").decode()
                ssize, soff = struct.unpack_from("<QI", data, s + 40)
                flags = struct.unpack_from("<I", data, s + 64)[0]
                if flags & 0xFF in S_ZEROFILL_TYPES:
                    digest = "zero-fill"
                else:
                    digest = hashlib.sha256(data[soff:soff + ssize]).hexdigest()
                sections[f"{seg}.{sect}"] = (ssize, digest)
        off += size
    return uuid, sections


def main():
    if len(sys.argv) == 2:
        uuid, sections = read(sys.argv[1])
        print(f"uuid {uuid}")
        for name, (size, digest) in sections.items():
            print(f"{name:28} {size:8}  {digest}")
        return 0
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    ua, a = read(sys.argv[1])
    ub, b = read(sys.argv[2])
    differ = 0
    for name in list(a) + [n for n in b if n not in a]:
        if a.get(name) == b.get(name):
            print(f"same    {name}")
        else:
            differ += 1
            print(f"DIFFER  {name}: {a.get(name, ('-', 'absent'))[0]} bytes vs "
                  f"{b.get(name, ('-', 'absent'))[0]} bytes")
    print(f"uuid    {'same' if ua == ub else 'differ'} ({ua} / {ub})")
    return 1 if differ else 0


if __name__ == "__main__":
    sys.exit(main())
