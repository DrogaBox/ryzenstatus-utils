#include "AMDRyzenCPUPowerManagement.hpp"
#include <string.h>
#include <mach/mach_time.h>
#include <kern/clock.h>
#include <IOKit/IOPlatformExpert.h>
#include <libkern/c++/OSString.h>
#include <libkern/c++/OSData.h>

OSDefineMetaClassAndStructors(AMDRyzenCPUPowerManagement, IOService);

#define TCTL_OFFSET_TABLE_LEN 6
static constexpr const struct tctl_offset tctl_offset_table[] = {
    { 0x17, "AMD Ryzen 5 1600X", 20 },
    { 0x17, "AMD Ryzen 7 1700X", 20 },
    { 0x17, "AMD Ryzen 7 1800X", 20 },
    { 0x17, "AMD Ryzen 7 2700X", 10 },
    { 0x17, "AMD Ryzen Threadripper 19", 27 }, /* 19{00,20,50}X */
    { 0x17, "AMD Ryzen Threadripper 29", 27 }, /* 29{20,50,70,90}[W]X */
};

static constexpr float  kTHERMAL_THROTTLE_TEMP_C     = 95.0f; // CPPC throttle
static constexpr float  kTHERMAL_THROTTLE_CLEAR_C    = 85.0f;
static constexpr float  kCURVE_OPTIMIZER_BLOCK_TEMP_C = 75.0f;

bool ADDPR(debugEnabled) = false;
uint32_t ADDPR(debugPrintDelay) = 0;


extern "C"{
void pmRyzen_wrmsr_safe(void *handle, uint32_t addr, uint64_t value){
    static_cast<AMDRyzenCPUPowerManagement*>(handle)->write_msr(addr, value);
}

uint64_t pmRyzen_rdmsr_safe(void *handle, uint32_t addr){
    uint64_t v = 0;
    static_cast<AMDRyzenCPUPowerManagement*>(handle)->read_msr(addr, &v);
    return v;
}

pmRyzen_symtable_t pmRyzen_symtable={0};
uint8_t pmRyzen_symtable_ready = 0;

}

#pragma mark - Lifecycle (init, free, start, stop)

bool AMDRyzenCPUPowerManagement::init(OSDictionary *dictionary){
    strncpy(kMODULE_VERSION, xStringify(MODULE_VERSION), sizeof(kMODULE_VERSION) - 1);
    kMODULE_VERSION[sizeof(kMODULE_VERSION) - 1] = '\0';
    IOLog("AMDRyzenCPUPowerManagement v%s, init\n", xStringify(MODULE_VERSION));
    
    IOLog("AMDRyzenCPUPowerManagement::enter dlinking..\n");
    
    pmRyzen_symtable_ready = 0;
    bool resolved = false;
    find_mach_header_addr(getKernelVersion() >= KernelVersion::BigSur);
    for (int symbolRetries = 0; symbolRetries < 50; symbolRetries++) {
        pmRyzen_symtable._wrmsr_carefully = lookup_symbol("_wrmsr_carefully");
        if (pmRyzen_symtable._wrmsr_carefully) {
            resolved = true;
            break;
        }
        if (symbolRetries < 49) IOSleep(10);
    }
    if (!resolved) {
        OSIncrementAtomic(&kextloadAlerts);
        IOLog("AMDRyzenCPUPowerManagement::init symbol resolution for _wrmsr_carefully failed after 50 retries\n");
        return false;
    }
    
    pciConfigLock = IOSimpleLockAlloc();
    superIOLock = IOLockAlloc();
    smuCmdLock = IOLockAlloc();
    rendezvousLock = IOLockAlloc();
    controlLock = IOLockAlloc();
    
    pmRyzen_symtable._KUNCUserNotificationDisplayAlert = lookup_symbol("_KUNCUserNotificationDisplayAlert");
    pmRyzen_symtable._tscFreq = lookup_symbol("_tscFreq");
    pmRyzen_symtable._pmDispatch = lookup_symbol("_pmDispatch");
    pmRyzen_symtable._pmUnRegister = lookup_symbol("_pmUnRegister");
    pmRyzen_symtable._cpu_NMI_interrupt = lookup_symbol("_cpu_NMI_interrupt");
    pmRyzen_symtable._NMIPI_enable = lookup_symbol("_NMIPI_enable");
    pmRyzen_symtable._i386_cpu_IPI = lookup_symbol("_i386_cpu_IPI");
    pmRyzen_symtable_ready = 1;
    IOLog("AMDRyzenCPUPowerManagement::enter link finished.\n");
    return IOService::init(dictionary);
}

void AMDRyzenCPUPowerManagement::free(){
    // Cleanup resources allocated in init() in case start() failed partway
    // and stop() was never called. IOLockFree handles NULL on some XNU versions
    // but we guard explicitly for safety.
    if (pciConfigLock)   { IOSimpleLockFree(pciConfigLock);   pciConfigLock = nullptr; }
    if (superIOLock)     { IOLockFree(superIOLock);           superIOLock = nullptr; }
    if (smuCmdLock)      { IOLockFree(smuCmdLock);            smuCmdLock = nullptr; }
    if (rendezvousLock)  { IOLockFree(rendezvousLock);        rendezvousLock = nullptr; }
    if (controlLock)     { IOLockFree(controlLock);           controlLock = nullptr; }
    if (fIOPCIDevice)    { fIOPCIDevice->release();           fIOPCIDevice = nullptr; }

    // GPU device cleanup
    for (uint32_t i = 0; i < gpuCount; i++) {
        if (gpuDevices[i]) {
            gpuDevices[i]->release();
            gpuDevices[i] = nullptr;
        }
    }
    gpuCount = 0;

    IOService::free();
}


#pragma mark - PCI & Board Info Helpers

bool AMDRyzenCPUPowerManagement::getPCIService(){
    OSDictionary *matching_dict = serviceMatching("IOPCIDevice");
    if(!matching_dict){
        IOLog("AMDRyzenCPUPowerManagement::getPCIService: serviceMatching unable to generate matching dictionary.\n");
        return false;
    }
    
    //Wait for PCI services to init.
    waitForMatchingService(matching_dict);
    
    OSIterator *service_iter = getMatchingServices(matching_dict);
    matching_dict->release();
    IOPCIDevice *service = nullptr;
    
    if(!service_iter){
        IOLog("AMDRyzenCPUPowerManagement::getPCIService: unable to find a matching IOPCIDevice.\n");
        return false;
    }
    
    while (OSObject *obj = service_iter->getNextObject()) {
        IOPCIDevice *dev = OSDynamicCast(IOPCIDevice, obj);
        if (dev) {
            uint16_t vendor = dev->configRead16(kIOPCIConfigVendorID);
            if (vendor == 0x1022) { // AMD Host Bridge Vendor ID
                service = dev;
                break;
            }
        }
    }
    service_iter->release();
    
    if(!service){
        IOLog("AMDRyzenCPUPowerManagement::getPCIService: unable to get AMD IOPCIDevice on host system.\n");
        return false;
    }
    
    IOLog("AMDRyzenCPUPowerManagement::getPCIService: succeed!\n");
    // Retain PCI device reference to guarantee pointer outlives both telemetry timer event sources
    fIOPCIDevice = service;
    fIOPCIDevice->retain();
    
    return true;
}


#pragma mark - GPU Enumeration

void AMDRyzenCPUPowerManagement::enumerateGPUs() {
    OSDictionary *matching_dict = IOService::serviceMatching("IOPCIDevice");
    if (!matching_dict) {
        IOLog("AMDRyzenCPUPowerManagement::enumerateGPUs: serviceMatching failed\n");
        return;
    }

    waitForMatchingService(matching_dict);

    OSIterator *service_iter = IOService::getMatchingServices(matching_dict);
    matching_dict->release();

    if (!service_iter) {
        IOLog("AMDRyzenCPUPowerManagement::enumerateGPUs: no PCI devices found\n");
        return;
    }

    while (OSObject *obj = service_iter->getNextObject()) {
        IOPCIDevice *device = OSDynamicCast(IOPCIDevice, obj);
        if (!device) continue;

        uint16_t vendorID = device->configRead16(kIOPCIConfigVendorID);
        if (vendorID != 0x1002) continue;  // AMD/ATI vendor

        uint32_t fullClass = device->configRead32(kIOPCIConfigClassCode);
        uint32_t baseClass = (fullClass >> 24) & 0xFF;
        uint32_t subClass  = (fullClass >> 16) & 0xFF;

        // Base Class 0x03 = Display Controller
        // Subclasses: 0x00=VGA, 0x01=XGA, 0x02=3D
        if (baseClass != 0x03) {
            continue;
        }

        uint16_t devID = device->configRead16(kIOPCIConfigDeviceID);

        auto *gpu = new AMDGPUDevice{};
        // Max 16 GPUs (sufficient for workstation configs; expand if needed)
        if (gpu && gpu->initFromDevice(device) && gpuCount < 16) {
            gpuDevices[gpuCount] = gpu;
            // AUDIT F-06: no retain() here — OSObject construction starts at
            // refcount 1 and free()/stop() release each slot once. The extra
            // reference made AMDGPUDevice::free() unreachable, leaking the
            // BAR mapping and gpuLock per GPU.
            gpuCount++;
            IOLog("AMDRyzenCPUPowerManagement: Found AMD GPU #%u (device 0x%04X, sub 0x%02X)\n",
                  gpuCount, devID, subClass);
        } else {
            OSSafeReleaseNULL(gpu);
        }
    }

    service_iter->release();
    IOLog("AMDRyzenCPUPowerManagement: Total AMD GPU(s) found: %u\n", gpuCount);
}


#pragma mark - Work Loop Management
void AMDRyzenCPUPowerManagement::initWorkLoop() {
    IOLog("AMDRyzenCPUPowerManagement::startWorkLoop setting up timer");
    timerEvent_main = IOTimerEventSource::timerEventSource(this, [](OSObject *object, IOTimerEventSource *sender) {
        AMDRyzenCPUPowerManagement *provider = OSDynamicCast(AMDRyzenCPUPowerManagement, object);
        if (!provider) return;

        //Run initialization
        if(!provider->serviceInitialized){
            IOLog("AMDRyzenCPUPowerManagement::startWorkLoop initialize service");
            
            //Disable interrupts and sync all processor cores.
            IOLockLock(provider->rendezvousLock);
            mp_rendezvous_no_intrs([](void *obj) {
                auto provider = static_cast<AMDRyzenCPUPowerManagement*>(obj);
                
                // NOTE: Writing kMSR_CSTATE_ADDR (0xC0010073) with 0xF0 disables
                // deep C-states (C6+), reducing wake latency for telemetry and audio.
                // Configured via the amdcstate boot-arg (amdcstate=0 enables C6;
                // amdcstate=1 or default disables C6).
                if (provider->disableCStates) {
                    provider->write_msr(kMSR_CSTATE_ADDR, 0xf0);
                }
                
                uint64_t hwConfig;
                if(!provider->read_msr(kMSR_HWCR, &hwConfig)) {
                    IOLog("AMDRyzenCPUPowerManagement::startWorkLoop: failed to read kMSR_HWCR, skipping init.\n");
                    return;
                }

                hwConfig |= (1 << 30);
                provider->write_msr(kMSR_HWCR, hwConfig);


                uint32_t cpu_num = cpu_number();

                //Read PStateDef generated by EFI.
                if(pmRyzen_cpu_is_master(cpu_num))
                    provider->dumpPstate();

                // Query CPPC core ranking per logical core if supported
                // Only read CPPC CAP1 for core ranking; do NOT write CPPC_ENABLE in baseline.
                if (provider->cppcSupported && cpu_num < CPUInfo::MaxCpus) {
                    uint64_t cppcCap = 0;
                    bool msrSuccess = provider->read_msr(kMSR_AMD_CPPC_CAP1, &cppcCap);
                    IOLog("AMDRyzenCPUPowerManagement::startWorkLoop Core %d CPPC CAP1 read: %d, value: 0x%llX\n", cpu_num, msrSuccess, cppcCap);
                    if (msrSuccess) {
                        // AMD PPR states bits 7:0 are HighestPerformance
                        provider->cppcHighestPerf_perCore[cpu_num] = cppcCap & 0xFF;
                        
                        // For Vermeer baseline: do NOT enable CPPC by default
                        // Keep cppcActiveMode=false to avoid writing CPPC_ENABLE/REQ
                    }
                }


                if(!pmRyzen_cpu_primary_in_core(cpu_num)) return;
                uint8_t physical = pmRyzen_cpu_phys_num(cpu_num);

                // AUDIT F-13: guard physical core index on systems with >64 CPUs (>64 physical cores)
                if (physical >= CPUInfo::MaxCpus) return;

                //Init performance frequency counter.
                uint64_t APERF, MPERF;
                if(!provider->read_msr(kMSR_APERF, &APERF) || !provider->read_msr(kMSR_MPERF, &MPERF)) {
                    IOLog("AMDRyzenCPUPowerManagement::startWorkLoop: failed to read APERF/MPERF, skipping core init.\n");
                    return;
                }

                provider->lastAPERF_perCore[physical] = APERF;
                provider->lastMPERF_perCore[physical] = MPERF;

            }, provider);
            
            uint64_t cstateAddr = 0;
            if (provider->read_msr(kMSR_CSTATE_ADDR, &cstateAddr)) {
                provider->cstateAddrConfig = cstateAddr;
                IOLog("AMDRyzenCPUPowerManagement::startWorkLoop: C-State address configuration: 0x%llX\n", cstateAddr);
            }
            
            //Make all cores P0 state by default.
            provider->PStateCtl = 0;
            
            provider->serviceInitialized = true;
            provider->timerEvent_main->setTimeoutMS(1);
            IOLockUnlock(provider->rendezvousLock);
            return;
        }

        if (!provider->serviceInitialized) return;

        // Post-wake deferred reinit: consume the flag set by resumeWorkLoop()
        // so reinitHwState() runs here on the workLoop thread, not the PM thread.
        if (provider->pendingReinit) {
            provider->pendingReinit = false;
            provider->reinitHwState();
            sender->setTimeoutMS(provider->updateTimeInterval);
            return;
        }

        IOLockLock(provider->rendezvousLock);
        mp_rendezvous_no_intrs([](void *obj) {
            auto provider = static_cast<AMDRyzenCPUPowerManagement*>(obj);
            uint32_t cpu_num = cpu_number();

            provider->updateInstructionDelta(cpu_num);

            // Ignore hyper-threaded cores
            if(!pmRyzen_cpu_primary_in_core(cpu_num)) return;
            uint8_t physical = pmRyzen_cpu_phys_num(cpu_num);


            provider->calculateEffectiveFrequency(physical);

        }, provider);
        
        //Read stats from package.
        provider->updatePackageTemp();
        provider->updatePackageEnergy();
        
        // Read Package C6 Residency MSR (cumulative microseconds)
        provider->read_msr(kMSR_PKG_C6_RES, &provider->packageC6Residency);

        // S5: refresh cached boost telemetry (Vermeer RSMU 0x6E/0x59 reads)
        // from the same command gate — never from user threads (F-05 lesson).
        provider->pollBoostTelemetry();

        // S6: one-shot ProcessorParameters (0x6F) read — static silicon
        // configuration, so stop after the first successful answer this boot.
        provider->pollProcessorParameters();

        // S7: one-shot SMU firmware version (0x02) read — static, cached
        // after the first successful answer this boot.
        provider->pollSmuVersion();

        // S9a: SMU PM-table plumbing — version probe, 0x05 transfer, 0x06
        // base, read-only snapshot capture (throttled to 1/s). Diagnostic
        // only: failures never disturb the control paths.
        provider->pollPMTable();

        IOLockUnlock(provider->rendezvousLock);

        uint64_t now = getCurrentTimeNs() / 1000000; //ms
        uint64_t deltaMissed = (now >= provider->timeOfLastMissedRequest) ? (now - provider->timeOfLastMissedRequest) : 0;
        uint64_t newInt = max(deltaMissed, provider->estimatedRequestTimeInterval);

        uint64_t deltaLast = (now >= provider->timeOfLastUpdate) ? (now - provider->timeOfLastUpdate) : 1;
        provider->actualUpdateTimeInterval = (uint32_t)min((uint64_t)UINT32_MAX, deltaLast);
        provider->timeOfLastUpdate = now;
        provider->updateTimeInterval = (uint32_t)min((uint64_t)1200, max((uint64_t)50, newInt));

        provider->timerEvent_main->setTimeoutMS(provider->updateTimeInterval);

//        IOLog("fpp %d %d %.4f.\n", HF_TEMP_SAMPLE_FREQ, HF_TEMP_SAMPLE_PERIOD, (float)HF_TEMP_SAMPLE_REP);

    });
    
//    tempSamplePeriod = (int)((1.0f / (float)HF_TEMP_SAMPLE_FREQ) * 1000);
    // S10 KRN-04b: seed the ring buffer only with a trustworthy value; the
    // sentinel must never enter tempSamples[], whose average becomes
    // PACKAGE_TEMPERATURE_perPackage[0] (selector 95 guard + SMC keys).
    float fillT = getPackageTemp();
    if (!isTempValid(fillT)) fillT = 0.0f;
    tempNextSample = 0;
    for (int i = 0; i < HF_TEMP_SAMPLE_LEN; i++) tempSamples[i] = fillT;
    
    timerEvent_tempe = IOTimerEventSource::timerEventSource(this, [](OSObject *object, IOTimerEventSource *sender) {
        AMDRyzenCPUPowerManagement *provider = OSDynamicCast(AMDRyzenCPUPowerManagement, object);
        if (!provider || !provider->serviceInitialized) return;
        
        int next_samp = provider->tempNextSample;
        // S10 KRN-04b: hold the previous sample when the read fails, instead of
        // averaging in the sentinel. A stale-but-plausible temperature is far
        // safer here than a value that silently disarms every thermal clamp.
        float t = provider->getPackageTemp();
        if (isTempValid(t)) {
            provider->tempSamples[next_samp] = t;
        }
        provider->tempNextSample = (next_samp + 1) % HF_TEMP_SAMPLE_LEN;
        
        for (uint8_t i = 0; i < provider->ccdCount; i++) {
            provider->ccdTemperatures[i] = provider->getCCDTemp(i);
        }
        
        // Update gpuTempC for fan curve source sensor from first GPU
        if (provider->gpuCount > 0) {
            // Convert UInt16 temperature (degrees C) to float
            provider->gpuTempC = (float)provider->gpuTemperatures[0];
        }

        provider->evaluateFanCurves();

        // GPU temperature and power update
        for (uint32_t i = 0; i < provider->gpuCount; i++) {
            if (provider->gpuDevices[i]) {
                provider->gpuDevices[i]->getTemperature(&provider->gpuTemperatures[i]);
                if (provider->gpuDevices[i]->supportsPower()) {
                    provider->gpuDevices[i]->getPower(&provider->gpuPowers[i]);
                }
            }
        }

        sender->setTimeoutMS(HF_TEMP_SAMPLE_PERIOD);
    });
    
    registerService();
    
    lastUpdateTime = getCurrentTimeNs();
    pwrLastTSC = rdtsc64();
    workLoop->addEventSource(timerEvent_main);
    workLoop->addEventSource(timerEvent_tempe);
    timerEvent_main->setTimeoutMS(1);
    timerEvent_tempe->setTimeoutMS(HF_TEMP_SAMPLE_PERIOD);
}

