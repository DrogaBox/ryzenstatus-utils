// vtenc: VideoToolbox hardware encode probe.
//
//   vtenc list                      print every registered video encoder (no
//   session is created) vtenc props  [--codec hevc]     create a session and
//   dump the encoder's supported properties vtenc encode [options] encode
//   synthetic frames and time every frame
//
// encode options (defaults in brackets):
//   --codec hevc|h264      [hevc]
//   --size WxH             [1920x1080]
//   --fps N                [60]
//   --frames N             [300]
//   --bitrate MBPS         [20]
//   --pace 0|1             [1]  1: submit one frame every 1/fps (like a live
//   capture), 0: as fast as accepted
//   --realtime 0|1|-1      [-1] kVTCompressionPropertyKey_RealTime, -1 leaves
//   it unset
//   --reorder 0|1          [0]  kVTCompressionPropertyKey_AllowFrameReordering
//   --keyint N             [fps*2]
//   --profile NAME         main|main10|baseline|h264main|high  [encoder
//   default]
//   --fmt nv12|p010|bgra   [nv12] pixel format of the source frames
//   --sw 0|1               [0]  1: allow a software encoder (default requires
//   hardware)
//   --lowlatency 0|1       [0]
//   kVTVideoEncoderSpecification_EnableLowLatencyRateControl
//   --out FILE             write the elementary stream (Annex B) for inspection
//   --csv FILE             write per-frame timings
//   --source ring|touch|rewrite|copy|copykeep|new|gpu  [ring] ring: reuse 8
//   prefilled buffers untouched; touch: rewrite one byte of the
//                          buffer before each submit; rewrite: write every byte
//                          of the buffer back in place (same content, all pages
//                          written) before each submit; copy: take a buffer
//                          from the session's pixel buffer pool and copy the
//                          whole frame into it before each submit (what a
//                          capture app does); copykeep: copy the whole frame
//                          into one of 8 buffers this process keeps alive; new:
//                          copy into a newly created buffer every frame,
//                          released after the submit; gpu: fill one of 8 kept
//                          buffers on the GPU with a Metal blit (gpusrc.m, NV12
//                          only)
//   --pause SEC            sleep after the session is prepared (time to attach
//   a debugger to VTEncoderXPCService)
//   --quiet                no per-second progress lines
//
// Build: see build.sh (vtenc.c + gpusrc.m, frameworks VideoToolbox CoreMedia
// CoreVideo CoreFoundation IOSurface Metal Foundation)

#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <IOSurface/IOSurface.h>
#include <VideoToolbox/VideoToolbox.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int gpusrc_init(CVPixelBufferRef* ring, CVPixelBufferRef* dst, int n);
int gpusrc_fill(int i, int k);

static double now_ms(void) {
  static mach_timebase_info_data_t tb;
  if (!tb.denom) mach_timebase_info(&tb);
  return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

static void show(const char* label, CFTypeRef v) {
  if (!v) {
    printf("%s: (null)\n", label);
    return;
  }
  CFStringRef d = CFCopyDescription(v);
  char* buf = malloc(1 << 20);
  CFStringGetCString(d, buf, 1 << 20, kCFStringEncodingUTF8);
  printf("%s: %s\n", label, buf);
  free(buf);
  CFRelease(d);
}

static int cmd_list(void) {
  CFArrayRef list = NULL;
  OSStatus st = VTCopyVideoEncoderList(NULL, &list);
  if (st || !list) {
    printf("VTCopyVideoEncoderList failed: %d\n", (int)st);
    return 1;
  }
  CFIndex n = CFArrayGetCount(list);
  printf("%ld encoders\n", (long)n);
  for (CFIndex i = 0; i < n; i++) {
    CFDictionaryRef d = CFArrayGetValueAtIndex(list, i);
    printf("---- [%ld]\n", (long)i);
    show("entry", d);
  }
  CFRelease(list);
  return 0;
}

// ---------------------------------------------------------------- encode

typedef struct {
  double submit_ms;  // when EncodeFrame was called
  double call_ms;    // how long EncodeFrame blocked
  double prep_ms;  // time spent preparing the source buffer (touch/copy modes)
  double done_ms;  // when the output callback fired
  int bytes;
  int key;
  int status;
  int dropped;
} FrameRec;

static FrameRec* g_rec;
static int g_nframes;
static int g_done;
static FILE* g_out;
static int g_is_hevc = 1;
static int g_wrote_ps;
static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;

static const uint8_t kStartCode[4] = {0, 0, 0, 1};

static void write_param_sets(CMFormatDescriptionRef fd) {
  size_t count = 0;
  int nalLen = 0;
  if (g_is_hevc) {
    if (CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(fd, 0, NULL, NULL,
                                                           &count, &nalLen))
      return;
  } else {
    if (CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fd, 0, NULL, NULL,
                                                           &count, &nalLen))
      return;
  }
  for (size_t i = 0; i < count; i++) {
    const uint8_t* p = NULL;
    size_t sz = 0;
    OSStatus st = g_is_hevc
                      ? CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                            fd, i, &p, &sz, NULL, NULL)
                      : CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                            fd, i, &p, &sz, NULL, NULL);
    if (st) continue;
    fwrite(kStartCode, 1, 4, g_out);
    fwrite(p, 1, sz, g_out);
  }
}

