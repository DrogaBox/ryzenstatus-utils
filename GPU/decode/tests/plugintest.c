// plugintest: the VideoToolbox side of a decoder plug-in, with the decoder
// session replaced by a stand-in (nothing opens the GPU or the driver). Built
// once for each plug-in, with -DTEST_AV1, -DTEST_VP9, -DTEST_MPEG2, -DTEST_VC1
// or -DTEST_MPEG4 (the last three share common/vtlegacy.h and have no hidden
// frames: their sample 6 is one more shown frame). It checks:
//
//   1. the factory refuses a NULL result pointer;
//   2. a second session start replaces the decoder of the first;
//   3. a format of another codec is not accepted;
//   4. a shown frame, a sample with no shown frame (dropped, no error), a
//      sample that holds only a hidden frame (its picture, no error: FFmpeg
//      makes a new session on a decode with no picture), a sample that fails
//      after showing a frame (an error, no picture) and a frame with a missing
//      reference (kVTVideoDecoderReferenceMissingErr, which FFmpeg skips);
//   5. calls made from inside the output callback (finish delayed frames, a
//      synchronous decode, more asynchronous decodes than the queue holds) do
//      not trap or hang;
//   6. a NULL sample is refused;
//   7. after invalidate, frames are refused and nothing is emitted;
//   8. (AV1) a sequence header in av1C that the engine cannot decode refuses
//      the session;
//   9. a sample the decoder session fails as a device failure (a stuck GPU,
//      a driver call that failed) is a malfunction, not bad data, and the
//      format is not accepted after it; one that runs out of memory is
//      kVTAllocationFailedErr;
//  10. after a start that fails, no format is accepted;
//  11. canAcceptFormatDescription does not wait for a decode in progress;
//  12. a start that invalidate overtakes closes its new session again;
//  13. an invalidate on another thread while a decode waits for a queue slot
//      returns only after that decode has left the plug-in, and the frame is
//      refused;
//  14. finalize from inside the output callback (the host lets go of the
//      decoder there, and CoreMedia frees its storage when finalize returns),
//      with frames still queued and a synchronous decode on another thread
//      waiting for the queue: nothing freed is used (the address sanitizer
//      stops the program if it is), nothing more is emitted, every queued
//      frame lets go of its sample, and the session ends once and not while
//      a frame decodes;
//  15. an invalidate on another thread while a decode has passed its check
//      for invalidate and not yet queued its frame returns only after that
//      decode has queued it, and the frame is emitted;
//  16. (AV1, VP9) the picture handed back carries the colour attachments:
//      AV1 takes the stream's values before the format description's, VP9
//      the format description's before the stream's, each value on its own;
//      a picture with no colour from either loses what an earlier one left.
//
// usage: plugintest   (exit status 0 = pass)
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <unistd.h>

// The plug-in's semaphore waits go through test_semaphore_wait, so that test
// 13 can hold a decode between taking a queue slot and queuing its frame; its
// dispatch_sync calls through test_dispatch_sync, so that test 14 knows when a
// synchronous decode is on its way into the queue; and its CFRetain calls
// through test_CFRetain, so that test 15 can hold a decode at the retain of
// its sample, after its check for invalidate and before it queues the frame.
static long test_semaphore_wait(dispatch_semaphore_t sem, dispatch_time_t t);
static void test_dispatch_sync(dispatch_queue_t q, dispatch_block_t b);
static CFTypeRef test_CFRetain(CFTypeRef cf);
#define dispatch_semaphore_wait test_semaphore_wait
#define dispatch_sync test_dispatch_sync
#define CFRetain test_CFRetain
#if defined(TEST_AV1)
#include "../av1/AV1VCNDecoder.c"
#define CODEC kCMVideoCodecType_AV1
#define CREATE AV1VCN_VTDecoder_CreateInstance
typedef VcnAV1 Vcn;
typedef VcnAV1OutputFn OutputFn;
#elif defined(TEST_VP9)
#include "../vp9/VP9VCNDecoder.c"
#define CODEC kCMVideoCodecType_VP9
#define CREATE VP9VCN_VTDecoder_CreateInstance
typedef VcnVP9 Vcn;
typedef VcnVP9OutputFn OutputFn;
#elif defined(TEST_MPEG2) || defined(TEST_VC1) || defined(TEST_MPEG4)
#define TEST_LEGACY 1
#if defined(TEST_MPEG2)
#include "../mpeg2/MPEG2VCNDecoder.c"
#define CODEC kCMVideoCodecType_MPEG2Video
#define CREATE MPEG2VCN_VTDecoder_CreateInstance
#define FAKE_CODEC vcnmpeg2_codec
#elif defined(TEST_VC1)
#include "../vc1/VC1VCNDecoder.c"
#define CODEC 'WVC1'
#define CREATE VC1VCN_VTDecoder_CreateInstance
#define FAKE_CODEC vcnvc1_codec
#else
#include "../mpeg4/MPEG4VCNDecoder.c"
#define CODEC kCMVideoCodecType_MPEG4Video
#define CREATE MPEG4VCN_VTDecoder_CreateInstance
#define FAKE_CODEC vcnmpeg4_codec
#endif
typedef void Vcn;
typedef VcnLegacyOutputFn OutputFn;
#else
#error \
    "build with -DTEST_AV1, -DTEST_VP9, -DTEST_MPEG2, -DTEST_VC1 or -DTEST_MPEG4"
#endif
#undef dispatch_semaphore_wait
#undef dispatch_sync
#undef CFRetain

