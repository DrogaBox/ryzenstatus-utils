// av1state: checks that the AV1 parser keeps a consistent state across
// samples when one of them is refused. Each case starts from the first
// temporal unit of a real stream.
//
//   1. A frame header sent as its own OBU, then the tiles as a tile group OBU,
//      gives the same frame as the original OBU_FRAME.
//   2. After a valid frame header, a refused sample must end that frame: a
//      later tile group may not complete it with the refused sample's state.
//   3. A refused header must leave the reference state exactly as it was.
//   4. A tile group with no tile bytes is refused.
//   5. A still picture header with more than 14 luma or 10 chroma film grain
//      points is refused and leaves the references as they were; the same
//      header with 14 and 10 points parses.
//   6. A sequence header cut short is refused and leaves the stored one as
//      it was; a frame after it still parses with the first header; a
//      different valid sequence header replaces it.
//   7. What the parser hands the decoder across a change of sequence header:
//      a key frame at 8 bits, then a 10-bit sequence header and an inter
//      frame using slot 0 hand over seq.BitDepth 10 with the reference's
//      bit_depth still 8 (the state the decoder-side check relies on; no
//      code change, this pins it).
//
// usage: av1state file.ivf   (a single-tile AV1 stream; exit status 0 = pass)
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "av1parse.h"

enum {
  kObuSequenceHeader = 1,
  kObuFrameHeader = 3,
  kObuTileGroup = 4,
  kObuFrame = 6
};

static int failures;
static void expect(const char* what, bool ok) {
  printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) failures++;
}

typedef struct {
  int ready, shown;
  size_t header_bytes;
  size_t tile_bytes;
  uint64_t tile_hash;
} Seen;

static int on_frame(void* ctx, AV1Parser* p, AV1ParseResult kind) {
  Seen* s = ctx;
  if (kind == AV1_PARSE_SHOW_EXISTING) {
    s->shown++;
    return 0;
  }
  s->ready++;
  s->tile_bytes = p->tile_data_size;
  uint64_t h = 0xcbf29ce484222325ull;
  for (size_t i = 0; i < p->tile_data_size; i++)
    h = (h ^ p->tile_data[i]) * 0x100000001b3ull;
  s->tile_hash = h;
  av1_reference_update(p, 0);
  return 0;
}

// Header bytes of the frame header inside an OBU_FRAME, read as the parser
// records them before the tiles.
static int on_header_bytes(void* ctx, AV1Parser* p, AV1ParseResult kind) {
  (void)kind;
  *(size_t*)ctx = p->fh.header_bytes;
  return 0;
}

// The depths of the handover, recorded before the reference update replaces
// the slots.
static int handover_seq_depth, handover_ref_depth;
static int on_handover(void* ctx, AV1Parser* p, AV1ParseResult kind) {
  Seen* s = ctx;
  if (kind == AV1_PARSE_SHOW_EXISTING) {
    s->shown++;
    return 0;
  }
  s->ready++;
  handover_seq_depth = p->seq.BitDepth;
  handover_ref_depth = p->ref[p->fh.ref_frame_idx[0]].bit_depth;
  av1_reference_update(p, 0);
  return 0;
}

static size_t put_obu(uint8_t* out, int type, const uint8_t* payload,
                      size_t size) {
  size_t n = 0;
  out[n++] = (uint8_t)(type << 3 | 0x02);  // has_size_field
  size_t v = size;
  do {
    uint8_t byte = v & 0x7f;
    v >>= 7;
    out[n++] = byte | (v ? 0x80 : 0);
  } while (v);
  memcpy(out + n, payload, size);
  return n + size;
}

// A hand-made bit string, most significant bit first.
typedef struct {
  uint8_t d[256];
  size_t pos;
} BW;
static void put(BW* w, uint32_t v, int n) {
  for (int i = n - 1; i >= 0; i--, w->pos++)
    if (v >> i & 1) w->d[w->pos >> 3] |= (uint8_t)(0x80 >> (w->pos & 7));
}

