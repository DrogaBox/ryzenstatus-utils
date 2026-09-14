#ifndef AMDRyzenCPUPowerManagement_h
#define AMDRyzenCPUPowerManagement_h

//Support for macOS 10.13
#include "Headers/LegacyHeaders/LegacyIOService.h"

#include <math.h>
#include <IOKit/pci/IOPCIDevice.h>
#include <IOKit/IOTimerEventSource.h>
#include <IOKit/IOMemoryDescriptor.h>


#include <i386/proc_reg.h>
#include <libkern/libkern.h>
#include <libkern/OSAtomic.h>


#include <Headers/kern_efi.hpp>
#include <Headers/kern_util.hpp>
#include <Headers/kern_cpu.hpp>
#include <Headers/kern_time.hpp>


//#include <Headers/kern_api.hpp>
#define LILU_CUSTOM_KMOD_INIT
#define LILU_CUSTOM_IOKIT_INIT
#include <Headers/plugin_start.hpp>
#include "symresolver/kernel_resolver.h"

#include "SuperIO/ISSuperIONCT668X.hpp"
#include "SuperIO/ISSuperIONCT67XXFamily.hpp"
#include "SuperIO/ISSuperIOIT86XXEFamily.hpp"
#include "AMDGPU.hpp"

#include "Headers/pmRyzenSymbolTable.h"

#include <i386/cpuid.h>

#define OC_OEM_VENDOR_VARIABLE_NAME        u"oem-vendor"
#define OC_OEM_BOARD_VARIABLE_NAME         u"oem-board"

#define BASEBOARD_STRING_MAX 64

#define kNrOfPowerStates 2
#define kIOPMPowerOff 0

extern "C" {
#include "pmAMDRyzen.h"

#include "Headers/osfmk/i386/pmCPU.h"
#include "Headers/osfmk/i386/cpu_topology.h"
    

int cpu_number(void);
void mp_rendezvous_no_intrs(void (*action_func)(void *), void *arg);

void mp_rendezvous(void (*setup_func)(void *),
                  void (*action_func)(void *),
                  void (*teardown_func)(void *),
                  void *arg);

void i386_deactivate_cpu(void);
//    int wrmsr_carefully(uint32_t msr, uint64_t val);


void pmRyzen_wrmsr_safe(void *, uint32_t, uint64_t);
uint64_t pmRyzen_rdmsr_safe(void *, uint32_t);



extern pmRyzen_symtable_t pmRyzen_symtable;
};


/**
 * Offset table: https://github.com/torvalds/linux/blob/master/drivers/hwmon/k10temp.c#L78
 */
typedef struct tctl_offset {
    uint8_t model;
    char const *id;
    int offset;
} TempOffset;


#define MAX_FAN_CURVES 4
struct FanCurveConfig {
    uint8_t lut[256];
    uint8_t sourceSensor; // 0 = CPU, 1 = GPU
    uint8_t hysteresis;   // In °C
    uint8_t rampRate;     // Max PWM change per second
};


//
// Thermal guard bounds shared between the power-management driver and the
// UserClient: above kTHERMAL_GUARD_TEMP_C, any fan command is clamped to at
// least kTHERMAL_GUARD_PWM (curve mode and manual mode alike).
//
static constexpr float    kTHERMAL_GUARD_TEMP_C = 85.0f;
static constexpr uint8_t  kTHERMAL_GUARD_PWM    = 200;   // ~78.4% duty

// S10 KRN-00: hardware safety bounds for curve-mode fan output.
//
// kCURVE_MIN_ACTIVE_PWM — minimum duty actually written to the Super I/O once a
// fan is under curve control. PWM 0 keeps its special meaning ("release this fan
// back to BIOS/SmartFan"), but ANY non-zero request below this floor is raised
// to it. Rationale: this is a strictly open-loop controller (no RPM feedback),
// so a duty below the rotor's start threshold yields a silently stalled fan
// drawing locked-rotor current with zero airflow and zero detection.
// Cross-reference: the Swift manual-mode floor is AMDFanSafety.minimumManualPWM
// (Sources/RyzenStatus/Services/AMD/FanCurveModels.swift) — keep both in sync.
static constexpr uint8_t  kCURVE_MIN_ACTIVE_PWM = 40;    // ~15.7% duty

// kFAN_STOPPED_RPM — below this, a fan with a TRUSTED tachometer reading is
// treated as not turning. Used to decide whether a commanded duty is a rotor
// START (dangerous below the floor) or merely maintaining a rotor that is
// already turning (safe, and the case the floor must NOT touch — see
// AMDFanSafety.guardOnlyPWM on the Swift side). Same threshold the Auto-mode
// PWM estimator already uses to decide a fan is spinning.
static constexpr uint32_t  kFAN_STOPPED_RPM = 100;

// kTEMP_INVALID — explicit sentinel for "temperature could not be read".
// getPackageTemp() returned 0.0f for BOTH a genuine 0 C and a failed SMN/PCI
// transaction; 0 C simultaneously selects lut[0] (coldest, slowest point) AND
// makes the >= 85 C guard test false. That is fail-dangerous.
static constexpr float    kTEMP_INVALID = -1000.0f;

