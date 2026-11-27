//
//  kern_pmlog.cpp - copies the PMLog each time Apple's AMD driver reads it.
//
//  AMDRadeonX6000_AMDHardware::samplePMStatistics asks the power management
//  library (AMDRadeonX6000HWLibs, or AMDRadeonX6800HWLibs when the card is
//  set up that way) for the PMLog, a table of about 40 sensor readings, and
//  publishes seven of them in IOAccelerator's PerformanceStatistics: GPU and
//  memory clocks, fan speed and percentage, activity, board power and the
//  hotspot temperature. The edge temperature, the GFX voltage, the memory
//  activity and the PCIe link are in the table too, and thrown away.
//
//  Which ids the library fills is fixed once, when the power management starts:
//  a list for the chip that leaves the memory and VR temperatures, the memory
//  voltage, the throttler status and the video clocks off on the RX 6800 XT,
//  unless the setting PP_EnableAllPMLogSensors on the GPU's PCI device is not
//  0. The values themselves are read every second either way (the power
//  firmware's metrics table). The Navi 21 cards are found when Lilu's patcher
//  loads (the moment WhateverGreen sets its GPU properties); once the PMLog
//  function is routed, before the power management starts, this file sets that
//  property to 1 on each of them that does not have it already. -gpusensnoall
//  leaves it alone. The setting has no other use in the library.
//
//  This file routes the library's _PEM_CWDDEPM_QueryPMLogData. The route calls
//  the original first, with the same arguments, and returns its result
//  untouched; when it succeeded and the log looks filled, it copies the 2052
//  bytes. The readings are the ones the driver takes anyway, at the driver's
//  own pace.
//
//  0.9.1: the driver takes them only when someone reads the accelerator's
//  PerformanceStatistics, so with nothing outside polling nothing here is
//  fresh and the fan watchdog goes blind. While a fan curve, an OD8 change or a
//  raised power limit is held, the worker asks the library for the same log
//  itself, once a second (pmlog_logic.hpp, kKeeperMs), through the power
//  management object the driver used: one PEM_CWDDEPM_QueryPMLogData call,
//  which is one PMLog query of the power firmware, the same message a read of
//  the statistics sends. Nothing else is ever asked of the card, and nothing at
//  all while nothing is held.
//
//  The function is found by symbol and only routed when its first 17 bytes are
//  the ones in pmlog_logic.hpp. The route is a long jump (routeMultipleLong),
//  which lets another plug-in route the same function later without Lilu
//  panicking. VCNEncodeFloor routes a different function of the same library
//  (_PEM_CWDDEPM_PMRequest); the two do not meet.
//
#include "kern_pmlog.hpp"

#include <IOKit/IOLib.h>
#include <IOKit/IOLocks.h>
#include <kern/clock.h>
#include <libkern/OSAtomic.h>

#include <Headers/kern_api.hpp>
#include <Headers/kern_devinfo.hpp>
#include <Headers/kern_iokit.hpp>
#include <Headers/kern_patcher.hpp>
#include <Headers/kern_util.hpp>

#include "kern_control.hpp"

static const char* kX6000Paths[]{
    "/System/Library/Extensions/AMDRadeonX6000HWServices.kext/Contents/PlugIns/"
    "AMDRadeonX6000HWLibs.kext/Contents/MacOS/AMDRadeonX6000HWLibs"};
static const char* kX6800Paths[]{
    "/System/Library/Extensions/AMDRadeonX6000HWServices.kext/Contents/PlugIns/"
    "AMDRadeonX6800HWLibs.kext/Contents/MacOS/AMDRadeonX6800HWLibs"};
static KernelPatcher::KextInfo kHWLibs[]{
    {"com.apple.kext.AMDRadeonX6000HWLibs",
     kX6000Paths,
     arrsize(kX6000Paths),
     {},
     {},
     KernelPatcher::KextInfo::Unloaded},
    {"com.apple.kext.AMDRadeonX6800HWLibs",
     kX6800Paths,
     arrsize(kX6800Paths),
     {},
     {},
     KernelPatcher::KextInfo::Unloaded},
};
static const char* kNames[]{"AMDRadeonX6000HWLibs", "AMDRadeonX6800HWLibs"};
static_assert(arrsize(kNames) == arrsize(kHWLibs), "one name per library");

