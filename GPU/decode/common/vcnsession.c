// The part of a decoder session that only talks to the driver through its
// function pointers: the wait for a command, opening and closing the
// accelerator, driver and bitstream pool, and what a system sleep does to a
// session. See vcndriver.h.
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "vcndriver.h"

static double wait_now_ms(void) {
  static mach_timebase_info_data_t tb;
  if (!tb.denom) mach_timebase_info(&tb);
  return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

static int query_once(AVD_QueryAVDCommandStatus_fn query, void* driver,
                      void* refcon, uint32_t wait, AVD_QueryEntry* qe) {
  // +8 stays 1, the value sent before it was known to be unused.
  *qe = (AVD_QueryEntry){.refcon = refcon, .unused8 = 1, .wait = wait};
  AVD_QueryList ql = {.count = 1, .entries = qe};
  return query(driver, &ql);
}

VcnWaitResult vcn_wait_command(AVD_QueryAVDCommandStatus_fn query, void* driver,
                               void* refcon, unsigned timeoutMs,
                               uint32_t* hwStatus, int* driverStatus) {
  *hwStatus = 0;
  *driverStatus = 0;
  const double start = wait_now_ms();
  AVD_QueryEntry qe;
  for (;;) {
    int r = query_once(query, driver, refcon, 0, &qe);
    if (r) {
      *driverStatus = r;
      return VCN_WAIT_FAILED;
    }
    if (qe.status == 1) break;
    if (qe.status != 2) {
      *driverStatus = (int)qe.status;
      return VCN_WAIT_FAILED;
    }
    if (wait_now_ms() - start >= timeoutMs) return VCN_WAIT_TIMEOUT;
    // A frame takes milliseconds; a quarter of one between looks adds little
    // latency and keeps the thread asleep most of the time.
    usleep(250);
  }
  // Done: the blocking form now returns at once, runs the driver's steps after
  // a decode and reports the firmware's result.
  int r = query_once(query, driver, refcon, 1, &qe);
  if (r) {
    *driverStatus = r;
    return VCN_WAIT_FAILED;
  }
  *hwStatus = qe.status2;
  return VCN_WAIT_DONE;
}

#define FN(name) ((AVD_##name##_fn)s->accel->fn[AVD_FN_##name])

unsigned vcn_wake_command_timeout_ms = VCN_WAKE_COMMAND_TIMEOUT_MS;

bool vcn_slept_between(const VcnSleepMark* then, const VcnSleepMark* now) {
  if (now->asleepNs > then->asleepNs + 1000000) return true;
  if (then->wakeUs && now->wakeUs && then->wakeUs != now->wakeUs) return true;
  // The wall clock counts through a sleep even when the kernel counted none of
  // it, and mach_absolute_time does not: the two running apart by more than a
  // second is a sleep neither of the other signals saw. A wall clock set back
  // (NTP, a manual change) makes the difference negative and is not a sleep; a
  // clock set forward is, which is the safe direction.
  if (then->wallUs && now->wallUs) {
    int64_t wallUs = now->wallUs - then->wallUs;
    int64_t monoUs = (int64_t)(now->monoNs - then->monoNs) / 1000;
    if (wallUs - monoUs > 1000000) return true;
  }
  return false;
}

bool vcn_session_lost(VcnDriverSession* s) {
  if (s->lost) return true;
  if (!s->accel) return false;
  VcnSleepMark now;
  vcn_sleep_mark(&now);
  if (!vcn_slept_between(&s->opened, &now)) return false;
  s->lost = true;
  os_log_error(s->log,
               "the system slept since this session opened (%.1f s asleep in "
               "between)",
               now.asleepNs > s->opened.asleepNs
                   ? (double)(now.asleepNs - s->opened.asleepNs) / 1e9
                   : 0.0);
  return true;
}

// The open sessions of this plug-in, and how the plug-ins of a process count
// each other's sessions from before a sleep. Each plug-in bundle has its own
// copy of this file. They meet in the process's local notification center,
// which calls every observer, in every image, on the posting thread before the
// post returns.
static pthread_mutex_t g_open_lock = PTHREAD_MUTEX_INITIALIZER;
static VcnDriverSession* g_open;

static void list_open(VcnDriverSession* s) {
  pthread_mutex_lock(&g_open_lock);
  s->nextOpen = g_open;
  g_open = s;
  s->listed = true;
  pthread_mutex_unlock(&g_open_lock);
}
static void unlist(VcnDriverSession* s) {
  if (!s->listed) return;
  pthread_mutex_lock(&g_open_lock);
  for (VcnDriverSession** p = &g_open; *p; p = &(*p)->nextOpen)
    if (*p == s) {
      *p = s->nextOpen;
      break;
    }
  s->listed = false;
  pthread_mutex_unlock(&g_open_lock);
}

#define STALE_QUERY CFSTR("com.droga.vcn.sessions-from-before-a-sleep")
typedef struct {
  VcnSleepMark now;
  int stale;
} StaleQuery;

// One plug-in's answer: how many of its open sessions opened before a sleep.
static void count_stale(CFNotificationCenterRef center, void* observer,
                        CFNotificationName name, const void* object,
                        CFDictionaryRef info) {
  (void)center, (void)observer, (void)name, (void)object;
  CFNumberRef n = info ? CFDictionaryGetValue(info, CFSTR("query")) : NULL;
  int64_t addr = 0;
  if (!n || CFGetTypeID(n) != CFNumberGetTypeID() ||
      !CFNumberGetValue(n, kCFNumberSInt64Type, &addr) || !addr)
    return;
  StaleQuery* q = (StaleQuery*)(intptr_t)addr;
  pthread_mutex_lock(&g_open_lock);
  for (VcnDriverSession* s = g_open; s; s = s->nextOpen)
    if (vcn_slept_between(&s->opened, &q->now)) q->stale++;
  pthread_mutex_unlock(&g_open_lock);
}

static void pin_this_image(void);

// Sessions of this process, in every plug-in, opened before a sleep and still
// open; -1 when the question could not be asked.
static int stale_sessions(const VcnSleepMark* now) {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    // The observer is called from other plug-ins: this image must stay.
    pin_this_image();
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetLocalCenter(), (const void*)&g_open, count_stale,
        STALE_QUERY, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
  });
  StaleQuery q = {.now = *now};
  int64_t addr = (int64_t)(intptr_t)&q;
  CFNumberRef n = CFNumberCreate(NULL, kCFNumberSInt64Type, &addr);
  const void* k[] = {CFSTR("query")};
  const void* v[] = {n};
  CFDictionaryRef info =
      n ? CFDictionaryCreate(NULL, k, v, 1, &kCFTypeDictionaryKeyCallBacks,
                             &kCFTypeDictionaryValueCallBacks)
        : NULL;
  if (n) CFRelease(n);
  if (!info) return -1;
  CFNotificationCenterPostNotification(CFNotificationCenterGetLocalCenter(),
                                       STALE_QUERY, NULL, info, true);
  CFRelease(info);
  return q.stale;
}

