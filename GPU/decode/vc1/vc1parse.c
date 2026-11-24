#include "vc1parse.h"

#include <stdio.h>
#include <string.h>

#include "bitreader.h"

void vc1_parser_init(Vc1Parser* p) { memset(p, 0, sizeof(*p)); }

static int fail(Vc1Parser* p, const char* what) {
  snprintf(p->err, sizeof(p->err), "%s", what);
  return -1;
}

// Advanced profile headers are escaped like H.264 (00 00 03 before a byte of
// 3 or less). Copies at most cap bytes without the escapes.
static size_t unescape(uint8_t* out, size_t cap, const uint8_t* in, size_t n) {
  size_t o = 0;
  for (size_t i = 0; i < n && o < cap; i++) {
    if (i >= 2 && in[i] == 3 && !in[i - 1] && !in[i - 2] && i + 1 < n &&
        in[i + 1] <= 3)
      continue;
    out[o++] = in[i];
  }
  return o;
}

// FFmpeg's decode_sequence_header_adv is the public description of this
// layout (SMPTE 421M 6.1).
static int sequence_header(Vc1Parser* p, const uint8_t* d, size_t n) {
  uint8_t buf[256];
  BitReader b;
  br_init(&b, buf, unescape(buf, sizeof(buf), d, n));
  Vc1Parser s = {0};
  s.profile = (uint8_t)br_get(&b, 2);
  if (s.profile != VC1_PROFILE_ADVANCED)
    return fail(p,
                "VC-1 sequence header of a start-code stream is not "
                "advanced profile");
  s.level = (uint8_t)br_get(&b, 3);
  uint32_t chroma = br_get(&b, 2);
  br_get(&b, 3);  // frmrtq_postproc
  br_get(&b, 5);  // bitrtq_postproc
  s.postprocflag = (uint8_t)br_get(&b, 1);
  s.max_width = (br_get(&b, 12) + 1) * 2;
  s.max_height = (br_get(&b, 12) + 1) * 2;
  s.pulldown = (uint8_t)br_get(&b, 1);
  s.interlace = (uint8_t)br_get(&b, 1);
  s.tfcntrflag = (uint8_t)br_get(&b, 1);
  s.finterpflag = (uint8_t)br_get(&b, 1);
  br_get(&b, 1);  // reserved
  s.psf = (uint8_t)br_get(&b, 1);
  if (br_get(&b, 1)) {  // display_ext
    br_get(&b, 14);
    br_get(&b, 14);
    if (br_get(&b, 1) && br_get(&b, 4) == 15) br_get(&b, 16);  // aspect ratio
    if (br_get(&b, 1)) {                                       // framerate_flag
      if (br_get(&b, 1))
        br_get(&b, 16);
      else
        br_get(&b, 12);
    }
    if (br_get(&b, 1)) br_get(&b, 24);  // colour description
  }
  s.hrd_param_flag = (uint8_t)br_get(&b, 1);
  if (s.hrd_param_flag) s.hrd_buckets = (uint8_t)br_get(&b, 5);
  if (b.err) return fail(p, "VC-1 sequence header too short");
  if (chroma != 1) return fail(p, "VC-1 chroma format is not 4:2:0");
  s.maxbframes = 7;  // what FFmpeg tells VA-API for the advanced profile
  s.have_sequence = true;
  s.width = s.max_width;
  s.height = s.max_height;
  *p = s;
  return 0;
}

// FFmpeg's ff_vc1_decode_entry_point (SMPTE 421M 6.2).
static int entry_point(Vc1Parser* p, const uint8_t* d, size_t n) {
  if (!p->have_sequence) return 0;
  uint8_t buf[64];
  BitReader b;
  br_init(&b, buf, unescape(buf, sizeof(buf), d, n));
  br_get(&b, 1);  // broken_link
  br_get(&b, 1);  // closed_entry
  uint8_t panscan = (uint8_t)br_get(&b, 1);
  uint8_t refdist = (uint8_t)br_get(&b, 1);
  uint8_t loopfilter = (uint8_t)br_get(&b, 1);
  uint8_t fastuvmc = (uint8_t)br_get(&b, 1);
  uint8_t extended_mv = (uint8_t)br_get(&b, 1);
  uint8_t dquant = (uint8_t)br_get(&b, 2);
  uint8_t vstransform = (uint8_t)br_get(&b, 1);
  uint8_t overlap = (uint8_t)br_get(&b, 1);
  uint8_t quantizer = (uint8_t)br_get(&b, 2);
  if (p->hrd_param_flag) br_skip(&b, 8u * p->hrd_buckets);
  uint32_t w = p->max_width, h = p->max_height;
  if (br_get(&b, 1)) {  // coded_size_flag
    w = (br_get(&b, 12) + 1) * 2;
    h = (br_get(&b, 12) + 1) * 2;
  }
  uint8_t extended_dmv = extended_mv ? (uint8_t)br_get(&b, 1) : 0;
  uint8_t mapy_flag = (uint8_t)br_get(&b, 1);
  uint8_t mapy = mapy_flag ? (uint8_t)br_get(&b, 3) : 0;
  uint8_t mapuv_flag = (uint8_t)br_get(&b, 1);
  uint8_t mapuv = mapuv_flag ? (uint8_t)br_get(&b, 3) : 0;
  if (b.err) return fail(p, "VC-1 entry point header too short");
  p->panscan_flag = panscan;
  p->refdist_flag = refdist;
  p->loopfilter = loopfilter;
  p->fastuvmc = fastuvmc;
  p->extended_mv = extended_mv;
  p->extended_dmv = extended_dmv;
  p->dquant = dquant;
  p->vstransform = vstransform;
  p->overlap = overlap;
  p->quantizer = quantizer;
  p->range_mapy_flag = mapy_flag;
  p->range_mapy = mapy;
  p->range_mapuv_flag = mapuv_flag;
  p->range_mapuv = mapuv;
  p->width = w;
  p->height = h;
  p->have_entry = true;
  return 0;
}

