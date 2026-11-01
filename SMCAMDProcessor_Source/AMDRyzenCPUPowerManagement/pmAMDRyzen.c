//
//  pmAMDRyzen.c
//  AMDRyzenCPUPowerManagement
//
//  Created by trulyspinach, modified by Droga (2026) on 3/27/20.
//

#include "pmAMDRyzen.h"

#include <pexpert/pexpert.h>
#include <architecture/i386/pio.h>

x86_lcpu_t *pmRyzen_cpunum_to_lcpu[XNU_MAX_CPU];

void *pmRyzen_io_service_handle;

pmProcessor_t pmRyzen_cpus[XNU_MAX_CPU];
uint64_t pmRyzen_tsc_freq;
uint64_t pmRyzen_effective_timetsc;

uint32_t pmRyzen_num_phys;
uint32_t pmRyzen_num_logi;

volatile uint32_t pmRyzen_c6_port = 0;
// Set once by pmRyzen_init: legacy P-state stepping is allowed (Zen 1/2).
static uint32_t pmRyzen_pstate_control = 0;

uint64_t pmRyzen_p_sdtsc;
uint64_t pmRyzen_p_sutsc;

uint32_t pmRyzen_hpcpus = 0;
volatile uint32_t pmRyzen_pstatelimit;

void(*pmRyzen_pmUnRegister)(pmDispatch_t*) = 0;

pmDispatch_t pmRyzen_cpuFuncs = {
    .pmCPUStateInit = 0,
    .cstateInit = 0,
    .MachineIdle = &pmRyzen_machine_idle,
    .GetDeadline = 0,
    .SetDeadline = 0,
    .Deadline = 0,
    .exitIdle = 0,
    .markCPURunning = 0,
    .pmCPUControl = 0,
    .pmCPUHalt = 0,
    .getMaxSnoop = 0,
    .setMaxBusDelay = 0,
    .getMaxBusDelay = 0,
    .setMaxIntDelay = 0,
    .getMaxIntDelay = 0,
    .pmCPUSafeMode = 0,
    .pmTimerStateSave = 0,
    .pmTimerStateRestore = 0,
    .exitHalt = 0,
    .exitHaltToOff = 0,
    .markAllCPUsOff = 0,
    .pmSetRunCount = 0,
    .pmIsCPUUnAvailable = 0,
    .pmChooseCPU = &pmRyzen_choose_cpu,
    .pmIPIHandler = 0,
    .pmThreadTellUrgency = 0,
    .pmActiveRTThreads = 0,
    .pmInterruptPrewakeApplicable = 0,
    .pmThreadGoingOffCore = 0,
};

#pragma mark - P-State Initialization

void pmRyzen_init_PState(void){
    // P1 = 80% of P0 by default. Override via boot-arg `amdpp1ratio=0.75` etc.
    static float p1_ratio = 0.0f;
    if (p1_ratio == 0.0f) {
        uint32_t bootRatio = 0;
        PE_parse_boot_argn("amdpp1ratio", &bootRatio, sizeof(bootRatio));
        p1_ratio = (bootRatio > 0 && bootRatio <= 100) ? (float)bootRatio / 100.0f : 0.80f;
    }

    uint64_t p0 = pmRyzen_rdmsr_safe(pmRyzen_io_service_handle, MSR_PSTATE_0);
    if (!(p0 & (1ULL << 63))) return;

    uint64_t p0dfsid = (p0 >> 8) & 0x3f;
    if (p0dfsid == 0) return;

    float p0spd = ((float)(p0 & 0xff) / (float)p0dfsid) * 200.0f;

    uint64_t p1 = pmRyzen_rdmsr_safe(pmRyzen_io_service_handle, MSR_PSTATE_0 + 1);
    uint64_t p1dfsid = (p1 >> 8) & 0x3f;
    if (p1dfsid == 0) return;

    uint32_t fid_raw = (uint32_t)((p0spd * p1_ratio) / 200.0f * (float)p1dfsid);
    if (fid_raw > 0xFF) fid_raw = 0xFF;
    if (fid_raw < 0x10) fid_raw = 0x10;
    uint64_t p1fid = (uint64_t)fid_raw;

    pmRyzen_wrmsr_safe(pmRyzen_io_service_handle, MSR_PSTATE_0 + 1, (p1 & ~0xFFULL) | p1fid | (1ULL << 63));
}

static inline void set_PState(pmProcessor_t *cpu, uint8_t state){
    // Zen 3+ never writes MSR_PSTATE_CTL, whatever PPM/LPM ask for.
    if(!pmRyzen_pstate_control || pmRyzen_pstatelimit == 0) return;
    if (state >= 8) state = 7;
    if (state > pmRyzen_pstatelimit) state = (uint8_t)pmRyzen_pstatelimit;
    if(cpu->PState == state) return;

    boolean_t from_hpstate = !cpu->PState;

    pmRyzen_wrmsr_safe(pmRyzen_io_service_handle, MSR_PSTATE_CTL, state);
    cpu->PState = state;

    if(!state){
        __asm__ volatile("lock incl (%0)"::"r"(&pmRyzen_hpcpus):"memory");
    } else if(from_hpstate) {
        __asm__ volatile("lock decl (%0)"::"r"(&pmRyzen_hpcpus):"memory");
    }
}

