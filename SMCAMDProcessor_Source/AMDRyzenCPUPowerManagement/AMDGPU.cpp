//
//  AMDGPU.cpp
//  AMDRyzenCPUPowerManagement
//
//  GPU temperature and power monitoring through the GPU's register BAR.
//  Register offsets, field layouts and device-ID ranges are hardware facts
//  taken from the Linux amdgpu driver (drivers/gpu/drm/amd/); each block
//  below names the Linux function it mirrors.
//  Implementation is original — no code copied from SMCRadeonSensors.
//

#include "AMDGPU.hpp"
#include <Headers/kern_iokit.hpp>

OSDefineMetaClassAndStructors(AMDGPUDevice, OSObject);

//==============================================================================
// MARK: - Register definitions (dword offsets)
//==============================================================================

// Index/data windows for registers beyond the mapped BAR.
static constexpr UInt32 mmPCIE_INDEX  = 0xC;
static constexpr UInt32 mmPCIE_DATA   = 0xD;
static constexpr UInt32 mmPCIE_INDEX2 = 0xE;
static constexpr UInt32 mmPCIE_DATA2  = 0xF;

// SMC indirect space: pair 0 on GCN 1/2, pair 11 on GCN 3/4 (cik_smc_rreg /
// vi_smc_rreg).
static constexpr UInt32 mmSMC_IND_INDEX_0  = 0x80;
static constexpr UInt32 mmSMC_IND_DATA_0   = 0x81;
static constexpr UInt32 mmSMC_IND_INDEX_11 = 0x1AC;
static constexpr UInt32 mmSMC_IND_DATA_11  = 0x1AD;

// CG_MULT_THERMAL_STATUS: a plain MMIO register on GCN 1 (smu_6_0_d.h), an
// SMC indirect register on GCN 2-4 (ci_dpm_get_temp, smu7_thermal_get_temperature),
// and inside the THM block on Vega (vega10/vega20_thermal_get_temperature).
static constexpr UInt32 mmCG_MULT_THERMAL_STATUS_SI    = 0x1C5;
static constexpr UInt32 ixCG_MULT_THERMAL_STATUS       = 0xC0300014;
static constexpr UInt32 THM_BASE                       = 0x16600;
static constexpr UInt32 mmCG_MULT_THERMAL_STATUS_THM9  = 0x5A;
static constexpr UInt32 mmCG_MULT_THERMAL_STATUS_THM11 = 0x5F;
static constexpr UInt32 kCTF_TEMP_MASK  = 0x0003FE00;
static constexpr UInt32 kCTF_TEMP_SHIFT = 9;
static constexpr UInt32 kCTF_TEMP_INVALID = 0x200;   // within the shifted field

// THM_TCON_CUR_TMP on Raven and Navi: CUR_TEMP in bits 31:21, 1/8 °C, with
// a -49 °C offset when CUR_TEMP_RANGE_SEL is set.
static constexpr UInt32 mmTHM_TCON_CUR_TMP  = 0x0;
static constexpr UInt32 kCUR_TEMP_RANGE_SEL = 0x80000;
static constexpr UInt32 kCUR_TEMP_SHIFT     = 21;

// SMU7 mailbox on GCN 3/4 (smu7_send_msg_to_smc).
static constexpr UInt32 mmSMC_MESSAGE_0 = 0x94;
static constexpr UInt32 mmSMC_RESP_0    = 0x95;
static constexpr UInt32 mmSMC_MSG_ARG_0 = 0xA4;
static constexpr UInt32 kSMC_RESP_MASK  = 0xFFFF;

// SMU9 mailbox on Vega 10 (MP1 C2PMSG registers, smu9_send_msg_to_smc).
static constexpr UInt32 MP1_BASE_SMU9       = 0x16000;
static constexpr UInt32 mmMP1_SMN_C2PMSG_66 = 0x282;   // message
static constexpr UInt32 mmMP1_SMN_C2PMSG_82 = 0x292;   // argument / result
static constexpr UInt32 mmMP1_SMN_C2PMSG_90 = 0x29A;   // response

static constexpr UInt32 PPSMC_MSG_GetCurrPkgPwr_SMU7 = 0x282;
static constexpr UInt32 PPSMC_MSG_GetCurrPkgPwr_SMU9 = 0x61;

// SMU response codes shared by both mailboxes.
static constexpr UInt32 kSMU_RESP_OK = 1;

/// How long the work loop may wait for an SMU reply while holding gpuLock.
static constexpr UInt32 kSMUReplyTimeoutUS = 10000;

/// Orders an index write before the matching data access. The BAR is mapped
/// uncached, which x86 already keeps in program order; the fence also stops
/// the compiler from moving accesses across it.
static inline void memoryBarrier() {
    __asm__ volatile("mfence" ::: "memory");
}

