// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Pure logic behind the Settings "Hardware Validation" page.
///
/// Why this exists: the S-series waves shipped an SMU control surface whose
/// on-hardware probes were never run. The probes did not stall for lack of
/// code — they stalled because their *evidence* had nowhere to live. The
/// kernel log is unreadable for our tooling (`log show` is sandboxed) and
/// `--sensors` cannot be used mid-probe at all: opening and closing a user
/// client releases all six fans to BIOS, which silently resets the very state
/// a probe is measuring (see `.kiro/steering/hardware-safety.md`).
///
/// So the app becomes the evidence surface. This type holds the three pieces
/// that make a probe cycle auditable and repeatable:
///
/// 1. the **precondition gates** that decide whether a measurement means
///    anything at all (a probe run without privilege measures the BIOS idle,
///    not the floor);
/// 2. the **ASCII report** a probe records, under the same paste-able
///    convention as the SMU diagnostics bundle;
/// 3. the **checklist record** (status + samples) that survives the reboot
///    a cycle spans.
///
/// Foundation-only and deterministic on purpose: it joins `build.sh --test`,
/// so every verdict rule below is unit-tested without a kext. Nothing here
/// touches IOKit, and nothing here decides anything the kernel decides — the
/// gates only label whether a measurement is trustworthy.
enum HardwareValidation {

    // MARK: - Expected identity

    /// Kext revision the current runbook probes are written against.
    ///
    /// A version bump is a debugging tool in this project: two different
    /// binaries sharing a version number are indistinguishable in `kextstat`,
    /// so a probe against an unknown build is void before it starts. Pinned by
    /// a test that reads `Config/Version.xcconfig`, the single source of truth,
    /// so bumping the kext cannot silently leave this pointing backwards.
    static let expectedKextVersion = "3.34.17"

    /// The app release that introduced this harness. Informational — the app
    /// version coming from the bundle is what gets reported.
    static let expectedAppVersion = "1.36.1"

    /// The reference machine's Super I/O family. The probe expectations (the
    /// ~15.7 % rotor-start floor, the six ITE channels) are calibrated for it;
    /// on any other family a PASS is still meaningful, but a FAIL is not
    /// evidence of a kernel bug until the runbook is re-read.
    static let referenceSuperIOFamily = "ITE IT86XXE"

    // MARK: - Driver header name tables
    //
    // Pinned against the kernel's own `kFAN_READABLE_STRS` arrays by a test
    // that parses the three driver headers, so the family inference cannot
    // drift away from the drivers it infers from. These names are hardcoded in
    // the drivers (never read off the board), which is exactly what makes them
    // usable as a fingerprint of the driver that answered.

    /// `ISSuperIOIT86XXEFamily.hpp`.
    static let iteHeaderNames: [String] = [
        "CPU Fan", "System 1 Fan", "System 2 Fan",
        "PCH Fan", "CPU OPT Fan", "System 3 Fan",
    ]

    /// `ISSuperIONCT67XXFamily.hpp` — the labels unique to this family.
    static let nct67xxDistinctiveNames: [String] = [
        "AUX_0", "AUX_1", "AUX_2", "AUX_3", "PECI",
    ]

    /// `ISSuperIONCT668X.hpp` — the labels unique to this family.
    static let nct668xDistinctiveNames: [String] = [
        "SYS_1", "SYS_2", "SYS_3", "SYS_4", "SYS_5", "AUX",
    ]

    /// Labels both NCT families use, so they identify the family but not which
    /// one (`ISSuperIONCT67XXFamily.hpp` and `ISSuperIONCT668X.hpp` overlap).
    static let nctSharedNames: [String] = ["CPU", "Pump"]

    // MARK: - Verdicts

    enum Verdict: String, Equatable {
        case pass = "PASS"
        case fail = "FAIL"
        case unknown = "UNKNOWN"
    }

