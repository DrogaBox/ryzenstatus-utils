// vtjpegtest: drives our Motion JPEG decoder through the public VideoToolbox
// API and compares every frame with FFmpeg's decode of the same file.
//
//   vtjpegtest -load bundle clip.mjpeg reference.yuv width height 420|422
//              [-dmb1] [-frames N]
//   vtjpegtest -apple clip.mjpeg reference.yuv width height 420|422 [-dmb1]
//       the same with Apple's own software decoder, asked for the same pixel
//       format: runs on the CPU only, checks the clip, the reference and this
//       program's comparison without the GPU
//
// clip.mjpeg is a raw Motion JPEG stream (JPEG pictures one after the other, as
// `ffmpeg -c:v mjpeg -f mjpeg` writes it). reference.yuv holds the same frames
// as FFmpeg decodes them, planar and full range: yuvj420p for 420, yuvj422p for
// 422 (`ffmpeg -i clip.mjpeg -f rawvideo -pix_fmt yuvj4xxp reference.yuv`).
//
// -load registers the bundle in this process only, under the ID
// com.droga.vtjpegtest (VideoToolbox lists it as com.droga.vtjpegtest.jpeg or
// .dmb1), and the session asks for exactly that decoder: an installed plug-in
// or Apple's software decoders cannot serve it. Nothing is installed.
// -dmb1 uses the OpenDML codec type instead of 'jpeg'. -frames stops early.
//
// Checks, per frame: decoded without error, the pixel format is the one our
// decoder gives for the sampling ('420f' for 4:2:0, '422f' for 4:2:2), and
// every sample is within 2 of FFmpeg's (the block's IDCT rounds differently,
// a difference of 1 was seen on hardware).
//
// There is no switch to arm: a run goes to the GPU as soon as the apps build
// of VCNJpegProbe is loaded and its JPEG queue is started.
//
// Exit status: 0 = every frame decoded and matched, 2 = a frame failed,
// differs or is missing, 1 = anything else.
#include <CoreMedia/CoreMedia.h>
#include <VideoToolbox/VideoToolbox.h>
#include <dlfcn.h>
#include <limits.h>
#include <mach/mach_time.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static double now_ms(void) {
  static mach_timebase_info_data_t tb;
  if (!tb.denom) mach_timebase_info(&tb);
  return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

static void copy_kv(const void* k, const void* v, void* dict) { CFDictionarySetValue(dict, k, v); }

// Registers the bundle's decoder for one codec in this process only, under our
// own ID. Fails when nothing was registered.
static int load_bundle(const char* path, FourCharCode codec, const char* fourcc) {
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8*)path, (CFIndex)strlen(path), true);
  CFBundleRef b = url ? CFBundleCreate(NULL, url) : NULL;
  if (url) CFRelease(url);
  if (!b || !CFBundleLoadExecutable(b)) {
    fprintf(stderr, "cannot load %s\n", path);
    return -1;
  }
  CFArrayRef impls = CFBundleGetValueForInfoDictionaryKey(b, CFSTR("CMClassImplementations"));
  OSStatus (*reg)(FourCharCode, CFDictionaryRef, void*) = dlsym(RTLD_DEFAULT, "VTRegisterVideoDecoderWithInfo");
  CFStringRef want = CFStringCreateWithCString(NULL, fourcc, kCFStringEncodingASCII);
  int registered = 0;
  for (CFIndex i = 0; impls && reg && want && i < CFArrayGetCount(impls); i++) {
    CFDictionaryRef impl = CFArrayGetValueAtIndex(impls, i);
    CFDictionaryRef match = CFDictionaryGetValue(impl, CFSTR("CMMatchingInfo"));
    CFStringRef type = match ? CFDictionaryGetValue(match, CFSTR("VTCodecType")) : NULL;
    if (!type || !CFEqual(type, want)) continue;
    CFStringRef fn = CFDictionaryGetValue(impl, CFSTR("CMFactoryFunction"));
    void* factory = fn ? CFBundleGetFunctionPointerForName(b, fn) : NULL;
    if (!factory) continue;
    CFMutableDictionaryRef info = CFDictionaryCreateMutableCopy(NULL, 0, impl);
    // dynamic registration ignores CMMatchingInfo: lift its keys to the top
    CFDictionaryApplyFunction(match, copy_kv, info);
    CFDictionarySetValue(info, CFSTR("CMClassImplementationID"), CFSTR("com.droga.vtjpegtest"));
    CFDictionarySetValue(info, CFSTR("IsHardwareAccelerated"), kCFBooleanTrue);
    CFStringRef name = CFDictionaryGetValue(impl, CFSTR("CMClassImplementationName"));
    if (name) CFDictionarySetValue(info, CFSTR("CodecName"), name);
    OSStatus st = reg(codec, info, factory);
    CFRelease(info);
    printf("registered %s from %s -> %d\n", fourcc, path, (int)st);
    if (!st) registered++;
  }
  if (want) CFRelease(want);
  if (!registered) {
    fprintf(stderr, "no %s decoder of %s could be registered\n", fourcc, path);
    return -1;
  }
  return 0;
}

