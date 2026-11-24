// jpegtest: the JPEG plug-in below its VideoToolbox side, with nothing sent to
// the GPU or the kernel. It checks:
//
//   1. jpeg/jpegprep.c gives the block the shape Mesa gives it (SOI, DQT, DHT,
//      SOF0, SOS, scan, EOI) and the same picture: ImageIO decodes the
//      original and the rewritten file to the same pixels;
//   2. a picture without Huffman tables (Motion JPEG) gets those of Annex K,
//      and APPn/COM segments and fill bytes change nothing;
//   3. 4:2:2 is taken (as YUYV), what the block is not given (4:4:4, grey) is refused, and no
//      prefix or damaged copy of a sample is read outside its buffer (the
//      address sanitizer stops the program if one is);
//   4. jpeg/vcnjpeg.c against a made-up kext behind the transport: the
//      session needs the plug-in armed and the kext's door; a picture comes
//      back in an NV12 full-range buffer with the kext's pixels in place; a
//      refused picture, a failed job, a decoder that stays busy and a reply
//      that does not match are reported as the right kind of failure.
//
// usage: jpegtest   (exit status 0 = pass)
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "jpegprep.h"
#include "jpegsamples.h"
#include "vcnjpeg.h"

static int failures;
static void expect(const char* what, bool ok) {
  printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) failures++;
}

