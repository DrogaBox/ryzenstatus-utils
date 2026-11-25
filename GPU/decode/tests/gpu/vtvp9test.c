// vtvp9test: drives a vp09 decoder through the public VideoToolbox API, the
// way Safari does.
//
//   vtvp9test [-load bundle] list
//       shows the vp09 decoders VideoToolbox knows about
//   vtvp9test [-load bundle] file [reference] [-n] [-a] [-pace fps] [-loop N]
//             [-renew] [-frames N] [-id decoder] [-sw] [-attach]
//             [-color primaries,transfer,matrix] [-hdr]
//       decodes the file (IVF or WebM) and compares the MD5 of every frame as
//       I420 with a reference in the format of FFmpeg's FATE suite
//
// -load registers the bundle in this process only, nothing is installed on the
// system. -n reads no pixels, -a decodes asynchronously, -pace feeds at a fixed
// rate and reports lateness, -loop feeds the file N times in one session (a
// seek back to a keyframe), -renew makes that a new session for every pass, in
// this same process (a browser that opens one video after another), and with
// -loop a line per pass says when it ended and how it went (for a run across a
// system sleep), -frames stops after N container frames, -id picks
// one decoder when several handle vp09, -sw doesn't ask for hardware.
// -attach prints the colour attachments of the first picture, and again
// whenever they change. The format description carries no colour unless
// -color gives the H.273 code points a container would (vpcC and the
// format description's colour extensions, as Safari passes a WebM Colour
// element; 9,16,9 = BT.2020 PQ); -hdr adds a typical HDR10 mastering display
// and light level to it. Without -color the plug-in has only the bitstream's
// color_space, which names no transfer function.
//
// There is no switch to arm here: a decode run goes to the GPU as soon as a
// VP9 hardware decoder is installed or loaded.
//
// Exit status: 0 = every frame decoded and matched, 2 = a frame failed,
// differs or is missing, 1 = anything else.
#include <CommonCrypto/CommonDigest.h>
#include <CoreMedia/CoreMedia.h>
#include <VideoToolbox/VideoToolbox.h>
#include <dlfcn.h>
#include <limits.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "container.h"
#include "vp9parse.h"
#include "vtattach.h"

static double now_ms(void) {
  static mach_timebase_info_data_t tb;
  if (!tb.denom) mach_timebase_info(&tb);
  return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

static void copy_kv(const void* k, const void* v, void* dict) {
  CFDictionarySetValue(dict, k, v);
}

// Register a decoder bundle in this process only (nothing is installed on the
// system). Fails when nothing was registered: the run would then test the
// installed decoder while looking like a test of this bundle.
static int load_bundle(const char* path) {
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(
      NULL, (const UInt8*)path, (CFIndex)strlen(path), true);
  CFBundleRef b = url ? CFBundleCreate(NULL, url) : NULL;
  if (url) CFRelease(url);
  if (!b || !CFBundleLoadExecutable(b)) {
    fprintf(stderr, "cannot load %s\n", path);
    return -1;
  }
  CFArrayRef impls =
      CFBundleGetValueForInfoDictionaryKey(b, CFSTR("CMClassImplementations"));
  OSStatus (*reg)(FourCharCode, CFDictionaryRef, void*) =
      dlsym(RTLD_DEFAULT, "VTRegisterVideoDecoderWithInfo");
  int registered = 0;
  for (CFIndex i = 0; impls && reg && i < CFArrayGetCount(impls); i++) {
    CFDictionaryRef impl = CFArrayGetValueAtIndex(impls, i);
    CFStringRef fn = CFDictionaryGetValue(impl, CFSTR("CMFactoryFunction"));
    void* factory = fn ? CFBundleGetFunctionPointerForName(b, fn) : NULL;
    if (!factory) continue;
    CFMutableDictionaryRef info = CFDictionaryCreateMutableCopy(NULL, 0, impl);
    // Dynamic registration ignores CMMatchingInfo: lift the matching keys to
    // the top level.
    CFDictionaryRef match = CFDictionaryGetValue(impl, CFSTR("CMMatchingInfo"));
    if (match) CFDictionaryApplyFunction(match, copy_kv, info);
    CFDictionarySetValue(info, CFSTR("IsHardwareAccelerated"), kCFBooleanTrue);
    CFStringRef name =
        CFDictionaryGetValue(impl, CFSTR("CMClassImplementationName"));
    if (name) CFDictionarySetValue(info, CFSTR("CodecName"), name);
    OSStatus st = reg(kCMVideoCodecType_VP9, info, factory);
    CFRelease(info);
    printf("registered %p from %s -> %d\n", factory, path, (int)st);
    if (!st) registered++;
  }
  if (!registered) {
    fprintf(stderr, "no decoder of %s could be registered\n", path);
    return -1;
  }
  return 0;
}

static int list(void) {
  OSStatus (*copyList)(CFDictionaryRef, CFArrayRef*) =
      dlsym(RTLD_DEFAULT, "VTCopyVideoDecoderList");
  CFArrayRef decs = NULL;
  if (copyList) copyList(NULL, &decs);
  printf("VTCopyVideoDecoderList: %ld decoders\n",
         decs ? (long)CFArrayGetCount(decs) : 0L);
  for (CFIndex i = 0; decs && i < CFArrayGetCount(decs); i++) {
    CFStringRef desc = CFCopyDescription(CFArrayGetValueAtIndex(decs, i));
    if (CFStringFind(desc, CFSTR("vp09"), 0).location != kCFNotFound ||
        CFStringFind(desc, CFSTR("VP9"), 0).location != kCFNotFound)
      CFShow(CFArrayGetValueAtIndex(decs, i));
    CFRelease(desc);
  }
  printf("VTIsHardwareDecodeSupported(vp09) = %d\n",
         VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9));
  if (decs) CFRelease(decs);
  return 0;
}