    /// One precondition, and why it can void a probe.
    enum Gate: String, CaseIterable, Equatable {
        /// The driver that answered is the binary the runbook was written for.
        case kextVersion = "kext-version"
        /// The kext connection is live and selector 100 produced a packet —
        /// without it there is no package temperature to judge a fan against.
        case kextTelemetry = "kext-telemetry"
        /// Privileged access works. This is the probe cycle's worst false
        /// positive: with no privilege the curve never uploads, the fan keeps
        /// spinning at the BIOS idle setpoint (~15 %), and that number is
        /// indistinguishable from the floor a P2 run is supposed to prove.
        case privilege
        /// Channels exist and at least one is not a pump. A pump must stay on
        /// BIOS control; throttling one raises CPU temperature under load.
        case fanTopology = "fan-topology"
        /// Per-channel tachometer trust. A frozen or unconnected channel
        /// reports a plausible unchanging RPM, which every RPM-based
        /// heuristic — including the kernel's rotor-start floor — reads as a
        /// healthy rotor.
        case tachValidity = "tach-validity"
        /// Which Super I/O answered.
        case superIOFamily = "superio-family"
    }

    struct GateResult: Equatable {
        let gate: Gate
        let verdict: Verdict
        /// Technical, unlocalized detail (versions, counts, indices), same
        /// convention as the diagnostics bundle.
        let detail: String
    }

    // MARK: - Evidence

    struct FanEvidence: Equatable {
        let id: Int
        let name: String
        let isPump: Bool
        let rpm: UInt64
        let rpmValid: Bool
        let throttle: UInt8
        let isAuto: Bool

        var pwmPercent: Double { (Double(throttle) / 255.0) * 100.0 }

        init(id: Int, name: String, isPump: Bool, rpm: UInt64,
             rpmValid: Bool, throttle: UInt8, isAuto: Bool) {
            self.id = id
            self.name = name
            self.isPump = isPump
            self.rpm = rpm
            self.rpmValid = rpmValid
            self.throttle = throttle
            self.isAuto = isAuto
        }
    }

    struct CurveEvidence: Equatable {
        let name: String
        /// "cpu" / "gpu" — the sensor the kernel evaluates this curve against.
        let sourceSensor: String
        let fanIds: [Int]
    }

    /// Everything the gates and the report need, as plain values. The live
    /// snapshot is assembled in the UI layer; this type stays testable.
    struct Snapshot: Equatable {
        var appVersion: String = ""
        var appBuild: String = ""
        var kextVersion: String = ""
        var kextConnected: Bool = false
        /// Selector 100 produced a packet this snapshot.
        var hasTelemetryPacket: Bool = false
        /// The privileged read-only probe (selector 58) was attempted.
        var privilegeChecked: Bool = false
        /// …and the kext answered with a report.
        var privilegeReported: Bool = false
        /// …or refused it.
        var privilegeDenied: Bool = false
        /// Last denial text observed on any write path this session.
        var privilegeMessage: String? = nil
        var fans: [FanEvidence] = []
        var packageTempC: Double = 0
        var packagePowerW: Double = 0
        var curves: [CurveEvidence] = []
        /// Pre-formatted SMU state lines (the same ones the diagnostics bundle
        /// carries) — this type deliberately knows nothing about SMU decoding.
        var smuLines: [String] = []
        var pmTableLine: String? = nil
        var expectedKextVersion: String = HardwareValidation.expectedKextVersion
        /// When the values above were read. The gates read like a live meter,
        /// so the page has to be able to say how stale they are.
        var capturedAt: Date? = nil

        /// Where the probes in the runbook are expected to be run.
        var onReferenceSuperIO: Bool {
            HardwareValidation.superIOFamily(for: fans) == HardwareValidation.referenceSuperIOFamily
        }
    }

    // MARK: - Gate evaluation

    static func gates(_ s: Snapshot) -> [GateResult] {
        [kextVersionGate(s), telemetryGate(s), privilegeGate(s),
         topologyGate(s), tachGate(s), familyGate(s)]
    }

    private static func kextVersionGate(_ s: Snapshot) -> GateResult {
        if s.kextVersion.isEmpty {
            return GateResult(gate: .kextVersion, verdict: .unknown,
                              detail: "driver version not reported (no connection)")
        }
        if s.kextVersion == s.expectedKextVersion {
            return GateResult(gate: .kextVersion, verdict: .pass,
                              detail: "\(s.kextVersion) == expected \(s.expectedKextVersion)")
        }
        return GateResult(gate: .kextVersion, verdict: .fail,
                          detail: "\(s.kextVersion) != expected \(s.expectedKextVersion)")
    }

