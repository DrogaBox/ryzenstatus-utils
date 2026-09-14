import Foundation

// MARK: - CPU Generation Classification

/// Zen generation classification for gate-keeping kext features whose
/// implementation is family/model specific — most notably Curve Optimizer
/// (selectors 110/111), whose SMU payload is Vermeer-only.
///
/// Family/model come from the kext's CPUID report (selector 7):
/// `family` = dataOut[0], `model` = dataOut[1].
enum AMDCpuGeneration: Equatable {
    case unknown
    case zen2AndOlder
    case zen3
    case zen4
    case zen5

    /// Classification ranges (Family 0x19):
    /// - Zen 3:      model 0x01–0x5F (Vermeer 0x21, Cezanne 0x50, …)
    /// - Zen 4:      model 0x60–0x7F (Raphael 0x61, Phoenix 0x74, …)
    /// - Zen 5:      model ≥ 0x90 (Granite Ridge 0xA0+, Strix Point family 0x1A)
    static func classify(family: Int, model: Int) -> AMDCpuGeneration {
        guard family == 0x19 else {
            return family >= 0x1A ? .zen5 : .zen2AndOlder
        }
        if model >= 0x90 { return .zen5 }
        if model >= 0x60 && model <= 0x7F { return .zen4 }
        return .zen3
    }

    /// Whether the user-facing message should say "Zen 4/5 not supported".
    var isZen4OrNewer: Bool { self == .zen4 || self == .zen5 }
}

// MARK: - Curve Optimizer Gate (selectors 110/111)

enum AMDCurveOptimizer {
    /// The kext only accepts Curve Optimizer writes on Zen 3 Vermeer
    /// (family 0x19, model 0x21–0x2F) and only when `legacyPstateAllowed`
    /// — the baseline/telemetry-only profile disables the SMU control path
    /// and returns `kIOReturnUnsupported` for every write.
    static func supported(family: Int, model: Int) -> Bool {
        family == 0x19 && (0x21...0x2F).contains(model)
    }

    /// Safe offset range enforced by the kext ([-30, +30]).
    static let minOffset = -30
    static let maxOffset = 30

    /// Clamps an offset to the kext's safe [-30, +30] range.
    static func clamp(_ offset: Int) -> Int8 {
        Int8(min(maxOffset, max(minOffset, offset)))
    }

    /// True when the raw offsets array returned by selector 110 (fixed
    /// 64-entry buffer, `CPUInfo::MaxCpus`) is meaningful for `coreCount`.
    static func validOffsets(_ offsets: [Int8], coreCount: Int) -> Bool {
        !offsets.isEmpty && coreCount > 0 && offsets.count >= coreCount
    }
}

// MARK: - PBO Limits & Scalar (S4, selectors 36-42)

enum AMDPBOLimits {
    /// The kext accepts PBO limit/scalar writes on the same silicon window as
    /// Curve Optimizer: Zen 3 Vermeer (family 0x19, model 0x21–0x2F) with a
    /// supported SMU mailbox. Fail-closed everywhere else.
    static func supported(family: Int, model: Int) -> Bool {
        family == 0x19 && (0x21...0x2F).contains(model)
    }

    /// Hard envelope shared with the kext: 1000…500000 milli-units per axis
    /// (PPT in mW ⇒ 1…500 W; TDC/EDC in mA ⇒ 1…500 A). The lower bound also
    /// blocks "disable the limit" (0) writes.
    static let minLimit = 1000
    static let maxLimit = 500000

    /// PBO scalar range in %×100: 100 (1x) … 1000 (10x) — the Ryzen Master range.
    static let minScalarPercentX100 = 100
    static let maxScalarPercentX100 = 1000

    /// Clamps one limit axis to the shared 1…500000 milli-unit envelope.
    static func clampLimit(_ value: Int) -> Int {
        min(maxLimit, max(minLimit, value))
    }

    /// Clamps PPT/TDC/EDC as a triple (used by the settings UI stepper validation).
    static func clampTriple(ppt: Int, tdc: Int, edc: Int) -> (ppt: Int, tdc: Int, edc: Int) {
        (clampLimit(ppt), clampLimit(tdc), clampLimit(edc))
    }

