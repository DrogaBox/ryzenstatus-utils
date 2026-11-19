// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// What the GPU control in GPUSensors.kext (0.3.0 and later) says about
/// itself: whether it watches the driver, the power profile the card booted
/// with and, from 0.4.0, the power limit and the sleeps and wakes it saw.
/// Read only: the app shows these and never writes anything to the kext.
///
/// The kext rebuilds every key on each full property read, the same
/// `IORegistryEntryCreateCFProperties` read the sensors use. Each key is
/// optional: 0.2.0 has none of them, 0.3.0 has no `Power`/`PowerWatch`.
struct GPUControlStatus: Equatable {
    /// `Control` and `Power`: a watch the kext runs or why it does not.
    enum Watch: Equatable {
        case watching
        /// `Power` only: some of its functions could not be routed.
        case watchingInPart
        case waiting
        /// The kext's reason (English, as it wrote it), nil for a bare "off".
        case off(reason: String?)
        /// A state this app does not know yet, shown as the kext wrote it.
        case other(String)
    }

    /// `Profile`: the power profile asked for at boot.
    enum Profile: Equatable {
        /// Nobody asked: macOS keeps the profile it sets on every Navi 21.
        case macOSDefault
        /// Put on the card before the power management started.
        case set
        case waiting
        case refused(reason: String?)
        case off
        case notSet(reason: String?)
        case other(String)
    }

    /// `PowerWatch` (0.4.0). Each field is nil when the kext left its key out:
    /// it only writes the ones whose function it watches and has a value for.
    struct PowerWatch: Equatable {
        var bootW: Int?
        var lastReadW: Int?
        var reads: Int?
        var sent: Int?
        var lastSentW: Int?
        var lastSentSource: Int?
        /// 0 = the firmware took it.
        var lastSentResult: Int?
        var sleeps: Int?
        var wakes: Int?
    }

    var control: Watch
    var profile: Profile?
    /// `ProfileSet`: the profile put on every allowed card, once it was.
    var profileSet: Int?
    var power: Watch?
    var powerWatch: PowerWatch?

    /// Nil for a kext without the GPU control (0.2.0 and older).
    static func parse(_ properties: [String: Any]) -> GPUControlStatus? {
        guard let control = properties["Control"] as? String else { return nil }
        let watch = PowerWatch.parse(properties["PowerWatch"])
        return GPUControlStatus(
            control: Watch.parse(control),
            profile: (properties["Profile"] as? String).map(Profile.parse),
            profileSet: integer(properties["ProfileSet"]),
            power: (properties["Power"] as? String).map(Watch.parse),
            powerWatch: watch)
    }

    /// A whole, non-negative number that fits an Int; anything else is no value.
    static func integer(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value <= Double(Int32.max), value == value.rounded() else { return nil }
        return Int(value)
    }

