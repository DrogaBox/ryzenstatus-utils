#!/usr/bin/env python3
"""Prints the fields of a VCN decode message dumped by dryrun.py or dryrun_vp9.py.

The layouts come from Mesa's ac_vcn_dec.h (MIT license), which is not kept in this
repository. Point VCN_DEC_H at a copy, or put one at deps/mesa/ac_vcn_dec.h:
  https://gitlab.freedesktop.org/mesa/mesa/-/raw/main/src/amd/common/ac_vcn_dec.h

Usage:
  vcnmsg.py <vcn_msg.bin> [field_filter]
      field_filter is a regular expression on the field names.
It compiles and runs a small C program built from that header to learn the offsets.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

_HDR = os.environ.get("VCN_DEC_H") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "../../deps/mesa/ac_vcn_dec.h"
)

_MESSAGE_NAMES = {
    2: "rvcn_dec_message_decode",
    17: "rvcn_dec_message_av1",
    14: "rvcn_dec_message_vp9",
    3: "rvcn_dec_message_drm",
}


def layout(struct: str) -> list[tuple[int, int, str]]:
    """Return (offset, size, name) for each field of `struct`."""
    header = Path(_HDR).read_text(encoding="utf-8")
    match = re.search(
        r"typedef struct %s_s \{(.*?)\} %s_t;" % (struct, struct), header, re.S
    )
    if match is None:
        raise ValueError(f"unknown struct {struct}")
    body = match.group(1)
    fields: list[str] = []
    for line in body.split(";"):
        line = re.sub(r"/\*.*?\*/", "", line).strip()
        field_match = re.match(r".*?\s\**(\w+)\s*((?:\[\d+\])*)$", line)
        if field_match:
            fields.append(field_match.group(1))
    source = (
        "#include <stdio.h>\n#include <stddef.h>\n"
        "#include <stdint.h>\n#include <stdbool.h>\n"
        + re.sub(r"#include.*", "", header)
    )
    source += "\nint main(){\n"
    for field in fields:
        source += (
            f' printf("%zu %zu {field}\\n", offsetof({struct}_t,{field}), '
            f"sizeof((({struct}_t*)0)->{field}));\n"
        )
    source += (
        f' printf("%zu %zu __size\\n", sizeof({struct}_t), '
        f"sizeof({struct}_t));\n}}\n"
    )
    with tempfile.TemporaryDirectory() as temp_dir:
        c_path = Path(temp_dir) / "x.c"
        exe_path = Path(temp_dir) / "x"
        c_path.write_text(source, encoding="utf-8")
        subprocess.run(
            ["clang", "-w", str(c_path), "-o", str(exe_path)],
            check=True,
            timeout=60,
        )
        out = subprocess.run(
            [str(exe_path)],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        ).stdout
    return [
        (int(offset), int(size), name)
        for offset, size, name in (line.split() for line in out.splitlines())
    ]


def u32(buf: bytes, offset: int) -> int:
    """Read a little-endian uint32 from `buf` at `offset`."""
    return int.from_bytes(buf[offset : offset + 4], "little")


def show(buf: bytes, base: int, struct: str, filt: str | None = None) -> None:
    """Print fields of `struct` starting at `base` in `buf`."""
    for offset, size, name in layout(struct):
        if name == "__size":
            continue
        if filt and not re.search(filt, name):
            continue
        raw = buf[base + offset : base + offset + size]
        if size in (1, 2, 4) and len(raw) == size:
            value = int.from_bytes(raw, "little", signed=False)
            print(f"  {offset:5d} {name:34s} {value} (0x{value:x})")
        else:
            nonzero = [i for i, byte in enumerate(raw) if byte]
            print(
                f"  {offset:5d} {name:34s} [{size}B] "
                f"nonzero_bytes={len(nonzero)} first={raw[:24].hex()}"
            )


def main(argv: list[str] | None = None) -> None:
    """Decode the VCN message listed on the command line."""
    args = sys.argv if argv is None else argv
    if len(args) < 2:
        raise SystemExit("usage: vcnmsg.py <vcn_msg.bin> [field_filter]")
    if not os.path.isfile(_HDR):
        raise SystemExit(f"no ac_vcn_dec.h at {_HDR}: set VCN_DEC_H (see the top of this file)")
    buf = Path(args[1]).read_bytes()
    filt = args[2] if len(args) > 2 else None
    header_size, total, nbuf, msg_type, handle, fb = (
        u32(buf, i * 4) for i in range(6)
    )
    print(
        f"header: header_size={header_size} total_size={total} "
        f"num_buffers={nbuf} msg_type={msg_type} "
        f"stream_handle=0x{handle:x} fb={fb}"
    )
    for i in range(nbuf):
        mid, offset, size, filled = (
            u32(buf, 24 + 16 * i + 4 * k) for k in range(4)
        )
        print(
            f"index[{i}]: id={mid} offset={offset} size={size} filled={filled}"
        )
        if mid in _MESSAGE_NAMES:
            print(f"== {_MESSAGE_NAMES[mid]} @ {offset}")
            show(buf, offset, _MESSAGE_NAMES[mid], filt)


if __name__ == "__main__":
    main()
