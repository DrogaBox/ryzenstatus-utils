// legacyparse: the MPEG-2, VC-1 and MPEG-4 parsers and the messages built from
// them, on the CPU. Nothing here loads the driver or opens the GPU.
//
//   legacyparse                      the checks below; exit status 0 = pass
//   legacyparse <codec> <stream>     prints the pictures of a stream, one a
//   line
//
// The checks:
//   1. MPEG-2: a made-up stream (sequence header with its own intra matrix,
//      sequence extension, I and P pictures, a quant matrix extension) comes
//      out as the right pictures; MPEG-1 and 4:2:2 are refused; the codec
//      block and the decode message are, byte for byte, what Mesa sent to the
//      same card on Linux for an intra picture (capture of 2026-11-23);
//   2. VC-1: advanced profile headers and frames with and without start
//      codes, a field-interlaced frame, a simple/main header; the codec block
//      equals the Linux capture;
//   3. MPEG-4: a VOL with a quantiser matrix that stops early, I/P/B VOPs and
//      their time distances, a VOP that is not coded; what the block cannot
//      say is refused;
//   4. every prefix of every made-up stream, and thousands of copies damaged
//      at random, parse without reading outside the buffer (the build has the
//      address sanitizer), and the codec blocks are still filled from what the
//      parser accepted.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vcnlegacy.h"
#include "vcnmpeg2.h"
#include "vcnmpeg4.h"
#include "vcnvc1.h"

static int failures;
static void expect(const char* what, int ok) {
  printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) failures++;
}

// ---- a bit writer for the made-up streams
typedef struct {
  uint8_t d[4096];
  size_t bits;
} W;
static void put(W* w, uint32_t v, unsigned n) {
  for (unsigned i = n; i-- > 0;) {
    if (w->bits / 8 >= sizeof(w->d)) abort();
    if ((v >> i) & 1) w->d[w->bits / 8] |= (uint8_t)(0x80 >> (w->bits % 8));
    w->bits++;
  }
}
static void align(W* w) { w->bits = (w->bits + 7) & ~(size_t)7; }
static void start(W* w, uint8_t code) {
  align(w);
  put(w, 0x000001, 24);
  put(w, code, 8);
}
static size_t bytes(W* w) {
  align(w);
  return w->bits / 8;
}

// ---- damaged copies
static uint32_t rngState = 0x2545F491;
static uint32_t rnd(void) {
  rngState ^= rngState << 13;
  rngState ^= rngState >> 17;
  rngState ^= rngState << 5;
  return rngState;
}
typedef void (*ParseFn)(const uint8_t* d, size_t n);
// Each copy has up to eight bytes replaced and is sometimes cut short; it is
// parsed from a heap block of exactly its size, so a read past the end stops
// the program.
static void damaged(const uint8_t* d, size_t n, ParseFn parse, int rounds) {
  for (int r = 0; r < rounds; r++) {
    size_t len = rnd() % 4 ? n : rnd() % (n + 1);
    uint8_t* copy = malloc(len ? len : 1);
    memcpy(copy, d, len);
    for (uint32_t hits = len ? 1 + rnd() % 8 : 0; hits; hits--)
      copy[rnd() % len] = (uint8_t)rnd();
    parse(copy, len);
    free(copy);
  }
}
enum { kDamagedRounds = 5000 };

// ---- MPEG-2
typedef struct {
  int n;
  Mpeg2Picture pic[8];
  uint8_t firstSlice[8];
} M2;
static int m2_cb(void* ctx, Mpeg2Parser* p, const Mpeg2Picture* pic) {
  (void)p;
  M2* m = ctx;
  if (m->n < 8) {
    m->pic[m->n] = *pic;
    m->firstSlice[m->n] = pic->slicesSize > 3 ? pic->slices[3] : 0;
  }
  m->n++;
  return 0;
}

static int m2_fill_cb(void* ctx, Mpeg2Parser* p, const Mpeg2Picture* pic) {
  VcnMpeg2Msg b;
  vcnmpeg2_fill_block(&b, p, pic, ++*(uint32_t*)ctx, 1, 2);
  return 0;
}
static void m2_parse(const uint8_t* d, size_t n) {
  Mpeg2Parser p;
  uint32_t count = 0;
  mpeg2_parser_init(&p);
  mpeg2_parse_chunk(&p, d, n, m2_fill_cb, &count);
}

static void m2_sequence(W* w, int matrix, int mpeg1, int chroma) {
  start(w, 0xB3);
  put(w, 720, 12);
  put(w, 576, 12);
  put(w, 2, 4);
  put(w, 3, 4);
  put(w, 10000, 18);
  put(w, 1, 1);
  put(w, 112, 10);
  put(w, 0, 1);
  put(w, matrix, 1);
  if (matrix)
    for (int i = 0; i < 64; i++) put(w, (uint32_t)(i + 1), 8);
  put(w, 0, 1);
  if (mpeg1) return;
  start(w, 0xB5);
  put(w, 1, 4);
  put(w, 0x48, 8);
  put(w, 1, 1);  // progressive_sequence
  put(w, (uint32_t)chroma, 2);
  put(w, 0, 2);
  put(w, 0, 2);
  put(w, 0, 12);
  put(w, 1, 1);
  put(w, 0, 8);
  put(w, 0, 1);
  put(w, 0, 2);
  put(w, 0, 5);
}
static void m2_picture(W* w, int type, int structure, int alternate,
                       int slices) {
  start(w, 0x00);
  put(w, 5, 10);
  put(w, (uint32_t)type, 3);
  put(w, 0xffff, 16);
  if (type != 1) put(w, 7, 4);
  if (type == 3) put(w, 7, 4);
  put(w, 0, 1);
  start(w, 0xB5);
  put(w, 8, 4);
  put(w, type == 1 ? 15 : 3, 4);
  put(w, type == 1 ? 15 : 2, 4);
  put(w, type == 3 ? 4 : 15, 4);
  put(w, type == 3 ? 5 : 15, 4);
  put(w, 2, 2);  // intra_dc_precision
  put(w, (uint32_t)structure, 2);
  put(w, 1, 1);  // top_field_first
  put(w, 0, 1);  // frame_pred_frame_dct
  put(w, 0, 1);
  put(w, 1, 1);  // q_scale_type
  put(w, 1, 1);  // intra_vlc_format
  put(w, (uint32_t)alternate, 1);
  put(w, 0, 1);
  put(w, 1, 1);
  put(w, 0, 1);  // progressive_frame
  put(w, 0, 1);
  for (int s = 1; s <= slices; s++) {
    start(w, (uint8_t)s);
    put(w, 0x5a5a5a, 24);
  }
}

