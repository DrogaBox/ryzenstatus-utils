# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RyzenStatus

"""Keeps Tools/dmg-layout.DS_Store in step with the DMG's items.

The .DS_Store that make-dmg.sh seeds into the DMG holds the window settings (size, icon
view, background picture) and one position record (Iloc) per item at the top of the
volume. An item without a record lands wherever Finder puts it, so every item the DMG has
at its top needs one, and they must match the AppleScript positions in make-dmg.sh.

    python3 -I -B Tools/dmg-layout.py           rewrite the window size and the positions
    python3 -I -B Tools/dmg-layout.py --check   exit 1 unless the file holds exactly these

Only the records of the single leaf node are rewritten; the window settings, the
background picture records and the file's allocator blocks are kept byte for byte.
Writing nothing else is what keeps this safe without Finder: the file was made by Finder,
and this script changes no structure Finder built.
"""
import plistlib
import struct
import sys
from pathlib import Path

LAYOUT = Path(__file__).resolve().parent / "dmg-layout.DS_Store"

# Points from the top left of the window, the centre of each icon; the same numbers as
# the AppleScript in make-dmg.sh and the arrow in MakeDMGBackground.swift.
WINDOW = (600, 560)
WINDOW_ORIGIN = (200, 400)
POSITIONS = {
    "Kexts": (150, 120),
    "GPU RX 6000": (450, 120),
    "RyzenStatus.app": (150, 275),
    "Applications": (450, 275),
    "README.txt": (300, 400),
}


def blocks(data):
    if data[0:4] != b"\x00\x00\x00\x01" or data[4:8] != b"Bud1":
        raise SystemExit("not a .DS_Store file")
    off1, size, off2 = struct.unpack(">III", data[8:20])
    root = data[4 + off1: 4 + off1 + size]
    count = struct.unpack(">I", root[0:4])[0]
    addrs = list(struct.unpack(">%dI" % count, root[8:8 + 4 * count]))
    pos = 8 + 4 * ((count + 255) // 256 * 256)
    ntoc = struct.unpack(">I", root[pos:pos + 4])[0]
    pos += 4
    toc = {}
    for _ in range(ntoc):
        n = root[pos]
        toc[root[pos + 1:pos + 1 + n].decode()] = struct.unpack(">I", root[pos + 1 + n:pos + 5 + n])[0]
        pos += 5 + n
    return addrs, toc


def span(addr):
    return 4 + (addr & ~0x1F), 1 << (addr & 0x1F)


def parse_record(b, p):
    nlen = struct.unpack(">I", b[p:p + 4])[0]
    name = b[p + 4:p + 4 + 2 * nlen].decode("utf-16-be")
    p += 4 + 2 * nlen
    sid, typ = b[p:p + 4], b[p + 4:p + 8]
    p += 8
    start = p
    if typ in (b"long", b"shor", b"type"):
        p += 4
    elif typ == b"bool":
        p += 1
    elif typ == b"blob":
        p += 4 + struct.unpack(">I", b[p:p + 4])[0]
    elif typ == b"ustr":
        p += 4 + 2 * struct.unpack(">I", b[p:p + 4])[0]
    elif typ in (b"comp", b"dutc"):
        p += 8
    else:
        raise SystemExit("unknown record type %r" % typ)
    return (name, sid, typ, b[start:p]), p


def read(data):
    addrs, toc = blocks(data)
    m_off, _ = span(addrs[toc["DSDB"]])
    root_node, levels, nrec, nnodes, page = struct.unpack(">IIIII", data[m_off:m_off + 20])
    if levels != 0 or nnodes != 1:
        raise SystemExit("the layout file has more than one node; let Finder write it again")
    n_off, n_size = span(addrs[root_node])
    node = data[n_off:n_off + n_size]
    child, count = struct.unpack(">II", node[:8])
    if child != 0:
        raise SystemExit("the layout file's node is not a leaf")
    records, p = [], 8
    for _ in range(count):
        rec, p = parse_record(node, p)
        records.append(rec)
    return records, m_off, n_off, n_size


def iloc(x, y):
    return struct.pack(">I", 16) + struct.pack(">II", x, y) + b"\xff\xff\xff\xff\xff\xff\x00\x00"


def wanted(records):
    out = []
    for name, sid, typ, value in records:
        if sid == b"Iloc":
            continue
        if name == "." and sid == b"bwsp":
            settings = plistlib.loads(value[4:])
            settings["WindowBounds"] = "{{%d, %d}, {%d, %d}}" % (WINDOW_ORIGIN + WINDOW)
            blob = plistlib.dumps(settings, fmt=plistlib.FMT_BINARY, sort_keys=False)
            value = struct.pack(">I", len(blob)) + blob
        out.append((name, sid, typ, value))
    for name, (x, y) in POSITIONS.items():
        out.append((name, b"Iloc", b"blob", iloc(x, y)))
    # Finder keeps the records ordered by name, ignoring case, then by record type.
    out.sort(key=lambda r: (r[0].lower(), r[1]))
    return out


def encode(record):
    name, sid, typ, value = record
    raw = name.encode("utf-16-be")
    return struct.pack(">I", len(raw) // 2) + raw + sid + typ + value


def positions(records):
    found = {}
    for name, sid, _, value in records:
        if sid == b"Iloc":
            found[name] = struct.unpack(">II", value[4:12])
    return found


def window(records):
    for name, sid, _, value in records:
        if name == "." and sid == b"bwsp":
            return plistlib.loads(value[4:]).get("WindowBounds")
    return None


def main():
    data = bytearray(LAYOUT.read_bytes())
    records, m_off, n_off, n_size = read(bytes(data))
    want_bounds = "{{%d, %d}, {%d, %d}}" % (WINDOW_ORIGIN + WINDOW)
    if "--check" in sys.argv[1:]:
        ok = positions(records) == POSITIONS and window(records) == want_bounds
        print("layout matches" if ok else "layout differs: %s %s" % (positions(records), window(records)))
        return 0 if ok else 1
    new = wanted(records)
    body = struct.pack(">II", 0, len(new)) + b"".join(encode(r) for r in new)
    if len(body) > n_size:
        raise SystemExit("the records no longer fit in one node; let Finder write the file again")
    data[n_off:n_off + n_size] = body + b"\x00" * (n_size - len(body))
    data[m_off + 8:m_off + 12] = struct.pack(">I", len(new))
    LAYOUT.write_bytes(bytes(data))
    print("wrote %s: %d records, %d of %d bytes in the node" % (LAYOUT.name, len(new), len(body), n_size))
    return 0


if __name__ == "__main__":
    sys.exit(main())
