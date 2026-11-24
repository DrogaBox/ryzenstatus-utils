#include "vc1parse.h"

#include "bitreader.h"

// Sequence header, advanced profile. Field order from FFmpeg's
// decode_sequence_header_adv (libavcodec/vc1.c), which is the only public
// description of the advanced-profile bit layout.
static int parse_sequence(const uint8_t* d, size_t n, size_t at,
                          Vc1Picture* out, char* err, size_t errLen) {
  BitReader b;
  br_init(&b, d + at + 4, n - at - 4);
  out->profile = (uint8_t)br_get(&b, 2);
  out->level = (uint8_t)br_get(&b, 3);
  out->chroma_format = (uint8_t)br_get(&b, 2);
  br_get(&b, 3);  // frmrtq_postproc
  br_get(&b, 5);  // bitrtq_postproc
  out->postprocflag = (uint8_t)br_get(&b, 1);
  out->au.width = (br_get(&b, 12) + 1) * 2;  // max_coded_width
  out->au.height = (br_get(&b, 12) + 1) * 2;
  out->pulldown = (uint8_t)br_get(&b, 1);  // broadcast
  out->interlace = (uint8_t)br_get(&b, 1);
  out->tfcntrflag = (uint8_t)br_get(&b, 1);
  out->finterpflag = (uint8_t)br_get(&b, 1);
  br_get(&b, 1);  // reserved
  out->psf = (uint8_t)br_get(&b, 1);
  if (br_get(&b, 1)) {    // display extension
    br_get(&b, 14);       // display_horiz_size
    br_get(&b, 14);       // display_vert_size
    if (br_get(&b, 1)) {  // aspect_ratio_flag
      if (br_get(&b, 4) == 15) {
        br_get(&b, 8);  // aspect_horiz_size
        br_get(&b, 8);  // aspect_vert_size
      }
    }
    if (br_get(&b, 1)) {    // framerate_flag
      if (br_get(&b, 1)) {  // framerateind
        br_get(&b, 16);     // frameratenr
      } else {
        br_get(&b, 8);  // frameratenr
        br_get(&b, 4);  // frameratedr
      }
    }
    if (br_get(&b, 1)) {  // color_format_flag
      br_get(&b, 8);      // color_prim
      br_get(&b, 8);      // transfer_char
      br_get(&b, 8);      // matrix_coef
    }
  }
  if (br_get(&b, 1)) {  // hrd_param_flag
    uint32_t buckets = br_get(&b, 5);
    br_get(&b, 4);  // bitrate exponent
    br_get(&b, 4);  // buffer size exponent
    for (uint32_t i = 0; i < buckets && !b.err; i++) {
      br_get(&b, 16);  // hrd_rate
      br_get(&b, 16);  // hrd_buffer
    }
  }
  if (b.err || !out->au.width || !out->au.height) {
    copy_err(err, errLen, "VC-1 sequence header too short");
    return -1;
  }
  if (out->profile != 3) {
    copy_err(err, errLen, "VC-1 sample is not advanced profile");
    return -1;
  }
  return 0;
}

// Entry point (FFmpeg ff_vc1_decode_entry_point). Its coded size replaces the
// sequence header's maximum, and that is the size the surface is made at: the
// RTVC1 sample says 640x480 in the sequence header and 352x288 here, and
// FFmpeg decodes it at 352x288.
static void parse_entry(const uint8_t* d, size_t n, size_t at, Vc1Picture* o) {
  BitReader b;
  br_init(&b, d + at + 4, n - at - 4);
  br_get(&b, 1);  // broken_link
  br_get(&b, 1);  // closed_entry
  o->panscan = (uint8_t)br_get(&b, 1);
  o->refdist_flag = (uint8_t)br_get(&b, 1);
  o->loopfilter = (uint8_t)br_get(&b, 1);
  o->fastuvmc = (uint8_t)br_get(&b, 1);
  o->extended_mv = (uint8_t)br_get(&b, 1);
  o->dquant = (uint8_t)br_get(&b, 2);
  o->vstransform = (uint8_t)br_get(&b, 1);
  o->overlap = (uint8_t)br_get(&b, 1);
  br_get(&b, 2);        // quantizer_mode
  if (br_get(&b, 1)) {  // coded_size_flag
    uint32_t w = (br_get(&b, 12) + 1) * 2, h = (br_get(&b, 12) + 1) * 2;
    if (!b.err && w && h) {
      o->au.width = w;
      o->au.height = h;
    }
  }
  if (b.err) return;
  if (o->extended_mv) o->extended_dmv = (uint8_t)br_get(&b, 1);
  // range_mapy/range_mapuv follow; FFmpeg cannot scale either and neither can
  // this probe, so a stream that sets them is not accepted.
  if (!b.err && br_get(&b, 1)) o->range_mapy = 1;
  if (!b.err && br_get(&b, 1)) o->range_mapuv = 1;
}

