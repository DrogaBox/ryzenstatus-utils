//
//  kern_service.cpp - see kern_service.hpp.
//
//  Properties, all rebuilt when read:
//    Status, StatusCode, Library   what the kext did at boot
//    AllSensors                    what became of PP_EnableAllPMLogSensors
//    Samples                       good logs copied since boot
//    SampleAgeMs                   how old the last one is
//    Sensors                       { name: value } for the named ids
//                                  (pmlog_logic.hpp) the card marks supported
//    Units                         { name: unit } for the same names
//    PMLog                         { "id": value } for the same readings,
//                                  by AMD's id, as the driver filled them
//    Control                       what the GPU control did (kern_control.cpp)
//    Profile                       the boot profile: asked, set, or why not
//    ProfileSet                    the value set, once it was
//    ProfileRequests               { Last, Seen, Calls }: the profile the
//                                  driver's clients asked for
//    Power                         the power watch: what it watches, or why not
//    PowerWatch                    { BootW, LastReadW, Reads, Sent, LastSentW,
//                                  LastSentSource, LastSentResult, Sleeps,
//                                  Wakes }, each only when its function is
//                                  watched (BootW and LastReadW once read,
//                                  LastSent* once Sent > 0)
//    Write                         the power limit write path (0.5.0): off,
//                                  waiting, closed, or armed and what it holds
//    WriteState                    { WriteOff, WriteOffText, Armed, Owned,
//                                  HeldW, Changes, Reverts, LastReply }
//    PowerRangeState               the card's power range (0.8.0): where the
//                                  floor comes from, or why it is not known
//    PowerRange                    { FloorW, MaxW, StepW, PercentMin,
//                                  PercentMax, Known }: the lowest and highest
//                                  limit set takes; Known 1 with FloorW and
//                                  MaxW once the floor is known (FloorW = MaxW
//                                  when the card offers nothing lower);
//                                  PercentMin/Max once OD8 was read
//    OD8State                      OD8 (0.6.0, read only): waiting, read,
//                                  not available, or why not
//    OD8                           { Reads, Tries, LastResult, LastReadAgeS,
//                                  Caps, NotAllowed, StockOdd, DefaultsMoved,
//                                  CurrentMoved,
//                                  FanCurveStock, FanCurve, Settings: { name:
//                                  { Feature, Min, Max, Stock, Current } } }
//                                  once tried; OddEntry/OddEscape when an
//                                  answer was not as expected
//
#include "kern_service.hpp"

#include <libkern/c++/OSArray.h>
#include <libkern/c++/OSDictionary.h>
#include <libkern/c++/OSNumber.h>
#include <libkern/c++/OSString.h>

#include <Headers/kern_version.hpp>
#include <Headers/plugin_start.hpp>

#include "kern_control.hpp"
#include "kern_pmlog.hpp"

OSDefineMetaClassAndStructors(DrogaBoxGPUSensors, IOService);
OSDefineMetaClassAndStructors(DrogaBoxGPUControlClient, IOUserClient);

IOService* DrogaBoxGPUSensors::probe(IOService* provider, SInt32* score) {
  auto service = IOService::probe(provider, score);
  return ADDPR(startSuccess) ? service : nullptr;
}

// Serialises readers: they share the 2 KB buffer below, kept off the kernel
// stack. A function-local static would need a C++ guard the kernel does not
// have, so both live at file scope and the lock is made in start().
static IOLock* gReadLock{nullptr};
static uint8_t gReadLog[gpusens::kLogBytes];

bool DrogaBoxGPUSensors::start(IOService* provider) {
  if (!IOService::start(provider)) return false;
  if (gReadLock == nullptr) gReadLock = IOLockAlloc();
  setProperty("VersionInfo", kextVersion);
  publish();
  registerService();
  return ADDPR(startSuccess);
}

static void putNumber(OSDictionary* d, const char* key, uint64_t v) {
  auto n = OSNumber::withNumber(v, 64);
  if (n == nullptr) return;
  d->setObject(key, n);
  n->release();
}

