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