void AMDRyzenCPUPowerManagement::stopWorkLoop() {
    if (timerEvent_main) timerEvent_main->cancelTimeout();
    if (timerEvent_tempe) timerEvent_tempe->cancelTimeout();
    if (workLoop) workLoop->disableAllEventSources();
    serviceInitialized = false;
}

void AMDRyzenCPUPowerManagement::resumeWorkLoop() {
    if (!workLoop) return;
    // NOTE: Do NOT call reinitHwState() here — this runs on the IOKit PM thread
    // during the wake sequence. Blocking the PM thread with MSR reads + CPPC
    // write + dumpPstate() (up to 128 MSR reads on 16-core Zen 3) causes
    // perceptible lag right after S3 resume. Instead, set the pending flag and
    // let the first timer tick on the workLoop thread do the reinit safely.
    pendingReinit = true;
    workLoop->enableAllEventSources();
    serviceInitialized = true;
    pwrLastTSC = rdtsc64();
    // Give the system 250ms to complete the wake sequence before the kext
    // starts its own rendezvous / MSR work. 1ms was causing a CPU stall spike.
    if (timerEvent_main) timerEvent_main->setTimeoutMS(250);
    if (timerEvent_tempe) timerEvent_tempe->setTimeoutMS(HF_TEMP_SAMPLE_PERIOD);
}


#pragma mark - start() — Main Initialization
bool AMDRyzenCPUPowerManagement::start(IOService *provider){
    
    bool success = IOService::start(provider);
    if(!success){
        IOLog("AMDRyzenCPUPowerManagement::start failed to start. :(\n");
        return false;
    }
    
    disablePrivilegeCheck = checkKernelArgument("-amdpnopchk");
    
    uint32_t amdcstateVal = 1;
    if (PE_parse_boot_argn("amdcstate", &amdcstateVal, sizeof(amdcstateVal))) {
        disableCStates = (amdcstateVal != 0);
    } else {
        disableCStates = true;
    }
    IOLog("AMDRyzenCPUPowerManagement::start C-States (C6) %s (amdcstate=%u)\n",
          disableCStates ? "disabled (low-latency)" : "enabled (power-saving)", amdcstateVal);
    
    uint32_t cpuid_eax = 0;
    uint32_t cpuid_ebx = 0;
    uint32_t cpuid_ecx = 0;
    uint32_t cpuid_edx = 0;
    CPUInfo::getCpuid(0, 0, &cpuid_eax, &cpuid_ebx, &cpuid_ecx, &cpuid_edx);
    IOLog("AMDRyzenCPUPowerManagement::start got CPUID: %X %X %X %X\n", cpuid_eax, cpuid_ebx, cpuid_ecx, cpuid_edx);
    
    if(cpuid_ebx != CPUInfo::signature_AMD_ebx
       || cpuid_ecx != CPUInfo::signature_AMD_ecx
       || cpuid_edx != CPUInfo::signature_AMD_edx){
        IOLog("AMDRyzenCPUPowerManagement::start no AMD signature detected, failing..\n");
        
        return false;
    }
    
    CPUInfo::getCpuid(1, 0, &cpuid_eax, &cpuid_ebx, &cpuid_ecx, &cpuid_edx);
    cpuFamily = ((cpuid_eax >> 20) & 0xff) + ((cpuid_eax >> 8) & 0xf);
    // Correct CPUID model decode: extended model must be shifted left by 4
    uint8_t baseModel = (cpuid_eax >> 4) & 0xF;
    uint8_t extModel = (cpuid_eax >> 16) & 0xF;
    cpuModel = baseModel | (extModel << 4);
    
    // Support for Zen (17h), Zen 2/3/4 (19h), and Zen 5 (1Ah)
    cpuSupportedByCurrentVersion = (cpuFamily == 0x17 || cpuFamily == 0x19 || cpuFamily == 0x1A)? 1 : 0;
    IOLog("AMDRyzenCPUPowerManagement::start Family %02Xh, Model %02Xh\n", cpuFamily, cpuModel);
    
    // cpuArchName is populated below by the active profile's generationName.
    // The profile block handles all known CPU families (Zen 1-5) and
    // sets "Unknown" for unmatched CPUs.
    
    // Determine CCD temperature register offset based on CPU family/model.
    // Sourced from Linux kernel drivers/hwmon/k10temp.c:
    //   Family 17h: offset 0x154 (all models)
    //   Family 19h models 00-5Fh: offset 0x154 (Zen 3/3+)
    //   Family 19h models 60-7Fh: offset 0x308 (Zen 4)
    //   Family 1Ah models 40-4Fh: offset 0x308 (Zen 5 Granite Ridge)
    if (cpuFamily == 0x1A) {
        // Zen 5 (Granite Ridge, etc.)
        ccdOffset = kZEN_CCD_OFFSET_ZEN4_5;
    } else if (cpuFamily == 0x19 && cpuModel >= 0x60 && cpuModel <= 0x7F) {
        // Family 19h models 60-7Fh: Zen 4 desktop (Raphael)
        ccdOffset = kZEN_CCD_OFFSET_ZEN4_5;
    } else {
        // Family 17h all models and Family 19h Zen 3/3+ models use the legacy offset.
        ccdOffset = kZEN_CCD_OFFSET_LEGACY;
    }
    IOLog("AMDRyzenCPUPowerManagement::start CCD temperature offset: 0x%X\n", ccdOffset);
    
    // Resolve capability profile for detected CPU from all known profiles.
    // Each profile defines whether the kext registers PM dispatch + legacy P-states
    // (Zen 1/2: macOS has no native AMD PM) or stays telemetry-only (Zen 3+).
    {
        const ZenCpuFeatureMap *allProfiles[] = {
            &ZEN1_PROFILE, &ZEN_PLUS_PROFILE, &ZEN2_PROFILE,
            &ZEN3_CEZANNE_PROFILE, &ZEN3_VERMEER_PROFILE, &ZEN3_PLUS_PROFILE,
            &ZEN4_PROFILE, &ZEN5_PROFILE,
        };
        const ZenCpuFeatureMap *activeProfile = nullptr;
        for (auto *profile : allProfiles) {
            if (cpuFamily == profile->family &&
                cpuModel >= profile->modelStart &&
                cpuModel <= profile->modelEnd) {
                activeProfile = profile;
                break;
            }
        }
        
        if (activeProfile) {
            cppcReadInInit = activeProfile->supportsCPPC;
            legacyPstateAllowed = activeProfile->legacyPstateAllowed;
            pmDispatchAllowed = activeProfile->pmDispatchAllowed;
            temperatureOffset49 = activeProfile->temperatureOffset49;
            supportsCPPC = activeProfile->supportsCPPC;
            supportsCPPCv2 = activeProfile->supportsCPPCv2;
            zenGeneration = activeProfile->zenGeneration;
            strlcpy(cpuArchName, activeProfile->generationName, sizeof(cpuArchName));
            
            // Build capabilities string matching the app's profile log format
            char capsBuf[64];
            capsBuf[0] = '\0';
            if (activeProfile->pmDispatchAllowed) {
                strlcpy(capsBuf, "PM Dispatch", sizeof(capsBuf));
            }
            if (activeProfile->legacyPstateAllowed) {
                if (capsBuf[0]) strlcat(capsBuf, " · ", sizeof(capsBuf));
                strlcat(capsBuf, "Legacy P-States", sizeof(capsBuf));
            }
            if (activeProfile->supportsCPPC) {
                if (capsBuf[0]) strlcat(capsBuf, " · ", sizeof(capsBuf));
                strlcat(capsBuf, "CPPC", sizeof(capsBuf));
            }
            if (capsBuf[0] == '\0') {
                strlcpy(capsBuf, "Telemetry only", sizeof(capsBuf));
            }
            
            const char *mode = activeProfile->pmDispatchAllowed ? "Full PM Dispatch" : "Telemetry-only";
            IOLog("AMDRyzenCPUPowerManagement::start CPU Profile: %s — %s (Capabilities: %s)\n",
                  mode, activeProfile->generationName, capsBuf);
        } else {
            zenGeneration = 0;
            strlcpy(cpuArchName, "Unknown", sizeof(cpuArchName));
            IOLog("AMDRyzenCPUPowerManagement::start WARN: no profile for Family %02Xh Model %02Xh\n",
                  cpuFamily, cpuModel);
        }
    }
    
    // Single idle strategy for all CPUs: sti; hlt (SIMPLE).
    // Intel-style MONITOR/MWAIT was removed (unsafe on AMD — CPUs don't report CPUID.01h:ECX[3]).
    // AMD MONITORX/MWAITX may be added as a future enhancement for Zen 3+.
    cpuIdleStrategy = PMRYZEN_IDLE_STRATEGY_SIMPLE;
    pmRyzen_idle_strategy = cpuIdleStrategy;
    IOLog("AMDRyzenCPUPowerManagement::start Idle strategy: SIMPLE (sti;hlt)\n");
    
    CPUInfo::getCpuid(0x80000005, 0, &cpuid_eax, &cpuid_ebx, &cpuid_ecx, &cpuid_edx);
    // L1-D size in bits [31:24] of ECX, L1-I size in bits [31:24] of EDX (CPUID 0x80000005)
    cpuCacheL1_perCore = (cpuid_ecx >> 24) + (cpuid_edx >> 24);
    
    
    CPUInfo::getCpuid(0x80000006, 0, &cpuid_eax, &cpuid_ebx, &cpuid_ecx, &cpuid_edx);
    cpuCacheL2_perCore = (cpuid_ecx >> 16);
    cpuCacheL3 = (cpuid_edx >> 18) * 512;
    IOLog("AMDRyzenCPUPowerManagement::start L1: %u, L2: %u, L3: %u\n",
          cpuCacheL1_perCore, cpuCacheL2_perCore, cpuCacheL3);
    
    
    char nameString[49] = {0};
    uint32_t *namePtr = (uint32_t*)nameString;
    CPUInfo::getCpuid(0x80000002, 0, &cpuid_eax, &cpuid_ebx, &cpuid_ecx, &cpuid_edx);
    namePtr[0] = cpuid_eax; namePtr[1] = cpuid_ebx; namePtr[2] = cpuid_ecx; namePtr[3] = cpuid_edx;
    CPUInfo::getCpuid(0x80000003, 0, &cpuid_eax, &cpuid_ebx, &cpuid_ecx, &cpuid_edx);
    namePtr[4] = cpuid_eax; namePtr[5] = cpuid_ebx; namePtr[6] = cpuid_ecx; namePtr[7] = cpuid_edx;
    CPUInfo::getCpuid(0x80000004, 0, &cpuid_eax, &cpuid_ebx, &cpuid_ecx, &cpuid_edx);
    namePtr[8] = cpuid_eax; namePtr[9] = cpuid_ebx; namePtr[10] = cpuid_ecx; namePtr[11] = cpuid_edx;
    nameString[48] = '\0';
    
    IOLog("AMDRyzenCPUPowerManagement::start Processor: %s\n", nameString);
    
    //Check tctl temperature offset
    for(int i = 0; i < TCTL_OFFSET_TABLE_LEN; i++){
        const TempOffset *to = tctl_offset_table + i;
        if(cpuFamily == to->model && strstr(nameString, to->id)){
            
            tempOffset = (float)to->offset;
            break;
        }
    }

    reinitHwState();
    
    fetchOEMBaseBoardInfo();
    
    IOLog("AMDRyzenCPUPowerManagement::start trying to init PCI service...\n");
    if(!getPCIService()){
        IOLog("AMDRyzenCPUPowerManagement::start no PCI support found, failing...\n");
        return false;
    }

    // Enumerate AMD GPUs
    enumerateGPUs();
    
    // Probe for available CCDs by reading CCD temperature registers.
    // A CCD is considered present if the valid bit (bit 11) is set.
    ccdCount = 0;
    for (uint8_t i = 0; i < kMAX_CCD_COUNT; i++) {
        uint32_t regVal = readCCDRegisterRaw(i);
        if (regVal & kZEN_CCD_TEMP_VALID_BIT) {
            ccdCount = i + 1;
            IOLog("AMDRyzenCPUPowerManagement::start CCD%u detected, raw=0x%X\n", i, regVal);
        } else {
            // CCDs are contiguous. If this one is missing/invalid, there are no more.
            // This prevents reading garbage from PCI space at higher indices.
            break;
        }
    }
    // Cap at 8 to match the CPUSensorPacket limit
    if (ccdCount > 8) ccdCount = 8;
    IOLog("AMDRyzenCPUPowerManagement::start Total CCDs detected: %u\n", ccdCount);
    
//    while (!pmRyzen_symtable_ready) {
//        IOSleep(200);
//    }
    
    void *safe_wrmsr = pmRyzen_symtable._wrmsr_carefully;
    if(!safe_wrmsr){
        IOLog("AMDRyzenCPUPowerManagement::start WARN: Can't find _wrmsr_carefully, proceeding with unsafe wrmsr\n");
    } else {
        wrmsr_carefully = (int(*)(uint32_t,uint32_t,uint32_t)) safe_wrmsr;
    }

    void *_kunc_alert = pmRyzen_symtable._KUNCUserNotificationDisplayAlert;
    if(!_kunc_alert){
        IOLog("AMDRyzenCPUPowerManagement::start WARN: Can't find _KUNCUserNotificationDisplayAlert.\n");
    } else {
        kunc_alert =
        (kern_return_t(*)(int,unsigned,const char*,const char*,const char*,
        const char*,const char*,const char*,const char*,const char*,unsigned*))_kunc_alert;
    }

    if (pmRyzen_symtable._tscFreq != nullptr) {
        xnuTSCFreq = *((uint64_t*)pmRyzen_symtable._tscFreq);
    } else {
        struct mach_timebase_info tbInfoData;
        clock_timebase_info(&tbInfoData);
        if (tbInfoData.numer != 0) {
            xnuTSCFreq = (1000000000ULL * (uint64_t)tbInfoData.denom) / (uint64_t)tbInfoData.numer;
            IOLog("AMDRyzenCPUPowerManagement::start WARN: _tscFreq symbol null, using mach_timebase_info fallback TSC frequency (%llu Hz)\n", xnuTSCFreq);
        }
    }
    if (xnuTSCFreq == 0) {
        xnuTSCFreq = 1000000000u; // Fallback default 1GHz calibration
    }

    pmRyzen_init(this, pmDispatchAllowed ? 1 : 0);

    // Populate per-family SMU mailbox descriptor.
    // Sources: ryzen_smu (smu.c / rsmu_commands.md), Linux amd_pmf, AGESA SMU headers.
    // Vermeer RSMU mailbox addresses:
    //   cmd (msg):  0x3B10524
    //   rsp:        0x3B10570
    //   args:       0x3B10A40 (window up to 6 dwords: +0x0, +0x4, ...)
    if (cpuFamily == 0x19 && cpuModel >= 0x21 && cpuModel <= 0x2F) {
        // Zen 3 Vermeer
        smuMailbox = { 0x3B10524, 0x3B10A40, 0x3B10570, 0x3D, true };
    } else if (cpuFamily == 0x19 && cpuModel >= 0x60 && cpuModel <= 0x7F) {
        // Zen 4 Raphael — SMU mailbox moved; Curve Optimizer command is 0x55.
        // NOTE: offsets below are placeholders — verify against AGESA Family 19h Model 60h PPR.
        smuMailbox = { 0x3B10590, 0x3B10594, 0x3B10598, 0x55, true };
        IOLog("AMDRyzenCPUPowerManagement: Zen 4 SMU mailbox offsets are UNVERIFIED — Curve Optimizer writes blocked.\n");
        smuMailbox.supported = false;   // Block until verified
    } else if (cpuFamily == 0x1A) {
        // Zen 5 Granite Ridge — SMU firmware restructured; Curve Optimizer path unknown.
        smuMailbox = { 0, 0, 0, 0, false };
        IOLog("AMDRyzenCPUPowerManagement: Zen 5 SMU mailbox unsupported — Curve Optimizer blocked.\n");
    } else {
        smuMailbox = { 0x3B10524, 0x3B10A40, 0x3B10570, 0x3D, false };
    }

    // One-shot SMU mailbox diagnostic probe at boot
    if (smuMailbox.supported) {
        IOLog("AMDRyzenCPUPowerManagement: [SMU Diagnostic] Mailbox initialized: cmd=0x%08X, arg=0x%08X, rsp=0x%08X\n",
              smuMailbox.msgReg, smuMailbox.argReg, smuMailbox.rspReg);

        uint32_t tctlVal = smnRead32(kF17H_M01H_THM_TCON_CUR_TMP);
        IOLog("AMDRyzenCPUPowerManagement: [SMU Diagnostic] SMN Aperture Probe (0x%08X) = 0x%08X\n",
              kF17H_M01H_THM_TCON_CUR_TMP, tctlVal);

        uint32_t testResult = 0;
        uint32_t testElapsedUs = 0;
        int testRsp = smuSendCmd(0x01, 0x42, testResult, &testElapsedUs);
        IOLog("AMDRyzenCPUPowerManagement: [SMU Diagnostic] TestMessage(0x01, arg=0x42): rsp=0x%X, res0=0x%X (expected 0x43), elapsed=%u us\n",
              testRsp, testResult, testElapsedUs);

        uint32_t verResult = 0;
        uint32_t verElapsedUs = 0;
        int verRsp = smuSendCmd(0x02, 1, verResult, &verElapsedUs);
        IOLog("AMDRyzenCPUPowerManagement: [SMU Diagnostic] GetSMUVersion(0x02, arg=1): rsp=0x%X, raw=0x%08X, elapsed=%u us\n",
              verRsp, verResult, verElapsedUs);

        if (testRsp == SMU_RSP_OK && testResult == 0x43) {
            IOLog("AMDRyzenCPUPowerManagement: [SMU Diagnostic] Mailbox communication verified OK.\n");
        } else {
            IOLog("AMDRyzenCPUPowerManagement: [SMU Diagnostic] WARN: Mailbox communication check failed (rsp=0x%X).\n", testRsp);
        }
    }

    totalNumberOfLogicalCores = pmRyzen_num_logi;
    totalNumberOfPhysicalCores = pmRyzen_num_phys;

    IOLog("AMDRyzenCPUPowerManagement::start, Physical Count: %u, Logical Count %u.\n",
              totalNumberOfPhysicalCores, totalNumberOfLogicalCores);

    for (size_t i = 0; i < kMAX_FANS; i++) {
        fanToCurveMap[i] = -1;
        lastAppliedPWM[i] = 0;
        lastPWMUpdateTime[i] = 0;
    }
    for (int i = 0; i < MAX_FAN_CURVES; i++) {
        memset(fanCurves[i].lut, 0, 256);
        fanCurves[i].sourceSensor = 0;
        fanCurves[i].hysteresis = 2;
        fanCurves[i].rampRate = 5;
        curveSmoothedTemp[i] = 0.0f;
        curveSmoothedSeeded[i] = false;
        // AUDIT F-14: Seed per-curve anchor temperature for downward hysteresis
        lastAppliedTemp[i] = 0.0f;
        lastAppliedTempSeeded[i] = false;
    }
    gpuTempC = 0.0f;

    workLoop = IOWorkLoop::workLoop();
    initWorkLoop();


    PMinit();
    provider->joinPMtree(this);
    registerPowerDriver(this, powerStates, kNrOfPowerStates);

    return success;
}