// kFAILSAFE_PWM — duty applied when the loop cannot trust its temperature
// input. Deliberately audible: a loud fan is a self-announcing failure mode,
// a silent stalled fan is not.
static constexpr uint8_t  kFAILSAFE_PWM = 160;           // ~62.7% duty

// Valid Zen package-temperature window. NaN and infinities fail by
// construction. (t == t) is the NaN test; -ffast-math is not enabled here.
static inline bool isTempValid(float t) {
    return (t == t) && (t > -20.0f) && (t < 135.0f);
}

static IOPMPowerState powerStates[kNrOfPowerStates] = {
   {1, kIOPMPowerOff, kIOPMPowerOff, kIOPMPowerOff, 0, 0, 0, 0, 0, 0, 0, 0},
   {1, kIOPMPowerOn, kIOPMPowerOn, kIOPMPowerOn, 0, 0, 0, 0, 0, 0, 0, 0}
};

class AMDRyzenCPUPowerManagement : public IOService {
    OSDeclareDefaultStructors(AMDRyzenCPUPowerManagement)
    
public:
    
    char kMODULE_VERSION[12]{};
    
    /**
     *  MSRs supported by AMD 17h/19h/1Ah CPU from:
     *  https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/blob/master/LibreHardwareMonitorLib/Hardware/Cpu/Amd17Cpu.cs
     * and
     * Processor Programming Reference for AMD Family 17h/19h/1Ah CPUs,
     * Linux kernel k10temp driver (drivers/hwmon/k10temp.c)
     */
    
    static constexpr uint32_t kCOFVID_STATUS = 0xC0010071;
    static constexpr uint32_t k17H_M01H_SVI = 0x0005A000;
    static constexpr uint32_t kF17H_M01H_THM_TCON_CUR_TMP = 0x00059800;
    static constexpr uint32_t kF17H_M70H_CCD1_TEMP = 0x00059954;
    static constexpr uint32_t kF17H_TEMP_OFFSET_FLAG = 0x80000;
    static constexpr uint32_t kF18H_TEMP_OFFSET_FLAG = 0x60000;
    static constexpr uint8_t kFAMILY_17H_PCI_CONTROL_REGISTER = 0x60;
    static constexpr uint8_t kFAMILY_1AH_PCI_CONTROL_REGISTER = 0x60;   // Zen 5 — confirm against PPR
    static constexpr uint16_t kAMD_HOST_BRIDGE_VENDOR = 0x1022;
    
    /**
     *  CCD (Core Complex Die) temperature register offsets.
     *  These offsets are added to kF17H_M01H_THM_TCON_CUR_TMP (0x59800)
     *  to get the per-CCD temperature register addresses.
     *
     *  Values sourced from Linux kernel k10temp.c:
     *  - 0x154: Family 17h (Zen/Zen+/Zen2), Family 19h models 00-5Fh (Zen3/3+)
     *  - 0x308: Family 19h models 60-7Fh (Zen4), Family 1Ah (Zen5 Granite Ridge)
     */
    static constexpr uint32_t kZEN_CCD_OFFSET_LEGACY = 0x154;
    static constexpr uint32_t kZEN_CCD_OFFSET_ZEN4_5 = 0x308;
    static constexpr uint8_t  kMAX_CCD_COUNT = 16;
    static constexpr uint32_t kZEN_CCD_TEMP_VALID_BIT = (1 << 11);
    static constexpr uint32_t kZEN_CCD_TEMP_MASK = 0x7FF;
    
    enum SMUResponse : uint32_t {
        SMU_RSP_OK           = 1,
        SMU_RSP_INVALID_CMD  = 0xFF,
        SMU_RSP_INVALID_ARGS = 0xFE,
        SMU_RSP_BUSY         = 0xFD,
        SMU_RSP_TIMEOUT      = 0,
    };
    
    static constexpr uint32_t kMSR_HWCR = 0xC0010015;
    static constexpr uint32_t kMSR_CORE_ENERGY_STAT = 0xC001029A;
    static constexpr uint32_t kMSR_HARDWARE_PSTATE_STATUS = 0xC0010293;
    static constexpr uint32_t kMSR_PKG_ENERGY_STAT = 0xC001029B;
    static constexpr uint32_t kMSR_PSTATE_0 = 0xC0010064;
    static constexpr uint32_t kMSR_PSTATE_LEN = 8;
    static constexpr uint32_t kMSR_PSTATE_STAT = 0xC0010063;
    static constexpr uint32_t kMSR_PSTATE_CTL = 0xC0010062;
    static constexpr uint32_t kMSR_RAPL_PWR_UNIT = 0xC0010299;
    static constexpr uint32_t kMSR_PKG_C6_RES = 0xC0010296;
    static constexpr uint32_t kMSR_MPERF = 0x000000E7;
    static constexpr uint32_t kMSR_APERF = 0x000000E8;
    static constexpr uint32_t kMSR_PERF_CTL_0 = 0xC0010000;
    static constexpr uint32_t kMSR_PERF_CTR_0 = 0xC0010004;
    static constexpr uint32_t kMSR_PERF_IRPC = 0xC00000E9;
    static constexpr uint32_t kMSR_CSTATE_ADDR = 0xC0010073;
    static constexpr uint32_t kMSR_AMD_CPPC_CAP1 = 0xC00102B0;
    static constexpr uint32_t kMSR_AMD_CPPC_ENABLE = 0xC00102B1;
    static constexpr uint32_t kMSR_AMD_CPPC_CAP2 = 0xC00102B2;
    static constexpr uint32_t kMSR_AMD_CPPC_REQ = 0xC00102B3;
    static constexpr uint32_t kMSR_AMD_CPPC_STATUS = 0xC00102B4;
    
//    static constexpr uint32_t EF = 0x88;
    
