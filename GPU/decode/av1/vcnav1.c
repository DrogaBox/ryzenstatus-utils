#include "vcnav1.h"

#include <CoreFoundation/CoreFoundation.h>
#include <CoreVideo/CoreVideo.h>
#include <IOKit/IOKitLib.h>
#include <mach/mach_time.h>
#include <os/log.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "avd.h"
#include "vcndriver.h"

int vcnav1_debug = 0;
int vcnav1_gpu_armed = 0;
#define DBG(...)                                                \
  do {                                                          \
    if (vcnav1_debug) fprintf(stderr, "[vcnav1] " __VA_ARGS__); \
  } while (0)

#define VCN_MODE_VCN0 4
#define NUM_DPB 9
// A session that failed after a sleep is rebuilt and waits for a key frame,
// dropping the frames before it; at 60 fps this is ten seconds of frames. A
// stream that does not send one by then is stopped the way PR 160 stopped it,
// so the host can hand it to another decoder.
#define REBUILD_MAX_DROPPED 600
#define NUM_BS VCN_NUM_BS
#define BS_SIZE VCN_BS_SIZE
#define SEQ_BYTES 2048
#define FRAME_BYTES 4096
#define BSINFO_BYTES (20 + 64 * 512 + 64)

// Parameter block consumed by AvdVcnAv1DecDataProcessor (recovered layout).
typedef struct {
  void* seq;              // +0
  void* frame;            // +8
  uint32_t curr_pic_idx;  // +16
  uint32_t pad0;
  IOSurfaceRef output;        // +24
  uint32_t ref_frame_map[8];  // +32
  uint32_t frame_refs[7];     // +64
  uint32_t pad1;              // +92
  void* bsinfo;               // +96
  uint8_t reserved[160];
} AV1Params;

struct VcnAV1 {
  VcnDriverSession s;  // accelerator, driver, context and bitstream pool
  int bsNext;
  uint32_t maxW, maxH;
  AV1Parser parser;
  CVPixelBufferRef dpb[NUM_DPB];  // last picture decoded into each DPB slot
                                  // (kept for show_existing_frame)
  int dpbRefs[NUM_DPB];           // number of reference slots pointing here
  uint8_t *seq, *frame, *bsinfo;
  char err[256];
  VcnAV1OutputFn out;
  void* outCtx;
  int64_t tag;
  CVPixelBufferPoolRef
      pool;  // decode targets; references live in the driver's internal DPB
  uint32_t poolW, poolH;
  bool poolTen;
  bool stuck;   // a command never finished: the GPU may still hold it
  bool broken;  // stuck, or a driver call failed: nothing more goes out
  // The system slept since the driver side opened: frames still go to it, and
  // it is rebuilt at the next key frame (on_frame).
  bool rebuildAtKey;
  unsigned keptAfterWake;  // frames decoded on it since the sleep was seen
  bool needKey;      // rebuilt after a failure: drop frames until a key frame
  unsigned dropped;  // frames dropped since that rebuild
  // The long limit applies to the first command on the rebuilt session too:
  // right after a wake the engine can still take seconds, and a timeout there
  // would stop a session that is healthy. Cleared by the first command that
  // finishes on it.
  bool wakeGrace;
  uint32_t lastFw;          // firmware result of the last command that finished
  int failure;              // VCNAV1_FAIL_* of the last error
  bool shown;               // the current decode call output a frame
  CVPixelBufferRef hidden;  // retained: last frame it decoded without showing
  unsigned fwErrors;        // decodes the firmware reported as failed
  unsigned done;            // decode commands that finished
};

#define FN(name) ((AVD_##name##_fn)d->s.accel->fn[AVD_FN_##name])

static os_log_t vlog(void) {
  static os_log_t l;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    l = os_log_create("com.droga.vtav1vcn", "driver");
  });
  return l;
}

// The parameter layouts were recovered from (and validated on the GPU against)
// these exact builds of AMDRadeonVADriver2. Another build may lay them out
// differently, and a wrong VCN message can hang the GPU, so refuse to run
// elsewhere unless VCNAV1_ALLOW_UNVALIDATED_DRIVER=1 (after a dry run).
static const char* const kValidatedDrivers[] = {
    "8D3BA61E7BC73BDFADB3A7866360B6DE",  // macOS 26.7.1 (25G241)
    "5D90FED3BCBF34759F4B8FC00026D3AB",  // macOS 15.8.2 (24H232) and 15.8.3
                                         // (24H241, same binary): compared in
                                         // IDA against 26.7.1, same AV1 path
    "1181E2CA31B33DF090E23AE70552D753",  // macOS 26.7.2 (25G332) and 26.7.3
                                         // (25G342, same binary): compared in
                                         // IDA against 26.7.1, same code
    "F7D8F5849EC139DB857C769697294957",  // macOS 26.7.4 (25G422): same code
                                         // as 26.7.3 (2760/2760 functions
                                         // identical, only a build path)
};

static CFNumberRef cfnum(long long v) {
  return CFNumberCreate(NULL, kCFNumberLongLongType, &v);
}
// Sets one number; false when it could not be made (out of memory).
static bool put_num(CFMutableDictionaryRef a, CFStringRef k, long long v) {
  CFNumberRef n = cfnum(v);
  if (!n) return false;
  CFDictionarySetValue(a, k, n);
  CFRelease(n);
  return true;
}
// Pixel buffer attributes whose IOSurfaces have the layout validated on the
// VCN: pitch aligned to 256, height padded to 64, UV plane offset aligned to
// 4096.
CFDictionaryRef vcnav1_copy_pixel_buffer_attributes(uint32_t w, uint32_t h,
                                                    bool tenBit) {
  CFMutableDictionaryRef a =
      CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                &kCFTypeDictionaryValueCallBacks);
  CFMutableDictionaryRef io =
      CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                &kCFTypeDictionaryValueCallBacks);
  // NULL when anything cannot be made: half a set of attributes would give
  // surfaces with a layout the engine was never checked with.
  if (!a || !io) {
    if (a) CFRelease(a);
    if (io) CFRelease(io);
    return NULL;
  }
  bool ok = true;