// Frame coding mode and picture type, the first bits of an advanced profile
// frame (FFmpeg's ff_vc1_parse_frame_header_adv, SMPTE 421M 7.1.1).
static int frame_type_adv(const Vc1Parser* p, const uint8_t* d, size_t n,
                          Vc1Picture* pic) {
  uint8_t buf[8];
  BitReader b;
  br_init(&b, buf, unescape(buf, sizeof(buf), d, n));
  pic->fcm = VC1_PROGRESSIVE;
  if (p->interlace && br_get(&b, 1))
    pic->fcm = br_get(&b, 1) ? VC1_FIELD_INTERLACE : VC1_FRAME_INTERLACE;
  if (pic->fcm == VC1_FIELD_INTERLACE) {
    // FPTYPE: 0 I/I, 1 I/P, 2 P/I, 3 P/P, 4 B/B, 5 B/BI, 6 BI/B, 7 BI/BI.
    static const uint8_t first[8] = {VC1_I, VC1_I, VC1_P,  VC1_P,
                                     VC1_B, VC1_B, VC1_BI, VC1_BI};
    static const uint8_t second[8] = {VC1_I, VC1_P,  VC1_I, VC1_P,
                                      VC1_B, VC1_BI, VC1_B, VC1_BI};
    uint32_t fptype = br_get(&b, 3);
    pic->type = first[fptype];
    pic->secondFieldType = second[fptype];
  } else {
    uint32_t ones = 0;
    while (!b.err && ones < 4 && br_get(&b, 1)) ones++;
    pic->type = (uint8_t)ones;  // 0 P, 10 B, 110 I, 1110 BI, 1111 skipped
    pic->secondFieldType = pic->type;
  }
  return b.err ? -1 : 0;
}

static int emit_adv(Vc1Parser* p, const uint8_t* frame, size_t size,
                    size_t secondField, bool needStartCode, Vc1PictureFn fn,
                    void* ctx) {
  if (!p->have_sequence || !p->have_entry) {
    p->missing_sequence = true;
    return fail(p, "VC-1 frame before its sequence and entry point headers");
  }
  Vc1Picture pic = {.data = frame,
                    .size = size,
                    .needStartCode = needStartCode,
                    .secondField = secondField};
  size_t skip = needStartCode ? 0 : 4;
  if (size <= skip || frame_type_adv(p, frame + skip, size - skip, &pic))
    return fail(p, "VC-1 frame header too short");
  if (pic.fcm != VC1_FIELD_INTERLACE) pic.secondField = 0;
  return fn ? fn(ctx, p, &pic) : 0;
}

int vc1_parse_chunk(Vc1Parser* p, const uint8_t* data, size_t size,
                    Vc1PictureFn fn, void* ctx) {
  p->err[0] = 0;
  p->stop = false;
  p->missing_sequence = false;
  size_t at = next_start_code(data, size, 0);
  // No start code at all, or data before the first one: a frame whose own
  // start code the container left out (ASF and Matroska do).
  if (at > 0 && size) {
    size_t end = at;
    // The frame may still hold field and slice start codes of its own.
    size_t field = 0;
    while (end < size) {
      uint8_t code = data[end + 3];
      if (code != 0x0B && code != 0x0C && code < 0x1B) break;
      if (code == 0x0C && !field) field = end;
      end = next_start_code(data, size, end + 4);
    }
    int r = emit_adv(p, data, end, field, true, fn, ctx);
    if (r || p->stop) return r;
    at = end;
  }
  size_t frame = size, field = 0;
  while (at < size) {
    uint8_t code = data[at + 3];
    size_t next = next_start_code(data, size, at + 4);
    // Field (0C), slice (0B) and user data (1B..1F) belong to the frame they
    // follow; anything else ends it.
    bool inFrame =
        code == 0x0B || code == 0x0C || (code >= 0x1B && code <= 0x1F);
    if (!inFrame && frame < size) {
      int r = emit_adv(p, data + frame, at - frame, field, false, fn, ctx);
      frame = size;
      field = 0;
      if (r || p->stop) return r;
    }
    int r = 0;
    if (code == 0x0F)
      r = sequence_header(p, data + at + 4, next - at - 4);
    else if (code == 0x0E)
      r = entry_point(p, data + at + 4, next - at - 4);
    else if (code == 0x0D)
      frame = at;
    else if (code == 0x0C && frame < size && !field)
      field = at - frame;
    if (r) return r;
    at = next;
  }
  if (frame < size)
    return emit_adv(p, data + frame, size - frame, field, false, fn, ctx);
  return 0;
}