// Shared by open and reopen. `rebuild` keeps the session in this plug-in's
// list of open sessions (it is replacing one, not adding one) and skips the
// question asked of the other plug-ins, which was for a new session opened
// beside a stale one; a rebuild is the answer to that case now.
static bool open_session(VcnDriverSession* s, const VcnDriverLib* lib,
                         io_service_t svc, os_log_t log, bool rebuild,
                         char* err, size_t errLen) {
  bool listed = s->listed;
  VcnDriverSession* nextOpen = s->nextOpen;
  *s = (VcnDriverSession){.destroy = lib->destroy, .svc = svc, .log = log};
  if (rebuild) {
    // Already in the list: keep it there (close unlists it if this fails).
    s->listed = listed;
    s->nextOpen = nextOpen;
  }
  // Before anything is opened: a sleep during the open loses the session too.
  vcn_sleep_mark(&s->opened);
  if (!s->opened.wakeKnown) {
    // Not fatal: the other two signals still count. Said once, because in a
    // sandbox it is the expected case (container.sb lists kern.waketime by
    // name, so a profile stricter than that one refuses it) and the value is
    // never read later, which used to be invisible.
    static bool told;
    if (!__atomic_exchange_n(&told, true, __ATOMIC_RELAXED))
      os_log_error(log,
                   "kern.waketime is not readable in this process: a sleep is "
                   "noticed through the monotonic and wall clocks only");
  }
#define FAIL(...)                       \
  do {                                  \
    snprintf(err, errLen, __VA_ARGS__); \
    vcn_session_close(s);               \
    return false;                       \
  } while (0)
  // Other sessions of this process from before a sleep are only counted now: a
  // new session opens beside them and each one rebuilds for itself, which is
  // what stops a paused tab from turning hardware decode off for the process
  // (F3 of the review). A rebuild does not ask at all.
  int stale = rebuild ? 0 : stale_sessions(&s->opened);
  if (stale < 0) {
    // The question could not be asked (no memory for the dictionary). Fail
    // open, as a decoder must, but say so once: this is the one case where
    // the guard is not in force.
    static bool toldQuery;
    if (!__atomic_exchange_n(&toldQuery, true, __ATOMIC_RELAXED))
      os_log_error(log,
                   "could not ask the other plug-ins for sessions from before "
                   "a sleep: this session opens beside them");
  }
  if (stale > 0) {
    // Once per process: the count is a diagnostic, not a refusal any more.
    static bool toldStale;
    if (!__atomic_exchange_n(&toldStale, true, __ATOMIC_RELAXED))
      os_log_error(log,
                   "%d session(s) of this process from before a system sleep "
                   "are still open: this one opens beside them and rebuilds "
                   "for itself if it needs to",
                   stale);
  }
  if (!lib->destroy) {
    // Said once per process: every session would say the same.
    static bool told;
    if (!__atomic_exchange_n(&told, true, __ATOMIC_RELAXED))
      os_log_error(log,
                   "AMDRadeonVADriver2 build %{public}s has no "
                   "AVD_DestroyAVDAccelerator: each session leaves its "
                   "accelerator open",
                   lib->uuid);
  }
  // One service, and the mask says so. The driver opens services[index] and
  // reads no other entry (avd.h, AVD_AcceleratorCreate).
  uint32_t services[1] = {svc};
  AVD_AcceleratorCreate ac = {
      .index = 0, .services = services, .validMask = 1u << 0};
  uint8_t info[256] = {0};
  int r = lib->create(&s->accel, &ac, info);
  if (r || !s->accel) {
    // Nothing to destroy: on every failure the driver frees the accelerator
    // itself and leaves the result NULL (read in IDA, see avd.h). A result
    // set anyway is not one this call made.
    s->accel = NULL;
    FAIL("CreateAVDAccelerator %d", r);
  }
  AVD_DriverCreate dc = {.initFlags = 0, .accel = s->accel};
  r = FN(CreateDriver)(&s->drv, &dc);
  if (r || !s->drv) {
    // Nothing to delete: a failed CreateDriver returns no handle, and what it
    // made stays inside the driver (read in IDA, see avd.h). The accelerator
    // is still destroyed by the close below.
    s->drv = NULL;
    FAIL("CreateDriver %d", r);
  }
  AVD_BitstreamPool pool = {.type = 0,
                            .size = VCN_BS_SIZE,
                            .format = 0x72617762,
                            .one = 1,
                            .count = VCN_NUM_BS,
                            .addressesOut = s->bsAddr,
                            .eight = 8,
                            .five = 5};
  r = FN(AllocateBitstreamBufferPool)(s->drv, &pool);
  if (r) FAIL("AllocateBitstreamBufferPool %d", r);
  s->poolAllocated = true;
  // Frames go to the buffers in turn: every one of them must be there.
  for (int i = 0; i < VCN_NUM_BS; i++)
    if (!s->bsAddr[i]) FAIL("AllocateBitstreamBufferPool: no buffer %d", i);
#undef FAIL
  if (!rebuild) list_open(s);
  return true;
}

