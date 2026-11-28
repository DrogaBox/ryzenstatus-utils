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
//  The hook is installed only if the function's bytes match one of the layouts it was written
//  against: macOS 14.8.9 (23J631), 15.8.2/15.8.3 (24H232/24H241, one kernel) and 26.7.2/26.7.3
//  (25G332/25G342, one kernel). On any other kernel it stays off and says why in sysctl debug.ccd_log.
//
//  Boot-args: -ccdoff (do not load), -ccddbg (Lilu debug log), ccdmode=0|1|2 (start mode, default 1).
//  sysctls:   debug.ccd_mode (rw, root), debug.ccd_state, debug.ccd_stat, debug.ccd_log (read).
//

#include <Headers/plugin_start.hpp>
#include <Headers/kern_api.hpp>
#include <sys/sysctl.h>

// ---- Layouts (IDA/Hex-Rays of each kernel's _choose_starting_pset and CPU picker) ---------------
// Same in every build: thread->sched_pri (int16) and pset->pset_id (uint32 at +0).
static constexpr size_t kThreadSchedPri     = 0x434;  // thread->sched_pri (int16)
static constexpr size_t kPsetId             = 0x0;    // pset->pset_id (read as uint32 by the kernel)
static constexpr int16_t kBasePriRtQueues   = 97;     // BASEPRI_RTQUEUES

// A byte check at an offset of _choose_starting_pset.
struct SigAt { size_t off; uint8_t bytes[13]; size_t len; };

struct Layout {
    const char *name;
    size_t threadAffinitySet;  // thread->affinity_set
    size_t threadLastProc;     // thread->last_processor
    size_t taskPsetHint;       // task->pset_hint
    size_t psetOnlineCount;    // pset->online_processor_count (int)
    size_t nodePsetMap;        // pset_node->pset_map (uint64)
    // Per-pset CPU maps (bit = cpu_id), as the kernel's CPU picker reads them to find an idle primary core:
    size_t psetRecommended;    // pset->recommended_bitmask
    size_t psetIdleCpus;       // pset->cpu_state_map[PROCESSOR_IDLE]
    size_t psetPrimaryMap;     // pset->primary_map (processor_set_primary clears SMT siblings)
    // Bytes of _choose_starting_pset from offset 0; 0x100 = "any byte" (relative displacements).
    const uint16_t *head; size_t headLen;
    size_t callOff;            // e8 rel32 of the get_threadtask call, checked against the symbol
    const SigAt *more; size_t moreLen;
    // The CPU picker's load of the three pset maps above.
    const char *picker; size_t pickerOff; const uint8_t *pick; size_t pickLen;
};

// macOS 26.7.2 / 26.7.3 (25G332 / 25G342: the same kernel). Booted and measured on a 5900XT.
static const uint16_t kHead25[] = {
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
    0xe8, 0x100, 0x100, 0x100, 0x100,                                   // call _get_threadtask
    0x4c, 0x8b, 0x48, 0x68,                                             // mov r9,[rax+0x68]  pset_hint
};
static const SigAt kMore25[] = {
    { 0x90,  {0x48, 0x8b, 0x88, 0x90, 0x08, 0x00, 0x00, 0x48, 0x8b, 0x59, 0x18}, 11 },  // pset->node, node->pset_map
    { 0xd1,  {0x42, 0x83, 0x7c, 0x19, 0x08, 0x00}, 6 },                                // cmp online_processor_count,0
    { 0xde,  {0x48, 0x8b, 0x4f, 0x18, 0x44, 0x8b, 0x08}, 7 },                          // node->pset_map; pset_id
    { 0x11b, {0x66, 0x83, 0xbe, 0x34, 0x04, 0x00, 0x00, 0x61}, 8 },                    // cmp sched_pri,97
    { 0x20e, {0x49, 0x39, 0x40, 0x28, 0x75, 0x03, 0x4c, 0x89, 0x02}, 9 },              // out: hint only if its pset is the result
};
// _choose_processor_smt + 0x201: mov rbx,[r13+0x30]; mov r8,[r13+0x58]; mov r9,[r13+0x70]; mov rax,r9; and rax,r8
static const uint8_t kPick25[] = {0x49, 0x8b, 0x5d, 0x30, 0x4d, 0x8b, 0x45, 0x58, 0x4d, 0x8b, 0x4d, 0x70,
                                  0x4c, 0x89, 0xc8, 0x4c, 0x21, 0xc0};

