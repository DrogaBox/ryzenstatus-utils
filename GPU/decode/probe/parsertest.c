// parsertest <mpeg2.m2v> <vc1.vc1> <mpeg4.m4v> <jpeg.jpg> [vc1 width height]
//
// Host-only: checks each parser against the sample it was written for, plus a
// few headers that must be refused. It never touches the driver or the GPU.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "jpegparse.h"
#include "mpeg2parse.h"
#include "mpeg4parse.h"
#include "vc1parse.h"

static int failures;

static void check(int ok, const char* what) {
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  if (!ok) failures++;
}

static uint8_t* slurp(const char* path, size_t* n) {
  FILE* f = fopen(path, "rb");
  if (!f) return NULL;
  if (fseek(f, 0, SEEK_END)) {
    fclose(f);
    return NULL;
  }
  long len = ftell(f);
  if (len <= 0 || fseek(f, 0, SEEK_SET)) {
    fclose(f);
    return NULL;
  }
  uint8_t* p = malloc((size_t)len);
  if (!p || fread(p, 1, (size_t)len, f) != (size_t)len) {
    free(p);
    fclose(f);
    return NULL;
  }
  fclose(f);
  *n = (size_t)len;
  return p;
}

int main(int argc, char** argv) {
  if (argc < 5) {
    fprintf(stderr,
            "usage: %s <mpeg2.m2v> <vc1.vc1> <mpeg4.m4v> <jpeg.jpg> [w h]\n",
            argv[0]);
    return 2;
  }
  char err[256];
  size_t n;

  uint8_t* d = slurp(argv[1], &n);
  check(d != NULL, "read the MPEG-2 sample");
  if (d) {
    Mpeg2Picture p;
    int r = mpeg2_parse(d, n, &p, err, sizeof(err));
    check(r == 0 && p.au.width == 720 && p.au.height == 576 &&
              p.picture_coding_type == 1 && p.picture_structure == 3,
          "MPEG-2 720x576 frame I picture");
    check(p.au.auSize > 0 && p.au.au >= d && p.au.au + p.au.auSize <= d + n,
          "MPEG-2 access unit inside the file");
    // The 720x576 sample's picture coding extension starts with identifier 8,
    // then f_code 15,15,15,15 (unused in an I picture), intra_dc_precision 0,
    // picture_structure 3, frame_pred_frame_dct 1, read by hand from the
    // bytes at offset 38 (report 134).
    printf(
        "     MPEG-2 f_code %u,%u,%u,%u intra_dc=%u structure=%u "
        "frame_pred_dct=%u au[3]=0x%02x pic_au[3]=0x%02x\n",
        p.f_code[0][0], p.f_code[0][1], p.f_code[1][0], p.f_code[1][1],
        p.intra_dc_precision, p.picture_structure, p.frame_pred_frame_dct,
        p.au.au[3], p.picAu.au[3]);
    check(p.f_code[0][0] == 15 && p.f_code[0][1] == 15 &&
              p.f_code[1][0] == 15 && p.f_code[1][1] == 15,
          "MPEG-2 extension identifier skipped (f_code 15,15,15,15)");
    check(p.intra_dc_precision == 0 && p.picture_structure == 3 &&
              p.frame_pred_frame_dct == 1,
          "MPEG-2 intra_dc_precision/structure/frame_pred_dct match the bytes");
    check(p.au.auSize > 4 && p.au.au[3] == 0xB3 && p.au.auSize > p.picAu.auSize,
          "MPEG-2 bitstream starts at the sequence header");
    check(p.picAu.auSize > 4 && p.picAu.au[3] == 0x00,
          "MPEG-2 picture-only variant starts at 00 00 01 00");
    free(d);
  }

  d = slurp(argv[3], &n);
  check(d != NULL, "read the MPEG-4 sample");
  if (d) {
    Mpeg4Picture p;
    int r = mpeg4_parse(d, n, &p, err, sizeof(err));
    check(r == 0 && p.au.width == 640 && p.au.height == 480 &&
              p.vop_coding_type == 0 && p.shape == 0,
          "MPEG-4 640x480 rectangular I-VOP");
    check(p.vop_time_increment_resolution > 0, "MPEG-4 time base read");
    free(d);
  }

  d = slurp(argv[4], &n);
  check(d != NULL, "read the JPEG sample");
  if (d) {
    JpegPicture p;
    int r = jpeg_parse(d, n, &p, err, sizeof(err));
    check(r == 0 && p.au.width == 640 && p.au.height == 480 &&
              p.components == 3 && p.sampling == 1 && p.precision == 8,
          "JPEG 640x480 4:2:0 baseline");
    check(p.au.au == d && p.au.auSize == n,
          "JPEG whole file is the access unit");
    free(d);
  }

  d = slurp(argv[2], &n);
  check(d != NULL, "read the VC-1 sample");
  if (d) {
    Vc1Picture p;
    int r = vc1_parse(d, n, &p, err, sizeof(err));
    check(r == 0 && p.profile == 3 && p.pic_structure == 3,
          "VC-1 advanced-profile frame");
    if (argc >= 7) {
      uint32_t w = (uint32_t)atoi(argv[5]), h = (uint32_t)atoi(argv[6]);
      printf("     VC-1 parsed %ux%u, expected %ux%u\n", p.au.width,
             p.au.height, w, h);
      check(p.au.width == w && p.au.height == h,
            "VC-1 size matches the reference decode");
    }
    check(p.au.auSize > 0 && p.au.au >= d && p.au.au + p.au.auSize <= d + n,
          "VC-1 access unit inside the file");
    check(p.au.auSize > 4 && p.au.au[3] == 0x0F && p.au.auSize > p.picAu.auSize,
          "VC-1 bitstream starts at the sequence header");
    free(d);
  }

  // Refusals: headers the probe must not send.
  const uint8_t notJpeg[] = {0x00, 0x00, 0x01, 0xB3, 0x2D, 0x02};
  JpegPicture jp;
  check(jpeg_parse(notJpeg, sizeof(notJpeg), &jp, err, sizeof(err)) == -1,
        "JPEG parser refuses a non-JPEG");
  const uint8_t progJpeg[] = {
      0xFF, 0xD8, 0xFF, 0xC2, 0x00, 0x11, 0x08, 0x01, 0xE0, 0x02, 0x80, 0x03,
      0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, 0xFF, 0xDA, 0x00,
      0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x12, 0xFF, 0xD9};
  check(jpeg_parse(progJpeg, sizeof(progJpeg), &jp, err, sizeof(err)) == -1,
        "JPEG parser refuses progressive (SOF2)");
  const uint8_t badMpeg4[] = {0x00, 0x00, 0x01, 0xB6, 0x00, 0x00};
  Mpeg4Picture m4;
  check(mpeg4_parse(badMpeg4, sizeof(badMpeg4), &m4, err, sizeof(err)) == -1,
        "MPEG-4 parser refuses a file with no VOL");
  Vc1Picture v1;
  check(vc1_parse(notJpeg, sizeof(notJpeg), &v1, err, sizeof(err)) == -1,
        "VC-1 parser refuses a file with no sequence header");
  check(v1.profile == 0, "a refused VC-1 picture leaves the output empty");

  printf("%s: %d failure(s)\n", failures ? "FAILED" : "passed", failures);
  return failures ? 1 : 0;
}
