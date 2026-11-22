//
//  kern_control.cpp - the GPU control part of GPUSensors.
//
//  1. The boot profile. macOS fixes the power firmware's workload profile at
//     16 (compute) on every Navi 21: the framebuffer copies
//     PP_WorkLoadPolicyMask = 16 onto the GPU when its controller starts, and
//     the power management reads it once when it starts (ppInitialize ->
//     PP_InitializeEX -> PhwNavi21_Initialize). With the boot argument
//     gpuprofile=N (N = 0, 2 or 16), this file sets the property to N on the
//     card right before ppInitialize runs, which is after the framebuffer's
//     copy. 0 is "automatic": the library then uses what its own clients ask
//     for (the video profile while a video session runs, the firmware's
//     default otherwise) instead of replacing it. 2 is power saving. Without
//     the boot argument nothing is set.
//
//  2. Watching. Phw_SwSmu_WorkLoadPolicyManager gets the profile the clients
//     ask for; this file keeps the last one, every bit seen and a count, and
//     passes the call through unchanged.
//
//  3. The power limit, watched (0.4.0). The limit the framebuffer reads
//     (Phw_SwSmu_GetPowerLimit, at boot and after each wake: the first answer
//     is the boot limit), every limit sent to the power firmware
//     (smu_11_0_7_set_power_limit, whoever sends it), and each sleep and wake
//     (AtiPowerPlayServices::ppSleep, ppWake). Each call goes through
//     unchanged.
//
//  4. The power limit, written (0.5.0, design v2). One program at a time may
//     LOWER the limit between the card's floor (200 W until 0.8.0) and the
//     boot limit, in 10 W steps, through
//     the IOUserClient in kern_service.cpp, once an administrator armed the
//     control since restart. Every decision is in control_logic.hpp (tested on
//     the CPU); this file carries them out:
//     - ppInitialize is routed always now (still pass-through) to keep the
//       AtiPowerPlayServices object. The only driver function called is
//       ppCWDDE on it, with two escapes: 0x2a (is the GPU up) before every
//       0x6e (set the package power limit).
//     - Every driver call runs on one kernel thread of this file (the
//       worker), one at a time. The user client's thread hands its request to
//       a single pending slot and waits 5 s at most.
//     - The routed functions store numbers with atomic builtins and take no
//       lock, except ppSleep: before the original runs it sets the sleep
//       flag under gStateLock and waits (3 s at most) for a ppCWDDE call in
//       flight, so no call can interleave with the sleep. ppSleep and ppWake
//       signal the worker's semaphore; set_power_limit records what it saw on
//       the worker's own thread, which confirms each 0x6e. After wake the
//       worker waits for the framebuffer's read of the limit, then 2 s more.
//     - gStateLock is a leaf: held only around Owner and slot updates (and
//       ppSleep's handshake, which sleeps on it, releasing it), never across
//       a driver call, never in a routed function that runs under the
//       PowerPlay lock.
//     - The boot limit goes back when the program asks, closes or crashes,
//       after 30 s without its word, and after a wake that followed a change.
//       A change that is not confirmed sends the boot limit once and turns
//       writing off until restart; so does a way back that fails three times.
//
//  5. OD8, read only (0.6.0, design-od8.md v2 phase A). The worker sends the
//     two escapes that only read the driver's own OD8 data, 0x9f (ranges and
//     defaults) and 0xa0 (current values): 2 s after the framebuffer's first
//     read of the power limit, and again after each wake's margin. Nothing
//     goes to the power firmware. The count word is preset to exactly 38 and
//     a sentinel tells "asleep, nothing written" from data; every entry is
//     checked against report.md 11.3. The first 0x9f is kept as "stock". An
//     answer that does not fit stops the reads until restart. OD8 changes
//     (0xa1) are not in this version.
//
//  6. OD8, written (0.7.0, design-od8-b.md v3.1). Through the same channel
//     and owner rules as the power limit (arm, one program, alive, the way
//     back on release, close, 30 s of silence and after a wake), a program
//     may hold a fan curve with more air than stock, zero RPM off, and a
//     lower GFX maximum (1500 MHz up to stock). Never both a power change and
//     an OD8 change. Each change: fresh 0x9f + 0xa0, every check of
//     control_logic.hpp, the whole 0xa1 built from the wanted state (all ten
//     curve entries in every call; the stock state is the all-ten reset,
//     zero RPM at stock and the GFX pair at stock), sent with the no-replay
//     flag, then both read back and compared, and the driver's replay list
//     must still be empty. A call that fails or reads back wrong is followed
//     by the stock call at once and writing goes off until restart. While a
//     curve is held, a watchdog reads the hotspot and fan once a second from
//     the PMLog copy: too hot with the fan under 90 %, or 95 C, or no
//     readings for 10 s, and the stock call goes out and writing goes off.
//     A curve is only taken while that copy is fresh. Whenever writing goes
//     off with a change maybe still on the card, the stock call gets 3 tries
//     500 ms apart, once; then nothing more is sent.
//
//  7. 0.8.0. disarm (any program) closes writing again without a restart
//     (refused while anything is applied). The power floor is the card's own
//     (PowerRange in control_logic.hpp, from the first clean 0x9f): until it is
//     known no lower limit is taken. An RX 6900 XT (73BF revision C0) is read
//     exactly like the RX 6800 XT (routes, start-up limit, OD8 reads) and
//     writing never opens on it (WriteOff::ReadOnlyCard): set, setOd8 and arm
//     answer "off", and the only escapes it can reach are the read-only 0x9f
//     and 0xa0 (0x2a and 0x6e are sent only by runSet and runRevert, 0xa1 only
//     by od8Commit, and none of them can run; each sender checks again).
//
//  Only on an RX 6800 XT (73BF revision C1) or, read only, an RX 6900 XT (C0),
//  and only when each function starts with the bytes in control_logic.hpp.
//  Writing needs more: an RX 6800 XT, exactly one AMD GPU,
//  AMDRadeonX6000HWLibs, every watcher routed, ppCWDDE as expected.
//  -gpuctloff turns all of this off and leaves the sensors as they were.
//
#include "kern_control.hpp"

#include <IOKit/IOLib.h>
#include <IOKit/IOLocks.h>
#include <IOKit/IOMessage.h>
#include <IOKit/IORegistryEntry.h>
#include <IOKit/IOService.h>
#include <IOKit/pwr_mgt/RootDomain.h>
#include <kern/clock.h>
#include <kern/thread.h>
#include <libkern/OSAtomic.h>
#include <libkern/c++/OSArray.h>
#include <libkern/c++/OSData.h>
#include <libkern/c++/OSDictionary.h>
#include <libkern/c++/OSNumber.h>
#include <libkern/c++/OSString.h>
#include <mach/semaphore.h>
#include <mach/task.h>
#include <pexpert/pexpert.h>

#include <Headers/kern_api.hpp>
#include <Headers/kern_devinfo.hpp>
#include <Headers/kern_iokit.hpp>
#include <Headers/kern_patcher.hpp>
#include <Headers/kern_util.hpp>

#include "control_logic.hpp"
#include "kern_pmlog.hpp"
#include "pmlog_logic.hpp"