#define PUT(k, v) (ok = put_num(a, k, v) && ok)
  PUT(kCVPixelBufferPixelFormatTypeKey,
      tenBit ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
             : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
  PUT(kCVPixelBufferWidthKey, w);
  PUT(kCVPixelBufferHeightKey, h);
  PUT(kCVPixelBufferBytesPerRowAlignmentKey, 256);
  PUT(kCVPixelBufferPlaneAlignmentKey, 4096);
  uint32_t padH = (h + 63) & ~63u, pitch = (w + 255) & ~255u;
  PUT(kCVPixelBufferExtendedPixelsBottomKey, padH - h);
  // The driver's AV1 path leaves the picture blank, with no error, when the
  // padded height is larger than the pitch (portrait video). Widen the rows
  // until the pitch reaches the padded height.
  if (padH > pitch)
    PUT(kCVPixelBufferExtendedPixelsRightKey, ((padH + 255) & ~255u) - w);
#undef PUT
  CFDictionarySetValue(a, kCVPixelBufferIOSurfacePropertiesKey, io);
  CFDictionarySetValue(a, kCVPixelBufferMetalCompatibilityKey, kCFBooleanTrue);
  CFRelease(io);
  if (!ok) {
    CFRelease(a);
    return NULL;
  }
  return a;
}
static CVPixelBufferRef new_target(VcnAV1* d, uint32_t w, uint32_t h,
                                   bool tenBit) {
  if (d->pool && (d->poolW != w || d->poolH != h || d->poolTen != tenBit)) {
    CVPixelBufferPoolRelease(d->pool);
    d->pool = NULL;
  }
  if (!d->pool) {
    CFDictionaryRef attrs = vcnav1_copy_pixel_buffer_attributes(w, h, tenBit);
    if (!attrs) return NULL;
    CVReturn r = CVPixelBufferPoolCreate(NULL, NULL, attrs, &d->pool);
    CFRelease(attrs);
    if (r) {
      d->pool = NULL;
      return NULL;
    }
    d->poolW = w;
    d->poolH = h;
    d->poolTen = tenBit;
  }
  CVPixelBufferRef pb = NULL;
  if (CVPixelBufferPoolCreatePixelBuffer(NULL, d->pool, &pb)) return NULL;
  return pb;
}
// One AV1 context on the driver handle this session has open: what a create
// and a rebuild after a sleep both need.
static int av1_create_context(VcnAV1* d) {
  AVD_ContextList list = {0};
  void* ctxOut[2] = {0};
  AVD_FunctionInfo* fis[1] = {&list.inlineInfo};
  list.count = 1;
  list.functions = fis;
  list.contextsOut = ctxOut;
  // mode 3/5 => VAVcnDecoder::Init(1) => second VCN instance (VCN1Dec), which
  // has NO AV1 on Navi21 and hangs the GPU. Mode 4 (what AppleGVA uses for
  // H.264) => Init(0) => VCN0Dec.
  list.inlineInfo = (AVD_FunctionInfo){.kind = 1,
                                       .function = AVD_FUNC_AV1,
                                       .mode = VCN_MODE_VCN0,
                                       .pixelRate = d->maxW * d->maxH * 60,
                                       .width = d->maxW,
                                       .height = d->maxH,
                                       .inFormat = 0x72617762,
                                       .inFormatCount = 1,
                                       .outFormat = 0x4e563132,
                                       .outFormatCount = 1};
  AVD_DriverContextInit ci = {.list = &list};
  int r = FN(CreateContexts)(d->s.drv, &ci);
  if (r || !ctxOut[0]) return r ? r : 1;
  d->s.ctx = ctxOut[0];
  return 0;
}

// The builds the AV1 parameter blocks were validated against, or the override
// a dry run sets (vcndriver.h).
static bool av1_driver_allowed(const VcnDriverLib* lib) {
  for (size_t i = 0; i < sizeof(kValidatedDrivers) / sizeof(*kValidatedDrivers);
       i++)
    if (!strcmp(lib->uuid, kValidatedDrivers[i])) return true;
  const char* ov = getenv("VCNAV1_ALLOW_UNVALIDATED_DRIVER");
  return ov && !strcmp(ov, "1");
}

VcnAV1* vcnav1_create(uint32_t maxWidth, uint32_t maxHeight, char* err,
                      size_t errLen) {
  VcnAV1* d = calloc(1, sizeof(*d));
  if (!d) {
    if (err && errLen) snprintf(err, errLen, "out of memory");
    return NULL;
  }
  d->maxW = maxWidth;
  d->maxH = maxHeight;
  av1_parser_init(&d->parser);
  d->seq = calloc(1, SEQ_BYTES);
  d->frame = calloc(1, FRAME_BYTES);
  d->bsinfo = calloc(1, BSINFO_BYTES);
#define FAIL(...)                                          \
  do {                                                     \
    if (err && errLen) snprintf(err, errLen, __VA_ARGS__); \
    vcnav1_destroy(d);                                     \
    return NULL;                                           \
  } while (0)
  if (!d->seq || !d->frame || !d->bsinfo) FAIL("out of memory");
  // The driver takes width * height * 60 in 32 bits, and not 0.
  if (!maxWidth || !maxHeight || maxWidth > 8192 || maxHeight > 4352)
    FAIL("session size %ux%u out of range", maxWidth, maxHeight);
  char why[200];
  VcnDriverLib lib;
  if (!vcn_driver_load(&lib, why, sizeof(why))) FAIL("%s", why);
  bool validated = false;
  for (size_t i = 0; i < sizeof(kValidatedDrivers) / sizeof(*kValidatedDrivers);
       i++)
    if (!strcmp(lib.uuid, kValidatedDrivers[i])) validated = true;
  const char* ov = getenv("VCNAV1_ALLOW_UNVALIDATED_DRIVER");
  if (!validated && !(ov && !strcmp(ov, "1")))
    FAIL(
        "AMDRadeonVADriver2 build %s not validated (dry-run it, then set "
        "VCNAV1_ALLOW_UNVALIDATED_DRIVER=1)",
        lib.uuid);
  DBG("driver %s%s\n", lib.uuid, validated ? " (validated)" : " (UNVALIDATED)");
  io_service_t svc = vcn_find_accelerator();
  if (!svc) FAIL("no AMD accelerator");
  // From here on, a failure closes everything opened so far, the accelerator
  // included.
  if (!vcn_session_open(&d->s, &lib, svc, vlog(), why, sizeof(why)))
    FAIL("%s", why);
  int r = av1_create_context(d);
  if (r) FAIL("CreateContexts(AV1) %d", r);
  DBG("created: drv=%p ctx=%p bs=%p\n", d->s.drv, d->s.ctx, d->s.bsAddr[0]);
  return d;
}

