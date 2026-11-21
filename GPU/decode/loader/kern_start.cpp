//
//  kern_start.cpp - VCNVTLoader, a Lilu plug-in.
//
//  Lets the AV1 and VP9 decoder plug-ins of this repository load into Safari's
//  media processes on a Mac that does not run AMFIPass: it adds one exception
//  to AMFI's library validation, for the exact plug-in builds listed when the
//  kext was built, and for nothing else. See kern_amfi.cpp.
//
//  With AMFIPass, or with plug-ins signed under a CA the Mac trusts, the
//  plug-ins are never refused and this kext has nothing to do. It is harmless
//  next to either.
//
//  State: ioreg -r -c VCNVTLoader -l  (Status, AllowedBuilds, Overrides).
//  Boot arguments: -vcnvtoff turns it off, -vcnvtdbg logs more, -vcnvtbeta lets
//  it start on a kernel newer than the last one checked.
//
//  Version 1.0.0 also tried to patch CoreMedia so the plug-ins could live
//  outside /System. That part never ran (Lilu's user patcher is off on current
//  macOS) and is gone.
//
#include <Headers/kern_api.hpp>
#include <Headers/kern_util.hpp>
#include <Headers/plugin_start.hpp>

#include "kern_amfi.hpp"

static const char* bootargOff[]{"-vcnvtoff"};
static const char* bootargDebug[]{"-vcnvtdbg"};
static const char* bootargBeta[]{"-vcnvtbeta"};

// clang-format off
PluginConfiguration ADDPR(config){
    xStringify(PRODUCT_NAME),
    parseModuleVersion(xStringify(MODULE_VERSION)),
    LiluAPI::AllowNormal,
    bootargOff, arrsize(bootargOff),
    bootargDebug, arrsize(bootargDebug),
    bootargBeta, arrsize(bootargBeta),
    KernelVersion::Sequoia,  // the decoders run on 15.8.2 and later
    KernelVersion::Tahoe,
    []() { AmfiAllow::init(); }};
// clang-format on