typedef struct {
  FILE* ref;
  int frames, mismatches, errors, dropped, nohash, attach;
  char lastAttach[1024];
  double *fed, *lat;
} Ctx;

// Next frame line of a FATE reference: "stream, dts, pts, duration, size, md5".
static bool next_ref(Ctx* c, char out[33]) {
  char line[512];
  while (c->ref && fgets(line, sizeof(line), c->ref)) {
    if (line[0] == '#') continue;
    char* h = strrchr(line, ',');
    if (!h) continue;
    return sscanf(h + 1, " %32s", out) == 1;
  }
  return false;
}

static void out_cb(void* refcon, void* frameRefcon, OSStatus st,
                   VTDecodeInfoFlags flags, CVImageBufferRef img, CMTime pts,
                   CMTime dur) {
  Ctx* c = refcon;
  if (c->lat) {
    long i = (long)frameRefcon;
    c->lat[i] = now_ms() - c->fed[i];
  }
  if (st) {
    c->errors++;
    printf("frame error %d flags %x\n", (int)st, flags);
    return;
  }
  if (!img) {
    c->dropped++;
    return;
  }
  if (c->attach) print_attachments(img, c->frames + 1, c->lastAttach);
  c->frames++;
  if (c->nohash) return;
  int w = (int)CVPixelBufferGetWidth(img), h = (int)CVPixelBufferGetHeight(img);
  uint16_t* row = malloc((size_t)w * 2 + 16);
  if (!row) {
    c->errors++;
    printf("frame %d: out of memory hashing it\n", c->frames);
    return;
  }
  CVPixelBufferLockBaseAddress(img, kCVPixelBufferLock_ReadOnly);
  int ten = CVPixelBufferGetPixelFormatType(img) ==
            kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange;
  uint8_t *y = CVPixelBufferGetBaseAddressOfPlane(img, 0),
          *uv = CVPixelBufferGetBaseAddressOfPlane(img, 1);
  size_t ys = CVPixelBufferGetBytesPerRowOfPlane(img, 0),
         uvs = CVPixelBufferGetBytesPerRowOfPlane(img, 1);
  CC_MD5_CTX m;
  CC_MD5_Init(&m);
  int cw = (w + 1) / 2, ch = (h + 1) / 2;
  for (int r = 0; r < h; r++) {
    if (ten) {
      uint16_t* src = (uint16_t*)(y + r * ys);
      for (int i = 0; i < w; i++) row[i] = src[i] >> 6;
      CC_MD5_Update(&m, row, (CC_LONG)w * 2);
    } else {
      CC_MD5_Update(&m, y + r * ys, (CC_LONG)w);
    }
  }
  for (int pl = 0; pl < 2; pl++)
    for (int r = 0; r < ch; r++) {
      if (ten) {
        uint16_t* src = (uint16_t*)(uv + r * uvs);
        for (int i = 0; i < cw; i++) row[i] = src[2 * i + pl] >> 6;
        CC_MD5_Update(&m, row, (CC_LONG)cw * 2);
      } else {
        uint8_t* b = (uint8_t*)row;
        for (int i = 0; i < cw; i++) b[i] = uv[r * uvs + 2 * i + pl];
        CC_MD5_Update(&m, b, (CC_LONG)cw);
      }
    }
  free(row);
  CVPixelBufferUnlockBaseAddress(img, kCVPixelBufferLock_ReadOnly);
  uint8_t dg[16];
  char hex[33], expect[33] = "";
  CC_MD5_Final(dg, &m);
  for (int i = 0; i < 16; i++) snprintf(hex + 2 * i, 3, "%02x", dg[i]);
  if (c->ref) {
    bool have = next_ref(c, expect);
    if (!have || strcmp(expect, hex)) {
      c->mismatches++;
      printf("frame %d %dx%d %s MISMATCH expected %s\n", c->frames, w, h, hex,
             have ? expect : "(reference ended)");
    }
  }
}