static uint8_t* read_all(const char* path, size_t* n) {
  FILE* f = fopen(path, "rb");
  if (!f) return NULL;
  fseek(f, 0, SEEK_END);
  long len = ftell(f);
  fseek(f, 0, SEEK_SET);
  uint8_t* d = len > 0 ? malloc((size_t)len) : NULL;
  if (d && fread(d, 1, (size_t)len, f) != (size_t)len) {
    free(d);
    d = NULL;
  }
  fclose(f);
  *n = d ? (size_t)len : 0;
  return d;
}

// The next JPEG picture of a raw Motion JPEG stream: SOI, segments up to the
// scan, the scan (where FF is always stuffed or a restart marker), EOI.
static bool next_picture(const uint8_t* d, size_t n, size_t* at, size_t* start, size_t* len) {
  size_t i = *at;
  while (i + 1 < n && !(d[i] == 0xff && d[i + 1] == 0xd8)) i++;
  if (i + 1 >= n) return false;
  size_t s = i;
  i += 2;
  while (1) {
    if (i + 4 > n || d[i] != 0xff) return false;
    uint8_t m = d[i + 1];
    if (m == 0xff) {  // fill byte
      i++;
      continue;
    }
    size_t l = ((size_t)d[i + 2] << 8) | d[i + 3];
    if (l < 2 || i + 2 + l > n) return false;
    i += 2 + l;
    if (m == 0xda) break;
  }
  while (i + 1 < n) {
    if (d[i] == 0xff && d[i + 1] != 0x00 && !(d[i + 1] >= 0xd0 && d[i + 1] <= 0xd7)) {
      if (d[i + 1] != 0xd9) return false;
      *start = s;
      *len = i + 2 - s;
      *at = i + 2;
      return true;
    }
    i++;
  }
  return false;
}

typedef struct {
  const uint8_t* ref;  // reference frames, planar
  size_t refFrames, frameBytes;
  int w, h, chromaRows;
  OSType wantFormat;
  int frames, errors, wrongFormat, mismatches, missing;
  int maxDiff;
  double sqErr, samples;
  double firstOut;
} Ctx;

