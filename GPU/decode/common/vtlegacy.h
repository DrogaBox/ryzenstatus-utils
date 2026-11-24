// The VideoToolbox side of the MPEG-2, VC-1 and MPEG-4 decoder plug-ins
// (macOS x86_64): one implementation, included once by each plug-in's source
// file (mpeg2/MPEG2VCNDecoder.c, vc1/VC1VCNDecoder.c, mpeg4/MPEG4VCNDecoder.c).
// Same ABI and threading as vp9/VP9VCNDecoder.c and av1/AV1VCNDecoder.c, which
// documents where the private plugin interface comes from.
//
// Before including it, the plug-in defines:
//   LEGACY_FACTORY  the exported factory function's name
//   LEGACY_CODEC    its codec layer (const VcnLegacyCodec*)
//   LEGACY_LOG      its os_log subsystem, a string literal
//   LEGACY_NAME     the codec's name for the log, a string literal
// and two functions:
//   static bool legacy_accepts(FourCharCode codec);
//   // The headers the container keeps outside the samples, as the codec
//   // layer's create() takes them, or NULL when there are none.
//   static CFDataRef legacy_copy_config(CMFormatDescriptionRef fmt);
#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <VideoToolbox/VideoToolbox.h>
#include <mach/mach_time.h>
#include <os/log.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "vcnlegacy.h"

// ---- private CoreMedia / VideoToolbox plugin SPI
// -------------------------------------------
typedef const void* CMBaseClassID;
typedef struct OpaqueCMBaseObject* CMBaseObjectRef;
typedef struct OpaqueVTVideoDecoder* VTVideoDecoderRef;
typedef struct OpaqueVTVideoDecoderSession* VTVideoDecoderSession;
typedef struct OpaqueVTVideoDecoderFrame* VTVideoDecoderFrame;

#pragma pack(push, 4)
typedef struct {
  uint32_t version;
  size_t derivedStorageSize;
  Boolean (*equal)(CMBaseObjectRef, CMBaseObjectRef);
  OSStatus (*invalidate)(CMBaseObjectRef);
  void (*finalize)(CMBaseObjectRef);
  CFStringRef (*copyDebugDescription)(CMBaseObjectRef);
  OSStatus (*copyProperty)(CMBaseObjectRef, CFStringRef, CFAllocatorRef, void*);
  OSStatus (*setProperty)(CMBaseObjectRef, CFStringRef, CFTypeRef);
  OSStatus (*notificationBarrier)(CMBaseObjectRef);
  const void* propertyHandlers;
} CMBaseClass;

typedef struct {
  uint32_t version;
  OSStatus (*startSession)(VTVideoDecoderRef, VTVideoDecoderSession,
                           CMVideoFormatDescriptionRef);
  OSStatus (*decodeFrame)(VTVideoDecoderRef, VTVideoDecoderFrame,
                          CMSampleBufferRef, VTDecodeFrameFlags,
                          VTDecodeInfoFlags*);
  OSStatus (*copySupportedPropertyDictionary)(VTVideoDecoderRef,
                                              CFDictionaryRef*);
  OSStatus (*setProperties)(VTVideoDecoderRef, CFDictionaryRef);
  OSStatus (*copySerializableProperties)(VTVideoDecoderRef, CFAllocatorRef,
                                         CFDictionaryRef*);
  Boolean (*canAcceptFormatDescription)(VTVideoDecoderRef,
                                        CMFormatDescriptionRef);
  OSStatus (*finishDelayedFrames)(VTVideoDecoderRef);
  void* reserved[6];
} VTVideoDecoderClass;
#pragma pack(pop)

typedef struct {
  void* reserved;
  const CMBaseClass* baseClass;
  const VTVideoDecoderClass* decoderClass;
} VTVideoDecoderVTable;

extern OSStatus CMDerivedObjectCreate(CFAllocatorRef, const void* vtable,
                                      CMBaseClassID, CMBaseObjectRef*);
extern void* CMBaseObjectGetDerivedStorage(CMBaseObjectRef);
extern CMBaseClassID VTVideoDecoderGetClassID(void);
extern CMBaseObjectRef VTVideoDecoderGetCMBaseObject(VTVideoDecoderRef);
extern OSStatus VTDecoderSessionSetPixelBufferAttributes(VTVideoDecoderSession,
                                                         CFDictionaryRef);