    /// Clamps the scalar to 100…1000 (%×100).
    static func clampScalar(_ percentX100: Int) -> Int {
        min(maxScalarPercentX100, max(minScalarPercentX100, percentX100))
    }

    /// Formats a milli-unit value for the UI: ≥ 1000 renders in the base unit
    /// with at most one decimal ("142 W", "95.5 A"), smaller values stay in the
    /// milli unit ("800 mA"). `unitMilli`/`unitBase` are already-localized suffixes.
    static func formatLimit(_ milliValue: Int, unitMilli: String, unitBase: String) -> String {
        if milliValue >= 1000 {
            let whole = milliValue / 1000
            let tenths = (milliValue % 1000) / 100
            return tenths == 0 ? "\(whole) \(unitBase)" : "\(whole).\(tenths) \(unitBase)"
        }
        return "\(milliValue) \(unitMilli)"
    }

    /// Formats the scalar cache/capability values: %×100 → "2.0x" style.
    static func formatScalar(_ percentX100: Int) -> String {
        let whole = percentX100 / 100
        let tenths = (percentX100 % 100) / 10
        return "\(whole).\(tenths)x"
    }

    /// Inverse of the UI display step: whole W (or A) → milli-units for the kext.
    static func milliFromBase(_ baseValue: Int) -> Int {
        baseValue * 1000
    }
}

// MARK: - SMU Boost Telemetry (S5, selector 43 — Vermeer read commands)

enum AMDSmuBoost {
    /// Vermeer RSMU read command IDs polled by the kext's command-gate timer
    /// (ryzen_smu `rsmu_commands.md`, same mailbox the kext already drives).
    static let getMaxFrequencyCmd: UInt32 = 0x6E
    static let getFastestCoreOfSocketCmd: UInt32 = 0x59

    /// Decode of the raw `GetFastestCoreOfSocket` (0x59) response word.
    ///
    /// The public record documents the response as the self-referential
    /// `Res0:(16 * BYTE2(Res0)) | (Res0 + 4 * BYTE1(Res0)) & 0xF` — an
    /// ambiguous expression, so this decode is kept in one tested place.
    /// Under the literal reading, the core index contributes 16·n to the
    /// word ⇒ n lives in the high nibble of byte 2 (`raw >> 20 & 0xF`),
    /// which exactly covers the 0…15 physical-core range of the silicon
    /// this feature is gated to (Vermeer, 1–16 cores).
    /// Returns nil for the "never read" placeholder (0) and for any word
    /// that does not fit the documented window — callers show the raw value
    /// instead of inventing a wrong core number.
    static func decodeFastestCore(_ raw: UInt32) -> Int? {
        guard raw != 0 else { return nil }
        let index = Int((raw >> 20) & 0xF)
        guard raw & 0x000F_0000 == 0, raw & 0xFF00_0000 == 0, index != 0 else { return nil }
        return index
    }
}

// MARK: - SMU Processor Parameters (S6, selector 44 — Vermeer read command)

enum AMDSmuParameters {
    /// Vermeer RSMU `GetProcessorParameters` command ID polled once by the
    /// kext's command-gate timer (ryzen_smu `rsmu_commands.md`; the doc
    /// carries an uncertainty marker, so the kext caches the raw word and
    /// every interpretation lives in this single unit-tested place).
    static let getProcessorParametersCmd: UInt32 = 0x6F

    /// cHTC default for the UI slider when nothing has been programmed this
    /// boot (°C) — AMD's stock thermal ceiling for Vermeer.
    static let defaultCHTCCelsius = 85

    /// Safety window enforced identically by the kext (selector 46) and the
    /// UI slider: below 40 °C the limit could engage before the package even
    /// warms up; Vermeer's Tjmax is 95 °C.
    static let minCHTCCelsius = 40
    static let maxCHTCCelsius = 95

    /// Clamps a cHTC target to the shared 40…95 °C window.
    static func clampCHTCCelsius(_ celsius: Int) -> Int {
        min(maxCHTCCelsius, max(minCHTCCelsius, celsius))
    }

    /// Bit 0 of the 0x6F bitfield: the fused overclocking fuse is blown —
    /// the silicon accepts SMU overclocking/limit commands.
    static func isOverclockable(_ raw: UInt32) -> Bool {
        raw & 0x1 != 0
    }

