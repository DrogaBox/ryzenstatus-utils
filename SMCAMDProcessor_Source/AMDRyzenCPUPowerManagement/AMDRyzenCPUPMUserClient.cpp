//
//  AMDRyzenCPUPowerManagementUserClient.cpp
//  AMDRyzenCPUPowerManagement
//
//  Created by trulyspinach, modified by Droga (2026) on 2/4/20.
//

#include "AMDRyzenCPUPMUserClient.hpp"

OSDefineMetaClassAndStructors(AMDRyzenCPUPMUserClient, IOUserClient);


bool AMDRyzenCPUPMUserClient::initWithTask(task_t owningTask,
                                             void *securityToken,
                                             UInt32 type,
                                             OSDictionary *properties){
    
    if(!IOUserClient::initWithTask(owningTask, securityToken, type, properties)){
        return false;
    }
    
    token = securityToken;
    // AUDIT F-07 fix: retain our own reference to the owning task. The task_t
    // handed to initWithTask is NOT retained for us; hasPrivilege() dereferences
    // fOwningTask on every privileged call, which can race with client death
    // (use-after-free window). We balance this retain in free().
    fOwningTask = owningTask;
    task_reference(owningTask);
    
    proc_t proc = (proc_t)get_bsdtask_info(owningTask);
    if (!proc) return false;
    
    // Capture binary name for audit logging only — never use it for authorization.
    proc_name(proc_pid(proc), taskProcessBinaryName, sizeof(taskProcessBinaryName));
    taskProcessBinaryName[sizeof(taskProcessBinaryName) - 1] = '\0';
    
    // Authorization model (v3.16.1):
    // - Always allow the UserClient connection so monitoring apps (menu bar) can
    //   open the service as a normal user and read telemetry.
    // - Privilege for WRITE selectors (MSR/SMU/fan/Curve Optimizer) is enforced
    //   per-call via hasPrivilege() — root or boot-arg -amdpnopchk only.
    // - Do NOT return false for non-root here: that makes IOServiceOpen fail and
    //   the GUI shows a false "kext not found" error.
    // kauth_cred_proc_ref() increments the refcount; we must balance it with
    // kauth_cred_unref() after reading the UID to avoid a kernel memory leak.
    kauth_cred_t cred = kauth_cred_proc_ref(proc);
    bool isRoot = (proc_suser(proc) == 0 || kauth_cred_getuid(cred) == 0);
    kauth_cred_unref(&cred);
    bool isDebugBypass = checkKernelArgument("-amdpnopchk");

    if (isDebugBypass) {
        IOLog("⚠️ WARNING: -amdpnopchk boot-arg is active. Privilege checks are DISABLED.\n");
        IOLog("⚠️ WARNING: This boot-arg is FOR DEVELOPMENT ONLY. DO NOT USE IN PRODUCTION.\n");
    }

    if (isRoot || isDebugBypass) {
        IOLog("AMDRyzenCPUPMUserClient: ACCEPTED privileged pid=%d binary='%s' (root=%d debug=%d)\n",
              proc_pid(proc), taskProcessBinaryName, isRoot, isDebugBypass);
    } else {
        IOLog("AMDRyzenCPUPMUserClient: ACCEPTED read-only pid=%d binary='%s' (writes require root or -amdpnopchk)\n",
              proc_pid(proc), taskProcessBinaryName);
    }
    
    return true;
}

bool AMDRyzenCPUPMUserClient::start(IOService *provider){
    IOLog("AMDRyzenCPUPMUserClient::start\n");
    bool success = IOService::start(provider);
    if(success){
        fProvider = OSDynamicCast(AMDRyzenCPUPowerManagement, provider);
    }
    return success;
}

void AMDRyzenCPUPMUserClient::stop(IOService *provider){
    IOLog("AMDRyzenCPUPMUserClient::stop\n");
    fProvider = nullptr;
    IOService::stop(provider);
}

IOReturn AMDRyzenCPUPMUserClient::clientClose() {
    //
    // S10 KRN-03: dead-man switch.
    //
    // clientClose() is the ONLY kernel callback guaranteed to run when the
    // userspace client goes away — including SIGKILL, a crash or a force quit,
    // none of which reach AppDelegate.applicationWillTerminate and its
    // resetFansToAutoSync().
    //
    // Why this matters: a fan in manual mode has fanToCurveMap[fan] == -1, so
    // evaluateFanCurves() skips it entirely. Nothing in the kernel ever writes
    // it again, and the manual-mode thermal guard lives in the app's 1.5 s
    // timer. A crash while a fan sat at PWM 3 (~1 % duty) left that fan latched
    // at 1 % indefinitely, with no guard and no airflow.
    //
    // Handing every fan back to BIOS/SmartFan is the correct failure mode: the
    // firmware controller is always safe, never stalls and needs no client.
    // Curve-mode fans are released too — they are re-uploaded and re-mapped on
    // the next client connection (selectors 101/102).
    //
    AMDRyzenCPUPowerManagement *provider = fProvider;
    if (provider && provider->superIOLock) {
        IOLockLock(provider->superIOLock);
        if (provider->superIO) {
            int fanCount = provider->superIO->getNumberOfFans();
            for (int i = 0; i < fanCount; i++) {
                provider->fanToCurveMap[i] = -1;
                provider->superIO->setDefaultFanControl(i);
                provider->lastAppliedPWM[i] = 0;
            }
            IOLog("AMDRyzenCPUPMUserClient: clientClose released %d fan(s) to BIOS control\n", fanCount);
        }
        IOLockUnlock(provider->superIOLock);
    }

    terminate();
    return kIOReturnSuccess;
}

// AUDIT F-07 fix: balance the task_reference() taken in initWithTask(). free()
// is the final teardown point for every IOService exit path, so releasing the
// extra task reference here closes the use-after-free window in hasPrivilege().
void AMDRyzenCPUPMUserClient::free() {
    if (fOwningTask) {
        task_deallocate(fOwningTask);
        fOwningTask = nullptr;
    }
    IOUserClient::free();
}

bool AMDRyzenCPUPMUserClient::hasPrivilege(uint32_t selector){
    // Boot-arg bypass: allow writes without root when -amdpnopchk is present
    if (fProvider && fProvider->disablePrivilegeCheck) return true;
    
    // Re-validate root privilege on every call (audit B-1). This adds a small
    // per-call overhead but is negligible for write selectors that are invoked
    // infrequently (user-initiated control changes). It prevents a scenario
    // where a process opens a UserClient connection as root, then drops
    // privileges — the cached flag would incorrectly remain true.
    proc_t proc = (proc_t)get_bsdtask_info(fOwningTask);
    if (proc) {
        // Acquire + read + release — mirrors the fix in initWithTask.
        kauth_cred_t cred = kauth_cred_proc_ref(proc);
        bool privileged = (proc_suser(proc) == 0 || kauth_cred_getuid(cred) == 0);
        kauth_cred_unref(&cred);
        if (privileged)
            return true;
    }
    
    IOLog("AMDRyzenCPUPMUserClient: DENIED select %u pid=%d binary='%s' (need root or -amdpnopchk)\n",
          selector, proc_selfpid(), taskProcessBinaryName);
    return false;
}

