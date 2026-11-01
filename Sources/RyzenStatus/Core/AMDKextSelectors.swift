// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

/// Centralized table of IOKit selectors for the AMDRyzenCPUPowerManagement kext.
///
/// **Rationale**: selector numbers were previously scattered as integer literals in
/// `ProcessorModel.swift` and documented only in kext comments. A desync between the
/// app and kext version caused silent writes to wrong selectors. This enum is the
/// single source of truth — any mismatch is a compile-time naming error.
///
/// - Important: These values MUST match `AMDRyzenCPUPMUserClient.cpp` exactly.
///   When bumping a selector in the kext, update this file in the same commit.
enum AMDKextSelector: UInt32, CaseIterable {

    // MARK: — Telemetry (Read-only)

    /// Delta instruction count per core — used to derive IPC.
    case deltaInstructions = 5
    /// Raw CPUID information block.
    case cpuidInfo         = 7
    /// Full telemetry snapshot: temps, clocks, voltages, power (selector 100).
    case telemetryFull     = 100
    /// Core metric snapshot: per-core frequencies, temps, power.
    /// Returns: `UInt64` core count + `[Float]` metric array.
    case coreMetric        = 4
    /// Kext version string + compatibility flags.
    case kextVersion       = 8
    /// Baseboard vendor/name strings (2×64-byte null-terminated fields).
    case baseboardInfo     = 16

    // MARK: — Processor Identity (Read-only)

    /// CCD topology — returns CCD/CCX count and mapping.
    case ccdTopology       = 20
    /// Per-core ranking based on silicon quality / boost headroom.
    case coreRanking       = 21
    /// Whether CPPC (Collaborative Processor Performance Control) is active.
    case cppcActive        = 23

    // MARK: — Power Management (Read/Write)

    /// Energy Performance Preference (0 = Performance … 255 = Power Save).
    case eppValue          = 25
    /// Core Performance Boost enable/disable.
    case cpb               = 12
    /// Power Profile Mode (platform power policy).
    case ppm               = 14
    /// Low Power Mode enable/disable.
    case lpm               = 19
    /// Manual P-State override (write-only).
    case pStateManual      = 15
    /// Write P-State index directly (alternate write path, selector 10).
    case pStateWrite       = 10
    /// CPU power profile index.
    case cpuPowerProfile   = 26

    // MARK: — GPU Telemetry (Read-only)

    /// GPU count query — returns number of detected AMD GPUs (selector 27).
    case gpuStats0         = 27
    /// GPU temperatures array in integer degrees Celsius, one per GPU (selector 28).
    case gpuStats1         = 28
    /// GPU powers array in Watts, one per GPU (selector 29).
    case gpuStats2         = 29
    /// GPU capability flags (bit 0 = power supported) per GPU (selector 30).
    case gpuStats3         = 30

    // MARK: — C-State Telemetry (Read-only)