namespace {

constexpr size_t kMaxGpus = 4;
IORegistryEntry* gGpus[kMaxGpus]{};  // retained for the whole uptime
size_t gGpuCount{0};                 // readable cards (deviceReadable)
size_t gWritableGpus{0};  // of those, allowed to write (deviceAllowed)
// Set once by findGpus, before the library comes and before any thread of
// this file starts: a readable card that is not allowed is there. Nothing is
// ever written to the GPU while it is true (each sender checks it again).
bool gReadOnlyCard{false};
uint32_t gAmdGpus{0};  // every AMD GPU, allowed or not

bool gOff{false};
bool gAsked{false};  // a valid gpuprofile= was given
uint32_t gAskedValue{0};
bool gRefused{false};     // gpuprofile= was given with a value not allowed
bool gTried{false};       // a library was handled (only one ever is)
bool gScanned{false};     // findGpus ran
bool gScanFailed{false};  // findGpus had no list of devices
bool gMissedScan{false};  // the library came before findGpus
bool gWatching{false};
bool gPPInitRouted{false};

// Set by the routed ppInitialize, read by ioreg readers.
volatile UInt32 gSetCards{0};
volatile UInt32 gSetDone{0};

volatile UInt32 gLastRequest{0};
volatile UInt32 gSeenRequests{0};
volatile SInt64 gRequestCalls{0};

mach_vm_address_t orgPPInit{0};
mach_vm_address_t orgPolicy{0};
mach_vm_address_t orgGetLimit{0};
mach_vm_address_t orgSetLimit{0};
mach_vm_address_t orgSleep{0};
mach_vm_address_t orgWake{0};
// The power watch: which functions are routed, and what they saw.
bool gWatchGet{false}, gWatchSet{false}, gWatchSleep{false}, gWatchWake{false};
// Written in the driver's threads, read by ioreg readers, all with atomic
// builtins. The boot value is (1 << 32 | watts), set once by the first read.
// Each counter is bumped after the values it covers, and readers load the
// counter first, so a count above 0 means its values are already there.
uint64_t gBoot{0};
uint32_t gLastReadW{0};
uint64_t gReads{0};
uint32_t gLastSetW{0};
uint32_t gLastSetSource{0};
uint32_t gLastSetResult{0};
uint64_t gSets{0};
uint32_t gSleeps{0};
uint32_t gWakes{0};

// ---------------------------------------------------------- the write path --
//
// Set by routed functions, with atomic builtins only:
void* gPP{nullptr};         // the first AtiPowerPlayServices, after its init
void* gHwmgr{nullptr};      // the first hwmgr GetPowerLimit was called with
uint32_t gSecondObject{0};  // 1: another object or hwmgr showed up
uint32_t gInSleep{0};       // 1 from ppSleep's start to ppWake's end
uint64_t gSleepGen{0};      // bumped at each ppSleep
uint64_t gReadsAtWake{0};   // gReads right before ppWake ran
thread_t gWorkerThread{nullptr};
// Written by set_power_limit only on the worker's thread, cleared by the
// worker before each 0x6e and read by it after: never shared.
uint32_t gTagCount{0}, gTagW{0}, gTagResult{0};

semaphore_t gSem{nullptr};  // wakes the worker; signalled lock-free
// 1 while a token is in the semaphore (or being taken): signals coalesce, so
// the semaphore never holds more than one and the worker's timed waits wait.
uint32_t gSignalled{0};
mach_vm_address_t gCwdde{0};
bool gX6000{false};

// Under gStateLock (a leaf lock):
IOLock* gStateLock{nullptr};
gpuctl::Owner gOwner;
gpuctl::SetSlot gSlot;
gpuctl::WriteOff gWriteOff{gpuctl::WriteOff::None};
uint64_t gPendingRevert{0};  // the way back the worker has to send, or 0
bool gWorkerUp{false};       // the worker runs and its notifiers are set
bool gTornDown{false};       // no driver call ever again
bool gInFlight{false};       // a ppCWDDE call is running
uint32_t gHeldW{0};          // the confirmed lowered limit, 0 = boot
bool gLimitUnknown{false};   // a failed change was not confirmed back
uint64_t gChanges{0}, gReverts{0};
gpuctl::Reply gLastReply{gpuctl::Reply::Ok};
uint64_t gNextClient{0};
// OD8 writes (0.7.0), also under gStateLock:
bool gOd8Dirty{false};  // OD8 may not be at stock (a change, or unknown)
uint64_t gOd8Held{0};   // kOd8Held* of the confirmed state
gpuctl::Od8Want gOd8HeldWant{};
uint64_t gOd8Changes{0}, gOd8Reverts{0};
gpuctl::Od8Check gOd8LastCheck{gpuctl::Od8Check::Ok};
uint64_t gOd8SentPower{0};  // 0xa1 calls during which a power limit went out
bool gOd8OffAfterWayBack{false};  // the watchdog tripped: off once stock
uint32_t gSlotKind{0};            // 0 power, 1 OD8: what the slot's request is
gpuctl::Od8Want gSlotWant{};
uint32_t gSlotCheck{0};  // the worker's Od8Check for a refused setOd8

const char* gStatus{"waiting for the driver's library"};

// OD8 phase A: what the worker read, under gOd8Lock (a leaf, never held
// across a driver call; ioreg readers build their dictionary under it).
IOLock* gOd8Lock{nullptr};
gpuctl::Od8Read gOd8State{gpuctl::Od8Read::Waiting};
uint32_t gOd8LastRet{0};
uint32_t gOd8OddEntry{0};   // 0, or the first odd entry + 1
uint32_t gOd8OddEscape{0};  // which answer had it
uint32_t gOd8Reads{0};      // complete reads (both escapes)
uint32_t gOd8Tries{0};      // every try, failed ones too
bool gOd8HaveStock{false};  // the first complete 0x9f after boot
gpuctl::Od8InitialOut gOd8Stock{};
bool gOd8HaveCurrent{false};
gpuctl::Od8CurrentOut gOd8Current{};      // the last complete 0xa0
gpuctl::Od8CurrentOut gOd8BootCurrent{};  // the first complete 0xa0
bool gOd8DefaultsMoved{false};            // a later 0x9f differs from the first
bool gOd8StockOdd{false};                 // stock came from an odd 0x9f
gpuctl::Od8InitialOut gOd8Latest{};       // the last complete 0x9f
uint64_t gOd8LastReadMs{0};               // when the last complete read was

using t_ppinit = uint64_t (*)(void*, void*);
using t_policy = uint64_t (*)(void*, uint32_t);
using t_getlimit = uint64_t (*)(void*, uint32_t*);
using t_setlimit = uint64_t (*)(void*, const gpuctl::SetLimit*);
using t_event = uint64_t (*)(void*);
using t_cwdde = uint32_t (*)(void*, const void*, uint32_t, void*, uint32_t*);

uint64_t nowMs() {
  uint64_t ns = 0;
  absolutetime_to_nanoseconds(mach_absolute_time(), &ns);
  return ns / 1000000;
}
uint64_t msToAbs(uint64_t ms) {
  uint64_t abs = 0;
  nanoseconds_to_absolutetime(ms * 1000000, &abs);
  return abs;
}
// Callers change the state first, then signal. Only the 0 -> 1 change of
// gSignalled posts a token; the worker clears it after a wait took that token
// (waitUntil), then looks at the state, so no signal is lost.
void signalWorker() {
  semaphore_t s = __atomic_load_n(&gSem, __ATOMIC_ACQUIRE);
  if (s != nullptr &&
      __atomic_exchange_n(&gSignalled, 1, __ATOMIC_SEQ_CST) == 0)
    semaphore_signal(s);
}
uint32_t bootW() {
  uint64_t boot = __atomic_load_n(&gBoot, __ATOMIC_ACQUIRE);
  return (boot >> 32) != 0 ? static_cast<uint32_t>(boot) : 0;
}

// Runs where the framebuffer starts the power management (thread context,
// before PowerPlay takes its lock), so setting a property is fine here.
uint64_t wrapPPInit(void* self, void* config) {
  // The boot profile changes the card's behaviour: never on a read-only card.
  if (gAsked && gWatching && gGpuCount != 0 && !gReadOnlyCard) {
    UInt32 set = 0;
    for (size_t i = 0; i < gGpuCount; i++)
      if (gGpus[i]->setProperty(gpuctl::kProfileKey,
                                static_cast<unsigned long long>(gAskedValue),
                                32))
        set++;
    gSetCards = set;
    gSetDone = 1;
  }
  uint64_t result = reinterpret_cast<t_ppinit>(orgPPInit)(self, config);
  // The object the control calls ppCWDDE on, kept once its init returned.
  void* none = nullptr;
  if (!__atomic_compare_exchange_n(&gPP, &none, self, false, __ATOMIC_RELEASE,
                                   __ATOMIC_RELAXED) &&
      none != self) {
    __atomic_store_n(&gSecondObject, 1, __ATOMIC_RELEASE);
    signalWorker();  // the worker turns writing off now
  }
  return result;
}

uint64_t wrapPolicy(void* hwmgr, uint32_t mask) {
  gLastRequest = mask;
  OSBitOrAtomic(mask, &gSeenRequests);
  OSIncrementAtomic64(&gRequestCalls);
  return reinterpret_cast<t_policy>(orgPolicy)(hwmgr, mask);
}

// The power watch. These run in the driver's own path. GetPowerLimit and
// set_power_limit (which runs under the PowerPlay lock) only store numbers
// and take no lock; besides the original, set_power_limit only asks which
// thread it runs on (design v2, F6), and GetPowerLimit signals the worker at
// its first read and when it sees a second hwmgr. ppSleep and ppWake signal the
// worker's semaphore (F5), and ppSleep alone also takes gStateLock for the
// sleep handshake: it is entered with no AMD lock held, before the original
// takes the PowerPlay lock (phase 0d, sleep-race section 4).
uint64_t wrapGetLimit(void* hwmgr, uint32_t* watts) {
  uint64_t result = reinterpret_cast<t_getlimit>(orgGetLimit)(hwmgr, watts);
  if (static_cast<uint32_t>(result) == gpuctl::kPPResultOK && watts) {
    uint32_t w = *watts;
    uint64_t none = 0;
    bool first =
        __atomic_compare_exchange_n(&gBoot, &none, (1ULL << 32) | w, false,
                                    __ATOMIC_RELEASE, __ATOMIC_RELAXED);
    __atomic_store_n(&gLastReadW, w, __ATOMIC_RELAXED);
    __atomic_fetch_add(&gReads, 1, __ATOMIC_RELEASE);
    // The first read: the worker reads OD8 2 s later, and turns writing off
    // now if the start-up limit is unbelievable.
    if (first) signalWorker();
  }
  void* known = nullptr;
  if (hwmgr != nullptr &&
      !__atomic_compare_exchange_n(&gHwmgr, &known, hwmgr, false,
                                   __ATOMIC_RELAXED, __ATOMIC_RELAXED) &&
      known != hwmgr) {
    __atomic_store_n(&gSecondObject, 1, __ATOMIC_RELEASE);
    signalWorker();
  }
  return result;
}
uint64_t wrapSetLimit(void* smu, const gpuctl::SetLimit* request) {
  // Read before the call (the request is the caller's), stored after it, so
  // the watts, source and result published always belong to one call.
  bool have = request != nullptr;
  uint32_t w = have ? request->watts : 0;
  uint32_t source = have ? request->source : 0;
  uint64_t result = reinterpret_cast<t_setlimit>(orgSetLimit)(smu, request);
  if (have) {
    __atomic_store_n(&gLastSetW, w, __ATOMIC_RELAXED);
    __atomic_store_n(&gLastSetSource, source, __ATOMIC_RELAXED);
    __atomic_store_n(&gLastSetResult, static_cast<uint32_t>(result),
                     __ATOMIC_RELAXED);
    __atomic_fetch_add(&gSets, 1, __ATOMIC_RELEASE);
    // The worker's own 0x6e: it confirms the send with these.
    thread_t worker = __atomic_load_n(&gWorkerThread, __ATOMIC_ACQUIRE);
    if (worker != nullptr && current_thread() == worker) {
      __atomic_store_n(&gTagW, w, __ATOMIC_RELAXED);
      __atomic_store_n(&gTagResult, static_cast<uint32_t>(result),
                       __ATOMIC_RELAXED);
      __atomic_fetch_add(&gTagCount, 1, __ATOMIC_RELAXED);
    }
  }
  return result;
}
// The sleep handshake (control_logic.hpp, kSleepWaitMs). Before the original
// takes the PowerPlay lock, under gStateLock: the sleep flag is set, then a
// ppCWDDE call already in flight is waited for, 3 s at most. callCwdde checks
// the flag and marks its call in flight under the same lock, so a call either
// ends before the sleep starts (the SMU still fully up) or is never made.
// gInSleep is set before the generation moves, so a worker that sees the new
// generation also sees the sleep. Nothing else here blocks or allocates; the
// log line is only for a call that outlived the 3 s.
uint64_t wrapSleep(void* self) {
  bool late = false;
  IOLock* lock = gStateLock;  // made in init(), before anything is routed
  if (lock != nullptr) IOLockLock(lock);
  __atomic_store_n(&gInSleep, 1, __ATOMIC_SEQ_CST);
  __atomic_fetch_add(&gSleepGen, 1, __ATOMIC_SEQ_CST);
  __atomic_fetch_add(&gSleeps, 1, __ATOMIC_RELAXED);
  if (lock != nullptr) {
    if (gInFlight) {
      uint64_t deadline = 0;
      clock_interval_to_deadline(static_cast<uint32_t>(gpuctl::kSleepWaitMs),
                                 kMillisecondScale, &deadline);
      while (gInFlight)
        if (IOLockSleepDeadline(lock, &gInFlight, deadline, THREAD_UNINT) ==
            THREAD_TIMED_OUT) {
          late = gInFlight;
          break;
        }
    }
    IOLockUnlock(lock);
  }
  signalWorker();
  if (late)
    SYSLOG("gpuctl", "sleep: a ppCWDDE call still runs after %u ms; going on",
           static_cast<unsigned>(gpuctl::kSleepWaitMs));
  return reinterpret_cast<t_event>(orgSleep)(self);
}
// gInSleep is cleared only after the original ppWake returned: between the
// GPU's power-up (before ppWake) and the end of ppWake nothing is sent (phase
// 0d, window C), and the worker then still waits for the framebuffer's read
// and the margin.
uint64_t wrapWake(void* self) {
  __atomic_store_n(&gReadsAtWake, __atomic_load_n(&gReads, __ATOMIC_ACQUIRE),
                   __ATOMIC_RELAXED);
  uint64_t result = reinterpret_cast<t_event>(orgWake)(self);
  __atomic_fetch_add(&gWakes, 1, __ATOMIC_RELAXED);
  __atomic_store_n(&gInSleep, 0, __ATOMIC_SEQ_CST);
  // A copy read before the sleep is not a reading of the card that just woke,
  // and the clock its age comes from may pause while the Mac sleeps. Drop it
  // so nothing is published until the driver samples again.
  PMLogCopy::invalidate();
  signalWorker();
  return result;
}
void turnOffLocked(gpuctl::WriteOff why);
void findGpus(void*, KernelPatcher&) {
  if (gTried) return;  // the library already came: nothing would use the cards
  auto info = DeviceInfo::create();
  if (info == nullptr) {
    gScanFailed = true;
    gScanned = true;
    return;
  }
  uint32_t vendor = 0, device = 0, revision = 0;
  if (info->videoBuiltin != nullptr &&
      WIOKit::getOSDataValue(info->videoBuiltin, "vendor-id", vendor) &&
      (vendor & 0xffff) == gpuctl::kVendorAMD)
    gAmdGpus++;
  for (size_t i = 0; i < info->videoExternal.size(); i++) {
    auto& gpu = info->videoExternal[i];
    if (gpu.video == nullptr ||
        !WIOKit::getOSDataValue(gpu.video, "vendor-id", vendor))
      continue;
    // Every AMD GPU counts, also one whose other ids cannot be read.
    if ((vendor & 0xffff) == gpuctl::kVendorAMD) gAmdGpus++;
    if (!WIOKit::getOSDataValue(gpu.video, "device-id", device) ||
        !WIOKit::getOSDataValue(gpu.video, "revision-id", revision))
      continue;
    if (!gpuctl::deviceReadable(vendor & 0xffff, device & 0xffff,
                                revision & 0xff) ||
        gGpuCount >= kMaxGpus)
      continue;
    gpu.video->retain();
    gGpus[gGpuCount++] = gpu.video;
    if (gpuctl::deviceAllowed(vendor & 0xffff, device & 0xffff,
                              revision & 0xff))
      gWritableGpus++;
  }
  DeviceInfo::deleter(info);
  // Any readable card that may not write: every sender refuses from now on.
  gReadOnlyCard = gWritableGpus != gGpuCount;
  gpuctl::WriteOff scan = gpuctl::scanReason(
      static_cast<uint32_t>(gGpuCount), static_cast<uint32_t>(gWritableGpus));
  if (scan != gpuctl::WriteOff::None && gStateLock != nullptr) {
    // Off from the scan on, before the library or any program can ask. Only
    // the one card being read only marks it so (two cards: NotOneCard).
    IOLockLock(gStateLock);
    if (scan == gpuctl::WriteOff::ReadOnlyCard) gOwner.markReadOnly();
    turnOffLocked(scan);
    IOLockUnlock(gStateLock);
  }
  gScanned = true;
  SYSLOG("gpuctl", "%u readable card(s), %u of them writable, %u AMD GPU(s)",
         static_cast<unsigned>(gGpuCount), static_cast<unsigned>(gWritableGpus),
         static_cast<unsigned>(gAmdGpus));
}

// Routes one function after checking its first bytes. False changes nothing.
bool routeOne(KernelPatcher& patcher, size_t index, mach_vm_address_t address,
              size_t size, const char* symbol, const uint8_t* want, size_t n,
              void* wrapper, mach_vm_address_t& org, const char* name) {
  auto at = patcher.solveSymbol(index, symbol, address, size);
  if (at == 0) {
    patcher.clearError();
    SYSLOG("gpuctl", "%s: %s not found", name, symbol);
    return false;
  }
  if (at < address || at >= address + size) {
    SYSLOG("gpuctl", "%s: %s outside the library", name, symbol);
    return false;
  }
  auto entry = reinterpret_cast<const uint8_t*>(at);
  size_t available = static_cast<size_t>(address + size - at);
  if (gpusens::entryIsRouted(entry, available)) {
    SYSLOG("gpuctl", "%s: %s already routed by another kext", name, symbol);
    return false;
  }
  if (!gpuctl::bytesMatch(entry, available, want, n)) {
    SYSLOG("gpuctl", "%s: %s does not start as expected", name, symbol);
    return false;
  }
  KernelPatcher::RouteRequest requests[]{{symbol, wrapper, org}};
  bool routed = patcher.routeMultipleLong(index, requests, address, size);
  auto error = patcher.getError();
  patcher.clearError();
  if (routed && error == KernelPatcher::Error::NoError && org != 0 &&
      gpusens::entryIsRouted(entry, available))
    return true;
  SYSLOG("gpuctl", "%s: %s route failed (%d)", name, symbol, error);
  return false;
}

// ppCWDDE is called, not routed: found and checked like a routed function,
// and left alone when another kext routes it.
void findCwdde(KernelPatcher& patcher, size_t index, mach_vm_address_t address,
               size_t size, const char* name) {
  auto at = patcher.solveSymbol(index, gpuctl::kCwddeSymbol, address, size);
  if (at == 0) {
    patcher.clearError();
    SYSLOG("gpuctl", "%s: ppCWDDE not found", name);
    return;
  }
  if (at < address || at >= address + size) return;
  auto entry = reinterpret_cast<const uint8_t*>(at);
  size_t available = static_cast<size_t>(address + size - at);
  if (gpusens::entryIsRouted(entry, available) ||
      !gpuctl::bytesMatch(entry, available, gpuctl::kCwddeEntry,
                          gpuctl::kCwddeBytes)) {
    SYSLOG("gpuctl", "%s: ppCWDDE does not start as expected", name);
    return;
  }
  gCwdde = at;
}

// ---------------------------------------------------------------- worker --

// The OD8 way back after writing went off (under gStateLock): a change may
// still be on the card, so the fixed stock call goes out from the worker,
// kRevertTries tries 500 ms apart, once per boot. Then nothing more is sent.
bool gOd8OffBackArmed{false};
uint32_t gOd8OffBackLeft{0};
uint64_t gOd8OffBackAt{0};

// Under gStateLock. Writing off until restart: the first reason is kept. A
// set still waiting in the slot is answered "off" at once (a running one is
// finished by the worker). An OD8 change that may still be on the card gets
// the fixed way back (gOd8OffBack*).
void turnOffLocked(gpuctl::WriteOff why) {
  // The first reason, unless a read-only card's gives way (keptReason).
  gWriteOff = gpuctl::keptReason(gWriteOff, why);
  gOwner.turnOff();
  gPendingRevert = 0;
  if (gOd8Dirty && !gTornDown && !gOd8OffBackArmed && !gReadOnlyCard) {
    gOd8OffBackArmed = true;
    gOd8OffBackLeft = gpuctl::kRevertTries;
    gOd8OffBackAt = 0;
    signalWorker();
  }
  uint64_t t = 0, c = 0;
  uint32_t w = 0;
  if (gSlot.take(&t, &c, &w)) {
    gSlot.finish(t, gpuctl::Reply::Off);
    gLastReply = gpuctl::Reply::Off;
  }
  IOLockWakeup(gStateLock, &gSlot, false);
}
bool sleepingLocked() {
  return gOwner.isSleeping() ||
         __atomic_load_n(&gInSleep, __ATOMIC_SEQ_CST) != 0;
}
bool readyLocked() {
  return gWorkerUp && !gTornDown && gCwdde != 0 &&
         __atomic_load_n(&gPP, __ATOMIC_ACQUIRE) != nullptr &&
         gpuctl::bootValuePlausible(bootW());
}
// Whether the limit may be lower than the start-up one. Once off, Owner
// keeps its "changed" mark for good; what the kext confirmed decides then.
bool changedLocked() {
  if (gOwner.isOff()) return gHeldW != 0 || gLimitUnknown || gOd8Dirty;
  return gOwner.isChanged();
}

// The worker's view of sleep and wake (worker-only).
uint64_t wSeenGen{0};

// One ppCWDDE call on the worker's thread. False: nothing was called (torn
// down, no object yet, or asleep, also a whole sleep and wake the worker has
// not seen yet: checked under the lock right before).
bool callCwdde(const void* in, uint32_t inSize, void* out, uint32_t* outSize,
               uint32_t* ret) {
  IOLockLock(gStateLock);
  void* pp = __atomic_load_n(&gPP, __ATOMIC_ACQUIRE);
  if (gTornDown || pp == nullptr || gCwdde == 0 || sleepingLocked() ||
      __atomic_load_n(&gSleepGen, __ATOMIC_SEQ_CST) != wSeenGen) {
    IOLockUnlock(gStateLock);
    return false;
  }
  gInFlight = true;
  IOLockUnlock(gStateLock);
  *ret = reinterpret_cast<t_cwdde>(gCwdde)(pp, in, inSize, out, outSize);
  IOLockLock(gStateLock);
  gInFlight = false;
  IOLockWakeup(gStateLock, &gInFlight, false);
  IOLockUnlock(gStateLock);
  return true;
}
gpuctl::Access askAccess() {
  if (gReadOnlyCard) return gpuctl::Access::No;  // the only 0x2a: never here
  gpuctl::EscapeHeader q = gpuctl::accessQuery();
  gpuctl::AccessOut out = gpuctl::accessAnswer();
  uint32_t outSize = sizeof(out), ret = 0;
  if (!callCwdde(&q, sizeof(q), &out, &outSize, &ret))
    return gpuctl::Access::No;
  return gpuctl::classifyAccess(ret, outSize, out);
}
gpuctl::Sent sendLimit(uint32_t boot, uint32_t floor, uint32_t watts) {
  if (gReadOnlyCard) return gpuctl::Sent::NotSent;  // never on a read-only card
  gpuctl::SetLimitIn in;
  if (!gpuctl::makeSetLimit(boot, floor, watts, &in))
    return gpuctl::Sent::Failed;
  __atomic_store_n(&gTagCount, 0, __ATOMIC_RELAXED);
  __atomic_store_n(&gTagW, 0, __ATOMIC_RELAXED);
  __atomic_store_n(&gTagResult, 0, __ATOMIC_RELAXED);
  uint32_t outSize = 0, ret = 0;
  if (!callCwdde(&in, sizeof(in), nullptr, &outSize, &ret))
    return gpuctl::Sent::NotSent;
  gpuctl::SendSeen seen{__atomic_load_n(&gTagCount, __ATOMIC_RELAXED),
                        __atomic_load_n(&gTagW, __ATOMIC_RELAXED),
                        __atomic_load_n(&gTagResult, __ATOMIC_RELAXED)};
  gpuctl::Sent sent = gpuctl::classifySend(ret, seen, watts);
  SYSLOG("gpuctl", "0x6e %u W: ppCWDDE 0x%x, %u send(s) seen (%u W, %u): %s",
         watts, ret, seen.count, seen.watts, seen.result,
         sent == gpuctl::Sent::Confirmed ? "confirmed"
         : sent == gpuctl::Sent::NotSent ? "not sent"
                                         : "NOT CONFIRMED");
  return sent;
}

bool wAsleep{false};
bool wWakeWaiting{false};
bool wWakeRead{false};  // the read (or 10 s) came: the margin runs
uint64_t wWakeGen{0}, wWakeReads{0}, wWakeStart{0}, wWakeReadMs{0};

bool sleepStarted() {
  return __atomic_load_n(&gSleepGen, __ATOMIC_SEQ_CST) != wSeenGen ||
         __atomic_load_n(&gInSleep, __ATOMIC_SEQ_CST) != 0;
}
// Waits on the semaphore until `untilMs` (0 = until signalled). A signal
// ends the wait early; the caller looks at everything again. Only a wait
// that took the token clears gSignalled (signalWorker), so the semaphore
// holds one token at most and a timed wait really waits.
void waitUntil(uint64_t untilMs) {
  kern_return_t kr;
  if (untilMs == 0) {
    kr = semaphore_wait(gSem);
  } else {
    uint64_t now = nowMs();
    if (untilMs <= now) return;
    kr = semaphore_wait_deadline(gSem,
                                 mach_absolute_time() + msToAbs(untilMs - now));
  }
  if (kr == KERN_SUCCESS) __atomic_store_n(&gSignalled, 0, __ATOMIC_SEQ_CST);
}

// A request in the slot while the Mac sleeps: answered at once.
void refuseWaiting(gpuctl::Reply reply) {
  uint64_t t = 0, c = 0;
  uint32_t w = 0;
  IOLockLock(gStateLock);
  if (gSlot.take(&t, &c, &w)) {
    gSlot.finish(t, reply);
    gLastReply = reply;
    IOLockWakeup(gStateLock, &gSlot, false);
  }
  IOLockUnlock(gStateLock);
}

enum class Od8Result : uint32_t {
  Confirmed,   // sent and read back as sent
  NotApplied,  // the GPU did not take it (asleep, blocked): nothing changed
               // that is known; the staged state is unknown
  Refused,     // the checks refused it: nothing sent
  Failed,      // an error, or a read-back that does not match
};
// Whether phase A read OD8 cleanly, so a change can be checked at all.
bool od8Ready() {
  if (gOd8Lock == nullptr) return false;
  IOLockLock(gOd8Lock);
  bool ok = gOd8HaveStock && !gOd8StockOdd && gOd8State == gpuctl::Od8Read::Ok;
  IOLockUnlock(gOd8Lock);
  return ok;
}

// The card's power range now (0.8.0): the start-up limit and the first clean
// 0x9f. Takes gOd8Lock only: call it before gStateLock, never under it.
gpuctl::PowerRange rangeNow() {
  uint32_t boot = bootW();
  if (gOd8Lock == nullptr)
    return gpuctl::powerRange(boot, false, false, gpuctl::Od8InitialOut{});
  IOLockLock(gOd8Lock);
  gpuctl::PowerRange r =
      gpuctl::powerRange(boot, gOd8HaveStock, gOd8StockOdd, gOd8Stock);
  IOLockUnlock(gOd8Lock);
  return r;
}
Od8Result od8WayBackOnce();
void runSetOd8(uint64_t t, uint64_t client, const gpuctl::Od8Want& want);

void runRevert() {
  IOLockLock(gStateLock);
  uint64_t id = gPendingRevert;
  bool od8 = gOd8Dirty;  // read under the lock just taken above
  IOLockUnlock(gStateLock);
  if (id == 0) return;
  uint32_t boot = bootW();
  for (uint32_t tryNo = 1;; tryNo++) {
    // Before every try: still this way back, writing still on, not torn
    // down. A turnOff during the wait between tries clears gPendingRevert;
    // then nothing more is sent here.
    IOLockLock(gStateLock);
    bool stillWanted =
        gPendingRevert == id && !gOwner.isOff() && !gTornDown && !gReadOnlyCard;
    IOLockUnlock(gStateLock);
    if (!stillWanted) return;
    bool asleep = sleepStarted();
    gpuctl::TryResult r = gpuctl::TryResult::Transient;
    if (!asleep && od8) {
      // The fixed OD8 way back (design v3.1 B); the power limit was not
      // changed (never both).
      Od8Result o = od8WayBackOnce();
      r = o == Od8Result::Confirmed    ? gpuctl::TryResult::Confirmed
          : o == Od8Result::NotApplied ? gpuctl::TryResult::Transient
                                       : gpuctl::TryResult::Failed;
      asleep = sleepStarted();
    } else if (!asleep) {
      gpuctl::Access a = askAccess();
      // The way back is the start-up value: taken whatever the floor.
      gpuctl::Sent s = a == gpuctl::Access::Yes ? sendLimit(boot, 0, boot)
                                                : gpuctl::Sent::NotSent;
      r = gpuctl::tryResult(a, s);
      asleep = sleepStarted();
    }
    gpuctl::Next next = gpuctl::afterRevertTry(tryNo, r, asleep);
    if (next == gpuctl::Next::Abort) return;  // willSleep drops it
    IOLockLock(gStateLock);
    bool current = gPendingRevert == id;
    if (next == gpuctl::Next::Done) {
      gOwner.reverted(id, nowMs());
      if (current) {
        gPendingRevert = 0;
        if (od8) {
          gOd8Dirty = false;
          gOd8Held = 0;
          gOd8Reverts++;
          if (gOd8OffAfterWayBack) turnOffLocked(gpuctl::WriteOff::Od8Watchdog);
        } else {
          if (!gOwner.isChanged()) gHeldW = 0;
          gReverts++;
        }
      }
    } else if (next == gpuctl::Next::GiveUp) {
      gOwner.revertFailed(id);
      if (current) gPendingRevert = 0;
      if (od8) gOd8OffBackArmed = true;  // its tries are these
      if (gOwner.isOff()) turnOffLocked(gpuctl::WriteOff::RevertFailed);
    }
    IOLockUnlock(gStateLock);
    if (next == gpuctl::Next::Done) {
      if (od8)
        SYSLOG("gpuctl", "way back %llu: OD8 stock confirmed (try %u)", id,
               tryNo);
      else
        SYSLOG("gpuctl", "way back %llu: %u W confirmed (try %u)", id, boot,
               tryNo);
      return;
    }
    if (next == gpuctl::Next::GiveUp) {
      SYSLOG("gpuctl", "way back %llu failed after %u tries: writing off", id,
             tryNo);
      return;
    }
    if (!current) return;  // a newer one replaced it: the next pass runs it
    uint64_t until = nowMs() + gpuctl::kRevertRetryMs;
    while (nowMs() < until && !sleepStarted()) waitUntil(until);
  }
}

void runSet() {
  uint64_t t = 0, client = 0;
  uint32_t watts = 0;
  IOLockLock(gStateLock);
  bool have = gSlot.take(&t, &client, &watts);
  bool off = have && gOwner.isOff();
  bool od8 = have && gSlotKind == 1;
  gpuctl::Od8Want want = gSlotWant;
  gSlotKind = 0;
  if (off) {  // off: answered at once, nothing is asked of the driver
    gSlot.finish(t, gpuctl::Reply::Off);
    gLastReply = gpuctl::Reply::Off;
    IOLockWakeup(gStateLock, &gSlot, false);
  }
  IOLockUnlock(gStateLock);
  if (!have || off) return;
  if (od8) {
    runSetOd8(t, client, want);
    return;
  }
  uint32_t boot = bootW();
  uint32_t floor = rangeNow().floorW;  // fixed once known; 0 = not known
  // 0x2a first: a GPU that is not up changes nothing, not even Owner.
  gpuctl::Access access = askAccess();
  IOLockLock(gStateLock);
  gpuctl::Reply reply = gpuctl::Reply::Ok;
  bool go = false;
  if (!gSlot.wanted(t))
    reply = gpuctl::Reply::Cancelled;
  else if (sleepingLocked())
    reply = gpuctl::Reply::Sleeping;
  else if (access != gpuctl::Access::Yes)
    reply = gpuctl::Reply::NotReady;
  else if (gOd8Dirty)
    reply = gpuctl::Reply::Busy;  // an OD8 change is held: never both
  else if (gpuctl::routeSet(boot, floor, watts) != gpuctl::SetRoute::Change)
    reply = gpuctl::Reply::BadArgs;  // the client routed it already
  else {
    reply = gpuctl::replyFor(gOwner.change(client, nowMs()));
    go = reply == gpuctl::Reply::Ok;
  }
  if (!go) {
    gSlot.finish(t, reply);
    gLastReply = reply;
    IOLockWakeup(gStateLock, &gSlot, false);
    IOLockUnlock(gStateLock);
    return;
  }
  IOLockUnlock(gStateLock);

  gpuctl::Sent sent = sendLimit(boot, floor, watts);

  IOLockLock(gStateLock);
  if (sent == gpuctl::Sent::Failed) {
    // Not confirmed: the limit is not known. Release, send the boot value
    // once if not asleep, then off until restart, whatever that send did.
    // The program hears "failed" only once all of that is done.
    gOwner.release(client);
    gPendingRevert = 0;
    bool recover = !sleepingLocked();
    IOLockUnlock(gStateLock);
    gpuctl::Sent back = recover ? sendLimit(boot, 0, boot)  // checks the
                                : gpuctl::Sent::NotSent;    // sleep again
    IOLockLock(gStateLock);
    if (back == gpuctl::Sent::Confirmed) {
      gHeldW = 0;
      gReverts++;
    } else {
      gLimitUnknown = true;
    }
    turnOffLocked(gpuctl::WriteOff::SendFailed);
    reply = gpuctl::Reply::Failed;
  } else if (sent == gpuctl::Sent::Confirmed) {
    gHeldW = watts;
    gChanges++;
    reply = gpuctl::Reply::Ok;
  } else {
    // Busy or not ready: nothing reached the firmware. The change Owner
    // counted goes back (always safe); the program hears "busy".
    uint64_t id = gOwner.release(client);
    if (id != 0) gPendingRevert = id;
    reply = gpuctl::Reply::Busy;
  }
  gSlot.finish(t, reply);
  gLastReply = reply;
  IOLockWakeup(gStateLock, &gSlot, false);
  IOLockUnlock(gStateLock);
  if (sent == gpuctl::Sent::Confirmed)
    SYSLOG("gpuctl", "change: %u W held (boot %u W)", watts, boot);
  if (sent == gpuctl::Sent::Failed)
    SYSLOG("gpuctl", "a change to %u W was not confirmed: writing off", watts);
}

// OD8 phase A, on the worker's thread only: the two read-only escapes, once
// 2 s after the framebuffer's first read of the power limit and once after
// each wake's margin (design-od8.md v2). Nothing is sent to the firmware.
gpuctl::Od8InitialOut wOd8Init{};  // worker-only buffers, not on the stack
gpuctl::Od8CurrentOut wOd8Cur{};
bool wOd8BootSeen{false};
bool wOd8Due{false};
bool wOd8Stopped{false};  // an answer that did not fit: no more reads
uint64_t wOd8At{0};
uint32_t wOd8TriesNow{0};

void od8Due(uint64_t at) {
  wOd8BootSeen = true;
  wOd8Due = !wOd8Stopped;
  wOd8At = at;
  wOd8TriesNow = 0;
}

// One try of both reads. Returns what to publish: Ok or Odd only when both
// answers carried data (then wOd8Init and wOd8Cur are this try's). An odd
// 0x9f still sends 0xa0, so the numbers published always belong together;
// *initOdd says the defaults themselves were odd.
gpuctl::Od8Read od8Try(uint32_t* ret, uint32_t* odd, uint32_t* oddEscape,
                       bool* initOdd) {
  *ret = 0;
  *odd = 0;
  *oddEscape = 0;
  *initOdd = false;
  gpuctl::EscapeHeader q = gpuctl::od8Query(gpuctl::kEscapeOd8Initial);
  gpuctl::od8PrepareInitial(&wOd8Init);
  uint32_t size = sizeof(wOd8Init);
  if (!callCwdde(&q, sizeof(q), &wOd8Init, &size, ret))
    return gpuctl::Od8Read::NotCalled;
  gpuctl::Od8Read ri = gpuctl::od8CheckInitial(*ret, size, wOd8Init, odd);
  if (ri != gpuctl::Od8Read::Ok && ri != gpuctl::Od8Read::Odd) return ri;
  if (ri == gpuctl::Od8Read::Odd) {
    *oddEscape = gpuctl::kEscapeOd8Initial;
    *initOdd = true;
  }
  q = gpuctl::od8Query(gpuctl::kEscapeOd8Current);
  gpuctl::od8PrepareCurrent(&wOd8Cur);
  size = sizeof(wOd8Cur);
  uint32_t retCur = 0, oddCur = 0;
  if (!callCwdde(&q, sizeof(q), &wOd8Cur, &size, &retCur)) {
    *odd = 0;
    *oddEscape = 0;
    return gpuctl::Od8Read::NotCalled;
  }
  *ret = retCur;
  gpuctl::Od8Read rc = gpuctl::od8CheckCurrent(retCur, size, wOd8Cur, &oddCur);
  if (rc != gpuctl::Od8Read::Ok && rc != gpuctl::Od8Read::Odd) {
    *odd = 0;
    *oddEscape = 0;
    return rc;
  }
  if (rc == gpuctl::Od8Read::Odd && *odd == 0) {
    *odd = oddCur;
    *oddEscape = gpuctl::kEscapeOd8Current;
  }
  return ri == gpuctl::Od8Read::Odd || rc == gpuctl::Od8Read::Odd
             ? gpuctl::Od8Read::Odd
             : gpuctl::Od8Read::Ok;
}

// Publishes one try's result (wOd8Init / wOd8Cur when complete). A try that
// will be repeated publishes its state only while nothing was ever read.
void od8Publish(gpuctl::Od8Read r, uint32_t ret, uint32_t odd,
                uint32_t oddEscape, bool initOdd, bool again, uint64_t now) {
  bool complete = r == gpuctl::Od8Read::Ok || r == gpuctl::Od8Read::Odd;
  IOLockLock(gOd8Lock);
  gOd8Tries++;
  if (!again || !gOd8HaveCurrent) {
    gOd8State = r;
    gOd8LastRet = ret;
    gOd8OddEntry = odd;
    gOd8OddEscape = oddEscape;
  }
  if (complete) {
    // "Stock" is the first complete read; StockOdd marks one whose defaults
    // were not as expected (then no OD8 change is ever made).
    if (!gOd8HaveStock) {
      gOd8Stock = wOd8Init;
      gOd8StockOdd = initOdd;
      gOd8HaveStock = true;
    } else if (!gpuctl::od8SameDefaults(gOd8Stock, wOd8Init)) {
      gOd8DefaultsMoved = true;
    }
    gOd8Latest = wOd8Init;
    if (!gOd8HaveCurrent) gOd8BootCurrent = wOd8Cur;
    gOd8Current = wOd8Cur;
    gOd8HaveCurrent = true;
    gOd8Reads++;
    gOd8LastReadMs = now;
  }
  IOLockUnlock(gOd8Lock);
}

void od8Run() {
  uint32_t ret = 0, odd = 0, oddEscape = 0;
  bool initOdd = false;
  gpuctl::Od8Read r = od8Try(&ret, &odd, &oddEscape, &initOdd);
  wOd8TriesNow++;
  bool again = gpuctl::od8Retry(r) && wOd8TriesNow < gpuctl::kOd8Tries;
  if (r == gpuctl::Od8Read::Error) wOd8Stopped = true;
  uint64_t now = nowMs();
  od8Publish(r, ret, odd, oddEscape, initOdd, again, now);
  if (again) {
    wOd8At = now + gpuctl::kOd8RetryMs;
    return;
  }
  wOd8Due = false;
  SYSLOG("gpuctl", "OD8 read (try %u): %s, ppCWDDE 0x%x, odd entry %u of 0x%x",
         wOd8TriesNow, gpuctl::od8ReadText(r), ret, odd, oddEscape);
}

// ------------------------------------------------- OD8 writes (worker only) --
//
// design-od8-b.md v3.1. Each change: read 0x9f + 0xa0 fresh, check, build the
// whole call, send 0xa1, read both back and compare, and check that the
// driver kept nothing for its replay. The way back is the same call for the
// stock state, checked only for an unchanged layout.

gpuctl::Od8InitialOut wOd8First{};   // a copy of stock, worker-only
gpuctl::Od8InitialOut wOd8Fresh{};   // the 0x9f right before a call
gpuctl::Od8CurrentOut wOd8Before{};  // the 0xa0 right before a call
gpuctl::Od8CurrentOut wOd8Out{};     // 0xa1's own answer
gpuctl::Od8SetIn wOd8In{};
uint32_t wOd8Mismatch{0};  // the last read-back's odd entry + 1, or 0
gpuctl::Od8Watch wDog{};   // the fan watchdog's state

const uint8_t kEmptyReplay[12] = {0x0c, 0, 0, 0, 0, 0, 0, 0, 0x02, 0, 0, 0};
// The driver's replay list on the GPU is still the empty one (report.md
// 11.7): it kept none of our calls. Unknown (no property) counts as not.
bool replayEmpty() {
  auto gpu = gGpus[0];
  if (gpu == nullptr) return false;
  auto d = OSDynamicCast(OSData, gpu->getProperty("PP_CNEscapeInput"));
  return d != nullptr && d->getLength() == sizeof(kEmptyReplay) &&
         memcmp(d->getBytesNoCopy(), kEmptyReplay, sizeof(kEmptyReplay)) == 0;
}

// Reads 0x9f + 0xa0 now and publishes them (the same as a phase A read).
gpuctl::Od8Read od8ReadNow() {
  uint32_t ret = 0, odd = 0, oddEscape = 0;
  bool initOdd = false;
  gpuctl::Od8Read r = od8Try(&ret, &odd, &oddEscape, &initOdd);
  od8Publish(r, ret, odd, oddEscape, initOdd, false, nowMs());
  return r;
}

// Step 1 of a change or a way back: fresh read, checks, the bytes. On
// Confirmed, wOd8In / wOd8Before hold the call and the values before it.
Od8Result od8Prepare(const gpuctl::Od8Want& want, bool wayBack,
                     gpuctl::Od8Check* check) {
  *check = gpuctl::Od8Check::Ok;
  gpuctl::Od8Read r = od8ReadNow();
  if (r == gpuctl::Od8Read::NoData || r == gpuctl::Od8Read::NotCalled)
    return Od8Result::NotApplied;
  bool haveStock, stockOdd;
  IOLockLock(gOd8Lock);
  haveStock = gOd8HaveStock;
  stockOdd = gOd8StockOdd;
  if (haveStock) wOd8First = gOd8Stock;
  IOLockUnlock(gOd8Lock);
  if (wayBack) {
    // Never refused by the request checks (design v3.1 D): stock must be
    // known and the layout the same, that is all.
    if (!haveStock || r == gpuctl::Od8Read::Error ||
        r == gpuctl::Od8Read::Refused || r == gpuctl::Od8Read::Unsupported)
      return Od8Result::Failed;
    if (!gpuctl::od8SameLayout(wOd8First, wOd8Init)) return Od8Result::Failed;
  } else {
    if (!haveStock || stockOdd || r != gpuctl::Od8Read::Ok) {
      *check = gpuctl::Od8Check::NotRead;
      return Od8Result::Refused;
    }
    *check = gpuctl::od8CheckWant(want, wOd8First, wOd8Init, wOd8Cur);
    if (*check != gpuctl::Od8Check::Ok) return Od8Result::Refused;
  }
  // A way back over an odd fresh 0x9f takes the first read's defaults.
  wOd8Fresh = r == gpuctl::Od8Read::Ok ? wOd8Init : wOd8First;
  wOd8Before = wOd8Cur;
  gpuctl::od8Build(want, wOd8First, wOd8Fresh, &wOd8In);
  if (!gpuctl::od8ShapeOk(wOd8In)) return Od8Result::Failed;
  return Od8Result::Confirmed;
}

// Step 2: send wOd8In, read back, compare. *sentPower: the driver sent a
// power limit during the call (its own watcher saw it).
Od8Result od8Commit(bool* sentPower, uint32_t* retOut) {
  *sentPower = false;
  *retOut = 0;
  wOd8Mismatch = 0;
  if (gReadOnlyCard) return Od8Result::NotApplied;  // the only 0xa1: never here
  gpuctl::od8PrepareCurrent(&wOd8Out);
  uint32_t size = sizeof(wOd8Out), ret = 0;
  uint64_t setsBefore = __atomic_load_n(&gSets, __ATOMIC_ACQUIRE);
  bool called = callCwdde(&wOd8In, sizeof(wOd8In), &wOd8Out, &size, &ret);
  *sentPower = __atomic_load_n(&gSets, __ATOMIC_ACQUIRE) != setsBefore;
  *retOut = ret;
  if (!called) return Od8Result::NotApplied;
  uint32_t odd = 0;
  gpuctl::Od8Read a = gpuctl::od8CheckCurrent(ret, size, wOd8Out, &odd);
  if (a == gpuctl::Od8Read::NoData) return Od8Result::NotApplied;
  if (a != gpuctl::Od8Read::Ok) return Od8Result::Failed;
  gpuctl::Od8Read back = od8ReadNow();
  if (back == gpuctl::Od8Read::NoData || back == gpuctl::Od8Read::NotCalled)
    return Od8Result::NotApplied;
  if (back != gpuctl::Od8Read::Ok) return Od8Result::Failed;
  wOd8Mismatch = gpuctl::od8VerifyAfter(wOd8In, wOd8Before, wOd8Cur);
  if (wOd8Mismatch != 0) return Od8Result::Failed;
  if (!replayEmpty()) {
    wOd8Mismatch = 40;  // the driver kept the call for its replay
    return Od8Result::Failed;
  }
  return Od8Result::Confirmed;
}

uint64_t od8HeldFlags(const gpuctl::Od8Want& w) {
  return (w.curve ? gpuctl::kOd8HeldCurve : 0) |
         (w.zeroRpmOff ? gpuctl::kOd8HeldZeroRpmOff : 0) |
         (w.gfxMaxMHz != 0 ? gpuctl::kOd8HeldGfx : 0);
}

// The fixed way back once (design v3.1 B). Confirmed: stock again.
Od8Result od8WayBackOnce() {
  gpuctl::Od8Want stock{};
  gpuctl::Od8Check check;
  Od8Result p = od8Prepare(stock, true, &check);
  if (p != Od8Result::Confirmed) return p;
  bool sentPower = false;
  uint32_t ret = 0;
  Od8Result c = od8Commit(&sentPower, &ret);
  IOLockLock(gStateLock);
  if (sentPower) gOd8SentPower++;
  IOLockUnlock(gStateLock);
  SYSLOG("gpuctl", "OD8 way back: %s (ppCWDDE 0x%x, read-back %u)",
         c == Od8Result::Confirmed    ? "stock again"
         : c == Od8Result::NotApplied ? "not applied"
                                      : "FAILED",
         ret, wOd8Mismatch);
  return c;
}

// Called by workerPass when nothing else is to do, awake and past the wake
// margin. Returns when to look again (0 = only when signalled).
uint64_t od8Pass() {
  if (__atomic_load_n(&gSecondObject, __ATOMIC_ACQUIRE) != 0) return 0;
  uint64_t now = nowMs();
  if (!wOd8BootSeen) {
    // GetPowerLimit signals its first read.
    if (__atomic_load_n(&gReads, __ATOMIC_ACQUIRE) == 0) return 0;
    od8Due(now + gpuctl::kWakeReadyMarginMs);
  }
  if (!wOd8Due) return 0;
  if (now < wOd8At) return wOd8At;
  od8Run();
  return wOd8Due ? wOd8At : 0;
}
uint64_t earliest(uint64_t a, uint64_t b) {
  if (a == 0) return b;
  if (b == 0) return a;
  return a < b ? a : b;
}

// The fan watchdog's readings (worker-only).
uint8_t wDogLog[gpusens::kLogBytes];
uint64_t wDogNextMs{0};
// Whether the watchdog can see now: a fresh PMLog copy with the hotspot (27)
// and the fan (15).
bool od8DogSees() {
  uint64_t ageNs = 0, samples = 0;
  uint32_t hot = 0, fan = 0;
  bool have = PMLogCopy::snapshot(wDogLog, &ageNs, &samples) &&
              gpusens::entry(wDogLog, 27, &hot) &&
              gpusens::entry(wDogLog, 15, &fan);
  return gpuctl::od8DogCanWatch(have, ageNs / 1000000);
}

// A program's OD8 state, taken from the slot. Mirrors runSet: nothing is
// counted as changed before the checks passed; Owner counts the change before
// the send (a failed send is undone by going back, which is always safe).
void runSetOd8(uint64_t t, uint64_t client, const gpuctl::Od8Want& want) {
  IOLockLock(gStateLock);
  gpuctl::Reply reply = gpuctl::Reply::Ok;
  if (!gSlot.wanted(t))
    reply = gpuctl::Reply::Cancelled;
  else if (sleepingLocked())
    reply = gpuctl::Reply::Sleeping;
  else if (gHeldW != 0 || gLimitUnknown)
    reply = gpuctl::Reply::Busy;  // a power change is held: never both
  IOLockUnlock(gStateLock);
  gpuctl::Od8Check check = gpuctl::Od8Check::Ok;
  Od8Result p = Od8Result::Confirmed;
  if (reply == gpuctl::Reply::Ok && want.curve && !od8DogSees()) {
    check = gpuctl::Od8Check::NoReadings;  // never a curve it cannot watch
    p = Od8Result::Refused;
    reply = gpuctl::Reply::Od8Refused;
  }
  if (reply == gpuctl::Reply::Ok) {
    p = od8Prepare(want, false, &check);
    if (p == Od8Result::Refused) reply = gpuctl::Reply::Od8Refused;
    if (p == Od8Result::NotApplied) reply = gpuctl::Reply::NotReady;
    if (p == Od8Result::Failed) reply = gpuctl::Reply::Od8Refused;
  }
  IOLockLock(gStateLock);
  bool go = false;
  if (reply == gpuctl::Reply::Ok) {
    if (!gSlot.wanted(t))
      reply = gpuctl::Reply::Cancelled;
    else if (sleepingLocked())
      reply = gpuctl::Reply::Sleeping;
    else {
      reply = gpuctl::replyFor(gOwner.change(client, nowMs()));
      go = reply == gpuctl::Reply::Ok;
      if (go) gOd8Dirty = true;  // before the send, like Owner's mark
    }
  }
  if (p == Od8Result::Refused || p == Od8Result::Failed) gOd8LastCheck = check;
  if (!go) {
    gSlot.finish(t, reply);
    gLastReply = reply;
    gSlotCheck = static_cast<uint32_t>(check);
    IOLockWakeup(gStateLock, &gSlot, false);
    IOLockUnlock(gStateLock);
    return;
  }
  IOLockUnlock(gStateLock);

  bool sentPower = false;
  uint32_t ret = 0;
  Od8Result c = od8Commit(&sentPower, &ret);
  uint32_t mismatch = wOd8Mismatch;
  Od8Result back = Od8Result::Confirmed;
  if (c == Od8Result::Failed) back = od8WayBackOnce();  // stock over it

  IOLockLock(gStateLock);
  if (sentPower) gOd8SentPower++;
  if (c == Od8Result::Confirmed) {
    gOd8Held = od8HeldFlags(want);
    gOd8HeldWant = want;
    gOd8Changes++;
    gOd8LastCheck = gpuctl::Od8Check::Ok;
    wDog = gpuctl::Od8Watch{};
    reply = gpuctl::Reply::Ok;
  } else if (c == Od8Result::NotApplied) {
    // Not taken: the staged state is unknown, so the fixed way back goes
    // out once the GPU answers.
    gOd8Held = gpuctl::kOd8HeldUnknown;
    uint64_t id = gOwner.release(client);
    if (id != 0) gPendingRevert = id;
    reply = gpuctl::Reply::NotReady;
  } else {
    gOwner.release(client);
    gPendingRevert = 0;
    if (back == Od8Result::Confirmed) {
      gOd8Dirty = false;
      gOd8Held = 0;
      gOd8Reverts++;
    } else {
      gOd8Held = gpuctl::kOd8HeldUnknown;
    }
    turnOffLocked(gpuctl::WriteOff::Od8Failed);
    reply = gpuctl::Reply::Failed;
  }
  gSlot.finish(t, reply);
  gLastReply = reply;
  gSlotCheck = 0;
  IOLockWakeup(gStateLock, &gSlot, false);
  IOLockUnlock(gStateLock);
  if (c == Od8Result::Confirmed)
    SYSLOG("gpuctl", "OD8 change held: curve %d, zero RPM off %d, GFX max %d",
           want.curve, want.zeroRpmOff, want.gfxMaxMHz);
  if (c == Od8Result::Failed)
    SYSLOG("gpuctl",
           "OD8 change FAILED (ppCWDDE 0x%x, read-back %u), way back %s: "
           "writing off",
           ret, mismatch,
           back == Od8Result::Confirmed ? "ok" : "NOT confirmed");
}

// The fan watchdog (design v3.1 F), once a second while a curve is held.
uint64_t od8DogPass() {
  IOLockLock(gStateLock);
  bool curve =
      (gOd8Held & (gpuctl::kOd8HeldCurve | gpuctl::kOd8HeldUnknown)) != 0 &&
      gOd8Dirty && !gTornDown && !gOwner.isOff() && !gReadOnlyCard;
  IOLockUnlock(gStateLock);
  if (!curve) return 0;
  uint64_t now = nowMs();
  if (now < wDogNextMs) return wDogNextMs;
  wDogNextMs = now + 1000;
  uint64_t ageNs = 0, samples = 0;
  bool have = PMLogCopy::snapshot(wDogLog, &ageNs, &samples);
  uint32_t hot = 0, fan = 0;
  have = have && gpusens::entry(wDogLog, 27, &hot) &&
         gpusens::entry(wDogLog, 15, &fan);
  int32_t target = wOd8First.e[gpuctl::kOd8TargetTemp].def;
  gpuctl::Od8Dog d =
      gpuctl::od8Watchdog(&wDog, have, ageNs / 1000000, hot, fan, target, now);
  if (d == gpuctl::Od8Dog::Fine) return wDogNextMs;
  SYSLOG("gpuctl", "OD8 watchdog: %s (hotspot %u C, fan %u %%): stock fan",
         d == gpuctl::Od8Dog::Trip ? "too hot" : "no readings", hot, fan);
  // One try here; if it is not confirmed, writing goes off and the
  // off-back does the other tries, 500 ms apart.
  Od8Result back = sleepStarted() ? Od8Result::NotApplied : od8WayBackOnce();
  bool slept = back == Od8Result::NotApplied && sleepStarted();
  IOLockLock(gStateLock);
  if (back == Od8Result::Confirmed) {
    gOd8Dirty = false;
    gOd8Held = 0;
    gOd8Reverts++;
  }
  if (slept) {
    // A sleep: after the wake, Owner::didWake goes back, and writing goes
    // off once that is done.
    gOd8OffAfterWayBack = true;
    uint64_t id = gOwner.release(gOwner.owner());
    if (id != 0) gPendingRevert = id;
  } else {
    gOwner.release(gOwner.owner());
    gPendingRevert = 0;
    turnOffLocked(gpuctl::WriteOff::Od8Watchdog);
  }
  IOLockUnlock(gStateLock);
  return 0;
}

// The fixed way back after writing went off (gOd8OffBack*). Returns when to
// look again (0 = only when signalled).
uint64_t od8OffBackPass() {
  IOLockLock(gStateLock);
  bool due = gOd8OffBackLeft != 0 && gOd8Dirty && !gTornDown && !gReadOnlyCard;
  uint64_t at = gOd8OffBackAt;
  IOLockUnlock(gStateLock);
  if (!due) return 0;
  uint64_t now = nowMs();
  if (now < at) return at;
  Od8Result r = od8WayBackOnce();
  bool slept = r == Od8Result::NotApplied && sleepStarted();
  IOLockLock(gStateLock);
  if (r == Od8Result::Confirmed) {
    gOd8Dirty = false;
    gOd8Held = 0;
    gOd8Reverts++;
    gOd8OffBackLeft = 0;
  } else if (!slept) {
    gOd8OffBackLeft--;  // a sleep does not count: tried again after the wake
    gOd8OffBackAt = now + gpuctl::kRevertRetryMs;
    gOd8Held |= gpuctl::kOd8HeldUnknown;
  }
  uint32_t left = gOd8OffBackLeft;
  IOLockUnlock(gStateLock);
  if (r == Od8Result::Confirmed)
    SYSLOG("gpuctl", "writing off: OD8 back at stock");
  else if (!slept && left == 0)
    SYSLOG("gpuctl", "writing off: OD8 stock NOT confirmed after %u tries",
           static_cast<unsigned>(gpuctl::kRevertTries));
  return left != 0 && !slept ? now + gpuctl::kRevertRetryMs : 0;
}

// Checks that only become known after start: a second object, the boot value.
void checkRuntime() {
  bool second = __atomic_load_n(&gSecondObject, __ATOMIC_ACQUIRE) != 0;
  uint64_t boot = __atomic_load_n(&gBoot, __ATOMIC_ACQUIRE);
  bool implausible = (boot >> 32) != 0 &&
                     !gpuctl::bootValuePlausible(static_cast<uint32_t>(boot));
  if (!second && !implausible) return;
  gpuctl::WriteOff why = second ? gpuctl::WriteOff::SecondObject
                                : gpuctl::WriteOff::BootImplausible;
  IOLockLock(gStateLock);
  bool was = gOwner.isOff();
  turnOffLocked(why);
  IOLockUnlock(gStateLock);
  if (!was) SYSLOG("gpuctl", "writing off: %s", gpuctl::writeOffText(why));
}

// One pass: everything there is to do now. Returns when to look again (ms,
// 0 = only when signalled).
uint64_t workerPass() {
  for (;;) {
    checkRuntime();
    uint64_t gen = __atomic_load_n(&gSleepGen, __ATOMIC_SEQ_CST);
    bool inSleep = __atomic_load_n(&gInSleep, __ATOMIC_SEQ_CST) != 0;
    if (gen != wSeenGen) {
      // A sleep started (it may be over already): forget the owner and any
      // way back, send nothing; after wake Owner decides.
      wSeenGen = gen;
      wAsleep = true;
      wWakeWaiting = false;
      IOLockLock(gStateLock);
      gOwner.willSleep();
      gPendingRevert = 0;
      IOLockUnlock(gStateLock);
      continue;
    }
    if (wAsleep) {
      if (inSleep) {
        refuseWaiting(gpuctl::Reply::Sleeping);
        return 0;  // ppWake signals
      }
      uint64_t now = nowMs();
      if (!wWakeWaiting) {
        wWakeWaiting = true;
        wWakeRead = false;
        wWakeGen = gen;
        wWakeReads = __atomic_load_n(&gReadsAtWake, __ATOMIC_RELAXED);
        wWakeStart = now;
      }
      // First the framebuffer's read (or 10 s), then the 2 s margin.
      gpuctl::WakeWait w =
          wWakeRead
              ? gpuctl::wakeMargin(wWakeGen, gen, inSleep, wWakeReadMs, now)
              : gpuctl::wakeWait(wWakeGen, gen, inSleep, wWakeReads,
                                 __atomic_load_n(&gReads, __ATOMIC_ACQUIRE),
                                 wWakeStart, now);
      if (w == gpuctl::WakeWait::Abort) {
        wWakeWaiting = false;
        continue;
      }
      if (w == gpuctl::WakeWait::Done && !wWakeRead) {
        wWakeRead = true;
        wWakeReadMs = now;
        continue;
      }
      if (w == gpuctl::WakeWait::Keep) {
        refuseWaiting(gpuctl::Reply::Sleeping);
        return now + 100;  // neither is signalled: look every 100 ms
      }
      wAsleep = false;
      wWakeWaiting = false;
      od8Due(now);  // OD8 is read again once the way back, if any, is done
      IOLockLock(gStateLock);
      uint64_t id = gOwner.didWake();
      if (id != 0) gPendingRevert = id;
      IOLockUnlock(gStateLock);
      if (id != 0) SYSLOG("gpuctl", "after wake: going back");
      continue;
    }
    IOLockLock(gStateLock);
    uint64_t id = gOwner.expired(nowMs());
    if (id != 0) gPendingRevert = id;
    bool revert = gPendingRevert != 0;
    bool set = gSlot.waiting();
    uint64_t deadline = gOwner.deadline();
    IOLockUnlock(gStateLock);
    if (id != 0) SYSLOG("gpuctl", "30 s without word: going back");
    if (revert) {
      runRevert();
      continue;
    }
    if (set) {
      runSet();
      continue;
    }
    uint64_t offBack = od8OffBackPass();
    if (offBack != 0 && offBack <= nowMs()) continue;
    uint64_t dog = od8DogPass();
    uint64_t od8 = od8Pass();
    if (od8 != 0 && od8 <= nowMs()) continue;  // a retry is due already
    return earliest(earliest(deadline, offBack), earliest(od8, dog));
  }
}

// Teardown: the GPU went away, or the Mac is powering off or restarting.
// Nothing is sent from now on. Power off and restart return at once; GPU
// termination waits at most kTeardownWaitMs for one call already running.
void teardown(bool waitForCall) {
  bool late = false;
  IOLockLock(gStateLock);
  gTornDown = true;
  turnOffLocked(gpuctl::WriteOff::Teardown);
  if (waitForCall && gInFlight) {
    uint64_t deadline = 0;
    clock_interval_to_deadline(static_cast<uint32_t>(gpuctl::kTeardownWaitMs),
                               kMillisecondScale, &deadline);
    while (gInFlight)
      if (IOLockSleepDeadline(gStateLock, &gInFlight, deadline, THREAD_UNINT) ==
          THREAD_TIMED_OUT) {
        late = gInFlight;
        break;
      }
  }
  IOLockUnlock(gStateLock);
  if (late)
    SYSLOG("gpuctl",
           "teardown: a ppCWDDE call still runs after %u ms; going on",
           static_cast<unsigned>(gpuctl::kTeardownWaitMs));
}
IOReturn onSystemPower(void*, void*, UInt32 message, IOService*, void*,
                       vm_size_t) {
  if (message == kIOMessageSystemWillPowerOff ||
      message == kIOMessageSystemWillRestart)
    teardown(false);
  return kIOReturnSuccess;
}
IOReturn onGpuMessage(void*, void*, UInt32 message, IOService*, void*,
                      vm_size_t) {
  if (message == kIOMessageServiceIsTerminated) teardown(true);
  return kIOReturnSuccess;
}

// The worker publishes its own thread and semaphore before anything else,
// so set_power_limit's thread check and the wrappers' signals see them from
// the start. If a notification cannot be registered, writing is off, the
// other notification is removed and the thread ends. The semaphore stays
// (a wrapper may hold it); with the coalescing it keeps one token at most.
void workerMain(void* param, wait_result_t) {
  __atomic_store_n(&gWorkerThread, current_thread(), __ATOMIC_RELEASE);
  __atomic_store_n(&gSem, static_cast<semaphore_t>(param), __ATOMIC_RELEASE);
  IONotifier* power =
      registerPrioritySleepWakeInterest(onSystemPower, nullptr, nullptr);
  auto gpu = OSDynamicCast(IOService, gGpus[0]);
  IONotifier* gone = power != nullptr && gpu != nullptr
                         ? gpu->registerInterest(gIOGeneralInterest,
                                                 onGpuMessage, nullptr, nullptr)
                         : nullptr;
  bool ok = power != nullptr && gone != nullptr;
  IOLockLock(gStateLock);
  if (ok)
    gWorkerUp = true;
  else
    turnOffLocked(gpuctl::WriteOff::Start);
  IOLockUnlock(gStateLock);
  SYSLOG("gpuctl", "worker %s",
         ok ? "running" : "could not register its notifications: off");
  if (!ok) {
    if (power != nullptr) power->remove();
    __atomic_store_n(&gWorkerThread, nullptr, __ATOMIC_RELEASE);
    thread_terminate(current_thread());
    return;
  }
  for (;;) waitUntil(workerPass());
}

void startWriting(const char* library) {
  gpuctl::WritePrereqs p{
      false,
      static_cast<uint32_t>(gGpuCount),
      gAmdGpus,
      gX6000,
      gPPInitRouted && gWatchGet && gWatchSet && gWatchSleep && gWatchWake,
      gCwdde != 0,
      gReadOnlyCard};
  gpuctl::WriteOff refusal = gpuctl::staticRefusal(p);
  if (refusal == gpuctl::WriteOff::ReadOnlyCard) {
    // Off before the worker exists: nothing can arm, set or send from here
    // on, and the worker only reads.
    IOLockLock(gStateLock);
    gOwner.markReadOnly();
    turnOffLocked(refusal);
    IOLockUnlock(gStateLock);
  }
  if (gpuctl::workerStarts(refusal)) {
    semaphore_t sem = nullptr;
    thread_t thread = nullptr;
    if (semaphore_create(kernel_task, &sem, SYNC_POLICY_FIFO, 0) !=
        KERN_SUCCESS) {
      refusal = gpuctl::WriteOff::Start;
    } else if (kernel_thread_start(workerMain, sem, &thread) != KERN_SUCCESS) {
      // Nobody has seen the semaphore yet: it can go.
      semaphore_destroy(kernel_task, sem);
      refusal = gpuctl::WriteOff::Start;
    } else {
      thread_deallocate(thread);  // the thread keeps running
    }
  }
  if (refusal != gpuctl::WriteOff::None &&
      refusal != gpuctl::WriteOff::ReadOnlyCard) {
    IOLockLock(gStateLock);
    turnOffLocked(refusal);
    IOLockUnlock(gStateLock);
  }
  SYSLOG("gpuctl", "%s: writing %s%s", library,
         refusal == gpuctl::WriteOff::None           ? "closed until armed"
         : refusal == gpuctl::WriteOff::ReadOnlyCard ? "never (reads only): "
                                                     : "off: ",
         gpuctl::writeOffText(refusal));
}

}  // namespace