// What Mesa 26.3 sent on Linux for the first picture of a 720x576 clip with
// the default matrices (decode message bytes 0xf4..0x193).
static const uint8_t kLinuxMpeg2Block[160] = {
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  1,  1,  0,  0,  8,  16,
    16, 19, 16, 19, 22, 22, 22, 22, 26, 24, 26, 22, 22, 26, 26, 26, 27, 27,
    27, 29, 29, 29, 27, 27, 27, 26, 27, 27, 29, 29, 29, 34, 34, 34, 37, 34,
    34, 32, 32, 29, 29, 35, 34, 35, 35, 37, 38, 40, 40, 40, 38, 38, 46, 46,
    48, 48, 58, 56, 56, 69, 69, 83, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16,
    16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16,
    16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16,
    16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16,
    0,  1,  1,  0,  15, 15, 15, 15, 0,  3,  0,  1,  0,  0,  0,  0};

static void test_mpeg2(void) {
  W w = {0};
  m2_sequence(&w, 1, 0, 1);
  start(&w, 0xB8);  // group of pictures
  put(&w, 0, 27);
  m2_picture(&w, 1, 3, 0, 3);
  m2_picture(&w, 2, 3, 1, 2);
  start(&w, 0xB5);  // quant matrix extension: a new non-intra matrix
  put(&w, 3, 4);
  put(&w, 0, 1);
  put(&w, 1, 1);
  for (int i = 0; i < 64; i++) put(&w, (uint32_t)(64 - i), 8);
  put(&w, 0, 2);
  m2_picture(&w, 3, 1, 0, 1);
  start(&w, 0xB7);
  size_t n = bytes(&w);
  Mpeg2Parser p;
  M2 m = {0};
  mpeg2_parser_init(&p);
  int r = mpeg2_parse_chunk(&p, w.d, n, m2_cb, &m);
  expect("mpeg2: three pictures", r == 0 && m.n == 3);
  expect("mpeg2: sequence size and matrix",
         p.width == 720 && p.height == 576 && p.intra_matrix[0] == 1 &&
             p.intra_matrix[63] == 64 && p.have_extension);
  expect("mpeg2: I picture fields",
         m.pic[0].coding_type == MPEG2_I && m.pic[0].f_code[0][0] == 15 &&
             m.pic[0].intra_dc_precision == 2 &&
             m.pic[0].picture_structure == MPEG2_FRAME &&
             m.pic[0].top_field_first == 1 &&
             m.pic[0].frame_pred_frame_dct == 0 && m.pic[0].q_scale_type == 1 &&
             m.pic[0].intra_vlc_format == 1 && m.pic[0].alternate_scan == 0 &&
             m.pic[0].temporal_reference == 5);
  expect("mpeg2: slices run from the first slice to the next header",
         m.firstSlice[0] == 1 && m.pic[0].slicesSize == 3 * 7 &&
             m.pic[1].slicesSize == 2 * 7 && m.pic[2].slicesSize == 7);
  expect("mpeg2: P and B pictures",
         m.pic[1].coding_type == MPEG2_P && m.pic[1].f_code[0][0] == 3 &&
             m.pic[1].f_code[0][1] == 2 && m.pic[1].alternate_scan == 1 &&
             m.pic[2].coding_type == MPEG2_B && m.pic[2].f_code[1][1] == 5 &&
             m.pic[2].picture_structure == MPEG2_TOP_FIELD);
  expect("mpeg2: the quant matrix extension replaced the non-intra matrix",
         p.nonintra_matrix[0] == 64 && p.nonintra_matrix[63] == 1 &&
             p.intra_matrix[0] == 1);

  // The codec block: picture numbers as Mesa up to 25.x.
  VcnMpeg2Msg b;
  vcnmpeg2_index_mode = 0;
  vcnmpeg2_matrix_mode = 0;
  vcnmpeg2_fill_block(&b, &p, &m.pic[0], 1, 0, 0);
  expect("mpeg2: first picture is number 1 and refers to 0",
         b.decoded_pic_idx == 1 && b.forward_ref_pic_idx == 0 &&
             b.backward_ref_pic_idx == 0);
  vcnmpeg2_fill_block(&b, &p, &m.pic[2], 9, 2, 8);
  expect("mpeg2: a reference index stays within the last six pictures",
         b.decoded_pic_idx == 9 && b.forward_ref_pic_idx == 3 &&
             b.backward_ref_pic_idx == 8);
  expect("mpeg2: zigzag pictures get the matrix in the order sent",
         b.intra_quantiser_matrix[0] == 1 && b.intra_quantiser_matrix[5] == 6 &&
             b.intra_quantiser_matrix[63] == 64);
  vcnmpeg2_fill_block(&b, &p, &m.pic[1], 2, 1, 0);
  expect("mpeg2: alternate scan pictures get the matrix as the stream sent it",
         b.alternate_scan == 1 && b.intra_quantiser_matrix[0] == 1 &&
             b.intra_quantiser_matrix[1] == 2 &&
             b.intra_quantiser_matrix[63] == 64);
  vcnmpeg2_matrix_mode = 2;
  vcnmpeg2_fill_block(&b, &p, &m.pic[1], 2, 1, 0);
  // Alternate scan: coefficient 1 is block position 8, which the zigzag
  // order sends third.
  expect("mpeg2: mode 2 gives alternate scan pictures alternate scan order",
         b.alternate_scan == 1 && b.intra_quantiser_matrix[0] == 1 &&
             b.intra_quantiser_matrix[1] == 3 &&
             b.intra_quantiser_matrix[4] == 2);
  vcnmpeg2_matrix_mode = 0;

  // Against the Linux capture: default matrices, Mesa's VA-API matrix order,
  // indices zero.
  W v = {0};
  m2_sequence(&v, 0, 0, 1);
  start(&v, 0x00);
  put(&v, 0, 10);
  put(&v, 1, 3);
  put(&v, 0xffff, 16);
  put(&v, 0, 1);
  start(&v, 0xB5);
  put(&v, 8, 4);
  put(&v, 0xffff, 16);
  put(&v, 0, 2);
  put(&v, 3, 2);
  put(&v, 0, 1);
  put(&v, 1, 1);  // frame_pred_frame_dct
  put(&v, 0, 8);
  start(&v, 0x01);
  put(&v, 0x123456, 24);
  M2 one = {0};
  mpeg2_parser_init(&p);
  r = mpeg2_parse_chunk(&p, v.d, bytes(&v), m2_cb, &one);
  vcnmpeg2_index_mode = 1;
  vcnmpeg2_matrix_mode = 1;
  if (!r && one.n == 1) vcnmpeg2_fill_block(&b, &p, &one.pic[0], 1, 0, 0);
  expect("mpeg2: codec block equals the one Mesa sent on Linux",
         r == 0 && one.n == 1 && !memcmp(&b, kLinuxMpeg2Block, sizeof(b)));
  vcnmpeg2_index_mode = 0;
  vcnmpeg2_matrix_mode = 0;

  // The decode message around it: header and index as Linux (404 bytes, two
  // entries, decode block at 56, codec block at 244), no hardware context,
  // 128 KiB software context.
  uint8_t msg[1024];
  VcnLegacyMessage lm = {.codecId = VCN_CODEC_MPEG2_VLD,
                         .messageId = VCN_MESSAGE_MPEG2_VLD,
                         .width = 720,
                         .height = 576,
                         .pitch = 768,
                         .texHeight = 576,
                         .bytesPerElement = 1,
                         .dpbSize = 0x3a4000,
                         .bitstreamSize = 0x6580,
                         .streamHandle = 0x9896cca1,
                         .feedbackNumber = 0,
                         .block = kLinuxMpeg2Block,
                         .blockSize = 160};
  static const uint8_t kLinuxHead[64] = {
      0x28, 0,    0,    0,    0x94, 1, 0, 0, 2,    0, 0, 0, 1,    0, 0, 0,
      0xa1, 0xcc, 0x96, 0x98, 0,    0, 0, 0, 2,    0, 0, 0, 0x38, 0, 0, 0,
      0xbc, 0,    0,    0,    0,    0, 0, 0, 0x0a, 0, 0, 0, 0xf4, 0, 0, 0,
      0xa0, 0,    0,    0,    0,    0, 0, 0, 3,    0, 0, 0, 0,    0, 0, 0};
  uint32_t total = vcnlegacy_build_message(msg, sizeof(msg), &lm);
  const uint8_t* d = msg + 56;
#define D32(off) (*(const uint32_t*)(d + (off)))
  expect("message: header, index and stream type equal the Linux capture",
         total == 404 && !memcmp(msg, kLinuxHead, sizeof(kLinuxHead)));
  expect("message: sizes, no hardware context, 128 KiB software context",
         D32(8) == 720 && D32(12) == 576 && D32(16) == 0x6580 &&
             D32(20) == 0x3a4000 && D32(36) == 0 && D32(40) == 0x20000 &&
             D32(160) == 1);
  expect("message: the codec block follows the decode block",
         !memcmp(msg + 244, kLinuxMpeg2Block, 160));
  lm.blockSize = 0;
  expect("message: an empty block is refused",
         vcnlegacy_build_message(msg, sizeof(msg), &lm) == 0);
  lm.blockSize = 160;
  expect("message: a message that does not fit is refused",
         vcnlegacy_build_message(msg, 403, &lm) == 0);
#undef D32
  expect("dpb: six pictures and room for the firmware's side buffers",
         vcnlegacy_dpb_size(VCN_CODEC_MPEG2_VLD, 720, 576) >= 0x3a4000 &&
             vcnlegacy_dpb_size(VCN_CODEC_VC1, 1440, 576) >
                 1472u * 576 * 3 / 2 * 5 + 442080 &&
             vcnlegacy_dpb_size(VCN_CODEC_MPEG4, 640, 480) >= 30u << 20);

  // Refusals.
  W m1 = {0};
  m2_sequence(&m1, 0, 1, 1);
  start(&m1, 0x00);
  put(&m1, 0, 10);
  put(&m1, 1, 3);
  put(&m1, 0xffff, 16);
  put(&m1, 0, 3);
  start(&m1, 0x01);
  put(&m1, 0x123456, 24);
  mpeg2_parser_init(&p);
  expect(
      "mpeg2: MPEG-1 is refused",
      mpeg2_parse_chunk(&p, m1.d, bytes(&m1), m2_cb, &one) == -1 && p.err[0]);
  W c422 = {0};
  m2_sequence(&c422, 0, 0, 2);
  m2_picture(&c422, 1, 3, 0, 1);
  mpeg2_parser_init(&p);
  expect("mpeg2: 4:2:2 is refused",
         mpeg2_parse_chunk(&p, c422.d, bytes(&c422), m2_cb, &one) == -1);
  W nohdr = {0};
  m2_picture(&nohdr, 2, 3, 0, 1);
  mpeg2_parser_init(&p);
  expect("mpeg2: a picture before any sequence header says so",
         mpeg2_parse_chunk(&p, nohdr.d, bytes(&nohdr), m2_cb, &one) == -1 &&
             p.missing_sequence);
  // 4. Every prefix.
  for (size_t cut = 0; cut <= n; cut++) {
    uint8_t* copy = malloc(cut ? cut : 1);
    memcpy(copy, w.d, cut);
    mpeg2_parser_init(&p);
    mpeg2_parse_chunk(&p, copy, cut, m2_cb, &one);
    free(copy);
  }
  damaged(w.d, n, m2_parse, kDamagedRounds);
  expect("mpeg2: every prefix and 5000 damaged copies parse in bounds", 1);
}

