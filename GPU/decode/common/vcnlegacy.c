#include "vcnlegacy.h"

#include <IOKit/IOKitLib.h>
#include <IOSurface/IOSurfaceRef.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <os/log.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "avd.h"
#include "vcndriver.h"

int vcnlegacy_debug = 0;
int vcnlegacy_gpu_armed = 0;
int vcnlegacy_db_height_mode = 0;
int vcnlegacy_clear_dpb = 0;
int vcnlegacy_field_layout = 0;
int vcnlegacy_bottom_mode = 0;
int vcnlegacy_fill_target = 0;
#define DBG(...)                                                      \
  do {                                                                \
    if (vcnlegacy_debug) fprintf(stderr, "[vcnlegacy] " __VA_ARGS__); \
  } while (0)

#define VCN_MODE_VCN0 4  // the AV1 context only works on VCN0
#define FRAME_BYTES 4096
#define SEQ_BYTES 2048
#define BSINFO_BYTES (20 + 64 * 512 + 64)
#define MSG_MAX 1024
// Mesa's RDECODE_SESSION_CONTEXT_SIZE: what sw_ctxt_size always says.
#define SW_CTXT_SIZE (128u * 1024)
// The driver's AV1 path allocates a context buffer whatever the codec. These
// codecs have no hardware context (Mesa: hw_ctx_size 0), so it is small, never
// sent and never read.
#define UNUSED_CTX_BYTES 65536u
#define NUM_PICTURES 6  // Mesa's NUM_MPEG2_REFS; VC-1 and MPEG-4 need fewer

// Parameter block of the driver's AV1 path (see vp9/vcnvp9.c). The driver
// reads output, bsinfo and the frame size; the rest is for the message
// builder, which here is ours.
typedef struct {
  void* seq;              // +0
  void* frame;            // +8   driver reads +312 width, +320 height
  uint32_t curr_pic_idx;  // +16
  uint32_t pad0;
  IOSurfaceRef output;        // +24
  uint32_t ref_frame_map[8];  // +32
  uint32_t frame_refs[7];     // +64
  uint32_t pad1;              // +92
  void* bsinfo;               // +96  driver reads +0 buffer index, +16 size
  VcnLegacy* session;         // +104 ours
  uint8_t reserved[152];
} LegacyParams;

struct VcnLegacy {
  VcnDriverSession s;  // accelerator, driver, context and bitstream pool
  VcnLegacyConfig cfg;
  uint32_t dpbSize;
  int bsNext;
  uint8_t *seq, *frame, *bsinfo;
  char err[256];
  CVPixelBufferPoolRef pool;
  os_log_t log;
  bool stuck;   // a command never finished: the GPU may still hold it
  bool broken;  // stuck, or a driver call failed: nothing more goes out
  int failure;
  unsigned fwErrors, done;
  uint8_t* proc;  // the driver's processor object of this session
  // The picture being decoded, for the message hook.
  const void* block;
  uint32_t blockSize;
  // The feedback buffer the driver attached to the running command.
  uint8_t* fb;
  bool haveStatus, executed;
  uint32_t status;
  uint8_t fb_copy[44];  // the feedback words of the last command
  uint8_t* dpbSeen;     // the DPB texture of the last message (debug log)
  uint8_t* dpbCpu;      // and its CPU address and size (vcnlegacy_fill_target)
  uint32_t dpbBytes;
};

#define FN(name) ((AVD_##name##_fn)d->s.accel->fn[AVD_FN_##name])

static bool mapped(const void* p, size_t n, vm_prot_t prot);

// The one driver build this path was read and run on. The feedback buffer
// offsets and the ring command the context buffer turns into were read in this
// build only; the three codecs decoded on the GPU with it (2026-11-23).
static const char* const kValidatedDrivers[] = {
    "1181E2CA31B33DF090E23AE70552D753",  // macOS 26.7.2 (25G332) and 26.7.3
                                         // (25G342, same binary)
    "F7D8F5849EC139DB857C769697294957",  // macOS 26.7.4 (25G422): same code
                                         // as 26.7.3 (2760/2760 functions
                                         // identical, only a build path)
};

// ---------------------------------------------------------------------------
// Driver object layout, as in vp9/vcnvp9.c.
#define U32(p, off) (*(uint32_t*)((uint8_t*)(p) + (off)))
#define PTR(p, off) (*(uint8_t**)((uint8_t*)(p) + (off)))
#define PROC_DECODER(proc) PTR(proc, 16)
#define PROC_VACONTEXT(proc) PTR(proc, 24)
#define PROC_FEEDBACK(proc) U32(proc, 32)
#define PROC_DEPTH(proc) U32(proc, 64)
#define DEC_DATA(dec) PTR(dec, 88)
#define DEC_WIDTH(dec) U32(dec, 124)
#define DEC_HEIGHT(dec) U32(dec, 128)
#define DATA_REALLOC(data) (*((uint8_t*)(data) + 12))
#define DATA_TUPLE(data) ((uint8_t*)(data) + 16)
#define DATA_DPB_SIZE(data) U32(data, 48)
#define DATA_DPB_TEX(data) PTR(data, 56)
#define DATA_MSG_TEX(data) PTR(data, 8 * (uint64_t)U32(data, 216) + 152)
#define DATA_MSG(data) PTR(data, 224)
#define DATA_CTX_SIZE(data) U32(data, 456)
#define DATA_CTX_TEX(data) PTR(data, 464)
#define DATA_SESSION_TEX(data) PTR(data, 480)
#define DATA_BS_SIZE(data) U32(data, 688)
// DecodeDataProcessor::SetDecodeFeedbackFields (25G342, 0x7ffb10b1596e) keeps
// the CPU address of the feedback buffer it attaches here. It moves on to the
// next buffer after the submission, so the hook keeps its own copy.
#define DATA_FEEDBACK(data) PTR(data, 0x170)
#define TEX_CPU(tex) PTR(tex, 152)
#define TEX_HEIGHT(tex) U32(tex, 124)
#define TEX_PITCH(tex) U32(tex, 128)
#define TEX_BPE(tex) U32(tex, 132)
#define HWCONFIG(ctx) PTR(ctx, 1120)
#define BI_MSG_ON 4
#define BI_MSG 8
#define BI_DPB_ON 16
#define BI_DPB 24
#define BI_TARGET_ON 112
#define BI_TARGET 120
#define BI_TARGET_OFF 128
#define BI_CTX_ON 160
#define BI_SESSION_ON 176
#define BI_SESSION 184
// Virtual slots of AvdVcnAv1DecDataProcessor, in pointers.
enum {
  VT_CREATE_SESSION = 2,
  VT_DPB_SIZE = 8,
  VT_CTX_SIZE = 9,
  VT_INIT_CTX = 12,
  VT_SET_MESSAGE = 14,
  VT_SET_FEEDBACK = 15,
  VT_SLOTS = 16
};
#define FACTORY_CREATE_PROCESSOR 4  // VAFactory::createDecodeDataProcessor
#define FACTORY_SLOTS 32
#define AV1_PROCESSOR_TYPE 6