    private static func telemetryGate(_ s: Snapshot) -> GateResult {
        if !s.kextConnected {
            return GateResult(gate: .kextTelemetry, verdict: .fail,
                              detail: "kext connection closed")
        }
        if !s.hasTelemetryPacket {
            return GateResult(gate: .kextTelemetry, verdict: .fail,
                              detail: "selector 100 packet unavailable")
        }
        return GateResult(gate: .kextTelemetry, verdict: .pass,
                          detail: String(format: "selector 100: %.1f C / %.1f W",
                                         s.packageTempC, s.packagePowerW))
    }

    private static func privilegeGate(_ s: Snapshot) -> GateResult {
        if s.privilegeDenied {
            let why = s.privilegeMessage ?? "kext refused the privileged probe"
            return GateResult(gate: .privilege, verdict: .fail, detail: why)
        }
        if s.privilegeReported {
            return GateResult(gate: .privilege, verdict: .pass,
                              detail: "privileged read-only probe answered (selector 58)")
        }
        if let message = s.privilegeMessage {
            return GateResult(gate: .privilege, verdict: .fail,
                              detail: "write denied this session: \(message)")
        }
        return GateResult(gate: .privilege, verdict: .unknown,
                          detail: s.privilegeChecked
                              ? "probe attempted, no verdict from the kext"
                              : "not checked — run the preconditions check")
    }

    private static func topologyGate(_ s: Snapshot) -> GateResult {
        guard !s.fans.isEmpty else {
            return GateResult(gate: .fanTopology, verdict: .fail,
                              detail: "no fan channels reported")
        }
        let pump = s.fans.filter(\.isPump).map(\.id)
        let safe = s.fans.filter { !$0.isPump }.map(\.id)
        guard !safe.isEmpty else {
            return GateResult(gate: .fanTopology, verdict: .fail,
                              detail: "every channel reads as a pump: pump=\(format(pump))")
        }
        return GateResult(gate: .fanTopology, verdict: .pass,
                          detail: "\(s.fans.count) channels, pump=\(format(pump)), curve-safe=\(format(safe))")
    }

    private static func tachGate(_ s: Snapshot) -> GateResult {
        guard !s.fans.isEmpty else {
            return GateResult(gate: .tachValidity, verdict: .unknown,
                              detail: "no fan channels reported")
        }
        let invalid = s.fans.filter { !$0.rpmValid }.map(\.id)
        if !invalid.isEmpty {
            return GateResult(gate: .tachValidity, verdict: .fail,
                              detail: "invalid tachometer: \(format(invalid)) — a stalled rotor "
                                    + "cannot be told apart from a dead sensor")
        }
        if s.fans.allSatisfy({ $0.rpm == 0 }) {
            return GateResult(gate: .tachValidity, verdict: .unknown,
                              detail: "every channel reports 0 RPM — a stopped system cannot "
                                    + "demonstrate a live tachometer")
        }
        return GateResult(gate: .tachValidity, verdict: .pass,
                          detail: "\(s.fans.count)/\(s.fans.count) channels trusted")
    }

    private static func familyGate(_ s: Snapshot) -> GateResult {
        let family = superIOFamily(for: s.fans)
        if family == referenceSuperIOFamily {
            return GateResult(gate: .superIOFamily, verdict: .pass,
                              detail: "\(family) (driver header names)")
        }
        if family.isEmpty {
            return GateResult(gate: .superIOFamily, verdict: .unknown,
                              detail: "no driver header names reported")
        }
        return GateResult(gate: .superIOFamily, verdict: .unknown,
                          detail: "\(family) — the runbook's expected values are calibrated "
                                + "for \(referenceSuperIOFamily)")
    }

    // MARK: - Super I/O family inference

