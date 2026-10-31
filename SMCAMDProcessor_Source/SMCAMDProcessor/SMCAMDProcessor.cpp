//
//  SMCAMDProcessor.cpp
//  SMCAMDProcessor
//

#include "SMCAMDProcessor.hpp"
#include "KeyImplementations.hpp"

OSDefineMetaClassAndStructors(SMCAMDProcessor, IOService);

bool SMCAMDProcessor::setupKeysVsmc(){
    bool suc = true;
    size_t keyCount = 0;
    
    if (fProvider) {
        // === Temperature keys (SP78 format) ===
        // TC0x keys: package temperature reported by the SMU (index 0)
        suc &= VirtualSMCAPI::addKey(KeyTCxD(0), vsmcPlugin.data, VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new TempPackage(fProvider, 0))); keyCount++;
        suc &= VirtualSMCAPI::addKey(KeyTCxE(0), vsmcPlugin.data, VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new TempPackage(fProvider, 0))); keyCount++;
        suc &= VirtualSMCAPI::addKey(KeyTCxF(0), vsmcPlugin.data, VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new TempPackage(fProvider, 0))); keyCount++;
        suc &= VirtualSMCAPI::addKey(KeyTCxJ(0), vsmcPlugin.data, VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new TempPackage(fProvider, 0))); keyCount++;
        suc &= VirtualSMCAPI::addKey(KeyTCxP(0), vsmcPlugin.data, VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new TempPackage(fProvider, 0))); keyCount++;
        suc &= VirtualSMCAPI::addKey(KeyTCxT(0), vsmcPlugin.data, VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new TempPackage(fProvider, 0))); keyCount++;
        suc &= VirtualSMCAPI::addKey(KeyTCxp(0), vsmcPlugin.data, VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new TempPackage(fProvider, 0))); keyCount++;
        
        // === Energy keys (SP96/Float format) ===
        // PCPR/PSTR: package power reported by RAPL MSR
        suc &= VirtualSMCAPI::addKey(KeyPCPR, vsmcPlugin.data, VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp96, new EnergyPackage(fProvider, 0))); keyCount++;
        suc &= VirtualSMCAPI::addKey(KeyPSTR, vsmcPlugin.data, VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp96, new EnergyPackage(fProvider, 0))); keyCount++;

        // PC0C/PCPC: cores power from CORE_ENERGY_STAT, where it reads.
        if (fProvider->coreEnergySupported) {
            suc &= VirtualSMCAPI::addKey(KeyPC0C, vsmcPlugin.data, VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp96, new CorePowerValue(fProvider, 0))); keyCount++;
            suc &= VirtualSMCAPI::addKey(KeyPCPC, vsmcPlugin.data, VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp96, new CorePowerValue(fProvider, 0))); keyCount++;
        }
        
        // === Per-CCD temperature keys (SP78 format) ===
        // TCxC/TCxc: individual Core Complex Die temperatures, iterating over ccdCount
        uint8_t count = fProvider->ccdCount > 0 ? fProvider->ccdCount : 1;
        for (size_t ccd = 0; ccd < count; ccd++) {
            suc &= VirtualSMCAPI::addKey(KeyTCxC(ccd), vsmcPlugin.data, VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new TempCore(fProvider, 0, ccd))); keyCount++;
            suc &= VirtualSMCAPI::addKey(KeyTCxc(ccd), vsmcPlugin.data, VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new TempCore(fProvider, 0, ccd))); keyCount++;
        }
        IOLog("SMCAMDProcessor::setupKeysVsmc: registering %zu CCDs\n", size_t(count));
        
        // === GPU temperature keys (TGxx SP78 format) ===
        // Compatible with SMCRadeonSensors for iStat Menus / HWMonitor.
        uint32_t gpuCountLocal = fProvider->getGPUCount();
        for (uint32_t i = 0; i < gpuCountLocal && i < MaxGPUIndexCount; i++) {
            suc &= VirtualSMCAPI::addKey(KeyTGxD(i), vsmcPlugin.data,
                VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new RGPUTempValue(fProvider, i))); keyCount++;
            suc &= VirtualSMCAPI::addKey(KeyTGxP(i), vsmcPlugin.data,
                VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new RGPUTempValue(fProvider, i))); keyCount++;
            suc &= VirtualSMCAPI::addKey(KeyTGxd(i), vsmcPlugin.data,
                VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new RGPUTempValue(fProvider, i))); keyCount++;
            suc &= VirtualSMCAPI::addKey(KeyTGxp(i), vsmcPlugin.data,
                VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new RGPUTempValue(fProvider, i))); keyCount++;
            
            if (fProvider->gpuSupportsPower(i)) {
                suc &= VirtualSMCAPI::addKey(KeyPGxR(i), vsmcPlugin.data,
                    VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp96, new RGPUPowerValue(fProvider, i))); keyCount++;
                suc &= VirtualSMCAPI::addKey(KeyPGxC(i), vsmcPlugin.data,
                    VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp96, new RGPUPowerValue(fProvider, i))); keyCount++;
            }
        }
        
        // TGDD: primary GPU die temperature (legacy compatibility)
        if (gpuCountLocal > 0) {
            suc &= VirtualSMCAPI::addKey(KeyTGDD, vsmcPlugin.data,
                VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new RGPUTempValue(fProvider, 0))); keyCount++;
        }
        
        IOLog("SMCAMDProcessor::setupKeysVsmc: registering %u GPUs\n", gpuCountLocal);

        // === Fan keys (FNum ui8 const, FxAc fpe2) ===
        // Read-only mirrors of the tachometers the provider re-reads every
        // second; there is no SMC write path, fan control stays behind the
        // user client's privilege model. Absent without a detected chip, so
        // a board SMCSuperIO drives instead keeps its own keys.
        int fanCountLocal = fProvider->fanCount();
        if (fanCountLocal > (int)MaxFanIndexCount) fanCountLocal = (int)MaxFanIndexCount;
        if (fanCountLocal > 0) {
            suc &= VirtualSMCAPI::addKey(KeyFNum, vsmcPlugin.data,
                VirtualSMCAPI::valueWithUint8((uint8_t)fanCountLocal, nullptr,
                                              SMC_KEY_ATTRIBUTE_CONST | SMC_KEY_ATTRIBUTE_READ)); keyCount++;
            for (int i = 0; i < fanCountLocal; i++) {
                suc &= VirtualSMCAPI::addKey(KeyFxAc((size_t)i), vsmcPlugin.data,
                    VirtualSMCAPI::valueWithFp(0, SmcKeyTypeFpe2, new FanSpeedValue(fProvider, (size_t)i))); keyCount++;
            }
        }
        IOLog("SMCAMDProcessor::setupKeysVsmc: registering %d fan(s)\n", fanCountLocal);

        // === CPU core voltage (VC0C flt) ===
        // From the provider's SVI2 cache; absent on SVI3 parts (Zen 4/5).
        if (fProvider->svi.supported) {
            suc &= VirtualSMCAPI::addKey(KeyVC0C, vsmcPlugin.data,
                VirtualSMCAPI::valueWithFlt(0, new CoreVoltageValue(fProvider, 0))); keyCount++;
        }
    } else {
        IOLog("SMCAMDProcessor::setupKeysVsmc: fProvider is null, skipping key registration\n");
    }
    
    if(!suc){
        IOLog("SMCAMDProcessor::setupKeysVsmc: at least one of %zu keys failed to register\n", keyCount);
    } else {
        IOLog("SMCAMDProcessor::setupKeysVsmc: registered %zu VirtualSMC keys\n", keyCount);
    }

    // VirtualSMC merges a plugin's keys into its sorted store and looks them
    // up by binary search, so they must arrive sorted; keys added out of
    // order (the fan keys after the T* ones) land in the index but answer
    // no key-info request. acidanthera's plugins sort here too.
    qsort(const_cast<VirtualSMCKeyValue *>(vsmcPlugin.data.data()), vsmcPlugin.data.size(),
          sizeof(VirtualSMCKeyValue), VirtualSMCKeyValue::compare);

    // Only now ask for VirtualSMC: when it is already published the handler
    // runs inside this call and submits vsmcPlugin as it stands, so the keys
    // have to be in it first (acidanthera's own plugins use the same order).
    vsmcNotifier = VirtualSMCAPI::registerHandler(vsmcNotificationHandler, this);

    return suc;
}

