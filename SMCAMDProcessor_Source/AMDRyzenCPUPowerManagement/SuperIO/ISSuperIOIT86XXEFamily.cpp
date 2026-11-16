//
//  ISSuperIOIT86XXEFamily.cpp
//  AMDRyzenCPUPowerManagement
//
//  Created by Maurice on 25.05.20.
//

#include "ISSuperIOIT86XXEFamily.hpp"

namespace {
// One hand-over of the chip for the lifetime of the object; nests.
struct ChipAccess {
    ISSuperIOIT86XXEFamily &chip;
    explicit ChipAccess(ISSuperIOIT86XXEFamily &c) : chip(c) { chip.beginAccess(); }
    ~ChipAccess() { chip.endAccess(); }
};
}

ISSuperIOIT86XXEFamily::ISSuperIOIT86XXEFamily(int psel, uint16_t addr, uint16_t chipIntel, uint16_t gpioAddr, bool allowUnlock,
                                               uint8_t ecConfig, uint8_t smbusBits)
{
    lpcPortSel = psel;
    chipAddr = addr;
    this->gpioAddr = gpioAddr;
    ecSpecialConfig = ecConfig;
    smbusBitmap = smbusBits;
    ChipAccess access(*this);

    switch (chipIntel)
    {
        case CHIP_IT8665E:
            //
            // Selected BEFORE the backup loop below, which reads the control-mode
            // bytes through regPwmCtrl. Getting this order wrong would snapshot
            // the wrong registers and then restore them on top of the real ones.
            //
            regFanRPM = kFAN_RPM_REGS_8665;
            regFanRPMExt = kFAN_RPM_EXT_REGS_8665;
            regPwmCtrl = kFAN_PWM_CTRL_REGS_8665;
            activeFansOnSystem = 6;
            break;
        case CHIP_IT8688E:
        case CHIP_IT8686E:
        case CHIP_IT8689E:
        default:
            activeFansOnSystem = 6;
            break;
    }

    // Enable 16-bit fan tachometer mode for all 6 fans only when the caller
    // is privileged (same gate as NCT67XX/NCT668X in initSuperIO).
    if (allowUnlock) {
        tach16BitRequested = true;
        writeByte(0x0c, static_cast<uint8_t>(readByte(0x0c) | 0x3f));
    }

    // backup default ctrl mode
    for (int i = 0; i < activeFansOnSystem; i++)
    {
        fanDefaultControlMode[i] = readByte(regPwmCtrl[i]);
        fanDefaultExtControlMode[i] = readByte(kFAN_PWM_CTRL_EXT_REGS[i]);
    }

    if (allowUnlock && chipIntel == CHIP_IT8665E) {
        const uint8_t source = static_cast<uint8_t>(readReg(kTEMP_SRC1_REG) & 0x0f);
        temp1Written = source == kTEMP_SRC_WRITTEN;
        IOLog("IT8665E temperature input 1 source 0x%x%s\n", source, temp1Written ? ", written by this driver" : "");
    }
}

bool ISSuperIOIT86XXEFamily::feedCPUTemperature(uint8_t celsius)
{
    if (!temp1Written)
        return false;
    ChipAccess access(*this);
    writeByte(kTEMP1_REG, celsius > kTEMP1_MAX ? kTEMP1_MAX : celsius);
    return true;
}

// ITE MB PnP configuration mode, as Linux it87 / LibreHardwareMonitor IT87:
// the 0x87 0x01 0x55 key, then 0x55 on port 0x2E or 0xAA on port 0x4E.
static void enterConfig(i386_ioport_t regport)
{
    outb(regport, 0x87);
    outb(regport, 0x01);
    outb(regport, 0x55);
    outb(regport, regport == 0x4E ? 0xAA : 0x55);
}

// Leaving sets bit 1 of configuration-control register 0x02 (index AND value;
// the old code wrote only the index, which left the chip in config mode).
// Port 0x4E is the secondary chip on dual-ITE Gigabyte boards and is left
// alone, as LibreHardwareMonitor does: exiting it there disturbs the primary.
static void exitConfig(int portSel)
{
    const i386_ioport_t regport = ISLPCPort::kREGISTER_PORTS[portSel];
    if (regport == 0x4E)
        return;
    outb(regport, 0x02);
    outb(ISLPCPort::kVALUE_PORTS[portSel], 0x02);
}

