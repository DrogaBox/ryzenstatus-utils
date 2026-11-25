// obuwrite.h: writes the few AV1 OBUs the colour tests need (colortest.c,
// sessiontest.c): a reduced still picture sequence header with a colour
// config, and the HDR metadata OBUs. Test code only.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

typedef struct {
  uint8_t b[256];
  size_t bit;
} ObuBits;

static void obu_put(ObuBits* w, uint32_t v, int n) {
  for (int i = n - 1; i >= 0; i--, w->bit++)
    if (v >> i & 1) w->b[w->bit / 8] |= (uint8_t)(0x80 >> (w->bit % 8));
}

// Appends one OBU with its size field to out (at most 127 payload bytes);
// returns the new length.
static size_t obu_append(uint8_t* out, size_t len, int type,
                         const uint8_t* payload, size_t n) {
  out[len++] = (uint8_t)(type << 3 | 2);  // obu_has_size_field
  out[len++] = (uint8_t)n;
  memcpy(out + len, payload, n);
  return len + n;
}

// A reduced still picture sequence header (AV1 5.5), 16x16, with
// color_description_present_flag set when cp >= 0. depth 8, 10 or 12
// (12 needs profile 2).
static size_t obu_sequence_header(uint8_t* out, size_t len, int profile,
                                  int depth, int cp, int tc, int mc,
                                  int range) {
  ObuBits w = {{0}, 0};
  obu_put(&w, (uint32_t)profile, 3);
  obu_put(&w, 1, 1);          // still_picture
  obu_put(&w, 1, 1);          // reduced_still_picture_header
  obu_put(&w, 0, 5);          // seq_level_idx[0]
  obu_put(&w, 3, 4);          // frame_width_bits_minus_1
  obu_put(&w, 3, 4);          // frame_height_bits_minus_1
  obu_put(&w, 15, 4);         // max_frame_width_minus_1
  obu_put(&w, 15, 4);         // max_frame_height_minus_1
  obu_put(&w, 0, 3);          // 128x128 superblocks, filter intra, intra edge
  obu_put(&w, 0, 3);          // superres, cdef, restoration
  obu_put(&w, depth > 8, 1);  // high_bitdepth
  if (profile == 2 && depth > 8) obu_put(&w, depth == 12, 1);  // twelve_bit
  if (profile != 1) obu_put(&w, 0, 1);                         // mono_chrome
  obu_put(&w, cp >= 0, 1);  // color_description_present_flag
  if (cp >= 0) {
    obu_put(&w, (uint32_t)cp, 8);
    obu_put(&w, (uint32_t)tc, 8);
    obu_put(&w, (uint32_t)mc, 8);
  }
  obu_put(&w, (uint32_t)range, 1);  // color_range
  if (profile == 2 && depth == 12) {
    obu_put(&w, 1, 1);  // subsampling_x
    obu_put(&w, 1, 1);  // subsampling_y
  }
  if (profile == 0 || (profile == 2 && depth == 12))
    obu_put(&w, 0, 2);  // chroma_sample_position (4:2:0 only)
  obu_put(&w, 0, 1);    // separate_uv_delta_q
  obu_put(&w, 0, 1);    // film_grain_params_present
  obu_put(&w, 1, 1);    // trailing_one_bit
  return obu_append(out, len, 1, w.b, (w.bit + 7) / 8);
}

// HDR_MDCV metadata (5.8.4): primaries red, green, blue (0.16 fixed point),
// white point, luminance max (24.8) and min (18.14). cut: bytes left off the
// end, for a damaged one.
static size_t obu_mdcv(uint8_t* out, size_t len, const uint16_t px[3],
                       const uint16_t py[3], uint16_t wx, uint16_t wy,
                       uint32_t lmax, uint32_t lmin, size_t cut) {
  ObuBits w = {{0}, 0};
  obu_put(&w, 2, 8);  // metadata_type HDR_MDCV (leb128, one byte)
  for (int i = 0; i < 3; i++) {
    obu_put(&w, px[i], 16);
    obu_put(&w, py[i], 16);
  }
  obu_put(&w, wx, 16);
  obu_put(&w, wy, 16);
  obu_put(&w, lmax, 32);
  obu_put(&w, lmin, 32);
  if (!cut) obu_put(&w, 0x80, 8);  // trailing_bits
  return obu_append(out, len, 5, w.b, w.bit / 8 - cut);
}

// HDR_CLL metadata (5.8.3).
static size_t obu_cll(uint8_t* out, size_t len, uint16_t max_cll,
                      uint16_t max_fall) {
  uint8_t p[6] = {1,
                  (uint8_t)(max_cll >> 8),
                  (uint8_t)max_cll,
                  (uint8_t)(max_fall >> 8),
                  (uint8_t)max_fall,
                  0x80};  // trailing_bits
  return obu_append(out, len, 5, p, sizeof(p));
}
