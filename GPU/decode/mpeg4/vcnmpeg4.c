#include "vcnmpeg4.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int vcnmpeg4_index_mode = 0;
int vcnmpeg4_block_mode = 0;
int vcnmpeg4_cut_mode = 0;

static uint16_t al16(uint32_t v) { return (uint16_t)((v + 15) & ~15u); }

typedef struct {
  Mpeg4Parser parser;
  VcnLegacy* vcn;
  uint32_t frameNumber;   // one more for each VOP sent
  uint32_t refNumber[2];  // of the last two reference VOPs, [1] the later
  int refs;
  CVPixelBufferRef lastRef;  // the later one's picture, for a VOP not coded
  VcnLegacyOutputFn out;
  void* outCtx;
  char err[256];
  int failure;
  unsigned fwErrors;  // of sessions already closed
  // VOPs that did not go to the engine because no session could take them:
  // the ones a sleep took the session away from, and the ones that needed a
  // reference the session rebuilt at the wake does not have yet.
  unsigned dropped;
  bool ramping;  // rebuilt after a sleep: drop what has no reference yet
} VcnMpeg4;

#define NUM_REFS 6  // Mesa uses NUM_MPEG2_REFS for this codec too

static uint32_t ref_index(uint32_t frameNumber, uint32_t ref) {
  uint32_t min = (frameNumber > NUM_REFS ? frameNumber : NUM_REFS) - NUM_REFS;
  uint32_t max = (frameNumber > 1 ? frameNumber : 1) - 1;
  if (!ref) return max;
  return ref > max ? max : ref < min ? min : ref;
}

void vcnmpeg4_fill_block(VcnMpeg4Msg* m, const Mpeg4Parser* p,
                         const Mpeg4Picture* pic, uint32_t frameNumber,
                         uint32_t forwardRef, uint32_t backwardRef) {
  memset(m, 0, sizeof(*m));
  if (vcnmpeg4_index_mode == 0) {
    m->decoded_pic_idx = frameNumber;
    m->forward_ref_pic_idx = ref_index(frameNumber, forwardRef);
    m->backward_ref_pic_idx = ref_index(frameNumber, backwardRef);
  }
  // Aligned to whole macroblocks, as Mesa's radeon_create_decoder makes
  // dec->base.width/height for this codec (mesa-25.0.0 radeon_vcn_dec.c,
  // get_mpeg4_msg): 1920x1080 goes out as 1920x1088.
  m->video_object_layer_width = al16(p->width);
  m->video_object_layer_height = al16(p->height);
  m->vop_time_increment_resolution = p->time_increment_resolution;
  uint32_t fl = VCN_MPEG4_COMPLEXITY_ESTIMATION_DISABLE;
  if (p->interlaced) fl |= VCN_MPEG4_INTERLACED;
  if (p->quarter_sample) fl |= VCN_MPEG4_QUARTER_SAMPLE;
  if (p->resync_marker_disable) fl |= VCN_MPEG4_RESYNC_MARKER_DISABLE;
  m->quant_type = p->quant_type;
  // Mesa's radeon_uvd.c and radeon_vcn_dec.c send the same block: ASP level
  // 0, version 5, both matrices always loaded, the VOP part left empty (their
  // comment lists trd, trb and the VOP fields as not filled).
  if (vcnmpeg4_block_mode != 1) {
    m->profile_and_level_indication = 0xF0;
    m->video_object_layer_verid = 5;
    fl |= VCN_MPEG4_LOAD_INTRA_QUANT_MAT | VCN_MPEG4_LOAD_NONINTRA_QUANT_MAT;
    memcpy(m->intra_quant_mat, p->intra_matrix, 64);
    memcpy(m->nonintra_quant_mat, p->nonintra_matrix, 64);
    // Mode 2: and the B-VOP's time distances, which direct mode scales its
    // motion vectors by. Mode 3: the whole VOP part.
    if (vcnmpeg4_block_mode == 2) {
      m->vop.TRB[0] = m->vop.TRB[1] = pic->trb;
      m->vop.TRD[0] = m->vop.TRD[1] = pic->trd;
    }
    if (vcnmpeg4_block_mode == 3) {
      m->vop.vop_data_present = 1;
      m->vop.vop_coding_type = pic->coding_type;
      m->vop.vop_quant = pic->quant;
      m->vop.vop_coded = 1;
      m->vop.vop_rounding_type = pic->rounding_type;
      m->vop.intra_dc_vlc_thr = pic->intra_dc_vlc_thr;
      m->vop.top_field_first = pic->top_field_first;
      m->vop.alternate_vertical_scan_flag = pic->alternate_vertical_scan;
      m->vop.vop_fcode_forward = pic->fcode_forward;
      m->vop.vop_fcode_backward = pic->fcode_backward;
      m->vop.TRB[0] = m->vop.TRB[1] = pic->trb;
      m->vop.TRD[0] = m->vop.TRD[1] = pic->trd;
    }
  } else {
    m->profile_and_level_indication = p->profile_and_level;
    m->video_object_layer_verid = p->verid;
    if (p->obmc_disable) fl |= VCN_MPEG4_OBMC_DISABLE;
    if (p->quant_type) {
      fl |= VCN_MPEG4_LOAD_INTRA_QUANT_MAT | VCN_MPEG4_LOAD_NONINTRA_QUANT_MAT;
      memcpy(m->intra_quant_mat, p->intra_matrix, 64);
      memcpy(m->nonintra_quant_mat, p->nonintra_matrix, 64);
    }
    m->vop.vop_data_present = 1;
    m->vop.vop_coding_type = pic->coding_type;
    m->vop.vop_quant = pic->quant;
    m->vop.vop_coded = 1;
    m->vop.vop_rounding_type = pic->rounding_type;
    m->vop.intra_dc_vlc_thr = pic->intra_dc_vlc_thr;
    m->vop.top_field_first = pic->top_field_first;
    m->vop.alternate_vertical_scan_flag = pic->alternate_vertical_scan;
    m->vop.vop_fcode_forward = pic->fcode_forward;
    m->vop.vop_fcode_backward = pic->fcode_backward;
    m->vop.TRB[0] = m->vop.TRB[1] = pic->trb;
    m->vop.TRD[0] = m->vop.TRD[1] = pic->trd;
  }
  m->feature_flags = fl;
}