static const char* kQuerySymbol = "_PEM_CWDDEPM_QueryPMLogData";

// uint32_t PEM_CWDDEPM_QueryPMLogData(void* pem, void* in, void* out): out is
// the 2052-byte log; 0 is success (PEM_ResultToCwdde maps PP_Result_OK to 0).
using t_query = uint32_t (*)(void* pem, void* in, void* out);
static t_query orgQuery[arrsize(kHWLibs)]{};

// The library that was routed (its kHWLibs index), or arrsize(kHWLibs) before
// one is: the keeper samples through that one.
static size_t gActiveLib{arrsize(kHWLibs)};

// The power management object the driver reads the statistics with, and the
// sleep count (GPUControl::sleepCount) it was seen in. Written on whichever
// thread the driver reads on, read by the worker: single words, atomic
// builtins. PEM_CWDDEPM_QueryPMLogData uses pem[2] (the GPU's IP block state),
// pem[3] (the hardware manager) and pem[4] (PowerPlay's lock) and never looks
// at its request, so the keeper's zeroed 16-byte one is what the driver's calls
// amount to (AMDRadeonX6000HWLibs 26.7.3, 0xf6322).
static void* gPem{nullptr};
static uint64_t gPemGen{0};
static uint8_t gPemIn[16]{};

// Written only by Lilu's callbacks, which run one at a time during boot, and
// read by publish(). Each is a single word; a reader in the middle of the
// boot-time callbacks can see Status and AllSensors from two moments, and the
// next read agrees.
static PMLogCopy::Status gStatus{PMLogCopy::Status::Waiting};
static const char* gAllSensors{"not tried: the library has not loaded"};
static const char* gLibrary{""};
static IOSimpleLock* gLock{nullptr};
static uint8_t gLog[gpusens::kLogBytes];
static uint64_t gStamp{0};  // mach absolute time of the last good copy
static uint64_t gSamples{0};
// False once invalidate() dropped the copy (a wake) and until the driver reads
// the log again. gSamples keeps counting, so "since boot" stays true.
static bool gValid{false};

static bool keep(const void* out) {
  auto log = static_cast<const uint8_t*>(out);
  if (gLock == nullptr || !gpusens::plausible(log)) return false;
  uint64_t now = mach_absolute_time();
  IOSimpleLockLock(gLock);
  memcpy(gLog, log, sizeof(gLog));
  gStamp = now;
  gSamples++;
  gValid = true;
  IOSimpleLockUnlock(gLock);
  return true;
}

template <size_t K>
static uint32_t wrapQuery(void* pem, void* in, void* out) {
  uint32_t result = orgQuery[K](pem, in, out);
  if (result == 0 && out != nullptr) keep(out);
  // The object the driver is using now: the keeper asks the same one, and only
  // one seen in the current sleep count.
  // Not while the GPU sleeps (ppSleep to the end of ppWake): an object read
  // then may be gone after the wake, and the keeper once called the library
  // with one whose pem[2] was already NULL (panic in PSM_IsIPState,
  // 2026-11-27). The pointer goes first and the generation second, so a
  // reader that loads the generation first never pairs a new generation with
  // an old pointer.
  if (pem != nullptr && !GPUControl::inSleep()) {
    __atomic_store_n(&gPem, pem, __ATOMIC_RELEASE);
    __atomic_store_n(&gPemGen, GPUControl::sleepCount(), __ATOMIC_RELEASE);
  }
  return result;
}
static_assert(arrsize(kHWLibs) == 2, "one wrapper per library");
static void* const kWrappers[]{reinterpret_cast<void*>(wrapQuery<0>),
                               reinterpret_cast<void*>(wrapQuery<1>)};

// The Navi 21 cards, found when the patcher loads and kept (retained) until
// one of the libraries is routed. Lilu calls the patcher callbacks before any
// kext callback; findGpus also handles the other order. A card's reference is
// only given back once the property is set: a library that fails to route may
// be followed by the other one, and a device kept for the whole uptime costs
// nothing.
constexpr size_t kMaxGpus = 4;
static IORegistryEntry* gGpus[kMaxGpus]{};
static size_t gGpuCount{0};

