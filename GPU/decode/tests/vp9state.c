// vp9state: checks that the VP9 parser keeps the state that outlives a frame
// when a frame header is refused.
//
//   1. Every cut copy of the first frames' headers that is refused leaves the
//      references, colour config, loop filter deltas and segmentation exactly
//      as they were.
//   2. A profile 2 key frame header cut after its colour config is refused and
//      does not change the bit depth of an 8-bit stream.
//   3. A frame that ends where its headers end, with no tile data, is refused.
//   4. A 65536 wide key frame header that codes more than 64 tile columns is
//      refused and leaves the state as it was; the same header with 64 tile
//      columns parses.
//   5. A profile 0 inter frame after a 10-bit profile 2 key frame is refused
//      (the profile table has no such frame) and leaves the stream depth as
//      it was; the next valid key frame decodes.
//
// usage: vp9state file.ivf   (a profile 0 VP9 stream; exit status 0 = pass)
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vp9parse.h"

static int failures;
static void expect(const char* what, bool ok) {
  printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) failures++;
}

// The state that outlives a frame, field by field (no padding compared).
static bool same_state(const VP9Parser* a, const VP9Parser* b) {
  for (int i = 0; i < 8; i++) {
    const VP9Ref *x = &a->ref[i], *y = &b->ref[i];
    if (x->valid != y->valid || x->dpb_slot != y->dpb_slot ||
        x->width != y->width || x->height != y->height ||
        x->bit_depth != y->bit_depth)
      return false;
  }
  return a->bit_depth == b->bit_depth && a->subsampling_x == b->subsampling_x &&
         a->subsampling_y == b->subsampling_y &&
         !memcmp(a->lf_ref_deltas, b->lf_ref_deltas,
                 sizeof(a->lf_ref_deltas)) &&
         !memcmp(a->lf_mode_deltas, b->lf_mode_deltas,
                 sizeof(a->lf_mode_deltas)) &&
         a->seg_abs_delta == b->seg_abs_delta &&
         !memcmp(a->seg_feature_mask, b->seg_feature_mask,
                 sizeof(a->seg_feature_mask)) &&
         !memcmp(a->seg_feature_data, b->seg_feature_data,
                 sizeof(a->seg_feature_data)) &&
         !memcmp(a->seg_tree_probs, b->seg_tree_probs,
                 sizeof(a->seg_tree_probs)) &&
         !memcmp(a->seg_pred_probs, b->seg_pred_probs,
                 sizeof(a->seg_pred_probs)) &&
         a->last_width == b->last_width && a->last_height == b->last_height &&
         a->last_show_frame == b->last_show_frame &&
         a->last_intra_only == b->last_intra_only &&
         a->have_last == b->have_last;
}

// A hand-made bit string, most significant bit first.
typedef struct {
  uint8_t d[64];
  size_t pos;
} BW;
static void put(BW* w, uint32_t v, int n) {
  for (int i = n - 1; i >= 0; i--, w->pos++)
    if (v >> i & 1) w->d[w->pos >> 3] |= (uint8_t)(0x80 >> (w->pos & 7));
}

