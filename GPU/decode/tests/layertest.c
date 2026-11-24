// layertest: the MPEG-2 and VC-1 codec layers (mpeg2/vcnmpeg2.c,
// vc1/vcnvc1.c) on a stand-in for common/vcnlegacy.c: nothing opens the GPU
// or the driver. The stand-in records every command the layer would send to
// the firmware, so the test sees what goes out for a stream and which picture
// comes back for each sample. It checks:
//
//   1. a VC-1 simple/main skipped frame (a sample of one byte or none) sends
//      nothing to the firmware and shows the reference frame before it again;
//      one before any reference frame is refused, also without a command;
//   2. MPEG-2 field pictures are refused before any command, unless
//      VCNMPEG2_ALLOW_FIELDS=1; with it, the two field pictures of a frame go
//      into one picture, with two commands, the frame is shown once, after its
//      second field, and with numbered indices both fields carry the frame's
//      number (field mode 1).
#include <CoreVideo/CoreVideo.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mpeg2msg.h"
#include "vcnlegacy.h"
#include "vcnmpeg2.h"
#include "vcnvc1.h"

static int failures;
static void expect(const char* what, int ok) {
  printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) failures++;
}

// ---- the stand-in for vcnlegacy.c
enum { MAX_CMDS = 64 };
static struct {
  CVPixelBufferRef target;
  size_t size;
  uint8_t block[512];
  uint32_t blockSize;
} g_cmd[MAX_CMDS];
static int g_cmds, g_created, g_destroyed;

struct VcnLegacy {
  VcnLegacyConfig cfg;
};
int vcnlegacy_debug, vcnlegacy_gpu_armed;
VcnLegacy* vcnlegacy_create(const VcnLegacyConfig* cfg, char* err,
                            size_t errLen) {
  (void)err, (void)errLen;
  VcnLegacy* d = calloc(1, sizeof(*d));
  if (!d) abort();
  d->cfg = *cfg;
  g_created++;
  return d;
}
void vcnlegacy_destroy(VcnLegacy* d) {
  if (!d) return;
  g_destroyed++;
  free(d);
}
CVPixelBufferRef vcnlegacy_new_target(VcnLegacy* d) {
  CVPixelBufferRef pb = NULL;
  CVPixelBufferCreate(NULL, d->cfg.width, d->cfg.height,
                      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, NULL,
                      &pb);
  return pb;
}
int vcnlegacy_decode(VcnLegacy* d, const void* block, uint32_t blockSize,
                     const VcnLegacyBytes* parts, int nparts,
                     CVPixelBufferRef target) {
  (void)d;
  if (g_cmds == MAX_CMDS) abort();
  size_t size = 0;
  for (int i = 0; i < nparts; i++) size += parts[i].size;
  g_cmd[g_cmds].target = target;
  g_cmd[g_cmds].size = size;
  g_cmd[g_cmds].blockSize = blockSize;
  memcpy(
      g_cmd[g_cmds].block, block,
      blockSize < sizeof(g_cmd[0].block) ? blockSize : sizeof(g_cmd[0].block));
  g_cmds++;
  return 0;
}
const char* vcnlegacy_last_error(VcnLegacy* d) {
  (void)d;
  return "";
}
int vcnlegacy_failure(VcnLegacy* d) {
  (void)d;
  return VCNLEGACY_FAIL_STREAM;
}
unsigned vcnlegacy_firmware_errors(VcnLegacy* d) {
  (void)d;
  return 0;
}
uint32_t vcnlegacy_width(VcnLegacy* d) { return d ? d->cfg.width : 0; }
uint32_t vcnlegacy_height(VcnLegacy* d) { return d ? d->cfg.height : 0; }

// ---- what the layer shows
enum { MAX_OUT = 64 };
static struct {
  CVPixelBufferRef pb;
  int use;
} g_out[MAX_OUT];
static int g_outs;
static int on_frame(void* ctx, CVPixelBufferRef pb, int use, uint32_t w,
                    uint32_t h) {
  (void)ctx, (void)w, (void)h;
  if (g_outs == MAX_OUT) abort();
  g_out[g_outs].pb = pb ? CVPixelBufferRetain(pb) : NULL;
  g_out[g_outs].use = use;
  g_outs++;
  return 0;
}
static void reset(void) {
  for (int i = 0; i < g_outs; i++)
    if (g_out[i].pb) CVPixelBufferRelease(g_out[i].pb);
  g_outs = g_cmds = g_created = g_destroyed = 0;
}