// ---- VC-1
typedef struct {
  int n;
  Vc1Picture pic[8];
} V1;
static int v1_cb(void* ctx, Vc1Parser* p, const Vc1Picture* pic) {
  (void)p;
  V1* v = ctx;
  if (v->n < 8) v->pic[v->n] = *pic;
  v->n++;
  return 0;
}

static int v1_fill_cb(void* ctx, Vc1Parser* p, const Vc1Picture* pic) {
  (void)ctx, (void)pic;
  VcnVc1Msg b;
  vcnvc1_fill_block(&b, p);
  return 0;
}
static void v1_parse(const uint8_t* d, size_t n) {
  Vc1Parser p;
  vc1_parser_init(&p);
  vc1_parse_chunk(&p, d, n, v1_fill_cb, NULL);
  // The same bytes as a simple/main header and frame.
  if (!vc1_parse_struct_c(&p, d, n, 640, 480))
    vc1_parse_frame(&p, d, n, v1_fill_cb, NULL);
}

static void v1_headers(W* w, int interlace) {
  start(w, 0x0F);
  put(w, 3, 2);  // advanced
  put(w, 3, 3);  // level
  put(w, 1, 2);  // 4:2:0
  put(w, 0, 3);
  put(w, 0, 5);
  put(w, 0, 1);     // postprocflag
  put(w, 719, 12);  // (1440 / 2) - 1
  put(w, 287, 12);
  put(w, 1, 1);  // pulldown
  put(w, (uint32_t)interlace, 1);
  put(w, 0, 1);
  put(w, 0, 1);
  put(w, 1, 1);
  put(w, 0, 1);  // psf
  put(w, 0, 1);  // display_ext
  put(w, 1, 1);  // hrd_param_flag
  put(w, 2, 5);  // two leaky buckets
  put(w, 0, 8);
  put(w, 0, 32);
  put(w, 0, 32);
  put(w, 1, 1);
  start(w, 0x0E);
  put(w, 0, 2);
  put(w, 0, 1);     // panscan
  put(w, 0, 1);     // refdist
  put(w, 1, 1);     // loopfilter
  put(w, 0, 1);     // fastuvmc
  put(w, 0, 1);     // extended_mv
  put(w, 1, 2);     // dquant
  put(w, 0, 1);     // vstransform
  put(w, 0, 1);     // overlap
  put(w, 0, 2);     // quantizer
  put(w, 0xAA, 8);  // hrd fullness, bucket 1
  put(w, 0x55, 8);  // bucket 2
  put(w, 1, 1);     // coded_size_flag
  put(w, 319, 12);  // 640
  put(w, 239, 12);  // 480
  put(w, 0, 1);     // range_mapy_flag
  put(w, 1, 1);     // range_mapuv_flag
  put(w, 5, 3);
  put(w, 1, 1);
}

