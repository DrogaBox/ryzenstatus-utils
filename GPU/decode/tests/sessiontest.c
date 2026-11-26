// sessiontest: the AV1 or the VP9 decoder session (vcnav1.c / vcnvp9.c with
// common/vcnsession.c) against a made-up AMDRadeonVADriver2, on the CPU.
// Nothing opens the real driver, the accelerator or the GPU: this file stands
// in for common/vcndriver.c (driver loading, accelerator lookup) and the
// made-up driver below answers every call. Built once for each codec, with
// -DTEST_AV1 or -DTEST_VP9. It checks:
//
//   1. create + destroy releases everything once, in Apple's order:
//      DeleteContexts, FreeBitstreamBufferPool, DeleteDriver,
//      AVD_DestroyAVDAccelerator;
//   2. a create that fails after the accelerator was made (CreateDriver,
//      AllocateBitstreamBufferPool, CreateContexts) still destroys it, once;
//      a failed CreateAVDAccelerator destroys nothing;
//   3. a pool that was never allocated is never freed;
//   4. a driver without AVD_DestroyAVDAccelerator still opens and closes;
//   5. a command that never finishes stops the session as a device failure
//      (later frames too, without another command), and its teardown runs on
//      the background queue, not on the caller's thread, and still releases
//      everything; the same after a failed QueryAVDCommandStatus, since the
//      command may still be on the GPU;
//   6. a ScheduleAVDCommands failure is a device failure; a firmware result
//      is counted, the frame is not refused;
//   7. a pool with a missing buffer fails the create and is freed; a failed
//      CreateAVDAccelerator that leaves its result set destroys nothing;
//   8. the accelerator is asked for one service, as the 25G342 driver checks
//      it (common/avd.h), and every create that fails part way releases what
//      it made in the same order as a full close;
//   9. (VP9) a driver handle whose VAContext is NULL fails the create and is
//      released, without a read through it;
//  10. with a second clip whose samples pack a hidden frame with a shown one:
//      the hidden frame sent alone (as FFmpeg sends frames) shows nothing and
//      leaves its picture in *_hidden_picture, the rest of the sample then
//      shows one frame and clears it; a frame whose reference was never
//      decoded is a reference failure, not a stream failure;
//  11. (AV1) a 12-bit sequence header is refused as unsupported (VideoToolbox
//      then gives the stream to the software decoder); a 10-bit BT.2020 PQ
//      one is taken, and the session reports its colour and the light level
//      of its metadata OBU (vcnav1_color);
//  12. a system sleep (a made-up sleep mark, standing in for the clocks and
//      kern.waketime), 0.3.7: a key frame right after it rebuilds the driver
//      objects and decodes on the new ones; an inter frame after it still
//      decodes on the old ones, with no error and no frame dropped, and the
//      next key frame rebuilds; a second sleep rebuilds again; with no key
//      frame the old session decodes on past the drop limit; when the old
//      session fails after the wake (ScheduleAVDCommands, a command that does
//      not finish within the longer wake limit, a firmware result) it is
//      rebuilt at once, the frame is dropped with no error, the frames up to
//      the next key frame too, and the key frame decodes; a command that did
//      not finish has its accelerator closed on the background queue; with no
//      key frame after such a failure the session stops as a device failure
//      at the limit; a rebuild that fails stops the session; a session only
//      closed after the wake, or stuck when the sleep came, closes quietly on
//      the background queue (only AVD_DestroyAVDAccelerator); a new wake time
//      alone or a wall clock that ran ahead counts as a sleep, a change of
//      the time asleep under 1 ms or both clocks moving together does not; a
//      new session opens beside one from before the sleep and decodes.
//  13. 0.3.8: a sleep that lands inside a decode call (the frame was on the GPU
//      when the machine slept) rebuilds the session instead of stopping it; the
//      quiet rebuild closes the old accelerator on the background queue; the
//      15 s limit covers the first command on the rebuilt session, and the
//      usual 1 s is back once one has finished; the restart predicate takes an
//      AV1 intra-only frame that refreshes all eight slots and a VP9 one that
//      resets all four contexts, with its negatives.
//
// usage: sessiontest <small IVF clip of the codec> [clip with hidden frames]
// Exit status 0 = pass.
#include <IOKit/IOKitLib.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "vcndriver.h"

#if defined(TEST_AV1)
#include "obuwrite.h"
#include "vcnav1.h"
typedef VcnAV1 Vcn;
#define CREATE vcnav1_create
#define DESTROY vcnav1_destroy
#define DECODE vcnav1_decode
#define FAILURE vcnav1_failure
#define FWERRORS vcnav1_firmware_errors
#define LASTERR vcnav1_last_error
#define ARMED vcnav1_gpu_armed
#define FAIL_DEVICE VCNAV1_FAIL_DEVICE
#define FAIL_STREAM VCNAV1_FAIL_STREAM
#define FAIL_REFERENCE VCNAV1_FAIL_REFERENCE
#define HIDDEN vcnav1_hidden_picture
static void on_out(void* c, CVPixelBufferRef f, const AV1Parser* p, int64_t t) {
  (void)f, (void)p, (void)t;
  if (c) ++*(int*)c;
}
#elif defined(TEST_VP9)
#include "vcnvp9.h"
typedef VcnVP9 Vcn;
#define CREATE vcnvp9_create
#define DESTROY vcnvp9_destroy
#define DECODE vcnvp9_decode
#define FAILURE vcnvp9_failure
#define FWERRORS vcnvp9_firmware_errors
#define LASTERR vcnvp9_last_error
#define ARMED vcnvp9_gpu_armed
#define FAIL_DEVICE VCNVP9_FAIL_DEVICE
#define FAIL_STREAM VCNVP9_FAIL_STREAM
#define FAIL_REFERENCE VCNVP9_FAIL_REFERENCE
#define HIDDEN vcnvp9_hidden_picture
static void on_out(void* c, CVPixelBufferRef f, const VP9Parser* p, uint32_t w,
                   uint32_t h, int64_t t) {
  (void)f, (void)p, (void)w, (void)h, (void)t;
  if (c) ++*(int*)c;
}
#else
#error "build with -DTEST_AV1 or -DTEST_VP9"
#endif

static int failures;
static void expect(const char* what, bool ok) {
  printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) failures++;
}

// ---- the made-up driver
// What it was asked to do, and in which order (a number per call).
static struct {
  int creates, destroys, createDrivers, deleteDrivers, allocs, frees, createCtx,
      deleteCtx, schedules, queries;
  int seq, seqDeleteCtx, seqFree, seqDeleteDriver, seqDestroy;
  uint32_t mask, index, service;  // what CreateAVDAccelerator was asked for
  int liveAccels, liveDrivers;
  bool freeWithoutPool;  // FreeBitstreamBufferPool on a pool never allocated
  bool useAfterDestroy;  // a driver call after the accelerator was destroyed
  bool deleteCtxOnMain;  // DeleteContexts ran on the test's own thread
  bool gateTimedOut;     // DeleteContexts waited at the gate in vain
  bool destroyOnMain;    // a gated close destroyed on the test's own thread
} st;
// What it should get wrong.
static struct {
  int create, createDriver, alloc, createCtx, schedule;
  int queryFail;      // QueryAVDCommandStatus returns this
  bool leaveOut;      // a failed CreateAVDAccelerator leaves *out set
  bool nullBuf;       // the pool comes back without its second buffer
  bool noVA;          // the driver handle's +8 (the VAContext) is NULL
  bool hang;          // commands never finish
  unsigned firmware;  // result of every finished command
  bool noDestroy;     // the build has no AVD_DestroyAVDAccelerator
  bool
      rebuildFail;  // CreateDriver fails: the rebuild after a sleep cannot open
  bool sleepWhileHanging;  // the machine sleeps while a command is on the GPU
  unsigned hangMs;         // commands finish after this long (0: at once)
  double hangStart;        // when the current slow command started
} fault;