extern OSStatus VTDecoderSessionEmitDecodedFrame(VTVideoDecoderSession,
                                                 VTVideoDecoderFrame, OSStatus,
                                                 VTDecodeInfoFlags,
                                                 CVImageBufferRef);

// ---- decoder instance
// ----------------------------------------------------------------------
// What the decode queue and the calls still inside the plug-in use. It lives
// apart from the CoreMedia storage, which CoreMedia frees as soon as finalize
// returns, and it is counted: the storage holds one reference, each queued
// frame one and each call in the plug-in one, and the last to let go frees
// it. finalize can run on the decode queue (a host that lets go of its session
// from inside its output callback), where it may wait for nothing: the frames
// still queued and a call waiting for the queue then find the state alive,
// closed, and emit nothing.
typedef struct {
  VTVideoDecoderSession session;
  void* dec;  // the codec layer's session (LEGACY_CODEC)
  int32_t width, height;
  // Set by invalidate once the queue is drained, and by finalize: nothing is
  // emitted any more.
  bool invalidated;
  CVPixelBufferRef
      lastFrame;  // retained shown frame of the chunk being decoded
  pthread_mutex_t lock;
  // What canAcceptFormatDescription reads, under meta. A decode holds lock
  // for as long as the GPU takes; meta is never held across a driver call.
  pthread_mutex_t meta;
  CMVideoFormatDescriptionRef format;  // of the running session; NULL: none
  bool broken;  // the session failed as a device: it decodes nothing more
  // Also under meta. closing: invalidate or finalize has begun, frames are
  // refused. callers: decodeFrame calls from outside the decode queue that
  // are still in the plug-in (waiting for a slot, queuing, or decoding at
  // once); idle is signalled when the count drops to 0.
  bool closing;
  int callers;
  pthread_cond_t idle;
  dispatch_queue_t
      queue;  // serial: frames are decoded (and emitted) in submission order
  dispatch_semaphore_t slots;  // bounds frames queued but not yet decoded
  // stats, logged every STATS_EVERY frames: decode = time in the codec, queue
  // = enqueue -> start
  int st_n, st_over, st_depth_max, depth;
  double st_dec_sum, st_dec_max, st_q_sum, st_q_max, st_t0;
  // frame time of the stream (ms, 0 until known) and the last sample's time
  double st_frame_ms, st_frame_sum;
  CMTime st_last_pts;
  int refs;  // see above; changed with atomics only
} State;

// The CoreMedia storage of the decoder object.
typedef struct {
  State* state;  // NULL once finalized
} Storage;

#define STATS_EVERY 120

// Frames that may wait in the queue. The VCN runs one command at a time, the
// queue only lets the caller keep feeding samples while the previous one
// decodes.
#define MAX_QUEUED 4

// What the Linux driver allows these codecs on the same hardware.
#define MAX_WIDTH VCNLEGACY_MAX_WIDTH
#define MAX_HEIGHT VCNLEGACY_MAX_HEIGHT

static os_log_t logger(void) {
  static os_log_t l;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    l = os_log_create(LEGACY_LOG, "decoder");
  });
  return l;
}

// Driver sessions of this plug-in in this process, for the log: a host that
// keeps creating sessions without ending them shows up as a growing "live".
static long g_started, g_ended, g_live;

// Sets the format canAcceptFormatDescription compares with (NULL: none), for
// a session that starts or ends. Either way the session is not broken.
static void set_format(State* s, CMVideoFormatDescriptionRef fmt) {
  pthread_mutex_lock(&s->meta);
  CMVideoFormatDescriptionRef old = s->format;
  s->format = fmt ? (CMVideoFormatDescriptionRef)CFRetain(fmt) : NULL;
  s->broken = false;
  pthread_mutex_unlock(&s->meta);
  if (old) CFRelease(old);
}

// Ends the decoder session, if there is one, and logs it with the counts. The
// caller holds s->lock or is the only one left using s.
static void end_session(State* s, const char* why) {
  set_format(s, NULL);
  if (!s->dec) return;
  LEGACY_CODEC->destroy(s->dec);
  s->dec = NULL;
  long ended = __atomic_add_fetch(&g_ended, 1, __ATOMIC_RELAXED),
       live = __atomic_sub_fetch(&g_live, 1, __ATOMIC_RELAXED),
       started = __atomic_load_n(&g_started, __ATOMIC_RELAXED);
  os_log_info(logger(),
              "session %dx%d ended (%{public}s): %ld started, %ld ended, %ld "
              "live in this process",
              s->width, s->height, why, started, ended, live);
}

