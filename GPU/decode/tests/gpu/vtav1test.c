// vtav1test: drives an av01 decoder through the public VideoToolbox API, the
// way Safari does.
//
//   vtav1test [-load bundle] list
//       shows the av01 decoders VideoToolbox knows about (LIST_ALL=1: all of
//       them)
//   vtav1test [-load bundle] file.ivf [file.md5] [-n] [-a] [-pace fps]
//             [-loop N] [-renew] [-id decoder] [-sw] [-attach]
//       decodes the file with a VTDecompressionSession that requires
//       hardware, compares the MD5 of every frame as I420 with the reference,
//       and reports timing
//
// -load registers the bundle in this process only, nothing is installed on the
// system. -n reads no pixels, -a decodes asynchronously, -pace feeds at a fixed
// rate and reports lateness, -loop feeds the file N times in one session (the
// reference starts again each time), -renew makes that a new session for every
// pass, in this same process; with -loop a line per pass says when it ended and
// how it went (for a run across a system sleep). -id picks one decoder when
// several handle av01 (the installed one and a -load'ed build). -sw decodes in
// software only: with -id com.apple.videotoolbox.videodecoder.av1.sw, Apple's
// decoder; a session VideoToolbox gives a hardware decoder anyway decodes
// nothing. -attach prints the colour attachments of the first picture, and
// again whenever they change. VTAV1_DUMP_Y=<file> appends the 8-bit luma of
// every frame to that file.
//
// There is no switch to arm here: a decode run goes to the GPU as soon as an
// AV1 hardware decoder is installed or loaded.
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

#include "av1parse.h"
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
    OSStatus st = reg(kCMVideoCodecType_AV1, info, factory);
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
  printf("VTCopyVideoDecoderList: %s, %ld decoders\n",
         copyList ? "found" : "missing",
         decs ? (long)CFArrayGetCount(decs) : 0L);
  for (CFIndex i = 0; decs && i < CFArrayGetCount(decs); i++) {
    CFStringRef desc = CFCopyDescription(CFArrayGetValueAtIndex(decs, i));
    if (getenv("LIST_ALL") ||
        CFStringFind(desc, CFSTR("av01"), 0).location != kCFNotFound ||
        CFStringFind(desc, CFSTR("AV1"), 0).location != kCFNotFound)
      CFShow(CFArrayGetValueAtIndex(decs, i));
    CFRelease(desc);
  }
  printf("VTIsHardwareDecodeSupported(av01) = %d\n",
         VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1));
  if (decs) CFRelease(decs);
  return 0;
}

typedef struct {
  FILE* md5;
  int frames, mismatches, errors, nohash, attach;
  char lastAttach[1024];
  double *fed, *lat;  // per-frame feed time and output latency (ms), for -pace
} Ctx;

