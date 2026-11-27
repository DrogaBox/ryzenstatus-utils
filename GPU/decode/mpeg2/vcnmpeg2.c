#include "vcnmpeg2.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int vcnmpeg2_index_mode = 1;
int vcnmpeg2_matrix_mode = 0;
int vcnmpeg2_field_mode = 1;

bool vcnmpeg2_fields_allowed(void) {
  const char* allow = getenv("VCNMPEG2_ALLOW_FIELDS");
  return allow && !strcmp(allow, "1");
}

typedef struct {
  Mpeg2Parser parser;
  VcnLegacy* vcn;
  // Mesa's dec->frame_number: one more for each picture sent, fields
  // included.
  uint32_t frameNumber;
  // Numbers of the last two reference frames, [1] the later one, and how many
  // of them this session has decoded.
  uint32_t refNumber[2];
  int refs;
  // The first field of a frame whose second field has not come yet.
  CVPixelBufferRef field;
  uint8_t fieldStructure, fieldType;
  VcnLegacyOutputFn out;
  void* outCtx;
  char err[256];
  int failure;
  unsigned fwErrors;  // of sessions already closed
  // Pictures that did not go to the engine because no session could take
  // them: the ones a sleep took the session away from, and the ones that
  // needed a reference the session rebuilt at the wake does not have yet.
  unsigned dropped;
  bool ramping;  // rebuilt after a sleep: drop what has no reference yet
  bool broken;   // stopped: the stream sent no intra picture after the sleep
} VcnMpeg2;

// Mesa's NUM_MPEG2_REFS: a reference index is kept within the last six
// pictures (get_ref_pic_idx, radeon_vcn_dec.c).
#define NUM_REFS 6

static uint32_t ref_index(uint32_t frameNumber, uint32_t ref) {
  uint32_t min = (frameNumber > NUM_REFS ? frameNumber : NUM_REFS) - NUM_REFS;
  uint32_t max = (frameNumber > 1 ? frameNumber : 1) - 1;
  if (!ref) return max;  // "the most sane fallback"
  return ref > max ? max : ref < min ? min : ref;
}

// m[i] = the entry for the i-th coefficient in the picture's scan order. The
// stream sends a matrix in zigzag order whatever the picture's scan is.
static void scan_matrix(uint8_t* out, const uint8_t* stream, int alternate) {
  if (vcnmpeg2_matrix_mode == 0) {
    memcpy(out, stream, 64);
    return;
  }
  uint8_t block[64];
  for (int i = 0; i < 64; i++) block[mpeg2_zigzag_scan[i]] = stream[i];
  const uint8_t* scan = alternate && vcnmpeg2_matrix_mode != 3
                            ? mpeg2_alternate_scan
                            : mpeg2_zigzag_scan;
  for (int i = 0; i < 64; i++) {
    unsigned at = scan[i];
    if (vcnmpeg2_matrix_mode == 1) at = (at & 7) * 8 + (at >> 3);
    out[i] = block[at];
  }
}

void vcnmpeg2_fill_block(VcnMpeg2Msg* m, const Mpeg2Parser* p,
                         const Mpeg2Picture* pic, uint32_t frameNumber,
                         uint32_t forwardRef, uint32_t backwardRef) {
  memset(m, 0, sizeof(*m));
  if (vcnmpeg2_index_mode == 0) {
    m->decoded_pic_idx = frameNumber;
    m->forward_ref_pic_idx = ref_index(frameNumber, forwardRef);
    m->backward_ref_pic_idx = ref_index(frameNumber, backwardRef);
  }
  m->load_intra_quantiser_matrix = 1;
  m->load_nonintra_quantiser_matrix = 1;
  scan_matrix(m->intra_quantiser_matrix, p->intra_matrix, pic->alternate_scan);
  scan_matrix(m->nonintra_quantiser_matrix, p->nonintra_matrix,
              pic->alternate_scan);
  m->profile_and_level_indication = 0;  // as Mesa
  m->chroma_format = 1;
  m->picture_coding_type = pic->coding_type;
  memcpy(m->f_code, pic->f_code, sizeof(m->f_code));
  m->intra_dc_precision = pic->intra_dc_precision;
  m->pic_structure = pic->picture_structure;
  m->top_field_first = pic->top_field_first;
  m->frame_pred_frame_dct = pic->frame_pred_frame_dct;
  m->concealment_motion_vectors = pic->concealment_motion_vectors;
  m->q_scale_type = pic->q_scale_type;
  m->intra_vlc_format = pic->intra_vlc_format;
  m->alternate_scan = pic->alternate_scan;
}

static void drop_field(VcnMpeg2* d) {
  if (d->field) CVPixelBufferRelease(d->field);
  d->field = NULL;
}

