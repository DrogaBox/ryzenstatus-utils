//
//  ISSuperIOIT86XXEFamily.cpp
//  AMDRyzenCPUPowerManagement
//
//  Created by Maurice on 25.05.20.
//

#include "ISSuperIOIT86XXEFamily.hpp"

ISSuperIOIT86XXEFamily::ISSuperIOIT86XXEFamily(int psel, uint16_t addr, uint16_t chipIntel, uint16_t gpioAddr)
{
    lpcPortSel = psel;
    chipAddr = addr;
    this->gpioAddr = gpioAddr;

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

    // Enable 16-bit fan tachometer mode for all 6 fans
    writeByte(0x0c, static_cast<uint8_t>(readByte(0x0c) | 0x3f));

    // backup default ctrl mode
    for (int i = 0; i < activeFansOnSystem; i++)
    {
        fanDefaultControlMode[i] = readByte(regPwmCtrl[i]);
        fanDefaultExtControlMode[i] = readByte(kFAN_PWM_CTRL_EXT_REGS[i]);
    }
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

ISSuperIOIT86XXEFamily* ISSuperIOIT86XXEFamily::getDevice(uint16_t* chipIntel)
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

        exitConfig(portSel);
        return new ISSuperIOIT86XXEFamily(portSel, devAddr, chipID, gpioAddress);
    }

    return nullptr;
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
    if (fan < 3) {
        writeByte(kFAN_MAIN_CTRL_REG, static_cast<uint8_t>(readByte(kFAN_MAIN_CTRL_REG) | (1 << fan)));
    } else {
        writeByte(0x14, static_cast<uint8_t>(readByte(0x14) | (1 << (fan - 3))));
    }
    writeByte(regPwmCtrl[fan], static_cast<uint8_t>(fanDefaultControlMode[fan] & 0x7F));
    writeByte(kFAN_PWM_CTRL_EXT_REGS[fan], thr);
}

void ISSuperIOIT86XXEFamily::setDefaultFanControl(int fan)
{
    if (fan < 0 || fan >= activeFansOnSystem)
        return;
    // Clear override bit (restore BIOS automatic control)
    if (fan < 3) {
        writeByte(kFAN_MAIN_CTRL_REG, static_cast<uint8_t>(readByte(kFAN_MAIN_CTRL_REG) & ~(1 << fan)));
    } else {
        writeByte(0x14, static_cast<uint8_t>(readByte(0x14) & ~(1 << (fan - 3))));
    }
    writeByte(regPwmCtrl[fan], fanDefaultControlMode[fan]);
    writeByte(kFAN_PWM_CTRL_EXT_REGS[fan], fanDefaultExtControlMode[fan]);
}
