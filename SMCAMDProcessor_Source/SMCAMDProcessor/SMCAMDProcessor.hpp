//
//  SMCAMDProcessor.hpp
//  SMCAMDProcessor
//
//  VirtualSMC plugin publishing the AMDRyzenCPUPowerManagement sensors as
//  SMC keys.
//

#ifndef SMCAMDProcessor_h
#define SMCAMDProcessor_h

// Legacy IOService header keeps the plugin loadable on macOS 10.13.
#include "Headers/LegacyHeaders/LegacyIOService.h"
#include <IOKit/IOLib.h>

#include <AMDRyzenCPUPowerManagement.hpp>

#undef EFIAPI   // must place here!
#include <VirtualSMCSDK/kern_vsmcapi.hpp>
#include <VirtualSMCSDK/AppleSmc.h>
#define EFIAPI

class SMCAMDProcessor : public IOService {
    OSDeclareDefaultStructors(SMCAMDProcessor)
    
    /**
     *  VirtualSMC service registration notifier
     */
    IONotifier *vsmcNotifier {nullptr};
    
    static bool vsmcNotificationHandler(void *sensors, void *refCon, IOService *vsmc, IONotifier *notifier);
    
    /**
     *  Registered plugin instance
     */
    VirtualSMCAPI::Plugin vsmcPlugin {
        xStringify(PRODUCT_NAME),
        parseModuleVersion(xStringify(MODULE_VERSION)),
        VirtualSMCAPI::Version,
    };
    
    /**
     *  Key name index mapping — 36 positions (0-9, A-Z).
     *  Used to generate SMC key names like TC0C, TC1C, ..., TCCC, TCDC, etc.
     */
    static constexpr size_t MaxIndexCount = sizeof("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ") - 1;
    static constexpr const char *KeyIndexes = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    
    /** GPU key index limit — 16 positions (0-9, A-F) matching SMCRadeonSensors convention. */
    static constexpr size_t MaxGPUIndexCount = 16;
    
    
    /**
     *  SMC keys this plugin publishes (registered in setupKeysVsmc).
     *
     *  - TC0D/E/F/J/P/T/p: package temperature (SP78)
     *  - PCPR, PSTR: package power (SP96)
     *  - PC0C, PCPC: summed CPU core power (SP96), only where
     *    CORE_ENERGY_STAT reads
     *  - TCxC/TCxc: per-CCD temperature (SP78), x = CCD index
     *  - TGxD/P/d/p, TGDD: GPU temperature (SP78), x = GPU index
     *  - PGxR/PGxC: GPU power (SP96), only for GPUs that report it
     *  - FNum, FxAc: Super I/O fan count and tachometers (fpe2), x = header
     *  - VC0C: SVI2 core voltage (flt), only on silicon with an SVI2 layout
     */
    static constexpr SMC_KEY KeyPCPR = SMC_MAKE_IDENTIFIER('P','C','P','R');
    static constexpr SMC_KEY KeyPSTR = SMC_MAKE_IDENTIFIER('P','S','T','R');
    // CPU cores power (sum of the per-core energy counters), the keys
    // SMCProcessor fills on Intel and iStat Menus / Stats label "CPU Cores".
    static constexpr SMC_KEY KeyPC0C = SMC_MAKE_IDENTIFIER('P','C','0','C');
    static constexpr SMC_KEY KeyPCPC = SMC_MAKE_IDENTIFIER('P','C','P','C');
    static constexpr SMC_KEY KeyTCxD(size_t i) { return SMC_MAKE_IDENTIFIER('T','C',KeyIndexes[i < MaxIndexCount ? i : 0],'D'); }
    static constexpr SMC_KEY KeyTCxE(size_t i) { return SMC_MAKE_IDENTIFIER('T','C',KeyIndexes[i < MaxIndexCount ? i : 0],'E'); }
    static constexpr SMC_KEY KeyTCxF(size_t i) { return SMC_MAKE_IDENTIFIER('T','C',KeyIndexes[i < MaxIndexCount ? i : 0],'F'); }
    static constexpr SMC_KEY KeyTCxJ(size_t i) { return SMC_MAKE_IDENTIFIER('T','C',KeyIndexes[i < MaxIndexCount ? i : 0],'J'); }
    static constexpr SMC_KEY KeyTCxP(size_t i) { return SMC_MAKE_IDENTIFIER('T','C',KeyIndexes[i < MaxIndexCount ? i : 0],'P'); }
    static constexpr SMC_KEY KeyTCxT(size_t i) { return SMC_MAKE_IDENTIFIER('T','C',KeyIndexes[i < MaxIndexCount ? i : 0],'T'); }
    static constexpr SMC_KEY KeyTCxp(size_t i) { return SMC_MAKE_IDENTIFIER('T','C',KeyIndexes[i < MaxIndexCount ? i : 0],'p'); }