static uint32_t al(uint32_t v, uint32_t a) { return (v + a - 1) & ~(a - 1); }

uint32_t vcnlegacy_dpb_size(uint32_t codecId, uint32_t width, uint32_t height) {
  uint64_t size =
      (uint64_t)al(width, 64) * al(height, 64) * 3 / 2 * NUM_PICTURES + 65536;
  uint64_t wmb = al(width, 16) / 16, hmb = al(height, 16) / 16;
  if (codecId == VCN_CODEC_VC1) {
    // context, IT surface, deblocking surface, bit planes
    size += wmb * hmb * 128 + wmb * 64 + wmb * 128;
    size += al((uint32_t)((wmb > hmb ? wmb : hmb) * 7 * 16), 64);
  } else if (codecId == VCN_CODEC_MPEG4) {
    size += wmb * hmb * 64 + al((uint32_t)(wmb * hmb * 32), 64);
    if (size < 30u * 1024 * 1024) size = 30u * 1024 * 1024;
  }
  return size > UINT32_MAX ? 0 : (uint32_t)size;
}

// The message of the probe's variant 15, the one the three codecs decoded
// with on the GPU: Mesa's header, index and context sizes, and the target
// geometry Apple's own AV1 builder writes for its linear surfaces.
//
// What a run of one intra picture per change showed (2026-11-23, RX 6800 XT,
// macOS 26.7.3): the picture comes out the same with Apple's four index
// entries (DRM and 0x0f blocks) in place of Mesa's two, with sw_ctxt_size 0,
// and with Mesa's db_pitch (32-aligned) and bottom offsets 0. So the only
// thing the firmware insists on is the missing context-buffer command (see
// hook_set_message); the rest is kept as Mesa sends it because that is the
// layout every multi-picture run was made with.
uint32_t vcnlegacy_build_message(uint8_t* msg, size_t cap,
                                 const VcnLegacyMessage* m) {
  const uint32_t decodeOff = 24 + 16 * 2, decodeSize = 188;
  const uint32_t codecOff = decodeOff + decodeSize;
  if (!m->block || !m->blockSize || m->blockSize > MSG_MAX) return 0;
  const uint32_t total = codecOff + m->blockSize;
  if (total > cap) return 0;
  const uint32_t w = m->width, h = m->height, pitch = m->pitch,
                 texh = m->texHeight;
  const uint32_t bpe = m->bytesPerElement ? m->bytesPerElement : 1;
  if (!w || !h || !pitch || !texh) return 0;
  if (((uint64_t)3 * pitch * texh) >> 1 > UINT32_MAX ||
      (uint64_t)pitch * al(texh, 16) + (((uint64_t)pitch * h) >> 1) - 1 >
          UINT32_MAX)
    return 0;
  memset(msg, 0, total);
  U32(msg, 0) = 40;  // header size
  U32(msg, 4) = total;
  U32(msg, 8) = 2;   // index entries
  U32(msg, 12) = 1;  // RDECODE_MSG_DECODE
  U32(msg, 16) = m->streamHandle;
  U32(msg, 20) = m->feedbackNumber;
  U32(msg, 24) = 2;  // RDECODE_MESSAGE_DECODE
  U32(msg, 28) = decodeOff;
  U32(msg, 32) = decodeSize;
  U32(msg, 40) = m->messageId;
  U32(msg, 44) = codecOff;
  U32(msg, 48) = m->blockSize;

  uint8_t* d = msg + decodeOff;
  const uint32_t a = w <= 32 ? 32 : 64;
  U32(d, 0) = m->codecId;
  // db_pitch and db_aligned_height below come out the same from either size.
  U32(d, 8) = m->sizeInMacroblocks ? (w + 15) / 16
              : m->alignSizeTo16   ? al(w, 16)
                                   : w;
  U32(d, 12) = m->sizeInMacroblocks ? (h + 15) / 16
               : m->alignSizeTo16   ? al(h, 16)
                                    : h;
  U32(d, 16) = m->bitstreamSize;
  U32(d, 20) = m->dpbSize;
  U32(d, 24) = (uint32_t)(((uint64_t)3 * pitch * texh) >> 1);
  U32(d, 36) = 0;  // hw_ctxt_size: these codecs have no context buffer
  U32(d, 40) = SW_CTXT_SIZE;
  U32(d, 72) = al(w, a);                         // db_pitch
  U32(d, 76) = m->dbHeightZero ? 0 : al(h, 64);  // db_aligned_height
  U32(d, 100) = pitch / bpe;
  U32(d, 104) = (pitch / bpe) >> 1;
  U32(d, 140) = (uint32_t)((uint64_t)pitch * h - 1);
  U32(d, 144) = (uint32_t)((uint64_t)pitch * al(texh, 16));
  U32(d, 148) = (uint32_t)((uint64_t)pitch * al(texh, 16) +
                           (((uint64_t)pitch * h) >> 1) - 1);
  if (!m->fieldLayout && m->bottomMode == 1) {
    U32(d, 140) = 0;
    U32(d, 148) = 0;
  } else if (!m->fieldLayout && m->bottomMode == 2) {
    U32(d, 140) = U32(d, 136);
    U32(d, 148) = U32(d, 144);
  }
  if (m->fieldLayout) {
    // Each field as a plane of its own inside the interleaved frame: twice
    // the pitch, the bottom field one line further.
    U32(d, 92) = 1;   // db_field_mode
    U32(d, 120) = 1;  // dt_field_mode
    U32(d, 100) = 2 * pitch / bpe;
    U32(d, 104) = pitch / bpe;
    U32(d, 140) = pitch;                // dt_luma_bottom_offset
    U32(d, 148) = U32(d, 144) + pitch;  // dt_chroma_bottom_offset
  }
  U32(d, 160) = 1;  // mif_wrc_en
  U32(d, 164) = al(w / 2, a);
  memcpy(msg + codecOff, m->block, m->blockSize);
  return total;
}