void AMDRyzenCPUPowerManagement::stop(IOService *provider){

#pragma mark - stop() — Cleanup
    IOLog("AMDRyzenCPUPowerManagement stopping...\n");

    // 1. Cancel all timerEventSource (cancelTimeout)
    if (timerEvent_main)  timerEvent_main->cancelTimeout();
    if (timerEvent_tempe) timerEvent_tempe->cancelTimeout();

    // 2. workLoop->removeEventSource() for each timer
    if (workLoop) {
        workLoop->disableAllEventSources();
        if (timerEvent_main)  workLoop->removeEventSource(timerEvent_main);
        if (timerEvent_tempe) workLoop->removeEventSource(timerEvent_tempe);
    }
    serviceInitialized = false;

    // 3. release() and null each timer
    if (timerEvent_main)  { timerEvent_main->release();  timerEvent_main = nullptr; }
    if (timerEvent_tempe) { timerEvent_tempe->release(); timerEvent_tempe = nullptr; }

    // 4. pmRyzen_stop() after timers are completely drained and unlinked
    pmRyzen_stop();

    // 5. release() of fIOPCIDevice and null
    if (fIOPCIDevice) { fIOPCIDevice->release(); fIOPCIDevice = nullptr; }

    // 6. GPU devices cleanup before superIO and workloop
    for (uint32_t i = 0; i < gpuCount; i++) {
        if (gpuDevices[i]) {
            gpuDevices[i]->release();
            gpuDevices[i] = nullptr;
        }
    }
    gpuCount = 0;

    // 7. SuperIO defaults + delete and workloop release before super::stop()
    if (superIOLock) {
        IOLockLock(superIOLock);
        if (superIO) {
            for (int i = 0; i < superIO->getNumberOfFans(); i++) {
                superIO->setDefaultFanControl(i);
            }
            delete superIO;
            superIO = nullptr;
        }
        IOLockUnlock(superIOLock);
    } else if (superIO) {
        delete superIO;
        superIO = nullptr;
    }

    if (pciConfigLock) {
        IOSimpleLockFree(pciConfigLock);
        pciConfigLock = nullptr;
    }
    if (smuCmdLock) {
        IOLockFree(smuCmdLock);
        smuCmdLock = nullptr;
    }
    if (superIOLock) {
        IOLockFree(superIOLock);
        superIOLock = nullptr;
    }
    if (rendezvousLock) {
        IOLockFree(rendezvousLock);
        rendezvousLock = nullptr;
    }
    if (controlLock) {
        IOLockFree(controlLock);
        controlLock = nullptr;
    }
    if (workLoop) {
        workLoop->release();
        workLoop = nullptr;
    }

    PMstop();
    IOService::stop(provider);
}

IOReturn AMDRyzenCPUPowerManagement::setPowerState(unsigned long powerStateOrdinal, IOService* provider) {
    if (0 == powerStateOrdinal) {

#pragma mark - Power State Management
        // Going to sleep
        IOLog("AMDRyzenCPUPowerManagement::setPowerState preparing for sleep\n");
        wentToSleep = true;
        stopWorkLoop();
    } else if (1 == powerStateOrdinal && wentToSleep) {
        // Waking up
        IOLog("AMDRyzenCPUPowerManagement::setPowerState preparing for wakeup\n");
        wentToSleep = false;
        if (workLoop) {
            resumeWorkLoop();
        }
    }

    return kIOPMAckImplied;
}

void AMDRyzenCPUPowerManagement::fetchOEMBaseBoardInfo(){
    if (boardInfoValid) return;

#pragma mark - MSR Access (read_msr, write_msr)
    strlcpy(boardVendor, "Unknown Vendor", BASEBOARD_STRING_MAX);
    strlcpy(boardName, "Unknown Platform", BASEBOARD_STRING_MAX);
    
    auto efiRT = EfiRuntimeServices::get();
    // AUDIT F-10: Lilu's ownership contract makes the caller release this
    // instance; fetchOEMBaseBoardInfo is retried from selector 16 whenever
    // boardInfoValid is false, so the missing release leaked per retry.
    if (!efiRT) return;
    uint32_t att = 0;
    uint64_t sizee = BASEBOARD_STRING_MAX;
    uint64_t efistat;
    
    efistat = efiRT->getVariable(OC_OEM_VENDOR_VARIABLE_NAME, &EfiRuntimeServices::LiluVendorGuid,
                                 &att, &sizee, boardVendor);
    
    sizee = BASEBOARD_STRING_MAX;
    uint64_t efistat2 = efiRT->getVariable(OC_OEM_BOARD_VARIABLE_NAME, &EfiRuntimeServices::LiluVendorGuid,
                                  &att, &sizee, boardName);
                                  
    if (efistat == EFI_SUCCESS && efistat2 == EFI_SUCCESS) {
        boardInfoValid = true;
    } else {
        // Fallback: Query IOPlatformExpertDevice properties
        IOPlatformExpert *platform = getPlatform();
        if (platform) {
            bool foundVendor = false;
            bool foundModel = false;
            OSObject *mfgObj = platform->getProperty("manufacturer");
            OSObject *modelObj = platform->getProperty("model");
            
            if (mfgObj) {
                if (OSString *str = OSDynamicCast(OSString, mfgObj)) {
                    strncpy(boardVendor, str->getCStringNoCopy(), BASEBOARD_STRING_MAX - 1);
                    boardVendor[BASEBOARD_STRING_MAX - 1] = '\0';
                    foundVendor = true;
                } else if (OSData *data = OSDynamicCast(OSData, mfgObj)) {
                    size_t len = data->getLength();
                    size_t copyLen = (len < BASEBOARD_STRING_MAX - 1) ? len : (BASEBOARD_STRING_MAX - 1);
                    memcpy(boardVendor, data->getBytesNoCopy(), copyLen);
                    boardVendor[copyLen] = '\0';
                    foundVendor = true;
                }
            }
            
            if (modelObj) {
                if (OSString *str = OSDynamicCast(OSString, modelObj)) {
                    strncpy(boardName, str->getCStringNoCopy(), BASEBOARD_STRING_MAX - 1);
                    boardName[BASEBOARD_STRING_MAX - 1] = '\0';
                    foundModel = true;
                } else if (OSData *data = OSDynamicCast(OSData, modelObj)) {
                    size_t len = data->getLength();
                    size_t copyLen = (len < BASEBOARD_STRING_MAX - 1) ? len : (BASEBOARD_STRING_MAX - 1);
                    memcpy(boardName, data->getBytesNoCopy(), copyLen);
                    boardName[copyLen] = '\0';
                    foundModel = true;
                }
            }
            boardInfoValid = foundVendor && foundModel;
        } else {
            boardInfoValid = false;
        }
    }
    
    IOLog("MB: %s %s (Valid: %d)\n", boardName, boardVendor, boardInfoValid);
}