    /// What follows "off:", "refused:" or "not set:", nil when nothing does.
    fileprivate static func reason(_ text: String, after prefix: String) -> String? {
        let rest = text.dropFirst(prefix.count).drop { $0 == ":" || $0 == " " }
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension GPUControlStatus.Watch {
    /// The texts of `GPUControl::statusText()` and `powerText()`
    /// (kern_control.cpp): "watching ...", "watching in part: ...",
    /// "waiting for ...", "off" or "off: <reason>".
    static func parse(_ text: String) -> Self {
        if text.hasPrefix("watching in part") { return .watchingInPart }
        if text.hasPrefix("watching") { return .watching }
        if text.hasPrefix("waiting") { return .waiting }
        if text == "off" || text.hasPrefix("off:") || text.hasPrefix("off ") {
            return .off(reason: GPUControlStatus.reason(text, after: "off"))
        }
        return .other(text)
    }
}

extension GPUControlStatus.Profile {
    /// The texts of `GPUControl::profileText()` (kern_control.cpp).
    static func parse(_ text: String) -> Self {
        if text.hasPrefix("not asked") { return .macOSDefault }
        if text.hasPrefix("set") { return .set }
        if text.hasPrefix("asked") { return .waiting }
        if text.hasPrefix("refused") { return .refused(reason: GPUControlStatus.reason(text, after: "refused")) }
        if text.hasPrefix("not set") { return .notSet(reason: GPUControlStatus.reason(text, after: "not set")) }
        if text == "off" { return .off }
        return .other(text)
    }
}

extension GPUControlStatus.PowerWatch {
    static func parse(_ raw: Any?) -> Self? {
        guard let dict = raw as? [String: Any] else { return nil }
        func n(_ key: String) -> Int? { GPUControlStatus.integer(dict[key]) }
        return Self(bootW: n("BootW"), lastReadW: n("LastReadW"), reads: n("Reads"),
                    sent: n("Sent"), lastSentW: n("LastSentW"), lastSentSource: n("LastSentSource"),
                    lastSentResult: n("LastSentResult"), sleeps: n("Sleeps"), wakes: n("Wakes"))
    }
}

/// One line of the "GPU control" group in Settings > Sensors.
struct GPUControlRow: Equatable, Identifiable {
    let id: String
    let label: String
    let value: String
    /// The kext's own reason for an off, refused or unset state, in English
    /// as it wrote it; shown under the row.
    var detail: String?
    let icon: String
    /// Watts and counts, set in the page's monospaced figures.
    var isNumber = false
}

extension GPUControlStatus {
    /// The rows, in display order. Lines whose key the kext did not publish
    /// are left out, so 0.3.0 shows two rows and 0.4.0 up to six.
    func rows(_ s: GPUControlStrings) -> [GPUControlRow] {
        var rows: [GPUControlRow] = []
        let (controlText, controlDetail) = Self.text(control, watching: s.watchingProfileRequests, s)
        rows.append(GPUControlRow(id: "Control", label: s.control, value: controlText,
                                  detail: controlDetail, icon: "eye"))
        if let profile {
            let (text, detail) = profileText(profile, s)
            rows.append(GPUControlRow(id: "Profile", label: s.bootProfile, value: text,
                                      detail: detail, icon: "gauge.with.dots.needle.50percent"))
        }
        if let power {
            let (text, detail) = Self.text(power, watching: s.watchingPowerLimit, s)
            rows.append(GPUControlRow(id: "Power", label: s.powerWatch, value: text,
                                      detail: detail, icon: "bolt"))
        }
        if let watch = powerWatch {
            if let boot = watch.bootW, boot > 0 {
                rows.append(GPUControlRow(id: "BootW", label: s.bootPowerLimit,
                                          value: Self.watts(boot), icon: "bolt.badge.clock", isNumber: true))
            }
            if let sent = watch.sent, sent > 0, let watts = watch.lastSentW {
                var value = Self.watts(watts)
                if let result = watch.lastSentResult, result != 0 {
                    value = String(format: s.notTakenFormat, value, result)
                }
                rows.append(GPUControlRow(id: "LastSentW", label: s.lastLimitSent, value: value,
                                          icon: "arrow.up.forward", isNumber: true))
            }
            if watch.sleeps != nil || watch.wakes != nil {
                let value = "\(watch.sleeps.map(String.init) ?? "—") / \(watch.wakes.map(String.init) ?? "—")"
                rows.append(GPUControlRow(id: "SleepWake", label: s.sleepsWakes, value: value,
                                          icon: "moon.zzz", isNumber: true))
            }
        }
        return rows
    }

    /// The control's state in a few words, for the group's header.
    func summary(_ s: GPUControlStrings) -> String {
        switch control {
        case .watching, .watchingInPart: return s.watching
        case .waiting: return s.waiting
        case .off: return s.off
        case .other(let raw): return raw
        }
    }

    static func watts(_ value: Int) -> String { "\(value) W" }

    private static func text(_ watch: Watch, watching: String, _ s: GPUControlStrings) -> (String, String?) {
        switch watch {
        case .watching: return (watching, nil)
        case .watchingInPart: return (s.watchingInPart, nil)
        case .waiting: return (s.waitingForDriver, nil)
        case .off(let reason): return (s.off, reason)
        case .other(let raw): return (raw, nil)
        }
    }

    private func profileText(_ profile: Profile, _ s: GPUControlStrings) -> (String, String?) {
        switch profile {
        case .macOSDefault: return (s.profileMacOSDefault, nil)
        case .set:
            guard let value = profileSet else { return (s.profileSetAtBoot, nil) }
            return (String(format: s.profileSetFormat, Self.profileName(value, s)), nil)
        case .waiting: return (s.profileWaiting, nil)
        case .refused(let reason): return (s.refused, reason)
        case .off: return (s.off, nil)
        case .notSet(let reason): return (s.notSet, reason)
        case .other(let raw): return (raw, nil)
        }
    }

    /// The values `gpuprofile` takes (sensors/README.md): 0 lets the driver
    /// choose, 2 is power saving, 16 is what macOS sets on every Navi 21.
    static func profileName(_ value: Int, _ s: GPUControlStrings) -> String {
        switch value {
        case 0: return s.profileDriverChooses
        case 2: return s.profilePowerSaving
        case 16: return s.profileCompute
        default: return "\(value)"
        }
    }
}