// Rebuilds the driver side of a session the system slept through: the objects
// from before the sleep are dropped without a word to the driver, and a fresh
// accelerator, driver, context and bitstream pool are opened for the same
// plug-in session, so the host's decoder object lives on. The references live
// in the old driver's DPB, so the DPB pictures and the reference slots go; the
// parser keeps the sequence header (a key frame does not always repeat it) and
// the frame header being decoded. The old accelerator is closed on the teardown
// queue, never on this thread (see the note below). False when the rebuild
// fails: the caller then stops the session as PR 160 did.
static bool av1_rebuild(VcnAV1* d, char* why, size_t whyLen) {
  CVPixelBufferRef old[NUM_DPB + 1];
  int n = 0;
  for (int i = 0; i < NUM_DPB; i++)
    if (d->dpb[i]) {
      old[n++] = d->dpb[i];
      d->dpb[i] = NULL;
    }
  if (d->hidden) {  // its own reference to one of them
    old[n++] = d->hidden;
    d->hidden = NULL;
  }
  // The old accelerator always goes on the teardown queue, not on this thread:
  // its close still shuts three IOKit user clients, and on the kernel side the
  // close of a video context goes through PowerPlay's notify, which can wait
  // after a failed wake (vcnsession.c, vcn_session_close). Nothing of the new
  // session waits for it, and the pictures are let go only after it, because a
  // command the wake dropped may still write into them. 0.3.7 closed it here
  // whenever the last command had finished, which is the normal path and the
  // one the teardown queue exists for. Without memory for the list the pictures
  // are never let go.
  CVPixelBufferRef* keep = n ? malloc((size_t)n * sizeof(*keep)) : NULL;
  if (keep) memcpy(keep, old, (size_t)n * sizeof(*keep));
  int kept = keep ? n : 0;
  vcn_session_drop_later(&d->s, "AV1 session from before the sleep", ^{
    for (int i = 0; i < kept; i++) CVPixelBufferRelease(keep[i]);
    free(keep);
  });
  vcnav1_flush(d);
  d->bsNext = 0;
  VcnDriverLib lib;
  if (!vcn_driver_load(&lib, why, whyLen)) return false;
  if (!av1_driver_allowed(&lib)) {
    snprintf(why, whyLen, "AMDRadeonVADriver2 build %s not validated",
             lib.uuid);
    return false;
  }
  io_service_t svc = vcn_find_accelerator();
  if (!svc) {
    snprintf(why, whyLen, "no AMD accelerator");
    return false;
  }
  if (!vcn_session_reopen(&d->s, &lib, svc, vlog(), why, whyLen)) return false;
  int r = av1_create_context(d);
  if (r) {
    snprintf(why, whyLen, "CreateContexts(AV1) %d", r);
    vcn_session_drop_later(&d->s, "AV1 session, CreateContexts failed", ^{});
    return false;
  }
  return true;
}

// Rebuilds now (av1_rebuild) and leaves the session decoding on the new driver;
// dropUntilKey: the frames before the next key frame are dropped. False, with
// the session stopped as a device failure, when the rebuild fails.
static bool rebuild_now(VcnAV1* d, bool dropUntilKey, const char* cause) {
  char why[200];
  unsigned kept = d->keptAfterWake;
  if (!av1_rebuild(d, why, sizeof(why))) {
    d->rebuildAtKey = false;
    d->broken = true;
    d->failure = VCNAV1_FAIL_DEVICE;
    snprintf(d->err, sizeof(d->err),
             "session stopped: the system slept since it opened and the "
             "rebuild failed (%s)",
             why);
    return false;
  }
  // What these said was about the old driver objects.
  d->rebuildAtKey = false;
  d->stuck = d->broken = false;
  d->keptAfterWake = 0;
  d->needKey = dropUntilKey;
  d->dropped = 0;
  // A fresh context may still be coming out of the wake: the first command on
  // it gets the long limit (0.3.7 gave it the usual second straight away).
  d->wakeGrace = true;
  if (dropUntilKey)
    os_log_error(
        vlog(),
        "the session from before the sleep failed after the wake "
        "(%{public}s, %u frames decoded on it before): driver rebuilt, "
        "frames are dropped until the next key frame; the old driver objects "
        "stay allocated, up to %d MiB not returned to the system",
        cause, kept,
        (int)(VCN_NUM_BS * (long long)VCN_BS_SIZE / (1024 * 1024)));
  else
    os_log_error(vlog(),
                 "driver rebuilt at the first key frame after the sleep (%u "
                 "frames decoded on the session from before it), no frame "
                 "dropped; the old driver objects stay allocated, up to %d MiB "
                 "not returned to the system",
                 kept,
                 (int)(VCN_NUM_BS * (long long)VCN_BS_SIZE / (1024 * 1024)));
  return true;
}

// The session from before the sleep failed on the frame being decoded: it is
// rebuilt at once and this frame is dropped, like the ones after it until a
// key frame. 0, or -1 when the rebuild fails.
static int failed_after_wake(VcnAV1* d) {
  char cause[256];
  snprintf(cause, sizeof(cause), "%s", d->err);
  if (!rebuild_now(d, true, cause)) return -1;
  d->err[0] = 0;
  d->failure = VCNAV1_FAIL_STREAM;
  d->dropped = 1;
  return 0;
}

