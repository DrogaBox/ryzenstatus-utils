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

struct KernelPatcher {
    enum class Error { NoError };
    static constexpr size_t KernelID = 0;
    mach_vm_address_t solveSymbol(size_t, const char *) { return 0; }
    void clearError() {}
    Error getError() { return Error::NoError; }
    mach_vm_address_t routeFunction(mach_vm_address_t, mach_vm_address_t, bool) { return 0; }
    struct RouteRequest {
        const char *symbol {nullptr};
        mach_vm_address_t from {0}, to {0};
        mach_vm_address_t *org {nullptr};
        template <typename T, typename O>
        RouteRequest(const char *s, T t, O &o) :
            symbol(s), to(reinterpret_cast<mach_vm_address_t>(t)), org(reinterpret_cast<mach_vm_address_t *>(&o)) {}
    };
    bool routeMultiple(size_t, RouteRequest *, size_t) { return false; }
};
enum class LiluAPI { AllowNormal };
enum class KernelVersion { Sonoma, Tahoe };
struct LiluStub { template <typename F> void onPatcherLoadForce(F) {} };
static LiluStub lilu;
struct PluginConfiguration {
    const char *name; int ver; LiluAPI api; const char **off; size_t noff; const char **dbg; size_t ndbg;
    void *a; size_t b; KernelVersion min, max; void (*start)();
};