void GPUControl::init() {
  gStateLock = IOLockAlloc();
  gOd8Lock = IOLockAlloc();
  if (checkKernelArgument("-gpuctloff")) {
    gOff = true;
    gStatus = "off: -gpuctloff";
    if (gStateLock) {
      IOLockLock(gStateLock);
      turnOffLocked(gpuctl::WriteOff::CtlOff);
      IOLockUnlock(gStateLock);
    }
    SYSLOG("gpuctl", "%s", gStatus);
    return;
  }
  if (gStateLock == nullptr || gOd8Lock == nullptr) {
    gOff = true;
    gStatus = "off: the control could not start";
    if (gStateLock) {
      IOLockLock(gStateLock);
      turnOffLocked(gpuctl::WriteOff::Start);
      IOLockUnlock(gStateLock);
    }
    SYSLOG("gpuctl", "%s", gStatus);
    return;
  }
  // The kernel's number parser: decimal, 0x hex, a leading 0 for octal (020
  // is 16, 016 is 14 and refused), k/m/g suffixes. Whatever it reads, only 0,
  // 2 and 16 are taken; a text value lands as bytes and is refused.
  uint64_t value = ~0ULL;
  if (PE_parse_boot_argn("gpuprofile", &value, sizeof(value))) {
    if (value <= 0xff && gpuctl::profileAllowed(static_cast<uint32_t>(value))) {
      gAsked = true;
      gAskedValue = static_cast<uint32_t>(value);
    } else {
      gRefused = true;
    }
  }
  if (lilu.onPatcherLoad(findGpus, nullptr) != LiluAPI::Error::NoError) {
    gOff = true;
    gStatus = "off: could not register with Lilu";
    IOLockLock(gStateLock);
    turnOffLocked(gpuctl::WriteOff::Start);
    IOLockUnlock(gStateLock);
  }
}

