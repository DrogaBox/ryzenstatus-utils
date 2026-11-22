// parsefuzz: throws damaged and hand-built headers at the AV1 and VP9
// parsers. It is meant for the sanitizer build: the first out-of-bounds
// access, undefined shift or signed overflow stops the program. The seed and
// the variant are printed by the sanitizer death callback (and by SIGABRT),
// so the failing input can be reproduced.
//
// The streams are built here rather than read from tests/media: the parser
// tests must still work without the downloads. The shapes are the ones that
// reach furthest into av1parse.c and vp9parse.c: a reduced still-picture AV1
// sequence and key frame, a non-reduced AV1 sequence and inter frame with
// global motion, a VP9 key frame, every short prefix of those, and the size
// and count fields at 0, max and max-1.
//
// usage: parsefuzz [variants-per-parser]   (default 5000, fixed seed)
#include <signal.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "av1parse.h"
#include "vp9parse.h"

enum { kMaxBuf = 1 << 16, kDefaultVariants = 5000 };

static const uint64_t kSeed = 0x5eedf00dcafebabeull;
static uint64_t rng_state;
static const char* current_codec = "none";
static unsigned current_variant;
static unsigned av1_ok, av1_frames, vp9_ok, vp9_frames;

static uint32_t rnd(void) {  // xorshift64*
  rng_state ^= rng_state >> 12;
  rng_state ^= rng_state << 25;
  rng_state ^= rng_state >> 27;
  return (uint32_t)((rng_state * 0x2545F4914F6CDD1Dull) >> 32);
}

static void random_bytes(uint8_t* out, size_t n) {
  for (size_t i = 0; i < n; i++) out[i] = (uint8_t)rnd();
}

static void report_stop(void) {
  fprintf(stderr, "\nparsefuzz STOP seed=%016llx codec=%s variant=%u\n",
          (unsigned long long)kSeed, current_codec, current_variant);
  fflush(stderr);
}

static void on_signal(int sig) {
  report_stop();
  signal(sig, SIG_DFL);
  raise(sig);
}

// Clang's sanitizer runtime calls this before it exits, also for a UBSan
// finding built with -fno-sanitize-recover.
void __sanitizer_set_death_callback(void (*callback)(void));
static void on_sanitizer_death(void) { report_stop(); }

static void install_reporting(void) {
  __sanitizer_set_death_callback(on_sanitizer_death);
  // UBSan with -fno-sanitize-recover aborts; ASan calls the death callback.
  signal(SIGABRT, on_signal);
}

typedef struct {
  uint8_t* d;
  size_t cap;   // bytes
  size_t bits;  // bits written
} BW;

static void bw_init(BW* w, uint8_t* d, size_t cap) {
  w->d = d;
  w->cap = cap;
  w->bits = 0;
  memset(d, 0, cap);
}

static void bw_put(BW* w, uint32_t v, int n) {
  if (n < 0 || n > 32 || w->bits + (size_t)n > w->cap * 8) abort();
  for (int i = n - 1; i >= 0; i--, w->bits++)
    if ((v >> i) & 1) w->d[w->bits >> 3] |= (uint8_t)(0x80 >> (w->bits & 7));
}

static size_t bw_bytes(const BW* w) { return (w->bits + 7) >> 3; }

static size_t put_obu(uint8_t type, const uint8_t* payload, size_t n,
                      uint8_t* out) {
  size_t k = 0;
  out[k++] = (uint8_t)(type << 3 | 0x02);  // has_size_field
  size_t v = n;
  do {
    uint8_t byte = v & 0x7f;
    v >>= 7;
    out[k++] = byte | (v ? 0x80 : 0);
  } while (v);
  memcpy(out + k, payload, n);
  return k + n;
}

