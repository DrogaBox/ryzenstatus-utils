//
//  ISSuperIOIT86XXEFamily.hpp
//  AMDRyzenCPUPowerManagement
//
//  Created by Maurice on 25.05.20.
//

#ifndef ISSuperIOIT86XXEFamily_hpp
#define ISSuperIOIT86XXEFamily_hpp

#include <IOKit/IOLib.h>

#include <architecture/i386/pio.h>

#include "ISLPCPort.h"
#include "ISSuperIOSMCFamily.hpp"

#define CHIP_IT8688E 0x8688
#define CHIP_IT8686E 0x8686
#define CHIP_IT8665E 0x8665
#define CHIP_IT8689E 0x8689

#define IT86XXE_MAX_NUMFAN 6

#define CHIP_ENVIRONMENT_CONTROLLER_LDN 0x04
#define CHIP_GPIO_LDN 0x07

#define CHIP_ADDR_REG_OFFSET 0x05
#define CHIP_DAT_REG_OFFSET 0x06

class ISSuperIOIT86XXEFamily : public ISSuperIOSMCFamily
{

  public:
    static constexpr const char* kFAN_READABLE_STRS[] = {
        "CPU Fan",
        "System 1 Fan",
        "System 2 Fan",
        "PCH Fan",
        "CPU OPT Fan",
        "System 3 Fan",
    };

    static ISSuperIOIT86XXEFamily* getDevice(uint16_t* chipIntel);

    ISSuperIOIT86XXEFamily(int psel, uint16_t addr, uint16_t chipIntel, uint16_t gpioAddr);

    int fanRPMs[IT86XXE_MAX_NUMFAN];
    int fanControlMode[IT86XXE_MAX_NUMFAN];
    int fanThrottles[IT86XXE_MAX_NUMFAN]{};
    uint16_t fanPeakRPMs[IT86XXE_MAX_NUMFAN]{};

    int activeFansOnSystem = 0;

    int getNumberOfFans() override;
    const char* getReadableStringForFan(int fan) override;

    uint32_t getRPMForFan(int fan) override;
    bool getFanAutoControlMode(int fan) override;
    uint8_t getFanThrottle(int fan) override;

    void updateFanRPMS() override;
    void updateFanControl() override;

    void overrideFanControl(int fan, uint8_t thr) override;
    void setDefaultFanControl(int fan) override;

    uint8_t readReg(uint16_t reg) override { return readByte(reg); }
    void writeReg(uint16_t reg, uint8_t val) override { writeByte(reg, val); }

  private:
    static constexpr uint16_t kFAN_MAIN_CTRL_REG = 0x13;
    //
    // This family needs TWO register maps, not one. IT8686E/IT8688E/IT8689E and
    // IT8665E differ in the sixth tachometer and in the PWM control-mode byte of
    // channels 4-6. Linux's it87 driver carries both tables and picks per chip in
    // it87_init_regs(); this driver carried only the first and applied it to every
    // ITE part it claims to support.
    //
    // On an IT8665E that made the sixth tachometer read 0x4c/0x4d, which hold
    // something else there, and — the part that actually matters — made
    // overrideFanControl() and setDefaultFanControl() WRITE the control-mode byte
    // of fans 3-5 into 0x7f/0xa7/0xaf instead of 0x1e/0x1f/0x92.
    //
    // The duty table has no _8665 variant because it needs none: Linux keeps one
    // IT87_REG_PWM_DUTY for the whole family, which is why duty read back
    // correctly on all six channels while the sixth tachometer did not.
    //
    static constexpr uint16_t kFAN_RPM_REGS[] = {0x0d, 0x0e, 0x0f, 0x80, 0x82, 0x4c};
    static constexpr uint16_t kFAN_RPM_EXT_REGS[] = {0x18, 0x19, 0x1a, 0x81, 0x83, 0x4d};
    static constexpr uint16_t kFAN_PWM_CTRL_REGS[] = {0x15, 0x16, 0x17, 0x7f, 0xa7, 0xaf};

    static constexpr uint16_t kFAN_RPM_REGS_8665[] = {0x0d, 0x0e, 0x0f, 0x80, 0x82, 0x93};
    static constexpr uint16_t kFAN_RPM_EXT_REGS_8665[] = {0x18, 0x19, 0x1a, 0x81, 0x83, 0x94};
    static constexpr uint16_t kFAN_PWM_CTRL_REGS_8665[] = {0x15, 0x16, 0x17, 0x1e, 0x1f, 0x92};

    static constexpr uint16_t kFAN_PWM_CTRL_EXT_REGS[] = {0x63, 0x6b, 0x73, 0x7b, 0xa3, 0xab};

    //
    // Resolved once in the constructor from the chip id getDevice() has already
    // read off the hardware, so which map is used is decided by the silicon and
    // never assumed. Defaults are the pre-existing tables, so a chip that is not
    // an IT8665E keeps its exact previous behaviour.
    //
    const uint16_t* regFanRPM = kFAN_RPM_REGS;
    const uint16_t* regFanRPMExt = kFAN_RPM_EXT_REGS;
    const uint16_t* regPwmCtrl = kFAN_PWM_CTRL_REGS;

    int lpcPortSel = 0;

    uint16_t chipAddr = 0;
    uint16_t gpioAddr = 0;
    uint8_t fanDefaultControlMode[IT86XXE_MAX_NUMFAN];
    uint8_t fanDefaultExtControlMode[IT86XXE_MAX_NUMFAN];

    uint8_t readByte(uint16_t addr);
    uint16_t readWord(uint16_t addr);

    void writeByte(uint16_t addr, uint8_t val);
};

#endif /* ISSuperIOIT86XXE_hpp */
