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
enum AMDKextSelector: UInt32 {

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
    /// C-State MSR base address — used by `CStateNvramService`.
    case cStateAddress     = 22

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
    /// CPPC Active Mode toggle (enables hardware-controlled EPP).
    case cppcActiveMode    = 24

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
    /// Per-core C6 residency %% — one UInt16 (0…100) per logical core (KEXT_WAVE 1.20.0 C-1).
    case coreC6Residency   = 32
    /// Per-core instructions-retired delta — one UInt32 per logical core (KEXT_WAVE 1.20.0 C-2).
    case coreInstRetired   = 33
    /// Read-only C-state policy: [0] = 1 if the kext disables deep C-States
    /// (amdcstate=1 or default), [1] = raw cstateAddrConfig. Added in kext 1.21.0 (S2-T4).
    case cStatePolicy      = 34
    /// Read-only Curve Optimizer capability report (S3-B): [0] = 1 when the kext
    /// accepts CO writes for this silicon, [1] = active SMU command ID,
    /// [2]/[3] = min/max safe offset. Unsupported on pre-1.22 kexts.
    case curveOptimizerCapability = 35
    /// Read-only PBO limits cache (S4): [0] = PPT mW, [1] = TDC mA, [2] = EDC mA
    /// — the last values successfully programmed this boot (0 = never set).
    /// The SMU has no read-back for limits; the kext caches on success.
    case pboLimitsRead = 36
    /// Read-only PBO scalar cache (S4): [0] = scalar in %×100 (200 = 2x; 0 = never set).
    case pboScalarRead = 37
    /// Read-only PBO capability (S4): [0] = 1 when PBO limit writes are accepted
    /// (Vermeer + SMU mailbox), [1..3] reserved. Unsupported on pre-1.24 kexts.
    case pboCapability = 38
    /// Read-only PBO scalar capability (S4): [0] = supported,
    /// [1]/[2] = min/max scalar in %×100 (100…1000). Unsupported on pre-1.24 kexts.
    case pboScalarCapability = 39
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
    /// Read-only OC capability report (S8): [0] = 1 when the kext accepts
    /// OC-mode and frequency/VID commands (Vermeer + SMU mailbox, same
    /// verdict policy as selector 38), [1] = cached ProcessorParameters
    /// (0x6F) bitfield for context (bit 0 IsOverclockable fuse), [2] =
    /// OC-mode cache state (`AMDOcMode` codes: 0 unknown / 1 enabled /
    /// 2 disabled), [3] = 1 when frequency overrides (0x5C/0x5D) are
    /// accepted — S8.2; 1.28.0 shipped this slot as reserved 0, so a 0
    /// simply hides those controls. Unsupported on pre-1.28 kexts.
    case ocCapability = 49
    /// Write OC mode (S8, privileged): [0] = 1 enable (RSMU 0x5A, Arg0 1) or
    /// 0 disable (RSMU 0x5B, Arg0 0) — semantics pinned by ZenStates-Core,
    /// resolving rsmu_commands.md's contradictory rows; [1] = reset-scalar
    /// flag (on disable, also re-program the PBO scalar to 1.0 via 0x58 —
    /// some SMU firmware does not auto-reset it). Frequency (0x5C/0x5D) and
    /// VID (0x61) writes are deliberately NOT exposed yet.
    case ocModeWrite = 50
    /// Write frequency override (S8.2, privileged): [0] = mode (0 all-core
    /// via 0x5C, 1 per-CCD via 0x5D), [1] = MHz (all-core mode), [2..9] =
    /// per-CCD MHz (entry i targets CCD startCcd + i, per-CCD mode),
    /// [10] = startCcd, [11] = CCD count (contiguous window; a single-CCD
    /// apply is startCcd = ccd, count = 1). Envelopes: 400..8000 MHz,
    /// startCcd + count ≤ 8. The kernel builds the 0x5D mask ((ccd << 28) |
    /// freq on Vermeer) — never pack masks in user space. Refuses with
    /// `kIOReturnNotPermitted` unless THIS driver enabled OC mode earlier
    /// this boot, `kIOReturnNotReady` under the thermal interlock. Output:
    /// [0] = 0, [1] = programmed MHz (all-core), [2] = last mask/arg
    /// (0xFFFFFFFF sentinel = all-core), [3] = CCDs processed, [4..7]
    /// reserved. Unsupported on pre-1.29 kexts.
    case ocFreqWrite = 51
    /// Read-only frequency-override cache (S8.2): [0] = all-core cache MHz
    /// (0 = never written by this driver this boot), [1] = kext's CCD count
    /// from its start-time register probe (0 = not ready / no AMD host —
    /// fall back to the app's own estimate), [2..9] = per-CCD caches (index
    /// = CCD, 0 = never written). Cache only, no SMU traffic (F-05).
    /// Unsupported on pre-1.29 kexts.
    case ocFreqCacheRead = 52

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
}