    /// Bit 1 of the 0x6F bitfield: fused PBO support.
    static func pboSupportFused(_ raw: UInt32) -> Bool {
        raw & 0x2 != 0
    }

    /// Bits above the two documented ones are reserved — surfaced as "unknown
    /// extra state" rather than silently dropped (honesty over guessing).
    static func hasReservedBits(_ raw: UInt32) -> Bool {
        raw & ~0x3 != 0
    }
}

// MARK: - SMU Readbacks (S7, selectors 47/48 — version + active scalar)

enum AMDSmuReadback {
    /// Global TestMessage-family SMU version command (0x02 — per ryzen_smu:
    /// "consistent with all platforms").
    static let getSmuVersionCmd: UInt32 = 0x02
    /// Vermeer RSMU `GetPBOScalar` command (0x6C).
    static let getPBOScalarCmd: UInt32 = 0x6C

    /// Decode of the SMU firmware version word from `GetSMUVersion` (0x02).
    ///
    /// The public record documents only `Res0: Version`; the reference
    /// libsmu renders the word byte-packed as dotted decimal — 24-bit
    /// `maj.min.rev`, or 32-bit `maj.min.rev.alt` when byte 3 ≠ 0. Returns
    /// nil for the "never read" placeholder (0) — callers show nothing
    /// rather than a bogus "0.0.0".
    static func formatSmuVersion(_ raw: UInt32) -> String? {
        guard raw != 0 else { return nil }
        if raw & 0xFF00_0000 != 0 {
            return "\((raw >> 24) & 0xFF).\((raw >> 16) & 0xFF).\((raw >> 8) & 0xFF).\(raw & 0xFF)"
        }
        return "\((raw >> 16) & 0xFF).\((raw >> 8) & 0xFF).\(raw & 0xFF)"
    }

    /// Decode of the SMU's active PBO scalar response word from
    /// `GetPBOScalar` (0x6C): an IEEE-754 float in the documented 1.0–10.0
    /// range (reference monitor_cpu.c renders `%.fx`). Returns nil for the
    /// "never read" placeholder (0) or any word outside the documented
    /// range — the kext's 0x58 write cache remains the authoritative UI
    /// value; this readback only reports what the SMU itself claims.
    static func formatActiveScalar(_ raw: UInt32) -> String? {
        guard raw != 0 else { return nil }
        let value = Float(bitPattern: raw)
        guard value >= 1.0, value <= 10.0, value.isFinite else { return nil }
        return String(format: "%.1fx", value)
    }
}

// MARK: - Mailbox Diagnostics (selector 58)

/// Decode + formatting for the kext's on-demand mailbox health report
/// (selector 58, kext 3.34.13+). The kext runs the same three probes as its
/// boot diagnostic — SMN aperture (Tctl), TestMessage round-trip (0x01:
/// documented Res0 = Arg0 + 1, so arg 0x42 returns 0x43) and GetSMUVersion
/// (0x02) — and hands back every raw
/// code; this type turns that into a human-readable verdict.
enum AMDSmuDiagnostics {
    /// Wire layout of the kext's 48-byte structure report (12 × UInt32,
    /// little-endian). Field order mirrors the C struct — pinned by the
    /// kernel-side static_assert and the app-side byte-count check.
    /// Mutable so tests can derive verdict-checking variants.
    struct Report: Equatable {
        var mailboxSupported: Bool
        var msgReg: UInt32
        var argReg: UInt32
        var rspReg: UInt32
        var curveOptimizerCmd: UInt32
        var smnTctlRaw: UInt32
        var testRspCode: Int32
        var testArg0: UInt32
        var testElapsedUs: UInt32
        var versionRspCode: Int32
        var versionRaw: UInt32
        var versionElapsedUs: UInt32
    }

    static let wireByteCount = 48

