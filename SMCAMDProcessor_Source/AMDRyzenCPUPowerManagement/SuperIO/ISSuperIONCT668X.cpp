//
//  ISSuperIONCT668X.cpp
//  AMDRyzenCPUPowerManagement
//
//  Created by trulyspinach, modified by Droga (2026) on 5/17/20.
//

#include "ISSuperIONCT668X.hpp"

ISSuperIONCT668X::ISSuperIONCT668X(int psel, uint16_t addr, uint16_t chipIntel){
    lpcPortSel = psel;
    chipAddr = addr;
    activeFansOnSystem = NCT668X_MAX_NUMFAN;
    // No control-mode backup: setDefaultFanControl() hands a fan back to the
    // EC by writing PWM command 0, which is "automatic" on this family.
}

// Super-I/O config mode, as Linux nct6683 superio_enter/superio_exit.
static void superioEnter(i386_ioport_t regport){
    outb(regport, CHIP_SIO_OPEN);
    outb(regport, CHIP_SIO_OPEN);
}

static void superioExit(int portSel){
    const i386_ioport_t regport = ISLPCPort::kREGISTER_PORTS[portSel];
    outb(regport, CHIP_SIO_CLOSE);
    outb(regport, 0x02);
    outb(ISLPCPort::kVALUE_PORTS[portSel], 0x02);
}

ISSuperIONCT668X* ISSuperIONCT668X::getDevice(uint16_t *chipIntel, bool allowUnlock){
    IOLog("probe NCT668X\n");

    for (int portSel = 0; portSel < 2; portSel++) {
        superioEnter(ISLPCPort::kREGISTER_PORTS[portSel]);

        const uint8_t idHigh = ISLPCPort::readByte(portSel, ISLPCPort::kCHIP_ID_REG);
        const uint8_t idLow = ISLPCPort::readByte(portSel, ISLPCPort::kCHIP_REVISION_REG);
        const uint16_t chipID = (uint16_t)((idHigh << 8) | idLow);
        *chipIntel = chipID;

        // The low nibble is the silicon revision (Linux SIO_ID_MASK).
        switch (chipID & NCT668X_ID_MASK) {
            case CHIP_NCT6681:
            case CHIP_NCT6683:
                break;
            default:
                superioExit(portSel);
                continue;
        }

        IOLog("NCT668X chip identified (id 0x%04X)\n", chipID);
        ISLPCPort::select(portSel, CHIP_HWM_LDN);

        const uint16_t devAddr = ISLPCPort::readWord(portSel, ISLPCPort::kBASE_ADDRESS_REGISTER) & ~7;
        IODelay(10);
        const uint16_t devAddrVerify = ISLPCPort::readWord(portSel, ISLPCPort::kBASE_ADDRESS_REGISTER) & ~7;
        if (devAddrVerify != devAddr) {
            IOLog("NCT668X address verification failed: 0x%X != 0x%X\n", devAddrVerify, devAddr);
            superioExit(portSel);
            return nullptr;
        }
        IOLog("NCT668X EC address: 0x%X\n", devAddr);

        // Register 0x30 bit 0 activates the EC logical device. Linux nct6683
        // sets it when firmware left it off ("forcibly enabling EC access");
        // that is a firmware-configuration write, so it stays limited to
        // privileged callers like every other unlock in this driver.
        const uint8_t enable = ISLPCPort::readByte(portSel, NCT668X_SIO_REG_ENABLE);
        if (!(enable & 0x01)) {
            if (allowUnlock) {
                IOLog("NCT668X: EC logical device was disabled; enabling it\n");
                ISLPCPort::writeByte(portSel, NCT668X_SIO_REG_ENABLE, enable | 0x01);
            } else {
                IOLog("NCT668X: EC logical device is disabled; readings may be unusable\n");
            }
        }

        superioExit(portSel);
        ISSuperIONCT668X *device = new ISSuperIONCT668X(portSel, devAddr, chipID);
        if (device) device->ecEnableRequested = allowUnlock;
        return device;
    }

    return nullptr;
}

// The probe's EC enable again, after a wake.
void ISSuperIONCT668X::resume(){
    if (!ecEnableRequested) return;
    superioEnter(ISLPCPort::kREGISTER_PORTS[lpcPortSel]);
    ISLPCPort::select(lpcPortSel, CHIP_HWM_LDN);
    const uint8_t enable = ISLPCPort::readByte(lpcPortSel, NCT668X_SIO_REG_ENABLE);
    if (!(enable & 0x01)) {
        ISLPCPort::writeByte(lpcPortSel, NCT668X_SIO_REG_ENABLE, enable | 0x01);
    }
    superioExit(lpcPortSel);
}

uint8_t ISSuperIONCT668X::readByte(uint16_t addr){
    outb(chipAddr + EC_BANK_REG_OFFSET, 0xff);
    outb(chipAddr + EC_BANK_REG_OFFSET, static_cast<uint8_t>(addr >> 8));
    outb(chipAddr + EC_INDEX_REG_OFFSET, static_cast<uint8_t>(addr & 0xff));
    return inb(chipAddr + EC_DAT_REG_OFFSET);
}