// VCNMPEG4_ALLOW_B=1 is for experiments only (see on_picture).
static bool b_vops_allowed(void) {
  const char* allow = getenv("VCNMPEG4_ALLOW_B");
  return allow && !strcmp(allow, "1");
}

static void end_session(VcnMpeg4* d) {
  if (d->lastRef) CVPixelBufferRelease(d->lastRef);
  d->lastRef = NULL;
  if (d->vcn) {
    d->fwErrors += vcnlegacy_firmware_errors(d->vcn);
    vcnlegacy_destroy(d->vcn);
    d->vcn = NULL;
  }
  d->frameNumber = 0;
  d->refs = 0;
  d->refNumber[0] = d->refNumber[1] = 0;
}

static int on_picture(void* ctx, Mpeg4Parser* p, const Mpeg4Picture* pic) {
  VcnMpeg4* d = ctx;
  if (p->width > VCNLEGACY_MAX_WIDTH || p->height > VCNLEGACY_MAX_HEIGHT) {
    snprintf(d->err, sizeof(d->err), "%ux%u is over the %ux%u this path takes",
             p->width, p->height, VCNLEGACY_MAX_WIDTH, VCNLEGACY_MAX_HEIGHT);
    return -1;
  }
  if (d->vcn && (vcnlegacy_width(d->vcn) != p->width ||
                 vcnlegacy_height(d->vcn) != p->height))
    end_session(d);
  // A session from before a system sleep cannot take another VOP. An I-VOP is
  // intra coded and uses no motion compensation from another VOP (ISO/IEC
  // 14496-2 6.3.3, vop_coding_type in Table 6-7), so it decodes the same in a
  // new session: the VOPs up to it are dropped without an error — the host
  // sees the stream carry on — and it starts the new session. The VOL and its
  // size are what a new sequence can change, and both come with the session
  // (the size check above, vcnmpeg4_fill_block for the flags). The P-VOPs
  // after it that predict from a VOP this session never decoded are dropped by
  // the reference check below (ramping).
  if (d->vcn && vcnlegacy_session_lost(d->vcn)) {
    if (pic->coding_type != MPEG4_I) {
      d->dropped++;
      return 0;
    }
    vcnlegacy_log_rebuild(d->vcn, "an MPEG-4 I-VOP", d->dropped);
    end_session(d);
    d->dropped = 0;
    d->ramping = true;
  }
  if (!d->vcn) {
    VcnLegacyConfig cfg = {.codecId = VCN_CODEC_MPEG4,
                           .messageId = VCN_MESSAGE_MPEG4_ASP_VLD,
                           .width = p->width,
                           .height = p->height,
                           .alignSizeTo16 = true,
                           .logSubsystem = "com.droga.vtmpeg4vcn"};
    d->vcn = vcnlegacy_create(&cfg, d->err, sizeof(d->err));
    if (!d->vcn) {
      d->failure = VCNLEGACY_FAIL_DEVICE;
      return -1;
    }
  }
  // B-VOPs never go to the GPU: on the RX 6800 XT each one kept the firmware
  // busy about 2 s with no picture, and the third in a row hung the video
  // engine until a forced reboot (2026-11-23). VCNMPEG4_ALLOW_B=1 is for
  // experiments only.
  if (pic->coding_type == MPEG4_B && pic->vop_coded && !b_vops_allowed()) {
    snprintf(d->err, sizeof(d->err),
             "MPEG-4 B-VOPs are not decoded on this GPU yet");
    return -1;
  }
  // Direct mode scales the co-located motion vectors by TRB / TRD. A B-VOP
  // whose reference VOPs carry the same time (or times the parser could not
  // order) has TRD 0, and a firmware that divides by it unguarded may never
  // finish: such a B-VOP never goes to the GPU, whatever VCNMPEG4_ALLOW_B
  // says. It fails as a missing reference, on which FFmpeg goes on with the
  // next frame.
  if (pic->coding_type == MPEG4_B && pic->vop_coded && !pic->trd) {
    snprintf(d->err, sizeof(d->err),
             "MPEG-4 B-VOP with no time distance between its reference VOPs "
             "(TRD 0); not sent to the GPU");
    d->failure = VCNLEGACY_FAIL_REFERENCE;
    return -1;
  }
  int need = pic->coding_type == MPEG4_B   ? 2
             : pic->coding_type == MPEG4_P ? 1
                                           : 0;
  if (!pic->vop_coded) need = 1;
  if (d->refs < need) {
    if (d->ramping) {
      d->dropped++;
      return 0;
    }
    snprintf(d->err, sizeof(d->err), "VOP without its reference VOP%s",
             need == 2 ? "s" : "");
    d->failure = VCNLEGACY_FAIL_REFERENCE;
    return -1;
  }
  // A VOP that is not coded repeats the reference picture before it; nothing
  // goes to the GPU.
  if (!pic->vop_coded) {
    int stop = d->out ? d->out(d->outCtx, d->lastRef, VCNLEGACY_PIC_REFERENCE,
                               p->width, p->height)
                      : 0;
    if (stop) p->stop = true;
    return 0;
  }
  CVPixelBufferRef target = vcnlegacy_new_target(d->vcn);
  if (!target) {
    snprintf(d->err, sizeof(d->err), "no pixel buffer for %ux%u", p->width,
             p->height);
    d->failure = VCNLEGACY_FAIL_MEMORY;
    return -1;
  }
  uint32_t n = ++d->frameNumber;
  uint32_t fwd = 0, back = 0;
  if (pic->coding_type == MPEG4_P) {
    fwd = d->refNumber[1];
  } else if (pic->coding_type == MPEG4_B) {
    fwd = d->refNumber[0];
    back = d->refNumber[1];
  }
  VcnMpeg4Msg msg;
  vcnmpeg4_fill_block(&msg, p, pic, n, fwd, back);
  // Cut mode 1 (experiments only): from the VOP start code on, without the
  // headers in front of it (visual object sequence, VOL, GOV). Mesa's VA path
  // never sends a VOL in the bitstream either.
  size_t skip = vcnmpeg4_cut_mode == 1 ? pic->vopOffset : 0;
  VcnLegacyBytes part = {pic->data + skip, pic->size - skip};
  if (vcnlegacy_decode(d->vcn, &msg, sizeof(msg), &part, 1, target)) {
    snprintf(d->err, sizeof(d->err), "%s", vcnlegacy_last_error(d->vcn));
    d->failure = vcnlegacy_failure(d->vcn);
    CVPixelBufferRelease(target);
    return -1;
  }
  bool b = pic->coding_type == MPEG4_B;
  if (!b) {
    d->refNumber[0] = d->refNumber[1];
    d->refNumber[1] = n;
    if (d->refs < 2) d->refs++;
    if (d->lastRef) CVPixelBufferRelease(d->lastRef);
    d->lastRef = CVPixelBufferRetain(target);
  }
  if (d->ramping && d->refs >= 2) d->ramping = false;
  int stop = d->out ? d->out(d->outCtx, target,
                             b ? VCNLEGACY_PIC_B : VCNLEGACY_PIC_REFERENCE,
                             p->width, p->height)
                    : 0;
  CVPixelBufferRelease(target);
  if (stop) p->stop = true;
  return 0;
}