// macOS 15.8.2 / 15.8.3 (24H232 / 24H241: the same kernel). Not booted by us.
static const uint16_t kHead24[] = {
    0x55, 0x48, 0x89, 0xe5, 0x41, 0x57, 0x41, 0x56, 0x41, 0x55, 0x41, 0x54, 0x53, 0x50,  // prologue, push r15-r12,rbx,rax
    0x48, 0x89, 0xfb,                                                   // mov rbx,rdi
    0x48, 0x8b, 0x86, 0x68, 0x05, 0x00, 0x00,                           // mov rax,[rsi+0x568]  affinity_set
    0x48, 0x85, 0xc0, 0x74, 0x0f,                                       // test rax,rax; jz
    0x48, 0x83, 0xc0, 0x38, 0x45, 0x31, 0xf6, 0x48, 0x8b, 0x00,         // aset_pset
    0xe9, 0x100, 0x100, 0x100, 0x100,                                   // jmp out
    0x4c, 0x8b, 0xb6, 0xb0, 0x04, 0x00, 0x00,                           // mov r14,[rsi+0x4b0]  last_processor
    0x4d, 0x85, 0xf6, 0x74, 0x0c,                                       // test r14,r14; jz
    0x49, 0x8d, 0x46, 0x28, 0x48, 0x8b, 0x00,                           // processor_set
    0xe9, 0x100, 0x100, 0x100, 0x100,                                   // jmp out
    0x49, 0x89, 0xd7, 0x49, 0x89, 0xf4, 0x48, 0x89, 0xf7,               // save args; rdi = thread
    0xe8, 0x100, 0x100, 0x100, 0x100,                                   // call _get_threadtask
    0x48, 0x8b, 0x78, 0x68,                                             // mov rdi,[rax+0x68]  pset_hint
};
static const SigAt kMore24[] = {
    { 0x90,  {0x48, 0x8b, 0x88, 0x90, 0x08, 0x00, 0x00, 0x4c, 0x8b, 0x51, 0x20}, 11 },  // pset->node, node->pset_map
    { 0xd6,  {0x83, 0x78, 0x04, 0x00}, 4 },                                            // cmp online_processor_count,0
    { 0xe1,  {0x48, 0x8b, 0x4b, 0x20, 0x8b, 0x38}, 6 },                                // node->pset_map; pset_id
    { 0x179, {0x66, 0x83, 0xbe, 0x34, 0x04, 0x00, 0x00, 0x61}, 8 },                    // cmp sched_pri,97
    { 0x269, {0x49, 0x39, 0x46, 0x28, 0x75, 0x03, 0x4c, 0x89, 0x32}, 9 },              // out: hint only if its pset is the result
};
// _choose_processor_smt + 0x1ac: mov rcx,[rdx+0x70]; and rcx,[rdx+0x58]; and rcx,[rdx+0x30]
static const uint8_t kPick24[] = {0x48, 0x8b, 0x4a, 0x70, 0x48, 0x23, 0x4a, 0x58, 0x48, 0x23, 0x4a, 0x30};

// macOS 14.8.9 (23J631). Not booted by us. No choose_processor_smt in this kernel: choose_processor
// makes the same idle-primary test.
static const uint16_t kHead23[] = {
    0x55, 0x48, 0x89, 0xe5, 0x41, 0x57, 0x41, 0x56, 0x41, 0x55, 0x41, 0x54, 0x53, 0x50,  // prologue, push r15-r12,rbx,rax
    0x48, 0x89, 0xd3, 0x49, 0x89, 0xf4, 0x49, 0x89, 0xff,               // save args
    0x48, 0x8b, 0x86, 0x70, 0x05, 0x00, 0x00,                           // mov rax,[rsi+0x570]  affinity_set
    0x48, 0x85, 0xc0, 0x74, 0x0f,                                       // test rax,rax; jz
    0x48, 0x83, 0xc0, 0x38, 0x45, 0x31, 0xed, 0x4c, 0x8b, 0x30,         // aset_pset
    0xe9, 0x100, 0x100, 0x100, 0x100,                                   // jmp out
    0x4d, 0x8b, 0xac, 0x24, 0xb8, 0x04, 0x00, 0x00,                     // mov r13,[r12+0x4b8]  last_processor
    0x4d, 0x85, 0xed, 0x74, 0x0c,                                       // test r13,r13; jz
    0x49, 0x8d, 0x45, 0x28, 0x4c, 0x8b, 0x30,                           // processor_set
    0xe9, 0x100, 0x100, 0x100, 0x100,                                   // jmp out
    0x4c, 0x89, 0xe7,                                                   // rdi = thread
    0xe8, 0x100, 0x100, 0x100, 0x100,                                   // call _get_threadtask
    0x48, 0x8b, 0x40, 0x70,                                             // mov rax,[rax+0x70]  pset_hint
};
static const SigAt kMore23[] = {
    { 0x90,  {0x49, 0x8b, 0x8e, 0x98, 0x08, 0x00, 0x00, 0x48, 0x8b, 0x79, 0x28}, 11 },  // pset->node, node->pset_map
    { 0xd4,  {0x41, 0x83, 0x7e, 0x04, 0x00}, 5 },                                      // cmp online_processor_count,0
    { 0xe5,  {0x49, 0x8b, 0x47, 0x28, 0x41, 0x8b, 0x0e}, 7 },                          // node->pset_map; pset_id
    { 0x176, {0x41, 0x0f, 0xb7, 0x8c, 0x24, 0x34, 0x04, 0x00, 0x00, 0x66, 0x83, 0xf9, 0x61}, 13 },  // sched_pri vs 97
    { 0x296, {0x4d, 0x39, 0x75, 0x28, 0x75, 0x03, 0x4c, 0x89, 0x2b}, 9 },              // out: hint only if its pset is the result
};
// _choose_processor + 0x60e: mov rcx,[rbx+0x58]; mov r8,[rbx+0x80]; mov rdi,[rbx+0x98]
static const uint8_t kPick23[] = {0x48, 0x8b, 0x4b, 0x58, 0x4c, 0x8b, 0x83, 0x80, 0x00, 0x00, 0x00,
                                  0x48, 0x8b, 0xbb, 0x98, 0x00, 0x00, 0x00};