bool AMDRyzenCPUPowerManagement::read_msr(uint32_t addr, uint64_t *value){
    if (cpuFamily >= 0x19) {

#pragma mark - Frequency & Clock Management
        // Zen 3+ MSR Bounds Checking — block Intel-exclusive MSRs that #GP on AMD.
        // Whitelist: 0xE7 (MPERF), 0xE8 (APERF) — used by this kext for effective freq.
        if (addr == 0xCE                          // IA32_ARCH_CAPABILITIES
            || addr == 0xE2                        // IA32_POWER_CTL (Intel layout)
            || (addr >= 0x198 && addr <= 0x19C)    // IA32_PERF_STATUS / PERF_CTL / UCODE
            || addr == 0x1A0                       // IA32_MISC_ENABLE
            || addr == 0x1AD                       // IA32_ENERGY_PERF_BIAS (Intel EPB)
            || addr == 0x345                       // IA32_PERF_LIMIT_REASONS
            || (addr >= 0x610 && addr <= 0x617)) { // Intel RAPL PL1/PL2/PL3 + status
            IOLog("AMDRyzenCPUPowerManagement::read_msr BLOCKED unsafe Intel MSR 0x%X for Zen 3+\n", addr);
            *value = 0;
            return false;
        }
    }

    uint32_t lo, hi;
    int err = rdmsr_carefully(addr, &lo, &hi);
    
    if(!err) *value = lo | ((uint64_t)hi << 32);
    
    return err == 0;
}

bool AMDRyzenCPUPowerManagement::write_msr(uint32_t addr, uint64_t value){
    if (cpuFamily >= 0x19) {
        // Zen 3+ MSR Bounds Checking — block Intel-exclusive MSRs that #GP on AMD.
        if (addr == 0xCE                          // IA32_ARCH_CAPABILITIES
            || addr == 0xE2                        // IA32_POWER_CTL (Intel layout)
            || (addr >= 0x198 && addr <= 0x19C)    // IA32_PERF_STATUS / PERF_CTL / UCODE
            || addr == 0x1A0                       // IA32_MISC_ENABLE
            || addr == 0x1AD                       // IA32_ENERGY_PERF_BIAS (Intel EPB)
            || addr == 0x345                       // IA32_PERF_LIMIT_REASONS
            || (addr >= 0x610 && addr <= 0x617)) { // Intel RAPL PL1/PL2/PL3 + status
            IOLog("AMDRyzenCPUPowerManagement::write_msr BLOCKED unsafe Intel MSR 0x%X for Zen 3+\n", addr);
            return false;
        }
    }

    if(wrmsr_carefully){
        uint32_t lo = value & 0xffffffff;
        uint32_t hi = value >> 32;
        return (*wrmsr_carefully)(addr, lo, hi) == 0;
    }
    
    IOLog("AMDRyzenCPUPowerManagement::write_msr safe wrapper unavailable for MSR 0x%X\n", addr);
    return false;
}

void AMDRyzenCPUPowerManagement::registerRequest(){
    uint64_t now = getCurrentTimeNs() / 1000000;
    
    estimatedRequestTimeInterval = (now >= timeOfLastMissedRequest) ? (now - timeOfLastMissedRequest) : 0;
    timeOfLastMissedRequest = now;
}

void AMDRyzenCPUPowerManagement::updateClockSpeed(uint8_t physical){
    // AUDIT F-13: guard physical core index on >64 core systems
    if (physical >= CPUInfo::MaxCpus) return;

#pragma mark - Power & EPP Control
    uint64_t msr_value_buf = 0;
    bool err = !read_msr(kMSR_HARDWARE_PSTATE_STATUS, &msr_value_buf);
    if (err) {
        IOLog("AMDRyzenCPUPowerManagement::updateClockSpeed failed to read MSR 0xC0010293\n");
        return;
    }
    
    //Convert register value to clock speed.
    uint32_t eax = (uint32_t)(msr_value_buf & 0xffffffff);
    
    float clock;
    if (cpuFamily >= 0x1A) {
        // Family 1Ah onward (Zen 5) uses 12-bit CpuFid and no CpuDfsId.
        // Frequency is CpuFid * 5 MHz.
        float curCpuFid = (float)(eax & 0xfff);
        clock = curCpuFid * 5.0f;
    } else {
        // MSRC001_0293
        // CurHwPstate [24:22]
        // CurCpuVid [21:14]
        // CurCpuDfsId [13:8]
        // CurCpuFid [7:0]
        float curCpuDfsId = (float)((eax >> 8) & 0x3f);
        float curCpuFid = (float)(eax & 0xff);
        if (curCpuDfsId == 0.0f) {
            static bool loggedUpdateClockDfsZero = false;
            if (!loggedUpdateClockDfsZero) {
                loggedUpdateClockDfsZero = true;
                IOLog("AMDRyzenCPUPowerManagement::updateClockSpeed: curCpuDfsId is zero, clamping clock to 0\n");
            }
            clock = 0.0f;
        } else {
            clock = curCpuFid / curCpuDfsId * 200.0f;
        }
    }
    
//    PStateCur_perCore[physical] = curHwPstate;
    effFreq_perCore[physical] = clock;
    
    //    IOLog("AMDRyzenCPUPowerManagement::updateClockSpeed: %u\n", curHwPstate);
}

void AMDRyzenCPUPowerManagement::calculateEffectiveFrequency(uint8_t physical){
    // AUDIT F-13: guard physical core index on >64 core systems
    if (physical >= CPUInfo::MaxCpus) return;

    uint64_t APERF = 0;
    uint64_t MPERF = 0;
    
    if (!read_msr(kMSR_APERF, &APERF) || !read_msr(kMSR_MPERF, &MPERF)) {
        return;
    }
        
    uint64_t lastAPERF = lastAPERF_perCore[physical];
    uint64_t lastMPERF = lastMPERF_perCore[physical];
    
    lastAPERF_perCore[physical] = APERF;
    lastMPERF_perCore[physical] = MPERF;
    //If an overflow of either the MPERF or APERF register occurs between read of last MPERF and
    //read of last APERF, the effective frequency calculated in is invalid.
    if(APERF <= lastAPERF || MPERF <= lastMPERF) {
//        IOLog("AMDRyzenCPUPowerManagement::calculateEffectiveFrequency: frequency is invalid!!!");
        return;
    }
    
    float freqP0 = PStateDefClock_perCore[0];
    // P0 clock not ready yet (dumpPstate failed / still zero) — skip this sample (audit R-3).
    if (freqP0 <= 0.0f) {
        return;
    }
    
    uint64_t deltaAPERF = APERF - lastAPERF;
    float effFreq = ((float)deltaAPERF / (float)(MPERF - lastMPERF)) * freqP0;
    
    effFreq_perCore[physical] = effFreq;
    

}

void AMDRyzenCPUPowerManagement::updateInstructionDelta(uint8_t cpu_num){
    // AUDIT F-13: guard logical CPU index on >64 CPU systems
    if (cpu_num >= CPUInfo::MaxCpus) return;

    uint64_t insCount;
    
    if(!read_msr(kMSR_PERF_IRPC, &insCount)) {
        return;
    }
    
    
    //Skip if overflowed
    if(lastInstructionDelta_perCore[cpu_num] > insCount) return;
    
//    uint64_t delta = insCount - lastInstructionDelta_perCore[cpu_num];
    instructionDelta_perCore[cpu_num] = insCount - lastInstructionDelta_perCore[cpu_num];
    
    lastInstructionDelta_perCore[cpu_num] = insCount;
    
    //write_msr(kMSR_PERF_IRPC, 0);
    
    
    //Calculate load index
//    float estimatedInstRet = (effFreq_perCore[cpu_num] * 1000000);
//    estimatedInstRet = estimatedInstRet * (actualUpdateTimeInterval * 0.001);
//    float index = (float)delta / estimatedInstRet;
//
//    float growth = 3200;
//    loadIndex_PerCore[cpu_num] = log10f(min(index,1) * growth) / log10f(growth);
}

void AMDRyzenCPUPowerManagement::applyPowerControl(){
    // Legacy P-state writes are controlled per CPU profile.

#pragma mark - SMU Mailbox Commands
    // Enabled on Zen 1/2 (full PM dispatch), disabled on Zen 3+ (telemetry-only).
    if (!legacyPstateAllowed) {
        if (cppcActiveMode) {
            IOLog("AMDRyzenCPUPowerManagement::applyPowerControl ignored - CPPC Active Mode active\n");
        } else {
            IOLog("AMDRyzenCPUPowerManagement::applyPowerControl ignored - legacy P-state disabled for this profile\n");
        }
        return;
    }
    
    IOLockLock(rendezvousLock);
    mp_rendezvous(nullptr, [](void *obj) {
        auto provider = static_cast<AMDRyzenCPUPowerManagement*>(obj);
        provider->write_msr(kMSR_PSTATE_CTL, (uint64_t)(provider->PStateCtl & 0x7));
    }, nullptr, this);
    IOLockUnlock(rendezvousLock);
}

void AMDRyzenCPUPowerManagement::applyEPPControl() {
    // CPPC writes (ENABLE/REQ MSRs) are disabled in the current baseline.
    // This function is a no-op until validated CPPC write support is added
    // via a per-profile capability flag.
    IOLog("AMDRyzenCPUPowerManagement::applyEPPControl ignored - CPPC writes disabled in baseline\n");
    return;
}

void AMDRyzenCPUPowerManagement::setCPBState(bool enabled){
    if(!cpbSupported) return;
    
    uint64_t hwConfig;
    if(!read_msr(kMSR_HWCR, &hwConfig)) {
        IOLog("AMDRyzenCPUPowerManagement::setCPBState failed to read MSR 0xC0010015\n");
        return;
    }
    
    if(enabled){
        hwConfig &= ~(1 << 25);
    } else {
        hwConfig |= (1 << 25);
    }
    
    struct CPBArgs {
        AMDRyzenCPUPowerManagement *provider;
        uint64_t hwConfig;
    } cpbArgs{this, hwConfig};

    IOLockLock(rendezvousLock);
    mp_rendezvous(nullptr, [](void *obj) {
        auto args = static_cast<CPBArgs*>(obj);
        args->provider->write_msr(kMSR_HWCR, args->hwConfig);
    }, nullptr, &cpbArgs);
    IOLockUnlock(rendezvousLock);
}

bool AMDRyzenCPUPowerManagement::getCPBState(){
    uint64_t hwConfig;
    if(!read_msr(kMSR_HWCR, &hwConfig)) {
        IOLog("AMDRyzenCPUPowerManagement::getCPBState failed to read MSR 0xC0010015\n");
        return false;
    }
    
    return !((hwConfig >> 25) & 0x1);
}

// S10 KRN-04: returns kTEMP_INVALID (not 0.0f) when the reading cannot be
// trusted. 0.0f was ambiguous with a genuine 0 C, and 0 C is the single most
// dangerous value in this driver: it selects lut[0] (slowest duty) and makes
// every ">= 85 C" guard test false. Callers must use isTempValid(), not "> 0".
inline float AMDRyzenCPUPowerManagement::getPackageTemp() {
    if (!fIOPCIDevice || !pciConfigLock) return kTEMP_INVALID;
    IOPCIAddressSpace space;
    space.bits = 0x00;
    
    uint8_t smnCtrlReg = (cpuFamily == 0x1A) ? kFAMILY_1AH_PCI_CONTROL_REGISTER
                                             : kFAMILY_17H_PCI_CONTROL_REGISTER;
    IOSimpleLockLock(pciConfigLock);
    fIOPCIDevice->configWrite32(space, smnCtrlReg, (UInt32)kF17H_M01H_THM_TCON_CUR_TMP);
    uint32_t temperature = fIOPCIDevice->configRead32(space, smnCtrlReg + 4);
    IOSimpleLockUnlock(pciConfigLock);
    
    // Temperature offset 49C is controlled per CPU profile via temperatureOffset49.
    // The hardware flag bit (0x80000) is checked only when the profile allows it.
    // Zen 4 has temperatureOffset49=true (verified). Zen 5 is false pending PPR validation.
    bool tempOffsetFlag = temperatureOffset49
                          ? ((temperature & kF17H_TEMP_OFFSET_FLAG) != 0)
                          : false;
    temperature = (temperature >> 21) * 125;
    
    float t = temperature * 0.001f;
    
    t -= tempOffset;
    
    if (tempOffsetFlag)
        t -= 49.0f;
    
    // Reject NaN, infinities and anything outside the plausible Zen window.
    if (!(t == t) || t < -20.0f || t > 135.0f) {
        return kTEMP_INVALID;
    }

    return t;
}

uint32_t AMDRyzenCPUPowerManagement::readCCDRegisterRaw(uint8_t ccd) {
    if (ccd >= kMAX_CCD_COUNT || !fIOPCIDevice || !pciConfigLock) return 0;
    IOPCIAddressSpace space;
    space.bits = 0x00;
    uint32_t ccdRegAddr = kF17H_M01H_THM_TCON_CUR_TMP + ccdOffset + (ccd * 4);
    
    IOSimpleLockLock(pciConfigLock);
    fIOPCIDevice->configWrite32(space, (UInt8)kFAMILY_17H_PCI_CONTROL_REGISTER, (UInt32)ccdRegAddr);
    uint32_t regVal = fIOPCIDevice->configRead32(space, kFAMILY_17H_PCI_CONTROL_REGISTER + 4);
    IOSimpleLockUnlock(pciConfigLock);
    
    return regVal;
}

float AMDRyzenCPUPowerManagement::getCCDTemp(uint8_t ccd) {
    if (ccd >= kMAX_CCD_COUNT) return 0.0f;
    
    uint32_t regVal = readCCDRegisterRaw(ccd);
    
    // Check CCD valid bit (bit 11) — if not set, CCD is not present
    if (!(regVal & kZEN_CCD_TEMP_VALID_BIT)) return 0.0f;
    
    // Temperature formula from Linux k10temp:
    // temp = (regVal & 0x7FF) * 125 - 49000 (in millidegrees)
    // We convert to float degrees Celsius:
    float temp = (float)(regVal & kZEN_CCD_TEMP_MASK) * 0.125f - 49.0f;
    return temp;
}

uint32_t AMDRyzenCPUPowerManagement::smnRead32(uint32_t addr) {
    if (!fIOPCIDevice || !pciConfigLock) return 0;

#pragma mark - SMN Access (smnRead32, smnWrite32)
    IOPCIAddressSpace space;
    space.bits = 0x00;
    
    IOSimpleLockLock(pciConfigLock);
    fIOPCIDevice->configWrite32(space, (UInt8)kFAMILY_17H_PCI_CONTROL_REGISTER, (UInt32)addr);
    uint32_t val = fIOPCIDevice->configRead32(space, kFAMILY_17H_PCI_CONTROL_REGISTER + 4);
    IOSimpleLockUnlock(pciConfigLock);
    return val;
}

void AMDRyzenCPUPowerManagement::smnWrite32(uint32_t addr, uint32_t val) {
    if (!fIOPCIDevice || !pciConfigLock) return;
    IOPCIAddressSpace space;
    space.bits = 0x00;
    
    IOSimpleLockLock(pciConfigLock);
    fIOPCIDevice->configWrite32(space, (UInt8)kFAMILY_17H_PCI_CONTROL_REGISTER, (UInt32)addr);
    fIOPCIDevice->configWrite32(space, kFAMILY_17H_PCI_CONTROL_REGISTER + 4, (UInt32)val);
    IOSimpleLockUnlock(pciConfigLock);
}

