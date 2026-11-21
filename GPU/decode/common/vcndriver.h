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
typedef struct {
  AVD_DestroyAVDAccelerator_fn destroy;
  AVD_Accelerator* accel;
  void* drv;
  void* ctx;  // set by the codec after CreateContexts; deleted by close
  void* bsAddr[VCN_NUM_BS];
  io_service_t svc;  // the accelerator service; released by close
  bool poolAllocated;
  os_log_t log;
} VcnDriverSession;

// Opens the accelerator on svc, a driver on it and the bitstream pool. svc is
// taken over: close releases it, and so does a failed open. On failure every
// part opened so far is closed again, s is left empty and err says which call
// failed.
bool vcn_session_open(VcnDriverSession* s, const VcnDriverLib* lib,
                      io_service_t svc, os_log_t log, char* err, size_t errLen);

// Closes what open (and the codec's CreateContexts) made, in the order Apple's
// own decoders use: DeleteContexts, FreeBitstreamBufferPool (only when the pool
// was allocated), DeleteDriver, AVD_DestroyAVDAccelerator, then the service.
// Every step can block in the kernel while a command is still on the GPU.
void vcn_session_close(VcnDriverSession* s);

// Runs close() now, or, when stuck (a command never finished), on a background
// queue, with a log line before and after: the driver's teardown then waits in
// the kernel for that command, and the caller (VideoToolbox's invalidate) must
// not wait with it. what names the session in the log.
void vcn_teardown(bool stuck, os_log_t log, const char* what,
                  void (^close)(void));

// Waits until every teardown handed to the background queue has finished, at
// most timeoutMs. False when one is still running: its kernel call may never
// return. For tests and command line tools.
bool vcn_teardown_drain(unsigned timeoutMs);