    static constexpr uint32_t kEFI_VARIABLE_NON_VOLATILE = 0x00000001;
    static constexpr uint32_t kEFI_VARIABLE_BOOTSERVICE_ACCESS = 0x00000002;
    static constexpr uint32_t kEFI_VARIABLE_RUNTIME_ACCESS = 0x00000004;
    
    

    virtual bool init(OSDictionary *dictionary = 0) override;
    virtual void free(void) override;
    
    virtual bool start(IOService *provider) override;
    virtual void stop(IOService *provider) override;
    
    virtual IOReturn setPowerState(unsigned long powerStateOrdinal, IOService* whatDevice) override;
    
    void fetchOEMBaseBoardInfo();
    volatile SInt32 fanUpdateCounter = 0;
    // S11-a: selector 94 needs its OWN counter. Sharing fanUpdateCounter with
    // selector 93 was not merely a cadence quirk — it made 94's rate-limit gate
    // unreachable. getFans() calls 93 then 94, so each pass consumes exactly two
    // values and the parity each selector sees never changes. The counter starts
    // at 0, OSIncrementAtomic returns the PRE-increment value, so 93 always reads
    // an even value and 94 always reads an odd one — and `% 4 == 0` can only ever
    // be true of an even value. updateFanControl() was therefore never called at
    // all, from boot, which is why every fan reported pwm 0.
    volatile SInt32 fanCtrlUpdateCounter = 0;

    bool read_msr(uint32_t addr, uint64_t *value);
    bool write_msr(uint32_t addr, uint64_t value);
    
    
    void updateClockSpeed(uint8_t physical);
    void calculateEffectiveFrequency(uint8_t physical);
    void updateInstructionDelta(uint8_t physical);
    void applyPowerControl();
    void applyEPPControl();
    
    void setCPBState(bool enabled);
    bool getCPBState();
    
#define HF_TEMP_SAMPLE_SECS 3
#define HF_TEMP_SAMPLE_FREQ 2
#define HF_TEMP_SAMPLE_LEN (HF_TEMP_SAMPLE_SECS * HF_TEMP_SAMPLE_FREQ)
#define HF_TEMP_SAMPLE_LENREP (1.0f / (float)HF_TEMP_SAMPLE_LEN)
#define HF_TEMP_SAMPLE_REP (1.0f / (float)HF_TEMP_SAMPLE_FREQ)
#define HF_TEMP_SAMPLE_PERIOD (int)(HF_TEMP_SAMPLE_REP * 1000.0)
    inline float getPackageTemp();
    float getCCDTemp(uint8_t ccd);
    uint32_t readCCDRegisterRaw(uint8_t ccd);
    void updatePackageTemp();
    
    void updatePackageEnergy();
    
    void registerRequest();
    
    void dumpPstate();
    void reinitHwState();
    void writePstate(const uint64_t *buf);
    
    bool initSuperIO(uint16_t* chipIntel, bool allowUnlock = true);
    void evaluateFanCurves();
    
    uint32_t getPMPStateLimit();
    void setPMPStateLimit(uint32_t);
    
    uint32_t getHPcpus();
    int setCurveOptimizer(uint8_t core, int8_t offset);
    
    uint32_t totalNumberOfPhysicalCores;
    uint32_t totalNumberOfLogicalCores;
    
    bool cppcSupported {false};
    bool cppcActiveMode {false};
    uint8_t cppcEPPValue {0x3F};
    uint8_t cppcHighestPerf_perCore[CPUInfo::MaxCpus] {};
    bool cppcThrottled {false};
    bool disableCStates = true;
    uint64_t cstateAddrConfig {0};
    uint64_t packageC6Residency {0};
    
    uint8_t cpuFamily;
    uint8_t cpuModel;
    uint8_t cpuSupportedByCurrentVersion;
    
    uint32_t ccdOffset = kZEN_CCD_OFFSET_LEGACY;
    uint8_t  ccdCount = 0;
    float    ccdTemperatures[kMAX_CCD_COUNT] {};
    char     cpuArchName[16] {};
    pmRyzen_idle_strategy_t cpuIdleStrategy{PMRYZEN_IDLE_STRATEGY_SIMPLE};
    
