//
//  KeyImplementations.hpp
//  AMDRyzenCPUPowerManagement
//
//  Created by trulyspinach, modified by Droga (2026) on 2/12/20.
//

#ifndef KeyImplementations_hpp
#define KeyImplementations_hpp


#include "SMCAMDProcessor.hpp"



class AMDRyzenCPUPowerManagement;


class AMDSupportVsmcValue : public VirtualSMCValue {
protected:
    AMDRyzenCPUPowerManagement *provider;
    size_t package;
    size_t core;
public:
    AMDSupportVsmcValue(AMDRyzenCPUPowerManagement *provider, size_t package, size_t core=0) : provider(provider), package(package), core(core) {}
};


class TempPackage : public AMDSupportVsmcValue { using AMDSupportVsmcValue::AMDSupportVsmcValue; protected: SMC_RESULT readAccess() override; };
class TempCore    : public AMDSupportVsmcValue { using AMDSupportVsmcValue::AMDSupportVsmcValue; protected: SMC_RESULT readAccess() override; };

class EnergyPackage: public AMDSupportVsmcValue
{ using AMDSupportVsmcValue::AMDSupportVsmcValue; protected: SMC_RESULT readAccess() override; };

// === Sensor values ===
// Every readAccess() returns the provider's cached sample (refreshed by its
// work loop every HF_TEMP_SAMPLE_PERIOD); none touches hardware on the SMC
// reader's thread.

// RGPUTempValue: GPU temperature; `package` is the GPU index.
class RGPUTempValue : public AMDSupportVsmcValue {
    using AMDSupportVsmcValue::AMDSupportVsmcValue;
protected:
    SMC_RESULT readAccess() override;
};

// RGPUPowerValue: GPU package power in watts; registered only for GPUs that
// report it (gpuSupportsPower).
class RGPUPowerValue : public AMDSupportVsmcValue {
    using AMDSupportVsmcValue::AMDSupportVsmcValue;
protected:
    SMC_RESULT readAccess() override;
};

// FanSpeedValue: Super I/O tachometer in RPM (fpe2); `package` is the fan
// header index. Served from the provider's cache (refreshFanTelemetryIfStale),
// an untrusted reading reports 0.
class FanSpeedValue : public AMDSupportVsmcValue {
    using AMDSupportVsmcValue::AMDSupportVsmcValue;
protected:
    SMC_RESULT readAccess() override;
};

#endif /* KeyImplementations_hpp */
