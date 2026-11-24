#include "vcnvc1.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  Vc1Parser parser;
  VcnLegacy* vcn;
  int refs;  // reference frames this session has decoded, at most 2
  CVPixelBufferRef lastRef;  // the later one's picture, for a skipped frame
  VcnLegacyOutputFn out;
  void* outCtx;
  char err[256];
  int failure;
  unsigned fwErrors;  // of sessions already closed
} VcnVc1;

// Bit positions of Mesa's get_vc1_msg (radeon_vcn_dec.c) and build_vc1_msg
// (ac_vcn_dec.c); the levels are the fixed ones Mesa sends per profile.
void vcnvc1_fill_block(VcnVc1Msg* m, const Vc1Parser* p) {
  memset(m, 0, sizeof(*m));
  if (p->profile == VC1_PROFILE_ADVANCED) {
    m->profile = VCN_VC1_ADVANCED;
    m->level = 4;
  } else if (p->profile == VC1_PROFILE_MAIN) {
    m->profile = VCN_VC1_MAIN;
    m->level = 2;
  } else {
    m->profile = VCN_VC1_SIMPLE;
    m->level = 1;
  }
  uint32_t sps = 0, pps = 0;
  sps |= (uint32_t)p->postprocflag << 7;
  sps |= (uint32_t)p->pulldown << 6;
  sps |= (uint32_t)p->interlace << 5;
  sps |= (uint32_t)p->tfcntrflag << 4;
  sps |= (uint32_t)p->finterpflag << 3;
  sps |= (uint32_t)p->psf << 1;
  pps |= (uint32_t)p->range_mapy_flag << 31;
  pps |= (uint32_t)p->range_mapy << 28;
  pps |= (uint32_t)p->range_mapuv_flag << 27;
  pps |= (uint32_t)p->range_mapuv << 24;
  pps |= (uint32_t)p->multires << 21;
  pps |= (uint32_t)p->maxbframes << 16;
  pps |= (uint32_t)p->overlap << 11;
  pps |= (uint32_t)p->quantizer << 9;
  pps |= (uint32_t)p->panscan_flag << 7;
  pps |= (uint32_t)p->refdist_flag << 6;
  pps |= (uint32_t)p->vstransform << 0;
  if (p->profile != VC1_PROFILE_SIMPLE) {
    pps |= (uint32_t)p->syncmarker << 20;
    pps |= (uint32_t)p->rangered << 19;
    pps |= (uint32_t)p->loopfilter << 5;
    pps |= (uint32_t)p->fastuvmc << 4;
    pps |= (uint32_t)p->extended_mv << 3;
    pps |= (uint32_t)p->extended_dmv << 8;
    pps |= (uint32_t)p->dquant << 1;
  }
  m->sps_info_flags = sps;
  m->pps_info_flags = pps;
  m->chroma_format = 1;
}

static void end_session(VcnVc1* d) {
  if (d->lastRef) CVPixelBufferRelease(d->lastRef);
  d->lastRef = NULL;
  if (d->vcn) {
    d->fwErrors += vcnlegacy_firmware_errors(d->vcn);
    vcnlegacy_destroy(d->vcn);
    d->vcn = NULL;
  }
  d->refs = 0;
}

static bool is_b(uint8_t type) { return type == VC1_B || type == VC1_BI; }

