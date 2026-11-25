// The colour of a decoded picture, as the stream or its container gives it:
// ITU-T H.273 code points for the primaries, the transfer function and the
// YCbCr matrix, and the HDR metadata in the byte layout CoreVideo takes.
// Plain C, no CoreFoundation: the decoder sessions fill it, the plug-ins turn
// it into pixel buffer attachments (common/vtcolor.h).
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

typedef struct {
  // H.273 code points; -1 when not given. 2 ("unspecified") is kept as it is
  // and attaches nothing, like any value CoreVideo has no name for.
  int primaries, transfer, matrix;
  bool has_mdcv, has_cll;
  // Big-endian, the payload of the HEVC mastering display colour volume SEI
  // (ISO/IEC 23008-2 D.2.28), as kCVImageBufferMasteringDisplayColorVolumeKey
  // takes it: x and y of the primaries in the order green, blue, red, then of
  // the white point (units of 0.00002), then the largest and the smallest
  // luminance (units of 0.0001 cd/m2, 4 bytes each).
  uint8_t mdcv[24];
  // Big-endian, the payload of the HEVC content light level SEI, as
  // kCVImageBufferContentLightLevelInfoKey takes it: MaxCLL, MaxFALL (cd/m2).
  uint8_t cll[4];
} VcnColor;

static inline void vcn_color_clear(VcnColor* c) {
  memset(c, 0, sizeof(*c));
  c->primaries = c->transfer = c->matrix = -1;
}

// VP9's color_space (VP9 bitstream spec 7.2): the standard it names fixes the
// matrix and the primaries. The transfer function is not in the bitstream
// (BT.2020 is used with PQ, HLG and the BT.2020 SDR curve alike): it can only
// come from the container. BT.601 does not say which primaries (525 or 625
// lines), so it gives the matrix only. 0 (unknown), 6 (reserved) and 7 (RGB,
// which the engine does not decode) give nothing.
static inline void vcn_color_from_vp9(int color_space, VcnColor* c) {
  vcn_color_clear(c);
  switch (color_space) {
    case 1:  // CS_BT_601
      c->matrix = 6;
      break;
    case 2:  // CS_BT_709
      c->primaries = c->matrix = 1;
      break;
    case 3:  // CS_SMPTE_170
      c->primaries = c->matrix = 6;
      break;
    case 4:  // CS_SMPTE_240
      c->primaries = c->matrix = 7;
      break;
    case 5:  // CS_BT_2020 (non-constant luminance)
      c->primaries = c->matrix = 9;
      break;
    default:
      break;
  }
}

// The colour fields of a vpcC record (VP Codec ISO Media File Format Binding
// 1.0, version 1): version and flags (4 bytes), profile, level, bitDepth |
// chromaSubsampling | videoFullRangeFlag, colourPrimaries,
// transferCharacteristics, matrixCoefficients, codecInitializationDataSize.
// Version 0 records have another layout and give nothing.
static inline void vcn_color_from_vpcC(const uint8_t* d, size_t n,
                                       VcnColor* c) {
  vcn_color_clear(c);
  if (!d || n < 10 || d[0] != 1) return;
  c->primaries = d[7];
  c->transfer = d[8];
  c->matrix = d[9];
}