bool SMCAMDProcessor::vsmcNotificationHandler(void *sensors, void *refCon, IOService *vsmc, IONotifier *notifier) {
    if (sensors && vsmc) {
        IOLog("SMCAMDProcessor: got vsmc notification\n");
        auto &plugin = static_cast<SMCAMDProcessor *>(sensors)->vsmcPlugin;
        auto ret = vsmc->callPlatformFunction(VirtualSMCAPI::SubmitPlugin, true, sensors, &plugin, nullptr, nullptr);
        if (ret == kIOReturnSuccess) {
            IOLog("SMCAMDProcessor: submitted plugin\n");
            return true;
        } else if (ret != kIOReturnUnsupported) {
            IOLog("SMCAMDProcessor: plugin submission failure %X\n", ret);
        } else {
            IOLog("SMCAMDProcessor: plugin submission to non vsmc\n");
        }
    } else {
        IOLog("SMCAMDProcessor: got null vsmc notification\n");
    }
    return false;
}

bool SMCAMDProcessor::init(OSDictionary *dictionary){
    return IOService::init(dictionary);
}

void SMCAMDProcessor::free(void){
    IOService::free();
}

bool SMCAMDProcessor::start(IOService *provider){
    
    if(!IOService::start(provider))
        return false;
    
    fProvider = OSDynamicCast(AMDRyzenCPUPowerManagement, provider);
    if(!fProvider)
        return false;
    
    
    IOLog("SMCAMDProcessor: inited, registering VirtualSMC keys...\n");
    
    setupKeysVsmc();
    
    return true;
}

void SMCAMDProcessor::stop(IOService *provider){
    if (vsmcNotifier) {
        vsmcNotifier->remove();
        vsmcNotifier = nullptr;
    }
    fProvider = nullptr;
    IOService::stop(provider);
}