// A reduced still-picture sequence header, with the largest frame size and
// film grain selectable. Returns the payload size.
static size_t av1_reduced_seq(uint8_t* out, unsigned maxw, unsigned maxh,
                              bool grain) {
  BW w;
  int wb = 1, hb = 1;
  while (maxw >= (1u << wb)) wb++;
  while (maxh >= (1u << hb)) hb++;
  bw_init(&w, out, kMaxBuf);
  bw_put(&w, 0, 3);  // seq_profile
  bw_put(&w, 1, 1);  // still_picture
  bw_put(&w, 1, 1);  // reduced_still_picture_header
  bw_put(&w, 0, 5);  // seq_level_idx[0]
  bw_put(&w, (uint32_t)(wb - 1), 4);
  bw_put(&w, (uint32_t)(hb - 1), 4);
  bw_put(&w, maxw, wb);
  bw_put(&w, maxh, hb);
  bw_put(&w, 0, 1);  // use_128x128_superblock
  bw_put(&w, 0, 1);  // enable_filter_intra
  bw_put(&w, 0, 1);  // enable_intra_edge_filter
  bw_put(&w, 0, 1);  // enable_superres
  bw_put(&w, 0, 1);  // enable_cdef
  bw_put(&w, 0, 1);  // enable_restoration
  bw_put(&w, 0, 1);  // high_bitdepth
  bw_put(&w, 0, 1);  // mono_chrome
  bw_put(&w, 0, 1);  // color_description_present_flag
  bw_put(&w, 0, 1);  // color_range
  bw_put(&w, 0, 2);  // chroma_sample_position
  bw_put(&w, 0, 1);  // separate_uv_delta_q
  bw_put(&w, grain ? 1 : 0, 1);
  return bw_bytes(&w);
}

// The same, without reduced_still_picture_header, so an inter frame can
// follow. Order hints are off and the frame size is the sequence maximum.
static size_t av1_full_seq(uint8_t* out, unsigned maxw, unsigned maxh,
                           bool grain) {
  BW w;
  int wb = 1, hb = 1;
  while (maxw >= (1u << wb)) wb++;
  while (maxh >= (1u << hb)) hb++;
  bw_init(&w, out, kMaxBuf);
  bw_put(&w, 0, 3);  // seq_profile
  bw_put(&w, 0, 1);  // still_picture
  bw_put(&w, 0, 1);  // reduced_still_picture_header
  bw_put(&w, 0, 1);  // timing_info_present_flag
  bw_put(&w, 0, 1);  // initial_display_delay_present_flag
  bw_put(&w, 0, 5);  // operating_points_cnt_minus_1
  bw_put(&w, 0, 12); // operating_point_idc[0]
  bw_put(&w, 0, 5);  // seq_level_idx[0]
  bw_put(&w, (uint32_t)(wb - 1), 4);
  bw_put(&w, (uint32_t)(hb - 1), 4);
  bw_put(&w, maxw, wb);
  bw_put(&w, maxh, hb);
  bw_put(&w, 0, 1);  // frame_id_numbers_present_flag
  bw_put(&w, 0, 1);  // use_128x128_superblock
  bw_put(&w, 0, 1);  // enable_filter_intra
  bw_put(&w, 0, 1);  // enable_intra_edge_filter
  bw_put(&w, 0, 1);  // enable_interintra_compound
  bw_put(&w, 0, 1);  // enable_masked_compound
  bw_put(&w, 0, 1);  // enable_warped_motion
  bw_put(&w, 0, 1);  // enable_dual_filter
  bw_put(&w, 0, 1);  // enable_order_hint
  bw_put(&w, 0, 1);  // seq_choose_screen_content_tools
  bw_put(&w, 0, 1);  // seq_force_screen_content_tools = 0
  bw_put(&w, 0, 1);  // enable_superres
  bw_put(&w, 0, 1);  // enable_cdef
  bw_put(&w, 0, 1);  // enable_restoration
  bw_put(&w, 0, 1);  // high_bitdepth
  bw_put(&w, 0, 1);  // mono_chrome
  bw_put(&w, 0, 1);  // color_description_present_flag
  bw_put(&w, 0, 1);  // color_range
  bw_put(&w, 0, 2);  // chroma_sample_position
  bw_put(&w, 0, 1);  // separate_uv_delta_q
  bw_put(&w, grain ? 1 : 0, 1);
  return bw_bytes(&w);
}

