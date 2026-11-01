#include "AMDRyzenCPUPowerManagement.hpp"
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <architecture/i386/pio.h>
#include <string.h>
#include <mach/mach_time.h>
#include <kern/clock.h>
#include <kern/thread.h>
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

pmRyzen_symtable_t pmRyzen_symtable = {};
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

    // The SMN index/data pair (config 0x60/0x64) belongs to the root complex
    // at 00:00.0, which is where Linux amd_smn sends it too. Writing 0x60 on
    // any other AMD function (USB, SATA, a GPP bridge) would hit an unrelated
    // config register, so 00:00.0 is taken whenever it is found; the first
    // AMD function is only a fallback for an unexpected topology.
    IOPCIDevice *firstAMD = nullptr;
    while (OSObject *obj = service_iter->getNextObject()) {
        IOPCIDevice *dev = OSDynamicCast(IOPCIDevice, obj);
        if (!dev || dev->configRead16(kIOPCIConfigVendorID) != kAMD_HOST_BRIDGE_VENDOR) continue;
        if (dev->getBusNumber() == 0 && dev->getDeviceNumber() == 0 && dev->getFunctionNumber() == 0) {
            service = dev;
            break;
        }
        if (!firstAMD) firstAMD = dev;
    }
    if (!service && firstAMD) {
        IOLog("AMDRyzenCPUPowerManagement::getPCIService: AMD root complex 00:00.0 not found, using %u:%u.%u\n",
              firstAMD->getBusNumber(), firstAMD->getDeviceNumber(), firstAMD->getFunctionNumber());
        service = firstAMD;
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
            // No retain() here — OSObject construction starts at
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
// Periodic re-arm with 10 % leeway, so xnu can fold the wakeup into one it
// already has scheduled instead of waking a core just for this driver. Every
// consumer either measures the real interval (energy, counters, the main
// timer's own bookkeeping) or tolerates the jitter (fan curves, the
// temperature average). One-off short kicks stay exact.
static void armCoalescedTimeout(IOTimerEventSource *timer, uint32_t ms) {
    if (!timer) return;
    AbsoluteTime interval = 0, leeway = 0;
    clock_interval_to_absolutetime_interval(ms, kMillisecondScale, &interval);
    clock_interval_to_absolutetime_interval(ms >= 10 ? ms / 10 : 1, kMillisecondScale, &leeway);
    timer->setTimeout(kIOTimeOptionsWithLeeway, interval, leeway);
}
void AMDRyzenCPUPowerManagement::initWorkLoop() {
    IOLog("AMDRyzenCPUPowerManagement::startWorkLoop setting up timer\n");
    timerEvent_main = IOTimerEventSource::timerEventSource(this, [](OSObject *object, IOTimerEventSource *sender) {
        AMDRyzenCPUPowerManagement *provider = OSDynamicCast(AMDRyzenCPUPowerManagement, object);
        if (!provider) return;

        //Run initialization
        if(!provider->serviceInitialized){
            IOLog("AMDRyzenCPUPowerManagement::startWorkLoop initialize service\n");

            // Program every core (C-state policy, IRPerf enable, counter
            // baselines, CPPC ranking) and log the outcome afterwards.
            IOLockLock(provider->rendezvousLock);
            provider->reapplyPerCoreConfig();
            // -amdcppcactive: hand the cores to CPPC from boot.
            if (provider->cppcActiveMode) provider->applyEPPControlLocked();

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
            // reinitHwState() rewrites the P-state tables writePstate()
            // also writes, so it runs under the same lock. Firmware
            // re-initialised the cores during resume: put the per-core MSR
            // programming back and restart the counter windows.
            IOLockLock(provider->rendezvousLock);
            provider->reinitHwState();
            provider->reapplyPerCoreConfig();
            // S3 reset CPPC_ENABLE/REQ with the cores: put back the mode
            // and EPP in force before sleep.
            if (provider->cppcActiveMode) provider->applyEPPControlLocked();
            IOLockUnlock(provider->rendezvousLock);
            provider->resumeSuperIO();
            armCoalescedTimeout(sender, provider->updateTimeInterval);
            return;
        }

        // Nobody has asked for per-CPU data lately: stop here without
        // re-arming. The SMU caches the app reads first are refreshed once
        // on the way (boost telemetry is throttled, the other two are
        // one-shot), so a client that connects later, including the first
        // one after boot, never starts from empty values.
        uint64_t tickMs = getCurrentTimeNs() / 1000000;
        if (!provider->hasRecentDemand(tickMs)) {
            IOLockLock(provider->rendezvousLock);
            provider->pollBoostTelemetry();
            provider->pollProcessorParameters();
            provider->pollSmuVersion();
            IOLockUnlock(provider->rendezvousLock);
            provider->mainSamplingIdle = true;
            provider->seedNextSample = true;
            return;
        }

        bool seedOnly = provider->seedNextSample;
        IOLockLock(provider->rendezvousLock);
        mp_rendezvous_no_intrs([](void *obj) {
            auto provider = static_cast<AMDRyzenCPUPowerManagement*>(obj);
            uint32_t cpu_num = (uint32_t)cpu_number();
            bool seed = provider->seedNextSample;

            provider->updateInstructionDelta(cpu_num, seed);
            provider->updateC0Residency(cpu_num, seed);

            // Ignore hyper-threaded cores
            if(!pmRyzen_cpu_primary_in_core(cpu_num)) return;
            uint32_t physical = pmRyzen_cpu_phys_num(cpu_num);


            provider->calculateEffectiveFrequency(physical, seed);
            provider->updateCoreEnergy(physical, seed);

        }, provider);
        if (!seedOnly) {
            provider->finishCoreSamples();
            // Every CPU has now closed one window since reapplyPerCoreConfig().
            provider->idleResidencySampled = true;
        }

        // Refresh cached boost telemetry (the family's RSMU max clock / fastest core reads)
        // From the same command gate — never from user threads.
        provider->pollBoostTelemetry();

        // One-shot ProcessorParameters (0x6F) read — static silicon
        // configuration, so stop after the first successful answer this boot.
        provider->pollProcessorParameters();

        // One-shot SMU firmware version (0x02) read — static, cached
        // after the first successful answer this boot.
        provider->pollSmuVersion();

        // SMU PM-table plumbing — version probe, 0x05 transfer, 0x06
        // base, read-only snapshot capture (throttled to 1/s). Diagnostic
        // only: failures never disturb the control paths.
        provider->pollPMTable();

        IOLockUnlock(provider->rendezvousLock);

        uint64_t now = getCurrentTimeNs() / 1000000; //ms
        if (seedOnly) {
            // Baselines are fresh on every CPU; sample a short window now.
            provider->seedNextSample = false;
            provider->timeOfLastUpdate = now;
            sender->setTimeoutMS(kSEED_WINDOW_MS);
            return;
        }
        uint64_t deltaMissed = (now >= provider->timeOfLastMissedRequest) ? (now - provider->timeOfLastMissedRequest) : 0;
        uint64_t newInt = deltaMissed > provider->estimatedRequestTimeInterval
            ? deltaMissed : provider->estimatedRequestTimeInterval;

        uint64_t deltaLast = (now >= provider->timeOfLastUpdate) ? (now - provider->timeOfLastUpdate) : 1;
        provider->actualUpdateTimeInterval = deltaLast > UINT32_MAX ? UINT32_MAX : (uint32_t)deltaLast;
        provider->timeOfLastUpdate = now;
        // Poll between 50 ms and 1.2 s, following how often user space asks.
        provider->updateTimeInterval = (uint32_t)(newInt < 50 ? 50 : (newInt > 1200 ? 1200 : newInt));

        armCoalescedTimeout(provider->timerEvent_main, provider->updateTimeInterval);
    });

    // Seed the ring buffer only with a trustworthy value; the
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
        // Hold the previous sample when the read fails, instead of
        // averaging in the sentinel. A stale-but-plausible temperature is far
        // safer here than a value that silently disarms every thermal clamp.
        float t = provider->getPackageTemp();
        if (isTempValid(t)) {
            provider->tempSamples[next_samp] = t;
        }
        provider->tempNextSample = (next_samp + 1) % HF_TEMP_SAMPLE_LEN;

        // Package temperature (the average of the ring above) and package
        // power feed the SMC keys and the thermal interlocks, so they are
        // refreshed here whether or not the main sampler runs.
        provider->updatePackageTemp();
        provider->updatePackageEnergy();

        // A consumer is back while the main sampler is stopped: restart it.
        // Its first tick seeds the counter windows (seedNextSample).
        if (provider->mainSamplingIdle && provider->hasRecentDemand(getCurrentTimeNs() / 1000000)) {
            provider->mainSamplingIdle = false;
            if (provider->timerEvent_main) provider->timerEvent_main->setTimeoutMS(1);
        }

        for (uint8_t i = 0; i < provider->ccdCount; i++) {
            provider->ccdTemperatures[i] = provider->getCCDTemp(provider->ccdSlot[i]);
        }

        provider->updateSviTelemetry();

        // GPU temperature and power update, before the fan curves read them.
        for (uint32_t i = 0; i < provider->gpuCount; i++) {
            if (provider->gpuDevices[i]) {
                provider->gpuDevices[i]->getTemperature(&provider->gpuTemperatures[i]);
                if (provider->gpuDevices[i]->supportsPower()) {
                    provider->gpuDevices[i]->getPower(&provider->gpuPowers[i]);
                }
            }
        }

        // Feed the fan curves' GPU source from the first GPU, but only with a
        // real reading: SMU7 reports 255 for an invalid sample and a failed
        // read leaves 0, and either would replace the value the app last sent
        // through selector 103.
        if (provider->gpuCount > 0) {
            float gpuT = (float)provider->gpuTemperatures[0];
            if (gpuT > 0.0f && isTempValid(gpuT)) {
                provider->gpuTempC = gpuT;
            }
        }

        if (provider->superIOLock) {
            IOLockLock(provider->superIOLock);
            provider->refreshFanTelemetryIfStale();
            IOLockUnlock(provider->superIOLock);
        }

        provider->evaluateFanCurves();

        armCoalescedTimeout(sender, HF_TEMP_SAMPLE_PERIOD);
    });

    registerService();

    if (!timerEvent_main || !timerEvent_tempe) {
        // The service still publishes (user clients get static data), but
        // nothing would ever sample: say so instead of dereferencing null.
        IOLog("AMDRyzenCPUPowerManagement::initWorkLoop: timer allocation failed, telemetry disabled\n");
        OSSafeReleaseNULL(timerEvent_main);
        OSSafeReleaseNULL(timerEvent_tempe);
        return;
    }

    lastUpdateTime = getCurrentTimeNs();
    pwrLastTSC = rdtsc64();
    pwrEnergySeeded = false;
    workLoop->addEventSource(timerEvent_main);
    workLoop->addEventSource(timerEvent_tempe);
    timerEvent_main->setTimeoutMS(1);
    armCoalescedTimeout(timerEvent_tempe, HF_TEMP_SAMPLE_PERIOD);
}

void AMDRyzenCPUPowerManagement::stopWorkLoop() {
    // The post-wake tick (pendingReinit) re-seeds every window; nothing may
    // restart the main timer before it.
    mainSamplingIdle = false;
    seedNextSample = false;
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
    pwrEnergySeeded = false;
    // Give the system 250ms to complete the wake sequence before the kext
    // starts its own rendezvous / MSR work. 1ms was causing a CPU stall spike.
    if (timerEvent_main) timerEvent_main->setTimeoutMS(250);
    armCoalescedTimeout(timerEvent_tempe, HF_TEMP_SAMPLE_PERIOD);
}


// The thread holds a reference on the driver until the user answers, which
// also keeps the kext (and the code this thread runs) from unloading.
void AMDRyzenCPUPowerManagement::showLoadAlertAsync() {
    if (!kextloadAlerts || !kunc_alert) return;
    if (!OSCompareAndSwap(0, 1, &kextAlertDisplayed)) return;

    retain();
    thread_t thread = nullptr;
    kern_return_t kr = kernel_thread_start([](void *param, wait_result_t) {
        auto provider = static_cast<AMDRyzenCPUPowerManagement *>(param);
        char buf[160];
        snprintf(buf, sizeof(buf),
                 "%d problem(s) were detected while the driver loaded. "
                 "Check the system log for AMDRyzenCPUPowerManagement messages.",
                 (int)provider->kextloadAlerts);

        // "OK" (rf 0) dismisses it for this boot; "Clear Alert" (rf 1)
        // also resets the count.
        unsigned int rf = 0;
        (*(provider->kunc_alert))(0, 0, NULL, NULL, NULL,
                                  "AMDRyzenCPUPowerManagement", buf, "OK", "Clear Alert", NULL, &rf);
        if (rf == 1) {
            provider->kextloadAlerts = 0;
            OSCompareAndSwap(1, 0, &provider->kextAlertDisplayed);
        }
        provider->release();
        // Returning ends the thread.
    }, this, &thread);

    if (kr != KERN_SUCCESS) {
        OSCompareAndSwap(1, 0, &kextAlertDisplayed);
        release();
        return;
    }
    thread_deallocate(thread);
}

