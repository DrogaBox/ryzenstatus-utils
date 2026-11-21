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
//      released, without a read through it.
//
// usage: sessiontest <first frames of a small IVF clip of the codec>
// Exit status 0 = pass.
#include <IOKit/IOKitLib.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "vcndriver.h"

#if defined(TEST_AV1)
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
static void on_out(void* c, CVPixelBufferRef f, const AV1Parser* p, int64_t t) {
  (void)c, (void)f, (void)p, (void)t;
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
static void on_out(void* c, CVPixelBufferRef f, const VP9Parser* p, uint32_t w,
                   uint32_t h, int64_t t) {
  (void)c, (void)f, (void)p, (void)w, (void)h, (void)t;
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
} fault;

enum { kFakeBuffer = 1 << 20 };  // larger than any frame of the test clips
typedef struct {
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

static int f_create_driver(void** out, AVD_DriverCreate* dc) {
  st.createDrivers++;
  if (((FakeAccel*)dc->accel)->destroyed) st.useAfterDestroy = true;
  if (fault.createDriver) return fault.createDriver;
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
  *out = raw;
  return 0;
}
static FakeDrv* drv_of(void* h) { return ((void**)h)[0]; }
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

static void hung(int sig) {
  (void)sig;
  static const char msg[] = "FAIL a test hung\n";
  write(1, msg, sizeof(msg) - 1);
  _exit(1);
}

int main(int argc, char** argv) {
  if (argc != 2 || !read_first_frame(argv[1])) {
    fprintf(stderr, "usage: sessiontest <small IVF clip of the codec>\n");
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

  free(frame0);
  return failures ? 1 : 0;
}