    /// Decode the kext's structure buffer. Returns nil for any size other
    /// than the pinned 48 bytes — a size mismatch means a kext/app mismatch
    /// and guessing would fabricate a verdict.
    static func decode(_ data: Data) -> Report? {
        guard data.count == wireByteCount else { return nil }
        func u32(_ offset: Int) -> UInt32 {
            var v: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &v) { data.copyBytes(to: $0, from: offset..<offset + 4) }
            return v.littleEndian
        }
        return Report(
            mailboxSupported: u32(0) != 0,
            msgReg: u32(4),
            argReg: u32(8),
            rspReg: u32(12),
            curveOptimizerCmd: u32(16),
            smnTctlRaw: u32(20),
            testRspCode: Int32(bitPattern: u32(24)),
            testArg0: u32(28),
            testElapsedUs: u32(32),
            versionRspCode: Int32(bitPattern: u32(36)),
            versionRaw: u32(40),
            versionElapsedUs: u32(44)
        )
    }

    /// SMU response codes (kernel `SMUResponse`); negative app-side codes
    /// (e.g. -11 for an unsupported mailbox) ride the same fields.
    static func responseName(_ code: Int32) -> String {
        switch code {
        case 1: return "OK"
        case 0: return "TIMEOUT"
        case 0xFF: return "FAILED"
        case 0xFE: return "UNKNOWN_CMD"
        case 0xFD: return "BUSY"
        case -11: return "UNSUPPORTED"
        default: return String(format: "0x%02X", UInt32(bitPattern: code))
        }
    }

    /// One rendered probe line for the diagnostics bundle.
    static func line(for report: Report) -> String {
        var lines: [String] = []
        lines.append(String(format: "mailbox: supported=%@ cmd=0x%08X arg=0x%08X rsp=0x%08X co=0x%02X",
                            report.mailboxSupported ? "1" : "0",
                            report.msgReg, report.argReg, report.rspReg,
                            report.curveOptimizerCmd))
        lines.append(String(format: "smn-aperture: TCTL(0x59800)=0x%08X%@",
                            report.smnTctlRaw,
                            report.smnTctlRaw == 0xFFFFFFFF ? " (BROKEN — PCI routing?)" : ""))
        lines.append(String(format: "test-message(0x01): rsp=%@ arg0=0x%X (%@) — %@",
                            responseName(report.testRspCode), report.testArg0,
                            formatUs(report.testElapsedUs),
                            (report.testRspCode == 1 && report.testArg0 == 0x43) ? "ROUND-TRIP OK" : "ROUND-TRIP MISMATCH"))
        lines.append(String(format: "smu-version(0x02): rsp=%@ raw=0x%08X (%@)%@",
                            responseName(report.versionRspCode), report.versionRaw,
                            formatUs(report.versionElapsedUs),
                            AMDSmuReadback.formatSmuVersion(report.versionRaw).map { " — SMU fw \($0)" } ?? ""))
        return lines.joined(separator: "\n")
    }

    /// Overall verdict: SMN aperture alive, the Arg0+1 round-trip came back
    /// exact, version read OK. Anything else is a degraded mailbox.
    static func decodeHealthy(_ report: Report) -> Bool {
        report.mailboxSupported
            && report.smnTctlRaw != 0 && report.smnTctlRaw != 0xFFFFFFFF
            && report.testRspCode == 1 && report.testArg0 == 0x43
            && report.versionRspCode == 1
    }

    private static func formatUs(_ us: UInt32) -> String {
        us >= 1000 ? String(format: "%.1f ms", Double(us) / 1000.0) : "\(us) us"
    }
}

// MARK: - OC Mode (S8, selectors 49/50 — Vermeer 0x5A/0x5B)

/// OC-mode cache-state codes reported by kext selector 49 ([2]) and the
/// semantic validation for selector 50 writes. The SMU has no read-back for
/// OC mode: `unknown` honestly means "this driver never touched it this
/// boot" — another tool may have flipped it before we loaded.
enum AMDOcMode {
    case unknown
    case enabled
    case disabled

    /// Decode the kext's cache code.
    static func from(code: UInt64) -> AMDOcMode {
        switch code {
        case 1: return .enabled
        case 2: return .disabled
        default: return .unknown
        }
    }

    /// Validate a selector-50 request before submission: enable and disable
    /// are both meaningful; anything else is rejected app-side.
    static func validate(enable: Bool, resetScalar: Bool) -> Bool {
        // A scalar reset only makes sense when disabling.
        !resetScalar || !enable
    }
}

// MARK: - OC Frequency Override (S8.2, selectors 51/52 — Vermeer 0x5C/0x5D)