void GPUControl::onLibrary(KernelPatcher& patcher, size_t index,
                           mach_vm_address_t address, size_t size,
                           const char* name) {
  if (gOff || gTried) return;
  gTried = true;
  // Writing stays off unless startWriting below finds everything in place;
  // each early return keeps it off with its reason.
  auto offFor = [](gpuctl::WriteOff why) {
    IOLockLock(gStateLock);
    turnOffLocked(why);
    IOLockUnlock(gStateLock);
  };
  // Lilu runs the patcher callbacks (findGpus) before any kext callback; if
  // that ever changes, nothing is routed and ioreg says why.
  if (!gScanned) {
    gMissedScan = true;
    gStatus = "off: the library loaded before the card scan";
    SYSLOG("gpuctl", "%s", gStatus);
    offFor(gpuctl::WriteOff::NotOneCard);
    return;
  }
  if (gScanFailed) {
    gStatus = "off: no list of devices";
    SYSLOG("gpuctl", "%s", gStatus);
    offFor(gpuctl::WriteOff::NotOneCard);
    return;
  }
  if (gGpuCount == 0) {
    gStatus = "off: no RX 6800 XT or RX 6900 XT (73BF rev C1 or C0) found";
    SYSLOG("gpuctl", "%s", gStatus);
    offFor(gpuctl::WriteOff::NotOneCard);
    return;
  }
  gX6000 = strcmp(name, "AMDRadeonX6000HWLibs") == 0;
  gWatching = routeOne(patcher, index, address, size, gpuctl::kPolicySymbol,
                       gpuctl::kPolicyEntry, gpuctl::kPolicyBytes,
                       reinterpret_cast<void*>(wrapPolicy), orgPolicy, name);
  // ppInitialize always (0.5.0): it keeps the PowerPlay object for writing.
  // The boot profile is only set when the profile watcher is routed too.
  gPPInitRouted =
      routeOne(patcher, index, address, size, gpuctl::kPPInitSymbol,
               gpuctl::kPPInitEntry, gpuctl::kPPInitBytes,
               reinterpret_cast<void*>(wrapPPInit), orgPPInit, name);
  // The power watch: each function on its own; one that fails is left out.
  gWatchGet =
      routeOne(patcher, index, address, size, gpuctl::kGetLimitSymbol,
               gpuctl::kGetLimitEntry, gpuctl::kGetLimitBytes,
               reinterpret_cast<void*>(wrapGetLimit), orgGetLimit, name);
  gWatchSet =
      routeOne(patcher, index, address, size, gpuctl::kSetLimitSymbol,
               gpuctl::kSetLimitEntry, gpuctl::kSetLimitBytes,
               reinterpret_cast<void*>(wrapSetLimit), orgSetLimit, name);
  gWatchSleep = routeOne(patcher, index, address, size, gpuctl::kSleepSymbol,
                         gpuctl::kSleepWakeEntry, gpuctl::kSleepWakeBytes,
                         reinterpret_cast<void*>(wrapSleep), orgSleep, name);
  gWatchWake = routeOne(patcher, index, address, size, gpuctl::kWakeSymbol,
                        gpuctl::kSleepWakeEntry, gpuctl::kSleepWakeBytes,
                        reinterpret_cast<void*>(wrapWake), orgWake, name);
  findCwdde(patcher, index, address, size, name);
  SYSLOG("gpuctl",
         "%s: power watch: limit read %d, limit sent %d, sleep %d, "
         "wake %d",
         name, gWatchGet, gWatchSet, gWatchSleep, gWatchWake);
  gStatus = gWatching ? "watching the profile requests"
                      : "off: the profile function could not be routed";
  SYSLOG("gpuctl", "%s: %s; boot profile %s", name, gStatus,
         !gAsked                      ? "not asked"
         : gPPInitRouted && gWatching ? "armed"
                                      : "not routed");
  startWriting(name);
}