int AMDRyzenCPUPowerManagement::smuSendCmd(uint32_t cmd, uint32_t arg) {
    uint32_t unused = 0;
    return smuSendCmd(cmd, arg, unused);
}

// S5: full-mailbox variant — after SMU_RSP_OK the read command's result word
// is left in the mailbox ARG register (reference driver reads it back from
// args_addr + 0 post-OK), so snapshot it inside the same critical section.
int AMDRyzenCPUPowerManagement::smuSendCmd(uint32_t cmd, uint32_t arg, uint32_t &outArg0, uint32_t *outElapsedUs) {
    if (outElapsedUs) *outElapsedUs = 0;
    if (!smuMailbox.supported) return SMU_RSP_INVALID_CMD;

#pragma mark - Thermal & Energy Monitoring
    uint32_t msgReg = smuMailbox.msgReg;
    uint32_t argReg = smuMailbox.argReg;
    uint32_t rspReg = smuMailbox.rspReg;
    
    // Serialize the full SMU mailbox sequence (clear → arg → msg → poll).
    // Individual smnRead/Write use pciConfigLock, but that alone does not protect
    // the multi-step protocol against concurrent UserClient callers (audit R-8).
    if (smuCmdLock) {
        IOLockLock(smuCmdLock);
    }
    
    // Step 1: Pre-flight probe — wait until RSP register is non-zero (mailbox ready)
    uint32_t preRsp = 0;
    uint32_t preElapsed = 0;
    while (preElapsed < 2000) {
        preRsp = smnRead32(rspReg);
        if (preRsp != 0) break;
        IODelay(10);
        preElapsed += 10;
    }

    uint32_t argRes = arg;
    
    // Step 2: Clear response register first
    smnWrite32(rspReg, 0);
    
    // Step 3: Write argument
    smnWrite32(argReg, arg);
    
    // Step 4: Send command
    smnWrite32(msgReg, cmd);
    
    // Memory barrier: ensure the SMU sees the command write before we start
    // polling the response register. Without this, write-combining buffers on
    // the SMN bus can delay command delivery, causing the poll to read a stale
    // zero and falsely trigger the timeout reset path.
    __asm__ volatile("mfence" ::: "memory");
    
    // Step 5: Wait for response. Curve Optimizer triggers PLL reconfiguration; PM table transfer DMA takes time.
    const uint32_t timeoutUs = (cmd == smuMailbox.curveOptimizerCmd || cmd == 0x05) ? 25000 : 10000;
    uint32_t rsp = 0;
    uint32_t elapsed = 0;
    while (elapsed < timeoutUs) {
        rsp = smnRead32(rspReg);
        if (rsp != 0) break;
        uint32_t step = (elapsed < 100) ? 5 : 20;
        IODelay(step);
        elapsed += step;
    }
    
    if (outElapsedUs) {
        *outElapsedUs = elapsed;
    }

    if (rsp == SMU_RSP_OK) {
        argRes = smnRead32(argReg);
    }

    if (smuCmdLock) {
        IOLockUnlock(smuCmdLock);
    }
    
    outArg0 = argRes;
    return (int)rsp;
}

// S5: one RSMU read command (no arg in). Returns the raw mailbox result word
// on OK, else 0. Never called from user threads — timer command gate only.
uint32_t AMDRyzenCPUPowerManagement::pollSmuRead(uint32_t smuCmd) {
    uint32_t result = 0;
    int rsp = smuSendCmd(smuCmd, 0, result);
    return (rsp == SMU_RSP_OK) ? result : 0;
}

// S9a: two-argument mailbox command returning both arg-window words after
// SMU_RSP_OK. Needed for Vermeer GetDramBaseAddress (0x06), which the
// reference driver calls with Arg0=1/Arg1=1 and reads the 64-bit physical
// base back as arg0 | (arg1 << 32) (smu.c smu_get_dram_base_address,
// BASE_ADDR_CLASS_1). Same protocol/locking as smuSendCmd: serialized under
// smuCmdLock (leaf lock), response register cleared first, bounded poll.
// Timer command gate only (F-05).
int AMDRyzenCPUPowerManagement::smuSendCmd2(uint32_t cmd, uint32_t arg0, uint32_t arg1,
                                            uint32_t &outArg0, uint32_t &outArg1, uint32_t *outElapsedUs) {
    outArg0 = 0;
    outArg1 = 0;
    if (outElapsedUs) *outElapsedUs = 0;
    if (!smuMailbox.supported) return SMU_RSP_INVALID_CMD;

    uint32_t msgReg = smuMailbox.msgReg;
    uint32_t argReg = smuMailbox.argReg;
    uint32_t rspReg = smuMailbox.rspReg;

    if (smuCmdLock) {
        IOLockLock(smuCmdLock);
    }

    // Step 1: Pre-flight probe
    uint32_t preRsp = 0;
    uint32_t preElapsed = 0;
    while (preElapsed < 2000) {
        preRsp = smnRead32(rspReg);
        if (preRsp != 0) break;
        IODelay(10);
        preElapsed += 10;
    }

    // Step 2: Clear response register first
    smnWrite32(rspReg, 0);

    // Step 3: Write both arguments (second word at argReg+4, same layout the
    // reference driver uses for its 6-word arg window).
    smnWrite32(argReg, arg0);
    smnWrite32(argReg + 4, arg1);

    // Step 4: Send command
    smnWrite32(msgReg, cmd);
    __asm__ volatile("mfence" ::: "memory");

    const uint32_t timeoutUs = 10000;
    uint32_t rsp = 0;
    uint32_t elapsed = 0;
    while (elapsed < timeoutUs) {
        rsp = smnRead32(rspReg);
        if (rsp != 0) break;
        uint32_t step = (elapsed < 100) ? 5 : 20;
        IODelay(step);
        elapsed += step;
    }

    if (outElapsedUs) {
        *outElapsedUs = elapsed;
    }

    if (rsp == SMU_RSP_OK) {
        outArg0 = smnRead32(argReg);
        outArg1 = smnRead32(argReg + 4);
    }

    if (smuCmdLock) {
        IOLockUnlock(smuCmdLock);
    }

    return (int)rsp;
}

void AMDRyzenCPUPowerManagement::pollBoostTelemetry() {
    if (!smuMailbox.supported) return;
    
    uint64_t now = getCurrentTimeNs() / 1000000; // ms
    if (smuBoostTelemetryLastPollMs != 0 &&
        now - smuBoostTelemetryLastPollMs < kSMU_BOOST_POLL_MIN_INTERVAL_MS) {
        return;
    }
    smuBoostTelemetryLastPollMs = now;
    
    // Vermeer RSMU read commands documented in ryzen_smu rsmu_commands.md:
    //   GetMaxFrequency        0x6E  Res0: MHz
    //   GetFastestCoreOfSocket 0x59  raw word; decode lives app-side
    //   GetPBOScalar           0x6C  active scalar (IEEE-754 float)
    // 0 responses are cached as "unknown" rather than retried every tick —
    // the SMU only returns 0 while clocks are being reconfigured.
    uint32_t maxFreq = 0;
    uint32_t fastestCore = 0;
    uint32_t activeScalar = 0;
    uint32_t elap6E = 0, elap59 = 0, elap6C = 0;

    int rsp6E = smuSendCmd(0x6E, 0, maxFreq, &elap6E);
    int rsp59 = smuSendCmd(0x59, 0, fastestCore, &elap59);
    int rsp6C = smuSendCmd(0x6C, 0, activeScalar, &elap6C);

    if (rsp6E == SMU_RSP_OK) smuMaxBoostFreqMHz = maxFreq;
    if (rsp59 == SMU_RSP_OK) smuFastestCoreRaw = fastestCore;
    if (rsp6C == SMU_RSP_OK) smuActiveScalarRaw = activeScalar;

    static bool sLoggedBoostFirst = false;
    if (!sLoggedBoostFirst) {
        IOLog("AMDRyzenCPUPowerManagement: Boost telemetry initial: 0x6E(rsp=0x%X, %u MHz, %u us), 0x59(rsp=0x%X, 0x%X, %u us), 0x6C(rsp=0x%X, 0x%X, %u us)\n",
              rsp6E, smuMaxBoostFreqMHz, elap6E, rsp59, smuFastestCoreRaw, elap59, rsp6C, smuActiveScalarRaw, elap6C);
        sLoggedBoostFirst = true;
    }
}

// S7: one-shot SMU firmware version read (global TestMessage-family command
// 0x02, per ryzen_smu: "OP 0x02 is consistent with all platforms"). Static —
// on the first SMU_RSP_OK the result is cached and never re-issued this
// boot. Response is the raw byte-packed version word; decode in
// AMDSmuReadback app-side. Timer command gate only (F-05 lesson).
uint32_t AMDRyzenCPUPowerManagement::pollSmuVersion() {
    if (!smuMailbox.supported) return 0;
    if (smuVersionPolled) return smuFirmwareVersionRaw;
    
    uint32_t result = 0;
    uint32_t elapsed = 0;
    int rsp = smuSendCmd(0x02, 1, result, &elapsed);
    if (rsp == SMU_RSP_OK) {
        smuFirmwareVersionRaw = result;
        smuVersionPolled = true;
        IOLog("AMDRyzenCPUPowerManagement: SMU firmware version word 0x%08X (elapsed %u us).\n", result, elapsed);
    } else {
        static bool sLoggedVerFail = false;
        if (!sLoggedVerFail) {
            IOLog("AMDRyzenCPUPowerManagement: pollSmuVersion (0x02) failed: rsp=0x%X, elapsed=%u us\n", rsp, elapsed);
            sLoggedVerFail = true;
        }
    }
    return smuFirmwareVersionRaw;
}

// S7: one-shot SMU PBO scalar read (Vermeer RSMU 0x6C, per ryzen_smu
// monitor_cpu.c: response is an IEEE-754 float in the 1.0–10.0 range —
// different encoding than the 0x58 write). Complements the 0x58 write cache
// with the SMU's actual active scalar. Timer command gate only (F-05).
uint32_t AMDRyzenCPUPowerManagement::pollSmuPBOScalar() {
    if (!smuMailbox.supported) return 0;
    
    uint32_t result = 0;
    int rsp = smuSendCmd(0x6C, 0, result);
    return (rsp == SMU_RSP_OK) ? result : 0;
}

// ------------------------------------------------------------------
// S9a: SMU PM-table plumbing (Vermeer RSMU 0x08 / 0x05 / 0x06).
//
// The SMU exposes a live metrics table (per-core clocks/temps/power —
// the same table ryzen_smu and HWiNFO feed from). The flow, pinned from
// the reference driver (smu.c):
//   0x08 GetPMTableVersion → response word, BCD-style (e.g. 0x380904)
//   table size             → per-version table sourced from Ryzen Master
//                            (Vermeer: 0x594 … 0x1BB0 bytes; unknown
//                            versions fail closed)
//   0x05 TransferTableSmu2Dram (Arg0 = 0) → SMU copies the table to DRAM
//   0x06 GetDramBaseAddress (Arg0=1, Arg1=1) → 64-bit physical base
//                            assembled as arg0 | (arg1 << 32)
// The kext maps the region READ-ONLY, copies it into a fixed snapshot
// buffer, and unmaps immediately; user space (selector 57) reads the
// snapshot only. Nothing in this path writes to SMU-controlled memory.
// Runs exclusively on the timer command gate (F-05).
// ------------------------------------------------------------------

// Documented Vermeer/Chagall PM-table sizes (Ryzen-Master-sourced list,
// reference smu.c smu_update_pmtablesize). Unknown versions → 0 (fail
// closed; the snapshot stays invalid rather than mapping a guessed size).
static uint32_t pmTableSizeForVersion(uint32_t version) {
    switch (version) {
    case 0x2D0803: return 0x0894;
    case 0x2D0903: return 0x0594;
    case 0x380005: return 0x1BB0;
    case 0x380505: return 0x0F30;
    case 0x380605: return 0x0C10;
    case 0x380705: return 0x08F0;
    case 0x380804: return 0x08A4;
    case 0x380805: return 0x08F0;
    case 0x380904: return 0x05A4;
    case 0x380905: return 0x05D0;
    default:       return 0;    // unknown version — fail closed
    }
}