uint16_t ISSuperIONCT668X::readWord(uint16_t addr){
    // Tear-resistant 16-bit read (same rationale as
    // ISSuperIONCT67XXFamily::readWord): re-read the high byte after the low;
    // persistent disagreement reports the 0xFFFF sentinel for the caller's
    // Plausibility filter to reject.
    for (int attempt = 0; attempt < 3; attempt++) {
        uint8_t hi  = readByte(addr);
        uint8_t lo  = readByte(static_cast<uint16_t>(addr + 1));
        uint8_t hi2 = readByte(addr);
        if (hi == hi2) {
            return (uint16_t)((hi << 8) | lo);
        }
    }
    return 0xFFFF;
}

void ISSuperIONCT668X::writeByte(uint16_t addr, uint8_t val){
    outb(chipAddr + EC_BANK_REG_OFFSET, 0xff);
    outb(chipAddr + EC_BANK_REG_OFFSET, static_cast<uint8_t>(addr >> 8));
    outb(chipAddr + EC_INDEX_REG_OFFSET, static_cast<uint8_t>(addr & 0xff));
    outb(chipAddr + EC_DAT_REG_OFFSET, val);
}

int ISSuperIONCT668X::getNumberOfFans(){
    return activeFansOnSystem;
}

const char *ISSuperIONCT668X::getReadableStringForFan(int fan){
    if (fan < 0 || fan >= activeFansOnSystem) return nullptr;
    const int kLabelCount = (int)(sizeof(kFAN_READABLE_STRS) / sizeof(kFAN_READABLE_STRS[0]));
    if (fan >= kLabelCount) return "Fan";
    return kFAN_READABLE_STRS[fan];
}

uint32_t ISSuperIONCT668X::getRPMForFan(int fan){
    if(fan < 0 || fan >= activeFansOnSystem) return 0;
    return static_cast<uint32_t>(fanRPMs[fan]);
}

bool ISSuperIONCT668X::getFanRPMValid(int fan){
    if(fan < 0 || fan >= activeFansOnSystem) return false;
    return fanRPMValid[fan];
}

bool ISSuperIONCT668X::getFanAutoControlMode(int fan){
    if(fan < 0 || fan >= activeFansOnSystem) return 0;
    return fanControlMode[fan] != 0;
}

uint8_t ISSuperIONCT668X::getFanThrottle(int fan){
    if(fan < 0 || fan >= activeFansOnSystem) return 0;
    return fanThrottles[fan];
}

void ISSuperIONCT668X::updateFanRPMS(){
    //
    // Validate every tachometer word before publishing it
    // (same rationale as ISSuperIONCT67XXFamily::updateFanRPMS).
    //
    static const int kMAX_PLAUSIBLE_RPM = 10500;

    for (int i = 0; i < activeFansOnSystem; i++) {
        int v = (int)readWord(static_cast<uint16_t>(FAN_RPM_REGS(i)));

        if (v == 0xFFFF || v < 0 || v > kMAX_PLAUSIBLE_RPM) {
            fanRPMValid[i] = false;
            continue;
        }

        fanRPMs[i] = v;
        fanRPMValid[i] = true;

        if ((uint32_t)v > fanPeakRPMs[i]) {
            fanPeakRPMs[i] = (uint16_t)v;
        }
    }
}

void ISSuperIONCT668X::updateFanControl(){
    for (int i = 0; i < activeFansOnSystem; i++) {
        uint8_t mode = readByte(static_cast<uint16_t>(FAN_PWMCMD_REGS(i)));
        fanControlMode[i] = (mode == 0) ? 1 : 0;
        // FAN_PWM_REGS: actual PWM duty cycle register.
        // In Auto mode this register should be updated by the EC firmware,
        // but some firmware versions don't update it -> read 0.
        fanThrottles[i] = readByte(static_cast<uint16_t>(FAN_PWM_REGS(i)));

        // Fallback: if register reports 0 but fan is spinning,
        // estimate throttle from RPM/peakRPM ratio.
        // Only estimate from a validated tach sample.
        if (fanThrottles[i] == 0 && fanRPMValid[i] && fanRPMs[i] > 100 && fanPeakRPMs[i] > 200) {
            uint32_t est = (uint32_t)((uint64_t)fanRPMs[i] * 255 / fanPeakRPMs[i]);
            fanThrottles[i] = est > 255 ? 255 : (uint8_t)est;
        }
    }
}

void ISSuperIONCT668X::overrideFanControl(int fan, uint8_t thr){
    if(fan < 0 || fan >= activeFansOnSystem) return;
    writeByte(FAN_CFG_CTRL_REG, FAN_CFG_REQ);
    // IODelay (µs) instead of IOSleep (ms): evaluateFanCurves may hold superIOLock;
    // sleeping while holding the lock stalls concurrent UserClient SuperIO calls.
    IODelay(50);
    writeByte(static_cast<uint16_t>(FAN_PWMCMD_REGS(fan)), thr);
    writeByte(FAN_CFG_CTRL_REG, FAN_CFG_DONE);
}

void ISSuperIONCT668X::setDefaultFanControl(int fan){
    if(fan < 0 || fan >= activeFansOnSystem) return;
    writeByte(FAN_CFG_CTRL_REG, FAN_CFG_REQ);
    IODelay(50);
    writeByte(static_cast<uint16_t>(FAN_PWMCMD_REGS(fan)), 0);
    writeByte(FAN_CFG_CTRL_REG, FAN_CFG_DONE);
    fanControlMode[fan] = 1;
}
