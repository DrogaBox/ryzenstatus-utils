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
//  bytes. Nothing new is ever asked of the GPU or of its power firmware: the
//  readings are the ones the driver takes anyway, at the driver's own pace.
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

static void keep(const void* out) {
  auto log = static_cast<const uint8_t*>(out);
  if (gLock == nullptr || !gpusens::plausible(log)) return;
  uint64_t now = mach_absolute_time();
  IOSimpleLockLock(gLock);
  memcpy(gLog, log, sizeof(gLog));
  gStamp = now;
  gSamples++;
  IOSimpleLockUnlock(gLock);
}

template <size_t K>
static uint32_t wrapQuery(void* pem, void* in, void* out) {
  uint32_t result = orgQuery[K](pem, in, out);
  if (result == 0 && out != nullptr) keep(out);
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
  if (count != 0) memcpy(out, gLog, sizeof(gLog));
  IOSimpleLockUnlock(gLock);
  if (samples) *samples = count;
  if (count == 0) return false;
  if (ageNs) {
    uint64_t elapsed = mach_absolute_time() - stamp, ns = 0;
    absolutetime_to_nanoseconds(elapsed, &ns);
    *ageNs = ns;
  }
  return true;
}