// Frame coding mode and picture type of the frame header at `f`, per FFmpeg's
// ff_vc1_parse_frame_header_adv: with the sequence header's interlace flag
// clear, fcm is PROGRESSIVE and not coded at all; otherwise it is a decode012.
// ptype is then get_unary(0, 4): 0 P, 1 B, 2 I, 3 BI, 4 skipped P.
static int frame_type(const uint8_t* d, size_t n, size_t f, int interlace,
                      int* fcm, int* ptype) {
  BitReader b;
  br_init(&b, d + f + 4, n - f - 4);
  int mode = 0;
  if (interlace) {
    mode = (int)br_get(&b, 1);
    if (mode) mode = 1 + (int)br_get(&b, 1);
  }
  if (mode == 2) {  // field picture: fptype is 3 bits
    uint32_t fptype = br_get(&b, 3);
    *ptype = (fptype & 4) ? 3 : (fptype & 2) ? 0 : 2;
  } else {
    uint32_t u = 0;
    while (!b.err && u < 4 && br_get(&b, 1) == 1) u++;
    *ptype = (int)u;
  }
  *fcm = mode;
  return b.err ? -1 : 0;
}

int vc1_parse(const uint8_t* data, size_t size, Vc1Picture* out, char* err,
              size_t errLen) {
  memset(out, 0, sizeof(*out));
  out->pic_structure = 3;
  size_t seq = find_start(data, size, 0, 0x0F);
  if (seq == (size_t)-1) {
    copy_err(err, errLen, "no VC-1 sequence header (00 00 01 0F)");
    return -1;
  }
  if (parse_sequence(data, size, seq, out, err, errLen)) return -1;

  // Walk the frames of the stream in order, tracking the last entry point seen
  // (its flags and coded size are what applies to the next frame).
  size_t at = seq + 4;
  Vc1Picture ep;
  memset(&ep, 0, sizeof(ep));
  uint32_t seqW = out->au.width, seqH = out->au.height;
  for (int tries = 0; tries < 4096; tries++) {
    uint8_t code = 0;
    size_t nxt = find_any_start(data, size, at, &code);
    if (nxt == (size_t)-1) break;
    if (code == 0x0E) {
      memset(&ep, 0, sizeof(ep));
      parse_entry(data, size, nxt, &ep);
      ep.au.width = ep.au.width ? ep.au.width : seqW;
      ep.au.height = ep.au.height ? ep.au.height : seqH;
      at = nxt + 4;
      continue;
    }
    if (code != 0x0D) {
      at = nxt + 4;
      continue;
    }
    int fcm = 0, ptype = -1;
    if (frame_type(data, size, nxt, out->interlace, &fcm, &ptype) == 0 &&
        fcm == 0 && ptype == 2) {
      // Apply the entry point in effect.
      out->panscan = ep.panscan;
      out->refdist_flag = ep.refdist_flag;
      out->loopfilter = ep.loopfilter;
      out->fastuvmc = ep.fastuvmc;
      out->extended_mv = ep.extended_mv;
      out->extended_dmv = ep.extended_dmv;
      out->dquant = ep.dquant;
      out->vstransform = ep.vstransform;
      out->overlap = ep.overlap;
      out->range_mapy = ep.range_mapy;
      out->range_mapuv = ep.range_mapuv;
      if (ep.au.width) out->au.width = ep.au.width;
      if (ep.au.height) out->au.height = ep.au.height;
      if (out->range_mapy || out->range_mapuv) {
        copy_err(err, errLen, "VC-1 range mapping is not supported");
        return -1;
      }
      // Default bitstream: sequence header + entry point + this frame, the
      // chunk Mesa hands to the VLD engine. VCNPROBE_PIC_AU=1 sends the frame
      // header only (the old behaviour).
      size_t picEnd = au_end_for(AU_VC1, data, size, nxt, nxt + 4);
      out->picAu.au = data + nxt;
      out->picAu.auSize = picEnd - nxt;
      out->au.au = data + seq;
      out->au.auSize = picEnd - seq;
      out->au.intra = 1;
      return 0;
    }
    at = nxt + 4;
  }
  copy_err(err, errLen, "no progressive VC-1 I frame in the stream");
  return -1;
}