static void destroy_now(VcnAV1* d) {
  vcn_session_close(&d->s);
  // The pictures go after the driver: a stuck command may still write one.
  for (int i = 0; i < NUM_DPB; i++)
    if (d->dpb[i]) CVPixelBufferRelease(d->dpb[i]);
  if (d->hidden) CVPixelBufferRelease(d->hidden);
  if (d->pool) CVPixelBufferPoolRelease(d->pool);
  av1_parser_free(&d->parser);
  free(d->seq);
  free(d->frame);
  free(d->bsinfo);
  free(d);
}

void vcnav1_destroy(VcnAV1* d) {
  if (!d) return;
  vcn_teardown(d->stuck, vcn_session_lost(&d->s), vlog(), "AV1 session", ^{
    destroy_now(d);
  });
}

const char* vcnav1_last_error(VcnAV1* d) { return d ? d->err : ""; }

unsigned vcnav1_firmware_errors(VcnAV1* d) { return d ? d->fwErrors : 0; }

int vcnav1_failure(VcnAV1* d) { return d ? d->failure : VCNAV1_FAIL_DEVICE; }

CVPixelBufferRef vcnav1_hidden_picture(VcnAV1* d) {
  return d && !d->shown ? d->hidden : NULL;
}
void vcnav1_color(VcnAV1* d, VcnColor* c) {
  vcn_color_clear(c);
  if (!d) return;
  const AV1Seq* s = &d->parser.seq;
  // Without color_description_present_flag the sequence header says nothing
  // (5.5.2: the three are then "unspecified").
  if (s->valid && s->color_description_present_flag) {
    c->primaries = s->color_primaries;
    c->transfer = s->transfer_characteristics;
    c->matrix = s->matrix_coefficients;
  }
  c->has_mdcv = av1_hdr_mdcv(&d->parser.hdr, c->mdcv);
  c->has_cll = av1_hdr_cll(&d->parser.hdr, c->cll);
}

static inline void S32(uint8_t* base, int idx, int v) {
  ((int32_t*)base)[idx] = v;
}
static inline void F32(uint8_t* base, int off, int v) {
  *(int32_t*)(base + off) = v;
}

static void pack_seq(VcnAV1* d) {
  const AV1Seq* s = &d->parser.seq;
  uint8_t* q = d->seq;
  memset(q, 0, SEQ_BYTES);
  S32(q, 0, s->seq_profile);
  S32(q, 1, s->still_picture);
  S32(q, 2, s->reduced_still_picture_header);
  S32(q, 305, s->max_frame_width_minus_1);
  S32(q, 306, s->max_frame_height_minus_1);
  S32(q, 307, s->frame_id_numbers_present_flag);
  S32(q, 308, s->delta_frame_id_length_minus_2);
  S32(q, 309, s->additional_frame_id_length_minus_1);
  S32(q, 310, s->use_128x128_superblock);
  S32(q, 311, s->enable_filter_intra);
  S32(q, 312, s->enable_intra_edge_filter);
  S32(q, 313, s->enable_interintra_compound);
  S32(q, 314, s->enable_masked_compound);
  S32(q, 315, s->enable_warped_motion);
  S32(q, 316, s->enable_dual_filter);
  S32(q, 317, s->enable_order_hint);
  S32(q, 318, s->enable_jnt_comp);
  S32(q, 319, s->enable_ref_frame_mvs);
  S32(q, 320, s->seq_choose_screen_content_tools);
  S32(q, 321, s->seq_force_screen_content_tools);
  S32(q, 322, s->seq_choose_integer_mv);
  S32(q, 323, s->seq_force_integer_mv);
  S32(q, 324, s->order_hint_bits_minus_1);
  S32(q, 325, s->OrderHintBits);
  S32(q, 326, s->enable_superres);
  S32(q, 327, s->enable_cdef);
  S32(q, 328, s->enable_restoration);
  S32(q, 329, s->high_bitdepth);
  S32(q, 330, s->twelve_bit);
  S32(q, 331, s->BitDepth);
  S32(q, 332, s->mono_chrome);
}