//==============================================================================
// MARK: - Device identification
//==============================================================================

bool AMDGPUDevice::initFromDevice(IOPCIDevice *device) {
    if (device == nullptr || !OSObject::init()) {
        return false;
    }

    // The matching iterator's reference is not ours; keep one so the device
    // cannot go away under ensureRMMIOMapped(). free() drops it.
    dev = device;
    dev->retain();
    UInt32 deviceID = WIOKit::readPCIConfigValue(dev, WIOKit::kIOPCIConfigDeviceID);

    // Ranges follow the per-chip groups in amdgpu_drv.c (pciidlist).
    switch (deviceID) {
    case 0x6780 ... 0x679F:   // Tahiti
    case 0x6800 ... 0x681F:   // Pitcairn
    case 0x6820 ... 0x683F:   // Cape Verde
    case 0x6600 ... 0x663F:   // Oland
    case 0x6660 ... 0x666F:   // Hainan
        family = Family::SouthernIslands;
        break;

    case 0x6640 ... 0x665F:   // Bonaire
    case 0x67A0 ... 0x67BF:   // Hawaii
        family = Family::SeaIslands;
        break;

    // GetCurrPkgPwr exists from Polaris on; smu7_get_gpu_power lists Tonga
    // and Fiji (and the older Bonaire/Hawaii) as not supporting it. Their
    // fallback, the PM status log, needs half-second sleeps that the work
    // loop cannot take, so those GPUs report temperature only.
    case 0x6900 ... 0x693F:   // Topaz, Tonga
    case 0x7300 ... 0x730F:   // Fiji
        family = Family::VolcanicIslands;
        break;

    case 0x67C0 ... 0x67FF:   // Polaris 10, Polaris 11
    case 0x6980 ... 0x699F:   // Polaris 12
    case 0x694C ... 0x694F:   // Vega M (Polaris-class graphics)
        family = Family::VolcanicIslands;
        supportsPower_ = true;
        break;

    case 0x6860 ... 0x687F:   // Vega 10
        family = Family::Vega;
        supportsPower_ = true;
        break;

    case 0x69A0 ... 0x69AF:   // Vega 12 (power comes from a metrics table, not read here)
        family = Family::Vega;
        break;

    case 0x66A0 ... 0x66AF:   // Vega 20 (likewise)
        family = Family::Vega;
        isVega20 = true;
        break;

    case 0x15D8:              // Picasso
    case 0x15DD:              // Raven
    case 0x15E7:              // Barcelo
    case 0x1636:              // Renoir
    case 0x1638:              // Cezanne
    case 0x164C:              // Lucienne
        family = Family::Raven;
        break;

    case 0x7310 ... 0x73FF:   // Navi 10/12/14, Navi 21/22/23
        family = Family::Navi;
        break;

    default:
        IOLog("AMDGPUDevice: unsupported GPU device ID 0x%04X\n", deviceID);
        return false;
    }

    gpuLock = IOLockAlloc();
    if (gpuLock == nullptr) {
        IOLog("AMDGPUDevice: failed to allocate gpuLock\n");
        return false;
    }

    IOLog("AMDGPUDevice: device 0x%04X, family %u, power %s\n",
          deviceID, static_cast<unsigned>(family), supportsPower_ ? "yes" : "no");
    return true;
}

void AMDGPUDevice::free() {
    rmmioPtr = nullptr;
    OSSafeReleaseNULL(rmmio);
    if (gpuLock) {
        IOLockFree(gpuLock);
        gpuLock = nullptr;
    }
    OSSafeReleaseNULL(dev);
    OSObject::free();
}

//==============================================================================
// MARK: - BAR mapping
//==============================================================================

IOReturn AMDGPUDevice::ensureRMMIOMapped() {
    if (__atomic_load_n(&rmmioPtr, __ATOMIC_ACQUIRE) != nullptr) {
        return kIOReturnSuccess;
    }

    IOLockLock(gpuLock);
    IOReturn result = kIOReturnSuccess;
    if (rmmioPtr == nullptr) {
        if (mapFailed) {
            result = kIOReturnNotReady;
        } else {
            // amdgpu_device_init: BAR5 from Bonaire on, BAR2 before.
            const bool useBar5 = family != Family::SouthernIslands;
            const unsigned bar = useBar5 ? 5 : 2;
            dev->setMemoryEnable(true);

            IOMemoryMap *map = dev->mapDeviceMemoryWithRegister(useBar5 ? kIOPCIConfigBaseAddress5
                                                                        : kIOPCIConfigBaseAddress2);
            volatile UInt32 *base = map ? reinterpret_cast<volatile UInt32 *>(map->getVirtualAddress()) : nullptr;
            if (map == nullptr || map->getLength() == 0 || base == nullptr) {
                IOLog("AMDGPUDevice: failed to map BAR%u; GPU sensors disabled\n", bar);
                OSSafeReleaseNULL(map);
                mapFailed = true;
                result = kIOReturnNotReady;
            } else {
                rmmio = map;
                __atomic_store_n(&rmmioPtr, base, __ATOMIC_RELEASE);
            }
        }
    }
    IOLockUnlock(gpuLock);
    return result;
}

