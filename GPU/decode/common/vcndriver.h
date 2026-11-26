// What the AV1 and the VP9 session share about Apple's AMD video driver: which
// accelerator to hand it, which build of it is loaded, and how a driver
// session is opened, waited on and closed.
//
// vcndriver.c holds what talks to the system (IOKit, dyld); vcnsession.c holds
// the rest, which only calls the driver through the pointers it is given, so a
// test can hand it a made-up driver.
#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <os/log.h>
#include <stdbool.h>

#include "avd.h"

// True when an accelerator's IOGVACodec property names an AMD codec. AMD's
// names start with "AMD" (Navi 21: "AMDVCN2"); Intel's integrated graphics
// publish one too ("Gen95").
bool vcn_codec_is_amd(CFTypeRef codec);

// The first IOAccelerator whose codec is AMD's, or 0. The caller releases it.
io_service_t vcn_find_accelerator(void);

// Writes the LC_UUID of the AMDRadeonVADriver2 image loaded in this process as
// 32 upper-case hex digits. False when the driver is not loaded.
bool vcn_driver_uuid(char out[33]);

// The driver's two exported entry points, and which build it is.
typedef struct {
  AVD_CreateAVDAccelerator_fn create;
  // NULL when this build does not export it: the accelerator is then left
  // open, as before 0.3.3.
  AVD_DestroyAVDAccelerator_fn destroy;
  char uuid[33];  // "unknown" when it could not be read
} VcnDriverLib;

// Loads AMDRadeonVADriver2 into this process (once; later calls only look the
// symbols up again) and fills lib. False, with err set, when the driver or its
// create function is missing.
bool vcn_driver_load(VcnDriverLib* lib, char* err, size_t errLen);

// How long one decode command may take before the session gives up on it. A 4K
// frame takes 5-60 ms on Navi 21, even at the video engine's lowest clock.
enum { VCN_COMMAND_TIMEOUT_MS = 1000 };

// A system sleep, as a session sees it. Apple's kernel driver keeps a decoder's
// video context across a sleep, but stops the video engine before it and starts
// it again at wake, and saves nothing of the session on the engine
// (AMDRadeonX6000, 26.7.3 KDK, read in IDA: systemWillSleep stops the VCN rings
// once their last command finished, powerUpHW and internalDidWake start them
// again, saveVCNSession is empty). Nothing in the driver, AppleGVA or
// VideoToolbox tells a decoder about it. A session opened before a sleep is
// therefore never used again: it decodes nothing more, and closing it skips the
// driver's own teardown, which would send the engine a command for that session
// and wait for it with no time limit (vcn_session_close).
//
// The mark is the time this Mac has spent asleep since it started, as the
// kernel counts it (mach_continuous_time runs on during a sleep,
// mach_absolute_time does not), the time of the last wake (kern.waketime), and
// the wall clock read next to mach_absolute_time. Any of the three changing
// means the system slept. The third is there for a machine whose sleep path
// skips the kernel's wake accounting, where the first signal never moves, and
// whose kern.waketime is refused inside the sandbox, where the second one is
// dead: the RTC counts through a sleep even when the kernel counted none of it,
// so a wall clock that ran ahead of mach_absolute_time is a sleep the other two
// would miss. None of the three needs a notification, which a
// decoder could not get anyway: VideoToolbox's decoder service is sandboxed
// without the root power domain's user client that IORegisterForSystemPower
// opens (VTDecoderSandboxProfile.sb).
typedef struct {
  uint64_t asleepNs;  // time asleep since boot
  int64_t wakeUs;     // last wake in microseconds since 1970; 0 when unknown
  bool wakeKnown;     // kern.waketime could be read (its value may still be 0)
  uint64_t monoNs;    // mach_absolute_time at the same reading, in ns
  int64_t wallUs;     // that same moment on the wall clock, us since 1970
} VcnSleepMark;

// Reads all of it now (vcndriver.c: it asks the system). kern.waketime is a
// sysctl and the codecs ask for a mark on every frame, so that one value is
// reused for 100 ms of mach_absolute_time; a sleep is still noticed at once
// through the time asleep.
void vcn_sleep_mark(VcnSleepMark* m);

// True when the system has slept between `then` and `now`: the time asleep
// moved by more than 1 ms (the error of a reading, not a sleep: a real one
// takes seconds), the wake time is two different non-zero values, or the wall
// clock ran more than a second ahead of mach_absolute_time (see above).
bool vcn_slept_between(const VcnSleepMark* then, const VcnSleepMark* now);

typedef enum {
  VCN_WAIT_DONE = 0,     // finished; *hwStatus = firmware result, 0 = no error
  VCN_WAIT_TIMEOUT = 1,  // still running after timeoutMs: the GPU is stuck
  VCN_WAIT_FAILED = -1,  // the query failed; *driverStatus says how
} VcnWaitResult;

// Waits for one command that ScheduleAVDCommands accepted (refcon is what it
// wrote back), at most timeoutMs. The driver's own blocking wait has no
// timeout in user space, so this polls without blocking, then makes one
// blocking call once the command is done; that call returns at once with the
// firmware's result. On VCN_WAIT_FAILED, *driverStatus is the driver's return
// value, or, when the driver returned 0, the unexpected status it reported.
VcnWaitResult vcn_wait_command(AVD_QueryAVDCommandStatus_fn query, void* driver,
                               void* refcon, unsigned timeoutMs,
                               uint32_t* hwStatus, int* driverStatus);