static void pack_frame(VcnAV1* d) {
  const AV1Frame* h = &d->parser.fh;
  uint8_t* q = d->frame;
  memset(q, 0, FRAME_BYTES);
  F32(q, 0, h->show_existing_frame);
  F32(q, 4, h->frame_to_show_map_idx);
  F32(q, 16, h->frame_type);
  F32(q, 20, h->FrameIsIntra);
  F32(q, 24, h->show_frame);
  F32(q, 28, h->showable_frame);
  F32(q, 32, h->error_resilient_mode);
  F32(q, 36, h->disable_cdf_update);
  F32(q, 40, h->allow_screen_content_tools);
  F32(q, 44, h->force_integer_mv);
  F32(q, 48, h->current_frame_id);
  F32(q, 52, h->frame_size_override_flag);
  F32(q, 64, h->order_hint);
  F32(q, 100, h->primary_ref_frame);
  F32(q, 236, h->refresh_frame_flags);
  F32(q, 304, h->frame_width_minus_1);
  F32(q, 308, h->frame_height_minus_1);
  F32(q, 312, h->FrameWidth);
  F32(q, 320, h->FrameHeight);
  F32(q, 324, h->UpscaledWidth);
  F32(q, 328, h->use_superres);
  F32(q, 332, h->SuperresDenom);
  F32(q, 364, h->allow_intrabc);
  F32(q, 440, h->allow_high_precision_mv);
  F32(q, 448, h->interpolation_filter);
  F32(q, 452, h->is_motion_mode_switchable);
  F32(q, 456, h->use_ref_frame_mvs);
  F32(q, 460, h->disable_frame_end_update_cdf);
  F32(q, 464, h->uniform_tile_spacing_flag);
  F32(q, 468, h->TileColsLog2);
  F32(q, 472, h->TileRowsLog2);
  for (int i = 0; i <= h->TileCols && i <= 64; i++)
    F32(q, 484 + 4 * i, h->MiColStarts[i]);
  for (int i = 0; i <= h->TileRows && i <= 64; i++)
    F32(q, 744 + 4 * i, h->MiRowStarts[i]);
  F32(q, 1004, h->TileCols);
  F32(q, 1008, h->TileRows);
  F32(q, 1020, h->context_update_tile_id);
  F32(q, 1024, h->TileSizeBytes);
  F32(q, 1032, h->base_q_idx);
  F32(q, 1044, h->DeltaQYDc);
  F32(q, 1048, h->diff_uv_delta);
  F32(q, 1052, h->DeltaQUDc);
  F32(q, 1056, h->DeltaQUAc);
  F32(q, 1060, h->DeltaQVDc);
  F32(q, 1064, h->DeltaQVAc);
  F32(q, 1068, h->using_qmatrix);
  F32(q, 1072, h->qm_y);
  F32(q, 1076, h->qm_u);
  F32(q, 1080, h->qm_v);
  F32(q, 1084, h->segmentation_enabled);
  F32(q, 1088, h->segmentation_update_map);
  F32(q, 1092, h->segmentation_temporal_update);
  F32(q, 1096, h->segmentation_update_data);
  for (int i = 0; i < 8; i++)
    for (int j = 0; j < 8; j++) {
      F32(q, 1104 + 32 * i + 4 * j, h->FeatureEnabled[i][j]);
      *(int16_t*)(q + 1364 + 16 * i + 2 * j) = (int16_t)h->FeatureData[i][j];
    }
  F32(q, 1500, h->delta_q_present);
  F32(q, 1504, h->delta_q_res);
  F32(q, 1508, h->delta_lf_present);
  F32(q, 1512, h->delta_lf_res);
  F32(q, 1516, h->delta_lf_multi);
  for (int i = 0; i < 4; i++) F32(q, 1656 + 4 * i, h->loop_filter_level[i]);
  F32(q, 1672, h->loop_filter_sharpness);
  F32(q, 1676, h->loop_filter_delta_enabled);
  F32(q, 1680, h->loop_filter_delta_update);
  for (int i = 0; i < 8; i++)
    F32(q, 1688 + 4 * i, h->loop_filter_ref_deltas[i]);
  F32(q, 1724, h->loop_filter_mode_deltas[0]);
  F32(q, 1728, h->loop_filter_mode_deltas[1]);
  F32(q, 1736, h->cdef_bits);
  for (int i = 0; i < 8; i++) {
    // driver computes (f[1772]<<6)|f[1740]; give it the VCN-ready (pri<<2)|sec
    // value
    F32(q, 1740 + 4 * i, (h->cdef_y_pri[i] << 2) | (h->cdef_y_sec[i] & 3));
    F32(q, 1772 + 4 * i, 0);
    F32(q, 1804 + 4 * i, (h->cdef_uv_pri[i] << 2) | (h->cdef_uv_sec[i] & 3));
    F32(q, 1836 + 4 * i, 0);
  }
  F32(q, 1868, h->CdefDamping);
  for (int i = 0; i < 3; i++) {
    F32(q, 1872 + 4 * i, h->FrameRestorationType[i]);
    F32(q, 1900 + 4 * i, h->LoopRestorationSize[i]);
  }
  F32(q, 1920, h->TxMode);
  F32(q, 1924, h->reference_select);
  F32(q, 1936, h->skip_mode_present);
  F32(q, 1940, h->allow_warped_motion);
  F32(q, 1944, h->reduced_tx_set);
  for (int ref = 1; ref <= 7; ref++) {
    F32(q, 1952 + 4 * (ref - 1), h->gm_type[ref]);
    for (int j = 0; j < 6; j++)
      F32(q, 2004 + 24 * (ref - 1) + 4 * j, h->gm_params[ref][j]);
  }
  const AV1FilmGrain* g = &h->film_grain;
  F32(q, 2376, g->apply_grain);
  F32(q, 2380, g->grain_seed);
  F32(q, 2384, g->update_grain);
  F32(q, 2388, g->film_grain_params_ref_idx);
  F32(q, 2392, g->num_y_points);
  for (int i = 0; i < 14; i++) {
    F32(q, 2396 + 4 * i, g->point_y_value[i]);
    F32(q, 2452 + 4 * i, g->point_y_scaling[i]);
  }
  F32(q, 2508, g->chroma_scaling_from_luma);
  F32(q, 2512, g->num_cb_points);
  F32(q, 2516, g->num_cr_points);
  for (int i = 0; i < 10; i++) {
    F32(q, 2520 + 4 * i, g->point_cb_value[i]);
    F32(q, 2560 + 4 * i, g->point_cb_scaling[i]);
    F32(q, 2600 + 4 * i, g->point_cr_value[i]);
    F32(q, 2640 + 4 * i, g->point_cr_scaling[i]);
  }
  F32(q, 2680, g->grain_scaling_minus_8);
  F32(q, 2684, g->ar_coeff_lag);
  for (int i = 0; i < 24; i++) F32(q, 2688 + 4 * i, g->ar_coeffs_y_plus_128[i]);
  for (int i = 0; i < 25; i++) {
    F32(q, 2784 + 4 * i, g->ar_coeffs_cb_plus_128[i]);
    F32(q, 2884 + 4 * i, g->ar_coeffs_cr_plus_128[i]);
  }
  F32(q, 2984, g->ar_coeff_shift_minus_6);
  F32(q, 2988, g->grain_scale_shift);
  F32(q, 2992, g->cb_mult);
  F32(q, 2996, g->cb_luma_mult);
  F32(q, 3000, g->cb_offset);
  F32(q, 3004, g->cr_mult);
  F32(q, 3008, g->cr_luma_mult);
  F32(q, 3012, g->cr_offset);
  F32(q, 3016, g->overlap_flag);
  F32(q, 3020, g->clip_to_restricted_range);
}

static int alloc_dpb_slot(VcnAV1* d) {
  for (int i = 0; i < NUM_DPB; i++)
    if (d->dpbRefs[i] == 0) return i;
  return -1;
}

static void release_slot_refs(VcnAV1* d) {
  memset(d->dpbRefs, 0, sizeof(d->dpbRefs));
  for (int i = 0; i < 8; i++) {
    int s = d->parser.ref[i].dpb_slot;
    if (s >= 0 && d->parser.ref[i].valid) d->dpbRefs[s]++;
  }
}