// Run once, by the next plug-in wait that returns, before the plug-in goes on.
static void (*afterWait)(void);
static int waitsStarted;
static long test_semaphore_wait(dispatch_semaphore_t sem, dispatch_time_t t) {
  __atomic_add_fetch(&waitsStarted, 1, __ATOMIC_SEQ_CST);
  long r = dispatch_semaphore_wait(sem, t);
  void (*hook)(void) = __atomic_exchange_n(&afterWait, NULL, __ATOMIC_SEQ_CST);
  if (hook) hook();
  return r;
}
static int syncsStarted;
static void test_dispatch_sync(dispatch_queue_t q, dispatch_block_t b) {
  __atomic_add_fetch(&syncsStarted, 1, __ATOMIC_SEQ_CST);
  dispatch_sync(q, b);
}
// Run once, by the next plug-in CFRetain on the thread retainThread names.
static void (*atRetain)(void);
static pthread_t retainThread;
static CFTypeRef test_CFRetain(CFTypeRef cf) {
  if (__atomic_load_n(&atRetain, __ATOMIC_SEQ_CST) &&
      pthread_equal(pthread_self(), retainThread)) {
    void (*hook)(void) = __atomic_exchange_n(&atRetain, NULL, __ATOMIC_SEQ_CST);
    if (hook) hook();
  }
  return CFRetain(cf);
}

static int failures;
static void expect(const char* what, bool ok) {
  printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) failures++;
}

// ---- stand-ins for the CoreMedia / VideoToolbox plug-in SPI
// -------------------
OSStatus CMDerivedObjectCreate(CFAllocatorRef alloc, const void* vtable,
                               CMBaseClassID id, CMBaseObjectRef* out) {
  (void)alloc;
  (void)vtable;
  (void)id;
  *out = calloc(1, sizeof(Storage));
  return *out ? noErr : kVTAllocationFailedErr;
}
void* CMBaseObjectGetDerivedStorage(CMBaseObjectRef obj) { return obj; }
CMBaseClassID VTVideoDecoderGetClassID(void) { return NULL; }
CMBaseObjectRef VTVideoDecoderGetCMBaseObject(VTVideoDecoderRef dec) {
  return (CMBaseObjectRef)dec;
}
OSStatus VTDecoderSessionSetPixelBufferAttributes(VTVideoDecoderSession s,
                                                  CFDictionaryRef a) {
  (void)s;
  (void)a;
  return noErr;
}

static int emits, emitErrors, emitImages, emitDropped;
static OSStatus lastStatus;
static void (*inCallback)(void);
OSStatus VTDecoderSessionEmitDecodedFrame(VTVideoDecoderSession session,
                                          VTVideoDecoderFrame frame,
                                          OSStatus status,
                                          VTDecodeInfoFlags flags,
                                          CVImageBufferRef image) {
  (void)session;
  (void)frame;
  __atomic_add_fetch(&emits, 1, __ATOMIC_RELAXED);
  if (status) __atomic_add_fetch(&emitErrors, 1, __ATOMIC_RELAXED);
  if (image) __atomic_add_fetch(&emitImages, 1, __ATOMIC_RELAXED);
  if (flags & kVTDecodeInfo_FrameDropped)
    __atomic_add_fetch(&emitDropped, 1, __ATOMIC_RELAXED);
  lastStatus = status;
  void (*hook)(void) = inCallback;
  inCallback = NULL;
  if (hook) hook();
  return noErr;
}

// ---- stand-in decoder session
// ------------------------------------------------- A sample's first byte says
// what it does: 0 shows nothing, 1 shows a frame, 2 shows a frame and then
// fails as a bad stream, 3 fails as a broken device, 4 runs out of memory, 5
// shows a frame after waiting (at most 3 s) for the test to let it go, 6
// decodes only a hidden frame, 7 fails on a missing reference.
struct Fake {
  int unused;
};
static int creates, destroys;
static bool failCreate;  // the next session start fails
static int lastFailure;
// Invalidated by the next session start while it makes its session.
static VTVideoDecoderRef invalidateInCreate;
// Sample 5: says it is decoding, then waits to be let go.
static dispatch_semaphore_t slowEntered, slowRelease;
static bool slowTimedOut;
static void slow_decode(void) {
  dispatch_semaphore_signal(slowEntered);
  if (dispatch_semaphore_wait(
          slowRelease, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)))
    slowTimedOut = true;
}
static int fake_failure(uint8_t what);
#if defined(TEST_AV1)
static int configureResult;
#endif
static CVPixelBufferRef picture;
static bool hiddenOnly;  // the last decode decoded only a hidden frame

// Decodes running in the stand-in session; a session destroyed while one runs
// sets destroyedWhileDecoding. A session is freed when it is destroyed, so a
// decode on it afterwards is a use after free.
static int decodesRunning;
static bool destroyedWhileDecoding;
static Vcn* fake_create(void) {
  if (failCreate) return NULL;
  if (invalidateInCreate) base_invalidate((CMBaseObjectRef)invalidateInCreate);
  creates++;
  return (Vcn*)calloc(1, sizeof(struct Fake));
}
static void fake_destroy(Vcn* d) {
  if (__atomic_load_n(&decodesRunning, __ATOMIC_SEQ_CST))
    destroyedWhileDecoding = true;
  __atomic_add_fetch(&destroys, 1, __ATOMIC_SEQ_CST);
  free(d);
}
static void fake_decode_begin(Vcn* d) {
  __atomic_add_fetch(&decodesRunning, 1, __ATOMIC_SEQ_CST);
  ((struct Fake*)d)->unused++;  // reads and writes the session
}
static void fake_decode_end(void) {
  __atomic_sub_fetch(&decodesRunning, 1, __ATOMIC_SEQ_CST);
}

#if defined(TEST_AV1)
int vcnav1_gpu_armed;
VcnAV1* vcnav1_create(uint32_t w, uint32_t h, char* err, size_t n) {
  (void)w, (void)h, (void)err, (void)n;
  return fake_create();
}
void vcnav1_destroy(VcnAV1* d) { fake_destroy(d); }
int vcnav1_configure(VcnAV1* d, const uint8_t* o, size_t n) {
  (void)d, (void)o, (void)n;
  return configureResult;
}
const char* vcnav1_last_error(VcnAV1* d) {
  (void)d;
  return "stand-in";
}
unsigned vcnav1_firmware_errors(VcnAV1* d) {
  (void)d;
  return 0;
}
CFDictionaryRef vcnav1_copy_pixel_buffer_attributes(uint32_t w, uint32_t h,
                                                    bool t) {
  (void)w, (void)h, (void)t;
  return CFDictionaryCreate(NULL, NULL, NULL, 0, NULL, NULL);
}
int vcnav1_decode(VcnAV1* d, const uint8_t* tu, size_t size, int64_t tag,
                  VcnAV1OutputFn fn, void* ctx) {
  (void)size;
  fake_decode_begin(d);
  if (tu[0] == 5) slow_decode();
  if (tu[0] == 1 || tu[0] == 2 || tu[0] == 5) fn(ctx, picture, NULL, tag);
  hiddenOnly = tu[0] == 6;
  lastFailure = fake_failure(tu[0]);
  fake_decode_end();
  return (tu[0] >= 2 && tu[0] <= 4) || tu[0] == 7 ? -1 : 0;
}
int vcnav1_failure(VcnAV1* d) {
  (void)d;
  return lastFailure;
}
CVPixelBufferRef vcnav1_hidden_picture(VcnAV1* d) {
  (void)d;
  return hiddenOnly ? picture : NULL;
}
static VcnColor streamColor = {
    .primaries = -1, .transfer = -1, .matrix = -1};  // what the stand-in says
