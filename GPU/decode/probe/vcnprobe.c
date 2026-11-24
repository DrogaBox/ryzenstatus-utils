// The probe session. Same driver route as GPU/decode/vp9/vcnvp9.c: the AV1
// context and decoder are the driver's, and only the five virtual slots that
// build the message are replaced, on one object, for the length of one call.
// What differs is the codec: the create message's codec id and the decode
// message's codec block come from the caller.
#include <CoreFoundation/CoreFoundation.h>
#include <CoreVideo/CoreVideo.h>
#include <IOSurface/IOSurfaceRef.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <os/log.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "avd.h"
#include "vcnprobe.h"
#include "vcndriver.h"
#include "vp9fill.h"

#define VCN_MODE_VCN0 4
#define BSINFO_BYTES (20 + 64 * 512 + 64)
#define SEQ_BYTES 2048
#define FRAME_BYTES 4096
#define MSG_MAX 4096

static uint32_t al(uint32_t v, uint32_t a) { return (v + a - 1) & ~(a - 1); }

// ---------------------------------------------------------------------------
// Driver object layout, same offsets as vcnvp9.c (read from the 25G342
// database there; every one of them is used by the VP9 decoder in production).
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
#define DATA_IT_TEX(data) PTR(data, 8 * (uint64_t)U32(data, 624) + 496)
#define DATA_IT(data) PTR(data, 632)
#define DATA_BS_SIZE(data) U32(data, 688)
// The VCN feedback buffer: DecodeDataProcessor::SetDecodeFeedbackFields builds
// a texture at DATA+0x170 and hands it to the kernel at build_info+0x34/0x38;
// the CPU mapping is the same +152 slot every texture uses.
#define DATA_FEEDBACK_TEX(data) PTR(data, 0x170)
#define DATA_FEEDBACK_IDX(data) U32(data, 0x168)
#define DATA_FEEDBACK_ARR(data) PTR(data, 0xE8)
#define TEX_CPU(tex) PTR(tex, 152)
#define TEX_HEIGHT(tex) U32(tex, 124)
#define TEX_PITCH(tex) U32(tex, 128)
#define TEX_BPE(tex) U32(tex, 132)
#define HWCONFIG(ctx) PTR(ctx, 1120)

// Buffer-info entries the driver hands to the kernel.
#define BI_MSG_ON 4
#define BI_MSG 8
#define BI_DPB_ON 16
#define BI_DPB 24
#define BI_TARGET_ON 112
#define BI_TARGET 120
#define BI_TARGET_OFF 128
#define BI_IT_ON 144
#define BI_IT 152
#define BI_CTX_ON 160
#define BI_CTX 168
#define BI_SESSION_ON 176
#define BI_SESSION 184
#define BI_FEEDBACK_ON 52  // bi+0x34, set by SetDecodeFeedbackFields
#define BI_FEEDBACK 56     // bi+0x38

// Virtual slots of AvdVcnAv1DecDataProcessor, in pointers (vcnvp9.c).
enum {
  VT_CREATE_SESSION = 2,
  VT_DPB_SIZE = 8,
  VT_CTX_SIZE = 9,
  VT_INIT_CTX = 12,
  VT_SET_MESSAGE = 14,
  VT_SET_FEEDBACK = 15,
  VT_SLOTS = 16
};
#define FACTORY_CREATE_PROCESSOR 4
#define FACTORY_SLOTS 32
#define AV1_PROCESSOR_TYPE 6

// Decode-message layout: a 40-byte header, four [type, offset, size] index
// entries, then the blocks.
#define DECODE_OFF 88
#define DECODE_SIZE 188
#define DRM_SIZE 68
#define ZERO_SIZE 168
#define VCN_MESSAGE_DECODE 2u
#define VCN_MESSAGE_DRM 3u
#define VCN_MESSAGE_0F 15u

// Parameter block of the driver's AV1 path (vcnav1.c). Only the fields the
// driver reads are filled here.
typedef struct {
  void* seq;
  void* frame;
  uint32_t curr_pic_idx;
  uint32_t pad0;
  IOSurfaceRef output;
  uint32_t ref_frame_map[8];
  uint32_t frame_refs[7];
  uint32_t pad1;
  void* bsinfo;
  uint8_t reserved[160];
} ProbeParams;

static struct {
  uint32_t codecId;
  uint32_t messageId;
  const void* block;
  uint32_t blockSize;
  uint32_t width, height;
  uint32_t profile, depth;
  uint32_t vc1Simple;  // VC-1 simple/main: sizes are in 16-sample units
  const VP9Parser* vp9;  // only for VP9, which needs the frame for its message
  int dump;
  uint8_t* data;  // saved by the hook, for the feedback read after the wait
  uint8_t* bi;
  uint8_t* proc;  // the processor the hook ran on, for ProcessDecodeStatus
} g;

// The create message the driver built inside CreateContexts, kept for the dry
// run's dump (the driver owns the storage, so it is copied).
static uint8_t g_create[64];
static int g_haveCreate;

static void dump_bytes(const char* label, const void* p, size_t n) {
  const uint8_t* b = p;
  printf("%s (%zu bytes):\n", label, n);
  for (size_t i = 0; i < n; i += 16) {
    printf("  %04zx:", i);
    for (size_t j = 0; j < 16 && i + j < n; j++) printf(" %02x", b[i + j]);
    printf("\n");
  }
}

// ---------------------------------------------------------------------------
// Message building, shared by the hook (real textures) and the dry run (no
// texture). Returns the total message size.
typedef struct {
  uint32_t width, height, pitch, texh, bpe;
  uint32_t dpbSize, ctxSize;
  uint32_t hwCtxt;      // variant 2: hw_ctxt_size stays 64 KiB in the header
  uint32_t swCtxt;      // VCNPROBE_VARIANT 1/2/10: RDECODE_SESSION_CONTEXT_SIZE
  uint32_t noHwCtxt;    // variant 10: hw_ctxt_size 0, as Mesa sends MPEG-2/VC-1
  uint32_t mesaIndex;   // variant 11: Mesa's two index entries, no DRM/0x0f
  uint32_t mesaGeom;    // variant 12: Mesa's db_pitch (32-aligned), bottom offsets 0
  uint32_t noMif;       // variant 13: mif_wrc_en (+160) 0, as Apple's VCN AVC builder
  uint32_t avcStyle;    // variant 14: the whole decode block as that builder leaves it
  uint32_t streamType;  // 0 = codecId; variant 5 takes it from the create msg
  uint32_t codecId, messageId, blockSize;
  const void* block;
  uint8_t* data;
  uint32_t feedback;
  uint32_t vc1Simple;
} MsgGeom;