// FFmpeg's ff_vc1_decode_sequence_header for the simple and main profiles
// (SMPTE 421M annex J, STRUCT_C).
int vc1_parse_struct_c(Vc1Parser* p, const uint8_t* hdr, size_t size,
                       uint32_t width, uint32_t height) {
  p->err[0] = 0;
  BitReader b;
  br_init(&b, hdr, size);
  Vc1Parser s = {0};
  s.profile = (uint8_t)br_get(&b, 2);
  if (s.profile != VC1_PROFILE_SIMPLE && s.profile != VC1_PROFILE_MAIN)
    return fail(p, "VC-1 header is not simple or main profile");
  uint32_t y411 = br_get(&b, 1), sprite = br_get(&b, 1);
  br_get(&b, 3);  // frmrtq_postproc
  br_get(&b, 5);  // bitrtq_postproc
  s.loopfilter = (uint8_t)br_get(&b, 1);
  uint32_t x8 = br_get(&b, 1);
  s.multires = (uint8_t)br_get(&b, 1);
  br_get(&b, 1);  // res_fasttx
  s.fastuvmc = (uint8_t)br_get(&b, 1);
  s.extended_mv = (uint8_t)br_get(&b, 1);
  s.dquant = (uint8_t)br_get(&b, 2);
  s.vstransform = (uint8_t)br_get(&b, 1);
  uint32_t transtab = br_get(&b, 1);
  s.overlap = (uint8_t)br_get(&b, 1);
  s.syncmarker = (uint8_t)br_get(&b, 1);
  s.rangered = (uint8_t)br_get(&b, 1);
  s.maxbframes = (uint8_t)br_get(&b, 3);
  s.quantizer = (uint8_t)br_get(&b, 2);
  s.finterpflag = (uint8_t)br_get(&b, 1);
  if (b.err) return fail(p, "VC-1 simple/main header shorter than four bytes");
  // WMV3 variants FFmpeg decodes in software only (sprites are the WMVP and
  // WVP2 image codecs; X8 intra frames are WMV2's).
  if (y411 || sprite || x8 || transtab)
    return fail(p, "VC-1 simple/main stream uses a WMV extension");
  if (!width || !height)
    return fail(p, "VC-1 simple/main stream without a size");
  s.level = s.profile == VC1_PROFILE_MAIN ? 2 : 0;
  s.width = s.max_width = width;
  s.height = s.max_height = height;
  s.have_sequence = s.have_entry = true;
  *p = s;
  return 0;
}

// FFmpeg's ff_vc1_parse_frame_header (SMPTE 421M 7.1.1, simple/main).
int vc1_parse_frame(Vc1Parser* p, const uint8_t* data, size_t size,
                    Vc1PictureFn fn, void* ctx) {
  p->err[0] = 0;
  p->stop = false;
  p->missing_sequence = false;
  if (!p->have_sequence || p->profile == VC1_PROFILE_ADVANCED) {
    p->missing_sequence = true;
    return fail(p, "VC-1 simple/main frame without its header");
  }
  Vc1Picture pic = {.data = data, .size = size, .fcm = VC1_PROGRESSIVE};
  // A frame of one byte or less is a skipped frame (FFmpeg: buf_size <= 1).
  if (size <= 1) {
    pic.type = VC1_SKIPPED;
  } else {
    BitReader b;
    br_init(&b, data, size);
    if (p->finterpflag) br_get(&b, 1);
    br_get(&b, 2);  // framecnt
    if (p->rangered) br_get(&b, 1);
    if (br_get(&b, 1))
      pic.type = VC1_P;
    else if (p->maxbframes && !br_get(&b, 1))
      pic.type = VC1_B;  // B or BI: neither is a reference
    else
      pic.type = VC1_I;
    if (b.err) return fail(p, "VC-1 frame header too short");
  }
  pic.secondFieldType = pic.type;
  return fn ? fn(ctx, p, &pic) : 0;
}
