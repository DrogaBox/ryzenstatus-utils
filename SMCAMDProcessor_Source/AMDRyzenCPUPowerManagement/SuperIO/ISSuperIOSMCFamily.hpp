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
    // Does getRPMForFan(fan) reflect a tachometer word the driver trusts?
    //
    // The NCT drivers already track this per fan to gate their PWM estimator,
    // but it never left the driver, so neither the kext's own safety checks nor
    // the app could tell a held-over stale reading from a fresh one. Default
    // true for a family that does not track validity (ITE), which preserves its
    // existing behaviour exactly: callers keep treating the reading as usable.
    virtual bool getFanRPMValid(int fan) { return true; }
    virtual bool getFanAutoControlMode(int fan);
    virtual uint8_t getFanThrottle(int fan);
    
    virtual void updateFanRPMS();
    virtual void updateFanControl();
    
    virtual void overrideFanControl(int fan, uint8_t thr);
    virtual void setDefaultFanControl(int fan);
    
    virtual uint8_t readReg(uint16_t reg) { return 0; }
    virtual void writeReg(uint16_t reg, uint8_t val) {}
};

#endif /* ISSuperIOSMCFamily_hpp */
