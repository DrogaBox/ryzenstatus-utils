// Exercises the real AMDCCDScheduler.cpp hook logic against fake kernel objects laid out at the
// 25G342 offsets. Run: tests/run.sh
#include <vector>
#include <thread>
#include <atomic>
static unsigned long long fakeNs;
#define CCD_NOW() fakeNs
#include "../AMDCCDScheduler.cpp"
#include <stdlib.h>

static int failures, checks;
#define CHECK(c) do { checks++; if (!(c)) { failures++; printf("FAIL line %d: %s\n", __LINE__, #c); } } while (0)

struct Obj { alignas(16) uint8_t b[0x700]; };
template <typename T> static void put(Obj &o, size_t off, T v) { memcpy(o.b + off, &v, sizeof v); }

static Obj node, pset0, pset1, procOnP0;

static Obj kernelTaskObj;
static thread_local int fakeCpu;
static void *orgReturn;      // what the fake original returns
static void *orgHint;        // processor hint the fake original writes (if non-null)
static std::atomic<int> orgCalls;

static void *fakeOrg(void *, void *, void **hint) {
    orgCalls++;
    if (orgHint && hint) *hint = orgHint;
    return orgReturn;
}
static void *fakeGetThreadTask(void *thread) { void *t; memcpy(&t, (uint8_t *)thread + 0x630, sizeof t); return t; }
static int fakeCpuNumber() { return fakeCpu; }

static void makeThread(Obj &th, Obj &task, int16_t pri = 31, void *aset = nullptr, void *lastProc = nullptr) {
    memset(th.b, 0, sizeof th.b);
    put<void *>(th, 0x570, aset);
    put<void *>(th, 0x4b8, lastProc);
    put<int16_t>(th, 0x434, pri);
    put<void *>(th, 0x630, task.b);
}
static void makeTask(Obj &task, void *hint) { memset(task.b, 0, sizeof task.b); put<void *>(task, 0x68, hint); }
static uint64_t stat(const char *name) {
    struct sysctl_req r = { nullptr };
    ccdStatSysctl(nullptr, nullptr, 0, &r);
    const char *p = strstr(g_test_str_out, name);
    return p ? strtoull(p + strlen(name) + 1, nullptr, 10) : ~0ULL;
}
static void resetCounters() { memset(gCount, 0, sizeof gCount); }

