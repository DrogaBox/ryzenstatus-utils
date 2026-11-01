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

// Hardware safety bounds for curve-mode fan output.
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

    static constexpr uint32_t kF17H_M01H_THM_TCON_CUR_TMP = 0x00059800;
    // Tctl register fields (Linux k10temp ZEN_CUR_TEMP_*): the reading is
    // 49 C high when the range-select bit is set or both TJ-select bits are.
    static constexpr uint32_t kZEN_CUR_TEMP_RANGE_SEL = 1u << 19;
    static constexpr uint32_t kZEN_CUR_TEMP_TJ_SEL_MASK = 3u << 16;
    // SMN index/data pair in the root complex's configuration space.
    static constexpr uint8_t kSMN_INDEX_REGISTER = 0x60;

    // SVI2 voltage telemetry (LibreHardwareMonitor Amd17Cpu.cs, zenpower):
    // the SMU mirrors the VRM's serial-VID interface at SMN 0x5A000. 0x5A008
    // holds the per-plane telemetry-function bits (bit 0 core plane off,
    // bit 1 SoC plane off); the plane registers carry the requested VID in
    // bits [23:16], 1.550 V - VID * 6.25 mV. Which plane register is core and
    // which is SoC depends on the model (see probeSviTelemetry). Zen 4/5 use
    // SVI3 with a different encoding, so they get no voltage from this path.
    static constexpr uint32_t kF17H_M01H_SVI = 0x0005A000;
    static constexpr uint32_t kF17H_M01H_SVI_TFN = kF17H_M01H_SVI + 0x8;
    static constexpr uint32_t kSVI_TFN_CORE_PLANE_OFF = 1u << 0;
    static constexpr uint32_t kSVI_TFN_SOC_PLANE_OFF = 1u << 1;

    static constexpr uint16_t kAMD_HOST_BRIDGE_VENDOR = 0x1022;

    // Per-CCD temperature registers live at 0x59800 + offset + 4 * ccd; the
    // offset and the number of CCD slots depend on the family and model
    // (Linux k10temp_probe). A slot reports a CCD when bit 11 is set.
    static constexpr uint8_t  kMAX_CCD_COUNT = 8;
    static constexpr uint32_t kZEN_CCD_TEMP_VALID_BIT = (1 << 11);
    static constexpr uint32_t kZEN_CCD_TEMP_MASK = 0x7FF;

    // Mailbox status. 0x01 and 0xFC-0xFF are the firmware's own codes
    // (ryzen_smu smu_return_val, ZenStates-Core SMU.Status); 0x00 and 0xFB
    // are reported by this driver when the firmware never answered.
    enum SMUResponse : uint32_t {
        SMU_RSP_TIMEOUT         = 0x00,  // no reply before the deadline
        SMU_RSP_OK              = 0x01,
        SMU_RSP_NOT_READY       = 0xFB,  // previous command still running, nothing sent
        SMU_RSP_REJECTED_BUSY   = 0xFC,
        SMU_RSP_REJECTED_PREREQ = 0xFD,
        SMU_RSP_UNKNOWN_CMD     = 0xFE,
        SMU_RSP_FAILED          = 0xFF,
    };

    static constexpr uint32_t kMSR_HWCR = 0xC0010015;
    static constexpr uint32_t kMSR_PKG_ENERGY_STAT = 0xC001029B;
    static constexpr uint32_t kMSR_CORE_ENERGY_STAT = 0xC001029A;
    static constexpr uint32_t kMSR_PSTATE_0 = 0xC0010064;
    static constexpr uint32_t kMSR_PSTATE_LEN = 8;
    static constexpr uint32_t kMSR_PSTATE_CTL = 0xC0010062;
    static constexpr uint32_t kMSR_RAPL_PWR_UNIT = 0xC0010299;
    static constexpr uint32_t kMSR_MPERF = 0x000000E7;
    static constexpr uint32_t kMSR_APERF = 0x000000E8;
    static constexpr uint32_t kMSR_PERF_IRPC = 0xC00000E9;
    static constexpr uint32_t kMSR_CSTATE_ADDR = 0xC0010073;
    static constexpr uint32_t kMSR_AMD_CPPC_CAP1 = 0xC00102B0;
    // CPPC_ENABLE bit 0 hands frequency selection to the CPU's CPPC
    // controller; once set it stays set until reset. CPPC_REQ: [7:0] max
    // perf, [15:8] min perf, [23:16] desired perf (0 = autonomous),
    // [31:24] EPP (0 = performance, 0xFF = power saving).
    static constexpr uint32_t kMSR_AMD_CPPC_ENABLE = 0xC00102B1;
    static constexpr uint32_t kMSR_AMD_CPPC_REQ = 0xC00102B3;




    virtual bool init(OSDictionary *dictionary = 0) override;
    virtual void free(void) override;

    virtual bool start(IOService *provider) override;
    virtual void stop(IOService *provider) override;

    virtual IOReturn setPowerState(unsigned long powerStateOrdinal, IOService* whatDevice) override;

    void fetchOEMBaseBoardInfo();

    // Fan telemetry (tachometers + control mode) is re-read from the Super
    // I/O at most once per kFAN_TELEMETRY_MIN_INTERVAL_MS, from the sensor
    // timer and on demand by selectors 93/94; everything else (SMC fan keys,
    // the selectors' output) is served from the driver's cache, so the port
    // traffic stays bounded however many readers there are. The limit is the
    // cadence SMCSuperIO polls at. Caller holds superIOLock.
    static constexpr uint64_t kFAN_TELEMETRY_MIN_INTERVAL_MS = 1000;
    uint64_t fanTelemetryLastMs {0};
    void refreshFanTelemetryIfStale();

    // Cached fan readings for the SMC plugin, never touching the hardware.
    // fanCount() takes superIOLock briefly (the chip object can be replaced
    // by a re-probe) and runs once, when the plugin builds its keys; it is
    // 0 without a detected chip. fanRPM() backs the FxAc keys and reads
    // fanRPMCache[] without a lock, so an SMC read never waits behind the
    // sensor timer's port I/O (acidanthera's sensor plugins keep their key
    // reads lock-free too).
    int fanCount();
    uint32_t fanRPM(int fan);

    bool read_msr(uint32_t addr, uint64_t *value);
    bool write_msr(uint32_t addr, uint64_t value);


    // Per-CPU samplers run inside the main rendezvous. With seedOnly they
    // only store fresh baselines: the first window after the sampler was
    // idle would span the pause, so it is dropped instead of published.
    void calculateEffectiveFrequency(uint32_t physical, bool seedOnly);
    void updateInstructionDelta(uint32_t cpu, bool seedOnly);
    // IRPerfCount (MSR C000_00E9) is 48 bits wide.
    static constexpr uint64_t kIRPERF_MASK = (1ULL << 48) - 1;
    void applyPowerControl();
    /// Programs CPPC_ENABLE/CPPC_REQ on every CPU from cppcActiveMode,
    /// cppcEPPValue and cppcThrottled. Takes rendezvousLock; the Locked
    /// variant is for callers that already hold it. False when the CPU has
    /// no MSR CPPC or any CPU refused the write.
    bool applyEPPControl();
    bool applyEPPControlLocked();

    void setCPBState(bool enabled);
    bool getCPBState();