ISSuperIOIT86XXEFamily* ISSuperIOIT86XXEFamily::getDevice(uint16_t* chipIntel, bool allowUnlock)
{
    IOLog("probe IT86XXE\n");

    for (int portSel = 0; portSel < 2; portSel++)
    {
        enterConfig(ISLPCPort::kREGISTER_PORTS[portSel]);

        const uint8_t idHigh = ISLPCPort::readByte(portSel, ISLPCPort::kCHIP_ID_REG);
        const uint8_t idLow = ISLPCPort::readByte(portSel, ISLPCPort::kCHIP_REVISION_REG);
        const uint16_t chipID = (uint16_t)((idHigh << 8) | idLow);
        *chipIntel = chipID;

        switch (chipID)
        {
            case CHIP_IT8688E:
            case CHIP_IT8686E:
            case CHIP_IT8665E:
            case CHIP_IT8689E:
                break;
            default:
                exitConfig(portSel);
                continue;
        }

        IOLog("IT%04XE chip identified\n", chipID);

        // Base addresses must read back the same twice; a mismatch means the
        // LPC bus is not answering reliably and the chip is not used.
        ISLPCPort::select(portSel, CHIP_ENVIRONMENT_CONTROLLER_LDN);
        const uint16_t devAddr = ISLPCPort::readWord(portSel, ISLPCPort::kBASE_ADDRESS_REGISTER);
        IODelay(10);
        if (ISLPCPort::readWord(portSel, ISLPCPort::kBASE_ADDRESS_REGISTER) != devAddr)
        {
            IOLog("IT%04XE address verify failed\n", chipID);
            exitConfig(portSel);
            return nullptr;
        }

        ISLPCPort::select(portSel, CHIP_GPIO_LDN);
        const uint16_t gpioAddress = ISLPCPort::readWord(portSel, ISLPCPort::kBASE_ADDRESS_REGISTER + 2);
        IODelay(10);
        if (ISLPCPort::readWord(portSel, ISLPCPort::kBASE_ADDRESS_REGISTER + 2) != gpioAddress)
        {
            IOLog("IT%04XE gpio address verify failed\n", chipID);
            exitConfig(portSel);
            return nullptr;
        }

        // SMBus access to the hardware monitor, as firmware set it up (see
        // the header). Left alone on port 0x4E, where this driver never
        // leaves configuration mode, and for unprivileged probes, which
        // must not write configuration registers.
        uint8_t ecConfig = 0;
        uint8_t smbusBits = 0;
        if (allowUnlock && ISLPCPort::kREGISTER_PORTS[portSel] == 0x2E)
        {
            ISLPCPort::select(portSel, CHIP_ENVIRONMENT_CONTROLLER_LDN);
            ecConfig = ISLPCPort::readByte(portSel, kSPECIAL_CFG_REG);
            const uint8_t chipBits = (chipID == CHIP_IT8665E) ? 0x04 : 0x06;
            smbusBits = static_cast<uint8_t>(ecConfig & chipBits);
            IOLog("IT%04XE EC config 0x%02x, SMBus access bits 0x%02x\n", chipID, ecConfig, smbusBits);
        }

        exitConfig(portSel);
        return new ISSuperIOIT86XXEFamily(portSel, devAddr, chipID, gpioAddress, allowUnlock, ecConfig, smbusBits);
    }

    return nullptr;
}

// Takes the chip from the embedded controller: SMBus access off, then the
// bank register saved and set to bank 0, where every register this driver
// uses lives. Linux it87 smbus_disable().
void ISSuperIOIT86XXEFamily::beginAccess()
{
    if (accessDepth++ > 0 || !smbusBitmap)
        return;
    enterConfig(ISLPCPort::kREGISTER_PORTS[lpcPortSel]);
    ISLPCPort::select(lpcPortSel, CHIP_ENVIRONMENT_CONTROLLER_LDN);
    ISLPCPort::writeByte(lpcPortSel, kSPECIAL_CFG_REG, static_cast<uint8_t>(ecSpecialConfig & ~smbusBitmap));
    exitConfig(lpcPortSel);
    savedBank = readByte(kBANK_REG);
    if (savedBank & 0x60)
        writeByte(kBANK_REG, static_cast<uint8_t>(savedBank & 0x1f));
}

// Gives it back: the bank register as found, then SMBus access on again.
// Linux it87 smbus_enable().
void ISSuperIOIT86XXEFamily::endAccess()
{
    if (accessDepth <= 0)
        return;
    if (--accessDepth > 0 || !smbusBitmap)
        return;
    if (savedBank & 0x60)
        writeByte(kBANK_REG, savedBank);
    enterConfig(ISLPCPort::kREGISTER_PORTS[lpcPortSel]);
    ISLPCPort::select(lpcPortSel, CHIP_ENVIRONMENT_CONTROLLER_LDN);
    ISLPCPort::writeByte(lpcPortSel, kSPECIAL_CFG_REG, ecSpecialConfig);
    exitConfig(lpcPortSel);
}