// The dry-run lldb script breaks here and verifies its kernel-submission trap
// is armed.
__attribute__((noinline)) void vcnav1_dryrun_checkpoint(const AV1Params* prm) {
  __asm__ volatile("" ::"r"(prm) : "memory");
}
static double tnow_ms(void) {
  static mach_timebase_info_data_t tb;
  if (!tb.denom) mach_timebase_info(&tb);
  return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}
static int timing = -1;
// Sends one frame and waits for it. *sched and *wait get the time spent in
// ScheduleAVDCommands and in the wait, for VCNAV1_TIMING.
static int submit(VcnAV1* d, AV1Params* prm, double* sched, double* wait) {
  *sched = *wait = 0;
  const char* arm = getenv("VCNAV1_ALLOW_GPU");
  if (!__atomic_load_n(&vcnav1_gpu_armed, __ATOMIC_RELAXED) &&
      (!arm || strcmp(arm, "yes-i-know-it-can-hang"))) {
    snprintf(d->err, sizeof(d->err),
             "GPU submission disabled (set VCNAV1_ALLOW_GPU)");
    d->failure = VCNAV1_FAIL_DEVICE;
    return -1;
  }
  vcnav1_dryrun_checkpoint(prm);
  AVD_CmdInfo cmd = {.kind = 1,
                     .function = AVD_FUNC_AV1,
                     .mode = VCN_MODE_VCN0,
                     .context = d->s.ctx,
                     .params = prm};
  AVD_CmdInfo* cmds[1] = {&cmd};
  AVD_CmdList list = {.count = 1, .cmds = cmds};
  void* refcons[1] = {0};
  AVD_RefConList rl = {.count = 1, .refcons = refcons};
  double t0 = tnow_ms();
  int r = FN(ScheduleAVDCommands)(d->s.drv, &list, &rl);
  double t1 = tnow_ms();
  // A driver call that fails leaves the session in a state nothing has
  // checked: no more commands go out, and VideoToolbox is told the decoder
  // broke, not that the stream is bad, so it can use another one.
  d->failure = VCNAV1_FAIL_DEVICE;
  if (r) {
    d->broken = true;
    snprintf(d->err, sizeof(d->err), "ScheduleAVDCommands %d", r);
    return -1;
  }
  uint32_t fw = 0;
  int ds = 0;
  // Longer on the session from before a sleep, and until one command on the
  // rebuilt one has finished: right after a wake the driver can take seconds
  // before a command runs (vcndriver.h).
  unsigned limit = d->rebuildAtKey || d->wakeGrace ? vcn_wake_command_timeout_ms
                                                   : VCN_COMMAND_TIMEOUT_MS;
  VcnWaitResult w = vcn_wait_command(FN(QueryAVDCommandStatus), d->s.drv,
                                     refcons[0], limit, &fw, &ds);
  *sched = t1 - t0;
  *wait = tnow_ms() - t1;
  DBG("wait=%d firmware=%u driver=%d\n", (int)w, fw, ds);
  if (w == VCN_WAIT_TIMEOUT) {
    // The GPU still holds this command. Sending more work, or reading the
    // target, could only make things worse: the session stops here.
    d->stuck = d->broken = true;
    // Unless the system slept inside this call. The timeout is measured on a
    // clock that stops while the machine is asleep, so the frame that was on
    // the GPU when it slept times out right after the wake, and nothing looked
    // again at the sleep: 0.3.7 stopped the session there instead of rebuilding
    // it, which is the one thing 0.3.7 exists to avoid.
    if (!d->rebuildAtKey && vcn_session_lost(&d->s)) {
      d->rebuildAtKey = true;
      d->keptAfterWake = 0;
      os_log_error(vlog(),
                   "the system slept while a frame was on the GPU: the frame "
                   "was given up on after the wake, the session is rebuilt");
      snprintf(d->err, sizeof(d->err),
               "the GPU did not finish the frame in %u ms after the sleep",
               limit);
      return -1;
    }
    snprintf(d->err, sizeof(d->err),
             "the GPU did not finish a frame in %u ms; session stopped", limit);
    return -1;
  }
  if (w != VCN_WAIT_DONE) {
    // The command went out and may still be on the GPU: closing the session
    // can wait for it, as after a timeout.
    d->stuck = d->broken = true;
    snprintf(d->err, sizeof(d->err), "QueryAVDCommandStatus %d", ds);
    return -1;
  }
  d->failure = VCNAV1_FAIL_STREAM;
  d->done++;
  d->lastFw = fw;
  // One command finished on the rebuilt session: the engine came back, and the
  // usual limit applies again.
  d->wakeGrace = false;
  // Counted, not refused: what each firmware result means for the picture
  // has not been checked on a GPU yet. The first one of a session is logged
  // at once, the count goes in the stats line.
  if (fw && !d->fwErrors++)
    os_log_error(vlog(),
                 "firmware result %u (0x%x) for decode %u of this session; "
                 "later ones are counted in the stats line",
                 fw, fw, d->done);
  return 0;
}

// What the engine decodes: profile 0, 8 or 10 bits, 4:2:0 in colour.
static bool seq_supported(const AV1Seq* s) {
  return s->seq_profile == 0 && (s->BitDepth == 8 || s->BitDepth == 10) &&
         !s->mono_chrome && s->subsampling_x == 1 && s->subsampling_y == 1;
}