    // Curve Optimizer (Phase 13)
    int8_t curveOptimizerOffsets[CPUInfo::MaxCpus] {};
    
    // S4: Precision Boost Overdrive limits (Vermeer-only SMU commands).
    // Values are the last successfully-programmed limits, cached for read-back
    // (the SMU has no read command for these — same approach as the CO cache).
    // Defaults of 0 mean "unknown / never set this boot"; the capability
    // selector reports support only — the board's PM-table power budget is
    // not parsed, so there is no default-limit read-back.
    uint32_t pboPPTMilliwatts {0};
    uint32_t pboTDCMilliamps  {0};
    uint32_t pboEDCMilliamps  {0};
    uint32_t pboScalarPercentX100 {0};  // e.g. 200 = 2x
    
    // S4: returns true only when the silicon matches the Vermeer RSMU command
    // set documented in ryzen_smu rsmu_commands.md (family 0x19, 0x21-0x2F) —
    // the same gate as Curve Optimizer. Fail-closed everywhere else.
    bool pboLimitsSupported() const {
        return (cpuFamily == 0x19 && cpuModel >= 0x21 && cpuModel <= 0x2F) &&
               smuMailbox.supported;
    }
    // int setPBOLimit(uint32_t cmd, uint32_t value): shared SMU write path for
    // PPT/TDC/EDC/scalar; negative return maps like setCurveOptimizer.
    int setPBOLimit(uint32_t smuCmd, uint32_t arg, uint32_t &cacheSlot);

    // S5: one RSMU read command polled from the main timer (no arg in,
    // result arrives in the mailbox arg register after SMU_RSP_OK). Returns
    // the raw result word, or 0 on failure / unsupported silicon.
    uint32_t pollSmuRead(uint32_t smuCmd);
    // S5: refresh both boost-telemetry caches; throttled to one SMU round trip
    // per kSMU_BOOST_POLL_MIN_INTERVAL_MS (the main timer cadence is shorter).
    void pollBoostTelemetry();
    
    // S6: shared write path for the Vermeer cHTC thermal limit (SMU 0x56,
    // Arg0 = degrees Celsius). Same capability gate + thermal interlock policy
    // as setPBOLimit; on success the new limit is cached for read-back.
    // Negative return maps like setPBOLimit (-1 unsupported, -4 hot, -5 SMU
    // error, -10 timeout, -11 invalid cmd, -12 invalid args, -13 busy).
    int setCHTCLimit(uint32_t arg);
    
    // S6: one-shot read of the Vermeer ProcessorParameters bitfield (SMU 0x6F:
    // bit 0 IsOverclockable, bit 1 PBO support). Returns the raw word on OK,
    // else 0. Timer command gate only — never from user threads (F-05).
    uint32_t pollProcessorParameters();
    
    // S7: one-shot read of the SMU firmware version (global TestMessage-family
    // command 0x02, works on every mailbox). Returns the raw byte-packed
    // version word on OK, else 0. Timer command gate only (F-05).
    uint32_t pollSmuVersion();
    
    // S7: read of the SMU's active PBO scalar (Vermeer RSMU 0x6C — response
    // is an IEEE-754 float, unlike the 0x58 write encoding). Returns the raw
    // word on OK, else 0. Rides the boost-telemetry throttle window; timer
    // command gate only (F-05).
    uint32_t pollSmuPBOScalar();

    // S8: enable/disable Vermeer OC mode (RSMU 0x5A EnableOcMode / 0x5B
    // DisableOcMode — semantics pinned by ZenStates-Core, resolving the doc's
    // contradictory rows). Writes blocked under the same thermal interlock as
    // the PBO/CO/cHTC paths. On the disable path `resetScalar` additionally
    // re-programs the PBO scalar to 1.0 via 0x58, working around SMU firmware
    // that does not auto-reset it. Returns 0 on success; negative maps like
    // setPBOLimit.
    int setOcMode(bool enable, bool resetScalar);

    // S9a: SMU PM-table plumbing (0x08 version → per-version size → 0x05
    // transfer → 0x06 base → read-only map → snapshot copy). Called from the
    // main timer command gate only (F-05), throttled to one 0x05 + re-map
    // check per second. All state is diagnostic: user space reads the
    // SNAPSHOT, never the live mapping, and nothing in this path writes to
    // SMU-controlled memory. Read-only map is unmapped on sleep/shutdown
    // (kext stop path) like every other ioremap in this kext.
    void pollPMTable();
    // S9a: immediate capture (selector 57 op 2). Returns 0 on success,
    // else the mapped negative table from the S9a helpers. Runs under
    // rendezvousLock (UserClient) or on the timer command gate (F-05) —
    // the same policy as every other privileged SMU write path (CO/cHTC/PBO).
    int forcePMTableCapture();

