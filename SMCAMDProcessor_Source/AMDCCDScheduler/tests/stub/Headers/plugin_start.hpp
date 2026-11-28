// User-space stand-ins for the Lilu and kernel APIs AMDCCDScheduler.cpp uses, so its hook logic
// can be compiled and exercised as a normal program.
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <errno.h>

typedef uint64_t mach_vm_address_t;
#define SYSLOG(mod, fmt, ...) printf("[log] " fmt "\n", ##__VA_ARGS__)
template <typename T, size_t N> constexpr size_t arrsize(const T (&)[N]) { return N; }
#define xStringify(x) #x
#define ADDPR(x) x
inline int parseModuleVersion(const char *) { return 0; }
inline bool PE_parse_boot_argn(const char *, void *, int) { return false; }

// The test drives the patcher through the knobs below: solveSymbol reads solveTable, routeMultiple
// resolves req.from, writes *req.org only when routeWritesOrg asks, returns routeResult and leaves
// routeError behind (getError reports it; clearError resets it, as Lilu's does).
struct KernelPatcher {
    enum class Error { NoError, MemoryIssue };
    static constexpr size_t KernelID = 0;
    struct Solved { const char *name; mach_vm_address_t address; };
    static inline Solved *solveTable = nullptr;
    static inline size_t solveCount = 0;
    static inline bool routeResult = false;
    static inline bool routeWritesOrg = false;
    static inline Error routeError = Error::NoError;
    static inline Error error = Error::NoError;
    mach_vm_address_t solveSymbol(size_t, const char *name) {
        if (solveTable)
            for (size_t i = 0; i < solveCount; i++)
                if (!strcmp(solveTable[i].name, name)) return solveTable[i].address;
        return 0;
    }
    void clearError() { error = Error::NoError; }
    Error getError() { return error; }
    mach_vm_address_t routeFunction(mach_vm_address_t, mach_vm_address_t, bool) { return 0; }
    struct RouteRequest {
        const char *symbol {nullptr};
        mach_vm_address_t from {0}, to {0};
        mach_vm_address_t *org {nullptr};
        template <typename T, typename O>
        RouteRequest(const char *s, T t, O &o) :
            symbol(s), to(reinterpret_cast<mach_vm_address_t>(t)), org(reinterpret_cast<mach_vm_address_t *>(&o)) {}
    };
    bool routeMultiple(size_t, RouteRequest *reqs, size_t n) {
        if (reqs)
            for (size_t i = 0; i < n; i++) {
                reqs[i].from = solveSymbol(KernelID, reqs[i].symbol);
                if (routeWritesOrg && reqs[i].org) *reqs[i].org = reqs[i].from;
            }
        error = routeError;
        return routeResult;
    }
};
enum class LiluAPI { AllowNormal };
enum class KernelVersion { Sonoma, Tahoe };
struct LiluStub { template <typename F> void onPatcherLoadForce(F) {} };
static LiluStub lilu;
struct PluginConfiguration {
    const char *name; int ver; LiluAPI api; const char **off; size_t noff; const char **dbg; size_t ndbg;
    void *a; size_t b; KernelVersion min, max; void (*start)();
};