static uint32_t fill_message(uint8_t* msg, const MsgGeom* m) {
  if (m->blockSize > MSG_MAX) return 0;
  // Variant 11: Mesa's layout (ac_vcn_dec.c, capture b33/msg-mpeg2.txt): two
  // index entries (decode, codec block), the decode block right after them at
  // 56, the codec block after it, total = the end of the codec block. No DRM
  // block and no 0x0f block, which Apple's builder adds and Linux never sends.
  const uint32_t nIndex = m->mesaIndex ? 2 : 4;
  const uint32_t decodeOff = 24 + 16 * nIndex;
  const uint32_t codecOff = decodeOff + DECODE_SIZE;
  const uint32_t drmOff = codecOff + al(m->blockSize, 4);
  const uint32_t zeroOff = drmOff + DRM_SIZE;
  const uint32_t end = m->mesaIndex ? codecOff + m->blockSize : zeroOff + ZERO_SIZE;
  const uint32_t total = m->mesaIndex ? end : end + 16;
  if ((size_t)end + 16 > MSG_MAX) return 0;
  memset(msg, 0, (size_t)end + 16);
  U32(msg, 0) = 40;
  U32(msg, 4) = total;  // the driver's AV1 total also has 16 extra bytes
  U32(msg, 8) = nIndex;
  U32(msg, 12) = 1;
  U32(msg, 16) = (uint32_t)(uintptr_t)m->data;
  U32(msg, 20) = m->feedback;
  const uint32_t index[4][3] = {{VCN_MESSAGE_DECODE, decodeOff, DECODE_SIZE},
                                {m->messageId, codecOff, m->blockSize},
                                {VCN_MESSAGE_DRM, drmOff, DRM_SIZE},
                                {VCN_MESSAGE_0F, zeroOff, ZERO_SIZE}};
  for (uint32_t i = 0; i < nIndex; i++)
    for (int j = 0; j < 3; j++) U32(msg, 24 + 16 * i + 4 * j) = index[i][j];

  uint8_t* d = msg + decodeOff;
  // Mesa's rvcn_dec_message_decode_t for VC-1 profile < 2 carries the size in
  // 16-sample units (ac_vcn_dec.c:1927-1932); every other field keeps the
  // pixel size.
  const uint32_t w = m->width, h = m->height;
  const uint32_t sw = m->vc1Simple ? (w + 15) / 16 : w;
  const uint32_t sh = m->vc1Simple ? (h + 15) / 16 : h;
  const uint32_t pitch = m->pitch,
                 texh = m->texh, bpe = m->bpe ? m->bpe : 1;
  const uint32_t a = w <= 32 ? 32 : 64;
  // Refuse geometries whose surface offsets do not fit the 32-bit fields rather
  // than silently wrapping them.
  if (((uint64_t)3 * pitch * texh) >> 1 > UINT32_MAX ||
      (uint64_t)pitch * al(texh, 16) + (((uint64_t)pitch * h) >> 1) - 1 >
          UINT32_MAX)
    return 0;
  U32(d, 0) = m->streamType ? m->streamType : m->codecId;
  U32(d, 8) = sw;
  U32(d, 12) = sh;
  U32(d, 16) = m->dpbSize;  // overwritten with the bitstream size by the hook
  U32(d, 20) = m->dpbSize;
  U32(d, 24) = (uint32_t)(((uint64_t)3 * pitch * texh) >> 1);
  U32(d, 36) = m->noHwCtxt ? 0 : m->hwCtxt ? m->hwCtxt : m->ctxSize;
  U32(d, 40) = m->swCtxt;
  U32(d, 72) = al(w, a);
  U32(d, 76) = al(h, 64);
  U32(d, 100) = pitch / bpe;
  U32(d, 104) = (pitch / bpe) >> 1;
  U32(d, 140) = (uint32_t)((uint64_t)pitch * h - 1);
  U32(d, 144) = (uint32_t)((uint64_t)pitch * al(texh, 16));
  U32(d, 148) = (uint32_t)((uint64_t)pitch * al(texh, 16) +
                           (((uint64_t)pitch * h) >> 1) - 1);
  U32(d, 160) = 1;
  U32(d, 164) = al(w / 2, a);
  // Variant 12 (non-VP9): Mesa's geometry where it differs from Apple's and is
  // not a tiling artefact (capture b33): db_pitch aligned to 32 (Mesa's
  // dpb_alignment for MPEG-2/VC-1; Linux 736 for 720 wide, Apple 768), and
  // dt_luma/chroma_bottom_offset 0. Apple puts the plane's last byte there;
  // VP9 never reads them, but codecs with field pictures may, and b36 showed
  // MPEG-2/VC-1 writing a flat Y 0 / Cb 0 / Cr 255 over the whole chroma plane.
  if (m->mesaGeom) {
    U32(d, 72) = al(w, 32);
    U32(d, 164) = al(w / 2, 32);
    U32(d, 140) = 0;
    U32(d, 148) = 0;
  }
  // Variants 13/14 (non-VP9): Apple's own builder for the other codec of the
  // legacy core, AvdVcnAvcDecDataProcessor::SetDecodeMessageFields (IDA
  // 25G342 0x7ffb10b40f44, b34/ida/avc.txt). It decodes H.264 into the same
  // linear surfaces and never writes +160 (Mesa's mif_wrc_en), +164
  // (db_pitch_uv), +76 (db_aligned_height) or +40 (sw_ctxt_size); the probe
  // took 1 / pitch / height from the AV1 builder. Its db_pitch is the width
  // aligned to the processor's alignment and its bottom offsets are Apple's.
  if (m->noMif) U32(d, 160) = 0;
  if (m->avcStyle) {
    U32(d, 160) = 0;
    U32(d, 164) = 0;
    U32(d, 76) = 0;
    U32(d, 40) = 0;
    U32(d, 72) = al(w, 32);
  }
  memcpy(msg + codecOff, m->block, m->blockSize);
  return total;
}

// The decode block's offset, from index entry 0 (88 with Apple's four
// entries, 56 with Mesa's two).
static inline uint32_t decode_off(const uint8_t* msg) { return U32(msg, 28); }

#define VCN_MAX_DPB (1024ull * 1024 * 1024)
#define VCN_MAX_CTX (256ull * 1024 * 1024)

static uint32_t g_dpbSize, g_ctxSize;
// Variant 5: the create message's stream type as the driver wrote it, before
// the probe patched +40.
static uint32_t g_createStreamType;
static int g_variant;
static int g_luma_blank = -1;  // set by write_nv12 before print_feedback
// The feedback buffer as the driver prefilled it, right after
// SetDecodeFeedbackFields; the firmware ran the command if it changed.
static uint8_t g_fbBefore[64];
static int g_fbAttached;
// The buffer attached to THIS command. DATA+0x170 moves on afterwards (the
// driver rotates feedback buffers: b37 read 0x4000 past the attached one and
// compared two different buffers), so keep the pointer from attach time.
static uint8_t* g_fbPtr;