static void out_cb(void* refcon, void* frameRefcon, OSStatus st, VTDecodeInfoFlags flags, CVImageBufferRef img,
                   CMTime pts, CMTime dur) {
  (void)pts, (void)dur;
  Ctx* c = refcon;
  long idx = (long)frameRefcon;
  if (st || !img) {
    c->errors++;
    printf("frame %ld: error %d flags %x\n", idx, (int)st, flags);
    return;
  }
  c->frames++;
  OSType f = CVPixelBufferGetPixelFormatType(img);
  if (f != c->wantFormat) {
    c->wrongFormat++;
    printf("frame %ld: pixel format '%c%c%c%c', not the one our decoder gives\n", idx, (char)(f >> 24),
           (char)(f >> 16), (char)(f >> 8), (char)f);
    return;
  }
  if ((size_t)idx >= c->refFrames) {
    c->missing++;
    printf("frame %ld: no reference frame for it\n", idx);
    return;
  }
  const uint8_t* ry = c->ref + (size_t)idx * c->frameBytes;
  int cw = (c->w + 1) / 2;
  const uint8_t* ru = ry + (size_t)c->w * c->h;
  const uint8_t* rv = ru + (size_t)cw * c->chromaRows;
  CVPixelBufferLockBaseAddress(img, kCVPixelBufferLock_ReadOnly);
  const uint8_t* y = CVPixelBufferGetBaseAddressOfPlane(img, 0);
  const uint8_t* uv = CVPixelBufferGetBaseAddressOfPlane(img, 1);
  size_t ys = CVPixelBufferGetBytesPerRowOfPlane(img, 0), uvs = CVPixelBufferGetBytesPerRowOfPlane(img, 1);
  bool sizes = (int)CVPixelBufferGetWidth(img) == c->w && (int)CVPixelBufferGetHeight(img) == c->h &&
               (int)CVPixelBufferGetHeightOfPlane(img, 1) == c->chromaRows;
  int frameMax = 0;
  if (sizes) {
    for (int r = 0; r < c->h; r++)
      for (int x = 0; x < c->w; x++) {
        int dd = abs((int)y[r * ys + x] - (int)ry[(size_t)r * c->w + x]);
        if (dd > frameMax) frameMax = dd;
        c->sqErr += (double)dd * dd;
        c->samples++;
      }
    for (int r = 0; r < c->chromaRows; r++)
      for (int x = 0; x < cw; x++) {
        int du = abs((int)uv[r * uvs + 2 * x] - (int)ru[(size_t)r * cw + x]);
        int dv = abs((int)uv[r * uvs + 2 * x + 1] - (int)rv[(size_t)r * cw + x]);
        int dd = du > dv ? du : dv;
        if (dd > frameMax) frameMax = dd;
        c->sqErr += (double)du * du + (double)dv * dv;
        c->samples += 2;
      }
  }
  CVPixelBufferUnlockBaseAddress(img, kCVPixelBufferLock_ReadOnly);
  if (!sizes) {
    c->mismatches++;
    printf("frame %ld: %zux%zu, not %dx%d\n", idx, CVPixelBufferGetWidth(img), CVPixelBufferGetHeight(img), c->w,
           c->h);
    return;
  }
  if (frameMax > c->maxDiff) c->maxDiff = frameMax;
  if (frameMax > 2) {
    c->mismatches++;
    printf("frame %ld: differs from FFmpeg by up to %d\n", idx, frameMax);
  }
}

static int usage(void) {
  fprintf(stderr,
          "usage: vtjpegtest -load bundle clip.mjpeg reference.yuv width height 420|422 [-dmb1] [-frames N]\n"
          "       vtjpegtest -apple clip.mjpeg reference.yuv width height 420|422 [-dmb1]  (CPU only)\n"
          "A run goes to the GPU: there is no switch to arm.\n");
  return 1;
}