// ---------------------------------------------------------------------------
// The hooks are shared by every session of the process; which session a
// processor object belongs to is looked up here.
enum { MAX_SESSIONS = 32 };
static struct {
  uint8_t* proc;
  VcnLegacy* d;
} g_reg[MAX_SESSIONS];
static pthread_mutex_t g_reg_lock = PTHREAD_MUTEX_INITIALIZER;
static __thread VcnLegacy* t_creating;

static bool reg_add(uint8_t* proc, VcnLegacy* d) {
  bool ok = false;
  pthread_mutex_lock(&g_reg_lock);
  // The driver may hand out the address of a processor it freed while that
  // session's own entry is still here: the new owner takes the entry over.
  for (int i = 0; i < MAX_SESSIONS && !ok; i++)
    if (g_reg[i].proc == proc) {
      g_reg[i].d = d;
      ok = true;
    }
  for (int i = 0; i < MAX_SESSIONS && !ok; i++)
    if (!g_reg[i].proc) {
      g_reg[i].proc = proc;
      g_reg[i].d = d;
      ok = true;
    }
  pthread_mutex_unlock(&g_reg_lock);
  return ok;
}
static void reg_remove(VcnLegacy* d) {
  pthread_mutex_lock(&g_reg_lock);
  for (int i = 0; i < MAX_SESSIONS; i++)
    if (g_reg[i].d == d) g_reg[i].proc = NULL, g_reg[i].d = NULL;
  pthread_mutex_unlock(&g_reg_lock);
}
static VcnLegacy* reg_find(uint8_t* proc) {
  VcnLegacy* d = NULL;
  pthread_mutex_lock(&g_reg_lock);
  for (int i = 0; i < MAX_SESSIONS; i++)
    if (g_reg[i].proc == proc) d = g_reg[i].d;
  pthread_mutex_unlock(&g_reg_lock);
  return d;
}

static void* g_vt[VT_SLOTS + 2];
static void** g_class_vt;

static int hook_create_session(uint8_t* proc, void* bi) {
  int r = ((int (*)(void*, void*))g_class_vt[VT_CREATE_SESSION])(proc, bi);
  VcnLegacy* d = reg_find(proc);
  // The create message is the driver's AV1 one with the codec id replaced.
  if (!r && d) U32(DATA_MSG(DEC_DATA(PROC_DECODER(proc))), 40) = d->cfg.codecId;
  return r;
}

static uint32_t hook_dpb_size(uint8_t* proc) {
  VcnLegacy* d = reg_find(proc);
  return d ? d->dpbSize : 0;
}

static uint32_t hook_ctx_size(uint8_t* proc) {
  (void)proc;
  return UNUSED_CTX_BYTES;
}

static void hook_init_ctx(uint8_t* proc) {
  uint8_t* data = DEC_DATA(PROC_DECODER(proc));
  uint8_t* tex = DATA_CTX_TEX(data);
  uint8_t* ctx = tex ? TEX_CPU(tex) : NULL;
  if (ctx && DATA_CTX_SIZE(data)) memset(ctx, 0, DATA_CTX_SIZE(data));
}