static const Layout kLayouts[] = {
    { "macOS 26.7.2-26.7.3 (25G332/25G342)", 0x570, 0x4b8, 0x68, 0x8, 0x18, 0x30, 0x58, 0x70,
      kHead25, arrsize(kHead25), 0x43, kMore25, arrsize(kMore25), "_choose_processor_smt", 0x201, kPick25, arrsize(kPick25) },
    { "macOS 15.8.2-15.8.3 (24H232/24H241)", 0x568, 0x4b0, 0x68, 0x4, 0x20, 0x30, 0x58, 0x70,
      kHead24, arrsize(kHead24), 0x4d, kMore24, arrsize(kMore24), "_choose_processor_smt", 0x1ac, kPick24, arrsize(kPick24) },
    { "macOS 14.8.9 (23J631)", 0x570, 0x4b8, 0x70, 0x4, 0x28, 0x58, 0x80, 0x98,
      kHead23, arrsize(kHead23), 0x4e, kMore23, arrsize(kMore23), "_choose_processor", 0x60e, kPick23, arrsize(kPick23) },
};
// The layout in use: the one whose bytes matched at install (the user-space tests set it directly).
static Layout gL = kLayouts[0];

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
    if (id >= 64 || !(fld<uint64_t>(node, gL.nodePsetMap) & (1ULL << id)) || fld<int32_t>(pset, gL.psetOnlineCount) <= 0)
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
    return (rd(gL.psetRecommended) & rd(gL.psetIdleCpus) & rd(gL.psetPrimaryMap)) != 0;
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
    if (mode == 0 || thread == nullptr || fld<void *>(thread, gL.threadAffinitySet) != nullptr ||
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
    int proposed = psetUsable(node, fld<void *>(task, gL.taskPsetHint), &hintId) ? static_cast<int>(hintId)
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
    if (fld<void *>(thread, gL.threadLastProc) != nullptr) return gOrg(node, thread, processor_hint);
    void *orig = gOrg(node, thread, processor_hint);
    CpuCounters &c = counters();
    c.placed++;
    void *task = gGetThreadTask(thread);
    void *home = task ? fld<void *>(task, gL.taskPsetHint) : nullptr;
    uint32_t id = 0;
    if (home == nullptr || home == orig || !psetUsable(node, home, &id)) {
        c.same++;
        return orig;
    }
    // The original may have set a processor hint inside its own pset; it does not apply to ours.
    if (processor_hint != nullptr) *processor_hint = nullptr;
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
// True if the kernel's bytes match `L`; otherwise `why` says where they differ.
static bool layoutMatches(const Layout &L, mach_vm_address_t fn, mach_vm_address_t getThreadTask, mach_vm_address_t picker,
                          char *why, size_t whyLen) {
    if (!picker) {
        snprintf(why, whyLen, "no %s", L.picker + 1);
        return false;
    }
    const uint8_t *p = reinterpret_cast<const uint8_t *>(fn);
    for (size_t i = 0; i < L.headLen; i++) {
        if (L.head[i] <= 0xff && p[i] != L.head[i]) {
            snprintf(why, whyLen, "byte 0x%zx is %02x, expected %02x", i, p[i], L.head[i]);
            return false;
        }
    }
    int32_t rel;
    memcpy(&rel, p + L.callOff + 1, sizeof(rel));
    mach_vm_address_t target = fn + L.callOff + 5 + static_cast<mach_vm_address_t>(static_cast<int64_t>(rel));
    if (target != getThreadTask) {
        snprintf(why, whyLen, "call at 0x%zx is not get_threadtask", L.callOff);
        return false;
    }
    for (size_t i = 0; i < L.moreLen; i++) {
        if (memcmp(p + L.more[i].off, L.more[i].bytes, L.more[i].len) != 0) {
            snprintf(why, whyLen, "bytes at 0x%zx differ", L.more[i].off);
            return false;
        }
    }
    if (memcmp(reinterpret_cast<const uint8_t *>(picker) + L.pickerOff, L.pick, L.pickLen) != 0) {
        snprintf(why, whyLen, "%s bytes at 0x%zx differ", L.picker + 1, L.pickerOff);
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

    auto solve = [&patcher](const char *name) {
        mach_vm_address_t a = patcher.solveSymbol(KernelPatcher::KernelID, name);
        patcher.clearError();
        return a;
    };
    mach_vm_address_t fn = solve("_choose_starting_pset");
    mach_vm_address_t gtt = solve("_get_threadtask");
    auto kernelTask = reinterpret_cast<void **>(solve("_kernel_task"));
    mach_vm_address_t cpuNum = solve("_cpu_number");
    // Pset count: sched_num_psets on macOS 26; older kernels have no such variable, so the psets in the
    // boot node are counted (pset_node0's pset_map, filled when the CPU topology is built at boot).
    auto numPsets = reinterpret_cast<uint32_t *>(solve("_sched_num_psets"));
    void *node0 = reinterpret_cast<void *>(solve("_pset_node0"));
    if (!fn || !gtt || !kernelTask || !cpuNum || (!numPsets && !node0)) {
        gState = 2;
        ccdLog("symbols: choose_starting_pset %s, get_threadtask %s, kernel_task %s, cpu_number %s, pset count %s",
               fn ? "ok" : "missing", gtt ? "ok" : "missing", kernelTask ? "ok" : "missing", cpuNum ? "ok" : "missing",
               (numPsets || node0) ? "ok" : "missing");
        return;
    }

    char why[arrsize(kLayouts)][96] = {};
    const Layout *found = nullptr;
    for (size_t i = 0; i < arrsize(kLayouts) && !found; i++) {
        if (layoutMatches(kLayouts[i], fn, gtt, solve(kLayouts[i].picker), why[i], sizeof(why[i]))) found = &kLayouts[i];
    }
    if (!found) {
        gState = 3;
        for (size_t i = 0; i < arrsize(kLayouts); i++) ccdLog("%s: %s", kLayouts[i].name, why[i]);
        ccdLog("choose_starting_pset matches no known layout: hook not installed");
        return;
    }
    gL = *found;

    gPsets = numPsets ? static_cast<int>(*numPsets) : __builtin_popcountll(fld<uint64_t>(node0, gL.nodePsetMap));
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
    if (*kernelTask == nullptr) {
        gState = 2;
        ccdLog("kernel_task not set yet: hook not installed");
        return;
    }

    gGetThreadTask = reinterpret_cast<get_threadtask_t>(gtt);
    gCpuNumber = reinterpret_cast<cpu_number_t>(cpuNum);
    gKernelTask = *kernelTask;
    // routeMultiple, not routeFunction: Lilu stores the original in gOrg BEFORE it writes the jump
    // (kern_patcher.cpp routeFunctionInternal, "to avoid null pointer dereference"). With routeFunction
    // gOrg was set after the route was live, and a CPU entering the hook in between called a null pointer.
    KernelPatcher::RouteRequest req("_choose_starting_pset", ccdChooseStartingPset, gOrg);
    // Lilu can report the route as done with gOrg written and no jump in place (a failed patch
    // allocation or memory protection change after the trampoline): it leaves the error code set then.
    patcher.clearError();
    if (!patcher.routeMultiple(KernelPatcher::KernelID, &req, 1) || !gOrg
        || patcher.getError() != KernelPatcher::Error::NoError) {
        gState = 4;
        ccdLog("routeMultiple failed (%d)", static_cast<int>(patcher.getError()));
        patcher.clearError();
        return;
    }
    if (req.from != fn) ccdLog("warning: routed %llx, checked %llx", (unsigned long long)req.from, (unsigned long long)fn);
    gState = 1;
    ccdLog("installed: %s layout, %d processor sets, mode %d", gL.name, gPsets, gMode);
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