//==============================================================================
// MARK: - Register access
//==============================================================================

UInt32 AMDGPUDevice::rawReadReg32(UInt32 reg) {
    if (reg * sizeof(UInt32) < rmmio->getLength()) {
        return rmmioPtr[reg];
    }
    rmmioPtr[mmPCIE_INDEX] = reg;
    memoryBarrier();
    return rmmioPtr[mmPCIE_DATA];
}

void AMDGPUDevice::rawWriteReg32(UInt32 reg, UInt32 val) {
    if (reg * sizeof(UInt32) < rmmio->getLength()) {
        rmmioPtr[reg] = val;
        return;
    }
    rmmioPtr[mmPCIE_INDEX] = reg;
    memoryBarrier();
    rmmioPtr[mmPCIE_DATA] = val;
}

UInt32 AMDGPUDevice::rawSoc15ReadReg32(UInt32 reg) {
    if (reg * sizeof(UInt32) < rmmio->getLength()) {
        return rmmioPtr[reg];
    }
    rmmioPtr[mmPCIE_INDEX2] = reg;
    memoryBarrier();
    return rmmioPtr[mmPCIE_DATA2];
}

void AMDGPUDevice::rawSoc15WriteReg32(UInt32 reg, UInt32 val) {
    if (reg * sizeof(UInt32) < rmmio->getLength()) {
        rmmioPtr[reg] = val;
        return;
    }
    rmmioPtr[mmPCIE_INDEX2] = reg;
    memoryBarrier();
    rmmioPtr[mmPCIE_DATA2] = val;
}

UInt32 AMDGPUDevice::readReg32(UInt32 reg) {
    IOLockLock(gpuLock);
    UInt32 value = rawReadReg32(reg);
    IOLockUnlock(gpuLock);
    return value;
}

UInt32 AMDGPUDevice::soc15ReadReg32(UInt32 reg) {
    IOLockLock(gpuLock);
    UInt32 value = rawSoc15ReadReg32(reg);
    IOLockUnlock(gpuLock);
    return value;
}

UInt32 AMDGPUDevice::readIndirectSMC(UInt32 reg) {
    const bool vi = family == Family::VolcanicIslands;
    const UInt32 index = vi ? mmSMC_IND_INDEX_11 : mmSMC_IND_INDEX_0;
    const UInt32 data  = vi ? mmSMC_IND_DATA_11  : mmSMC_IND_DATA_0;

    IOLockLock(gpuLock);
    rmmioPtr[index] = reg;
    memoryBarrier();
    UInt32 value = rmmioPtr[data];
    IOLockUnlock(gpuLock);
    return value;
}

//==============================================================================
// MARK: - Temperature
//==============================================================================

/// CTF_TEMP field of CG_MULT_THERMAL_STATUS. GCN 1-4 flag an invalid sample
/// with bit 9 of the field (si/ci_dpm_get_temp report it as 255); Vega only
/// keeps the low nine bits (vega10_thermal_get_temperature).
IOReturn AMDGPUDevice::ctfTempFrom(UInt32 status, UInt16 *celsius) {
    UInt32 field = (status & kCTF_TEMP_MASK) >> kCTF_TEMP_SHIFT;
    if (family != Family::Vega && (field & kCTF_TEMP_INVALID)) {
        *celsius = 255;
    } else {
        *celsius = static_cast<UInt16>(field & 0x1FF);
    }
    return kIOReturnSuccess;
}

/// THM_TCON_CUR_TMP (Raven, Navi).
IOReturn AMDGPUDevice::thm10GetTemp(UInt16 *celsius) {
    UInt32 reg = soc15ReadReg32(THM_BASE + mmTHM_TCON_CUR_TMP);
    UInt32 degrees = (reg >> kCUR_TEMP_SHIFT) / 8;
    if (reg & kCUR_TEMP_RANGE_SEL) {
        degrees = degrees > 49 ? degrees - 49 : 0;
    }
    *celsius = static_cast<UInt16>(degrees);
    return kIOReturnSuccess;
}