// A reduced still-picture key frame. nt, ncb, ncr are the film-grain point
// counts; the frame is otherwise minimal and 64x64.
static size_t av1_key_frame(uint8_t* out, int nt, int ncb, int ncr, int lag) {
  BW w;
  bw_init(&w, out, kMaxBuf);
  bw_put(&w, 0, 1);  // disable_cdf_update
  bw_put(&w, 0, 1);  // allow_screen_content_tools
  bw_put(&w, 0, 1);  // render_size
  bw_put(&w, 1, 1);  // uniform_tile_spacing_flag (64x64 -> one tile)
  bw_put(&w, 0, 8);  // base_q_idx
  bw_put(&w, 0, 1);  // DeltaQYDc absent
  bw_put(&w, 0, 1);  // DeltaQUDc absent
  bw_put(&w, 0, 1);  // DeltaQUAc absent
  bw_put(&w, 0, 1);  // using_qmatrix
  bw_put(&w, 0, 1);  // segmentation_enabled
  bw_put(&w, 0, 1);  // reduced_tx_set
  // film grain
  bw_put(&w, 1, 1);   // apply_grain
  bw_put(&w, 0x1234, 16);
  bw_put(&w, (uint32_t)nt, 4);
  for (int i = 0; i < nt; i++) {
    bw_put(&w, (uint32_t)i, 8);
    bw_put(&w, (uint32_t)(32 + i), 8);
  }
  bw_put(&w, 0, 1);  // chroma_scaling_from_luma
  // The parser takes the chroma counts only when luma has points.
  if (nt > 0) {
    bw_put(&w, (uint32_t)ncb, 4);
    for (int i = 0; i < ncb; i++) {
      bw_put(&w, (uint32_t)i, 8);
      bw_put(&w, (uint32_t)(32 + i), 8);
    }
    bw_put(&w, (uint32_t)ncr, 4);
    for (int i = 0; i < ncr; i++) {
      bw_put(&w, (uint32_t)i, 8);
      bw_put(&w, (uint32_t)(32 + i), 8);
    }
  }
  bw_put(&w, 0, 2);                 // grain_scaling_minus_8
  bw_put(&w, (uint32_t)lag, 2);     // ar_coeff_lag
  int posLuma = 2 * lag * (lag + 1);
  for (int i = 0; i < posLuma; i++) bw_put(&w, (uint32_t)i, 8);
  int posChroma = posLuma + (nt ? 1 : 0);
  if (ncb) for (int i = 0; i < posChroma; i++) bw_put(&w, (uint32_t)i, 8);
  if (ncr) for (int i = 0; i < posChroma; i++) bw_put(&w, (uint32_t)i, 8);
  bw_put(&w, 0, 2);  // ar_coeff_shift_minus_6
  bw_put(&w, 0, 2);  // grain_scale_shift
  if (ncb) {
    bw_put(&w, 0, 8);
    bw_put(&w, 0, 8);
    bw_put(&w, 0, 9);
  }
  if (ncr) {
    bw_put(&w, 0, 8);
    bw_put(&w, 0, 8);
    bw_put(&w, 0, 9);
  }
  bw_put(&w, 0, 1);  // overlap_flag
  bw_put(&w, 0, 1);  // clip_to_restricted_range
  return bw_bytes(&w);
}