static void out_cb(void* refcon, void* frameRefcon, OSStatus st,
                   VTDecodeInfoFlags flags, CVImageBufferRef img, CMTime pts,
                   CMTime dur) {
  Ctx* c = refcon;
  if (c->lat) {
    long i = (long)frameRefcon;
    c->lat[i] = now_ms() - c->fed[i];
  }
  if (st || !img) {
    c->errors++;
    printf("frame error %d flags %x\n", (int)st, flags);
    return;
  }
  c->frames++;
  if (c->attach) print_attachments(img, c->frames, c->lastAttach);
  if (c->nohash) return;
  int w = (int)CVPixelBufferGetWidth(img), h = (int)CVPixelBufferGetHeight(img);
  uint16_t* row = malloc((size_t)w * 2 + 16);
  if (!row) {
    c->errors++;
    printf("frame %d: out of memory hashing it\n", c->frames);
    return;
  }
  CVPixelBufferLockBaseAddress(img, kCVPixelBufferLock_ReadOnly);
  OSType fmt = CVPixelBufferGetPixelFormatType(img);
  int ten = fmt == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange;
  uint8_t *y = CVPixelBufferGetBaseAddressOfPlane(img, 0),
          *uv = CVPixelBufferGetBaseAddressOfPlane(img, 1);
  size_t ys = CVPixelBufferGetBytesPerRowOfPlane(img, 0),
         uvs = CVPixelBufferGetBytesPerRowOfPlane(img, 1);
  CC_MD5_CTX m;
  CC_MD5_Init(&m);
  int cw = (w + 1) / 2, ch = (h + 1) / 2;
  // VTAV1_DUMP_Y=<file>: append each frame's 8-bit luma (w*h bytes) to it.
  const char* dump = getenv("VTAV1_DUMP_Y");
  if (dump && !ten) {
    FILE* df = fopen(dump, "ab");
    for (int r = 0; df && r < h; r++) fwrite(y + r * ys, 1, w, df);
    if (df) fclose(df);
  }
  for (int r = 0; r < h; r++) {
    if (ten) {
      uint16_t* src = (uint16_t*)(y + r * ys);
      for (int i = 0; i < w; i++) row[i] = src[i] >> 6;
      CC_MD5_Update(&m, row, w * 2);
    } else {
      CC_MD5_Update(&m, y + r * ys, w);
    }
  }
  for (int pl = 0; pl < 2; pl++)
    for (int r = 0; r < ch; r++) {
      if (ten) {
        uint16_t* src = (uint16_t*)(uv + r * uvs);
        for (int i = 0; i < cw; i++) row[i] = src[2 * i + pl] >> 6;
        CC_MD5_Update(&m, row, cw * 2);
      } else {
        uint8_t* b = (uint8_t*)row;
        for (int i = 0; i < cw; i++) b[i] = uv[r * uvs + 2 * i + pl];
        CC_MD5_Update(&m, b, cw);
      }
    }
  free(row);
  CVPixelBufferUnlockBaseAddress(img, kCVPixelBufferLock_ReadOnly);
  uint8_t dg[16];
  char hex[33], expect[64] = "";
  CC_MD5_Final(dg, &m);
  for (int i = 0; i < 16; i++) snprintf(hex + 2 * i, 3, "%02x", dg[i]);
  if (c->md5) {
    char line[512];
    if (fgets(line, sizeof(line), c->md5)) sscanf(line, "%32s", expect);
    if (strcmp(expect, hex)) {
      c->mismatches++;
      printf("frame %d %dx%d %s MISMATCH expected %s\n", c->frames, w, h, hex,
             expect[0] ? expect : "(reference ended)");
    }
  }
}

static int noop_frame(void* ctx, AV1Parser* p, AV1ParseResult k) { return 0; }

// Build an av1C record (ISO/IEC AV1-ISOBMFF 2.3) from the first temporal unit.
static CFDataRef make_av1C(const uint8_t* tu, size_t n) {
  if (!tu || !n) return NULL;
  size_t o = 0;
  while (o < n) {
    uint8_t hdr = tu[o];
    int type = (hdr >> 3) & 15, ext = (hdr >> 2) & 1, has = (hdr >> 1) & 1;
    size_t p = o + 1 + (size_t)ext;
    if (p > n) return NULL;
    size_t sz = 0;
    for (int i = 0, sh = 0; has && i < 8; i++, sh += 7) {
      if (p >= n) return NULL;
      uint8_t b = tu[p++];
      sz |= (size_t)(b & 0x7f) << sh;
      if (!(b & 0x80)) break;
    }
    if (!has) {
      sz = n - p;
    } else if (sz > n - p) {
      return NULL;
    }
    size_t obu_len = p + sz - o;
    if (type == 1) {
      AV1Parser ps;
      av1_parser_init(&ps);
      av1_parse_temporal_unit(&ps, tu + o, obu_len, noop_frame, NULL);
      uint8_t rec[4] = {
          0x81, (uint8_t)(ps.seq.seq_profile << 5 | 13),
          (uint8_t)(ps.seq.high_bitdepth << 6 | ps.seq.twelve_bit << 5 |
                    ps.seq.mono_chrome << 4 | ps.seq.subsampling_x << 3 |
                    ps.seq.subsampling_y << 2 | ps.seq.chroma_sample_position),
          0};
      av1_parser_free(&ps);
      CFMutableDataRef d = CFDataCreateMutable(NULL, 0);
      CFDataAppendBytes(d, rec, 4);
      CFDataAppendBytes(d, tu + o, (CFIndex)obu_len);
      return d;
    }
    o = p + sz;
  }
  return NULL;
}

static int usage(void) {
  fprintf(stderr,
          "usage: vtav1test [-load bundle] list\n"
          "       vtav1test [-load bundle] file.ivf [file.md5] [-n] [-a] "
          "[-pace fps] [-loop N] [-renew] [-id decoder] [-sw] [-attach]\n"
          "A decode run goes to the GPU: there is no switch to arm.\n");
  return 1;
}

static int fail(const char* what) {
  fprintf(stderr, "%s\n", what);
  return 1;
}