static const char* variant_name(int v) {
  switch (v) {
    case 1: return "sw_ctxt_size 128 KiB (Mesa RDECODE_SESSION_CONTEXT_SIZE)";
    case 2: return "variant 1 + context buffer grown by 128 KiB";
    case 3: return "retired (DATA_REALLOC was a no-op)";
    case 4: return "bitstream without its leading 00 00 01 start code";
    case 5: return "decode stream type taken from the create message";
    case 6: return "MPEG-2 Mesa fields (f_code+1, refs 0, P&L 0)";
    case 7: return "CreateContexts mode 3 (Vcn2DecCommand instead of Vcn3DecCommand)";
    case 8: return "decode stream_type forced to 0x11 (VP9) with the codec block kept";
    case 9: return "create-message id 0x13 (AV1) with decode stream_type unchanged";
    case 10: return "as Linux/Mesa sends it (capture b31): hw_ctxt 0, sw_ctxt 128 KiB, "
                    "MPEG-2 refs 0, P&L 0, default quantiser matrices loaded";
    case 15: return "variant 11 + no context-buffer command (0x206) for MPEG-2/VC-1, "
                    "as Mesa";
    case 13: return "variant 11 + mif_wrc_en 0 (Apple's VCN AVC builder never sets it)";
    case 14: return "variant 11 + decode block as Apple's VCN AVC builder: mif_wrc_en, "
                    "db_pitch_uv, db_aligned_height, sw_ctxt_size 0; db_pitch 32-aligned";
    case 12: return "variant 11 + Mesa's db_pitch (32-aligned) and dt bottom "
                    "offsets 0 (MPEG-2/VC-1; VP9 unchanged)";
    case 11: return "variant 10 with Mesa's message layout: two index entries "
                    "(decode, codec block), no DRM block, no 0x0f block";
    default: return "baseline";
  }
}

// The processor object's vtable: built from the class the factory hands back,
// never from the factory's own vtable.
static void* g_vt[VT_SLOTS + 2];
static void** g_class_vt;

static int hook_create_session(uint8_t* proc, void* bi) {
  int r = ((int (*)(void*, void*))g_class_vt[VT_CREATE_SESSION])(proc, bi);
  if (!r) {
    uint8_t* msg = DATA_MSG(DEC_DATA(PROC_DECODER(proc)));
    // Variant 5: remember the driver's own value before the patch below.
    if (g_variant == 5) g_createStreamType = U32(msg, 40);
    // Variant 9: the driver's original create id (AV1 = 0x13) instead of the
    // codec's, so the create and decode messages disagree.
    U32(msg, 40) = g_variant == 9 ? 0x13 : g.codecId;
    if (g.dump && !g_haveCreate) {
      memcpy(g_create, msg, sizeof(g_create));
      g_haveCreate = 1;
    }
  }
  return r;
}

static uint32_t hook_dpb_size(uint8_t* proc) {
  (void)proc;
  return g_dpbSize;
}

static uint32_t hook_ctx_size(uint8_t* proc) {
  (void)proc;
  return g_ctxSize;
}

static void hook_init_ctx(uint8_t* proc) {
  uint8_t* data = DEC_DATA(PROC_DECODER(proc));
  uint8_t* ctx = TEX_CPU(DATA_CTX_TEX(data));
  if (!ctx || !DATA_CTX_SIZE(data)) return;
  // VP9 decodes with the default probability table the firmware derives the
  // frame contexts from; every other codec in the probe has no such table.
  if (g.codecId == VCN_CODEC_VP9)
    vp9probe_init_ctx(ctx, DATA_CTX_SIZE(data));
  else
    memset(ctx, 0, DATA_CTX_SIZE(data));
}

static int hook_set_message(uint8_t* proc, const ProbeParams* prm,
                            uint8_t* target, uint8_t* bi, uint32_t a4,
                            uint32_t a5) {
  (void)a4;
  (void)a5;
  uint8_t* dec = PROC_DECODER(proc);
  uint8_t* data = DEC_DATA(dec);
  uint8_t* hw = HWCONFIG(PROC_VACONTEXT(proc));
  uint32_t streamType = g.codecId;
  if (g_variant == 5 && g_createStreamType) {
    streamType = g_createStreamType;
    printf("variant 5: driver's create-message stream type 0x%x, codec id 0x%x\n",
           streamType, g.codecId);
  }
  // Variant 8: keep the codec block/message id, force the decode stream type
  // to VP9's 0x11. If feedback gets written the firmware ran the command and
  // the legacy codec id is the gate.
  if (g_variant == 8) {
    streamType = 0x11;
    printf("variant 8: decode stream type 0x11 with codec id 0x%x, message 0x%x\n",
           g.codecId, g.messageId);
  }
  // The driver stores the bit depth it decodes at in the processor, and the
  // tuple it reallocates the DPB/context for is {profile, 0, w, h, depth, 0}
  // (AvdVcnAv1DecDataProcessor::SetDecodeMessageFields, 0x7ffb10b42aee-
  // 0x7ffb10b42bb3). The probe must write both or the driver believes the
  // session is 8-bit profile 0 and never reallocates.
  PROC_DEPTH(proc) = g.depth ? g.depth : 8;
  uint32_t tuple[6] = {g.profile, 0, DEC_WIDTH(dec), DEC_HEIGHT(dec),
                       g.depth ? g.depth : 8, 0};
  memcpy(DATA_TUPLE(data), tuple, sizeof(tuple));
  g.data = data;
  g.bi = bi;
  g.proc = proc;
  DATA_DPB_SIZE(data) = g_dpbSize;
  DATA_CTX_SIZE(data) = g_ctxSize;

  MsgGeom m = {.width = DEC_WIDTH(dec),
               .height = DEC_HEIGHT(dec),
               .pitch = TEX_PITCH(target),
               .texh = TEX_HEIGHT(target),
               .bpe = TEX_BPE(target),
               .dpbSize = g_dpbSize,
               .ctxSize = g_ctxSize,
               // Variant 1: Mesa always fills sw_ctxt_size with 128 KiB
               // (RDECODE_SESSION_CONTEXT_SIZE, ac_vcn_dec.c:50,1938); the
               // probe leaves 0, matching Apple's AV1 builder instead.
               .swCtxt = (g_variant == 1 || g_variant == 2 || g_variant >= 10)
                             ? 128 * 1024
                             : 0,
               .hwCtxt = g_variant == 2 ? 65536 : 0,
               .noHwCtxt = g_variant >= 10 && g.codecId != VCN_CODEC_VP9,
               .mesaIndex = g_variant >= 11,
               .mesaGeom = g_variant == 12 && g.codecId != VCN_CODEC_VP9,
               .noMif = g_variant == 13 && g.codecId != VCN_CODEC_VP9,
               .avcStyle = g_variant == 14 && g.codecId != VCN_CODEC_VP9,
               .streamType = streamType,
               .codecId = g.codecId,
               .messageId = g.messageId,
               .blockSize = g.blockSize,
               .block = g.block,
               .data = data,
               .feedback = PROC_FEEDBACK(proc),
               .vc1Simple = g.vc1Simple};
  uint8_t* msg = DATA_MSG(data);
  uint32_t total = fill_message(msg, &m);
  if (!total) {
    printf("decode message: surface offsets do not fit 32 bits; not sending\n");
    return -1;
  }
  U32(msg + decode_off(msg), 16) = DATA_BS_SIZE(data);
  // SetupVcnDRMCommand with no protected content, as vcnvp9.c does. Variant
  // 11 sends no DRM block.
  if (g_variant < 11) {
    uint32_t drmOff = DECODE_OFF + DECODE_SIZE + al(g.blockSize, 4);
    if (U32(hw, 144) & 0x80000)
      U32(msg + drmOff, 56) = 0x1000000u;
    else
      U32(msg + drmOff, 52) = 0x80000000u;
  }

  U32(bi, BI_MSG_ON) = 1;
  *(uint8_t**)(bi + BI_MSG) = DATA_MSG_TEX(data);
  U32(bi, BI_DPB_ON) = 1;
  *(uint8_t**)(bi + BI_DPB) = DATA_DPB_TEX(data);
  U32(bi, BI_TARGET_ON) = 1;
  *(uint8_t**)(bi + BI_TARGET) = target;
  U32(bi, BI_TARGET_OFF) = 0;
  // VP9 keeps its per-frame segment table in the IT buffer; the driver's AV1
  // path allocates one (DATA_IT_TEX) and vcnvp9.c fills it every frame.
  if (g.codecId == VCN_CODEC_VP9 && g.vp9) {
    uint8_t* it = DATA_IT(data);
    if (it) {
      vp9probe_fill_segments(it, g.vp9);
      U32(bi, BI_IT_ON) = 1;
      *(uint8_t**)(bi + BI_IT) = DATA_IT_TEX(data);
    }
  }
  // Variant 15 (non-VP9): no context-buffer command. Mesa sends
  // RDECODE_CMD_CONTEXT_BUFFER only when hw_ctx_size != 0 (ac_vcn_dec.c:2189),
  // so never for MPEG-2/VC-1; the driver's UvdCommand::buildUvdCommand (IDA
  // 25G342 0x7ffb10b14472) emits command 0x206 whenever bi+160 is set. With
  // the message already equal to Linux's, it is the one difference left in
  // the ring packets: session, message, DPB, bitstream, target, feedback are
  // the same six buffers on both sides.
  U32(bi, BI_CTX_ON) = (g_variant == 15 && g.codecId != VCN_CODEC_VP9) ? 0 : 1;
  *(uint8_t**)(bi + BI_CTX) = DATA_CTX_TEX(data);
  if (*((int8_t*)hw + 149) < 0) {
    U32(bi, BI_SESSION_ON) = 1;
    *(uint8_t**)(bi + BI_SESSION) = DATA_SESSION_TEX(data);
  }
  // Which ring format the driver will use for this command:
  // Vcn3DecCommand::buildUvdCommand (IDA 25G342 0x7ffb10b53f4c) takes the
  // unified-queue builder when [command object + 48] != 0, else the register
  // packets Linux uses on VCN 3. The object is VADecoder+256 (DecodePicture).
  {
    uint8_t* cmdObj = PTR(dec, 256);
    if (cmdObj)
      printf("command builder %p: unified-queue flag %u, decode-and-copy %u\n",
             (void*)cmdObj, U32(cmdObj, 48), (unsigned)*(data + 640));
  }
  // What the session actually is, in the driver's own numbers: if the control
  // and the four codecs differ anywhere, it shows here.
  printf(
      "session: codec 0x%x %ux%u depth %u profile %u, dpb %u ctx %u, bs %u, "
      "feedback #%u, target pitch %u height %u bpe %u\n",
      g.codecId, DEC_WIDTH(dec), DEC_HEIGHT(dec), g.depth, g.profile,
      DATA_DPB_SIZE(data), DATA_CTX_SIZE(data), DATA_BS_SIZE(data),
      PROC_FEEDBACK(proc), TEX_PITCH(target), TEX_HEIGHT(target),
      TEX_BPE(target));
  // Report 130(b): the driver turns this build info into ring packets. Dump
  // it so a GPU run can be diffed against a VP9 run.
  printf("bi[0x100]:");
  for (int i = 0; i < 0x100; i++) printf(" %02x", bi[i]);
  printf("\n");
  if (g.dump) {
    printf("decode message built by the hook: %u bytes\n", total);
    dump_bytes("decode message", msg, total);
  }
  return 0;
}