void vcnav1_color(VcnAV1* d, VcnColor* c) {
  (void)d;
  *c = streamColor;
}
#elif defined(TEST_LEGACY)
// The codec layer the plug-in drives, and the two functions of
// common/vcnlegacy.c it calls itself.
int vcnlegacy_gpu_armed;
bool vcnlegacy_available(char* err, size_t n) {
  (void)err, (void)n;
  return !failCreate;
}
CFDictionaryRef vcnlegacy_copy_pixel_buffer_attributes(uint32_t w, uint32_t h) {
  (void)w, (void)h;
  return CFDictionaryCreate(NULL, NULL, NULL, 0, NULL, NULL);
}
static void* legacy_create(const uint8_t* config, size_t configSize, uint32_t w,
                           uint32_t h, char* err, size_t n) {
  (void)config, (void)configSize, (void)w, (void)h, (void)err, (void)n;
  return fake_create();
}
static int legacy_decode(void* d, const uint8_t* chunk, size_t size,
                         VcnLegacyOutputFn fn, void* ctx) {
  (void)size;
  fake_decode_begin(d);
  if (chunk[0] == 5) slow_decode();
  if (chunk[0] == 1 || chunk[0] == 2 || chunk[0] == 5 || chunk[0] == 6)
    fn(ctx, picture, VCNLEGACY_PIC_REFERENCE, 16, 16);
  hiddenOnly = false;
  lastFailure = fake_failure(chunk[0]);
  fake_decode_end();
  return (chunk[0] >= 2 && chunk[0] <= 4) || chunk[0] == 7 ? -1 : 0;
}
static const char* legacy_last_error(void* d) {
  (void)d;
  return "stand-in";
}
static int legacy_failure(void* d) {
  (void)d;
  return lastFailure;
}
static unsigned legacy_firmware_errors(void* d) {
  (void)d;
  return 0;
}
const VcnLegacyCodec FAKE_CODEC = {.name = "stand-in",
                                   .create = legacy_create,
                                   .destroy = fake_destroy,
                                   .decode = legacy_decode,
                                   .last_error = legacy_last_error,
                                   .failure = legacy_failure,
                                   .firmware_errors = legacy_firmware_errors};
#else
int vcnvp9_gpu_armed;
VcnVP9* vcnvp9_create(uint32_t w, uint32_t h, char* err, size_t n) {
  (void)w, (void)h, (void)err, (void)n;
  return fake_create();
}
void vcnvp9_destroy(VcnVP9* d) { fake_destroy(d); }
const char* vcnvp9_last_error(VcnVP9* d) {
  (void)d;
  return "stand-in";
}
unsigned vcnvp9_firmware_errors(VcnVP9* d) {
  (void)d;
  return 0;
}
CFDictionaryRef vcnvp9_copy_pixel_buffer_attributes(uint32_t w, uint32_t h,
                                                    bool t) {
  (void)w, (void)h, (void)t;
  return CFDictionaryCreate(NULL, NULL, NULL, 0, NULL, NULL);
}
int vcnvp9_decode(VcnVP9* d, const uint8_t* chunk, size_t size, int64_t tag,
                  VcnVP9OutputFn fn, void* ctx) {
  (void)size;
  fake_decode_begin(d);
  if (chunk[0] == 5) slow_decode();
  if (chunk[0] == 1 || chunk[0] == 2 || chunk[0] == 5)
    fn(ctx, picture, NULL, 16, 16, tag);
  hiddenOnly = chunk[0] == 6;
  lastFailure = fake_failure(chunk[0]);
  fake_decode_end();
  return (chunk[0] >= 2 && chunk[0] <= 4) || chunk[0] == 7 ? -1 : 0;
}
int vcnvp9_failure(VcnVP9* d) {
  (void)d;
  return lastFailure;
}
CVPixelBufferRef vcnvp9_hidden_picture(VcnVP9* d) {
  (void)d;
  return hiddenOnly ? picture : NULL;
}
static VcnColor streamColor = {.primaries = -1, .transfer = -1, .matrix = -1};
void vcnvp9_color(VcnVP9* d, VcnColor* c) {
  (void)d;
  *c = streamColor;
}
#endif

#if defined(TEST_AV1)
static int fake_failure(uint8_t what) {
  return what == 3   ? VCNAV1_FAIL_DEVICE
         : what == 4 ? VCNAV1_FAIL_MEMORY
         : what == 7 ? VCNAV1_FAIL_REFERENCE
                     : VCNAV1_FAIL_STREAM;
}
#elif defined(TEST_LEGACY)
static int fake_failure(uint8_t what) {
  return what == 3   ? VCNLEGACY_FAIL_DEVICE
         : what == 4 ? VCNLEGACY_FAIL_MEMORY
         : what == 7 ? VCNLEGACY_FAIL_REFERENCE
                     : VCNLEGACY_FAIL_STREAM;
}
#else
static int fake_failure(uint8_t what) {
  return what == 3   ? VCNVP9_FAIL_DEVICE
         : what == 4 ? VCNVP9_FAIL_MEMORY
         : what == 7 ? VCNVP9_FAIL_REFERENCE
                     : VCNVP9_FAIL_STREAM;
}
#endif

