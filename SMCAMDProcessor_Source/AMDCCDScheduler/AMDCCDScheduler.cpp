//
//  AMDCCDScheduler.cpp
//  Keeps the threads of one process on one CCD (one L3) on Ryzen CPUs with several CCDs.
//
//  xnu builds one processor set (pset) per last-level cache on x86, so a 2-CCD Ryzen has two psets.
//  Where a thread starts its search for a CPU is decided by choose_starting_pset():
//    - a thread that ran before starts in the pset of its last processor, wherever that was;
//    - a new thread goes to choose_next_pset(task->pset_hint): the NEXT pset, on purpose;
//    - task->pset_hint is rewritten by thread_setrun() after every placement of any thread of the
//      task, so it follows whichever thread was placed last and flips between the CCDs.
//  Threads that talk to each other therefore end up on both CCDs and every cache-line hand-off
//  crosses the Infinity Fabric (~155 ns round trip instead of ~65 ns on a 5900XT).
//
//  This Lilu plugin wraps choose_starting_pset(). Mode 1 (default) gives each process a fixed home
//  pset the first time it is seen (the pset xnu itself chose for the process, which alternates
//  between processes) and starts every placement of its threads there, as an affinity set shared by
//  the whole process would, but only while the home pset has an idle primary (physical) core, the
//  test choose_processor_smt() makes first. When the home CCD has none the kernel's choice stands,
//  so an all-core job still spreads over both CCDs.
//  Realtime threads, threads with an explicit affinity set and kernel_task threads are left alone.
//  Mode 2 is the 0.1.0 behaviour (only a thread's first placement, towards task->pset_hint), kept
//  for comparisons. Mode 0 calls the original only.
//
//  The hook is installed only if the function's bytes match the layout it was written against
//  (macOS 26.7.3, 25G342, xnu-12377.161.15). On any other kernel it stays off and says why in
//  sysctl debug.ccd_log.
//
//  Boot-args: -ccdoff (do not load), -ccddbg (Lilu debug log), ccdmode=0|1|2 (start mode, default 1).
//  sysctls:   debug.ccd_mode (rw, root), debug.ccd_state, debug.ccd_stat, debug.ccd_log (read).
//

#include <Headers/plugin_start.hpp>
#include <Headers/kern_api.hpp>
#include <sys/sysctl.h>

// ---- Layout, from the 25G342 kernel (IDA/Hex-Rays of _choose_starting_pset) ----------------------
static constexpr size_t kThreadAffinitySet  = 0x570;  // thread->affinity_set
static constexpr size_t kThreadLastProc     = 0x4b8;  // thread->last_processor
static constexpr size_t kThreadSchedPri     = 0x434;  // thread->sched_pri (int16)
static constexpr size_t kTaskPsetHint       = 0x68;   // task->pset_hint
static constexpr size_t kPsetId             = 0x0;    // pset->pset_id (read as uint32 by the kernel)
static constexpr size_t kPsetOnlineCount    = 0x8;    // pset->online_processor_count (int)
static constexpr size_t kNodePsetMap        = 0x18;   // pset_node->pset_map (uint64)
// Per-pset CPU maps (bit = cpu_id), as choose_processor_smt() reads them to find an idle primary core:
static constexpr size_t kPsetRecommended    = 0x30;   // pset->recommended_bitmask
static constexpr size_t kPsetIdleCpus       = 0x58;   // pset->cpu_state_map[PROCESSOR_IDLE] (pset_update_processor_state)
static constexpr size_t kPsetPrimaryMap     = 0x70;   // pset->primary_map (processor_set_primary clears SMT siblings)
static constexpr int16_t kBasePriRtQueues   = 97;     // BASEPRI_RTQUEUES