#define HF_TEMP_SAMPLE_SECS 3
#define HF_TEMP_SAMPLE_FREQ 2
#define HF_TEMP_SAMPLE_LEN (HF_TEMP_SAMPLE_SECS * HF_TEMP_SAMPLE_FREQ)
#define HF_TEMP_SAMPLE_LENREP (1.0f / (float)HF_TEMP_SAMPLE_LEN)
#define HF_TEMP_SAMPLE_REP (1.0f / (float)HF_TEMP_SAMPLE_FREQ)
#define HF_TEMP_SAMPLE_PERIOD (int)(HF_TEMP_SAMPLE_REP * 1000.0)
    inline float getPackageTemp();
    float getCCDTemp(uint8_t slot);
    void probeCCDs();
    void updatePackageTemp();

    void updatePackageEnergy();

    void registerRequest();

    // canLog = false inside mp_rendezvous handlers: IOLog takes locks that an
    // interrupted thread may hold, and every CPU is parked in the rendezvous.
    // Rendezvous handlers run in interrupt context on top of whatever thread
    // each CPU was running, and xnu does not save that thread's FPU/XMM
    // state for them, so they stay integer-only: readPstateDefs() there,
    // decodePstateClocks() afterwards on the work loop thread. dumpPstate()
    // does both and is for thread context only.
    void readPstateDefs(bool canLog);
    void decodePstateClocks(bool canLog);
    void dumpPstate(bool canLog = true);
    void reinitHwState();
    void writePstate(const uint64_t *buf);

    bool initSuperIO(uint16_t* chipIntel, bool allowUnlock = true);
    void evaluateFanCurves();

    uint32_t getPMPStateLimit();
    void setPMPStateLimit(uint32_t);

    uint32_t getHPcpus();
    int setCurveOptimizer(uint8_t core, int8_t offset);

    uint32_t totalNumberOfPhysicalCores {0};
    uint32_t totalNumberOfLogicalCores {0};

    bool cppcSupported {false};
    /// CPUID 8000_0008h EBX[27]: CPPC is driven through MSRs, so EPP can be
    /// programmed. Without it CPPC lives in ACPI shared memory only.
    bool cppcMsrSupported {false};
    /// EPP reaches the CPU through MSRs or through ACPI CPPC (PCC).
    bool cppcEppSupported() const { return cppcMsrSupported || acpiCppc.supported; }

    // ACPI CPPC over PCC shared memory (Linux amd-pstate "shared memory"
    // mode): each processor's _CPC names registers in a PCC subspace of the
    // PCCT. Used when the CPPC MSRs are missing (Ryzen 5000 desktop, among
    // others). Discovered once at start; selector 63 reports what was found.
    struct AcpiGas {
        uint8_t  space;       // 0 memory, 1 IO, 0x0A PCC, 0x7F FFH
        uint8_t  bitWidth;
        uint8_t  bitOffset;
        uint8_t  accessSize;  // PCC: subspace index
        uint64_t address;     // PCC: offset after the 8-byte channel header
    };
    struct CpcValue {
        bool     isRegister;
        uint64_t integer;     // when !isRegister
        AcpiGas  reg;
    };
    // The _CPC package entries this driver uses (ACPI 6.x, 8.4.6.1).
    enum CpcIndex : uint8_t {
        kCpcHighest = 2, kCpcNominal = 3, kCpcLowestNonlinear = 4, kCpcLowest = 5,
        kCpcDesired = 7, kCpcMin = 8, kCpcMax = 9, kCpcEnable = 16, kCpcAutoSel = 17,
        kCpcEpp = 19,
    };
    static constexpr uint8_t kCpcUsed[] = { kCpcHighest, kCpcNominal, kCpcLowestNonlinear, kCpcLowest,
                                            kCpcDesired, kCpcMin, kCpcMax, kCpcEnable, kCpcAutoSel, kCpcEpp };
    static constexpr uint32_t kCpcUsedCount = sizeof(kCpcUsed);
    // Positions in kCpcUsed (and in AcpiCppcState::cpc[cpu]).
    enum CpcSlot : uint8_t {
        kSlotHighest, kSlotNominal, kSlotLowestNonlinear, kSlotLowest, kSlotDesired,
        kSlotMin, kSlotMax, kSlotEnable, kSlotAutoSel, kSlotEpp,
    };
    static constexpr uint32_t kPccMaxSubspaces = 8;
    struct PccSubspace {
        bool          present;
        uint8_t       type;           // PCCT subspace type 0, 1 or 2
        uint64_t      base, length;   // shared memory
        AcpiGas       doorbell;
        uint64_t      preserve, write;
        uint32_t      latencyUs;      // nominal latency
        uint16_t      turnaroundUs;   // minimum request turnaround
        IOMemoryMap  *shm;
        IOMemoryMap  *doorbellMap;    // when the doorbell is in memory
        uint64_t      lastCmdNs;
    };
    struct AcpiCppcState {
        bool        supported;
        uint8_t     error;            // 0 ok, else AcpiCppcError
        uint32_t    cpuCount;         // processors with a usable _CPC
        uint32_t    cpcRevision;
        CpcValue    cpc[CPUInfo::MaxCpus][kCpcUsedCount];
        PccSubspace pcc[kPccMaxSubspaces];
        uint16_t    lastStatus;       // channel status after the last command
        int32_t     lastResult;       // 0 ok, -1 timeout, -2 error bit, -3 not ready
    } acpiCppc {};
    enum AcpiCppcError : uint8_t {
        kAcpiCppcOk = 0, kAcpiCppcNoPlane, kAcpiCppcNoCpc, kAcpiCppcBadCpc,
        kAcpiCppcNotPcc, kAcpiCppcNoPcct, kAcpiCppcBadPcct, kAcpiCppcMapFailed,
        kAcpiCppcCountMismatch,
    };
    void discoverAcpiCppc(IOService *provider);
    void releaseAcpiCppc();
    bool pccCommand(PccSubspace &ss, uint16_t command);
    bool cpcRead(const CpcValue &v, uint64_t &out);
    bool cpcWrite(const CpcValue &v, uint64_t value);
    bool applyEPPPcc(uint8_t epp);
    bool applyEPPMsr(uint8_t epp);
    /// Wanted: CPPC autonomous mode with cppcEPPValue (selector 24/25 or
    /// the -amdcppcactive boot-arg).
    bool cppcActiveMode {false};
    uint8_t cppcEPPValue {0x3F};
    /// CPPC_ENABLE was written this power cycle; S3 clears it with the cores.
    bool cppcEngaged {false};
    /// The EPP the last successful applyEPPControl() wrote to every CPU.
    uint8_t cppcAppliedEPP {0};
    uint8_t cppcHighestPerf_perCore[CPUInfo::MaxCpus] {};
    bool cppcThrottled {false};
    // CC6 idle (selector 61). The kext owns the idle loop on every supported
    // family unless `-amdnoidle`; amdcstate=1 forbids CC6, otherwise the app
    // switches it on and off live. cstateIoBase is the firmware's
    // CSTATE_ADDR[15:0], read before anything else touches the MSR.
    bool idleDispatchActive {false};
    bool c6Forbidden {false};
    uint16_t cstateIoBase {0};
    bool c6IdleActive {false};
    bool c6IdleSupported() const { return idleDispatchActive && !c6Forbidden && cstateIoBase != 0; }
    bool setC6Idle(bool on);
    uint64_t cstateAddrConfig {0};

    uint8_t cpuFamily {0};
    uint8_t cpuModel {0};
    uint8_t cpuSupportedByCurrentVersion {0};

    // ccdTemperatures[i] belongs to the CCD in register slot ccdSlot[i];
    // fused-off CCDs leave gaps in the slots, never in this array.
    uint32_t ccdOffset {0};
    uint8_t  ccdCount = 0;
    uint8_t  ccdSlot[kMAX_CCD_COUNT] {};
    float    ccdTemperatures[kMAX_CCD_COUNT] {};
    char     cpuArchName[16] {};

    // Curve Optimizer offsets last acknowledged by the SMU (selector 110)
    int8_t curveOptimizerOffsets[CPUInfo::MaxCpus] {};
    // SMU core mask (CCD [31:28], core [23:20]) of each enabled core, in the
    // order the OS numbers them; built from the fuses in buildCoreMap().
    uint32_t coreSmuMask[CPUInfo::MaxCpus] {};
    bool coreMapValid {false};

    // Precision Boost Overdrive limits (Vermeer-only SMU commands).
    // Values are the last successfully-programmed limits, cached for read-back
    // (the SMU has no read command for these — same approach as the CO cache).
    // Defaults of 0 mean "unknown / never set this boot"; the capability
    // selector reports support only — the board's PM-table power budget is
    // not parsed, so there is no default-limit read-back.
    uint32_t pboPPTMilliwatts {0};
    uint32_t pboTDCMilliamps  {0};
    uint32_t pboEDCMilliamps  {0};
    uint32_t pboScalarPercentX100 {0};  // e.g. 200 = 2x

    // Feature gates, all derived from the detected family's SMU command set
    // (selectSmuCommandSet) and reported to the app by selector 62.
    bool smuPptLimitsSupported() const { return rsmu.supported && smuCmd.setPpt && smuCmd.setTdc && smuCmd.setEdc; }
    bool smuApuLimitsSupported() const { return rsmu.supported && smuCmd.setStapm && smuCmd.setFast && smuCmd.setSlow; }
    bool smuTctlSupported() const      { return rsmu.supported && smuCmd.setTctl; }
    bool smuScalarSupported() const    { return rsmu.supported && smuCmd.setScalar; }
    bool smuOcSupported() const        { return rsmu.supported && smuCmd.ocEnable && smuCmd.ocDisable && smuCmd.ocClkAll; }
    bool smuOcPerCcdSupported() const  { return smuOcSupported() && smuCmd.ocClkPerCore && coreMapValid; }
    bool smuOcVidSupported() const     { return smuOcSupported() && smuCmd.ocVid; }
    bool smuCoPerCoreSupported() const { return mp1.supported && smuCmd.mp1CoPerCore && coreMapValid; }
    bool smuCoAllSupported() const     { return mp1.supported && smuCmd.mp1CoAll; }
    bool smuBoostLimitSupported() const { return mp1.supported && smuCmd.mp1BoostLimit; }
    bool smuPmTableSupported() const   { return rsmu.supported && smuCmd.pmVersion && smuCmd.pmBase && smuCmd.pmTransfer; }
    // Shared RSMU write path for the power limits and the scalar: thermal
    // interlock, one command, cache on success. cmd 0 (not on this family)
    // returns -1; other negatives map like setCurveOptimizer.
    int setPBOLimit(uint32_t cmd, uint32_t arg, uint32_t &cacheSlot);
    // Power limits for selector 41: PPT/TDC/EDC on desktop parts, or PPT as
    // the STAPM, fast and slow limits on APUs (TDC/EDC have no APU command).
    int setPowerLimits(uint32_t pptMilliwatts, uint32_t tdcMilliamps, uint32_t edcMilliamps);
    int setPboScalar(uint32_t percentX100);
    // OC VID (SVI2), all-core Curve Optimizer and boost ceiling (selectors
    // 65-67). Same thermal interlock and error mapping as setPBOLimit.
    int setOcVid(uint32_t vid);
    int setCurveOptimizerAll(int8_t offset);
    int setBoostLimit(uint32_t mhz);
    uint32_t ocVidCache {0};               // last VID this driver wrote (0 = none)
    int8_t   curveOptimizerAllCache {0};
    bool     curveOptimizerAllSet {false};
    uint32_t boostLimitMHzCache {0};       // 0 = never set this boot

    // Refresh both boost-telemetry caches; throttled to one SMU round trip
    // per kSMU_BOOST_POLL_MIN_INTERVAL_MS (the main timer cadence is shorter).
    void pollBoostTelemetry();

    // Shared write path for the Vermeer cHTC thermal limit (SMU 0x56,
    // Arg0 = degrees Celsius). Same capability gate + thermal interlock policy
    // as setPBOLimit; on success the new limit is cached for read-back.
    // Negative return maps like setPBOLimit (-1 unsupported, -4 hot, -5 SMU
    // error, -10 timeout, -11 unknown command, -12 rejected, -13 busy).
    int setCHTCLimit(uint32_t arg);

    // One-shot read of the Vermeer ProcessorParameters bitfield (SMU 0x6F:
    // bit 0 IsOverclockable, bit 1 PBO support). Returns the raw word on OK,
    // else 0. Timer command gate only — never from user threads.
    uint32_t pollProcessorParameters();

    // One-shot read of the SMU firmware version (global TestMessage-family
    // command 0x02, works on every mailbox). Returns the raw byte-packed
    // version word on OK, else 0. Timer command gate only.
    uint32_t pollSmuVersion();

    // Enable/disable Vermeer OC mode (RSMU 0x5A / 0x5B, Arg0 0). Writes are
    // blocked under the same thermal interlock as the PBO/CO/cHTC paths. On
    // disable, `resetScalar` also writes the PBO scalar back to 1.0 via 0x58
    // for SMU firmware that does not reset it. Returns 0 on success;
    // negative maps like setPBOLimit.
    int setOcMode(bool enable, bool resetScalar);

    // SMU PM-table plumbing (0x08 version → per-version size → 0x05
    // transfer → 0x06 base → read-only map → snapshot copy). Called from the
    // main timer command gate only, throttled to one 0x05 + re-map
    // check per second. All state is diagnostic: user space reads the
    // SNAPSHOT, never the live mapping, and nothing in this path writes to
    // SMU-controlled memory. Read-only map is unmapped on sleep/shutdown
    // (kext stop path) like every other ioremap in this kext.
    void pollPMTable();
    // Immediate capture (selector 57 op 2). Returns 0 on success,
    // else the mapped negative table from the PM-table helpers. Runs under
    // rendezvousLock (UserClient) or on the timer command gate —
    // the same policy as every other privileged SMU write path (CO/cHTC/PBO).
    int forcePMTableCapture();

    // Program a frequency override via the Vermeer RSMU OC commands:
    // all-core (0x5C, one call) or per-CCD (0x5D to every core of the CCD).
    // Refuses with -3 unless this driver enabled OC mode via 0x5A earlier
    // this boot (another tool's enable does not count). Same Vermeer gate,
    // thermal interlock and error mapping as setOcMode/setPBOLimit. A
    // failure stops a per-CCD sequence; the cache keeps only the CCDs that
    // were fully written.
    //   allCores: mhz in 400..8000.
    //   perCcd:   windowLen entries starting at enabled-CCD index
    //             `startCcd`, each an absolute MHz in 400..8000.
    // Returns 0 on success; negative maps: -1 unsupported, -2 bad args,
    // -3 OC mode not enabled by this driver, -4 hot, -5 SMU error,
    // -10 timeout, -11 unknown command, -12 rejected, -13 busy.
    int setOverclockFreqAllCores(uint32_t mhz);
    int setOverclockFreqPerCcd(const uint32_t *mhzByCcd, uint8_t windowLen, uint8_t startCcd);

    //Cache size in KB
    uint32_t cpuCacheL1_perCore {0};
    uint32_t cpuCacheL2_perCore {0};
    uint32_t cpuCacheL3 {0};

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
    // Raw counter deltas of the last window, written by the rendezvous
    // (integer only) and turned into MHz / watts by finishCoreSamples() on
    // the work loop thread. A zero MPERF / TSC delta marks a skipped window,
    // which keeps the previous reading.
    uint64_t freqDeltaAPERF_perCore[CPUInfo::MaxCpus] {};
    uint64_t freqDeltaMPERF_perCore[CPUInfo::MaxCpus] {};
    void finishCoreSamples();

    uint64_t instructionDelta_perCore[CPUInfo::MaxCpus] {};
    uint64_t lastInstructionDelta_perCore[CPUInfo::MaxCpus] {};

    // Per-logical-CPU C0 residency from MPERF against the TSC: MPERF counts
    // at the P0 reference rate only while the CPU is in C0, the TSC always,
    // so dMPERF / dTSC over one sampling window is the share of time the CPU
    // was running (Linux turbostat Busy%). Works on every Zen family and
    // needs no PM-dispatch takeover, unlike the pmAMDRyzen idle accounting,
    // which only runs where this driver owns the idle loop (Zen 1/2).
    // idlePercent_perCpu[] = 100 - C0 share, refreshed from the main timer
    // rendezvous; idleResidencySampled is set once a full window exists.
    uint64_t lastMPERFResidency_perCpu[CPUInfo::MaxCpus] {};
    uint64_t lastTSCResidency_perCpu[CPUInfo::MaxCpus] {};
    uint8_t  idlePercent_perCpu[CPUInfo::MaxCpus] {};
    bool     idleResidencySampled {false};
    void updateC0Residency(uint32_t cpu_num, bool seedOnly);

    // Per-core power from CORE_ENERGY_STAT (MSR 0xC001029A), the counter
    // Linux turbostat (CorWatt) and zenpower read: energy in the RAPL unit
    // the package counter uses, one per physical core, read on the core's
    // primary thread in the main rendezvous. corePowerW_perCore[] is the
    // average over the last window, indexed like effFreq_perCore[];
    // selector 60. A window restarts (TSC 0) on boot and after wake.
    uint32_t lastCoreEnergy_perCore[CPUInfo::MaxCpus] {};
    uint64_t lastCoreEnergyTSC_perCore[CPUInfo::MaxCpus] {};
    uint32_t coreEnergyDelta_perCore[CPUInfo::MaxCpus] {};
    uint64_t coreEnergyTSCDelta_perCore[CPUInfo::MaxCpus] {};
    float    corePowerW_perCore[CPUInfo::MaxCpus] {};
    // Sum of corePowerW_perCore[] for the PC0C / PCPC SMC keys. Reading
    // them stamps smcCoreDemandMs, which counts as demand for the main
    // sampler like a selector call does.
    bool     coreEnergySupported {false};
    volatile float corePowerTotalW {0};
    volatile uint64_t smcCoreDemandMs {0};
    void updateCoreEnergy(uint32_t physical, bool seedOnly);

    uint8_t PStateCur_perCore[CPUInfo::MaxCpus] {};
    uint8_t PStateCtl = 0;
    uint64_t PStateDef_perCore[8] {};
    uint8_t PStateEnabledLen = 0;
    float PStateDefClock_perCore[8] {};
    bool cpbSupported {false};

    uint64_t lastUpdateTime {0};
    uint64_t lastUpdateEnergyValue {0};

    double uniPackagePowerW {0};   // Average package power in watts (energy delta / time delta)

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
    // - pmDispatchAllowed + legacyPstateAllowed = false on Zen 3+: the kext
    //   never writes P-states there (that raced the kernel and panicked).
    //   macOS has no AMD power management of its own, so frequency scaling
    //   on these CPUs comes from CPPC autonomous mode (applyEPPControl).
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
    };

    // === Family 17h profiles: need full PM dispatch (macOS has no native AMD PM) ===

    // Zen 1 (Summit Ridge, Whitehaven)
    static constexpr ZenCpuFeatureMap ZEN1_PROFILE = {
        0x17, 0x00, 0x0F, "Zen", 1,
        false, false,           // CPPC: no, CPPCv2: no
        true, true              // legacyPstate: yes, pmDispatch: yes
    };
    // Zen+ (Pinnacle Ridge)
    static constexpr ZenCpuFeatureMap ZEN_PLUS_PROFILE = {
        0x17, 0x10, 0x2F, "Zen+", 1,
        false, false,
        true, true
    };
    // Zen 2 (Matisse, Rome)
    static constexpr ZenCpuFeatureMap ZEN2_PROFILE = {
        0x17, 0x30, 0xFF, "Zen 2", 2,
        false, false,
        true, true
    };

    // === Family 19h+ profiles: telemetry-only (macOS AMD Vanilla handles CPPC) ===

    // Model ranges follow Linux k10temp and ryzen_smu's codename table.
    // Zen 3 Milan (EPYC 7003) and Chagall (Threadripper 5000, model 0x08)
    static constexpr ZenCpuFeatureMap ZEN3_MILAN_PROFILE = {
        0x19, 0x00, 0x0F, "Zen 3 Milan", 3,
        true, false,
        false, false
    };
    // Zen 4 Genoa (EPYC 9004) and Storm Peak (Threadripper 7000, model 0x18)
    static constexpr ZenCpuFeatureMap ZEN4_GENOA_PROFILE = {
        0x19, 0x10, 0x1F, "Zen 4 Genoa", 4,
        true, false,
        false, false
    };
    // Zen 3 Vermeer (desktop)
    static constexpr ZenCpuFeatureMap ZEN3_VERMEER_PROFILE = {
        0x19, 0x21, 0x2F, "Zen 3 Vermeer", 3,
        true, false,            // CPPC: yes, CPPCv2: no
        false, false            // legacyPstate: no, pmDispatch: no
    };
    // Zen 3+ (Rembrandt)
    static constexpr ZenCpuFeatureMap ZEN3_PLUS_PROFILE = {
        0x19, 0x40, 0x4F, "Zen 3+", 3,
        true, false,
        false, false
    };
    // Zen 3 Cezanne / Barcelo (APU)
    static constexpr ZenCpuFeatureMap ZEN3_CEZANNE_PROFILE = {
        0x19, 0x50, 0x5F, "Zen 3 Cezanne", 3,
        true, false,
        false, false
    };
    // Zen 4 (Raphael, Phoenix)
    static constexpr ZenCpuFeatureMap ZEN4_PROFILE = {
        0x19, 0x60, 0x7F, "Zen 4", 4,
        true, false,
        false, false
    };
    // Zen 4c Bergamo / Siena (EPYC 8004/97x4)
    static constexpr ZenCpuFeatureMap ZEN4C_PROFILE = {
        0x19, 0xA0, 0xAF, "Zen 4c", 4,
        true, false,
        false, false
    };
    // Zen 5 (Granite Ridge, Strix Point)
    static constexpr ZenCpuFeatureMap ZEN5_PROFILE = {
        0x1A, 0x00, 0xFF, "Zen 5", 5,
        true, false,
        false, false
    };

    // Feature matrix - controlled per-profile
    bool legacyPstateAllowed {false};  // Legacy P-state writes
    bool pmDispatchAllowed {false};    // Custom PM dispatch takeover

    // Derived state
    uint32_t zenGeneration = 0;
    bool supportsCPPC = false;

    bool disablePrivilegeCheck = false;
    uint16_t savedSMCChipIntel = 0;
    SInt32 kextloadAlerts = 0;
    /// Ensures kunc_alert modal is shown at most once until the user dismisses/clears it.
    /// SInt32 for OSCompareAndSwap.
    SInt32 kextAlertDisplayed = 0;

    kern_return_t (*kunc_alert)(int,unsigned,const char*,const char*,const char*,
                                const char*,const char*,const char*,const char*,const char*,unsigned*) {nullptr};
    // Shows the load-problem alert from a kernel thread of its own.
    // KUNCUserNotificationDisplayAlert waits for the user's answer, and the
    // selector call that used to show it held the app's sampling thread for
    // as long as the dialog stayed on screen.
    void showLoadAlertAsync();


    ISSuperIOSMCFamily *superIO{nullptr};
    IOLock *superIOLock{nullptr};   // Protects multi-step SuperIO I/O port sequences from concurrent UserClient calls
    IOLock *smuCmdLock{nullptr};    // Serializes full SMU command sequences.
                                    // Lock order: rendezvousLock → smuCmdLock (timer boost-telemetry
                                    // poll) and controlLock → smuCmdLock (CO/PBO writes). smuCmdLock is
                                    // always a leaf — never take another lock while holding it.
    IOLock *rendezvousLock{nullptr}; // Serializes all mp_rendezvous calls (timer + UserClient control ops)
    IOLock *controlLock{nullptr};   // Serializes provider state writes (PStateCtl, CPPC) from concurrent UserClients

    static constexpr size_t kMAX_FANS = 16;
    // Trusted RPM of each fan (0 = unknown), copied on every tachometer
    // refresh for fanRPM(); read without a lock.
    volatile uint32_t fanRPMCache[kMAX_FANS] {};
    FanCurveConfig fanCurves[MAX_FAN_CURVES] {};
    int8_t fanToCurveMap[kMAX_FANS] {}; // Maps each physical fan index to a curve index (-1 = Auto; set in start())
    uint8_t lastAppliedPWM[kMAX_FANS] {};
    uint64_t lastPWMUpdateTime[kMAX_FANS] {};
    // When a curve fan's duty last reached the chip (ms, 0 = write on the
    // next tick). An unchanged duty is written again only every
    // kFAN_REASSERT_MS, in case firmware took the header back, instead of
    // on every 500 ms tick; fewer index/data cycles on the LPC ports that
    // ACPI and SMM firmware also use. Zeroed wherever the chip state stops
    // being known: probe, curve mapping, client close, wake.
    uint64_t lastPWMAssertMs[kMAX_FANS] {};
    static constexpr uint64_t kFAN_REASSERT_MS = 5000;
    void resumeSuperIO();

    static_assert(sizeof(fanToCurveMap) / sizeof(fanToCurveMap[0]) == kMAX_FANS, "fan array size mismatch");
    static_assert(sizeof(lastAppliedPWM) / sizeof(lastAppliedPWM[0]) == kMAX_FANS, "fan array size mismatch");
    static_assert(sizeof(lastPWMUpdateTime) / sizeof(lastPWMUpdateTime[0]) == kMAX_FANS, "fan array size mismatch");
    float gpuTempC {0};
    float curveSmoothedTemp[MAX_FAN_CURVES] {};
    bool curveSmoothedSeeded[MAX_FAN_CURVES] {};
    // Per-curve trust flag for the smoothed temperature, plus the
    // unsmoothed sample the emergency guard must be evaluated against.
    // curveSmoothedValid[c] == false means "no trustworthy reading this tick"
    // and forces kFAILSAFE_PWM instead of lut[0].
    bool curveSmoothedValid[MAX_FAN_CURVES] {};
    float curveRawSourceTemp[MAX_FAN_CURVES] {};
    // Per-curve anchor temperature for downward hysteresis
    float lastAppliedTemp[MAX_FAN_CURVES] {};
    bool lastAppliedTempSeeded[MAX_FAN_CURVES] {};

    // GPU monitoring
    AMDGPUDevice *gpuDevices[16] {};
    uint32_t gpuCount {0};
    UInt16 gpuTemperatures[16] {};
    float gpuPowers[16] {};

    // Readings are the gpuTemperatures[]/gpuPowers[] the work loop refreshes;
    // nothing outside it touches GPU registers.
    uint32_t getGPUCount() { return gpuCount; }
    bool gpuSupportsPower(uint32_t index);

    // SVI2 voltage telemetry, refreshed by the sensor timer every
    // HF_TEMP_SAMPLE_PERIOD from three SMN reads (selector 59). Millivolts
    // are decoded here from the VID so the app only formats; the raw words
    // are kept beside them for diagnostics. supported is false on silicon
    // whose plane layout is not in the reference tables (SVI3 parts).
    struct SviTelemetry {
        uint32_t coreReg;
        uint32_t socReg;
        bool     supported;
        // Raven (17h 0x11), Castle Peak/Rome (0x31), Matisse (0x71) and
        // Vermeer (19h 0x21) report the SoC plane with its TFN bit set;
        // LibreHardwareMonitor reads it regardless on those models.
        bool     socIgnoresTfn;
    };
    SviTelemetry svi{};
    uint32_t sviTfnRaw {0};
    uint32_t sviCoreRaw {0};
    uint32_t sviSocRaw {0};
    uint16_t sviCoreMillivolts {0};
    uint16_t sviSocMillivolts {0};
    bool     sviCoreValid {false};
    bool     sviSocValid {false};
    void probeSviTelemetry();
    void updateSviTelemetry();
    // Decodes one plane word; false when the plane is off or has no VID.
    static bool sviDecodeMillivolts(uint32_t word, bool planeOff, uint16_t &millivolts);

    // Cached boost telemetry (Vermeer RSMU read commands 0x6E/0x59).
    // Refreshed from the main command-gate timer; 0 = unknown / never read
    // this boot. Raw SMU response words are cached byte-identically (no
    // kernel-side decode) so the app owns the decode — keep it that way and
    // decode in AMDSmuBoost on the app side, where it is unit-testable.
    uint32_t smuMaxBoostFreqMHz {0};
    uint32_t smuFastestCoreRaw {0};
    uint64_t smuBoostTelemetryLastPollMs {0};

    // Cached ProcessorParameters bitfield (Vermeer RSMU 0x6F). Static
    // silicon configuration, so it is read once from the timer command gate
    // and cached; smuProcParamsPolled distinguishes a real 0 response from
    // "never read this boot". Raw word cached byte-identically — decode in
    // AMDSmuParameters on the app side, where it is unit-testable.
    uint32_t smuProcessorParametersRaw {0};
    bool smuProcParamsPolled {false};

    // CHTC limit cache — the last value successfully programmed via SMU
    // 0x56 this boot (0 = never set). The SMU has no read command for cHTC;
    // the kext caches on success, same as the PBO limits.
    uint32_t smuCHTCLimitCelsius {0};

    // Cached SMU readbacks. The 0x02 firmware version is static — read
    // once and kept. The 0x6C PBO scalar reflects live SMU state (what Ryzen
    // Master / the firmware actually apply), so it re-reads inside the boost
    // poll's 500 ms throttle window and pairs with the 0x58 write cache for
    // drift detection. Both words are cached raw; decode in AMDSmuReadback
    // app-side, where it is unit-testable.
    uint32_t smuFirmwareVersionRaw {0};
    bool smuVersionPolled {false};
    uint32_t smuActiveScalarRaw {0};

    // OC-mode state cache — mirrors the last 0x5A/0x5B outcome this boot
    // (0 = never touched by this driver, 1 = enabled via 0x5A, 2 = disabled
    // via 0x5B). The SMU has no read-back for OC mode; the cache is written
    // only on SMU_OK, and 0 honestly means "unknown" (another tool may have
    // flipped the mode before we loaded).
    uint32_t smuOcModeState {0};

    // Frequency-override caches (0x5C all-core / 0x5D per-CCD). 0 =
    // never written by this driver this boot; on success each slot holds the
    // absolute MHz last acknowledged by the SMU. Driver-local truth only:
    // the SMU has no read-back for these commands.
    static constexpr uint8_t kOC_MAX_CCDS = 8;   // Vermeer tops out well below
                                               // this; kept in step with the
                                               // CPUSensorPacket CCD cap.
    uint32_t ocFreqMHzAllCores {0};
    uint32_t ocFreqMHzPerCcd[kOC_MAX_CCDS] {0};

    /// Clears the caches above (and the CO/PBO/cHTC ones) when the system
    /// sleeps; see the definition for why.
    void forgetSMUSettingsForSleep();

    // SMU PM-table plumbing (Vermeer RSMU 0x05/0x06/0x08 — the same
    // table ryzen_smu/HWiNFO feed from). The table lives at a SMU-provided
    // physical address in DRAM; the kext maps it read-only and snapshots it
    // into a fixed buffer that user space reads through selector 57.
    static constexpr uint32_t kPM_TABLE_MAX_SIZE = 0x2000;   // covers every documented size (max 0x1E48)
    static constexpr uint64_t kPM_REFRESH_MIN_INTERVAL_MS = 1000; // one 0x05 + re-map check per second, worst case
    uint64_t pmRefreshLastPollMs {0};
    // Last time a client read the PM table or its info (selectors 56/57).
    // Once a first snapshot exists, the 1 s capture only runs while someone
    // asked within kPM_DEMAND_WINDOW_MS: each capture costs an SMU transfer
    // and an uncached mapping, and only the AMD Power page reads it.
    volatile uint64_t pmTableLastDemandMs {0};
    static constexpr uint64_t kPM_DEMAND_WINDOW_MS = 15000;
    uint32_t pmTableVersionRaw {0};          // 0x08 response (BCD-style, e.g. 0x380904 → 38.09.04)
    bool     pmTableVersionPolled {false};
    uint64_t pmDramBase {0};                 // physical base from 0x06 (0 = unknown)
    uint32_t pmTableSize {0};                // documented size for the detected version (0 = unknown version)
    uint8_t  pmTableSnapshot[kPM_TABLE_MAX_SIZE] {0};
    uint64_t pmTableCapturedMs {0};          // timestamp of the last successful capture
    bool     pmMapValid {false};             // snapshot reflects a successful 0x05+capture cycle

    // Read-only view for the UserClient capability report (selector 35).
    // Exposes only the fields the CO capability needs; keeps the rest of the
    // mailbox (SMN register layout) private.
    bool smuMailboxSupported() const { return rsmu.supported; }
    uint32_t smuCurveOptimizerCmd() const {
        return smuCoPerCoreSupported() ? smuCmd.mp1CoPerCore : 0;
    }

    // On-demand mailbox health report (UserClient selector 58). Runs the
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
    IOWorkLoop *workLoop {nullptr};
    IOTimerEventSource *timerEvent_main {nullptr};
    IOTimerEventSource *timerEvent_tempe {nullptr};

    bool serviceInitialized = false;

    uint32_t updateTimeInterval = 1000;
    uint32_t actualUpdateTimeInterval = 1;
    uint64_t timeOfLastUpdate = 0;
    // How often user space polls, as the smoothed gap between bursts of
    // calls: one app refresh is a dozen selectors back to back, and calls
    // closer than kREQUEST_BURST_GAP_MS belong to the same burst.
    uint64_t estimatedRequestTimeInterval = 0;
    uint64_t timeOfLastMissedRequest = 0;
    static constexpr uint64_t kREQUEST_BURST_GAP_MS = 25;
    static constexpr uint64_t kREQUEST_STREAM_MS = 250;
    uint64_t requestBurstStartMs = 0;
    // Demand-driven main sampler. With no selector call and no PC0C/PCPC
    // read for kCLIENT_IDLE_MS, the main timer stops re-arming: no more
    // rendezvous interrupting every CPU. The package temperature and energy
    // behind the SMC keys and the thermal interlocks come from the sensor
    // timer either way, and that timer restarts the main one once demand is
    // back (both run on the work loop, so nothing else touches the timer).
    // The first rendezvous after a pause only seeds the counter windows
    // (seedNextSample) and the real sample follows kSEED_WINDOW_MS later,
    // so no published window ever spans the pause.
    static constexpr uint64_t kCLIENT_IDLE_MS = 10000;
    static constexpr uint32_t kSEED_WINDOW_MS = 100;
    bool mainSamplingIdle = false;
    bool seedNextSample = false;
    bool hasRecentDemand(uint64_t nowMs) const {
        uint64_t last = timeOfLastMissedRequest;
        uint64_t smc = smcCoreDemandMs;
        if (smc > last) last = smc;
        return last > nowMs || nowMs - last <= kCLIENT_IDLE_MS;
    }

    int tempNextSample = 0;
    float tempSamples[HF_TEMP_SAMPLE_LEN] {};
    float tempOffset = 0;
    double pwrEnergyUnit = 0;
    uint64_t pwrLastTSC = 0;
    // The first energy read after boot or wake only seeds the counter: a
    // delta against 0 (or against a counter the SMU reset during S3) would
    // publish one absurd wattage sample.
    bool pwrEnergySeeded = false;

    uint64_t xnuTSCFreq = 1;
    int (*wrmsr_carefully)(uint32_t, uint32_t, uint32_t) {nullptr};

    IOPCIDevice *fIOPCIDevice{nullptr};
    IOSimpleLock *pciConfigLock{nullptr};

    bool getPCIService();
    void enumerateGPUs();
    bool wentToSleep{false};
    /// Set by resumeWorkLoop() on S3 wake. The main timer processes it on its
    /// first tick (workLoop thread) so reinitHwState() never runs on the PM thread.
    bool pendingReinit{false};
    // S3 hands the cores back with firmware MSR values: the C-state policy
    // and the IRPerf enable written at the first tick are gone, and the
    // APERF/MPERF/IRPerf baselines describe counters that were reset.
    // Runs the same per-core programming as the first tick, from the work
    // loop, once the wake sequence has settled.
    void reapplyPerCoreConfig();

    uint32_t smnRead32(uint32_t addr);
    void smnWrite32(uint32_t addr, uint32_t val);

    struct SMUMailbox {
        uint32_t msgReg;
        uint32_t argReg;   // first of kSMU_ARG_COUNT consecutive argument registers
        uint32_t rspReg;
        bool     supported;
    };
    // The SMU answers on several mailboxes: RSMU carries the Ryzen Master
    // command set (PBO, OC, PM table), MP1 the Curve Optimizer margins.
    SMUMailbox rsmu{};
    SMUMailbox mp1{};

    // Command numbers of the detected family's SMU, from the ZenMaster
    // tables (runner.py, mailbox.py, pmtable.py) and ryzen_smu. 0 means the
    // family has no such command, and every feature built on it reports
    // unsupported instead of sending a number meant for another chip.
    struct SmuCommandSet {
        const char *name;
        // RSMU
        uint8_t setPpt, setTdc, setEdc;        // desktop limits: mW, mA, mA
        uint8_t setStapm, setFast, setSlow;    // APU power limits, mW
        uint8_t setTctl;                       // cHTC / Tctl limit, °C
        uint8_t setScalar, getScalar;          // PBO scalar, %x100
        uint8_t ocEnable, ocDisable;
        uint8_t ocClkAll, ocClkPerCore;        // MHz in [19:0]
        uint8_t ocVid;                         // SVI2 VID
        uint8_t getMaxClk, getFastestCore, getProcessorParams;
        uint8_t pmVersion, pmBase, pmTransfer;
        uint8_t pmBaseArg0, pmBaseArg1, pmTransferArg;
        bool    pmBase64;                      // base comes back as arg0 | arg1 << 32
        // MP1
        uint8_t mp1CoPerCore, mp1CoAll;        // margin, 16-bit two's complement
        uint8_t mp1BoostLimit;                 // MHz
        // Core positions readable with the Zen 3 fuse layout: per-core
        // Curve Optimizer and per-CCD frequency need them.
        bool    zen3CoreFuses;
    };
    SmuCommandSet smuCmd{};
    // Picks the command set and mailboxes for cpuFamily/cpuModel; the CPU
    // name tells first- and second-generation Threadripper from Ryzen.
    void selectSmuCommandSet(const char *cpuName);

    static constexpr uint32_t kSMU_ARG_COUNT = 6;

    // One complete mailbox transaction. args[] goes out in the argument
    // registers and, on SMU_RSP_OK, comes back with the reply words.
    int smuExecute(const SMUMailbox &mb, uint32_t cmd, uint32_t (&args)[kSMU_ARG_COUNT],
                   uint32_t timeoutUs, uint32_t *outElapsedUs = nullptr);
    // RSMU helpers: one argument in, the first reply word out.
    int smuSendCmd(uint32_t cmd, uint32_t arg);
    int smuSendCmd(uint32_t cmd, uint32_t arg, uint32_t &outArg0, uint32_t *outElapsedUs = nullptr);
    // Maps a mailbox status to the driver's negative error codes
    // (-10 timeout, -11 unknown command, -12 rejected, -13 busy, -5 failed).
    static int smuError(int response);

    void buildCoreMap();
    bool physicalCcdForIndex(uint8_t index, uint32_t &physical) const;

    // SMU read commands ride the main timer's command gate. The throttle
    // keeps the added SMU traffic to ~2 round trips per second worst case.
    static constexpr uint64_t kSMU_BOOST_POLL_MIN_INTERVAL_MS = 500;

    void initWorkLoop();
    void stopWorkLoop();
    void resumeWorkLoop();
};
#endif