static void end_session(VcnMpeg2* d) {
  drop_field(d);
  if (d->vcn) {
    d->fwErrors += vcnlegacy_firmware_errors(d->vcn);
    vcnlegacy_destroy(d->vcn);
    d->vcn = NULL;
  }
  d->frameNumber = 0;
  d->refs = 0;
  d->refNumber[0] = d->refNumber[1] = 0;
  // The rebuild after a sleep sets ramping back right after end_session.
  d->ramping = false;
  d->dropped = 0;
}

static int on_picture(void* ctx, Mpeg2Parser* p, const Mpeg2Picture* pic) {
  VcnMpeg2* d = ctx;
  if (p->width > VCNLEGACY_MAX_WIDTH || p->height > VCNLEGACY_MAX_HEIGHT) {
    snprintf(d->err, sizeof(d->err), "%ux%u is over the %ux%u this path takes",
             p->width, p->height, VCNLEGACY_MAX_WIDTH, VCNLEGACY_MAX_HEIGHT);
    return -1;
  }
  // Field pictures never reach the GPU unless asked for (vcnmpeg2.h).
  if (pic->picture_structure != MPEG2_FRAME && !vcnmpeg2_fields_allowed()) {
    snprintf(d->err, sizeof(d->err),
             "MPEG-2 field pictures are not decoded on this GPU yet");
    drop_field(d);
    return -1;
  }
  // A new size is a new session: the firmware's reference pictures are of the
  // old one.
  if (d->vcn && (vcnlegacy_width(d->vcn) != p->width ||
                 vcnlegacy_height(d->vcn) != p->height))
    end_session(d);
  // A session from before a system sleep cannot take another picture. An I
  // picture is coded from nothing before it (ISO/IEC 13818-2 6.3.1, Table
  // 6-12: I pictures use no motion-compensated prediction), so it decodes the
  // same in a new session: the pictures up to it are dropped without an error
  // — the host sees the stream carry on — and it starts the new session. A GOP
  // header's closed_gop says the pictures after the I need nothing from the
  // one before (6.2.2.6); with an open GOP, or with broken_link, they predict
  // from the previous GOP, whose pictures this session never decoded, and are
  // dropped by the reference check below (ramping).
  if (d->vcn && vcnlegacy_session_lost(d->vcn)) {
    if (pic->coding_type != MPEG2_I) {
      // Bounded like the AV1 and VP9 rebuilds (REBUILD_MAX_DROPPED there): a
      // stream that sends no intra picture is stopped as a device failure, so
      // the host can hand it to another decoder, instead of dropping pictures
      // for however long the stream goes without one.
      if (++d->dropped > 600) {
        d->broken = true;
        d->failure = VCNLEGACY_FAIL_DEVICE;
        snprintf(d->err, sizeof(d->err),
                 "no intra picture in %u frames after the system sleep",
                 d->dropped);
        return -1;
      }
      return 0;
    }
    vcnlegacy_log_rebuild(d->vcn, "an MPEG-2 I picture", d->dropped);
    end_session(d);
    d->dropped = 0;
    d->ramping = true;
  }
  if (!d->vcn) {
    VcnLegacyConfig cfg = {.codecId = VCN_CODEC_MPEG2_VLD,
                           .messageId = VCN_MESSAGE_MPEG2_VLD,
                           .width = p->width,
                           .height = p->height,
                           .logSubsystem = "com.droga.vtmpeg2vcn"};
    d->vcn = vcnlegacy_create(&cfg, d->err, sizeof(d->err));
    if (!d->vcn) {
      d->failure = VCNLEGACY_FAIL_DEVICE;
      return -1;
    }
  }
  // The second field of a frame is the other parity right after the first.
  bool second = false;
  if (pic->picture_structure != MPEG2_FRAME && d->field &&
      d->fieldStructure + pic->picture_structure == 3)
    second = true;
  else
    drop_field(d);  // a first field whose second never came
  uint8_t type = second ? d->fieldType : pic->coding_type;
  // Every picture a P or B picture predicts from must have been decoded by
  // this session. The second field of a frame also has its first field.
  int need = pic->coding_type == MPEG2_B   ? 2
             : pic->coding_type == MPEG2_P ? 1
                                           : 0;
  if (second && pic->coding_type == MPEG2_P) need = 0;
  if (d->refs < need) {
    if (d->ramping) {
      drop_field(d);
      d->dropped++;
      return 0;
    }
    snprintf(d->err, sizeof(d->err),
             "%s picture without its reference picture%s",
             pic->coding_type == MPEG2_B ? "B" : "P", need == 2 ? "s" : "");
    d->failure = VCNLEGACY_FAIL_REFERENCE;
    return -1;
  }
  CVPixelBufferRef target =
      second ? CVPixelBufferRetain(d->field) : vcnlegacy_new_target(d->vcn);
  if (!target) {
    snprintf(d->err, sizeof(d->err), "no pixel buffer for %ux%u", p->width,
             p->height);
    d->failure = VCNLEGACY_FAIL_MEMORY;
    return -1;
  }
  // Field mode 1: the second field keeps the number of its first field.
  bool shared = second && vcnmpeg2_field_mode == 1;
  uint32_t n = shared ? d->frameNumber : ++d->frameNumber;
  uint32_t fwd = 0, back = 0;
  if (pic->coding_type == MPEG2_P) {
    fwd = d->refs ? d->refNumber[1] : 0;
  } else if (pic->coding_type == MPEG2_B) {
    fwd = d->refNumber[0];
    back = d->refNumber[1];
  }
  VcnMpeg2Msg msg;
  vcnmpeg2_fill_block(&msg, p, pic, n, fwd, back);
  // The second P field of the first frame predicts only from its first
  // field: that is its own number, which ref_index would move back by one.
  if (shared && vcnmpeg2_index_mode == 0 && pic->coding_type == MPEG2_P &&
      !d->refs)
    msg.forward_ref_pic_idx = n;
  VcnLegacyBytes part = {pic->slices, pic->slicesSize};
  if (vcnlegacy_decode(d->vcn, &msg, sizeof(msg), &part, 1, target)) {
    snprintf(d->err, sizeof(d->err), "%s", vcnlegacy_last_error(d->vcn));
    d->failure = vcnlegacy_failure(d->vcn);
    CVPixelBufferRelease(target);
    drop_field(d);
    return -1;
  }
  if (pic->picture_structure != MPEG2_FRAME && !second) {
    // Wait for the other field; nothing is shown yet.
    drop_field(d);
    d->field = target;
    d->fieldStructure = pic->picture_structure;
    d->fieldType = pic->coding_type;
    return 0;
  }
  drop_field(d);
  if (type != MPEG2_B) {
    d->refNumber[0] = d->refNumber[1];
    d->refNumber[1] = n;
    if (d->refs < 2) d->refs++;
  }
  if (d->ramping && d->refs >= 2) d->ramping = false;
  int stop = d->out ? d->out(d->outCtx, target,
                             type == MPEG2_B ? VCNLEGACY_PIC_B
                                             : VCNLEGACY_PIC_REFERENCE,
                             p->width, p->height)
                    : 0;
  CVPixelBufferRelease(target);
  if (stop) p->stop = true;
  return 0;
}

