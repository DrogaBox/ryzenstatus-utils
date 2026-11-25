// colortest: the colour of the decoded pictures, without the GPU. It checks:
//
//   1. CoreVideo names the H.273 code points the plug-ins use (BT.709,
//      BT.2020, PQ, HLG) and has no name for "unspecified";
//   2. AV1: the parser reads the colour config of a 10-bit sequence header,
//      and keeps the HDR_MDCV and HDR_CLL metadata OBUs; av1_hdr_mdcv and
//      av1_hdr_cll give the HEVC SEI layout CoreVideo takes (primaries
//      green, blue, red; 0.00002 and 0.0001 cd/m2 units);
//   3. AV1: a metadata OBU cut short, one of another type and one with a
//      broken type field change nothing and are not errors; a later one
//      replaces the earlier one;
//   4. VP9: a profile 2 key frame header gives color_space BT.2020 and
//      video range; a refused header leaves them as they were; color_space
//      names primaries and matrix, never the transfer; vpcC version 1 gives
//      its three code points, version 0 none;
//   5. the format description's colour extensions are read back into code
//      points, and the attachments set on a real pixel buffer are the names
//      and bytes asked for, and are taken off again.
//
// usage: colortest   (exit status 0 = pass)
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <stdio.h>
#include <string.h>

#include "av1parse.h"
#include "obuwrite.h"
#include "vp9parse.h"
#include "vtcolor.h"

static int failures;
static void expect(const char* what, bool ok) {
  printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) failures++;
}
static bool same(CFTypeRef a, CFTypeRef b) {
  return a == b || (a && b && CFEqual(a, b));
}

// Typical HDR10 mastering display (P3 primaries, D65, 1000 / 0.005 cd/m2),
// in AV1's fixed point, red, green, blue.
static const uint16_t kPX[3] = {44564, 17367, 9830};
static const uint16_t kPY[3] = {20972, 45220, 3932};
// The same in the HEVC SEI layout: G, B, R, white point, max, min.
static const uint8_t kMdcv[24] = {
    0x33, 0xc2, 0x86, 0xc4, 0x1d, 0x4c, 0x0b, 0xb8, 0x84, 0xd0, 0x3e, 0x80,
    0x3d, 0x13, 0x40, 0x42, 0x00, 0x98, 0x96, 0x80, 0x00, 0x00, 0x00, 0x32};

static int no_frames(void* ctx, AV1Parser* p, AV1ParseResult kind) {
  (void)ctx, (void)p, (void)kind;
  return -1;
}

static void test_names(void) {
  expect(
      "CoreVideo names H.273 primaries 1 and 9",
      same(vt_primaries_name(1), kCVImageBufferColorPrimaries_ITU_R_709_2) &&
          same(vt_primaries_name(9), kCVImageBufferColorPrimaries_ITU_R_2020));
  expect(
      "CoreVideo names transfer 1, 16 (PQ) and 18 (HLG)",
      same(vt_transfer_name(1), kCVImageBufferTransferFunction_ITU_R_709_2) &&
          same(vt_transfer_name(16),
               kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ) &&
          same(vt_transfer_name(18),
               kCVImageBufferTransferFunction_ITU_R_2100_HLG));
  expect("CoreVideo names matrix 1, 6 and 9",
         same(vt_matrix_name(1), kCVImageBufferYCbCrMatrix_ITU_R_709_2) &&
             same(vt_matrix_name(6), kCVImageBufferYCbCrMatrix_ITU_R_601_4) &&
             same(vt_matrix_name(9), kCVImageBufferYCbCrMatrix_ITU_R_2020));
  expect("matrix 5 (BT.470BG) is BT.601 too",
         same(vt_matrix_name(5), kCVImageBufferYCbCrMatrix_ITU_R_601_4));
  expect("a code point CoreVideo has only a made-up name for has none",
         !vt_primaries_name(4) && !vt_transfer_name(4) && !vt_matrix_name(8) &&
             vt_transfer_name(14));  // 14: BT.2020 10-bit, named as BT.709
  expect("unspecified (2) and not given (-1) have no name",
         !vt_primaries_name(2) && !vt_transfer_name(2) && !vt_matrix_name(2) &&
             !vt_primaries_name(-1) && !vt_transfer_name(-1) &&
             !vt_matrix_name(-1));
}