// Replaces AvdVcnAv1DecDataProcessor::SetDecodeMessageFields.
static int hook_set_message(uint8_t* proc, const LegacyParams* prm,
                            uint8_t* target, uint8_t* bi, uint32_t a4,
                            uint32_t a5) {
  (void)a4;
  (void)a5;
  VcnLegacy* d = prm->session;
  uint8_t* dec = PROC_DECODER(proc);
  uint8_t* data = DEC_DATA(dec);
  uint8_t* hw = HWCONFIG(PROC_VACONTEXT(proc));
  // The session's size never changes, so the buffers the driver made at create
  // time stay: a new DPB would lose the reference pictures the firmware keeps
  // in it.
  DATA_REALLOC(data) = 0;
  PROC_DEPTH(proc) = 8;
  uint32_t tuple[6] = {0, 0, DEC_WIDTH(dec), DEC_HEIGHT(dec), 8, 0};
  if (memcmp(tuple, DATA_TUPLE(data), sizeof(tuple))) {
    if (d->dpbSize > DATA_DPB_SIZE(data) ||
        UNUSED_CTX_BYTES > DATA_CTX_SIZE(data)) {
      DATA_REALLOC(data) = 1;
      DATA_DPB_SIZE(data) = d->dpbSize;
      DATA_CTX_SIZE(data) = UNUSED_CTX_BYTES;
    }
    memcpy(DATA_TUPLE(data), tuple, sizeof(tuple));
  }
  VcnLegacyMessage m = {.codecId = d->cfg.codecId,
                        .messageId = d->cfg.messageId,
                        .width = DEC_WIDTH(dec),
                        .height = DEC_HEIGHT(dec),
                        .sizeInMacroblocks = d->cfg.sizeInMacroblocks,
                        .alignSizeTo16 = d->cfg.alignSizeTo16,
                        .pitch = TEX_PITCH(target),
                        .texHeight = TEX_HEIGHT(target),
                        .bytesPerElement = TEX_BPE(target),
                        .dpbSize = DATA_DPB_SIZE(data),
                        .bitstreamSize = DATA_BS_SIZE(data),
                        .streamHandle = (uint32_t)(uintptr_t)data,
                        .feedbackNumber = PROC_FEEDBACK(proc),
                        .dbHeightZero = vcnlegacy_db_height_mode == 1,
                        .fieldLayout = vcnlegacy_field_layout == 1,
                        .bottomMode = (uint8_t)vcnlegacy_bottom_mode,
                        .block = d->block,
                        .blockSize = d->blockSize};
  if (!vcnlegacy_build_message(DATA_MSG(data), MSG_MAX, &m)) return -1;

  U32(bi, BI_MSG_ON) = 1;
  *(uint8_t**)(bi + BI_MSG) = DATA_MSG_TEX(data);
  U32(bi, BI_DPB_ON) = 1;
  *(uint8_t**)(bi + BI_DPB) = DATA_DPB_TEX(data);
  U32(bi, BI_TARGET_ON) = 1;
  *(uint8_t**)(bi + BI_TARGET) = target;
  U32(bi, BI_TARGET_OFF) = 0;
  // No context buffer: with it the driver emits RDECODE_CMD_CONTEXT_BUFFER
  // (0x206, UvdCommand::buildUvdCommand, 25G342 0x7ffb10b14472) and the
  // firmware then skips the decode of these codecs without a word. Mesa sends
  // that command only when hw_ctx_size is not 0 (ac_vcn_dec.c).
  U32(bi, BI_CTX_ON) = 0;
  bool session = *((int8_t*)hw + 149) < 0;
  if (session) {
    U32(bi, BI_SESSION_ON) = 1;
    *(uint8_t**)(bi + BI_SESSION) = DATA_SESSION_TEX(data);
  }
  uint8_t* dpbTex = DATA_DPB_TEX(data);
  uint8_t* dpbCpu = dpbTex ? TEX_CPU(dpbTex) : NULL;
  // Before the first picture only: later ones need the references in it.
  const char* cleared = "";
  if (vcnlegacy_clear_dpb == 1 && !d->done && !d->dpbSeen) {
    if (dpbCpu && m.dpbSize &&
        mapped(dpbCpu, m.dpbSize, VM_PROT_READ | VM_PROT_WRITE)) {
      memset(dpbCpu, 0, m.dpbSize);
      cleared = ", DPB cleared";
    } else {
      cleared = ", DPB NOT cleared (not mapped here)";
    }
  }
  DBG("message: %ux%u pitch %u texh %u dpb %u bs %u feedback #%u\n", m.width,
      m.height, m.pitch, m.texHeight, m.dpbSize, m.bitstreamSize,
      m.feedbackNumber);
  DBG("  buffers: session context %s (hw byte 149 0x%02x), DPB texture %p%s, "
      "cpu %p, db_aligned_height %u%s\n",
      session ? "sent" : "NOT sent", *((uint8_t*)hw + 149), (void*)dpbTex,
      d->dpbSeen && d->dpbSeen != dpbTex ? " (CHANGED)" : "", (void*)dpbCpu,
      m.dbHeightZero ? 0 : al(m.height, 64), cleared);
  {
    const uint8_t* db = DATA_MSG(data) + 24 + 16 * 2;
    DBG("  target: dt_pitch %u dt_uv_pitch %u dt_field_mode %u db_field_mode "
        "%u luma top %u bottom %u chroma top %u bottom %u\n",
        U32(db, 100), U32(db, 104), U32(db, 120), U32(db, 92), U32(db, 136),
        U32(db, 140), U32(db, 144), U32(db, 148));
  }
  d->dpbSeen = dpbTex;
  d->dpbCpu = dpbCpu;
  d->dpbBytes = m.dpbSize;
  return 0;
}

// Wraps the driver's SetDecodeFeedbackFields, which Process calls right after
// the message slot: it attaches a feedback buffer and prefills it with what a
// decode without errors also leaves (header, zeros). To tell a command the
// firmware ran from one it dropped, the three result words (number, status,
// value) are marked here, after the prefill: the firmware rewrites them.
#define FB_MARK_OFF 12
#define FB_MARK_LEN 12
static int hook_set_feedback(uint8_t* proc, uint8_t* bi) {
  int r = ((int (*)(void*, void*))g_class_vt[VT_SET_FEEDBACK])(proc, bi);
  VcnLegacy* d = reg_find(proc);
  if (!d) return r;
  d->fb = NULL;
  uint8_t* fb = DATA_FEEDBACK(DEC_DATA(PROC_DECODER(proc)));
  if (!r && fb) {
    memset(fb + FB_MARK_OFF, 0xA5, FB_MARK_LEN);
    d->fb = fb;
  }
  return r;
}

static bool g_watch_feedback;
static void init_vt(void) {
  memcpy(g_vt, g_class_vt - 2, sizeof(g_vt));
  void** vt = &g_vt[2];
  vt[VT_CREATE_SESSION] = (void*)hook_create_session;
  vt[VT_DPB_SIZE] = (void*)hook_dpb_size;
  vt[VT_CTX_SIZE] = (void*)hook_ctx_size;
  vt[VT_INIT_CTX] = (void*)hook_init_ctx;
  vt[VT_SET_MESSAGE] = (void*)hook_set_message;
  // Only when slot 15 really is the function that was read.
  void* sf = dlsym(RTLD_DEFAULT,
                   "_ZN19DecodeDataProcessor23SetDecodeFeedbackFieldsEP23_"
                   "uvd_command_build_info");
  if (sf && g_class_vt[VT_SET_FEEDBACK] == sf) {
    vt[VT_SET_FEEDBACK] = (void*)hook_set_feedback;
    g_watch_feedback = true;
  }
}

static void* (*g_orig_create_processor)(void*, int, void*);
static void* hook_create_processor(void* factory, int type, void* decoder) {
  void** proc = g_orig_create_processor(factory, type, decoder);
  if (proc && type == AV1_PROCESSOR_TYPE && t_creating) {
    void** vt = *(void***)proc;
    if (!g_class_vt) g_class_vt = vt;
    // Something else where AV1's class should be, or no room to remember the
    // session: the object is left as the driver made it, and the create fails
    // because no processor was taken over.
    if (vt != g_class_vt || !reg_add((uint8_t*)proc, t_creating)) return proc;
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, init_vt);
    t_creating->proc = (uint8_t*)proc;
    *proc = (void*)&g_vt[2];
  }
  return proc;
}

// ---------------------------------------------------------------------------
static bool put_num(CFMutableDictionaryRef a, CFStringRef k, long long v) {
  CFNumberRef n = CFNumberCreate(NULL, kCFNumberLongLongType, &v);
  if (!n) return false;
  CFDictionarySetValue(a, k, n);
  CFRelease(n);
  return true;
}

// The same surface layout the VP9 decoder asks for; the message's target
// offsets are computed for it.
CFDictionaryRef vcnlegacy_copy_pixel_buffer_attributes(uint32_t w, uint32_t h) {
  CFMutableDictionaryRef a =
      CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                &kCFTypeDictionaryValueCallBacks);
  CFMutableDictionaryRef io =
      CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                &kCFTypeDictionaryValueCallBacks);
  if (!a || !io) {
    if (a) CFRelease(a);
    if (io) CFRelease(io);
    return NULL;
  }
  bool ok = true;
