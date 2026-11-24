#!/usr/bin/env python3
"""mkfield.py <in.yuv> <width> <height> <frames> <out.m2v>

Writes an MPEG-2 Main Profile stream made only of field pictures
(picture_structure 1 and 2), from raw yuv420p frames: there is no encoder on
this Mac that makes them (FFmpeg's mpeg2video always codes frame pictures).

Every frame is two field pictures, top field first:
  frame 0: top field I, bottom field P;
  later frames: both fields P.
In a P field the even macroblock rows are intra macroblocks of that field's
own lines, the odd rows are "MC, not coded" with a zero field motion vector,
so the picture copies a reference field:
  - first field of a frame: motion_vertical_field_select alternates per
    macroblock between the top and the bottom field of the previous frame;
  - second field: it alternates between the first field of the same frame
    (field select 0, the case a decoder has to get right for field pictures)
    and the previous frame's bottom field.
Only escape codes are used for the AC coefficients (ISO 13818-2 table B.14
needs no other entry for that), so the stream is large but valid.
"""
import math
import sys

ZIGZAG = [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
          12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
          35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
          58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63]
# Default intra matrix (ISO 13818-2 6.3.11), in raster order.
INTRA = [8, 16, 19, 22, 26, 27, 29, 34, 16, 16, 22, 24, 27, 29, 34, 37,
         19, 22, 26, 27, 29, 34, 34, 38, 22, 22, 26, 27, 29, 34, 37, 40,
         22, 26, 27, 29, 32, 35, 40, 48, 26, 27, 29, 32, 35, 40, 48, 58,
         26, 27, 29, 34, 38, 46, 56, 69, 27, 29, 35, 38, 46, 56, 69, 83]
# dct_dc_size_luminance / _chrominance (tables B.12, B.13).
DC_LUMA = ["100", "00", "01", "101", "110", "1110", "11110", "111110",
           "1111110", "11111110", "111111110", "111111111"]
DC_CHROMA = ["00", "01", "10", "110", "1110", "11110", "111110", "1111110",
             "11111110", "111111110", "1111111110", "1111111111"]
QSCALE_CODE = 4  # q_scale_type 0: quantiser_scale 8

COS = [[math.cos((2 * x + 1) * u * math.pi / 16) * (math.sqrt(0.5) if u == 0 else 1.0)
        for x in range(8)] for u in range(8)]


class Bits:
    def __init__(self):
        self.out = bytearray()
        self.acc = 0
        self.n = 0

    def put(self, value, count):
        for i in range(count - 1, -1, -1):
            self.acc = (self.acc << 1) | ((value >> i) & 1)
            self.n += 1
            if self.n == 8:
                self.out.append(self.acc)
                self.acc = 0
                self.n = 0

    def code(self, s):
        for ch in s:
            self.put(1 if ch == "1" else 0, 1)

    def align(self):
        while self.n:
            self.put(0, 1)

    def start(self, code):
        self.align()
        self.out += bytes([0, 0, 1, code])


def fdct(block):
    """8x8 forward DCT of ISO 13818-2 annex A, rows then columns."""
    tmp = [0.0] * 64
    for y in range(8):
        row = block[y * 8:(y + 1) * 8]
        for u in range(8):
            c = COS[u]
            tmp[y * 8 + u] = 0.5 * sum(row[x] * c[x] for x in range(8))
    out = [0.0] * 64
    for u in range(8):
        col = [tmp[y * 8 + u] for y in range(8)]
        for v in range(8):
            c = COS[v]
            out[v * 8 + u] = 0.5 * sum(col[y] * c[y] for y in range(8))
    return out


def put_dc(bits, diff, chroma):
    size = 0 if diff == 0 else abs(diff).bit_length()
    bits.code((DC_CHROMA if chroma else DC_LUMA)[size])
    if size:
        bits.put(diff if diff > 0 else diff + (1 << size) - 1, size)


def intra_block(bits, block, pred, comp):
    """Codes one intra block; returns the new DC predictor."""
    f = fdct(block)
    qs = 2 * QSCALE_CODE
    dc = max(0, min(255, int(round(f[0] / 8))))
    put_dc(bits, dc - pred, comp > 0)
    run = 0
    for i in range(1, 64):
        k = ZIGZAG[i]
        level = int(round(16 * f[k] / (INTRA[k] * qs)))
        level = max(-2047, min(2047, level))
        if level == 0:
            run += 1
            continue
        bits.code("000001")         # escape
        bits.put(run, 6)
        bits.put(level & 0xFFF, 12)  # 12-bit two's complement
        run = 0
    bits.code("10")  # end of block (table B.14)
    return dc