static void test_av1(void) {
  AV1Parser p;
  av1_parser_init(&p);
  uint8_t tu[512];
  size_t n = obu_sequence_header(tu, 0, 0, 10, 9, 16, 9, 0);
  n = obu_mdcv(tu, n, kPX, kPY, 20493, 21561, 1000 << 8, 82, 0);
  n = obu_cll(tu, n, 1000, 400);
  expect("AV1: a sequence header and HDR metadata parse",
         !av1_parse_temporal_unit(&p, tu, n, no_frames, NULL));
  expect("AV1: 10 bits, BT.2020 PQ, video range",
         p.seq.valid && p.seq.BitDepth == 10 &&
             p.seq.color_description_present_flag &&
             p.seq.color_primaries == 9 &&
             p.seq.transfer_characteristics == 16 &&
             p.seq.matrix_coefficients == 9 && p.seq.color_range == 0);
  uint8_t m[24], c[4];
  expect("AV1: the mastering display in the HEVC SEI layout",
         av1_hdr_mdcv(&p.hdr, m) && !memcmp(m, kMdcv, 24));
  static const uint8_t kCll[4] = {0x03, 0xe8, 0x01, 0x90};
  expect("AV1: the content light level in the HEVC SEI layout",
         av1_hdr_cll(&p.hdr, c) && !memcmp(c, kCll, 4));

  // Damaged or other metadata: nothing changes, no error.
  AV1HdrMetadata before = p.hdr;
  n = obu_mdcv(tu, 0, kPX, kPY, 1, 1, 1, 1, 1);  // one byte short
  uint8_t other[3] = {4, 0xb5, 0};               // ITU-T T.35
  n = obu_append(tu, n, 5, other, sizeof(other));
  uint8_t badType[2] = {0x80, 0x80};  // leb128 that never ends
  n = obu_append(tu, n, 5, badType, sizeof(badType));
  uint8_t cutCll[4] = {1, 0, 1, 0};  // type + 3 bytes
  n = obu_append(tu, n, 5, cutCll, sizeof(cutCll));
  n = obu_append(tu, n, 5, other, 0);  // no payload at all
  expect("AV1: cut, unknown and broken metadata OBUs are not errors",
         !av1_parse_temporal_unit(&p, tu, n, no_frames, NULL));
  expect("AV1: ... and change nothing",
         !memcmp(&before, &p.hdr, sizeof(before)));
  n = obu_cll(tu, 0, 4000, 1000);
  av1_parse_temporal_unit(&p, tu, n, no_frames, NULL);
  expect(
      "AV1: a later light level replaces the earlier, the mastering "
      "display stays",
      p.hdr.max_cll == 4000 && p.hdr.max_fall == 1000 && p.hdr.has_mdcv);
  AV1HdrMetadata none = {0};
  expect("AV1: no metadata, no bytes",
         !av1_hdr_mdcv(&none, m) && !av1_hdr_cll(&none, c));
  // Rounding and limits: 1.0 in 0.16 is over HEVC's 50000; 0.5 is 25000.
  AV1HdrMetadata edge = {.has_mdcv = true,
                         .primary_x = {65535, 32768, 0},
                         .luminance_max = UINT32_MAX,
                         .luminance_min = UINT32_MAX};
  av1_hdr_mdcv(&edge, m);
  expect("AV1: chromaticity stays within 0..50000, luminance within 32 bits",
         m[8] == 0xc3 && m[9] == 0x4f &&        // red x 65535 -> 49999
             m[0] == 0x61 && m[1] == 0xa8 &&    // green x 0.5 -> 25000
             m[16] == 0xff && m[19] == 0xff &&  // max saturates
             m[20] == 0x9c && m[23] == 0xff);   // min fits: 0x9c3fffff
  av1_parser_free(&p);

  // A 12-bit profile 2 header reads as 12 bits (vcnav1.c refuses it).
  av1_parser_init(&p);
  n = obu_sequence_header(tu, 0, 2, 12, 9, 16, 9, 0);
  expect("AV1: a 12-bit profile 2 header reads as 12 bits",
         !av1_parse_temporal_unit(&p, tu, n, no_frames, NULL) &&
             p.seq.BitDepth == 12 && p.seq.seq_profile == 2);
  av1_parser_free(&p);
}