// The factory and the processor it creates are different classes with
// different vtables (vcnvp9.c keeps them apart too): the factory gets only
// createDecodeDataProcessor replaced, the processor object all five message
// slots, and the two arrays are never mixed.
// g_vt and g_class_vt are declared above hook_create_session.
// Slot 15: the driver's own SetDecodeFeedbackFields, which Process calls right
// after SetDecodeMessageFields (AvdVcnAv1DecDataProcessor::Process, IDA 25G342
// 0x7ffb10b428ac: slots 13, 14, 15). It zeroes the first 44 bytes of the
// feedback buffer and writes header 44 / total 44, which is also what a decode
// without errors leaves. Two earlier checks were wrong because of it: b38 saw
// "unchanged", and b39's 0xA5 mark, written from the message hook, was wiped
// by this very call before the submit. So mark the result fields here, AFTER
// the driver's prefill, and keep the pointer: DATA+0x170 rotates afterwards.
// VCNPROBE_NO_FB_MARK=1 leaves the driver's prefill alone.
static int hook_set_feedback(uint8_t* proc, uint8_t* bi) {
  int r = ((int (*)(void*, void*))g_class_vt[VT_SET_FEEDBACK])(proc, bi);
  uint8_t* data = DEC_DATA(PROC_DECODER(proc));
  uint8_t* fb = DATA_FEEDBACK_TEX(data);
  g_fbAttached = 0;
  if (!r && fb) {
    if (!getenv("VCNPROBE_NO_FB_MARK")) memset(fb + 12, 0xA5, 32);
    memcpy(g_fbBefore, fb, sizeof(g_fbBefore));
    g_fbPtr = fb;
    g_fbAttached = 1;
  }
  printf("feedback buffer (driver's slot 15): result %d, cpu %p, bi+0x34 %u, "
         "bi+0x38 %p\n", r, (void*)fb, U32(bi, BI_FEEDBACK_ON),
         *(void**)(bi + BI_FEEDBACK));
  return r;
}

static void init_vt(void) {
  memcpy(g_vt, g_class_vt - 2, sizeof(g_vt));
  void** vt = &g_vt[2];
  vt[VT_CREATE_SESSION] = (void*)hook_create_session;
  vt[VT_DPB_SIZE] = (void*)hook_dpb_size;
  vt[VT_CTX_SIZE] = (void*)hook_ctx_size;
  vt[VT_INIT_CTX] = (void*)hook_init_ctx;
  vt[VT_SET_MESSAGE] = (void*)hook_set_message;
  // Only if slot 15 really is DecodeDataProcessor::SetDecodeFeedbackFields.
  void* sf = dlsym(RTLD_DEFAULT,
                   "_ZN19DecodeDataProcessor23SetDecodeFeedbackFieldsEP23_"
                   "uvd_command_build_info");
  if (sf && g_class_vt[VT_SET_FEEDBACK] == sf)
    vt[VT_SET_FEEDBACK] = (void*)hook_set_feedback;
  else
    printf("slot 15 is not SetDecodeFeedbackFields (%p vs %p): feedback not "
           "marked\n", g_class_vt[VT_SET_FEEDBACK], sf);
}

static void* g_factoryVt[FACTORY_SLOTS + 2];
static void* (*g_orig_create_processor)(void*, int, void*);
static int g_creating;