bool vcn_session_open(VcnDriverSession* s, const VcnDriverLib* lib,
                      io_service_t svc, os_log_t log, char* err,
                      size_t errLen) {
  return open_session(s, lib, svc, log, false, err, errLen);
}

bool vcn_session_reopen(VcnDriverSession* s, const VcnDriverLib* lib,
                        io_service_t svc, os_log_t log, char* err,
                        size_t errLen) {
  return open_session(s, lib, svc, log, true, err, errLen);
}

// Takes the accelerator and the service out of s and forgets the rest of the
// driver objects (see vcn_session_drop); the session stays listed.
static void detach(VcnDriverSession* s, AVD_Accelerator** accel,
                   io_service_t* svc) {
  *accel = s->accel;
  *svc = s->svc;
  s->accel = NULL;
  s->drv = NULL;
  s->ctx = NULL;
  s->poolAllocated = false;
  memset(s->bsAddr, 0, sizeof(s->bsAddr));
  s->svc = 0;
}

void vcn_session_drop(VcnDriverSession* s) {
  if (!s->accel) return;
  // No DeleteContexts, FreeBitstreamBufferPool or DeleteDriver: those send the
  // engine a command for a session it has forgotten and wait with no limit.
  AVD_Accelerator* accel;
  io_service_t svc;
  detach(s, &accel, &svc);
  if (s->destroy) s->destroy(accel);
  if (svc) IOObjectRelease(svc);
}