IOReturn AMDGPUDevice::getTemperature(UInt16 *celsius) {
    if (celsius == nullptr) {
        return kIOReturnBadArgument;
    }
    IOReturn ret = ensureRMMIOMapped();
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    switch (family) {
    case Family::SouthernIslands:
        return ctfTempFrom(readReg32(mmCG_MULT_THERMAL_STATUS_SI), celsius);
    case Family::SeaIslands:
    case Family::VolcanicIslands:
        return ctfTempFrom(readIndirectSMC(ixCG_MULT_THERMAL_STATUS), celsius);
    case Family::Vega:
        return ctfTempFrom(soc15ReadReg32(THM_BASE + (isVega20 ? mmCG_MULT_THERMAL_STATUS_THM11
                                                               : mmCG_MULT_THERMAL_STATUS_THM9)),
                           celsius);
    case Family::Raven:
    case Family::Navi:
        return thm10GetTemp(celsius);
    case Family::Unknown:
        break;
    }
    return kIOReturnUnsupported;
}

//==============================================================================
// MARK: - Power
//==============================================================================
// Both mailboxes are shared with the macOS AMD driver, which cannot know this
// kext exists. A zero response register means a message is in flight, so a
// busy mailbox skips the sample (the caller keeps its last value) rather than
// overwriting another sender's argument. Nothing else is ever sent.

/// Polaris / Vega M, as smu7_get_gpu_power: GetCurrPkgPwr with argument 0
/// returns package power in Q24.8 watts in SMC_MSG_ARG_0.
IOReturn AMDGPUDevice::smu7GetPower(float *watts) {
    IOLockLock(gpuLock);

    if ((rawReadReg32(mmSMC_RESP_0) & kSMC_RESP_MASK) == 0) {
        IOLockUnlock(gpuLock);
        return kIOReturnBusy;
    }

    rawWriteReg32(mmSMC_MSG_ARG_0, 0);
    rawWriteReg32(mmSMC_RESP_0, 0);
    memoryBarrier();
    rawWriteReg32(mmSMC_MESSAGE_0, PPSMC_MSG_GetCurrPkgPwr_SMU7);
    memoryBarrier();

    UInt32 resp = 0;
    for (UInt32 waited = 0; waited < kSMUReplyTimeoutUS && resp == 0; waited++) {
        IODelay(1);
        resp = rawReadReg32(mmSMC_RESP_0) & kSMC_RESP_MASK;
    }
    UInt32 value = (resp == kSMU_RESP_OK) ? rawReadReg32(mmSMC_MSG_ARG_0) : 0;
    IOLockUnlock(gpuLock);

    if (resp != kSMU_RESP_OK) {
        return resp == 0 ? kIOReturnTimeout : kIOReturnError;
    }
    // Linux falls back to the PM status log when this reads 0; that needs
    // sleeps the work loop cannot take, so the sample is skipped instead.
    if (value == 0) {
        return kIOReturnNotReady;
    }
    *watts = static_cast<float>(value) / 256.0f;
    return kIOReturnSuccess;
}

/// Vega 10, as vega10_get_gpu_power: GetCurrPkgPwr returns whole watts in
/// C2PMSG_82.
IOReturn AMDGPUDevice::smu9GetPower(float *watts) {
    const UInt32 msgReg  = MP1_BASE_SMU9 + mmMP1_SMN_C2PMSG_66;
    const UInt32 argReg  = MP1_BASE_SMU9 + mmMP1_SMN_C2PMSG_82;
    const UInt32 respReg = MP1_BASE_SMU9 + mmMP1_SMN_C2PMSG_90;

    IOLockLock(gpuLock);

    if (rawSoc15ReadReg32(respReg) == 0) {
        IOLockUnlock(gpuLock);
        return kIOReturnBusy;
    }

    rawSoc15WriteReg32(argReg, 0);
    rawSoc15WriteReg32(respReg, 0);
    memoryBarrier();
    rawSoc15WriteReg32(msgReg, PPSMC_MSG_GetCurrPkgPwr_SMU9);
    memoryBarrier();

    UInt32 resp = 0;
    for (UInt32 waited = 0; waited < kSMUReplyTimeoutUS && resp == 0; waited++) {
        IODelay(1);
        resp = rawSoc15ReadReg32(respReg);
    }
    UInt32 value = (resp == kSMU_RESP_OK) ? rawSoc15ReadReg32(argReg) : 0;
    IOLockUnlock(gpuLock);

    if (resp != kSMU_RESP_OK) {
        return resp == 0 ? kIOReturnTimeout : kIOReturnError;
    }
    *watts = static_cast<float>(value);
    return kIOReturnSuccess;
}

IOReturn AMDGPUDevice::getPower(float *watts) {
    if (watts == nullptr) {
        return kIOReturnBadArgument;
    }
    if (!supportsPower_) {
        return kIOReturnUnsupported;
    }
    IOReturn ret = ensureRMMIOMapped();
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    switch (family) {
    case Family::VolcanicIslands:
        return smu7GetPower(watts);
    case Family::Vega:
        return smu9GetPower(watts);
    default:
        return kIOReturnUnsupported;
    }
}
