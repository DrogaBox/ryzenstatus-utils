#include "mpeg4parse.h"

#include <stdio.h>
#include <string.h>

#include "bitreader.h"

// Zigzag scan of ISO 14496-2 figure 7-3 (the same as MPEG-2's).
static const uint8_t kZigzag[64] = {
    0,  1,  8,  16, 9,  2,  3,  10, 17, 24, 32, 25, 18, 11, 4,  5,
    12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6,  7,  14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63};

// Default matrices of ISO 14496-2 6.3.3, by rows.
static const uint8_t kDefaultIntra[64] = {
    8,  17, 18, 19, 21, 23, 25, 27, 17, 18, 19, 21, 23, 25, 27, 28,
    20, 21, 22, 23, 24, 26, 28, 30, 21, 22, 23, 24, 26, 28, 30, 32,
    22, 23, 24, 26, 28, 30, 32, 35, 23, 24, 26, 28, 30, 32, 35, 38,
    25, 26, 28, 30, 32, 35, 38, 41, 27, 28, 30, 32, 35, 38, 41, 45};
static const uint8_t kDefaultNonIntra[64] = {
    16, 17, 18, 19, 20, 21, 22, 23, 17, 18, 19, 20, 21, 22, 23, 24,
    18, 19, 20, 21, 22, 23, 24, 25, 19, 20, 21, 22, 23, 24, 26, 27,
    20, 21, 22, 23, 25, 26, 27, 28, 21, 22, 23, 24, 26, 27, 28, 30,
    22, 23, 24, 26, 27, 28, 30, 31, 23, 24, 25, 27, 28, 30, 31, 33};

void mpeg4_parser_init(Mpeg4Parser* p) { memset(p, 0, sizeof(*p)); }

static int fail(Mpeg4Parser* p, const char* what) {
  snprintf(p->err, sizeof(p->err), "%s", what);
  return -1;
}

// A matrix is sent in zigzag order and may stop early with a zero: the rest
// repeats the last value (ISO 14496-2 6.3.3).
static void read_matrix(BitReader* b, uint8_t* m) {
  uint8_t last = 0;
  int i = 0;
  for (; i < 64; i++) {
    uint8_t v = (uint8_t)br_get(b, 8);
    if (!v) break;
    m[i] = last = v;
  }
  if (!i) return;  // a zero first: the matrix stays as it was
  for (; i < 64; i++) m[i] = last;
}

// ISO 14496-2 6.2.3, in order. What the decode message cannot say is refused.
static int vol_header(Mpeg4Parser* p, const uint8_t* d, size_t n) {
  BitReader b;
  br_init(&b, d, n);
  Mpeg4Parser v = {0};
  v.profile_and_level = p->profile_and_level;
  br_get(&b, 1);                           // random_accessible_vol
  v.object_type = (uint8_t)br_get(&b, 8);  // video_object_type_indication
  v.verid = 1;
  if (br_get(&b, 1)) {  // is_object_layer_identifier
    v.verid = (uint8_t)br_get(&b, 4);
    br_get(&b, 3);  // priority
  }
  if (br_get(&b, 4) == 15) br_get(&b, 16);  // extended PAR
  // A Simple object has no B-VOPs, and neither has a VOL whose low_delay is
  // set (ISO 14496-2 6.3.3). Without vol_control_parameters nothing says.
  v.no_b_vops = v.object_type == 1;
  if (br_get(&b, 1)) {                      // vol_control_parameters
    br_get(&b, 2);                          // chroma_format
    if (br_get(&b, 1)) v.no_b_vops = true;  // low_delay
    if (br_get(&b, 1)) br_skip(&b, 79);     // vbv_parameters
  }
  uint32_t shape = br_get(&b, 2);
  if (b.err) return fail(p, "MPEG-4 VOL header too short");
  if (shape != 0) return fail(p, "MPEG-4 shape coding is not supported");
  br_get(&b, 1);  // marker
  v.time_increment_resolution = (uint16_t)br_get(&b, 16);
  br_get(&b, 1);  // marker
  if (!v.time_increment_resolution)
    return fail(p, "MPEG-4 VOL with a time resolution of 0");
  // The number of bits that hold 0 .. resolution - 1, at least one.
  v.time_increment_bits = 1;
  while (v.time_increment_bits < 16 &&
         (1u << v.time_increment_bits) < v.time_increment_resolution)
    v.time_increment_bits++;
  if (br_get(&b, 1)) br_get(&b, v.time_increment_bits);  // fixed_vop_rate
  br_get(&b, 1);                                         // marker
  v.width = br_get(&b, 13);
  br_get(&b, 1);  // marker
  v.height = br_get(&b, 13);
  br_get(&b, 1);  // marker
  v.interlaced = (uint8_t)br_get(&b, 1);
  v.obmc_disable = (uint8_t)br_get(&b, 1);
  uint32_t sprite = v.verid == 1 ? br_get(&b, 1) : br_get(&b, 2);
  if (b.err) return fail(p, "MPEG-4 VOL header too short");
  if (sprite) return fail(p, "MPEG-4 sprites and GMC are not supported");
  v.quant_precision = 5;
  if (br_get(&b, 1)) {  // not_8_bit
    v.quant_precision = (uint8_t)br_get(&b, 4);
    if (br_get(&b, 4) != 8 || v.quant_precision != 5)
      return fail(p, "MPEG-4 with more than 8 bits is not supported");
  }
  for (int i = 0; i < 64; i++) {
    v.intra_matrix[i] = kDefaultIntra[kZigzag[i]];
    v.nonintra_matrix[i] = kDefaultNonIntra[kZigzag[i]];
  }
  v.quant_type = (uint8_t)br_get(&b, 1);
  if (v.quant_type) {
    if (br_get(&b, 1)) read_matrix(&b, v.intra_matrix);
    if (br_get(&b, 1)) read_matrix(&b, v.nonintra_matrix);
  }
  if (v.verid != 1) v.quarter_sample = (uint8_t)br_get(&b, 1);
  if (!br_get(&b, 1))  // complexity_estimation_disable
    return fail(p, "MPEG-4 complexity estimation headers are not supported");
  v.resync_marker_disable = (uint8_t)br_get(&b, 1);
  if (br_get(&b, 1))  // data_partitioned
    return fail(p, "MPEG-4 data partitioning is not supported");
  if (v.verid != 1) {
    if (br_get(&b, 1)) return fail(p, "MPEG-4 newpred is not supported");
    if (br_get(&b, 1))
      return fail(p, "MPEG-4 reduced resolution VOPs are not supported");
  }
  if (br_get(&b, 1)) return fail(p, "MPEG-4 scalability is not supported");
  if (b.err) return fail(p, "MPEG-4 VOL header too short");
  if (!v.width || !v.height) return fail(p, "MPEG-4 VOL without a size");
  v.have_vol = true;
  *p = v;
  return 0;
}

