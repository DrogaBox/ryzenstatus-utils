//
//  kern_amfi.cpp - lets the two decoder plug-ins pass AMFI's library validation
//  without AMFIPass and without turning validation off for anything else.
//
//  Safari decodes video in com.apple.WebKit.GPU and VTDecoderXPCService. Both
//  are Apple platform programs with library validation: AMFI only lets them map
//  code signed by Apple. A plug-in built from this repository is ad-hoc signed,
//  so AMFI refuses it ("mapping process is a platform binary, but mapped file
//  is not").
//
//  Every refusal goes through one function in AppleMobileFileIntegrity,
//  _library_validation_failure, which returns non-zero when the library is
//  allowed after all (Apple has its own exceptions there). This file routes
//  that function. When the library being mapped is one of the plug-in builds
//  listed in cdhashes.h, compared by code directory hash, it returns 1. For
//  anything else it calls the original, so every other refusal stays exactly as
//  it was.
//
//  The code directory hash covers the plug-in's code, its Info.plist and its
//  resources, so a listed hash is one exact build. The list is written at
//  build time by build.sh. The exception holds for any program with library
//  validation and for any path: it is tied to the build, not to who loads it.
//
//  Read in IDA in the AMFI of 14.8.9 (23J631), 15.8.2 (24H232) and 26.7.2
//  (25G332); run on 26.7.3 (25G342). The function is found by symbol and only
//  routed when its first instructions are the plain prologue seen in those
//  builds (allow_logic.hpp).
//
//  The route is a long jump (routeMultipleLong): Lilu lets a plug-in loaded
//  later route the same function only over a long jump, and panics over a short
//  one. If another plug-in got there first, this one stays off.
//
#include "kern_amfi.hpp"

#include <libkern/OSAtomic.h>

#include <Headers/kern_api.hpp>
#include <Headers/kern_patcher.hpp>
#include <Headers/kern_util.hpp>

#include "allow_logic.hpp"
#include "cdhashes.h"  // generated: kAllowedCdhashes, kAllowedCdhashCount

static const char* kAMFIPaths[]{
    "/System/Library/Extensions/AppleMobileFileIntegrity.kext/Contents/MacOS/"
    "AppleMobileFileIntegrity"};
static KernelPatcher::KextInfo kextAMFI{
    "com.apple.driver.AppleMobileFileIntegrity",
    kAMFIPaths,
    arrsize(kAMFIPaths),
    {true},  // already loaded (boot kernel collection) when the patcher runs
    {},
    KernelPatcher::KextInfo::Unloaded};

// static bool _library_validation_failure(ProcessAccessor&, FileGlobAccessor&,
//     SystemFacts&, bool, const char*, unsigned long long, unsigned long)
// It is a static function, and in the builds read the compiler dropped the
// bool: the reason string arrives in rcx. All arguments are passed on as they
// came, seven register-width values, which is right for both shapes (reading
// the seventh from the caller's stack is harmless when there are only six).
using t_failure = uint64_t (*)(void* proc, void* file, void* facts, uint64_t a4,
                               uint64_t a5, uint64_t a6, uint64_t a7);
// const uint8_t* AbstractCSBlobAccessor::cdHash(); 20 bytes, or null.
// FileGlobAccessor has AbstractCSBlobAccessor as its first base, so the
// FileGlobAccessor& the failure function receives is its `this`.
using t_cdHash = const uint8_t* (*)(void* blob);

static t_failure orgFailure{nullptr};
static t_cdHash fnCdHash{nullptr};
static AmfiAllow::Status gStatus{AmfiAllow::Status::Waiting};
static SInt64 gOverrides{0};

static uint64_t allowFailure(void* proc, void* file, void* facts, uint64_t a4,
                             uint64_t a5, uint64_t a6, uint64_t a7) {
  if (file != nullptr && vcnvt::cdhashAllowed(fnCdHash(file), kAllowedCdhashes,
                                              kAllowedCdhashCount)) {
    OSIncrementAtomic64(&gOverrides);
    return 1;
  }
  return orgFailure(proc, file, facts, a4, a5, a6, a7);
}

static const char* kFailureSymbol =
    "__ZL27_library_validation_failureR15ProcessAccessorR16FileGlobAccessorR11"
    "SystemFactsbPKcym";