    // S8.2: program a frequency override via the Vermeer RSMU OC commands —
    // all-core (0x5C, one call) or per-CCD (0x5D, one round trip per CCD;
    // Vermeer mask = (ccd << 28) | freq, see S_SERIES_ROADMAP.md §1.1).
    // Hard-gated: refuses with -3 unless THIS driver enabled OC mode via
    // 0x5A earlier this boot (we only send frequency writes after observing
    // the gate open ourselves — another tool's enable does not count).
    // Same Vermeer gate, thermal interlock and mapped-error policy as
    // setOcMode/setPBOLimit. Per-CCD writes are all-or-nothing per CCD:
    // a mid-sequence failure returns the mapped error and the cache keeps
    // only the CCDs that acknowledged OK.
    //   allCores: mhz in 400..8000 (doc MAX), perCcd must be null.
    //   perCcd:   window of ccdCount entries starting at CCD `startCcd`,
    //             each an absolute MHz in 400..8000. ccd index of entry i
    //             = startCcd + i.
    // Returns 0 on success; negative maps: -1 unsupported, -2 bad args,
    // -3 OC mode not enabled by this driver, -4 hot, -5 SMU error,
    // -10 timeout, -11 invalid cmd, -12 invalid args, -13 busy.
    int setOverclockFreqAllCores(uint32_t mhz);
    int setOverclockFreqPerCcd(const uint32_t *mhzByCcd, uint8_t ccdCount, uint8_t startCcd);

    //Cache size in KB
    uint32_t cpuCacheL1_perCore;
    uint32_t cpuCacheL2_perCore;
    uint32_t cpuCacheL3;
    
    char boardVendor[BASEBOARD_STRING_MAX]{};
    char boardName[BASEBOARD_STRING_MAX]{};
    bool boardInfoValid = false;
    
    
    /**
     *  Hard allocate space for cached readings.
     */
    float effFreq_perCore[CPUInfo::MaxCpus] {};
    float PACKAGE_TEMPERATURE_perPackage[CPUInfo::MaxCpus] {};
    
    uint64_t lastMPERF_perCore[CPUInfo::MaxCpus] {};
    uint64_t lastAPERF_perCore[CPUInfo::MaxCpus] {};
    uint64_t deltaMPERF_perCore[CPUInfo::MaxCpus] {};
    
    uint64_t instructionDelta_perCore[CPUInfo::MaxCpus] {};
    uint64_t lastInstructionDelta_perCore[CPUInfo::MaxCpus] {};
    
    float loadIndex_perCore[CPUInfo::MaxCpus] {};
    
    float PStateStepUpRatio = 0.36;
    float PStateStepDownRatio = 0.05;
    
    uint8_t PStateCur_perCore[CPUInfo::MaxCpus] {};
    uint8_t PStateCtl = 0;
    uint64_t PStateDef_perCore[8] {};
    uint8_t PStateEnabledLen = 0;
    float PStateDefClock_perCore[8];
    bool cpbSupported;
    
    
    uint64_t lastUpdateTime;
    uint64_t lastUpdateEnergyValue;
    
    double uniPackagePowerW;   // Average package power in watts (energy delta / time delta)
    
#pragma pack(push, 1)
    struct CPUSensorPacket {
        float packagePowerW;
        float packageTempC;
        uint32_t numLogicalCores; // Assigned total logical cores count per ABI spec
        uint32_t ccdCount;
        float ccdTemperatures[8];
        float coreFrequenciesMHz[64];
    };
#pragma pack(pop)

    // CPU capability profile per family/model
    // Each profile defines what features should be enabled for a given CPU.
    // - pmDispatchAllowed + legacyPstateAllowed = true on Zen 1/2 where
    //   macOS lacks native AMD power management.
    // - pmDispatchAllowed + legacyPstateAllowed = false on Zen 3+ where
    //   macOS AMD Vanilla handles CPPC natively — kext is telemetry-only.
    struct ZenCpuFeatureMap {
        uint32_t family;
        uint32_t modelStart;
        uint32_t modelEnd;
        const char *generationName;
        uint8_t zenGeneration;   // 1-5 for Zen 1 through 5
        bool supportsCPPC;
        bool supportsCPPCv2;
        bool legacyPstateAllowed;
        bool pmDispatchAllowed;
        bool temperatureOffset49;  // applies 49 C temperature offset to package temp
    };

    // === Family 17h profiles: need full PM dispatch (macOS has no native AMD PM) ===

    // Zen 1 (Summit Ridge, Whitehaven)
    static constexpr ZenCpuFeatureMap ZEN1_PROFILE = {
        0x17, 0x00, 0x0F, "Zen", 1,
        false, false,           // CPPC: no, CPPCv2: no
        true, true,             // legacyPstate: yes, pmDispatch: yes
        true                    // temperatureOffset49: hardware bit verified
    };
    // Zen+ (Pinnacle Ridge)
    static constexpr ZenCpuFeatureMap ZEN_PLUS_PROFILE = {
        0x17, 0x10, 0x2F, "Zen+", 1,
        false, false,
        true, true,
        true
    };
    // Zen 2 (Matisse, Rome)
    static constexpr ZenCpuFeatureMap ZEN2_PROFILE = {
        0x17, 0x30, 0xFF, "Zen 2", 2,
        false, false,
        true, true,
        true
    };