// A VP9 profile 2 key frame, 64x64, 10 bits, color_space BT.2020.
typedef struct {
  uint8_t d[64];
  size_t pos;
} BW;
static void put(BW* w, uint32_t v, int n) {
  for (int i = n - 1; i >= 0; i--, w->pos++)
    if (v >> i & 1) w->d[w->pos >> 3] |= (uint8_t)(0x80 >> (w->pos & 7));
}
static size_t vp9_key_frame(uint8_t* out, int color_space, int range) {
  BW w = {{0}, 0};
  put(&w, 2, 2);          // frame_marker
  put(&w, 0, 1);          // profile_low_bit
  put(&w, 1, 1);          // profile_high_bit: profile 2
  put(&w, 0, 1);          // show_existing_frame
  put(&w, 0, 1);          // key frame
  put(&w, 1, 1);          // show_frame
  put(&w, 0, 1);          // error_resilient_mode
  put(&w, 0x498342, 24);  // sync code
  put(&w, 0, 1);          // ten_or_twelve_bit: 10
  put(&w, (uint32_t)color_space, 3);
  put(&w, (uint32_t)range, 1);
  put(&w, 63, 16);  // frame_width_minus_1
  put(&w, 63, 16);  // frame_height_minus_1
  put(&w, 0, 1);    // no render size
  put(&w, 1, 1);    // refresh_frame_context
  put(&w, 1, 1);    // frame_parallel_decoding_mode
  put(&w, 0, 2);    // frame_context_idx
  put(&w, 10, 6);   // filter_level
  put(&w, 0, 3);    // sharpness
  put(&w, 0, 1);    // loop_filter_delta_enabled
  put(&w, 60, 8);   // base_q_idx
  put(&w, 0, 3);    // no delta_q
  put(&w, 0, 1);    // segmentation_enabled
  put(&w, 0, 1);    // log2_tile_rows 0 (64 wide: no tile column bits)
  put(&w, 1, 16);   // header_size_in_bytes
  size_t n = (w.pos + 7) >> 3;
  memcpy(out, w.d, n);
  out[n] = 0;      // compressed header
  out[n + 1] = 0;  // tile data
  return n + 2;
}

static void test_vp9(void) {
  VP9Parser p;
  vp9_parser_init(&p);
  expect("VP9: no colour config read yet",
         p.color_space == -1 && p.color_range == -1);
  uint8_t f[64];
  size_t n = vp9_key_frame(f, 5, 0);
  int r = vp9_parse_frame_header(&p, f, n);
  if (r) printf("  (%s)\n", p.err);
  expect("VP9: a profile 2 BT.2020 key frame header parses, 10 bits",
         !r && p.fh.bit_depth == 10 && p.fh.profile == 2);
  expect("VP9: color_space BT.2020, video range",
         p.color_space == 5 && p.color_range == 0);
  n = vp9_key_frame(f, 2, 1);
  expect("VP9: a header cut after its colour config is refused",
         vp9_parse_frame_header(&p, f, 12) != 0);
  expect("VP9: ... and keeps the earlier colour",
         p.color_space == 5 && p.color_range == 0);
  VcnColor c;
  vcn_color_from_vp9(5, &c);
  expect("VP9: BT.2020 names primaries and matrix 9, no transfer",
         c.primaries == 9 && c.matrix == 9 && c.transfer == -1 && !c.has_mdcv &&
             !c.has_cll);
  vcn_color_from_vp9(1, &c);
  expect("VP9: BT.601 names the matrix only",
         c.matrix == 6 && c.primaries == -1 && c.transfer == -1);
  vcn_color_from_vp9(7, &c);
  expect("VP9: RGB and unknown name nothing",
         c.matrix == -1 && c.primaries == -1);
  const uint8_t v1[12] = {1, 0, 0, 0, 2, 51, 0xa0, 9, 16, 9, 0, 0};
  vcn_color_from_vpcC(v1, sizeof(v1), &c);
  expect("vpcC version 1 gives its code points",
         c.primaries == 9 && c.transfer == 16 && c.matrix == 9);
  const uint8_t v0[12] = {0, 0, 0, 0, 2, 51, 0xa0, 9, 16, 9, 0, 0};
  vcn_color_from_vpcC(v0, sizeof(v0), &c);
  VcnColor e;
  vcn_color_from_vpcC(v1, 9, &e);  // too short for the matrix
  expect("vpcC version 0 or cut short gives nothing",
         c.primaries == -1 && c.transfer == -1 && c.matrix == -1 &&
             e.primaries == -1);
}