int main() {
    put<uint64_t>(node, 0x18, 0x3);
    // Both psets: CPUs 0-7, primaries 0-3 (4-7 are their SMT siblings), all recommended, all idle.
    for (Obj *ps : {&pset0, &pset1}) { put<uint64_t>(*ps, 0x30, 0xff); put<uint64_t>(*ps, 0x58, 0xff); put<uint64_t>(*ps, 0x70, 0x0f); }
    put<uint32_t>(pset0, 0, 0); put<int32_t>(pset0, 8, 12);
    put<uint32_t>(pset1, 0, 1); put<int32_t>(pset1, 8, 12);
    put<void *>(procOnP0, 0x28, pset0.b);
    gOrg = fakeOrg; gGetThreadTask = fakeGetThreadTask; gCpuNumber = fakeCpuNumber;
    gKernelTask = kernelTaskObj.b; gState = 1; gPsets = 2; gMode = 1;

    Obj taskA, th1, th2;
    void *hint;

    // 1. First placement of a process: home = its pset_hint (xnu's own pick, here pset1); the kernel
    //    wanted pset0, the hook starts it in pset1 and clears the hint.
    makeTask(taskA, pset1.b); makeThread(th1, taskA);
    orgReturn = pset0.b; orgHint = nullptr; hint = nullptr;
    CHECK(ccdChooseStartingPset(node.b, th1.b, &hint) == pset1.b);
    CHECK(hint == nullptr);
    CHECK(stat("new") == 1 && stat("kept") == 1 && stat("nohint") == 1 && stat("same") == 0);

    // 2. pset_hint drifts to pset0 (thread_setrun rewrote it); a thread that last ran on pset0 comes
    //    back: the home stays pset1 and the stale hint processor (on pset0) is dropped.
    put<void *>(taskA, 0x68, pset0.b);
    makeThread(th2, taskA, 31, nullptr, procOnP0.b);
    orgReturn = pset0.b; orgHint = procOnP0.b; hint = nullptr;
    CHECK(ccdChooseStartingPset(node.b, th2.b, &hint) == pset1.b);
    CHECK(hint == nullptr);
    CHECK(stat("nohint") == 1);  // no second home for the same task

    // 3. The kernel already picked the home pset: its result and its hint are kept.
    orgReturn = pset1.b; orgHint = procOnP0.b; hint = nullptr;
    CHECK(ccdChooseStartingPset(node.b, th2.b, &hint) == pset1.b);
    CHECK(hint == procOnP0.b);
    CHECK(stat("same") == 1);

    // 3b. Home pset (pset1) has only idle SMT siblings (CPUs 4-7), no idle primary core: the kernel's
    //     choice and its hint stand and the placement counts as full. An idle primary that is not
    //     recommended does not count either. Once a recommended primary is idle, the thread goes home.
    put<uint64_t>(pset1, 0x58, 0xf0);
    orgReturn = pset0.b; orgHint = procOnP0.b; hint = nullptr;
    CHECK(ccdChooseStartingPset(node.b, th2.b, &hint) == pset0.b);
    CHECK(hint == procOnP0.b);
    CHECK(stat("full") == 1 && stat("kept") == 2);
    put<uint64_t>(pset1, 0x58, 0xf4); put<uint64_t>(pset1, 0x30, 0xfb);  // CPU 2 idle but not recommended
    CHECK(ccdChooseStartingPset(node.b, th2.b, &hint) == pset0.b);
    CHECK(stat("full") == 2);
    put<uint64_t>(pset1, 0x30, 0xff);
    hint = nullptr;
    CHECK(ccdChooseStartingPset(node.b, th2.b, &hint) == pset1.b);
    CHECK(hint == nullptr && stat("kept") == 3);
    put<uint64_t>(pset1, 0x58, 0xff);
    orgHint = nullptr;

    // 4. Realtime, affinity-set and kernel_task threads go to the original untouched and uncounted.
    uint64_t placed = stat("new");
    Obj rt; makeThread(rt, taskA, 97);
    orgReturn = pset0.b; orgHint = nullptr; hint = nullptr;
    CHECK(ccdChooseStartingPset(node.b, rt.b, &hint) == pset0.b);
    Obj as; makeThread(as, taskA, 31, (void *)0x1234);
    CHECK(ccdChooseStartingPset(node.b, as.b, &hint) == pset0.b);
    Obj kth; makeThread(kth, kernelTaskObj);
    CHECK(ccdChooseStartingPset(node.b, kth.b, &hint) == pset0.b);
    CHECK(stat("new") == placed);

    // 5. Home pset offline or outside the node: the kernel's choice stands.
    put<int32_t>(pset1, 8, 0);
    orgReturn = pset0.b; hint = nullptr;
    CHECK(ccdChooseStartingPset(node.b, th1.b, &hint) == pset0.b);
    put<int32_t>(pset1, 8, 12);
    put<uint64_t>(node, 0x18, 0x1);
    CHECK(ccdChooseStartingPset(node.b, th1.b, &hint) == pset0.b);
    put<uint64_t>(node, 0x18, 0x3);

    // 6. Mode 0: original only, nothing counted.
    resetCounters(); gMode = 0;
    orgReturn = pset0.b;
    CHECK(ccdChooseStartingPset(node.b, th1.b, &hint) == pset0.b);
    CHECK(stat("new") == 0);

    // 7. Mode 2 (0.1.0): only first placements move, towards the current pset_hint.
    gMode = 2;
    Obj taskB, fresh, ran; makeTask(taskB, pset1.b); makeThread(fresh, taskB); makeThread(ran, taskB, 31, nullptr, procOnP0.b);
    orgReturn = pset0.b; orgHint = nullptr;
    CHECK(ccdChooseStartingPset(node.b, fresh.b, &hint) == pset1.b);
    CHECK(ccdChooseStartingPset(node.b, ran.b, &hint) == pset0.b);
    CHECK(stat("kept") == 1);

    // 8. Counters are per CPU and summed by the sysctl.
    resetCounters(); gMode = 1;
    for (int c = 0; c < 24; c++) { fakeCpu = c; orgReturn = pset1.b; ccdChooseStartingPset(node.b, th1.b, &hint); }
    fakeCpu = 999;  // out of range lands in slot 0
    ccdChooseStartingPset(node.b, th1.b, &hint);
    CHECK(stat("new") == 25 && stat("same") == 25);
    fakeCpu = 0;

    // 9. Churn: 1000 long-lived processes keep running (a placement every second) while 40000
    //    short-lived ones start, run once and die (a build). Live processes must keep their home.
    std::vector<Obj> *live = new std::vector<Obj>(1000), *dead = new std::vector<Obj>(400);
    Obj t; int wrongHome = 0;
    for (size_t i = 0; i < live->size(); i++) {
        makeTask((*live)[i], (i & 1) ? pset1.b : pset0.b);
        makeThread(t, (*live)[i]); orgReturn = pset0.b; ccdChooseStartingPset(node.b, t.b, &hint);
        put<void *>((*live)[i], 0x68, pset0.b);  // pset_hint drifts afterwards
    }
    for (int k = 0; k < 40000; k++) {
        Obj &d = (*dead)[k % dead->size()];  // addresses get reused, as zone memory does
        makeTask(d, (k & 1) ? pset1.b : pset0.b);
        makeThread(t, d); orgReturn = pset0.b; ccdChooseStartingPset(node.b, t.b, &hint);
        if (k % 50 == 49) {
            fakeNs += 1ULL << 30;  // next second
            for (size_t i = 0; i < live->size(); i++) {
                makeThread(t, (*live)[i], 31, nullptr, procOnP0.b); orgReturn = pset0.b;
                if (ccdChooseStartingPset(node.b, t.b, &hint) != ((i & 1) ? pset1.b : pset0.b)) wrongHome++;
            }
        }
    }
    printf("live-process placements that lost their home during 40000 short processes: %d of %zu\n", wrongHome, (size_t)800 * 1000);
    CHECK(wrongHome == 0);
    // And with far more distinct dead processes than slots, each a new address:
    std::vector<Obj> *many = new std::vector<Obj>(50000);
    wrongHome = 0;
    for (size_t k = 0; k < many->size(); k++) {
        makeTask((*many)[k], pset0.b); makeThread(t, (*many)[k]); orgReturn = pset0.b; ccdChooseStartingPset(node.b, t.b, &hint);
        if (k % 50 == 49) {
            fakeNs += 1ULL << 30;
            for (size_t i = 0; i < live->size(); i++) {
                makeThread(t, (*live)[i], 31, nullptr, procOnP0.b); orgReturn = pset0.b;
                if (ccdChooseStartingPset(node.b, t.b, &hint) != ((i & 1) ? pset1.b : pset0.b)) wrongHome++;
            }
        }
    }
    printf("same with 50000 distinct short processes (3x the table): %d of %zu\n", wrongHome, (size_t)1000 * 1000);
    CHECK(wrongHome < 1000);  // under 0.1%
    // 10. Mode sysctl accepts 0..2 only.
    struct sysctl_req w = { (void *)1 };
    g_test_int_in = 3; CHECK(ccdModeSysctl(nullptr, nullptr, 0, &w) == EINVAL && gMode == 1);
    g_test_int_in = 2; CHECK(ccdModeSysctl(nullptr, nullptr, 0, &w) == 0 && gMode == 2);
    g_test_int_in = 0; CHECK(ccdModeSysctl(nullptr, nullptr, 0, &w) == 0 && gMode == 0);

    // 11. Concurrency: 16 threads place threads of the same 64 new processes at once; every
    //     process must end up with one home that all of them see.
    gMode = 1; memset(gHome, 0, sizeof gHome); memset(gUsed, 0, sizeof gUsed);
    static Obj ctasks[64];
    for (int i = 0; i < 64; i++) makeTask(ctasks[i], (i & 1) ? pset1.b : pset0.b);
    static std::atomic<void *> seen[64];
    std::atomic<int> mismatch{0};
    std::vector<std::thread> ts;
    for (int w = 0; w < 16; w++) ts.emplace_back([w, &mismatch] {
        fakeCpu = w;
        Obj th; void *h;
        for (int n = 0; n < 20000; n++) {
            int i = (n * 7 + w) & 63;
            makeThread(th, ctasks[i]);
            void *r = ccdChooseStartingPset(node.b, th.b, &h);
            void *expect = nullptr;
            if (!seen[i].compare_exchange_strong(expect, r) && expect != r) mismatch++;
        }
    });
    for (auto &x : ts) x.join();
    CHECK(mismatch.load() == 0);
    printf("concurrent placements with a different home for the same process: %d\n", mismatch.load());
    printf("%s (%d checks, %d failed)\n", failures ? "TESTS FAILED" : "TESTS OK", checks, failures);
    return failures != 0;
}