    static constexpr SMC_KEY KeyTCxC(size_t i) { return SMC_MAKE_IDENTIFIER('T','C',KeyIndexes[i < MaxIndexCount ? i : 0],'C'); }
    static constexpr SMC_KEY KeyTCxc(size_t i) { return SMC_MAKE_IDENTIFIER('T','C',KeyIndexes[i < MaxIndexCount ? i : 0],'c'); }
    
    // === GPU temperature keys (TGxx) ===
    // Follow SMCRadeonSensors convention for iStat Menus / HWMonitor compatibility.
    // Indices: 0-9, A-F (up to 16 GPUs)
    static constexpr SMC_KEY KeyTGxD(size_t i) { return SMC_MAKE_IDENTIFIER('T','G',KeyIndexes[i < MaxGPUIndexCount ? i : 0],'D'); }
    static constexpr SMC_KEY KeyTGxP(size_t i) { return SMC_MAKE_IDENTIFIER('T','G',KeyIndexes[i < MaxGPUIndexCount ? i : 0],'P'); }
    static constexpr SMC_KEY KeyTGxd(size_t i) { return SMC_MAKE_IDENTIFIER('T','G',KeyIndexes[i < MaxGPUIndexCount ? i : 0],'d'); }
    static constexpr SMC_KEY KeyTGxp(size_t i) { return SMC_MAKE_IDENTIFIER('T','G',KeyIndexes[i < MaxGPUIndexCount ? i : 0],'p'); }
    static constexpr SMC_KEY KeyTGDD = SMC_MAKE_IDENTIFIER('T','G','D','D');
    
    // === GPU power keys (PGxx) ===
    static constexpr SMC_KEY KeyPGxR(size_t i) { return SMC_MAKE_IDENTIFIER('P','G',KeyIndexes[i < MaxGPUIndexCount ? i : 0],'R'); }
    static constexpr SMC_KEY KeyPGxC(size_t i) { return SMC_MAKE_IDENTIFIER('P','G',KeyIndexes[i < MaxGPUIndexCount ? i : 0],'C'); }

    // === Fan keys (FNum ui8, FxAc fpe2) ===
    // The SMCSuperIO convention (acidanthera/VirtualSMC, NuvotonDevice::setupKeys),
    // which is what iStat Menus, Stats and HWMonitor read. Up to 16 headers.
    static constexpr size_t MaxFanIndexCount = 16;
    static constexpr SMC_KEY KeyFNum = SMC_MAKE_IDENTIFIER('F','N','u','m');

    // === CPU core voltage (VC0C flt) ===
    // The key iStat Menus, Stats and HWMonitor read as "CPU Core" voltage.
    static constexpr SMC_KEY KeyVC0C = SMC_MAKE_IDENTIFIER('V','C','0','C');
    static constexpr SMC_KEY KeyFxAc(size_t i) { return SMC_MAKE_IDENTIFIER('F',KeyIndexes[i < MaxFanIndexCount ? i : 0],'A','c'); }
    
public:
    
    virtual bool init(OSDictionary *dictionary = 0) override;
    virtual void free(void) override;
    
    virtual bool start(IOService *provider) override;
    virtual void stop(IOService *provider) override;
    
    
private:
    
    bool setupKeysVsmc();
    AMDRyzenCPUPowerManagement *fProvider {nullptr};
    
};


#endif
