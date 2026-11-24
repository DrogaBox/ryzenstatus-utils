// vcnjpeg.c - see vcnjpeg.h.
#include "vcnjpeg.h"

#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "jpegprep.h"

int vcnjpeg_gpu_armed = 0;

static void* iokit_open(void) {
  io_connect_t c = ja_iokit_open();
  if (c == IO_OBJECT_NULL) return NULL;
  io_connect_t* p = malloc(sizeof(*p));
  if (!p) {
    ja_iokit_close(c);
    return NULL;
  }
  *p = c;
  return p;
}
static void iokit_close(void* ctx) {
  if (!ctx) return;
  ja_iokit_close(*(io_connect_t*)ctx);  // the video context and its shared client
  free(ctx);
}
ja_transport vcnjpeg_transport = ja_iokit_call;
void* (*vcnjpeg_transport_open)(void) = iokit_open;
void (*vcnjpeg_transport_close)(void* ctx) = iokit_close;

// How long a frame waits while another process holds the block before the
// session counts as broken: a picture of 48 MP takes the block well under that.
enum { kBusyWaitMs = 1000 };

struct VcnJpeg {
  void* conn;
  uint32_t maxW, maxH;
  uint8_t* surface;  // what the kext copies the picture into (its layout, see ja_picture)
  size_t surfaceCap;
  CVPixelBufferPoolRef pool;
  uint32_t poolW, poolH;
  int failure;
  char err[160];
};

static bool put_num(CFMutableDictionaryRef d, CFStringRef k, int32_t v) {
  CFNumberRef n = CFNumberCreate(NULL, kCFNumberSInt32Type, &v);
  if (!n) return false;
  CFDictionarySetValue(d, k, n);
  CFRelease(n);
  return true;
}

CFDictionaryRef vcnjpeg_copy_pixel_buffer_attributes(uint32_t w, uint32_t h, bool ten) {
  (void)ten;
  CFMutableDictionaryRef a = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                                       &kCFTypeDictionaryValueCallBacks);
  CFMutableDictionaryRef io = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                                        &kCFTypeDictionaryValueCallBacks);
  if (!a || !io) {
    if (a) CFRelease(a);
    if (io) CFRelease(io);
    return NULL;
  }
  bool ok = put_num(a, kCVPixelBufferPixelFormatTypeKey, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange);
  ok = put_num(a, kCVPixelBufferWidthKey, (int32_t)w) && ok;
  ok = put_num(a, kCVPixelBufferHeightKey, (int32_t)h) && ok;
  CFDictionarySetValue(a, kCVPixelBufferIOSurfacePropertiesKey, io);
  CFDictionarySetValue(a, kCVPixelBufferMetalCompatibilityKey, kCFBooleanTrue);
  CFRelease(io);
  if (!ok) {
    CFRelease(a);
    return NULL;
  }
  return a;
}

static int failed(VcnJpeg* d, int failure, const char* what, int status) {
  d->failure = failure;
  if (status == 0)
    snprintf(d->err, sizeof(d->err), "%s", what);
  else
    snprintf(d->err, sizeof(d->err), "%s (status %d)", what, status);
  return -1;
}

VcnJpeg* vcnjpeg_create(uint32_t maxWidth, uint32_t maxHeight, char* err, size_t errLen) {
  if (!__atomic_load_n(&vcnjpeg_gpu_armed, __ATOMIC_RELAXED)) {
    snprintf(err, errLen, "not armed");
    return NULL;
  }
  VcnJpeg* d = calloc(1, sizeof(*d));
  if (!d) {
    snprintf(err, errLen, "out of memory");
    return NULL;
  }
  d->maxW = maxWidth;
  d->maxH = maxHeight;
  d->conn = vcnjpeg_transport_open();
  if (!d->conn) {
    snprintf(err, errLen, "cannot open a video context on the AMD accelerator");
    free(d);
    return NULL;
  }
  uint64_t state = 0, jcap = 0, scap = 0;
  int s = ja_info(vcnjpeg_transport, d->conn, &state, &jcap, &scap);
  if (s != JA_OK) {
    // -1: the request went on to PowerPlay, which refused it: no kext with the door
    snprintf(err, errLen, s == -1 ? "no JPEG decoder: the apps build of VCNJpegProbe is not loaded"
                                  : "the JPEG decoder is not ready (status %d)", s);
    vcnjpeg_transport_close(d->conn);
    free(d);
    return NULL;
  }
  return d;
}

void vcnjpeg_destroy(VcnJpeg* d) {
  if (!d) return;
  if (d->conn) {
    struct ja_reply rp;
    ja_call(vcnjpeg_transport, d->conn, JA_OP_RELEASE, 0, 0, NULL, 0, &rp, NULL, 0);
    vcnjpeg_transport_close(d->conn);
  }
  if (d->pool) CVPixelBufferPoolRelease(d->pool);
  free(d->surface);
  free(d);
}

static CVPixelBufferRef new_target(VcnJpeg* d, uint32_t w, uint32_t h) {
  if (d->pool && (d->poolW != w || d->poolH != h)) {
    CVPixelBufferPoolRelease(d->pool);
    d->pool = NULL;
  }
  if (!d->pool) {
    CFDictionaryRef a = vcnjpeg_copy_pixel_buffer_attributes(w, h, false);
    if (!a) return NULL;
    CVReturn r = CVPixelBufferPoolCreate(NULL, NULL, a, &d->pool);
    CFRelease(a);
    if (r) {
      d->pool = NULL;
      return NULL;
    }
    d->poolW = w;
    d->poolH = h;
  }
  CVPixelBufferRef pb = NULL;
  if (CVPixelBufferPoolCreatePixelBuffer(NULL, d->pool, &pb)) return NULL;
  return pb;
}