uint8_t ISSuperIOIT86XXEFamily::readConfig(uint8_t index)
{
    if (ISLPCPort::kREGISTER_PORTS[lpcPortSel] != 0x2E)
        return 0;
    enterConfig(ISLPCPort::kREGISTER_PORTS[lpcPortSel]);
    ISLPCPort::select(lpcPortSel, CHIP_ENVIRONMENT_CONTROLLER_LDN);
    const uint8_t value = ISLPCPort::readByte(lpcPortSel, index);
    exitConfig(lpcPortSel);
    return value;
}

uint8_t ISSuperIOIT86XXEFamily::readReg(uint16_t reg)
{
    if (reg & 0x1000)
        return readConfig(static_cast<uint8_t>(reg & 0xff));
    ChipAccess access(*this);
    const uint8_t bank = static_cast<uint8_t>((reg >> 8) & 0x03);
    if (!bank)
        return readByte(reg);
    const uint8_t bankReg = readByte(kBANK_REG);
    writeByte(kBANK_REG, static_cast<uint8_t>((bankReg & 0x1f) | (bank << 5)));
    const uint8_t value = readByte(reg);
    writeByte(kBANK_REG, bankReg);
    return value;
}

void ISSuperIOIT86XXEFamily::writeReg(uint16_t reg, uint8_t val)
{
    if (reg & 0xfc00)
        return;
    ChipAccess access(*this);
    const uint8_t bank = static_cast<uint8_t>((reg >> 8) & 0x03);
    if (!bank) {
        writeByte(reg, val);
        return;
    }
    const uint8_t bankReg = readByte(kBANK_REG);
    writeByte(kBANK_REG, static_cast<uint8_t>((bankReg & 0x1f) | (bank << 5)));
    writeByte(reg, val);
    writeByte(kBANK_REG, bankReg);
}

uint8_t ISSuperIOIT86XXEFamily::readByte(uint16_t addr)
{
    outb(chipAddr + CHIP_ADDR_REG_OFFSET, addr & 0xFF);
    return inb(chipAddr + CHIP_DAT_REG_OFFSET);
}

void ISSuperIOIT86XXEFamily::writeByte(uint16_t addr, uint8_t val)
{
    outb(chipAddr + CHIP_ADDR_REG_OFFSET, addr & 0xFF);
    outb(chipAddr + CHIP_DAT_REG_OFFSET, val);
}

int ISSuperIOIT86XXEFamily::getNumberOfFans()
{
    return activeFansOnSystem;
}

const char* ISSuperIOIT86XXEFamily::getReadableStringForFan(int fan)
{
    if (fan < 0 || fan >= activeFansOnSystem || fan >= 6)
        return nullptr;
    return kFAN_READABLE_STRS[fan];
}

uint32_t ISSuperIOIT86XXEFamily::getRPMForFan(int fan)
{
    if (fan < 0 || fan >= activeFansOnSystem)
        return 0;
    return static_cast<uint32_t>(fanRPMs[fan]);
}

bool ISSuperIOIT86XXEFamily::getFanRPMValid(int fan)
{
    if (fan < 0 || fan >= activeFansOnSystem)
        return false;
    return fanRPMValid[fan];
}

bool ISSuperIOIT86XXEFamily::getFanAutoControlMode(int fan)
{
    if (fan < 0 || fan >= activeFansOnSystem)
        return 0;
    // RegPwmCtrl[fan] (0x15-0x17 on channels 0-2, chip-dependent above): bit 7 = SmartGuardian mode
    // In SmartGuardian mode: fan is controlled by SmartGuardian firmware (Auto).
    // In Manual mode (bit 7 = 0): fan is overridden by software.
    return (fanControlMode[fan] & 0x80) != 0;
}

uint8_t ISSuperIOIT86XXEFamily::getFanThrottle(int fan)
{
    if (fan < 0 || fan >= activeFansOnSystem)
        return 0;
    return static_cast<uint8_t>(fanThrottles[fan]);
}