/// Encoding helpers for the Vermeer SMU frequency-override commands, pinned
/// from two independent sources (amkillam/ryzen_smu rsmu_commands.md and
/// irusanov/ZenStates-Core `MakeCoreMask`) — see S_SERIES_ROADMAP.md §1.
///
/// 0x5C (all cores): arg = freq & 0xFFFFF — absolute MHz.
/// 0x5D (per-CCD):  arg = (freq & 0xFFFFF) | coreMask with the documented
/// fields [31:28] CCD, [27:24] CCX, [23:20] core-in-CCX, [19:0] freq MHz.
/// Vermeer has one CCX per CCD and all cores of a CCX must share one
/// frequency (CCX-uniformity rule, both sources), so the effective
/// granularity IS the CCD: with core = ccd·8, (core % 8) == 0 and the mask
/// collapses to `(ccd << 28) | freq`. The kernel builds the mask itself —
/// these helpers exist for the app-side clamp + cache decode, never to ship
/// packed masks over IPC.
enum AMDOcFreq {
    /// Doc-documented envelope: MIN 400, MAX 8000 MHz (absolute targets).
    static let minMHz = 400
    static let maxMHz = 8000
    /// Kernel `kS8MaxCcds` mirror — Vermeer tops out well below this.
    static let maxCcds = 8

    /// Validate an absolute MHz target against the pinned envelope.
    static func isValidMHz(_ mhz: Int) -> Bool {
        mhz >= minMHz && mhz <= maxMHz
    }

    /// 0x5C argument for an all-core target. Nil outside 400…8000.
    static func allCoresArg(_ mhz: Int) -> UInt32? {
        guard isValidMHz(mhz) else { return nil }
        return UInt32(mhz) & 0xFFFFF
    }

    /// 0x5D argument for a single Vermeer CCD target. Nil outside the
    /// envelope or for a CCD index ≥ 8.
    ///
    /// The full documented packing (non-Vermeer future) is
    /// `(ccd << 28) | ((ccx & 0xF) << 24) | ((core % 8) << 20) | freq`;
    /// on Vermeer ccx is always 0 and core = ccd·8, so both inner fields
    /// vanish. Written out longhand here to match the pinned spec.
    static func perCcdArg(ccd: Int, mhz: Int) -> UInt32? {
        guard ccd >= 0, ccd < maxCcds, isValidMHz(mhz) else { return nil }
        let ccx = 0                        // Vermeer: one CCX per CCD
        let core = ccd * 8                 // first core of the CCD's CCX
        let freqField = UInt32(mhz) & 0xFFFFF
        let coreField = UInt32(core % 8) << 20          // == 0 on Vermeer
        let ccxField = UInt32(ccx & 0xF) << 24          // == 0 on Vermeer
        let ccdField = UInt32(ccd) << 28
        return ccdField | ccxField | coreField | freqField
    }

    /// Inverse of `perCcdArg` for cache/debug rendering of a 0x5D arg:
    /// refuses freq fields above 0xFFFFF·0 that cannot exist (mhz ≤ 8000
    /// always fits) and out-of-range CCD indices.
    static func decode(mask: UInt32) -> (ccd: Int, core: Int, mhz: Int)? {
        let ccd = Int(mask >> 28)
        let ccx = Int((mask >> 24) & 0xF)
        let coreInCcx = Int((mask >> 20) & 0xF)
        let mhz = Int(mask & 0xFFFFF)
        guard ccd < maxCcds, isValidMHz(mhz) else { return nil }
        // Absolute core index for display: Vermeer layout (core % 8 maps
        // within one CCD of 8; other layouts stay documented-unknown).
        let core = ccd * 8 + (ccx * 8 + coreInCcx) % 8
        return (ccd, core, mhz)
    }
}

// MARK: - SMU PM Table (selectors 56/57 — 0x05/0x06/0x08 plumbing)

/// Decode/format helpers for the SMU PM-table plumbing wave. The version
/// word from `GetPMTableVersion` (0x08) is BCD-style, e.g. 0x380904 renders
/// as "38.09.04" (the reference treats it as three byte fields; unknown
/// bytes stay honest in hex rather than guessed).
enum AMDSmuPMTable {
    /// BCD-ish rendering of the version word: three byte fields joined with
    /// dots. Refuses nothing — unknown words still render field-by-field,
    /// which is exactly what a bug report needs.
    static func formatVersion(_ raw: UInt32) -> String {
        String(format: "%02u.%02u.%02u",
               (raw >> 16) & 0xFF, (raw >> 8) & 0xFF, raw & 0xFF)
    }