def field_planes(frame, w, h, parity):
    y, cb, cr = frame
    cw, ch = w // 2, h // 2
    fy = [y[(2 * r + parity) * w:(2 * r + parity) * w + w] for r in range(h // 2)]
    fcb = [cb[(2 * r + parity) * cw:(2 * r + parity) * cw + cw] for r in range(ch // 2)]
    fcr = [cr[(2 * r + parity) * cw:(2 * r + parity) * cw + cw] for r in range(ch // 2)]
    return fy, fcb, fcr


def grab(plane, x0, y0):
    return [plane[y0 + r][x0 + c] for r in range(8) for c in range(8)]


def intra_mb(bits, planes, mbx, mby, preds):
    fy, fcb, fcr = planes
    for b in range(4):
        x0 = mbx * 16 + (b & 1) * 8
        y0 = mby * 16 + (b >> 1) * 8
        preds[0] = intra_block(bits, grab(fy, x0, y0), preds[0], 0)
    preds[1] = intra_block(bits, grab(fcb, mbx * 8, mby * 8), preds[1], 1)
    preds[2] = intra_block(bits, grab(fcr, mbx * 8, mby * 8), preds[2], 2)


def headers(bits, w, h, frames):
    bits.start(0xB3)  # sequence header
    bits.put(w, 12)
    bits.put(h, 12)
    bits.put(2, 4)       # 4:3
    bits.put(3, 4)       # 25 frames/s
    bits.put(50000, 18)  # 20 Mbit/s in units of 400 bit/s
    bits.put(1, 1)
    bits.put(112, 10)    # vbv_buffer_size
    bits.put(0, 1)       # constrained_parameters_flag
    bits.put(0, 1)       # load_intra_quantiser_matrix
    bits.put(0, 1)       # load_non_intra_quantiser_matrix
    bits.start(0xB5)     # sequence extension
    bits.put(1, 4)
    bits.put(0x48, 8)    # Main profile, Main level
    bits.put(0, 1)       # progressive_sequence
    bits.put(1, 2)       # 4:2:0
    bits.put(0, 2)
    bits.put(0, 2)
    bits.put(0, 12)
    bits.put(1, 1)
    bits.put(0, 8)
    bits.put(1, 1)       # low_delay: no B pictures
    bits.put(0, 2)
    bits.put(0, 5)
    bits.start(0xB8)     # group of pictures
    bits.put(0, 25)
    bits.put(1, 1)       # closed_gop
    bits.put(0, 1)


def field_picture(bits, frame, w, h, index, structure):
    first = structure == 1
    coding = 1 if (index == 0 and first) else 2
    bits.start(0x00)
    bits.put(index & 1023, 10)  # temporal_reference: both fields of a frame
    bits.put(coding, 3)
    bits.put(0xFFFF, 16)        # vbv_delay
    if coding == 2:
        bits.put(0, 1)          # full_pel_forward_vector
        bits.put(7, 3)          # forward_f_code
    bits.put(0, 1)              # extra_bit_picture
    bits.start(0xB5)            # picture coding extension
    bits.put(8, 4)
    fh = 1 if coding == 2 else 15
    for v in (fh, fh, 15, 15):
        bits.put(v, 4)
    bits.put(0, 2)              # intra_dc_precision: 8 bits
    bits.put(structure, 2)
    bits.put(0, 1)              # top_field_first (0 in a field picture)
    bits.put(0, 1)              # frame_pred_frame_dct (0 in a field picture)
    bits.put(0, 1)              # concealment_motion_vectors
    bits.put(0, 1)              # q_scale_type
    bits.put(0, 1)              # intra_vlc_format
    bits.put(0, 1)              # alternate_scan
    bits.put(0, 1)              # repeat_first_field
    bits.put(0, 1)              # chroma_420_type
    bits.put(0, 1)              # progressive_frame
    bits.put(0, 1)              # composite_display_flag
    planes = field_planes(frame, w, h, structure - 1)
    mbw, mbh = w // 16, h // 32
    for mby in range(mbh):
        bits.start(mby + 1)     # slice_vertical_position
        bits.put(QSCALE_CODE, 5)
        bits.put(0, 1)          # extra_bit_slice
        preds = [128, 128, 128]
        for mbx in range(mbw):
            bits.code("1")      # macroblock_address_increment 1
            if coding == 1:
                bits.code("1")  # intra (table B.2)
                intra_mb(bits, planes, mbx, mby, preds)
            elif mby % 2 == 0:
                bits.code("00011")  # intra (table B.3)
                intra_mb(bits, planes, mbx, mby, preds)
            else:
                bits.code("001")    # MC, not coded (table B.3)
                bits.put(1, 2)      # field_motion_type: field
                # First field: the previous frame's top (0) or bottom (1).
                # Second field: its own first field (0) or the previous
                # frame's bottom field (1); frame 0 has no previous frame.
                select = mbx & 1
                if not first and index == 0:
                    select = 0
                bits.put(select, 1)  # motion_vertical_field_select[0][0]
                bits.code("1")      # motion_code horizontal 0
                bits.code("1")      # motion_code vertical 0
                preds[:] = [128, 128, 128]  # reset after a non-intra macroblock
    return coding


def main():
    if len(sys.argv) != 6:
        sys.exit(__doc__)
    src, w, h, n, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
    if w % 16 or h % 32:
        sys.exit("width must be a multiple of 16 and height of 32")
    size = w * h * 3 // 2
    data = open(src, "rb").read()
    if len(data) < size * n:
        sys.exit("not enough frames in %s" % src)
    bits = Bits()
    headers(bits, w, h, n)
    for i in range(n):
        raw = data[i * size:(i + 1) * size]
        frame = (raw[:w * h], raw[w * h:w * h + w * h // 4], raw[w * h + w * h // 4:])
        types = [field_picture(bits, frame, w, h, i, s) for s in (1, 2)]
        print("frame %d: top %s, bottom %s" % (i, " IP"[types[0]], " IP"[types[1]]))
    bits.start(0xB7)  # sequence end
    open(out, "wb").write(bits.out)
    print("%s: %d bytes" % (out, len(bits.out)))


if __name__ == "__main__":
    main()
