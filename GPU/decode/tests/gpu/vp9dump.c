// vp9dump: checks that the VP9 parser reads a file (IVF or WebM), with no
// driver and no GPU. Run it on a new clip before decode_vp9 or vtvp9test.
//
// For every coded frame it walks the tile size markers that follow the
// headers: they only land exactly on the end of the frame if the uncompressed
// header parse (sizes, tile layout, header lengths) was right.
//
// usage: vp9dump file [-v]
//   -v  one line per frame
//
// Exit status: 0 = the whole file was read and every tile walk ended on the
// frame end, 2 = parse error, bad tile walk, or a damaged file.
#include <stdio.h>
#include <string.h>

#include "container.h"
#include "vp9parse.h"

typedef struct {
  int coded, shown, keys, intra, hidden, existing, seg, tiles_bad, verbose,
      prev_mvs, delta_lf, unsupported;
  uint32_t maxw, maxh;
} Stats;

static int on_frame(void* vctx, VP9Parser* p, VP9ParseResult kind,
                    const uint8_t* d, size_t size) {
  Stats* s = vctx;
  const VP9Frame* h = &p->fh;
  if (kind == VP9_PARSE_SHOW_EXISTING) {
    if (!p->ref[h->frame_to_show].valid) {
      snprintf(p->err, sizeof(p->err), "show_existing of a missing reference");
      return -1;
    }
    s->existing++;
    s->shown++;
    if (s->verbose)
      printf("show_existing %d (%ux%u)\n", h->frame_to_show,
             p->ref[h->frame_to_show].width, p->ref[h->frame_to_show].height);
    return 0;
  }
  s->coded++;
  if (h->show_frame)
    s->shown++;
  else
    s->hidden++;
  if (h->frame_type == 0) s->keys++;
  if (h->intra_only) s->intra++;
  if (h->seg_enabled) s->seg++;
  if (h->use_prev_frame_mvs) s->prev_mvs++;
  if (h->lf_delta_update) s->delta_lf++;
  if (!vp9_frame_supported(p)) s->unsupported++;
  if (h->width > s->maxw) s->maxw = h->width;
  if (h->height > s->maxh) s->maxh = h->height;
  // Every tile but the last has a 4 byte big endian size in front of it.
  size_t off = h->uncompressed_header_size + h->compressed_header_size;
  int tiles = 1 << (h->log2_tile_cols + h->log2_tile_rows);
  bool ok = true;
  for (int i = 0; i < tiles - 1; i++) {
    if (off + 4 > size) {
      ok = false;
      break;
    }
    size_t t = (size_t)d[off] << 24 | (size_t)d[off + 1] << 16 |
               (size_t)d[off + 2] << 8 | d[off + 3];
    off += 4 + t;
    if (off > size || !t) {
      ok = false;
      break;
    }
  }
  if (ok && off >= size)
    ok = false;  // the last tile takes what is left, and it cannot be empty
  if (!ok) s->tiles_bad++;
  if (s->verbose)
    printf(
        "frame type=%d show=%d intra=%d err=%d %ux%u depth=%d refresh=%02x "
        "refs=%d,%d,%d filt=%d ctx=%d reset=%d q=%d lf=%d/%d seg=%d "
        "tiles=%dx%d hdr=%u+%u size=%zu prevmv=%d%s\n",
        h->frame_type, h->show_frame, h->intra_only, h->error_res, h->width,
        h->height, h->bit_depth, h->refresh_frame_flags, h->ref_frame_idx[0],
        h->ref_frame_idx[1], h->ref_frame_idx[2], h->interp_filter,
        h->frame_context_idx, h->reset_frame_context, h->base_q_idx,
        h->lf_level, h->lf_sharpness, h->seg_enabled, 1 << h->log2_tile_cols,
        1 << h->log2_tile_rows, h->uncompressed_header_size,
        h->compressed_header_size, size, h->use_prev_frame_mvs,
        ok ? "" : " TILES-BAD");
  vp9_frame_done(p, 0);
  return 0;
}

int main(int argc, char** argv) {
  if (argc < 2 || argv[1][0] == '-') {
    fprintf(stderr, "usage: vp9dump file [-v]\n");
    return 1;
  }
  Container c;
  if (!container_open(&c, argv[1])) {
    fprintf(stderr, "%s: %s\n", argv[1], c.problem);
    return 1;
  }
  Stats s = {.verbose = argc > 2 && !strcmp(argv[2], "-v")};
  VP9Parser p;
  vp9_parser_init(&p);
  const uint8_t* d;
  size_t n;
  int chunks = 0, rc = 0;
  while (container_next(&c, &d, &n)) {
    chunks++;
    if ((rc = vp9_parse_chunk(&p, d, n, on_frame, &s))) {
      printf("%s: parse error at chunk %d: %s\n", argv[1], chunks, p.err);
      break;
    }
  }
  if (c.problem) {
    printf("%s: stopped after chunk %d: %s\n", argv[1], chunks, c.problem);
    rc = 1;
  }
  printf(
      "%s: chunks=%d coded=%d shown=%d hidden=%d existing=%d key=%d "
      "intra_only=%d seg=%d lfdelta=%d prevmv=%d max=%ux%u unsupported=%d "
      "tiles_bad=%d\n",
      argv[1], chunks, s.coded, s.shown, s.hidden, s.existing, s.keys, s.intra,
      s.seg, s.delta_lf, s.prev_mvs, s.maxw, s.maxh, s.unsupported,
      s.tiles_bad);
  container_close(&c);
  return rc || s.tiles_bad ? 2 : 0;
}