const char* GPUControl::statusText() { return gStatus; }
const char* GPUControl::powerText() {
  if (gOff) return "off";
  if (!gTried) return "waiting for the driver's library";
  if (gMissedScan) return "off: the library loaded before the card scan";
  if (gScanFailed) return "off: no list of devices";
  if (gGpuCount == 0) return "off: no RX 6800 XT or RX 6900 XT";
  int n = gWatchGet + gWatchSet + gWatchSleep + gWatchWake;
  if (n == 4) return "watching the power limit, sleep and wake";
  if (n == 0) return "off: none of its functions could be routed";
  return "watching in part: see PowerWatch";
}
bool GPUControl::power(PowerWatch* out) {
  if (out == nullptr || gOff || !gTried || gGpuCount == 0) return false;
  int n = gWatchGet + gWatchSet + gWatchSleep + gWatchWake;
  if (n == 0) return false;
  *out = PowerWatch{};
  out->watchRead = gWatchGet;
  out->watchSent = gWatchSet;
  out->watchSleep = gWatchSleep;
  out->watchWake = gWatchWake;
  out->reads = __atomic_load_n(&gReads, __ATOMIC_ACQUIRE);
  out->lastReadW = __atomic_load_n(&gLastReadW, __ATOMIC_RELAXED);
  uint64_t boot = __atomic_load_n(&gBoot, __ATOMIC_ACQUIRE);
  out->haveBoot = (boot >> 32) != 0;
  out->bootW = static_cast<uint32_t>(boot);
  out->sends = __atomic_load_n(&gSets, __ATOMIC_ACQUIRE);
  out->lastSentW = __atomic_load_n(&gLastSetW, __ATOMIC_RELAXED);
  out->lastSentSource = __atomic_load_n(&gLastSetSource, __ATOMIC_RELAXED);
  out->lastSentResult = __atomic_load_n(&gLastSetResult, __ATOMIC_RELAXED);
  out->sleeps = __atomic_load_n(&gSleeps, __ATOMIC_RELAXED);
  out->wakes = __atomic_load_n(&gWakes, __ATOMIC_RELAXED);
  return true;
}