// One capture cycle: (re-map if needed) 0x05 → 0x06 → map → copy → unmap.
// Returns 0 on success, else a mapped negative (-1 unsupported, -5 SMU
// error, -10 timeout, -11 invalid cmd, -12 invalid args, -13 busy, -14
// unknown table version, -15 map failed).
int AMDRyzenCPUPowerManagement::forcePMTableCapture() {
    if (!pboLimitsSupported()) {
        static bool sLoggedNotSupp = false;
        if (!sLoggedNotSupp) {
            IOLog("AMDRyzenCPUPowerManagement: forcePMTableCapture aborted: pboLimitsSupported() returned false.\n");
            sLoggedNotSupp = true;
        }
        return -1;
    }

    // 0x08: version (one-shot — static per firmware)
    if (!pmTableVersionPolled) {
        uint32_t versionWord = 0;
        uint32_t elap08 = 0;
        int rsp = smuSendCmd(0x08, 0, versionWord, &elap08);
        if (rsp != SMU_RSP_OK) {
            static bool sLogged08Fail = false;
            if (!sLogged08Fail) {
                IOLog("AMDRyzenCPUPowerManagement: PM table 0x08 (GetPMTableVersion) failed: rsp=0x%X, elapsed=%u us\n", rsp, elap08);
                sLogged08Fail = true;
            }
            return (rsp == SMU_RSP_TIMEOUT) ? -10 :
                   (rsp == SMU_RSP_INVALID_CMD) ? -11 :
                   (rsp == SMU_RSP_INVALID_ARGS) ? -12 :
                   (rsp == SMU_RSP_BUSY) ? -13 : -5;
        }
        pmTableVersionRaw = versionWord;
        pmTableVersionPolled = true;
        IOLog("AMDRyzenCPUPowerManagement: PM table version 0x%08X (BCD %u.%u.%u, elapsed %u us).\n",
              versionWord, (versionWord >> 16) & 0xFF, (versionWord >> 8) & 0xFF, versionWord & 0xFF, elap08);
    }

    // Size lookup — unknown versions fail closed.
    uint32_t size = pmTableSizeForVersion(pmTableVersionRaw);
    if (size == 0 || size > kPM_TABLE_MAX_SIZE) {
        static bool sLoggedSzFail = false;
        if (!sLoggedSzFail) {
            IOLog("AMDRyzenCPUPowerManagement: PM table version 0x%08X unsupported or unknown size %u (fail closed)\n",
                  pmTableVersionRaw, size);
            sLoggedSzFail = true;
        }
        return -14;
    }
    pmTableSize = size;

    // 0x05: ask the SMU to copy the live table into DRAM (Arg0 = 0: main
    // CPU table; for CPUs the argument is ignored per the reference).
    {
        uint32_t arg0 = 0;
        uint32_t elap05 = 0;
        int rsp = smuSendCmd(0x05, 0, arg0, &elap05);
        if (rsp != SMU_RSP_OK) {
            static bool sLogged05Fail = false;
            if (!sLogged05Fail) {
                IOLog("AMDRyzenCPUPowerManagement: PM table 0x05 (TransferTableSmu2Dram) failed: rsp=0x%X, elapsed=%u us\n", rsp, elap05);
                sLogged05Fail = true;
            }
            return (rsp == SMU_RSP_TIMEOUT) ? -10 :
                   (rsp == SMU_RSP_INVALID_CMD) ? -11 :
                   (rsp == SMU_RSP_INVALID_ARGS) ? -12 :
                   (rsp == SMU_RSP_BUSY) ? -13 : -5;
        }
    }

    // 0x06: 64-bit physical base (Arg0=1/Arg1=1 in, arg0|arg1<<32 out).
    {
        uint32_t lo = 0, hi = 0;
        uint32_t elap06 = 0;
        int rsp = smuSendCmd2(0x06, 1, 1, lo, hi, &elap06);
        if (rsp != SMU_RSP_OK) {
            static bool sLogged06Fail = false;
            if (!sLogged06Fail) {
                IOLog("AMDRyzenCPUPowerManagement: PM table 0x06 (GetDramBaseAddress) failed: rsp=0x%X, elapsed=%u us\n", rsp, elap06);
                sLogged06Fail = true;
            }
            return (rsp == SMU_RSP_TIMEOUT) ? -10 :
                   (rsp == SMU_RSP_INVALID_CMD) ? -11 :
                   (rsp == SMU_RSP_INVALID_ARGS) ? -12 :
                   (rsp == SMU_RSP_BUSY) ? -13 : -5;
        }
        uint64_t base = (uint64_t)lo | ((uint64_t)hi << 32);
        if (base == 0) {
            IOLog("AMDRyzenCPUPowerManagement: PM table 0x06 returned base=0\n");
            return -15;
        }
        if (pmDramBase == 0 || pmDramBase != base) {
            IOLog("AMDRyzenCPUPowerManagement: PM table physical DRAM base 0x%llx (lo=0x%X, hi=0x%X, elapsed %u us).\n",
                  (unsigned long long)base, lo, hi, elap06);
        }
        pmDramBase = base;
    }

    // Map READ-ONLY, copy into the snapshot, unmap immediately. Nothing
    // persistent is created: the base address can change across firmware
    // events, so every capture creates a fresh short-lived kernel mapping
    // of exactly pmTableSize bytes at the SMU-provided physical address.
    {
        IOMemoryDescriptor *md =
            IOMemoryDescriptor::withPhysicalAddress(
                (IOPhysicalAddress)pmDramBase, (IOByteCount)pmTableSize,
                kIODirectionIn);
        if (!md) {
            IOLog("AMDRyzenCPUPowerManagement: PM table IOMemoryDescriptor creation failed (base 0x%llx, %u bytes).\n",
                  (unsigned long long)pmDramBase, pmTableSize);
            return -15;
        }
        IOMemoryMap *map = md->createMappingInTask(kernel_task, 0,
                                                   kIOMapAnywhere | kIOMapInhibitCache | kIOMapReadOnly,
                                                   0, pmTableSize);
        if (!map) {
            IOLog("AMDRyzenCPUPowerManagement: PM table mapping failed (base 0x%llx, %u bytes).\n",
                  (unsigned long long)pmDramBase, pmTableSize);
            md->release();
            return -15;
        }
        memcpy(pmTableSnapshot, (const void *)map->getVirtualAddress(), pmTableSize);
        map->release();
        md->release();
    }

    pmTableCapturedMs = getCurrentTimeNs() / 1000000;
    if (!pmMapValid) {
        IOLog("AMDRyzenCPUPowerManagement: PM table snapshot capture active (%u bytes from physical 0x%llx, version 0x%08X).\n",
              pmTableSize, (unsigned long long)pmDramBase, pmTableVersionRaw);
    }
    pmMapValid = true;
    return 0;
}

// S9a: main-timer refresh (F-05 — timer command gate only), throttled to
// one 0x05 + capture per second. Re-runs the full cycle every time (the
// reference re-issues 0x05 per read; bases can migrate across firmware
// events), so a changed base address is picked up within a second.
// Failures keep the previous snapshot and stay diagnostic — this path
// must never disturb the PBO/CO/OC command flow (it shares smuCmdLock,
// which stays a leaf).
void AMDRyzenCPUPowerManagement::pollPMTable() {
    if (!pboLimitsSupported()) return;

    uint64_t now = getCurrentTimeNs() / 1000000; // ms
    if (pmRefreshLastPollMs != 0 &&
        now - pmRefreshLastPollMs < kPM_REFRESH_MIN_INTERVAL_MS) {
        return;
    }
    pmRefreshLastPollMs = now;

    (void)forcePMTableCapture();
}

// S6: one-shot ProcessorParameters read (Vermeer RSMU 0x6F, per ryzen_smu
// rsmu_commands.md — Res0 bitfield, no input arg). Static silicon config:
// on the first SMU_RSP_OK the result is cached and the command is never
// re-issued this boot. Runs on the timer command gate only (F-05 lesson).
uint32_t AMDRyzenCPUPowerManagement::pollProcessorParameters() {
    if (!smuMailbox.supported) return 0;
    if (smuProcParamsPolled) return smuProcessorParametersRaw;
    
    uint32_t result = 0;
    uint32_t elapsed = 0;
    int rsp = smuSendCmd(0x6F, 0, result, &elapsed);
    if (rsp == SMU_RSP_OK) {
        smuProcessorParametersRaw = result;
        smuProcParamsPolled = true;
        IOLog("AMDRyzenCPUPowerManagement: ProcessorParameters (0x6F) = 0x%X (bit0 overclockable, bit1 PBO, elapsed %u us).\n", result, elapsed);
    } else {
        static bool sLoggedProcFail = false;
        if (!sLoggedProcFail) {
            IOLog("AMDRyzenCPUPowerManagement: pollProcessorParameters (0x6F) failed: rsp=0x%X, elapsed=%u us\n", rsp, elapsed);
            sLoggedProcFail = true;
        }
    }
    return smuProcessorParametersRaw;
}

// S9d: on-demand mailbox health report (UserClient selector 58). Same three
// probes as the boot diagnostic, but callable from the app any time — every
// raw code is returned so the app can render the report without log show.
// The caller (UserClient) holds rendezvousLock across the whole run, matching
// the selector-57-op-2 capture convention; smuSendCmd's smuCmdLock stays the
// inner leaf. Read-only: never writes mailbox-visible state beyond the two
// probe commands themselves.
bool AMDRyzenCPUPowerManagement::runMailboxDiagnostics(SMUDiagnosticReport &out)
{
    out = {};
    out.mailboxSupported = smuMailbox.supported ? 1 : 0;
    out.msgReg = smuMailbox.msgReg;
    out.argReg = smuMailbox.argReg;
    out.rspReg = smuMailbox.rspReg;
    out.curveOptimizerCmd = smuMailbox.curveOptimizerCmd;
    if (!smuMailbox.supported) return false;

    // Probe 1 — SMN aperture: Tctl raw word through the PCI 0x60/0x64
    // window. A constant 0xFFFFFFFF here means the aperture itself is
    // broken (PCI config routing), independent of the mailbox.
    out.smnTctlRaw = smnRead32(kF17H_M01H_THM_TCON_CUR_TMP);

    // Probe 2 — TestMessage round-trip: documented semantics are
    // Res0 = Arg0 + 1, so arg 0x42 must come back as 0x43. Proves the full
    // write-command-poll cycle plus SMU firmware liveness.
    uint32_t testResult = 0;
    uint32_t testElapsedUs = 0;
    out.testRsp = smuSendCmd(0x01, 0x42, testResult, &testElapsedUs);
    out.testArg0 = testResult;
    out.testElapsedUs = testElapsedUs;

    // Probe 3 — GetSMUVersion (0x02, Arg0 = 1): the BCD version word.
    uint32_t verResult = 0;
    uint32_t verElapsedUs = 0;
    out.versionRsp = smuSendCmd(0x02, 1, verResult, &verElapsedUs);
    out.versionRaw = verResult;
    out.versionElapsedUs = verElapsedUs;

    IOLog("AMDRyzenCPUPowerManagement: [SMU Diagnostic] run: tctl=0x%08X, TestMessage rsp=0x%X arg0=0x%X (%u us), GetSMUVersion rsp=0x%X raw=0x%08X (%u us)\n",
          out.smnTctlRaw, out.testRsp, out.testArg0, out.testElapsedUs,
          out.versionRsp, out.versionRaw, out.versionElapsedUs);

    return (out.testRsp == SMU_RSP_OK && out.testArg0 == 0x43);
}

// S8: enable/disable Vermeer OC mode (RSMU 0x5A EnableOcMode / 0x5B
// DisableOcMode). Semantics pinned during S8 research: amkillam/ryzen_smu
// rsmu_commands.md lists the pair, and irusanov/ZenStates-Core (Rsmu.
// SMU_MSG_EnableOcMode = 0x5A / SMU_MSG_DisableOcMode = 0x5B, SetOcMode.cs)
// resolves the doc's contradictory arg rows. Arg 1 enables, 0 disables.
// Same capability gate and thermal interlock as every other SMU write path.
// Disable quirk (pinned from ZenStates-Core SetOcMode.cs): some SMU firmware
// versions do not auto-reset the PBO scalar when leaving OC mode — when
// `resetScalar` is set, re-program the scalar to 1.0 (100 in %×100) via the
// proven 0x58 write path after a successful disable.
int AMDRyzenCPUPowerManagement::setOcMode(bool enable, bool resetScalar) {
    if (!pboLimitsSupported()) return -1;
    
    // Thermal safety interlock, same policy as CO/PBO/cHTC: no new OC-mode
    // transitions while the package is already hot.
    float currentTemp = PACKAGE_TEMPERATURE_perPackage[0];
    if (currentTemp > kCURVE_OPTIMIZER_BLOCK_TEMP_C) {
        IOLog("AMDRyzenCPUPowerManagement: Blocked OC mode %s (0x%X) due to high package temperature (%.1f C).\n",
              enable ? "enable" : "disable", enable ? 0x5A : 0x5B, currentTemp);
        return -4;
    }
    
    int response = smuSendCmd(enable ? 0x5A : 0x5B, enable ? 1 : 0);
    
    if (response == SMU_RSP_OK) {
        smuOcModeState = enable ? 1 : 2;
        IOLog("AMDRyzenCPUPowerManagement: OC mode %s (0x%X).\n", enable ? "ENABLED" : "DISABLED", enable ? 0x5A : 0x5B);
        
        if (!enable && resetScalar) {
            // Pass the real cache slot: setPBOLimit updates it on success.
            int scalarRc = setPBOLimit(0x58, 100, pboScalarPercentX100);
            IOLog("AMDRyzenCPUPowerManagement: OC disable scalar reset (0x58 → 100): %s.\n",
                  scalarRc == 0 ? "ok" : "failed");
        }
        return 0;
    }
    
    IOLog("AMDRyzenCPUPowerManagement: SMU OC mode command 0x%X failed with response code: 0x%X\n",
          enable ? 0x5A : 0x5B, response);
    if (response == SMU_RSP_TIMEOUT) return -10;
    if (response == SMU_RSP_INVALID_CMD) return -11;
    if (response == SMU_RSP_INVALID_ARGS) return -12;
    if (response == SMU_RSP_BUSY) return -13;
    return -5;
}

// ------------------------------------------------------------------
// S8.2: frequency overrides (Vermeer RSMU 0x5C all-core / 0x5D per-CCD).
//
// PINNED semantics (S_SERIES_ROADMAP.md §1, sources D+ZC):
//   0x5C SetOverclockFreqAllCores: Arg0 = freq & 0xFFFFF (absolute MHz,
//        doc MAX 8000).
//   0x5D SetOverclockFreqPerCore:  Arg0 = (freq & 0xFFFFF) | coreMask with
//        Vermeer coreMask = (ccd << 28) | ((core % 8) << 20). Vermeer has
//        one CCX per CCD and all cores of a CCX must share one frequency
//        (CCX-uniformity rule, both sources) — so the effective granularity
//        IS the CCD and core = ccd*8 makes (core % 8) == 0: the mask
//        collapses to (ccd << 28) | freq.
// Both are write-only SMU commands: there is no read-back, so the caches
// describe THIS driver's last successful writes only.
//
// Fail-closed: Vermeer-with-mailbox gate, OC-mode gate (this driver must
// have enabled OC mode via 0x5A earlier this boot — another tool's enable
// does not count), and the same thermal interlock as every write path.
// ------------------------------------------------------------------

int AMDRyzenCPUPowerManagement::setOverclockFreqAllCores(uint32_t mhz) {
    if (!pboLimitsSupported()) return -1;
    
    if (mhz < 400 || mhz > 8000) {
        IOLog("AMDRyzenCPUPowerManagement: Freq override %u MHz outside the 400..8000 envelope. Blocking.\n", mhz);
        return -2;
    }
    
    // OC-mode gate: we only send 0x5C/0x5D after observing the gate open
    // ourselves (0x5A succeeded this boot). Maps to kIOReturnNotPermitted.
    if (smuOcModeState != 1) {
        IOLog("AMDRyzenCPUPowerManagement: Blocked freq override (0x5C): OC mode not enabled by this driver this boot.\n");
        return -3;
    }
    
    // Thermal safety interlock, same policy as CO/PBO/cHTC/OC-mode.
    float currentTemp = PACKAGE_TEMPERATURE_perPackage[0];
    if (currentTemp > kCURVE_OPTIMIZER_BLOCK_TEMP_C) {
        IOLog("AMDRyzenCPUPowerManagement: Blocked freq override (0x5C) due to high package temperature (%.1f C).\n", currentTemp);
        return -4;
    }
    
    uint32_t arg = mhz & 0xFFFFF;   // 0x5C: absolute MHz in the low 20 bits
    int response = smuSendCmd(0x5C, arg);
    
    if (response == SMU_RSP_OK) {
        ocFreqMHzAllCores = mhz;
        IOLog("AMDRyzenCPUPowerManagement: All-core freq override applied (0x5C, %u MHz).\n", mhz);
        return 0;
    }
    
    IOLog("AMDRyzenCPUPowerManagement: SMU 0x5C failed with response code: 0x%X\n", response);
    if (response == SMU_RSP_TIMEOUT) return -10;
    if (response == SMU_RSP_INVALID_CMD) return -11;
    if (response == SMU_RSP_INVALID_ARGS) return -12;
    if (response == SMU_RSP_BUSY) return -13;
    return -5;
}