static int decode_one(void* vctx, AV1Parser* p, AV1ParseResult kind) {
  VcnAV1* d = vctx;
  const AV1Frame* h = &p->fh;
  // A frame nothing decoded before it is used after: a key frame that
  // refreshes all eight slots (vcnav1_is_restart). A hidden key frame that
  // keeps some slots is not one: the frames after it may still use those.
  bool restart = vcnav1_is_restart(h, kind);
  // The system slept since the driver side opened, and it kept decoding (a
  // real sleep on this Mac did not break it): it is replaced at the first such
  // frame, which then decodes on the new one.
  if (d->rebuildAtKey && restart && !rebuild_now(d, false, NULL)) return -1;
  // After a rebuild that followed a failure nothing from before it can be
  // used: every frame but such a key frame is dropped (no picture for this
  // sample, which is what a hidden frame looks like to the host, not an
  // error), and the key frame starts the decoder again. Bounded: a stream that
  // never sends one is stopped as a device failure, PR 160's behaviour.
  if (d->needKey) {
    if (!restart) {
      if (++d->dropped > REBUILD_MAX_DROPPED) {
        d->broken = true;
        d->failure = VCNAV1_FAIL_DEVICE;
        snprintf(d->err, sizeof(d->err),
                 "no key frame in %u frames after the system sleep",
                 d->dropped);
        return -1;
      }
      return 0;
    }
    vcnav1_flush(d);
    d->needKey = false;
    d->dropped = 0;
  }
  if (kind == AV1_PARSE_SHOW_EXISTING) {
    AV1RefSlot* r = &p->ref[h->frame_to_show_map_idx];
    if (!r->valid || r->dpb_slot < 0 || r->dpb_slot >= NUM_DPB ||
        !d->dpb[r->dpb_slot]) {
      snprintf(d->err, sizeof(d->err), "show_existing of a missing reference");
      d->failure = VCNAV1_FAIL_REFERENCE;
      return -1;
    }
    d->shown = true;
    if (d->out) d->out(d->outCtx, d->dpb[r->dpb_slot], p, d->tag);
    if (h->frame_type == AV1_KEY_FRAME) {
      av1_reference_update(p, r->dpb_slot);
      release_slot_refs(d);
    }
    return 0;
  }
  // A sequence header inside the stream can ask for more than av1C said.
  if (!seq_supported(&p->seq)) {
    snprintf(d->err, sizeof(d->err),
             "profile %d, %d bits, mono %d, subsampling %d%d not supported",
             p->seq.seq_profile, p->seq.BitDepth, p->seq.mono_chrome,
             p->seq.subsampling_x, p->seq.subsampling_y);
    return -1;
  }
  if (timing < 0) timing = getenv("VCNAV1_TIMING") != NULL;
  double tf0 = timing ? tnow_ms() : 0;
  bool tenBit = p->seq.BitDepth > 8;
  uint32_t w = h->UpscaledWidth, hh = h->FrameHeight;
  // 5.9.2: every reference of an inter frame must hold a decoded picture. A
  // reference without one would make the engine read the slot it writes.
  if (!h->FrameIsIntra)
    for (int i = 0; i < 7; i++) {
      const AV1RefSlot* r = &p->ref[h->ref_frame_idx[i]];
      if (!r->valid || r->dpb_slot < 0 || r->dpb_slot >= NUM_DPB ||
          !d->dpb[r->dpb_slot]) {
        snprintf(d->err, sizeof(d->err), "missing reference");
        d->failure = VCNAV1_FAIL_REFERENCE;
        return -1;
      }
    }
  if (w > d->maxW || hh > d->maxH) {
    snprintf(d->err, sizeof(d->err), "%ux%u is over the session maximum", w,
             hh);
    return -1;
  }
  // Refuse what does not fit before a DPB slot or bitstream buffer is taken.
  if (p->tile_data_size > BS_SIZE - 256) {
    snprintf(d->err, sizeof(d->err), "frame too big");
    return -1;
  }
  for (int i = 0; i < p->num_tiles; i++) {
    const AV1Tile* t = &p->tiles[i];
    if (t->row < 0 || t->row >= 64 || t->col < 0 || t->col >= 64) {
      snprintf(d->err, sizeof(d->err), "tile index out of range");
      return -1;
    }
  }
  int slot = alloc_dpb_slot(d);
  if (slot < 0) {
    snprintf(d->err, sizeof(d->err), "no free DPB slot");
    return -1;
  }
  // Fresh decode target per picture: the consumer may still hold earlier ones.
  CVPixelBufferRef target = new_target(d, w, hh, tenBit);
  if (!target) {
    snprintf(d->err, sizeof(d->err), "no pixel buffer for %ux%u", w, hh);
    d->failure = VCNAV1_FAIL_MEMORY;
    return -1;
  }
  if (d->dpb[slot]) CVPixelBufferRelease(d->dpb[slot]);
  d->dpb[slot] = target;
  pack_seq(d);
  pack_frame(d);
  // bitstream: concatenated tile data
  int bi = d->bsNext;
  d->bsNext = (d->bsNext + 1) % NUM_BS;
  memcpy(d->s.bsAddr[bi], p->tile_data, p->tile_data_size);
  memset((uint8_t*)d->s.bsAddr[bi] + p->tile_data_size, 0, 256);
  memset(d->bsinfo, 0, BSINFO_BYTES);
  *(uint32_t*)(d->bsinfo + 0) = bi;
  *(uint32_t*)(d->bsinfo + 16) = (uint32_t)((p->tile_data_size + 127) & ~127u);
  for (int i = 0; i < p->num_tiles; i++) {
    const AV1Tile* t = &p->tiles[i];
    uint32_t* e = (uint32_t*)(d->bsinfo + 20 + 512 * t->row + 8 * t->col);
    e[0] = t->offset;
    e[1] = t->size;
  }
  AV1Params prm;
  memset(&prm, 0, sizeof(prm));
  prm.seq = d->seq;
  prm.frame = d->frame;
  prm.curr_pic_idx = slot;
  prm.output = CVPixelBufferGetIOSurface(d->dpb[slot]);
  if (!prm.output) {
    snprintf(d->err, sizeof(d->err), "pixel buffer without an IOSurface");
    d->failure = VCNAV1_FAIL_MEMORY;
    return -1;
  }
  // A reference slot the header emptied keeps its old DPB index, which may be
  // the slot this frame is decoded into: give the driver no index for it.
  for (int i = 0; i < 8; i++)
    prm.ref_frame_map[i] = p->ref[i].valid && p->ref[i].dpb_slot >= 0
                               ? (uint32_t)p->ref[i].dpb_slot
                               : 0x7f;
  for (int i = 0; i < 7; i++) {
    int s = h->FrameIsIntra ? -1 : p->ref[h->ref_frame_idx[i]].dpb_slot;
    prm.frame_refs[i] = s >= 0 ? s : 0x7f;
  }
  prm.bsinfo = d->bsinfo;
  DBG("frame type=%d show=%d %dx%d q=%d tiles=%dx%d bytes=%zu slot=%d "
      "refresh=%02x\n",
      h->frame_type, h->show_frame, w, hh, h->base_q_idx, h->TileCols,
      h->TileRows, p->tile_data_size, slot, h->refresh_frame_flags);
  double tf1 = timing ? tnow_ms() : 0;
  double tSched, tWait;
  if (submit(d, &prm, &tSched, &tWait))
    // On the session from before a sleep, a driver failure is taken for the
    // sleep's doing: rebuilt at once, instead of stopping the session.
    return d->rebuildAtKey && d->broken ? failed_after_wake(d) : -1;
  if (d->rebuildAtKey) {
    if (d->lastFw) {
      // A firmware error on it after the wake: its picture is not trusted.
      snprintf(d->err, sizeof(d->err), "firmware result %u", d->lastFw);
      return failed_after_wake(d);
    }
    d->keptAfterWake++;
  }
  if (timing)
    fprintf(stderr, "timing bytes=%zu prep=%.2f sched=%.2f wait=%.2f\n",
            p->tile_data_size, tf1 - tf0, tSched, tWait);
  av1_reference_update(p, slot);
  release_slot_refs(d);
  if (h->show_frame) {
    d->shown = true;
    if (d->out) d->out(d->outCtx, d->dpb[slot], p, d->tag);
  } else {
    if (d->hidden) CVPixelBufferRelease(d->hidden);
    d->hidden = CVPixelBufferRetain(d->dpb[slot]);
  }
  return 0;
}