// Bytes of _choose_starting_pset that must match; 0x100 = "any byte" (relative displacements).
// Offset 0x00: prologue and the affinity_set / last_processor / get_threadtask / pset_hint loads.
static const uint16_t kSigHead[] = {
    0x55, 0x48, 0x89, 0xe5, 0x41, 0x57, 0x41, 0x56, 0x53, 0x50,         // push rbp; mov rbp,rsp; push r15,r14,rbx,rax
    0x48, 0x8b, 0x86, 0x70, 0x05, 0x00, 0x00,                           // mov rax,[rsi+0x570]
    0x48, 0x85, 0xc0, 0x74, 0x0c,                                       // test rax,rax; jz
    0x48, 0x8b, 0x40, 0x38,                                             // mov rax,[rax+0x38]  aset_pset
    0x45, 0x31, 0xc0,                                                   // xor r8d,r8d
    0xe9, 0x100, 0x100, 0x100, 0x100,                                   // jmp out
    0x4c, 0x8b, 0x86, 0xb8, 0x04, 0x00, 0x00,                           // mov r8,[rsi+0x4b8]
    0x4d, 0x85, 0xc0, 0x74, 0x09,                                       // test r8,r8; jz
    0x49, 0x8b, 0x40, 0x28,                                             // mov rax,[r8+0x28]  processor_set
    0xe9, 0x100, 0x100, 0x100, 0x100,                                   // jmp out
    0x48, 0x89, 0xfb, 0x49, 0x89, 0xd6, 0x49, 0x89, 0xf7, 0x48, 0x89, 0xf7,  // save args; rdi = thread
    0xe8, 0x100, 0x100, 0x100, 0x100,                                   // call _get_threadtask (checked below)
    0x4c, 0x8b, 0x48, 0x68,                                             // mov r9,[rax+0x68]  pset_hint
};
static constexpr size_t kCallOff = 0x43;  // e8 rel32 of the get_threadtask call

struct SigAt { size_t off; uint8_t bytes[11]; size_t len; };
static const SigAt kSigMore[] = {
    { 0x90,  {0x48, 0x8b, 0x88, 0x90, 0x08, 0x00, 0x00, 0x48, 0x8b, 0x59, 0x18}, 11 },  // pset->node, node->pset_map
    { 0xd1,  {0x42, 0x83, 0x7c, 0x19, 0x08, 0x00}, 6 },                                // cmp online_processor_count,0
    { 0xde,  {0x48, 0x8b, 0x4f, 0x18, 0x44, 0x8b, 0x08}, 7 },                          // node->pset_map; pset_id
    { 0x11b, {0x66, 0x83, 0xbe, 0x34, 0x04, 0x00, 0x00, 0x61}, 8 },                    // cmp sched_pri,97
    { 0x20e, {0x49, 0x39, 0x40, 0x28, 0x75, 0x03, 0x4c, 0x89, 0x02}, 9 },              // out: hint only if its pset is the result
};

// _choose_processor_smt + 0x201: mov rbx,[r13+0x30]; mov r8,[r13+0x58]; mov r9,[r13+0x70]; mov rax,r9; and rax,r8
// (idle primary cores of the starting pset). The hook reads the same three fields.
static constexpr size_t kSmtSigOff = 0x201;
static const uint8_t kSmtSig[] = {0x49, 0x8b, 0x5d, 0x30, 0x4d, 0x8b, 0x45, 0x58, 0x4d, 0x8b, 0x4d, 0x70,
                                  0x4c, 0x89, 0xc8, 0x4c, 0x21, 0xc0};

// ---- State ---------------------------------------------------------------------------------------
using choose_starting_pset_t = void *(*)(void *node, void *thread, void **processor_hint);
using get_threadtask_t = void *(*)(void *thread);
using cpu_number_t = int (*)(void);

static choose_starting_pset_t gOrg;
static get_threadtask_t gGetThreadTask;
static cpu_number_t gCpuNumber;
static void *gKernelTask;
// Psets by id, filled with every usable pset the hook sees go through the kernel's own decisions
// (the original's result and task->pset_hint). Psets are never freed. pset_array is not used: at
// install time its entry for the second pset did not hold that pset yet (first 0.2.0 boot).
static void *gSeenPset[64];
static int gMode = 1;
static int gState;          // 0 not run, 1 installed, 2 symbol missing, 3 layout mismatch, 4 route failed, 5 one pset only
static int gPsets;