#pragma mark - start() — Main Initialization
bool AMDRyzenCPUPowerManagement::start(IOService *provider){

    bool success = IOService::start(provider);
    if(!success){
        IOLog("AMDRyzenCPUPowerManagement::start: IOService::start failed\n");
        return false;
    }

    disablePrivilegeCheck = checkKernelArgument("-amdpnopchk");

    // amdcstate=1 forbids CC6 idle; absent or 0 lets the app switch it on.
    uint32_t amdcstateVal = 0;
    PE_parse_boot_argn("amdcstate", &amdcstateVal, sizeof(amdcstateVal));
    c6Forbidden = (amdcstateVal != 0);

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
    cpuModel = (uint8_t)(baseModel | (extModel << 4));

    // Support for Zen (17h), Zen 2/3/4 (19h), and Zen 5 (1Ah)
    cpuSupportedByCurrentVersion = (cpuFamily == 0x17 || cpuFamily == 0x19 || cpuFamily == 0x1A)? 1 : 0;
    IOLog("AMDRyzenCPUPowerManagement::start Family %02Xh, Model %02Xh\n", cpuFamily, cpuModel);

    // Resolve capability profile for detected CPU from all known profiles.
    // Each profile defines whether the kext registers PM dispatch + legacy P-states
    // (Zen 1/2: macOS has no native AMD PM) or stays telemetry-only (Zen 3+).
    {
        const ZenCpuFeatureMap *allProfiles[] = {
            &ZEN1_PROFILE, &ZEN_PLUS_PROFILE, &ZEN2_PROFILE,
            &ZEN3_MILAN_PROFILE, &ZEN4_GENOA_PROFILE,
            &ZEN3_VERMEER_PROFILE, &ZEN3_PLUS_PROFILE, &ZEN3_CEZANNE_PROFILE,
            &ZEN4_PROFILE, &ZEN4C_PROFILE, &ZEN5_PROFILE,
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
            legacyPstateAllowed = activeProfile->legacyPstateAllowed;
            pmDispatchAllowed = activeProfile->pmDispatchAllowed;
            // The idle loop is the kernel's sti; hlt until CC6 is switched
            // on; `-amdnoidle` leaves it to the kernel entirely.
            idleDispatchActive = !checkKernelArgument("-amdnoidle");
            supportsCPPC = activeProfile->supportsCPPC;
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

    discoverAcpiCppc(provider);
    reinitHwState();

    fetchOEMBaseBoardInfo();

    IOLog("AMDRyzenCPUPowerManagement::start trying to init PCI service...\n");
    if(!getPCIService()){
        IOLog("AMDRyzenCPUPowerManagement::start no PCI support found, failing...\n");
        return false;
    }

    // Enumerate AMD GPUs
    enumerateGPUs();

    probeCCDs();
    probeSviTelemetry();

    // Probe the Super I/O now, so the SMC fan keys exist from boot and the
    // plugin can count the headers when it starts. The unlock writes
    // (NCT67XX I/O-space lock, IT86XXE 16-bit tachometer mode, NCT668X EC
    // enable) are the same ones SMCSuperIO makes at load, and privileged
    // selector 90 callers made them on every boot the app ran.
    if (initSuperIO(nullptr, true)) {
        IOLog("AMDRyzenCPUPowerManagement::start Super I/O chip 0x%04X, %d fan header(s)\n",
              savedSMCChipIntel, fanCount());
    } else {
        IOLog("AMDRyzenCPUPowerManagement::start no supported Super I/O chip found\n");
    }

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

    // Created before the PM dispatch takeover so a failure leaves the kernel's
    // own power management untouched.
    workLoop = IOWorkLoop::workLoop();
    if (!workLoop) {
        IOLog("AMDRyzenCPUPowerManagement::start failed to create work loop\n");
        return false;
    }

    // The firmware's C-state IO base (CstateAddr + 1 is _CST's CC6 port),
    // read before any core is reprogrammed. A base below 0x100 would make
    // the CC6 read hit a legacy port (0xF1 is the x87 error latch), so it
    // counts as no base at all.
    uint64_t cstateAddr = 0;
    if (read_msr(kMSR_CSTATE_ADDR, &cstateAddr)) {
        const uint16_t base = (uint16_t)(cstateAddr & 0xFFFF);
        cstateIoBase = (base >= 0x100 && base < 0xFFFF) ? base : 0;
    }
    IOLog("AMDRyzenCPUPowerManagement::start C-state IO base 0x%X, idle loop %s, CC6 %s\n",
          cstateIoBase, idleDispatchActive ? "owned" : "kernel's",
          c6IdleSupported() ? "available" : (c6Forbidden ? "forbidden by amdcstate" : "unavailable"));

    pmRyzen_init(this, idleDispatchActive ? 1 : 0, pmDispatchAllowed ? 1 : 0);

    selectSmuCommandSet(nameString);

    // One-shot SMU mailbox diagnostic probe at boot
    if (rsmu.supported) {
        IOLog("AMDRyzenCPUPowerManagement: [SMU Diagnostic] Mailbox initialized: cmd=0x%08X, arg=0x%08X, rsp=0x%08X\n",
              rsmu.msgReg, rsmu.argReg, rsmu.rspReg);

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

        if (verRsp == SMU_RSP_OK) {
            // The timer's one-shot pollSmuVersion() is then already answered.
            smuFirmwareVersionRaw = verResult;
            smuVersionPolled = true;
        }

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

    buildCoreMap();

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
        // Seed per-curve anchor temperature for downward hysteresis
        lastAppliedTemp[i] = 0.0f;
        lastAppliedTempSeeded[i] = false;
    }
    gpuTempC = 0.0f;

    initWorkLoop();

    PMinit();
    provider->joinPMtree(this);
    registerPowerDriver(this, powerStates, kNrOfPowerStates);

    return success;
}

#pragma mark - stop() — Cleanup

void AMDRyzenCPUPowerManagement::stop(IOService *provider){
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
    releaseAcpiCppc();

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
        for (size_t i = 0; i < kMAX_FANS; i++) fanRPMCache[i] = 0;
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

#pragma mark - Power State Management

// S3 powers the SMU down; on resume the firmware starts again from the BIOS
// values, so every "last programmed this boot" cache would describe settings
// that are no longer in effect, and smuOcModeState == 1 would keep the
// frequency-override gate open while OC mode is actually off. Back to 0 =
// "unknown / never set", which is what the app and the gates already handle.
// Nothing is re-applied here: re-programming an overclock on wake is the
// user's call, made from the app.
void AMDRyzenCPUPowerManagement::forgetSMUSettingsForSleep() {
    if (controlLock) IOLockLock(controlLock);
    memset(curveOptimizerOffsets, 0, sizeof(curveOptimizerOffsets));
    pboPPTMilliwatts = 0;
    pboTDCMilliamps = 0;
    pboEDCMilliamps = 0;
    pboScalarPercentX100 = 0;
    smuCHTCLimitCelsius = 0;
    smuOcModeState = 0;
    ocFreqMHzAllCores = 0;
    memset(ocFreqMHzPerCcd, 0, sizeof(ocFreqMHzPerCcd));
    if (controlLock) IOLockUnlock(controlLock);
}

IOReturn AMDRyzenCPUPowerManagement::setPowerState(unsigned long powerStateOrdinal, IOService* provider) {
    if (0 == powerStateOrdinal) {
        // Going to sleep
        IOLog("AMDRyzenCPUPowerManagement::setPowerState preparing for sleep\n");
        wentToSleep = true;
        stopWorkLoop();
        forgetSMUSettingsForSleep();
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

    strlcpy(boardVendor, "Unknown Vendor", BASEBOARD_STRING_MAX);
    strlcpy(boardName, "Unknown Platform", BASEBOARD_STRING_MAX);

    // Locked access, released with put() below: EFI runtime calls are not
    // reentrant and other Lilu users (NVRAM, VirtualSMC) share them.
    auto efiRT = EfiRuntimeServices::get(true);
    if (!efiRT) return;
    uint32_t att = 0;
    uint64_t sizee = BASEBOARD_STRING_MAX;
    uint64_t efistat;

    efistat = efiRT->getVariable(OC_OEM_VENDOR_VARIABLE_NAME, &EfiRuntimeServices::LiluVendorGuid,
                                 &att, &sizee, boardVendor);

    sizee = BASEBOARD_STRING_MAX;
    uint64_t efistat2 = efiRT->getVariable(OC_OEM_BOARD_VARIABLE_NAME, &EfiRuntimeServices::LiluVendorGuid,
                                  &att, &sizee, boardName);
    efiRT->put();

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

#pragma mark - MSR Access (read_msr, write_msr)

bool AMDRyzenCPUPowerManagement::read_msr(uint32_t addr, uint64_t *value){
    if (cpuFamily >= 0x19) {
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

// Every selector call lands here. Measuring the gap between single calls
// read a refresh of a dozen back-to-back selectors as a client polling
// every few milliseconds, so the timer kept dropping to its 50 ms floor and
// climbed back geometrically between refreshes: about five rendezvous of
// every CPU a second for an app asking once a second. The estimate now
// follows the period between burst starts, smoothed over the last few; a
// client that never pauses for kREQUEST_BURST_GAP_MS is a fast poller and
// gets the 50 ms floor as before.
void AMDRyzenCPUPowerManagement::registerRequest(){
    uint64_t now = getCurrentTimeNs() / 1000000;

    uint64_t gap = (now >= timeOfLastMissedRequest) ? (now - timeOfLastMissedRequest) : 0;
    timeOfLastMissedRequest = now;

    // While the main sampler is stopped, this timestamp is all it needs:
    // the sensor timer restarts it within one period. A client back after
    // a pause is a fresh one: its first period must not average in the
    // pause, which would hold the timer at its 1.2 s ceiling for the next
    // twenty-odd refreshes.
    if (gap > kCLIENT_IDLE_MS) {
        requestBurstStartMs = now;
        estimatedRequestTimeInterval = 0;
        return;
    }

    if (gap < kREQUEST_BURST_GAP_MS) {
        if (now - requestBurstStartMs > kREQUEST_STREAM_MS) {
            estimatedRequestTimeInterval = 0;
            requestBurstStartMs = now;
        }
        return;
    }

    uint64_t period = (requestBurstStartMs != 0 && now > requestBurstStartMs) ? (now - requestBurstStartMs) : gap;
    requestBurstStartMs = now;
    uint64_t est = estimatedRequestTimeInterval;
    estimatedRequestTimeInterval = (est == 0) ? period : (est * 3 + period) / 4;
}

#pragma mark - Frequency & Clock Management

void AMDRyzenCPUPowerManagement::calculateEffectiveFrequency(uint32_t physical, bool seedOnly){
    // Guard physical core index on >64 core systems
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
    freqDeltaAPERF_perCore[physical] = 0;
    freqDeltaMPERF_perCore[physical] = 0;
    if (seedOnly) return;
    //If an overflow of either the MPERF or APERF register occurs between read of last MPERF and
    //read of last APERF, the effective frequency calculated in is invalid.
    if(APERF <= lastAPERF || MPERF <= lastMPERF) {
        return;
    }

    // Rendezvous handler: keep the raw window, finishCoreSamples() scales it.
    freqDeltaAPERF_perCore[physical] = APERF - lastAPERF;
    freqDeltaMPERF_perCore[physical] = MPERF - lastMPERF;
}

// Runs inside the main rendezvous on each core's primary thread, so it
// only reads one MSR and the TSC and writes this core's slots. The counter
// is 32 bits wide: with the usual 15.3 uJ unit it wraps after about 65 kJ,
// some 18 h at 1 W or 30 min at 35 W. Unsigned subtraction handles one
// wrap, a delta past 2^31 is taken as a reset and skipped like the package
// path, and windows stay far below one wrap because the first window after
// an idle pause is only a seed (seedOnly) and wake restarts them.
void AMDRyzenCPUPowerManagement::updateCoreEnergy(uint32_t physical, bool seedOnly){
    if (physical >= CPUInfo::MaxCpus) return;

    uint64_t raw = 0;
    if (!read_msr(kMSR_CORE_ENERGY_STAT, &raw)) return;
    uint32_t energy = (uint32_t)(raw & 0xffffffff);
    uint64_t tsc = rdtsc64();

    uint32_t lastEnergy = lastCoreEnergy_perCore[physical];
    uint64_t lastTsc = lastCoreEnergyTSC_perCore[physical];
    lastCoreEnergy_perCore[physical] = energy;
    lastCoreEnergyTSC_perCore[physical] = tsc;
    coreEnergyDelta_perCore[physical] = 0;
    coreEnergyTSCDelta_perCore[physical] = 0;

    if (seedOnly || lastTsc == 0 || tsc <= lastTsc) return;
    uint32_t delta = energy - lastEnergy;
    if (delta > 0x80000000u) return;

    coreEnergyDelta_perCore[physical] = delta;
    coreEnergyTSCDelta_perCore[physical] = tsc - lastTsc;
}

// Work loop thread, right after the main rendezvous and under the same
// rendezvousLock: the floating-point half of calculateEffectiveFrequency()
// and updateCoreEnergy(). Cores without a fresh window keep their reading.
void AMDRyzenCPUPowerManagement::finishCoreSamples(){
    // P0 clock not ready yet (dumpPstate failed / still zero): no MHz.
    float freqP0 = PStateDefClock_perCore[0];
    float total = 0.0f;
    for (uint32_t physical = 0; physical < CPUInfo::MaxCpus; physical++) {
        uint64_t dMperf = freqDeltaMPERF_perCore[physical];
        if (freqP0 > 0.0f && dMperf != 0) {
            effFreq_perCore[physical] =
                ((float)freqDeltaAPERF_perCore[physical] / (float)dMperf) * freqP0;
        }

        uint64_t dTsc = coreEnergyTSCDelta_perCore[physical];
        if (xnuTSCFreq != 0 && dTsc != 0) {
            double seconds = (double)dTsc / (double)xnuTSCFreq;
            corePowerW_perCore[physical] =
                (float)((pwrEnergyUnit * (double)coreEnergyDelta_perCore[physical]) / seconds);
        }
        total += corePowerW_perCore[physical];
    }
    corePowerTotalW = total;
}

// Per-core programming shared by the first tick and the post-wake path.
// Caller holds rendezvousLock. The rendezvous handler runs with interrupts
// off on every CPU, so it only touches MSRs and the provider's arrays; the
// outcome is logged here afterwards, from the work loop thread.
void AMDRyzenCPUPowerManagement::reapplyPerCoreConfig() {
    struct Outcome {
        AMDRyzenCPUPowerManagement *provider;
        volatile SInt32 hwcrFailures;
        volatile SInt32 counterFailures;
        volatile SInt32 cppcFailures;
    } outcome{this, 0, 0, 0};

    idleResidencySampled = false;

    mp_rendezvous_no_intrs([](void *obj) {
        auto out = static_cast<Outcome*>(obj);
        auto provider = out->provider;

        // HWCR[30] IRPerfEn: the instructions-retired counter behind
        // kMSR_PERF_IRPC (selectors 5 and 33).
        uint64_t hwConfig;
        if (!provider->read_msr(kMSR_HWCR, &hwConfig)) {
            OSIncrementAtomic(&out->hwcrFailures);
            return;
        }
        hwConfig |= (1ULL << 30);
        provider->write_msr(kMSR_HWCR, hwConfig);

        uint32_t cpu_num = (uint32_t)cpu_number();
        if (cpu_num >= CPUInfo::MaxCpus) return;

        // Read PStateDef generated by EFI (identical on every core); the
        // clocks are decoded after the rendezvous.
        if (pmRyzen_cpu_is_master(cpu_num)) {
            provider->readPstateDefs(false);
        }

        // CPPC CAP1 bits 31:24 are HighestPerformance, the per-core value
        // the preferred-core ranking comes from (7:0 is LowestPerformance,
        // the same on every core).
        if (provider->cppcSupported) {
            uint64_t cppcCap = 0;
            if (provider->read_msr(kMSR_AMD_CPPC_CAP1, &cppcCap)) {
                provider->cppcHighestPerf_perCore[cpu_num] = (cppcCap >> 24) & 0xFF;
            } else {
                OSIncrementAtomic(&out->cppcFailures);
            }
        }

        // Restart the per-CPU counter windows: the deltas on the next tick
        // must not span the time the counters were reset or not sampled.
        uint64_t mperf = 0, aperf = 0, irpc = 0;
        if (!provider->read_msr(kMSR_MPERF, &mperf) || !provider->read_msr(kMSR_APERF, &aperf)) {
            OSIncrementAtomic(&out->counterFailures);
            return;
        }
        provider->lastMPERFResidency_perCpu[cpu_num] = mperf;
        provider->lastTSCResidency_perCpu[cpu_num] = rdtsc64();
        provider->idlePercent_perCpu[cpu_num] = 0;
        if (provider->read_msr(kMSR_PERF_IRPC, &irpc)) {
            provider->lastInstructionDelta_perCore[cpu_num] = irpc;
        }

        if (!pmRyzen_cpu_primary_in_core(cpu_num)) return;
        uint32_t physical = pmRyzen_cpu_phys_num(cpu_num);
        if (physical >= CPUInfo::MaxCpus) return;
        provider->lastAPERF_perCore[physical] = aperf;
        provider->lastMPERF_perCore[physical] = mperf;
        provider->lastCoreEnergyTSC_perCore[physical] = 0;
    }, &outcome);
    decodePstateClocks(true);

    uint64_t cstateAddr = 0;
    if (read_msr(kMSR_CSTATE_ADDR, &cstateAddr)) {
        cstateAddrConfig = cstateAddr;
    }
    // Firmware re-initialises CSTATE_ADDR on resume; CC6 entry only goes on
    // while it still points at the port the kext enters CC6 through.
    if (c6IdleActive && (cstateAddrConfig & 0xFFFF) != cstateIoBase) {
        IOLog("AMDRyzenCPUPowerManagement: C-state base moved to 0x%llX, CC6 idle off\n",
              cstateAddrConfig & 0xFFFF);
        setC6Idle(false);
    }
    IOLog("AMDRyzenCPUPowerManagement::reapplyPerCoreConfig C-state address 0x%llX, "
          "HWCR failures %d, counter failures %d, CPPC CAP1 failures %d\n",
          cstateAddrConfig, (int)outcome.hwcrFailures, (int)outcome.counterFailures, (int)outcome.cppcFailures);
}

// C0 share of one logical CPU since its previous sample, integer math only
// (rendezvous handler: no FPU). A wrapped or reset counter skips the window.
void AMDRyzenCPUPowerManagement::updateC0Residency(uint32_t cpu_num, bool seedOnly){
    if (cpu_num >= CPUInfo::MaxCpus) return;

    uint64_t mperf = 0;
    if (!read_msr(kMSR_MPERF, &mperf)) return;
    uint64_t tsc = rdtsc64();

    uint64_t lastMperf = lastMPERFResidency_perCpu[cpu_num];
    uint64_t lastTsc = lastTSCResidency_perCpu[cpu_num];
    lastMPERFResidency_perCpu[cpu_num] = mperf;
    lastTSCResidency_perCpu[cpu_num] = tsc;

    if (seedOnly || lastTsc == 0 || tsc <= lastTsc || mperf < lastMperf) return;
    uint64_t dTsc = tsc - lastTsc;
    uint64_t dMperf = mperf - lastMperf;
    if (dMperf > dTsc) dMperf = dTsc;   // MPERF never outruns the TSC; clamp noise

    uint64_t busyPercent = (dMperf * 100) / dTsc;
    idlePercent_perCpu[cpu_num] = (uint8_t)(100 - busyPercent);
}

void AMDRyzenCPUPowerManagement::updateInstructionDelta(uint32_t cpu_num, bool seedOnly){
    // Guard logical CPU index on >64 CPU systems
    if (cpu_num >= CPUInfo::MaxCpus) return;

    uint64_t insCount;

    if(!read_msr(kMSR_PERF_IRPC, &insCount)) {
        return;
    }

    // The counter is 48 bits wide: modular subtraction carries a wrap, and
    // the baseline always moves on (keeping the old one after a wrap froze
    // the delta until the counter climbed back past it).
    uint64_t last = lastInstructionDelta_perCore[cpu_num];
    lastInstructionDelta_perCore[cpu_num] = insCount;
    if (seedOnly) return;
    instructionDelta_perCore[cpu_num] = (insCount - last) & kIRPERF_MASK;
}

#pragma mark - Power & EPP Control

void AMDRyzenCPUPowerManagement::applyPowerControl(){
    // Legacy P-state writes are controlled per CPU profile.
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

bool AMDRyzenCPUPowerManagement::applyEPPControl() {
    IOLockLock(rendezvousLock);
    bool applied = applyEPPControlLocked();
    IOLockUnlock(rendezvousLock);
    return applied;
}

// CPPC autonomous mode, the same programming as Linux amd-pstate-epp: the
// CPU picks its own frequency between LowestPerf and HighestPerf, biased
// by the EPP. P-states (PStateCtl / PStateDef) are never touched, so this
// does not compete with anything for frequency control; it replaces the
// "every core asks for P0" default that keeps an idle Zen 3 at full clocks.
bool AMDRyzenCPUPowerManagement::applyEPPControlLocked() {
    if (!cppcEppSupported()) return false;
    // Nothing engaged and nothing wanted: leave the firmware's state alone.
    if (!cppcActiveMode && !cppcEngaged) return true;

    // Off after being on: CPPC_ENABLE cannot be cleared before a reset, so
    // ask for full performance, the closest match to running without CPPC.
    uint8_t epp = 0x00;
    if (cppcActiveMode) epp = cppcThrottled ? 0xFF : cppcEPPValue;

    const bool ok = cppcMsrSupported ? applyEPPMsr(epp) : applyEPPAcpi(epp);
    if (ok) {
        cppcAppliedEPP = epp;
        IOLog("AMDRyzenCPUPowerManagement::applyEPPControl: CPPC %s, EPP 0x%02X on every CPU (%s)\n",
              cppcActiveMode ? "autonomous" : "performance", epp, cppcMsrSupported ? "MSR" : "ACPI");
    }
    return ok;
}

// MSR CPPC: CPPC_ENABLE, then CPPC_REQ with the core's own CAP1 range.
bool AMDRyzenCPUPowerManagement::applyEPPMsr(uint8_t epp) {
    struct EPPArgs {
        AMDRyzenCPUPowerManagement *provider;
        uint64_t epp;
        volatile SInt32 enableFailures;
        volatile SInt32 capFailures;
        volatile SInt32 reqFailures;
    } args{this, epp, 0, 0, 0};

    // Integer-only handler: it runs on every CPU with interrupts off.
    mp_rendezvous(nullptr, [](void *obj) {
        auto a = static_cast<EPPArgs*>(obj);
        auto p = a->provider;

        uint64_t enable = 0;
        if (!p->read_msr(kMSR_AMD_CPPC_ENABLE, &enable)) {
            OSIncrementAtomic(&a->enableFailures);
            return;
        }
        if (!(enable & 1) && !p->write_msr(kMSR_AMD_CPPC_ENABLE, enable | 1)) {
            OSIncrementAtomic(&a->enableFailures);
            return;
        }

        // CAP1 is per CPU (preferred cores report a higher HighestPerf).
        // A zero or inverted range would cap the core at nothing, so such a
        // core keeps whatever request it has.
        uint64_t cap1 = 0;
        if (!p->read_msr(kMSR_AMD_CPPC_CAP1, &cap1)) {
            OSIncrementAtomic(&a->capFailures);
            return;
        }
        uint64_t highest = (cap1 >> 24) & 0xFF;
        uint64_t lowest = cap1 & 0xFF;
        if (highest == 0 || lowest == 0 || lowest > highest) {
            OSIncrementAtomic(&a->capFailures);
            return;
        }

        // Bits 63:32 are reserved; keep what the CPU holds there.
        uint64_t req = 0;
        if (!p->read_msr(kMSR_AMD_CPPC_REQ, &req)) {
            OSIncrementAtomic(&a->reqFailures);
            return;
        }
        req = (req & 0xFFFFFFFF00000000ULL)
            | highest                   // max perf
            | (lowest << 8)             // min perf
            | (0ULL << 16)              // desired perf: autonomous
            | ((a->epp & 0xFF) << 24);  // EPP
        if (!p->write_msr(kMSR_AMD_CPPC_REQ, req)) {
            OSIncrementAtomic(&a->reqFailures);
        }
    }, nullptr, &args);

    const bool ok = args.enableFailures == 0 && args.capFailures == 0 && args.reqFailures == 0;
    if (args.enableFailures == 0) cppcEngaged = true;
    if (!ok) {
        IOLog("AMDRyzenCPUPowerManagement::applyEPPControl: EPP 0x%02X not applied (enable %d, cap %d, req %d CPU failures)\n",
              epp, (int)args.enableFailures, (int)args.capFailures, (int)args.reqFailures);
    }
    return ok;
}

#pragma mark - ACPI CPPC (PCC shared memory)

// Little-endian field readers for ACPI tables and resource buffers.
static uint64_t acpiLE(const uint8_t *p, uint32_t bytes) {
    uint64_t v = 0;
    for (uint32_t i = 0; i < bytes; i++) v |= (uint64_t)p[i] << (8 * i);
    return v;
}

static AMDRyzenCPUPowerManagement::AcpiGas acpiGasAt(const uint8_t *p) {
    AMDRyzenCPUPowerManagement::AcpiGas g;
    g.space = p[0]; g.bitWidth = p[1]; g.bitOffset = p[2]; g.accessSize = p[3];
    g.address = acpiLE(p + 4, 8);
    return g;
}

// Discovery, following Linux drivers/acpi/cppc_acpi.c (acpi_cppc_processor_probe)
// and drivers/mailbox/pcc.c: every ACPI processor beside the provider must
// return a _CPC package whose used registers live in PCC subspaces the PCCT
// describes; the subspaces' shared memory is mapped once, uncached. Any
// mismatch leaves acpiCppc.supported false with the reason in .error.
void AMDRyzenCPUPowerManagement::discoverAcpiCppc(IOService *provider) {
    acpiCppc = {};
    const IORegistryPlane *plane = IORegistryEntry::getPlane("IOACPIPlane");
    IORegistryEntry *parent = (plane && provider) ? provider->getParentEntry(plane) : nullptr;
    OSIterator *it = parent ? parent->getChildIterator(plane) : nullptr;
    if (!it) { acpiCppc.error = kAcpiCppcNoPlane; return; }

    uint32_t processors = 0;
    uint32_t subspacesUsed = 0;
    while (OSObject *obj = it->getNextObject()) {
        IOACPIPlatformDevice *dev = OSDynamicCast(IOACPIPlatformDevice, obj);
        if (!dev) continue;
        OSNumber *index = OSDynamicCast(OSNumber, dev->getProperty("processor-index"));
        if (!index) continue;
        processors++;
        const uint32_t cpu = index->unsigned32BitValue();
        if (cpu >= CPUInfo::MaxCpus) continue;

        OSObject *result = nullptr;
        if (dev->evaluateObject("_CPC", &result) != kIOReturnSuccess || !result) {
            if (!acpiCppc.error) acpiCppc.error = kAcpiCppcNoCpc;
            continue;
        }
        OSArray *pkg = OSDynamicCast(OSArray, result);
        OSNumber *revision = pkg ? OSDynamicCast(OSNumber, pkg->getObject(1)) : nullptr;
        // Revision 2 has 21 entries, revision 3 has 23; both hold every used index.
        if (!pkg || pkg->getCount() < 21 || !revision) {
            if (!acpiCppc.error) acpiCppc.error = kAcpiCppcBadCpc;
            result->release();
            continue;
        }
        acpiCppc.cpcRevision = revision->unsigned32BitValue();

        bool usable = true;
        for (uint32_t i = 0; i < kCpcUsedCount && usable; i++) {
            CpcValue &v = acpiCppc.cpc[cpu][i];
            OSObject *entry = pkg->getObject(kCpcUsed[i]);
            if (OSNumber *n = OSDynamicCast(OSNumber, entry)) {
                v.isRegister = false;
                v.integer = n->unsigned64BitValue();
                continue;
            }
            // Generic Register descriptor: 0x82, length 0x000C, then the GAS.
            OSData *d = OSDynamicCast(OSData, entry);
            const uint8_t *b = d ? (const uint8_t *)d->getBytesNoCopy() : nullptr;
            if (!b || d->getLength() < 15 || b[0] != 0x82) {
                if (!acpiCppc.error) acpiCppc.error = kAcpiCppcBadCpc;
                usable = false;
                break;
            }
            v.isRegister = true;
            v.reg = acpiGasAt(b + 3);
            // An all-zero register is "not implemented" (ACPI 6.x, 8.4.6.1).
            if (v.reg.space == 0 && v.reg.address == 0) {
                v.isRegister = false;
                v.integer = 0;
                continue;
            }
            // SystemMemory (0) or PCC (0x0A), the spaces Linux cppc_acpi drives
            // for AMD shared-memory CPPC; FFH would mean MSRs, which are absent.
            if (v.reg.space == 0x0A && v.reg.accessSize < kPccMaxSubspaces) {
                subspacesUsed |= 1u << v.reg.accessSize;
            } else if (v.reg.space != 0) {
                if (!acpiCppc.error) acpiCppc.error = kAcpiCppcNotPcc;
                usable = false;
                break;
            }
        }
        result->release();
        // EPP and the min/max/desired requests must be writable registers.
        const CpcValue *c = acpiCppc.cpc[cpu];
        if (usable && c[kSlotEpp].isRegister && c[kSlotMin].isRegister && c[kSlotMax].isRegister &&
            c[kSlotDesired].isRegister) {
            acpiCppc.cpuCount++;
        } else if (!acpiCppc.error) {
            acpiCppc.error = kAcpiCppcNotPcc;
        }
    }
    it->release();

    if (acpiCppc.error) return;
    if (acpiCppc.cpuCount == 0 || acpiCppc.cpuCount != processors) {
        acpiCppc.error = kAcpiCppcCountMismatch;
        return;
    }

    IOACPIPlatformDevice *acpiDev = OSDynamicCast(IOACPIPlatformDevice, provider);
    const OSData *pcct = (subspacesUsed && acpiDev) ? acpiDev->getACPITableData("PCCT", 0) : nullptr;
    const uint8_t *t = pcct ? (const uint8_t *)pcct->getBytesNoCopy() : nullptr;
    const uint32_t tableLength = t && pcct->getLength() >= 48 ? (uint32_t)acpiLE(t + 4, 4) : 0;
    if (subspacesUsed &&
        (!t || tableLength < 48 || tableLength > pcct->getLength() || memcmp(t, "PCCT", 4) != 0)) {
        acpiCppc.error = kAcpiCppcNoPcct;
        return;
    }

    // Subspaces follow the 36-byte header, Flags (4) and Reserved (8).
    uint32_t offset = 48;
    for (uint32_t id = 0; id < kPccMaxSubspaces && offset + 2 <= tableLength; id++) {
        const uint8_t *ss = t + offset;
        const uint8_t type = ss[0], length = ss[1];
        if (length < 2 || offset + length > tableLength) break;
        offset += length;
        if (!(subspacesUsed & (1u << id))) continue;
        if (type > 2 || length < 62) { acpiCppc.error = kAcpiCppcBadPcct; return; }

        PccSubspace &p = acpiCppc.pcc[id];
        p.present = true;
        p.type = type;
        p.base = acpiLE(ss + 8, 8);
        p.length = acpiLE(ss + 16, 8);
        p.doorbell = acpiGasAt(ss + 24);
        p.preserve = acpiLE(ss + 36, 8);
        p.write = acpiLE(ss + 44, 8);
        p.latencyUs = (uint32_t)acpiLE(ss + 52, 4);
        p.turnaroundUs = (uint16_t)acpiLE(ss + 60, 2);
        if (p.base == 0 || p.length < 8 || (p.doorbell.space != 0 && p.doorbell.space != 1)) {
            acpiCppc.error = kAcpiCppcBadPcct;
            return;
        }
    }
    for (uint32_t id = 0; id < kPccMaxSubspaces; id++) {
        if ((subspacesUsed & (1u << id)) && !acpiCppc.pcc[id].present) {
            acpiCppc.error = kAcpiCppcBadPcct;
            return;
        }
    }

    // Every PCC register must lie inside its subspace, every memory register
    // inside one page.
    for (uint32_t cpu = 0; cpu < CPUInfo::MaxCpus; cpu++) {
        for (uint32_t i = 0; i < kCpcUsedCount; i++) {
            const CpcValue &v = acpiCppc.cpc[cpu][i];
            if (!v.isRegister) continue;
            if (v.reg.bitWidth == 0 || (uint32_t)v.reg.bitOffset + v.reg.bitWidth > 64) {
                acpiCppc.error = kAcpiCppcBadCpc;
                return;
            }
            if (v.reg.space == 0x0A) {
                if (8 + v.reg.address + 8 > acpiCppc.pcc[v.reg.accessSize].length) {
                    acpiCppc.error = kAcpiCppcBadPcct;
                    return;
                }
            } else if ((v.reg.address & 0xFFF) + 8 > 0x1000) {
                acpiCppc.error = kAcpiCppcBadCpc;
                return;
            }
        }
    }

    for (uint32_t id = 0; id < kPccMaxSubspaces; id++) {
        PccSubspace &p = acpiCppc.pcc[id];
        if (!p.present) continue;
        IOMemoryDescriptor *md = IOMemoryDescriptor::withPhysicalAddress(
            (IOPhysicalAddress)p.base, (IOByteCount)p.length, kIODirectionInOut);
        p.shm = md ? md->createMappingInTask(kernel_task, 0, kIOMapAnywhere | kIOMapInhibitCache) : nullptr;
        if (md) md->release();
        if (p.doorbell.space == 0) {
            IOMemoryDescriptor *dmd = IOMemoryDescriptor::withPhysicalAddress(
                (IOPhysicalAddress)p.doorbell.address, 8, kIODirectionInOut);
            p.doorbellMap = dmd ? dmd->createMappingInTask(kernel_task, 0, kIOMapAnywhere | kIOMapInhibitCache) : nullptr;
            if (dmd) dmd->release();
        }
        if (!p.shm || (p.doorbell.space == 0 && !p.doorbellMap)) {
            acpiCppc.error = kAcpiCppcMapFailed;
            releaseAcpiCppc();
            return;
        }
    }

    // Map the pages that hold SystemMemory registers.
    for (uint32_t cpu = 0; cpu < CPUInfo::MaxCpus; cpu++) {
        for (uint32_t i = 0; i < kCpcUsedCount; i++) {
            const CpcValue &v = acpiCppc.cpc[cpu][i];
            if (!v.isRegister || v.reg.space != 0) continue;
            const uint64_t page = v.reg.address & ~0xFFFULL;
            uint32_t slot = 0;
            while (slot < kCpcMaxMemPages && acpiCppc.memPages[slot].map &&
                   acpiCppc.memPages[slot].base != page) slot++;
            if (slot == kCpcMaxMemPages) {
                acpiCppc.error = kAcpiCppcMapFailed;
                releaseAcpiCppc();
                return;
            }
            if (acpiCppc.memPages[slot].map) continue;
            IOMemoryDescriptor *md = IOMemoryDescriptor::withPhysicalAddress(
                (IOPhysicalAddress)page, 0x1000, kIODirectionInOut);
            acpiCppc.memPages[slot].map = md
                ? md->createMappingInTask(kernel_task, 0, kIOMapAnywhere | kIOMapInhibitCache) : nullptr;
            if (md) md->release();
            if (!acpiCppc.memPages[slot].map) {
                acpiCppc.error = kAcpiCppcMapFailed;
                releaseAcpiCppc();
                return;
            }
            acpiCppc.memPages[slot].base = page;
        }
    }
    acpiCppc.supported = true;
    IOLog("AMDRyzenCPUPowerManagement: ACPI CPPC on %u CPUs (_CPC revision %u, PCC subspaces 0x%X)\n",
          acpiCppc.cpuCount, acpiCppc.cpcRevision, subspacesUsed);
}

void AMDRyzenCPUPowerManagement::releaseAcpiCppc() {
    acpiCppc.supported = false;
    for (uint32_t id = 0; id < kPccMaxSubspaces; id++) {
        PccSubspace &p = acpiCppc.pcc[id];
        if (p.shm) { p.shm->release(); p.shm = nullptr; }
        if (p.doorbellMap) { p.doorbellMap->release(); p.doorbellMap = nullptr; }
    }
    for (uint32_t slot = 0; slot < kCpcMaxMemPages; slot++) {
        CpcMemPage &page = acpiCppc.memPages[slot];
        if (page.map) { page.map->release(); page.map = nullptr; }
    }
}

// One PCC command (0x00 read, 0x01 write) on a generic communication
// channel: wait for the previous command and the minimum turnaround, clear
// the status, ring the doorbell (read & preserve | write), poll for
// command-complete. Thread context, caller holds the lock that serialises
// EPP changes.
bool AMDRyzenCPUPowerManagement::pccCommand(PccSubspace &ss, uint16_t command) {
    volatile uint16_t *cmd = (volatile uint16_t *)(ss.shm->getVirtualAddress() + 4);
    volatile uint16_t *status = (volatile uint16_t *)(ss.shm->getVirtualAddress() + 6);
    const uint32_t timeoutUs = ss.latencyUs * 10 < 1000 ? 1000
                             : (ss.latencyUs * 10 > 20000 ? 20000 : ss.latencyUs * 10);

    // The channel is free once the previous command completed.
    uint32_t waited = 0;
    while (!(*status & 0x1) && waited < timeoutUs) { IODelay(10); waited += 10; }
    if (!(*status & 0x1)) {
        acpiCppc.lastStatus = *status;
        acpiCppc.lastResult = -3;
        return false;
    }
    if (ss.turnaroundUs && ss.lastCmdNs) {
        const uint64_t elapsedUs = (getCurrentTimeNs() - ss.lastCmdNs) / 1000;
        if (elapsedUs < ss.turnaroundUs) IODelay((uint32_t)(ss.turnaroundUs - elapsedUs));
    }

    *cmd = command;
    *status = 0;
    __sync_synchronize();

    const uint8_t width = ss.doorbell.bitWidth;
    if (ss.doorbell.space == 0) {
        volatile uint8_t *db = (volatile uint8_t *)ss.doorbellMap->getVirtualAddress();
        switch (width) {
            case 8:  *db = (uint8_t)((*db & ss.preserve) | ss.write); break;
            case 16: *(volatile uint16_t *)db = (uint16_t)((*(volatile uint16_t *)db & ss.preserve) | ss.write); break;
            case 64: *(volatile uint64_t *)db = (*(volatile uint64_t *)db & ss.preserve) | ss.write; break;
            default: *(volatile uint32_t *)db = (uint32_t)((*(volatile uint32_t *)db & ss.preserve) | ss.write); break;
        }
    } else {
        const uint16_t port = (uint16_t)ss.doorbell.address;
        switch (width) {
            case 8:  outb(port, (uint8_t)((inb(port) & ss.preserve) | ss.write)); break;
            case 16: outw(port, (uint16_t)((inw(port) & ss.preserve) | ss.write)); break;
            default: outl(port, (uint32_t)((inl(port) & ss.preserve) | ss.write)); break;
        }
    }

    waited = 0;
    while (!(*status & 0x1) && waited < timeoutUs) { IODelay(10); waited += 10; }
    ss.lastCmdNs = getCurrentTimeNs();
    acpiCppc.lastStatus = *status;
    if (!(*status & 0x1)) { acpiCppc.lastResult = -1; return false; }
    if (*status & 0x4)    { acpiCppc.lastResult = -2; return false; }
    acpiCppc.lastResult = 0;
    return true;
}

// Register access inside a mapped subspace; the field is bitWidth bits at
// bitOffset within the smallest naturally sized container that holds it.
static uint32_t cpcContainerBytes(const AMDRyzenCPUPowerManagement::AcpiGas &g) {
    const uint32_t bits = (uint32_t)g.bitOffset + g.bitWidth;
    return bits <= 8 ? 1 : bits <= 16 ? 2 : bits <= 32 ? 4 : 8;
}

// Kernel address of a register: inside its PCC subspace (after the 8-byte
// channel header), or inside its mapped SystemMemory page. nullptr when the
// mapping is missing.
volatile uint8_t *AMDRyzenCPUPowerManagement::cpcAddress(const AcpiGas &reg) {
    if (reg.space == 0x0A) {
        const PccSubspace &p = acpiCppc.pcc[reg.accessSize];
        return p.shm ? (volatile uint8_t *)(p.shm->getVirtualAddress() + 8 + reg.address) : nullptr;
    }
    const uint64_t page = reg.address & ~0xFFFULL;
    for (uint32_t slot = 0; slot < kCpcMaxMemPages; slot++) {
        const CpcMemPage &m = acpiCppc.memPages[slot];
        if (m.map && m.base == page) {
            return (volatile uint8_t *)(m.map->getVirtualAddress() + (reg.address & 0xFFF));
        }
    }
    return nullptr;
}

bool AMDRyzenCPUPowerManagement::cpcRead(const CpcValue &v, uint64_t &out) {
    if (!v.isRegister) { out = v.integer; return true; }
    volatile uint8_t *addr = cpcAddress(v.reg);
    if (!addr) return false;
    uint64_t raw = 0;
    switch (cpcContainerBytes(v.reg)) {
        case 1:  raw = *addr; break;
        case 2:  raw = *(volatile uint16_t *)addr; break;
        case 4:  raw = *(volatile uint32_t *)addr; break;
        default: raw = *(volatile uint64_t *)addr; break;
    }
    const uint64_t mask = v.reg.bitWidth >= 64 ? ~0ULL : ((1ULL << v.reg.bitWidth) - 1);
    out = (raw >> v.reg.bitOffset) & mask;
    return true;
}

bool AMDRyzenCPUPowerManagement::cpcWrite(const CpcValue &v, uint64_t value) {
    if (!v.isRegister) return true;   // a constant needs no write
    volatile uint8_t *addr = cpcAddress(v.reg);
    if (!addr) return false;
    const uint64_t mask = (v.reg.bitWidth >= 64 ? ~0ULL : ((1ULL << v.reg.bitWidth) - 1)) << v.reg.bitOffset;
    switch (cpcContainerBytes(v.reg)) {
        case 1:  *addr = (uint8_t)((*addr & ~mask) | ((value << v.reg.bitOffset) & mask)); break;
        case 2:  *(volatile uint16_t *)addr = (uint16_t)((*(volatile uint16_t *)addr & ~mask) | ((value << v.reg.bitOffset) & mask)); break;
        case 4:  *(volatile uint32_t *)addr = (uint32_t)((*(volatile uint32_t *)addr & ~mask) | ((value << v.reg.bitOffset) & mask)); break;
        default: *(volatile uint64_t *)addr = (*(volatile uint64_t *)addr & ~mask) | ((value << v.reg.bitOffset) & mask); break;
    }
    return true;
}

// Autonomous mode through ACPI CPPC, like amd-pstate shared memory mode: a
// PCC READ refreshes the capabilities, then for every CPU min = lowest,
// max = highest, desired = 0 (autonomous), autonomous selection and CPPC
// enable on, EPP; one PCC WRITE per subspace carries all of them. Registers
// in SystemMemory take the writes directly, no command needed.
bool AMDRyzenCPUPowerManagement::applyEPPAcpi(uint8_t epp) {
    if (!acpiCppc.supported) return false;

    for (uint32_t id = 0; id < kPccMaxSubspaces; id++) {
        if (acpiCppc.pcc[id].present && !pccCommand(acpiCppc.pcc[id], 0x00)) {
            IOLog("AMDRyzenCPUPowerManagement: PCC read on subspace %u failed (status 0x%X)\n",
                  id, acpiCppc.lastStatus);
            return false;
        }
    }

    for (uint32_t cpu = 0; cpu < CPUInfo::MaxCpus; cpu++) {
        const CpcValue *c = acpiCppc.cpc[cpu];
        if (!c[kSlotEpp].isRegister) continue;   // no _CPC for this index
        uint64_t highest = 0, lowest = 0;
        if (!cpcRead(c[kSlotHighest], highest) || !cpcRead(c[kSlotLowest], lowest) ||
            highest == 0 || lowest == 0 || lowest > highest) {
            IOLog("AMDRyzenCPUPowerManagement: CPU %u has no usable CPPC range (%llu..%llu)\n",
                  cpu, lowest, highest);
            return false;
        }
        cpcWrite(c[kSlotMin], lowest);
        cpcWrite(c[kSlotMax], highest);
        cpcWrite(c[kSlotDesired], 0);       // autonomous
        cpcWrite(c[kSlotEnable], 1);
        cpcWrite(c[kSlotAutoSel], 1);
        cpcWrite(c[kSlotEpp], epp);
    }
    __sync_synchronize();

    for (uint32_t id = 0; id < kPccMaxSubspaces; id++) {
        if (acpiCppc.pcc[id].present && !pccCommand(acpiCppc.pcc[id], 0x01)) {
            IOLog("AMDRyzenCPUPowerManagement: PCC write on subspace %u failed (status 0x%X)\n",
                  id, acpiCppc.lastStatus);
            return false;
        }
    }
    cppcEngaged = true;
    return true;
}

void AMDRyzenCPUPowerManagement::setCPBState(bool enabled){
    if(!cpbSupported) return;

    uint64_t hwConfig;
    if(!read_msr(kMSR_HWCR, &hwConfig)) {
        IOLog("AMDRyzenCPUPowerManagement::setCPBState failed to read MSR 0xC0010015\n");
        return;
    }

    if(enabled){
        hwConfig &= ~(1ULL << 25);
    } else {
        hwConfig |= (1ULL << 25);
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

#pragma mark - Thermal & Energy Monitoring

// Returns kTEMP_INVALID (not 0.0f) when the reading cannot be
// trusted. 0.0f was ambiguous with a genuine 0 C, and 0 C is the single most
// dangerous value in this driver: it selects lut[0] (slowest duty) and makes
// every ">= 85 C" guard test false. Callers must use isTempValid(), not "> 0".
inline float AMDRyzenCPUPowerManagement::getPackageTemp() {
    if (!fIOPCIDevice || !pciConfigLock) return kTEMP_INVALID;
    uint32_t reg = smnRead32(kF17H_M01H_THM_TCON_CUR_TMP);
    if (reg == 0xFFFFFFFF) return kTEMP_INVALID;

    // Linux k10temp get_raw_temp(): Tctl in 0.125 C steps from bit 21,
    // 49 C high on the extended range, then the per-model Tctl offset (Tdie).
    float t = (float)(reg >> 21) * 0.125f;
    if ((reg & kZEN_CUR_TEMP_RANGE_SEL) ||
        (reg & kZEN_CUR_TEMP_TJ_SEL_MASK) == kZEN_CUR_TEMP_TJ_SEL_MASK) {
        t -= 49.0f;
    }
    t -= tempOffset;

    // Reject NaN, infinities and anything outside the plausible Zen window.
    if (!isTempValid(t)) return kTEMP_INVALID;
    return t;
}

// Finds the CCD temperature registers the way Linux k10temp_probe() does:
// the register offset and the number of slots come from the family/model,
// and a slot holds a CCD when its valid bit is set. Slots are not contiguous
// on parts with fused-off CCDs, so every slot is checked. Families k10temp
// does not list get no CCD sensors.
void AMDRyzenCPUPowerManagement::probeCCDs() {
    uint8_t slots = 0;
    ccdOffset = 0;
    if (cpuFamily == 0x17) {
        switch (cpuModel) {
        case 0x01: case 0x08: case 0x11: case 0x18:
            ccdOffset = 0x154; slots = 4; break;
        case 0x31: case 0x47: case 0x60: case 0x68: case 0x71:
            ccdOffset = 0x154; slots = 8; break;
        default:
            if (cpuModel >= 0xA0 && cpuModel <= 0xAF) { ccdOffset = 0x300; slots = 8; }
            break;
        }
    } else if (cpuFamily == 0x19) {
        if (cpuModel <= 0x01 || cpuModel == 0x08 || cpuModel == 0x21 ||
            (cpuModel >= 0x50 && cpuModel <= 0x5F)) {
            ccdOffset = 0x154; slots = 8;
        } else if (cpuModel >= 0x40 && cpuModel <= 0x4F) {
            ccdOffset = 0x300; slots = 8;
        } else if (cpuModel >= 0x60 && cpuModel <= 0x7F) {
            ccdOffset = 0x308; slots = 8;
        } else if ((cpuModel >= 0x10 && cpuModel <= 0x1F) || (cpuModel >= 0xA0 && cpuModel <= 0xAF)) {
            ccdOffset = 0x300; slots = 12;
        }
    } else if (cpuFamily == 0x1A) {
        if (cpuModel <= 0x1F) {
            ccdOffset = 0x1F0; slots = 16;
        } else if (cpuModel >= 0x40 && cpuModel <= 0x4F) {
            ccdOffset = 0x308; slots = 8;
        }
    }

    ccdCount = 0;
    for (uint8_t slot = 0; slot < slots && ccdCount < kMAX_CCD_COUNT; slot++) {
        uint32_t reg = smnRead32(kF17H_M01H_THM_TCON_CUR_TMP + ccdOffset + slot * 4u);
        // An unreachable register reads all ones, which would pass the valid-bit test.
        if (reg == 0xFFFFFFFF || !(reg & kZEN_CCD_TEMP_VALID_BIT)) continue;
        ccdSlot[ccdCount++] = slot;
        IOLog("AMDRyzenCPUPowerManagement::probeCCDs CCD slot %u present, raw=0x%X\n", slot, reg);
    }
    IOLog("AMDRyzenCPUPowerManagement::probeCCDs %u CCD sensor(s) at offset 0x%X\n", ccdCount, ccdOffset);
}

float AMDRyzenCPUPowerManagement::getCCDTemp(uint8_t slot) {
    uint32_t reg = smnRead32(kF17H_M01H_THM_TCON_CUR_TMP + ccdOffset + slot * 4u);
    if (reg == 0xFFFFFFFF || !(reg & kZEN_CCD_TEMP_VALID_BIT)) return 0.0f;

    // Linux k10temp: (reg & 0x7FF) * 125 - 49000 millidegrees.
    return (float)(reg & kZEN_CCD_TEMP_MASK) * 0.125f - 49.0f;
}

// Picks the SVI2 plane registers the way LibreHardwareMonitor (Amd17Cpu.cs)
// and zenpower do: Zen/Zen+ use plane 0 (SVI + 0xC) for the cores and
// plane 1 (SVI + 0x10) for the SoC; Matisse (0x71) and Vermeer (19h 0x21)
// swap them; Castle Peak/Rome (0x31) have the cores at SVI + 0x14. Family
// 19h parts other than Vermeer keep the default layout behind the TFN bits,
// as LibreHardwareMonitor does. Zen 4 and Zen 5 run SVI3 and are left out.
void AMDRyzenCPUPowerManagement::probeSviTelemetry() {
    svi = {};
    if (cpuFamily == 0x17) {
        switch (cpuModel) {
        case 0x31:
            svi = { kF17H_M01H_SVI + 0x14, kF17H_M01H_SVI + 0x10, true, true };
            break;
        case 0x71:
            svi = { kF17H_M01H_SVI + 0x10, kF17H_M01H_SVI + 0xC, true, true };
            break;
        default:
            svi = { kF17H_M01H_SVI + 0xC, kF17H_M01H_SVI + 0x10, true, cpuModel == 0x11 };
            break;
        }
    } else if (cpuFamily == 0x19 && cpuModel <= 0x5F) {
        if (cpuModel == 0x21) {
            svi = { kF17H_M01H_SVI + 0x10, kF17H_M01H_SVI + 0xC, true, true };
        } else {
            svi = { kF17H_M01H_SVI + 0xC, kF17H_M01H_SVI + 0x10, true, false };
        }
    }
    IOLog("AMDRyzenCPUPowerManagement::probeSviTelemetry %s (core 0x%X, SoC 0x%X)\n",
          svi.supported ? "SVI2 planes mapped" : "no SVI2 layout for this silicon",
          svi.coreReg, svi.socReg);
}

// VID in bits [23:16] of the plane word, 1.550 V - VID * 6.25 mV. A plane
// whose telemetry function is off (TFN bit set), an unreadable register or
// a VID of 0 (plane idle / no data) leaves the slot invalid; the last good
// value is not kept, so the app shows a gap instead of a stale voltage.
void AMDRyzenCPUPowerManagement::updateSviTelemetry() {
    if (!svi.supported) return;

    uint32_t tfn = smnRead32(kF17H_M01H_SVI_TFN);
    uint32_t core = smnRead32(svi.coreReg);
    uint32_t soc = smnRead32(svi.socReg);
    sviTfnRaw = tfn;
    sviCoreRaw = core;
    sviSocRaw = soc;

    if (tfn == 0xFFFFFFFF) {
        sviCoreValid = false;
        sviSocValid = false;
        return;
    }
    sviCoreValid = sviDecodeMillivolts(core, (tfn & kSVI_TFN_CORE_PLANE_OFF) != 0, sviCoreMillivolts);
    sviSocValid = sviDecodeMillivolts(soc, !svi.socIgnoresTfn && (tfn & kSVI_TFN_SOC_PLANE_OFF) != 0, sviSocMillivolts);
}

bool AMDRyzenCPUPowerManagement::sviDecodeMillivolts(uint32_t word, bool planeOff, uint16_t &millivolts) {
    if (planeOff || word == 0xFFFFFFFF) return false;
    uint32_t vid = (word >> 16) & 0xFF;
    // VID 0 is "no request" (1.550 V); 0xF8 and above would be 0 V or less.
    if (vid == 0 || vid >= 0xF8) return false;
    millivolts = (uint16_t)((155000u - vid * 625u) / 100u);
    return true;
}

#pragma mark - SMN Access (smnRead32, smnWrite32)

uint32_t AMDRyzenCPUPowerManagement::smnRead32(uint32_t addr) {
    if (!fIOPCIDevice || !pciConfigLock) return 0;

    IOPCIAddressSpace space;
    space.bits = 0x00;

    IOSimpleLockLock(pciConfigLock);
    fIOPCIDevice->configWrite32(space, kSMN_INDEX_REGISTER, (UInt32)addr);
    uint32_t val = fIOPCIDevice->configRead32(space, kSMN_INDEX_REGISTER + 4);
    IOSimpleLockUnlock(pciConfigLock);
    return val;
}

void AMDRyzenCPUPowerManagement::smnWrite32(uint32_t addr, uint32_t val) {
    if (!fIOPCIDevice || !pciConfigLock) return;
    IOPCIAddressSpace space;
    space.bits = 0x00;

    IOSimpleLockLock(pciConfigLock);
    fIOPCIDevice->configWrite32(space, kSMN_INDEX_REGISTER, (UInt32)addr);
    fIOPCIDevice->configWrite32(space, kSMN_INDEX_REGISTER + 4, (UInt32)val);
    IOSimpleLockUnlock(pciConfigLock);
}

#pragma mark - SMU Command Sets

// Per-family SMU command numbers (ZenMaster runner.py _CMD_* tables and
// pmtable.py PM_TABLE_CMDS, ryzen_smu, ZenStates-Core). Only commands whose
// argument encoding is the same as on Vermeer are filled in; a family that
// lacks one keeps 0 and the feature reports unsupported there.
//   - OC mode needs both an enable and a disable command on RSMU.
//   - The OC VID is SVI2 (1.55 V - VID * 6.25 mV): left out on AM5 (SVI3).
//   - Curve Optimizer exists from Zen 3 on; per-core margins also need the
//     Zen 3 core fuse layout (Vermeer).
//   - APUs take STAPM/fast/slow power limits instead of PPT/TDC/EDC.
void AMDRyzenCPUPowerManagement::selectSmuCommandSet(const char *cpuName) {
    static const SmuCommandSet kSmuSummitRidge = {
        .name = "Summit Ridge / Threadripper 1000-2000",
        .setPpt = 0x64, .setTdc = 0x65, .setEdc = 0x66, .setTctl = 0x68, .setScalar = 0x6A,
        .pmVersion = 0x08, .pmBase = 0x06, .pmTransfer = 0x05, .pmBaseArg0 = 1, .pmBaseArg1 = 1,
        .pmBase64 = true,
    };
    static const SmuCommandSet kSmuPinnacleRidge = {
        .name = "Pinnacle Ridge",
        .setPpt = 0x64, .setTdc = 0x65, .setEdc = 0x66, .setTctl = 0x68, .setScalar = 0x6A,
        .pmVersion = 0x0C, .pmBase = 0x0B, .pmTransfer = 0x3D, .pmBaseArg0 = 3, .pmTransferArg = 3,
    };
    static const SmuCommandSet kSmuMatisse = {
        .name = "Matisse / Castle Peak",
        .setPpt = 0x53, .setTdc = 0x54, .setEdc = 0x55, .setTctl = 0x56,
        .setScalar = 0x58, .getScalar = 0x6C,
        .ocEnable = 0x5A, .ocDisable = 0x5B, .ocClkAll = 0x5C, .ocClkPerCore = 0x5D, .ocVid = 0x61,
        .getMaxClk = 0x6E, .getFastestCore = 0x59, .getProcessorParams = 0x6F,
        .pmVersion = 0x08, .pmBase = 0x06, .pmTransfer = 0x05, .pmBaseArg0 = 1, .pmBaseArg1 = 1,
        .pmBase64 = true,
        .mp1BoostLimit = 0x2B,
    };
    static const SmuCommandSet kSmuChagall = {
        .name = "Chagall",
        .setPpt = 0x53, .setTdc = 0x54, .setEdc = 0x55, .setTctl = 0x56,
        .setScalar = 0x58, .getScalar = 0x6C,
        .ocEnable = 0x5A, .ocDisable = 0x5B, .ocClkAll = 0x5C, .ocClkPerCore = 0x5D, .ocVid = 0x61,
        .getMaxClk = 0x6E, .getFastestCore = 0x59, .getProcessorParams = 0x6F,
        .pmVersion = 0x08, .pmBase = 0x06, .pmTransfer = 0x05, .pmBaseArg0 = 1, .pmBaseArg1 = 1,
        .pmBase64 = true,
        .mp1CoAll = 0x36, .mp1BoostLimit = 0x2B,
    };
    static const SmuCommandSet kSmuVermeer = {
        .name = "Vermeer",
        .setPpt = 0x53, .setTdc = 0x54, .setEdc = 0x55, .setTctl = 0x56,
        .setScalar = 0x58, .getScalar = 0x6C,
        .ocEnable = 0x5A, .ocDisable = 0x5B, .ocClkAll = 0x5C, .ocClkPerCore = 0x5D, .ocVid = 0x61,
        .getMaxClk = 0x6E, .getFastestCore = 0x59, .getProcessorParams = 0x6F,
        .pmVersion = 0x08, .pmBase = 0x06, .pmTransfer = 0x05, .pmBaseArg0 = 1, .pmBaseArg1 = 1,
        .pmBase64 = true,
        .mp1CoPerCore = 0x35, .mp1CoAll = 0x36, .mp1BoostLimit = 0x2B,
        .zen3CoreFuses = true,
    };
    static const SmuCommandSet kSmuAM5 = {
        .name = "Raphael / Storm Peak / Granite Ridge",
        .setPpt = 0x56, .setTdc = 0x57, .setEdc = 0x58, .setTctl = 0x59,
        .setScalar = 0x5B, .getScalar = 0x6D,
        .ocEnable = 0x5D, .ocDisable = 0x5E, .ocClkAll = 0x5F, .ocClkPerCore = 0x60,
        .getMaxClk = 0x6E, .getProcessorParams = 0x6F,
        .pmVersion = 0x05, .pmBase = 0x04, .pmTransfer = 0x03, .pmBase64 = true,
        .mp1CoAll = 0x36, .mp1BoostLimit = 0x2B,
    };
    static const SmuCommandSet kSmuRavenPicasso = {
        .name = "Raven Ridge / Picasso / Dali",
        .setStapm = 0x2E, .setFast = 0x30, .setSlow = 0x2F, .setTctl = 0x33,
        .pmVersion = 0x0C, .pmBase = 0x0B, .pmTransfer = 0x3D, .pmBaseArg0 = 3, .pmTransferArg = 3,
    };
    static const SmuCommandSet kSmuRenoirCezanne = {
        .name = "Renoir / Lucienne / Cezanne",
        .setStapm = 0x31, .setFast = 0x32, .setSlow = 0x33,
        .pmVersion = 0x06, .pmBase = 0x66, .pmTransfer = 0x65,
    };
    static const SmuCommandSet kSmuRembrandtPhoenix = {
        .name = "Rembrandt / Phoenix / Hawk Point",
        .setStapm = 0x31, .setFast = 0x32, .setSlow = 0x33,
        .pmVersion = 0x06, .pmBase = 0x66, .pmTransfer = 0x65, .pmBase64 = true,
    };

    // Mailbox register triples (message, first argument, response), from
    // ZenMaster mailbox.py and ryzen_smu smu.c.
    static const SMUMailbox kRsmuAM4V1 = { 0x3B1051C, 0x3B10590, 0x3B10568, true };
    static const SMUMailbox kMp1AM4V1  = { 0x3B10528, 0x3B10598, 0x3B10564, true };
    static const SMUMailbox kRsmuAM4V2 = { 0x3B10524, 0x3B10A40, 0x3B10570, true };
    static const SMUMailbox kMp1AM4V2  = { 0x3B10530, 0x3B109C4, 0x3B1057C, true };
    static const SMUMailbox kRsmuApu   = { 0x3B10A20, 0x3B10A88, 0x3B10A80, true };
    static const SMUMailbox kMp1Apu    = { 0x3B10528, 0x3B10998, 0x3B10564, true };
    static const SMUMailbox kMp1ApuFT6 = { 0x3B10528, 0x3B10998, 0x3B10578, true };

    const SmuCommandSet *set = nullptr;
    const SMUMailbox *r = nullptr, *m = nullptr;
    const bool threadripper = cpuName && strstr(cpuName, "Threadripper");

    if (cpuFamily == 0x17) {
        switch (cpuModel) {
        case 0x01:                    set = &kSmuSummitRidge; r = &kRsmuAM4V1; m = &kMp1AM4V1; break;
        case 0x08:
            set = threadripper ? &kSmuSummitRidge : &kSmuPinnacleRidge;
            r = &kRsmuAM4V1; m = &kMp1AM4V1;
            break;
        case 0x11: case 0x12: case 0x18: case 0x20:
                                      set = &kSmuRavenPicasso; r = &kRsmuApu; m = &kMp1Apu; break;
        case 0x31: case 0x71:         set = &kSmuMatisse; r = &kRsmuAM4V2; m = &kMp1AM4V2; break;
        case 0x60: case 0x68:         set = &kSmuRenoirCezanne; r = &kRsmuApu; m = &kMp1Apu; break;
        default: break;
        }
    } else if (cpuFamily == 0x19) {
        if (cpuModel == 0x08) {
            set = &kSmuChagall; r = &kRsmuAM4V2; m = &kMp1AM4V2;
        } else if (cpuModel == 0x18 && threadripper) {
            set = &kSmuAM5; r = &kRsmuAM4V2; m = &kMp1AM4V2;
        } else if (cpuModel >= 0x21 && cpuModel <= 0x2F) {
            set = &kSmuVermeer; r = &kRsmuAM4V2; m = &kMp1AM4V2;
        } else if (cpuModel == 0x3F || cpuModel == 0x40 || cpuModel == 0x44 ||
                   cpuModel == 0x74 || cpuModel == 0x75 || cpuModel == 0x78 || cpuModel == 0x7C) {
            set = &kSmuRembrandtPhoenix; r = &kRsmuApu; m = &kMp1ApuFT6;
        } else if (cpuModel == 0x50) {
            set = &kSmuRenoirCezanne; r = &kRsmuApu; m = &kMp1Apu;
        } else if (cpuModel == 0x61) {
            set = &kSmuAM5; r = &kRsmuAM4V2; m = &kMp1AM4V2;
        }
    } else if (cpuFamily == 0x1A && cpuModel == 0x44) {
        set = &kSmuAM5; r = &kRsmuAM4V2; m = &kMp1AM4V2;
    }

    if (!set) {
        IOLog("AMDRyzenCPUPowerManagement: no SMU command set for family %02Xh model %02Xh, SMU control off\n",
              cpuFamily, cpuModel);
        return;
    }
    smuCmd = *set;
    rsmu = *r;
    mp1 = *m;
    IOLog("AMDRyzenCPUPowerManagement: SMU command set %s (family %02Xh model %02Xh)\n",
          smuCmd.name, cpuFamily, cpuModel);
}

#pragma mark - SMU Mailbox Commands

// One mailbox transaction, following ryzen_smu smu_send_command() and
// ZenStates-Core SendSmuCommand():
//   1. wait for a non-zero response register (no command in flight);
//   2. clear it, write all argument registers, write the message id;
//   3. poll the response register; on OK read the arguments back.
// If step 1 times out nothing is written: overwriting the registers of a
// command the firmware is still executing would corrupt it.
int AMDRyzenCPUPowerManagement::smuExecute(const SMUMailbox &mb, uint32_t cmd,
                                           uint32_t (&args)[kSMU_ARG_COUNT],
                                           uint32_t timeoutUs, uint32_t *outElapsedUs) {
    if (outElapsedUs) *outElapsedUs = 0;
    if (!mb.supported || !smuCmdLock) return SMU_RSP_UNKNOWN_CMD;

    IOLockLock(smuCmdLock);

    // Every caller holds mutexes only (smuCmdLock, rendezvousLock, the work
    // loop gate), so a slow answer can yield the CPU: spin for the first
    // millisecond, where nearly every command completes, then sleep in 1 ms
    // steps against the real clock instead of busy-waiting the whole
    // deadline (25 ms for a PM-table transfer).
    auto waitStep = [](uint64_t startNs) -> uint32_t {
        uint64_t elapsedUs = (getCurrentTimeNs() - startNs) / 1000;
        if (elapsedUs < 1000) IODelay(elapsedUs < 100 ? 5 : 20);
        else IOSleep(1);
        elapsedUs = (getCurrentTimeNs() - startNs) / 1000;
        return elapsedUs > UINT32_MAX ? UINT32_MAX : (uint32_t)elapsedUs;
    };

    bool ready = false;
    uint64_t idleStartNs = getCurrentTimeNs();
    for (uint32_t waited = 0; waited <= 2000; waited = waitStep(idleStartNs)) {
        if (smnRead32(mb.rspReg) != 0) { ready = true; break; }
    }
    if (!ready) {
        IOLockUnlock(smuCmdLock);
        IOLog("AMDRyzenCPUPowerManagement: SMU mailbox busy, command 0x%X not sent\n", cmd);
        return SMU_RSP_NOT_READY;
    }

    smnWrite32(mb.rspReg, 0);
    for (uint32_t i = 0; i < kSMU_ARG_COUNT; i++) {
        smnWrite32(mb.argReg + i * 4, args[i]);
    }
    smnWrite32(mb.msgReg, cmd);

    uint32_t rsp = 0;
    uint32_t elapsed = 0;
    uint64_t sentNs = getCurrentTimeNs();
    while (elapsed < timeoutUs) {
        rsp = smnRead32(mb.rspReg);
        if (rsp != 0) break;
        elapsed = waitStep(sentNs);
    }
    // One last look: a sleep can overshoot the deadline by a tick.
    if (rsp == 0) rsp = smnRead32(mb.rspReg);

    if (rsp == SMU_RSP_OK) {
        for (uint32_t i = 0; i < kSMU_ARG_COUNT; i++) {
            args[i] = smnRead32(mb.argReg + i * 4);
        }
    }

    IOLockUnlock(smuCmdLock);

    if (outElapsedUs) *outElapsedUs = elapsed;
    return (int)rsp;
}

int AMDRyzenCPUPowerManagement::smuSendCmd(uint32_t cmd, uint32_t arg) {
    uint32_t unused = 0;
    return smuSendCmd(cmd, arg, unused);
}

// PM-table transfer (0x05) waits on a DMA copy, hence the longer deadline.
int AMDRyzenCPUPowerManagement::smuSendCmd(uint32_t cmd, uint32_t arg, uint32_t &outArg0, uint32_t *outElapsedUs) {
    uint32_t args[kSMU_ARG_COUNT] = { arg };
    int rsp = smuExecute(rsmu, cmd, args,
                         (smuCmd.pmTransfer && cmd == smuCmd.pmTransfer) ? 25000 : 10000, outElapsedUs);
    outArg0 = (rsp == SMU_RSP_OK) ? args[0] : arg;
    return rsp;
}

int AMDRyzenCPUPowerManagement::smuError(int response) {
    switch (response) {
    case SMU_RSP_TIMEOUT:         return -10;
    case SMU_RSP_UNKNOWN_CMD:     return -11;
    case SMU_RSP_REJECTED_PREREQ: return -12;
    case SMU_RSP_REJECTED_BUSY:
    case SMU_RSP_NOT_READY:       return -13;
    default:                      return -5;
    }
}

void AMDRyzenCPUPowerManagement::pollBoostTelemetry() {
    if (!rsmu.supported) return;

    uint64_t now = getCurrentTimeNs() / 1000000; // ms
    if (smuBoostTelemetryLastPollMs != 0 &&
        now - smuBoostTelemetryLastPollMs < kSMU_BOOST_POLL_MIN_INTERVAL_MS) {
        return;
    }
    smuBoostTelemetryLastPollMs = now;

    // RSMU read commands (ryzen_smu rsmu_commands.md, ZenMaster): the
    // family's GetMaxFrequency (Res0: MHz), GetFastestCoreOfSocket (raw
    // word, decoded app-side) and GetPBOScalar (IEEE-754 float). A family
    // without one skips it. 0 responses are cached as "unknown" rather than
    // retried every tick: the SMU only returns 0 while clocks are being
    // reconfigured.
    int rspMax = -1, rspFastest = -1, rspScalar = -1;
    uint32_t value = 0;
    if (smuCmd.getMaxClk) {
        rspMax = smuSendCmd(smuCmd.getMaxClk, 0, value);
        if (rspMax == SMU_RSP_OK) smuMaxBoostFreqMHz = value;
    }
    if (smuCmd.getFastestCore) {
        rspFastest = smuSendCmd(smuCmd.getFastestCore, 0, value);
        if (rspFastest == SMU_RSP_OK) smuFastestCoreRaw = value;
    }
    if (smuCmd.getScalar) {
        rspScalar = smuSendCmd(smuCmd.getScalar, 0, value);
        if (rspScalar == SMU_RSP_OK) smuActiveScalarRaw = value;
    }

    static bool sLoggedBoostFirst = false;
    if (!sLoggedBoostFirst) {
        IOLog("AMDRyzenCPUPowerManagement: Boost telemetry initial: max clock rsp=0x%X %u MHz, fastest core rsp=0x%X 0x%X, scalar rsp=0x%X 0x%X\n",
              rspMax, smuMaxBoostFreqMHz, rspFastest, smuFastestCoreRaw, rspScalar, smuActiveScalarRaw);
        sLoggedBoostFirst = true;
    }
}

// One-shot SMU firmware version read (global TestMessage-family command
// 0x02, per ryzen_smu: "OP 0x02 is consistent with all platforms"). Static —
// on the first SMU_RSP_OK the result is cached and never re-issued this
// boot. Response is the raw byte-packed version word; decode in
// AMDSmuReadback app-side. Timer command gate only.
uint32_t AMDRyzenCPUPowerManagement::pollSmuVersion() {
    if (!rsmu.supported) return 0;
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

// ------------------------------------------------------------------
// SMU PM-table plumbing (the family's version / base / transfer commands,
// smuCmd.pm*; Vermeer: RSMU 0x08 / 0x06 / 0x05).
//
// The SMU exposes a live metrics table (per-core clocks/temps/power —
// the same table ryzen_smu and HWiNFO feed from). The flow follows
// ryzen_smu smu.c:
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
// Runs exclusively on the timer command gate.
// ------------------------------------------------------------------

// PM-table size per version (ZenMaster pmtable.py TABLE_SIZES, which
// extends the Ryzen-Master-sourced list in ryzen_smu smu.c
// smu_update_pmtablesize to every family). Unknown versions -> 0 (fail
// closed; the snapshot stays invalid rather than mapping a guessed size).
static uint32_t pmTableSizeForVersion(uint32_t version) {
    switch (version) {
    case 0x00000400: return 0x0948;
    case 0x001E0001: return 0x0568;
    case 0x001E0002: return 0x0580;
    case 0x001E0003: return 0x0578;
    case 0x001E0004: return 0x0608;
    case 0x001E0005: return 0x0608;
    case 0x001E000A: return 0x0608;
    case 0x001E0101: return 0x0608;
    case 0x00240003: return 0x18AC;
    case 0x00240503: return 0x0D7C;
    case 0x00240603: return 0x0AB0;
    case 0x00240703: return 0x07E4;
    case 0x00240802: return 0x07E0;
    case 0x00240803: return 0x07E4;
    case 0x00240902: return 0x0514;
    case 0x00240903: return 0x0518;
    case 0x002D0008: return 0x1AB0;
    case 0x002D0803: return 0x0894;
    case 0x002D0903: return 0x0594;
    case 0x00370000: return 0x0794;
    case 0x00370001: return 0x0884;
    case 0x00370002: return 0x088C;
    case 0x00370003: return 0x08AC;
    case 0x00370004: return 0x08AC;
    case 0x00370005: return 0x08C8;
    case 0x00380005: return 0x1BB0;
    case 0x00380505: return 0x0F30;
    case 0x00380605: return 0x0C10;
    case 0x00380705: return 0x08F0;
    case 0x00380804: return 0x08A4;
    case 0x00380805: return 0x08F0;
    case 0x00380904: return 0x05A4;
    case 0x00380905: return 0x05D0;
    case 0x003F0000: return 0x07AC;
    case 0x00400001: return 0x0910;
    case 0x00400002: return 0x0928;
    case 0x00400003: return 0x094C;
    case 0x00400004: return 0x0944;
    case 0x00400005: return 0x0944;
    case 0x00450004: return 0x0AA4;
    case 0x00450005: return 0x0AB0;
    case 0x004C0003: return 0x0B18;
    case 0x004C0004: return 0x0B1C;
    case 0x004C0005: return 0x0AF8;
    case 0x004C0006: return 0x0AFC;
    case 0x004C0007: return 0x0B00;
    case 0x004C0008: return 0x0AF0;
    case 0x004C0009: return 0x0B00;
    case 0x00540000: return 0x0828;
    case 0x00540001: return 0x082C;
    case 0x00540002: return 0x087C;
    case 0x00540003: return 0x089C;
    case 0x00540004: return 0x08BC;
    case 0x00540005: return 0x08C8;
    case 0x00540208: return 0x08D0;
    case 0x00540100: return 0x0618;
    case 0x00540101: return 0x061C;
    case 0x00540102: return 0x066C;
    case 0x00540103: return 0x068C;
    case 0x00540104: return 0x06A8;
    case 0x00540105: return 0x06B4;
    case 0x00540108: return 0x06BC;
    case 0x005C0002: return 0x1E3C;
    case 0x005C0003: return 0x1E48;
    case 0x005C0102: return 0x1A14;
    case 0x005C0103: return 0x1A20;
    case 0x005C0202: return 0x15EC;
    case 0x005C0203: return 0x15F8;
    case 0x005C0302: return 0x0D9C;
    case 0x005C0303: return 0x0DA8;
    case 0x005C0402: return 0x0974;
    case 0x005C0403: return 0x0980;
    case 0x005D0008: return 0x0D54;
    case 0x005D0009: return 0x0D54;
    case 0x005D000A: return 0x0D54;
    case 0x005D000B: return 0x0D54;
    case 0x00620105: return 0x0724;
    case 0x00620205: return 0x0994;
    case 0x00621102: return 0x0724;
    case 0x00621202: return 0x0994;
    case 0x0064010C: return 0x0E50;
    case 0x0064020C: return 0x0E50;
    case 0x00650004: return 0x0B74;
    case 0x00650005: return 0x0B78;
    case 0x00650006: return 0x0B80;
    case 0x00650007: return 0x0D54;
    default:         return 0;
    }
}

// One capture cycle: (re-map if needed) 0x05 → 0x06 → map → copy → unmap.
// Returns 0 on success, else a mapped negative (-1 unsupported, -5 SMU
// error, -10 timeout, -11 unknown command, -12 rejected, -13 busy, -14
// unknown table version, -15 map failed).
int AMDRyzenCPUPowerManagement::forcePMTableCapture() {
    if (!smuPmTableSupported()) return -1;

    // 0x08: version (one-shot — static per firmware)
    if (!pmTableVersionPolled) {
        uint32_t versionWord = 0;
        uint32_t elap08 = 0;
        int rsp = smuSendCmd(smuCmd.pmVersion, 0, versionWord, &elap08);
        if (rsp != SMU_RSP_OK) {
            static bool sLogged08Fail = false;
            if (!sLogged08Fail) {
                IOLog("AMDRyzenCPUPowerManagement: PM table 0x08 (GetPMTableVersion) failed: rsp=0x%X, elapsed=%u us\n", rsp, elap08);
                sLogged08Fail = true;
            }
            return smuError(rsp);
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
        int rsp = smuSendCmd(smuCmd.pmTransfer, smuCmd.pmTransferArg, arg0, &elap05);
        if (rsp != SMU_RSP_OK) {
            static bool sLogged05Fail = false;
            if (!sLogged05Fail) {
                IOLog("AMDRyzenCPUPowerManagement: PM table 0x05 (TransferTableSmu2Dram) failed: rsp=0x%X, elapsed=%u us\n", rsp, elap05);
                sLogged05Fail = true;
            }
            return smuError(rsp);
        }
    }

    // 0x06: 64-bit physical base (Arg0=1/Arg1=1 in, arg0|arg1<<32 out).
    {
        uint32_t args[kSMU_ARG_COUNT] = { smuCmd.pmBaseArg0, smuCmd.pmBaseArg1 };
        uint32_t elap06 = 0;
        int rsp = smuExecute(rsmu, smuCmd.pmBase, args, 10000, &elap06);
        uint32_t lo = args[0], hi = smuCmd.pmBase64 ? args[1] : 0;
        if (rsp != SMU_RSP_OK) {
            static bool sLogged06Fail = false;
            if (!sLogged06Fail) {
                IOLog("AMDRyzenCPUPowerManagement: PM table 0x06 (GetDramBaseAddress) failed: rsp=0x%X, elapsed=%u us\n", rsp, elap06);
                sLogged06Fail = true;
            }
            return smuError(rsp);
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

// Main-timer refresh (timer command gate only), throttled to
// one 0x05 + capture per second. Re-runs the full cycle every time (the
// reference re-issues 0x05 per read; bases can migrate across firmware
// events), so a changed base address is picked up within a second.
// Failures keep the previous snapshot and stay diagnostic — this path
// must never disturb the PBO/CO/OC command flow (it shares smuCmdLock,
// which stays a leaf).
void AMDRyzenCPUPowerManagement::pollPMTable() {
    if (!smuPmTableSupported()) return;

    uint64_t now = getCurrentTimeNs() / 1000000; // ms
    if (pmRefreshLastPollMs != 0 &&
        now - pmRefreshLastPollMs < kPM_REFRESH_MIN_INTERVAL_MS) {
        return;
    }
    // Nobody has looked lately: keep the last snapshot and leave the SMU
    // alone (see pmTableLastDemandMs). The first capture still runs, so the
    // version and base are known from boot.
    const uint64_t demand = pmTableLastDemandMs;
    if (pmMapValid && (demand == 0 || now - demand > kPM_DEMAND_WINDOW_MS)) {
        return;
    }
    pmRefreshLastPollMs = now;

    (void)forcePMTableCapture();
}

// One-shot ProcessorParameters read (RSMU 0x6F on AM4 Zen 2/3 and AM5,
// per ryzen_smu rsmu_commands.md — Res0 bitfield, no input arg). Static silicon config:
// on the first SMU_RSP_OK the result is cached and the command is never
// re-issued this boot. Runs on the timer command gate only.
uint32_t AMDRyzenCPUPowerManagement::pollProcessorParameters() {
    if (!rsmu.supported || !smuCmd.getProcessorParams) return 0;
    if (smuProcParamsPolled) return smuProcessorParametersRaw;

    uint32_t result = 0;
    uint32_t elapsed = 0;
    int rsp = smuSendCmd(smuCmd.getProcessorParams, 0, result, &elapsed);
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

// On-demand mailbox health report (UserClient selector 58). Same three
// probes as the boot diagnostic, but callable from the app any time — every
// raw code is returned so the app can render the report without log show.
// The caller (UserClient) holds rendezvousLock across the whole run, matching
// the selector-57-op-2 capture convention; smuSendCmd's smuCmdLock stays the
// inner leaf. Read-only: never writes mailbox-visible state beyond the two
// probe commands themselves.
bool AMDRyzenCPUPowerManagement::runMailboxDiagnostics(SMUDiagnosticReport &out)
{
    out = {};
    out.mailboxSupported = rsmu.supported ? 1 : 0;
    out.msgReg = rsmu.msgReg;
    out.argReg = rsmu.argReg;
    out.rspReg = rsmu.rspReg;
    out.curveOptimizerCmd = smuCurveOptimizerCmd();
    if (!rsmu.supported) return false;

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

// Enable/disable OC mode (smuCmd.ocEnable/ocDisable; Vermeer: RSMU 0x5A EnableOcMode / 0x5B
// DisableOcMode, both with Arg0 = 0 (ZenStates-Core Zen2Settings and
// SetOcMode.ExecuteOcMode; ryzen_smu rsmu_commands.md lists 0 as "enabled"
// for 0x5A, while 0x1000000 in that argument is the PROCHOT switch).
// Same capability gate and thermal interlock as every other SMU write path.
// Some SMU firmware does not reset the PBO scalar when OC mode is left
// (ZenStates-Core SetOcMode), so `resetScalar` writes 1.0 (100) via 0x58
// after a successful disable.
int AMDRyzenCPUPowerManagement::setOcMode(bool enable, bool resetScalar) {
    if (!smuOcSupported()) return -1;
    const uint32_t cmd = enable ? smuCmd.ocEnable : smuCmd.ocDisable;

    // Thermal safety interlock, same policy as CO/PBO/cHTC: no new OC-mode
    // transitions while the package is already hot.
    float currentTemp = PACKAGE_TEMPERATURE_perPackage[0];
    if (currentTemp > kCURVE_OPTIMIZER_BLOCK_TEMP_C) {
        IOLog("AMDRyzenCPUPowerManagement: Blocked OC mode %s (0x%X) due to high package temperature (%.1f C).\n",
              enable ? "enable" : "disable", cmd, currentTemp);
        return -4;
    }

    int response = smuSendCmd(cmd, 0);

    if (response == SMU_RSP_OK) {
        smuOcModeState = enable ? 1 : 2;
        IOLog("AMDRyzenCPUPowerManagement: OC mode %s (0x%X).\n", enable ? "ENABLED" : "DISABLED", cmd);

        if (!enable && resetScalar && smuCmd.setScalar) {
            // Pass the real cache slot: setPBOLimit updates it on success.
            int scalarRc = setPBOLimit(smuCmd.setScalar, 100, pboScalarPercentX100);
            IOLog("AMDRyzenCPUPowerManagement: OC disable scalar reset (0x%X → 100): %s.\n",
                  smuCmd.setScalar, scalarRc == 0 ? "ok" : "failed");
        }
        return 0;
    }

    IOLog("AMDRyzenCPUPowerManagement: SMU OC mode command 0x%X failed with response code: 0x%X\n",
          cmd, response);
    return smuError(response);
}

// ------------------------------------------------------------------
// Frequency overrides (smuCmd.ocClkAll/ocClkPerCore; Vermeer: RSMU 0x5C all-core / 0x5D per-core).
//
//   0x5C SetOverclockFrequencyAllCores: Arg0 = MHz & 0xFFFFF.
//   0x5D SetOverclockFrequencyPerCore:  Arg0 = core mask | (MHz & 0xFFFFF).
// The cores of one CCX should run at one frequency (rsmu_commands.md), and
// a Vermeer CCD is one CCX, so a CCD is set by writing 0x5D to each of its
// cores, as ZenStates-Core SetFrequencyCCD does.
// The SMU cannot read these back: the caches hold this driver's last
// successful writes. Writes need the family's OC commands, OC mode enabled by this driver
// this boot (another tool's enable does not count) and a package below the
// thermal interlock.
// ------------------------------------------------------------------

int AMDRyzenCPUPowerManagement::setOverclockFreqAllCores(uint32_t mhz) {
    if (!smuOcSupported()) return -1;

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
    int response = smuSendCmd(smuCmd.ocClkAll, arg);

    if (response == SMU_RSP_OK) {
        ocFreqMHzAllCores = mhz;
        IOLog("AMDRyzenCPUPowerManagement: All-core freq override applied (0x5C, %u MHz).\n", mhz);
        return 0;
    }

    IOLog("AMDRyzenCPUPowerManagement: SMU 0x5C failed with response code: 0x%X\n", response);
    return smuError(response);
}

int AMDRyzenCPUPowerManagement::setOverclockFreqPerCcd(const uint32_t *mhzByCcd, uint8_t windowLen, uint8_t startCcd) {
    if (!smuOcPerCcdSupported()) return -1;

    if (!mhzByCcd || windowLen == 0 || windowLen > kOC_MAX_CCDS || startCcd >= kOC_MAX_CCDS ||
        startCcd + windowLen > kOC_MAX_CCDS) {
        IOLog("AMDRyzenCPUPowerManagement: Invalid per-CCD freq request (%u CCDs from %u).\n", windowLen, startCcd);
        return -2;
    }
    for (uint8_t i = 0; i < windowLen; i++) {
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

    // ccd counts the enabled CCDs in order; the core map gives each core's
    // physical CCD and slot. A failure stops the sequence: CCDs already
    // written keep their cache entry, the failed one does not.
    for (uint8_t i = 0; i < windowLen; i++) {
        uint32_t mhz = mhzByCcd[i];
        uint8_t ccd = (uint8_t)(startCcd + i);
        uint32_t physicalCcd = 0;
        if (!physicalCcdForIndex(ccd, physicalCcd)) {
            IOLog("AMDRyzenCPUPowerManagement: Per-CCD freq override: CCD%u does not exist.\n", ccd);
            return -2;
        }
        uint32_t written = 0;
        for (uint32_t core = 0; core < totalNumberOfPhysicalCores; core++) {
            if ((coreSmuMask[core] >> 28) != physicalCcd) continue;
            int response = smuSendCmd(smuCmd.ocClkPerCore, coreSmuMask[core] | (mhz & 0xFFFFF));
            if (response != SMU_RSP_OK) {
                IOLog("AMDRyzenCPUPowerManagement: SMU 0x5D CCD%u core %u failed, response 0x%X\n", ccd, core, response);
                return smuError(response);
            }
            written++;
        }
        ocFreqMHzPerCcd[ccd] = mhz;
        IOLog("AMDRyzenCPUPowerManagement: Per-CCD freq override applied (0x5D, CCD%u, %u cores, %u MHz).\n",
              ccd, written, mhz);
    }
    return 0;
}

// Physical CCD number of the index-th enabled CCD, from the core map.
bool AMDRyzenCPUPowerManagement::physicalCcdForIndex(uint8_t index, uint32_t &physical) const {
    if (!coreMapValid) return false;
    uint8_t seen = 0;
    for (uint32_t core = 0; core < totalNumberOfPhysicalCores; core++) {
        uint32_t ccd = coreSmuMask[core] >> 28;
        if (core > 0 && ccd == (coreSmuMask[core - 1] >> 28)) continue;
        if (seen++ == index) { physical = ccd; return true; }
    }
    return false;
}

// Program the cHTC thermal limit (smuCmd.setTctl; Vermeer: SMU 0x56, Arg0 = °C, per
// ryzen_smu rsmu_commands.md). Same capability gate and thermal interlock
// policy as the PBO limits: the family must have the command, writes blocked while
// the package is already hot. Cache updated for read-back on success.
int AMDRyzenCPUPowerManagement::setCHTCLimit(uint32_t arg) {
    if (!smuTctlSupported()) return -1;

    // Thermal safety interlock, same policy as Curve Optimizer / PBO: don't
    // push a new thermal limit while the package is already hot.
    float currentTemp = PACKAGE_TEMPERATURE_perPackage[0];
    if (currentTemp > kCURVE_OPTIMIZER_BLOCK_TEMP_C) {
        IOLog("AMDRyzenCPUPowerManagement: Blocked cHTC limit write (0x56) due to high package temperature (%.1f C).\n", currentTemp);
        return -4;
    }

    int response = smuSendCmd(smuCmd.setTctl, arg);

    if (response == SMU_RSP_OK) {
        smuCHTCLimitCelsius = arg;
        IOLog("AMDRyzenCPUPowerManagement: cHTC limit applied (0x56, %u C).\n", arg);
        return 0;
    }

    IOLog("AMDRyzenCPUPowerManagement: SMU cHTC command 0x56 failed with response code: 0x%X\n", response);
    return smuError(response);
}

// The SMU addresses a core by its physical position: CCD in [31:28], CCX in
// [27:24], core in [23:20] (ZenStates-Core Cpu.MakeCoreMask). On parts with
// fused-off cores (6-core CCDs, for example) the positions of the enabled
// cores differ from chip to chip, so they are read from the fuses exactly as
// ZenStates-Core reads them for Vermeer (Cpu.cs ReadCcdFuses/ReadCoreFuses):
//   0x5D218 [31:30]  CCD0/1 down        0x5D21C [5:0]  CCD2-7 down
//   0x30081D98 + ccd * 0x2000000, [7:0]  disabled core slots of that CCD
// The map is used only when it yields exactly the cores the OS sees; any
// disagreement leaves Curve Optimizer unavailable rather than aiming a
// voltage offset at the wrong core.
void AMDRyzenCPUPowerManagement::buildCoreMap() {
    coreMapValid = false;
    if (!mp1.supported || !smuCmd.zen3CoreFuses) return;

    uint32_t ccdPresent = smnRead32(0x5D218);
    uint32_t ccdDown = smnRead32(0x5D21C);
    if (ccdPresent == 0xFFFFFFFF || ccdDown == 0xFFFFFFFF) {
        IOLog("AMDRyzenCPUPowerManagement::buildCoreMap CCD fuses unreadable, Curve Optimizer disabled\n");
        return;
    }
    uint32_t ccdDisabled = ((ccdPresent >> 30) & 0x3) | ((ccdDown & 0x3F) << 2);
    uint32_t ccdEnabled = ~ccdDisabled & 0xFF;

    uint32_t cores = 0;
    for (uint32_t ccd = 0; ccd < 8; ccd++) {
        if (!(ccdEnabled & (1u << ccd))) continue;
        uint32_t fuse = smnRead32(0x30081D98 + ccd * 0x2000000);
        if (fuse == 0xFFFFFFFF) {
            IOLog("AMDRyzenCPUPowerManagement::buildCoreMap core fuse of CCD%u unreadable, Curve Optimizer disabled\n", ccd);
            return;
        }
        for (uint32_t slot = 0; slot < 8; slot++) {
            if (fuse & (1u << slot)) continue;
            if (cores < CPUInfo::MaxCpus) coreSmuMask[cores] = (ccd << 28) | (slot << 20);
            cores++;
        }
    }

    if (cores == 0 || cores != totalNumberOfPhysicalCores) {
        IOLog("AMDRyzenCPUPowerManagement::buildCoreMap fuses give %u cores, the OS %u; Curve Optimizer disabled\n",
              cores, totalNumberOfPhysicalCores);
        return;
    }
    coreMapValid = true;
    IOLog("AMDRyzenCPUPowerManagement::buildCoreMap %u cores, CCD map 0x%02X\n", cores, ccdEnabled);
}

// Per-core Curve Optimizer margin: smuCmd.mp1CoPerCore (Vermeer MP1 SetDldoPsmMargin 0x35) with
// arg = core mask | margin as a 16-bit two's complement value
// (ZenStates-Core SetPsmMarginSingleCore, Utils.MakePsmMarginArg).
int AMDRyzenCPUPowerManagement::setCurveOptimizer(uint8_t core, int8_t offset) {
    if (!smuCoPerCoreSupported()) return -1;

    if (core >= totalNumberOfPhysicalCores) {
        IOLog("AMDRyzenCPUPowerManagement: Invalid core index %d (max: %d).\n", core, totalNumberOfPhysicalCores - 1);
        return -2;
    }

    // Zen 3 margins span -30..+30 (ZenStates-Core).
    if (offset < -30 || offset > 30) {
        IOLog("AMDRyzenCPUPowerManagement: Offset %d outside [-30, +30], not written.\n", offset);
        return -3;
    }

    float currentTemp = PACKAGE_TEMPERATURE_perPackage[0];
    if (currentTemp > kCURVE_OPTIMIZER_BLOCK_TEMP_C) {
        IOLog("AMDRyzenCPUPowerManagement: Blocked Curve Optimizer write due to high package temperature (%.1f C).\n", currentTemp);
        return -4;
    }

    uint32_t args[kSMU_ARG_COUNT] = { coreSmuMask[core] | ((uint32_t)(int32_t)offset & 0xFFFF) };
    int response = smuExecute(mp1, smuCmd.mp1CoPerCore, args, 25000);

    if (response == SMU_RSP_OK) {
        curveOptimizerOffsets[core] = offset;
        IOLog("AMDRyzenCPUPowerManagement: Curve Optimizer core %d set to %d.\n", core, offset);
        return 0;
    }
    IOLog("AMDRyzenCPUPowerManagement: Curve Optimizer core %d failed, response 0x%X\n", core, response);
    return smuError(response);
}

// ------------------------------------------------------------------
// Precision Boost Overdrive limits, scalar, OC VID, all-core Curve
// Optimizer and boost ceiling, through the family's command set.
//
//   PPT / TDC / EDC     mW / mA / mA   (desktop)
//   STAPM / fast / slow mW             (APU: the PPT value goes to all three)
//   PBO scalar          %x100, 100..1000 => 1x..10x
//   OC VID              SVI2 VID: 1.55 V - VID * 6.25 mV, OC mode only
//   CO all-core         MP1, margin as 16-bit two's complement
//   Boost ceiling       MP1, MHz
// These are write-only SMU commands: there is no read-back, so the
// successfully-programmed values are cached for the UI in the same way as
// Curve Optimizer offsets. Every write is blocked while the package is
// above the thermal interlock.
// ------------------------------------------------------------------

int AMDRyzenCPUPowerManagement::setPBOLimit(uint32_t cmd, uint32_t arg, uint32_t &cacheSlot) {
    if (!rsmu.supported || cmd == 0) return -1;

    float currentTemp = PACKAGE_TEMPERATURE_perPackage[0];
    if (currentTemp > kCURVE_OPTIMIZER_BLOCK_TEMP_C) {
        IOLog("AMDRyzenCPUPowerManagement: Blocked SMU write 0x%X due to high package temperature (%.1f C).\n", cmd, currentTemp);
        return -4;
    }

    int response = smuSendCmd(cmd, arg);

    if (response == SMU_RSP_OK) {
        cacheSlot = arg;
        IOLog("AMDRyzenCPUPowerManagement: SMU write applied (cmd 0x%X, arg %u).\n", cmd, arg);
        return 0;
    }

    IOLog("AMDRyzenCPUPowerManagement: SMU write 0x%X failed with response code: 0x%X\n", cmd, response);
    return smuError(response);
}

int AMDRyzenCPUPowerManagement::setPowerLimits(uint32_t pptMilliwatts, uint32_t tdcMilliamps, uint32_t edcMilliamps) {
    if (smuPptLimitsSupported()) {
        int rc = setPBOLimit(smuCmd.setPpt, pptMilliwatts, pboPPTMilliwatts);
        if (rc == 0) rc = setPBOLimit(smuCmd.setTdc, tdcMilliamps, pboTDCMilliamps);
        if (rc == 0) rc = setPBOLimit(smuCmd.setEdc, edcMilliamps, pboEDCMilliamps);
        return rc;
    }
    if (smuApuLimitsSupported()) {
        uint32_t written = 0;
        int rc = setPBOLimit(smuCmd.setStapm, pptMilliwatts, written);
        if (rc == 0) rc = setPBOLimit(smuCmd.setFast, pptMilliwatts, written);
        if (rc == 0) rc = setPBOLimit(smuCmd.setSlow, pptMilliwatts, pboPPTMilliwatts);
        return rc;
    }
    return -1;
}

int AMDRyzenCPUPowerManagement::setPboScalar(uint32_t percentX100) {
    if (!smuScalarSupported()) return -1;
    return setPBOLimit(smuCmd.setScalar, percentX100, pboScalarPercentX100);
}
int AMDRyzenCPUPowerManagement::setOcVid(uint32_t vid) {
    if (!smuOcVidSupported()) return -1;
    // 16..120 = 1.45 V .. 0.80 V: nothing outside it is a sane fixed core voltage.
    if (vid < 16 || vid > 120) return -2;
    if (smuOcModeState != 1) {
        IOLog("AMDRyzenCPUPowerManagement: Blocked OC VID: OC mode not enabled by this driver this boot.\n");
        return -3;
    }
    return setPBOLimit(smuCmd.ocVid, vid, ocVidCache);
}

int AMDRyzenCPUPowerManagement::setCurveOptimizerAll(int8_t offset) {
    if (!smuCoAllSupported()) return -1;
    if (offset < -30 || offset > 30) return -2;

    float currentTemp = PACKAGE_TEMPERATURE_perPackage[0];
    if (currentTemp > kCURVE_OPTIMIZER_BLOCK_TEMP_C) {
        IOLog("AMDRyzenCPUPowerManagement: Blocked all-core Curve Optimizer due to high package temperature (%.1f C).\n", currentTemp);
        return -4;
    }

    uint32_t args[kSMU_ARG_COUNT] = { (uint32_t)(int32_t)offset & 0xFFFF };
    int response = smuExecute(mp1, smuCmd.mp1CoAll, args, 25000);
    if (response == SMU_RSP_OK) {
        curveOptimizerAllCache = offset;
        curveOptimizerAllSet = true;
        // The all-core margin replaces every per-core one.
        for (uint32_t core = 0; core < CPUInfo::MaxCpus; core++) curveOptimizerOffsets[core] = offset;
        IOLog("AMDRyzenCPUPowerManagement: Curve Optimizer all cores set to %d.\n", offset);
        return 0;
    }
    IOLog("AMDRyzenCPUPowerManagement: all-core Curve Optimizer failed, response 0x%X\n", response);
    return smuError(response);
}

int AMDRyzenCPUPowerManagement::setBoostLimit(uint32_t mhz) {
    if (!smuBoostLimitSupported()) return -1;
    if (mhz < 400 || mhz > 8000) return -2;

    float currentTemp = PACKAGE_TEMPERATURE_perPackage[0];
    if (currentTemp > kCURVE_OPTIMIZER_BLOCK_TEMP_C) {
        IOLog("AMDRyzenCPUPowerManagement: Blocked boost ceiling due to high package temperature (%.1f C).\n", currentTemp);
        return -4;
    }

    uint32_t args[kSMU_ARG_COUNT] = { mhz };
    int response = smuExecute(mp1, smuCmd.mp1BoostLimit, args, 10000);
    if (response == SMU_RSP_OK) {
        boostLimitMHzCache = mhz;
        IOLog("AMDRyzenCPUPowerManagement: boost ceiling set to %u MHz.\n", mhz);
        return 0;
    }
    IOLog("AMDRyzenCPUPowerManagement: boost ceiling failed, response 0x%X\n", response);
    return smuError(response);
}

void AMDRyzenCPUPowerManagement::updatePackageTemp(){
    float sum = 0;
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
        // Once per boot: this runs on every tick, up to 20 times a second.
        static bool loggedEnergyReadFailure = false;
        if (!loggedEnergyReadFailure) {
            loggedEnergyReadFailure = true;
            IOLog("AMDRyzenCPUPowerManagement::updatePackageEnergy: failed to read MSR 0xC001029B\n");
        }
        return;
    }

    uint32_t energyValue = (uint32_t)(msr_value_buf & 0xffffffff);

    if (!pwrEnergySeeded) {
        lastUpdateEnergyValue = energyValue;
        pwrLastTSC = ctsc;
        pwrEnergySeeded = true;
        return;
    }

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

#pragma mark - P-State & Debug

void AMDRyzenCPUPowerManagement::dumpPstate(bool canLog){
    readPstateDefs(canLog);
    decodePstateClocks(canLog);
}

// Integer only: also runs inside rendezvous handlers.
void AMDRyzenCPUPowerManagement::readPstateDefs(bool canLog){
    uint8_t len = 0;
    for (uint32_t i = 0; i < kMSR_PSTATE_LEN; i++) {
        uint64_t msr_value_buf = 0;
        bool err = !read_msr(kMSR_PSTATE_0 + i, &msr_value_buf);
        if (err) {
            if (canLog) IOLog("AMDRyzenCPUPowerManagement::dumpPstate failed to read MSR 0x%X\n", kMSR_PSTATE_0 + i);
            continue;
        }

        PStateDef_perCore[i] = msr_value_buf;
        if(msr_value_buf & ((uint64_t)1 << 63)) len++;
    }

    PStateEnabledLen = (len <= kMSR_PSTATE_LEN) ? len : (uint8_t)kMSR_PSTATE_LEN;
}

// Thread context only (floating point).
void AMDRyzenCPUPowerManagement::decodePstateClocks(bool canLog){
    for (uint32_t i = 0; i < kMSR_PSTATE_LEN; i++) {
        uint32_t eax = (uint32_t)(PStateDef_perCore[i] & 0xffffffff);

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
                if (canLog && !loggedDumpPstateDfsZero) {
                    loggedDumpPstateDfsZero = true;
                    IOLog("AMDRyzenCPUPowerManagement::dumpPstate: curCpuDfsId is zero, clamping clock to 0\n");
                }
                clock = 0.0f;
            } else {
                clock = (float)((float)curCpuFid / (float)curCpuDfsId * 200.0);
            }
        }

        PStateDefClock_perCore[i] = clock;
    }
}

void AMDRyzenCPUPowerManagement::reinitHwState() {
    uint32_t cpuid_eax = 0;
    uint32_t cpuid_ebx = 0;
    uint32_t cpuid_ecx = 0;
    uint32_t cpuid_edx = 0;

    CPUInfo::getCpuid(0x80000007, 0, &cpuid_eax, &cpuid_ebx, &cpuid_ecx, &cpuid_edx);
    cpbSupported = (cpuid_edx >> 9) & 0x1;

    // Probe CPPC support: read CAP1 MSR. All Zen families (17h/19h/1Ah) support CPPC.
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

    // MSR CPPC: probe the registers rather than trusting CPUID 8000_0008h
    // EBX[27]. rdmsr_carefully fails on an MSR the CPU does not implement,
    // and CAP1 must hold a real perf range. Ryzen 5000 desktop parts (0x21)
    // have neither the bit nor the MSRs; their CPPC is ACPI's (acpiCppc).
    uint64_t cppcEnableProbe = 0, cppcReqProbe = 0;
    const uint32_t capHighest = (uint32_t)((cppcVal >> 24) & 0xFF);
    const uint32_t capLowest = (uint32_t)(cppcVal & 0xFF);
    cppcMsrSupported = cppcSupported && msrSuccess
        && capHighest != 0 && capLowest != 0 && capLowest <= capHighest
        && read_msr(kMSR_AMD_CPPC_ENABLE, &cppcEnableProbe)
        && read_msr(kMSR_AMD_CPPC_REQ, &cppcReqProbe);

    // Firmware (boot) or S3 (wake) left CPPC_ENABLE in its reset state, so
    // the next applyEPPControl() must write it again.
    cppcEngaged = false;

    // -amdcppcactive engages CPPC autonomous mode from boot, before the app
    // runs; the app then sends the EPP it wants. The first tick applies it.
    // On wake the flag keeps whatever the app last chose.
    if (!serviceInitialized && checkKernelArgument("-amdcppcactive")) {
        cppcActiveMode = cppcEppSupported();
    }
    IOLog("AMDRyzenCPUPowerManagement::reinitHwState: MSR CPPC %s, ACPI CPPC %s, active mode %s\n",
          cppcMsrSupported ? "available" : "unavailable", acpiCppc.supported ? "available" : "unavailable",
          cppcActiveMode ? "on" : "off");

    uint64_t rapl = 0;
    if (read_msr(kMSR_RAPL_PWR_UNIT, &rapl)) {
        uint8_t energyStatusUnits = (rapl >> 8) & 0x1f;
        pwrEnergyUnit = 1.0 / (double)(1ULL << energyStatusUnits);
    } else {
        static bool loggedRaplFallback = false;
        if (!loggedRaplFallback) {
            loggedRaplFallback = true;
            IOLog("AMDRyzenCPUPowerManagement::reinitHwState WARN: failed to read MSR_RAPL_POWER_UNIT, using default 1/2^16 energy unit\n");
        }
        pwrEnergyUnit = 1.0 / (double)(1ULL << 16);
    }

    // CORE_ENERGY_STAT exists from Zen 1 on, but a hypervisor may not pass
    // it through; the SMC plugin publishes core power only when it reads.
    uint64_t coreEnergy = 0;
    coreEnergySupported = read_msr(kMSR_CORE_ENERGY_STAT, &coreEnergy);

    dumpPstate();
}

void AMDRyzenCPUPowerManagement::writePstate(const uint64_t *buf){
    // Selector 15 reaches here without the legacyPstateAllowed
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

    // Vet the definitions once, here in thread context, with the same
    // 400 MHz floor in integer form: Zen 5 runs at FID * 5 MHz, earlier
    // families at FID / DfsId * 200 MHz. The rendezvous only writes.
    uint32_t writeMask = 0;
    for (uint32_t i = 0; i < kMSR_PSTATE_LEN; i++) {
        uint64_t def = buf[i];
        if (!def) continue;
        if (cpuFamily >= 0x1A) {
            uint64_t curCpuFid = (def & 0xfff);
            if (curCpuFid < 80) continue;
        } else {
            uint64_t curCpuDfsId = ((def >> 8) & 0x3f);
            uint64_t curCpuFid = (def & 0xff);
            if (curCpuDfsId == 0 || curCpuFid == 0 || curCpuFid < 2 * curCpuDfsId) continue;
        }
        writeMask |= (1u << i);
    }

    struct WritePstateArgs {
        AMDRyzenCPUPowerManagement *provider;
        const uint64_t *defs;   // kMSR_PSTATE_LEN entries
        uint32_t mask;
    } args{this, buf, writeMask};

    IOLockLock(rendezvousLock);
    mp_rendezvous(nullptr, [](void *obj) {
        auto a = static_cast<WritePstateArgs*>(obj);
        auto provider = a->provider;

        for (uint32_t i = 0; i < kMSR_PSTATE_LEN; i++) {
            if (a->mask & (1u << i)) provider->write_msr(kMSR_PSTATE_0 + i, a->defs[i]);
        }

        if(!pmRyzen_cpu_is_master((uint32_t)cpu_number())) return;
        provider->readPstateDefs(false);
    }, nullptr, &args);
    decodePstateClocks(true);
    IOLockUnlock(rendezvousLock);
}

#pragma mark - Super IO & Fan Control

bool AMDRyzenCPUPowerManagement::initSuperIO(uint16_t *chipIntel, bool allowUnlock){
    if (!superIOLock) return false;

    IOLockLock(superIOLock);
    if (superIO) { delete superIO; superIO = nullptr; }
    // The FxAc keys read this cache without the lock; until the new chip
    // (if any) is read, they report 0 like the old locked read did.
    for (size_t i = 0; i < kMAX_FANS; i++) fanRPMCache[i] = 0;
    // Pass allowUnlock to NCT668X to prevent unprivileged firmware unlock
    if(!superIO) superIO = ISSuperIONCT668X::getDevice(&savedSMCChipIntel, allowUnlock);
    // Only privileged callers may clear the NCT67XX I/O-space lock.
    if(!superIO) superIO = ISSuperIONCT67XXFamily::getDevice(&savedSMCChipIntel, allowUnlock);
    // Only privileged callers may write the IT86XXE 16-bit tachometer enable register (0x0c).
    if(!superIO) superIO = ISSuperIOIT86XXEFamily::getDevice(&savedSMCChipIntel, allowUnlock);

    if (chipIntel) {
        *chipIntel = savedSMCChipIntel;
    }

    // Reset last applied PWM state on SuperIO re-probe
    for (size_t i = 0; i < kMAX_FANS; i++) {
        lastAppliedPWM[i] = 0;
        lastPWMUpdateTime[i] = 0;
        lastPWMAssertMs[i] = 0;
    }
    fanTelemetryLastMs = 0;
    // Reset per-curve hysteresis state on re-probe
    for (int i = 0; i < MAX_FAN_CURVES; i++) {
        lastAppliedTemp[i] = 0.0f;
        lastAppliedTempSeeded[i] = false;
    }

    bool ok = (superIO != nullptr);
    IOLockUnlock(superIOLock);
    return ok;
}

// Caller holds controlLock (selector 61) or runs on the work loop (resume).
bool AMDRyzenCPUPowerManagement::setC6Idle(bool on){
    if (on && !c6IdleSupported()) return false;
    c6IdleActive = on;
    pmRyzen_set_c6_port(on ? (uint32_t)cstateIoBase + 1 : 0);
    IOLog("AMDRyzenCPUPowerManagement: CC6 idle %s\n", on ? "on" : "off");
    return true;
}

uint32_t AMDRyzenCPUPowerManagement::getPMPStateLimit(){
    return pmRyzen_pstatelimit;
}

void AMDRyzenCPUPowerManagement::setPMPStateLimit(uint32_t state){
    uint32_t safeState = state < 2 ? state : 2;
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

// After a wake: the chip re-applies what its probe set up (16-bit
// tachometers, I/O-space lock, EC enable), the tachometers are read afresh
// and every curve fan is written on the next tick whatever it held before
// sleep, since firmware may have taken the headers back. Manual duties come
// back with the app's next selector 95 write.
void AMDRyzenCPUPowerManagement::resumeSuperIO() {
    if (!superIOLock) return;
    IOLockLock(superIOLock);
    if (superIO) {
        superIO->resume();
        fanTelemetryLastMs = 0;
        for (size_t i = 0; i < kMAX_FANS; i++) {
            lastPWMAssertMs[i] = 0;
        }
    }
    IOLockUnlock(superIOLock);
}

void AMDRyzenCPUPowerManagement::refreshFanTelemetryIfStale() {
    if (!superIO) return;
    uint64_t now = getCurrentTimeNs() / 1000000;
    if (fanTelemetryLastMs != 0 && now - fanTelemetryLastMs < kFAN_TELEMETRY_MIN_INTERVAL_MS) return;
    fanTelemetryLastMs = now;
    // RPMs first: under firmware control the duty register reads 0 and
    // updateFanControl() estimates the duty from the tachometer just read.
    superIO->updateFanRPMS();
    superIO->updateFanControl();

    int fans = superIO->getNumberOfFans();
    for (int i = 0; i < (int)kMAX_FANS; i++) {
        fanRPMCache[i] = (i < fans && superIO->getFanRPMValid(i)) ? superIO->getRPMForFan(i) : 0;
    }
}

int AMDRyzenCPUPowerManagement::fanCount() {
    if (!superIOLock) return 0;
    IOLockLock(superIOLock);
    int n = superIO ? superIO->getNumberOfFans() : 0;
    IOLockUnlock(superIOLock);
    if (n < 0) n = 0;
    if (n > (int)kMAX_FANS) n = (int)kMAX_FANS;
    return n;
}

uint32_t AMDRyzenCPUPowerManagement::fanRPM(int fan) {
    if (fan < 0 || fan >= (int)kMAX_FANS) return 0;
    return fanRPMCache[fan];
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

    // 2. Smooth temperature per curve once before evaluating fan loop
    //
    // The EMA is validated on both input and output.
    //  - A non-finite or out-of-range sample is never fed into the filter; it
    //    is dropped and the slot unseeded, so the next good sample re-seeds
    //    at once instead of crawling back over ~11 s from a poisoned value.
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

    const int fanCount = superIO->getNumberOfFans();
    for (int fanIdx = 0; fanIdx < fanCount && fanIdx < (int)kMAX_FANS; fanIdx++) {
        int8_t curveIdx = fanToCurveMap[fanIdx];
        if (curveIdx < 0 || curveIdx >= MAX_FAN_CURVES) {
            continue; // Default BIOS Auto control
        }

        FanCurveConfig &config = fanCurves[curveIdx];

        // Trust gate. curveSmoothedValid[] is published by the EMA stage;
        // false means neither the configured source nor the CPU fallback
        // produced a reading inside the valid Zen window this tick, so the
        // fan gets the audible failsafe duty instead of lut[0].
        if (!curveSmoothedValid[curveIdx]) {
            superIO->overrideFanControl(fanIdx, kFAILSAFE_PWM);
            lastAppliedPWM[fanIdx] = kFAILSAFE_PWM;
            lastPWMAssertMs[fanIdx] = 0;
            lastAppliedTempSeeded[curveIdx] = false;
            lastPWMUpdateTime[fanIdx] = now;
            continue;
        }

        float rawSourceTemp = curveRawSourceTemp[curveIdx];
        float smoothed = curveSmoothedTemp[curveIdx];

        // The emergency guard is a system-wide limit, so it is armed from the
        // hottest trustworthy sensor, not from the curve's own source: a cool
        // GPU curve must not hold a 95 C CPU at a low duty.
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
            // Track downward hysteresis against the temperature where PWM was last applied,
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
        // PWM 0 keeps its special meaning ("hand this fan back
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

        // 8. Apply PWM override to the Super I/O chip. An unchanged duty
        // is only written again every kFAN_REASSERT_MS (see lastPWMAssertMs).
        const uint64_t nowMs = now / 1000000;
        const bool mustWrite = lastPWMAssertMs[fanIdx] == 0
            || targetPWM != lastAppliedPWM[fanIdx]
            || nowMs - lastPWMAssertMs[fanIdx] >= kFAN_REASSERT_MS;
        if (targetPWM == 0) {
            if (mustWrite) {
                superIO->setDefaultFanControl(fanIdx);
                lastPWMAssertMs[fanIdx] = nowMs ? nowMs : 1;
            }
            lastAppliedPWM[fanIdx] = 0;
            lastAppliedTempSeeded[curveIdx] = false;
        } else {
            if (mustWrite) {
                superIO->overrideFanControl(fanIdx, targetPWM);
                lastPWMAssertMs[fanIdx] = nowMs ? nowMs : 1;
            }
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
    // It is not safe to hot-unload AMDRyzenCPUPowerManagement while PM dispatch, SMU timers, or SuperIO fan curves are active!
    return KERN_FAILURE;
}