static void test_vc1(void) {
  W w = {0};
  v1_headers(&w, 0);
  static const uint8_t types[5] = {0xC0, 0x00, 0x80, 0xE0,
                                   0xF0};  // I P B BI skip
  for (int i = 0; i < 5; i++) {
    start(&w, 0x0D);
    put(&w, types[i], 8);
    put(&w, 0x424242, 24);
    if (i == 0) {  // a slice inside the I frame
      start(&w, 0x0B);
      put(&w, 0x777777, 24);
    }
  }
  start(&w, 0x0A);
  size_t n = bytes(&w);
  Vc1Parser p;
  V1 v = {0};
  vc1_parser_init(&p);
  int r = vc1_parse_chunk(&p, w.d, n, v1_cb, &v);
  expect("vc1: five frames", r == 0 && v.n == 5);
  expect("vc1: sequence header and entry point",
         p.profile == VC1_PROFILE_ADVANCED && p.level == 3 &&
             p.max_width == 1440 && p.max_height == 576 && p.pulldown == 1 &&
             p.interlace == 0 && p.hrd_buckets == 2 && p.loopfilter == 1 &&
             p.dquant == 1 && p.width == 640 && p.height == 480 &&
             p.range_mapy_flag == 0 && p.range_mapuv_flag == 1 &&
             p.range_mapuv == 5);
  expect("vc1: frame types", v.pic[0].type == VC1_I && v.pic[1].type == VC1_P &&
                                 v.pic[2].type == VC1_B &&
                                 v.pic[3].type == VC1_BI &&
                                 v.pic[4].type == VC1_SKIPPED);
  expect("vc1: a frame keeps its slices and ends at the next frame",
         v.pic[0].size == 8 + 7 && v.pic[1].size == 8 &&
             v.pic[0].data[3] == 0x0D && !v.pic[0].needStartCode &&
             v.pic[0].secondField == 0);

  // The codec block against the Linux capture (352x288 advanced profile clip:
  // pulldown, loop filter, dquant 1).
  static const uint8_t kLinuxVc1Block[36] = {
      2, 0, 0, 0, 4, 0, 0, 0, 0x40, 0, 0, 0, 0x22, 0, 7, 0, 0, 0,
      0, 0, 1, 0, 0, 0, 0, 0, 0,    0, 0, 0, 0,    0, 0, 0, 0, 0};
  Vc1Parser q = p;
  q.range_mapuv_flag = q.range_mapuv = 0;
  VcnVc1Msg b;
  vcnvc1_fill_block(&b, &q);
  expect("vc1: codec block equals the one Mesa sent on Linux",
         !memcmp(&b, kLinuxVc1Block, sizeof(b)));
  vcnvc1_fill_block(&b, &p);
  expect("vc1: range mapping goes in the picture flags",
         b.pps_info_flags == (0x00070022u | 1u << 27 | 5u << 24));

  // A frame the container stripped of its start code, after the headers
  // arrived on their own (the codec private data).
  size_t hdr = 0;
  while (!(w.d[hdr] == 0 && w.d[hdr + 1] == 0 && w.d[hdr + 2] == 1 &&
           w.d[hdr + 3] == 0x0D))
    hdr++;
  vc1_parser_init(&p);
  V1 none = {0};
  expect("vc1: headers alone give no frame",
         vc1_parse_chunk(&p, w.d, hdr, v1_cb, &none) == 0 && none.n == 0 &&
             p.have_entry);
  static const uint8_t bare[6] = {0x00, 0x42, 0x42, 0x42, 0x10, 0x20};
  expect("vc1: a frame without a start code is one frame that needs one",
         vc1_parse_chunk(&p, bare, sizeof(bare), v1_cb, &none) == 0 &&
             none.n == 1 && none.pic[0].needStartCode &&
             none.pic[0].type == VC1_P && none.pic[0].size == sizeof(bare));
  vc1_parser_init(&p);
  expect("vc1: a frame before its headers says so",
         vc1_parse_chunk(&p, bare, sizeof(bare), v1_cb, &none) == -1 &&
             p.missing_sequence);

  // Field-interlaced: fcm 11, fptype 001 (I then P), a field start code.
  W f = {0};
  v1_headers(&f, 1);
  start(&f, 0x0D);
  put(&f, 3, 2);
  put(&f, 1, 3);
  put(&f, 0, 3);
  put(&f, 0x111111, 24);
  start(&f, 0x0C);
  put(&f, 0x222222, 24);
  start(&f, 0x0D);  // frame interlace (fcm 10), P
  put(&f, 2, 2);
  put(&f, 0, 1);
  put(&f, 0, 5);
  V1 fv = {0};
  vc1_parser_init(&p);
  r = vc1_parse_chunk(&p, f.d, bytes(&f), v1_cb, &fv);
  expect("vc1: a field-interlaced frame is split at its field start code",
         r == 0 && fv.n == 2 && fv.pic[0].fcm == VC1_FIELD_INTERLACE &&
             fv.pic[0].type == VC1_I && fv.pic[0].secondFieldType == VC1_P &&
             fv.pic[0].secondField == 8 && fv.pic[0].size == 15 &&
             fv.pic[1].fcm == VC1_FRAME_INTERLACE && fv.pic[1].type == VC1_P &&
             fv.pic[1].secondField == 0);

  // Simple/main: main profile, loop filter, fast UV MC, extended MV, dquant
  // 1, variable transform, overlap, 2 B frames, finterp.
  W s = {0};
  put(&s, 1, 2);  // main
  put(&s, 0, 2);
  put(&s, 0, 8);
  put(&s, 1, 1);  // loopfilter
  put(&s, 0, 1);
  put(&s, 0, 1);  // multires
  put(&s, 1, 1);  // res_fasttx
  put(&s, 1, 1);  // fastuvmc
  put(&s, 1, 1);  // extended_mv
  put(&s, 1, 2);  // dquant
  put(&s, 1, 1);  // vstransform
  put(&s, 0, 1);
  put(&s, 1, 1);  // overlap
  put(&s, 0, 1);  // syncmarker
  put(&s, 0, 1);  // rangered
  put(&s, 2, 3);  // maxbframes
  put(&s, 1, 2);  // quantizer
  put(&s, 1, 1);  // finterpflag
  put(&s, 1, 1);
  vc1_parser_init(&p);
  expect("vc1: simple/main header",
         vc1_parse_struct_c(&p, s.d, bytes(&s), 1280, 720) == 0 &&
             p.profile == VC1_PROFILE_MAIN && p.loopfilter && p.fastuvmc &&
             p.extended_mv && p.dquant == 1 && p.vstransform && p.overlap &&
             p.maxbframes == 2 && p.quantizer == 1 && p.finterpflag &&
             p.width == 1280 && p.height == 720);
  vcnvc1_fill_block(&b, &p);
  expect("vc1: main profile block",
         b.profile == VCN_VC1_MAIN && b.level == 2 &&
             b.sps_info_flags == 1u << 3 &&
             b.pps_info_flags == (2u << 16 | 1u << 11 | 1u << 9 | 1u << 0 |
                                  1u << 5 | 1u << 4 | 1u << 3 | 1u << 1));
  // Frames: interpfrm(1) framecnt(2) then 1 = P; 0 1 = I; 0 0 = B.
  static const uint8_t fp[2] = {0x10, 0}, fi[2] = {0x08, 0}, fb[2] = {0x00, 0},
                       fs[1] = {0};
  V1 mv = {0};
  vc1_parse_frame(&p, fi, 2, v1_cb, &mv);
  vc1_parse_frame(&p, fp, 2, v1_cb, &mv);
  vc1_parse_frame(&p, fb, 2, v1_cb, &mv);
  vc1_parse_frame(&p, fs, 1, v1_cb, &mv);
  expect("vc1: simple/main frame types",
         mv.n == 4 && mv.pic[0].type == VC1_I && mv.pic[1].type == VC1_P &&
             mv.pic[2].type == VC1_B && mv.pic[3].type == VC1_SKIPPED &&
             !mv.pic[0].needStartCode);
  expect("vc1: a header that is not simple or main is refused",
         vc1_parse_struct_c(&p, (const uint8_t[]){0xC0, 0, 0, 0}, 4, 16, 16) ==
             -1);
  for (size_t cut = 0; cut <= n; cut++) {
    uint8_t* copy = malloc(cut ? cut : 1);
    memcpy(copy, w.d, cut);
    vc1_parser_init(&p);
    vc1_parse_chunk(&p, copy, cut, v1_cb, &none);
    free(copy);
  }
  for (size_t cut = 0; cut <= 4; cut++) {
    uint8_t* copy = malloc(cut ? cut : 1);
    memcpy(copy, s.d, cut);
    vc1_parser_init(&p);
    vc1_parse_struct_c(&p, copy, cut, 16, 16);
    free(copy);
  }
  damaged(w.d, n, v1_parse, kDamagedRounds);
  damaged(f.d, bytes(&f), v1_parse, kDamagedRounds);
  damaged(s.d, bytes(&s), v1_parse, kDamagedRounds);
  expect("vc1: every prefix and 5000 damaged copies parse in bounds", 1);
}