#define PUT(k, v) (ok = put_num(a, k, v) && ok)
  PUT(kCVPixelBufferPixelFormatTypeKey,
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
  PUT(kCVPixelBufferWidthKey, w);
  PUT(kCVPixelBufferHeightKey, h);
  PUT(kCVPixelBufferBytesPerRowAlignmentKey, 256);
  PUT(kCVPixelBufferPlaneAlignmentKey, 4096);
  PUT(kCVPixelBufferExtendedPixelsBottomKey, al(h, 64) - h);
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

// vcnlegacy_fill_target: the surface from its luma plane on, which is where
// the firmware's offsets start (CoreVideo puts the luma plane 4096 bytes into
// the IOSurface; dt_chroma_top_offset is the distance between the planes).
typedef struct {
  uint8_t* base;                         // the luma plane
  size_t alloc, chroma, pitch0, pitch1;  // bytes from base to the end, ...
} SurfaceLayout;

static bool surface_layout(CVPixelBufferRef pb, SurfaceLayout* l) {
  IOSurfaceRef s = CVPixelBufferGetIOSurface(pb);
  uint8_t* io = s ? IOSurfaceGetBaseAddress(s) : NULL;
  uint8_t* y = CVPixelBufferGetBaseAddressOfPlane(pb, 0);
  uint8_t* uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
  if (!io || !y || !uv || y < io || uv <= y) return false;
  size_t size = IOSurfaceGetAllocSize(s);
  if ((size_t)(y - io) >= size || (size_t)(uv - io) >= size) return false;
  l->base = y;
  l->alloc = size - (size_t)(y - io);
  l->chroma = (size_t)(uv - y);
  l->pitch0 = CVPixelBufferGetBytesPerRowOfPlane(pb, 0);
  l->pitch1 = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
  return true;
}

static void fill_target(CVPixelBufferRef pb) {
  SurfaceLayout l;
  if (CVPixelBufferLockBaseAddress(pb, 0)) return;
  if (surface_layout(pb, &l)) {
    memset(l.base, 0x11, l.chroma);
    memset(l.base + l.chroma, 0x22, l.alloc - l.chroma);
  }
  CVPixelBufferUnlockBaseAddress(pb, 0);
}

// Bytes of [from, to) that are no longer the fill, and the first of them.
typedef struct {
  size_t changed, first;
  uint8_t firstValue;
} Changed;

static Changed changed_bytes(const uint8_t* p, size_t from, size_t to,
                             size_t pitch, size_t cols, size_t step,
                             uint8_t fill) {
  // A rectangle: rows of cols bytes every pitch * step bytes from `from`, up
  // to `to`; pitch 0 for a plain range.
  Changed c = {0, 0, 0};
  if (!pitch) {
    for (size_t i = from; i < to; i++)
      if (p[i] != fill && !c.changed++) c.first = i, c.firstValue = p[i];
    return c;
  }
  for (size_t row = from; row + cols <= to; row += pitch * step)
    for (size_t i = row; i < row + cols; i++)
      if (p[i] != fill && !c.changed++) c.first = i, c.firstValue = p[i];
  return c;
}

static void report_writes(VcnLegacy* d, CVPixelBufferRef pb) {
  SurfaceLayout l;
  if (CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly)) return;
  if (surface_layout(pb, &l)) {
    const size_t w = d->cfg.width, h = d->cfg.height, ch = (h + 1) / 2;
    const size_t cw = (w + 1) / 2 * 2;
    const uint8_t* p = l.base;
    Changed y = changed_bytes(p, 0, l.pitch0 * h, l.pitch0, w, 1, 0x11);
    Changed y0 = changed_bytes(p, 0, 256, 0, 0, 0, 0x11);
    Changed ypad = l.pitch0 > w ? changed_bytes(p + w, 0, l.pitch0 * h - w,
                                                l.pitch0, l.pitch0 - w, 1, 0x11)
                                : (Changed){0, 0, 0};
    Changed ytail = changed_bytes(p, l.pitch0 * h, l.chroma, 0, 0, 0, 0x11);
    const uint8_t* c = p + l.chroma;
    Changed ce = changed_bytes(c, 0, l.pitch1 * ch, l.pitch1, cw, 2, 0x22);
    Changed co = changed_bytes(c + l.pitch1, 0, l.pitch1 * (ch - 1), l.pitch1,
                               cw, 2, 0x22);
    Changed ctail =
        changed_bytes(p, l.chroma + l.pitch1 * ch, l.alloc, 0, 0, 0, 0x22);
    // "first at" only for a part the firmware wrote at all.
    char below[64] = "", after[64] = "";
    if (ytail.changed)
      snprintf(below, sizeof(below), " (first at %zu = 0x%02x)", ytail.first,
               ytail.firstValue);
    if (ctail.changed)
      snprintf(after, sizeof(after), " (first at %zu = 0x%02x)", ctail.first,
               ctail.firstValue);
    DBG("  writes: %zu bytes from the luma plane, chroma at %zu, pitches "
        "%zu/%zu; luma %zu of %zu, first 256 bytes %zu, right of the picture "
        "%zu, below it %zu%s; chroma even rows %zu odd rows %zu of %zu each, "
        "after the plane %zu%s\n",
        l.alloc, l.chroma, l.pitch0, l.pitch1, y.changed, w * h, y0.changed,
        ypad.changed, ytail.changed, below, ce.changed, co.changed,
        cw * ((ch + 1) / 2), ctail.changed, after);
  }
  CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  // The DPB buffer, read only: how many bytes of each 64 KiB are not zero
  // ('.' none, '0'..'9' tenths, '#' all).
  if (d->dpbCpu && d->dpbBytes &&
      mapped(d->dpbCpu, d->dpbBytes, VM_PROT_READ)) {
    char map[160];
    size_t n = 0;
    for (size_t at = 0; at < d->dpbBytes && n + 1 < sizeof(map); at += 65536) {
      size_t end = at + 65536 < d->dpbBytes ? at + 65536 : d->dpbBytes, nz = 0;
      for (size_t i = at; i < end; i++) nz += d->dpbCpu[i] != 0;
      map[n++] = !nz              ? '.'
                 : nz == end - at ? '#'
                                  : (char)('0' + nz * 10 / (end - at));
    }
    map[n] = 0;
    DBG("  dpb: %s\n", map);
  } else {
    DBG("  dpb: not mapped here\n");
  }
}