static void output_cb(void* refcon, void* frameRefcon, OSStatus status,
                      VTEncodeInfoFlags flags, CMSampleBufferRef sb) {
  int idx = (int)(intptr_t)frameRefcon;
  double t = now_ms();
  pthread_mutex_lock(&g_mu);
  FrameRec* r = &g_rec[idx];
  r->done_ms = t;
  r->status = (int)status;
  r->dropped = (flags & kVTEncodeInfo_FrameDropped) ? 1 : 0;
  if (sb && status == noErr) {
    r->bytes = (int)CMSampleBufferGetTotalSampleSize(sb);
    CFArrayRef att = CMSampleBufferGetSampleAttachmentsArray(sb, false);
    r->key = 1;
    if (att && CFArrayGetCount(att)) {
      CFDictionaryRef a = CFArrayGetValueAtIndex(att, 0);
      CFBooleanRef notSync =
          CFDictionaryGetValue(a, kCMSampleAttachmentKey_NotSync);
      if (notSync && CFBooleanGetValue(notSync)) r->key = 0;
    }
    if (g_out) {
      if (r->key || !g_wrote_ps) {
        write_param_sets(CMSampleBufferGetFormatDescription(sb));
        g_wrote_ps = 1;
      }
      CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
      size_t total = CMBlockBufferGetDataLength(bb);
      uint8_t* tmp = malloc(total);
      CMBlockBufferCopyDataBytes(bb, 0, total, tmp);
      size_t off = 0;
      while (off + 4 <= total) {
        uint32_t len = (tmp[off] << 24) | (tmp[off + 1] << 16) |
                       (tmp[off + 2] << 8) | tmp[off + 3];
        off += 4;
        if (off + len > total) break;
        fwrite(kStartCode, 1, 4, g_out);
        fwrite(tmp + off, 1, len, g_out);
        off += len;
      }
      free(tmp);
    }
  }
  g_done++;
  pthread_mutex_unlock(&g_mu);
}

static uint32_t xs = 0x1234567;
static inline uint32_t rnd(void) {
  xs ^= xs << 13;
  xs ^= xs >> 17;
  xs ^= xs << 5;
  return xs;
}