// ---- MPEG-4
typedef struct {
  int n;
  Mpeg4Picture pic[8];
} M4;
static int m4_cb(void* ctx, Mpeg4Parser* p, const Mpeg4Picture* pic) {
  (void)p;
  M4* m = ctx;
  if (m->n < 8) m->pic[m->n] = *pic;
  m->n++;
  return 0;
}

static int m4_fill_cb(void* ctx, Mpeg4Parser* p, const Mpeg4Picture* pic) {
  VcnMpeg4Msg b;
  vcnmpeg4_block_mode = (int)(++*(uint32_t*)ctx & 1);
  vcnmpeg4_fill_block(&b, p, pic, *(uint32_t*)ctx, 1, 2);
  vcnmpeg4_block_mode = 0;
  return 0;
}
static void m4_parse(const uint8_t* d, size_t n) {
  Mpeg4Parser p;
  uint32_t count = 0;
  mpeg4_parser_init(&p);
  mpeg4_parse_chunk(&p, d, n, m4_fill_cb, &count);
}

// flags: 1 = data partitioned, 2 = sprite, 4 = complexity estimation,
// 8 = low_delay, 16 = Simple object without vol_control_parameters
static void m4_vol(W* w, int verid, int quantType, int interlaced, int flags) {
  start(w, 0xB0);
  put(w, 0xF5, 8);
  start(w, 0x20);
  put(w, 0, 1);
  put(w, flags & 16 ? 1 : 17, 8);
  put(w, 1, 1);  // is_object_layer_identifier
  put(w, (uint32_t)verid, 4);
  put(w, 1, 3);
  put(w, 1, 4);  // aspect ratio
  if (flags & 16) {
    put(w, 0, 1);  // no vol_control_parameters
  } else {
    put(w, 1, 1);  // vol_control_parameters
    put(w, 1, 2);
    put(w, flags & 8 ? 1 : 0, 1);  // low_delay
    put(w, 0, 1);                  // no vbv
  }
  put(w, 0, 2);  // rectangular
  put(w, 1, 1);
  put(w, 25, 16);  // time resolution: 5 bits
  put(w, 1, 1);
  put(w, 1, 1);  // fixed_vop_rate
  put(w, 1, 5);
  put(w, 1, 1);
  put(w, 640, 13);
  put(w, 1, 1);
  put(w, 480, 13);
  put(w, 1, 1);
  put(w, (uint32_t)interlaced, 1);
  put(w, 1, 1);  // obmc_disable
  put(w, flags & 2 ? 1 : 0, verid == 1 ? 1 : 2);
  put(w, 0, 1);  // not_8_bit
  put(w, (uint32_t)quantType, 1);
  if (quantType) {
    put(w, 1, 1);  // intra matrix: 9, 10, 11, then it stops
    put(w, 9, 8);
    put(w, 10, 8);
    put(w, 11, 8);
    put(w, 0, 8);
    put(w, 0, 1);  // default non-intra matrix
  }
  if (verid != 1) put(w, 1, 1);  // quarter_sample
  put(w, flags & 4 ? 0 : 1, 1);  // complexity_estimation_disable
  put(w, 1, 1);                  // resync_marker_disable
  put(w, flags & 1 ? 1 : 0, 1);  // data_partitioned
  if (verid != 1) {
    put(w, 0, 1);
    put(w, 0, 1);
  }
  put(w, 0, 1);  // scalability
}
static void m4_vop(W* w, int type, int seconds, int increment, int coded,
                   int interlaced) {
  start(w, 0xB6);
  put(w, (uint32_t)type, 2);
  for (int i = 0; i < seconds; i++) put(w, 1, 1);
  put(w, 0, 1);
  put(w, 1, 1);
  put(w, (uint32_t)increment, 5);
  put(w, 1, 1);
  put(w, (uint32_t)coded, 1);
  if (!coded) return;
  if (type == 1) put(w, 1, 1);   // rounding
  put(w, 5, 3);                  // intra_dc_vlc_thr
  if (interlaced) put(w, 2, 2);  // top_field_first, no alternate scan
  put(w, 12, 5);                 // quant
  if (type != 0) put(w, 3, 3);
  if (type == 2) put(w, 4, 3);
  put(w, 0x3c3c3c, 24);
}