// The bitstream pool both codecs use: four buffers of 24 MiB, used in turn.
enum { VCN_NUM_BS = 4 };
#define VCN_BS_SIZE 0x1800000u

// One accelerator, one driver and its bitstream pool: what a decoder session
// holds of the driver. The codec adds its context (ctx) itself.
typedef struct VcnDriverSession {
  AVD_DestroyAVDAccelerator_fn destroy;
  AVD_Accelerator* accel;
  void* drv;
  void* ctx;  // set by the codec after CreateContexts; deleted by close
  void* bsAddr[VCN_NUM_BS];
  io_service_t svc;  // the accelerator service; released by close
  bool poolAllocated;
  VcnSleepMark opened;  // taken when open began
  bool lost;            // the system slept since: see vcn_session_lost
  bool listed;  // in this plug-in's list of open sessions (vcnsession.c)
  struct VcnDriverSession* nextOpen;
  os_log_t log;
} VcnDriverSession;

// Opens the accelerator on svc, a driver on it and the bitstream pool. svc is
// taken over: close releases it, and so does a failed open. On failure every
// part opened so far is closed again, s is left empty and err says which call
// failed.
//
// It counts, once per process, the sessions of this process that opened before
// a system sleep and are still open in any of the plug-ins (they ask each
// other through the process's local notification center). It no longer refuses
// because of them: those sessions rebuild for themselves now, and refusing
// would turn a paused tab into no hardware decode in the whole process (F3 of
// the review). A reported
// hang began exactly so: two VP9 sessions of a browser's decoder process stayed
// open across a sleep, and the AV1 session the same process opened after the
// wake never decoded a frame. That is why a decoder session does not fail when
// it finds the system slept: it rebuilds its driver side (vcn_session_reopen)
// and drops frames until a key frame, so the host's decoder object lives on and
// never sees a malfunction. What is left of the refusal below is the case where
// the rebuild itself fails.
bool vcn_session_open(VcnDriverSession* s, const VcnDriverLib* lib,
                      io_service_t svc, os_log_t log, char* err, size_t errLen);

// Opens the driver side of a session that replaces one the system slept
// through: the same work without the check for other sessions of the process
// from before the sleep (this one is being replaced, not added beside them),
// and it clears `lost`, because what it opens is from after the wake. The
// session stays in this plug-in's list of open ones.
bool vcn_session_reopen(VcnDriverSession* s, const VcnDriverLib* lib,
                        io_service_t svc, os_log_t log, char* err,
                        size_t errLen);

// Drops the driver objects of a lost session without telling the driver
// anything: AVD_DestroyAVDAccelerator (that is what closes the IOKit clients)
// and the service. The driver handle, its context and the bitstream pool are
// left where they are, because only the driver can free them and it may be
// wedged after a wake (F4 of the review); a rebuild leaks that once per sleep
// and starts a new pool. The session stays listed as open.
void vcn_session_drop(VcnDriverSession* s);

// True once the system has slept since s opened (see VcnSleepMark), and from
// then on; the first time, it says so in the log. A codec that finds this
// rebuilds its driver side (vcnav1.c / vcnvp9.c: vcn_session_drop then
// vcn_session_reopen) and drops frames until a key frame; only a rebuild that
// fails stops the session, with kVTVideoDecoderMalfunctionErr (-12911), which
// is PR 160's behaviour. A session with no accelerator is never lost.
bool vcn_session_lost(VcnDriverSession* s);

// Closes what open (and the codec's CreateContexts) made, in the order Apple's
// own decoders use: DeleteContexts, FreeBitstreamBufferPool (only when the pool
// was allocated), DeleteDriver, AVD_DestroyAVDAccelerator, then the service.
// Every step can block in the kernel while a command is still on the GPU.
//
// A lost session (vcn_session_lost) skips the first three. DeleteContexts, and
// DeleteDriver for a context still open, send the engine a destroy command for
// the session and wait for it with no time limit (AMDRadeonVADriver2:
// VADecoder::Terminate -> DestroyDecodeSession -> waitForCurrentEvent), for a
// session the engine lost at wake; the pool's textures may wait for a command
// the wake dropped. Only AVD_DestroyAVDAccelerator runs: it closes the
// accelerator's device, shared and video context connections, and the kernel's
// close of a video context sends the engine nothing (AMDRadeonX6000:
// contextStop -> destroyVCNSession -> submitDestroyCommand, which returns at
// once). What the driver allocated in this process stays allocated: nothing
// touches it again.
void vcn_session_close(VcnDriverSession* s);

// Runs close() now, or on a background queue when stuck (a command never
// finished) or lost (the system slept since the session opened), with a log
// line before and after: the teardown may then wait in the kernel, and the
// caller (VideoToolbox's invalidate) must not wait with it. what names the
// session in the log.
void vcn_teardown(bool stuck, bool lost, os_log_t log, const char* what,
                  void (^close)(void));

// Waits until every teardown handed to the background queue has finished, at
// most timeoutMs. False when one is still running: its kernel call may never
// return. For tests and command line tools.
bool vcn_teardown_drain(unsigned timeoutMs);