enum { kFakeBuffer = 1 << 20 };  // larger than any frame of the test clips
typedef struct FakeDrv {
  void* va;       // +8 holds the VAContext pointer, as the real driver's does
  void* factory;  // what va+75072 points to (VP9 swaps its class pointer)
  bool poolAllocated;
  void* buffers[VCN_NUM_BS];
  int ctx;
} FakeDrv;
typedef struct {
  AVD_Accelerator a;
  bool destroyed;
} FakeAccel;
// The start of every bitstream buffer of the last driver made, to see that
// nothing was written into the pool after a sleep.
static FakeDrv* lastDrv;
static uint8_t poolSnapshot[VCN_NUM_BS][64];

static int f_create_driver(void** out, AVD_DriverCreate* dc) {
  st.createDrivers++;
  if (((FakeAccel*)dc->accel)->destroyed) st.useAfterDestroy = true;
  if (fault.createDriver) return fault.createDriver;
  if (fault.rebuildFail) return 7;  // the rebuild's own CreateDriver
  FakeDrv* d = calloc(1, sizeof(*d));
  d->va = calloc(1, 75080);
  d->factory = calloc(1, 16);
  // One class for every factory, as in the real driver (VAFactory's vtable).
  static void* factoryClass[40];
  *(void**)d->factory = &factoryClass[2];
  *(void**)((uint8_t*)d->va + 75072) = d->factory;
  // the layout vcnvp9.c reads: drv+8 -> VAContext
  void** raw = calloc(2, sizeof(void*));
  raw[1] = fault.noVA ? NULL : d->va;
  // keep FakeDrv reachable from the handle: raw[0]
  raw[0] = d;
  st.liveDrivers++;
  lastDrv = d;
  *out = raw;
  return 0;
}
static FakeDrv* drv_of(void* h) { return ((void**)h)[0]; }
static void snapshot_pool(void) {
  for (int i = 0; lastDrv && i < VCN_NUM_BS; i++)
    if (lastDrv->buffers[i]) memcpy(poolSnapshot[i], lastDrv->buffers[i], 64);
}
static bool pool_untouched(void) {
  for (int i = 0; lastDrv && i < VCN_NUM_BS; i++)
    if (lastDrv->buffers[i] && memcmp(poolSnapshot[i], lastDrv->buffers[i], 64))
      return false;
  return lastDrv != NULL;
}
static int f_delete_driver(void* h) {
  st.deleteDrivers++;
  st.seqDeleteDriver = ++st.seq;
  FakeDrv* d = drv_of(h);
  for (int i = 0; i < VCN_NUM_BS; i++) free(d->buffers[i]);
  free(d->factory);
  free(d->va);
  free(d);
  free(h);
  st.liveDrivers--;
  return 0;
}
static int f_alloc(void* h, AVD_BitstreamPool* p) {
  st.allocs++;
  if (fault.alloc) return fault.alloc;
  FakeDrv* d = drv_of(h);
  if (p->count != VCN_NUM_BS) return 5;
  for (int i = 0; i < VCN_NUM_BS; i++)
    p->addressesOut[i] = d->buffers[i] = calloc(1, kFakeBuffer);
  if (fault.nullBuf) {
    free(d->buffers[1]);
    p->addressesOut[1] = d->buffers[1] = NULL;
  }
  d->poolAllocated = true;
  return 0;
}
static int f_free(void* h, uint32_t type) {
  (void)type;
  st.frees++;
  st.seqFree = ++st.seq;
  FakeDrv* d = drv_of(h);
  if (!d->poolAllocated) st.freeWithoutPool = true;
  d->poolAllocated = false;
  return 0;
}
static int f_create_ctx(void* h, AVD_DriverContextInit* ci) {
  st.createCtx++;
  if (fault.createCtx) return fault.createCtx;
  FakeDrv* d = drv_of(h);
  ci->list->contextsOut[0] = &d->ctx;
  return 0;
}
// While set, DeleteContexts waits until the test has its thread back from
// DESTROY: a close that runs on that thread, or that DESTROY waits for, cannot
// get through and is seen.
static dispatch_semaphore_t closeGate;
static pthread_t mainThread;
static int f_delete_ctx(void* h, AVD_DriverContextDelete* del) {
  (void)h;
  st.deleteCtx++;
  st.seqDeleteCtx = ++st.seq;
  if (closeGate) {
    if (pthread_equal(pthread_self(), mainThread)) st.deleteCtxOnMain = true;
    if (dispatch_semaphore_wait(
            closeGate, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)))
      st.gateTimedOut = true;
  }
  return del->count == 1 && del->contexts[0] ? 0 : 5;
}
// What vcn_sleep_mark reports: the test moves it to make a sleep.
static VcnSleepMark fakeSleep = {.asleepNs = 5000000000ull,
                                 .wakeUs = 1795000000000000ll,
                                 .wallUs = 1795000000000000ll};
static void sleep_for(uint64_t ns) {
  fakeSleep.asleepNs += ns;
  fakeSleep.wakeUs += 1000000;
  // The wall clock counts through a sleep, mach_absolute_time does not.
  fakeSleep.wallUs += (int64_t)(ns / 1000);
}