// Counters. The hook runs on every placement (every wakeup), at splsched on one CPU, so each CPU
// counts in its own cache line: no shared line bouncing between the CCDs.
//   placed: placements the kext decided (user threads, not realtime, no affinity set)
//   kept:   the kernel would have started in another pset; the kext started in the home pset
//   same:   the kernel's choice already was the home pset
//   homes:  processes that got their home pset
//   full:   the home pset had no idle primary core, so the kernel's choice was kept
struct alignas(64) CpuCounters { uint64_t placed, kept, same, homes, full; };
static constexpr int kMaxCpus = 256;
static CpuCounters gCount[kMaxCpus];

// Home pset per task. One 64-bit word per slot: (task pointer << 8) | (pset_id + 1). Kernel
// pointers have their top 8 bits set, so the shift loses nothing. Lock-free (CAS on empty slots).
// gUsed holds the last second a slot was hit: a live process refreshes it (at most one write per
// second), a dead one stops, so when a probe window is full the oldest slot goes first. gUsed is
// only an eviction hint; a torn or stale value just evicts a different slot.
static constexpr size_t kSlots = 16384;
static constexpr size_t kProbe = 8;
static uint64_t gHome[kSlots];
static uint32_t gUsed[kSlots];

extern "C" uint64_t mach_absolute_time(void);
#ifndef CCD_NOW
#define CCD_NOW() mach_absolute_time()  // the user-space test build replaces the clock
#endif
static inline uint32_t epochNow() { return static_cast<uint32_t>(CCD_NOW() >> 30); }  // ~1.07 s on x86 (ns)

static char gLog[1024];
static size_t gLogLen;