void ISSuperIOIT86XXEFamily::updateFanRPMS()
{
    ChipAccess access(*this);
    // Same validation as ISSuperIONCT67XXFamily::updateFanRPMS. The low and
    // extended count bytes are two separate reads, so they can tear across a
    // tach update, and a count of 0x40 alone gives ~10,500 RPM. One such sample
    // latched into fanPeakRPMs (a high-water mark that only rises) pinned the
    // Auto-mode duty estimate in updateFanControl() near 0 % for the whole boot.
    // A stopped fan (count 0xFFFF or <= 0x3F) still reads as a trusted 0 RPM,
    // which the selector 95 start-up floor relies on.
    static const int kMAX_PLAUSIBLE_RPM = 10500;

    for (int i = 0; i < activeFansOnSystem; i++)
    {
        int ext = readByte(regFanRPMExt[i]);
        int value = readByte(regFanRPM[i]);
        int ext2 = readByte(regFanRPMExt[i]);
        if (ext != ext2) {
            // The count rolled over between reads; take a fresh low byte
            // against the settled high byte.
            value = readByte(regFanRPM[i]);
            ext = ext2;
        }
        value |= ext << 8;

        int rpm = 0;
        if (value > 0x3f && value < 0xffff)
        {
            rpm = (int)(1.35e6f / (value * 2));
        }

        if (rpm > kMAX_PLAUSIBLE_RPM) {
            // Implausible: hold the previous good reading and mark it untrusted.
            fanRPMValid[i] = false;
            continue;
        }

        fanRPMs[i] = rpm;
        fanRPMValid[i] = true;

        // Track peak RPM for PWM estimation in Auto mode. Only trusted samples
        // may raise the high-water mark.
        if ((uint32_t)rpm > fanPeakRPMs[i]) {
            fanPeakRPMs[i] = (uint16_t)rpm;
        }
    }
}

void ISSuperIOIT86XXEFamily::updateFanControl()
{
    ChipAccess access(*this);
    for (int i = 0; i < activeFansOnSystem; i++)
    {
        // kFAN_PWM_CTRL_REGS: contains the PWM control mode byte (bit 7 = SmartGuardian/auto)
        fanControlMode[i] = readByte(regPwmCtrl[i]);
        // kFAN_PWM_CTRL_EXT_REGS: contains the PWM duty cycle register.
        // In manual mode (bit 7 clear): this register holds the user-set duty cycle.
        // In SmartGuardian mode (bit 7 set): this register may not reflect the
        // actual PWM being output — SmartGuardian controls the fan independently.
        fanThrottles[i]   = readByte(kFAN_PWM_CTRL_EXT_REGS[i]);

        // Fallback: if the register reports 0 but the fan is clearly spinning
        // (RPM > 100), the chip is in SmartGuardian mode and doesn't update
        // the ext register. Estimate the throttle from RPM/peakRPM ratio
        // so the UI slider shows the real fan speed in Auto mode.
        if (fanThrottles[i] == 0 && fanRPMValid[i] && fanRPMs[i] > 100 && fanPeakRPMs[i] > 200) {
            uint32_t est = (uint32_t)((uint64_t)fanRPMs[i] * 255 / fanPeakRPMs[i]);
            fanThrottles[i] = est > 255 ? 255 : (uint8_t)est;
        }
    }
}

void ISSuperIOIT86XXEFamily::overrideFanControl(int fan, uint8_t thr)
{
    if (fan < 0 || fan >= activeFansOnSystem)
        return;
    ChipAccess access(*this);
    // Channels 0-2 only, as LibreHardwareMonitor does. Channels 3-5 have no
    // such bit: the old code set bits 0-2 of register 0x14 for them, which
    // belong to channels 0-2 on the chips that use that register at all and
    // which neither Linux it87 nor LibreHardwareMonitor writes. Measured on an
    // IT8665E: a manual duty on channel 4 works without it.
    if (fan < 3) {
        writeByte(kFAN_MAIN_CTRL_REG, static_cast<uint8_t>(readByte(kFAN_MAIN_CTRL_REG) | (1 << fan)));
    }
    writeByte(regPwmCtrl[fan], static_cast<uint8_t>(fanDefaultControlMode[fan] & 0x7F));
    writeByte(kFAN_PWM_CTRL_EXT_REGS[fan], thr);
}

// Linux it87_resume() re-runs it87_init_device(), whose job here is the
// 16-bit counters: firmware that resets them on wake leaves the 8-bit
// counters, which saturate and read slow fans wrong until the next reboot.
void ISSuperIOIT86XXEFamily::resume()
{
    if (!tach16BitRequested)
        return;
    ChipAccess access(*this);
    const uint8_t mode = readByte(0x0c);
    if ((mode & 0x3f) != 0x3f) {
        writeByte(0x0c, static_cast<uint8_t>(mode | 0x3f));
    }
}

void ISSuperIOIT86XXEFamily::setDefaultFanControl(int fan)
{
    if (fan < 0 || fan >= activeFansOnSystem)
        return;
    ChipAccess access(*this);
    // Clear override bit (restore BIOS automatic control). Channels 0-2
    // only; see overrideFanControl().
    if (fan < 3) {
        writeByte(kFAN_MAIN_CTRL_REG, static_cast<uint8_t>(readByte(kFAN_MAIN_CTRL_REG) & ~(1 << fan)));
    }
    writeByte(regPwmCtrl[fan], fanDefaultControlMode[fan]);
    writeByte(kFAN_PWM_CTRL_EXT_REGS[fan], fanDefaultExtControlMode[fan]);
}