// The value an existing PP_EnableAllPMLogSensors holds, read the way the
// driver's registry callback reads it: a number, a boolean, or the first bytes
// of a data object.
static bool existingValue(const OSObject* obj, uint32_t* value) {
  if (auto n = OSDynamicCast(OSNumber, obj)) {
    *value = n->unsigned32BitValue();
    return true;
  }
  if (auto b = OSDynamicCast(OSBoolean, obj)) {
    *value = b->isTrue() ? 1 : 0;
    return true;
  }
  if (auto d = OSDynamicCast(OSData, obj)) {
    uint32_t v = 0;
    size_t n = d->getLength() < sizeof(v) ? d->getLength() : sizeof(v);
    if (n) memcpy(&v, d->getBytesNoCopy(), n);
    *value = v;
    return true;
  }
  return false;
}

static void requestAllSensors() {
  if (gGpuCount == 0) return;
  size_t set = 0;
  for (size_t i = 0; i < gGpuCount; i++) {
    if (gGpus[i]->setProperty(gpusens::kEnableAllKey, 1ULL, 32)) set++;
    gGpus[i]->release();
    gGpus[i] = nullptr;
  }
  gAllSensors = set == gGpuCount ? "requested"
                                 : "not set: the GPU did not take the property";
  gGpuCount = 0;
  SYSLOG("gpusens", "all sensors: %s", gAllSensors);
}

static void findGpus(void*, KernelPatcher&) {
  if (checkKernelArgument("-gpusensnoall")) {
    gAllSensors = "off: -gpusensnoall";
    SYSLOG("gpusens", "all sensors: %s", gAllSensors);
    return;
  }
  auto info = DeviceInfo::create();
  if (info == nullptr) {
    gAllSensors = "not set: no list of devices";
    SYSLOG("gpusens", "all sensors: %s", gAllSensors);
    return;
  }
  size_t on = 0, off = 0;
  for (size_t i = 0; i < info->videoExternal.size(); i++) {
    auto& gpu = info->videoExternal[i];
    uint32_t device = 0;
    if (gpu.video == nullptr || gpu.vendor != WIOKit::VendorID::ATIAMD ||
        !WIOKit::getOSDataValue(gpu.video, "device-id", device) ||
        !gpusens::isNavi21(device))
      continue;
    // A value from the OpenCore DeviceProperties is left as it is.
    uint32_t value = 0;
    auto existing = gpu.video->getProperty(gpusens::kEnableAllKey);
    if (existing != nullptr) {
      if (existingValue(existing, &value) && value == 0)
        off++;
      else
        on++;
    } else if (gGpuCount < kMaxGpus) {
      gpu.video->retain();
      gGpus[gGpuCount++] = gpu.video;
    }
  }
  DeviceInfo::deleter(info);
  if (gGpuCount != 0) {
    if (gStatus == PMLogCopy::Status::Active)
      requestAllSensors();
    else if (gStatus == PMLogCopy::Status::Waiting)
      gAllSensors = "waiting for the PMLog function to be routed";
    else
      gAllSensors = "not set: the PMLog function is not routed";
    return;
  }
  gAllSensors = off  ? "off: set to 0 in the OpenCore DeviceProperties"
                : on ? "already set (OpenCore DeviceProperties)"
                     : "not set: no Navi 21 card found";
  SYSLOG("gpusens", "all sensors: %s", gAllSensors);
}