const char* GPUControl::profileText() {
  if (gOff) return "off";
  if (gRefused) return "refused: gpuprofile must be 0, 2 or 16";
  if (!gAsked) return "not asked: macOS keeps its 16 (compute)";
  if (!gTried) return "asked: waiting for the driver's library";
  if (gMissedScan) return "not set: the library loaded before the card scan";
  if (gScanFailed) return "not set: no list of devices";
  if (gGpuCount == 0) return "not set: no RX 6800 XT or RX 6900 XT found";
  if (gReadOnlyCard) return "not set: a card here can only be read";
  if (!gWatching) return "not set: the profile function could not be routed";
  if (!gPPInitRouted)
    return "not set: the start of the power management could not be routed";
  if (gSetDone == 0) return "asked: waiting for the power management to start";
  return gSetCards == gGpuCount ? "set before the power management started"
                                : "not set: the GPU did not take the property";
}

bool GPUControl::profileSetValue(uint32_t* value) {
  if (gSetDone == 0 || gSetCards == 0 || gSetCards != gGpuCount) return false;
  if (value) *value = gAskedValue;
  return true;
}

bool GPUControl::requests(uint32_t* last, uint32_t* seen, uint64_t* calls) {
  if (!gWatching) return false;
  if (last) *last = gLastRequest;
  if (seen) *seen = gSeenRequests;
  if (calls) *calls = static_cast<uint64_t>(gRequestCalls);
  return true;
}