// A minimal non-reduced inter frame. It sets global motion for the first
// reference and then feeds `ones` continuation bits, which walks
// decode_subexp() as far as the header allows.
static size_t av1_inter_frame(uint8_t* out, int ones) {
  BW w;
  bw_init(&w, out, kMaxBuf);
  bw_put(&w, 0, 1);  // show_existing_frame
  bw_put(&w, 1, 2);  // frame_type = INTER
  bw_put(&w, 1, 1);  // show_frame
  bw_put(&w, 1, 1);  // error_resilient_mode
  bw_put(&w, 1, 1);  // disable_cdf_update
  bw_put(&w, 0, 1);  // frame_size_override_flag
  bw_put(&w, 0, 8);  // refresh_frame_flags
  bw_put(&w, 0, 1);  // render_size
  bw_put(&w, 0, 1);  // allow_high_precision_mv
  bw_put(&w, 0, 1);  // is_filter_switchable
  bw_put(&w, 0, 2);  // interpolation_filter
  bw_put(&w, 0, 1);  // is_motion_mode_switchable
  for (int i = 0; i < 7; i++) bw_put(&w, 0, 3);
  bw_put(&w, 1, 1);  // uniform_tile_spacing_flag
  bw_put(&w, 0, 8);  // base_q_idx (CodedLossless)
  bw_put(&w, 0, 1);  // DeltaQYDc absent
  bw_put(&w, 0, 1);  // DeltaQUDc absent
  bw_put(&w, 0, 1);  // DeltaQUAc absent
  bw_put(&w, 0, 1);  // using_qmatrix
  bw_put(&w, 0, 1);  // segmentation_enabled
  bw_put(&w, 0, 1);  // reference_select
  bw_put(&w, 0, 1);  // reduced_tx_set
  bw_put(&w, 1, 1);  // use_global_motion for ref 1
  bw_put(&w, 1, 1);  // type: not translation
  bw_put(&w, 1, 1);  // type: ROTZOOM
  for (int i = 0; i < ones; i++) bw_put(&w, 1, 1);
  return bw_bytes(&w);
}

static int on_av1(void* ctx, AV1Parser* p, AV1ParseResult kind) {
  (void)ctx;
  av1_frames++;
  if (kind == AV1_PARSE_FRAME_READY) av1_reference_update(p, 0);
  return 0;
}

static void run_av1(const uint8_t* data, size_t size, bool config) {
  AV1Parser* p = calloc(1, sizeof(*p));
  if (!p) abort();
  av1_parser_init(p);
  int r = config ? av1_parse_config_obus(p, data, size)
                 : av1_parse_temporal_unit(p, data, size, on_av1, NULL);
  if (!r) av1_ok++;
  av1_parser_free(p);
  free(p);
}

static int on_vp9(void* ctx, VP9Parser* p, VP9ParseResult kind,
                  const uint8_t* data, size_t size) {
  (void)ctx;
  (void)data;
  (void)size;
  vp9_frames++;
  if (kind == VP9_PARSE_DECODE) vp9_frame_done(p, 0);
  return 0;
}

static void run_vp9(const uint8_t* data, size_t size, bool chunk) {
  VP9Parser* p = calloc(1, sizeof(*p));
  if (!p) abort();
  vp9_parser_init(p);
  int r = chunk ? vp9_parse_chunk(p, data, size, on_vp9, NULL)
                : vp9_parse_frame_header(p, data, size);
  if (!r) vp9_ok++;
  free(p);
}

static size_t vp9_key_header(uint8_t* out, unsigned width, unsigned height,
                             unsigned tile_bits, unsigned compressed) {
  BW w;
  bw_init(&w, out, kMaxBuf);
  bw_put(&w, 2, 2);  // frame_marker
  bw_put(&w, 0, 2);  // profile 0
  bw_put(&w, 0, 1);  // show_existing_frame
  bw_put(&w, 0, 1);  // frame_type = key
  bw_put(&w, 1, 1);  // show_frame
  bw_put(&w, 0, 1);  // error_res
  bw_put(&w, 0x498342, 24);
  bw_put(&w, 0, 3);  // color_space
  bw_put(&w, 0, 1);  // color_range
  bw_put(&w, width - 1, 16);
  bw_put(&w, height - 1, 16);
  bw_put(&w, 0, 1);  // render_size
  bw_put(&w, 1, 1);  // refresh_frame_context
  bw_put(&w, 1, 1);  // frame_parallel_decoding_mode
  bw_put(&w, 0, 2);  // frame_context_idx
  bw_put(&w, 0, 6);  // loop_filter_level
  bw_put(&w, 0, 3);  // sharpness
  bw_put(&w, 0, 1);  // loop_filter_delta_enabled
  bw_put(&w, 0, 8);  // base_q_idx
  bw_put(&w, 0, 1);  // y_dc_delta_q present
  bw_put(&w, 0, 1);  // uv_dc_delta_q present
  bw_put(&w, 0, 1);  // uv_ac_delta_q present
  bw_put(&w, 0, 1);  // segmentation_enabled
  // The width chooses the minimum tile-columns log2. For 64 that is 0 and
  // no increment bit is read; for 65536 it is 4 and two ones reach 6.
  if (width > 64) {
    for (unsigned i = 64; i < width; i <<= 1) bw_put(&w, 1, 1);
    bw_put(&w, 0, 1);
  }
  for (unsigned i = 0; i < tile_bits; i++) bw_put(&w, 1, 1);
  bw_put(&w, 0, 1);  // log2_tile_rows = 0
  bw_put(&w, compressed, 16);
  return bw_bytes(&w);
}