int AMDRyzenCPUPowerManagement::setOverclockFreqPerCcd(const uint32_t *mhzByCcd, uint8_t ccdCount, uint8_t startCcd) {
    if (!pboLimitsSupported()) return -1;
    
    if (!mhzByCcd || ccdCount == 0 || ccdCount > kS8MaxCcds || startCcd >= kS8MaxCcds ||
        startCcd + ccdCount > kS8MaxCcds) {
        IOLog("AMDRyzenCPUPowerManagement: Invalid per-CCD freq request (%u CCDs from %u, array %p).\n", ccdCount, startCcd, mhzByCcd);
        return -2;
    }
    for (uint8_t i = 0; i < ccdCount; i++) {
        if (mhzByCcd[i] < 400 || mhzByCcd[i] > 8000) {
            IOLog("AMDRyzenCPUPowerManagement: CCD%u freq %u MHz outside the 400..8000 envelope. Blocking.\n", startCcd + i, mhzByCcd[i]);
            return -2;
        }
    }
    
    // OC-mode gate, same as the all-core path.
    if (smuOcModeState != 1) {
        IOLog("AMDRyzenCPUPowerManagement: Blocked per-CCD freq override (0x5D): OC mode not enabled by this driver this boot.\n");
        return -3;
    }
    
    // Thermal safety interlock (one check up front — the whole sequence
    // runs within a single controlLock hold, milliseconds apart).
    float currentTemp = PACKAGE_TEMPERATURE_perPackage[0];
    if (currentTemp > kCURVE_OPTIMIZER_BLOCK_TEMP_C) {
        IOLog("AMDRyzenCPUPowerManagement: Blocked per-CCD freq override (0x5D) due to high package temperature (%.1f C).\n", currentTemp);
        return -4;
    }
    
    // One mailbox round trip per CCD. All-or-nothing per CCD: a mid-sequence
    // failure returns the mapped error and the cache keeps only the CCDs
    // that acknowledged OK — the UI reads the cache, so it shows the truth.
    for (uint8_t i = 0; i < ccdCount; i++) {
        uint32_t mhz = mhzByCcd[i];
        uint8_t ccd = startCcd + i;
        // Vermeer: (ccd << 28) | ((core % 8) << 20) | freq with core = ccd*8
        // → (core % 8) == 0 → (ccd << 28) | freq. The full packing stays in
        // this comment for a future multi-CCX silicon (see rsmu_commands.md
        // §SetOverclockFreqPerCore and ZenStates-Core MakeCoreMask).
        uint32_t arg = ((uint32_t)ccd << 28) | (mhz & 0xFFFFF);
        
        int response = smuSendCmd(0x5D, arg);
        if (response == SMU_RSP_OK) {
            ocFreqMHzPerCcd[ccd] = mhz;
            IOLog("AMDRyzenCPUPowerManagement: Per-CCD freq override applied (0x5D, ccd %u, %u MHz).\n", ccd, mhz);
        } else {
            IOLog("AMDRyzenCPUPowerManagement: SMU 0x5D ccd %u failed (response 0x%X) — earlier CCDs keep their programmed values.\n", ccd, response);
            if (response == SMU_RSP_TIMEOUT) return -10;
            if (response == SMU_RSP_INVALID_CMD) return -11;
            if (response == SMU_RSP_INVALID_ARGS) return -12;
            if (response == SMU_RSP_BUSY) return -13;
            return -5;
        }
    }
    return 0;
}

// S6: program the cHTC thermal limit (Vermeer SMU 0x56, Arg0 = °C, per
// ryzen_smu rsmu_commands.md). Same capability gate and thermal interlock
// policy as the PBO limits: Vermeer-with-mailbox only, writes blocked while
// the package is already hot. Cache updated for read-back on success.
int AMDRyzenCPUPowerManagement::setCHTCLimit(uint32_t arg) {
    if (!pboLimitsSupported()) return -1;
    
    // Thermal safety interlock, same policy as Curve Optimizer / PBO: don't
    // push a new thermal limit while the package is already hot.
    float currentTemp = PACKAGE_TEMPERATURE_perPackage[0];
    if (currentTemp > kCURVE_OPTIMIZER_BLOCK_TEMP_C) {
        IOLog("AMDRyzenCPUPowerManagement: Blocked cHTC limit write (0x56) due to high package temperature (%.1f C).\n", currentTemp);
        return -4;
    }
    
    int response = smuSendCmd(0x56, arg);
    
    if (response == SMU_RSP_OK) {
        smuCHTCLimitCelsius = arg;
        IOLog("AMDRyzenCPUPowerManagement: cHTC limit applied (0x56, %u C).\n", arg);
        return 0;
    }
    
    IOLog("AMDRyzenCPUPowerManagement: SMU cHTC command 0x56 failed with response code: 0x%X\n", response);
    if (response == SMU_RSP_TIMEOUT) return -10;
    if (response == SMU_RSP_INVALID_CMD) return -11;
    if (response == SMU_RSP_INVALID_ARGS) return -12;
    if (response == SMU_RSP_BUSY) return -13;
    return -5;
}

int AMDRyzenCPUPowerManagement::setCurveOptimizer(uint8_t core, int8_t offset) {
    // SMU command 0x3D (Curve Optimizer) is supported on Vermeer
    // regardless of whether CPPC or Legacy P-States are active.
    // Removed the legacyPstateAllowed block to enable CO in CPPC mode.
    
    // Bounds check on core index
    if (core >= totalNumberOfPhysicalCores) {
        IOLog("AMDRyzenCPUPowerManagement: Invalid core index %d (max: %d).\n", core, totalNumberOfPhysicalCores - 1);
        return -2;
    }
    
    // Safety check: Limit Curve Optimizer offset to safe range [-30, +30] as per implementation plan
    if (offset < -30 || offset > 30) {
        IOLog("AMDRyzenCPUPowerManagement: Offset %d exceeds safe limits [-30, +30]. Blocking write for safety.\n", offset);
        return -3;
    }
    
    // Thermal safety check: Block if temperature is too high (> kCURVE_OPTIMIZER_BLOCK_TEMP_C) to prevent instability
    float currentTemp = PACKAGE_TEMPERATURE_perPackage[0];
    if (currentTemp > kCURVE_OPTIMIZER_BLOCK_TEMP_C) {
        IOLog("AMDRyzenCPUPowerManagement: Blocked Curve Optimizer write due to high core temperature (%.1f°C > %.1f°C).\n", currentTemp, kCURVE_OPTIMIZER_BLOCK_TEMP_C);
        return -4;
    }
    
    // Format argument: Bits [7:0] = Core Index, Bits [15:8] = Offset (signed 8-bit)
    // NOTE: This payload format is Zen 3 (Vermeer) specific.
    // Zen 4 Raphael uses a per-CCD layout; Zen 5 Granite Ridge uses a different
    // signed-magnitude encoding. smuMailbox.curveOptimizerCmd must be 0x3D AND the
    // detected family must be Vermeer before this path is reachable.
    if (cpuFamily != 0x19 || cpuModel < 0x21 || cpuModel > 0x2F) return -1;
    uint32_t arg = ((uint32_t)core & 0xFF) | (((uint32_t)offset & 0xFF) << 8);
    
    // Send command 0x3D (SetCurveOptimizer) to SMU
    int response = smuSendCmd(smuMailbox.curveOptimizerCmd, arg);
    
    if (response == SMU_RSP_OK) {
        curveOptimizerOffsets[core] = offset;
        IOLog("AMDRyzenCPUPowerManagement: Successfully set Curve Optimizer for Core %d to %d (Offset counts).\n", core, offset);
        return 0;
    } else {
        IOLog("AMDRyzenCPUPowerManagement: SMU Curve Optimizer command failed with response code: 0x%X\n", response);
        if (response == SMU_RSP_TIMEOUT) return -10;
        if (response == SMU_RSP_INVALID_CMD) return -11;
        if (response == SMU_RSP_INVALID_ARGS) return -12;
        if (response == SMU_RSP_BUSY) return -13;
        return -5;
    }
}

// ------------------------------------------------------------------
// S4: Precision Boost Overdrive limits + scalar (Vermeer RSMU set).
//
// Commands follow the evidence-documented Vermeer mailbox set used by
// Ryzen Master / ryzen_smu (rsmu_commands.md):
//   0x53 SetPptLimit   (arg in mW)
//   0x54 SetTdcLimit   (arg in mA)
//   0x55 SetEdcLimit   (arg in mA)
//   0x58 SetPboScalar  (arg in %x100, 100..1000 => 1x..10x)
// These are write-only SMU commands: there is no read-back, so the
// successfully-programmed values are cached for the UI in the same
// way as Curve Optimizer offsets.
//
// Fail-closed: requires Vermeer (family 0x19, model 0x21..0x2F) and a
// supported mailbox — identical gating to setCurveOptimizer.
// ------------------------------------------------------------------

int AMDRyzenCPUPowerManagement::setPBOLimit(uint32_t smuCmd, uint32_t arg, uint32_t &cacheSlot) {
    if (!pboLimitsSupported()) return -1;
    
    // Thermal safety interlock, same policy as Curve Optimizer: don't push
    // new power limits while the package is already hot.
    float currentTemp = PACKAGE_TEMPERATURE_perPackage[0];
    if (currentTemp > kCURVE_OPTIMIZER_BLOCK_TEMP_C) {
        IOLog("AMDRyzenCPUPowerManagement: Blocked PBO limit write (cmd 0x%X) due to high package temperature (%.1f C).\n", smuCmd, currentTemp);
        return -4;
    }
    
    int response = smuSendCmd(smuCmd, arg);
    
    if (response == SMU_RSP_OK) {
        cacheSlot = arg;
        IOLog("AMDRyzenCPUPowerManagement: PBO limit applied (cmd 0x%X, arg %u).\n", smuCmd, arg);
        return 0;
    }
    
    IOLog("AMDRyzenCPUPowerManagement: SMU PBO command 0x%X failed with response code: 0x%X\n", smuCmd, response);
    if (response == SMU_RSP_TIMEOUT) return -10;
    if (response == SMU_RSP_INVALID_CMD) return -11;
    if (response == SMU_RSP_INVALID_ARGS) return -12;
    if (response == SMU_RSP_BUSY) return -13;
    return -5;
}

void AMDRyzenCPUPowerManagement::updatePackageTemp(){
    float sum = 0;

#pragma mark - Curve Optimizer
    for (int i = 0; i < HF_TEMP_SAMPLE_LEN; i++) sum += tempSamples[i];
    float currentTemp = sum * HF_TEMP_SAMPLE_LENREP;
    PACKAGE_TEMPERATURE_perPackage[0] = currentTemp;
    __sync_synchronize();
    
    // Dynamic CPPC Throttling Logic
    if (cppcActiveMode) {
        if (!cppcThrottled && currentTemp > kTHERMAL_THROTTLE_TEMP_C) {
            cppcThrottled = true;
            IOLog("AMDRyzenCPUPowerManagement: Thermal limit reached (%.1f°C). Throttling CPPC EPP to Power Save.\n", currentTemp);
            applyEPPControl();
        } else if (cppcThrottled && currentTemp < kTHERMAL_THROTTLE_CLEAR_C) {
            cppcThrottled = false;
            IOLog("AMDRyzenCPUPowerManagement: Thermal condition cleared (%.1f°C). Restoring CPPC EPP.\n", currentTemp);
            applyEPPControl();
        }
    }
}

void AMDRyzenCPUPowerManagement::updatePackageEnergy(){
    
    uint64_t ctsc = rdtsc64();

    uint64_t msr_value_buf = 0;
    if (!read_msr(kMSR_PKG_ENERGY_STAT, &msr_value_buf)) {
        IOLog("AMDRyzenCPUPowerManagement::updatePackageEnergy: failed to read MSR 0xC001029B\n");
        return;
    }

    uint32_t energyValue = (uint32_t)(msr_value_buf & 0xffffffff);

    uint32_t energyDelta = energyValue - (uint32_t)lastUpdateEnergyValue;

    // Guard against anomalous wrap-around producing absurd delta values
    if (energyDelta > 0x80000000u) { lastUpdateEnergyValue = energyValue; return; }

    double seconds = (ctsc - pwrLastTSC) / (double)(xnuTSCFreq);
    if (seconds <= 0.0) { pwrLastTSC = ctsc; return; }
    double e = (pwrEnergyUnit * (double)energyDelta) / seconds;
    uniPackagePowerW = e;
    __sync_synchronize();


    lastUpdateEnergyValue = energyValue;
    pwrLastTSC = ctsc;  // Use the timestamp captured at the start of this function to avoid drift
}

void AMDRyzenCPUPowerManagement::dumpPstate(){
    

#pragma mark - P-State & Debug
    uint8_t len = 0;
    for (uint32_t i = 0; i < kMSR_PSTATE_LEN; i++) {
        uint64_t msr_value_buf = 0;
        bool err = !read_msr(kMSR_PSTATE_0 + i, &msr_value_buf);
        if (err) {
            IOLog("AMDRyzenCPUPowerManagement::dumpPstate failed to read MSR 0xC0010064\n");
            continue;
        }
        
        uint32_t eax = (uint32_t)(msr_value_buf & 0xffffffff);
        
        float clock;
        if (cpuFamily >= 0x1A) {
            // Family 1Ah (Zen 5) uses 12-bit CpuFid.
            int curCpuFid = (int)(eax & 0xfff);
            clock = (float)(curCpuFid * 5.0);
        } else {
            // CpuVid [21:14]
            // CpuDfsId [13:8]
            // CpuFid [7:0]
            int curCpuDfsId = (int)((eax >> 8) & 0x3f);
            int curCpuFid = (int)(eax & 0xff);
            if (curCpuDfsId == 0) {
                static bool loggedDumpPstateDfsZero = false;
                if (!loggedDumpPstateDfsZero) {
                    loggedDumpPstateDfsZero = true;
                    IOLog("AMDRyzenCPUPowerManagement::dumpPstate: curCpuDfsId is zero, clamping clock to 0\n");
                }
                clock = 0.0f;
            } else {
                clock = (float)((float)curCpuFid / (float)curCpuDfsId * 200.0);
            }
        }
        
        PStateDef_perCore[i] = msr_value_buf;
        PStateDefClock_perCore[i] = clock;
        
        if(msr_value_buf & ((uint64_t)1 << 63)) len++;
        //        IOLog("a: %llu", msr_value_buf);
    }
    
    PStateEnabledLen = (len <= kMSR_PSTATE_LEN) ? len : (uint8_t)kMSR_PSTATE_LEN;
}

void AMDRyzenCPUPowerManagement::reinitHwState() {
    uint32_t cpuid_eax = 0;
    uint32_t cpuid_ebx = 0;
    uint32_t cpuid_ecx = 0;
    uint32_t cpuid_edx = 0;

    CPUInfo::getCpuid(0x80000007, 0, &cpuid_eax, &cpuid_ebx, &cpuid_ecx, &cpuid_edx);
    cpbSupported = (cpuid_edx >> 9) & 0x1;

    // Probe CPPC support: read CAP1 MSR. All Zen families (17h/19h/1Ah) support CPPC,
    // but CPPC writes (ENABLE/REQ MSRs) are disabled in the current baseline.
    // CPPC writes may be enabled in a future profile update once validated.
    uint64_t cppcVal = 0;
    bool msrSuccess = read_msr(kMSR_AMD_CPPC_CAP1, &cppcVal);
    const bool zenFamily = (cpuFamily == 0x17 || cpuFamily == 0x19 || cpuFamily == 0x1A);

    // CPPC is supported if MSR reads successfully or CPU is a known Zen family.
    if (msrSuccess || zenFamily) {
        if (!cppcSupported) {
            cppcSupported = true;
        }
        IOLog("AMDRyzenCPUPowerManagement::reinitHwState: CPPC CAP1 readable (CAP1=0x%llx)\n", cppcVal);
    } else {
        cppcSupported = false;
    }

    // CPPC write paths (ENABLE/REQ) are disabled in the current baseline.
    // cppcActiveMode requires a future profile flag and boot-arg to enable.
    cppcActiveMode = checkKernelArgument("-amdcppcactive");
    // CPPC writes blocked until per-profile cppcWriteAllowed flag is implemented.
    if (cppcActiveMode) {
        cppcActiveMode = false;
        IOLog("AMDRyzenCPUPowerManagement::reinitHwState: CPPC Active Mode blocked — writes disabled in baseline\n");
    }
    
    uint64_t rapl = 0;
    if (read_msr(kMSR_RAPL_PWR_UNIT, &rapl)) {
        uint8_t energyStatusUnits = (rapl >> 8) & 0x1f;
        uint8_t timeUnits = (rapl >> 16) & 0x0f;
        pwrEnergyUnit = 1.0 / (double)(1ULL << energyStatusUnits);
        pwrTimeUnit = 1.0 / (double)(1ULL << timeUnits);
    } else {
        static bool loggedRaplFallback = false;
        if (!loggedRaplFallback) {
            loggedRaplFallback = true;
            IOLog("AMDRyzenCPUPowerManagement::reinitHwState WARN: failed to read MSR_RAPL_POWER_UNIT, using default 1/2^16 energy unit\n");
        }
        pwrEnergyUnit = 1.0 / (double)(1ULL << 16);
        pwrTimeUnit = 1.0 / (double)(1ULL << 10);
    }
    
    dumpPstate();
}