// ---- a bit writer for the made-up streams
typedef struct {
  uint8_t d[1024];
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

// ---- 1. VC-1 simple/main skipped frames
static void test_vc1_skipped(void) {
  // STRUCT_C: main profile, no B frames, no frame interpolation, no range
  // reduction: a frame is framecnt (2 bits), then 1 for P, 0 for I.
  static const uint8_t structc[4] = {0x40, 0, 0, 0};
  static const uint8_t fi[8] = {0x00, 1, 2, 3, 4, 5, 6, 7};
  static const uint8_t fp[8] = {0x20, 1, 2, 3, 4, 5, 6, 7};
  static const uint8_t skip1[1] = {0};
  char err[256] = "";
  void* d =
      vcnvc1_codec.create(structc, sizeof(structc), 320, 240, err, sizeof(err));
  expect("vc1: a main profile STRUCT_C is taken", d != NULL);
  if (!d) return;
  reset();
  int r = vcnvc1_codec.decode(d, skip1, 1, on_frame, NULL);
  expect("vc1: a skipped frame before any reference is refused, no command",
         r != 0 && g_cmds == 0 && g_outs == 0 &&
             vcnvc1_codec.failure(d) == VCNLEGACY_FAIL_REFERENCE);
  r = vcnvc1_codec.decode(d, fi, sizeof(fi), on_frame, NULL);
  r |= vcnvc1_codec.decode(d, skip1, 1, on_frame, NULL);
  r |= vcnvc1_codec.decode(d, fp, sizeof(fp), on_frame, NULL);
  r |= vcnvc1_codec.decode(d, skip1, 0, on_frame, NULL);
  expect("vc1: I, skipped, P, skipped: two commands, four frames shown",
         r == 0 && g_cmds == 2 && g_outs == 4);
  expect("vc1: no command carries a bitstream of one byte or none",
         g_cmds == 2 && g_cmd[0].size > 1 && g_cmd[1].size > 1);
  expect("vc1: each skipped frame shows the reference frame before it",
         g_outs == 4 && g_out[1].pb && g_out[1].pb == g_out[0].pb &&
             g_out[3].pb && g_out[3].pb == g_out[2].pb &&
             g_out[2].pb != g_out[0].pb &&
             g_out[1].use == VCNLEGACY_PIC_REFERENCE &&
             g_out[3].use == VCNLEGACY_PIC_REFERENCE);
  vcnvc1_codec.destroy(d);
  expect("vc1: the session is closed with the decoder",
         g_created == 1 && g_destroyed == 1);
  reset();
}

// ---- 2. MPEG-2 field pictures
static void mpeg2_headers(W* w) {
  start(w, 0xB3);  // sequence header
  put(w, 64, 12);  // width
  put(w, 64, 12);  // height
  put(w, 1, 4);    // aspect ratio
  put(w, 3, 4);    // 25 fps
  put(w, 1000, 18);
  put(w, 1, 1);
  put(w, 112, 10);
  put(w, 0, 3);    // constrained, no matrices
  start(w, 0xB5);  // sequence extension
  put(w, 1, 4);
  put(w, 0x48, 8);
  put(w, 0, 1);  // interlaced sequence
  put(w, 1, 2);  // 4:2:0
  put(w, 0, 4);
  put(w, 0, 12);
  put(w, 1, 1);
  put(w, 0, 8);
  put(w, 1, 1);  // low delay
  put(w, 0, 7);
}
static void mpeg2_field(W* w, int type, int structure) {
  start(w, 0x00);  // picture header
  put(w, 0, 10);
  put(w, (uint32_t)type, 3);
  put(w, 0xFFFF, 16);
  if (type == 2) put(w, 7, 4);  // full_pel_forward_vector, forward_f_code
  start(w, 0xB5);               // picture coding extension
  put(w, 8, 4);
  uint32_t f = type == 2 ? 1 : 15;
  put(w, f, 4);
  put(w, f, 4);
  put(w, 15, 4);
  put(w, 15, 4);
  put(w, 0, 2);
  put(w, (uint32_t)structure, 2);
  put(w, 0, 10);
  start(w, 0x01);  // one slice; its contents do not matter here
  put(w, 0x5A5A5A5A, 32);
}
static void test_mpeg2_fields(void) {
  W w = {0};
  mpeg2_headers(&w);
  mpeg2_field(&w, 1, 1);  // frame 1: top I
  mpeg2_field(&w, 2, 2);  //          bottom P, from the top field
  mpeg2_field(&w, 2, 1);  // frame 2: top P
  mpeg2_field(&w, 2, 2);  //          bottom P
  size_t n = bytes(&w);
  char err[256] = "";
  unsetenv("VCNMPEG2_ALLOW_FIELDS");
  void* d = vcnmpeg2_codec.create(NULL, 0, 64, 64, err, sizeof(err));
  expect("mpeg2: a decoder without a configuration is made", d != NULL);
  if (!d) return;
  reset();
  int r = vcnmpeg2_codec.decode(d, w.d, n, on_frame, NULL);
  expect("mpeg2: field pictures are refused, with no command and no session",
         r != 0 && g_cmds == 0 && g_outs == 0 && g_created == 0 &&
             strstr(vcnmpeg2_codec.last_error(d), "field pictures"));
  vcnmpeg2_codec.destroy(d);
  reset();

  setenv("VCNMPEG2_ALLOW_FIELDS", "1", 1);
  d = vcnmpeg2_codec.create(NULL, 0, 64, 64, err, sizeof(err));
  if (!d) return;
  r = vcnmpeg2_codec.decode(d, w.d, n, on_frame, NULL);
  expect("mpeg2: two frames of two field pictures: four commands, two frames",
         r == 0 && g_cmds == 4 && g_outs == 2);
  expect("mpeg2: both fields of a frame go into one picture",
         g_cmds == 4 && g_cmd[0].target == g_cmd[1].target &&
             g_cmd[2].target == g_cmd[3].target &&
             g_cmd[0].target != g_cmd[2].target);
  VcnMpeg2Msg m[4];
  for (int i = 0; i < 4 && i < g_cmds; i++)
    memcpy(&m[i], g_cmd[i].block, sizeof(m[i]));
  expect("mpeg2: the commands say top, bottom, top, bottom",
         g_cmds == 4 && m[0].pic_structure == 1 && m[1].pic_structure == 2 &&
             m[2].pic_structure == 1 && m[3].pic_structure == 2);
  expect(
      "mpeg2: each frame is shown once, as a reference, after its second "
      "field",
      g_outs == 2 && g_out[0].pb == g_cmd[1].target &&
          g_out[1].pb == g_cmd[3].target &&
          g_out[0].use == VCNLEGACY_PIC_REFERENCE &&
          g_out[1].use == VCNLEGACY_PIC_REFERENCE);
  expect("mpeg2: with zero indices (the default) every index is 0",
         g_cmds == 4 && !m[0].decoded_pic_idx && !m[1].decoded_pic_idx &&
             !m[3].decoded_pic_idx && !m[3].forward_ref_pic_idx);
  vcnmpeg2_codec.destroy(d);
  reset();

  // Numbered indices, field mode 1: one number per frame.
  vcnmpeg2_index_mode = 0;
  vcnmpeg2_field_mode = 1;
  d = vcnmpeg2_codec.create(NULL, 0, 64, 64, err, sizeof(err));
  if (!d) return;
  r = vcnmpeg2_codec.decode(d, w.d, n, on_frame, NULL);
  for (int i = 0; i < 4 && i < g_cmds; i++)
    memcpy(&m[i], g_cmd[i].block, sizeof(m[i]));
  expect(
      "mpeg2: field mode 1: both fields of a frame carry the frame's number; "
      "the second field of the first frame predicts from its own number, a "
      "later frame from the frame before",
      r == 0 && g_cmds == 4 && m[0].decoded_pic_idx == 1 &&
          m[1].decoded_pic_idx == 1 && m[1].forward_ref_pic_idx == 1 &&
          m[2].decoded_pic_idx == 2 && m[3].decoded_pic_idx == 2 &&
          m[2].forward_ref_pic_idx == 1 && m[3].forward_ref_pic_idx == 1);
  vcnmpeg2_codec.destroy(d);
  reset();

  // Field mode 0: one number per field, as round 3 sent them.
  vcnmpeg2_field_mode = 0;
  d = vcnmpeg2_codec.create(NULL, 0, 64, 64, err, sizeof(err));
  if (!d) return;
  r = vcnmpeg2_codec.decode(d, w.d, n, on_frame, NULL);
  for (int i = 0; i < 4 && i < g_cmds; i++)
    memcpy(&m[i], g_cmd[i].block, sizeof(m[i]));
  expect("mpeg2: field mode 0: one number per field",
         r == 0 && g_cmds == 4 && m[0].decoded_pic_idx == 1 &&
             m[1].decoded_pic_idx == 2 && m[2].decoded_pic_idx == 3 &&
             m[3].decoded_pic_idx == 4);
  vcnmpeg2_codec.destroy(d);
  reset();
  vcnmpeg2_index_mode = 1;
  vcnmpeg2_field_mode = 1;
  unsetenv("VCNMPEG2_ALLOW_FIELDS");
}

int main(void) {
  test_vc1_skipped();
  test_mpeg2_fields();
  printf("%s\n", failures ? "FAILED" : "all passed");
  return failures ? 1 : 0;
}