// Moving gradient + moving bars + light noise: compressible, but every frame
// differs.
static void fill_frame(CVPixelBufferRef pb, int k, OSType fmt) {
  CVPixelBufferLockBaseAddress(pb, 0);
  size_t w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb);
  if (fmt == kCVPixelFormatType_32BGRA) {
    uint8_t* base = CVPixelBufferGetBaseAddress(pb);
    size_t bpr = CVPixelBufferGetBytesPerRow(pb);
    for (size_t y = 0; y < h; y++) {
      uint8_t* row = base + y * bpr;
      for (size_t x = 0; x < w; x++) {
        uint32_t n = rnd();
        row[x * 4 + 0] = (uint8_t)((x + k * 7) >> 2) + (n & 7);
        row[x * 4 + 1] = (uint8_t)((y + k * 5) >> 2) + ((n >> 3) & 7);
        row[x * 4 + 2] = (uint8_t)((x + y + k * 11) >> 3);
        row[x * 4 + 3] = 255;
      }
    }
  } else {
    int ten = (fmt == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange);
    uint8_t* yp = CVPixelBufferGetBaseAddressOfPlane(pb, 0);
    size_t ys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0);
    uint8_t* cp = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
    size_t cs = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
    for (size_t y = 0; y < h; y++) {
      for (size_t x = 0; x < w; x++) {
        uint32_t n = rnd();
        unsigned v =
            16 + (((x + k * 9) >> 2) + ((y + k * 4) >> 3)) % 200 + (n & 7);
        if ((((x + k * 16) / 64) & 7) == 0) v = 235 - (v >> 2);
        if (ten)
          ((uint16_t*)(yp + y * ys))[x] = (uint16_t)(v << 8);
        else
          yp[y * ys + x] = (uint8_t)v;
      }
    }
    for (size_t y = 0; y < h / 2; y++) {
      for (size_t x = 0; x < w / 2; x++) {
        unsigned u = 64 + ((x + k * 3) >> 2) % 128,
                 v = 64 + ((y + k * 2) >> 2) % 128;
        if (ten) {
          uint16_t* row = (uint16_t*)(cp + y * cs);
          row[x * 2] = (uint16_t)(u << 8);
          row[x * 2 + 1] = (uint16_t)(v << 8);
        } else {
          cp[y * cs + x * 2] = (uint8_t)u;
          cp[y * cs + x * 2 + 1] = (uint8_t)v;
        }
      }
    }
  }
  CVPixelBufferUnlockBaseAddress(pb, 0);
}

static int cmp_d(const void* a, const void* b) {
  double x = *(const double*)a, y = *(const double*)b;
  return x < y ? -1 : x > y;
}

static void stats(const char* name, double* v, int n) {
  if (n <= 0) {
    printf("  %-28s (no samples)\n", name);
    return;
  }
  double sum = 0;
  for (int i = 0; i < n; i++) sum += v[i];
  qsort(v, n, sizeof(double), cmp_d);
  printf("  %-28s avg %8.2f  p50 %8.2f  p95 %8.2f  p99 %8.2f  max %8.2f ms\n",
         name, sum / n, v[n / 2], v[(int)(n * 0.95)], v[(int)(n * 0.99)],
         v[n - 1]);
}

// Ping-pong through the ring so the wrap is not a scene cut (the encoder
// inserts a keyframe on one).
enum { RING = 8 };
static int ring_index(int i) {
  int m = i % (2 * RING - 2);
  return m < RING ? m : 2 * RING - 2 - m;
}

static CFNumberRef num_i(int v) {
  return CFNumberCreate(NULL, kCFNumberIntType, &v);
}

static void set_prop(VTSessionRef s, CFStringRef key, CFTypeRef val,
                     const char* name) {
  OSStatus st = VTSessionSetProperty(s, key, val);
  if (st) printf("  set %s -> error %d\n", name, (int)st);
}