// ---- helpers
// ------------------------------------------------------------------
static CMSampleBufferRef sample(uint8_t what) {
  static uint8_t bytes[8][4] = {{0, 1, 2, 3}, {1, 1, 2, 3}, {2, 1, 2, 3},
                                {3, 1, 2, 3}, {4, 1, 2, 3}, {5, 1, 2, 3},
                                {6, 1, 2, 3}, {7, 1, 2, 3}};
  CMBlockBufferRef bb = NULL;
  if (CMBlockBufferCreateWithMemoryBlock(NULL, bytes[what], 4, kCFAllocatorNull,
                                         NULL, 0, 4, 0, &bb))
    return NULL;
  CMSampleBufferRef sb = NULL;
  size_t sz = 4;
  CMSampleBufferCreate(NULL, bb, true, NULL, NULL, NULL, 1, 0, NULL, 1, &sz,
                       &sb);
  CFRelease(bb);
  return sb;
}

static CMVideoFormatDescriptionRef format(CMVideoCodecType codec,
                                          const uint8_t* av1C, size_t len) {
  CFDictionaryRef ext = NULL;
  if (av1C) {
    CFDataRef data = CFDataCreate(NULL, av1C, (CFIndex)len);
    const void* k1[] = {CFSTR("av1C")};
    const void* v1[] = {data};
    CFDictionaryRef atoms =
        CFDictionaryCreate(NULL, k1, v1, 1, &kCFTypeDictionaryKeyCallBacks,
                           &kCFTypeDictionaryValueCallBacks);
    const void* k2[] = {
        kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms};
    const void* v2[] = {atoms};
    ext = CFDictionaryCreate(NULL, k2, v2, 1, &kCFTypeDictionaryKeyCallBacks,
                             &kCFTypeDictionaryValueCallBacks);
    CFRelease(atoms);
    CFRelease(data);
  }
  CMVideoFormatDescriptionRef f = NULL;
  CMVideoFormatDescriptionCreate(NULL, codec, 64, 64, ext, &f);
  if (ext) CFRelease(ext);
  return f;
}