static State* state_retain(State* s) {
  __atomic_add_fetch(&s->refs, 1, __ATOMIC_RELAXED);
  return s;
}
// The last one frees the state. Nothing is queued and no call is inside the
// plug-in by then: no lock is held, nobody waits on the semaphore and every
// slot has been given back.
static void state_release(State* s) {
  if (__atomic_sub_fetch(&s->refs, 1, __ATOMIC_ACQ_REL)) return;
  end_session(s, "finalized");  // finalize ended it already: only the format
  if (s->lastFrame) CVPixelBufferRelease(s->lastFrame);
  if (s->queue) dispatch_release(s->queue);
  if (s->slots) dispatch_release(s->slots);
  pthread_mutex_destroy(&s->lock);
  pthread_mutex_destroy(&s->meta);
  pthread_cond_destroy(&s->idle);
  free(s);
}

// The state of a decoder, without a reference: for calls that wait for
// nothing.
static State* state_of(VTVideoDecoderRef dec) {
  Storage* st =
      CMBaseObjectGetDerivedStorage(VTVideoDecoderGetCMBaseObject(dec));
  return __atomic_load_n(&st->state, __ATOMIC_ACQUIRE);
}
// The same with a reference, for a call that may wait for the decode queue:
// it keeps the state alive until the call lets go, also if the decoder is
// finalized meanwhile. NULL after finalize.
static State* state_enter(VTVideoDecoderRef dec) {
  State* s = state_of(dec);
  return s ? state_retain(s) : NULL;
}

// Marks the decode queue. The output callback runs on it, and a call made from
// inside the callback must not wait for the queue, which is busy running it.
static char kQueueKey;
static bool on_queue(State* s) {
  return dispatch_get_specific(&kQueueKey) == s;
}
// Waits until every queued frame has been emitted, also those queued from
// inside the callback while it waited. From inside the callback the frames
// queued after the running one cannot be waited for.
static void drain(State* s) {
  if (!s->queue || on_queue(s)) return;
  do
    dispatch_sync(s->queue, ^{
                  });
  while (__atomic_load_n(&s->depth, __ATOMIC_RELAXED) > 0);
}

// A decodeFrame call from outside the decode queue counts itself in callers
// for as long as it runs. Returns false, counting nothing, once invalidate or
// finalize has begun.
static bool enter_call(State* s, bool counted) {
  pthread_mutex_lock(&s->meta);
  bool open = !s->closing;
  if (open && counted) s->callers++;
  pthread_mutex_unlock(&s->meta);
  return open;
}
static void leave_call(State* s) {
  pthread_mutex_lock(&s->meta);
  if (--s->callers == 0) pthread_cond_broadcast(&s->idle);
  pthread_mutex_unlock(&s->meta);
}
static bool is_closing(State* s) {
  pthread_mutex_lock(&s->meta);
  bool closing = s->closing;
  pthread_mutex_unlock(&s->meta);
  return closing;
}
// Refuses frames from now on and waits for the decodeFrame calls still on
// their way in: drain() only sees frames already queued, and a call that
// waits for a slot has not queued its frame yet. From the decode queue (the
// output callback) nothing is waited for: a call waiting for a slot may be
// waiting for the frame whose callback this is. Such a call refuses its frame
// once it gets the slot. Its own reference keeps the state until it has
// left, as each queued frame's own does until the frame has run, also when
// finalize runs on the queue.
static void close_calls(State* s) {
  pthread_mutex_lock(&s->meta);
  s->closing = true;
  if (!on_queue(s))
    while (s->callers > 0) pthread_cond_wait(&s->idle, &s->meta);
  pthread_mutex_unlock(&s->meta);
}

// ---- CMBaseClass
// ---------------------------------------------------------------------------
static OSStatus base_invalidate(CMBaseObjectRef obj) {
  Storage* st = CMBaseObjectGetDerivedStorage(obj);
  State* s = __atomic_load_n(&st->state, __ATOMIC_ACQUIRE);
  if (!s) return noErr;
  state_retain(s);
  // Frames handed in from now on are refused; the ones already queued are
  // still emitted.
  close_calls(s);
  drain(s);
  pthread_mutex_lock(&s->lock);
  // None is emitted any more.
  __atomic_store_n(&s->invalidated, true, __ATOMIC_RELAXED);
  end_session(s, "invalidated");
  pthread_mutex_unlock(&s->lock);
  state_release(s);
  return noErr;
}