static void test_mpeg4(void) {
  W w = {0};
  m4_vol(&w, 2, 1, 1, 0);
  m4_vop(&w, 0, 0, 0, 1, 1);   // I at tick 0
  m4_vop(&w, 1, 0, 3, 1, 1);   // P at tick 3
  m4_vop(&w, 2, 0, 1, 1, 1);   // B at tick 1
  m4_vop(&w, 1, 1, 2, 1, 1);   // P at 1 s + 2 = tick 27
  m4_vop(&w, 2, 0, 24, 1, 1);  // B at tick 24 (still the second before)
  m4_vop(&w, 1, 0, 5, 0, 1);   // not coded
  size_t n = bytes(&w);
  Mpeg4Parser p;
  M4 m = {0};
  mpeg4_parser_init(&p);
  int r = mpeg4_parse_chunk(&p, w.d, n, m4_cb, &m);
  expect("mpeg4: six VOPs", r == 0 && m.n == 6);
  expect("mpeg4: VOL fields",
         p.width == 640 && p.height == 480 && p.verid == 2 &&
             p.time_increment_resolution == 25 && p.time_increment_bits == 5 &&
             p.interlaced && p.quant_type && p.quarter_sample &&
             p.resync_marker_disable && p.profile_and_level == 0xF5);
  expect("mpeg4: a matrix that stops early repeats its last value",
         p.intra_matrix[0] == 9 && p.intra_matrix[2] == 11 &&
             p.intra_matrix[3] == 11 && p.intra_matrix[63] == 11 &&
             p.nonintra_matrix[0] == 16 && p.nonintra_matrix[63] == 33);
  expect("mpeg4: VOP header fields",
         m.pic[0].coding_type == MPEG4_I && m.pic[0].vop_coded &&
             m.pic[0].intra_dc_vlc_thr == 5 && m.pic[0].top_field_first &&
             m.pic[0].quant == 12 && m.pic[1].coding_type == MPEG4_P &&
             m.pic[1].rounding_type == 1 && m.pic[1].fcode_forward == 3 &&
             m.pic[2].coding_type == MPEG4_B && m.pic[2].fcode_backward == 4);
  expect("mpeg4: time distances of the B-VOPs",
         m.pic[2].trd == 3 && m.pic[2].trb == 1 && m.pic[4].trd == 24 &&
             m.pic[4].trb == 21 && m.pic[1].trd == 0);
  expect("mpeg4: a VOP that is not coded is reported as such",
         m.pic[5].vop_coded == 0 && m.pic[5].coding_type == MPEG4_P);
  expect("mpeg4: the first unit carries the headers in front of its VOP",
         m.pic[0].data == w.d && m.pic[0].vopOffset > 8 &&
             m.pic[0].data[m.pic[0].vopOffset + 3] == 0xB6 &&
             m.pic[1].vopOffset == 0 &&
             m.pic[1].data == m.pic[0].data + m.pic[0].size);

  VcnMpeg4Msg b;
  vcnmpeg4_index_mode = 0;
  vcnmpeg4_block_mode = 0;
  vcnmpeg4_fill_block(&b, &p, &m.pic[2], 3, 1, 2);
  expect("mpeg4: block as Mesa built it for older video engines",
         b.decoded_pic_idx == 3 && b.forward_ref_pic_idx == 1 &&
             b.backward_ref_pic_idx == 2 &&
             b.profile_and_level_indication == 0xF0 &&
             b.video_object_layer_verid == 5 &&
             b.video_object_layer_width == 640 &&
             b.video_object_layer_height == 480 &&
             b.vop_time_increment_resolution == 25 &&
             b.feature_flags ==
                 (VCN_MPEG4_INTERLACED | VCN_MPEG4_LOAD_INTRA_QUANT_MAT |
                  VCN_MPEG4_LOAD_NONINTRA_QUANT_MAT | VCN_MPEG4_QUARTER_SAMPLE |
                  VCN_MPEG4_COMPLEXITY_ESTIMATION_DISABLE |
                  VCN_MPEG4_RESYNC_MARKER_DISABLE) &&
             b.quant_type == 1 && b.intra_quant_mat[0] == 9 &&
             b.vop.vop_data_present == 0);
  // intra matrix in zigzag order: 9, 10, 11, 11, ... The transposed one in
  // zigzag order swaps the 2nd and 3rd entries (raster 1 and 8).
  vcnmpeg4_matrix_mode = 1;
  VcnMpeg4Msg t;
  vcnmpeg4_fill_block(&t, &p, &m.pic[2], 3, 1, 2);
  vcnmpeg4_matrix_mode = 0;
  expect("mpeg4: matrices go in stream order; mode 1 sends the transposed one",
         b.intra_quant_mat[1] == 10 && b.intra_quant_mat[2] == 11 &&
             t.intra_quant_mat[0] == 9 && t.intra_quant_mat[1] == 11 &&
             t.intra_quant_mat[2] == 10 && t.intra_quant_mat[63] == 11 &&
             t.nonintra_quant_mat[63] == 33);
  vcnmpeg4_block_mode = 1;
  vcnmpeg4_fill_block(&b, &p, &m.pic[2], 3, 1, 2);
  expect("mpeg4: block with the VOP part filled",
         b.vop.vop_data_present == 1 && b.vop.vop_coding_type == MPEG4_B &&
             b.vop.vop_quant == 12 && b.vop.vop_fcode_forward == 3 &&
             b.vop.vop_fcode_backward == 4 && b.vop.TRB[0] == 1 &&
             b.vop.TRD[1] == 3 && b.video_object_layer_verid == 2);
  vcnmpeg4_block_mode = 0;

  M4 none = {0};
  for (int flags = 1; flags <= 4; flags <<= 1) {
    W bad = {0};
    m4_vol(&bad, 2, 0, 0, flags);
    m4_vop(&bad, 0, 0, 0, 1, 0);
    mpeg4_parser_init(&p);
    expect(flags == 1   ? "mpeg4: data partitioning is refused"
           : flags == 2 ? "mpeg4: sprites are refused"
                        : "mpeg4: complexity estimation is refused",
           mpeg4_parse_chunk(&p, bad.d, bytes(&bad), m4_cb, &none) == -1 &&
               !p.have_vol);
  }
  W novol = {0};
  m4_vop(&novol, 0, 0, 0, 1, 0);
  mpeg4_parser_init(&p);
  expect("mpeg4: a VOP before any VOL says so",
         mpeg4_parse_chunk(&p, novol.d, bytes(&novol), m4_cb, &none) == -1 &&
             p.missing_vol);
  W v1 = {0};
  m4_vol(&v1, 1, 0, 0, 0);
  mpeg4_parser_init(&p);
  expect("mpeg4: a version 1 VOL has no quarter sample bit",
         mpeg4_parse_chunk(&p, v1.d, bytes(&v1), m4_cb, &none) == 0 &&
             p.have_vol && p.verid == 1 && !p.quarter_sample &&
             p.resync_marker_disable);
  // What a VOL says about B-VOPs, and the codec layer's answer to such a
  // configuration (create() only parses it; nothing goes to the GPU).
  expect("mpeg4: an ASP VOL without low_delay can carry B-VOPs",
         p.object_type == 17 && !p.no_b_vops);
  char err[256] = "";
  void* c = vcnmpeg4_codec.create(w.d, n, 0, 0, err, sizeof(err));
  expect("mpeg4: a configuration that can carry B-VOPs is refused",
         !c && strstr(err, "B-VOPs"));
  for (int f = 8; f <= 16; f += 8) {
    W ok = {0};
    m4_vol(&ok, 2, 0, 0, f);
    mpeg4_parser_init(&p);
    mpeg4_parse_chunk(&p, ok.d, bytes(&ok), m4_cb, &none);
    err[0] = 0;
    c = vcnmpeg4_codec.create(ok.d, bytes(&ok), 0, 0, err, sizeof(err));
    expect(f == 8 ? "mpeg4: low_delay rules B-VOPs out and is taken"
                  : "mpeg4: a Simple object rules B-VOPs out and is taken",
           p.no_b_vops && c && !err[0]);
    vcnmpeg4_codec.destroy(c);
  }
  setenv("VCNMPEG4_ALLOW_B", "1", 1);
  c = vcnmpeg4_codec.create(w.d, n, 0, 0, err, sizeof(err));
  unsetenv("VCNMPEG4_ALLOW_B");
  expect("mpeg4: VCNMPEG4_ALLOW_B=1 takes it for experiments", c != NULL);
  vcnmpeg4_codec.destroy(c);

  for (size_t cut = 0; cut <= n; cut++) {
    uint8_t* copy = malloc(cut ? cut : 1);
    memcpy(copy, w.d, cut);
    mpeg4_parser_init(&p);
    mpeg4_parse_chunk(&p, copy, cut, m4_cb, &none);
    free(copy);
  }
  damaged(w.d, n, m4_parse, kDamagedRounds);
  expect("mpeg4: every prefix and 5000 damaged copies parse in bounds", 1);
}