    /// Known Vermeer/Chagall table sizes (bytes) — mirrors the kext's
    /// fail-closed size table (Ryzen-Master-sourced, reference smu.c).
    /// Used app-side only to display "unknown" when the kext reports 0.
    static func isKnownVersion(_ raw: UInt32) -> Bool {
        switch raw {
        case 0x2D0803, 0x2D0903, 0x380005, 0x380505, 0x380605,
             0x380705, 0x380804, 0x380805, 0x380904, 0x380905:
            return true
        default:
            return false
        }
    }

    // MARK: — Decoded per-core telemetry from a captured snapshot

    /// One decoded core row of the 0x380805 Vermeer PM table. All raw SMU
    /// floats, byte-for-byte what the table holds (ryzen_monitor's mapping,
    /// pm_tables.c — validated on a 5900XT live capture).
    struct CoreRow: Equatable {
        /// Table slot index 0…15 (Vermeer topology order, not OS core number).
        let slot: Int
        /// CORE_POWER — watts.
        let powerW: Float
        /// CORE_VOLTAGE — raw SMU per-core voltage word (SVI2-ish; the
        /// display voltage ryzen_monitor derives from telemetry differs).
        let voltageRaw: Float
        /// CORE_TEMP — °C.
        let tempC: Float
        /// CORE_FREQEFF × 1000 — effective clock in MHz (the value AMD
        /// reports as the real average, vs CORE_FREQ the requested one).
        let freqMHz: Float
        /// CORE_C0 — % of time in C0 (0…100).
        let c0Percent: Float
        /// CORE_CC1 — % of time in CC1.
        let cc1Percent: Float
        /// CORE_CC6 — % of time in CC6 (package core-column entry).
        let cc6Percent: Float

        /// AMD/Ryzen Master sleeping threshold: a core that spent < 6% of
        /// the sample window in C0 is considered parked.
        var isSleeping: Bool { c0Percent < 6.0 }

        /// A disabled (fused-off) slot decodes as all-zero on real silicon.
        var isPresent: Bool {
            powerW != 0 || tempC != 0 || freqMHz != 0 || c0Percent != 0
        }
    }

    /// Package-level fields decoded from the table head (elements 0…51 + PC6).
    struct Summary: Equatable {
        let pptLimitW: Float
        let pptValueW: Float
        let tdcLimitA: Float
        let tdcValueA: Float
        let edcLimitA: Float
        let edcValueA: Float
        let thmLimitC: Float
        /// VID_VALUE — core VRM voltage in V (limit is element 10).
        let coreVoltageV: Float
        let coreVoltageLimitV: Float
        /// CPU_TELEMETRY_VOLTAGE — SVI2 telemetry V.
        let cpuTelemetryV: Float
        /// SOCKET_POWER — package socket power in W.
        let socketPowerW: Float
        /// FCLK/UCLK/MEMCLK in MHz.
        let fclkMHz: Float
        let uclkMHz: Float
        let memclkMHz: Float
        /// PEAK_TEMP — hottest sensor reading this window, °C.
        let peakTempC: Float
        /// PC6 — package C6 residency % (0 = unsupported/never sleeps).
        let pc6Percent: Float
    }

    /// One decoded L3 (GameCache) cache row. Fields mirror the L3 block of
    /// `pm_tables.c`: 16 elements per cache, field arrays of `l3Count`
    /// consecutive elements — element(field j, cache i) = base + j·l3Count + i.
    /// Validated upstream (0x380805/0x380804) and against two live 5900XT
    /// captures; 0x380904/0x380905 inherit their head's guess caveat.
    struct L3Row: Equatable {
        /// Cache index within the package (0 for single-CCD parts, 0…1 for
        /// Vermeer dual-CCD).
        let id: Int
        /// L3_TEMP — °C.
        let tempC: Float
        /// L3_FREQ_EFF × 1000 — effective GameCache clock in MHz (the table
        /// stores GHz like the core clocks; live capture reads ~4.4).
        let freqEffMHz: Float
        /// L3_LOGIC_POWER — logic power in W.
        let logicPowerW: Float
        /// L3_VDDM_POWER — VDDM power in W.
        let vddmPowerW: Float
        /// L3_EDC_LIMIT — EDC ceiling for the cache in A.
        let edcLimitA: Float
    }

