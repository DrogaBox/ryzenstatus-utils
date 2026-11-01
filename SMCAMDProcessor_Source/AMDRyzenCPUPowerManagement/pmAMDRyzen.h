//
//  pmAMDRyzen.h
//  AMDRyzenCPUPowerManagement
//
//  Created by trulyspinach, modified by Droga (2026) on 3/27/20.
//

#ifndef pmAMDRyzen_h
#define pmAMDRyzen_h


#include <Headers/mach/mach_types.h>
#include <IOKit/IOLib.h>

#include "Headers/osfmk/i386/pmCPU.h"
#include "Headers/osfmk/i386/cpu_topology.h"

#include "symresolver/kernel_resolver.h"

#include <i386/proc_reg.h>
#include "Headers/pmRyzenSymbolTable.h"

#define MOD_NAME pmARyzen
#define XNU_MAX_CPU 64

// Idle entry: sti; hlt (CC1), or, while pmRyzen_c6_port is non-zero, a byte
// read of that IO port, which the core turns into a CC6 entry (the SystemIO
// C2 entry of AMD's ACPI _CST: CstateAddr + 1). The read returns once an
// interrupt is pending, with interrupts still masked, like the SystemIO path
// of Linux's acpi_idle.

#define MSR_PSTATE_CTL 0xC0010062
#define MSR_PSTATE_0 0xC0010064

#define EFF_INTERVAL 0.15
#define PSTATE_LIMIT 1
#define PSTATE_STEPDOWN_THRE 0.12
#define PSTATE_STEPUP_THRE 0.38
#define PSTATE_STEPDOWN_TIME 16
#define PSTATE_STEPDOWN_MP_GAIN 5


extern int cpu_number(void);
extern void mp_rendezvous_no_intrs(void (*action_func)(void *), void *arg);

extern x86_lcpu_t *pmRyzen_cpunum_to_lcpu[XNU_MAX_CPU];

extern uint32_t pmRyzen_num_phys;
extern uint32_t pmRyzen_num_logi;

// CC6 entry port, 0 = CC1 (hlt). Written by the kext, read on every idle entry.
extern volatile uint32_t pmRyzen_c6_port;


#pragma mark - Idle Strategy
extern uint32_t pmRyzen_hpcpus;

extern volatile uint32_t pmRyzen_pstatelimit;


extern void pmRyzen_wrmsr_safe(void *, uint32_t, uint64_t);
extern uint64_t pmRyzen_rdmsr_safe(void *, uint32_t);
extern pmRyzen_symtable_t pmRyzen_symtable;


typedef struct __attribute__((aligned(64))) pmProcessor {
    // Cache Line 1: idle & TSC tracking
    x86_lcpu_t *lcpu;
    uint64_t cpu_awake;
    uint64_t last_idle_tsc;
    uint64_t last_start_tsc;

    // Load accumulators & P-state control
    uint64_t eff_timeacc;
    uint64_t eff_idleacc;
    uint64_t eff_timeaccd;
    uint64_t eff_idleaccd;
    uint32_t ll_count;
    uint8_t PState;
} pmProcessor_t;

// allowDispatch: take over the kernel's idle loop (MachineIdle, pmChooseCPU).
// pstateControl: also step legacy P-states from it (Zen 1/2 only: Zen 3+
// must never write MSR_PSTATE_CTL).
void pmRyzen_init(void*, int allowDispatch, int pstateControl);
void pmRyzen_stop(void);
// Every later idle entry goes to CC6 through `port`, or to CC1 with 0.
void pmRyzen_set_c6_port(uint32_t port);
void pmRyzen_PState_reset(void);
float pmRyzen_avgload_pcpu(uint32_t);

uint64_t pmRyzen_machine_idle(uint64_t);

int pmRyzen_choose_cpu(int,int,int);

pmProcessor_t* pmRyzen_get_processor(uint32_t);

static inline uint32_t pmRyzen_cpu_phys_num(uint32_t cpunum){
    if (cpunum >= XNU_MAX_CPU || !pmRyzen_cpunum_to_lcpu[cpunum] ||
        !pmRyzen_cpunum_to_lcpu[cpunum]->core) return 0;
    return pmRyzen_cpunum_to_lcpu[cpunum]->core->pcore_num;
}

static inline uint32_t pmRyzen_cpu_primary_in_core(uint32_t cpunum){
    if (cpunum >= XNU_MAX_CPU || !pmRyzen_cpunum_to_lcpu[cpunum] ||
        !pmRyzen_cpunum_to_lcpu[cpunum]->core) return 0;
    return pmRyzen_cpunum_to_lcpu[cpunum]->core->lcpus == pmRyzen_cpunum_to_lcpu[cpunum];
}

static inline boolean_t pmRyzen_cpu_is_master(uint32_t cpunum){
    if (cpunum >= XNU_MAX_CPU || !pmRyzen_cpunum_to_lcpu[cpunum]) return FALSE;
    return pmRyzen_cpunum_to_lcpu[cpunum]->master;
}


#endif /* pmAMDRyzen_h */