    // === Family 19h+ profiles: telemetry-only (macOS AMD Vanilla handles CPPC) ===

    // Zen 3 Cezanne (mobile)
    static constexpr ZenCpuFeatureMap ZEN3_CEZANNE_PROFILE = {
        0x19, 0x10, 0x1F, "Zen 3 Cezanne", 3,
        true, false,            // CPPC: yes, CPPCv2: no
        false, false,           // legacyPstate: no, pmDispatch: no
        true
    };
    // Zen 3 Vermeer (desktop)
    static constexpr ZenCpuFeatureMap ZEN3_VERMEER_PROFILE = {
        0x19, 0x21, 0x2F, "Zen 3 Vermeer", 3,
        true, false,
        false, false,
        true
    };
    // Zen 3+ (Rembrandt, Barcelo)
    static constexpr ZenCpuFeatureMap ZEN3_PLUS_PROFILE = {
        0x19, 0x40, 0x5F, "Zen 3+", 3,
        true, false,
        false, false,
        true
    };
    // Zen 4 (Raphael, Phoenix)
    static constexpr ZenCpuFeatureMap ZEN4_PROFILE = {
        0x19, 0x60, 0x7F, "Zen 4", 4,
        true, false,
        false, false,
        true                    // temperatureOffset49: verified working
    };
    // Zen 5 (Granite Ridge, Strix Point)
    static constexpr ZenCpuFeatureMap ZEN5_PROFILE = {
        0x1A, 0x00, 0xFF, "Zen 5", 5,
        true, false,
        false, false,
        true                    // temperatureOffset49: verified working on 9950X3D
    };

    // Feature matrix - controlled per-profile
    bool cppcReadInInit {false};       // Read CPPC CAP1 during workloop init
    bool legacyPstateAllowed {false};  // Legacy P-state writes
    bool pmDispatchAllowed {false};    // Custom PM dispatch takeover
    bool temperatureOffset49 {false};  // Apply 49C temperature offset (per profile)

    // Derived state
    uint32_t zenGeneration = 0;
    bool supportsCPPC = false;
    bool supportsCPPCv2 = false;

    bool disablePrivilegeCheck = false;
    uint16_t savedSMCChipIntel = 0;
    SInt32 kextloadAlerts = 0;
    /// Ensures kunc_alert modal is shown at most once until the user dismisses/clears it.
    /// SInt32 for OSCompareAndSwap (audit R-6).
    SInt32 kextAlertDisplayed = 0;

    kern_return_t (*kunc_alert)(int,unsigned,const char*,const char*,const char*,
                                const char*,const char*,const char*,const char*,const char*,unsigned*) {nullptr};
    
    
    ISSuperIOSMCFamily *superIO{nullptr};
    IOLock *superIOLock{nullptr};   // Protects multi-step SuperIO I/O port sequences from concurrent UserClient calls
    IOLock *smuCmdLock{nullptr};    // Serializes full SMU command sequences (audit R-8).
                                    // Lock order: rendezvousLock → smuCmdLock (S5 timer boost-telemetry
                                    // poll) and controlLock → smuCmdLock (CO/PBO writes). smuCmdLock is
                                    // always a leaf — never take another lock while holding it.
    IOLock *rendezvousLock{nullptr}; // Serializes all mp_rendezvous calls (timer + UserClient control ops)
    IOLock *controlLock{nullptr};   // Serializes provider state writes (PStateCtl, CPPC) from concurrent UserClients (audit K-2)
    
    static constexpr size_t kMAX_FANS = 16;
    FanCurveConfig fanCurves[MAX_FAN_CURVES];
    int8_t fanToCurveMap[kMAX_FANS]; // Maps each physical fan index to a curve index (-1 = Auto)
    uint8_t lastAppliedPWM[kMAX_FANS];
    uint64_t lastPWMUpdateTime[kMAX_FANS];
    
    static_assert(sizeof(fanToCurveMap) / sizeof(fanToCurveMap[0]) == kMAX_FANS, "fan array size mismatch");
    static_assert(sizeof(lastAppliedPWM) / sizeof(lastAppliedPWM[0]) == kMAX_FANS, "fan array size mismatch");
    static_assert(sizeof(lastPWMUpdateTime) / sizeof(lastPWMUpdateTime[0]) == kMAX_FANS, "fan array size mismatch");
    float gpuTempC;
    float curveSmoothedTemp[MAX_FAN_CURVES];
    bool curveSmoothedSeeded[MAX_FAN_CURVES] {};
    // S10 KRN-01: per-curve trust flag for the smoothed temperature, plus the
    // unsmoothed sample the emergency guard must be evaluated against.
    // curveSmoothedValid[c] == false means "no trustworthy reading this tick"
    // and forces kFAILSAFE_PWM instead of lut[0].
    bool curveSmoothedValid[MAX_FAN_CURVES] {};
    float curveRawSourceTemp[MAX_FAN_CURVES] {};
    // AUDIT F-14: per-curve anchor temperature for downward hysteresis
    float lastAppliedTemp[MAX_FAN_CURVES];
    bool lastAppliedTempSeeded[MAX_FAN_CURVES] {};