static int f_schedule(void* h, AVD_CmdList* l, AVD_RefConList* r) {
  (void)h, (void)l;
  st.schedules++;
  r->refcons[0] = (void*)0x1234;
  return fault.schedule;
}
static int f_query(void* h, AVD_QueryList* q) {
  (void)h;
  st.queries++;
  AVD_QueryEntry* e = q->entries;
  if (fault.queryFail) return fault.queryFail;
  if (fault.sleepWhileHanging) {
    // The machine slept while this command was on the GPU: the session's sleep
    // mark moves under the wait, whose own clock does not run while asleep.
    fault.sleepWhileHanging = false;
    sleep_for(10000000000ull);
  }
  if (fault.hangMs) {
    // Finishes, but only after this long: what a 1 s limit stops.
    double t = (double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e6;
    if (!fault.hangStart) fault.hangStart = t;
    if (t - fault.hangStart < (double)fault.hangMs) {
      e->status = 2;
      return 0;
    }
    fault.hangStart = 0;
    e->status = 1;
    e->status2 = e->wait ? fault.firmware : 0;
    return 0;
  }
  if (fault.hang) {
    if (e->wait) return 99;  // the real one would block here
    e->status = 2;
    return 0;
  }
  e->status = 1;
  e->status2 = e->wait ? fault.firmware : 0;
  return 0;
}

static int f_create_accel(AVD_Accelerator** out, AVD_AcceleratorCreate* in,
                          void* info) {
  (void)info;
  st.creates++;
  *out = NULL;
  // The 25G342 driver's check (common/avd.h): bit `index` of the mask set,
  // index below the highest bit set plus one, services[index] not 0.
  st.mask = in->validMask;
  st.index = in->index;
  uint32_t count = 0;
  for (uint32_t i = 0; i < 32; i++)
    if (in->validMask >> i & 1) count = i + 1;
  if (in->index >= 32 || !(in->validMask >> in->index & 1) ||
      in->index >= count || !in->services[in->index])
    return 5;
  st.service = in->services[in->index];
  if (fault.create) {
    // Never made: a destroy or a driver call through it is seen. The real
    // driver never leaves *out set on a failure (common/avd.h); leaveOut is a
    // driver that would, which must not be destroyed either.
    static FakeAccel stray;
    if (fault.leaveOut) *out = &stray.a;
    return fault.create;
  }
  FakeAccel* a = calloc(1, sizeof(*a));
  a->a.fn[AVD_FN_CreateDriver] = (void*)f_create_driver;
  a->a.fn[AVD_FN_DeleteDriver] = (void*)f_delete_driver;
  a->a.fn[AVD_FN_CreateContexts] = (void*)f_create_ctx;
  a->a.fn[AVD_FN_DeleteContexts] = (void*)f_delete_ctx;
  a->a.fn[AVD_FN_AllocateBitstreamBufferPool] = (void*)f_alloc;
  a->a.fn[AVD_FN_FreeBitstreamBufferPool] = (void*)f_free;
  a->a.fn[AVD_FN_ScheduleAVDCommands] = (void*)f_schedule;
  a->a.fn[AVD_FN_QueryAVDCommandStatus] = (void*)f_query;
  st.liveAccels++;
  *out = &a->a;
  return 0;
}
static int f_destroy_accel(AVD_Accelerator* acc) {
  st.destroys++;
  if (closeGate && pthread_equal(pthread_self(), mainThread))
    st.destroyOnMain = true;
  st.seqDestroy = ++st.seq;
  FakeAccel* a = (FakeAccel*)acc;
  if (a->destroyed) st.useAfterDestroy = true;
  a->destroyed = true;
  st.liveAccels--;
  // Kept, not freed: a call through it afterwards is then seen, not a crash.
  return 0;
}

// ---- stand-ins for common/vcndriver.c
bool vcn_codec_is_amd(CFTypeRef codec) {
  (void)codec;
  return true;
}
io_service_t vcn_find_accelerator(void) {
  // A real registry entry, so the session's IOObjectRelease is a real one.
  return IOServiceGetMatchingService(kIOMainPortDefault,
                                     IOServiceMatching("IOResources"));
}
bool vcn_driver_uuid(char out[33]) {
  snprintf(out, 33, "1181E2CA31B33DF090E23AE70552D753");
  return true;
}
void vcn_sleep_mark(VcnSleepMark* m) { *m = fakeSleep; }
bool vcn_driver_load(VcnDriverLib* lib, char* err, size_t errLen) {
  (void)err, (void)errLen;
  *lib = (VcnDriverLib){.create = f_create_accel,
                        .destroy = fault.noDestroy ? NULL : f_destroy_accel};
  vcn_driver_uuid(lib->uuid);
  return true;
}

// ---- helpers
static uint8_t* frame0;
static size_t frame0Size;
static bool read_first_frame(const char* path) {
  FILE* f = fopen(path, "rb");
  uint8_t h[32], fh[12];
  if (!f || fread(h, 1, 32, f) != 32 || memcmp(h, "DKIF", 4) ||
      fread(fh, 1, 12, f) != 12) {
    if (f) fclose(f);
    return false;
  }
  frame0Size = fh[0] | fh[1] << 8 | fh[2] << 16 | (size_t)fh[3] << 24;
  frame0 =
      frame0Size && frame0Size < kFakeBuffer - 256 ? malloc(frame0Size) : NULL;
  bool ok = frame0 && fread(frame0, 1, frame0Size, f) == frame0Size;
  fclose(f);
  return ok;
}
static void reset(void) {
  memset(&st, 0, sizeof(st));
  memset(&fault, 0, sizeof(fault));
}
// The calls a close made come in Apple's order, whichever of them ran.
static bool released_in_order(void) {
  int seq[] = {st.seqDeleteCtx, st.seqFree, st.seqDeleteDriver, st.seqDestroy};
  int last = 0;
  for (int i = 0; i < 4; i++) {
    if (!seq[i]) continue;
    if (seq[i] < last) return false;
    last = seq[i];
  }
  return true;
}
// After a rebuild the driver handle from before the sleep is still open: that
// is the leak F4 of the review describes, one per rebuild, left behind on
// purpose because only the driver could free it and it may be wedged. What
// must hold is that every accelerator is closed, and that exactly the dropped
// drivers are left.
static bool closed_after_rebuild(int dropped) {
  return st.liveAccels == 0 && st.liveDrivers == dropped &&
         !st.useAfterDestroy && !st.freeWithoutPool;
}
static bool all_released(void) {
  return st.liveAccels == 0 && st.liveDrivers == 0 && !st.useAfterDestroy &&
         !st.freeWithoutPool;
}
static Vcn* make(void) {
  char err[256] = "";
  Vcn* d = CREATE(4096, 2304, err, sizeof(err));
  if (!d) printf("     create: %s\n", err);
  return d;
}

// Destroys a stuck session and checks that its close ran on the background
// queue: not on this thread, and not waited for by DESTROY.
static bool closed_in_background(Vcn* d) {
  closeGate = dispatch_semaphore_create(0);
  DESTROY(d);
  dispatch_semaphore_signal(closeGate);
  bool drained = vcn_teardown_drain(10000);
  // A close still running may yet wait on the gate: keep it then.
  if (drained) dispatch_release(closeGate);
  closeGate = NULL;
  return drained && st.deleteCtx == 1 && !st.deleteCtxOnMain &&
         !st.gateTimedOut;
}

// Destroys a session from before a sleep: its close runs on the background
// queue and calls nothing of the driver but AVD_DestroyAVDAccelerator. The
// driver handle it never deleted stays: the made-up driver counts it live.
static bool closed_quietly(Vcn* d) {
  int before = st.deleteCtx + st.frees + st.deleteDrivers;
  closeGate = dispatch_semaphore_create(0);
  DESTROY(d);
  // Nothing calls DeleteContexts, so nothing waits at the gate: open it anyway.
  dispatch_semaphore_signal(closeGate);
  bool drained = vcn_teardown_drain(10000);
  if (drained) dispatch_release(closeGate);
  closeGate = NULL;
  return drained && st.deleteCtx + st.frees + st.deleteDrivers == before &&
         st.destroys == 1 && st.liveAccels == 0 && !st.useAfterDestroy &&
         !st.destroyOnMain;
}

// ---- samples split the way FFmpeg sends them
typedef struct {
  uint8_t* data;
  size_t size;
} Sample;
static Sample clip[64];
static int clipCount;
static void clip_clear(void) {
  for (int i = 0; i < clipCount; i++) free(clip[i].data);
  clipCount = 0;
}
static bool read_clip(const char* path) {
  FILE* f = fopen(path, "rb");
  uint8_t h[32], fh[12];
  if (!f || fread(h, 1, 32, f) != 32 || memcmp(h, "DKIF", 4)) {
    if (f) fclose(f);
    return false;
  }
  while (clipCount < 64 && fread(fh, 1, 12, f) == 12) {
    size_t n = fh[0] | fh[1] << 8 | fh[2] << 16 | (size_t)fh[3] << 24;
    uint8_t* b = n && n < kFakeBuffer - 256 ? malloc(n) : NULL;
    if (!b || fread(b, 1, n, f) != n) {
      free(b);
      break;
    }
    clip[clipCount++] = (Sample){b, n};
  }
  fclose(f);
  return clipCount > 0;
}
// Where the second frame of a sample starts, or 0 when it holds one frame.
static size_t second_frame(const uint8_t* b, size_t n) {
#if defined(TEST_AV1)
  // OBUs with sizes; frames are OBU_FRAME_HEADER (3) or OBU_FRAME (6).
  size_t o = 0;
  int frames = 0;
  while (o < n) {
    uint8_t hd = b[o];
    int type = hd >> 3 & 15;
    size_t q = o + 1 + (hd >> 2 & 1), len = 0;
    if (!(hd >> 1 & 1)) return 0;
    for (int k = 0; k < 8 && q < n; k++, q++) {
      len |= (size_t)(b[q] & 0x7f) << (7 * k);
      if (!(b[q] & 0x80)) {
        q++;
        break;
      }
    }
    if (type == 3 || type == 6) {
      if (++frames == 2) return o;
    }
    o = q + len;
  }
  return 0;
#else
  // A superframe index at the end; the first frame's size is its first entry.
  uint8_t m = b[n - 1];
  if ((m & 0xe0) != 0xc0) return 0;
  int count = (m & 7) + 1, mag = (m >> 3 & 3) + 1;
  size_t index = 2 + (size_t)mag * count;
  if (n < index || b[n - index] != m || count < 2) return 0;
  size_t first = 0;
  for (int k = 0; k < mag; k++)
    first |= (size_t)b[n - index + 1 + k] << (8 * k);
  return first < n - index ? first : 0;
#endif
}

static void hidden_frames(const char* path) {
  if (!read_clip(path)) {
    expect("the clip with hidden frames reads", false);
    return;
  }
  int at = -1;
  size_t cut = 0;
  for (int i = 0; i < clipCount && at < 0; i++)
    if ((cut = second_frame(clip[i].data, clip[i].size))) at = i;
  expect("the clip has a sample with a hidden frame packed in", at >= 0);
  if (at < 0) return;
  const Sample* s = &clip[at];
#if defined(TEST_AV1)
  // The rest of an AV1 temporal unit is its later frames' OBUs.
  const uint8_t* rest = s->data + cut;
  size_t restSize = s->size - cut;
#else
  // The rest of a superframe: the following frames, without the index.
  uint8_t m = s->data[s->size - 1];
  size_t index = 2 + (size_t)((m >> 3 & 3) + 1) * ((m & 7) + 1);
  const uint8_t* rest = s->data + cut;
  size_t restSize = s->size - index - cut;
#endif
  reset();
  Vcn* d = make();
  int shown = 0, r = 0;
  for (int i = 0; d && i < at && !r; i++)
    r = DECODE(d, clip[i].data, clip[i].size, i, on_out, &shown);
  expect("the samples before it decode", d && r == 0);
  shown = 0;
  int rh = d ? DECODE(d, s->data, cut, at, on_out, &shown) : -1;
  if (rh) printf("     hidden frame alone: %s\n", d ? LASTERR(d) : "");
  expect("its hidden frame alone shows nothing and keeps its picture",
         d && rh == 0 && shown == 0 && HIDDEN(d) != NULL);
  shown = 0;
  int rr = d ? DECODE(d, rest, restSize, at, on_out, &shown) : -1;
  if (rr) printf("     rest of the sample: %s\n", d ? LASTERR(d) : "");
  expect("the rest of the sample shows one frame, no hidden picture left",
         d && rr == 0 && shown == 1 && HIDDEN(d) == NULL);
  if (d) DESTROY(d);
  expect("and that session closes fully", all_released());

  // A new session that starts on the rest of the sample: its frame refers to
  // pictures this session never decoded.
  reset();
  d = make();
  int rm = -1;
  if (d) {
    r = DECODE(d, clip[0].data, clip[0].size, 0, on_out, NULL);  // headers
#if defined(TEST_AV1)
    vcnav1_flush(d);
#else
    DESTROY(d);
    d = make();
#endif
    rm =
        d ? DECODE(d, clip[at + 1 < clipCount ? at + 1 : at].data,
                   clip[at + 1 < clipCount ? at + 1 : at].size, 0, on_out, NULL)
          : -1;
  }
  if (d) printf("     after the references were dropped: %s\n", LASTERR(d));
  expect("a frame whose reference was never decoded is a reference failure",
         d && rm != 0 && FAILURE(d) == FAIL_REFERENCE);
  if (d) DESTROY(d);
  clip_clear();
}

#if defined(TEST_VP9)
// The video engine predicts bit-exactly from a reference up to 2x smaller than
// the frame and not from a smaller one: vp90-2-22-svc_1280x720_3's 1280x720
// layer predicts from a 320x180 reference (4x) and differed from libvpx in
// more than half the picture, while its 640x360 layer (a 2x smaller reference)
// was identical. A frame it cannot do is refused, and the slots it should have
// refreshed are emptied, so the frames that read them are refused too instead
// of decoding against older pictures.
static void scaled_references(const char* svc, const char* scaled) {
  clip_clear();
  expect("the clip that predicts from a 2x smaller reference reads",
         read_clip(scaled));
  reset();
  Vcn* d = make();
  int shown = 0, bad = d ? 0 : -1;
  for (int i = 0; d && i < clipCount; i++)
    if (DECODE(d, clip[i].data, clip[i].size, i, on_out, &shown)) {
      printf("     sample %d: %s\n", i, LASTERR(d));
      bad++;
    }
  expect("references up to 2x smaller are not refused (mv-with-scaling)",
         d && bad == 0 && shown > 0);
  if (d) DESTROY(d);
  expect("and that session closes fully", all_released());

  clip_clear();
  expect("the spatial-SVC clip reads", read_clip(svc) && clipCount >= 3);
  if (clipCount < 3) return;
  reset();
  d = make();
  shown = 0;
  int r0 = d ? DECODE(d, clip[0].data, clip[0].size, 0, on_out, &shown) : 0;
  if (r0) printf("     chunk 0: %s\n", d ? LASTERR(d) : "");
  expect("a frame whose reference is 4x smaller is refused as a stream failure",
         d && r0 != 0 && FAILURE(d) == FAIL_STREAM &&
             strstr(LASTERR(d), "2x smaller"));
  expect("the two layers before it were sent to the engine, it was not",
         st.schedules == 2);
  int sent = st.schedules;
  int r1 = d ? DECODE(d, clip[1].data, clip[1].size, 1, on_out, &shown) : 0;
  expect(
      "a frame predicted from what it should have refreshed is a reference "
      "failure and sends nothing",
      d && r1 != 0 && FAILURE(d) == FAIL_REFERENCE && st.schedules == sent);
  int r2 = d ? DECODE(d, clip[2].data, clip[2].size, 2, on_out, &shown) : 0;
  expect("and so is the next one", d && r2 != 0 && st.schedules == sent);
  int rk = d ? DECODE(d, frame0, frame0Size, 3, on_out, &shown) : -1;
  expect("a key frame refreshes every slot and decodes again",
         d && rk == 0 && st.schedules > sent);
  if (d) DESTROY(d);
  expect("and that session closes fully", all_released());
  clip_clear();
}
#endif

static void hung(int sig) {
  (void)sig;
  static const char msg[] = "FAIL a test hung\n";
  write(1, msg, sizeof(msg) - 1);
  _exit(1);
}

int main(int argc, char** argv) {
  if (argc < 2 || argc > 5 || !read_first_frame(argv[1])) {
    fprintf(stderr,
            "usage: sessiontest <small IVF clip of the codec> [clip with "
            "hidden frames [VP9: spatial-SVC clip, clip with 2x scaled "
            "references]]\n");
    return 1;
  }
  signal(SIGALRM, hung);
  alarm(60);
  mainThread = pthread_self();
  ARMED = 1;

  reset();
  Vcn* d = make();
  bool made = d != NULL;
  if (d) DESTROY(d);
  expect("create + destroy: one accelerator, destroyed once",
         made && st.creates == 1 && st.destroys == 1 && all_released());
  expect("in Apple's order: contexts, pool, driver, accelerator",
         st.seqDeleteCtx && st.seqDeleteCtx < st.seqFree &&
             st.seqFree < st.seqDeleteDriver &&
             st.seqDeleteDriver < st.seqDestroy);
  expect("the accelerator is asked for services[0] only, as one valid entry",
         st.index == 0 && st.mask == 1 && st.service != 0);

  reset();
  fault.create = 1;
  expect(
      "a failed CreateAVDAccelerator destroys nothing",
      !make() && st.creates == 1 && st.destroys == 0 && st.createDrivers == 0);

  reset();
  fault.create = 1;
  fault.leaveOut = true;
  expect("one that leaves its result set destroys nothing either",
         !make() && st.destroys == 0 && st.createDrivers == 0);

  reset();
  fault.createDriver = 5;
  expect("a failed CreateDriver still destroys the accelerator, once",
         !make() && st.destroys == 1 && st.frees == 0 &&
             st.deleteDrivers == 0 && all_released() && st.seqDestroy);

  reset();
  fault.alloc = 7;
  expect("a failed pool allocation: the pool is not freed, the rest is",
         !make() && st.frees == 0 && st.deleteDrivers == 1 &&
             st.destroys == 1 && all_released());
  expect("in order: driver, accelerator", released_in_order());

  reset();
  fault.nullBuf = true;
  expect("a pool with a missing buffer fails the create and is freed",
         !make() && st.createCtx == 0 && st.frees == 1 &&
             st.deleteDrivers == 1 && st.destroys == 1 && all_released());
  expect("in order: pool, driver, accelerator", released_in_order());

  reset();
  fault.createCtx = 10;
  expect("a failed CreateContexts: no context deleted, the rest released",
         !make() && st.deleteCtx == 0 && st.frees == 1 &&
             st.deleteDrivers == 1 && st.destroys == 1 && all_released());
  expect("in order: pool, driver, accelerator", released_in_order());

#if defined(TEST_VP9)
  reset();
  fault.noVA = true;
  expect("a driver handle with no VAContext fails the create, all released",
         !make() && st.createCtx == 0 && st.deleteDrivers == 1 &&
             st.destroys == 1 && all_released() && released_in_order());
#endif

  reset();
  fault.noDestroy = true;
  d = make();
  made = d != NULL;
  if (d) DESTROY(d);
  expect(
      "a driver without AVD_DestroyAVDAccelerator still opens and closes",
      made && st.destroys == 0 && st.deleteDrivers == 1 && st.liveDrivers == 0);

  reset();
  d = make();
  int r1 = d ? DECODE(d, frame0, frame0Size, 0, on_out, NULL) : 0;
  int k1 = d ? FAILURE(d) : -1;
  expect("a frame on a working driver decodes", d && r1 == 0);
  fault.firmware = 6;
  int r2 = d ? DECODE(d, frame0, frame0Size, 1, on_out, NULL) : -1;
  expect("a firmware result is counted, the frame is not refused",
         d && r2 == 0 && FWERRORS(d) == 1);
  (void)k1;
  if (d) DESTROY(d);
  expect("and the session closes fully", all_released() && st.destroys == 1);

#if defined(TEST_AV1)
  reset();
  d = make();
  uint8_t obus[128];
  size_t on = obu_sequence_header(obus, 0, 2, 12, 9, 16, 9, 0);
  int r12 = d ? vcnav1_configure(d, obus, on) : 0;
  expect("a 12-bit sequence header is refused as unsupported",
         d && r12 == VCNAV1_UNSUPPORTED);
  if (d) DESTROY(d);
  reset();
  d = make();
  on = obu_sequence_header(obus, 0, 0, 10, 9, 16, 9, 0);
  on = obu_cll(obus, on, 1000, 400);
  int r10 = d ? vcnav1_configure(d, obus, on) : -1;
  VcnColor col;
  vcnav1_color(d, &col);
  expect(
      "a 10-bit BT.2020 PQ one is taken, and gives its colour and light "
      "level",
      d && r10 == 0 && col.primaries == 9 && col.transfer == 16 &&
          col.matrix == 9 && col.has_cll && !col.has_mdcv &&
          col.cll[0] == 0x03 && col.cll[1] == 0xe8 && col.cll[3] == 0x90);
  if (d) DESTROY(d);
  expect("and both sessions close fully", all_released());
#endif

  reset();
  d = make();
  fault.hang = true;
  int rh = d ? DECODE(d, frame0, frame0Size, 0, on_out, NULL) : 0;
  int kh = d ? FAILURE(d) : -1;
  printf("     after the timeout: %s\n", d ? LASTERR(d) : "");
  int schedules = st.schedules;
  int rh2 = d ? DECODE(d, frame0, frame0Size, 1, on_out, NULL) : 0;
  int kh2 = d ? FAILURE(d) : -1;
  expect("a command that never finishes is a device failure",
         rh != 0 && kh == FAIL_DEVICE);
  expect("later frames fail the same way and send nothing",
         rh2 != 0 && kh2 == FAIL_DEVICE && st.schedules == schedules);
  bool background = d && closed_in_background(d);
  expect("the stuck session is closed on the background queue, fully",
         background && st.destroys == 1 && all_released());

  reset();
  d = make();
  fault.queryFail = 4;
  int rq = d ? DECODE(d, frame0, frame0Size, 0, on_out, NULL) : 0;
  int kq = d ? FAILURE(d) : -1;
  fault.queryFail = 0;
  expect("a failed QueryAVDCommandStatus is a device failure",
         rq != 0 && kq == FAIL_DEVICE);
  background = d && closed_in_background(d);
  expect("and, the command maybe still on the GPU, closes in the background",
         background && st.destroys == 1 && all_released());

  reset();
  d = make();
  fault.schedule = 3;
  int rs = d ? DECODE(d, frame0, frame0Size, 0, on_out, NULL) : 0;
  int ks = d ? FAILURE(d) : -1;
  fault.schedule = 0;
  int schedulesBefore = st.schedules;
  int rs2 = d ? DECODE(d, frame0, frame0Size, 1, on_out, NULL) : 0;
  int ks2 = d ? FAILURE(d) : -1;
  expect("a ScheduleAVDCommands failure is a device failure, and sticks",
         rs != 0 && ks == FAIL_DEVICE && rs2 != 0 && ks2 == FAIL_DEVICE);
  expect("and the frames after it send nothing",
         schedulesBefore == 1 && st.schedules == schedulesBefore);
  if (d) DESTROY(d);
  expect("and that session closes fully", all_released());

  reset();
  d = make();
  static const uint8_t junk[16] = {0xff, 0xff, 0xff, 0xff};
  int rj = d ? DECODE(d, junk, sizeof(junk), 0, on_out, NULL) : 0;
  expect("a damaged sample is a stream failure",
         d && rj != 0 && FAILURE(d) == FAIL_STREAM && st.schedules == 0);
  if (d) DESTROY(d);

  // 12. A system sleep, and the rebuild that follows it instead of failing
  // every frame (plan B, job 178).
  clip_clear();
  bool haveSamples = read_clip(argv[1]);
  if (!haveSamples) printf("     the clip did not read for the sleep tests\n");
  bool haveInter = haveSamples && clipCount > 1;
  // A second sample only exercises "dropped until a key frame" if it really
  // needs references: on a fresh session such a frame fails as a reference
  // error, while a second key frame would decode.
  bool interUsable = false;  // reported below: the tests it gates must run
  if (haveInter) {
    reset();
    Vcn* probe = make();
#if defined(TEST_AV1)
    // An AV1 frame needs the sequence header of the first sample, and the
    // references dropped after it.
    if (probe) DECODE(probe, clip[0].data, clip[0].size, 0, on_out, NULL);
    if (probe) vcnav1_flush(probe);
#endif
    if (probe) DECODE(probe, clip[1].data, clip[1].size, 0, on_out, NULL);
    interUsable = probe && FAILURE(probe) == FAIL_REFERENCE;
    if (probe) DESTROY(probe);
  }

  reset();
  d = make();
  int rb = d ? DECODE(d, frame0, frame0Size, 0, on_out, NULL) : -1;
  expect("before the sleep, a frame decodes", d && rb == 0);
  int createsBefore12 = st.creates, ctxBefore12 = st.createCtx;
  sleep_for(30000000000ull);
  int shown12 = 0;
  int ra = d ? DECODE(d, frame0, frame0Size, 1, on_out, &shown12) : -1;
  printf("     after the sleep: %s\n", d && ra ? LASTERR(d) : "driver rebuilt");
  expect(
      "after it, the session rebuilds the driver and decodes the key frame on "
      "it, with no error",
      d && ra == 0 && shown12 == 1 && st.creates == createsBefore12 + 1 &&
          st.createCtx == ctxBefore12 + 1);
  if (d) DESTROY(d);
  expect("and the rebuilt session closes fully, only the dropped driver left",
         closed_after_rebuild(1));

  // Closed after the wake without a frame: still the quiet close of PR 160,
  // because no rebuild happened.
  reset();
  d = make();
  sleep_for(10000000000ull);
  expect("a session only closed after the wake closes quietly",
         d && closed_quietly(d) && st.schedules == 0);

  reset();
  d = make();
  fault.hang = true;
  int rs12 = d ? DECODE(d, frame0, frame0Size, 0, on_out, NULL) : 0;
  sleep_for(10000000000ull);
  expect("a session stuck when the sleep came closes the same way",
         rs12 != 0 && d && closed_quietly(d));

  reset();
  d = make();
  fakeSleep.wakeUs += 1000000;  // a wake whose time asleep was not counted
  int rw = d ? DECODE(d, frame0, frame0Size, 0, on_out, NULL) : -1;
  expect("a new wake time alone counts as a sleep, and the session rebuilds",
         d && rw == 0 && st.creates == 2);
  if (d) DESTROY(d);

  reset();
  d = make();
  fakeSleep.asleepNs += 900000;  // 0.9 ms: the reading's error, no sleep
  int rj12 = d ? DECODE(d, frame0, frame0Size, 0, on_out, NULL) : -1;
  if (d) DESTROY(d);
  expect("a change of the time asleep under 1 ms is not a sleep",
         rj12 == 0 && st.deleteCtx == 1 && st.creates == 1 && all_released());

  reset();
  d = make();
  // A machine whose sleep path skipped the kernel's wake accounting: the
  // counters do not move, only the wall clock does (the RTC counts through a
  // sleep even when the kernel counted none of it).
  fakeSleep.wallUs += 30000000;
  int rwall = d ? DECODE(d, frame0, frame0Size, 0, on_out, NULL) : -1;
  expect("a wall clock that ran ahead of the counters counts as a sleep",
         d && rwall == 0 && st.creates == 2);
  if (d) DESTROY(d);
  fakeSleep.wallUs -= 30000000;

  reset();
  d = make();
  fakeSleep.wallUs += 2000000;  // the same two seconds on both clocks
  fakeSleep.monoNs += 2000000000ull;
  int rboth = d ? DECODE(d, frame0, frame0Size, 0, on_out, NULL) : -1;
  if (d) DESTROY(d);
  expect("the wall clock and the counters moving together is not a sleep",
         rboth == 0 && st.deleteCtx == 1 && st.creates == 1);
  fakeSleep.wallUs -= 2000000;
  fakeSleep.monoNs -= 2000000000ull;

  expect(
      "the clip's second sample needs references (the inter frame tests run)",
      interUsable);
  if (interUsable) {
    // An inter frame after the sleep decodes on the driver objects from before
    // it (a real sleep on this Mac did not break them), and the next key frame
    // rebuilds them.
    reset();
    d = make();
    int k0 = d ? DECODE(d, clip[0].data, clip[0].size, 0, on_out, NULL) : -1;
    sleep_for(10000000000ull);
    int createsB = st.creates, ctxB = st.createCtx, schedB = st.schedules;
    int shownI = 0;
    int di = d ? DECODE(d, clip[1].data, clip[1].size, 1, on_out, &shownI) : -1;
    if (di) printf("     inter frame after the sleep: %s\n", LASTERR(d));
    expect(
        "an inter frame after the sleep decodes on the old session: shown, no "
        "error, no rebuild",
        d && k0 == 0 && di == 0 && shownI == 1 && st.creates == createsB &&
            st.schedules == schedB + 1);
    int shownK = 0;
    int dk = d ? DECODE(d, clip[0].data, clip[0].size, 2, on_out, &shownK) : -1;
    if (dk) printf("     key frame after it: %s\n", d ? LASTERR(d) : "");
    expect("the next key frame rebuilds the driver and decodes on the new one",
           d && dk == 0 && shownK == 1 && st.creates == createsB + 1 &&
               st.createCtx == ctxB + 1);
    int shownI2 = 0;
    int di2 =
        d ? DECODE(d, clip[1].data, clip[1].size, 3, on_out, &shownI2) : -1;
    expect("an inter frame after the rebuild decodes, no second rebuild",
           d && di2 == 0 && shownI2 == 1 && st.creates == createsB + 1);
    sleep_for(10000000000ull);
    int shownK2 = 0;
    int dk2 =
        d ? DECODE(d, clip[0].data, clip[0].size, 4, on_out, &shownK2) : -1;
    expect("a second sleep: the next key frame rebuilds again",
           d && dk2 == 0 && shownK2 == 1 && st.creates == createsB + 2);
    if (d) DESTROY(d);
    expect("and that session closes, only the two dropped drivers left",
           closed_after_rebuild(2));

    // With no key frame at all, the old session simply decodes on: nothing is
    // dropped, past the limit that applies after a failure.
    reset();
    d = make();
    if (d) DECODE(d, clip[0].data, clip[0].size, 0, on_out, NULL);
    sleep_for(10000000000ull);
    int shownN = 0, failedN = 0;
    for (int i = 0; d && i < 700; i++)
      if (DECODE(d, clip[1].data, clip[1].size, i, on_out, &shownN)) failedN++;
    expect(
        "with no key frame the old session decodes on: 700 frames shown, no "
        "error, no rebuild",
        d && failedN == 0 && shownN == 700 && st.creates == 1);
    if (d) DESTROY(d);
    bool drainedN = vcn_teardown_drain(10000);
    expect("and, never rebuilt, it closes quietly: nothing but the accelerator",
           drainedN && st.deleteCtx == 0 && st.liveAccels == 0 &&
               st.liveDrivers == 1);

    // The old session fails after the wake: rebuilt at once, the frame
    // dropped with no picture and no error, the frames up to the next key
    // frame too, and the key frame decodes on the new driver.
    reset();
    d = make();
    if (d) DECODE(d, clip[0].data, clip[0].size, 0, on_out, NULL);
    sleep_for(10000000000ull);
    fault.schedule = 3;
    int shownF = 0;
    int df = d ? DECODE(d, clip[1].data, clip[1].size, 1, on_out, &shownF) : -1;
    fault.schedule = 0;
    if (df) printf("     schedule failure after the sleep: %s\n", LASTERR(d));
    expect(
        "a ScheduleAVDCommands failure after the sleep rebuilds at once and "
        "drops the frame, with no error",
        d && df == 0 && shownF == 0 && st.creates == 2);
    int schedF = st.schedules, shownD = 0;
    int dd = d ? DECODE(d, clip[1].data, clip[1].size, 2, on_out, &shownD) : -1;
    expect("the next inter frame is dropped too, sending nothing",
           d && dd == 0 && shownD == 0 && st.schedules == schedF);
    int shownFK = 0;
    int dfk =
        d ? DECODE(d, clip[0].data, clip[0].size, 3, on_out, &shownFK) : -1;
    expect("and the key frame decodes on the rebuilt driver",
           d && dfk == 0 && shownFK == 1 && st.creates == 2);
    if (d) DESTROY(d);
    expect("and that session closes fully, only the dropped driver left",
           closed_after_rebuild(1));

    // A command on the old session that does not finish: it is waited for up
    // to the wake limit (longer than the usual one), then the session is
    // rebuilt and the old accelerator closed on the background queue.
    reset();
    d = make();
    if (d) DECODE(d, clip[0].data, clip[0].size, 0, on_out, NULL);
    sleep_for(10000000000ull);
    vcn_wake_command_timeout_ms = 1500;  // above the usual 1000 ms
    fault.hang = true;
    closeGate = dispatch_semaphore_create(0);  // marks a destroy on this thread
    int shownH = 0;
    double h0 = (double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e6;
    int dh = d ? DECODE(d, clip[1].data, clip[1].size, 1, on_out, &shownH) : -1;
    double waited = (double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e6 - h0;
    fault.hang = false;
    vcn_wake_command_timeout_ms = VCN_WAKE_COMMAND_TIMEOUT_MS;
    printf("     waited %.0f ms for the command on the old session\n", waited);
    bool drainedH = vcn_teardown_drain(10000);
    if (drainedH) dispatch_release(closeGate);
    closeGate = NULL;
    expect(
        "a command on the old session that does not finish is waited for up "
        "to the wake limit, not the usual one",
        waited >= 1400);
    expect(
        "then the session is rebuilt, the frame dropped with no error, and the "
        "old accelerator closed on the background queue",
        d && dh == 0 && shownH == 0 && st.creates == 2 && drainedH &&
            st.destroys == 1 && !st.destroyOnMain && st.deleteCtx == 0);
    int shownHK = 0;
    int dhk =
        d ? DECODE(d, clip[0].data, clip[0].size, 2, on_out, &shownHK) : -1;
    expect("and the key frame decodes on the rebuilt driver",
           d && dhk == 0 && shownHK == 1);
    if (d) DESTROY(d);
    expect("and that session closes fully, only the dropped driver left",
           closed_after_rebuild(1));

    // A firmware result on the old session after the wake: its picture is not
    // trusted, the session is rebuilt and the frame dropped.
    reset();
    d = make();
    if (d) DECODE(d, clip[0].data, clip[0].size, 0, on_out, NULL);
    sleep_for(10000000000ull);
    fault.firmware = 6;
    int shownW = 0;
    int dw = d ? DECODE(d, clip[1].data, clip[1].size, 1, on_out, &shownW) : -1;
    fault.firmware = 0;
    expect(
        "a firmware result on the old session after the sleep rebuilds and "
        "drops the frame, with no error",
        d && dw == 0 && shownW == 0 && st.creates == 2);
    int shownWK = 0;
    int dwk =
        d ? DECODE(d, clip[0].data, clip[0].size, 2, on_out, &shownWK) : -1;
    expect("and the key frame decodes on the rebuilt driver",
           d && dwk == 0 && shownWK == 1);
    if (d) DESTROY(d);
    expect("and that session closes fully, only the dropped driver left",
           closed_after_rebuild(1));

    // A stream that never sends a key frame after such a failure: frames are
    // dropped for a while, then the session stops the way PR 160 stopped it.
    reset();
    d = make();
    if (d) DECODE(d, clip[0].data, clip[0].size, 0, on_out, NULL);
    sleep_for(10000000000ull);
    fault.schedule = 3;
    int dl = d ? DECODE(d, clip[1].data, clip[1].size, 1, on_out, NULL) : -1;
    fault.schedule = 0;
    int stopped = 0, iters = 0;
    for (; d && dl == 0 && iters < 1000 && !stopped; iters++)
      stopped = DECODE(d, clip[1].data, clip[1].size, iters, on_out, NULL) != 0;
    expect(
        "with no key frame after a failure the frames are dropped up to the "
        "limit, then the session stops as a device failure",
        d && dl == 0 && stopped && FAILURE(d) == FAIL_DEVICE);
    if (d) DESTROY(d);
    expect("and it still releases everything, only the dropped driver left",
           closed_after_rebuild(1));
  }

  // A rebuild that fails is the case the refusal is left for.
  reset();
  d = make();
  if (d) DECODE(d, frame0, frame0Size, 0, on_out, NULL);
  sleep_for(10000000000ull);
  fault.rebuildFail = true;
  int rf = d ? DECODE(d, frame0, frame0Size, 1, on_out, NULL) : 0;
  printf("     rebuild failure: %s\n", d ? LASTERR(d) : "");
  fault.rebuildFail = false;
  expect("a rebuild that fails stops the session, as PR 160 did",
         d && rf != 0 && FAILURE(d) == FAIL_DEVICE);
  int rf2 = d ? DECODE(d, frame0, frame0Size, 2, on_out, NULL) : 0;
  expect("and later frames fail without opening anything else",
         d && rf2 != 0 && st.creates == 2);
  if (d) DESTROY(d);
  expect("the failed rebuild leaves nothing open, only the dropped driver",
         closed_after_rebuild(1));

  // A new session opens beside one from before the sleep: no process-wide
  // refusal any more, each session rebuilds for itself.
  reset();
  Vcn* before = make();
  sleep_for(10000000000ull);
  int createsB = st.creates;
  Vcn* beside = make();
  expect("a new session opens beside one from before the sleep",
         before && beside && st.creates == createsB + 1);
  int rn = beside ? DECODE(beside, frame0, frame0Size, 0, on_out, NULL) : -1;
  expect("and decodes on its own driver", beside && rn == 0);
  if (beside) DESTROY(beside);
  if (before) closed_quietly(before);

  reset();
  d = make();
  int rn2 = d ? DECODE(d, frame0, frame0Size, 0, on_out, NULL) : -1;
  if (d) DESTROY(d);
  expect("a session opened after the wake decodes and closes fully",
         rn2 == 0 && st.deleteCtx == 1 && st.destroys == 1 && all_released());

  // 13. 0.3.8. A sleep that lands inside a decode call: the frame was on the
  // GPU when the machine slept, and the wait's clock stopped with it, so the
  // frame times out right after the wake. It must be rebuilt at once, not
  // taken for a stuck GPU (0.3.7 stopped the session here).
  reset();
  d = make();
  if (d) DECODE(d, frame0, frame0Size, 0, on_out, NULL);
  fault.hang = true;
  fault.sleepWhileHanging = true;
  int shownS = 0;
  int ds = d ? DECODE(d, frame0, frame0Size, 1, on_out, &shownS) : -1;
  fault.hang = false;
  printf("     sleep inside the decode call: %s\n",
         d && ds ? LASTERR(d) : "rebuilt");
  expect(
      "a sleep inside a decode call rebuilds the session and drops the frame, "
      "with no error",
      d && ds == 0 && shownS == 0 && st.creates == 2);
  int shownS2 = 0;
  int ds2 = d ? DECODE(d, frame0, frame0Size, 2, on_out, &shownS2) : -1;
  expect("and the frame after it decodes on the rebuilt driver",
         d && ds2 == 0 && shownS2 == 1 && st.creates == 2);
  if (d) DESTROY(d);
  expect("and that session closes, only the dropped driver left",
         closed_after_rebuild(1));

  // The quiet rebuild, with the last command finished, closes the old
  // accelerator on the background queue too, never on this thread.
  reset();
  d = make();
  if (d) DECODE(d, frame0, frame0Size, 0, on_out, NULL);
  sleep_for(10000000000ull);
  closeGate = dispatch_semaphore_create(0);  // marks a close on this thread
  int shownQ = 0;
  int dq = d ? DECODE(d, frame0, frame0Size, 1, on_out, &shownQ) : -1;
  bool drainedQ = vcn_teardown_drain(10000);
  if (drainedQ) dispatch_release(closeGate);
  closeGate = NULL;
  expect(
      "the rebuild at the restart point closes the old accelerator on the "
      "background queue, not on the decoding thread",
      d && dq == 0 && shownQ == 1 && drainedQ && st.creates == 2 &&
          st.destroys == 1 && !st.destroyOnMain && st.deleteCtx == 0);
  if (d) DESTROY(d);
  expect("and that session closes fully, only the dropped driver left",
         closed_after_rebuild(1));

  // The 15 s limit covers the first command on the rebuilt session too.
  reset();
  d = make();
  if (d) DECODE(d, frame0, frame0Size, 0, on_out, NULL);
  sleep_for(10000000000ull);
  vcn_wake_command_timeout_ms = 1500;
  fault.hangMs = 1200;  // finishes, but after the usual 1 s limit
  int shownG = 0;
  int dg = d ? DECODE(d, frame0, frame0Size, 1, on_out, &shownG) : -1;
  printf("     the first frame on the rebuilt session: %s\n",
         d && dg ? LASTERR(d) : "decoded");
  expect(
      "the first command on the rebuilt session is still waited for up to the "
      "wake limit, so a slow one does not stop a healthy session",
      d && dg == 0 && shownG == 1 && st.creates == 2);
  int dg2 = d ? DECODE(d, frame0, frame0Size, 2, on_out, &shownG) : -1;
  printf("     a slow command after the first one: %s\n", d ? LASTERR(d) : "");
  expect("and the usual limit is back once one has finished",
         d && dg2 != 0 && FAILURE(d) == FAIL_DEVICE);
  fault.hangMs = 0;
  vcn_wake_command_timeout_ms = VCN_WAKE_COMMAND_TIMEOUT_MS;
  if (d) DESTROY(d);
  // The stuck close runs on the background queue: wait for it before looking.
  bool drainedG = vcn_teardown_drain(10000);
  expect("and the session it stopped still releases everything",
         drainedG && st.liveAccels == 0 && !st.useAfterDestroy);

  // The restart points the stream may send with no key frame at all.
#if defined(VCN_AV1_RESTART_PREDICATE) || defined(VCN_VP9_RESTART_PREDICATE)
  {
#if defined(TEST_AV1)
    AV1Frame f;
    memset(&f, 0, sizeof(f));
    f.frame_type = AV1_KEY_FRAME;
    f.refresh_frame_flags = 0xFF;
    bool key = vcnav1_is_restart(&f, AV1_PARSE_FRAME_READY);
    f.frame_type = AV1_INTRA_ONLY_FRAME;
    bool intraAll = vcnav1_is_restart(&f, AV1_PARSE_FRAME_READY);
    f.refresh_frame_flags = 0x7F;
    bool intraHalf = vcnav1_is_restart(&f, AV1_PARSE_FRAME_READY);
    f.refresh_frame_flags = 0xFF;
    f.frame_type = AV1_INTER_FRAME;
    bool inter = vcnav1_is_restart(&f, AV1_PARSE_FRAME_READY);
    bool other = vcnav1_is_restart(&f, AV1_PARSE_SHOW_EXISTING);
    expect("AV1 restarts at a key frame", key);
    expect(
        "not at an intra-only frame, which the spec never lets refresh all "
        "eight slots",
        !intraAll && !intraHalf);
    expect("nor at an inter frame, nor at show_existing", !inter && !other);
#else
    VP9Frame f;
    memset(&f, 0, sizeof(f));
    f.frame_type = 1;
    f.intra_only = 1;
    f.refresh_frame_flags = 0xff;
    f.reset_frame_context = 2;
    bool ctxAll = vcnvp9_is_restart(&f, VP9_PARSE_DECODE);
    f.reset_frame_context = 1;
    bool ctxOne = vcnvp9_is_restart(&f, VP9_PARSE_DECODE);
    f.error_res = 1;
    f.reset_frame_context = 3;
    bool errRes = vcnvp9_is_restart(&f, VP9_PARSE_DECODE);
    f.frame_type = 0;
    bool key = vcnvp9_is_restart(&f, VP9_PARSE_DECODE);
    expect(
        "VP9 does not restart at an intra-only frame with "
        "reset_frame_context 2, which resets one context",
        !ctxAll);
    expect("and at one with error_resilient mode and reset_frame_context 3",
           errRes);
    expect("not at one that resets no context", !ctxOne);
    expect("and at a key frame", key);
#endif
  }
#else
  printf(
      "SKIP the restart predicate is not exposed in this tree (0.3.7 takes "
      "key frames only)\n");
#endif

  clip_clear();
  if (argc >= 3) hidden_frames(argv[2]);
#if defined(TEST_VP9)
  if (argc == 5) scaled_references(argv[3], argv[4]);
#endif

  free(frame0);
  return failures ? 1 : 0;
}