// Off the decode queue this waits, as invalidate does, for the calls still on
// their way in and for every queued frame. On the queue (the host let go of
// the decoder from inside its output callback) it waits for neither: the
// frames queued behind the running one and a call waiting for the queue on
// another thread still hold the state, run after this returns and emit
// nothing. Either way the session ends here, once, under lock: a decode holds
// lock for as long as the GPU works on its frame, and on the queue the frame
// whose callback this is has finished with the GPU before it emits.
static void base_finalize(CMBaseObjectRef obj) {
  Storage* st = CMBaseObjectGetDerivedStorage(obj);
  State* s = __atomic_exchange_n(&st->state, NULL, __ATOMIC_ACQ_REL);
  if (!s) return;
  close_calls(s);
  drain(s);
  pthread_mutex_lock(&s->lock);
  __atomic_store_n(&s->invalidated, true, __ATOMIC_RELAXED);
  end_session(s, "finalized");  // releases the format too
  pthread_mutex_unlock(&s->lock);
  state_release(s);  // the storage's reference: the last one frees the state
}

static CFStringRef base_copy_debug_description(CMBaseObjectRef obj) {
  return CFStringCreateWithFormat(
      NULL, NULL, CFSTR("<" LEGACY_NAME " VCN Decoder %p>"), obj);
}

static OSStatus base_copy_property(CMBaseObjectRef obj, CFStringRef key,
                                   CFAllocatorRef alloc, void* out) {
  if (!key || !out) return kVTParameterErr;
  if (CFEqual(
          key,
          kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder)) {
    *(CFTypeRef*)out = CFRetain(kCFBooleanTrue);
    return noErr;
  }
  return kVTPropertyNotSupportedErr;
}

static OSStatus base_set_property(CMBaseObjectRef obj, CFStringRef key,
                                  CFTypeRef value) {
  return kVTPropertyNotSupportedErr;
}

// ---- VTVideoDecoderClass
// -------------------------------------------------------------------
static OSStatus start_session(State* s, VTVideoDecoderSession session,
                              CMVideoFormatDescriptionRef fmt) {
  if (!fmt) return kVTParameterErr;
  CMVideoDimensions dim = CMVideoFormatDescriptionGetDimensions(fmt);
  if (dim.width <= 0 || dim.height <= 0)
    return kVTVideoDecoderUnsupportedDataFormatErr;
  // A second start replaces the decoder of the first one. Ending it drops its
  // format too: a start that fails must leave none that
  // canAcceptFormatDescription could match.
  drain(s);
  pthread_mutex_lock(&s->lock);
  end_session(s, "replaced by a new start");
  s->session = session;
  pthread_mutex_unlock(&s->lock);
  int32_t width = dim.width, height = dim.height;
  if (!legacy_accepts(CMFormatDescriptionGetMediaSubType(fmt)) ||
      width > MAX_WIDTH || height > MAX_HEIGHT)
    return kVTVideoDecoderUnsupportedDataFormatErr;

  char err[256] = "";
  // The driver session itself is made at the first picture, which says the
  // coded size; what can be known now is whether one can be made here.
  if (!vcnlegacy_available(err, sizeof(err))) {
    os_log_error(logger(), "not available: %{public}s", err);
    return kVTVideoDecoderNotAvailableNowErr;
  }
  __atomic_store_n(&vcnlegacy_gpu_armed, 1, __ATOMIC_RELAXED);
  CFDataRef config = legacy_copy_config(fmt);
  void* dec =
      LEGACY_CODEC->create(config ? CFDataGetBytePtr(config) : NULL,
                           config ? (size_t)CFDataGetLength(config) : 0,
                           (uint32_t)width, (uint32_t)height, err, sizeof(err));
  if (config) CFRelease(config);
  if (!dec) {
    // Headers the codec layer does not take: the stream is refused, and
    // VideoToolbox goes on to another decoder.
    os_log_error(logger(), "session not started: %{public}s", err);
    return kVTVideoDecoderUnsupportedDataFormatErr;
  }
  // The new session is set up before anything else can see it: until it is
  // published below, neither invalidate nor a decode can reach it.
  CFDictionaryRef attrs =
      vcnlegacy_copy_pixel_buffer_attributes((uint32_t)width, (uint32_t)height);
  if (!attrs) {  // out of memory: no session rather than one with no attributes
    LEGACY_CODEC->destroy(dec);
    return kVTAllocationFailedErr;
  }
  VTDecoderSessionSetPixelBufferAttributes(session, attrs);
  CFRelease(attrs);
  pthread_mutex_lock(&s->lock);
  if (__atomic_load_n(&s->invalidated, __ATOMIC_RELAXED)) {
    // Invalidated while the session was being made: nothing may stay open.
    pthread_mutex_unlock(&s->lock);
    LEGACY_CODEC->destroy(dec);
    return kVTInvalidSessionErr;
  }
  end_session(s, "replaced by a new start");  // a start that ran alongside
  s->dec = dec;
  s->st_frame_ms = 0;  // a new stream: learn its frame time again
  s->st_last_pts = kCMTimeInvalid;
  s->width = width;
  s->height = height;
  long started = __atomic_add_fetch(&g_started, 1, __ATOMIC_RELAXED),
       live = __atomic_add_fetch(&g_live, 1, __ATOMIC_RELAXED),
       ended = __atomic_load_n(&g_ended, __ATOMIC_RELAXED);
  set_format(s, fmt);
  pthread_mutex_unlock(&s->lock);
  os_log(logger(),
         "session %dx%d: %ld started, %ld ended, %ld live in this process",
         width, height, started, ended, live);
  return noErr;
}
static OSStatus dec_start_session(VTVideoDecoderRef dec,
                                  VTVideoDecoderSession session,
                                  CMVideoFormatDescriptionRef fmt) {
  State* s = state_enter(dec);  // it waits for the queue
  if (!s) return kVTInvalidSessionErr;
  OSStatus r = start_session(s, session, fmt);
  state_release(s);
  return r;
}