static void routeLibrary(KernelPatcher& patcher, size_t index,
                         mach_vm_address_t address, size_t size) {
  size_t k = arrsize(kHWLibs);
  for (size_t i = 0; i < arrsize(kHWLibs); i++)
    if (kHWLibs[i].loadIndex == index) k = i;
  if (k == arrsize(kHWLibs)) return;
  gLibrary = kNames[k];

  auto query = patcher.solveSymbol(index, kQuerySymbol, address, size);
  if (query == 0) {
    patcher.clearError();
    SYSLOG("gpusens", "%s: PMLog function not found, doing nothing", kNames[k]);
    gStatus = PMLogCopy::Status::NoSymbol;
    return;
  }
  auto entry = reinterpret_cast<const uint8_t*>(query);
  size_t available = static_cast<size_t>(address + size - query);
  if (gpusens::entryIsRouted(entry, available)) {
    SYSLOG("gpusens", "%s: another kext already routes the PMLog function",
           kNames[k]);
    gStatus = PMLogCopy::Status::AlreadyRouted;
    return;
  }
  if (!gpusens::entryMatches(entry, available)) {
    SYSLOG("gpusens", "%s: PMLog function does not start as expected",
           kNames[k]);
    gStatus = PMLogCopy::Status::UnknownEntry;
    return;
  }
  KernelPatcher::RouteRequest requests[]{
      {kQuerySymbol, kWrappers[k], orgQuery[k]},
  };
  bool routed = patcher.routeMultipleLong(index, requests, address, size);
  auto error = patcher.getError();
  patcher.clearError();
  // Lilu can report success after failing to write the jump, so it is only
  // believed when there is no error, the original came back and the entry
  // really changed.
  if (routed && error == KernelPatcher::Error::NoError &&
      orgQuery[k] != nullptr && gpusens::entryIsRouted(entry, available)) {
    SYSLOG("gpusens", "%s: active", kNames[k]);
    gActiveLib = k;
    gStatus = PMLogCopy::Status::Active;
  } else {
    SYSLOG("gpusens", "%s: route failed (%d), nothing changed", kNames[k],
           error);
    gStatus = PMLogCopy::Status::RouteFailed;
  }
}

static void onHWLibsLoad(void*, KernelPatcher& patcher, size_t index,
                         mach_vm_address_t address, size_t size) {
  // Once one library is routed, a later call (the other library, or the same
  // one again) must not overwrite that, nor route anything twice.
  if (gStatus == PMLogCopy::Status::Active) return;
  routeLibrary(patcher, index, address, size);
  // The GPU control routes its own functions of the same library (only the
  // first library it is given; it ignores later calls).
  for (size_t i = 0; i < arrsize(kHWLibs); i++)
    if (kHWLibs[i].loadIndex == index)
      GPUControl::onLibrary(patcher, index, address, size, kNames[i]);
  // Lilu also calls this for kexts other plug-ins asked for; routeLibrary
  // ignores those and the status stays Waiting.
  if (gStatus == PMLogCopy::Status::Active)
    requestAllSensors();
  else if (gStatus != PMLogCopy::Status::Waiting && gGpuCount != 0)
    gAllSensors = "not set: the PMLog function is not routed";
}

void PMLogCopy::init() {
  gLock = IOSimpleLockAlloc();
  if (gLock == nullptr) {
    gStatus = Status::RegistrationFailed;
    gAllSensors = "not set: the kext could not start";
    return;
  }
  auto error =
      lilu.onKextLoad(kHWLibs, arrsize(kHWLibs), onHWLibsLoad, nullptr);
  if (error != LiluAPI::Error::NoError) {
    SYSLOG("gpusens", "could not register with Lilu (%d), doing nothing",
           error);
    gStatus = Status::RegistrationFailed;
    gAllSensors = "not set: could not register with Lilu";
    return;
  }
  if (lilu.onPatcherLoad(findGpus, nullptr) != LiluAPI::Error::NoError)
    gAllSensors = "not set: could not register with Lilu";
}

PMLogCopy::Status PMLogCopy::status() { return gStatus; }

const char* PMLogCopy::library() { return gLibrary; }

const char* PMLogCopy::allSensors() { return gAllSensors; }

const char* PMLogCopy::statusText() { return statusText(gStatus); }

const char* PMLogCopy::statusText(Status st) {
  switch (st) {
    case Status::Waiting:
      return "waiting for AMDRadeonX6000HWLibs or AMDRadeonX6800HWLibs";
    case Status::Active:
      return "active";
    case Status::NoSymbol:
      return "off: function not found in this library";
    case Status::UnknownEntry:
      return "off: function does not start as expected";
    case Status::RouteFailed:
      return "off: route failed";
    case Status::AlreadyRouted:
      return "off: another kext already handles this function";
    case Status::RegistrationFailed:
      return "off: could not register with Lilu";
  }
  return "off";
}

bool PMLogCopy::snapshot(uint8_t* out, uint64_t* ageNs, uint64_t* samples) {
  if (gLock == nullptr) return false;
  IOSimpleLockLock(gLock);
  uint64_t stamp = gStamp, count = gSamples;
  bool valid = gValid;
  if (valid) memcpy(out, gLog, sizeof(gLog));
  IOSimpleLockUnlock(gLock);
  if (samples) *samples = count;
  if (!valid) return false;
  if (ageNs) {
    uint64_t elapsed = mach_absolute_time() - stamp, ns = 0;
    absolutetime_to_nanoseconds(elapsed, &ns);
    *ageNs = ns;
  }
  return true;
}

