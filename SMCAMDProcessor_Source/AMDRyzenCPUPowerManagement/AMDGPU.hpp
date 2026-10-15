//
//  AMDGPU.hpp
//  AMDRyzenCPUPowerManagement
//
//  GPU temperature and power monitoring through the GPU's register BAR.
//  Register offsets, field layouts and device-ID ranges are hardware facts
//  taken from the Linux amdgpu driver (drivers/gpu/drm/amd/).
//  Implementation is original — no code copied from SMCRadeonSensors.
//

#pragma once

#include <IOKit/IOService.h>
#include <IOKit/pci/IOPCIDevice.h>

/**
 *  One AMD discrete GPU (or Vega-based APU graphics), read directly from its
 *  MMIO registers while macOS's own driver keeps running the device.
 *
 *  Everything here is read-only towards the GPU except the SMU power query,
 *  which uses the same mailbox as the macOS driver and therefore only sends
 *  when that mailbox is idle (see smu7GetPower / smu9GetPower).
 *
 *  Threading: the provider's work loop is the only caller in practice, but
 *  every multi-register sequence runs under gpuLock so a second caller is
 *  safe. gpuLock is a plain IOLock and is NOT recursive: code that holds it
 *  calls only the raw* accessors.
 */
class AMDGPUDevice : public OSObject {
    OSDeclareDefaultStructors(AMDGPUDevice);

public:
    /** GPU generations, named and split as in Linux amdgpu. */
    enum class Family : UInt8 {
        Unknown = 0,
        SouthernIslands,   // GCN 1: Tahiti, Pitcairn, Cape Verde, Oland, Hainan
        SeaIslands,        // GCN 2: Bonaire, Hawaii
        VolcanicIslands,   // GCN 3/4: Tonga, Fiji, Polaris 10/11/12, Vega M
        Vega,              // GCN 5: Vega 10, Vega 12, Vega 20
        Raven,             // GCN 5 APU graphics: Raven, Picasso, Renoir, Cezanne, ...
        Navi,              // RDNA 1/2: Navi 1x, Navi 2x
    };

    /**
     *  Identify the GPU from its PCI device ID and take a reference on it.
     *  Returns false for an unsupported GPU or when allocation fails; the
     *  caller then releases the object, which drops the reference again.
     */
    bool initFromDevice(IOPCIDevice *device);

    void free() APPLE_KEXT_OVERRIDE;

    /** Current GPU temperature in whole °C (255 = the GPU flagged it invalid). */
    IOReturn getTemperature(UInt16 *celsius);

    /**
     *  Current package power in watts. kIOReturnBusy means the SMU mailbox was
     *  in use by the macOS driver and the sample was skipped.
     */
    IOReturn getPower(float *watts);

    /** Whether this GPU's firmware answers the package-power query. */
    bool supportsPower() const { return supportsPower_; }

private:
    IOPCIDevice *dev {nullptr};
    IOMemoryMap *rmmio {nullptr};
    /** Published last, after rmmio, so a non-null value means "mapped". */
    volatile UInt32 *rmmioPtr {nullptr};
    /** Set once mapping failed; the BAR is not retried every sample. */
    bool mapFailed {false};
    IOLock *gpuLock {nullptr};

    Family family {Family::Unknown};
    bool supportsPower_ {false};
    /** Vega 20 moved CG_MULT_THERMAL_STATUS within the THM block. */
    bool isVega20 {false};

    /** Map the register BAR on first use (BAR2 on GCN 1, BAR5 later). */
    IOReturn ensureRMMIOMapped();

    // Register access. raw* = caller holds gpuLock.
    UInt32 rawReadReg32(UInt32 reg);
    void rawWriteReg32(UInt32 reg, UInt32 val);
    UInt32 rawSoc15ReadReg32(UInt32 reg);
    void rawSoc15WriteReg32(UInt32 reg, UInt32 val);

    /** One locked register read (pre-SOC15 / SOC15 index-data window). */
    UInt32 readReg32(UInt32 reg);
    UInt32 soc15ReadReg32(UInt32 reg);
    /** One locked read through the SMC indirect index/data pair. */
    UInt32 readIndirectSMC(UInt32 reg);

    // Temperature, per register layout.
    IOReturn ctfTempFrom(UInt32 status, UInt16 *celsius);
    IOReturn thm10GetTemp(UInt16 *celsius);

    // Power, per SMU generation.
    IOReturn smu7GetPower(float *watts);
    IOReturn smu9GetPower(float *watts);
};
