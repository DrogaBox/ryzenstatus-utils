// The part of a decoder session that only talks to the driver through its
// function pointers: the wait for a command, opening and closing the
// accelerator, driver and bitstream pool. See vcndriver.h.
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <mach/mach_time.h>
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

bool vcn_session_open(VcnDriverSession* s, const VcnDriverLib* lib,
                      io_service_t svc, os_log_t log, char* err,
                      size_t errLen) {
  *s = (VcnDriverSession){.destroy = lib->destroy, .svc = svc, .log = log};
#define FAIL(...)                       \
  do {                                  \
    snprintf(err, errLen, __VA_ARGS__); \
    vcn_session_close(s);               \
    return false;                       \
  } while (0)
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
  return true;
}

void vcn_session_close(VcnDriverSession* s) {
  if (s->accel) {
    if (s->drv) {
      if (s->ctx) {
        void* ctxs[1] = {s->ctx};
        AVD_DriverContextDelete del = {.count = 1, .contexts = ctxs};
        FN(DeleteContexts)(s->drv, &del);
      }
      if (s->poolAllocated) FN(FreeBitstreamBufferPool)(s->drv, 0);
      FN(DeleteDriver)(s->drv);
    }
    if (s->destroy) s->destroy(s->accel);
  }
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
    Dl_info info;
    if (dladdr((const void*)vcn_teardown, &info) && info.dli_fname)
      dlopen(info.dli_fname, RTLD_NOW | RTLD_NOLOAD | RTLD_NODELETE);
  });
  return q;
}

void vcn_teardown(bool stuck, os_log_t log, const char* what,
                  void (^close)(void)) {
  if (!stuck) {
    close();
    return;
  }
  // Kept for the line after the close, which runs once the caller is gone.
  char* name = strdup(what ? what : "session");
  os_log_error(log,
               "%{public}s: a command never finished; closing the session on "
               "a background thread, the driver may wait for the GPU",
               name ? name : "session");
  dispatch_queue_t q = teardown_queue();  // also makes the group
  // dispatch_group_async copies this block, and with it close.
  dispatch_group_async(teardown_group, q, ^{
    double t0 = wait_now_ms();
    close();
    os_log_error(log, "%{public}s: stuck session closed after %.0f ms",
                 name ? name : "session", wait_now_ms() - t0);
    free(name);
  });
}

bool vcn_teardown_drain(unsigned timeoutMs) {
  teardown_queue();
  return !dispatch_group_wait(
      teardown_group,
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)timeoutMs * NSEC_PER_MSEC));
}
