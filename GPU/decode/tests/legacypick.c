// legacypick: which decoder VideoToolbox gives an MPEG-4 part 2 stream when
// the MPEG-4 plug-in is registered as an installed copy is (VTRating 400,
// hardware accelerated), next to Apple's own MPEG-4 decoder (AppleMP4V).
// Nothing opens the GPU or the driver: the plug-in runs on a stand-in for
// common/vcnlegacy.c, and any decode or driver session fails the test. It
// checks:
//
//   1. a Simple profile stream goes to our plug-in, not to AppleMP4V (the
//   plug-in is
//      registered with a rating above Apple's: 400 was not enough on 26.7.3,
//      where another MPEG-4 decoder answered first and our plug-in was never
//      asked);
//   2. an Advanced Simple stream whose VOL allows B-VOPs is refused by our
//      plug-in when the session starts, and VideoToolbox goes on to the next
//      decoder;
//   3. no decoder takes it: AppleMP4V refuses it too (2026-11-24, with
//      tests/gpu/vtlegacytest VTLEGACY_DECODER=apple: it takes plain Simple
//      profile only, codecBadDataErr -8969 for Advanced Simple, interlaced
//      or MPEG quantisation), and the session fails with our error, so the
//      app uses its own decoder;
//   4. when our plug-in cannot start a session (no usable driver), another
//      decoder takes the Simple stream: VideoToolbox tries the next one after a
//      refused session start. Whether that decoder is AppleMP4V and whether it
//      calls itself hardware accelerated is not ours to decide (on 26.7.3 the
//      one that answers does), so the check is that a session starts and that
//      it is not ours.
// 3 and 4 are skipped where VideoToolbox lists no AppleMP4V.
//
// The VOL headers are those of two clips made with FFmpeg's mpeg4 encoder
// (with and without B-frames), user data removed.
#include <dlfcn.h>
#include <stdio.h>

#include "../mpeg4/MPEG4VCNDecoder.c"

static int failures;
static void expect(const char* what, int ok) {
  printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) failures++;
}

// ---- the stand-in for vcnlegacy.c
static int g_reached, g_sessions;
static bool g_unavailable;
int vcnlegacy_debug, vcnlegacy_gpu_armed;
bool vcnlegacy_available(char* err, size_t n) {
  if (g_unavailable) {
    snprintf(err, n, "stand-in: no usable driver");
    return false;
  }
  g_reached++;  // the plug-in's session start got past the format checks
  return true;
}
CFDictionaryRef vcnlegacy_copy_pixel_buffer_attributes(uint32_t w, uint32_t h) {
  (void)w, (void)h;
  return CFDictionaryCreate(NULL, NULL, NULL, 0, NULL, NULL);
}
VcnLegacy* vcnlegacy_create(const VcnLegacyConfig* cfg, char* err,
                            size_t errLen) {
  (void)cfg;
  g_sessions++;
  snprintf(err, errLen, "stand-in: no driver session in this test");
  return NULL;
}
void vcnlegacy_destroy(VcnLegacy* d) { (void)d; }
CVPixelBufferRef vcnlegacy_new_target(VcnLegacy* d) {
  (void)d;
  return NULL;
}
int vcnlegacy_decode(VcnLegacy* d, const void* block, uint32_t blockSize,
                     const VcnLegacyBytes* parts, int nparts,
                     CVPixelBufferRef target) {
  (void)d, (void)block, (void)blockSize, (void)parts, (void)nparts,
      (void)target;
  g_sessions++;
  return -1;
}
const char* vcnlegacy_last_error(VcnLegacy* d) {
  (void)d;
  return "stand-in";
}
int vcnlegacy_failure(VcnLegacy* d) {
  (void)d;
  return VCNLEGACY_FAIL_DEVICE;
}
unsigned vcnlegacy_firmware_errors(VcnLegacy* d) {
  (void)d;
  return 0;
}
uint32_t vcnlegacy_width(VcnLegacy* d) {
  (void)d;
  return 0;
}
uint32_t vcnlegacy_height(VcnLegacy* d) {
  (void)d;
  return 0;
}
bool vcnlegacy_session_lost(VcnLegacy* d) {
  (void)d;
  return false;  // the stand-in never gets a session to lose
}
void vcnlegacy_log_rebuild(VcnLegacy* d, const char* what, unsigned dropped) {
  (void)d, (void)what, (void)dropped;
}