static void putSigned32(OSDictionary* d, const char* key, int32_t v) {
  auto n = OSNumber::withNumber(
      static_cast<unsigned long long>(static_cast<uint32_t>(v)), 32);
  if (n == nullptr) return;
  d->setObject(key, n);
  n->release();
}
// Runs in the reader's context (ioreg, a monitor app), never in the driver's
// path, so it may allocate.
void DrogaBoxGPUSensors::publish() {
  IOLock* lock = gReadLock;
  if (lock == nullptr) return;
  IOLockLock(lock);
  // One read of the status, so Status and StatusCode always agree; two
  // readers at once cannot interleave their updates.
  auto status = PMLogCopy::status();
  setProperty("Status", PMLogCopy::statusText(status));
  setProperty("StatusCode", static_cast<uint32_t>(status), 32);
  setProperty("Library", PMLogCopy::library());
  setProperty("AllSensors", PMLogCopy::allSensors());
  setProperty("Control", GPUControl::statusText());
  setProperty("Profile", GPUControl::profileText());
  uint32_t profile = 0;
  if (GPUControl::profileSetValue(&profile))
    setProperty("ProfileSet", profile, 32);
  else
    removeProperty("ProfileSet");
  uint32_t last = 0, seen = 0;
  uint64_t calls = 0;
  if (GPUControl::requests(&last, &seen, &calls)) {
    auto r = OSDictionary::withCapacity(3);
    if (r) {
      putNumber(r, "Last", last);
      putNumber(r, "Seen", seen);
      putNumber(r, "Calls", calls);
      setProperty("ProfileRequests", r);
      r->release();
    }
  } else {
    removeProperty("ProfileRequests");
  }
  setProperty("Power", GPUControl::powerText());
  GPUControl::PowerWatch pw;
  if (GPUControl::power(&pw)) {
    auto d = OSDictionary::withCapacity(9);
    if (d) {
      if (pw.watchRead) {
        if (pw.haveBoot) putNumber(d, "BootW", pw.bootW);
        if (pw.reads != 0) putNumber(d, "LastReadW", pw.lastReadW);
        putNumber(d, "Reads", pw.reads);
      }
      if (pw.watchSent) {
        putNumber(d, "Sent", pw.sends);
        if (pw.sends != 0) {
          putNumber(d, "LastSentW", pw.lastSentW);
          putNumber(d, "LastSentSource", pw.lastSentSource);
          putNumber(d, "LastSentResult", pw.lastSentResult);
        }
      }
      if (pw.watchSleep) putNumber(d, "Sleeps", pw.sleeps);
      if (pw.watchWake) putNumber(d, "Wakes", pw.wakes);
      setProperty("PowerWatch", d);
      d->release();
    }
  } else {
    removeProperty("PowerWatch");
  }
  setProperty("Write", GPUControl::writeText());
  GPUControl::WriteState ws;
  if (GPUControl::writeState(&ws)) {
    auto d = OSDictionary::withCapacity(8);
    if (d) {
      putNumber(d, "WriteOff", static_cast<uint64_t>(ws.off));
      auto t = OSString::withCString(gpuctl::writeOffText(ws.off));
      if (t) {
        d->setObject("WriteOffText", t);
        t->release();
      }
      putNumber(d, "Armed", ws.armed);
      putNumber(d, "Owned", ws.owned);
      putNumber(d, "HeldW", ws.heldW);
      putNumber(d, "Changes", ws.changes);
      putNumber(d, "Reverts", ws.reverts);
      putNumber(d, "LastReply", static_cast<uint64_t>(ws.lastReply));
      setProperty("WriteState", d);
      d->release();
    }
  } else {
    removeProperty("WriteState");
  }
  setProperty("PowerRangeState", GPUControl::powerRangeText());
  gpuctl::PowerRange pr;
  if (GPUControl::powerRange(&pr)) {
    auto d = OSDictionary::withCapacity(6);
    if (d) {
      bool floorKnown = pr.floorW != 0;
      putNumber(d, "Known", floorKnown);
      if (floorKnown) {
        putNumber(d, "FloorW", pr.floorW);
        putNumber(d, "MaxW", pr.maxW);
      }
      putNumber(d, "StepW", gpuctl::kStepW);
      if (pr.state != gpuctl::FloorState::NoBootValue &&
          pr.state != gpuctl::FloorState::NotRead) {
        // Signed, as 32-bit numbers like the OD8 settings (-6 reads as
        // 0xfffffffa; CFNumber's SInt32 gives -6).
        putSigned32(d, "PercentMin", pr.percentMin);
        putSigned32(d, "PercentMax", pr.percentMax);
      }
      setProperty("PowerRange", d);
      d->release();
    }
  } else {
    removeProperty("PowerRange");
  }
  setProperty("OD8Write", GPUControl::od8WriteText());
  GPUControl::Od8WriteState ow;
  if (GPUControl::od8WriteState(&ow)) {
    auto d = OSDictionary::withCapacity(10);
    if (d) {
      putNumber(d, "Held", ow.held);
      putNumber(d, "Changes", ow.changes);
      putNumber(d, "Reverts", ow.reverts);
      putNumber(d, "LastCheck", static_cast<uint64_t>(ow.lastCheck));
      auto t = OSString::withCString(
          gpuctl::od8CheckText(static_cast<uint64_t>(ow.lastCheck)));
      if (t) {
        d->setObject("LastCheckText", t);
        t->release();
      }
      putNumber(d, "SentPower", ow.sentPower);
      if (ow.want.curve) {
        auto a = OSArray::withCapacity(gpuctl::kOd8CurvePoints);
        if (a) {
          for (uint32_t k = 0; k < gpuctl::kOd8CurvePoints; k++) {
            auto n = OSNumber::withNumber(
                static_cast<unsigned long long>(ow.want.temp[k]) * 1000 +
                    static_cast<unsigned long long>(ow.want.speed[k]),
                32);
            if (n) {
              a->setObject(n);
              n->release();
            }
          }
          d->setObject("FanCurveHeld", a);  // C * 1000 + %
          a->release();
        }
      }
      if (ow.want.gfxMaxMHz != 0)
        putNumber(d, "GfxMaxHeld", static_cast<uint64_t>(ow.want.gfxMaxMHz));
      setProperty("OD8WriteState", d);
      d->release();
    }
  } else {
    removeProperty("OD8WriteState");
  }
  setProperty("OD8State", GPUControl::od8Text());
  if (auto od8 = GPUControl::od8Dictionary()) {
    setProperty("OD8", od8);
    od8->release();
  } else {
    removeProperty("OD8");
  }
  uint8_t* log = gReadLog;
  uint64_t ageNs = 0, samples = 0;
  bool have = PMLogCopy::snapshot(log, &ageNs, &samples);
  setProperty("Samples", samples, 64);
  if (!have) {
    removeProperty("SampleAgeMs");
    removeProperty("Sensors");
    removeProperty("Units");
    removeProperty("PMLog");
    IOLockUnlock(lock);
    return;
  }
  setProperty("SampleAgeMs", ageNs / 1000000, 64);
  auto sensors = OSDictionary::withCapacity(gpusens::kSensorCount);
  auto units = OSDictionary::withCapacity(gpusens::kSensorCount);
  auto raw = OSDictionary::withCapacity(64);
  if (sensors && units && raw) {
    uint32_t v;
    char key[8];
    for (size_t i = 0; i < gpusens::kSensorCount; i++) {
      const auto& s = gpusens::kSensors[i];
      if (!gpusens::entry(log, s.id, &v)) continue;
      putNumber(sensors, s.key, v);
      snprintf(key, sizeof(key), "%u", static_cast<unsigned>(s.id));
      putNumber(raw, key, v);
      auto u = OSString::withCString(gpusens::unitName(s.unit));
      if (u) {
        units->setObject(s.key, u);
        u->release();
      }
    }
    setProperty("Sensors", sensors);
    setProperty("Units", units);
    setProperty("PMLog", raw);
  }
  OSSafeReleaseNULL(sensors);
  OSSafeReleaseNULL(units);
  OSSafeReleaseNULL(raw);
  IOLockUnlock(lock);
}