// A reduced still picture sequence header (profile 0, 16x16, 4:2:0, film grain
// present) and its frame header with the given film grain point counts, as a
// sequence header OBU + frame header OBU. Returns the size in bytes.
static size_t grain_still(uint8_t* out, int y_points, int cb_points,
                          int cr_points) {
  BW s = {{0}, 0};
  put(&s, 0, 3);   // seq_profile
  put(&s, 1, 1);   // still_picture
  put(&s, 1, 1);   // reduced_still_picture_header
  put(&s, 0, 5);   // seq_level_idx
  put(&s, 3, 4);   // frame_width_bits_minus_1
  put(&s, 3, 4);   // frame_height_bits_minus_1
  put(&s, 15, 4);  // max_frame_width_minus_1
  put(&s, 15, 4);  // max_frame_height_minus_1
  put(&s, 0, 3);   // 64x64 superblocks, no filter intra, no intra edge
  put(&s, 0, 3);   // no superres, cdef, restoration
  put(&s, 0, 1);   // high_bitdepth
  put(&s, 0, 1);   // mono_chrome
  put(&s, 0, 1);   // color_description_present_flag
  put(&s, 0, 1);   // color_range
  put(&s, 0, 2);   // chroma_sample_position
  put(&s, 0, 1);   // separate_uv_delta_q
  put(&s, 1, 1);   // film_grain_params_present
  BW h = {{0}, 0};
  put(&h, 0, 1);      // disable_cdf_update
  put(&h, 0, 1);      // allow_screen_content_tools
  put(&h, 0, 1);      // no render size
  put(&h, 1, 1);      // uniform_tile_spacing_flag (one tile)
  put(&h, 100, 8);    // base_q_idx
  put(&h, 0, 3);      // no DeltaQYDc, DeltaQUDc, DeltaQUAc
  put(&h, 0, 1);      // using_qmatrix
  put(&h, 0, 1);      // segmentation_enabled
  put(&h, 0, 1);      // delta_q_present
  put(&h, 0, 12);     // loop_filter_level[0], [1]
  put(&h, 0, 3);      // loop_filter_sharpness
  put(&h, 0, 1);      // loop_filter_delta_enabled
  put(&h, 0, 1);      // tx_mode_select
  put(&h, 0, 1);      // reduced_tx_set
  put(&h, 1, 1);      // apply_grain
  put(&h, 1234, 16);  // grain_seed
  put(&h, y_points, 4);
  for (int i = 0; i < y_points; i++) {
    put(&h, 16 * i, 8);  // point_y_value
    put(&h, 64, 8);      // point_y_scaling
  }
  put(&h, 0, 1);  // chroma_scaling_from_luma
  put(&h, cb_points, 4);
  for (int i = 0; i < cb_points; i++) {
    put(&h, 20 * i, 8);
    put(&h, 32, 8);
  }
  put(&h, cr_points, 4);
  for (int i = 0; i < cr_points; i++) {
    put(&h, 20 * i, 8);
    put(&h, 32, 8);
  }
  // The rest of the film grain fields read as zeros from the padding.
  size_t n = put_obu(out, kObuSequenceHeader, s.d, (s.pos + 7) >> 3);
  return n + put_obu(out + n, kObuFrameHeader, h.d, ((h.pos + 7) >> 3) + 16);
}

// Finds the OBUs of one temporal unit (each with a size field).
static bool find_obu(const uint8_t* tu, size_t size, int type,
                     const uint8_t** payload, size_t* payload_size) {
  size_t off = 0;
  while (off < size) {
    uint8_t hdr = tu[off];
    size_t pos = off + 1 + ((hdr >> 2) & 1);
    if (!(hdr & 0x02)) return false;
    uint64_t len = 0;
    for (int i = 0; i < 8 && pos < size; i++) {
      len |= (uint64_t)(tu[pos] & 0x7f) << (7 * i);
      if (!(tu[pos++] & 0x80)) break;
    }
    if (len > size - pos) return false;
    if (((hdr >> 3) & 15) == type) {
      *payload = tu + pos;
      *payload_size = (size_t)len;
      return true;
    }
    off = pos + (size_t)len;
  }
  return false;
}