// ---- the streams' headers
static const uint8_t kSimple[] = {  // profile 0x01, object type 1
    0x00, 0x00, 0x01, 0xb0, 0x01, 0x00, 0x00, 0x01, 0xb5, 0x89,
    0x13, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x20, 0x00,
    0xc4, 0xf8, 0x78, 0x45, 0x88, 0x00, 0xcd, 0x14, 0x04, 0x3c,
    0x14, 0x43, 0x00, 0x00, 0x01, 0xb3, 0x00, 0x10, 0x07};
static const uint8_t kAdvancedSimpleB[] = {  // 0xf1, object type 17, no
                                             // low_delay
    0x00, 0x00, 0x01, 0xb0, 0xf1, 0x00, 0x00, 0x01, 0xb5, 0xa9,
    0x13, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x20, 0x08,
    0xd4, 0xf8, 0x78, 0x45, 0x08, 0x00, 0xcd, 0x14, 0x04, 0x3c,
    0x14, 0x10, 0x3f, 0x00, 0x00, 0x01, 0xb3, 0x00, 0x10, 0x07};

// An esds atom as an MP4 file carries it (as in tests/gpu/vtlegacytest.c).
static size_t put_descriptor(uint8_t* at, uint8_t tag, size_t len) {
  at[0] = tag;
  at[1] = 0x80 | (uint8_t)((len >> 21) & 0x7f);
  at[2] = 0x80 | (uint8_t)((len >> 14) & 0x7f);
  at[3] = 0x80 | (uint8_t)((len >> 7) & 0x7f);
  at[4] = (uint8_t)(len & 0x7f);
  return 5;
}
static CMVideoFormatDescriptionRef format(const uint8_t* headers, size_t n) {
  uint8_t e[256] = {0};
  size_t decConfig = 13 + 5 + n, es = 3 + 5 + decConfig + 5 + 1;
  size_t at = 4;
  at += put_descriptor(e + at, 3, es);
  e[at++] = 0, e[at++] = 1, e[at++] = 0;
  at += put_descriptor(e + at, 4, decConfig);
  e[at++] = 0x20;
  e[at++] = 0x11;
  at += 11;
  at += put_descriptor(e + at, 5, n);
  memcpy(e + at, headers, n);
  at += n;
  at += put_descriptor(e + at, 6, 1);
  e[at++] = 2;
  CFDataRef data = CFDataCreate(NULL, e, (CFIndex)at);
  const void* k1[] = {CFSTR("esds")};
  const void* v1[] = {data};
  CFDictionaryRef atoms =
      CFDictionaryCreate(NULL, k1, v1, 1, &kCFTypeDictionaryKeyCallBacks,
                         &kCFTypeDictionaryValueCallBacks);
  const void* k2[] = {
      kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms};
  const void* v2[] = {atoms};
  CFDictionaryRef ext =
      CFDictionaryCreate(NULL, k2, v2, 1, &kCFTypeDictionaryKeyCallBacks,
                         &kCFTypeDictionaryValueCallBacks);
  CMVideoFormatDescriptionRef fmt = NULL;
  CMVideoFormatDescriptionCreate(NULL, kCMVideoCodecType_MPEG4Video, 640, 480,
                                 ext, &fmt);
  CFRelease(ext);
  CFRelease(atoms);
  CFRelease(data);
  return fmt;
}

static bool apple_listed(void) {
  OSStatus (*copyList)(CFDictionaryRef, CFArrayRef*) =
      dlsym(RTLD_DEFAULT, "VTCopyVideoDecoderList");
  CFArrayRef decs = NULL;
  if (!copyList || copyList(NULL, &decs) || !decs) return false;
  bool found = false;
  for (CFIndex i = 0; !found && i < CFArrayGetCount(decs); i++) {
    CFStringRef id = CFDictionaryGetValue(CFArrayGetValueAtIndex(decs, i),
                                          CFSTR("DecoderID"));
    found = id && CFGetTypeID(id) == CFStringGetTypeID() &&
            CFEqual(id, CFSTR("com.apple.videotoolbox.videodecoder.mp4v"));
  }
  CFRelease(decs);
  return found;
}