void AMDRyzenCPUPowerManagement::writePstate(const uint64_t *buf){
    // AUDIT F-08: selector 15 reaches here without the legacyPstateAllowed
    // check that applyPowerControl() performs. On Zen 3+ profiles the feature
    // matrix declares the CPU telemetry-only — macOS's native CPPC owns the
    // P-state tables, so privileged writes must not fight it.
    if (!legacyPstateAllowed) {
        static bool loggedLegacyBlocked = false;
        if (!loggedLegacyBlocked) {
            loggedLegacyBlocked = true;
            IOLog("AMDRyzenCPUPowerManagement::writePstate refused: CPU profile is telemetry-only (legacyPstateAllowed == false)\n");
        }
        return;
    }
    if (!buf) {
        static bool loggedNullBuf = false;
        if (!loggedNullBuf) {
            loggedNullBuf = true;
            IOLog("AMDRyzenCPUPowerManagement::writePstate WARN: Null buffer passed\n");
        }
        return;
    }
    
    PStateEnabledLen = 0;
    
    //A bit hacky but at least works for now.
    void* args[] = {this, (void*)buf};


    IOLockLock(rendezvousLock);
    mp_rendezvous(nullptr, [](void *obj) {
        auto v = static_cast<uint64_t*>(((uint64_t**)obj)[1]);
        auto provider = static_cast<AMDRyzenCPUPowerManagement*>(*((AMDRyzenCPUPowerManagement**)obj));

        for (uint32_t i = 0; i < provider->kMSR_PSTATE_LEN; i++) {
            if (i >= 8) {
                break;
            }
            uint64_t def = v[i];
            
            if (provider->cpuFamily >= 0x1A) {
                uint64_t curCpuFid = (def & 0xfff);
                float freq = (float)curCpuFid * 5.0f;
                if (!def || curCpuFid == 0 || freq < 400.0f) {
                    continue;
                }
            } else {
                uint64_t curCpuDfsId = ((def >> 8) & 0x3f);
                uint64_t curCpuFid = (def & 0xff);
                float freq = (curCpuDfsId > 0) ? ((float)curCpuFid / (float)curCpuDfsId * 200.0f) : 0.0f;
                if (!def || curCpuDfsId == 0 || curCpuFid == 0 || freq < 400.0f) {
                    continue;
                }
            }
            
            provider->write_msr(provider->kMSR_PSTATE_0 + i, def);
            
        }
    
        
        if(!pmRyzen_cpu_is_master(cpu_number())) return;
        provider->dumpPstate();

    }, nullptr, args);
    IOLockUnlock(rendezvousLock);

}

bool AMDRyzenCPUPowerManagement::initSuperIO(uint16_t *chipIntel, bool allowUnlock){
    if (!superIOLock) return false;

#pragma mark - Super IO & Fan Control
    IOLockLock(superIOLock);
    if (superIO) { delete superIO; superIO = nullptr; }
    // AUDIT F-15: pass allowUnlock to NCT668X to prevent unprivileged firmware unlock
    if(!superIO) superIO = ISSuperIONCT668X::getDevice(&savedSMCChipIntel, allowUnlock);
    // AUDIT F-03: only privileged callers may clear the NCT67XX I/O-space lock.
    if(!superIO) superIO = ISSuperIONCT67XXFamily::getDevice(&savedSMCChipIntel, allowUnlock);
    if(!superIO) superIO = ISSuperIOIT86XXEFamily::getDevice(&savedSMCChipIntel);
    
    if (chipIntel) {
        *chipIntel = savedSMCChipIntel;
    }
    
    // Reset last applied PWM state on SuperIO re-probe
    for (size_t i = 0; i < kMAX_FANS; i++) {
        lastAppliedPWM[i] = 0;
        lastPWMUpdateTime[i] = 0;
    }
    // AUDIT F-14: Reset per-curve hysteresis state on re-probe
    for (int i = 0; i < MAX_FAN_CURVES; i++) {
        lastAppliedTemp[i] = 0.0f;
        lastAppliedTempSeeded[i] = false;
    }
    
    bool ok = (superIO != nullptr);
    IOLockUnlock(superIOLock);
    return ok;
}

uint32_t AMDRyzenCPUPowerManagement::getPMPStateLimit(){
    return pmRyzen_pstatelimit;
}

void AMDRyzenCPUPowerManagement::setPMPStateLimit(uint32_t state){
    uint32_t safeState = min(2U, state);
    pmRyzen_pstatelimit = safeState;
    if (safeState > 0) {
        if (rendezvousLock) IOLockLock(rendezvousLock);
        pmRyzen_PState_reset();
        if (rendezvousLock) IOLockUnlock(rendezvousLock);
    }
}

uint32_t AMDRyzenCPUPowerManagement::getHPcpus(){
    return pmRyzen_hpcpus;
}

void AMDRyzenCPUPowerManagement::evaluateFanCurves() {
    if (!superIOLock) return;
    IOLockLock(superIOLock);
    if (!superIO) {
        IOLockUnlock(superIOLock);
        return;
    }
    
    // 1. Get raw current temperatures
    float cpuTemp = getPackageTemp();
    float gpuTemp = gpuTempC;
    
    uint64_t now = getCurrentTimeNs();
    
    // 2. Smooth temperature per curve once before evaluating fan loop (KRN-07, KRN-09)
    //
    // S10 KRN-01: the EMA is validated on both input and output.
    //  - A non-finite or out-of-range sample is NEVER fed into the filter; it is
    //    dropped and the slot unseeded, so the next good sample re-seeds
    //    instantly instead of crawling back over ~11 s from a poisoned value.
    //  - NaN used to be absorbing AND permanent (the seeded flag was never
    //    cleared), pinning the fan at lut[0] with the 85 C guard disabled.
    //  - The validity flag is consumed by the fan loop below, which applies
    //    kFAILSAFE_PWM rather than trusting an absent reading.
    for (int c = 0; c < MAX_FAN_CURVES; c++) {
        FanCurveConfig &config = fanCurves[c];

        float rawSourceTemp = cpuTemp;
        if (config.sourceSensor == 1 && isTempValid(gpuTemp) && gpuTemp > 0.0f) {
            rawSourceTemp = gpuTemp;
        }

        if (!isTempValid(rawSourceTemp)) {
            curveSmoothedValid[c] = false;
            curveSmoothedSeeded[c] = false;
            continue;
        }

        if (!curveSmoothedSeeded[c]) {
            curveSmoothedTemp[c] = rawSourceTemp;
            curveSmoothedSeeded[c] = true;
        } else {
            const float alpha = 0.2f;
            float prev = curveSmoothedTemp[c];
            if (!isTempValid(prev)) {
                curveSmoothedTemp[c] = rawSourceTemp;
            } else {
                curveSmoothedTemp[c] = (alpha * rawSourceTemp) + ((1.0f - alpha) * prev);
            }
        }

        if (!isTempValid(curveSmoothedTemp[c])) {
            curveSmoothedTemp[c] = rawSourceTemp;
        }
        curveSmoothedValid[c] = true;
        curveRawSourceTemp[c] = rawSourceTemp;
    }

    for (int fanIdx = 0; fanIdx < superIO->getNumberOfFans(); fanIdx++) {
        int8_t curveIdx = fanToCurveMap[fanIdx];
        if (curveIdx < 0 || curveIdx >= MAX_FAN_CURVES) {
            continue; // Default BIOS Auto control
        }
        
        FanCurveConfig &config = fanCurves[curveIdx];
        
        // S10 KRN-02 (a): trust gate. curveSmoothedValid[] is published by the
        // EMA stage; false means neither the configured source nor the CPU
        // fallback produced a reading inside the valid Zen window this tick.
        // An unreadable sensor used to decay to 0.0f, which selected lut[0] AND
        // made the >= 85 C test false — the two worst outcomes at once.
        if (!curveSmoothedValid[curveIdx]) {
            superIO->overrideFanControl(fanIdx, kFAILSAFE_PWM);
            lastAppliedPWM[fanIdx] = kFAILSAFE_PWM;
            lastAppliedTempSeeded[curveIdx] = false;
            lastPWMUpdateTime[fanIdx] = now;
            continue;
        }

        float rawSourceTemp = curveRawSourceTemp[curveIdx];
        float smoothed = curveSmoothedTemp[curveIdx];

        // S10 KRN-02 (b): the emergency guard is a SYSTEM-WIDE limit, so it is
        // armed from the hottest trustworthy sensor, never from the curve's own
        // configured source. A GPU-sourced curve used to leave a 95 C CPU
        // running at the (cool) GPU curve's low duty.
        float guardTemp = rawSourceTemp;
        if (isTempValid(cpuTemp) && cpuTemp > guardTemp) guardTemp = cpuTemp;
        if (isTempValid(gpuTemp) && gpuTemp > guardTemp) guardTemp = gpuTemp;

        // 4. Map temperature index (0 - 255) with proper rounding.
        // smoothed is guaranteed finite and in (-20, 135) by the EMA stage.
        int tempIdx = (int)(smoothed + 0.5f);
        if (tempIdx < 0) tempIdx = 0;
        if (tempIdx > 255) tempIdx = 255;

        // 5. Look up target PWM from LUT
        uint8_t targetPWM = config.lut[tempIdx];
        
        uint8_t currentPWM = lastAppliedPWM[fanIdx];
        uint64_t lastTime = lastPWMUpdateTime[fanIdx];
        
        // 7. Enforce Hysteresis and Ramp Rate Limiting
        if (currentPWM > 0 && targetPWM != 0) {
            double deltaTime = (double)HF_TEMP_SAMPLE_PERIOD / 1000.0;
            if (lastTime > 0 && now > lastTime) {
                deltaTime = (double)(now - lastTime) / 1e9;
            }
            
            // Check temperature delta for hysteresis
            // AUDIT F-14: Track downward hysteresis against the temperature where PWM was last applied,
            // preventing the fan from permanently locking at elevated RPM.
            if (!lastAppliedTempSeeded[curveIdx]) {
                lastAppliedTemp[curveIdx] = smoothed;
                lastAppliedTempSeeded[curveIdx] = true;
            }
            float tempDelta = smoothed - lastAppliedTemp[curveIdx];
            if (tempDelta < 0.0f && -tempDelta < (float)config.hysteresis && targetPWM < currentPWM) {
                targetPWM = currentPWM;
            } else {
                // Limit the speed change to config.rampRate
                float deltaPWM = (float)targetPWM - (float)currentPWM;
                float limit = (float)config.rampRate * (float)deltaTime;
                if (limit < 1.0f) limit = 1.0f; // Ensure at least 1 PWM step can change
                
                if (deltaPWM > limit) {
                    targetPWM = (uint8_t)(currentPWM + limit);
                } else if (deltaPWM < -limit) {
                    targetPWM = (uint8_t)(currentPWM - limit);
                }
            }
        }
        
        // 7.5. Apply the minimum-duty floor, then the emergency thermal guard.
        //
        // S10 KRN-02 (c): PWM 0 keeps its special meaning ("hand this fan back
        // to BIOS/SmartFan"), but any non-zero request below
        // kCURVE_MIN_ACTIVE_PWM is raised to it. Writing 1..39 produced a
        // silently stalled rotor. The floor is applied AFTER hysteresis/ramp
        // limiting so those stages cannot smuggle a sub-floor value through,
        // and BEFORE the guard so the guard always wins.
        // Cross-reference: Swift manual-mode floor is AMDFanSafety.minimumManualPWM
        // (Sources/RyzenStatus/Services/AMD/FanCurveModels.swift) — keep in sync.
        if (targetPWM != 0 && targetPWM < kCURVE_MIN_ACTIVE_PWM) {
            targetPWM = kCURVE_MIN_ACTIVE_PWM;
        }

        // Emergency thermal guard, armed from the hottest trustworthy sensor.
        // Last so it overrides the floor, the ramp limiter and the
        // release-to-BIOS branch alike: a hot fan is never handed to BIOS.
        if (guardTemp >= kTHERMAL_GUARD_TEMP_C) {
            targetPWM = (targetPWM < kTHERMAL_GUARD_PWM) ? kTHERMAL_GUARD_PWM : targetPWM;
        }
        
        // 8. Apply PWM override to the Super I/O chip
        if (targetPWM == 0) {
            superIO->setDefaultFanControl(fanIdx);
            lastAppliedPWM[fanIdx] = 0;
            lastAppliedTempSeeded[curveIdx] = false;
        } else {
            superIO->overrideFanControl(fanIdx, targetPWM);
            if (lastAppliedPWM[fanIdx] != targetPWM) {
                lastAppliedTemp[curveIdx] = smoothed;
                lastAppliedTempSeeded[curveIdx] = true;
            }
            lastAppliedPWM[fanIdx] = targetPWM;
        }
        lastPWMUpdateTime[fanIdx] = now;
    }
    IOLockUnlock(superIOLock);
}


#pragma mark - GPU Public Accessors

IOReturn AMDRyzenCPUPowerManagement::getGPUTemperature(uint32_t index, UInt16 *data) {
    if (index >= gpuCount || !gpuDevices[index]) {
        return kIOReturnNoDevice;
    }
    return gpuDevices[index]->getTemperature(data);
}

IOReturn AMDRyzenCPUPowerManagement::getGPUPower(uint32_t index, float *data) {
    if (index >= gpuCount || !gpuDevices[index]) {
        return kIOReturnNoDevice;
    }
    return gpuDevices[index]->getPower(data);
}

bool AMDRyzenCPUPowerManagement::gpuSupportsPower(uint32_t index) {
    if (index >= gpuCount || !gpuDevices[index]) {
        return false;
    }
    return gpuDevices[index]->supportsPower();
}

EXPORT extern "C" kern_return_t amdryzencpupm_kern_start(kmod_info_t *, void *) {
    // Report success but actually do not start and let I/O Kit unload us.
    // This works better and increases boot speed in some cases.
    PE_parse_boot_argn("liludelay", &ADDPR(debugPrintDelay), sizeof(ADDPR(debugPrintDelay)));
    ADDPR(debugEnabled) = checkKernelArgument("-amdpdbg");
    
    return KERN_SUCCESS;
}

EXPORT extern "C" kern_return_t amdryzencpupm_kern_stop(kmod_info_t *, void *) {
    // It is not safe to unload VirtualSMC plugins!
    return KERN_FAILURE;
}