// Wraps the factory's createDecodeDataProcessor: the driver builds the
// processor and sends the create message inside one call, so this is the only
// moment to swap the vtable pointer on that one object. Other threads may pass
// through here while the factory is wrapped and get the plain object.
static void* hook_create_processor(void* factory, int type, void* decoder) {
  void* proc = g_orig_create_processor(factory, type, decoder);
  if (proc && type == AV1_PROCESSOR_TYPE && g_creating) {
    void** vt = *(void***)proc;
    if (!g_class_vt) g_class_vt = vt;
    if (vt != g_class_vt) {
      fprintf(stderr,
              "the driver's AV1 processor class changed (%p, was %p): "
              "leaving it alone\n",
              (void*)vt, (void*)g_class_vt);
      return proc;
    }
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, init_vt);
    *(void**)proc = (void*)&g_vt[2];
  }
  return proc;
}

// ---------------------------------------------------------------------------
static CFDictionaryRef pixel_buffer_attributes(uint32_t w, uint32_t h) {
  CFMutableDictionaryRef a = CFDictionaryCreateMutable(
      NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFMutableDictionaryRef io = CFDictionaryCreateMutable(
      NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  if (!a || !io) {
    if (a) CFRelease(a);
    if (io) CFRelease(io);
    return NULL;
  }
  CFNumberRef n;
  int32_t v;
#define PUT(key, val)                                    \
  do {                                                   \
    v = (val);                                           \
    n = CFNumberCreate(NULL, kCFNumberSInt32Type, &v);   \
    if (!n) {                                            \
      CFRelease(a);                                      \
      CFRelease(io);                                     \
      return NULL;                                       \
    }                                                    \
    CFDictionarySetValue(a, key, n);                     \
    CFRelease(n);                                        \
  } while (0)
  PUT(kCVPixelBufferPixelFormatTypeKey,
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
  PUT(kCVPixelBufferWidthKey, (int)w);
  PUT(kCVPixelBufferHeightKey, (int)h);
  PUT(kCVPixelBufferBytesPerRowAlignmentKey, 256);
  PUT(kCVPixelBufferPlaneAlignmentKey, 4096);
  PUT(kCVPixelBufferExtendedPixelsBottomKey, (int)(al(h, 64) - h));
#undef PUT
  CFDictionarySetValue(a, kCVPixelBufferIOSurfacePropertiesKey, io);
  // vcnvp9.c and vcnav1.c both set this on their decode targets; without it
  // the control would not be running the same surface creation as production.
  CFDictionarySetValue(a, kCVPixelBufferMetalCompatibilityKey,
                       kCFBooleanTrue);
  CFRelease(io);
  return a;
}

// NV12: plane 1 is interleaved CbCr, so one chroma row is w bytes, not w/2
// (the first version of this function wrote half of every chroma row and the
// files came out short: 518400 instead of 622080 for 720x576). The luma
// min/max/mean is printed because a blank picture and a decoded one differ in
// nothing else the probe can check without a reference.
// Decode status after the wait. The kernel's firmware result is only the ring
// status; the decode status is the VCN feedback buffer, which the driver
// builds in DecodeDataProcessor::SetDecodeFeedbackFields (build_info+0x34/0x38,
// texture at DATA+0x170) and reads in ProcessDecodeStatus as the qword at
// feedback + 8 + 8*[this+0x3C]. The offsets printed here are Mesa's
// rvcn_dec_feedback_header_t (ac_vcn_dec.h:1102-1111); the driver's own reader
// is called too, so the report does not rest on that guess.
// Where did the picture go? MPEG-2/VC-1 report OK in the feedback (b35) and
// leave the target blank, so look at every buffer the probe can read for
// bytes the firmware wrote: non-zero count, first and last non-zero offset.
// Only ranges the task has mapped readable are read.
static int readable(const void* p, size_t n) {
  mach_vm_address_t a = (mach_vm_address_t)(uintptr_t)p;
  mach_vm_size_t sz = 0;
  vm_region_basic_info_data_64_t info;
  mach_msg_type_number_t cnt = VM_REGION_BASIC_INFO_COUNT_64;
  mach_port_t obj = MACH_PORT_NULL;
  if (mach_vm_region(mach_task_self(), &a, &sz, VM_REGION_BASIC_INFO_64,
                     (vm_region_info_t)&info, &cnt, &obj) != KERN_SUCCESS)
    return 0;
  if (obj != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), obj);
  if (a > (mach_vm_address_t)(uintptr_t)p) return 0;
  if (!(info.protection & VM_PROT_READ)) return 0;
  return (uintptr_t)p + n <= a + sz;
}

static void scan_buffer(const char* name, const uint8_t* p, size_t n) {
  if (!p || !n) {
    printf("scan %s: no CPU mapping\n", name);
    return;
  }
  if (!readable(p, n)) {
    printf("scan %s: %p + %zu not mapped readable, skipped\n", name, (void*)p, n);
    return;
  }
  size_t nz = 0, first = 0, last = 0;
  for (size_t i = 0; i < n; i++)
    if (p[i]) {
      if (!nz) first = i;
      last = i;
      nz++;
    }
  if (!nz)
    printf("scan %s: %zu bytes, all zero\n", name, n);
  else
    printf("scan %s: %zu bytes, %zu non-zero, first at 0x%zx, last at 0x%zx\n",
           name, n, nz, first, last);
}

static void scan_buffers(CVPixelBufferRef pb) {
  if (g.data) {
    uint8_t* dpb = DATA_DPB_TEX(g.data);
    scan_buffer("dpb", dpb ? TEX_CPU(dpb) : NULL, g_dpbSize);
    uint8_t* ctx = DATA_CTX_TEX(g.data);
    scan_buffer("context", ctx ? TEX_CPU(ctx) : NULL, g_ctxSize);
    uint8_t* fb = g_fbAttached ? g_fbPtr : DATA_FEEDBACK_TEX(g.data);
    if (fb && readable(fb, 64)) {
      printf("feedback after (64 bytes):");
      for (int i = 0; i < 64; i++) printf(" %02x", fb[i]);
      printf("\n");
    }
  }
  IOSurfaceRef surf = pb ? CVPixelBufferGetIOSurface(pb) : NULL;
  if (surf && !IOSurfaceLock(surf, kIOSurfaceLockReadOnly, NULL)) {
    scan_buffer("target surface (whole allocation)",
                IOSurfaceGetBaseAddress(surf), IOSurfaceGetAllocSize(surf));
    IOSurfaceUnlock(surf, kIOSurfaceLockReadOnly, NULL);
  }
}

static void print_feedback(void) {
  if (!g.data) {
    printf("feedback: no driver data (dry run)\n");
    return;
  }
  // DATA+0x170 is already the CPU address of the feedback buffer: Apple's
  // SetDecodeFeedbackFields writes header_size straight through it and stores
  // the GPU address in DATA+0xE8[index] (bi+0x38). So this is not a texture
  // and has no TEX_CPU mapping; dereferencing +152 is why the first version
  // printed cpu 0x0.
  uint8_t* cpu = g_fbAttached ? g_fbPtr : DATA_FEEDBACK_TEX(g.data);
  if (g_fbAttached && !readable(cpu, 64)) {
    printf("feedback: attached buffer %p is no longer mapped\n", (void*)cpu);
    return;
  }
  // g.bi is not read here: the build info belongs to the driver and is
  // reused after the submit (it printed the picture width at +0x38).
  printf("feedback: cpu %p (DATA+0x170 is now %p)\n", (void*)cpu,
         (void*)DATA_FEEDBACK_TEX(g.data));
  if (!cpu) {
    printf("feedback: no CPU mapping; firmware decode status not readable\n");
    return;
  }
  printf("feedback first 32 bytes:");
  for (int i = 0; i < 32; i++) printf(" %02x", cpu[i]);
  printf("\n");
  printf(
      "feedback header=%u total=%u buffers=%u number=%u status=%u value=%u "
      "errorBits=0x%x\n",
      U32(cpu, 0), U32(cpu, 4), U32(cpu, 8), U32(cpu, 12), U32(cpu, 16),
      U32(cpu, 20), U32(cpu, 24));
  // The driver's own reader: DecodeDataProcessor::ProcessDecodeStatus. Only
  // called if that exact function address is a slot of the processor class,
  // so a wrong slot can never be called.
  void* fn = dlsym(RTLD_DEFAULT,
                   "_ZN19DecodeDataProcessor19ProcessDecodeStatusEPcP19_"
                   "VADecodeStatusInfo");
  if (fn && g_class_vt) {
    for (int i = 0; i < VT_SLOTS; i++) {
      if (g_class_vt[i] != fn) continue;
      uint32_t status = 0xdeadbeef;
      ((int (*)(void*, void*, void*))fn)(g.proc, cpu, &status);
      printf("driver ProcessDecodeStatus: %u (0x%x)\n", status, status);
      break;
    }
  }
  // A zero buffer means the firmware never wrote feedback, so status 0 is not
  // an OK: the first version printed OK for exactly this case.
  int written = 0;
  if (g_fbAttached) {
    // The driver prefilled it (header 9504, status 1, or the 44-byte form),
    // so "non-zero" proves nothing: compare with that prefill instead.
    written = memcmp(cpu, g_fbBefore, sizeof(g_fbBefore)) != 0;
    printf("feedback before:");
    for (int i = 0; i < 32; i++) printf(" %02x", g_fbBefore[i]);
    printf("\nfeedback %s since the prefill\n", written ? "CHANGED" : "unchanged");
  } else {
    for (int i = 0; i < 32; i++)
      if (cpu[i]) written = 1;
  }
  // b41 (VP9): the firmware rewrites bytes 12..23 only (feedback number,
  // status, value) and leaves +24 alone, so a still-marked errorBits field is
  // not an error.
  uint32_t errBits = U32(cpu, 24);
  if (g_fbAttached && errBits == 0xA5A5A5A5u) errBits = 0;
  int ok = written && U32(cpu, 16) == 0 && errBits == 0;
  printf("decode status: %s\n",
         !written ? "NOT EXECUTED (feedback never written)"
                  : ok ? "OK (status 0, errorBits 0)"
                       : "FAILED (firmware reported a decode error)");
  printf("result: %s\n", !written ? "not executed"
                         : !ok    ? "failed"
                         : g_luma_blank == 1 ? "blank"
                                              : "decoded");
}

static int write_nv12(CVPixelBufferRef pb, const char* path) {
  if (CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly)) return -1;
  size_t w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb);
  FILE* f = fopen(path, "wb");
  int rc = 0;
  if (!f) rc = -1;
  for (int plane = 0; plane < 2 && !rc; plane++) {
    const uint8_t* base = CVPixelBufferGetBaseAddressOfPlane(pb, plane);
    if (!base) {
      rc = -1;
      break;
    }
    size_t pitch = CVPixelBufferGetBytesPerRowOfPlane(pb, plane);
    size_t rows = plane ? (h + 1) / 2 : h;
    size_t cols = w;  // luma: w, chroma: w (interleaved CbCr)
    for (size_t y = 0; y < rows && !rc; y++)
      if (fwrite(base + y * pitch, 1, cols, f) != cols) rc = -1;
  }
  if (!rc) {
    const uint8_t* luma = CVPixelBufferGetBaseAddressOfPlane(pb, 0);
    if (!luma) {
      if (f) fclose(f);
      CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
      return -1;
    }
    size_t pitch = CVPixelBufferGetBytesPerRowOfPlane(pb, 0);
    unsigned lo = 255, hi = 0;
    unsigned long long sum = 0;
    for (size_t y = 0; y < h; y++) {
      const uint8_t* row = luma + y * pitch;
      for (size_t x = 0; x < w; x++) {
        unsigned v = row[x];
        if (v < lo) lo = v;
        if (v > hi) hi = v;
        sum += v;
      }
    }
    g_luma_blank = hi == 0;
    printf("luma min %u max %u mean %.2f%s\n", lo, hi,
           w && h ? (double)sum / (double)(w * h) : 0.0,
           hi == 0 ? " (blank)" : "");
  }
  if (f) fclose(f);
  CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  return rc;
}