static int on_output(void* ctx, CVPixelBufferRef frame, int use, uint32_t w,
                     uint32_t h) {
  (void)use, (void)w, (void)h;
  State* s = ctx;
  // A sample is one frame; keep the last one if a stream packs more.
  if (s->lastFrame) CVPixelBufferRelease(s->lastFrame);
  s->lastFrame = CVPixelBufferRetain(frame);
  return 0;
}

static double now_ms(void) {
  static mach_timebase_info_data_t tb;
  if (!tb.denom) mach_timebase_info(&tb);
  return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

// The stream's frame time: the sample's duration, or the step from the
// previous sample's presentation time when the caller gives none. The last good
// value is kept for samples with no timing; 60 fps is assumed until one is
// known. It is the stream's time, so at 2x playback each frame really has half
// of it.
static double frame_ms(State* s, CMSampleBufferRef sbuf) {
  if (!sbuf) return s->st_frame_ms > 0 ? s->st_frame_ms : 1000.0 / 60;
  CMTime d = CMSampleBufferGetDuration(sbuf);
  CMTime pts = CMSampleBufferGetPresentationTimeStamp(sbuf);
  double ms = 0;
  if (CMTIME_IS_NUMERIC(d) && d.value > 0) {
    ms = CMTimeGetSeconds(d) * 1000;
  } else if (CMTIME_IS_NUMERIC(pts) && CMTIME_IS_NUMERIC(s->st_last_pts)) {
    // A step longer than 100 ms is a seek, not a frame.
    ms = CMTimeGetSeconds(CMTimeSubtract(pts, s->st_last_pts)) * 1000;
    if (ms > 100) ms = 0;
  }
  if (CMTIME_IS_NUMERIC(pts)) s->st_last_pts = pts;
  if (ms >= 1 && ms <= 1000) s->st_frame_ms = ms;
  return s->st_frame_ms > 0 ? s->st_frame_ms : 1000.0 / 60;
}

// A frame counts as slow when its decode alone took longer than the stream's
// frame time. Time in the queue is not counted: frames wait there by design,
// up to the queue depth, while the one ahead decodes.
static void stats_add(State* s, double queued, double decode, double frame) {
  if (!s->st_n) s->st_t0 = now_ms();
  s->st_n++;
  s->st_dec_sum += decode;
  if (decode > s->st_dec_max) s->st_dec_max = decode;
  s->st_q_sum += queued;
  if (queued > s->st_q_max) s->st_q_max = queued;
  s->st_frame_sum += frame;
  if (decode > frame) s->st_over++;
  if (s->st_n >= STATS_EVERY) {
    os_log(logger(),
           "stats %dx%d: %d frames in %.0f ms, decode avg %.2f max %.2f ms, "
           "queue avg %.2f max %.2f ms, "
           "decode over frame time (avg %.1f ms) %d, max depth %d, "
           "firmware errors %u",
           s->width, s->height, s->st_n, now_ms() - s->st_t0,
           s->st_dec_sum / s->st_n, s->st_dec_max, s->st_q_sum / s->st_n,
           s->st_q_max, s->st_frame_sum / s->st_n, s->st_over, s->st_depth_max,
           LEGACY_CODEC->firmware_errors(s->dec));
    s->st_n = s->st_over = s->st_depth_max = 0;
    s->st_dec_sum = s->st_dec_max = s->st_q_sum = s->st_q_max = 0;
    s->st_frame_sum = 0;
  }
}

// A sample larger than one bitstream buffer of the driver pool (BS_SIZE in
// the session code) cannot be decoded: refuse it before copying anything.
enum { kMaxSampleBytes = 0x1800000 };

// What VideoToolbox is told when a sample fails. A broken session (a driver
// call failed, or the GPU did not finish a command) is a malfunction, so that
// the host can fall back to another decoder; bad data is kept for streams
// that cannot be decoded as they are.
static OSStatus decode_status(int failure) {
  switch (failure) {
    case VCNLEGACY_FAIL_DEVICE:
      return kVTVideoDecoderMalfunctionErr;
    case VCNLEGACY_FAIL_MEMORY:
      return kVTAllocationFailedErr;
    // VideoToolbox's own code for it: FFmpeg goes on with the next frame on
    // this one, and makes a new session on any other error.
    case VCNLEGACY_FAIL_REFERENCE:
      return kVTVideoDecoderReferenceMissingErr;
    default:
      return kVTVideoDecoderBadDataErr;
  }
}

// Decode one sample and hand its frame to VideoToolbox. A sample that gives
// no frame (the first field of a frame whose second field comes in the next
// sample) is dropped without an error.
static void decode_and_emit(State* s, VTVideoDecoderFrame frame,
                            CMSampleBufferRef sbuf, double enqueued) {
  double started = now_ms();
  CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sbuf);
  size_t len = bb ? CMBlockBufferGetDataLength(bb) : 0;
  OSStatus status = noErr;
  uint8_t* copy = NULL;
  char* ptr = NULL;
  if (!len || len > kMaxSampleBytes)
    status = kVTVideoDecoderBadDataErr;
  else if (CMBlockBufferIsRangeContiguous(bb, 0, len) &&
           !CMBlockBufferGetDataPointer(bb, 0, NULL, NULL, &ptr) && ptr) {
  } else {
    copy = malloc(len);
    if (!copy)
      status = kVTAllocationFailedErr;
    else if (CMBlockBufferCopyDataBytes(bb, 0, len, copy))
      status = kVTVideoDecoderBadDataErr;
    ptr = (char*)copy;
  }
  pthread_mutex_lock(&s->lock);
  int depth = __atomic_load_n(&s->depth, __ATOMIC_RELAXED);
  if (depth > s->st_depth_max) s->st_depth_max = depth;
  bool invalidated = s->invalidated;
  if (!status && !s->dec) status = kVTInvalidSessionErr;
  if (!status &&
      LEGACY_CODEC->decode(s->dec, (const uint8_t*)ptr, len, on_output, s)) {
    os_log_error(logger(), "decode: %{public}s",
                 LEGACY_CODEC->last_error(s->dec));
    int failure = LEGACY_CODEC->failure(s->dec);
    status = decode_status(failure);
    // The session takes no more frames: canAcceptFormatDescription says no
    // from now on, so VideoToolbox makes a new decoder.
    if (failure == VCNLEGACY_FAIL_DEVICE) {
      pthread_mutex_lock(&s->meta);
      s->broken = true;
      pthread_mutex_unlock(&s->meta);
    }
  }
  CVPixelBufferRef out = s->lastFrame;
  s->lastFrame = NULL;
  bool shown = out != NULL;
  double decode = now_ms() - started;
  // A sample that gave no frame is measured against the known frame time and
  // does not change it.
  stats_add(s, started - enqueued, decode, frame_ms(s, shown ? sbuf : NULL));
  pthread_mutex_unlock(&s->lock);
  free(copy);
  // A sample that failed hands back no picture, even one it showed before.
  if (status && out) {
    CVPixelBufferRelease(out);
    out = NULL;
  }
  if (!invalidated)
    VTDecoderSessionEmitDecodedFrame(s->session, frame, status,
                                     out ? 0 : kVTDecodeInfo_FrameDropped, out);
  if (out) CVPixelBufferRelease(out);
}

