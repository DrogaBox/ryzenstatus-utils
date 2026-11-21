// vp9state: checks that the VP9 parser keeps the state that outlives a frame
// when a frame header is refused.
//
//   1. Every cut copy of the first frames' headers that is refused leaves the
//      references, colour config, loop filter deltas and segmentation exactly
//      as they were.
//   2. A profile 2 key frame header cut after its colour config is refused and
//      does not change the bit depth of an 8-bit stream.
//   3. A frame that ends where its headers end, with no tile data, is refused.
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

  free(p);
  free(before);
  free(q);
  return failures ? 1 : 0;
}