void pmRyzen_doPState_reset(void *arg){
    uint32_t cn = (uint32_t)cpu_number();
    // This rendezvous runs on EVERY CPU. Every other entry point
    // guards cn against XNU_MAX_CPU; on >64-logical-CPU systems the unguarded
    // index wrote past pmRyzen_cpus[] with interrupts disabled.
    if (cn >= XNU_MAX_CPU) return;
    pmProcessor_t *self = &pmRyzen_cpus[cn];
    self->PState = 8;
    set_PState(self, 0);
}

void pmRyzen_PState_reset(void){
    if (!pmRyzen_pstate_control) return;
    pmRyzen_hpcpus = 0;
    if(pmRyzen_pstatelimit == 0) pmRyzen_pstatelimit = 1;
    mp_rendezvous_no_intrs(&pmRyzen_doPState_reset, NULL);
}

#pragma mark - Init / Stop

void pmRyzen_init(void *handle, int allowDispatch, int pstateControl){

    pmRyzen_io_service_handle = handle;
    pmRyzen_c6_port = 0;
    pmRyzen_pstate_control = (allowDispatch && pstateControl) ? 1 : 0;
    IOLog("AMDRyzenCPUPowerManagement::pmRyzen_init sizeof(pmProcessor_t) = %lu bytes (cacheline aligned)\n", (unsigned long)sizeof(pmProcessor_t));


    if (!pmRyzen_symtable._pmDispatch || !pmRyzen_symtable._pmUnRegister ||
        !pmRyzen_symtable._tscFreq) {
        IOLog("pmRyzen_init: critical symbols not resolved, aborting\n");
        return;
    }

    void **kernelDisp = pmRyzen_symtable._pmDispatch;
    pmRyzen_pmUnRegister = (void(*)(pmDispatch_t*))pmRyzen_symtable._pmUnRegister;
    pmRyzen_tsc_freq = *((uint64_t*)pmRyzen_symtable._tscFreq);

    pmCallBacks_t cb;
    if (allowDispatch) {
        if(*kernelDisp)(*pmRyzen_pmUnRegister)(*kernelDisp);
        pmKextRegister(PM_DISPATCH_VERSION, &pmRyzen_cpuFuncs, &cb);
    } else {
        pmKextRegister(PM_DISPATCH_VERSION, NULL, &cb);
    }

    x86_pkg_t * pkg = cb.GetPkgRoot();

    pmRyzen_num_phys = 0;
    pmRyzen_num_logi = 0;
    pmRyzen_hpcpus = 0;
    pmRyzen_pstatelimit = PSTATE_LIMIT;

    while(pkg){
        x86_core_t *core = pkg->cores;

        while (core) {
            pmRyzen_num_phys++;
            x86_lcpu_t *lcpu = core->lcpus;

            while (lcpu) {
                pmRyzen_num_logi++;
                if (lcpu->cpu_num >= XNU_MAX_CPU) {
                    static boolean_t loggedMaxCpu = FALSE;
                    if (!loggedMaxCpu) {
                        loggedMaxCpu = TRUE;
                        IOLog("AMDRyzenCPUPowerManagement ERR: System has CPU %u beyond limit %u. Cores beyond limit will not be managed.\n", lcpu->cpu_num, XNU_MAX_CPU);
                    }
                    lcpu = lcpu->next_in_core;
                    continue;
                }

                pmRyzen_cpunum_to_lcpu[lcpu->cpu_num] = lcpu;

                pmProcessor_t *cpu = &pmRyzen_cpus[lcpu->cpu_num];
                cpu->lcpu = lcpu;
                cpu->cpu_awake = 1;

                lcpu = lcpu->next_in_core;
            }

            core = core->next_in_pkg;
        }

        pkg = pkg->next;
    }

    pmRyzen_effective_timetsc = ((double)pmRyzen_tsc_freq * EFF_INTERVAL);
    pmRyzen_p_sdtsc = (uint64_t)((double)pmRyzen_effective_timetsc * PSTATE_STEPDOWN_THRE);
    pmRyzen_p_sutsc = (uint64_t)((double)pmRyzen_effective_timetsc * PSTATE_STEPUP_THRE);

    if (pmRyzen_pstate_control) {
        pmRyzen_init_PState();
        pmRyzen_PState_reset();
    }

    cb.initComplete();
}