// The caller holds a reference to s for as long as this runs.
static OSStatus decode_frame(State* s, VTVideoDecoderFrame frame,
                             CMSampleBufferRef sbuf, VTDecodeFrameFlags flags,
                             VTDecodeInfoFlags* infoOut) {
  if (!sbuf) return kVTParameterErr;
  // From inside the output callback the queue is already running this code,
  // and invalidate run from there waits for no call (see close_calls).
  bool counted = !on_queue(s);
  if (!enter_call(s, counted)) return kVTInvalidSessionErr;
  if (!(flags & kVTDecodeFrame_EnableAsynchronousDecompression)) {
    double t = now_ms();
    if (!counted)
      decode_and_emit(s, frame, sbuf, t);
    else
      dispatch_sync(s->queue, ^{
        decode_and_emit(s, frame, sbuf, t);
      });  // keeps order with queued work
    if (counted) leave_call(s);
    return noErr;
  }
  // From inside the output callback the running frame still holds its slot,
  // so waiting for one could wait for ever: queue the frame without one.
  if (counted) {
    dispatch_semaphore_wait(s->slots, DISPATCH_TIME_FOREVER);
    // An invalidate that began during the wait refuses the frame.
    if (is_closing(s)) {
      dispatch_semaphore_signal(s->slots);
      leave_call(s);
      return kVTInvalidSessionErr;
    }
  }
  CFRetain(sbuf);
  double t = now_ms();
  __atomic_add_fetch(&s->depth, 1, __ATOMIC_RELAXED);
  state_retain(s);  // the frame's own reference, let go of last
  dispatch_async(s->queue, ^{
    decode_and_emit(s, frame, sbuf, t);
    __atomic_sub_fetch(&s->depth, 1, __ATOMIC_RELAXED);
    CFRelease(sbuf);
    if (counted) dispatch_semaphore_signal(s->slots);
    state_release(s);
  });
  if (infoOut) *infoOut = kVTDecodeInfo_Asynchronous;
  // Queued and counted in depth: from here on drain() waits for the frame.
  // Until then the call is counted in callers, so an invalidate or finalize
  // off the queue, which waits for callers before it drains, cannot miss it.
  // On the queue they wait for no frame queued behind the running one.
  if (counted) leave_call(s);
  return noErr;
}
static OSStatus dec_decode_frame(VTVideoDecoderRef dec,
                                 VTVideoDecoderFrame frame,
                                 CMSampleBufferRef sbuf,
                                 VTDecodeFrameFlags flags,
                                 VTDecodeInfoFlags* infoOut) {
  if (infoOut) *infoOut = 0;
  State* s = state_enter(dec);
  if (!s) return kVTInvalidSessionErr;
  OSStatus r = decode_frame(s, frame, sbuf, flags, infoOut);
  state_release(s);
  return r;
}