// configOBUs hold the sequence header and metadata only, never a frame.
static int config_no_frames(void* vctx, AV1Parser* p, AV1ParseResult kind) {
  (void)p;
  (void)kind;
  VcnAV1* d = vctx;
  snprintf(d->err, sizeof(d->err), "a frame in the configOBUs");
  return -1;
}

int vcnav1_configure(VcnAV1* d, const uint8_t* obus, size_t size) {
  d->err[0] = 0;
  d->failure = VCNAV1_FAIL_STREAM;
  if (av1_parse_temporal_unit(&d->parser, obus, size, config_no_frames, d)) {
    if (!d->err[0]) snprintf(d->err, sizeof(d->err), "unreadable configOBUs");
    return -1;
  }
  if (d->parser.seq.valid && !seq_supported(&d->parser.seq)) {
    snprintf(d->err, sizeof(d->err),
             "sequence header: profile %d, %d bits, mono %d not supported",
             d->parser.seq.seq_profile, d->parser.seq.BitDepth,
             d->parser.seq.mono_chrome);
    return VCNAV1_UNSUPPORTED;
  }
  return 0;
}

// A frame that was not decoded leaves the reference slots it should have
// refreshed holding older pictures. Frames that predict from them would decode
// without an error and show a wrong picture, so those slots are emptied: the
// frames that read them are refused ("missing reference") until a frame
// refreshes them again, which is how libaom treats a frame it could not decode.
static int on_frame(void* vctx, AV1Parser* p, AV1ParseResult kind) {
  int r = decode_one(vctx, p, kind);
  if (r && kind == AV1_PARSE_FRAME_READY) {
    for (int i = 0; i < 8; i++)
      if (p->fh.refresh_frame_flags & (1u << i)) p->ref[i].valid = 0;
    release_slot_refs((VcnAV1*)vctx);
  }
  return r;
}

int vcnav1_decode(VcnAV1* d, const uint8_t* tu, size_t size, int64_t userTag,
                  VcnAV1OutputFn fn, void* ctx) {
  d->out = fn;
  d->outCtx = ctx;
  d->tag = userTag;
  d->err[0] = 0;
  d->failure = VCNAV1_FAIL_STREAM;
  d->shown = false;
  if (d->hidden) {
    CVPixelBufferRelease(d->hidden);
    d->hidden = NULL;
  }
  // A sleep since the driver side opened: it keeps decoding, and on_frame
  // rebuilds it at the next key frame (or at once if it fails).
  if (!d->broken && !d->rebuildAtKey && vcn_session_lost(&d->s)) {
    d->rebuildAtKey = true;
    d->keptAfterWake = 0;
    os_log_error(vlog(),
                 "AV1 session from before the sleep: it keeps decoding and is "
                 "rebuilt at the next key frame");
  }
  if (d->broken) {
    snprintf(d->err, sizeof(d->err), "session stopped: %s",
             d->stuck ? "the GPU did not finish an earlier frame"
                      : "an earlier driver call failed");
    d->failure = VCNAV1_FAIL_DEVICE;
    return -1;
  }
  int r = av1_parse_temporal_unit(&d->parser, tu, size, on_frame, d);
  if (r && !d->err[0])
    snprintf(d->err, sizeof(d->err), "bitstream parse error");
  return r;
}

void vcnav1_flush(VcnAV1* d) {
  for (int i = 0; i < 8; i++) {
    d->parser.ref[i].valid = 0;
    d->parser.ref[i].dpb_slot = -1;
  }
  memset(d->dpbRefs, 0, sizeof(d->dpbRefs));
}

#ifdef VCN_DRYRUN_TOOLS  // Used by tools/dryrun.py: copy (possibly GPU-mapped)
                         // memory to a file from
// inside the process.
__attribute__((noinline, used)) int vcnav1_dump(const void* p, long n,
                                                const char* path) {
  // Refuse odd sizes and anything but plain path characters.
  if (!p || !path || n <= 0 || n > 64 * 1024 * 1024) return -1;
  for (const unsigned char* c = (const unsigned char*)path; *c; c++) {
    if (*c < 0x20 || *c == 0x7f) return -1;
    if (!((*c >= 'A' && *c <= 'Z') || (*c >= 'a' && *c <= 'z') ||
          (*c >= '0' && *c <= '9') || *c == '.' || *c == '_' || *c == '/' ||
          *c == '-'))
      return -1;
  }
  if (strstr(path, "..")) return -1;
  FILE* f = fopen(path, "wb");
  if (!f) return -1;
  long w = (long)fwrite(p, 1, (size_t)n, f);
  fclose(f);
  return (int)w;
}
#endif  // VCN_DRYRUN_TOOLS