int main(int argc, char** argv) {
  if (argc < 2) return usage();
  if (!strcmp(argv[1], "-load")) {
    if (argc < 4) return usage();
    if (load_bundle(argv[2])) return 1;
    argv += 2;
    argc -= 2;
  }
  if (!strcmp(argv[1], "list")) return list();
  if (argv[1][0] == '-') return usage();
  Ctx c = {0};
  int async = 0, require_hw = 1, loops = 1, renew = 0;
  double pace = 0;  // feed frames at this rate (fps) and report output latency
  const char *decoderID = NULL, *md5Path = NULL;
  for (int i = 2; i < argc; i++) {
    if (!strcmp(argv[i], "-n")) {
      c.nohash = 1;
    } else if (!strcmp(argv[i], "-a")) {
      async = 1;
    } else if (!strcmp(argv[i], "-sw")) {
      require_hw = 0;
    } else if (!strcmp(argv[i], "-attach")) {
      c.attach = 1;
    } else if (!strcmp(argv[i], "-pace") && i + 1 < argc) {
      const char* s = argv[++i];
      char* end = NULL;
      double v = strtod(s, &end);
      if (!end || end == s || *end || !(v >= 0)) return fail("invalid -pace");
      pace = v;
    } else if (!strcmp(argv[i], "-loop") && i + 1 < argc) {
      char* end = NULL;
      long v = strtol(argv[++i], &end, 10);
      if (!end || *end || v < 1 || v > INT_MAX / 2)
        return fail("invalid -loop");
      loops = (int)v;
    } else if (!strcmp(argv[i], "-renew")) {
      renew = 1;
    } else if (!strcmp(argv[i], "-id") && i + 1 < argc) {
      decoderID = argv[++i];
    } else if (argv[i][0] == '-' || md5Path) {
      return usage();
    } else {
      md5Path = argv[i];
    }
  }
  // A reference that cannot be opened must not turn into a run that compares
  // nothing and passes.
  if (md5Path && !(c.md5 = fopen(md5Path, "r"))) {
    perror(md5Path);
    return 1;
  }
  FILE* fp = fopen(argv[1], "rb");
  if (!fp) {
    perror(argv[1]);
    return 1;
  }
  uint8_t hdr[32];
  if (fread(hdr, 1, 32, fp) != 32 || memcmp(hdr, "DKIF", 4))
    return fail("not IVF");
  int w = hdr[12] | hdr[13] << 8, h = hdr[14] | hdr[15] << 8;
  // The largest temporal unit the decoder takes (the BS_SIZE of its session).
  // An empty one is reported as a damaged file.
  enum { kMaxTuBytes = 0x1800000u };
  size_t cap = 64, cnt = 0;
  uint8_t** tus = malloc(cap * sizeof(*tus));
  size_t* sizes = malloc(cap * sizeof(*sizes));
  if (!tus || !sizes) return fail("out of memory");
  uint8_t fh[12];
  size_t got;
  while ((got = fread(fh, 1, 12, fp)) == 12) {
    uint32_t sz = fh[0] | fh[1] << 8 | fh[2] << 16 | (uint32_t)fh[3] << 24;
    if (!sz || sz > kMaxTuBytes) {
      fprintf(stderr, "invalid frame size %u at TU %zu\n", sz, cnt);
      return 1;
    }
    if (cnt == cap) {
      cap *= 2;
      tus = realloc(tus, cap * sizeof(*tus));
      sizes = realloc(sizes, cap * sizeof(*sizes));
      if (!tus || !sizes) return fail("out of memory");
    }
    tus[cnt] = malloc(sz);
    if (!tus[cnt]) return fail("out of memory reading a frame");
    if (fread(tus[cnt], 1, sz, fp) != sz) {
      fprintf(stderr, "truncated frame at TU %zu\n", cnt);
      return 1;
    }
    sizes[cnt++] = sz;
  }
  if (got || ferror(fp)) {
    fprintf(stderr, "error reading %s: the file ends inside a frame header\n",
            argv[1]);
    return 1;
  }
  fclose(fp);
  if (!cnt) {
    fprintf(stderr, "no frames in %s\n", argv[1]);
    return 1;
  }
  CFDataRef av1C = make_av1C(tus[0], sizes[0]);
  if (!av1C) return fail("no sequence header in first TU");
  const void* ak[] = {CFSTR("av1C")};
  const void* av[] = {av1C};
  CFDictionaryRef atoms =
      CFDictionaryCreate(NULL, ak, av, 1, &kCFTypeDictionaryKeyCallBacks,
                         &kCFTypeDictionaryValueCallBacks);
  const void* ek[] = {
      kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms};
  const void* ev[] = {atoms};
  CFDictionaryRef ext =
      CFDictionaryCreate(NULL, ek, ev, 1, &kCFTypeDictionaryKeyCallBacks,
                         &kCFTypeDictionaryValueCallBacks);
  CMVideoFormatDescriptionRef fmt = NULL;
  OSStatus st = CMVideoFormatDescriptionCreate(NULL, kCMVideoCodecType_AV1, w,
                                               h, ext, &fmt);
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
  else {
    CFDictionarySetValue(
        spec,
        kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder,
        kCFBooleanFalse);
    // Apple's software decoder is a supplemental one: VideoToolbox finds no
    // av01 software decoder without this.
    VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_AV1);
  }
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
  printf("VTDecompressionSessionCreate(%s) = %d\n",
         require_hw ? "require HW" : "software only", (int)st);
  if (st) return 1;
  CFBooleanRef hw = NULL;
  VTSessionCopyProperty(
      sess, kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
      NULL, &hw);
  printf("UsingHardwareAcceleratedVideoDecoder = %s\n",
         hw == kCFBooleanTrue ? "true" : "false");
  // -sw is a promise that nothing goes to the GPU: a hardware decoder given
  // anyway decodes nothing.
  if (!require_hw && hw == kCFBooleanTrue)
    return fail("-sw: VideoToolbox gave a hardware decoder; nothing decoded");

  double t0 = now_ms();
  int passFrames = 0, passMismatches = 0, passErrors = 0;
  for (size_t i = 0; i < total; i++) {
    size_t k = i % cnt;  // the temporal unit of the file
    if (k == 0 && i > 0) {
      // The pass before is all out: say how it went, with the wall clock, so
      // that a pass across a sleep can be told from the ones before and after.
      VTDecompressionSessionWaitForAsynchronousFrames(sess);
      time_t now = time(NULL);
      char when[32];
      strftime(when, sizeof(when), "%H:%M:%S", localtime(&now));
      printf("pass %zu ended %s: %d frames, %d mismatches, %d errors\n",
             i / cnt, when, c.frames - passFrames,
             c.mismatches - passMismatches, c.errors - passErrors);
      fflush(stdout);
      passFrames = c.frames;
      passMismatches = c.mismatches;
      passErrors = c.errors;
      if (c.md5) rewind(c.md5);
      if (renew) {
        VTDecompressionSessionInvalidate(sess);
        CFRelease(sess);
        sess = NULL;
        st = VTDecompressionSessionCreate(NULL, fmt, spec, NULL, &cb, &sess);
        if (st) {
          printf("pass %zu: VTDecompressionSessionCreate = %d\n", i / cnt + 1,
                 (int)st);
          c.errors++;
          break;
        }
      }
    }
    if (pace > 0) {
      double due = t0 + i * 1000.0 / pace;
      while (now_ms() < due) usleep(200);
      // Lateness is measured against the frame's schedule: a decoder that
      // blocks delays the later frames too.
      c.fed[i] = due;
    }
    CMBlockBufferRef bb = NULL;
    CMBlockBufferCreateWithMemoryBlock(NULL, tus[k], sizes[k], kCFAllocatorNull,
                                       NULL, 0, sizes[k], 0, &bb);
    CMSampleBufferRef sb = NULL;
    CMSampleTimingInfo ti = {CMTimeMake(1, 30), CMTimeMake((int64_t)i, 30),
                             kCMTimeInvalid};
    size_t ss = sizes[k];
    if (bb) CMSampleBufferCreateReady(NULL, bb, fmt, 1, 1, &ti, 1, &ss, &sb);
    if (!sb) {
      printf("frame %zu: no sample buffer\n", i);
      c.errors++;
      if (bb) CFRelease(bb);
      continue;
    }
    VTDecodeInfoFlags info = 0;
    st = VTDecompressionSessionDecodeFrame(
        sess, sb, async ? kVTDecodeFrame_EnableAsynchronousDecompression : 0,
        (void*)(long)i, &info);
    if (st) printf("DecodeFrame %zu -> %d\n", i, (int)st);
    CFRelease(sb);
    CFRelease(bb);
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
  printf("%s: %d frames, %d mismatches, %d errors, %.1f ms (%.1f fps%s)\n",
         argv[1], c.frames, c.mismatches, c.errors, t, c.frames * 1000.0 / t,
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
        "paced %.0f fps: latency avg %.1f ms, max %.1f ms, >2 frames late %d, "
        ">3 frames late %d (of %zu)\n",
        pace, sum / total, mx, late33, late50, total);
  }
  if (sess) {
    VTDecompressionSessionInvalidate(sess);
    CFRelease(sess);
  }
  return c.mismatches || c.errors || c.frames != (int)total ? 2 : 0;
}