// A profile 0 key frame, 65536x64, that changes the loop filter deltas and the
// segmentation before its tile info, with log2_tile_cols coded as
// 4 (the minimum for this width) + extra. Returns the frame size in bytes.
static size_t wide_key_frame(uint8_t* out, int extra) {
  BW w = {{0}, 0};
  put(&w, 2, 2);          // frame_marker
  put(&w, 0, 2);          // profile 0
  put(&w, 0, 1);          // show_existing_frame
  put(&w, 0, 1);          // key frame
  put(&w, 1, 1);          // show_frame
  put(&w, 0, 1);          // error_resilient_mode
  put(&w, 0x498342, 24);  // sync code
  put(&w, 1, 3);          // color_space BT.601
  put(&w, 0, 1);          // color_range
  put(&w, 65535, 16);     // frame_width_minus_1
  put(&w, 63, 16);        // frame_height_minus_1
  put(&w, 0, 1);          // no render size
  put(&w, 1, 1);          // refresh_frame_context
  put(&w, 1, 1);          // frame_parallel_decoding_mode
  put(&w, 0, 2);          // frame_context_idx
  put(&w, 10, 6);         // filter_level
  put(&w, 0, 3);          // sharpness
  put(&w, 1, 1);          // loop_filter_delta_enabled
  put(&w, 1, 1);          // loop_filter_delta_update
  for (int i = 0; i < 4; i++) {
    put(&w, 1, 1);  // update_ref_delta
    put(&w, 5, 6);  // 5
    put(&w, 1, 1);  // negative
  }
  for (int i = 0; i < 2; i++) {
    put(&w, 1, 1);  // update_mode_delta
    put(&w, 3, 6);
    put(&w, 0, 1);
  }
  put(&w, 60, 8);  // base_q_idx
  put(&w, 0, 3);   // no delta_q
  put(&w, 1, 1);   // segmentation_enabled
  put(&w, 0, 1);   // no update_map
  put(&w, 1, 1);   // update_data
  put(&w, 1, 1);   // abs_or_delta_update
  for (int i = 0; i < 8; i++)
    for (int j = 0; j < 4; j++) {
      bool on = i == 0 && j == 0;
      put(&w, on, 1);  // feature_enabled
      if (on) {
        put(&w, 40, 8);  // alternate quantizer 40
        put(&w, 0, 1);
      }
    }
  for (int i = 0; i < extra; i++) put(&w, 1, 1);  // increment_tile_cols_log2
  put(&w, 0, 1);   // stop (the maximum for this width is 8)
  put(&w, 0, 1);   // log2_tile_rows 0
  put(&w, 1, 16);  // header_size_in_bytes
  size_t n = (w.pos + 7) >> 3;
  memcpy(out, w.d, n);
  out[n] = 0;      // compressed header
  out[n + 1] = 0;  // tile data
  return n + 2;
}

static int slot;
static int on_frame(void* ctx, VP9Parser* p, VP9ParseResult kind,
                    const uint8_t* data, size_t size) {
  (void)ctx;
  (void)data;
  (void)size;
  if (kind == VP9_PARSE_DECODE) vp9_frame_done(p, slot++ % 8);
  return 0;
}