static size_t vp9_key_tu(uint8_t* out, unsigned width, unsigned height,
                         unsigned tile_bits, unsigned compressed) {
  uint8_t hdr[kMaxBuf];
  size_t n = vp9_key_header(hdr, width, height, tile_bits, compressed);
  memcpy(out, hdr, n);
  // One byte of compressed header and one byte of tile data.
  out[n] = 0;
  out[n + 1] = 0;
  return n + 2;
}

static size_t vp9_superframe(uint8_t* out, int frames, int zero_size,
                             unsigned width, unsigned height) {
  uint8_t frame[kMaxBuf];
  size_t fn = vp9_key_tu(frame, width, height, 0, 1);
  size_t total = 0;
  for (int i = 0; i < frames; i++) {
    memcpy(out + total, frame, fn);
    total += fn;
  }
  int mag = 2;
  size_t index = 2 + (size_t)mag * (size_t)frames;
  uint8_t marker = (uint8_t)(0xc0 | (frames - 1) | ((mag - 1) << 3));
  // First marker, then one little-endian size per frame, then the same
  // marker again. A zero size is accepted today (report 54, finding 4).
  out[total] = marker;
  for (int i = 0; i < frames; i++) {
    size_t s = zero_size && i == 0 ? 0 : fn;
    out[total + 1 + (size_t)i * mag] = (uint8_t)(s & 0xff);
    out[total + 1 + (size_t)i * mag + 1] = (uint8_t)((s >> 8) & 0xff);
  }
  out[total + index - 1] = marker;
  return total + index;
}

static void fuzz_av1(unsigned variants) {
  uint8_t buf[kMaxBuf], seq[kMaxBuf], frame[kMaxBuf], tu[kMaxBuf];
  current_codec = "av1";
  for (unsigned i = 0; i < variants; i++) {
    current_variant = i;
    size_t n = 0;
    switch (i % 8) {
      case 0: {  // pure random
        n = rnd() % 512;
        random_bytes(buf, n);
        run_av1(buf, n, false);
        break;
      }
      case 1: {  // random payload behind an OBU header
        size_t pn = rnd() % 512;
        random_bytes(tu, pn);
        uint8_t type = (uint8_t)(1 + rnd() % 8);
        n = put_obu(type, tu, pn, buf);
        run_av1(buf, n, false);
        break;
      }
      case 2: {  // valid sequence, random frame/header OBU
        static const unsigned widths[] = {0, 63, 65534, 65535};
        unsigned maxw = widths[(i / 8) % 4];
        size_t sn = av1_reduced_seq(seq, maxw, maxw, false);
        size_t so = put_obu(1, seq, sn, tu);
        size_t pn = rnd() % 600;
        random_bytes(frame, pn);
        n = put_obu(6, frame, pn, tu + so);
        run_av1(tu, so + n, false);
        break;
      }
      case 3: {  // reduced sequence + key frame with selected grain counts
        static const int counts[] = {0, 1, 10, 14, 15};
        int nt = counts[i % 5], ncb = counts[(i / 5) % 5],
            ncr = counts[(i / 25) % 5];
        size_t sn = av1_reduced_seq(seq, 63, 63, true);
        size_t so = put_obu(1, seq, sn, tu);
        size_t fn = av1_key_frame(frame, nt, ncb, ncr, (int)(i % 4));
        n = put_obu(6, frame, fn, tu + so);
        run_av1(tu, so + n, false);
        break;
      }
      case 4: {  // every short prefix of a valid sequence + key frame
        size_t sn = av1_reduced_seq(seq, 63, 63, true);
        size_t so = put_obu(1, seq, sn, tu);
        size_t fn = av1_key_frame(frame, 14, 10, 10, 3);
        n = put_obu(6, frame, fn, tu + so);
        size_t cut = (i / 8) % (so + n);
        run_av1(tu, cut, false);
        break;
      }
      case 5: {  // non-reduced sequence + inter frame with global motion
        size_t sn = av1_full_seq(seq, 63, 63, false);
        size_t so = put_obu(1, seq, sn, tu);
        size_t fn = av1_inter_frame(frame, (int)(i % 64));
        n = put_obu(6, frame, fn, tu + so);
        run_av1(tu, so + n, false);
        break;
      }
      case 6: {  // config OBUs: sequence payload, random and cut
        size_t sn = av1_reduced_seq(seq, (i / 8) % 2 ? 65535 : 0, 63,
                                    (i / 16) % 2);
        size_t cut = (i / 32) % (sn + 1);
        run_av1(seq, cut, true);
        break;
      }
      default: {  // random input through the config-OBU entry point
        n = rnd() % 512;
        random_bytes(buf, n);
        run_av1(buf, n, true);
        break;
      }
    }
  }
}