    // GPU monitoring (added)
    AMDGPUDevice *gpuDevices[16] {};
    uint32_t gpuCount {0};
    UInt16 gpuTemperatures[16] {};
    float gpuPowers[16] {};

    uint32_t getGPUCount() { return gpuCount; }
    IOReturn getGPUTemperature(uint32_t index, UInt16 *data);
    IOReturn getGPUPower(uint32_t index, float *data);
    bool gpuSupportsPower(uint32_t index);

    // S5: cached boost telemetry (Vermeer RSMU read commands 0x6E/0x59).
    // Refreshed from the main command-gate timer; 0 = unknown / never read
    // this boot. Raw SMU response words are cached byte-identically (no
    // kernel-side decode) so the app owns the decode — keep it that way and
    // decode in AMDSmuBoost on the app side, where it is unit-testable.
    uint32_t smuMaxBoostFreqMHz {0};
    uint32_t smuFastestCoreRaw {0};
    uint64_t smuBoostTelemetryLastPollMs {0};

    // S6: cached ProcessorParameters bitfield (Vermeer RSMU 0x6F). Static
    // silicon configuration, so it is read once from the timer command gate
    // and cached; smuProcParamsPolled distinguishes a real 0 response from
    // "never read this boot". Raw word cached byte-identically — decode in
    // AMDSmuParameters on the app side, where it is unit-testable.
    uint32_t smuProcessorParametersRaw {0};
    bool smuProcParamsPolled {false};

    // S6: cHTC limit cache — the last value successfully programmed via SMU
    // 0x56 this boot (0 = never set). The SMU has no read command for cHTC;
    // the kext caches on success, same as the PBO limits.
    uint32_t smuCHTCLimitCelsius {0};

    // S7: cached SMU readbacks. The 0x02 firmware version is static — read
    // once and kept. The 0x6C PBO scalar reflects live SMU state (what Ryzen
    // Master / the firmware actually apply), so it re-reads inside the boost
    // poll's 500 ms throttle window and pairs with the 0x58 write cache for
    // drift detection. Both words are cached raw; decode in AMDSmuReadback
    // app-side, where it is unit-testable.
    uint32_t smuFirmwareVersionRaw {0};
    bool smuVersionPolled {false};
    uint32_t smuActiveScalarRaw {0};

    // S8: OC-mode state cache — mirrors the last 0x5A/0x5B outcome this boot
    // (0 = never touched by this driver, 1 = enabled via 0x5A, 2 = disabled
    // via 0x5B). The SMU has no read-back for OC mode; the cache is written
    // only on SMU_OK, and 0 honestly means "unknown" (another tool may have
    // flipped the mode before we loaded).
    uint32_t smuOcModeState {0};

    // S8.2: frequency-override caches (0x5C all-core / 0x5D per-CCD). 0 =
    // never written by this driver this boot; on success each slot holds the
    // absolute MHz last acknowledged by the SMU. Driver-local truth only:
    // the SMU has no read-back for these commands.
    static constexpr uint8_t kS8MaxCcds = 8;   // Vermeer tops out well below
                                               // this; kept in step with the
                                               // CPUSensorPacket CCD cap.
    uint32_t ocFreqMHzAllCores {0};
    uint32_t ocFreqMHzPerCcd[kS8MaxCcds] {0};

    // S9a: SMU PM-table plumbing (Vermeer RSMU 0x05/0x06/0x08 — the same
    // table ryzen_smu/HWiNFO feed from). The table lives at a SMU-provided
    // physical address in DRAM; the kext maps it read-only and snapshots it
    // into a fixed buffer that user space reads through selector 57.
    static constexpr uint32_t kPM_TABLE_MAX_SIZE = 0x2000;   // covers every documented Vermeer size (max 0x1BB0)
    static constexpr uint64_t kPM_REFRESH_MIN_INTERVAL_MS = 1000; // one 0x05 + re-map check per second, worst case
    uint64_t pmRefreshLastPollMs {0};
    uint32_t pmTableVersionRaw {0};          // 0x08 response (BCD-style, e.g. 0x380904 → 38.09.04)
    bool     pmTableVersionPolled {false};
    uint64_t pmDramBase {0};                 // physical base from 0x06 (0 = unknown)
    uint32_t pmTableSize {0};                // documented size for the detected version (0 = unknown version)
    uint8_t  pmTableSnapshot[kPM_TABLE_MAX_SIZE] {0};
    uint64_t pmTableCapturedMs {0};          // timestamp of the last successful capture
    bool     pmMapValid {false};             // snapshot reflects a successful 0x05+capture cycle

