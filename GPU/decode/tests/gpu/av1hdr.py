#!/usr/bin/env python3
"""av1hdr.py - adds HDR metadata OBUs to an AV1 IVF file, for the colour tests.

    python3 -I av1hdr.py in.ivf out.ivf

Every temporal unit that holds a sequence header (the key frames of an FFmpeg
libaom encode) gets an HDR_MDCV and an HDR_CLL metadata OBU (AV1 spec 5.8.3,
5.8.4) right after its temporal delimiter: a typical HDR10 master, P3
primaries, D65 white, 1000 / 0.005 cd/m2, MaxCLL 1000, MaxFALL 400. FFmpeg's
libaom wrapper writes the colour config of the sequence header
(-color_primaries and friends) but no HDR metadata OBUs.

Nothing else in the file changes. It reads only the file it is given.
"""
import struct
import sys

# AV1 fixed point: chromaticity 0.16, luminance max 24.8, min 18.14.
RED, GREEN, BLUE, WHITE = (44564, 20972), (17367, 45220), (9830, 3932), (20493, 21561)
LMAX, LMIN = 1000 << 8, 82  # 1000 cd/m2, 0.005 cd/m2
MAX_CLL, MAX_FALL = 1000, 400


def leb128(data, pos):
    value = 0
    for i in range(8):
        if pos + i >= len(data):
            raise ValueError("leb128 past the end")
        b = data[pos + i]
        value |= (b & 0x7F) << (7 * i)
        if not b & 0x80:
            return value, i + 1
    raise ValueError("leb128 too long")


def obu(obu_type, payload):
    assert len(payload) < 128
    return bytes([obu_type << 3 | 2, len(payload)]) + payload


def metadata():
    # each payload ends with trailing_bits (5.3.4): a one bit, then zeros
    mdcv = struct.pack(">B6H2H2IB", 2, *RED, *GREEN, *BLUE, *WHITE, LMAX, LMIN, 0x80)
    cll = struct.pack(">B2HB", 1, MAX_CLL, MAX_FALL, 0x80)
    return obu(5, mdcv) + obu(5, cll)


def obus(tu):
    """(type, start, end) of each OBU of a temporal unit."""
    out, pos = [], 0
    while pos < len(tu):
        hdr = tu[pos]
        obu_type, ext, has_size = hdr >> 3 & 15, hdr >> 2 & 1, hdr >> 1 & 1
        head = 1 + ext
        if has_size:
            size, n = leb128(tu, pos + head)
            head += n
        else:
            size = len(tu) - pos - head
        end = pos + head + size
        if end > len(tu):
            raise ValueError("OBU past the end of its temporal unit")
        out.append((obu_type, pos, end))
        pos = end
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: av1hdr.py in.ivf out.ivf")
    data = open(sys.argv[1], "rb").read()
    if data[:4] != b"DKIF" or len(data) < 32:
        sys.exit("not an IVF file")
    hlen = struct.unpack_from("<H", data, 6)[0]
    out, pos, added = bytearray(data[:hlen]), hlen, 0
    while pos < len(data):
        if pos + 12 > len(data):
            sys.exit("IVF frame header cut short")
        size, pts = struct.unpack_from("<IQ", data, pos)
        tu = data[pos + 12 : pos + 12 + size]
        if len(tu) != size:
            sys.exit("IVF frame cut short")
        pos += 12 + size
        parts = obus(tu)
        if any(t == 1 for t, _, _ in parts):
            at = parts[0][2] if parts and parts[0][0] == 2 else 0
            tu = tu[:at] + metadata() + tu[at:]
            added += 1
        out += struct.pack("<IQ", len(tu), pts) + tu
    open(sys.argv[2], "wb").write(out)
    print(f"{sys.argv[2]}: HDR metadata added to {added} temporal unit(s)")


if __name__ == "__main__":
    main()
