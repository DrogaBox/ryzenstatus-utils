//
//  KeyImplementations.cpp
//  AMDRyzenCPUPowerManagement
//
//  Created by trulyspinach, modified by Droga (2026) on 2/12/20.
//

#include "KeyImplementations.hpp"
#include <libkern/OSAtomic.h>


SMC_RESULT TempPackage::readAccess() {
    if (!provider) return SmcError;
    __sync_synchronize();
    uint16_t *ptr = reinterpret_cast<uint16_t *>(data);
    *ptr = VirtualSMCAPI::encodeSp(type, (double)provider->PACKAGE_TEMPERATURE_perPackage[0]);

    return SmcSuccess;
}

SMC_RESULT TempCore::readAccess() {
    if (!provider) return SmcError;
    __sync_synchronize();
    uint16_t *ptr = reinterpret_cast<uint16_t *>(data);
    // Cached, like RGPUTempValue below: getCCDTemp() does PCI config I/O under
    // pciConfigLock on the thread of whichever process reads the key, racing
    // the SMU mailbox. The provider's timer refreshes ccdTemperatures[] every
    // HF_TEMP_SAMPLE_PERIOD.
    double temp = (core < provider->ccdCount) ? (double)provider->ccdTemperatures[core] : 0.0;
    if (temp <= 0.0) {
        temp = (double)provider->PACKAGE_TEMPERATURE_perPackage[0];
    }
    *ptr = VirtualSMCAPI::encodeSp(type, temp);

    return SmcSuccess;
}

SMC_RESULT EnergyPackage::readAccess(){
    if (!provider) return SmcError;
    __sync_synchronize();
    if (type == SmcKeyTypeFloat)
        *reinterpret_cast<uint32_t *>(data) = VirtualSMCAPI::encodeFlt(provider->uniPackagePowerW);
    else
        *reinterpret_cast<uint16_t *>(data) = VirtualSMCAPI::encodeSp(type, provider->uniPackagePowerW);

    return SmcSuccess;
}

SMC_RESULT RGPUTempValue::readAccess() {
    if (!provider) return SmcError;
    // Cached value only: a live register read would run on the thread of
    // whichever process reads this key. The provider's work loop refreshes
    // gpuTemperatures[] every HF_TEMP_SAMPLE_PERIOD.
    if (package >= provider->gpuCount) return SmcError;

    __sync_synchronize();
    uint16_t *ptr = reinterpret_cast<uint16_t *>(data);
    *ptr = VirtualSMCAPI::encodeSp(type, (double)provider->gpuTemperatures[package]);

    return SmcSuccess;
}

SMC_RESULT CoreVoltageValue::readAccess() {
    if (!provider) return SmcError;
    __sync_synchronize();
    float volts = provider->sviCoreValid ? (float)provider->sviCoreMillivolts / 1000.0f : 0.0f;
    *reinterpret_cast<uint32_t *>(data) = VirtualSMCAPI::encodeFlt(volts);
    return SmcSuccess;
}

SMC_RESULT CorePowerValue::readAccess() {
    if (!provider) return SmcError;
    provider->smcCoreDemandMs = getCurrentTimeNs() / 1000000;
    __sync_synchronize();
    *reinterpret_cast<uint16_t *>(data) = VirtualSMCAPI::encodeSp(type, (double)provider->corePowerTotalW);
    return SmcSuccess;
}

SMC_RESULT FanSpeedValue::readAccess() {
    if (!provider) return SmcError;
    uint32_t rpm = provider->fanRPM((int)package);
    // fpe2 carries 14 integer bits.
    if (rpm > 16383) rpm = 16383;
    *reinterpret_cast<uint16_t *>(data) = VirtualSMCAPI::encodeIntFp(SmcKeyTypeFpe2, (uint16_t)rpm);
    return SmcSuccess;
}

SMC_RESULT RGPUPowerValue::readAccess() {
    if (!provider) return SmcError;
    // Cached read — see RGPUTempValue::readAccess() above for
    // the full rationale (no live SMU mailbox busy-wait on reader threads).
    if (package >= provider->gpuCount) return SmcError;

    __sync_synchronize();
    uint16_t *ptr = reinterpret_cast<uint16_t *>(data);
    *ptr = VirtualSMCAPI::encodeSp(type, (double)provider->gpuPowers[package]);

    return SmcSuccess;
}