// ISO 14496-2 6.2.5 up to the f_codes; the times as FFmpeg's
// decode_vop_header computes them.
static int vop_header(Mpeg4Parser* p, const uint8_t* d, size_t n,
                      Mpeg4Picture* pic) {
  BitReader b;
  br_init(&b, d, n);
  pic->coding_type = (uint8_t)br_get(&b, 2);
  uint32_t seconds = 0;
  while (!b.err && br_get(&b, 1)) seconds++;  // modulo_time_base
  br_get(&b, 1);                              // marker
  uint32_t increment = br_get(&b, p->time_increment_bits);
  br_get(&b, 1);  // marker
  pic->vop_coded = (uint8_t)br_get(&b, 1);
  if (b.err) return fail(p, "MPEG-4 VOP header too short");
  if (pic->coding_type == MPEG4_S)
    return fail(p, "MPEG-4 sprite VOPs are not supported");
  int64_t res = p->time_increment_resolution, time;
  if (pic->coding_type != MPEG4_B) {
    p->last_time_base = p->time_base;
    p->time_base += seconds;
    time = p->time_base * res + increment;
    int64_t dist = time - p->last_ref_time;
    p->ref_distance = dist > 0 && dist <= UINT32_MAX ? (uint32_t)dist : 0;
    p->last_ref_time = time;
  } else {
    time = (p->last_time_base + seconds) * res + increment;
    int64_t back = p->last_ref_time - time;  // from the B-VOP to the later one
    pic->trd = p->ref_distance;
    pic->trb = back > 0 && back < p->ref_distance
                   ? p->ref_distance - (uint32_t)back
                   : 0;
  }
  if (!pic->vop_coded) return 0;
  if (pic->coding_type == MPEG4_P) pic->rounding_type = (uint8_t)br_get(&b, 1);
  pic->intra_dc_vlc_thr = (uint8_t)br_get(&b, 3);
  if (p->interlaced) {
    pic->top_field_first = (uint8_t)br_get(&b, 1);
    pic->alternate_vertical_scan = (uint8_t)br_get(&b, 1);
  }
  pic->quant = (uint8_t)br_get(&b, p->quant_precision);
  if (pic->coding_type != MPEG4_I) pic->fcode_forward = (uint8_t)br_get(&b, 3);
  if (pic->coding_type == MPEG4_B) pic->fcode_backward = (uint8_t)br_get(&b, 3);
  if (b.err) return fail(p, "MPEG-4 VOP header too short");
  return 0;
}

int mpeg4_parse_chunk(Mpeg4Parser* p, const uint8_t* data, size_t size,
                      Mpeg4PictureFn fn, void* ctx) {
  p->err[0] = 0;
  p->stop = false;
  p->missing_vol = false;
  size_t at = next_start_code(data, size, 0);
  size_t unit = at;  // where the current access unit's headers begin
  while (at < size) {
    uint8_t code = data[at + 3];
    size_t next = next_start_code(data, size, at + 4);
    const uint8_t* body = data + at + 4;
    size_t bodySize = next - at - 4;
    int r = 0;
    if (code == 0xB0) {  // visual object sequence
      if (bodySize) p->profile_and_level = body[0];
    } else if (code >= 0x20 && code <= 0x2F) {
      r = vol_header(p, body, bodySize);
    } else if (code == 0xB6) {
      if (!p->have_vol) {
        p->missing_vol = true;
        return fail(p, "MPEG-4 VOP before any VOL header");
      }
      Mpeg4Picture pic = {
          .data = data + unit, .size = next - unit, .vopOffset = at - unit};
      r = vop_header(p, body, bodySize, &pic);
      if (!r && fn) r = fn(ctx, p, &pic);
      unit = next;
      if (!r && p->stop) return 0;
    }
    if (r) return r;
    at = next;
  }
  return 0;
}