int main(int argc, char** argv) {
  const char* bundle = NULL;
  bool apple = false;
  const char* pos[5];
  int npos = 0, maxFrames = INT_MAX;
  bool dmb1 = false;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "-load") && i + 1 < argc)
      bundle = argv[++i];
    else if (!strcmp(argv[i], "-apple"))
      apple = true;
    else if (!strcmp(argv[i], "-dmb1"))
      dmb1 = true;
    else if (!strcmp(argv[i], "-frames") && i + 1 < argc)
      maxFrames = atoi(argv[++i]);
    else if (npos < 5)
      pos[npos++] = argv[i];
    else
      return usage();
  }
  if (!!bundle == apple || npos != 5 || maxFrames < 1) return usage();
  int w = atoi(pos[2]), h = atoi(pos[3]);
  bool s422 = !strcmp(pos[4], "422");
  if (w < 1 || h < 1 || w > 16384 || h > 16384 || (!s422 && strcmp(pos[4], "420"))) return usage();
  FourCharCode codec = dmb1 ? kCMVideoCodecType_JPEG_OpenDML : kCMVideoCodecType_JPEG;
  const char* fourcc = dmb1 ? "dmb1" : "jpeg";
  if (!apple && load_bundle(bundle, codec, fourcc)) return 1;

  size_t clipLen = 0, refLen = 0;
  uint8_t* clip = read_all(pos[0], &clipLen);
  uint8_t* ref = read_all(pos[1], &refLen);
  if (!clip || !ref) return fprintf(stderr, "cannot read %s or %s\n", pos[0], pos[1]), 1;
  Ctx c = {0};
  c.ref = ref;
  c.w = w;
  c.h = h;
  c.chromaRows = s422 ? h : (h + 1) / 2;
  c.frameBytes = (size_t)w * h + 2 * (size_t)((w + 1) / 2) * c.chromaRows;
  c.refFrames = refLen / c.frameBytes;
  c.wantFormat = s422 ? kCVPixelFormatType_422YpCbCr8BiPlanarFullRange : kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;

  CMVideoFormatDescriptionRef fmt = NULL;
  OSStatus st = CMVideoFormatDescriptionCreate(NULL, codec, w, h, NULL, &fmt);
  if (st) return fprintf(stderr, "format description %d\n", (int)st), 1;
  CFMutableDictionaryRef spec =
      CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFMutableDictionaryRef dest = NULL;
  if (!apple) {
    CFDictionarySetValue(spec, kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder, kCFBooleanTrue);
    CFStringRef id = CFStringCreateWithFormat(NULL, NULL, CFSTR("com.droga.vtjpegtest.%s"), fourcc);
    CFDictionarySetValue(spec, CFSTR("DecoderID"), id);
    printf("asking for decoder com.droga.vtjpegtest.%s (ours, loaded in this process)\n", fourcc);
    CFRelease(id);
  } else {
    // Apple's decoder, converted by VideoToolbox to the format ours gives
    dest = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    int32_t pf = (int32_t)c.wantFormat;
    CFNumberRef n = CFNumberCreate(NULL, kCFNumberSInt32Type, &pf);
    CFDictionarySetValue(dest, kCVPixelBufferPixelFormatTypeKey, n);
    CFRelease(n);
    printf("Apple's software decoder (no -load), output asked as the format ours gives\n");
  }
  VTDecompressionOutputCallbackRecord cb = {out_cb, &c};
  VTDecompressionSessionRef sess = NULL;
  if (dest && getenv("VTJPEG_NODEST")) {  // debugging: Apple's own output format
    CFRelease(dest);
    dest = NULL;
  }
  st = VTDecompressionSessionCreate(NULL, fmt, spec, dest, &cb, &sess);
  CFRelease(spec);
  if (dest) CFRelease(dest);
  printf("VTDecompressionSessionCreate = %d\n", (int)st);
  if (st || !sess) return 1;
  CFBooleanRef hw = NULL;
  VTSessionCopyProperty(sess, kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder, NULL, &hw);
  printf("UsingHardwareAcceleratedVideoDecoder = %s\n", hw == kCFBooleanTrue ? "yes" : "no");
  if (hw) CFRelease(hw);

  size_t at = 0, start = 0, len = 0;
  long fed = 0;
  double t0 = now_ms();
  while (fed < maxFrames && next_picture(clip, clipLen, &at, &start, &len)) {
    CMBlockBufferRef bb = NULL;
    CMSampleBufferRef sb = NULL;
    st = CMBlockBufferCreateWithMemoryBlock(NULL, clip + start, len, kCFAllocatorNull, NULL, 0, len, 0, &bb);
    CMSampleTimingInfo ti = {CMTimeMake(1, 30), CMTimeMake(fed, 30), kCMTimeInvalid};
    size_t ss = len;
    if (!st) st = CMSampleBufferCreateReady(NULL, bb, fmt, 1, 1, &ti, 1, &ss, &sb);
    if (!st) {
      VTDecodeInfoFlags info = 0;
      st = VTDecompressionSessionDecodeFrame(sess, sb, 0, (void*)fed, &info);
      if (st) printf("DecodeFrame %ld -> %d\n", fed, (int)st);
    }
    if (sb) CFRelease(sb);
    if (bb) CFRelease(bb);
    if (st) c.errors++;
    fed++;
  }
  VTDecompressionSessionWaitForAsynchronousFrames(sess);
  double ms = now_ms() - t0;
  VTDecompressionSessionInvalidate(sess);
  CFRelease(sess);
  CFRelease(fmt);
  double psnr = c.sqErr > 0 ? 10 * log10(255.0 * 255.0 * c.samples / c.sqErr) : INFINITY;
  printf("fed %ld pictures (%s %s %dx%d), got %d frames in %.1f ms (%.2f ms each)\n", fed, fourcc,
         s422 ? "4:2:2" : "4:2:0", w, h, c.frames, ms, fed ? ms / (double)fed : 0.0);
  printf("errors %d, wrong pixel format %d, differ %d, no reference %d; max difference %d, PSNR %.2f dB\n", c.errors,
         c.wrongFormat, c.mismatches, c.missing, c.maxDiff, psnr);
  bool ok = fed > 0 && c.frames == fed && !c.errors && !c.wrongFormat && !c.mismatches && !c.missing;
  printf("%s\n", ok ? (apple ? "PASS: every frame from Apple's decoder, matching FFmpeg"
                             : "PASS: every frame from our decoder, matching FFmpeg")
                     : "FAIL");
  free(clip);
  free(ref);
  return ok ? 0 : 2;
}