int main(int argc, char** argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: vp9state file.ivf\n");
    return 2;
  }
  FILE* f = fopen(argv[1], "rb");
  if (!f) return 2;
  static uint8_t file[4 << 20];
  size_t n = fread(file, 1, sizeof(file), f);
  fclose(f);
  if (n < 44 || memcmp(file, "DKIF", 4) || memcmp(file + 8, "VP90", 4)) {
    fprintf(stderr, "%s: not a VP9 IVF file\n", argv[1]);
    return 2;
  }
  size_t pos = (size_t)(file[6] | file[7] << 8);

  VP9Parser* p = calloc(1, sizeof(*p));
  VP9Parser* before = calloc(1, sizeof(*before));
  if (!p || !before) return 2;
  vp9_parser_init(p);
  int frames = 0, cuts = 0, kept = 0;
  bool all_parse = true;
  while (frames < 12 && pos + 12 <= n) {
    size_t size = (size_t)file[pos] | (size_t)file[pos + 1] << 8 |
                  (size_t)file[pos + 2] << 16 | (size_t)file[pos + 3] << 24;
    const uint8_t* chunk = file + pos + 12;
    if (size > n - pos - 12) break;
    pos += 12 + size;
    // Cut copies of the chunk: the first frame's header is read from them.
    for (size_t cut = 1; cut < size && cut <= 256; cut++) {
      memcpy(before, p, sizeof(*p));
      if (vp9_parse_frame_header(p, chunk, cut)) {
        cuts++;
        if (same_state(p, before)) kept++;
      }
      memcpy(p, before, sizeof(*p));
    }
    if (vp9_parse_chunk(p, chunk, size, on_frame, NULL)) all_parse = false;
    frames++;
  }
  expect("the first frames of the stream parse", frames > 0 && all_parse);
  printf("     %d refused cut headers\n", cuts);
  expect("every refused cut header leaves the state as it was",
         cuts > 0 && kept == cuts);

  // A profile 2 key frame: 10-bit colour config, then cut before its size.
  static const uint8_t p2key[] = {0x93, 0x49, 0x83, 0x42, 0x10};
  int depth = p->bit_depth;
  int r = vp9_parse_frame_header(p, p2key, sizeof(p2key));
  expect("a cut profile 2 key frame header is refused", r != 0);
  expect("the stream's bit depth is as it was",
         depth == 8 && p->bit_depth == 8);

  // The first frame again, ending where its headers end.
  pos = (size_t)(file[6] | file[7] << 8);
  size_t size = (size_t)file[pos] | (size_t)file[pos + 1] << 8 |
                (size_t)file[pos + 2] << 16 | (size_t)file[pos + 3] << 24;
  const uint8_t* chunk = file + pos + 12;
  VP9Parser* q = calloc(1, sizeof(*q));
  if (!q) return 2;
  vp9_parser_init(q);
  bool first = !vp9_parse_frame_header(q, chunk, size);
  size_t headers =
      first ? q->fh.uncompressed_header_size + q->fh.compressed_header_size : 0;
  expect("the first frame's header parses", first && headers < size);
  vp9_parser_init(q);
  expect("the same frame with no tile data is refused",
         headers && vp9_parse_frame_header(q, chunk, headers) != 0);

  // More than 64 tile columns: 4 + 3 = log2 7.
  uint8_t wide[64];
  vp9_parser_init(q);
  size_t wn = wide_key_frame(wide, 2);
  expect("a 65536 wide key frame with 64 tile columns parses",
         !vp9_parse_frame_header(q, wide, wn) && q->fh.width == 65536 &&
             q->fh.log2_tile_cols == 6 && q->lf_ref_deltas[0] == -5 &&
             q->seg_feature_mask[0] == 1);
  memcpy(before, p, sizeof(*p));
  wn = wide_key_frame(wide, 3);
  expect("the same frame with 128 tile columns is refused",
         vp9_parse_frame_header(p, wide, wn) != 0);
  expect("the refused wide frame leaves the state as it was",
         same_state(p, before));

  // A profile 2 key frame at 10 bits, then a profile 0 inter frame: the
  // profile table has no "profile 0, 10 bits", so the inter frame is refused
  // with the stream depth as it was, and the next valid key frame decodes.
  // The three chunks are the V1 finding's inputs.
  static const uint8_t v1key[] = {0x93, 0x49, 0x83, 0x42, 0x10, 0x01, 0xf8,
                                  0x01, 0xf8, 0x00, 0x19, 0x00, 0x00, 0x04,
                                  0x42, 0x00, 0x00};
  static const uint8_t v1inter[] = {0x86, 0x03, 0xc0, 0x02, 0x08, 0x00, 0x32,
                                    0x00, 0x00, 0x04, 0x42, 0x00, 0x00};
  static const uint8_t v1next[] = {0x83, 0x49, 0x83, 0x42, 0x20, 0x03, 0xf0,
                                   0x03, 0xf0, 0x00, 0x32, 0x00, 0x00, 0x08,
                                   0x42, 0x00, 0x00};
  vp9_parser_init(q);
  expect("a profile 2 key frame at 10 bits decodes",
         !vp9_parse_chunk(q, v1key, sizeof v1key, on_frame, NULL) &&
             q->fh.profile == 2 && q->fh.bit_depth == 10 &&
             q->ref[0].valid && q->ref[0].bit_depth == 10);
  expect("a profile 0 inter frame after it is refused",
         vp9_parse_chunk(q, v1inter, sizeof v1inter, on_frame, NULL) != 0 &&
             q->bit_depth == 10 && q->err[0]);
  expect("the next valid key frame decodes",
         !vp9_parse_chunk(q, v1next, sizeof v1next, on_frame, NULL) &&
             q->fh.profile == 0 && q->fh.bit_depth == 8 && q->ref[0].valid &&
             q->ref[0].bit_depth == 8);

  free(p);
  free(before);
  free(q);
  return failures ? 1 : 0;
}