    /// Infers which Super I/O driver answered from the header names it reports.
    ///
    /// The names are a driver constant, not board data — the driver hardcodes
    /// a generic label per channel and a real board maps its own headers onto
    /// them however it likes. That makes the label set a faithful fingerprint
    /// of the *driver*, which is the only thing the runbook needs here; the
    /// physical mapping (which channel is the pump) stays a human decision.
    ///
    /// - Returns: the family name, `""` when no channel reported a name, or
    ///   the unrecognized label set when it matches no known table.
    static func superIOFamily(for fans: [FanEvidence]) -> String {
        let names = Set(fans.map(\.name).filter { !$0.isEmpty })
        guard !names.isEmpty else { return "" }
        if !names.isDisjoint(with: iteHeaderNames) { return referenceSuperIOFamily }
        if !names.isDisjoint(with: nct67xxDistinctiveNames) { return "Nuvoton NCT67XX" }
        if !names.isDisjoint(with: nct668xDistinctiveNames) { return "Nuvoton NCT668X" }
        if !names.isDisjoint(with: nctSharedNames) { return "Nuvoton (unidentified)" }
        return "unrecognized (\(names.sorted().joined(separator: ", ")))"
    }

    // MARK: - Report

    /// The paste-able ASCII artifact for one probe snapshot.
    ///
    /// Unlocalized on purpose, exactly like the SMU diagnostics bundle: this
    /// text gets pasted into the roadmap/issue tracker, and a localized
    /// artifact would make two runs incomparable.
    static func report(_ s: Snapshot, samples: [String], now: Date) -> String {
        var lines: [String] = []
        lines.append("RyzenStatus hardware validation — app \(s.appVersion.isEmpty ? "?" : s.appVersion) "
                     + "(\(s.appBuild.isEmpty ? "?" : s.appBuild)), "
                     + "kext \(s.kextVersion.isEmpty ? "not connected" : s.kextVersion) "
                     + "(expected \(s.expectedKextVersion))")
        lines.append("captured \(timestamp(s.capturedAt ?? now))")
        lines.append("")
        lines.append("preconditions:")
        for result in gates(s) {
            lines.append("  \(result.gate.rawValue.padding(toLength: 15, withPad: " ", startingAt: 0)) "
                         + "\(result.verdict.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) "
                         + result.detail)
        }
        lines.append("")
        lines.append("fans:")
        if s.fans.isEmpty {
            lines.append("  (no channels reported)")
        } else {
            lines.append(contentsOf: fanLines(s).map { "  " + $0 })
        }
        lines.append("")
        lines.append("curves:")
        if s.curves.isEmpty {
            lines.append("  (no curves configured)")
        } else {
            for curve in s.curves {
                let fans = curve.fanIds.isEmpty ? "unmapped" : "fans=\(format(curve.fanIds))"
                lines.append("  \"\(curve.name)\" source=\(curve.sourceSensor) \(fans)")
            }
        }
        lines.append("")
        lines.append("package: temp=\(decimal(s.packageTempC)) C power=\(decimal(s.packagePowerW)) W"
                     + "  floor=PWM\(AMDFanSafety.minimumManualPWM)"
                     + " guard=\(decimal(AMDFanSafety.thermalGuardTempC)) C/PWM\(AMDFanSafety.thermalGuardPWM)"
                     + " failsafe=PWM\(AMDFanSafety.failsafePWM)")
        lines.append("")
        lines.append("smu:")
        if s.smuLines.isEmpty {
            lines.append("  (no SMU state available)")
        } else {
            lines.append(contentsOf: s.smuLines.map { "  " + $0 })
        }
        lines.append("")
        lines.append("pm-table:")
        lines.append("  \(s.pmTableLine ?? "not available")")
        lines.append("")
        lines.append("samples (\(samples.count)):")
        if samples.isEmpty {
            lines.append("  (none recorded)")
        } else {
            lines.append(contentsOf: samples.map { "  " + $0 })
        }
        return lines.joined(separator: "\n")
    }

    /// One line per channel: mode, commanded duty, real reported duty and the
    /// two independent trust signals. The duty is what the Super I/O chip
    /// reports (the kext's own `lastAppliedPWM` is kernel-internal), which is
    /// why a duty path regression shows up here as six zeros.
    static func fanLines(_ s: Snapshot) -> [String] {
        s.fans.map { f in
            let name = f.name.isEmpty ? "fan\(f.id)" : f.name
            return "fan\(f.id) "
                + name.padding(toLength: 16, withPad: " ", startingAt: 0)
                + " mode=\(f.isAuto ? "auto  " : "manual")"
                + " duty=\(f.throttle) (\(decimal(f.pwmPercent))%)"
                + " rpm=\(f.rpm) valid=\(f.rpmValid ? 1 : 0)"
                + " pump=\(f.isPump ? 1 : 0)"
        }
    }