CVPixelBufferRef vcnlegacy_new_target(VcnLegacy* d) {
  if (!d->pool) {
    CFDictionaryRef a =
        vcnlegacy_copy_pixel_buffer_attributes(d->cfg.width, d->cfg.height);
    if (!a) return NULL;
    CVReturn r = CVPixelBufferPoolCreate(NULL, NULL, a, &d->pool);
    CFRelease(a);
    if (r) {
      d->pool = NULL;
      return NULL;
    }
  }
  CVPixelBufferRef pb = NULL;
  if (CVPixelBufferPoolCreatePixelBuffer(NULL, d->pool, &pb)) return NULL;
  if (vcnlegacy_fill_target) fill_target(pb);
  return pb;
}

static void destroy_now(VcnLegacy* d) {
  vcn_session_close(&d->s);
  reg_remove(d);
  if (d->pool) CVPixelBufferPoolRelease(d->pool);
  if (d->log && d->log != OS_LOG_DEFAULT) os_release(d->log);
  free(d->seq);
  free(d->frame);
  free(d->bsinfo);
  free(d);
}

void vcnlegacy_destroy(VcnLegacy* d) {
  if (!d) return;
  vcn_teardown(d->stuck, vcn_session_lost(&d->s), d->log,
               "legacy codec session", NULL, ^{
                 destroy_now(d);
               });
}

static bool driver_validated(const VcnDriverLib* lib) {
  for (size_t i = 0; i < sizeof(kValidatedDrivers) / sizeof(*kValidatedDrivers);
       i++)
    if (!strcmp(lib->uuid, kValidatedDrivers[i])) return true;
  return false;
}

bool vcnlegacy_available(char* err, size_t errLen) {
  char why[200];
  VcnDriverLib lib;
  if (!vcn_driver_load(&lib, why, sizeof(why))) {
    if (err && errLen) snprintf(err, errLen, "%s", why);
    return false;
  }
  if (!driver_validated(&lib)) {
    if (err && errLen)
      snprintf(err, errLen,
               "AMDRadeonVADriver2 build %s not validated for "
               "MPEG-2/VC-1/MPEG-4",
               lib.uuid);
    return false;
  }
  io_service_t svc = vcn_find_accelerator();
  if (!svc) {
    if (err && errLen) snprintf(err, errLen, "no AMD accelerator");
    return false;
  }
  IOObjectRelease(svc);
  return true;
}

VcnLegacy* vcnlegacy_create(const VcnLegacyConfig* cfg, char* err,
                            size_t errLen) {
#define FAIL(...)                                          \
  do {                                                     \
    if (err && errLen) snprintf(err, errLen, __VA_ARGS__); \
    vcnlegacy_destroy(d);                                  \
    return NULL;                                           \
  } while (0)
  VcnLegacy* d = calloc(1, sizeof(*d));
  if (!d) {
    if (err && errLen) snprintf(err, errLen, "out of memory");
    return NULL;
  }
  d->cfg = *cfg;
  d->log = os_log_create(
      cfg->logSubsystem ? cfg->logSubsystem : "com.droga.vtlegacyvcn",
      "driver");
  if (!d->log) d->log = OS_LOG_DEFAULT;
  d->seq = calloc(1, SEQ_BYTES);
  d->frame = calloc(1, FRAME_BYTES);
  d->bsinfo = calloc(1, BSINFO_BYTES);
  if (!d->seq || !d->frame || !d->bsinfo) FAIL("out of memory");
  // Only the three codecs that were run. A stream type the firmware does not
  // expect on this path hung the video engine until a reboot (2026-11-23).
  bool pair =
      (cfg->codecId == VCN_CODEC_MPEG2_VLD &&
       cfg->messageId == VCN_MESSAGE_MPEG2_VLD) ||
      (cfg->codecId == VCN_CODEC_VC1 && cfg->messageId == VCN_MESSAGE_VC1) ||
      (cfg->codecId == VCN_CODEC_MPEG4 &&
       cfg->messageId == VCN_MESSAGE_MPEG4_ASP_VLD);
  if (!pair)
    FAIL("codec %u with message %u is not one of the three this path decodes",
         cfg->codecId, cfg->messageId);
  if (!cfg->width || !cfg->height || cfg->width > VCNLEGACY_MAX_WIDTH ||
      cfg->height > VCNLEGACY_MAX_HEIGHT)
    FAIL("picture size %ux%u out of range", cfg->width, cfg->height);
  d->dpbSize = vcnlegacy_dpb_size(cfg->codecId, cfg->width, cfg->height);
  if (!d->dpbSize) FAIL("no DPB size for %ux%u", cfg->width, cfg->height);
  const char* arm = getenv("VCNLEGACY_ALLOW_GPU");
  bool armed = __atomic_load_n(&vcnlegacy_gpu_armed, __ATOMIC_RELAXED) ||
               (arm && !strcmp(arm, "yes-i-know-it-can-hang"));
  if (!armed) FAIL("GPU submission disabled (set VCNLEGACY_ALLOW_GPU)");
  char why[200];
  VcnDriverLib lib;
  if (!vcn_driver_load(&lib, why, sizeof(why))) FAIL("%s", why);
  if (!driver_validated(&lib))
    FAIL("AMDRadeonVADriver2 build %s not validated for MPEG-2/VC-1/MPEG-4",
         lib.uuid);
  io_service_t svc = vcn_find_accelerator();
  if (!svc) FAIL("no AMD accelerator");
  if (!vcn_session_open(&d->s, &lib, svc, d->log, why, sizeof(why)))
    FAIL("%s", why);
  AVD_ContextList list = {0};
  void* ctxOut[2] = {0};
  AVD_FunctionInfo* fis[1] = {&list.inlineInfo};
  list.count = 1;
  list.functions = fis;
  list.contextsOut = ctxOut;
  list.inlineInfo =
      (AVD_FunctionInfo){.kind = 1,
                         .function = AVD_FUNC_AV1,
                         .mode = VCN_MODE_VCN0,
                         .pixelRate = cfg->width * cfg->height * 60,
                         .width = cfg->width,
                         .height = cfg->height,
                         .inFormat = 0x72617762,
                         .inFormatCount = 1,
                         .outFormat = 0x4e563132,
                         .outFormatCount = 1};
  AVD_DriverContextInit ci = {.list = &list};
  // The factory's class pointer is swapped only for the length of
  // CreateContexts, as in vp9/vcnvp9.c.
  static pthread_mutex_t create_lock = PTHREAD_MUTEX_INITIALIZER;
  static void* factoryVt[FACTORY_SLOTS + 2];
  static void** factoryOrigVt;
  uint8_t* va = PTR(d->s.drv, 8);
  if (!va) FAIL("no VAContext");
  void*** factory = (void***)PTR(va, 75072);
  if (!factory || !*factory) FAIL("no factory");
  pthread_mutex_lock(&create_lock);
  void** origFactoryVt = *factory;
  if (!factoryOrigVt) {
    memcpy(factoryVt, origFactoryVt - 2, sizeof(factoryVt));
    g_orig_create_processor =
        (void* (*)(void*, int, void*))origFactoryVt[FACTORY_CREATE_PROCESSOR];
    factoryVt[2 + FACTORY_CREATE_PROCESSOR] = (void*)hook_create_processor;
    factoryOrigVt = origFactoryVt;
  }
  if (origFactoryVt != factoryOrigVt) {
    pthread_mutex_unlock(&create_lock);
    FAIL("the driver's factory class changed (%p, was %p)",
         (void*)origFactoryVt, (void*)factoryOrigVt);
  }
  __atomic_store_n(factory, &factoryVt[2], __ATOMIC_RELEASE);
  t_creating = d;
  int r = FN(CreateContexts)(d->s.drv, &ci);
  t_creating = NULL;
  __atomic_store_n(factory, origFactoryVt, __ATOMIC_RELEASE);
  pthread_mutex_unlock(&create_lock);
  if (r || !ctxOut[0]) FAIL("CreateContexts %d", r);
  d->s.ctx = ctxOut[0];
  // Without our processor the driver would send its own AV1 messages.
  if (!d->proc) FAIL("the driver's AV1 processor was not taken over");
  DBG("created: driver %s codec %u %ux%u dpb %u\n", lib.uuid, cfg->codecId,
      cfg->width, cfg->height, d->dpbSize);
  return d;
#undef FAIL
}