    // S3-B: read-only view for the UserClient capability report (selector 35).
    // Exposes only the fields the CO capability needs; keeps the rest of the
    // mailbox (SMN register layout) private.
    bool smuMailboxSupported() const { return smuMailbox.supported; }
    uint32_t smuCurveOptimizerCmd() const { return smuMailbox.curveOptimizerCmd; }

    // S9d: on-demand mailbox health report (UserClient selector 58). Runs the
    // same three probes the boot diagnostic does — SMN aperture read (Tctl),
    // TestMessage round-trip (0x01: documented Res0 = Arg0 + 1, so arg
    // 0x42 expects 0x43 back) and GetSMUVersion
    // (0x02) — and returns every raw code plus the SMN read word, so the app
    // can render a full health report without touching log show. Adds SMU
    // mailbox traffic on demand, hence the privilege gate lives in the
    // UserClient (same policy as selector 57 op 2). Serialized under
    // rendezvousLock by the caller (UserClient convention for timer-context
    // capture paths); smuCmdLock remains the inner leaf.
    struct SMUDiagnosticReport {
        uint32_t mailboxSupported;   // 1 when the family mailbox descriptor is live
        uint32_t msgReg;             // mailbox descriptor registers (0 when unsupported)
        uint32_t argReg;
        uint32_t rspReg;
        uint32_t curveOptimizerCmd;
        uint32_t smnTctlRaw;         // SMN 0x59800 read word (Tctl encoding)
        int      testRsp;            // smuSendCmd result code for 0x01 (SMUResponse / timeout)
        uint32_t testArg0;           // arg-window word after the echo (0x43 expected)
        uint32_t testElapsedUs;
        int      versionRsp;         // smuSendCmd result code for 0x02
        uint32_t versionRaw;         // arg-window word (BCD-packed version)
        uint32_t versionElapsedUs;
    };
    bool runMailboxDiagnostics(SMUDiagnosticReport &out);

private:
    IOWorkLoop *workLoop;
    IOTimerEventSource *timerEvent_main;
    IOTimerEventSource *timerEvent_tempe;
    
    bool serviceInitialized = false;
    
    uint32_t updateTimeInterval = 1000;
    uint32_t actualUpdateTimeInterval = 1;
    uint64_t timeOfLastUpdate = 0;
    uint64_t estimatedRequestTimeInterval = 0;
    uint64_t timeOfLastMissedRequest = 0;
    
    int tempNextSample = 0;
    float tempSamples[HF_TEMP_SAMPLE_LEN];
    float tempOffset = 0;
    double pwrTimeUnit = 0;
    double pwrEnergyUnit = 0;
    uint64_t pwrLastTSC = 0;
    
    uint64_t xnuTSCFreq = 1;
    int (*wrmsr_carefully)(uint32_t, uint32_t, uint32_t) {nullptr};
    
    CPUInfo::CpuTopology cpuTopology {};
    
    IOPCIDevice *fIOPCIDevice{nullptr};
    IOSimpleLock *pciConfigLock{nullptr};
    
    KernelPatcher *liluKernelPatcher;
    
    bool getPCIService();
    void enumerateGPUs();
    bool wentToSleep{false};
    /// Set by resumeWorkLoop() on S3 wake. The main timer processes it on its
    /// first tick (workLoop thread) so reinitHwState() never runs on the PM thread.
    bool pendingReinit{false};
    
    uint32_t smnRead32(uint32_t addr);
    void smnWrite32(uint32_t addr, uint32_t val);
    int smuSendCmd(uint32_t cmd, uint32_t arg);
    int smuSendCmd(uint32_t cmd, uint32_t arg, uint32_t &outArg0, uint32_t *outElapsedUs = nullptr);
    // S9a: two-argument variant returning both arg-window words after OK —
    // GetDramBaseAddress (0x06) is called with Arg0=1/Arg1=1 on Vermeer and
    // the 64-bit physical base assembles as arg0 | (arg1 << 32)
    // (reference smu.c smu_get_dram_base_address, BASE_ADDR_CLASS_1).
    int smuSendCmd2(uint32_t cmd, uint32_t arg0, uint32_t arg1,
                    uint32_t &outArg0, uint32_t &outArg1, uint32_t *outElapsedUs = nullptr);

    struct SMUMailbox {
        uint32_t msgReg;
        uint32_t argReg;
        uint32_t rspReg;
        uint32_t curveOptimizerCmd;   // 0x3D on Zen 3, 0x55 on Zen 4 (per AGESA), 0x0 (unsupported) otherwise
        bool     supported;
    };
    SMUMailbox smuMailbox{};

    // S5: SMU read commands ride the main timer's command gate. The throttle
    // keeps the added SMU traffic to ~2 round trips per second worst case.
    static constexpr uint64_t kSMU_BOOST_POLL_MIN_INTERVAL_MS = 500;
    
    void initWorkLoop();
    void stopWorkLoop();
    void resumeWorkLoop();
};
#endif