void PMLogCopy::invalidate() {
  // The object seen before the sleep is not trusted after it: the keeper waits
  // for the driver's own read after the wake.
  __atomic_store_n(&gPem, static_cast<void*>(nullptr), __ATOMIC_RELEASE);
  if (gLock == nullptr) return;
  IOSimpleLockLock(gLock);
  gValid = false;
  IOSimpleLockUnlock(gLock);
}

// ----------------------------------------------------------------- keeper --

// The keeper's buffer and counters. The log is worker-only; the counters are
// loaded atomically by the ioreg readers.
static uint8_t wKeeperLog[gpusens::kLogBytes];
static uint64_t gKeeperTries{0};
static uint64_t gKeeperKept{0};
static uint64_t gKeeperRefused{0};
static uint32_t gKeeperResult{0};

// The object the keeper may ask with, or nullptr. The sleep count is read
// before and after: a sleep that starts in between makes the two differ, and
// the keeper then waits for the driver's own read after that wake. The three
// words the library reads first (pem[2], pem[3], pem[4]) must be set: if one is
// NULL the object is not one the library can use now, and the keeper does not
// ask (the library itself would fault on pem[2], see wrapQuery).
static void* pemNow() {
  if (gStatus != PMLogCopy::Status::Active || gActiveLib >= arrsize(kHWLibs) ||
      orgQuery[gActiveLib] == nullptr || GPUControl::inSleep())
    return nullptr;
  uint64_t before = GPUControl::sleepCount();
  uint64_t seen = __atomic_load_n(&gPemGen, __ATOMIC_ACQUIRE);
  void* pem = __atomic_load_n(&gPem, __ATOMIC_ACQUIRE);
  if (pem == nullptr || seen != before || GPUControl::sleepCount() != before)
    return nullptr;
  void* const* words = static_cast<void* const*>(pem);
  if (words[2] == nullptr || words[3] == nullptr || words[4] == nullptr)
    return nullptr;
  return pem;
}

bool PMLogCopy::canSample() { return pemNow() != nullptr; }

bool PMLogCopy::sampleNow() {
  void* pem = pemNow();
  if (pem == nullptr) return false;
  t_query org = orgQuery[gActiveLib];
  // The library clears the log itself once it gets to the hardware
  // (PECI_ClearMemory, AMDRadeonX6000HWLibs 0xf6390); zeroing here covers the
  // answers that come before that (the GPU's IP block off, hardware access
  // blocked in a sleep), so an old reading is never kept with a new stamp.
  memset(wKeeperLog, 0, sizeof(wKeeperLog));
  __atomic_add_fetch(&gKeeperTries, 1, __ATOMIC_RELAXED);
  uint32_t r = org(pem, gPemIn, wKeeperLog);
  __atomic_store_n(&gKeeperResult, r, __ATOMIC_RELAXED);
  if (r == 0 && keep(wKeeperLog)) {
    __atomic_add_fetch(&gKeeperKept, 1, __ATOMIC_RELAXED);
    return true;
  }
  __atomic_add_fetch(&gKeeperRefused, 1, __ATOMIC_RELAXED);
  return false;
}

void PMLogCopy::keeperCounts(uint64_t* tries, uint64_t* samples,
                             uint64_t* refused, uint32_t* lastResult) {
  if (tries) *tries = __atomic_load_n(&gKeeperTries, __ATOMIC_RELAXED);
  if (samples) *samples = __atomic_load_n(&gKeeperKept, __ATOMIC_RELAXED);
  if (refused) *refused = __atomic_load_n(&gKeeperRefused, __ATOMIC_RELAXED);
  if (lastResult)
    *lastResult = __atomic_load_n(&gKeeperResult, __ATOMIC_RELAXED);
}

const char* PMLogCopy::keeperText(bool held) {
  if (!held) return "off: nothing held";
  if (gStatus != Status::Active) return "off: the PMLog function is not routed";
  if (!canSample())
    return "off: no reading from the driver since the last sleep";
  return "on: one sample a second while something is held";
}