// ------------------------------------------------------ the channel's side --
//
// Called on the program's own thread (the user client's externalMethod, no
// command gate). Only set waits, on gStateLock, for the worker's answer.

uint64_t GPUControl::openClient() {
  if (gStateLock == nullptr) return 0;
  IOLockLock(gStateLock);
  uint64_t id = ++gNextClient;
  IOLockUnlock(gStateLock);
  return id;
}

void GPUControl::status(uint64_t client, uint64_t out[gpuctl::kStatusCount]) {
  for (uint32_t i = 0; i < gpuctl::kStatusCount; i++) out[i] = 0;
  out[gpuctl::kStReply] = static_cast<uint64_t>(gpuctl::Reply::Ok);
  out[gpuctl::kStVersion] = gpuctl::kChannelVersion;
  out[gpuctl::kStBootW] = bootW();
  if (gStateLock == nullptr) {
    out[gpuctl::kStFlags] = gpuctl::kFlagOff;
    out[gpuctl::kStWriteOff] = static_cast<uint64_t>(gpuctl::WriteOff::Start);
    return;
  }
  checkRuntime();
  bool od8ok = od8Ready();
  IOLockLock(gStateLock);
  uint64_t f = 0;
  if (od8ok) f |= gpuctl::kFlagOd8Ready;
  if (gOwner.isArmed()) f |= gpuctl::kFlagArmed;
  if (gOwner.isOff()) f |= gpuctl::kFlagOff;
  if (sleepingLocked()) f |= gpuctl::kFlagSleeping;
  if (gOwner.isReverting() || gPendingRevert != 0) f |= gpuctl::kFlagReverting;
  if (changedLocked()) f |= gpuctl::kFlagChanged;
  if (gOwner.owner() != 0) f |= gpuctl::kFlagOwned;
  if (client != 0 && gOwner.owner() == client) f |= gpuctl::kFlagMine;
  if (readyLocked()) f |= gpuctl::kFlagReady;
  out[gpuctl::kStFlags] = f;
  out[gpuctl::kStHeldW] = gHeldW != 0 ? gHeldW : bootW();
  out[gpuctl::kStWriteOff] = static_cast<uint64_t>(gWriteOff);
  out[gpuctl::kStChanges] = gChanges;
  out[gpuctl::kStReverts] = gReverts;
  out[gpuctl::kStLastReply] = static_cast<uint64_t>(gLastReply);
  out[gpuctl::kStOd8Held] =
      gOd8Dirty ? (gOd8Held != 0 ? gOd8Held : gpuctl::kOd8HeldUnknown) : 0;
  out[gpuctl::kStOd8Changes] = gOd8Changes;
  out[gpuctl::kStOd8Reverts] = gOd8Reverts;
  out[gpuctl::kStOd8Check] = static_cast<uint64_t>(gOd8LastCheck);
  IOLockUnlock(gStateLock);
}

gpuctl::Reply GPUControl::arm(bool administrator) {
  if (!administrator) return gpuctl::Reply::NotPrivileged;
  if (gStateLock == nullptr) return gpuctl::Reply::Off;
  // The one way writing opens: never on a read-only card, whoever asks.
  if (gReadOnlyCard) return gpuctl::Reply::Off;
  checkRuntime();
  IOLockLock(gStateLock);
  gpuctl::Reply r =
      gpuctl::armCheck(administrator, gOwner,
                       gpuctl::bootValuePlausible(bootW()), readyLocked());
  if (r == gpuctl::Reply::Ok && !gOwner.arm()) r = gpuctl::Reply::Off;
  IOLockUnlock(gStateLock);
  if (r == gpuctl::Reply::Ok) SYSLOG("gpuctl", "armed until restart");
  return r;
}
gpuctl::Reply GPUControl::disarm(bool administrator) {
  // No privilege needed (disarmCheck): closing only makes it safer.
  if (gStateLock == nullptr) return gpuctl::Reply::Off;
  IOLockLock(gStateLock);
  // What only the kext knows is still applied or being handled: a lower
  // limit or an OD8 state not confirmed back, a way back waiting, a request
  // waiting or running in the slot (an answer not collected yet is not).
  bool holds = changedLocked() || gHeldW != 0 || gLimitUnknown || gOd8Dirty ||
               gPendingRevert != 0 || gSlot.busy();
  bool was = gOwner.isArmed();
  gpuctl::Reply r = gpuctl::disarmCheck(administrator, gOwner, holds);
  if (r == gpuctl::Reply::Ok && !gOwner.disarm())
    r = gpuctl::Reply::StillApplied;
  IOLockUnlock(gStateLock);
  if (r == gpuctl::Reply::Ok && was)
    SYSLOG("gpuctl", "closed again (disarm by %s)",
           administrator ? "an administrator" : "a program");
  return r;
}

gpuctl::Reply GPUControl::set(uint64_t client, uint64_t rawWatts,
                              const uint32_t* closedFlag) {
  if (gStateLock == nullptr) return gpuctl::Reply::Off;
  checkRuntime();
  uint32_t boot = bootW();
  // Before gStateLock (it takes gOd8Lock); fixed once known.
  uint32_t floor = rangeNow().floorW;
  uint32_t watts = 0;
  IOLockLock(gStateLock);
  // The connection's own flag, set by closed() under this lock: a set that
  // got past externalMethod's check while the connection closed stops here.
  if (closedFlag != nullptr && __atomic_load_n(closedFlag, __ATOMIC_ACQUIRE)) {
    IOLockUnlock(gStateLock);
    return gpuctl::Reply::Cancelled;
  }
  uint64_t now = nowMs();
  bool wake = false;
  uint64_t id = gOwner.expired(now);
  if (id != 0) {
    gPendingRevert = id;
    wake = true;
  }
  gpuctl::Reply r = gpuctl::Reply::Ok;
  uint64_t ticket = 0;
  if (client == 0) {
    r = gpuctl::Reply::BadArgs;
  } else if (gReadOnlyCard) {
    r = gpuctl::Reply::Off;
  } else if ((r = gpuctl::setWire(gOwner, rawWatts, &watts)) !=
             gpuctl::Reply::Ok) {
    // off or not armed, before the value; then a value that is no watts
  } else {
    switch (gpuctl::routeSet(boot, floor, watts)) {
      case gpuctl::SetRoute::Refuse:
        r = gpuctl::replyFor(gpuctl::checkPower(boot, floor, watts));
        break;
      case gpuctl::SetRoute::Release:
        // The start-up value is going back, never a change.
        gSlot.abandonClient(client);
        IOLockWakeup(gStateLock, &gSlot, false);  // its other set, if any
        id = gOwner.release(client);
        if (id != 0) {
          gPendingRevert = id;
          wake = true;
        }
        break;
      case gpuctl::SetRoute::Change:
        r = gpuctl::replyFor(gOwner.wouldChange(client, now));
        if (r == gpuctl::Reply::Ok && !readyLocked())
          r = gpuctl::Reply::NotReady;
        if (r == gpuctl::Reply::Ok && gOd8Dirty)
          r = gpuctl::Reply::Busy;  // an OD8 change is held: never both
        if (r == gpuctl::Reply::Ok) {
          ticket = gSlot.post(client, watts);
          if (ticket == 0)
            r = gpuctl::Reply::Busy;
          else
            gSlotKind = 0;
        }
        break;
    }
  }
  if (ticket != 0) {
    IOLockUnlock(gStateLock);
    signalWorker();
    IOLockLock(gStateLock);
    uint64_t deadline = 0;
    clock_interval_to_deadline(static_cast<uint32_t>(gpuctl::kSetWaitMs),
                               kMillisecondScale, &deadline);
    while (!gSlot.collect(ticket, &r)) {
      int w =
          IOLockSleepDeadline(gStateLock, &gSlot, deadline, THREAD_ABORTSAFE);
      if (w == THREAD_AWAKENED) continue;
      if (gSlot.collect(ticket, &r)) break;
      // 5 s, or interrupted: drop the request; whatever this program holds
      // goes back, after any 0x6e still running.
      gSlot.abandon(ticket);
      if (gOwner.owner() == client) {
        id = gOwner.release(client);
        if (id != 0) gPendingRevert = id;
      }
      r = gpuctl::Reply::Timeout;
      wake = true;
      break;
    }
  }
  if (ticket != 0 || r != gpuctl::Reply::Ok) gLastReply = r;
  IOLockUnlock(gStateLock);
  if (wake) signalWorker();
  return r;
}

gpuctl::Reply GPUControl::alive(uint64_t client) {
  if (gStateLock == nullptr) return gpuctl::Reply::Off;
  IOLockLock(gStateLock);
  bool ok = gOwner.alive(client, nowMs());
  IOLockUnlock(gStateLock);
  if (ok) signalWorker();  // the owner's deadline moved; anyone else: nothing
  return ok ? gpuctl::Reply::Ok : gpuctl::Reply::NotOwner;
}

gpuctl::Reply GPUControl::release(uint64_t client) {
  if (gStateLock == nullptr) return gpuctl::Reply::Off;
  IOLockLock(gStateLock);
  gSlot.abandonClient(client);  // a release always wins over its own set
  uint64_t id = gOwner.release(client);
  if (id != 0) gPendingRevert = id;
  IOLockWakeup(gStateLock, &gSlot, false);
  IOLockUnlock(gStateLock);
  if (id != 0) signalWorker();
  return gpuctl::Reply::Ok;
}

bool GPUControl::closed(uint64_t client, uint32_t* closedFlag) {
  if (gStateLock == nullptr) {
    uint32_t was = 0;
    return closedFlag == nullptr ||
           __atomic_compare_exchange_n(closedFlag, &was, 1, false,
                                       __ATOMIC_ACQ_REL, __ATOMIC_RELAXED);
  }
  IOLockLock(gStateLock);
  if (closedFlag != nullptr) {
    if (__atomic_load_n(closedFlag, __ATOMIC_ACQUIRE) != 0) {
      IOLockUnlock(gStateLock);
      return false;  // closed once already
    }
    __atomic_store_n(closedFlag, 1, __ATOMIC_RELEASE);
  }
  if (client == 0) {
    IOLockUnlock(gStateLock);
    return true;
  }
  gSlot.abandonClient(client);
  uint64_t id = gOwner.closed(client);
  if (id != 0) gPendingRevert = id;
  IOLockWakeup(gStateLock, &gSlot, false);  // its set, if one waits
  IOLockUnlock(gStateLock);
  if (id != 0) signalWorker();
  return true;
}