static int cmd_encode(int argc, char** argv, int propsOnly) {
  int w = 1920, h = 1080, fps = 60, frames = 300, pace = 1, realtime = -1,
      reorder = 0, keyint = -1;
  int allowSW = 0, lowlat = 0, quiet = 0, pauseSec = 0, source = 0;
  double mbps = 20;
  const char *codec = "hevc", *profile = NULL, *fmtName = "nv12",
             *outPath = NULL, *csvPath = NULL;
  for (int i = 0; i < argc; i++) {
    const char *a = argv[i], *v = (i + 1 < argc) ? argv[i + 1] : "";
    if (!strcmp(a, "--codec"))
      codec = v, i++;
    else if (!strcmp(a, "--size")) {
      if (sscanf(v, "%dx%d", &w, &h) != 2) {
        printf("bad --size\n");
        return 2;
      }
      i++;
    } else if (!strcmp(a, "--fps"))
      fps = atoi(v), i++;
    else if (!strcmp(a, "--frames"))
      frames = atoi(v), i++;
    else if (!strcmp(a, "--bitrate"))
      mbps = atof(v), i++;
    else if (!strcmp(a, "--pace"))
      pace = atoi(v), i++;
    else if (!strcmp(a, "--realtime"))
      realtime = atoi(v), i++;
    else if (!strcmp(a, "--reorder"))
      reorder = atoi(v), i++;
    else if (!strcmp(a, "--keyint"))
      keyint = atoi(v), i++;
    else if (!strcmp(a, "--profile"))
      profile = v, i++;
    else if (!strcmp(a, "--fmt"))
      fmtName = v, i++;
    else if (!strcmp(a, "--sw"))
      allowSW = atoi(v), i++;
    else if (!strcmp(a, "--lowlatency"))
      lowlat = atoi(v), i++;
    else if (!strcmp(a, "--out"))
      outPath = v, i++;
    else if (!strcmp(a, "--csv"))
      csvPath = v, i++;
    else if (!strcmp(a, "--source"))
      source = !strcmp(v, "touch")      ? 1
               : !strcmp(v, "copy")     ? 2
               : !strcmp(v, "copykeep") ? 3
               : !strcmp(v, "new")      ? 4
               : !strcmp(v, "rewrite")  ? 5
               : !strcmp(v, "gpu")      ? 6
                                        : 0,
      i++;
    else if (!strcmp(a, "--pause"))
      pauseSec = atoi(v), i++;
    else if (!strcmp(a, "--quiet"))
      quiet = 1;
    else {
      printf("unknown option %s\n", a);
      return 2;
    }
  }
  if (keyint < 0) keyint = fps * 2;
  g_is_hevc = strcmp(codec, "h264") != 0;
  CMVideoCodecType ctype =
      g_is_hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264;
  OSType fmt = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
  if (!strcmp(fmtName, "p010"))
    fmt = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange;
  else if (!strcmp(fmtName, "bgra"))
    fmt = kCVPixelFormatType_32BGRA;

  printf(
      "== %s %dx%d @%d fps, %d frames, %.1f Mbps, fmt %s, pace %d, realtime "
      "%d, reorder %d, keyint %d, lowlatency %d, source %s, hw %s\n",
      codec, w, h, fps, frames, mbps, fmtName, pace, realtime, reorder, keyint,
      lowlat,
      source == 6   ? "gpu"
      : source == 5 ? "rewrite"
      : source == 4 ? "new"
      : source == 3 ? "copykeep"
      : source == 2 ? "copy"
      : source == 1 ? "touch"
                    : "ring",
      allowSW ? "preferred" : "required");

  CFMutableDictionaryRef spec =
      CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                &kCFTypeDictionaryValueCallBacks);
  if (allowSW)
    CFDictionarySetValue(
        spec,
        kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder,
        kCFBooleanTrue);
  else
    CFDictionarySetValue(
        spec,
        kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder,
        kCFBooleanTrue);
  if (lowlat)
    CFDictionarySetValue(
        spec, kVTVideoEncoderSpecification_EnableLowLatencyRateControl,
        kCFBooleanTrue);

  VTCompressionSessionRef s = NULL;
  double t0 = now_ms();
  OSStatus st = VTCompressionSessionCreate(NULL, w, h, ctype, spec, NULL, NULL,
                                           output_cb, NULL, &s);
  double tCreate = now_ms() - t0;
  printf("VTCompressionSessionCreate: status %d, %.1f ms\n", (int)st, tCreate);
  if (st || !s) {
    printf("RESULT: no session (status %d)\n", (int)st);
    return 1;
  }

  CFTypeRef v = NULL;
  if (VTSessionCopyProperty(
          s, kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder,
          NULL, &v) == noErr &&
      v) {
    printf("UsingHardwareAcceleratedVideoEncoder: %s\n",
           CFBooleanGetValue(v) ? "YES" : "NO");
    CFRelease(v);
  } else
    printf("UsingHardwareAcceleratedVideoEncoder: (not reported)\n");
  v = NULL;
  if (VTSessionCopyProperty(s, kVTCompressionPropertyKey_EncoderID, NULL, &v) ==
          noErr &&
      v) {
    show("EncoderID", v);
    CFRelease(v);
  }

  if (propsOnly) {
    CFDictionaryRef sup = NULL;
    st = VTSessionCopySupportedPropertyDictionary(s, &sup);
    printf("VTSessionCopySupportedPropertyDictionary: %d\n", (int)st);
    if (sup) {
      show("supported", sup);
      CFRelease(sup);
    }
    VTCompressionSessionInvalidate(s);
    CFRelease(s);
    return 0;
  }

  CFNumberRef n;
  if (realtime >= 0)
    set_prop(s, kVTCompressionPropertyKey_RealTime,
             realtime ? kCFBooleanTrue : kCFBooleanFalse, "RealTime");
  set_prop(s, kVTCompressionPropertyKey_AllowFrameReordering,
           reorder ? kCFBooleanTrue : kCFBooleanFalse, "AllowFrameReordering");
  n = num_i(keyint);
  set_prop(s, kVTCompressionPropertyKey_MaxKeyFrameInterval, n,
           "MaxKeyFrameInterval");
  CFRelease(n);
  n = num_i(fps);
  set_prop(s, kVTCompressionPropertyKey_ExpectedFrameRate, n,
           "ExpectedFrameRate");
  CFRelease(n);
  n = num_i((int)(mbps * 1e6));
  set_prop(s, kVTCompressionPropertyKey_AverageBitRate, n, "AverageBitRate");
  CFRelease(n);
  if (profile) {
    CFStringRef p = NULL;
    if (!strcmp(profile, "main"))
      p = kVTProfileLevel_HEVC_Main_AutoLevel;
    else if (!strcmp(profile, "main10"))
      p = kVTProfileLevel_HEVC_Main10_AutoLevel;
    else if (!strcmp(profile, "baseline"))
      p = kVTProfileLevel_H264_Baseline_AutoLevel;
    else if (!strcmp(profile, "h264main"))
      p = kVTProfileLevel_H264_Main_AutoLevel;
    else if (!strcmp(profile, "high"))
      p = kVTProfileLevel_H264_High_AutoLevel;
    if (!p) {
      printf("unknown profile\n");
      return 2;
    }
    set_prop(s, kVTCompressionPropertyKey_ProfileLevel, p, "ProfileLevel");
  }
  t0 = now_ms();
  st = VTCompressionSessionPrepareToEncodeFrames(s);
  printf("PrepareToEncodeFrames: status %d, %.1f ms\n", (int)st, now_ms() - t0);

  if (pauseSec) {
    printf("pausing %d s (attach a debugger to VTEncoderXPCService now)\n",
           pauseSec);
    sleep(pauseSec);
  }

  // Source frames: a small ring of IOSurface-backed buffers filled before
  // timing starts.
  CVPixelBufferRef ring[RING];
  CFMutableDictionaryRef attrs =
      CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                &kCFTypeDictionaryValueCallBacks);
  CFDictionaryRef empty =
      CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                         &kCFTypeDictionaryValueCallBacks);
  CFDictionarySetValue(attrs, kCVPixelBufferIOSurfacePropertiesKey, empty);
  for (int i = 0; i < RING; i++) {
    if (CVPixelBufferCreate(NULL, w, h, fmt, attrs, &ring[i])) {
      printf("CVPixelBufferCreate failed\n");
      return 1;
    }
    fill_frame(ring[i], i, fmt);
  }

  CVPixelBufferRef keep[RING];
  uint32_t ids[64];
  int nids = 0;
  if (source == 3 || source == 6)
    for (int i = 0; i < RING; i++)
      if (CVPixelBufferCreate(NULL, w, h, fmt, attrs, &keep[i])) {
        printf("CVPixelBufferCreate failed\n");
        return 1;
      }
  if (source == 6) {
    if (fmt != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
      printf("--source gpu needs --fmt nv12\n");
      return 2;
    }
    int gr = gpusrc_init(ring, keep, RING);
    if (gr) {
      printf("gpusrc_init failed (%d)\n", gr);
      return 1;
    }
  }
  g_nframes = frames;
  g_rec = calloc(frames, sizeof(FrameRec));
  if (outPath) g_out = fopen(outPath, "wb");

  double start = now_ms(), period = 1000.0 / fps, lastReport = start;
  int lastDone = 0, submitErr = 0;
  for (int i = 0; i < frames; i++) {
    if (pace) {
      double due = start + i * period, t = now_ms();
      if (due > t) usleep((useconds_t)((due - t) * 1000));
    }
    CMTime pts = CMTimeMake(i, fps);
    double a = now_ms();
    pthread_mutex_lock(&g_mu);
    g_rec[i].submit_ms = a;
    pthread_mutex_unlock(&g_mu);
    CVPixelBufferRef src = ring[ring_index(i)], fresh = NULL;
    if (source == 1) {
      CVPixelBufferLockBaseAddress(src, 0);
      uint8_t* b = CVPixelBufferIsPlanar(src)
                       ? CVPixelBufferGetBaseAddressOfPlane(src, 0)
                       : CVPixelBufferGetBaseAddress(src);
      b[0] ^= 1;
      CVPixelBufferUnlockBaseAddress(src, 0);
    } else if (source == 5) {
      CVPixelBufferLockBaseAddress(src, 0);
      for (size_t pl = 0; pl < CVPixelBufferGetPlaneCount(src); pl++) {
        volatile uint8_t* b = CVPixelBufferGetBaseAddressOfPlane(src, pl);
        size_t n = CVPixelBufferGetBytesPerRowOfPlane(src, pl) *
                   CVPixelBufferGetHeightOfPlane(src, pl);
        for (size_t k = 0; k < n; k += 64) b[k] = b[k];
      }
      CVPixelBufferUnlockBaseAddress(src, 0);
    } else if (source == 6) {
      if (gpusrc_fill(i % RING, ring_index(i))) {
        printf("gpusrc_fill failed\n");
        return 1;
      }
      src = keep[i % RING];
    } else if (source >= 2) {
      if (source == 2) {
        CVPixelBufferPoolRef pool = VTCompressionSessionGetPixelBufferPool(s);
        if (!pool || CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &fresh)) {
          printf("no pixel buffer from the session pool\n");
          return 1;
        }
        if (i == 0)
          printf("pool buffer: format %08x, IOSurface %s\n",
                 (unsigned)CVPixelBufferGetPixelFormatType(fresh),
                 CVPixelBufferGetIOSurface(fresh) ? "yes" : "no");
      } else if (source == 3) {
        fresh = keep[i % RING];
      } else if (CVPixelBufferCreate(NULL, w, h, fmt, attrs, &fresh)) {
        printf("CVPixelBufferCreate failed\n");
        return 1;
      }
      if (source != 3 && i < 64) {
        uint32_t sid = IOSurfaceGetID(CVPixelBufferGetIOSurface(fresh));
        int seen = 0;
        for (int k = 0; k < nids; k++) seen |= ids[k] == sid;
        if (!seen) ids[nids++] = sid;
      }
      CVPixelBufferLockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
      CVPixelBufferLockBaseAddress(fresh, 0);
      size_t np = CVPixelBufferGetPlaneCount(fresh);
      for (size_t pl = 0; pl < (np ? np : 1); pl++) {
        uint8_t* d = np ? CVPixelBufferGetBaseAddressOfPlane(fresh, pl)
                        : CVPixelBufferGetBaseAddress(fresh);
        uint8_t* sp = np ? CVPixelBufferGetBaseAddressOfPlane(src, pl)
                         : CVPixelBufferGetBaseAddress(src);
        size_t db = np ? CVPixelBufferGetBytesPerRowOfPlane(fresh, pl)
                       : CVPixelBufferGetBytesPerRow(fresh);
        size_t sb = np ? CVPixelBufferGetBytesPerRowOfPlane(src, pl)
                       : CVPixelBufferGetBytesPerRow(src);
        size_t rows = np ? CVPixelBufferGetHeightOfPlane(fresh, pl)
                         : CVPixelBufferGetHeight(fresh);
        for (size_t y = 0; y < rows; y++)
          memcpy(d + y * db, sp + y * sb, db < sb ? db : sb);
      }
      CVPixelBufferUnlockBaseAddress(fresh, 0);
      CVPixelBufferUnlockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
      src = fresh;
    }
    double c0 = now_ms();
    g_rec[i].prep_ms = c0 - a;
    st = VTCompressionSessionEncodeFrame(s, src, pts, CMTimeMake(1, fps), NULL,
                                         (void*)(intptr_t)i, NULL);
    if (fresh && source != 3) CVPixelBufferRelease(fresh);
    a = c0;
    double b = now_ms();
    g_rec[i].call_ms = b - a;
    if (st) {
      if (!submitErr) printf("EncodeFrame[%d] error %d\n", i, (int)st);
      submitErr++;
      g_rec[i].status = (int)st;
    }
    if (!quiet && b - lastReport >= 1000) {
      pthread_mutex_lock(&g_mu);
      int d = g_done;
      pthread_mutex_unlock(&g_mu);
      printf(
          "  t=%5.1fs submitted %d, completed %d (%.1f fps out in the last "
          "second)\n",
          (b - start) / 1000, i + 1, d,
          (d - lastDone) * 1000.0 / (b - lastReport));
      lastDone = d;
      lastReport = b;
    }
  }
  double tSubmitEnd = now_ms();
  st = VTCompressionSessionCompleteFrames(s, kCMTimeInvalid);
  double end = now_ms();
  printf("CompleteFrames: status %d, waited %.1f ms\n", (int)st,
         end - tSubmitEnd);

  double *lat = malloc(sizeof(double) * frames),
         *call = malloc(sizeof(double) * frames),
         *gap = malloc(sizeof(double) * frames);
  int nl = 0, ng = 0, nerr = 0, ndrop = 0, nkey = 0;
  long long bytes = 0;
  double firstDone = 0, lastDoneT = 0, prev = 0;
  FILE* csv = csvPath ? fopen(csvPath, "w") : NULL;
  if (csv)
    fprintf(csv,
            "frame,submit_ms,call_ms,latency_ms,bytes,key,status,dropped\n");
  for (int i = 0; i < frames; i++) {
    FrameRec* r = &g_rec[i];
    call[i] = r->call_ms;
    if (csv)
      fprintf(csv, "%d,%.3f,%.3f,%.3f,%d,%d,%d,%d\n", i, r->submit_ms - start,
              r->call_ms, r->done_ms ? r->done_ms - r->submit_ms : -1, r->bytes,
              r->key, r->status, r->dropped);
    if (r->status) nerr++;
    if (r->dropped) ndrop++;
    if (!r->done_ms || r->status || r->dropped) continue;
    lat[nl++] = r->done_ms - r->submit_ms;
    bytes += r->bytes;
    nkey += r->key;
    if (!firstDone) firstDone = r->done_ms;
    if (prev) gap[ng++] = r->done_ms - prev;
    prev = r->done_ms;
    lastDoneT = r->done_ms;
  }
  if (csv) fclose(csv);
  if (g_out) fclose(g_out);

  double wall = end - start;
  printf(
      "RESULT %s %dx%d@%d: %d/%d frames out, %d errors, %d dropped, %d "
      "keyframes\n",
      codec, w, h, fps, nl, frames, nerr, ndrop, nkey);
  printf(
      "  wall %.1f ms -> %.2f fps encoded (target %d); first output after %.1f "
      "ms\n",
      wall, nl * 1000.0 / wall, fps, firstDone ? firstDone - start : -1.0);
  if (nl > 1)
    printf("  steady output rate (first..last output) %.2f fps\n",
           (nl - 1) * 1000.0 / (lastDoneT - firstDone));
  printf("  bitstream %.2f Mbps (%lld bytes)\n",
         bytes * 8.0 * fps / (nl ? nl : 1) / 1e6, bytes);
  if (source == 2 || source == 4)
    printf("  distinct IOSurfaces in the first 64 frames: %d\n", nids);
  if (source) {
    double* pr = malloc(sizeof(double) * frames);
    for (int i = 0; i < frames; i++) pr[i] = g_rec[i].prep_ms;
    stats("source buffer prep", pr, frames);
    free(pr);
  }
  stats("EncodeFrame call time", call, frames);
  stats("submit->output latency", lat, nl);
  stats("gap between outputs", gap, ng);

  VTCompressionSessionInvalidate(s);
  CFRelease(s);
  return nerr || nl != frames;
}

int main(int argc, char** argv) {
  setvbuf(stdout, NULL, _IOLBF, 0);
  if (argc < 2) {
    printf(
        "usage: vtenc list | props [opts] | encode [opts]   (see the header of "
        "vtenc.c)\n");
    return 2;
  }
  if (!strcmp(argv[1], "list")) return cmd_list();
  if (!strcmp(argv[1], "props")) return cmd_encode(argc - 2, argv + 2, 1);
  if (!strcmp(argv[1], "encode")) return cmd_encode(argc - 2, argv + 2, 0);
  printf("unknown command %s\n", argv[1]);
  return 2;
}