IOReturn AMDRyzenCPUPMUserClient::externalMethod(uint32_t selector, IOExternalMethodArguments *arguments,
                                                 IOExternalMethodDispatch *dispatch,
                                                   OSObject *target, void *reference){
    AMDRyzenCPUPowerManagement *provider = fProvider;
    if (!provider) return kIOReturnNotReady;
    
    // Surface kext-load alerts at most once across concurrent UserClient connections.
    // OSCompareAndSwap makes the check-and-set atomic (audit R-6).
    if (provider->kextloadAlerts && provider->kunc_alert) {
        if (OSCompareAndSwap(0, 1, &provider->kextAlertDisplayed)) {
            unsigned int rf = 0;
            
            char buf[128];
            snprintf(buf, 128,
                     "Kext alert detected: %d",
                     provider->kextloadAlerts);
            
            (*(provider->kunc_alert))(0, 0, NULL, NULL, NULL,
                          "AMDRyzenCPUPowerManagement", buf, "Ok", "Ok and Clear Alert", "WTF?", &rf);
            if (rf == 1) {
                provider->kextloadAlerts = 0;
                OSCompareAndSwap(1, 0, &provider->kextAlertDisplayed);
            }
        }
    }
    
    provider->registerRequest();

    //
    // S10 IOK-05: centralized pre-switch validation gate.
    //
    // This driver overrides externalMethod() directly and ignores the `dispatch`
    // argument, so IOUserClient's own checkScalarInputCount /
    // checkStructureInputSize / checkScalarOutputCount /
    // checkStructureOutputSize are never applied. All ~70 cases below validate
    // by hand and are currently correct — but there is no single place a
    // reviewer can check, and each new selector re-litigates the question.
    //
    // This gate enforces the invariants that hold for EVERY selector, so an
    // omission in a future case cannot reach a memcpy.
    //
    if (arguments->structureInputSize > 0 && !arguments->structureInput) {
        IOLog("AMDRyzenCPUPMUserClient: selector %u declared %u input bytes with a null pointer\n",
              selector, (unsigned)arguments->structureInputSize);
        return kIOReturnBadArgument;
    }
    if (arguments->structureOutputSize > 0 && !arguments->structureOutput) {
        IOLog("AMDRyzenCPUPMUserClient: selector %u declared %u output bytes with a null pointer\n",
              selector, (unsigned)arguments->structureOutputSize);
        return kIOReturnBadArgument;
    }
    if (arguments->scalarInputCount > 16 || arguments->scalarOutputCount > 16) {
        // Defensive: IOKit caps these at 16, but the switch below indexes
        // scalarInput[0..1] after only checking the count for equality.
        return kIOReturnBadArgument;
    }

    switch (selector) {
            
        //Get PStateDef raw values for core 0
        case 0: {
            arguments->scalarOutputCount = 0;
            
            uint32_t requiredSize = (provider->kMSR_PSTATE_LEN) * sizeof(uint64_t);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }

            uint64_t *dataOut = (uint64_t*) arguments->structureOutput;
            uint32_t copyCount = (maxLen / sizeof(uint64_t) < provider->kMSR_PSTATE_LEN) ? (maxLen / sizeof(uint64_t)) : provider->kMSR_PSTATE_LEN;
            
            for(uint32_t i = 0; i < copyCount; i++){
                dataOut[i] = provider->PStateDef_perCore[i];
            }
            
            break;
        }
            
            
        //Get PStateDef floating point clock values for core 0
        case 1: {
            arguments->scalarOutputCount = 0;
            
            uint32_t requiredSize = (provider->kMSR_PSTATE_LEN) * sizeof(float);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;

            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }

            float *dataOut = (float*) arguments->structureOutput;
            uint32_t copyCount = (maxLen / sizeof(float) < provider->kMSR_PSTATE_LEN) ? (maxLen / sizeof(float)) : provider->kMSR_PSTATE_LEN;
            
            for(uint32_t i = 0; i < copyCount; i++){
                dataOut[i] = provider->PStateDefClock_perCore[i];
            }
            
            break;
        }
            
        case 2: {
            uint32_t numPhyCores = provider->totalNumberOfPhysicalCores;

            arguments->scalarOutputCount = 1;
            arguments->scalarOutput[0] = numPhyCores;
            
            uint32_t requiredSize = numPhyCores * sizeof(float);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;

            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }

            float *dataOut = (float*) arguments->structureOutput;
            uint32_t copyCount = (maxLen / sizeof(float) < numPhyCores) ? (maxLen / sizeof(float)) : numPhyCores;

            for(uint32_t i = 0; i < copyCount; i++){
                dataOut[i] = provider->effFreq_perCore[i];
            }
            
            break;
        }
        
        case 3: {
            arguments->scalarOutputCount = 0;
            
            uint32_t requiredSize = 1 * sizeof(float);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;

            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            float *dataOut = (float*) arguments->structureOutput;
            if (maxLen >= sizeof(float)) {
                dataOut[0] = provider->PACKAGE_TEMPERATURE_perPackage[0];
            }
            break;
        }
        
        //Get all data like this: [power, temp, pstateCur, clock_core_1, 2, 3 .....]
        //Yes, i am too lazy to write a struct
        case 4: {
            uint32_t numPhyCores = provider->totalNumberOfPhysicalCores;
            arguments->scalarOutputCount = 1;
            arguments->scalarOutput[0] = numPhyCores;   // keep the REAL count for the app

            // AUDIT F-26: cap at CPUInfo::MaxCpus — effFreq_perCore is sized [MaxCpus];
            // the un-capped loop read past the array on >64-physical-core machines (OOB
            // read / infoleak) and inflated requiredSize past every userspace buffer.
            uint32_t effectiveCores = (numPhyCores < CPUInfo::MaxCpus) ? numPhyCores : CPUInfo::MaxCpus;
            uint32_t requiredSize = (effectiveCores + 3) * sizeof(float);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;

            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }

            uint32_t copyLen = (maxLen < requiredSize) ? maxLen : requiredSize;
            float *dataOut = (float*) arguments->structureOutput;
            
            if (copyLen >= 1 * sizeof(float)) dataOut[0] = (float)provider->uniPackagePowerW;
            if (copyLen >= 2 * sizeof(float)) dataOut[1] = provider->PACKAGE_TEMPERATURE_perPackage[0];
            if (copyLen >= 3 * sizeof(float)) dataOut[2] = (float)provider->PStateCtl;
            
            uint32_t copyCount = (copyLen > 3 * sizeof(float)) ? (copyLen - 3 * sizeof(float)) / sizeof(float) : 0;
            for(uint32_t i = 0; i < copyCount; i++){
                dataOut[i + 3] = provider->effFreq_perCore[i];
            }
            
            break;
        }
            
        //Get per core raw load index
        case 5: {
            arguments->scalarOutputCount = 0;
            
            uint32_t requiredSize = 1 * sizeof(uint64_t);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;

            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }

            uint64_t *dataOut = (uint64_t*) arguments->structureOutput;
            
            if (maxLen >= sizeof(uint64_t)) {
                dataOut[0] = 0;
                uint32_t numLogCores = provider->totalNumberOfLogicalCores;
                if (numLogCores > CPUInfo::MaxCpus) {
                    numLogCores = CPUInfo::MaxCpus;
                }
                for(uint32_t i = 0; i < numLogCores; i++){
                    dataOut[0] += provider->instructionDelta_perCore[i];
                }
            }
            
            break;
        }
            
        //Get per core load index
        case 6: {
            arguments->scalarOutputCount = 0;
            
            uint32_t requiredSize = (provider->totalNumberOfPhysicalCores) * sizeof(float);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;

            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }

            float *dataOut = (float*) arguments->structureOutput;
            
            int lcpu_percore = 1;
            if (provider->totalNumberOfPhysicalCores > 0) {
                lcpu_percore = provider->totalNumberOfLogicalCores / provider->totalNumberOfPhysicalCores;
            }
            if (lcpu_percore <= 0) {
                lcpu_percore = 1;
            }
            
            uint32_t copyCount = (maxLen / sizeof(float) < provider->totalNumberOfPhysicalCores) ? (maxLen / sizeof(float)) : provider->totalNumberOfPhysicalCores;
            
            for(uint32_t i = 0; i < copyCount; i++){
                float l = pmRyzen_avgload_pcpu(i * lcpu_percore);
                dataOut[i] = l;
            }
            
            break;
        }
            
        //Get basic CPUID
        //[Family, Model, Physical, Logical, L1_perCore, L2_perCore, L3]
        case 7: {
            arguments->scalarOutputCount = 0;
            
            uint32_t requiredSize = (8) * sizeof(uint64_t);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;

            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }

            uint64_t *dataOut = (uint64_t*) arguments->structureOutput;
            uint32_t copyCount = (maxLen / sizeof(uint64_t) < 8) ? (maxLen / sizeof(uint64_t)) : 8;
            
            if (copyCount > 0) dataOut[0] = (uint64_t)provider->cpuFamily;
            if (copyCount > 1) dataOut[1] = (uint64_t)provider->cpuModel;
            if (copyCount > 2) dataOut[2] = (uint64_t)provider->totalNumberOfPhysicalCores;
            if (copyCount > 3) dataOut[3] = (uint64_t)provider->totalNumberOfLogicalCores;
            if (copyCount > 4) dataOut[4] = (uint64_t)provider->cpuCacheL1_perCore;
            if (copyCount > 5) dataOut[5] = (uint64_t)provider->cpuCacheL2_perCore;
            if (copyCount > 6) dataOut[6] = (uint64_t)provider->cpuCacheL3;
            if (copyCount > 7) dataOut[7] = (uint64_t)provider->cpuSupportedByCurrentVersion;
            
            break;
        }
        
        //Get AMDRyzenCPUPowerManagement Version String
        case 8: {
            arguments->scalarOutputCount = 0;
            
            uint32_t requiredSize = sizeof(xStringify(MODULE_VERSION));
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            char *dataOut = (char*) arguments->structureOutput;
            uint32_t copyLen = (maxLen < requiredSize) ? maxLen : requiredSize;
            for (uint32_t i = 0; i < copyLen; i++) {
                dataOut[i] = xStringify(MODULE_VERSION)[i];
            }
            
            break;
        }
        
        //Get PState
        case 9: {
            arguments->scalarOutputCount = 0;
            
            uint32_t requiredSize = 1 * sizeof(uint64_t);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            uint64_t *dataOut = (uint64_t*) arguments->structureOutput;

            if (maxLen >= sizeof(uint64_t)) {
                dataOut[0] = provider->PStateCtl;
            }
            
            break;
        }
        
        //Set PState
        case 10: {
            if(!hasPrivilege(10)) return kIOReturnNotPrivileged;
            arguments->scalarOutputCount = 0;
            arguments->structureOutputSize = 0;
            
            if(arguments->scalarInputCount != 1)
                return kIOReturnBadArgument;
            
            // controlLock protects PStateCtl + applyPowerControl as an atomic
            // critical section against concurrent UserClient calls (audit K-2).
            if (provider->controlLock) IOLockLock(provider->controlLock);
            provider->PStateCtl = (uint8_t)arguments->scalarInput[0];
            provider->applyPowerControl();
            if (provider->controlLock) IOLockUnlock(provider->controlLock);
            break;
        }

        // Zero-copy streaming structured telemetry packet (Task 1.2)
        case 100: {
            arguments->scalarOutputCount = 0;
            uint32_t requiredSize = sizeof(AMDRyzenCPUPowerManagement::CPUSensorPacket);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            if (!arguments->structureOutput || maxLen < requiredSize) {
                return kIOReturnBadArgument;
            }
            
            AMDRyzenCPUPowerManagement::CPUSensorPacket *packet = (AMDRyzenCPUPowerManagement::CPUSensorPacket*) arguments->structureOutput;
            // AUDIT F-01: zero the packet first. The trap copies out the whole
            // struct, and with fewer than 64 logical cores the tail of
            // coreFrequenciesMHz[] (plus any padding) stayed uninitialized —
            // an unprivileged kernel-heap infoleak of ~128 bytes per call.
            memset(packet, 0, sizeof(*packet));
            packet->packagePowerW = (float)provider->uniPackagePowerW;
            packet->packageTempC = provider->PACKAGE_TEMPERATURE_perPackage[0];
            packet->numLogicalCores = provider->totalNumberOfLogicalCores;
            packet->ccdCount = provider->ccdCount;
            for (uint32_t i = 0; i < 8; i++) {
                packet->ccdTemperatures[i] = (i < provider->ccdCount) ? provider->ccdTemperatures[i] : 0.0f;
            }
            for (uint32_t i = 0; i < 64 && i < provider->totalNumberOfLogicalCores; i++) {
                uint32_t phys = (provider->totalNumberOfPhysicalCores > 0)
                    ? (i % provider->totalNumberOfPhysicalCores) : i;
                packet->coreFrequenciesMHz[i] = provider->effFreq_perCore[phys];
            }
            break;
        }
            
        //Get CPB
        case 11: {
            arguments->scalarOutputCount = 0;
            
            uint32_t requiredSize = 2 * sizeof(uint64_t);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            uint64_t *dataOut = (uint64_t*) arguments->structureOutput;

            if (maxLen >= sizeof(uint64_t)) {
                dataOut[0] = (uint64_t)provider->cpbSupported;
            }
            if (maxLen >= 2 * sizeof(uint64_t)) {
                dataOut[1] = (uint64_t)provider->getCPBState();
            }
            break;
        }
        
        //Set CPB
        case 12: {
            if(!hasPrivilege(12)) return kIOReturnNotPrivileged;
            arguments->scalarOutputCount = 0;
            arguments->structureOutputSize = 0;
            
            if(arguments->scalarInputCount != 1)
                return kIOReturnBadArgument;
            
            if(!provider->cpbSupported)
                return kIOReturnNoDevice;
            
            provider->setCPBState(arguments->scalarInput[0]==1?true:false);
            
            break;
        }
            
        //Get PPM
        case 13: {
            arguments->scalarOutputCount = 0;
                
            uint32_t requiredSize = 1 * sizeof(uint64_t);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
                
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            uint64_t *dataOut = (uint64_t*) arguments->structureOutput;

            if (maxLen >= sizeof(uint64_t)) {
                dataOut[0] = (uint64_t)(provider->getPMPStateLimit() == 0 ? 0 : 1);
            }
            break;
        }
            
        //Set PPM
        case 14: {
            if(!hasPrivilege(14)) return kIOReturnNotPrivileged;
            arguments->scalarOutputCount = 0;
            arguments->structureOutputSize = 0;
                
            if(arguments->scalarInputCount != 1)
                return kIOReturnBadArgument;
                
            boolean_t enabled = arguments->scalarInput[0]==1?true:false;
            
            provider->setPMPStateLimit(enabled ? 1 : 0);
            
            break;
        }
            
        //Set PStateDef
        case 15: {
            if(!hasPrivilege(15))
                return kIOReturnNotPrivileged;
            
            if(arguments->scalarInputCount != 8)
                return kIOReturnBadArgument;
            
            
            provider->writePstate(arguments->scalarInput);
            
            break;
        }
            
        //get board info
        case 16: {
            //Let's give that one more try :)
            if(!provider->boardInfoValid)
                provider->fetchOEMBaseBoardInfo();
            
            arguments->scalarOutputCount = 1;
            arguments->scalarOutput[0] = provider->boardInfoValid ? 1 : 0;
            
            uint32_t requiredSize = 128;
            uint32_t maxLen = arguments->structureOutputSize;
            uint32_t copyLen = maxLen < requiredSize ? maxLen : requiredSize;
            arguments->structureOutputSize = copyLen;
            
            if (!arguments->structureOutput || maxLen == 0) {
                return kIOReturnBadArgument;
            }
            
            char *dataOut = (char*) arguments->structureOutput;
            memset(dataOut, 0, copyLen);
            
            if (copyLen > 0) {
                size_t vendorCopy = copyLen < 64 ? copyLen : 64;
                strlcpy(dataOut, provider->boardVendor, vendorCopy);
            }
            if (copyLen > 64) {
                size_t nameCopy = (copyLen - 64) < 64 ? (copyLen - 64) : 64;
                strlcpy(dataOut + 64, provider->boardName, nameCopy);
            }
            
            break;
        }
            
        case 17: {
            arguments->scalarOutputCount = 0;
                
            uint32_t requiredSize = 1 * sizeof(uint64_t);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
                
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            uint64_t *dataOut = (uint64_t*) arguments->structureOutput;

            if (maxLen >= sizeof(uint64_t)) {
                dataOut[0] = (uint64_t)(provider->getHPcpus());
            }
            break;
        }
        
        //Get LPM
        case 18: {
            arguments->scalarOutputCount = 0;
                
            uint32_t requiredSize = 1 * sizeof(uint64_t);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
                
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            uint64_t *dataOut = (uint64_t*) arguments->structureOutput;

            if (maxLen >= sizeof(uint64_t)) {
                dataOut[0] = (uint64_t)(provider->getPMPStateLimit() == 2 ? 1 : 0);
            }
            break;
        }
            
        //Set LPM
        case 19: {
            if(!hasPrivilege(19)) return kIOReturnNotPrivileged;
            arguments->scalarOutputCount = 0;
            arguments->structureOutputSize = 0;
                
            if(arguments->scalarInputCount != 1)
                return kIOReturnBadArgument;
                
            boolean_t enabled = arguments->scalarInput[0]==1?true:false;
            
            provider->setPMPStateLimit(enabled ? 2 : 1);
            
            break;
        }
            
        //Get CCD temperatures
        case 20: {
            uint32_t ccdCount = provider->ccdCount;
            arguments->scalarOutputCount = 1;
            arguments->scalarOutput[0] = ccdCount;
            
            uint32_t requiredSize = ccdCount * sizeof(float);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;

            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }

            float *dataOut = (float*) arguments->structureOutput;
            uint32_t copyCount = (maxLen / sizeof(float) < ccdCount) ? (maxLen / sizeof(float)) : ccdCount;
            
            // Telemetry read: individual float reads are naturally aligned and atomic on x86_64
            for(uint32_t i = 0; i < copyCount; i++){
                dataOut[i] = provider->ccdTemperatures[i];
            }
            
            break;
        }
        
        // Get CPPC Highest Performance values per logical core
        case 21: {
            uint32_t numLogicalCores = provider->totalNumberOfLogicalCores;

            arguments->scalarOutputCount = 1;
            arguments->scalarOutput[0] = provider->cppcSupported ? 1 : 0;
            
            uint32_t requiredSize = numLogicalCores * sizeof(uint8_t);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;

            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            uint8_t *dataOut = (uint8_t*) arguments->structureOutput;
            uint32_t copyLen = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            for(uint32_t i = 0; i < copyLen; i++) {
                dataOut[i] = provider->cppcHighestPerf_perCore[i];
            }
            break;
        }

        // Get C-State address configuration
        case 22: {
            arguments->scalarOutputCount = 1;
            arguments->scalarOutput[0] = provider->cstateAddrConfig;
            
            break;
        }
        
        // S2-T4: Get resolved deep C-State policy (read-only, no privilege).
        // Scalar output: [0] = 1 if the kext disables deep C-States (C6+),
        //                [1] = raw cstateAddrConfig read after the boot write.
        // Complements selector 22: apps can distinguish "0xF0 because we wrote
        // it" from "0xF0 because firmware set it" and detect pre-1.21 kexts
        // (this case absent → kIOReturnUnsupported → selector-22 fallback).
        case 34: {
            arguments->scalarOutputCount = 2;
            arguments->scalarOutput[0] = provider->disableCStates ? 1 : 0;
            arguments->scalarOutput[1] = provider->cstateAddrConfig;
            
            break;
        }
        
        // S3-B: Curve Optimizer capability report (read-only, no privilege).
        // Scalar output: [0] = 1 when the kext will accept CO writes (family
        //                 matches the Vermeer-only payload AND the SMU mailbox
        //                 reports itself supported),
        //                 0 when writes are fail-closed (other generations).
        // [1] = active SMU command ID for CO (0x3D on Vermeer, else 0),
        // [2] = minimum safe offset (-30),
        // [3] = maximum safe offset (+30).
        // Single source of truth: the app renders its CO UI from this report
        // instead of re-implementing the family gate, so a future Zen 4/5 CO
        // payload only flips this switch in the kext — no app update needed.
        case 35: {
            arguments->scalarOutputCount = 4;
            arguments->scalarOutput[0] = (provider->smuMailboxSupported() &&
                                          provider->smuCurveOptimizerCmd() != 0) ? 1 : 0;
            arguments->scalarOutput[1] = provider->smuCurveOptimizerCmd();
            arguments->scalarOutput[2] = -30;
            arguments->scalarOutput[3] = 30;
            
            break;
        }
        
        // Get CPPC Active Mode status and current EPP value
        case 23: {
            arguments->scalarOutputCount = 2;
            arguments->scalarOutput[0] = provider->cppcActiveMode ? 1 : 0;
            arguments->scalarOutput[1] = provider->cppcEPPValue;
            
            break;
        }
        
        // Set CPPC Active Mode status
        case 24: {
            if (!hasPrivilege(24))
                return kIOReturnNotPrivileged;
                
            if (arguments->scalarInputCount != 1)
                return kIOReturnBadArgument;
                
            // controlLock protects cppcActiveMode + applyEPPControl as an atomic
            // critical section against concurrent UserClient calls (audit K-2).
            if (provider->controlLock) IOLockLock(provider->controlLock);
            provider->cppcActiveMode = (arguments->scalarInput[0] == 1);
            if (provider->cppcActiveMode) {
                provider->applyEPPControl();
            }
            if (provider->controlLock) IOLockUnlock(provider->controlLock);
            
            break;
        }
        
        // Set CPPC EPP Value
        case 25: {
            if (!hasPrivilege(25))
                return kIOReturnNotPrivileged;
                
            if (arguments->scalarInputCount != 1)
                return kIOReturnBadArgument;
                
            // controlLock protects cppcEPPValue + applyEPPControl as an atomic
            // critical section against concurrent UserClient calls (audit K-2).
            if (provider->controlLock) IOLockLock(provider->controlLock);
            provider->cppcEPPValue = (uint8_t)arguments->scalarInput[0];
            if (provider->cppcActiveMode) {
                provider->applyEPPControl();
            }
            if (provider->controlLock) IOLockUnlock(provider->controlLock);
            
            break;
        }
        
        // Get CPU profile info: architecture name + capability flags.
        // Structure output: cpuArchName (16 bytes) packed as chars,
        // followed by capability flags as uint64.
        // Flags bit layout:
        //   bit 0: pmDispatchAllowed
        //   bit 1: legacyPstateAllowed
        //   bit 2: supportsCPPC
        //   bits 3-7: reserved
        case 26: {
            arguments->scalarOutputCount = 0;
            
            uint32_t nameSize = 16;
            uint32_t flagsSize = sizeof(uint64_t);
            uint32_t requiredSize = nameSize + flagsSize;
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            char *dataOut = (char*) arguments->structureOutput;
            memset(dataOut, 0, maxLen);
            
            // Copy architecture name (first 16 bytes)
            uint32_t nameCopy = (maxLen < nameSize) ? maxLen : nameSize;
            if (nameCopy > 0) {
                strlcpy(dataOut, provider->cpuArchName, nameCopy);
            }
            
            // Pack capability flags into uint64 after the name
            if (maxLen >= nameSize + flagsSize) {
                uint64_t flags = 0;
                if (provider->pmDispatchAllowed)    flags |= (1ULL << 0);
                if (provider->legacyPstateAllowed)  flags |= (1ULL << 1);
                if (provider->supportsCPPC)         flags |= (1ULL << 2);
                memcpy(dataOut + nameSize, &flags, flagsSize);
            }
            
            break;
        }
            
        // Get GPU count
        case 27: {
            arguments->scalarOutputCount = 1;
            arguments->scalarOutput[0] = provider->getGPUCount();
            break;
        }
        
        // Get GPU temperatures (integer degrees Celsius)
        // Structure output: array of UInt16 in integer degrees Celsius, one per GPU
        case 28: {
            arguments->scalarOutputCount = 0;
            uint32_t gpuCountLocal = provider->getGPUCount();
            uint32_t requiredSize = gpuCountLocal * sizeof(UInt16);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            UInt16 *dataOut = (UInt16*) arguments->structureOutput;
            uint32_t copyCount = (maxLen / sizeof(UInt16) < gpuCountLocal) ? (maxLen / sizeof(UInt16)) : gpuCountLocal;
            
            // AUDIT N-01: never emit an uninitialized element. gpuTemperatures[]
            // is zero-initialized and refreshed by the provider's command-gate
            // timer, so a plain cached copy is always fully defined (F-05 fix:
            // no live per-GPU MMIO from the caller's thread either).
            for (uint32_t i = 0; i < copyCount; i++) {
                dataOut[i] = (i < gpuCountLocal) ? provider->gpuTemperatures[i] : 0;
            }
            break;
        }
        
        // Get GPU powers (watts as float)
        // Structure output: array of float, one per GPU
        case 29: {
            arguments->scalarOutputCount = 0;
            uint32_t gpuCountLocal = provider->getGPUCount();
            uint32_t requiredSize = gpuCountLocal * sizeof(float);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            float *dataOut = (float*) arguments->structureOutput;
            uint32_t copyCount = (maxLen / sizeof(float) < gpuCountLocal) ? (maxLen / sizeof(float)) : gpuCountLocal;
            
            // AUDIT N-01: see case 28 — cached, always-initialized copy (F-05 fix).
            for (uint32_t i = 0; i < copyCount; i++) {
                dataOut[i] = (i < gpuCountLocal) ? provider->gpuPowers[i] : 0.0f;
            }
            break;
        }
        
        // Get Package C6 Residency (cumulative microseconds)
        case 31: {
            arguments->scalarOutputCount = 0;
            
            uint32_t requiredSize = sizeof(uint64_t);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            uint64_t *dataOut = (uint64_t*) arguments->structureOutput;
            if (maxLen >= sizeof(uint64_t)) {
                dataOut[0] = provider->packageC6Residency;
            }
            break;
        }
        
        // KEXT_WAVE 1.20.0 (C-1): Per-core C6 residency (%), one UInt16 per logical core.
        // Derived from the pmRyzen per-CPU idle accounting the kernel already
        // maintains (pmAMDRyzen.c: eff_idleaccd/eff_timeaccd decayed deltas).
        // Read-only, cache-free (counters are lock-free per-CPU accumulators),
        // and ABI-safe: new selector, no change to existing ones.
        case 32: {
            arguments->scalarOutputCount = 0;
            uint32_t n = pmRyzen_num_logi;
            if (n > XNU_MAX_CPU) n = XNU_MAX_CPU;
            if (n == 0) return kIOReturnNoDevice;
            
            uint32_t requiredSize = n * sizeof(UInt16);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            UInt16 *dataOut = (UInt16*) arguments->structureOutput;
            uint32_t copyCount = (maxLen / sizeof(UInt16) < n) ? (maxLen / sizeof(UInt16)) : n;
            
            for (uint32_t c = 0; c < copyCount; c++) {
                pmProcessor_t *p = pmRyzen_get_processor(c);
                if (!p) { dataOut[c] = 0; continue; }
                uint64_t idle = p->eff_idleaccd;
                uint64_t tot  = p->eff_timeaccd;
                dataOut[c] = (tot > 0) ? (UInt16)((idle * 100) / tot) : 0;
            }
            break;
        }
        
        // KEXT_WAVE 1.20.0 (C-2): Per-core instruction-retired delta (IPC input),
        // one UInt32 per logical core. instructionDelta_perCore is refreshed by
        // the provider timer (updateInstructionDelta, MSR PERF_IRPC); this
        // selector only exports the latest window. Read-only, additive (ABI-safe).
        case 33: {
            arguments->scalarOutputCount = 0;
            uint32_t n = provider->totalNumberOfLogicalCores;
            if (n > CPUInfo::MaxCpus) n = CPUInfo::MaxCpus;
            if (n == 0) return kIOReturnNoDevice;
            
            uint32_t requiredSize = n * sizeof(UInt32);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            UInt32 *dataOut = (UInt32*) arguments->structureOutput;
            uint32_t copyCount = (maxLen / sizeof(UInt32) < n) ? (maxLen / sizeof(UInt32)) : n;
            
            for (uint32_t c = 0; c < copyCount; c++) {
                dataOut[c] = (c < CPUInfo::MaxCpus)
                    ? (UInt32)min(provider->instructionDelta_perCore[c], (uint64_t)UINT32_MAX)
                    : 0;
            }
            break;
        }
        
        // Get GPU capabilities bitmask per GPU
        // Structure output: array of uint64, one per GPU
        // Bit 0: supports power reading
        case 30: {
            arguments->scalarOutputCount = 0;
            uint32_t gpuCountLocal = provider->getGPUCount();
            uint32_t requiredSize = gpuCountLocal * sizeof(uint64_t);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            uint64_t *dataOut = (uint64_t*) arguments->structureOutput;
            uint32_t copyCount = (maxLen / sizeof(uint64_t) < gpuCountLocal) ? (maxLen / sizeof(uint64_t)) : gpuCountLocal;
            
            for (uint32_t i = 0; i < copyCount; i++) {
                uint64_t caps = 0;
                if (provider->gpuSupportsPower(i)) caps |= (1ULL << 0);
                dataOut[i] = caps;
            }
            break;
        }
        
        //Try load SMC driver
        case 90: {
            // AUDIT F-03: the probe itself stays unprivileged so the read-only
            // fan list keeps working, but clearing the NCT67XX I/O-space lock
            // (a firmware protection write) is now reserved for privileged
            // callers — hasPrivilege is threaded down to the NCT67XX driver,
            // which skips the CHIP_IO_SPACE_LOCK write without it.
            bool allowUnlock = hasPrivilege(90);

            arguments->scalarOutputCount = 0;
            uint32_t requiredSize = 2 * sizeof(uint64_t);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            uint64_t *dataOut = (uint64_t*) arguments->structureOutput;
            
            // Snapshot under superIOLock (audit R-1). initSuperIO also takes the lock
            // (non-recursive) so we must not hold it across that call.
            if (provider->superIOLock) {
                IOLockLock(provider->superIOLock);
                if (provider->superIO != nullptr) {
                    if (maxLen >= sizeof(uint64_t)) {
                        dataOut[0] = (uint64_t)(1);
                    }
                    if (maxLen >= 2 * sizeof(uint64_t)) {
                        dataOut[1] = (uint64_t)(provider->savedSMCChipIntel);
                    }
                    IOLockUnlock(provider->superIOLock);
                    break;
                }
                IOLockUnlock(provider->superIOLock);
            }
            
            uint16_t ci = 0;
            bool found = provider->initSuperIO(&ci, allowUnlock);
            
            if (maxLen >= sizeof(uint64_t)) {
                dataOut[0] = (uint64_t)(found ? 1 : 0);
            }
            if (maxLen >= 2 * sizeof(uint64_t)) {
                dataOut[1] = (uint64_t)(ci);
            }
            
            break;
        }
        
        //SMC load number of fans
        case 91: {
            if (!provider->superIOLock)
                return kIOReturnNoDevice;

            uint32_t requiredSize = 1 * sizeof(uint64_t);
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) return kIOReturnBadArgument;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            uint64_t *dataOut = (uint64_t*) arguments->structureOutput;
            
            IOLockLock(provider->superIOLock);
            if (!provider->superIO) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnNoDevice;
            }
            uint32_t numFans = (uint32_t)provider->superIO->getNumberOfFans();
            IOLockUnlock(provider->superIOLock);
            
            if (maxLen >= sizeof(uint64_t)) {
                dataOut[0] = (uint64_t)numFans;
            }
            break;
        }
        
        //SMC load readable desc for fan
        case 92: {
            if (!provider->superIOLock)
                return kIOReturnNoDevice;

            arguments->scalarOutputCount = 0;
                
            if(arguments->scalarInputCount != 1)
                return kIOReturnBadArgument;
            
            uint32_t maxLen = arguments->structureOutputSize;
            if (!arguments->structureOutput || maxLen == 0) {
                arguments->structureOutputSize = 0;
                return kIOReturnBadArgument;
            }
            
            char *dataOut = (char*) arguments->structureOutput;
            char localBuf[64] = {0};
            
            IOLockLock(provider->superIOLock);
            if (!provider->superIO) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnNoDevice;
            }
            const char *str = provider->superIO->getReadableStringForFan((int)arguments->scalarInput[0]);
            if (!str) {
                str = "";
            }
            // Copy under lock so the SuperIO object cannot be deleted mid-read.
            strlcpy(localBuf, str, sizeof(localBuf));
            IOLockUnlock(provider->superIOLock);
            
            strlcpy(dataOut, localBuf, maxLen);
            arguments->structureOutputSize = (uint32_t)strlen(dataOut);
            
            break;
        }
            
        //SMC fan rpms
        case 93: {
            if (!provider->superIOLock)
                return kIOReturnNoDevice;
            
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            uint64_t *dataOut = (uint64_t*) arguments->structureOutput;
            uint32_t maxLen = arguments->structureOutputSize;
            
            IOLockLock(provider->superIOLock);
            if (!provider->superIO) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnNoDevice;
            }
            
            uint32_t numFans = (uint32_t)provider->superIO->getNumberOfFans();
            uint32_t requiredSize = numFans * sizeof(uint64_t);
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnBadArgument;
            }
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            UInt32 currentCount = (UInt32)OSIncrementAtomic(&provider->fanUpdateCounter);
            if ((currentCount % 4) == 0) {
                provider->superIO->updateFanRPMS();
            }
            uint32_t copyCount = (maxLen / sizeof(uint64_t) < numFans) ? (maxLen / sizeof(uint64_t)) : numFans;
            for (uint32_t i = 0; i < copyCount; i++) {
                dataOut[i] = provider->superIO->getRPMForFan(i);
            }
            IOLockUnlock(provider->superIOLock);
            
            break;
        }
        
        //SMC fan throttles and control mode
        case 94: {
            if (!provider->superIOLock)
                return kIOReturnNoDevice;
            
            if (!arguments->structureOutput) {
                return kIOReturnBadArgument;
            }
            
            uint64_t *dataOut = (uint64_t*) arguments->structureOutput;
            uint32_t maxLen = arguments->structureOutputSize;
            
            IOLockLock(provider->superIOLock);
            if (!provider->superIO) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnNoDevice;
            }
            
            uint32_t numFans = (uint32_t)provider->superIO->getNumberOfFans();
            uint32_t requiredSize = numFans * sizeof(uint64_t);
            // AUDIT F-16: reject undersized output buffer to prevent uninitialized kernel memory leak
            if (maxLen < requiredSize) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnBadArgument;
            }
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            UInt32 snap94 = (UInt32)OSIncrementAtomic(&provider->fanUpdateCounter);
            if ((snap94 % 4) == 0) {
                // S11-a: refresh the estimator's INPUTS in the same critical
                // section that consumes them.
                //
                // updateFanControl()'s fallback estimator — which is what
                // produces a duty reading at all while a fan is under BIOS
                // SmartFan control, since the PWM command register genuinely
                // reads 0 there — is gated on fanRPMValid[i] and
                // fanPeakRPMs[i] > 200. Both of those are written ONLY by
                // updateFanRPMS().
                //
                // fanUpdateCounter is a single shared counter and BOTH selector
                // 93 (which calls updateFanRPMS) and this one increment it, so
                // the producer and the consumer fired on different values of it
                // and could never coincide. getFans() calls 93 then 94 back to
                // back, consuming n and n+1: updateFanRPMS on n % 4 == 0 and
                // updateFanControl on (n+1) % 4 == 0 are never the same tick.
                // The only timer-driven path, evaluateFanCurves(), early-continues
                // for every fan with fanToCurveMap[fan] < 0 — i.e. every fan under
                // BIOS Auto — so nothing else ever seeded fanPeakRPMs for exactly
                // the fans that need the estimator. The guard stayed false, the
                // estimator never ran, and all six fans reported pwm 0 (0.0%)
                // while physically spinning at 40-1683 RPM.
                //
                // Pairing them here is the fix: the estimator now always sees
                // inputs written on this same tick, under this same lock. The
                // %4 gate is deliberately kept — it rate-limits Super I/O port
                // I/O, which is slow and shared with the firmware.
                provider->superIO->updateFanRPMS();
                provider->superIO->updateFanControl();
            }
            uint32_t copyCount = (maxLen / sizeof(uint64_t) < numFans) ? (maxLen / sizeof(uint64_t)) : numFans;
            for (uint32_t i = 0; i < copyCount; i++) {
                // S11-c: bit 1 carries per-fan tachometer validity.
                //
                // Wire format, per fan, one uint64_t: bits 15:8 throttle (a
                // uint8_t, so it cannot spill), bit 0 auto-control mode, bit 1
                // rpmValid, everything else zero. Bit 1 was previously written as
                // zero, and the Swift reader masks only bits 15:8 and bit 0, so an
                // OLDER app against this kext ignores the new bit and behaves
                // exactly as before. The buffer size is unchanged, so nothing in
                // the size negotiation on either side moves.
                //
                // Why it matters: the NCT drivers now hold the last good value
                // when a tach read is untrustworthy, which is safer than
                // publishing 65535 but LESS detectable — a dead sensor shows a
                // plausible frozen RPM instead of an obviously wrong one. Without
                // this bit the app has no way to tell the difference, and its own
                // `rawRPM <= 10500` heuristic can never fire because the kext
                // already filters above that threshold.
                //
                // The app-side consumption is deliberately NOT in this change: a
                // kext revision costs a hardware validation cycle and an app
                // revision costs nothing, so the expensive half ships now and the
                // Swift reader (which needs a kext-version gate so a new app does
                // not blank every fan against an old kext) follows separately.
                dataOut[i] = provider->superIO->getFanThrottle(i) << 8
                           | (provider->superIO->getFanRPMValid(i) ? 0x2 : 0)
                           | (provider->superIO->getFanAutoControlMode(i) ? 1 : 0);
            }
            IOLockUnlock(provider->superIOLock);
            
            break;
        }
        
        //SMC fan override control
        case 95: {
            if(!hasPrivilege(95))
                return kIOReturnNotPrivileged;
            
            if(arguments->scalarInputCount != 2)
                return kIOReturnBadArgument;
            
            if (!provider->superIOLock)
                return kIOReturnNoDevice;
            
            int fanSel = (int)arguments->scalarInput[0];
            uint8_t pwm = (uint8_t)arguments->scalarInput[1];
            
            // S2-T4b (defense-in-depth): every manual PWM write, from any
            // privileged process, honors the same emergency thermal guard the
            // kext applies to curve-mode fans (kTHERMAL_GUARD_TEMP_C →
            // kTHERMAL_GUARD_PWM). PACKAGE_TEMPERATURE_perPackage[0] is the
            // timer-cached snapshot refreshed by updatePackageTemp() on the
            // command-gated workloop (no live SMN/PCI read here — F-05 rule).
            // Reading it under superIOLock is safe: writers hold rendezvousLock
            // only, and the float read is atomic-enough for a clamp floor.
            if (provider->PACKAGE_TEMPERATURE_perPackage[0] >= kTHERMAL_GUARD_TEMP_C
                && pwm < kTHERMAL_GUARD_PWM) {
                pwm = kTHERMAL_GUARD_PWM;
            }
            
            IOLockLock(provider->superIOLock);
            if (!provider->superIO) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnNoDevice;
            }
            if (fanSel < 0 || fanSel >= provider->superIO->getNumberOfFans()) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnBadArgument;
            }
            // S11: floor a duty that would be commanded to a STOPPED rotor.
            //
            // The S10 floor (kCURVE_MIN_ACTIVE_PWM) lives only in
            // evaluateFanCurves(), and overrideFanControl() writes whatever byte
            // it is handed straight to the PWM register — so this privileged
            // manual path could latch a rotor at duty 1-39, below its start
            // threshold, on an open-loop controller with no RPM feedback. Below
            // 85 C the thermal guard above does not fire, so nothing caught it.
            //
            // The floor is NOT applied unconditionally, and that is the whole
            // point. The hazard is at rotor START, not at maintain: a fan the
            // BIOS is holding at duty 20 and which is demonstrably turning is
            // safe, and raising it to 40 would just make the machine louder for
            // nothing. That is exactly why the Swift side splits
            // clampManualPWM (user-commanded, floored) from guardOnlyPWM
            // (hardware-inherited, guard only) — and why a blanket floor here
            // would break the inherited path and ramp every BIOS-fixed fan on
            // the first poll.
            //
            // So the kernel decides from the evidence it has rather than from a
            // caller's claim: floor only when the tachometer is TRUSTED and says
            // the fan is not turning. When validity is unknown the reading is not
            // evidence, so behaviour is left exactly as before.
            if (pwm != 0 && pwm < kCURVE_MIN_ACTIVE_PWM
                && provider->superIO->getFanRPMValid(fanSel)
                && provider->superIO->getRPMForFan(fanSel) < kFAN_STOPPED_RPM) {
                pwm = kCURVE_MIN_ACTIVE_PWM;
            }
            provider->superIO->overrideFanControl(fanSel, pwm);
            IOLockUnlock(provider->superIOLock);
            
            break;
        }
        
        //SMC fan default control
        case 96: {
            if(!hasPrivilege(96))
                return kIOReturnNotPrivileged;
            
            if(arguments->scalarInputCount != 1)
                return kIOReturnBadArgument;
            
            if (!provider->superIOLock)
                return kIOReturnNoDevice;
            
            int fanSel = (int)arguments->scalarInput[0];
            
            IOLockLock(provider->superIOLock);
            if (!provider->superIO) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnNoDevice;
            }
            if (fanSel < 0 || fanSel >= provider->superIO->getNumberOfFans()) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnBadArgument;
            }
            provider->superIO->setDefaultFanControl(fanSel);
            IOLockUnlock(provider->superIOLock);
            
            break;
        }
        
        //SMC Secret Undocumented feature (⁎⁍̴̛ᴗ⁍̴̛⁎) - Capped at 80% PWM (0xC8) for hardware safety
        case 97: {
            if(!hasPrivilege(97))
                return kIOReturnNotPrivileged;
            
            if(arguments->scalarInputCount != 1)
                return kIOReturnBadArgument;
            
            if (!provider->superIOLock)
                return kIOReturnNoDevice;
            
            IOLockLock(provider->superIOLock);
            if (!provider->superIO) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnNoDevice;
            }
            int numFan = provider->superIO->getNumberOfFans();
            for (int i = 0; i < numFan; i++) {
                if(arguments->scalarInput[0])
                    provider->superIO->overrideFanControl(i, 0xC8);
                else
                    provider->superIO->setDefaultFanControl(i);
            }
            IOLockUnlock(provider->superIOLock);
            
            break;
        }
        
        // Read raw SuperIO register
        case 98: {
            if (!provider || !provider->superIOLock)
                return kIOReturnNoDevice;

            // AUDIT F-04: a "read" still writes the register index into the
            // chip (bank select / index outb) and can hit EC registers, so an
            // unprivileged caller must not drive it — it would race the kext's
            // own fan-control sequences. Mirror the write gate of case 99.
            if (!hasPrivilege(98))
                return kIOReturnNotPrivileged;

            if(arguments->scalarInputCount != 1)
                return kIOReturnBadArgument;
            
            uint16_t reg = (uint16_t)arguments->scalarInput[0];
            uint64_t *dataOut = (uint64_t*) arguments->structureOutput;
            uint32_t maxLen = arguments->structureOutputSize;
            
            if (!arguments->structureOutput || maxLen < sizeof(uint64_t))
                return kIOReturnBadArgument;
            
            IOLockLock(provider->superIOLock);
            if (!provider->superIO) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnNoDevice;
            }
            uint8_t val = provider->superIO->readReg(reg);
            IOLockUnlock(provider->superIOLock);
            
            dataOut[0] = val;
            arguments->structureOutputSize = sizeof(uint64_t);
            break;
        }
        
        // Write raw SuperIO register
        case 99: {
            if (!provider || !provider->superIOLock)
                return kIOReturnNoDevice;
            
            if(!hasPrivilege(99))
                return kIOReturnNotPrivileged;
            
            if(arguments->scalarInputCount != 2)
                return kIOReturnBadArgument;
            
            uint16_t reg = (uint16_t)arguments->scalarInput[0];
            uint8_t val = (uint8_t)arguments->scalarInput[1];
            
            IOLockLock(provider->superIOLock);
            if (!provider->superIO) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnNoDevice;
            }
            provider->superIO->writeReg(reg, val);
            IOLockUnlock(provider->superIOLock);
            
            break;
        }
        
        // Update fan curve LUT and parameters
        case 101: {
            if(!provider)
                return kIOReturnNoDevice;
            if(!provider->superIOLock)
                return kIOReturnNoDevice;
            
            if(!hasPrivilege(101))
                return kIOReturnNotPrivileged;
                
            #pragma pack(push, 1)
            struct FanCurveInput {
                uint32_t curveIndex;
                uint32_t sourceSensor;
                uint32_t hysteresis;
                uint32_t rampRate;
                uint8_t lut[256];
            };
            #pragma pack(pop)
            
            if (!arguments->structureInput || arguments->structureInputSize != sizeof(FanCurveInput)) {
                return kIOReturnBadArgument;
            }
            
            const FanCurveInput *input = (const FanCurveInput*) arguments->structureInput;
            uint32_t idx = input->curveIndex;
            if (idx >= MAX_FAN_CURVES) {
                return kIOReturnBadArgument;
            }
            
            uint8_t hyst = (uint8_t)input->hysteresis;
            if (hyst > 10) hyst = 10;
            uint8_t ramp = (uint8_t)input->rampRate;
            if (ramp < 1) ramp = 1;
            if (ramp > 100) ramp = 100;

            IOLockLock(provider->superIOLock);
            provider->fanCurves[idx].sourceSensor = (uint8_t)input->sourceSensor;
            provider->fanCurves[idx].hysteresis   = hyst;
            provider->fanCurves[idx].rampRate     = ramp;
            memcpy(provider->fanCurves[idx].lut, input->lut, 256);
            IOLockUnlock(provider->superIOLock);
            
            break;
        }
        
        // Map physical fan to curve
        case 102: {
            if(!provider)
                return kIOReturnNoDevice;
            
            if(!hasPrivilege(102))
                return kIOReturnNotPrivileged;
                
            if (arguments->scalarInputCount != 2) {
                return kIOReturnBadArgument;
            }
            
            int fanIdx = (int)arguments->scalarInput[0];
            int curveIdx = (int)arguments->scalarInput[1];
            
            if (fanIdx < 0 || fanIdx >= 16 || curveIdx < -1 || curveIdx >= MAX_FAN_CURVES) {
                return kIOReturnBadArgument;
            }
            if (!provider->superIOLock) {
                return kIOReturnNoDevice;
            }
            
            IOLockLock(provider->superIOLock);
            if (provider->superIO && fanIdx >= provider->superIO->getNumberOfFans()) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnBadArgument;
            }
            provider->fanToCurveMap[fanIdx] = (int8_t)curveIdx;
            // If mapping to Auto, restore default fan control
            if (curveIdx == -1 && provider->superIO) {
                provider->superIO->setDefaultFanControl(fanIdx);
            }
            IOLockUnlock(provider->superIOLock);
            
            break;
        }
        
        // Set GPU temperature (used by the app for fan-curve source).
        // Privilege required: root or boot-arg -amdpnopchk.
        // Process-name authorization was removed (audit A-01).
        // The menu-bar process should run with -amdpnopchk or as root.
        // Temperature is clamped to a safe [0, 120] °C range to prevent abuse.
        case 103: {
            if(!provider)
                return kIOReturnNoDevice;
            
            if(arguments->scalarInputCount != 1)
                return kIOReturnBadArgument;
            
            if (!hasPrivilege(103))
                return kIOReturnNotPrivileged;
            
            float t = (float)arguments->scalarInput[0];
            if (t < 0.0f) t = 0.0f;
            if (t > 120.0f) t = 120.0f;
            provider->gpuTempC = t;
            
            break;
        }
        
        // Get Curve Optimizer Offsets (Phase 13)
        case 110: {
            if(!provider)
                return kIOReturnNoDevice;
            
            uint32_t requiredSize = CPUInfo::MaxCpus;
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-12: report only what actually fits the caller's buffer.
            // IOKit forbids raising structureOutputSize beyond the supplied
            // buffer; the old line reported `requiredSize` even when the write
            // below was clamped to maxLen, so undersized callers failed the
            // trap (or, on older kernels, over-copied).
            arguments->structureOutputSize = (maxLen < requiredSize) ? maxLen : requiredSize;
            
            if (!arguments->structureOutput || maxLen < requiredSize) {
                return kIOReturnBadArgument;
            }
            
            memcpy(arguments->structureOutput, provider->curveOptimizerOffsets, requiredSize);
            break;
        }
        
        // Set Curve Optimizer Offset (Phase 13)
        case 111: {
            if(!provider)
                return kIOReturnNoDevice;
            
            if(!hasPrivilege(111))
                return kIOReturnNotPrivileged;
                
            if(arguments->scalarInputCount != 2)
                return kIOReturnBadArgument;
                
            uint8_t core = (uint8_t)arguments->scalarInput[0];
            int8_t offset = (int8_t)arguments->scalarInput[1];
            
            int rc = provider->setCurveOptimizer(core, offset);
            if (rc < 0) {
                // Map setCurveOptimizer error codes to IOReturn values.
                // -1 unsupported, -2/-3 bad args, -4 not ready,
                // -10 SMU timeout, -11 invalid SMU cmd, -12 invalid SMU args, -13 SMU busy.
                if (rc == -1 || rc == -11) return kIOReturnUnsupported;
                if (rc == -2 || rc == -3 || rc == -12) return kIOReturnBadArgument;
                if (rc == -4) return kIOReturnNotReady;
                if (rc == -10) return kIOReturnTimeout;
                if (rc == -13) return kIOReturnBusy;
                return kIOReturnError;
            }
            break;
        }
        
        // ---- S4: Precision Boost Overdrive limits + scalar (Vermeer) ----
        // Read-only selectors 36-39 report the last successfully-programmed
        // values plus the PBO capability; write selectors 41-42 program new
        // limits and are root/-amdpnopchk only.
        
        // Get PBO limits cache (mW / mA / mA) — last set this boot, 0 = never.
        case 36: {
            if(!provider)
                return kIOReturnNoDevice;
            
            arguments->scalarOutputCount = 3;
            arguments->scalarOutput[0] = provider->pboPPTMilliwatts;
            arguments->scalarOutput[1] = provider->pboTDCMilliamps;
            arguments->scalarOutput[2] = provider->pboEDCMilliamps;
            
            break;
        }
        
        // Get PBO scalar cache (%x100 — 200 means 2x), 0 = never set.
        case 37: {
            if(!provider)
                return kIOReturnNoDevice;
            
            arguments->scalarOutputCount = 1;
            arguments->scalarOutput[0] = provider->pboScalarPercentX100;
            
            break;
        }
        
        // Get PBO capability: [0] supported (Vermeer + mailbox),
        // [1..3] reserved (no verified SMU read command exists for limits —
        // the PM-table budget is not parsed; reported as 0).
        case 38: {
            if(!provider)
                return kIOReturnNoDevice;
            
            arguments->scalarOutputCount = 4;
            arguments->scalarOutput[0] = provider->pboLimitsSupported() ? 1 : 0;
            arguments->scalarOutput[1] = 0;
            arguments->scalarOutput[2] = 0;
            arguments->scalarOutput[3] = 0;
            
            break;
        }
        
        // Get PBO scalar capability: [0] supported, [1] min %x100 (100), [2] max %x100 (1000).
        case 39: {
            if(!provider)
                return kIOReturnNoDevice;
            
            arguments->scalarOutputCount = 3;
            arguments->scalarOutput[0] = provider->pboLimitsSupported() ? 1 : 0;
            arguments->scalarOutput[1] = 100;   // 1x
            arguments->scalarOutput[2] = 1000;  // 10x — matches Ryzen Master range
            
            break;
        }
        
        // Get boost telemetry snapshot (S5): [0] = max boost frequency in MHz
        // (RSMU 0x6E), [1] = raw GetFastestCoreOfSocket word (RSMU 0x59 —
        // decoded app-side in AMDSmuBoost where it is unit-testable),
        // [2] = 1 once the timer has populated the caches this boot.
        // Read-only: served from the command-gate timer cache, never a live
        // SMU read on a user thread (F-05 lesson).
        case 43: {
            if(!provider)
                return kIOReturnNoDevice;
            
            arguments->scalarOutputCount = 3;
            arguments->scalarOutput[0] = provider->smuMaxBoostFreqMHz;
            arguments->scalarOutput[1] = provider->smuFastestCoreRaw;
            arguments->scalarOutput[2] = (provider->smuMaxBoostFreqMHz != 0 ||
                                          provider->smuFastestCoreRaw != 0) ? 1 : 0;
            
            break;
        }
        
        // Get ProcessorParameters bitfield (S6): [0] = raw 0x6F response word
        // (bit 0 IsOverclockable, bit 1 PBO support — decode lives app-side in
        // AMDSmuParameters), [1] = 1 once the timer command gate has read the
        // command successfully this boot (a real 0-bitfield is a valid answer,
        // so "polled" must be distinct from the value). Read-only: served from
        // the timer cache, never a live SMU read on a user thread (F-05).
        case 44: {
            if(!provider)
                return kIOReturnNoDevice;
            
            arguments->scalarOutputCount = 2;
            arguments->scalarOutput[0] = provider->smuProcessorParametersRaw;
            arguments->scalarOutput[1] = provider->smuProcParamsPolled ? 1 : 0;
            
            break;
        }
        
        // Get cHTC limit cache (S6): [0] = the last value successfully
        // programmed via SMU 0x56 this boot in °C (0 = never set — the SMU has
        // no read command for cHTC; the kext caches on write success).
        // Read-only, no SMU traffic.
        case 45: {
            if(!provider)
                return kIOReturnNoDevice;
            
            arguments->scalarOutputCount = 1;
            arguments->scalarOutput[0] = provider->smuCHTCLimitCelsius;
            
            break;
        }
        
        // Set cHTC thermal limit (S6, privileged): [0] = target in °C, valid
        // window 40..95 (0x56 Arg0 = degrees Celsius). Privilege required,
        // same as the PBO limits; the provider enforces the Vermeer gate and
        // the package-temperature interlock.
        case 46: {
            if(!provider)
                return kIOReturnNoDevice;
            
            if(!hasPrivilege(46))
                return kIOReturnNotPrivileged;
                
            if(arguments->scalarInputCount != 1)
                return kIOReturnBadArgument;
                
            uint32_t celsius = (uint32_t)arguments->scalarInput[0];
            
            // Safety window: below 40 °C the limit could engage before the
            // package even warms up, and nothing in the Ryzen Master range
            // asks for more than 95 °C (Tjmax is 95 °C on Vermeer).
            if (celsius < 40 || celsius > 95)
                return kIOReturnBadArgument;
            
            if (!provider->pboLimitsSupported())
                return kIOReturnUnsupported;
            
            if (provider->controlLock) IOLockLock(provider->controlLock);
            int rc = provider->setCHTCLimit(celsius);
            if (provider->controlLock) IOLockUnlock(provider->controlLock);
            
            if (rc < 0) {
                if (rc == -1 || rc == -11) return kIOReturnUnsupported;
                if (rc == -4) return kIOReturnNotReady;
                if (rc == -10) return kIOReturnTimeout;
                if (rc == -13) return kIOReturnBusy;
                return kIOReturnError;
            }
            break;
        }
        
        // Get SMU firmware version (S7): [0] = raw byte-packed version word
        // (24-bit A.B.C, or 32-bit A.B.C.D when byte 3 != 0 — decoded app-side
        // in AMDSmuReadback.formatSmuVersion), [1] = 1 once the timer command
        // gate has read the command successfully this boot. Read-only: served
        // from the timer cache, never a live SMU read on a user thread (F-05).
        case 47: {
            if(!provider)
                return kIOReturnNoDevice;
            
            arguments->scalarOutputCount = 2;
            arguments->scalarOutput[0] = provider->smuFirmwareVersionRaw;
            arguments->scalarOutput[1] = provider->smuVersionPolled ? 1 : 0;
            
            break;
        }
        
        // Get active PBO scalar (S7): [0] = raw 0x6C response word (IEEE-754
        // float 1.0–10.0, decoded app-side in AMDSmuReadback — different
        // encoding than the 0x58 write), [1] = 1 once the timer has read the
        // command successfully this boot. Read-only, rides the
        // boost-telemetry throttle cache.
        case 48: {
            if(!provider)
                return kIOReturnNoDevice;
            
            arguments->scalarOutputCount = 2;
            arguments->scalarOutput[0] = provider->smuActiveScalarRaw;
            arguments->scalarOutput[1] = (provider->smuActiveScalarRaw != 0) ? 1 : 0;
            
            break;
        }
        
        // Get OC capability report (S8): [0] = 1 when the kext accepts OC-mode
        // and frequency/VID commands on this silicon (Vermeer + SMU mailbox —
        // same verdict policy as selector 38), [1] = cached ProcessorParameters
        // (0x6F) bitfield for app-side context (bit 0 IsOverclockable fuse),
        // [2] = OC-mode cache state (0 = never touched by this driver this
        // boot, 1 = enabled via 0x5A, 2 = disabled via 0x5B — the SMU has no
        // read-back, and 0 honestly means "unknown"). [3] = 1 when the kext
        // accepts frequency overrides (S8.2: 0x5C/0x5D behind the OC-mode
        // gate) — same Vermeer verdict as [0]; the app mirrors the kext's
        // fixed 8-CCD cache model. 1.28.0 shipped [3] as reserved 0, so
        // pre-1.29 apps reading 0 simply hide those controls (compatibility-
        // safe promotion).
        // Read-only: no SMU traffic, cache only.
        case 49: {
            if(!provider)
                return kIOReturnNoDevice;
            
            arguments->scalarOutputCount = 4;
            arguments->scalarOutput[0] = provider->pboLimitsSupported() ? 1 : 0;
            arguments->scalarOutput[1] = provider->smuProcessorParametersRaw;
            arguments->scalarOutput[2] = provider->smuOcModeState;
            arguments->scalarOutput[3] = provider->pboLimitsSupported() ? 1 : 0;
            
            break;
        }
        
        // Set OC mode (S8, privileged): [0] = 1 enable (RSMU 0x5A, Arg0 1) or
        // 0 disable (RSMU 0x5B, Arg0 0) — semantics pinned by ZenStates-Core,
        // resolving rsmu_commands.md's contradictory rows. [1] = reset-scalar
        // flag: when disabling with [1] = 1, the kext additionally re-programs
        // the PBO scalar to 1.0 via 0x58 (some SMU firmware does not auto-reset
        // it on leaving OC mode). Frequency (0x5C/0x5D) and VID (0x61) writes
        // are NOT in this selector — deferred until owner hardware validation.
        // Privilege required; provider enforces the Vermeer gate and the
        // package-temperature interlock.
        case 50: {
            if(!provider)
                return kIOReturnNoDevice;
            
            if(!hasPrivilege(50))
                return kIOReturnNotPrivileged;
                
            if(arguments->scalarInputCount != 2)
                return kIOReturnBadArgument;
                
            uint32_t enable = (uint32_t)arguments->scalarInput[0];
            uint32_t resetScalar = (uint32_t)arguments->scalarInput[1];
            if (enable > 1 || resetScalar > 1)
                return kIOReturnBadArgument;
            
            if (!provider->pboLimitsSupported())
                return kIOReturnUnsupported;
            
            if (provider->controlLock) IOLockLock(provider->controlLock);
            int rc = provider->setOcMode(enable == 1, resetScalar == 1);
            if (provider->controlLock) IOLockUnlock(provider->controlLock);
            
            if (rc < 0) {
                if (rc == -1 || rc == -11) return kIOReturnUnsupported;
                if (rc == -4) return kIOReturnNotReady;
                if (rc == -10) return kIOReturnTimeout;
                if (rc == -13) return kIOReturnBusy;
                return kIOReturnError;
            }
            break;
        }
        
        // Set frequency override (S8.2, privileged): [0] = mode (0 all-core
        // via 0x5C, 1 per-CCD via 0x5D), [1] = MHz for all-core mode,
        // [2..9] = per-CCD MHz (entry i targets CCD startCcd + i),
        // [10] = startCcd, [11] = CCD count for per-CCD mode (contiguous
        // window — the app applies one CCD with startCcd = ccd, count = 1).
        // Envelopes mirror the kernel: 400..8000 MHz, startCcd + count <= 8.
        // The kernel builds the 0x5D mask itself ((ccd << 28) | freq on
        // Vermeer) — user space never ships a packed mask. Hard-gated
        // kernel-side: OC mode must have been enabled by THIS driver earlier
        // this boot — refusal maps to kIOReturnNotPermitted; thermal
        // interlock maps to kIOReturnNotReady.
        // Output scalars: [0] = 0 on success, [1] = programmed MHz (all-core
        // mode) or 0, [2] = last mask/arg used (0xFFFFFFFF sentinel for
        // all-core), [3] = CCD count processed, [4..7] reserved 0.
        case 51: {
            if(!provider)
                return kIOReturnNoDevice;
            
            if(!hasPrivilege(51))
                return kIOReturnNotPrivileged;
            
            if(arguments->scalarInputCount < 2 || arguments->scalarInputCount > 11)
                return kIOReturnBadArgument;
            
            uint32_t mode = (uint32_t)arguments->scalarInput[0];
            if (mode > 1)
                return kIOReturnBadArgument;
            
            if (!provider->pboLimitsSupported())
                return kIOReturnUnsupported;
            
            int rc;
            uint32_t maskUsed = 0xFFFFFFFF;   // sentinel: all-core
            uint32_t ccdsDone = 0;
            
            if (mode == 0) {
                if (arguments->scalarInputCount != 2)
                    return kIOReturnBadArgument;
                uint32_t mhz = (uint32_t)arguments->scalarInput[1];
                rc = provider->setOverclockFreqAllCores(mhz);
                maskUsed = mhz & 0xFFFFF;
            } else {
                if (arguments->scalarInputCount != 12)
                    return kIOReturnBadArgument;
                uint32_t startCcd = (uint32_t)arguments->scalarInput[10];
                uint32_t ccdCount = (uint32_t)arguments->scalarInput[11];
                if (ccdCount == 0 || startCcd >= AMDRyzenCPUPowerManagement::kS8MaxCcds ||
                    startCcd + ccdCount > AMDRyzenCPUPowerManagement::kS8MaxCcds)
                    return kIOReturnBadArgument;
                uint32_t mhzByCcd[AMDRyzenCPUPowerManagement::kS8MaxCcds];
                for (uint8_t c = 0; c < ccdCount; c++)
                    mhzByCcd[c] = (uint32_t)arguments->scalarInput[2 + c];
                rc = provider->setOverclockFreqPerCcd(mhzByCcd, (uint8_t)ccdCount, (uint8_t)startCcd);
                if (rc == 0)
                    maskUsed = ((uint32_t)(startCcd + ccdCount - 1) << 28) | (mhzByCcd[ccdCount - 1] & 0xFFFFF);
                ccdsDone = (rc == 0) ? ccdCount : 0;
            }
            
            if (rc < 0) {
                if (rc == -1 || rc == -11) return kIOReturnUnsupported;
                if (rc == -2 || rc == -12) return kIOReturnBadArgument;
                if (rc == -3) return kIOReturnNotPermitted;   // OC gate closed
                if (rc == -4) return kIOReturnNotReady;        // thermal
                if (rc == -10) return kIOReturnTimeout;
                if (rc == -13) return kIOReturnBusy;
                return kIOReturnError;
            }
            
            arguments->scalarOutputCount = 8;
            arguments->scalarOutput[0] = 0;
            arguments->scalarOutput[1] = (mode == 0) ? (uint32_t)arguments->scalarInput[1] : 0;
            arguments->scalarOutput[2] = maskUsed;
            arguments->scalarOutput[3] = ccdsDone;
            arguments->scalarOutput[4] = 0;
            arguments->scalarOutput[5] = 0;
            arguments->scalarOutput[6] = 0;
            arguments->scalarOutput[7] = 0;
            
            break;
        }
        
        // Get frequency-override cache (S8.2, read-only): [0] = all-core
        // cache MHz (0 = never written by this driver this boot), [1] = CCD
        // count from the kext's start-time register probe (0 = probe not
        // ready or no AMD host — the app falls back to its own estimate),
        // [2..9] = per-CCD caches (array index = CCD index, 0 = never
        // written). Cache only — no SMU traffic (F-05).
        case 52: {
            if(!provider)
                return kIOReturnNoDevice;
            
            arguments->scalarOutputCount = 10;
            arguments->scalarOutput[0] = provider->ocFreqMHzAllCores;
            arguments->scalarOutput[1] = provider->ccdCount;
            for (uint8_t c = 0; c < AMDRyzenCPUPowerManagement::kS8MaxCcds; c++)
                arguments->scalarOutput[2 + c] = provider->ocFreqMHzPerCcd[c];
            
            break;
        }
        
        // Mailbox health diagnostics (S9d, privileged): runs the provider's
        // three boot-diagnostic probes on demand — SMN aperture (Tctl word),
        // TestMessage round-trip (0x01: Res0 = Arg0 + 1 → 0x43) and GetSMUVersion (0x02)
        // — and returns the full raw report through structure output so the
        // app can surface a health report without log show. Privileged
        // because it adds SMU mailbox traffic on demand (same policy as
        // selector 57 op 2); serialized under rendezvousLock like the
        // capture path. Struct layout (little-endian, 4-byte fields, 48
        // bytes total; int fields carry SMUResponse/timeout codes):
        //   [0] mailboxSupported  [1] msgReg       [2] argReg      [3] rspReg
        //   [4] curveOptimizerCmd [5] smnTctlRaw   [6] testRsp     [7] testArg0
        //   [8] testElapsedUs     [9] versionRsp  [10] versionRaw [11] versionElapsedUs
        case 58: {
            if(!provider)
                return kIOReturnNoDevice;

            if(!hasPrivilege(58))
                return kIOReturnNotPrivileged;

            AMDRyzenCPUPowerManagement::SMUDiagnosticReport report;
            if (provider->rendezvousLock) IOLockLock(provider->rendezvousLock);
            provider->runMailboxDiagnostics(report);
            if (provider->rendezvousLock) IOLockUnlock(provider->rendezvousLock);

            struct SMUDiagWire {
                uint32_t mailboxSupported;
                uint32_t msgReg;
                uint32_t argReg;
                uint32_t rspReg;
                uint32_t curveOptimizerCmd;
                uint32_t smnTctlRaw;
                int32_t  testRsp;
                uint32_t testArg0;
                uint32_t testElapsedUs;
                int32_t  versionRsp;
                uint32_t versionRaw;
                uint32_t versionElapsedUs;
            };
            static_assert(sizeof(SMUDiagWire) == 48, "SMU diagnostic wire layout must stay 48 bytes");
            SMUDiagWire wire{};
            wire.mailboxSupported  = report.mailboxSupported;
            wire.msgReg            = report.msgReg;
            wire.argReg            = report.argReg;
            wire.rspReg            = report.rspReg;
            wire.curveOptimizerCmd = report.curveOptimizerCmd;
            wire.smnTctlRaw        = report.smnTctlRaw;
            wire.testRsp           = (int32_t)report.testRsp;
            wire.testArg0          = report.testArg0;
            wire.testElapsedUs     = report.testElapsedUs;
            wire.versionRsp        = (int32_t)report.versionRsp;
            wire.versionRaw        = report.versionRaw;
            wire.versionElapsedUs  = report.versionElapsedUs;

            // AUDIT F-12/F-16: report only what fits the caller's buffer.
            if (arguments->structureOutput == nullptr || arguments->structureOutputSize < sizeof(SMUDiagWire))
                return kIOReturnBadArgument;
            memcpy(arguments->structureOutput, &wire, sizeof(SMUDiagWire));
            arguments->structureOutputSize = sizeof(SMUDiagWire);
            arguments->scalarOutputCount = 0;
            break;
        }

        // Get PM-table info (S9a, read-only): [0] = table version word
        // (0x08 response, BCD-style e.g. 0x380904 → 38.09.04), [1] = version
        // polled flag, [2] = documented size in bytes for that version
        // (0 = unknown version — fail closed), [3] = physical base low 32,
        // [4] = physical base high 32, [5] = snapshot valid flag, [6] =
        // snapshot age in ms (0 = never captured). Cache only — no SMU
        // traffic (F-05); unsupported on pre-1.30 kexts.
        case 56: {
            if(!provider)
                return kIOReturnNoDevice;

            if (provider->rendezvousLock) IOLockLock(provider->rendezvousLock);
            arguments->scalarOutputCount = 8;
            arguments->scalarOutput[0] = provider->pmTableVersionRaw;
            arguments->scalarOutput[1] = provider->pmTableVersionPolled ? 1 : 0;
            arguments->scalarOutput[2] = provider->pmTableSize;
            arguments->scalarOutput[3] = (uint32_t)(provider->pmDramBase & 0xFFFFFFFF);
            arguments->scalarOutput[4] = (uint32_t)(provider->pmDramBase >> 32);
            arguments->scalarOutput[5] = provider->pmMapValid ? 1 : 0;
            {
                uint64_t nowMs = 0;
                if (provider->pmTableCapturedMs != 0) {
                    nowMs = getCurrentTimeNs() / 1000000;
                }
                arguments->scalarOutput[6] = (provider->pmTableCapturedMs != 0 && nowMs > provider->pmTableCapturedMs)
                    ? (uint64_t)(nowMs - provider->pmTableCapturedMs) : 0;
            }
            arguments->scalarOutput[7] = 0;
            if (provider->rendezvousLock) IOLockUnlock(provider->rendezvousLock);

            break;
        }

        // PM-table raw access (S9a): op 1 = read a chunk of the snapshot
        // (structure output; [0] = byte offset, clamped so offset+count stay
        // inside the captured table — never reads past pmTableSize, never
        // touches the SMU); op 2 = force an immediate capture cycle (0x08
        // once, then 0x05 → 0x06 → map → copy), privileged because it adds
        // SMU mailbox traffic on demand.
        case 57: {
            if(!provider)
                return kIOReturnNoDevice;

            uint32_t op = (arguments->scalarInputCount >= 1)
                ? (uint32_t)arguments->scalarInput[0] : 1;

            if (op == 2) {
                if(!hasPrivilege(57))
                    return kIOReturnNotPrivileged;

                if (provider->rendezvousLock) IOLockLock(provider->rendezvousLock);
                int rc = provider->forcePMTableCapture();
                if (provider->rendezvousLock) IOLockUnlock(provider->rendezvousLock);

                IOLog("AMDRyzenCPUPMUserClient: selector 57 op 2 (forcePMTableCapture) pid=%d rc=%d\n",
                      proc_selfpid(), rc);

                if (rc < 0) {
                    if (rc == -1 || rc == -11) return kIOReturnUnsupported;
                    if (rc == -14) return kIOReturnUnsupported;   // unknown table version
                    if (rc == -15) return kIOReturnIOError;
                    if (rc == -10) return kIOReturnTimeout;
                    if (rc == -13) return kIOReturnBusy;
                    return kIOReturnError;
                }
                arguments->scalarOutputCount = 1;
                arguments->scalarOutput[0] = 0;
                break;
            }

            if (op != 1)
                return kIOReturnBadArgument;

            // op 1: chunked snapshot read. Serialize against the timer's
            // capture path so callers never observe a partially-copied buffer.
            arguments->scalarOutputCount = 0;
            if (provider->rendezvousLock) IOLockLock(provider->rendezvousLock);

            uint32_t offset = (arguments->scalarInputCount == 2)
                ? (uint32_t)arguments->scalarInput[1] : 0;
            uint32_t tableSize = provider->pmTableSize;
            if (!provider->pmMapValid || tableSize == 0) {
                if (provider->rendezvousLock) IOLockUnlock(provider->rendezvousLock);
                return kIOReturnNotReady;
            }
            if (offset >= tableSize) {
                if (provider->rendezvousLock) IOLockUnlock(provider->rendezvousLock);
                return kIOReturnBadArgument;
            }

            uint32_t available = tableSize - offset;
            uint32_t maxLen = arguments->structureOutputSize;
            // AUDIT F-16: reject undersized output buffers; AUDIT F-12:
            // report only what actually fits.
            if (maxLen == 0 || arguments->structureOutput == nullptr) {
                if (provider->rendezvousLock) IOLockUnlock(provider->rendezvousLock);
                return kIOReturnBadArgument;
            }
            uint32_t copyCount = (maxLen < available) ? maxLen : available;
            arguments->structureOutputSize = copyCount;
            memcpy(arguments->structureOutput, provider->pmTableSnapshot + offset, copyCount);

            if (provider->rendezvousLock) IOLockUnlock(provider->rendezvousLock);
            break;
        }

        // Set PBO limits: PPT mW, TDC mA, EDC mA. Privilege required.
        case 41: {
            if(!provider)
                return kIOReturnNoDevice;
            
            if(!hasPrivilege(41))
                return kIOReturnNotPrivileged;
                
            if(arguments->scalarInputCount != 3)
                return kIOReturnBadArgument;
                
            uint32_t ppt = (uint32_t)arguments->scalarInput[0];
            uint32_t tdc = (uint32_t)arguments->scalarInput[1];
            uint32_t edc = (uint32_t)arguments->scalarInput[2];
            
            // Hard safety envelope: reject limits outside 1000..500000
            // milli-units (1..500 W for PPT, 1..500 A for TDC/EDC) — nothing
            // the silicon could have shipped with falls outside this band.
            if (ppt < 1000 || ppt > 500000 || tdc < 1000 || tdc > 500000 || edc < 1000 || edc > 500000)
                return kIOReturnBadArgument;
            
            if (!provider->pboLimitsSupported())
                return kIOReturnUnsupported;
            
            // Serialize the three writes; abort on first failure so the UI
            // never shows a half-applied set as success.
            if (provider->controlLock) IOLockLock(provider->controlLock);
            int rc = provider->setPBOLimit(0x53, ppt, provider->pboPPTMilliwatts);
            if (rc == 0) rc = provider->setPBOLimit(0x54, tdc, provider->pboTDCMilliamps);
            if (rc == 0) rc = provider->setPBOLimit(0x55, edc, provider->pboEDCMilliamps);
            if (provider->controlLock) IOLockUnlock(provider->controlLock);
            
            if (rc < 0) {
                if (rc == -1 || rc == -11) return kIOReturnUnsupported;
                if (rc == -4) return kIOReturnNotReady;
                if (rc == -10) return kIOReturnTimeout;
                if (rc == -13) return kIOReturnBusy;
                return kIOReturnError;
            }
            break;
        }
        
        // Set PBO scalar: %x100 (100..1000). Privilege required.
        case 42: {
            if(!provider)
                return kIOReturnNoDevice;
            
            if(!hasPrivilege(42))
                return kIOReturnNotPrivileged;
                
            if(arguments->scalarInputCount != 1)
                return kIOReturnBadArgument;
                
            uint32_t scalar = (uint32_t)arguments->scalarInput[0];
            if (scalar < 100 || scalar > 1000)
                return kIOReturnBadArgument;
            
            if (!provider->pboLimitsSupported())
                return kIOReturnUnsupported;
            
            if (provider->controlLock) IOLockLock(provider->controlLock);
            int rc = provider->setPBOLimit(0x58, scalar, provider->pboScalarPercentX100);
            if (provider->controlLock) IOLockUnlock(provider->controlLock);
            
            if (rc < 0) {
                if (rc == -1 || rc == -11) return kIOReturnUnsupported;
                if (rc == -4) return kIOReturnNotReady;
                if (rc == -10) return kIOReturnTimeout;
                if (rc == -13) return kIOReturnBusy;
                return kIOReturnError;
            }
            break;
        }
        
        default: {
            IOLog("AMDRyzenCPUPMUserClient::externalMethod: invalid selector %u\n", selector);
            return kIOReturnUnsupported;
        }
    }
    
    return kIOReturnSuccess;
}
