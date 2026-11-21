//
//  kern_start.cpp - GPUSensors, a Lilu plug-in.
//
//  Publishes the GPU sensor readings Apple's AMD driver takes and does not
//  show: edge, memory and VR temperatures, voltages, throttler status, PCIe
//  link, video and fabric clocks. It only copies what the driver already reads
//  (kern_pmlog.cpp) and never talks to the GPU itself. It sets the driver's
//  own PP_EnableAllPMLogSensors so the driver keeps them all.
//
//  Readings: ioreg -r -c DrogaBoxGPUSensors -l, or sensors/build/gpusensors.
//  Boot arguments: -gpusensoff turns it off, -gpusensnoall leaves the driver's
//  list of sensors as it is, -gpusensdbg logs more, -gpusensbeta lets it start
//  on a kernel newer than the last one checked. GPU control (kern_control.cpp):
//  gpuprofile=0|2|16 sets the power profile at boot, -gpuctloff turns the
//  control off and keeps the sensors.
//
#include <Headers/kern_api.hpp>
#include <Headers/kern_util.hpp>
#include <Headers/plugin_start.hpp>

#include "kern_control.hpp"
#include "kern_pmlog.hpp"

static const char* bootargOff[]{"-gpusensoff"};
static const char* bootargDebug[]{"-gpusensdbg"};
static const char* bootargBeta[]{"-gpusensbeta"};

// clang-format off
PluginConfiguration ADDPR(config){
    xStringify(PRODUCT_NAME),
    parseModuleVersion(xStringify(MODULE_VERSION)),
    LiluAPI::AllowNormal,
    bootargOff, arrsize(bootargOff),
    bootargDebug, arrsize(bootargDebug),
    bootargBeta, arrsize(bootargBeta),
    KernelVersion::Sequoia,  // libraries checked: 15.8.2, 15.8.3, 26.7.2, 26.7.3
    KernelVersion::Tahoe,
    []() {
      PMLogCopy::init();
      GPUControl::init();
    }};
// clang-format on