const char* GPUControl::writeText() {
  if (gStateLock == nullptr) return "off";
  checkRuntime();
  IOLockLock(gStateLock);
  const char* text;
  if (gOwner.isReadOnly())
    text = !gTried ? "read only: this card can only be read; waiting for the "
                     "driver's library"
                   : "read only: this card can only be read (see WriteState)";
  else if (gOwner.isOff())
    text = "off until restart: see WriteState";
  else if (!readyLocked())
    text = gWorkerUp ? "waiting for the power management and its start-up limit"
                     : "waiting for the driver's library";
  else if (!gOwner.isArmed())
    text = "closed: sudo gpucontrol arm opens it until restart";
  else if (sleepingLocked())
    text = "armed: the Mac is between sleep and wake";
  else if (gOwner.isReverting() || gPendingRevert != 0)
    text = "armed: going back to the start-up limit";
  // One program holds one thing at a time, the power limit or an OD8 change,
  // and Owner marks both as changed: say which one it is.
  else if (gOwner.owner() != 0 && gOwner.isChanged() && gHeldW != 0)
    text = "armed: a program holds a lower limit";
  else if (gOwner.owner() != 0 && gOwner.isChanged() && gOd8Dirty)
    text = "armed: a program holds a fan or clock change (OD8Write); the "
           "power limit is the start-up one";
  else if (gOwner.owner() != 0 && gOwner.isChanged())
    text = "armed: a program is setting a limit";
  else
    text = "armed: nothing held";
  IOLockUnlock(gStateLock);
  return text;
}

bool GPUControl::writeState(WriteState* out) {
  if (out == nullptr || gStateLock == nullptr) return false;
  checkRuntime();
  IOLockLock(gStateLock);
  out->off = gWriteOff;
  out->armed = gOwner.isArmed();
  out->owned = gOwner.owner() != 0;
  out->heldW = gHeldW != 0 ? gHeldW : bootW();
  out->changes = gChanges;
  out->reverts = gReverts;
  out->lastReply = gLastReply;
  IOLockUnlock(gStateLock);
  return true;
}

// ----------------------------------------------------------------- OD8 ----

const char* GPUControl::od8Text() {
  if (gOff || gStateLock == nullptr || gOd8Lock == nullptr) return "off";
  if (__atomic_load_n(&gSecondObject, __ATOMIC_ACQUIRE) != 0)
    return "off: a second power object showed up";
  IOLockLock(gStateLock);
  bool up = gWorkerUp;
  IOLockUnlock(gStateLock);
  IOLockLock(gOd8Lock);
  gpuctl::Od8Read r = gOd8State;
  IOLockUnlock(gOd8Lock);
  if (r == gpuctl::Od8Read::Waiting) {
    if (!gTried) return "waiting for the driver's library";
    if (!up) return "off: the control's worker does not run (see WriteState)";
  }
  return gpuctl::od8ReadText(r);
}

namespace {
void od8Number(OSDictionary* d, const char* key, uint32_t v) {
  auto n = OSNumber::withNumber(static_cast<unsigned long long>(v), 32);
  if (n) {
    d->setObject(key, n);
    n->release();
  }
}
void od8Signed(OSDictionary* d, const char* key, int32_t v) {
  od8Number(d, key, static_cast<uint32_t>(v));
}
// [[temperature C, speed %] x 5] from one set of 38 values.
OSArray* od8Curve(const int32_t* values) {
  auto a = OSArray::withCapacity(gpuctl::kOd8CurvePoints);
  if (a == nullptr) return nullptr;
  for (uint32_t k = 0; k < gpuctl::kOd8CurvePoints; k++) {
    auto p = OSArray::withCapacity(2);
    if (p == nullptr) continue;
    uint32_t pair[2] = {
        static_cast<uint32_t>(values[gpuctl::od8CurveTempId(k)]),
        static_cast<uint32_t>(values[gpuctl::od8CurveSpeedId(k)])};
    for (uint32_t v : pair) {
      auto n = OSNumber::withNumber(static_cast<unsigned long long>(v), 32);
      if (n) {
        p->setObject(n);
        n->release();
      }
    }
    a->setObject(p);
    p->release();
  }
  return a;
}
}  // namespace

namespace {
// What od8Dictionary copies under gOd8Lock (about 2.3 KB, on the heap).
struct Od8Copy {
  uint32_t reads, tries, lastRet, oddEntry, oddEscape;
  bool haveStock, haveCurrent, stockOdd, defaultsMoved, currentMoved;
  uint64_t lastReadMs;
  gpuctl::Od8InitialOut stock;
  gpuctl::Od8InitialOut latest;
  gpuctl::Od8CurrentOut current;
};
}  // namespace

OSDictionary* GPUControl::od8Dictionary() {
  if (gOff || gOd8Lock == nullptr) return nullptr;
  auto c = static_cast<Od8Copy*>(IOMalloc(sizeof(Od8Copy)));
  if (c == nullptr) return nullptr;
  IOLockLock(gOd8Lock);
  c->tries = gOd8Tries;
  c->reads = gOd8Reads;
  c->lastRet = gOd8LastRet;
  c->oddEntry = gOd8OddEntry;
  c->oddEscape = gOd8OddEscape;
  c->haveStock = gOd8HaveStock;
  c->haveCurrent = gOd8HaveCurrent;
  c->stockOdd = gOd8StockOdd;
  c->defaultsMoved = gOd8DefaultsMoved;
  c->currentMoved = !gpuctl::od8SameCurrent(gOd8BootCurrent, gOd8Current);
  c->lastReadMs = gOd8LastReadMs;
  c->stock = gOd8Stock;
  c->latest = gOd8Latest;
  c->current = gOd8Current;
  IOLockUnlock(gOd8Lock);
  OSDictionary* d = c->tries != 0 ? OSDictionary::withCapacity(16) : nullptr;
  if (d != nullptr) {
    od8Number(d, "Reads", c->reads);
    od8Number(d, "Tries", c->tries);
    od8Number(d, "LastResult", c->lastRet);
    if (c->oddEntry != 0) {
      od8Number(d, "OddEntry", c->oddEntry);
      od8Number(d, "OddEscape", c->oddEscape);
    }
    if (c->haveStock && c->haveCurrent) {
      uint64_t now = nowMs();
      od8Number(d, "LastReadAgeS",
                static_cast<uint32_t>((now - c->lastReadMs) / 1000));
      od8Number(d, "Caps", c->stock.caps);
      od8Number(d, "NotAllowed", c->current.notAllowed);
      od8Number(d, "StockOdd", c->stockOdd);
      od8Number(d, "DefaultsMoved", c->defaultsMoved);
      od8Number(d, "CurrentMoved", c->currentMoved);
      int32_t stock[gpuctl::kOd8Count];
      for (uint32_t i = 0; i < gpuctl::kOd8Count; i++)
        stock[i] = c->stock.e[i].def;
      if (auto a = od8Curve(stock)) {
        d->setObject("FanCurveStock", a);
        a->release();
      }
      if (auto a = od8Curve(c->current.cur)) {
        d->setObject("FanCurve", a);
        a->release();
      }
      auto all = OSDictionary::withCapacity(gpuctl::kOd8Count);
      if (all) {
        for (uint32_t i = 0; i < gpuctl::kOd8Count; i++) {
          const gpuctl::Od8Entry& e = c->stock.e[i];
          int32_t cur = c->current.cur[i];
          if (e.feature == 0 && e.min == 0 && e.max == 0 && e.def == 0 &&
              cur == 0)
            continue;  // nothing there for this card
          auto s = OSDictionary::withCapacity(6);
          if (s == nullptr) continue;
          od8Number(s, "Feature", e.feature);
          od8Signed(s, "Min", e.min);
          od8Signed(s, "Max", e.max);
          od8Signed(s, "Stock", e.def);
          od8Signed(s, "Default", c->latest.e[i].def);
          od8Signed(s, "Current", cur);
          all->setObject(gpuctl::od8Name(i), s);
          s->release();
        }
        d->setObject("Settings", all);
        all->release();
      }
    }
  }
  IOFree(c, sizeof(Od8Copy));
  return d;
}

// ---------------------------------------------------- OD8 writes, channel ----

gpuctl::Reply GPUControl::setOd8(uint64_t client, const uint64_t* in,
                                 const uint32_t* closedFlag, uint32_t* check) {
  *check = 0;
  gpuctl::Od8Want want{};
  if (gStateLock == nullptr) return gpuctl::Reply::Off;
  checkRuntime();
  bool ready = od8Ready();
  IOLockLock(gStateLock);
  if (closedFlag != nullptr && __atomic_load_n(closedFlag, __ATOMIC_ACQUIRE)) {
    IOLockUnlock(gStateLock);
    return gpuctl::Reply::Cancelled;
  }
  uint64_t now = nowMs();
  bool wake = false;
  uint64_t id = gOwner.expired(now);
  if (id != 0) {
    gPendingRevert = id;
    wake = true;
  }
  gpuctl::Reply r = gpuctl::Reply::Ok;
  uint64_t ticket = 0;
  if (client == 0) {
    r = gpuctl::Reply::BadArgs;
  } else if (gReadOnlyCard) {
    r = gpuctl::Reply::Off;
  } else if ((r = gpuctl::od8Wire(gOwner, in, &want)) != gpuctl::Reply::Ok) {
    // off or not armed, before any value; then a malformed state
  } else if (gpuctl::od8IsStock(want)) {
    // The stock state is the way back, never a change.
    if (gOwner.owner() != 0 && gOwner.owner() != client) {
      r = gpuctl::Reply::Busy;  // another program's change: not this one's
    } else if (gOd8Dirty || gOwner.owner() == client) {
      gSlot.abandonClient(client);
      IOLockWakeup(gStateLock, &gSlot, false);
      id = gOwner.release(client);
      if (id != 0) {
        gPendingRevert = id;
        wake = true;
      }
    }
  } else {
    r = gpuctl::replyFor(gOwner.wouldChange(client, now));
    if (r == gpuctl::Reply::Ok && (!readyLocked() || !ready))
      r = gpuctl::Reply::NotReady;
    if (r == gpuctl::Reply::Ok && (gHeldW != 0 || gLimitUnknown))
      r = gpuctl::Reply::Busy;  // a power change is held: never both
    if (r == gpuctl::Reply::Ok) {
      ticket = gSlot.post(client, 0);
      if (ticket == 0) {
        r = gpuctl::Reply::Busy;
      } else {
        gSlotKind = 1;
        gSlotWant = want;
        gSlotCheck = 0;
      }
    }
  }
  if (ticket != 0) {
    IOLockUnlock(gStateLock);
    signalWorker();
    IOLockLock(gStateLock);
    uint64_t deadline = 0;
    clock_interval_to_deadline(static_cast<uint32_t>(gpuctl::kSetWaitMs),
                               kMillisecondScale, &deadline);
    while (!gSlot.collect(ticket, &r)) {
      int w =
          IOLockSleepDeadline(gStateLock, &gSlot, deadline, THREAD_ABORTSAFE);
      if (w == THREAD_AWAKENED) continue;
      if (gSlot.collect(ticket, &r)) break;
      gSlot.abandon(ticket);
      if (gOwner.owner() == client) {
        id = gOwner.release(client);
        if (id != 0) gPendingRevert = id;
      }
      r = gpuctl::Reply::Timeout;
      wake = true;
      break;
    }
    if (r == gpuctl::Reply::Od8Refused) *check = gSlotCheck;
  }
  if (ticket != 0 || r != gpuctl::Reply::Ok) gLastReply = r;
  IOLockUnlock(gStateLock);
  if (wake) signalWorker();
  return r;
}

const char* GPUControl::od8WriteText() {
  if (gStateLock == nullptr) return "off";
  bool ready = od8Ready();
  IOLockLock(gStateLock);
  const char* text;
  if (gOwner.isReadOnly())
    text = !gTried ? "read only: this card can only be read; waiting for the "
                     "driver's library"
                   : "read only: this card can only be read (see WriteState)";
  else if (gOwner.isOff())
    text = "off until restart: see WriteState";
  else if (!ready)
    text = "waiting for a clean OD8 read (OD8State)";
  else if (!gOwner.isArmed())
    text = "closed: sudo gpucontrol arm opens it until restart";
  else if ((gOd8Held & gpuctl::kOd8HeldUnknown) != 0)
    text = "armed: the last OD8 call was not taken; going back to stock";
  else if (gOd8Dirty && gOd8Held != 0)
    text = "armed: a program holds a fan or clock change";
  else if (gOd8Dirty)
    text = "armed: going back to stock";
  else
    text = "armed: OD8 at stock";
  IOLockUnlock(gStateLock);
  return text;
}

bool GPUControl::od8WriteState(Od8WriteState* out) {
  if (out == nullptr || gStateLock == nullptr) return false;
  IOLockLock(gStateLock);
  out->held = gOd8Dirty ? gOd8Held : 0;
  out->dirty = gOd8Dirty;
  out->changes = gOd8Changes;
  out->reverts = gOd8Reverts;
  out->lastCheck = gOd8LastCheck;
  out->sentPower = gOd8SentPower;
  out->want = gOd8Dirty ? gOd8HeldWant : gpuctl::Od8Want{};
  IOLockUnlock(gStateLock);
  return true;
}
// ------------------------------------------------- the card's power range ----
bool GPUControl::powerRange(gpuctl::PowerRange* out) {
  if (out == nullptr || gOff || !gTried || gGpuCount == 0) return false;
  *out = rangeNow();
  return true;
}
const char* GPUControl::powerRangeText() {
  if (gOff) return "off";
  if (!gTried) return "waiting for the driver's library";
  if (gGpuCount == 0) return "off: no RX 6800 XT or RX 6900 XT";
  return gpuctl::floorStateText(rangeNow().state);
}