    /// C6 residency percentage (package-level).
    case c6Residency       = 31
    /// Per-core idle residency %% — one UInt16 (0…100) per logical core
    /// (kext 1.20.0+). Since kext 3.36.0 it is 100 minus the CPU's C0 share
    /// (MPERF against the TSC), live on every Zen generation; older kexts
    /// only filled it where the driver owns the idle loop (Zen 1/2).
    case coreC6Residency   = 32
    /// Per-core instructions-retired delta — one UInt32 per logical core (kext 1.20.0+).
    case coreInstRetired   = 33
    /// Read-only CC6 idle state (`AMDCStatePolicy`): [0] idle cores stay out
    /// of CC6, [1] raw CSTATE_ADDR, and from kext 3.40.0 [2] CC6 on, [3]
    /// firmware C-state IO base, [4] CC6 available, [5] forbidden by amdcstate=1.
    case cStatePolicy      = 34
    /// Read-only PBO limits cache (S4): [0] = PPT mW, [1] = TDC mA, [2] = EDC mA
    /// — the last values successfully programmed this boot (0 = never set).
    /// The SMU has no read-back for limits; the kext caches on success.
    case pboLimitsRead = 36
    /// Read-only PBO scalar cache (S4): [0] = scalar in %×100 (200 = 2x; 0 = never set).
    case pboScalarRead = 37
    /// Write PBO limits (S4, privileged): [0] = PPT mW, [1] = TDC mA, [2] = EDC mA.
    /// All three programmed atomically; aborts on first SMU failure.
    case pboLimitsWrite = 41
    /// Write PBO scalar (S4, privileged): [0] = scalar in %×100 (100…1000).
    case pboScalarWrite = 42
    /// Read-only SMU boost telemetry snapshot (S5): [0] = max boost frequency
    /// in MHz (Vermeer RSMU `GetMaxFrequency` 0x6E), [1] = raw
    /// `GetFastestCoreOfSocket` (0x59) response word — decoded app-side in
    /// `AMDSmuBoost` where it is unit-testable, [2] = 1 once the kext timer
    /// has populated the caches this boot. Unsupported on pre-1.25 kexts.
    case boostTelemetry = 43
    /// Read-only ProcessorParameters bitfield (S6): [0] = raw Vermeer RSMU
    /// `GetProcessorParameters` (0x6F) response word — decoded app-side in
    /// `AMDSmuParameters` (bit 0 IsOverclockable, bit 1 PBO support),
    /// [1] = 1 once the kext timer has read the command successfully this
    /// boot (a real 0-bitfield is a valid answer, so "polled" is distinct
    /// from the value). Unsupported on pre-1.26 kexts.
    case processorParametersRead = 44
    /// Read-only cHTC limit cache (S6): [0] = the last value successfully
    /// programmed via SMU `SetcHTCLimit` (0x56) this boot in °C (0 = never
    /// set — the SMU has no cHTC read command). Unsupported on pre-1.26 kexts.
    case chtcLimitRead = 45
    /// Write cHTC thermal limit (S6, privileged): [0] = target in °C
    /// (40…95). Same Vermeer gate + thermal interlock as the PBO limits.
    case chtcLimitWrite = 46
    /// Read-only SMU firmware version (S7): [0] = raw byte-packed version
    /// word (24-bit A.B.C, or 32-bit A.B.C.D when byte 3 ≠ 0 — decoded
    /// app-side in `AMDSmuReadback.formatSmuVersion`), [1] = 1 once the kext
    /// timer has read the command (global 0x02) successfully this boot.
    /// Unsupported on pre-1.27 kexts.
    case smuVersionRead = 47
    /// Read-only active PBO scalar (S7): [0] = raw Vermeer RSMU `GetPBOScalar`
    /// (0x6C) response word — an IEEE-754 float in the 1.0–10.0 range,
    /// decoded app-side in `AMDSmuReadback.formatActiveScalar` (different
    /// encoding than the 0x58 write!), [1] = 1 once the kext timer has read
    /// it successfully this boot. Unsupported on pre-1.27 kexts.
    case activeScalarRead = 48
    /// Read-only OC capability report: [0] = 1 when the kext accepts
    /// OC-mode and frequency/VID commands (Vermeer + SMU mailbox, same
    /// verdict policy as selector 38), [1] = cached ProcessorParameters
    /// (0x6F) bitfield for context (bit 0 IsOverclockable fuse), [2] =
    /// OC-mode cache state (`AMDOcMode` codes: 0 unknown / 1 enabled /
    /// 2 disabled), [3] = 1 when frequency overrides (0x5C/0x5D) are
    /// accepted; 1.28.0 shipped this slot as reserved 0, so a 0
    /// simply hides those controls. Unsupported on pre-1.28 kexts.
    case ocCapability = 49
    /// Write OC mode (privileged): [0] = 1 enable (RSMU 0x5A) or 0 disable
    /// (RSMU 0x5B), Arg0 0 in both cases (ZenStates-Core); [1] = reset-scalar
    /// flag (on disable, also re-program the PBO scalar to 1.0 via 0x58 —
    /// some SMU firmware does not auto-reset it). Frequency overrides are
    /// selector 51; VID (0x61) is not exposed.
    case ocModeWrite = 50
    /// Write frequency override (privileged): [0] = mode (0 all-core
    /// via 0x5C, 1 per-CCD via 0x5D), [1] = MHz (all-core mode), [2..9] =
    /// per-CCD MHz (entry i targets CCD startCcd + i, per-CCD mode),
    /// [10] = startCcd, [11] = CCD count (contiguous window; a single-CCD
    /// apply is startCcd = ccd, count = 1). All-core sends 2 scalars,
    /// per-CCD 12. Envelopes: 400..8000 MHz, startCcd + count ≤ 8. The
    /// kernel writes 0x5D to every core of each CCD with masks it builds
    /// itself — user space sends plain MHz. Refuses with
    /// `kIOReturnNotPermitted` unless THIS driver enabled OC mode earlier
    /// this boot, `kIOReturnNotReady` under the thermal interlock. Output:
    /// [0] = 0, [1] = programmed MHz (all-core), [2] = 0x5C argument
    /// (all-core) or 0, [3] = CCDs processed, [4..7] reserved.
    /// Unsupported on pre-1.29 kexts.
    case ocFreqWrite = 51
    /// Read-only frequency-override cache: [0] = all-core cache MHz
    /// (0 = never written by this driver this boot), [1] = kext's CCD count
    /// from its start-time register probe (0 = not ready / no AMD host —
    /// fall back to the app's own estimate), [2..9] = per-CCD caches (index
    /// = CCD, 0 = never written). Cache only, no SMU traffic.
    /// Unsupported on pre-1.29 kexts.
    case ocFreqCacheRead = 52
    /// Read-only PM-table info: [0] = table version word (0x08
    /// response, BCD-style e.g. 0x380904 → 38.09.04), [1] = version-polled
    /// flag, [2] = documented size in bytes (0 = unknown version, fail
    /// closed), [3]/[4] = physical base low/high 32, [5] = snapshot-valid
    /// flag, [6] = snapshot age in ms (0 = never captured), [7] = reserved.
    /// Cache only, no SMU traffic. Unsupported on pre-1.30 kexts.
    case pmTableInfo = 56
    /// PM-table raw access: op 1 = read a chunk of the kext's snapshot
    /// (structure output; scalarInput [0] = op, [1] = byte offset; the kext
    /// clamps to the captured table and never reads past its size — no SMU
    /// traffic); op 2 = force an immediate capture cycle (0x08 once, then
    /// 0x05 → 0x06 → read-only map → snapshot), privileged because it adds
    /// SMU mailbox traffic on demand. Unsupported on pre-1.30 kexts.
    case pmTableRaw = 57
    /// Mailbox health diagnostics (privileged): runs the kext's three
    /// boot-diagnostic probes on demand — SMN aperture (Tctl word), TestMessage
    /// echo (0x01 arg 0x42 → 0x43) and GetSMUVersion (0x02) — and returns a
    /// 48-byte structure report (decoded in `AMDSmuDiagnostics.Report`).
    /// Privileged: adds SMU mailbox traffic on demand (same policy as 57 op 2).
    /// Unsupported on pre-3.34.13 kexts.
    case smuDiagnostics = 58
    /// Read-only SVI2 voltage telemetry (kext 3.36.0+): [0] = 1 when the
    /// silicon has a known SVI2 plane layout (family 17h, family 19h up to
    /// model 0x5F; 0 on the SVI3 Zen 4/5 parts, where every other field is
    /// 0), [1] = core reading trusted, [2] = core voltage in mV, [3] = SoC
    /// reading trusted, [4] = SoC voltage in mV, [5..7] = raw TFN / core /
    /// SoC plane words. Cache only, refreshed by the kext's sensor timer.
    /// Unsupported on pre-3.36.0 kexts.
    case sviVoltage = 59
    /// Read-only per-core power (kext 3.37.0+): one Float in watts per
    /// physical core, indexed like the effective clocks of selector 2, from
    /// the CORE_ENERGY_STAT counter; scalar [0] = core count. Cache only,
    /// refreshed by the kext's main timer. Unsupported on older kexts.
    case corePower = 60
    /// CC6 idle on/off (kext 3.40.0+, privileged): scalar [0] = 1/0. The
    /// kext enters CC6 through the firmware's C-state IO port on every idle
    /// entry while it is on; selector 34 reports the state.
    case c6IdleWrite = 61
    /// Power-control capabilities (kext 3.40.0+): scalar [0] = bitmask
    /// (`AMDPowerCapabilities`), [1] last OC VID, [2] all-core CO byte,
    /// [3] all-core CO written, [4] boost ceiling MHz.
    case powerCapabilities = 62
    /// ACPI CPPC discovery report (kext 3.40.0+): uint32 words, see
    /// `AMDAcpiCppcReport`.
    case acpiCppcReport = 63
    /// ACPI CPPC capability read through PCC (kext 3.40.0+, privileged):
    /// [0] highest, [1] nominal, [2] lowest non-linear, [3] lowest, [4] EPP,
    /// [5] channel status.
    case acpiCppcProbe = 64
    /// OC VID write (kext 3.40.0+, privileged): SVI2 VID 16…120, OC mode only.
    case ocVidWrite = 65
    /// All-core Curve Optimizer (kext 3.40.0+, privileged): margin −30…+30.
    case curveOptimizerAllWrite = 66
    /// Boost frequency ceiling (kext 3.40.0+, privileged): MHz.
    case boostLimitWrite = 67

