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
    
    virtual uint8_t readReg(uint16_t reg) { return 0; }
    virtual void writeReg(uint16_t reg, uint8_t val) {}
};

#endif /* ISSuperIOSMCFamily_hpp */