static void fuzz_vp9(unsigned variants) {
  uint8_t buf[kMaxBuf], frame[kMaxBuf], chunk[kMaxBuf];
  current_codec = "vp9";
  for (unsigned i = 0; i < variants; i++) {
    current_variant = i;
    size_t n = 0;
    switch (i % 7) {
      case 0: {  // pure random
        n = rnd() % 512;
        random_bytes(buf, n);
        run_vp9(buf, n, false);
        break;
      }
      case 1: {  // key frame, width at 1, 64, 65534, 65535 or 65536
        static const unsigned widths[] = {64, 1, 65534, 65535, 65536};
        unsigned w = widths[(i / 7) % 5];
        n = vp9_key_tu(buf, w, 64, 0, 1);
        run_vp9(buf, n, false);
        break;
      }
      case 2: {  // every short prefix of a key frame
        n = vp9_key_tu(frame, 64, 64, 0, 1);
        size_t cut = (i / 7) % n;
        run_vp9(frame, cut, false);
        break;
      }
      case 3: {  // compressed header size at 0, max and max-1
        static const unsigned sizes[] = {0, 65535, 65534, 1, 2};
        n = vp9_key_tu(buf, 64, 64, 0, sizes[i % 5]);
        run_vp9(buf, n, false);
        break;
      }
      case 4: {  // a superframe index, including an empty first frame
        n = vp9_superframe(chunk, 1 + (int)(i % 8), (i / 7) % 2, 64, 64);
        run_vp9(chunk, n, true);
        break;
      }
      case 5: {  // random bytes through the chunk splitter
        n = rnd() % 512;
        random_bytes(buf, n);
        run_vp9(buf, n, true);
        break;
      }
      default: {  // bit-damaged key frame
        n = vp9_key_tu(buf, 64, 64, 0, 1);
        for (unsigned k = 0; k < 1 + i % 8; k++)
          buf[rnd() % n] ^= (uint8_t)(1u << (rnd() % 8));
        run_vp9(buf, n, false);
        break;
      }
    }
  }
}

int main(int argc, char** argv) {
  unsigned variants = kDefaultVariants;
  if (argc > 2) {
    fprintf(stderr, "usage: parsefuzz [variants-per-parser]\n");
    return 2;
  }
  if (argc == 2) variants = (unsigned)strtoul(argv[1], NULL, 10);
  if (!variants) return 2;
  install_reporting();
  rng_state = kSeed;
  fprintf(stderr, "parsefuzz: seed=%016llx, %u variants per parser\n",
          (unsigned long long)kSeed, variants);
  fuzz_av1(variants);
  fuzz_vp9(variants);
  printf("parsefuzz: seed=%016llx, %u AV1 and %u VP9 variants, no sanitizer "
         "finding (%u/%u AV1 parsed, %u/%u VP9 parsed, %u AV1 frames, %u VP9 "
         "frames)\n",
         (unsigned long long)kSeed, variants, variants, av1_ok, variants, vp9_ok,
         variants, av1_frames, vp9_frames);
  return 0;
}
