//
//  ISSuperIOSMCFamily.hpp
//  AMDRyzenCPUPowerManagement
//
//  Created by trulyspinach, modified by Droga (2026) on 5/17/20.
//

#ifndef ISSuperIOSMCFamily_hpp
#define ISSuperIOSMCFamily_hpp

class ISSuperIOSMCFamily {

    
public:
    virtual ~ISSuperIOSMCFamily() = default;
    
    virtual int getNumberOfFans();
    virtual const char *getReadableStringForFan(int fan);
    
    virtual uint32_t getRPMForFan(int fan);
    // Does getRPMForFan(fan) reflect a tachometer sample the driver trusts?
    // Every driver here tracks it per fan (an implausible sample is held back
    // and flagged); selector 94 reports it and the selector 95 start-up floor
    // only trusts a valid reading. The default keeps a family without tracking
    // usable.
    virtual bool getFanRPMValid(int fan) { return true; }
    virtual bool getFanAutoControlMode(int fan);
    virtual uint8_t getFanThrottle(int fan);
    
    virtual void updateFanRPMS();
    virtual void updateFanControl();
    
    virtual void overrideFanControl(int fan, uint8_t thr);
    virtual void setDefaultFanControl(int fan);

    // Called from the work loop after a wake from sleep. Firmware may put the
    // chip back to its power-on state on resume (Linux it87 and nct6683 have
    // resume handlers for this), so a family re-applies here whatever its
    // probe set up. The default has nothing to redo.
    virtual void resume() {}

    virtual uint8_t readReg(uint16_t reg) { return 0; }
    virtual void writeReg(uint16_t reg, uint8_t val) {}
};

#endif /* ISSuperIOSMCFamily_hpp */