void pmRyzen_stop(void){
    // Back to hlt first: no core may enter CC6 through a port the kext no
    // longer owns. A core already idling returns on its next interrupt.
    pmRyzen_c6_port = 0;

    if (pmRyzen_pmUnRegister) {
        (*pmRyzen_pmUnRegister)(&pmRyzen_cpuFuncs);
    }
}

void pmRyzen_set_c6_port(uint32_t port){
    pmRyzen_c6_port = port;
}



#pragma mark - Load & Idle

float pmRyzen_avgload_pcpu(uint32_t cpu){
    if (cpu >= XNU_MAX_CPU || !pmRyzen_cpunum_to_lcpu[cpu]) return 0.0f;
    float loadacc = 0;
    int num_lcpus = 0;

    x86_lcpu_t *lcpu = pmRyzen_cpunum_to_lcpu[cpu]->core->lcpus;
    while (lcpu) {
        if (lcpu->cpu_num < XNU_MAX_CPU) {
            float idle_ratio = (pmRyzen_cpus[lcpu->cpu_num].eff_timeaccd > 0)
                ? (float)pmRyzen_cpus[lcpu->cpu_num].eff_idleaccd / (float)pmRyzen_cpus[lcpu->cpu_num].eff_timeaccd
                : 0.0f;
            loadacc += 1.0f - idle_ratio;
            num_lcpus++;
        }
        lcpu = lcpu->next_in_core;
    }

    if (num_lcpus == 0) return 0.0f;
    return loadacc / (float)num_lcpus;
}


volatile uint32_t pmRyzen_last_woken_cpu=0;
uint64_t pmRyzen_machine_idle(uint64_t maxDur){

    __asm__ volatile("cli;");

    uint32_t cn = (uint32_t)cpu_number();
    if (cn >= XNU_MAX_CPU) {
        __asm__ volatile("sti;hlt;");
        return 0;
    }
    pmProcessor_t *self = &pmRyzen_cpus[cn];

    self->cpu_awake = 0;

    uint64_t tscnow = rdtsc64();

    self->last_idle_tsc = tscnow;

    const uint32_t c6Port = pmRyzen_c6_port;
    if (c6Port) {
        // CC6 entry; returns once an interrupt is pending, which sti then serves.
        (void)inb((uint16_t)c6Port);
        __asm__ volatile("sti;");
    } else {
        __asm__ volatile("sti;hlt;");
    }

    self->cpu_awake = 1;

    tscnow = rdtsc64();

    uint64_t tscela = tscnow - self->last_idle_tsc;
    self->eff_timeacc += tscnow - self->last_start_tsc;
    self->eff_idleacc += tscela;

    if(self->eff_timeacc > pmRyzen_effective_timetsc){
        // Busy time in TSC ticks against integer thresholds: no floating
        // point here, the idle path must not touch the FPU/XMM state.
        uint64_t rt = self->eff_timeacc - self->eff_idleacc;

        if(rt > pmRyzen_p_sutsc){
            set_PState(self, 0);
            self->ll_count = 0;
        } else if(rt < pmRyzen_p_sdtsc){
            self->ll_count++;
            if(self->ll_count > PSTATE_STEPDOWN_TIME + pmRyzen_hpcpus * PSTATE_STEPDOWN_MP_GAIN){
                self->ll_count = 0;
                set_PState(self, self->PState+1);
            }
        }

        self->eff_idleaccd = self->eff_idleacc;
        self->eff_timeaccd = self->eff_timeacc;
        self->eff_timeacc = 0;
        self->eff_idleacc = 0;
    }

    self->last_start_tsc = tscnow;

    pmRyzen_last_woken_cpu = cn;
    return 0;
}

#pragma mark - CPU Selection

// pmChooseCPU contract (osfmk/i386/pmCPU.c): pick a CPU in [startCPU, endCPU]
// of the processor set being scheduled, or return preferredCPU unchanged.
// Prefer an awake CPU so a wakeup does not have to leave hlt.
int pmRyzen_choose_cpu(int startCPU, int endCPU, int preferredCPU){
    if (preferredCPU >= 0 && preferredCPU < XNU_MAX_CPU
        && pmRyzen_cpunum_to_lcpu[preferredCPU]
        && pmRyzen_cpus[preferredCPU].cpu_awake)
        return preferredCPU;

    const int lastWoken = (int)pmRyzen_last_woken_cpu;
    if (lastWoken >= startCPU && lastWoken <= endCPU
        && lastWoken < XNU_MAX_CPU
        && pmRyzen_cpunum_to_lcpu[lastWoken]
        && pmRyzen_cpus[lastWoken].cpu_awake)
        return lastWoken;

    return preferredCPU;
}

pmProcessor_t* pmRyzen_get_processor(uint32_t cpu){
    if (cpu >= XNU_MAX_CPU) return NULL;
    return &pmRyzen_cpus[cpu];
}
