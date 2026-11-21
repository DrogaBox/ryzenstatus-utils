#!/usr/bin/env python3
"""kcfunc.py - prints the first bytes of named functions of one kext inside a macOS kernel
collection (BootKernelExtensions.kc or SystemKernelExtensions.kc). It only reads the file.

    python3 tools/driver/kcfunc.py <kext bundle id> <symbol>[,<symbol>...] <label>=<kc> ...

Output, one line per function found: "<hex of the first 32 bytes> <symbol> <label>".
Exit status: 0 every symbol found in every collection; 1 a collection was read but a symbol
is not in it; 2 a collection could not be read (2 wins when both happen).

The collections are Apple's: do not commit them or a disassembly of them. The bytes printed
are function prologues, used as test input by the kexts' entry checks.

Used by amficheck.py (VCNVTLoader) and by the sensors kext's tests.
"""
import struct
import sys

MH_MAGIC_64 = 0xFEEDFACF
MH_FILESET = 0xC
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x2
LC_FILESET_ENTRY = 0x80000035
ENTRY_BYTES = 32


def commands(data, at):
    """Yields (cmd, offset, size) for the Mach-O header at `at`."""
    magic, _, _, _, ncmds, sizeofcmds, _, _ = struct.unpack_from("<8I", data, at)
    if magic != MH_MAGIC_64:
        raise ValueError("not a 64-bit Mach-O at offset %#x" % at)
    p = at + 32
    end = p + sizeofcmds
    for _ in range(ncmds):
        if p + 8 > end:
            raise ValueError("load commands run past their size")
        cmd, size = struct.unpack_from("<2I", data, p)
        if size < 8 or p + size > end:
            raise ValueError("bad load command size")
        yield cmd, p, size
        p += size


def read_collection(path):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 32 or struct.unpack_from("<I", data, 0)[0] != MH_MAGIC_64:
        raise ValueError("not a plain kernel collection (compressed or fat files are not read)")
    if struct.unpack_from("<I", data, 12)[0] != MH_FILESET:
        raise ValueError("not a kernel collection (file type is not MH_FILESET)")
    return data


def kext_offset(data, bundle):
    """The file offset of a kext's Mach-O header in the collection, or None."""
    for cmd, p, size in commands(data, 0):
        if cmd == LC_FILESET_ENTRY:
            _, fileoff, name_off, _ = struct.unpack_from("<2Q2I", data, p + 8)
            name = data[p + name_off : p + size].split(b"\0", 1)[0].decode()
            if name == bundle:
                return fileoff
    return None


def symbol_bytes(path, bundle, symbols, count=ENTRY_BYTES):
    """Returns {symbol: first `count` bytes} for the symbols of `bundle` found in the
    collection at `path`. Raises ValueError when the kext is not there or has no symbols."""
    data = read_collection(path)
    kext_at = kext_offset(data, bundle)
    if kext_at is None:
        raise ValueError("no %s in the collection" % bundle)
    segments = []
    symtab = None
    for cmd, p, _ in commands(data, kext_at):
        if cmd == LC_SEGMENT_64:
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<4Q", data, p + 24)
            segments.append((vmaddr, vmsize, fileoff, filesize))
        elif cmd == LC_SYMTAB:
            symtab = struct.unpack_from("<4I", data, p + 8)
    if symtab is None:
        raise ValueError("%s has no symbol table in this collection" % bundle)
    symoff, nsyms, stroff, strsize = symtab
    if symoff + nsyms * 16 > len(data) or stroff + strsize > len(data):
        raise ValueError("symbol table runs past the file")
    wanted = {s.encode(): s for s in symbols}
    found = {}
    for i in range(nsyms):
        strx, ntype, _, _, value = struct.unpack_from("<IBBHQ", data, symoff + 16 * i)
        if ntype & 0xE0 or strx >= strsize:  # debugging entry, or bad name
            continue
        start = stroff + strx
        name = data[start : data.index(b"\0", start, stroff + strsize)]
        sym = wanted.get(name)
        if sym is None:
            continue
        for vmaddr, vmsize, fileoff, filesize in segments:
            if vmaddr <= value < vmaddr + min(vmsize, filesize):
                at = fileoff + (value - vmaddr)
                found[sym] = data[at : at + count]
                break
    return found


def main(argv):
    if len(argv) < 4 or any("=" not in a for a in argv[3:]):
        print(__doc__, file=sys.stderr)
        return 1
    bundle, symbols = argv[1], argv[2].split(",")
    status = 0
    for arg in argv[3:]:
        label, path = arg.split("=", 1)
        try:
            found = symbol_bytes(path, bundle, symbols)
        except (OSError, ValueError, struct.error) as e:
            print("%s: %s" % (label, e), file=sys.stderr)
            status = 2
            continue
        for sym in symbols:
            if len(found.get(sym, b"")) == ENTRY_BYTES:
                print("%s %s %s" % (found[sym].hex(), sym, label))
            else:
                print("%s: %s was not found in %s" % (label, sym, bundle), file=sys.stderr)
                status = max(status, 1)
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv))