// config: the visual object sequence, visual object and video object layer
// headers, with their start codes (the decoder specific info of an esds
// atom; anything in front of the first start code is skipped).
// A configuration whose VOL does not rule B-VOPs out is refused here, before
// the first sample, instead of stopping at the first B-VOP (on_picture refuses
// those): VideoToolbox then tries the next decoder. On macOS that is AppleMP4V,
// which takes plain Simple profile only, so such a stream gets no decoder and
// the app uses its own (tests/legacypick.c).
static void* create(const uint8_t* config, size_t configSize, uint32_t width,
                    uint32_t height, char* err, size_t errLen) {
  (void)width, (void)height;
  VcnMpeg4* d = calloc(1, sizeof(*d));
  if (!d) {
    if (err && errLen) snprintf(err, errLen, "out of memory");
    return NULL;
  }
  mpeg4_parser_init(&d->parser);
  const char* why = NULL;
  if (config && configSize &&
      mpeg4_parse_chunk(&d->parser, config, configSize, NULL, NULL))
    why = d->parser.err;
  else if (d->parser.have_vol && !d->parser.no_b_vops && !b_vops_allowed())
    why =
        "MPEG-4 stream that can carry B-VOPs (its VOL does not set low_delay); "
        "B-VOPs are not decoded on this GPU yet";
  if (why) {
    if (err && errLen) snprintf(err, errLen, "%s", why);
    free(d);
    return NULL;
  }
  return d;
}