void vcn_session_drop_later(VcnDriverSession* s, const char* what,
                            void (^after)(void)) {
  AVD_Accelerator* accel;
  io_service_t svc;
  detach(s, &accel, &svc);
  AVD_DestroyAVDAccelerator_fn destroy = s->destroy;
  // vcn_teardown copies the block, and with it `after`.
  vcn_teardown(true, false, s->log, what, ^{
    if (accel && destroy) destroy(accel);
    // Released only after the driver is gone: it may hold on to the service.
    if (svc) IOObjectRelease(svc);
    if (after) after();
  });
}

// Skipping the driver's own teardown keeps this close from waiting on a command
// for a session the engine has forgotten, but it does not make it a
// non-blocking call: AVD_DestroyAVDAccelerator below still closes three IOKit
// user clients, and on the kernel side a context stop goes through PowerPlay's
// notify (escape 0x34), which can wait after a failed wake. That is why a lost
// or stuck session is closed on the teardown queue (vcn_teardown) and never on
// the caller's thread.
void vcn_session_close(VcnDriverSession* s) {
  // Asked here too: a session can be closed without having been asked since
  // the wake (a paused video that is closed after it).
  bool lost = vcn_session_lost(s);
  if (s->accel) {
    if (s->drv && !lost) {
      if (s->ctx) {
        void* ctxs[1] = {s->ctx};
        AVD_DriverContextDelete del = {.count = 1, .contexts = ctxs};
        FN(DeleteContexts)(s->drv, &del);
      }
      if (s->poolAllocated) FN(FreeBitstreamBufferPool)(s->drv, 0);
      FN(DeleteDriver)(s->drv);
    }
    if (s->destroy) s->destroy(s->accel);
    if (lost) {
      // What the skipped teardown leaves behind, and how much of it this
      // process has left behind so far: the driver's pool and context go with
      // the driver handle, which is never deleted here. Accounting only; the
      // fix is a process that does not sleep with sessions open.
      static long lostCloses;
      long n = __atomic_add_fetch(&lostCloses, 1, __ATOMIC_RELAXED);
      os_log_error(
          s->log,
          "session from before the sleep closed without the driver's own "
          "teardown: %ld so far in this process, up to %lld MiB of the "
          "driver's bitstream pool and its context not returned%{public}s",
          n, (long long)n * VCN_NUM_BS * VCN_BS_SIZE / (1024 * 1024),
          s->destroy ? ""
                     : " (this driver build has no "
                       "AVD_DestroyAVDAccelerator: it stays open)");
    }
  }
  // Out of the list only now: until the accelerator is closed, the session
  // still counts as open for a new one.
  unlist(s);
  // Released only after the driver is gone: it may hold on to the service.
  if (s->svc) IOObjectRelease(s->svc);
  os_log_t log = s->log;
  *s = (VcnDriverSession){.log = log};
}

// Every close handed to the background queue, so that a tool can wait for
// them with a limit.
static dispatch_group_t teardown_group;

static dispatch_queue_t teardown_queue(void) {
  static dispatch_queue_t q;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    q = dispatch_queue_create("com.droga.vcn.teardown",
                              dispatch_queue_attr_make_with_qos_class(
                                  DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    teardown_group = dispatch_group_create();
    // A close may still run after the host is done with the plug-in. If the
    // host unloaded the bundle by then, the queue would run code that is gone:
    // this image stays loaded for the life of the process.
    pin_this_image();
  });
  return q;
}

static void pin_this_image(void) {
  Dl_info info;
  if (dladdr((const void*)vcn_teardown, &info) && info.dli_fname)
    dlopen(info.dli_fname, RTLD_NOW | RTLD_NOLOAD | RTLD_NODELETE);
}

void vcn_teardown(bool stuck, bool lost, os_log_t log, const char* what,
                  void (^close)(void)) {
  if (!stuck && !lost) {
    close();
    return;
  }
  // Kept for the line after the close, which runs once the caller is gone.
  char* name = strdup(what ? what : "session");
  os_log_error(
      log,
      "%{public}s: %{public}s; closing the session on a background "
      "thread, the close may wait for the GPU",
      name ? name : "session",
      stuck ? "a command never finished" : "the system slept since it opened");
  dispatch_queue_t q = teardown_queue();  // also makes the group
  // dispatch_group_async copies this block, and with it close.
  dispatch_group_async(teardown_group, q, ^{
    double t0 = wait_now_ms();
    close();
    os_log_error(log, "%{public}s: %{public}s session closed after %.0f ms",
                 name ? name : "session", stuck ? "stuck" : "lost",
                 wait_now_ms() - t0);
    free(name);
  });
}

bool vcn_teardown_drain(unsigned timeoutMs) {
  teardown_queue();
  return !dispatch_group_wait(
      teardown_group,
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)timeoutMs * NSEC_PER_MSEC));
}