// ---- file mode
static int print_m2(void* ctx, Mpeg2Parser* p, const Mpeg2Picture* pic) {
  int* n = ctx;
  printf(
      "%d %c %ux%u structure %u tff %u frame_pred %u alt %u f_code "
      "%u,%u,%u,%u slices %zu bytes\n",
      (*n)++, " IPB"[pic->coding_type], p->width, p->height,
      pic->picture_structure, pic->top_field_first, pic->frame_pred_frame_dct,
      pic->alternate_scan, pic->f_code[0][0], pic->f_code[0][1],
      pic->f_code[1][0], pic->f_code[1][1], pic->slicesSize);
  return 0;
}
static int print_v1(void* ctx, Vc1Parser* p, const Vc1Picture* pic) {
  int* n = ctx;
  static const char* const t[] = {"P", "B", "I", "BI", "skipped"};
  printf("%d %s %ux%u fcm %u second field at %zu, %zu bytes\n", (*n)++,
         t[pic->type], p->width, p->height, pic->fcm, pic->secondField,
         pic->size);
  return 0;
}
static int print_m4(void* ctx, Mpeg4Parser* p, const Mpeg4Picture* pic) {
  int* n = ctx;
  printf(
      "%d %c %ux%u%s coded %u quant %u fcode %u/%u trd %u trb %u, %zu "
      "bytes (VOP at %zu)\n",
      (*n)++, "IPBS"[pic->coding_type], p->width, p->height,
      p->no_b_vops ? " no-B" : "", pic->vop_coded, pic->quant,
      pic->fcode_forward, pic->fcode_backward, pic->trd, pic->trb, pic->size,
      pic->vopOffset);
  return 0;
}