static void destroy(void* v) {
  VcnMpeg4* d = v;
  if (!d) return;
  end_session(d);
  free(d);
}

static int decode(void* v, const uint8_t* chunk, size_t size,
                  VcnLegacyOutputFn fn, void* ctx) {
  VcnMpeg4* d = v;
  d->out = fn;
  d->outCtx = ctx;
  d->err[0] = 0;
  d->failure = VCNLEGACY_FAIL_STREAM;
  int r = mpeg4_parse_chunk(&d->parser, chunk, size, on_picture, d);
  if (r && !d->err[0]) {
    snprintf(d->err, sizeof(d->err), "%s",
             d->parser.err[0] ? d->parser.err : "bitstream error");
    if (d->parser.missing_vol) d->failure = VCNLEGACY_FAIL_REFERENCE;
  }
  return r ? -1 : 0;
}

static const char* last_error(void* v) { return v ? ((VcnMpeg4*)v)->err : ""; }
static int failure(void* v) {
  return v ? ((VcnMpeg4*)v)->failure : VCNLEGACY_FAIL_DEVICE;
}
static unsigned firmware_errors(void* v) {
  VcnMpeg4* d = v;
  return d ? d->fwErrors + vcnlegacy_firmware_errors(d->vcn) : 0;
}

const VcnLegacyCodec vcnmpeg4_codec = {.name = "mpeg4",
                                       .create = create,
                                       .destroy = destroy,
                                       .decode = decode,
                                       .last_error = last_error,
                                       .failure = failure,
                                       .firmware_errors = firmware_errors};