int vcnprobe_run(const ProbeJob* job, const char* outPath, int gpu, char* err,
                 size_t errLen) {
  if (!job->width || !job->height) {
    snprintf(err, errLen, "job has no size");
    return -1;
  }
  if (job->bitstreamSize > VCN_BS_SIZE - 256) {
    snprintf(err, errLen, "bitstream %zu bytes is over the %u-byte buffer",
             job->bitstreamSize, VCN_BS_SIZE);
    return -1;
  }
  if ((uint64_t)job->width * job->height * 60 > UINT32_MAX) {
    snprintf(err, errLen, "%ux%u overflows the 32-bit pixel-rate field",
             job->width, job->height);
    return -1;
  }
  g.codecId = job->codecId;
  g.messageId = job->messageId;
  g.block = job->block;
  g.blockSize = job->blockSize;
  g.width = job->width;
  g.height = job->height;
  g.profile = job->profile;
  g.depth = job->depth ? job->depth : 8;
  g.vc1Simple = job->vc1Simple;
  g.vp9 = (const VP9Parser*)job->vp9;
  g.dump = 1;
  // Bisect switches for the owner. Dry runs read it too, so the message a
  // variant builds can be checked before it goes to the GPU.
  g_variant = 0;
  {
    const char* vs = getenv("VCNPROBE_VARIANT");
    if (vs && *vs) g_variant = atoi(vs);
  }
  if (g_variant < 0 || g_variant > 15) g_variant = 0;
  if (g_variant == 3) {
    printf("variant 3 is retired: the hook replaces SetDecodeMessageFields, so "
           "DATA_REALLOC never reached the driver; running baseline\n");
    g_variant = 0;
  }
  if (g_variant) printf("variant %d: %s\n", g_variant, variant_name(g_variant));
  uint64_t protoDpb, protoCtx;
  if (job->codecId == VCN_CODEC_VP9) {
    // vcnvp9.c's numbers: 9 pictures of the session size, and Mesa's
    // calc_ctx_size_vp9 for VCN 2 and later (the default probability table
    // lives in the first 2304 bytes of that context).
    protoDpb = (uint64_t)al(job->width, 64) * al(job->height, 64) * 3 / 2 * 9;
    protoCtx = 2304ull * 5 + 32ull * 2 * 128 * 68 + 9ull * 64 * 2 * 128 * 68 +
               8ull * 2 * 2 * 8192;
    if (g.depth == 10) protoCtx += 8ull * 2 * 4096;
  } else {
    protoDpb = (uint64_t)al(job->width, 64) * al(job->height, 64) * 3 / 2 * 4;
    // Variant 10: Mesa asked for more (MPEG-2 720x576: 0x3a4000 against our
    // 0x288000; VC-1 352x288: 0xc8440 against 0xb4000, capture b31), and a
    // firmware that checks dpb_size would drop a smaller one without a word.
    // Six pictures plus 64 KiB covers both.
    if (g_variant >= 10)
      protoDpb = (uint64_t)al(job->width, 64) * al(job->height, 64) * 3 / 2 * 6 +
                 65536;
    protoCtx = 65536;
  }
  // Variant 2: a context buffer with room for Mesa's 128 KiB software context
  // on top of the hardware context (the probe asks the driver for it at
  // create time through hook_ctx_size; see ac_vcn_dec.c:2191 for the ring
  // packet Mesa sends, which the probe cannot build). The header's
  // hw_ctxt_size stays 64 KiB (fill_message's hwCtxt).
  if (g_variant == 2) protoCtx += 128 * 1024;
  if (protoDpb > VCN_MAX_DPB || protoCtx > VCN_MAX_CTX) {
    snprintf(err, errLen, "%ux%u needs dpb %llu / ctx %llu bytes, over the "
             "probe's buffer limits", job->width, job->height,
             (unsigned long long)protoDpb, (unsigned long long)protoCtx);
    return -1;
  }
  g_dpbSize = (uint32_t)protoDpb;
  g_ctxSize = (uint32_t)protoCtx;

  VcnDriverLib lib;
  char why[200];
  if (!vcn_driver_load(&lib, why, sizeof(why))) {
    snprintf(err, errLen, "%s", why);
    return -1;
  }
  printf("driver %s\n", lib.uuid);
  // Same validated builds as vcnav1.c/vcnvp9.c.
  static const char* const ok[] = {"1181E2CA31B33DF090E23AE70552D753",
                                   "8D3BA61E7BC73BDFADB3A7866360B6DE",
                                   "5D90FED3BCBF34759F4B8FC00026D3AB"};
  int validated = 0;
  for (size_t i = 0; i < sizeof(ok) / sizeof(*ok); i++)
    if (!strcmp(lib.uuid, ok[i])) validated = 1;
  if (!validated) {
    snprintf(err, errLen, "driver build %s is not a validated one", lib.uuid);
    return -1;
  }
  if (!gpu) {
    // Dry run: build the same message the hook would, with the geometry the
    // target would have, without opening the accelerator or creating contexts.
    MsgGeom m = {.width = job->width,
                 .height = job->height,
                 .pitch = al(job->width, 256),
                 .texh = al(job->height, 64),
                 .bpe = 1,
                 .dpbSize = g_dpbSize,
                 .ctxSize = g_ctxSize,
                 .swCtxt = (g_variant == 1 || g_variant == 2 || g_variant >= 10)
                               ? 128 * 1024
                               : 0,
                 .hwCtxt = g_variant == 2 ? 65536 : 0,
                 .noHwCtxt = g_variant >= 10 && job->codecId != VCN_CODEC_VP9,
                 .mesaIndex = g_variant >= 11,
                 .mesaGeom = g_variant == 12 && job->codecId != VCN_CODEC_VP9,
                 .noMif = g_variant == 13 && job->codecId != VCN_CODEC_VP9,
                 .avcStyle = g_variant == 14 && job->codecId != VCN_CODEC_VP9,
                 .codecId = job->codecId,
                 .messageId = job->messageId,
                 .blockSize = job->blockSize,
                 .block = job->block,
                 .data = NULL,
                 .feedback = 0,
                 .vc1Simple = g.vc1Simple};
    uint8_t msg[MSG_MAX];
    uint32_t total = fill_message(msg, &m);
    if (!total) {
      snprintf(err, errLen, "surface offsets do not fit 32 bits");
      return -1;
    }
    U32(msg + decode_off(msg), 16) = al((uint32_t)job->bitstreamSize, 128);
    printf("dry run: no ScheduleAVDCommands\n");
    printf("geometry %ux%u pitch %u dpb %u ctx %u block %u\n", m.width,
           m.height, m.pitch, m.dpbSize, m.ctxSize, m.blockSize);
    dump_bytes("decode message", msg, total);
    for (uint32_t i = 0; i < U32(msg, 8); i++)
      printf("index[%u] = type 0x%x off %u size %u\n", i, U32(msg, 24 + 16 * i),
             U32(msg, 28 + 16 * i), U32(msg, 32 + 16 * i));
    printf("decode block codec id = 0x%x, codec block at %u\n",
           U32(msg + decode_off(msg), 0), decode_off(msg) + DECODE_SIZE);
    return 0;
  }
  io_service_t svc = vcn_find_accelerator();
  if (!svc) {
    snprintf(err, errLen, "no AMD accelerator");
    return -1;
  }
  VcnDriverSession s;
  os_log_t log = os_log_create("com.droga.vcncodecprobe", "probe");
  if (!vcn_session_open(&s, &lib, svc, log, why, sizeof(why))) {
    if (log) os_release(log);
    snprintf(err, errLen, "%s", why);
    return -1;
  }

  void* seq = calloc(1, SEQ_BYTES);
  void* frame = calloc(1, FRAME_BYTES);
  void* bsinfo = calloc(1, BSINFO_BYTES);
  CVPixelBufferRef pb = NULL;
  int rc = -1;
  if (!seq || !frame || !bsinfo) {
    snprintf(err, errLen, "out of memory");
    goto done;
  }
  if (gpu) {
    CFDictionaryRef attrs = pixel_buffer_attributes(job->width, job->height);
    int pc = attrs ? (int)CVPixelBufferCreate(
                         kCFAllocatorDefault, job->width, job->height,
                         kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attrs,
                         &pb)
                   : -1;
    if (attrs) CFRelease(attrs);
    if (pc || !pb) {
      snprintf(err, errLen, "no pixel buffer (%d)", pc);
      goto done;
    }
  }

  // CreateContexts with the AV1 function, mode 4 (VCN0), as vcnav1.c does.
  uint8_t* va = *(uint8_t**)((uint8_t*)s.drv + 8);
  if (!va) {
    snprintf(err, errLen, "no VAContext");
    goto done;
  }
  void*** factory = (void***)(*(uint8_t**)(va + 75072));
  if (!factory || !*factory) {
    snprintf(err, errLen, "no factory");
    goto done;
  }
  void** orig = *factory;
  static void** factoryOrigVt;
  if (!factoryOrigVt) {
    memcpy(g_factoryVt, orig - 2, sizeof(g_factoryVt));
    g_orig_create_processor =
        (void* (*)(void*, int, void*))orig[FACTORY_CREATE_PROCESSOR];
    g_factoryVt[2 + FACTORY_CREATE_PROCESSOR] = (void*)hook_create_processor;
    factoryOrigVt = orig;
  } else if (orig != factoryOrigVt) {
    snprintf(err, errLen, "the driver's factory class changed");
    goto done;
  }
  *factory = &g_factoryVt[2];
  g_creating = 1;

  AVD_ContextList list = {0};
  void* ctxOut[2] = {0};
  AVD_FunctionInfo* fis[1] = {&list.inlineInfo};
  list.count = 1;
  list.functions = fis;
  list.contextsOut = ctxOut;
  list.inlineInfo = (AVD_FunctionInfo){
      .kind = 1,
      .function = AVD_FUNC_AV1,
      // Variant 7: mode 3 makes VAFactory::createUVDCommand choose
      // Vcn2DecCommand (switch case 3, VADriver2.asm:21849) instead of the
      // Vcn3DecCommand case 4 our mode 4 gets.
      .mode = g_variant == 7 ? 3 : VCN_MODE_VCN0,
      .pixelRate = (uint32_t)((uint64_t)job->width * job->height * 60),
      .width = job->width,
      .height = job->height,
      .inFormat = 0x72617762,
      .inFormatCount = 1,
      .outFormat = 0x4e563132,
      .outFormatCount = 1};
  AVD_DriverContextInit ci = {.list = &list};
  int r = ((AVD_CreateContexts_fn)s.accel->fn[AVD_FN_CreateContexts])(s.drv,
                                                                     &ci);
  g_creating = 0;
  *factory = orig;
  if (r || !ctxOut[0]) {
    snprintf(err, errLen, "CreateContexts(AV1) %d", r);
    goto done;
  }
  s.ctx = ctxOut[0];

  if (g_haveCreate) {
    dump_bytes("create message (driver's, codec id patched)", g_create,
               sizeof(g_create));
    printf("create message codec id at +40: 0x%x (wanted 0x%x)\n",
           *(uint32_t*)(g_create + 40), g.codecId);
  }

  // Frame block fields the driver's own AV1 code reads (vcnvp9.c).
  *(uint32_t*)((uint8_t*)frame + 308) = job->width - 1;
  *(uint32_t*)((uint8_t*)frame + 312) = job->width;
  *(uint32_t*)((uint8_t*)frame + 316) = job->height - 1;
  *(uint32_t*)((uint8_t*)frame + 320) = job->height;
  const uint8_t* bs = job->bitstream;
  size_t bsSize = job->bitstreamSize;
  // Variant 4: start at the first slice (MPEG-2 slice codes 0x01..0xAF), so the
  // firmware gets slice data without the picture/sequence headers. Other
  // codecs keep the old 4-byte strip.
  if (g_variant == 4) {
    size_t skip = 0;
    if (job->codecId == 3) {  // VCN codec id 3 = MPEG-2
      for (size_t i = 4; i + 3 < bsSize; i++)
        if (!bs[i] && !bs[i + 1] && bs[i + 2] == 1 && bs[i + 3] >= 1 &&
            bs[i + 3] <= 0xAF) {
          skip = i;
          break;
        }
    }
    if (!skip && bsSize > 4 && !bs[0] && !bs[1] && bs[2] == 1) skip = 4;
    if (skip) {
      printf("variant 4: bitstream starts at offset %zu (start code %02x %02x "
             "%02x %02x)\n", skip, bs[skip], bs[skip + 1], bs[skip + 2],
             bs[skip + 3]);
      bs += skip;
      bsSize -= skip;
    }
  }
  memcpy(s.bsAddr[0], bs, bsSize);
  memset((uint8_t*)s.bsAddr[0] + bsSize, 0, 256);
  memset(bsinfo, 0, BSINFO_BYTES);
  *(uint32_t*)((uint8_t*)bsinfo + 0) = 0;  // bitstream buffer index
  *(uint32_t*)((uint8_t*)bsinfo + 16) = al((uint32_t)bsSize, 128);

  ProbeParams prm;
  memset(&prm, 0, sizeof(prm));
  prm.seq = seq;
  prm.frame = frame;
  prm.curr_pic_idx = 0;
  prm.output = CVPixelBufferGetIOSurface(pb);
  prm.bsinfo = bsinfo;
  for (int i = 0; i < 8; i++) prm.ref_frame_map[i] = 0x7f;
  for (int i = 0; i < 7; i++) prm.frame_refs[i] = 0x7f;
  if (!prm.output) {
    snprintf(err, errLen, "pixel buffer without an IOSurface");
    goto done;
  }
  AVD_CmdInfo cmd = {.kind = 1,
                     .function = AVD_FUNC_AV1,
                     .mode = VCN_MODE_VCN0,
                     .context = s.ctx,
                     .params = &prm};
  AVD_CmdInfo* cmds[1] = {&cmd};
  AVD_CmdList cl = {.count = 1, .cmds = cmds};
  void* refcons[1] = {0};
  AVD_RefConList rl = {.count = 1, .refcons = refcons};
  printf("submitting one command (VCNPROBE_ALLOW_GPU set)\n");
  r = ((AVD_ScheduleAVDCommands_fn)s.accel->fn[AVD_FN_ScheduleAVDCommands])(
      s.drv, &cl, &rl);
  if (r) {
    snprintf(err, errLen, "ScheduleAVDCommands %d", r);
    goto done;
  }
  uint32_t fw = 0;
  int ds = 0;
  VcnWaitResult w = vcn_wait_command(
      (AVD_QueryAVDCommandStatus_fn)s.accel->fn[AVD_FN_QueryAVDCommandStatus],
      s.drv, refcons[0], VCN_COMMAND_TIMEOUT_MS, &fw, &ds);
  if (w == VCN_WAIT_TIMEOUT) {
    snprintf(err, errLen,
             "the GPU did not finish the command in %d ms; the queue may be "
             "stuck (do not run another codec in this state)",
             VCN_COMMAND_TIMEOUT_MS);
    goto done;
  }
  if (w != VCN_WAIT_DONE) {
    snprintf(err, errLen, "QueryAVDCommandStatus failed (%d)", ds);
    goto done;
  }
  printf("command done, firmware result 0x%x (0 = no error)\n", fw);
  printf("pixel buffer: %zux%zu, plane 0 pitch %zu, plane 1 pitch %zu\n",
         CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb),
         CVPixelBufferGetBytesPerRowOfPlane(pb, 0),
         CVPixelBufferGetBytesPerRowOfPlane(pb, 1));
  // Luma first: the verdict below uses it to say decoded, blank or not
  // executed.
  if (write_nv12(pb, outPath)) {
    snprintf(err, errLen, "could not write %s", outPath);
    goto done;
  }
  print_feedback();
  scan_buffers(pb);
  printf("wrote %s\n", outPath);
  rc = 0;

done:
  if (pb) CVPixelBufferRelease(pb);
  free(seq);
  free(frame);
  free(bsinfo);
  vcn_session_close(&s);
  if (log) os_release(log);
  return rc;
}