const char* vcnlegacy_last_error(VcnLegacy* d) { return d ? d->err : ""; }
int vcnlegacy_failure(VcnLegacy* d) {
  return d ? d->failure : VCNLEGACY_FAIL_DEVICE;
}
unsigned vcnlegacy_firmware_errors(VcnLegacy* d) { return d ? d->fwErrors : 0; }
uint32_t vcnlegacy_width(VcnLegacy* d) { return d ? d->cfg.width : 0; }
uint32_t vcnlegacy_height(VcnLegacy* d) { return d ? d->cfg.height : 0; }
bool vcnlegacy_session_lost(VcnLegacy* d) {
  return d && !d->broken && vcn_session_lost(&d->s);
}
void vcnlegacy_log_rebuild(VcnLegacy* d, const char* what, unsigned dropped) {
  if (!d) return;
  os_log_info(d->log,
              "a session from before a system sleep: a new one at %{public}s, "
              "%u picture(s) dropped meanwhile",
              what, dropped);
}
bool vcnlegacy_last_status(VcnLegacy* d, bool* executed, uint32_t* status) {
  if (!d || !d->haveStatus) return false;
  if (executed) *executed = d->executed;
  if (status) *status = d->status;
  return true;
}

// True when [p, p + n) is mapped readable in this task: the feedback buffer
// belongs to the driver, which may have let go of it.
static bool readable(const void* p, size_t n) {
  return mapped(p, n, VM_PROT_READ);
}

// The same with any protection bits: one region, mapped with all of prot.
static bool mapped(const void* p, size_t n, vm_prot_t prot) {
  mach_vm_address_t a = (mach_vm_address_t)(uintptr_t)p;
  mach_vm_size_t sz = 0;
  vm_region_basic_info_data_64_t info;
  mach_msg_type_number_t cnt = VM_REGION_BASIC_INFO_COUNT_64;
  mach_port_t obj = MACH_PORT_NULL;
  if (mach_vm_region(mach_task_self(), &a, &sz, VM_REGION_BASIC_INFO_64,
                     (vm_region_info_t)&info, &cnt, &obj) != KERN_SUCCESS)
    return false;
  if (obj != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), obj);
  if (a > (mach_vm_address_t)(uintptr_t)p) return false;
  if ((info.protection & prot) != prot) return false;
  return (uintptr_t)p + n <= a + sz;
}