    // MARK: — Fan Control (via SuperIO)

    /// Fan count query — returns the number of SuperIO fan headers.
    case fanCountRead      = 91
    /// Fan speed read — per-fan RPM values (the kext also calls this path
    /// “fan speed write”; selector 95 is the actual PWM write).
    case fanSpeedRead      = 93

    // MARK: — Fan Curve LUT & Fan Mapping

    /// Write fan curve LUT (256 points) + hysteresis/ramp parameters to kext storage.
    case fanCurveLUTWrite  = 101
    /// Map a physical fan header to a curve slot; -1 restores automatic control.
    case fanToCurveMap     = 102
    /// Write current GPU temperature into kext for GPU-sourced fan curves.
    case gpuTempWrite      = 103

    // MARK: — Curve Optimizer

    /// Read current Curve Optimizer per-core offsets.
    case curveOptimizerRead  = 110
    /// Write Curve Optimizer per-core offsets (clamped ±30 in kext).
    case curveOptimizerWrite = 111
}

extension AMDKextSelector {
    /// Convenience: raw value as the `UInt32` expected by `IOConnectCallMethod`.
    var id: UInt32 { rawValue }
}

// MARK: — Extended selectors (used via kernelGetUInt64 / kernelGetFloats / kernelSetStruct)

extension AMDKextSelector {

