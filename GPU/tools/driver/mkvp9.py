#!/usr/bin/env python3
"""Makes a synthetic VP9 test clip of any size, and its reference.

libvpx encodes the clip; FFmpeg decodes it on the CPU and writes the MD5 of every frame as
I420 to <out.ivf>.md5, in the format of FFmpeg's FATE references, which decode_vp9 and
vtvp9test compare with. Useful for sizes the public test vectors do not have (portrait, 4K).

Usage:
  python3 tools/driver/mkvp9.py <out.ivf> <w> <h> <frames>

Needs PyAV built with libvpx, and NumPy (pip install av numpy).
"""
import hashlib
import sys

import av
import numpy as np


def frame(i, width, height):
    """Return the (y, u, v) float planes of synthetic frame i."""
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    tex = np.random.default_rng(1234).integers(0, 255, (256, 256)).astype(np.float32)
    t = np.tile(np.roll(np.roll(tex, i * 7, 0), i * 13, 1), (height // 256 + 1, width // 256 + 1))
    t = t[:height, :width]
    y = 0.35 * (xx / width * 255) + 0.35 * t
    y += 0.3 * (128 + 127 * np.sin((xx + i * 24) / 90) * np.cos((yy - i * 11) / 70))
    u = 128 + 60 * np.sin((xx[::2, ::2] + i * 5) / 200)
    v = 128 + 60 * np.cos((yy[::2, ::2] - i * 4) / 150)
    return y, u, v


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    out, width, height, count = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    if width < 2 or height < 2 or count < 1:
        sys.exit("width and height must be at least 2, frames at least 1")

    oc = av.open(out, "w", format="ivf")
    st = oc.add_stream("libvpx-vp9", rate=30)
    st.width, st.height, st.pix_fmt = width, height, "yuv420p"
    st.options = {"crf": "32", "b": "0", "cpu-used": "6", "row-mt": "1"}
    for i in range(count):
        f = av.VideoFrame(width, height, "yuv420p")
        for plane, data in zip(f.planes, frame(i, width, height)):
            a = np.clip(data, 0, 255).astype(np.uint8)
            # The plane can hold padding rows below the picture.
            buf = np.frombuffer(plane, np.uint8).reshape(-1, plane.line_size)
            buf[: a.shape[0], : a.shape[1]] = a
        f.pts = i
        for pkt in st.encode(f):
            oc.mux(pkt)
    for pkt in st.encode(None):
        oc.mux(pkt)
    oc.close()

    n = 0
    sizes = ((width, height), ((width + 1) // 2, (height + 1) // 2), ((width + 1) // 2, (height + 1) // 2))
    with open(out + ".md5", "w") as ref:
        for fr in av.open(out).decode(video=0):
            m = hashlib.md5()
            for plane, (pw, ph) in zip(fr.planes, sizes):
                a = np.frombuffer(plane, np.uint8).reshape(-1, plane.line_size)[:ph, :pw]
                m.update(a.tobytes())
            ref.write("0, %10d, %10d,        1, %8d, %s\n" % (n, n, width * height * 3 // 2, m.hexdigest()))
            n += 1
    print(out, "frames md5:", n)
    if n != count:
        sys.exit(f"the CPU decoder returned {n} frames for {count} encoded")


if __name__ == "__main__":
    main()