static void test_attach(void) {
  CFMutableDictionaryRef ext =
      CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                &kCFTypeDictionaryValueCallBacks);
  CFDictionarySetValue(ext, kCMFormatDescriptionExtension_ColorPrimaries,
                       kCMFormatDescriptionColorPrimaries_ITU_R_2020);
  CFDictionarySetValue(ext, kCMFormatDescriptionExtension_TransferFunction,
                       kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG);
  CFDictionarySetValue(ext, kCMFormatDescriptionExtension_YCbCrMatrix,
                       CFSTR("not a matrix CoreVideo knows"));
  CFDataRef md = CFDataCreate(NULL, kMdcv, 24);
  CFDataRef shortCll = CFDataCreate(NULL, kMdcv, 3);
  CFDictionarySetValue(
      ext, kCMFormatDescriptionExtension_MasteringDisplayColorVolume, md);
  CFDictionarySetValue(ext, kCMFormatDescriptionExtension_ContentLightLevelInfo,
                       shortCll);
  CMVideoFormatDescriptionRef fmt = NULL;
  CMVideoFormatDescriptionCreate(NULL, kCMVideoCodecType_AV1, 64, 64, ext,
                                 &fmt);
  VcnColor c;
  vt_color_from_format(fmt, &c);
  expect("format: primaries 9, transfer 18 (HLG), an unknown matrix is none",
         c.primaries == 9 && c.transfer == 18 && !vt_matrix_name(c.matrix));
  expect(
      "format: a 24-byte mastering display is taken, a 3-byte light "
      "level is not",
      c.has_mdcv && !memcmp(c.mdcv, kMdcv, 24) && !c.has_cll);

  CVPixelBufferRef pb = NULL;
  CVPixelBufferCreate(NULL, 16, 16,
                      kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, NULL,
                      &pb);
  c.matrix = 9;
  c.has_cll = true;
  memcpy(c.cll, "\x03\xe8\x01\x90", 4);
  vt_color_attach(pb, &c);
  CFTypeRef p = CVBufferCopyAttachment(pb, kCVImageBufferColorPrimariesKey,
                                       NULL),
            t = CVBufferCopyAttachment(pb, kCVImageBufferTransferFunctionKey,
                                       NULL),
            mx = CVBufferCopyAttachment(pb, kCVImageBufferYCbCrMatrixKey, NULL),
            mm = CVBufferCopyAttachment(
                pb, kCVImageBufferMasteringDisplayColorVolumeKey, NULL),
            cl = CVBufferCopyAttachment(
                pb, kCVImageBufferContentLightLevelInfoKey, NULL);
  expect("attach: BT.2020, HLG, BT.2020 on the pixel buffer",
         same(p, kCVImageBufferColorPrimaries_ITU_R_2020) &&
             same(t, kCVImageBufferTransferFunction_ITU_R_2100_HLG) &&
             same(mx, kCVImageBufferYCbCrMatrix_ITU_R_2020));
  expect("attach: the 24 and 4 bytes as given",
         same(mm, md) && cl && CFDataGetLength(cl) == 4);
  CFDictionaryRef prop =
      CVBufferCopyAttachments(pb, kCVAttachmentMode_ShouldPropagate);
  expect("attach: they propagate",
         prop && CFDictionaryGetValue(prop, kCVImageBufferColorPrimariesKey) &&
             CFDictionaryGetValue(
                 prop, kCVImageBufferMasteringDisplayColorVolumeKey));
  if (prop) CFRelease(prop);
  for (CFTypeRef *v = (CFTypeRef[]){p, t, mx, mm, cl}, *end = v + 5; v < end;
       v++)
    if (*v) CFRelease(*v);
  VcnColor none;
  vcn_color_clear(&none);
  vt_color_attach(pb, &none);
  prop = CVBufferCopyAttachments(pb, kCVAttachmentMode_ShouldPropagate);
  expect("attach: nothing given takes every colour attachment off",
         !prop ||
             (!CFDictionaryGetValue(prop, kCVImageBufferColorPrimariesKey) &&
              !CFDictionaryGetValue(prop, kCVImageBufferTransferFunctionKey) &&
              !CFDictionaryGetValue(prop, kCVImageBufferYCbCrMatrixKey) &&
              !CFDictionaryGetValue(
                  prop, kCVImageBufferMasteringDisplayColorVolumeKey) &&
              !CFDictionaryGetValue(prop,
                                    kCVImageBufferContentLightLevelInfoKey)));
  if (prop) CFRelease(prop);
  CVPixelBufferRelease(pb);
  CFRelease(fmt);
  CFRelease(md);
  CFRelease(shortCll);
  CFRelease(ext);
}

int main(void) {
  setvbuf(stdout, NULL, _IOLBF, 0);
  test_names();
  test_av1();
  test_vp9();
  test_attach();
  printf("%s\n", failures ? "FAIL" : "PASS colortest");
  return failures ? 1 : 0;
}