// RGBA pixels as ImageIO decodes them; NULL if it cannot.
static uint8_t* rgba(const uint8_t* d, size_t n, size_t* w, size_t* h) {
  CFDataRef data = CFDataCreate(NULL, d, (CFIndex)n);
  CGImageSourceRef src = CGImageSourceCreateWithData(data, NULL);
  CGImageRef img = src ? CGImageSourceCreateImageAtIndex(src, 0, NULL) : NULL;
  uint8_t* px = NULL;
  if (img) {
    *w = CGImageGetWidth(img);
    *h = CGImageGetHeight(img);
    px = calloc(*w * *h, 4);
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(px, *w, *h, 8, *w * 4, cs, kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(ctx, CGRectMake(0, 0, *w, *h), img);
    CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
    CGImageRelease(img);
  }
  if (src) CFRelease(src);
  CFRelease(data);
  return px;
}

static bool same_picture(const uint8_t* a, size_t an, const uint8_t* b, size_t bn) {
  size_t aw = 0, ah = 0, bw = 0, bh = 0;
  uint8_t* x = rgba(a, an, &aw, &ah);
  uint8_t* y = rgba(b, bn, &bw, &bh);
  bool ok = x && y && aw == bw && ah == bh && !memcmp(x, y, aw * ah * 4);
  free(x);
  free(y);
  return ok;
}

// The markers of a prepared file, in order, as text ("d8 db c4 c0 da d9").
static void shape(const uint8_t* d, size_t n, char* out, size_t cap) {
  size_t i = 2, p = 0;
  p += snprintf(out + p, cap - p, "d8");
  while (i + 4 <= n && p + 8 < cap) {
    uint8_t m = d[i + 1];
    p += snprintf(out + p, cap - p, " %02x", m);
    size_t len = ((size_t)d[i + 2] << 8) | d[i + 3];
    i += 2 + len;
    if (m == 0xda) break;
  }
  if (n >= 2 && d[n - 2] == 0xff && d[n - 1] == 0xd9) snprintf(out + p, cap - p, " d9");
}

// A copy of a sample with one segment of marker `m` cut out (all of them).
static uint8_t* without(const uint8_t* d, size_t n, uint8_t m, size_t* outN) {
  uint8_t* o = malloc(n);
  size_t i = 2, p = 2;
  memcpy(o, d, 2);
  while (i + 4 <= n) {
    uint8_t mk = d[i + 1];
    size_t len = ((size_t)d[i + 2] << 8) | d[i + 3];
    if (mk == 0xda) break;
    if (mk != m) {
      memcpy(o + p, d + i, 2 + len);
      p += 2 + len;
    }
    i += 2 + len;
  }
  memcpy(o + p, d + i, n - i);
  *outN = p + n - i;
  return o;
}

// ---- a made-up kext behind the transport ---------------------------------------------
static struct {
  int calls, opens, closes;
  int infoStatus;         // what INFO answers (-1: no door)
  int runStatus;          // what RUN answers
  bool busy;              // LOAD_USER says busy, always
  int widthOff;           // added to the width RUN reports
  uint8_t jpeg[1 << 16];  // what LOAD_USER copied
  size_t jpegLen;
  uint32_t w, h, pitch, rows;
  bool yuyv;              // the picture is 4:2:2: one YUYV plane
} K;
static size_t k_bytes(void) { return K.yuyv ? (size_t)K.pitch * K.rows : (size_t)K.pitch * K.rows * 3 / 2; }
static uint8_t pattern(size_t i) { return (uint8_t)(i * 13 + 5); }
static int fake_call(void* ctx, const void* in, size_t inSize, void* out, size_t* outSize) {
  (void)ctx;
  K.calls++;
  struct ja_request rq;
  memcpy(&rq, in, sizeof(rq));
  if (inSize < sizeof(rq) || rq.code != JA_CODE) return 0x2c2;
  if (K.infoStatus == -1) return 0x2c2;  // PowerPlay's refusal: no door
  struct ja_reply rp = {JA_REPLY_MAGIC, JA_OK, 0, 0, {0}};
  uint8_t* data = (uint8_t*)out + sizeof(rp);
  switch (rq.op) {
    case JA_OP_INFO:
      rp.status = (uint32_t)K.infoStatus;
      rp.v[1] = sizeof(K.jpeg);
      rp.v[2] = 1u << 24;
      break;
    case JA_OP_LOAD_USER: {
      if (K.busy) {
        rp.status = JA_BUSY;
        break;
      }
      if (rq.arg1 > sizeof(K.jpeg)) {
        rp.status = JA_BAD_REQUEST;
        break;
      }
      memcpy(K.jpeg, (const void*)(uintptr_t)rq.arg0, rq.arg1);
      K.jpegLen = rq.arg1;
      JpegInfo info;
      uint8_t* again = NULL;
      size_t againLen = 0;
      // the kext checks the stream again; a prepared file must come out unchanged
      if (jpeg_prepare(K.jpeg, K.jpegLen, &again, &againLen, &info, NULL, 0) != JPEG_OK || againLen != K.jpegLen ||
          memcmp(again, K.jpeg, againLen)) {
        free(again);
        rp.status = JA_BAD_STREAM;
        break;
      }
      free(again);
      K.w = info.width;
      K.h = info.height;
      K.yuyv = info.yuyv;
      K.pitch = K.yuyv ? (uint32_t)(((K.w + 15) / 16 * 16 * 2 + 255) / 256 * 256)
                       : (uint32_t)(((K.w + 15) / 16 * 16 + 255) / 256 * 256);
      K.rows = (K.h + 15) / 16 * 16;
      rp.v[0] = K.w;
      rp.v[1] = K.h;
      break;
    }
    case JA_OP_RUN: {
      rp.status = (uint32_t)K.runStatus;
      if (K.runStatus != JA_OK) break;
      struct ja_picture pic = {K.w + (uint32_t)K.widthOff, K.h, K.pitch, K.rows, K.yuyv ? 0 : K.pitch * K.rows,
                               (uint32_t)k_bytes(), 3, K.yuyv ? 1u : 0u};
      memcpy(data, &pic, sizeof(pic));
      rp.dataBytes = sizeof(pic);
      break;
    }
    case JA_OP_READ_USER: {
      size_t bytes = k_bytes();
      if (rq.arg1 < bytes) {
        rp.status = JA_BAD_REQUEST;
        break;
      }
      uint8_t* dst = (uint8_t*)(uintptr_t)rq.arg0;
      for (size_t i = 0; i < bytes; i++) dst[i] = pattern(i);
      rp.v[0] = bytes;
      break;
    }
    case JA_OP_RELEASE:
      break;
    default:
      rp.status = JA_BAD_REQUEST;
  }
  memcpy(out, &rp, sizeof(rp));
  *outSize = sizeof(rp) + rp.dataBytes;
  return 0;
}
static bool openFails;
static int dummyConn;
static void* fake_open(void) {
  K.opens++;
  return openFails ? NULL : &dummyConn;
}
static void fake_close(void* ctx) {
  (void)ctx;
  K.closes++;
}

static CVPixelBufferRef got;
static uint32_t gotW, gotH;
static void on_picture(void* ctx, CVPixelBufferRef pb, const void* unused, uint32_t w, uint32_t h, int64_t tag) {
  (void)ctx, (void)unused, (void)tag;
  if (got) CVPixelBufferRelease(got);
  got = CVPixelBufferRetain(pb);
  gotW = w;
  gotH = h;
}

// The kext's pattern is where the plug-in put it: luma row r at r * pitch, chroma after the luma rows.
// '422f' from the YUYV the made-up kext wrote: Y from the even bytes, Cb Cr from the odd ones.
static bool planes_hold_pattern_422(CVPixelBufferRef pb, uint32_t w, uint32_t h) {
  if (CVPixelBufferGetPixelFormatType(pb) != kCVPixelFormatType_422YpCbCr8BiPlanarFullRange) return false;
  CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  const uint8_t* y = CVPixelBufferGetBaseAddressOfPlane(pb, 0);
  const uint8_t* uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
  size_t ys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), uvs = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
  bool ok = CVPixelBufferGetWidth(pb) == w && CVPixelBufferGetHeight(pb) == h && CVPixelBufferGetHeightOfPlane(pb, 1) == h;
  for (uint32_t r = 0; ok && r < h; r++) {
    for (uint32_t c = 0; ok && c < w; c++) ok = y[r * ys + c] == pattern((size_t)r * K.pitch + 2 * c);
    for (uint32_t c = 0; ok && c < (w + 1) / 2 * 2; c++) ok = uv[r * uvs + c] == pattern((size_t)r * K.pitch + 2 * c + 1);
  }
  CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  return ok;
}
static bool planes_hold_pattern(CVPixelBufferRef pb, uint32_t w, uint32_t h) {
  if (CVPixelBufferGetPixelFormatType(pb) != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) return false;
  CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  const uint8_t* y = CVPixelBufferGetBaseAddressOfPlane(pb, 0);
  const uint8_t* uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
  size_t ys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), uvs = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
  bool ok = CVPixelBufferGetWidth(pb) == w && CVPixelBufferGetHeight(pb) == h;
  for (uint32_t r = 0; ok && r < h; r++)
    for (uint32_t c = 0; ok && c < w; c++) ok = y[r * ys + c] == pattern((size_t)r * K.pitch + c);
  size_t chromaAt = (size_t)K.pitch * K.rows;
  for (uint32_t r = 0; ok && r < (h + 1) / 2; r++)
    for (uint32_t c = 0; ok && c < (w + 1) / 2 * 2; c++)
      ok = uv[r * uvs + c] == pattern(chromaAt + (size_t)r * K.pitch + c);
  CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  return ok;
}