#if !defined(TEST_LEGACY)
static VTVideoDecoderRef dec;
// Test 16: a format description with colour extensions; NULL values are left
// out.
static CMVideoFormatDescriptionRef color_format(CFStringRef prim,
                                                CFStringRef tf, CFStringRef mat,
                                                const uint8_t* mdcv,
                                                const uint8_t* cll) {
  CFMutableDictionaryRef ext =
      CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                &kCFTypeDictionaryValueCallBacks);
  if (prim)
    CFDictionarySetValue(ext, kCMFormatDescriptionExtension_ColorPrimaries,
                         prim);
  if (tf)
    CFDictionarySetValue(ext, kCMFormatDescriptionExtension_TransferFunction,
                         tf);
  if (mat)
    CFDictionarySetValue(ext, kCMFormatDescriptionExtension_YCbCrMatrix, mat);
  if (mdcv) {
    CFDataRef d = CFDataCreate(NULL, mdcv, 24);
    CFDictionarySetValue(
        ext, kCMFormatDescriptionExtension_MasteringDisplayColorVolume, d);
    CFRelease(d);
  }
  if (cll) {
    CFDataRef d = CFDataCreate(NULL, cll, 4);
    CFDictionarySetValue(
        ext, kCMFormatDescriptionExtension_ContentLightLevelInfo, d);
    CFRelease(d);
  }
  CMVideoFormatDescriptionRef f = NULL;
  CMVideoFormatDescriptionCreate(NULL, CODEC, 64, 64, ext, &f);
  CFRelease(ext);
  return f;
}
// The picture's attachment for key is the string want (NULL: none).
static bool has_name(CFStringRef key, CFStringRef want) {
  CFTypeRef v = CVBufferCopyAttachment(picture, key, NULL);
  bool ok = want ? v && CFEqual(v, want) : !v;
  if (v) CFRelease(v);
  return ok;
}
// The picture's attachment for key is these n bytes (NULL: none).
static bool has_bytes(CFStringRef key, const uint8_t* want, CFIndex n) {
  CFTypeRef v = CVBufferCopyAttachment(picture, key, NULL);
  bool ok = want ? v && CFGetTypeID(v) == CFDataGetTypeID() &&
                       CFDataGetLength(v) == n &&
                       !memcmp(CFDataGetBytePtr(v), want, (size_t)n)
                 : !v;
  if (v) CFRelease(v);
  return ok;
}
static void decode_with(CMVideoFormatDescriptionRef f) {
  dec_start_session(dec, NULL, f);
  CMSampleBufferRef sb = sample(1);
  dec_decode_frame(dec, NULL, sb, 0, NULL);
  CFRelease(sb);
}
static void color_tests(void) {
#if defined(TEST_AV1)
  static const uint8_t mdcvA[24] = {1,  2,  3,  4,  5,  6,  7,  8,
                                    9,  10, 11, 12, 13, 14, 15, 16,
                                    17, 18, 19, 20, 21, 22, 23, 24};
#endif
  static const uint8_t mdcvB[24] = {0x3d, 0x13, 0x86, 0xc4};
  static const uint8_t cllB[4] = {0x03, 0xe8, 0x01, 0x90};
  CMVideoFormatDescriptionRef sdr =
      color_format(kCMFormatDescriptionColorPrimaries_ITU_R_709_2,
                   kCMFormatDescriptionTransferFunction_ITU_R_709_2,
                   kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2, mdcvB, cllB);
  CMVideoFormatDescriptionRef pqOnly =
      color_format(NULL, kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ,
                   NULL, NULL, NULL);
  CMVideoFormatDescriptionRef none = format(CODEC, NULL, 0);
#if defined(TEST_AV1)
  // The sequence header says BT.2020 PQ and the stream sent a mastering
  // display; the container says BT.709 and has both kinds of metadata.
  vcn_color_clear(&streamColor);
  streamColor.primaries = 9;
  streamColor.transfer = 16;
  streamColor.matrix = 9;
  streamColor.has_mdcv = true;
  memcpy(streamColor.mdcv, mdcvA, 24);
  decode_with(sdr);
  expect("AV1: the sequence header's colour wins over the container's",
         has_name(kCVImageBufferColorPrimariesKey,
                  kCVImageBufferColorPrimaries_ITU_R_2020) &&
             has_name(kCVImageBufferTransferFunctionKey,
                      kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ) &&
             has_name(kCVImageBufferYCbCrMatrixKey,
                      kCVImageBufferYCbCrMatrix_ITU_R_2020));
  expect(
      "AV1: the stream's mastering display wins, the container's light "
      "level fills in",
      has_bytes(kCVImageBufferMasteringDisplayColorVolumeKey, mdcvA, 24) &&
          has_bytes(kCVImageBufferContentLightLevelInfoKey, cllB, 4));
  // Unspecified (2) in the sequence header: the container's values.
  streamColor.primaries = streamColor.transfer = streamColor.matrix = 2;
  streamColor.has_mdcv = false;
  decode_with(sdr);
  expect(
      "AV1: an unspecified sequence header takes the container's colour",
      has_name(kCVImageBufferColorPrimariesKey,
               kCVImageBufferColorPrimaries_ITU_R_709_2) &&
          has_name(kCVImageBufferTransferFunctionKey,
                   kCVImageBufferTransferFunction_ITU_R_709_2) &&
          has_bytes(kCVImageBufferMasteringDisplayColorVolumeKey, mdcvB, 24));
  streamColor.primaries = 9;
  streamColor.matrix = 9;
  decode_with(pqOnly);
  expect(
      "AV1: each value on its own (primaries and matrix from the stream, "
      "transfer from the container)",
      has_name(kCVImageBufferColorPrimariesKey,
               kCVImageBufferColorPrimaries_ITU_R_2020) &&
          has_name(kCVImageBufferTransferFunctionKey,
                   kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ) &&
          has_name(kCVImageBufferYCbCrMatrixKey,
                   kCVImageBufferYCbCrMatrix_ITU_R_2020));
#else
  // color_space BT.2020 names primaries and matrix, never the transfer.
  vcn_color_clear(&streamColor);
  streamColor.primaries = streamColor.matrix = 9;
  decode_with(pqOnly);
  expect("VP9: the container's transfer, the bitstream's primaries and matrix",
         has_name(kCVImageBufferColorPrimariesKey,
                  kCVImageBufferColorPrimaries_ITU_R_2020) &&
             has_name(kCVImageBufferTransferFunctionKey,
                      kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ) &&
             has_name(kCVImageBufferYCbCrMatrixKey,
                      kCVImageBufferYCbCrMatrix_ITU_R_2020) &&
             has_bytes(kCVImageBufferMasteringDisplayColorVolumeKey, NULL, 24));
  decode_with(sdr);
  expect(
      "VP9: the container's colour wins over the bitstream's, with its "
      "HDR metadata",
      has_name(kCVImageBufferColorPrimariesKey,
               kCVImageBufferColorPrimaries_ITU_R_709_2) &&
          has_name(kCVImageBufferYCbCrMatrixKey,
                   kCVImageBufferYCbCrMatrix_ITU_R_709_2) &&
          has_bytes(kCVImageBufferMasteringDisplayColorVolumeKey, mdcvB, 24) &&
          has_bytes(kCVImageBufferContentLightLevelInfoKey, cllB, 4));
#endif
  // Nothing from either: what the earlier pictures left is taken off.
  vcn_color_clear(&streamColor);
  decode_with(none);
  expect(
      "a picture with no colour from stream or container loses the old "
      "tags",
      has_name(kCVImageBufferColorPrimariesKey, NULL) &&
          has_name(kCVImageBufferTransferFunctionKey, NULL) &&
          has_name(kCVImageBufferYCbCrMatrixKey, NULL) &&
          has_bytes(kCVImageBufferMasteringDisplayColorVolumeKey, NULL, 24) &&
          has_bytes(kCVImageBufferContentLightLevelInfoKey, NULL, 4));
  CFRelease(sdr);
  CFRelease(pqOnly);
  CFRelease(none);
}
#endif

static VTVideoDecoderRef dec;
static int reentered;
static void reenter(void) {
  // All of these run on the decode queue, from inside the output callback.
  dec_finish_delayed_frames(dec);
  CMSampleBufferRef sb = sample(1);
  dec_decode_frame(dec, NULL, sb, 0, NULL);
  for (int i = 0; i < MAX_QUEUED + 2; i++)
    dec_decode_frame(dec, NULL, sb,
                     kVTDecodeFrame_EnableAsynchronousDecompression, NULL);
  CFRelease(sb);
  reentered = 1;
}