static void ccdLog(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void ccdLog(const char *fmt, ...) {
    char line[160];
    va_list va;
    va_start(va, fmt);
    vsnprintf(line, sizeof(line), fmt, va);
    va_end(va);
    SYSLOG("ccd", "%s", line);
    size_t n = strlen(line);
    if (gLogLen + n + 2 > sizeof(gLog)) return;
    memcpy(gLog + gLogLen, line, n);
    gLogLen += n;
    gLog[gLogLen++] = '\n';
    gLog[gLogLen] = '\0';
}

template <typename T> static inline T fld(void *p, size_t off) { return *reinterpret_cast<T *>(reinterpret_cast<uint8_t *>(p) + off); }

static inline CpuCounters &counters() {
    int c = gCpuNumber();
    return gCount[static_cast<unsigned>(c) < kMaxCpus ? c : 0];
}

// A pset the kernel would accept as a starting pset: in this node and with CPUs online.
static inline bool psetUsable(void *node, void *pset, uint32_t *idOut) {
    if (pset == nullptr) return false;
    uint32_t id = fld<uint32_t>(pset, kPsetId);
    if (id >= 64 || !(fld<uint64_t>(node, kNodePsetMap) & (1ULL << id)) || fld<int32_t>(pset, kPsetOnlineCount) <= 0)
        return false;
    if (__atomic_load_n(&gSeenPset[id], __ATOMIC_RELAXED) != pset) __atomic_store_n(&gSeenPset[id], pset, __ATOMIC_RELAXED);
    *idOut = id;
    return true;
}

// The pset has a recommended, idle, primary CPU. Read without the pset lock, as a hint.
static inline bool idlePrimary(void *pset) {
    auto rd = [pset](size_t off) {
        return __atomic_load_n(reinterpret_cast<uint64_t *>(reinterpret_cast<uint8_t *>(pset) + off), __ATOMIC_RELAXED);
    };
    return (rd(kPsetRecommended) & rd(kPsetIdleCpus) & rd(kPsetPrimaryMap)) != 0;
}

// Returns the task's home pset id, assigning `proposed` the first time. -1 if none can be kept.
static int homeFor(void *task, int proposed, bool *assigned) {
    const uint64_t key = reinterpret_cast<uint64_t>(task) << 8;
    const size_t h = static_cast<size_t>((reinterpret_cast<uint64_t>(task) >> 4) * 0x9E3779B97F4A7C15ULL >> 50);
    const uint32_t now = epochNow();
    size_t oldest = h & (kSlots - 1);
    uint32_t oldestAge = 0;
    for (size_t j = 0; j < kProbe; j++) {
        const size_t i = (h + j) & (kSlots - 1);
        uint64_t v = __atomic_load_n(&gHome[i], __ATOMIC_RELAXED);
        if (v == 0) {
            if (proposed < 0) return -1;
            uint64_t want = key | static_cast<uint64_t>(proposed + 1);
            if (__atomic_compare_exchange_n(&gHome[i], &v, want, false, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {
                __atomic_store_n(&gUsed[i], now, __ATOMIC_RELAXED);
                *assigned = true;
                return proposed;
            }
            // Lost the race: v now holds the winner's word, check it below.
        }
        const uint32_t used = __atomic_load_n(&gUsed[i], __ATOMIC_RELAXED);
        if ((v & ~0xffULL) == key) {
            if (used != now) __atomic_store_n(&gUsed[i], now, __ATOMIC_RELAXED);
            return static_cast<int>(v & 0xff) - 1;
        }
        const uint32_t age = now - used;
        if (age > oldestAge) { oldestAge = age; oldest = i; }
    }
    if (proposed < 0) return -1;
    // Probe window full of other tasks: replace the one hit longest ago.
    __atomic_store_n(&gHome[oldest], key | static_cast<uint64_t>(proposed + 1), __ATOMIC_RELAXED);
    __atomic_store_n(&gUsed[oldest], now, __ATOMIC_RELAXED);
    *assigned = true;
    return proposed;
}
// ---- Hook ----------------------------------------------------------------------------------------
static void *ccdLegacyFirstPlacement(void *node, void *thread, void **processor_hint);

static void *ccdChooseStartingPset(void *node, void *thread, void **processor_hint) {
    const int mode = gMode;
    if (mode == 0 || thread == nullptr || fld<void *>(thread, kThreadAffinitySet) != nullptr ||
        fld<int16_t>(thread, kThreadSchedPri) >= kBasePriRtQueues) {
        return gOrg(node, thread, processor_hint);
    }
    if (mode == 2) return ccdLegacyFirstPlacement(node, thread, processor_hint);

    void *task = gGetThreadTask(thread);
    void *orig = gOrg(node, thread, processor_hint);
    if (task == nullptr || task == gKernelTask) return orig;

    CpuCounters &c = counters();
    c.placed++;

    uint32_t origId = 0;
    if (!psetUsable(node, orig, &origId)) return orig;
    uint32_t hintId = 0;
    int proposed = psetUsable(node, fld<void *>(task, kTaskPsetHint), &hintId) ? static_cast<int>(hintId)
                                                                                : static_cast<int>(origId);
    bool assigned = false;
    int home = homeFor(task, proposed, &assigned);
    if (assigned) c.homes++;
    if (home < 0 || static_cast<uint32_t>(home) == origId) {
        c.same++;
        return orig;
    }
    void *homePset = __atomic_load_n(&gSeenPset[home], __ATOMIC_RELAXED);
    uint32_t check = 0;
    if (!psetUsable(node, homePset, &check) || check != static_cast<uint32_t>(home)) return orig;
    // Pull to home only while home has an idle primary (physical) core, the same test
    // choose_processor_smt() makes first. An idle SMT sibling of a busy core does not count: when the
    // process fills its CCD (an all-core job) its threads stay where the kernel puts them.
    if (!idlePrimary(homePset)) {
        c.full++;
        return orig;
    }
    // The original may have set a processor hint inside its own pset; it does not apply to ours.
    if (processor_hint != nullptr) *processor_hint = nullptr;
    c.kept++;
    return homePset;
}

// 0.1.0: only a thread's first placement, towards the task's current pset_hint.
static void *ccdLegacyFirstPlacement(void *node, void *thread, void **processor_hint) {
    if (fld<void *>(thread, kThreadLastProc) != nullptr) return gOrg(node, thread, processor_hint);
    void *orig = gOrg(node, thread, processor_hint);
    CpuCounters &c = counters();
    c.placed++;
    void *task = gGetThreadTask(thread);
    void *home = task ? fld<void *>(task, kTaskPsetHint) : nullptr;
    uint32_t id = 0;
    if (home == nullptr || home == orig || !psetUsable(node, home, &id)) {
        c.same++;
        return orig;
    }
    c.kept++;
    return home;
}

// ---- sysctls ---------------------------------------------------------------------------------------
static int ccdModeSysctl SYSCTL_HANDLER_ARGS {
    int v = gMode;
    int err = sysctl_handle_int(oidp, &v, 0, req);
    if (err || !req->newptr) return err;
    if (v < 0 || v > 2) return EINVAL;
    gMode = v;
    return 0;
}
SYSCTL_PROC(_debug, OID_AUTO, ccd_mode, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, 0, ccdModeSysctl, "I",
            "AMDCCDScheduler: 1 keeps each process's threads on its CCD, 2 first placement only (0.1.0), 0 off");
SYSCTL_INT(_debug, OID_AUTO, ccd_state, CTLFLAG_RD | CTLFLAG_ANYBODY | CTLFLAG_LOCKED, &gState, 0,
           "AMDCCDScheduler: 0 not run, 1 installed, 2 symbol missing, 3 layout mismatch, 4 route failed, 5 one pset");

static int ccdStatSysctl SYSCTL_HANDLER_ARGS {
    uint64_t placed = 0, kept = 0, same = 0, homes = 0, full = 0;
    for (const auto &c : gCount) {
        placed += __atomic_load_n(&c.placed, __ATOMIC_RELAXED);
        kept += __atomic_load_n(&c.kept, __ATOMIC_RELAXED);
        same += __atomic_load_n(&c.same, __ATOMIC_RELAXED);
        homes += __atomic_load_n(&c.homes, __ATOMIC_RELAXED);
        full += __atomic_load_n(&c.full, __ATOMIC_RELAXED);
    }
    char buf[256];
    // Field names kept from 0.1.0 so older readers still parse: new = placed, nohint = homes. full is new in 0.2.1 (0.2.2: no idle primary core at home).
    snprintf(buf, sizeof(buf), "state %d mode %d psets %d new %llu kept %llu same %llu nohint %llu full %llu", gState, gMode,
             gPsets, placed, kept, same, homes, full);
    return sysctl_handle_string(oidp, buf, 0, req);
}
SYSCTL_PROC(_debug, OID_AUTO, ccd_stat, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_ANYBODY | CTLFLAG_LOCKED, nullptr, 0, ccdStatSysctl,
            "A", "AMDCCDScheduler counters");
static int ccdLogSysctl SYSCTL_HANDLER_ARGS { return sysctl_handle_string(oidp, gLog, 0, req); }
SYSCTL_PROC(_debug, OID_AUTO, ccd_log, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_ANYBODY | CTLFLAG_LOCKED, nullptr, 0, ccdLogSysctl,
            "A", "AMDCCDScheduler log");

// ---- Install ---------------------------------------------------------------------------------------
static bool layoutMatches(mach_vm_address_t fn, mach_vm_address_t getThreadTask, mach_vm_address_t smt) {
    const uint8_t *p = reinterpret_cast<const uint8_t *>(fn);
    for (size_t i = 0; i < arrsize(kSigHead); i++) {
        if (kSigHead[i] <= 0xff && p[i] != kSigHead[i]) {
            ccdLog("layout: byte 0x%zx is %02x, expected %02x", i, p[i], kSigHead[i]);
            return false;
        }
    }
    int32_t rel;
    memcpy(&rel, p + kCallOff + 1, sizeof(rel));
    mach_vm_address_t target = fn + kCallOff + 5 + static_cast<mach_vm_address_t>(static_cast<int64_t>(rel));
    if (target != getThreadTask) {
        ccdLog("layout: call at 0x%zx goes to 0x%llx, not get_threadtask", kCallOff, static_cast<unsigned long long>(target));
        return false;
    }
    for (const auto &s : kSigMore) {
        if (memcmp(p + s.off, s.bytes, s.len) != 0) {
            ccdLog("layout: bytes at 0x%zx differ", s.off);
            return false;
        }
    }
    if (memcmp(reinterpret_cast<const uint8_t *>(smt) + kSmtSigOff, kSmtSig, sizeof(kSmtSig)) != 0) {
        ccdLog("layout: choose_processor_smt bytes at 0x%zx differ", kSmtSigOff);
        return false;
    }
    return true;
}

static void ccdInstall(KernelPatcher &patcher) {
    PE_parse_boot_argn("ccdmode", &gMode, sizeof(gMode));
    if (gMode < 0 || gMode > 2) gMode = 1;
    sysctl_register_oid(&sysctl__debug_ccd_mode);
    sysctl_register_oid(&sysctl__debug_ccd_state);
    sysctl_register_oid(&sysctl__debug_ccd_stat);
    sysctl_register_oid(&sysctl__debug_ccd_log);

    const auto K = KernelPatcher::KernelID;
    mach_vm_address_t fn = patcher.solveSymbol(K, "_choose_starting_pset");
    patcher.clearError();
    mach_vm_address_t gtt = patcher.solveSymbol(K, "_get_threadtask");
    patcher.clearError();
    auto numPsets = reinterpret_cast<uint32_t *>(patcher.solveSymbol(K, "_sched_num_psets"));
    patcher.clearError();
    auto psetArray = reinterpret_cast<void **>(patcher.solveSymbol(K, "_pset_array"));
    patcher.clearError();
    auto kernelTask = reinterpret_cast<void **>(patcher.solveSymbol(K, "_kernel_task"));
    patcher.clearError();
    mach_vm_address_t cpuNum = patcher.solveSymbol(K, "_cpu_number");
    patcher.clearError();
    mach_vm_address_t smt = patcher.solveSymbol(K, "_choose_processor_smt");
    patcher.clearError();
    if (!fn || !gtt || !numPsets || !kernelTask || !cpuNum || !smt) {
        gState = 2;
        ccdLog("symbols: choose_starting_pset %s, get_threadtask %s, sched_num_psets %s, kernel_task %s, cpu_number %s, "
               "choose_processor_smt %s",
               fn ? "ok" : "missing", gtt ? "ok" : "missing", numPsets ? "ok" : "missing",
               kernelTask ? "ok" : "missing", cpuNum ? "ok" : "missing", smt ? "ok" : "missing");
        return;
    }

    gPsets = static_cast<int>(*numPsets);
    if (gPsets < 2) {
        gState = 5;
        ccdLog("%d processor set: one L3, nothing to keep together", gPsets);
        return;
    }
    if (gPsets > 64) {
        gState = 3;
        ccdLog("%d processor sets: more than the 64 this build handles", gPsets);
        return;
    }
    // Diagnostic only: what pset_array holds at install time (the hook does not use it).
    if (psetArray != nullptr) {
        for (int i = 0; i < gPsets && i < 4; i++) {
            void *p = psetArray[i];
            ccdLog("pset_array[%d] = %s, id %d", i, p ? "set" : "null", p ? static_cast<int>(fld<uint32_t>(p, kPsetId)) : -1);
        }
    }
    if (*kernelTask == nullptr) {
        gState = 2;
        ccdLog("kernel_task not set yet: hook not installed");
        return;
    }
    if (!layoutMatches(fn, gtt, smt)) {
        gState = 3;
        ccdLog("choose_starting_pset does not match the 25G342 layout: hook not installed");
        return;
    }

    gGetThreadTask = reinterpret_cast<get_threadtask_t>(gtt);
    gCpuNumber = reinterpret_cast<cpu_number_t>(cpuNum);
    gKernelTask = *kernelTask;
    mach_vm_address_t org = patcher.routeFunction(fn, reinterpret_cast<mach_vm_address_t>(ccdChooseStartingPset), true);
    if (patcher.getError() != KernelPatcher::Error::NoError || !org) {
        gState = 4;
        ccdLog("routeFunction failed (%d)", static_cast<int>(patcher.getError()));
        patcher.clearError();
        return;
    }
    gOrg = reinterpret_cast<choose_starting_pset_t>(org);
    gState = 1;
    ccdLog("installed: %d processor sets, mode %d", gPsets, gMode);
}

static const char *bootargOff[] {"-ccdoff"};
static const char *bootargDebug[] {"-ccddbg"};

PluginConfiguration ADDPR(config) {
    xStringify(PRODUCT_NAME),
    parseModuleVersion(xStringify(MODULE_VERSION)),
    LiluAPI::AllowNormal,
    bootargOff, arrsize(bootargOff),
    bootargDebug, arrsize(bootargDebug),
    nullptr, 0,
    KernelVersion::Sonoma,
    KernelVersion::Tahoe,
    []() { lilu.onPatcherLoadForce([](void *, KernelPatcher &patcher) { ccdInstall(patcher); }); },
};