int vcnlegacy_decode(VcnLegacy* d, const void* block, uint32_t blockSize,
                     const VcnLegacyBytes* parts, int nparts,
                     CVPixelBufferRef target) {
  d->err[0] = 0;
  d->failure = VCNLEGACY_FAIL_STREAM;
  d->haveStatus = false;
  // A session from before a system sleep never decodes another picture: the
  // engine lost it at the wake (vcndriver.h). That is not a failure of the
  // decoder: the codec layer drops the pictures up to its next intra picture
  // and starts a new session there (mpeg2/vcnmpeg2.c, vc1/vcnvc1.c,
  // mpeg4/vcnmpeg4.c), as AV1 and VP9 have done since 0.3.8. Only a session
  // that stopped for another reason stops the decoder. Nothing goes into the
  // pool or to the engine here.
  if (vcnlegacy_session_lost(d)) {
    snprintf(d->err, sizeof(d->err),
             "session stopped: the system slept since it opened");
    d->failure = VCNLEGACY_FAIL_DEVICE;
    return -1;
  }
  if (d->broken) {
    snprintf(d->err, sizeof(d->err), "session stopped: %s",
             d->stuck ? "the GPU did not finish an earlier picture"
                      : "an earlier driver call failed");
    d->failure = VCNLEGACY_FAIL_DEVICE;
    return -1;
  }
  size_t size = 0;
  for (int i = 0; i < nparts; i++) size += parts[i].size;
  if (!size || size > VCN_BS_SIZE - 256) {
    snprintf(d->err, sizeof(d->err), "picture of %zu bytes", size);
    return -1;
  }
  if (!block || !blockSize || blockSize > MSG_MAX - 244) {
    snprintf(d->err, sizeof(d->err), "codec block of %u bytes", blockSize);
    return -1;
  }
  IOSurfaceRef surface = target ? CVPixelBufferGetIOSurface(target) : NULL;
  if (!surface || CVPixelBufferGetWidth(target) != d->cfg.width ||
      CVPixelBufferGetHeight(target) != d->cfg.height) {
    snprintf(d->err, sizeof(d->err), "no target of the session's size");
    d->failure = VCNLEGACY_FAIL_MEMORY;
    return -1;
  }
  int bi = d->bsNext;
  d->bsNext = (d->bsNext + 1) % VCN_NUM_BS;
  uint8_t* bs = d->s.bsAddr[bi];
  size_t at = 0;
  for (int i = 0; i < nparts; i++) {
    memcpy(bs + at, parts[i].data, parts[i].size);
    at += parts[i].size;
  }
  memset(bs + size, 0, 256);
  memset(d->bsinfo, 0, BSINFO_BYTES);
  *(uint32_t*)(d->bsinfo + 0) = (uint32_t)bi;
  *(uint32_t*)(d->bsinfo + 16) = al((uint32_t)size, 128);
  memset(d->frame, 0, FRAME_BYTES);
  // What the driver's own code reads from the AV1 frame block.
  *(uint32_t*)(d->frame + 308) = d->cfg.width - 1;
  *(uint32_t*)(d->frame + 312) = d->cfg.width;
  *(uint32_t*)(d->frame + 316) = d->cfg.height - 1;
  *(uint32_t*)(d->frame + 320) = d->cfg.height;
  LegacyParams prm;
  memset(&prm, 0, sizeof(prm));
  prm.seq = d->seq;
  prm.frame = d->frame;
  prm.output = surface;
  prm.bsinfo = d->bsinfo;
  prm.session = d;
  for (int i = 0; i < 8; i++) prm.ref_frame_map[i] = 0x7f;
  for (int i = 0; i < 7; i++) prm.frame_refs[i] = 0x7f;
  d->block = block;
  d->blockSize = blockSize;
  d->fb = NULL;

  AVD_CmdInfo cmd = {.kind = 1,
                     .function = AVD_FUNC_AV1,
                     .mode = VCN_MODE_VCN0,
                     .context = d->s.ctx,
                     .params = &prm};
  AVD_CmdInfo* cmds[1] = {&cmd};
  AVD_CmdList list = {.count = 1, .cmds = cmds};
  void* refcons[1] = {0};
  AVD_RefConList rl = {.count = 1, .refcons = refcons};
  int r = FN(ScheduleAVDCommands)(d->s.drv, &list, &rl);
  d->block = NULL;
  d->failure = VCNLEGACY_FAIL_DEVICE;
  if (r) {
    d->broken = true;
    snprintf(d->err, sizeof(d->err), "ScheduleAVDCommands %d", r);
    return -1;
  }
  uint32_t fw = 0;
  int ds = 0;
  // VCNLEGACY_TIMEOUT_MS (100..5000) is for experiments: a command the
  // firmware gives up on after about a second can then still be read.
  unsigned timeout = VCN_COMMAND_TIMEOUT_MS;
  const char* tv = getenv("VCNLEGACY_TIMEOUT_MS");
  if (tv && atoi(tv) >= 100 && atoi(tv) <= 5000) timeout = (unsigned)atoi(tv);
  uint64_t t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
  VcnWaitResult w = vcn_wait_command(FN(QueryAVDCommandStatus), d->s.drv,
                                     refcons[0], timeout, &fw, &ds);
  uint64_t took = (clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0) / 1000000;
  if (w == VCN_WAIT_TIMEOUT) {
    d->stuck = d->broken = true;
    snprintf(d->err, sizeof(d->err),
             "the GPU did not finish a picture in %u ms; session stopped",
             timeout);
    return -1;
  }
  if (w != VCN_WAIT_DONE) {
    d->stuck = d->broken = true;
    snprintf(d->err, sizeof(d->err), "QueryAVDCommandStatus %d", ds);
    return -1;
  }
  d->failure = VCNLEGACY_FAIL_STREAM;
  d->done++;
  // The firmware's own word on this command, from the feedback buffer the
  // driver attached to it.
  bool bad = fw != 0;
  if (g_watch_feedback && d->fb && readable(d->fb, 44)) {
    static const uint8_t mark[FB_MARK_LEN] = {
        0xA5, 0xA5, 0xA5, 0xA5, 0xA5, 0xA5, 0xA5, 0xA5, 0xA5, 0xA5, 0xA5, 0xA5};
    d->haveStatus = true;
    memcpy(d->fb_copy, d->fb, sizeof(d->fb_copy));
    d->executed = memcmp(d->fb + FB_MARK_OFF, mark, FB_MARK_LEN) != 0;
    d->status = d->executed ? U32(d->fb, 16) : 0;
    bad = !d->executed || d->status != 0;
  }
  d->fb = NULL;
  if (vcnlegacy_fill_target && vcnlegacy_debug) report_writes(d, target);
  DBG("picture %u: %zu bytes, %llu ms, firmware result %u, %s, status %u\n",
      d->done, size, (unsigned long long)took, fw,
      !d->haveStatus ? "feedback not watched"
      : d->executed  ? "ran"
                     : "NOT RUN",
      d->status);
  if (vcnlegacy_debug && d->haveStatus)
    DBG("  feedback words: number %u status %u value %u error bits 0x%x\n",
        U32(d->fb_copy, 12), U32(d->fb_copy, 16), U32(d->fb_copy, 20),
        U32(d->fb_copy, 24));
  // Counted, not refused, as the VP9 decoder does: the picture is handed back
  // and the count goes in the stats line.
  if (bad && !d->fwErrors++)
    os_log_error(d->log,
                 "picture %u of this session: firmware result %u, %{public}s, "
                 "status %u; later ones are counted in the stats line",
                 d->done, fw,
                 !d->haveStatus ? "feedback not watched"
                 : d->executed  ? "command ran"
                                : "command was not run",
                 d->status);
  return 0;
}