    /// One recorded sample: the package reading plus one compact token per
    /// channel, so a probe's time series survives in a few lines. A trailing
    /// `!` on a token marks an untrusted tachometer.
    static func sampleLine(probe: Probe,
                           at date: Date,
                           packageTempC: Double,
                           packagePowerW: Double,
                           fans: [FanEvidence]) -> String {
        let tokens = fans.map { f -> String in
            "f\(f.id)=\(f.throttle)/\(decimal(f.pwmPercent))%/\(f.rpm)\(f.rpmValid ? "v" : "v!")"
        }
        return "\(probe.rawValue) \(timestamp(date)) temp=\(decimal(packageTempC))C "
            + "pkg=\(decimal(packagePowerW))W " + tokens.joined(separator: " ")
    }

    /// Fixed-format local timestamp. A localized date would make two runs
    /// incomparable, which is the same reason the whole artifact is ASCII.
    static func timestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static func decimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func format(_ values: [Int]) -> String {
        values.isEmpty ? "[]" : "[\(values.map(String.init).joined(separator: ","))]"
    }

    // MARK: - Probe checklist

    /// The runbook's ordered probes. The list itself is code (not a doc) so the
    /// app can carry the status of each one across the reboot a cycle spans;
    /// the steps, pass criteria and known false positives live in
    /// `HARDWARE_VALIDATION.md`, which is the document a human runs.
    enum Probe: String, CaseIterable, Equatable {
        /// Driver identity: the version the kernel actually loaded.
        case identity = "P0"
        /// Dead-man switch: a latched fan returns to BIOS when the app dies.
        case deadMan = "P1"
        /// Curve-mode PWM floor under an idle anchor.
        case pwmFloor = "P2"
        /// System-wide emergency guard armed from a GPU-sourced curve.
        case thermalGuard = "P3"
        /// The SMU control family (PBO, OC gate, frequency override, cHTC).
        case smuControls = "P4"
        /// SMU telemetry surface: package power, per-core grid, L3, PM table.
        case telemetry = "P5"
        /// UI regressions the last app wave touched.
        case surfaces = "P6"
    }

    enum ProbeStatus: String, Equatable {
        case pending, pass, fail
    }

    /// Probe statuses and recorded samples, persisted as one JSON blob so a
    /// cycle that spans reboots keeps its history. Tolerant by construction: a
    /// missing, truncated or foreign value decodes to an empty record rather
    /// than losing the page.
    struct Record: Codable, Equatable {
        var statuses: [String: String] = [:]
        var samples: [String] = []

        /// Bounded so a long session cannot grow UserDefaults without limit.
        static let maxSamples = 400

        init() {}

        init(from decoder: Decoder) throws {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            statuses = (try? container?.decodeIfPresent([String: String].self, forKey: .statuses)) ?? [:]
            samples = (try? container?.decodeIfPresent([String].self, forKey: .samples)) ?? []
        }

        func status(of probe: Probe) -> ProbeStatus {
            ProbeStatus(rawValue: statuses[probe.rawValue] ?? "") ?? .pending
        }

        mutating func setStatus(_ status: ProbeStatus, for probe: Probe) {
            statuses[probe.rawValue] = status.rawValue
        }

        /// Appends one sample, dropping the oldest past the cap so the newest
        /// evidence — the part a probe is actually judged on — always survives.
        mutating func appendSample(_ line: String) {
            samples.append(line)
            if samples.count > Self.maxSamples {
                samples.removeFirst(samples.count - Self.maxSamples)
            }
        }

        mutating func clearSamples() {
            samples.removeAll()
        }

        /// How many probes are still unresolved, for the page summary.
        var pendingCount: Int {
            Probe.allCases.filter { status(of: $0) == .pending }.count
        }

        var failedProbes: [Probe] {
            Probe.allCases.filter { status(of: $0) == .fail }
        }

        static func decode(_ raw: String?) -> Record {
            guard let raw, let data = raw.data(using: .utf8) else { return Record() }
            return (try? JSONDecoder().decode(Record.self, from: data)) ?? Record()
        }

        func encoded() -> String {
            guard let data = try? JSONEncoder().encode(self),
                  let json = String(data: data, encoding: .utf8) else { return "" }
            return json
        }
    }
}