static OSStatus dec_copy_supported_properties(VTVideoDecoderRef dec,
                                              CFDictionaryRef* out) {
  if (!out) return kVTParameterErr;
  *out = NULL;
  const void* k[] = {kVTPropertyTypeKey, kVTPropertyReadWriteStatusKey};
  const void* v[] = {kVTPropertyType_Boolean,
                     kVTPropertyReadWriteStatus_ReadOnly};
  CFDictionaryRef hw =
      CFDictionaryCreate(NULL, k, v, 2, &kCFTypeDictionaryKeyCallBacks,
                         &kCFTypeDictionaryValueCallBacks);
  if (!hw) return kVTAllocationFailedErr;
  const void* keys[] = {
      kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder};
  const void* vals[] = {hw};
  *out = CFDictionaryCreate(NULL, keys, vals, 1, &kCFTypeDictionaryKeyCallBacks,
                            &kCFTypeDictionaryValueCallBacks);
  CFRelease(hw);
  return *out ? noErr : kVTAllocationFailedErr;
}

// A new size or configuration gets a new session. Size changes inside the
// stream don't come through here, the format description stays the same for
// those.
static Boolean dec_can_accept_format(VTVideoDecoderRef dec,
                                     CMFormatDescriptionRef fmt) {
  State* s = state_of(dec);
  if (!s || !fmt) return false;
  // A decoder whose start failed, whose session broke or whose invalidate has
  // begun takes no format: VideoToolbox must make a new one. Read under meta,
  // not lock: a decode holds lock while the GPU works on its frame.
  pthread_mutex_lock(&s->meta);
  CMFormatDescriptionRef cur =
      s->format && !s->broken && !s->closing ? CFRetain(s->format) : NULL;
  pthread_mutex_unlock(&s->meta);
  if (!cur) return false;
  Boolean same = false;
  CMVideoDimensions a = CMVideoFormatDescriptionGetDimensions(cur),
                    b = CMVideoFormatDescriptionGetDimensions(fmt);
  if (CMFormatDescriptionGetMediaSubType(fmt) ==
          CMFormatDescriptionGetMediaSubType(cur) &&
      a.width == b.width && a.height == b.height) {
    CFDataRef x = legacy_copy_config(cur), y = legacy_copy_config(fmt);
    same = (!x && !y) || (x && y && CFEqual(x, y));
    if (x) CFRelease(x);
    if (y) CFRelease(y);
  }
  CFRelease(cur);
  return same;
}