static int on_picture(void* ctx, Vc1Parser* p, const Vc1Picture* pic) {
  VcnVc1* d = ctx;
  if (p->width > VCNLEGACY_MAX_WIDTH || p->height > VCNLEGACY_MAX_HEIGHT) {
    snprintf(d->err, sizeof(d->err), "%ux%u is over the %ux%u this path takes",
             p->width, p->height, VCNLEGACY_MAX_WIDTH, VCNLEGACY_MAX_HEIGHT);
    return -1;
  }
  // A new coded size (an entry point may change it) is a new session.
  if (d->vcn && (vcnlegacy_width(d->vcn) != p->width ||
                 vcnlegacy_height(d->vcn) != p->height))
    end_session(d);
  if (!d->vcn) {
    VcnLegacyConfig cfg = {
        .codecId = VCN_CODEC_VC1,
        .messageId = VCN_MESSAGE_VC1,
        .width = p->width,
        .height = p->height,
        .sizeInMacroblocks = p->profile != VC1_PROFILE_ADVANCED,
        .logSubsystem = "com.droga.vtvc1vcn"};
    d->vcn = vcnlegacy_create(&cfg, d->err, sizeof(d->err));
    if (!d->vcn) {
      d->failure = VCNLEGACY_FAIL_DEVICE;
      return -1;
    }
  }
  // The firmware finds the reference pictures itself, so the session only
  // makes sure it has decoded them: none for an intra frame, one for P and
  // skipped frames, two for B. A field-interlaced frame whose first field is I
  // needs none (its P field predicts from the I field).
  int need = pic->type == VC1_B                                 ? 2
             : (pic->type == VC1_P || pic->type == VC1_SKIPPED) ? 1
                                                                : 0;
  if (d->refs < need) {
    snprintf(d->err, sizeof(d->err), "VC-1 frame without its reference frame%s",
             need == 2 ? "s" : "");
    d->failure = VCNLEGACY_FAIL_REFERENCE;
    return -1;
  }
  // A skipped frame of the simple and main profiles is a sample of one byte
  // or none (vc1parse.c): it repeats the reference frame before it, and there
  // is nothing for the firmware to decode. An advanced profile skipped frame
  // has a frame header and goes to the GPU like a P frame.
  if (pic->type == VC1_SKIPPED && p->profile != VC1_PROFILE_ADVANCED) {
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
  VcnVc1Msg msg;
  vcnvc1_fill_block(&msg, p);
  // The bitstream starts at the frame start code. With the sequence header
  // and entry point in front of it the firmware reports no error and writes
  // a blank picture (seen on the GPU, 2026-11-23).
  // Mesa's VA-API front end puts the frame start code back when the container
  // dropped it (picture.c, start_code_vc1), and FFmpeg hands the two fields
  // of a field-interlaced frame over one at a time, the second from its
  // 00 00 01 0C on: two commands into the same picture.
  static const uint8_t kFrameStart[4] = {0, 0, 1, 0x0D};
  VcnLegacyBytes parts[2];
  int n = 0;
  if (pic->needStartCode) parts[n++] = (VcnLegacyBytes){kFrameStart, 4};
  size_t first = pic->secondField ? pic->secondField : pic->size;
  parts[n++] = (VcnLegacyBytes){pic->data, first};
  int r = vcnlegacy_decode(d->vcn, &msg, sizeof(msg), parts, n, target);
  if (!r && pic->secondField) {
    VcnLegacyBytes second = {pic->data + pic->secondField,
                             pic->size - pic->secondField};
    r = vcnlegacy_decode(d->vcn, &msg, sizeof(msg), &second, 1, target);
  }
  if (r) {
    snprintf(d->err, sizeof(d->err), "%s", vcnlegacy_last_error(d->vcn));
    d->failure = vcnlegacy_failure(d->vcn);
    CVPixelBufferRelease(target);
    return -1;
  }
  if (!is_b(pic->type)) {
    if (d->refs < 2) d->refs++;
    if (d->lastRef) CVPixelBufferRelease(d->lastRef);
    d->lastRef = CVPixelBufferRetain(target);
  }
  int stop = d->out ? d->out(d->outCtx, target,
                             is_b(pic->type) ? VCNLEGACY_PIC_B
                                             : VCNLEGACY_PIC_REFERENCE,
                             p->width, p->height)
                    : 0;
  CVPixelBufferRelease(target);
  if (stop) p->stop = true;
  return 0;
}

// config: an advanced profile sequence header and entry point with their
// start codes (what follows the seven fixed bytes of a dvc1 atom, or the
// codec private data of ASF and Matroska after its first byte), or the
// STRUCT_C bytes of a simple/main stream.
static void* create(const uint8_t* config, size_t configSize, uint32_t width,
                    uint32_t height, char* err, size_t errLen) {
  VcnVc1* d = calloc(1, sizeof(*d));
  if (!d) {
    if (err && errLen) snprintf(err, errLen, "out of memory");
    return NULL;
  }
  vc1_parser_init(&d->parser);
  if (config && configSize) {
    size_t sc = 0;
    while (sc + 3 < configSize &&
           !(config[sc] == 0 && config[sc + 1] == 0 && config[sc + 2] == 1))
      sc++;
    int r = sc + 3 < configSize ? vc1_parse_chunk(&d->parser, config + sc,
                                                  configSize - sc, NULL, NULL)
                                : vc1_parse_struct_c(&d->parser, config,
                                                     configSize, width, height);
    if (r) {
      if (err && errLen) snprintf(err, errLen, "%s", d->parser.err);
      free(d);
      return NULL;
    }
  }
  return d;
}

static void destroy(void* v) {
  VcnVc1* d = v;
  if (!d) return;
  end_session(d);
  free(d);
}

static int decode(void* v, const uint8_t* chunk, size_t size,
                  VcnLegacyOutputFn fn, void* ctx) {
  VcnVc1* d = v;
  d->out = fn;
  d->outCtx = ctx;
  d->err[0] = 0;
  d->failure = VCNLEGACY_FAIL_STREAM;
  bool raw =
      d->parser.have_sequence && d->parser.profile != VC1_PROFILE_ADVANCED;
  int r = raw ? vc1_parse_frame(&d->parser, chunk, size, on_picture, d)
              : vc1_parse_chunk(&d->parser, chunk, size, on_picture, d);
  if (r && !d->err[0]) {
    snprintf(d->err, sizeof(d->err), "%s",
             d->parser.err[0] ? d->parser.err : "bitstream error");
    if (d->parser.missing_sequence) d->failure = VCNLEGACY_FAIL_REFERENCE;
  }
  return r ? -1 : 0;
}

static const char* last_error(void* v) { return v ? ((VcnVc1*)v)->err : ""; }
static int failure(void* v) {
  return v ? ((VcnVc1*)v)->failure : VCNLEGACY_FAIL_DEVICE;
}
static unsigned firmware_errors(void* v) {
  VcnVc1* d = v;
  return d ? d->fwErrors + vcnlegacy_firmware_errors(d->vcn) : 0;
}

const VcnLegacyCodec vcnvc1_codec = {.name = "vc1",
                                     .create = create,
                                     .destroy = destroy,
                                     .decode = decode,
                                     .last_error = last_error,
                                     .failure = failure,
                                     .firmware_errors = firmware_errors};
