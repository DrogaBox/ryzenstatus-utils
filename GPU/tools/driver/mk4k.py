#!/usr/bin/env python3
"""Makes a synthetic AV1 test clip of any size, and its reference.

SVT-AV1 encodes the clip; dav1d decodes it on the CPU and writes the MD5 of every frame as
I420 to <out.ivf>.md5, the format decode_ivf and vtav1test compare with.

Usage:
  python3 tools/driver/mk4k.py <out.ivf> <w> <h> <frames> <bitdepth 8|10> [svt-params]
MD5ONLY=1 only rewrites the reference of an existing clip.

Needs PyAV built with libsvtav1 and libdav1d, and NumPy (pip install av numpy).
"""

from __future__ import annotations

import hashlib
import os
import sys

import av
import numpy as np


def frame(index: int, width: int, height: int):
    """Return (y, u, v) float planes for synthetic frame `index`."""
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    rng = np.random.default_rng(1234)
    tex = rng.integers(0, 255, (256, 256)).astype(np.float32)
    tiled = np.roll(np.roll(tex, index * 7, 0), index * 13, 1)
    tiled = np.tile(tiled, (height // 256 + 1, width // 256 + 1))[
        :height, :width
    ]
    luma = (
        0.35 * (xx / width * 255)
        + 0.35 * tiled
        + 0.3
        * (
            128
            + 127
            * np.sin((xx + index * 24) / 90)
            * np.cos((yy - index * 11) / 70)
        )
    )
    for k in range(6):  # moving discs
        cx = (width * (0.1 + 0.15 * k) + index * (9 + 3 * k)) % width
        cy = height * (0.2 + 0.1 * k) + 120 * np.sin(index / 9 + k)
        luma = np.where(
            (xx - cx) ** 2 + (yy - cy) ** 2 < (60 + 20 * k) ** 2,
            235 - 20 * k,
            luma,
        )
    u = 128 + 60 * np.sin((xx[::2, ::2] + index * 5) / 200)
    v = 128 + 60 * np.cos((yy[::2, ::2] - index * 4) / 150)
    return luma, u, v


def main(argv: list[str] | None = None) -> None:
    """Encode the synthetic clip and write `<out>.md5`."""
    args = sys.argv if argv is None else argv
    out, width, height, n_frames, bit_depth = (
        args[1],
        int(args[2]),
        int(args[3]),
        int(args[4]),
        int(args[5]),
    )
    params = args[6] if len(args) > 6 else ""

    if not os.environ.get("MD5ONLY"):
        container = av.open(out, "w", format="ivf")
        stream = container.add_stream("libsvtav1", rate=30)
        stream.width, stream.height = width, height
        stream.pix_fmt = "yuv420p10le" if bit_depth == 10 else "yuv420p"
        stream.options = {"preset": "10", "crf": "32", "g": "30"}
        if params:
            stream.options["svtav1-params"] = params
        for i in range(n_frames):
            y, u, v = frame(i, width, height)
            if bit_depth == 10:
                planes = [
                    (plane * 4).clip(0, 1023).astype(np.uint16)
                    for plane in (y, u, v)
                ]
                video_frame = av.VideoFrame(width, height, "yuv420p10le")
            else:
                planes = [
                    plane.clip(0, 255).astype(np.uint8) for plane in (y, u, v)
                ]
                video_frame = av.VideoFrame(width, height, "yuv420p")
            for k, plane in enumerate(planes):
                buf = np.frombuffer(
                    video_frame.planes[k], dtype=plane.dtype
                ).reshape(-1, video_frame.planes[k].line_size // plane.itemsize)
                buf[: plane.shape[0], : plane.shape[1]] = plane
            video_frame.pts = i
            for packet in stream.encode(video_frame):
                container.mux(packet)
        for packet in stream.encode():
            container.mux(packet)
        container.close()

    input_container = av.open(out)
    input_container.streams.video[0].codec_context.options = {}
    decoder = av.codec.CodecContext.create("libdav1d", "r")
    n = 0

    def emit(handle, decoded_frame) -> None:
        nonlocal n
        digest = hashlib.md5()
        bytes_per_element = 2 if bit_depth == 10 else 1
        for k, (plane_w, plane_h) in enumerate(
            [
                (width, height),
                ((width + 1) // 2, (height + 1) // 2),
                ((width + 1) // 2, (height + 1) // 2),
            ]
        ):
            plane = decoded_frame.planes[k]
            arr = np.frombuffer(plane, dtype=np.uint8).reshape(
                -1, plane.line_size
            )[:plane_h, : plane_w * bytes_per_element]
            digest.update(arr.tobytes())
        handle.write(f"{digest.hexdigest()}  frame-{n:04d}.i420\n")
        n += 1

    with open(out + ".md5", "w") as handle:
        for packet in input_container.demux(video=0):
            if packet.size:
                for decoded_frame in decoder.decode(packet):
                    emit(handle, decoded_frame)
        for decoded_frame in decoder.decode(None):
            emit(handle, decoded_frame)
    print(out, "frames md5:", n)


if __name__ == "__main__":
    main()