static int dump(const char* codec, const char* path) {
  FILE* f = fopen(path, "rb");
  if (!f) return 1;
  fseek(f, 0, SEEK_END);
  long size = ftell(f);
  fseek(f, 0, SEEK_SET);
  uint8_t* d = malloc(size > 0 ? (size_t)size : 1);
  if (!d || fread(d, 1, (size_t)size, f) != (size_t)size) return 1;
  fclose(f);
  int n = 0, r = 0;
  const char* err = "";
  if (!strcmp(codec, "mpeg2")) {
    Mpeg2Parser p;
    mpeg2_parser_init(&p);
    r = mpeg2_parse_chunk(&p, d, (size_t)size, print_m2, &n);
    if (r) printf("error: %s\n", p.err);
  } else if (!strcmp(codec, "vc1")) {
    Vc1Parser p;
    vc1_parser_init(&p);
    r = vc1_parse_chunk(&p, d, (size_t)size, print_v1, &n);
    if (r) printf("error: %s\n", p.err);
  } else if (!strcmp(codec, "mpeg4")) {
    Mpeg4Parser p;
    mpeg4_parser_init(&p);
    r = mpeg4_parse_chunk(&p, d, (size_t)size, print_m4, &n);
    if (r) printf("error: %s\n", p.err);
  } else {
    err = "unknown codec";
    r = 1;
  }
  if (*err) printf("%s\n", err);
  free(d);
  return r ? 1 : 0;
}

int main(int argc, char** argv) {
  if (argc == 3) return dump(argv[1], argv[2]);
  test_mpeg2();
  test_vc1();
  test_mpeg4();
  printf("%s\n", failures ? "FAILED" : "all passed");
  return failures ? 1 : 0;
}