// The kext's surface layout for a picture (VCNJpegProbe jc::outputLayout):
// rows of alignUp(alignUp(width, 16), 256) bytes, alignUp(height, 16) luma rows,
// then the interleaved chroma.
static size_t surface_bytes(uint32_t w, uint32_t h) {
  size_t pitch = (((size_t)w + 15) / 16 * 16 + 255) / 256 * 256;
  size_t rows = ((size_t)h + 15) / 16 * 16;
  return pitch * rows * 3 / 2;
}

// Copies the kext's surface into the planes of pb; false if the layout the kext
// reported does not fit the picture.
static bool copy_planes(const uint8_t* src, const struct ja_picture* pic, CVPixelBufferRef pb) {
  uint32_t w = pic->width, h = pic->height;
  if (pic->pitch < w || (size_t)pic->pitch * h > pic->chromaOffset ||
      pic->chromaOffset + (size_t)pic->pitch * ((h + 1) / 2) > pic->surfaceBytes)
    return false;
  if (CVPixelBufferLockBaseAddress(pb, 0)) return false;
  bool ok = CVPixelBufferGetPlaneCount(pb) == 2 && CVPixelBufferGetWidthOfPlane(pb, 0) == w &&
            CVPixelBufferGetHeightOfPlane(pb, 0) == h;
  if (ok) {
    uint8_t* y = CVPixelBufferGetBaseAddressOfPlane(pb, 0);
    uint8_t* uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
    size_t ys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), uvs = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
    size_t cw = ((size_t)w + 1) / 2 * 2, ch = CVPixelBufferGetHeightOfPlane(pb, 1);
    ok = y && uv && ys >= w && uvs >= cw && ch == (h + 1) / 2 && cw <= pic->pitch;
    for (uint32_t r = 0; ok && r < h; r++) memcpy(y + r * ys, src + (size_t)r * pic->pitch, w);
    for (size_t r = 0; ok && r < ch; r++)
      memcpy(uv + r * uvs, src + pic->chromaOffset + r * pic->pitch, cw);
  }
  CVPixelBufferUnlockBaseAddress(pb, 0);
  return ok;
}

int vcnjpeg_decode(VcnJpeg* d, const uint8_t* sample, size_t size, int64_t tag, VcnJpegOutputFn fn,
                   void* ctx) {
  d->failure = VCNJPEG_FAIL_STREAM;
  d->err[0] = 0;
  uint8_t* jpeg = NULL;
  size_t jpegLen = 0;
  JpegInfo info;
  char why[96];
  int p = jpeg_prepare(sample, size, &jpeg, &jpegLen, &info, why, sizeof(why));
  if (p == JPEG_NO_MEMORY) return failed(d, VCNJPEG_FAIL_MEMORY, why, 0);
  if (p != JPEG_OK) return failed(d, VCNJPEG_FAIL_STREAM, why, 0);
  if (info.width > d->maxW || info.height > d->maxH) {
    free(jpeg);
    return failed(d, VCNJPEG_FAIL_STREAM, "picture larger than the session allows", 0);
  }
  size_t need = surface_bytes(info.width, info.height);
  if (need > d->surfaceCap) {
    free(d->surface);
    d->surface = malloc(need);
    d->surfaceCap = d->surface ? need : 0;
    if (!d->surface) {
      free(jpeg);
      return failed(d, VCNJPEG_FAIL_MEMORY, "out of memory", 0);
    }
  }
  struct ja_picture pic;
  struct ja_reply rp;
  int s = ja_decode(vcnjpeg_transport, d->conn, jpeg, jpegLen, d->surface, d->surfaceCap, 0, kBusyWaitMs,
                    &pic, &rp);
  free(jpeg);
  if (s == JA_BAD_STREAM) return failed(d, VCNJPEG_FAIL_STREAM, "the kext refused the picture", (int)rp.detail);
  if (s == JA_BAD_REQUEST) return failed(d, VCNJPEG_FAIL_STREAM, "the picture does not fit the kext's buffers", s);
  if (s != JA_OK) return failed(d, VCNJPEG_FAIL_DEVICE, "the JPEG decoder failed", s);
  if (pic.width != info.width || pic.height != info.height || pic.surfaceBytes > d->surfaceCap)
    return failed(d, VCNJPEG_FAIL_DEVICE, "the kext's picture is not the one sent", 0);
  CVPixelBufferRef pb = new_target(d, info.width, info.height);
  if (!pb) return failed(d, VCNJPEG_FAIL_MEMORY, "no pixel buffer", 0);
  if (!copy_planes(d->surface, &pic, pb)) {
    CVPixelBufferRelease(pb);
    return failed(d, VCNJPEG_FAIL_DEVICE, "the kext's layout does not fit the picture", 0);
  }
  // JFIF: BT.601 matrix, full range (the pixel format says the range)
  CVBufferSetAttachment(pb, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_601_4,
                        kCVAttachmentMode_ShouldPropagate);
  fn(ctx, pb, NULL, info.width, info.height, tag);
  CVPixelBufferRelease(pb);
  return 0;
}

const char* vcnjpeg_last_error(VcnJpeg* d) { return d->err; }
int vcnjpeg_failure(VcnJpeg* d) { return d->failure; }
CVPixelBufferRef vcnjpeg_hidden_picture(VcnJpeg* d) {
  (void)d;
  return NULL;
}
unsigned vcnjpeg_firmware_errors(VcnJpeg* d) {
  (void)d;
  return 0;
}