// One frame's size and depth without a decoder. The first frame of a stream is
// enough.
typedef struct {
  int w, h, depth, profile, found;
} FirstFrame;
static int first_frame(void* ctx, VP9Parser* p, VP9ParseResult kind,
                       const uint8_t* d, size_t n) {
  FirstFrame* f = ctx;
  if (kind != VP9_PARSE_SHOW_EXISTING && !f->found) {
    f->w = (int)p->fh.width;
    f->h = (int)p->fh.height;
    f->depth = p->fh.bit_depth;
    f->profile = p->fh.profile;
    f->found = 1;
  }
  if (kind != VP9_PARSE_SHOW_EXISTING) vp9_frame_done(p, 0);
  return 0;
}

static int usage(void) {
  fprintf(stderr,
          "usage: vtvp9test [-load bundle] list\n"
          "       vtvp9test [-load bundle] file [reference] [-n] [-a] "
          "[-pace fps] [-loop N] [-renew] [-frames N] [-id decoder] [-sw] "
          "[-attach]\n"
          "       [-color primaries,transfer,matrix] [-hdr]\n"
          "A decode run goes to the GPU: there is no switch to arm.\n");
  return 1;
}

static int fail(const char* what) {
  fprintf(stderr, "%s\n", what);
  return 1;
}

// A whole number from lo to INT_MAX, or -1.
static int parse_count(const char* s, long lo) {
  char* end = NULL;
  long v = strtol(s, &end, 10);
  if (!end || end == s || *end || v < lo || v > INT_MAX) return -1;
  return (int)v;
}