static void on_frame(void* refcon, void* frameRefcon, OSStatus status,
                     VTDecodeInfoFlags flags, CVImageBufferRef image,
                     CMTime pts, CMTime duration) {
  (void)refcon, (void)frameRefcon, (void)status, (void)flags, (void)image,
      (void)pts, (void)duration;
}

// A session for the stream, VideoToolbox picking the decoder: its status,
// and whether the decoder says it is hardware accelerated (ours does; Apple's
// MPEG-4 decoder does not answer).
static OSStatus session(const uint8_t* headers, size_t n, bool* hw) {
  CMVideoFormatDescriptionRef fmt = format(headers, n);
  if (!fmt) return -1;
  VTDecompressionOutputCallbackRecord cb = {on_frame, NULL};
  VTDecompressionSessionRef s = NULL;
  OSStatus st = VTDecompressionSessionCreate(NULL, fmt, NULL, NULL, &cb, &s);
  *hw = false;
  if (!st && s) {
    CFBooleanRef v = NULL;
    VTSessionCopyProperty(
        s, kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
        NULL, &v);
    *hw = v == kCFBooleanTrue;
    if (v) CFRelease(v);
    VTDecompressionSessionInvalidate(s);
    CFRelease(s);
  }
  CFRelease(fmt);
  return st;
}

int main(void) {
  unsetenv("VCNMPEG4_ALLOW_B");
  OSStatus (*reg)(FourCharCode, CFDictionaryRef, void*) =
      dlsym(RTLD_DEFAULT, "VTRegisterVideoDecoderWithInfo");
  expect("VideoToolbox exports VTRegisterVideoDecoderWithInfo", reg != NULL);
  if (!reg) return 1;
  // Above Apple's own MPEG-4 decoder, or VideoToolbox takes that one and the
  // plug-in is never asked: on 26.7.3 a rating of 400 already sits below what
  // answers for a Simple profile stream, and the test failed for a reason that
  // was not the plug-in's.
  int rating = 2000;
  CFNumberRef r = CFNumberCreate(NULL, kCFNumberIntType, &rating);
  const void* k[] = {CFSTR("CMClassImplementationID"), CFSTR("CodecName"),
                     CFSTR("VTCodecType"), CFSTR("VTRating"),
                     CFSTR("IsHardwareAccelerated")};
  const void* v[] = {CFSTR("com.droga.legacypick.mpeg4"), CFSTR("legacypick"),
                     CFSTR("mp4v"), r, kCFBooleanTrue};
  CFDictionaryRef info =
      CFDictionaryCreate(NULL, k, v, 5, &kCFTypeDictionaryKeyCallBacks,
                         &kCFTypeDictionaryValueCallBacks);
  OSStatus st = reg(kCMVideoCodecType_MPEG4Video, info,
                    (void*)MPEG4VCN_VTDecoder_CreateInstance);
  CFRelease(info);
  CFRelease(r);
  expect("the MPEG-4 plug-in is registered in this process", st == noErr);

  bool hw = false;
  g_reached = 0;
  st = session(kSimple, sizeof(kSimple), &hw);
  expect(
      "1. a Simple profile stream gets our plug-in (session started, "
      "hardware accelerated)",
      st == noErr && hw && g_reached == 1);

  bool apple = apple_listed();
  g_reached = 0;
  st = session(kAdvancedSimpleB, sizeof(kAdvancedSimpleB), &hw);
  expect(
      "2. an Advanced Simple stream with B-VOPs reaches our plug-in first, "
      "which refuses it",
      g_reached == 1 && !(st == noErr && hw));
  if (apple) {
    expect(
        "3. no decoder takes it: the session fails with our "
        "kVTVideoDecoderUnsupportedDataFormatErr",
        st == kVTVideoDecoderUnsupportedDataFormatErr);
    g_unavailable = true;
    g_reached = 0;
    st = session(kSimple, sizeof(kSimple), &hw);
    g_unavailable = false;
    expect(
        "4. with our plug-in unable to start, another decoder takes the "
        "Simple stream",
        st == noErr && g_reached == 0);
  } else {
    printf("SKIP 3 and 4: VideoToolbox lists no AppleMP4V here (status %d)\n",
           (int)st);
  }
  expect("no driver session and no decode was asked for", g_sessions == 0);
  printf("%s\n", failures ? "FAILED" : "all passed");
  return failures ? 1 : 0;
}