    /// Decoded snapshot for one capture. `cores` has one slot per core the
    /// version's layout defines: 16 for 0x380805 (Vermeer dual-CCD), 8 for
    /// 0x380904/0x380905 (single-CCD parts like the 5600X). Disabled slots
    /// carry `isPresent == false`. `l3` follows the version's cache count
    /// (2 for the 16-core layouts, 1 for the 8-core ones).
    struct Decoded: Equatable {
        let summary: Summary
        let cores: [CoreRow]
        let l3: [L3Row]
    }

    /// Freshness gate for promoting SMU-native values over the kext's
    /// computed estimates: the kext's 1 Hz timer must have published the
    /// snapshot within the promotion window (older ⇒ the timer stopped and
    /// SMU values are stale — callers fall back to the estimate path).
    static func isFresh(ageMs: UInt64, limitMs: UInt64 = 6_000) -> Bool {
        ageMs <= limitMs
    }

    /// Package-head element map — identical across the Vermeer/Zen3 layout
    /// family (verified element-by-element between `pm_table_0x380805`,
    /// `pm_table_0x380904` and `pm_table_0x380905` in hattedsquirrel
    /// ryzen_monitor pm_tables.c). 4-byte float stride.
    private enum PmHead {
        static let pptLimit = 0
        static let pptValue = 1
        static let tdcLimit = 2
        static let tdcValue = 3
        static let thmLimit = 4
        static let edcLimit = 8
        static let edcValue = 9
        static let vidLimit = 10
        static let vidValue = 11
        static let socketPower = 29
        static let fclk = 48
        static let uclk = 50
        static let memclk = 51
        static let peakTemp = 140
    }

    /// Per-version deltas within the family: telemetry-voltage/PC6 head
    /// positions, core count, and the per-core block bases (element of slot
    /// 0; each block is `maxCores` consecutive elements).
    private struct Layout {
        let maxCores: Int
        /// min_size from pm_tables.c (highest accessed element + 1) × 4 —
        /// equals the kext size-table entry for the version.
        let minBytes: Int
        /// CPU_TELEMETRY_VOLTAGE (0x380805/0x380905: 40; 0x380904: 41).
        let cpuTelemetryVoltage: Int
        /// PC6 package residency (0x380805/0x380905: 155; 0x380904: 152).
        let pc6: Int
        let corePower: Int
        let coreVoltage: Int
        let coreTemp: Int
        let coreFreqEff: Int
        let coreC0: Int
        let coreCC1: Int
        let coreCC6: Int
        /// First element of the L3 (GameCache) block, or nil when a version
        /// has no L3 map documented (all four supported Zen3 versions do).
        /// The block is the tail of every layout: pm_tables.c sets each
        /// table's `min_size = (highest L3 element + 1) × 4`, so the existing
        /// minimum-size gate already bounds-checks the whole block.
        let l3Base: Int?
        /// Caches in the L3 block (1 = single-CCD parts, 2 = Vermeer).
        let l3Count: Int
    }