int main(int argc, char** argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: av1state file.ivf\n");
    return 2;
  }
  FILE* f = fopen(argv[1], "rb");
  if (!f) return 2;
  static uint8_t file[1 << 20];
  size_t n = fread(file, 1, sizeof(file), f);
  fclose(f);
  if (n < 44 || memcmp(file, "DKIF", 4) || memcmp(file + 8, "AV01", 4)) {
    fprintf(stderr, "%s: not an AV1 IVF file\n", argv[1]);
    return 2;
  }
  size_t pos = (size_t)(file[6] | file[7] << 8);
  size_t tu_size = (size_t)file[pos] | (size_t)file[pos + 1] << 8 |
                   (size_t)file[pos + 2] << 16 | (size_t)file[pos + 3] << 24;
  const uint8_t* tu = file + pos + 12;
  if (tu_size > n - pos - 12) return 2;

  const uint8_t *seq, *frame;
  size_t seq_size, frame_size;
  if (!find_obu(tu, tu_size, kObuSequenceHeader, &seq, &seq_size) ||
      !find_obu(tu, tu_size, kObuFrame, &frame, &frame_size)) {
    fprintf(stderr, "%s: first temporal unit has no OBU_FRAME\n", argv[1]);
    return 2;
  }
  static uint8_t seq_obu[4096], hdr_obu[4096], tiles_obu[1 << 20], buf[1 << 20];
  size_t seq_n = put_obu(seq_obu, kObuSequenceHeader, seq, seq_size);

  // Reference: the original temporal unit.
  AV1Parser* p = calloc(1, sizeof(*p));
  av1_parser_init(p);
  Seen want = {0};
  expect("the first temporal unit parses",
         !av1_parse_temporal_unit(p, tu, tu_size, on_frame, &want) &&
             want.ready == 1);
  av1_parser_free(p);

  // Split the frame: header OBU + tile group OBU.
  size_t header_bytes = 0;
  av1_parser_init(p);
  av1_parse_temporal_unit(p, seq_obu, seq_n, on_header_bytes, &header_bytes);
  size_t nb = put_obu(buf, kObuFrame, frame, frame_size);
  av1_parse_temporal_unit(p, buf, nb, on_header_bytes, &header_bytes);
  av1_parser_free(p);
  if (!header_bytes || header_bytes >= frame_size) {
    fprintf(stderr, "could not find the frame header size\n");
    return 1;
  }
  size_t hdr_n = put_obu(hdr_obu, kObuFrameHeader, frame, header_bytes);
  size_t tiles_n = put_obu(tiles_obu, kObuTileGroup, frame + header_bytes,
                           frame_size - header_bytes);

  // 1. split form decodes the same frame
  av1_parser_init(p);
  Seen got = {0};
  av1_parse_temporal_unit(p, seq_obu, seq_n, on_frame, &got);
  memcpy(buf, hdr_obu, hdr_n);
  memcpy(buf + hdr_n, tiles_obu, tiles_n);
  int r = av1_parse_temporal_unit(p, buf, hdr_n + tiles_n, on_frame, &got);
  expect("header OBU + tile group OBU give the same frame as OBU_FRAME",
         !r && got.ready == 1 && got.tile_bytes == want.tile_bytes &&
             got.tile_hash == want.tile_hash);
  av1_parser_free(p);

  // 2. a refused sample ends the pending frame
  av1_parser_init(p);
  got = (Seen){0};
  av1_parse_temporal_unit(p, seq_obu, seq_n, on_frame, &got);
  r = av1_parse_temporal_unit(p, hdr_obu, hdr_n, on_frame, &got);
  expect("a frame header alone is accepted, no frame yet",
         !r && got.ready == 0);
  nb = put_obu(buf, kObuFrame, frame, 1);  // truncated: refused
  expect("a truncated OBU_FRAME is refused",
         av1_parse_temporal_unit(p, buf, nb, on_frame, &got) != 0);
  r = av1_parse_temporal_unit(p, tiles_obu, tiles_n, on_frame, &got);
  expect("a tile group after a refused sample does not complete a frame",
         r != 0 && got.ready == 0);
  av1_parser_free(p);

  // 3. a refused header leaves the references untouched
  av1_parser_init(p);
  got = (Seen){0};
  av1_parse_temporal_unit(p, seq_obu, seq_n, on_frame, &got);
  av1_parse_temporal_unit(p, tu, tu_size, on_frame, &got);
  AV1RefSlot before[AV1_NUM_REF_FRAMES];
  memcpy(before, p->ref, sizeof(before));
  // A shown key frame header, cut right after its first byte: the parser
  // resets the references for a shown key frame, then runs out of bits.
  const uint8_t cut[] = {kObuFrame << 3 | 0x02, 0x01, 0x10};
  r = av1_parse_temporal_unit(p, cut, sizeof(cut), on_frame, &got);
  expect("a cut key frame header is refused", r != 0);
  expect("the references are as they were before it",
         !memcmp(before, p->ref, sizeof(before)));
  av1_parser_free(p);

  // 4. an empty tile group is refused
  av1_parser_init(p);
  got = (Seen){0};
  av1_parse_temporal_unit(p, seq_obu, seq_n, on_frame, &got);
  av1_parse_temporal_unit(p, hdr_obu, hdr_n, on_frame, &got);
  nb = put_obu(buf, kObuTileGroup, NULL, 0);
  r = av1_parse_temporal_unit(p, buf, nb, on_frame, &got);
  expect("a tile group with no tile bytes is refused", r != 0 && !got.ready);
  av1_parser_free(p);

  // 5. film grain point counts past the format's limits
  av1_parser_init(p);
  nb = grain_still(buf, 14, 10, 10);
  r = av1_parse_temporal_unit(p, buf, nb, on_frame, &got);
  const AV1FilmGrain* g = &p->fh.film_grain;
  expect("a still picture with 14 luma and 10 chroma grain points parses",
         !r && g->apply_grain && g->num_y_points == 14 &&
             g->num_cb_points == 10 && g->num_cr_points == 10 &&
             g->point_cr_value[9] == 180);
  av1_parser_free(p);
  static const int too_many[3][3] = {{15, 10, 10}, {14, 11, 10}, {14, 10, 11}};
  static const char* what[3] = {"15 luma grain points are refused",
                                "11 Cb grain points are refused",
                                "11 Cr grain points are refused"};
  bool kept_refs = true;
  for (int i = 0; i < 3; i++) {
    av1_parser_init(p);
    got = (Seen){0};
    av1_parse_temporal_unit(p, seq_obu, seq_n, on_frame, &got);
    av1_parse_temporal_unit(p, tu, tu_size, on_frame, &got);
    memcpy(before, p->ref, sizeof(before));
    nb = grain_still(buf, too_many[i][0], too_many[i][1], too_many[i][2]);
    expect(what[i], av1_parse_temporal_unit(p, buf, nb, on_frame, &got) != 0);
    if (memcmp(before, p->ref, sizeof(before))) kept_refs = false;
    av1_parser_free(p);
  }
  expect("the refused grain headers leave the references as they were",
         kept_refs);

  // 6. a refused sequence header leaves the stored one as it was; a
  //    different valid one replaces it
  av1_parser_init(p);
  got = (Seen){0};
  av1_parse_temporal_unit(p, seq_obu, seq_n, on_frame, &got);
  AV1Seq seq_before;
  memcpy(&seq_before, &p->seq, sizeof(seq_before));
  nb = put_obu(buf, kObuSequenceHeader, seq, 1);  // truncated: refused
  r = av1_parse_temporal_unit(p, buf, nb, on_frame, &got);
  expect("a cut sequence header is refused", r != 0);
  expect("the stored sequence header is as it was before it",
         !memcmp(&seq_before, &p->seq, sizeof(seq_before)));
  memcpy(buf, hdr_obu, hdr_n);
  memcpy(buf + hdr_n, tiles_obu, tiles_n);
  r = av1_parse_temporal_unit(p, buf, hdr_n + tiles_n, on_frame, &got);
  expect("a frame after a refused sequence header still parses with the first",
         !r && got.ready == 1 && got.tile_hash == want.tile_hash);
  nb = grain_still(buf, 0, 0, 0);
  const uint8_t* grain_seq;
  size_t grain_seq_size;
  if (!find_obu(buf, nb, kObuSequenceHeader, &grain_seq, &grain_seq_size)) {
    fprintf(stderr, "could not find the grain sequence header\n");
    return 1;
  }
  nb = put_obu(hdr_obu, kObuSequenceHeader, grain_seq, grain_seq_size);
  r = av1_parse_temporal_unit(p, hdr_obu, nb, on_frame, &got);
  expect("a different valid sequence header replaces the stored one",
         !r && p->seq.valid && p->seq.film_grain_params_present == 1 &&
             memcmp(&seq_before, &p->seq, sizeof(seq_before)) != 0);
  av1_parser_free(p);

  // 7. what the parser hands the decoder across a change of sequence header:
  //    a key frame at 8 bits, then a 10-bit sequence header and an inter
  //    frame that uses slot 0 (the a1 scenario, a1-harness.c). No code
  //    change here: this pins the state the decoder-side check relies on.
  static const uint8_t tu1[] = {0x0a, 0x08, 0x18, 0x3f, 0xc0, 0x0f, 0xc0,
                                0x0f, 0xc0, 0x00, 0x32, 0x06, 0x16, 0x40,
                                0x00, 0x00, 0x00, 0x55};
  static const uint8_t tu2[] = {0x0a, 0x0c, 0x00, 0x00, 0x00, 0x07, 0xf8,
                                0x01, 0xf8, 0x01, 0xf8, 0x03, 0x10, 0x00,
                                0x32, 0x0e, 0x30, 0xe1, 0xe0, 0x00, 0x00,
                                0x01, 0x64, 0x00, 0xa2, 0x8a, 0x28, 0x00,
                                0x00, 0x66};
  av1_parser_init(p);
  got = (Seen){0};
  r = av1_parse_temporal_unit(p, tu1, sizeof tu1, on_handover, &got);
  expect("the 8-bit key frame temporal unit parses",
         !r && got.ready == 1 && handover_seq_depth == 8);
  r = av1_parse_temporal_unit(p, tu2, sizeof tu2, on_handover, &got);
  expect("the inter frame hands over seq 10 with its reference at 8",
         !r && got.ready == 2 && handover_seq_depth == 10 &&
             handover_ref_depth == 8);
  av1_parser_free(p);

  free(p);
  return failures ? 1 : 0;
}