static const char* kCdHashSymbol = "__ZN22AbstractCSBlobAccessor6cdHashEv";
// How many bytes may be read at each function. The failure function is over
// 900 bytes; the accessor is 28, of which 13 are compared.
static constexpr size_t kEntryBytes = 32;

static void onAMFILoad(void*, KernelPatcher& patcher, size_t index,
                       mach_vm_address_t address, size_t size) {
  if (kextAMFI.loadIndex != index) return;

  auto failure = patcher.solveSymbol(index, kFailureSymbol, address, size);
  auto cdHash = patcher.solveSymbol(index, kCdHashSymbol, address, size);
  if (failure == 0 || cdHash == 0) {
    patcher.clearError();
    SYSLOG("vcnvt", "AMFI function not found, doing nothing");
    gStatus = AmfiAllow::Status::NoSymbol;
    return;
  }
  // solveSymbol only checks that the address is inside the image; the bytes
  // compared below must be inside it too.
  if (failure + kEntryBytes > address + size ||
      cdHash + vcnvt::kAccessorBytes > address + size) {
    SYSLOG("vcnvt",
           "AMFI function too close to the end of AMFI, doing nothing");
    gStatus = AmfiAllow::Status::UnknownEntry;
    return;
  }
  auto entry = reinterpret_cast<const uint8_t*>(failure);
  if (vcnvt::entryIsRouted(entry, kEntryBytes)) {
    SYSLOG("vcnvt",
           "another kext already routes the AMFI function, staying off");
    gStatus = AmfiAllow::Status::AlreadyRouted;
    return;
  }
  if (!vcnvt::entryIsPlainPrologue(entry, kEntryBytes) ||
      !vcnvt::isCdHashAccessor(reinterpret_cast<const uint8_t*>(cdHash),
                               vcnvt::kAccessorBytes)) {
    SYSLOG("vcnvt", "AMFI function does not start as expected, doing nothing");
    gStatus = AmfiAllow::Status::UnknownEntry;
    return;
  }
  fnCdHash = reinterpret_cast<t_cdHash>(cdHash);

  KernelPatcher::RouteRequest requests[]{
      {kFailureSymbol, allowFailure, orgFailure},
  };
  bool routed = patcher.routeMultipleLong(index, requests, address, size);
  auto error = patcher.getError();
  patcher.clearError();
  // Lilu can report success after failing to write the jump, so the result is
  // only believed when there is no error, the original was handed back and the
  // entry really changed.
  if (routed && error == KernelPatcher::Error::NoError &&
      orgFailure != nullptr && vcnvt::entryIsRouted(entry, kEntryBytes)) {
    SYSLOG("vcnvt", "active: %lu plug-in builds allowed",
           static_cast<unsigned long>(kAllowedCdhashCount));
    gStatus = AmfiAllow::Status::Active;
  } else {
    SYSLOG("vcnvt", "route failed (%d), AMFI left as it is", error);
    gStatus = AmfiAllow::Status::RouteFailed;
  }
}

void AmfiAllow::init() {
  auto error = lilu.onKextLoad(&kextAMFI, 1, onAMFILoad, nullptr);
  if (error != LiluAPI::Error::NoError) {
    SYSLOG("vcnvt", "could not register with Lilu (%d), doing nothing", error);
    gStatus = Status::RegistrationFailed;
  }
}

AmfiAllow::Status AmfiAllow::status() { return gStatus; }

const char* AmfiAllow::statusText(Status status) {
  switch (status) {
    case Status::Waiting:
      return "waiting for AMFI";
    case Status::Active:
      return "active";
    case Status::NoSymbol:
      return "off: function not found in this AMFI";
    case Status::UnknownEntry:
      return "off: function does not start as expected";
    case Status::RouteFailed:
      return "off: route failed";
    case Status::AlreadyRouted:
      return "off: another kext already handles this AMFI function";
    case Status::RegistrationFailed:
      return "off: could not register with Lilu";
  }
  return "off";
}

uint64_t AmfiAllow::allowedCount() { return kAllowedCdhashCount; }

uint64_t AmfiAllow::overrides() { return static_cast<uint64_t>(gOverrides); }