static void* create(const uint8_t* config, size_t configSize, uint32_t width,
                    uint32_t height, char* err, size_t errLen) {
  (void)config, (void)configSize, (void)width, (void)height;
  VcnMpeg2* d = calloc(1, sizeof(*d));
  if (!d) {
    if (err && errLen) snprintf(err, errLen, "out of memory");
    return NULL;
  }
  mpeg2_parser_init(&d->parser);
  // The driver session is made at the first sequence header: only that says
  // the size.
  return d;
}

static void destroy(void* v) {
  VcnMpeg2* d = v;
  if (!d) return;
  end_session(d);
  free(d);
}

static int decode(void* v, const uint8_t* chunk, size_t size,
                  VcnLegacyOutputFn fn, void* ctx) {
  VcnMpeg2* d = v;
  d->out = fn;
  d->outCtx = ctx;
  d->err[0] = 0;
  d->failure = VCNLEGACY_FAIL_STREAM;
  if (d->broken) {
    snprintf(d->err, sizeof(d->err),
             "session stopped: no intra picture in %u frames after the "
             "system sleep",
             d->dropped);
    d->failure = VCNLEGACY_FAIL_DEVICE;
    return -1;
  }
  int r = mpeg2_parse_chunk(&d->parser, chunk, size, on_picture, d);
  if (r && !d->err[0]) {
    snprintf(d->err, sizeof(d->err), "%s",
             d->parser.err[0] ? d->parser.err : "bitstream error");
    if (d->parser.missing_sequence) d->failure = VCNLEGACY_FAIL_REFERENCE;
  }
  return r ? -1 : 0;
}

static const char* last_error(void* v) { return v ? ((VcnMpeg2*)v)->err : ""; }
static int failure(void* v) {
  return v ? ((VcnMpeg2*)v)->failure : VCNLEGACY_FAIL_DEVICE;
}
static unsigned firmware_errors(void* v) {
  VcnMpeg2* d = v;
  return d ? d->fwErrors + vcnlegacy_firmware_errors(d->vcn) : 0;
}

const VcnLegacyCodec vcnmpeg2_codec = {.name = "mpeg2",
                                       .create = create,
                                       .destroy = destroy,
                                       .decode = decode,
                                       .last_error = last_error,
                                       .failure = failure,
                                       .firmware_errors = firmware_errors};