static OSStatus dec_finish_delayed_frames(VTVideoDecoderRef dec) {
  State* s = state_enter(dec);
  if (!s) return noErr;
  drain(s);  // every queued frame has been emitted when this returns
  state_release(s);
  return noErr;
}

static const CMBaseClass kBaseClass = {
    .version = 1,
    .derivedStorageSize = sizeof(Storage),
    .invalidate = base_invalidate,
    .finalize = base_finalize,
    .copyDebugDescription = base_copy_debug_description,
    .copyProperty = base_copy_property,
    .setProperty = base_set_property,
};

static const VTVideoDecoderClass kDecoderClass = {
    .version = 3,
    .startSession = dec_start_session,
    .decodeFrame = dec_decode_frame,
    .copySupportedPropertyDictionary = dec_copy_supported_properties,
    .canAcceptFormatDescription = dec_can_accept_format,
    .finishDelayedFrames = dec_finish_delayed_frames,
};

static const VTVideoDecoderVTable kVTable = {NULL, &kBaseClass, &kDecoderClass};

__attribute__((visibility("default"))) OSStatus LEGACY_FACTORY(
    FourCharCode codec, CFAllocatorRef alloc, VTVideoDecoderRef* out) {
  if (!out) return kVTParameterErr;
  *out = NULL;
  if (!legacy_accepts(codec)) return kVTCouldNotFindVideoDecoderErr;
  CMBaseObjectRef obj = NULL;
  OSStatus r =
      CMDerivedObjectCreate(alloc, &kVTable, VTVideoDecoderGetClassID(), &obj);
  if (r || !obj) return r ? r : kVTAllocationFailedErr;
  Storage* st = CMBaseObjectGetDerivedStorage(obj);
  memset(st, 0, sizeof(*st));
  State* s = calloc(1, sizeof(*s));
  if (!s) {
    CFRelease(obj);
    return kVTAllocationFailedErr;
  }
  s->refs = 1;  // the storage's
  pthread_mutex_init(&s->lock, NULL);
  pthread_mutex_init(&s->meta, NULL);
  pthread_cond_init(&s->idle, NULL);
  s->queue = dispatch_queue_create(
      LEGACY_LOG ".decode",
      dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                              QOS_CLASS_USER_INTERACTIVE, 0));
  s->slots = dispatch_semaphore_create(MAX_QUEUED);
  if (!s->queue || !s->slots) {
    state_release(s);  // the only reference: frees what was made
    CFRelease(obj);    // finalize finds no state
    return kVTAllocationFailedErr;
  }
  dispatch_queue_set_specific(s->queue, &kQueueKey, s, NULL);
  // Published with release once it is set up; from here on finalize frees
  // it.
  __atomic_store_n(&st->state, s, __ATOMIC_RELEASE);
  *out = (VTVideoDecoderRef)obj;
  return noErr;
}