// Test 13: a decode on its own thread that waits for a queue slot, and an
// invalidate on another. Each says, through `order`, when it left the plug-in.
static dispatch_semaphore_t slotTaken, slotHold, invalidateDone;
static int order, decodeLeft, invalidateLeft;
static OSStatus waitingResult;
static CMSampleBufferRef waitingSample;
static void hold_after_slot(void) {
  dispatch_semaphore_signal(slotTaken);
  dispatch_semaphore_wait(slotHold,
                          dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
}
static void* waiting_decode(void* arg) {
  (void)arg;
  waitingResult =
      dec_decode_frame(dec, NULL, waitingSample,
                       kVTDecodeFrame_EnableAsynchronousDecompression, NULL);
  decodeLeft = __atomic_add_fetch(&order, 1, __ATOMIC_SEQ_CST);
  return NULL;
}
static void* invalidating(void* arg) {
  (void)arg;
  base_invalidate((CMBaseObjectRef)dec);
  invalidateLeft = __atomic_add_fetch(&order, 1, __ATOMIC_SEQ_CST);
  dispatch_semaphore_signal(invalidateDone);
  return NULL;
}

// Test 14: the output callback lets go of the decoder, as a host that releases
// its session there does: finalize, and then CoreMedia frees the storage.
static bool finalizedInCallback;
static void finalize_in_callback(void) {
  VTVideoDecoderRef d = dec;
  dec = NULL;
  base_finalize((CMBaseObjectRef)d);
  free(d);
  finalizedInCallback = true;
}
static CMSampleBufferRef syncSample;
static bool syncLeft;
static void* sync_decode(void* arg) {
  dec_decode_frame((VTVideoDecoderRef)arg, NULL, syncSample, 0, NULL);
  __atomic_store_n(&syncLeft, true, __ATOMIC_SEQ_CST);
  return NULL;
}

// Test 15: a decode held at the retain of its sample, after it found no
// invalidate begun and before it queues its frame.
static dispatch_semaphore_t retainHeld, retainHold;
static void hold_at_retain(void) {
  dispatch_semaphore_signal(retainHeld);
  dispatch_semaphore_wait(retainHold,
                          dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
}
static void* held_decode(void* arg) {
  retainThread = pthread_self();
  __atomic_store_n(&atRetain, hold_at_retain, __ATOMIC_SEQ_CST);
  return waiting_decode(arg);
}

static void hung(int sig) {
  (void)sig;
  static const char msg[] = "FAIL a call from inside the callback hung\n";
  write(1, msg, sizeof(msg) - 1);
  _exit(1);
}

int main(void) {
  int d0;
  setvbuf(stdout, NULL, _IOLBF, 0);  // what passed is kept if a test crashes
  signal(SIGALRM, hung);
  alarm(30);
  CVPixelBufferCreate(NULL, 16, 16,
                      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, NULL,
                      &picture);

  expect("the factory refuses a NULL result pointer",
         CREATE(CODEC, NULL, NULL) == kVTParameterErr);
  expect("the factory makes a decoder", !CREATE(CODEC, NULL, &dec) && dec);
  CMBaseObjectRef obj = (CMBaseObjectRef)dec;

  CMVideoFormatDescriptionRef fmt = format(CODEC, NULL, 0);
  expect("a session starts",
         !dec_start_session(dec, NULL, fmt) && creates == 1);
  expect("a second start replaces the first decoder",
         !dec_start_session(dec, NULL, fmt) && creates == 2 && destroys == 1);
  expect("the same format is accepted", dec_can_accept_format(dec, fmt));
  CMVideoFormatDescriptionRef h264 = format(kCMVideoCodecType_H264, NULL, 0);
  expect("an H.264 format of the same size is not",
         !dec_can_accept_format(dec, h264));
  CFRelease(h264);

  CMSampleBufferRef shown = sample(1), hidden = sample(0), broken = sample(2);
  int e = emits;
  dec_decode_frame(dec, NULL, shown, 0, NULL);
  expect("a shown frame is emitted with its picture",
         emits == e + 1 && !lastStatus && emitImages == 1);
  dec_decode_frame(dec, NULL, hidden, 0, NULL);
  expect("a sample with no shown frame is dropped, with no error",
         emits == e + 2 && !lastStatus && emitDropped == 1 && emitImages == 1);
  CMSampleBufferRef hiddenAlone = sample(6), noRef = sample(7);
  int dropped = emitDropped;
  dec_decode_frame(dec, NULL, hiddenAlone, 0, NULL);
#if defined(TEST_LEGACY)
  expect("one more shown frame is emitted with its picture",
         emits == e + 3 && !lastStatus && emitImages == 2 &&
             emitDropped == dropped);
#else
  expect("a sample of only a hidden frame hands back its picture, no error",
         emits == e + 3 && !lastStatus && emitImages == 2 &&
             emitDropped == dropped);
#endif
  dec_decode_frame(dec, NULL, noRef, 0, NULL);
  expect("a missing reference is kVTVideoDecoderReferenceMissingErr",
         emits == e + 4 && lastStatus == kVTVideoDecoderReferenceMissingErr &&
             emitImages == 2);
  CFRelease(hiddenAlone);
  CFRelease(noRef);
  e += 2;
  dec_decode_frame(dec, NULL, broken, 0, NULL);
  expect("a sample that fails after showing a frame is an error, no picture",
         emits == e + 3 && lastStatus == kVTVideoDecoderBadDataErr &&
             emitImages == 2);
  CMSampleBufferRef stuck = sample(3);
  dec_decode_frame(dec, NULL, stuck, 0, NULL);
  expect("a sample failed by a stuck GPU or a driver call is a malfunction",
         emits == e + 4 && lastStatus == kVTVideoDecoderMalfunctionErr &&
             emitImages == 2);
  CFRelease(stuck);
  expect("after a device failure the format is not accepted",
         !dec_can_accept_format(dec, fmt));
  CMSampleBufferRef nomem = sample(4);
  dec_decode_frame(dec, NULL, nomem, 0, NULL);
  expect("a sample that runs out of memory is kVTAllocationFailedErr",
         emits == e + 5 && lastStatus == kVTAllocationFailedErr);
  CFRelease(nomem);
  expect("a new start takes the format again",
         !dec_start_session(dec, NULL, fmt) && dec_can_accept_format(dec, fmt));
#if !defined(TEST_LEGACY)
  color_tests();
  expect("the session takes the first format again",
         !dec_start_session(dec, NULL, fmt) && dec_can_accept_format(dec, fmt));
#endif

  // A decode holds the session while the GPU works on its frame.
  CMSampleBufferRef slow = sample(5);
  slowEntered = dispatch_semaphore_create(0);
  slowRelease = dispatch_semaphore_create(0);
  dec_decode_frame(dec, NULL, slow,
                   kVTDecodeFrame_EnableAsynchronousDecompression, NULL);
  bool entered = !dispatch_semaphore_wait(
      slowEntered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
  Boolean accepted = dec_can_accept_format(dec, fmt);
  bool blocked = slowTimedOut;
  dispatch_semaphore_signal(slowRelease);
  dec_finish_delayed_frames(dec);
  expect("canAcceptFormatDescription does not wait for a running decode",
         entered && accepted && !blocked);
  CFRelease(slow);

  e = emits;
  inCallback = reenter;
  dec_decode_frame(dec, NULL, shown, 0, NULL);
  dec_finish_delayed_frames(dec);
  // 1 frame, then from the callback 1 synchronous and MAX_QUEUED + 2 queued.
  expect("calls from inside the output callback neither trap nor hang",
         reentered && emits == e + 2 + MAX_QUEUED + 2);
  inCallback = reenter;
  reentered = 0;
  e = emits;
  dec_decode_frame(dec, NULL, shown,
                   kVTDecodeFrame_EnableAsynchronousDecompression, NULL);
  dec_finish_delayed_frames(dec);
  expect("the same from an asynchronous frame",
         reentered && emits == e + 2 + MAX_QUEUED + 2);

  expect("a NULL sample is refused",
         dec_decode_frame(dec, NULL, NULL, 0, NULL) == kVTParameterErr &&
             dec_decode_frame(dec, NULL, NULL,
                              kVTDecodeFrame_EnableAsynchronousDecompression,
                              NULL) == kVTParameterErr);

  base_invalidate(obj);
  expect("after invalidate the format is not accepted",
         !dec_can_accept_format(dec, fmt));
  e = emits;
  OSStatus r1 = dec_decode_frame(dec, NULL, shown, 0, NULL),
           r2 = dec_decode_frame(dec, NULL, shown,
                                 kVTDecodeFrame_EnableAsynchronousDecompression,
                                 NULL);
  dec_finish_delayed_frames(dec);
  expect("after invalidate frames are refused and nothing is emitted",
         r1 == kVTInvalidSessionErr && r2 == kVTInvalidSessionErr &&
             emits == e && destroys == creates);
  base_finalize(obj);
  free(obj);

  expect("a decoder for the failed start test",
         !CREATE(CODEC, NULL, &dec) && dec);
  expect("its session starts", !dec_start_session(dec, NULL, fmt));
  failCreate = true;
  d0 = destroys;
  expect(
      "a second start whose session cannot be made fails",
      dec_start_session(dec, NULL, fmt) == kVTVideoDecoderNotAvailableNowErr &&
          destroys == d0 + 1);
  failCreate = false;
  expect("after a start that failed, the format is not accepted",
         !dec_can_accept_format(dec, fmt));
  e = emits;
  OSStatus r3 = dec_decode_frame(dec, NULL, shown, 0, NULL);
  expect("and a frame is refused as an invalid session",
         !r3 && emits == e + 1 && lastStatus == kVTInvalidSessionErr);
  base_invalidate((CMBaseObjectRef)dec);
  base_finalize((CMBaseObjectRef)dec);
  free(dec);

  expect("a decoder for the start and invalidate test",
         !CREATE(CODEC, NULL, &dec) && dec);
  int c0 = creates;
  d0 = destroys;
  invalidateInCreate = dec;
  OSStatus ri = dec_start_session(dec, NULL, fmt);
  invalidateInCreate = NULL;
  expect("a start that invalidate overtakes closes its new session",
         ri == kVTInvalidSessionErr && creates == c0 + 1 &&
             destroys == d0 + 1 && !dec_can_accept_format(dec, fmt));
  base_finalize((CMBaseObjectRef)dec);
  free(dec);

  // 13. The queue is full of slow frames, a decode waits for a slot, and
  // another thread invalidates. The decode is held after it gets its slot:
  // invalidate must not return (and the host must not be able to free the
  // decoder) while that decode is still inside the plug-in.
  expect("a decoder for the invalidate during a decode test",
         !CREATE(CODEC, NULL, &dec) && dec);
  expect("its session starts too", !dec_start_session(dec, NULL, fmt));
  slowEntered = dispatch_semaphore_create(0);
  slowRelease = dispatch_semaphore_create(0);
  slowTimedOut = false;
  slotTaken = dispatch_semaphore_create(0);
  slotHold = dispatch_semaphore_create(0);
  invalidateDone = dispatch_semaphore_create(0);
  CMSampleBufferRef slow13 = sample(5);
  waitingSample = shown;
  e = emits;
  for (int i = 0; i < MAX_QUEUED; i++)
    dec_decode_frame(dec, NULL, slow13,
                     kVTDecodeFrame_EnableAsynchronousDecompression, NULL);
  bool decoding = !dispatch_semaphore_wait(
      slowEntered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
  int w0 = __atomic_load_n(&waitsStarted, __ATOMIC_SEQ_CST);
  afterWait = hold_after_slot;
  pthread_t ta, tb;
  pthread_create(&ta, NULL, waiting_decode, NULL);
  // Until the decode is in its wait for a slot (at most 2 s).
  for (int i = 0;
       i < 2000 && __atomic_load_n(&waitsStarted, __ATOMIC_SEQ_CST) == w0; i++)
    usleep(1000);
  bool waiting = __atomic_load_n(&waitsStarted, __ATOMIC_SEQ_CST) > w0 &&
                 !__atomic_load_n(&decodeLeft, __ATOMIC_SEQ_CST);
  pthread_create(&tb, NULL, invalidating, NULL);
  // Until invalidate has begun (at most 300 ms): the format is not accepted
  // from then on.
  for (int i = 0; i < 300 && dec_can_accept_format(dec, fmt); i++) usleep(1000);
  for (int i = 0; i < MAX_QUEUED; i++) dispatch_semaphore_signal(slowRelease);
  bool tookSlot = !dispatch_semaphore_wait(
      slotTaken, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
  // The decode is held now. An invalidate that does not wait for it is done
  // within this second.
  bool invalidateFirst = !dispatch_semaphore_wait(
      invalidateDone, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC));
  dispatch_semaphore_signal(slotHold);
  pthread_join(ta, NULL);
  pthread_join(tb, NULL);
  expect("test 13 set-up: the queue is full and a decode waits for a slot",
         decoding && waiting && tookSlot && !slowTimedOut);
  expect("invalidate waits for a decode still on its way into the queue",
         !invalidateFirst && decodeLeft && invalidateLeft &&
             decodeLeft < invalidateLeft);
  expect(
      "that decode is refused, and only the frames queued before are "
      "emitted",
      waitingResult == kVTInvalidSessionErr && emits == e + MAX_QUEUED);
  base_finalize((CMBaseObjectRef)dec);
  free(dec);
  CFRelease(slow13);

  // 14. A slow frame decodes, two more wait behind it and a synchronous decode
  // on another thread waits for the queue. The slow frame's callback lets go
  // of the decoder.
  expect("a decoder for the finalize from the callback test",
         !CREATE(CODEC, NULL, &dec) && dec);
  expect("its session starts as well", !dec_start_session(dec, NULL, fmt));
  slowEntered = dispatch_semaphore_create(0);
  slowRelease = dispatch_semaphore_create(0);
  slowTimedOut = false;
  CMSampleBufferRef slow14 = sample(5), behind[2] = {sample(1), sample(1)};
  syncSample = sample(1);
  e = emits;
  c0 = creates;
  d0 = destroys;
  dec_decode_frame(dec, NULL, slow14,
                   kVTDecodeFrame_EnableAsynchronousDecompression, NULL);
  bool busy = !dispatch_semaphore_wait(
      slowEntered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
  for (int i = 0; i < 2; i++)
    dec_decode_frame(dec, NULL, behind[i],
                     kVTDecodeFrame_EnableAsynchronousDecompression, NULL);
  int s0 = __atomic_load_n(&syncsStarted, __ATOMIC_SEQ_CST);
  pthread_t tc;
  pthread_create(&tc, NULL, sync_decode, dec);
  // Until the decode is on its way into dispatch_sync (at most 2 s), and a
  // little longer for it to be waiting there.
  for (int i = 0;
       i < 2000 && __atomic_load_n(&syncsStarted, __ATOMIC_SEQ_CST) == s0; i++)
    usleep(1000);
  usleep(50000);
  bool syncWaiting = __atomic_load_n(&syncsStarted, __ATOMIC_SEQ_CST) > s0 &&
                     !__atomic_load_n(&syncLeft, __ATOMIC_SEQ_CST);
  inCallback = finalize_in_callback;
  dispatch_semaphore_signal(slowRelease);
  pthread_join(tc, NULL);
  // Until every frame queued has let go of its sample (at most 5 s).
  CMSampleBufferRef held[] = {slow14, behind[0], behind[1], syncSample};
  bool released = false;
  for (int i = 0; i < 5000 && !released; i++) {
    released = true;
    for (int j = 0; j < 4; j++)
      if (CFGetRetainCount(held[j]) != 1) released = false;
    if (!released) usleep(1000);
  }
  usleep(100000);  // the last frame's block lets go of the state after that
  expect(
      "test 14 set-up: a frame decodes, two wait, a synchronous decode "
      "waits for the queue, and the callback finalizes",
      busy && syncWaiting && finalizedInCallback && !slowTimedOut);
  expect(
      "after finalize from the callback the frames still queued emit "
      "nothing, and let go of their samples",
      emits == e + 1 && released && syncLeft);
  expect("the session ends once, and not while a frame decodes",
         creates == c0 && destroys == d0 + 1 && !destroyedWhileDecoding);
  for (int j = 0; j < 4; j++) CFRelease(held[j]);

  // 15. A decode has found no invalidate begun and is held before it queues
  // its frame; another thread invalidates. The decode is still counted as a
  // call, so invalidate waits for it, and drains the frame it then queues.
  expect("a decoder for the invalidate before a frame is queued test",
         !CREATE(CODEC, NULL, &dec) && dec);
  expect("its session starts, again", !dec_start_session(dec, NULL, fmt));
  retainHeld = dispatch_semaphore_create(0);
  retainHold = dispatch_semaphore_create(0);
  invalidateDone = dispatch_semaphore_create(0);
  order = decodeLeft = invalidateLeft = 0;
  waitingResult = -1;
  waitingSample = shown;
  e = emits;
  pthread_create(&ta, NULL, held_decode, NULL);
  bool heldBeforeQueue = !dispatch_semaphore_wait(
      retainHeld, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
  pthread_create(&tb, NULL, invalidating, NULL);
  // Until invalidate has begun (at most 300 ms).
  for (int i = 0; i < 300 && dec_can_accept_format(dec, fmt); i++) usleep(1000);
  // An invalidate that does not wait for the decode is done within a second.
  bool invalidateEarly = !dispatch_semaphore_wait(
      invalidateDone, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC));
  dispatch_semaphore_signal(retainHold);
  pthread_join(ta, NULL);
  pthread_join(tb, NULL);
  expect("test 15 set-up: a decode is held after its check, before it queues",
         heldBeforeQueue);
  expect("invalidate waits for a decode that passed its check",
         !invalidateEarly && decodeLeft && invalidateLeft &&
             decodeLeft < invalidateLeft);
  expect("and the frame that decode queued is emitted",
         waitingResult == noErr && emits == e + 1 && !lastStatus);
  base_finalize((CMBaseObjectRef)dec);
  free(dec);

#if defined(TEST_AV1)
  // av1C: marker/version, profile 0 level 0, 8-bit 4:2:0, then one config byte.
  static const uint8_t av1C[] = {0x81, 0x00, 0x0c, 0x00, 0x0a};
  CMVideoFormatDescriptionRef withCfg = format(CODEC, av1C, sizeof(av1C));
  expect("a decoder for the av1C test", !CREATE(CODEC, NULL, &dec) && dec);
  configureResult = VCNAV1_UNSUPPORTED;
  int d = destroys;
  expect("an unsupported sequence header in av1C refuses the session",
         dec_start_session(dec, NULL, withCfg) ==
                 kVTVideoDecoderUnsupportedDataFormatErr &&
             destroys == d + 1);
  configureResult = -1;
  expect("unreadable configOBUs are logged, the session still starts",
         !dec_start_session(dec, NULL, withCfg));
  base_invalidate((CMBaseObjectRef)dec);
  base_finalize((CMBaseObjectRef)dec);
  free(dec);
  CFRelease(withCfg);
#endif

  // Every session is finalized by now: a plug-in that keeps a reference to a
  // picture it emitted (or never releases the last one) leaves the count
  // above 1.
  expect("every picture the plug-in took is released",
         CFGetRetainCount(picture) == 1);
  CFRelease(shown);
  CFRelease(hidden);
  CFRelease(broken);
  CFRelease(fmt);
  CVPixelBufferRelease(picture);
  return failures ? 1 : 0;
}