    /// Supported layouts. Provenance per pm_tables.c:
    /// - 0x380805: tested upstream on a 5900X AND hardware-validated by us
    ///   against two live 5900XT captures (Tests/Fixtures/PMTable).
    /// - 0x380905: upstream "pure guess" derived from 0x380805/0x380904 for
    ///   the 5600X; our synthetic tests exercise the mapping, silicon
    ///   confirmation still pending a real capture.
    /// - 0x380904: upstream loosely tested on a 5600X (older head: telemetry
    ///   voltage at 41, PC6 at 152, core blocks from 169).
    /// - 0x380804: tested upstream on a 5900X across several AGESA versions
    ///   (older head like 0x380904; 16-core blocks from 169).
    /// 0x380705 has NO public authoritative element map (verified: neither
    /// hattedsquirrel pm_tables.c nor leogx9r monitor_cpu.c defines it),
    /// so it stays fail-closed — the kext may capture it, the app must not
    /// guess telemetry offsets.
    private static let layouts: [UInt32: Layout] = [
        0x380805: Layout(maxCores: 16, minBytes: 572 * 4, cpuTelemetryVoltage: 40, pc6: 155,
                         corePower: 172, coreVoltage: 188, coreTemp: 204, coreFreqEff: 268,
                         coreC0: 284, coreCC1: 300, coreCC6: 316,
                         l3Base: 540, l3Count: 2),
        0x380905: Layout(maxCores: 8, minBytes: 372 * 4, cpuTelemetryVoltage: 40, pc6: 155,
                         corePower: 172, coreVoltage: 180, coreTemp: 188, coreFreqEff: 220,
                         coreC0: 228, coreCC1: 236, coreCC6: 244,
                         l3Base: 356, l3Count: 1),
        0x380904: Layout(maxCores: 8, minBytes: 361 * 4, cpuTelemetryVoltage: 41, pc6: 152,
                         corePower: 169, coreVoltage: 177, coreTemp: 185, coreFreqEff: 217,
                         coreC0: 225, coreCC1: 233, coreCC6: 241,
                         l3Base: 345, l3Count: 1),
        0x380804: Layout(maxCores: 16, minBytes: 553 * 4, cpuTelemetryVoltage: 41, pc6: 152,
                         corePower: 169, coreVoltage: 185, coreTemp: 201, coreFreqEff: 249,
                         coreC0: 265, coreCC1: 281, coreCC6: 297,
                         l3Base: 521, l3Count: 2),
    ]

    /// Decode a captured snapshot for one table version. Fail-closed:
    /// returns nil for any version without a layout in `layouts` (e.g.
    /// 0x380705 — the kext can capture it but the app cannot yet decode it)
    /// or snapshots shorter than the layout's documented minimum.
    static func decode(version: UInt32, data: Data) -> Decoded? {
        guard let l = layouts[version], data.count >= l.minBytes else { return nil }

        func f(_ element: Int) -> Float {
            Float(bitPattern: data.withUnsafeBytes { raw in
                raw.loadUnaligned(fromByteOffset: element * 4, as: UInt32.self)
            })
        }

        let summary = Summary(
            pptLimitW: f(PmHead.pptLimit),
            pptValueW: f(PmHead.pptValue),
            tdcLimitA: f(PmHead.tdcLimit),
            tdcValueA: f(PmHead.tdcValue),
            edcLimitA: f(PmHead.edcLimit),
            edcValueA: f(PmHead.edcValue),
            thmLimitC: f(PmHead.thmLimit),
            coreVoltageV: f(PmHead.vidValue),
            coreVoltageLimitV: f(PmHead.vidLimit),
            cpuTelemetryV: f(l.cpuTelemetryVoltage),
            socketPowerW: f(PmHead.socketPower),
            fclkMHz: f(PmHead.fclk),
            uclkMHz: f(PmHead.uclk),
            memclkMHz: f(PmHead.memclk),
            peakTempC: f(PmHead.peakTemp),
            pc6Percent: f(l.pc6)
        )

        var cores = [CoreRow]()
        cores.reserveCapacity(l.maxCores)
        for slot in 0..<l.maxCores {
            cores.append(CoreRow(
                slot: slot,
                powerW: f(l.corePower + slot),
                voltageRaw: f(l.coreVoltage + slot),
                tempC: f(l.coreTemp + slot),
                freqMHz: f(l.coreFreqEff + slot) * 1000,
                c0Percent: f(l.coreC0 + slot),
                cc1Percent: f(l.coreCC1 + slot),
                cc6Percent: f(l.coreCC6 + slot)
            ))
        }

        // L3 (GameCache) block. Element(field j, cache i) =
        // base + j·l3Count + i (field arrays are l3Count consecutive
        // elements). Display fields only — FIT/CKS_FDD/CCA/… stay raw.
        var l3 = [L3Row]()
        if let base = l.l3Base {
            l3.reserveCapacity(l.l3Count)
            for cache in 0..<l.l3Count {
                l3.append(L3Row(
                    id: cache,
                    tempC: f(base + 2 * l.l3Count + cache),
                    freqEffMHz: f(base + 6 * l.l3Count + cache) * 1000,
                    logicPowerW: f(base + cache),
                    vddmPowerW: f(base + 1 * l.l3Count + cache),
                    edcLimitA: f(base + 11 * l.l3Count + cache)
                ))
            }
        }
        return Decoded(summary: summary, cores: cores, l3: l3)
    }
}