int main(int argc, char** argv) {
  if (argc < 2) return usage();
  // Without this VideoToolbox refuses every vp09 decoder in this process, the
  // real ones too: it is what sets AllowAlternateDecoderSelection on the
  // decoder specification.
  VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9);
  if (!strcmp(argv[1], "-load")) {
    if (argc < 4) return usage();
    if (load_bundle(argv[2])) return 1;
    argv += 2;
    argc -= 2;
  }
  if (!strcmp(argv[1], "list")) return list();
  if (argv[1][0] == '-') return usage();
  Ctx c = {0};
  int async = 0, loops = 1, limit = 0, require_hw = 1, renew = 0;
  // -color: the colour a container would give (vpcC and the format
  // description's extensions), as Safari passes a WebM Colour element. 2 =
  // unspecified, what a stream with no container colour gets.
  int color[3] = {2, 2, 2}, hdr = 0;
  double pace = 0;
  const char *decoderID = NULL, *refPath = NULL;
  for (int i = 2; i < argc; i++) {
    if (!strcmp(argv[i], "-n")) {
      c.nohash = 1;
    } else if (!strcmp(argv[i], "-a")) {
      async = 1;
    } else if (!strcmp(argv[i], "-sw")) {
      require_hw = 0;
    } else if (!strcmp(argv[i], "-attach")) {
      c.attach = 1;
    } else if (!strcmp(argv[i], "-color") && i + 1 < argc) {
      if (sscanf(argv[++i], "%d,%d,%d", &color[0], &color[1], &color[2]) != 3)
        return fail("invalid -color");
      for (int k = 0; k < 3; k++)
        if (color[k] < 0 || color[k] > 255) return fail("invalid -color");
    } else if (!strcmp(argv[i], "-hdr")) {
      hdr = 1;
    } else if (!strcmp(argv[i], "-pace") && i + 1 < argc) {
      const char* s = argv[++i];
      char* end = NULL;
      double v = strtod(s, &end);
      if (!end || end == s || *end || !(v >= 0)) return fail("invalid -pace");
      pace = v;
    } else if (!strcmp(argv[i], "-loop") && i + 1 < argc) {
      if ((loops = parse_count(argv[++i], 1)) < 0) return fail("invalid -loop");
    } else if (!strcmp(argv[i], "-renew")) {
      renew = 1;
    } else if (!strcmp(argv[i], "-frames") && i + 1 < argc) {
      if ((limit = parse_count(argv[++i], 0)) < 0)
        return fail("invalid -frames");
    } else if (!strcmp(argv[i], "-id") && i + 1 < argc) {
      decoderID = argv[++i];
    } else if (argv[i][0] == '-' || refPath) {
      return usage();
    } else {
      refPath = argv[i];
    }
  }
  // A reference that cannot be opened must not turn into a run that compares
  // nothing and passes.
  if (refPath && !(c.ref = fopen(refPath, "r"))) {
    perror(refPath);
    return 1;
  }
  Container f;
  if (!container_open(&f, argv[1])) {
    fprintf(stderr, "%s: %s\n", argv[1], f.problem);
    return 1;
  }
  size_t cap = 4096, cnt = 0;
  const uint8_t** chunks = malloc(cap * sizeof(*chunks));
  size_t* sizes = malloc(cap * sizeof(*sizes));
  if (!chunks || !sizes) return fail("out of memory");
  const uint8_t* data;
  size_t size;
  while ((!limit || (int)cnt < limit) && container_next(&f, &data, &size)) {
    if (cnt == cap) {
      cap *= 2;
      chunks = realloc(chunks, cap * sizeof(*chunks));
      sizes = realloc(sizes, cap * sizeof(*sizes));
      if (!chunks || !sizes) return fail("out of memory");
    }
    chunks[cnt] = data;
    sizes[cnt++] = size;
  }
  if (f.problem) {
    fprintf(stderr, "%s: stopped after chunk %zu: %s\n", argv[1], cnt,
            f.problem);
    return 1;
  }
  if (!cnt) {
    fprintf(stderr, "no frames in %s\n", argv[1]);
    return 1;
  }
  VP9Parser ps;
  vp9_parser_init(&ps);
  FirstFrame ff = {0};
  vp9_parse_chunk(&ps, chunks[0], sizes[0], first_frame, &ff);
  if (!ff.found) return fail("no frame header in the first chunk");

  uint8_t vpcC[12] = {1,
                      0,
                      0,
                      0,
                      (uint8_t)ff.profile,
                      51,
                      (uint8_t)(ff.depth << 4 | 1 << 1),
                      (uint8_t)color[0],
                      (uint8_t)color[1],
                      (uint8_t)color[2],
                      0,
                      0};
  CFDataRef vc = CFDataCreate(NULL, vpcC, sizeof(vpcC));
  const void *ak[] = {CFSTR("vpcC")}, *av[] = {vc};
  CFDictionaryRef atoms =
      CFDictionaryCreate(NULL, ak, av, 1, &kCFTypeDictionaryKeyCallBacks,
                         &kCFTypeDictionaryValueCallBacks);
  const void *ek[] =
      {kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms},
             *ev[] = {atoms};
  CFMutableDictionaryRef ext =
      CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                &kCFTypeDictionaryValueCallBacks);
  CFDictionarySetValue(ext, ek[0], ev[0]);
  CFStringRef cp = CVColorPrimariesGetStringForIntegerCodePoint(color[0]),
              tf = CVTransferFunctionGetStringForIntegerCodePoint(color[1]),
              mc = CVYCbCrMatrixGetStringForIntegerCodePoint(color[2]);
  if (cp)
    CFDictionarySetValue(ext, kCMFormatDescriptionExtension_ColorPrimaries, cp);
  if (tf)
    CFDictionarySetValue(ext, kCMFormatDescriptionExtension_TransferFunction,
                         tf);
  if (mc)
    CFDictionarySetValue(ext, kCMFormatDescriptionExtension_YCbCrMatrix, mc);
  if (hdr) {
    // A typical HDR10 master: P3 primaries, D65, 1000 / 0.005 cd/m2; MaxCLL
    // 1000, MaxFALL 400 (HEVC SEI layout, as an MP4 mdcv/clli box gives it).
    static const uint8_t mdcv[24] = {
        0x33, 0xc2, 0x86, 0xc4, 0x1d, 0x4c, 0x0b, 0xb8, 0x84, 0xd0, 0x3e, 0x80,
        0x3d, 0x13, 0x40, 0x42, 0x00, 0x98, 0x96, 0x80, 0x00, 0x00, 0x00, 0x32};
    static const uint8_t cll[4] = {0x03, 0xe8, 0x01, 0x90};
    CFDataRef m = CFDataCreate(NULL, mdcv, sizeof(mdcv)),
              l = CFDataCreate(NULL, cll, sizeof(cll));
    CFDictionarySetValue(
        ext, kCMFormatDescriptionExtension_MasteringDisplayColorVolume, m);
    CFDictionarySetValue(
        ext, kCMFormatDescriptionExtension_ContentLightLevelInfo, l);
    CFRelease(m);
    CFRelease(l);
  }
  CMVideoFormatDescriptionRef fmt = NULL;
  OSStatus st = CMVideoFormatDescriptionCreate(NULL, kCMVideoCodecType_VP9,
                                               ff.w, ff.h, ext, &fmt);
  if (st) {
    fprintf(stderr, "format description %d\n", (int)st);
    return 1;
  }

  CFMutableDictionaryRef spec =
      CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                &kCFTypeDictionaryValueCallBacks);
  if (require_hw)
    CFDictionarySetValue(
        spec,
        kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder,
        kCFBooleanTrue);
  if (decoderID) {
    CFStringRef id =
        CFStringCreateWithCString(NULL, decoderID, kCFStringEncodingUTF8);
    if (!id) return fail("invalid -id");
    CFDictionarySetValue(spec, CFSTR("DecoderID"), id);
    CFRelease(id);
  }
  size_t total = cnt * (size_t)loops;
  if (pace > 0) {
    c.fed = calloc(total, sizeof(double));
    c.lat = calloc(total, sizeof(double));
    if (!c.fed || !c.lat) return fail("out of memory");
  }
  VTDecompressionOutputCallbackRecord cb = {out_cb, &c};
  VTDecompressionSessionRef sess = NULL;
  st = VTDecompressionSessionCreate(NULL, fmt, spec, NULL, &cb, &sess);
  printf("VTDecompressionSessionCreate = %d\n", (int)st);
  if (st) return 1;
  CFBooleanRef hw = NULL;
  VTSessionCopyProperty(
      sess, kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
      NULL, &hw);
  printf("UsingHardwareAcceleratedVideoDecoder = %s\n",
         hw == kCFBooleanTrue ? "true" : "false");

  double t0 = now_ms();
  size_t fed = 0;
  int passFrames = 0, passMismatches = 0, passErrors = 0;
  for (int l = 0; l < loops; l++) {
    if (l > 0 && loops > 1) {
      // The pass before is all out: say how it went, with the wall clock, so
      // that a pass across a sleep can be told from the ones before and after.
      VTDecompressionSessionWaitForAsynchronousFrames(sess);
      time_t now = time(NULL);
      char when[32];
      strftime(when, sizeof(when), "%H:%M:%S", localtime(&now));
      printf("pass %d ended %s: %d frames, %d mismatches, %d errors\n", l, when,
             c.frames - passFrames, c.mismatches - passMismatches,
             c.errors - passErrors);
      fflush(stdout);
      passFrames = c.frames;
      passMismatches = c.mismatches;
      passErrors = c.errors;
    }
    if (l > 0 && renew) {
      VTDecompressionSessionInvalidate(sess);
      CFRelease(sess);
      sess = NULL;
      st = VTDecompressionSessionCreate(NULL, fmt, spec, NULL, &cb, &sess);
      if (st) {
        printf("pass %d: VTDecompressionSessionCreate = %d\n", l + 1, (int)st);
        c.errors++;
        break;
      }
    }
    if (c.ref) {
      // Every pass over the file starts the reference again, once the frames
      // of the pass before are all out.
      if (async) VTDecompressionSessionWaitForAsynchronousFrames(sess);
      rewind(c.ref);
    }
    for (size_t i = 0; i < cnt; i++, fed++) {
      if (pace > 0) {
        double due = t0 + (double)fed * 1000.0 / pace;
        while (now_ms() < due) usleep(200);
        c.fed[fed] = due;
      }
      CMBlockBufferRef bb = NULL;
      CMBlockBufferCreateWithMemoryBlock(NULL, (void*)chunks[i], sizes[i],
                                         kCFAllocatorNull, NULL, 0, sizes[i], 0,
                                         &bb);
      CMSampleBufferRef sb = NULL;
      CMSampleTimingInfo ti = {CMTimeMake(1, 60), CMTimeMake((int64_t)fed, 60),
                               kCMTimeInvalid};
      size_t ss = sizes[i];
      if (bb) CMSampleBufferCreateReady(NULL, bb, fmt, 1, 1, &ti, 1, &ss, &sb);
      if (!sb) {
        printf("frame %zu: no sample buffer\n", fed);
        c.errors++;
        if (bb) CFRelease(bb);
        continue;
      }
      VTDecodeInfoFlags info = 0;
      st = VTDecompressionSessionDecodeFrame(
          sess, sb, async ? kVTDecodeFrame_EnableAsynchronousDecompression : 0,
          (void*)(long)fed, &info);
      if (st) {
        printf("DecodeFrame %zu -> %d\n", fed, (int)st);
        c.errors++;
      }
      CFRelease(sb);
      CFRelease(bb);
    }
  }
  if (sess) VTDecompressionSessionWaitForAsynchronousFrames(sess);
  double t = now_ms() - t0;
  if (loops > 1) {
    time_t now = time(NULL);
    char when[32];
    strftime(when, sizeof(when), "%H:%M:%S", localtime(&now));
    printf("last pass ended %s: %d frames, %d mismatches, %d errors\n", when,
           c.frames - passFrames, c.mismatches - passMismatches,
           c.errors - passErrors);
  }
  // A decoder that shows fewer frames than the reference lists must not pass.
  // With -frames the file was cut short on purpose.
  int missing = 0;
  char unused[33];
  if (c.ref && !limit && !c.nohash)
    while (next_ref(&c, unused)) missing++;
  if (missing)
    printf("%d reference frame(s) were never decoded  MISSING\n", missing);
  printf(
      "%s: %d frames, %d hidden only, %d mismatches, %d errors, %.1f ms (%.1f "
      "fps%s)\n",
      argv[1], c.frames, c.dropped, c.mismatches + missing, c.errors, t,
      c.frames * 1000.0 / t,
      c.nohash ? (async ? ", async" : "") : ", incl. CPU hashing");
  if (pace > 0) {
    int late33 = 0, late50 = 0;
    double mx = 0, sum = 0;
    for (size_t i = 0; i < total; i++) {
      double l = c.lat[i];
      sum += l;
      if (l > mx) mx = l;
      if (l > 33.3) late33++;
      if (l > 50) late50++;
    }
    printf(
        "paced %.0f fps: latency avg %.1f ms, max %.1f ms, over 33 ms %d, over "
        "50 ms %d (of %zu)\n",
        pace, sum / (double)total, mx, late33, late50, total);
  }
  if (sess) {
    VTDecompressionSessionInvalidate(sess);
    CFRelease(sess);
  }
  return c.mismatches || missing || c.errors ||
                 c.frames + c.dropped != (int)total
             ? 2
             : 0;
}