int main(void) {
  setvbuf(stdout, NULL, _IOLBF, 0);
  struct {
    const uint8_t* d;
    size_t n;
    uint32_t w, h;
  } ok420[] = {{kJpeg16x16, sizeof(kJpeg16x16), 16, 16},
               {kJpeg48x32, sizeof(kJpeg48x32), 48, 32},
               {kJpeg50x30, sizeof(kJpeg50x30), 50, 30}};
  char why[96], text[64];

  // ---- 1. shape and picture ----
  bool shapes = true, pictures = true, sizes = true;
  for (size_t k = 0; k < 3; k++) {
    uint8_t* o = NULL;
    size_t on = 0;
    JpegInfo info;
    int r = jpeg_prepare(ok420[k].d, ok420[k].n, &o, &on, &info, why, sizeof(why));
    if (r != JPEG_OK) {
      printf("     %s\n", why);
      shapes = pictures = sizes = false;
      continue;
    }
    shape(o, on, text, sizeof(text));
    shapes = shapes && !strcmp(text, "d8 db c4 c0 da d9");
    pictures = pictures && same_picture(ok420[k].d, ok420[k].n, o, on);
    sizes = sizes && info.width == ok420[k].w && info.height == ok420[k].h && on <= ok420[k].n + kJpegPrepExtra;
    // what comes out goes in again unchanged (the kext checks it again)
    uint8_t* o2 = NULL;
    size_t on2 = 0;
    shapes = shapes && jpeg_prepare(o, on, &o2, &on2, &info, NULL, 0) == JPEG_OK && on2 == on && !memcmp(o, o2, on);
    free(o2);
    free(o);
  }
  expect("16x16, 48x32 and 50x30: SOI, DQT, DHT, SOF0, SOS, scan, EOI, and nothing else", shapes);
  expect("ImageIO decodes the original and the rewritten file to the same pixels", pictures);
  expect("the size comes from the frame header", sizes);

  // ---- 2. Motion JPEG without tables; segments that are dropped ----
  uint8_t *base = NULL, *o = NULL;
  size_t baseN = 0, on = 0, cutN = 0;
  JpegInfo info;
  jpeg_prepare(kJpeg48x32, sizeof(kJpeg48x32), &base, &baseN, &info, NULL, 0);
  uint8_t* cut = without(kJpeg48x32, sizeof(kJpeg48x32), 0xc4, &cutN);
  int r = jpeg_prepare(cut, cutN, &o, &on, &info, why, sizeof(why));
  expect("without its DHT the picture gets Annex K's tables, byte for byte what FFmpeg wrote",
         r == JPEG_OK && info.stdTables && on == baseN && !memcmp(o, base, on));
  expect("and ImageIO, given the result, decodes the original picture", r == JPEG_OK &&
         same_picture(kJpeg48x32, sizeof(kJpeg48x32), o, on));
  free(o);
  free(cut);
  // APP1 + COM + fill bytes in front of SOF0
  size_t extraN = sizeof(kJpeg48x32) + 32;
  uint8_t* extra = malloc(extraN);
  memcpy(extra, kJpeg48x32, 2);
  static const uint8_t junk[] = {0xff, 0xe1, 0x00, 0x08, 'E', 'x', 'i', 'f', 0, 0,  0xff, 0xfe, 0x00, 0x06,
                                 'h',  'e',  'l',  'l',  0xff, 0xff, 0xff, 0xe2, 0x00, 0x0a, 1, 2, 3, 4,
                                 5,    6,    7,    8};
  memcpy(extra + 2, junk, sizeof(junk));
  memcpy(extra + 2 + sizeof(junk), kJpeg48x32 + 2, sizeof(kJpeg48x32) - 2);
  o = NULL;
  r = jpeg_prepare(extra, extraN, &o, &on, &info, why, sizeof(why));
  expect("APP1, COM and fill bytes are dropped: the same bytes as without them",
         r == JPEG_OK && on == baseN && !memcmp(o, base, on));
  free(o);
  free(extra);

  // ---- 3. refused, cut and damaged ----
  o = NULL;
  r = jpeg_prepare(kJpeg422, sizeof(kJpeg422), &o, &on, &info, why, sizeof(why));
  expect("4:2:2 (ffmpeg's 2x2/1x2/1x2) is taken, as YUYV", r == JPEG_OK && o && info.yuyv && info.width == 32);
  free(o);
  {
    // the other sampling forms Mesa takes or refuses on this block
    static const uint8_t forms[][4] = {{0x21, 0x11, 0x11, JPEG_OK}, {0x22, 0x21, 0x21, JPEG_OK},
                                       {0x11, 0x11, 0x11, JPEG_UNSUPPORTED}, {0x12, 0x11, 0x11, JPEG_UNSUPPORTED}};
    bool all = true;
    for (size_t f = 0; f < sizeof(forms) / sizeof(forms[0]); f++) {
      uint8_t* c = malloc(sizeof(kJpeg48x32));
      memcpy(c, kJpeg48x32, sizeof(kJpeg48x32));
      for (size_t i = 2; i + 20 < sizeof(kJpeg48x32); i++)
        if (c[i] == 0xff && c[i + 1] == 0xc0) {
          c[i + 11] = forms[f][0];
          c[i + 14] = forms[f][1];
          c[i + 17] = forms[f][2];
          break;
        }
      o = NULL;
      int rr = jpeg_prepare(c, sizeof(kJpeg48x32), &o, &on, &info, why, sizeof(why));
      all = all && rr == forms[f][3] && (rr != JPEG_OK || info.yuyv) && (rr == JPEG_OK || !o);
      free(o);
      free(c);
    }
    expect("sampling 211111 and 222121 are YUYV too; 4:4:4 and 4:4:0 are refused", all);
  }
  bool prefixes = true;
  for (size_t n = 0; n < sizeof(kJpeg48x32) - 1; n++) {
    uint8_t* copy = malloc(n ? n : 1);
    memcpy(copy, kJpeg48x32, n);
    o = NULL;
    r = jpeg_prepare(copy, n, &o, &on, &info, NULL, 0);
    // a prefix that ends inside the scan has no EOI: refused
    prefixes = prefixes && r != JPEG_OK && !o;
    free(copy);
  }
  expect("every prefix of a sample is refused, nothing read past it", prefixes);
  uint32_t seed = 1, accepted = 0;
  for (int k = 0; k < 40000; k++) {
    size_t n = ok420[k % 3].n;
    uint8_t* copy = malloc(n);
    memcpy(copy, ok420[k % 3].d, n);
    int flips = 1 + k % 8;
    for (int f = 0; f < flips; f++) {
      seed = seed * 1664525u + 1013904223u;
      size_t at = (seed >> 8) % (k % 2 ? 200 : n);  // half of them in the headers
      seed = seed * 1664525u + 1013904223u;
      copy[at] = k % 5 == 0 ? (uint8_t)(seed >> 24) : copy[at] ^ (uint8_t)(1u << ((seed >> 8) % 8));
    }
    o = NULL;
    r = jpeg_prepare(copy, n, &o, &on, &info, NULL, 0);
    if (r == JPEG_OK) {
      accepted++;
      if (on > n + kJpegPrepExtra) prefixes = false;
    }
    free(o);
    free(copy);
  }
  printf("     (%u of 40000 damaged copies still had the shape of a JPEG)\n", accepted);
  expect("40000 damaged copies are read without a fault", prefixes);

  // ---- 4. the session against a made-up kext ----
  vcnjpeg_transport = fake_call;
  vcnjpeg_transport_open = fake_open;
  vcnjpeg_transport_close = fake_close;
  char err[160] = "";
  VcnJpeg* d = vcnjpeg_create(16384, 16384, err, sizeof(err));
  expect("no session before the plug-in arms it, and nothing is opened", !d && K.opens == 0);
  vcnjpeg_gpu_armed = 1;
  K.infoStatus = -1;
  d = vcnjpeg_create(16384, 16384, err, sizeof(err));
  expect("no session without the kext's door (PowerPlay refuses the request), and the connection is closed",
         !d && K.opens == 1 && K.closes == 1 && strstr(err, "not loaded"));
  K.infoStatus = JA_NOT_READY;
  d = vcnjpeg_create(16384, 16384, err, sizeof(err));
  expect("no session while the kext's decoder is not ready", !d && K.closes == 2);
  openFails = true;
  d = vcnjpeg_create(16384, 16384, err, sizeof(err));
  expect("no session when the accelerator cannot be opened", !d && K.closes == 2);
  openFails = false;
  K.infoStatus = JA_OK;
  K.runStatus = JA_OK;
  d = vcnjpeg_create(16384, 16384, err, sizeof(err));
  expect("a session with the door open", d != NULL);
  bool pics = d != NULL;
  for (size_t k = 0; pics && k < 3; k++) {
    int calls = K.calls;
    pics = !vcnjpeg_decode(d, ok420[k].d, ok420[k].n, 0, on_picture, NULL) && got && gotW == ok420[k].w &&
           gotH == ok420[k].h && planes_hold_pattern(got, ok420[k].w, ok420[k].h) && K.calls == calls + 3;
    if (!pics) printf("     %s\n", vcnjpeg_last_error(d));
  }
  expect("16x16, 48x32 and 50x30 come back in NV12 full range, the kext's pixels in place, in three calls", pics);
  CFTypeRef matrix = got ? CVBufferCopyAttachment(got, kCVImageBufferYCbCrMatrixKey, NULL) : NULL;
  expect("the picture says BT.601 (JFIF)", matrix && CFEqual(matrix, kCVImageBufferYCbCrMatrix_ITU_R_601_4));
  if (matrix) CFRelease(matrix);
  int calls = K.calls;
  bool p422 = d && !vcnjpeg_decode(d, kJpeg422, sizeof(kJpeg422), 0, on_picture, NULL) && got && gotW == 32 &&
              gotH == 16 && planes_hold_pattern_422(got, 32, 16) && K.calls == calls + 3;
  if (!p422 && d) printf("     %s\n", vcnjpeg_last_error(d));
  expect("a 4:2:2 picture comes back as '422f', the kext's YUYV split into its planes, in three calls", p422);
  if (d) {
    vcnjpeg_destroy(d);
    d = vcnjpeg_create(32, 32, err, sizeof(err));
  }
  calls = K.calls;
  expect("a picture larger than the session allows fails as the stream's, nothing sent",
         d && vcnjpeg_decode(d, kJpeg48x32, sizeof(kJpeg48x32), 0, on_picture, NULL) &&
             vcnjpeg_failure(d) == VCNJPEG_FAIL_STREAM && K.calls == calls);
  vcnjpeg_destroy(d);
  d = vcnjpeg_create(16384, 16384, err, sizeof(err));
  K.runStatus = JA_FAILED;
  expect("a job that fails in the kext is a device failure",
         d && vcnjpeg_decode(d, kJpeg16x16, sizeof(kJpeg16x16), 0, on_picture, NULL) &&
             vcnjpeg_failure(d) == VCNJPEG_FAIL_DEVICE);
  K.runStatus = JA_OK;
  K.widthOff = 16;
  expect("a picture of another size than the one sent is a device failure",
         d && vcnjpeg_decode(d, kJpeg16x16, sizeof(kJpeg16x16), 0, on_picture, NULL) &&
             vcnjpeg_failure(d) == VCNJPEG_FAIL_DEVICE);
  K.widthOff = 0;
  K.busy = true;
  CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
  bool busy = d && vcnjpeg_decode(d, kJpeg16x16, sizeof(kJpeg16x16), 0, on_picture, NULL) &&
              vcnjpeg_failure(d) == VCNJPEG_FAIL_DEVICE;
  double waited = CFAbsoluteTimeGetCurrent() - t0;
  expect("a decoder another process keeps busy for a second is a device failure", busy && waited >= 0.9 && waited < 3);
  K.busy = false;
  int closes = K.closes;
  vcnjpeg_destroy(d);
  expect("destroy gives the decoder back and closes the connection", K.closes == closes + 1);
  if (got) CVPixelBufferRelease(got);
  free(base);
  return failures ? 1 : 0;
}
