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

    /// GPU clock / utilization stats — range 27-30 (mapped individually below).
    case gpuStats0         = 27
    case gpuStats1         = 28
    case gpuStats2         = 29
    case gpuStats3         = 30

    // MARK: — C-State Telemetry (Read-only)

    /// C6 residency percentage per core.
    case c6Residency       = 31

    // MARK: — Fan Control (via SuperIO)

    /// Fan speed read (RPM / duty cycle from SuperIO).
    case fanSpeedRead      = 91
    /// Fan speed write — set target PWM duty cycle.
    case fanSpeedWrite     = 93

    // MARK: — Fan Curve LUT

    /// Read current fan curve LUT from kext storage.
    case fanCurveLUTRead   = 101
    /// Write fan curve LUT to kext storage.
    case fanCurveLUTWrite  = 102

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
    /// LPM status read (1 × UInt64).
    static let lpmRead        = UInt32(17)
    /// C6 residency MSR address (1 × UInt64).
    static let c6ResidencyMSR = UInt32(18)
    /// C6 residency per-core read (1 × UInt64) — package-level.
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
    /// Fan speed write (selector 95 — used in setFanSpeed).
    static let fanSpeedWrite2 = UInt32(95)
    /// Fan mode write (selector 96 — auto/manual).
    static let fanModeWrite   = UInt32(96)
}