    // --- P-State read helpers ---
    // These are used by kernelGetUInt64/kernelGetFloats and share the same
    // UInt32 type; declare as static constants to avoid duplicate raw values.

    /// P-State definition table (8 × UInt64).
    static let pStateDef      = UInt32(0)
    /// P-State clock table (10 × Float).
    static let pStateDefClock = UInt32(1)

    // --- CPB / PPM / LPM read ---
    /// CPB status read (2 × UInt64: [supported, enabled]).
    static let cpbRead        = UInt32(11)
    /// PPM status read (2 × UInt64: [supported, enabled]).
    static let ppmRead        = UInt32(13)
    /// Number of high-performance CPUs (getHPcpus, 1 × UInt64).
    static let hpCpusRead     = UInt32(17)
    /// LPM status read (1 × UInt64) — true when the PMP state limit is 2.
    static let lpmRead        = UInt32(18)
    /// C6 residency read (1 × UInt64) — package-level percentage.
    static let c6ResidencyPkg = UInt32(31)

    // --- GPU stats (read) — use enum cases .gpuStats0/.gpuStats1/.gpuStats2/.gpuStats3 directly ---
    static let gpuLoad        = UInt32(27)
    // gpuTemps = 28, gpuClocks = 29, gpuStats3 = 30 are already enum cases above.

    // --- Fan helpers (SuperIO) ---
    /// Fan initialisation / count query.
    static let fanInit        = UInt32(90)
    /// Fan name string (1 × String).
    static let fanName        = UInt32(92)
    /// Fan control read.
    static let fanCtrlRead    = UInt32(94)
    /// Fan override control write (selector 95 — used in setFanSpeed).
    static let fanSpeedWrite = UInt32(95)
    /// Fan mode write (selector 96 — auto/manual).
    static let fanModeWrite   = UInt32(96)

    /// Every selector known to `AMDKextSelector` (both enum cases and static constants),
    /// verified in `MetricsTests` against `AMDRyzenCPUPMUserClient.cpp`.
    static var allKnownSelectors: Set<UInt32> {
        var set = Set(allCases.map(\.rawValue))
        set.formUnion([
            pStateDef,
            pStateDefClock,
            cpbRead,
            ppmRead,
            hpCpusRead,
            lpmRead,
            c6ResidencyPkg,
            gpuLoad,
            fanInit,
            fanName,
            fanCtrlRead,
            fanSpeedWrite,
            fanModeWrite,
        ])
        return set
    }
}