bool DrogaBoxGPUSensors::serializeProperties(OSSerialize* serialize) const {
  const_cast<DrogaBoxGPUSensors*>(this)->publish();
  return IOService::serializeProperties(serialize);
}

// ------------------------------------------------------------- channel --

IOReturn DrogaBoxGPUSensors::newUserClient(task_t owningTask, void* securityID,
                                           UInt32 type,
                                           OSDictionary* properties,
                                           IOUserClient** handler) {
  if (handler == nullptr || type != 0) return kIOReturnBadArgument;
  auto client = OSTypeAlloc(DrogaBoxGPUControlClient);
  if (client == nullptr) return kIOReturnNoMemory;
  if (!client->initWithTask(owningTask, securityID, type, properties)) {
    client->release();
    return kIOReturnError;
  }
  if (!client->attach(this)) {
    client->release();
    return kIOReturnError;
  }
  if (!client->start(this)) {
    client->detach(this);
    client->release();
    return kIOReturnError;
  }
  *handler = client;
  return kIOReturnSuccess;
}

bool DrogaBoxGPUControlClient::initWithTask(task_t owningTask,
                                            void* securityToken, UInt32 type,
                                            OSDictionary* properties) {
  if (!IOUserClient::initWithTask(owningTask, securityToken, type, properties))
    return false;
  id_ = GPUControl::openClient();
  return true;
}

// closed_ changes under the control's state lock (GPUControl::closed), where
// set also reads it: a set racing the close is refused, never posted after.
IOReturn DrogaBoxGPUControlClient::clientClose() {
  GPUControl::closed(id_, &closed_);
  terminate();
  return kIOReturnSuccess;
}

