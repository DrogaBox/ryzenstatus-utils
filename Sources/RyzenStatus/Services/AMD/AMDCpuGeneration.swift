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
    static func supported(family: Int, model: Int, legacyPstateAllowed: Bool) -> Bool {
        legacyPstateAllowed && family == 0x19 && (0x21...0x2F).contains(model)
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