// The program died: the same as closing, at once.
IOReturn DrogaBoxGPUControlClient::clientDied() { return clientClose(); }

// Every call: scalars only, the channel's version first; the reply is the
// first scalar out. Wrong counts are refused by IOKit's return value, a wrong
// version by the reply.
IOReturn DrogaBoxGPUControlClient::externalMethod(
    uint32_t selector, IOExternalMethodArguments* args,
    IOExternalMethodDispatch*, OSObject*, void*) {
  if (args == nullptr || selector >= gpuctl::kSelCount)
    return kIOReturnBadArgument;
  uint32_t wantIn = selector == gpuctl::kSelSet      ? 2
                    : selector == gpuctl::kSelSetOd8 ? gpuctl::kOd8WireCount
                                                     : 1;
  uint32_t wantOut = selector == gpuctl::kSelStatus   ? gpuctl::kStatusCount
                     : selector == gpuctl::kSelSetOd8 ? 2
                                                      : 1;
  // Another version first, whatever its counts: the reply says "old
  // channel" (status still fills what fits, the version field included).
  if (args->scalarInputCount >= 1 && args->scalarInput != nullptr &&
      args->scalarInput[0] != gpuctl::kChannelVersion &&
      args->scalarOutputCount >= 1 && args->scalarOutput != nullptr) {
    uint64_t all[gpuctl::kStatusCount] = {};
    if (selector == gpuctl::kSelStatus) GPUControl::status(id_, all);
    uint32_t n = args->scalarOutputCount < gpuctl::kStatusCount
                     ? args->scalarOutputCount
                     : gpuctl::kStatusCount;
    for (uint32_t i = 0; i < n; i++) args->scalarOutput[i] = all[i];
    args->scalarOutput[0] = static_cast<uint64_t>(gpuctl::Reply::BadVersion);
    args->scalarOutputCount = n;
    return kIOReturnSuccess;
  }
  if (args->scalarInputCount != wantIn || args->scalarOutputCount < wantOut ||
      args->structureInputSize != 0 ||
      args->structureInputDescriptor != nullptr ||
      args->scalarInput == nullptr || args->scalarOutput == nullptr)
    return kIOReturnBadArgument;
  args->scalarOutputCount = wantOut;
  uint64_t* out = args->scalarOutput;
  if (selector == gpuctl::kSelStatus) {
    GPUControl::status(id_, out);
    if (args->scalarInput[0] != gpuctl::kChannelVersion)
      out[gpuctl::kStReply] = static_cast<uint64_t>(gpuctl::Reply::BadVersion);
    return kIOReturnSuccess;
  }
  gpuctl::Reply r = gpuctl::Reply::BadVersion;
  if (args->scalarInput[0] == gpuctl::kChannelVersion &&
      __atomic_load_n(&closed_, __ATOMIC_ACQUIRE) == 0) {
    switch (selector) {
      case gpuctl::kSelArm:
        r = GPUControl::arm(
            clientHasPrivilege(current_task(),
                               kIOClientPrivilegeAdministrator) ==
            kIOReturnSuccess);
        break;
      case gpuctl::kSelDisarm:  // 0.8.0: anyone may close; the flag is for
                                // the log only
        r = GPUControl::disarm(
            clientHasPrivilege(current_task(),
                               kIOClientPrivilegeAdministrator) ==
            kIOReturnSuccess);
        break;
      case gpuctl::kSelSet:
        // The value is looked at only after off and not armed (setWire).
        r = GPUControl::set(id_, args->scalarInput[1], &closed_);
        break;
      case gpuctl::kSelAlive:
        r = GPUControl::alive(id_);
        break;
      case gpuctl::kSelRelease:
        r = GPUControl::release(id_);
        break;
      case gpuctl::kSelSetOd8: {
        // {version, flags, t1..t5, s1..s5, gfxMaxMHz}, decoded by
        // gpuctl::od8Wire after off and not armed; the kext checks the rest.
        uint32_t check = 0;
        r = GPUControl::setOd8(id_, args->scalarInput, &closed_, &check);
        out[1] = check;
        break;
      }
      default:
        r = gpuctl::Reply::BadArgs;
        break;
    }
  } else if (args->scalarInput[0] == gpuctl::kChannelVersion) {
    r = gpuctl::Reply::Cancelled;
  }
  out[0] = static_cast<uint64_t>(r);
  if (selector == gpuctl::kSelSetOd8 && r != gpuctl::Reply::Od8Refused)
    out[1] = 0;
  return kIOReturnSuccess;
}
