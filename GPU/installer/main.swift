import SwiftUI
import AppKit

// MARK: - Model

struct CheckItem: Identifiable, Decodable {
    let id: String
    let label: String
    let status: String   // ok | warn | fail
    let detail: String
}

struct DecodersCheck: Decodable {
    let canInstall: Bool
    let installed: String    // none | current | outdated
    let overridable: Bool
    let repairable: Bool
    let validated: Bool
    let macos: String
    let checks: [CheckItem]
}

struct EFIInfo: Decodable, Identifiable {
    let id: String
    let name: String
    let media: String
    let mounted: Bool
    let mountPoint: String
    let openCore: String
    let entry: String
    let kext: String
}

struct LoaderCheck: Decodable {
    let canInstall: Bool
    let version: String
    let running: String
    let accepted: String
    let acceptedDetail: String
    let result: String
    let efis: [EFIInfo]
    let checks: [CheckItem]
}

struct EncoderCheck: Decodable {
    let canInstall: Bool
    let version: String
    let installed: String    // none | current | outdated
    let service: String
    let kext: String
    let efis: [EFIInfo]
    let checks: [CheckItem]
}

struct SensorsCheck: Decodable {
    let canInstall: Bool
    let version: String
    let running: String
    let result: String
    let efis: [EFIInfo]
    let checks: [CheckItem]
}

enum ComponentID: String, CaseIterable, Identifiable {
    case decoders, loader, encoder, sensors
    var id: String { rawValue }
}

struct PlanResult: Identifiable {
    let id = UUID()
    let output: String
    let exitCode: Int32
    let withEncoder: Bool
    let withSensors: Bool
    // install.sh plan ends with this line when every part asked for is in place.
    var nothingToDo: Bool {
        exitCode == 0 && output.split(separator: "\n").contains { $0.hasPrefix("Nothing to install") }
    }
    var canInstall: Bool { exitCode == 0 && !nothingToDo }
}

enum ConfirmAction: Identifiable {
    case installDecoders(force: Bool)
    case repairDecoders
    case removeDecoders
    case installLoader
    case removeLoader
    case installEncoder
    case removeEncoder
    case installSensors
    case removeSensors
    case removeAll
    case reboot

    var id: String {
        switch self {
        case .installDecoders(let force): return "installDecoders-\(force)"
        case .repairDecoders: return "repairDecoders"
        case .removeDecoders: return "removeDecoders"
        case .installLoader:  return "installLoader"
        case .removeLoader:   return "removeLoader"
        case .installEncoder: return "installEncoder"
        case .removeEncoder:  return "removeEncoder"
        case .installSensors: return "installSensors"
        case .removeSensors:  return "removeSensors"
        case .removeAll:      return "removeAll"
        case .reboot:         return "reboot"
        }
    }
}

enum Phase: Equatable {
    case idle
    case checking
    case running(String)
    case done(String)
    case failed(String)
}

// MARK: - Engine bridge

final class Engine: ObservableObject {
    @Published var rootURL: URL? = nil
    @Published var decoders: DecodersCheck? = nil
    @Published var loader: LoaderCheck? = nil
    @Published var encoder: EncoderCheck? = nil
    @Published var sensors: SensorsCheck? = nil
    @Published var overallLine: String = ""
    @Published var leftovers: [String] = []
    @Published var phase: Phase = .idle
    @Published var lastOutput: String = ""
    @Published var lastActionTitle: String = ""
    @Published var needReboot = false
    @Published var planSheet: PlanResult? = nil
    /// True when the parts came inside this app (Contents/Resources/GPU), as in the DMG.
    /// Choosing a folder is then not offered: that is only for development builds.
    @Published var rootInBundle = false

    private static let rootDefaultsKey = "GPUToolsRoot"
    /// The folder the DMG build puts the parts in, inside Contents/Resources.
    static let bundledFolderName = "GPU"

    init() {
        if let bundled = Self.bundledRoot() {
            rootURL = bundled
            rootInBundle = true
        } else {
            rootURL = Self.findRootNearBundle()
        }
    }

    /// The parts inside this app: Contents/Resources/GPU, with install/ in it. Found from
    /// the bundle itself, so it works from the mounted DMG, from Applications, or from a
    /// translocated copy.
    static func bundledRoot() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let dir = resources.appendingPathComponent(bundledFolderName, isDirectory: true)
        return isValidRoot(dir) ? dir : nil
    }

    static func isValidRoot(_ dir: URL) -> Bool {
        let fm = FileManager.default
        let dec = dir.appendingPathComponent("install/decoders.sh").path
        let chk = dir.appendingPathComponent("install/check.sh").path
        return fm.isExecutableFile(atPath: dec) && fm.fileExists(atPath: chk)
    }

    static func findRootNearBundle() -> URL? {
        var dir = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<6 {
            if isValidRoot(dir) { return dir }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if isValidRoot(cwd) { return cwd }
        if let saved = UserDefaults.standard.string(forKey: rootDefaultsKey) {
            let url = URL(fileURLWithPath: saved)
            if isValidRoot(url) { return url }
        }
        return nil
    }

    func chooseRootFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose the GPU tools folder"
        panel.message = "Select the folder that contains install/ (for example, the GPU folder of the repository)."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if Self.isValidRoot(url) {
                UserDefaults.standard.set(url.path, forKey: Self.rootDefaultsKey)
                rootURL = url
                recheck()
            } else {
                phase = .failed("That folder does not contain install/decoders.sh and install/check.sh.")
            }
        }
    }

    func recheck(preserveOutput: Bool = false) {
        guard let root = rootURL else {
            phase = .failed("Select the GPU tools folder to check this Mac.")
            return
        }
        phase = .checking
        if !preserveOutput {
            lastOutput = ""
            lastActionTitle = ""
        }
        DispatchQueue.global().async {
            let group = DispatchGroup()
            var decOut = ""
            var ldrOut = ""
            var encOut = ""
            var snsOut = ""
            var sumOut = ""

            group.enter()
            DispatchQueue.global().async {
                decOut = self.runUser(root: root, script: "install/decoders.sh", args: ["check", "--json"])
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                ldrOut = self.runUser(root: root, script: "install/loader.sh", args: ["check", "--json"])
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                encOut = self.runUser(root: root, script: "install/encoder.sh", args: ["check", "--json"])
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                snsOut = self.runUser(root: root, script: "install/sensors.sh", args: ["check", "--json"])
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                sumOut = self.runUser(root: root, script: "install/check.sh", args: [])
                group.leave()
            }
            group.wait()

            let decoder = JSONDecoder()
            let dec = decOut.data(using: .utf8).flatMap { try? decoder.decode(DecodersCheck.self, from: $0) }
            let ldr = ldrOut.data(using: .utf8).flatMap { try? decoder.decode(LoaderCheck.self, from: $0) }
            let enc = encOut.data(using: .utf8).flatMap { try? decoder.decode(EncoderCheck.self, from: $0) }
            let sns = snsOut.data(using: .utf8).flatMap { try? decoder.decode(SensorsCheck.self, from: $0) }
            let (overall, left) = Self.parseCheckSummary(sumOut)

            DispatchQueue.main.async {
                self.decoders = dec
                self.loader = ldr
                self.encoder = enc
                self.sensors = sns
                self.overallLine = overall
                self.leftovers = left
                if dec == nil || ldr == nil || enc == nil || sns == nil {
                    self.phase = .failed("Could not read one or more check results from install/.")
                } else if !preserveOutput {
                    self.phase = .idle
                }
            }
        }
    }

    private static func parseCheckSummary(_ output: String) -> (String, [String]) {
        var overall = ""
        var leftovers: [String] = []
        var inLeftovers = false
        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("Overall:") {
                inLeftovers = false
                overall = line
            } else if line == "Leftovers:" {
                inLeftovers = true
            } else if inLeftovers && line.hasPrefix("  - ") {
                leftovers.append(String(line.dropFirst(4)))
            } else if inLeftovers && line.trimmingCharacters(in: .whitespaces).isEmpty {
                inLeftovers = false
            }
        }
        return (overall, leftovers)
    }

    func planInstall(withEncoder: Bool, withSensors: Bool) {
        guard let root = rootURL else {
            phase = .failed("GPU tools folder is not selected.")
            return
        }
        phase = .running("Building install plan")
        var args = ["plan"]
        if withEncoder { args.append("--with-encoder") }
        if withSensors { args.append("--with-sensors") }

        DispatchQueue.global().async {
            let (code, output) = self.runUserStatus(root: root, script: "install/install.sh", args: args)
            DispatchQueue.main.async {
                self.phase = .idle
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                self.planSheet = PlanResult(
                    output: trimmed.isEmpty ? "No output from install/install.sh plan (exit \(code))." : trimmed,
                    exitCode: code,
                    withEncoder: withEncoder,
                    withSensors: withSensors
                )
            }
        }
    }

    func runAction(title: String, script: String, args: [String], setsReboot: Bool, doneMessage: String) {
        guard let root = rootURL else {
            phase = .failed("GPU tools folder is not selected.")
            return
        }
        phase = .running(title)
        lastActionTitle = title
        lastOutput = ""
        let scriptPath = root.appendingPathComponent(script).path
        let argStr = args.map { Self.shq($0) }.joined(separator: " ")
        let inner = "/bin/zsh \(Self.shq(scriptPath))\(argStr.isEmpty ? "" : " " + argStr) 2>&1"

        DispatchQueue.global().async {
            let (ok, output) = self.runPrivileged(inner)
            DispatchQueue.main.async {
                self.lastOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if ok {
                    if setsReboot { self.needReboot = true }
                    self.phase = .done(doneMessage)
                } else {
                    self.phase = .failed("\(title) failed.")
                }
                self.recheck(preserveOutput: true)
            }
        }
    }

    func reboot() {
        let s = NSAppleScript(source: "tell application \"System Events\" to restart")
        var e: NSDictionary?
        s?.executeAndReturnError(&e)
    }

    private func runUser(root: URL, script: String, args: [String]) -> String {
        runUserStatus(root: root, script: script, args: args).1
    }

    private func runUserStatus(root: URL, script: String, args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let scriptPath = root.appendingPathComponent(script).path
        p.arguments = [scriptPath] + args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (1, error.localizedDescription) }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: d, encoding: .utf8) ?? "")
    }

    static func shq(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func asq(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func runPrivileged(_ inner: String) -> (Bool, String) {
        let wrapped = "\(inner); rc=$?; printf '\\n__DROGABOX_EXIT=%d\\n' \"$rc\"; exit 0"
        let src = "do shell script \"\(Self.asq(wrapped))\" with administrator privileges"
        let s = NSAppleScript(source: src)
        var err: NSDictionary?
        let r = s?.executeAndReturnError(&err)
        if let err = err {
            let m = (err[NSAppleScript.errorMessage] as? String)
                ?? "Authorization failed or the action was cancelled."
            return (false, m)
        }
        let raw = (r?.stringValue ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        var exitCode: Int? = nil
        if let last = lines.last, last.hasPrefix("__DROGABOX_EXIT=") {
            exitCode = Int(last.dropFirst("__DROGABOX_EXIT=".count))
            lines.removeLast()
            if lines.last?.isEmpty == true {
                lines.removeLast()
            }
        }
        let cleaned = lines.joined(separator: "\n")
        return (exitCode == 0, cleaned)
    }
}

// MARK: - UI helpers

struct StatusDot: View {
    let status: String
    var body: some View {
        let (name, color): (String, Color) = {
            switch status {
            case "ok":   return ("checkmark.circle.fill", .green)
            case "warn": return ("exclamationmark.triangle.fill", .orange)
            default:     return ("xmark.octagon.fill", .red)
            }
        }()
        Image(systemName: name)
            .foregroundStyle(color)
            .font(.system(size: 15, weight: .semibold))
            // The row it belongs to says the status in words (statusWord).
            .accessibilityHidden(true)
    }

    /// The status as VoiceOver reads it, in place of the symbol.
    static func statusWord(_ status: String) -> String {
        switch status {
        case "ok":   return "OK"
        case "warn": return "Warning"
        default:     return "Problem"
        }
    }
}

struct CheckRow: View {
    let c: CheckItem
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusDot(status: c.status).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.label).font(.system(size: 12, weight: .semibold))
                Text(c.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(c.label): \(StatusDot.statusWord(c.status))")
        .accessibilityValue(c.detail)
    }
}

struct ComponentSection<Content: View>: View {
    let title: String
    let subtitle: String
    let badgeStatus: String
    @Binding var isExpanded: Bool
    let installTitle: String
    let installTint: Color
    let installDisabled: Bool
    let removeDisabled: Bool
    let onInstall: () -> Void
    let onRemove: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    StatusDot(status: badgeStatus)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                // One element for VoiceOver: the part, its status in words, and whether
                // its checks are shown; activating it shows or hides them, like a click.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title), \(StatusDot.statusWord(badgeStatus)). \(subtitle)")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Button("Remove", role: .destructive, action: onRemove)
                        .controlSize(.small)
                        .disabled(removeDisabled)
                    Button(action: onInstall) {
                        Text(installTitle).frame(minWidth: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(installTint)
                    .controlSize(.small)
                    .disabled(installDisabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                Divider().padding(.leading, 14)
                VStack(spacing: 0) {
                    content()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject var engine = Engine()
    @State private var confirm: ConfirmAction? = nil
    @State private var expanded: Set<ComponentID> = [.decoders]
    @State private var withEncoder = false
    @State private var withSensors = false

    var busy: Bool {
        switch engine.phase {
        case .checking, .running: return true
        default: return false
        }
    }

    private func binding(for id: ComponentID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { open in
                if open { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if engine.rootURL == nil {
                missingRootView
            } else {
                mainScrollView
            }
            Divider()
            footer
            credit
        }
        // A minimum, not a fixed size: the window can grow when the text does.
        .frame(minWidth: 600, idealWidth: 600, minHeight: 740, idealHeight: 740)
        .onAppear {
            if engine.rootURL != nil {
                engine.recheck()
            }
        }
        .alert(item: $confirm) { action in alert(for: action) }
        .sheet(item: $engine.planSheet) { plan in
            PlanSheetView(plan: plan) {
                engine.planSheet = nil
            } onInstall: {
                engine.planSheet = nil
                var flags: [String] = []
                if plan.withEncoder { flags.append("--with-encoder") }
                if plan.withSensors { flags.append("--with-sensors") }
                engine.runAction(
                    title: "Install what this Mac needs",
                    script: "install/install.sh",
                    args: flags,
                    setsReboot: true,
                    doneMessage: "Installed. Reboot to apply."
                )
            }
        }
    }

    var missingRootView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("GPU tools folder not found")
                .font(.system(size: 15, weight: .semibold))
            Text("Choose the GPU tools folder (the one that contains install/) so the app can run checks and installers.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Choose Folder…") {
                engine.chooseRootFolder()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(24)
    }

    var mainScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !engine.overallLine.isEmpty && !engine.needReboot {
                    overallBanner
                }
                if !engine.leftovers.isEmpty {
                    banner(
                        icon: "tray.full.fill",
                        color: .orange,
                        text: "Leftovers found:\n" + engine.leftovers.map { "• " + $0 }.joined(separator: "\n")
                    )
                }

                if engine.decoders == nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking this Mac…").foregroundStyle(.secondary)
                    }
                    // Read as one: "Checking this Mac…", not a wordless "busy".
                    .accessibilityElement(children: .combine)
                    .padding(.vertical, 12)
                } else {
                    quickInstallCard
                    decodersSection
                    loaderSection
                    encoderSection
                    sensorsSection
                }

                phaseBanner
                if !engine.lastOutput.isEmpty {
                    outputBox
                }
            }
            .padding(16)
        }
    }

    // MARK: - Sections

    var quickInstallCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Guided install").font(.system(size: 13, weight: .semibold))
                    Text("Checks what this Mac needs and installs it in the right order.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    engine.planInstall(withEncoder: withEncoder, withSensors: withSensors)
                } label: {
                    Text("Install what this Mac needs").bold()
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
            }
            HStack(spacing: 16) {
                Toggle("Encoding fix", isOn: $withEncoder)
                    .toggleStyle(.checkbox)
                    .help("Full-speed HEVC/H.264 in the GPU's video engine")
                Toggle("GPU sensors", isOn: $withSensors)
                    .toggleStyle(.checkbox)
                    .help("Temperatures, clocks and fan speed in RyzenStatus")
            }
            .font(.system(size: 12))
            .disabled(busy)
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder var decodersSection: some View {
        if let dec = engine.decoders {
            let status: String = {
                if dec.repairable { return "warn" }
                if dec.installed == "current" { return "ok" }
                if dec.canInstall { return dec.checks.contains(where: { $0.status == "warn" }) ? "warn" : "ok" }
                return dec.overridable ? "warn" : "fail"
            }()
            let subtitle: String = {
                if dec.repairable { return "Apple's system video plug-ins need repair" }
                switch dec.installed {
                case "current":  return "Installed and up to date"
                case "outdated": return "Outdated version installed — click Update"
                default:
                    if dec.canInstall { return "Ready to install (requires reboot)" }
                    if dec.overridable { return "Unvalidated macOS build" }
                    return "Not ready — expand for details"
                }
            }()
            let installTitle: String = {
                if dec.repairable { return "Repair" }
                if dec.overridable && !dec.canInstall { return "Install anyway" }
                switch dec.installed {
                case "current":  return "Installed"
                case "outdated": return "Update"
                default:         return "Install"
                }
            }()
            let installTint: Color = (dec.repairable || (dec.overridable && !dec.canInstall)) ? .orange : .accentColor
            let installDisabled = busy || (!dec.repairable && (dec.installed == "current" || (!dec.canInstall && !dec.overridable)))

            ComponentSection(
                title: "Decoder plug-ins (AV1 + VP9)",
                subtitle: subtitle,
                badgeStatus: status,
                isExpanded: binding(for: .decoders),
                installTitle: installTitle,
                installTint: installTint,
                installDisabled: installDisabled,
                removeDisabled: busy || dec.installed == "none",
                onInstall: {
                    if dec.repairable {
                        confirm = .repairDecoders
                    } else {
                        confirm = .installDecoders(force: dec.overridable && !dec.canInstall)
                    }
                },
                onRemove: { confirm = .removeDecoders }
            ) {
                checkRows(dec.checks)
            }
        }
    }

    @ViewBuilder var loaderSection: some View {
        if let ldr = engine.loader {
            let needed = ldr.checks.first(where: { $0.id == "loader-need" })?.detail.hasPrefix("yes:") ?? true
            let onEfi = ldr.efis.contains(where: { $0.kext != "none" && $0.kext != "unknown" })
            let loaded = ldr.running.hasPrefix("loaded")
            // The EFI copy is this build's and it runs: nothing to update.
            let upToDate = ldr.efis.contains(where: { $0.kext == "current" }) && ldr.result.hasPrefix("working:")
            let status: String = {
                if !needed { return "ok" }
                if ldr.result.hasPrefix("working:") || ldr.result.hasPrefix("installed") { return "ok" }
                return ldr.canInstall ? "warn" : "fail"
            }()
            let subtitle: String = {
                if !needed { return "Not needed on this Mac (\(ldr.checks.first(where: { $0.id == "loader-need" })?.detail ?? "other loader active"))" }
                return ldr.result
            }()

            ComponentSection(
                title: "Loader kext (VCNVTLoader)",
                subtitle: subtitle,
                badgeStatus: status,
                isExpanded: binding(for: .loader),
                installTitle: upToDate ? "Installed" : (onEfi ? "Update" : "Install"),
                installTint: .accentColor,
                installDisabled: busy || !ldr.canInstall || upToDate,
                removeDisabled: busy || (!onEfi && !loaded),
                onInstall: { confirm = .installLoader },
                onRemove: { confirm = .removeLoader }
            ) {
                checkRows(ldr.checks)
            }
        }
    }

    @ViewBuilder var encoderSection: some View {
        if let enc = engine.encoder {
            let onEfi = enc.efis.contains(where: { $0.kext != "none" && $0.kext != "unknown" })
            let installedAny = enc.installed != "none" || enc.service == "running" || enc.kext.hasPrefix("loaded") || onEfi
            let status: String = {
                if enc.installed == "current" && enc.service == "running" { return "ok" }
                if enc.canInstall { return enc.checks.contains(where: { $0.status == "warn" }) ? "warn" : "ok" }
                return "fail"
            }()
            let subtitle = "Optional — Service: \(enc.service) · Kext: \(enc.kext)"
            let installTitle = enc.installed == "outdated" ? "Update" : (enc.installed == "current" ? "Reinstall" : "Install")

            ComponentSection(
                title: "Encoding fix (VCNEncodeFix)",
                subtitle: subtitle,
                badgeStatus: status,
                isExpanded: binding(for: .encoder),
                installTitle: installTitle,
                installTint: .accentColor,
                installDisabled: busy || !enc.canInstall,
                removeDisabled: busy || !installedAny,
                onInstall: { confirm = .installEncoder },
                onRemove: { confirm = .removeEncoder }
            ) {
                checkRows(enc.checks)
            }
        }
    }

    @ViewBuilder var sensorsSection: some View {
        if let sns = engine.sensors {
            let onEfi = sns.efis.contains(where: { $0.kext != "none" && $0.kext != "unknown" })
            let loaded = sns.running.hasPrefix("loaded")
            let upToDate = sns.efis.contains(where: { $0.kext == "current" }) && sns.result.hasPrefix("working:")
            let status: String = {
                if sns.result.hasPrefix("working:") || sns.result.hasPrefix("installed") { return "ok" }
                return sns.canInstall ? "warn" : "fail"
            }()

            ComponentSection(
                title: "GPU sensors (GPUSensors)",
                subtitle: "Optional — " + sns.result,
                badgeStatus: status,
                isExpanded: binding(for: .sensors),
                installTitle: upToDate ? "Installed" : (onEfi ? "Update" : "Install"),
                installTint: .accentColor,
                installDisabled: busy || !sns.canInstall || upToDate,
                removeDisabled: busy || (!onEfi && !loaded),
                onInstall: { confirm = .installSensors },
                onRemove: { confirm = .removeSensors }
            ) {
                checkRows(sns.checks)
            }
        }
    }

    @ViewBuilder
    private func checkRows(_ checks: [CheckItem]) -> some View {
        ForEach(checks) { c in
            CheckRow(c: c)
            if c.id != checks.last?.id {
                Divider().padding(.leading, 30)
            }
        }
    }

    // MARK: - Header, Banners, Output, Footer

    var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("RyzenStatus GPU").font(.system(size: 18, weight: .bold))
                Text("AMD RX 6000 decoders, encoding fix & GPU sensors")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(engine.decoders?.macos ?? "detecting macOS…")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            // A folder is chosen only in a development build; the app from the DMG carries
            // its parts inside.
            if engine.rootURL != nil && !engine.rootInBundle {
                Button("Change Folder…") {
                    engine.chooseRootFolder()
                }
                .controlSize(.small)
                .disabled(busy)
            }
        }
        .padding(18)
    }

    @ViewBuilder var overallBanner: some View {
        let lower = engine.overallLine.lowercased()
        let (icon, color): (String, Color) = {
            if lower.contains("overall: working") { return ("checkmark.seal.fill", .green) }
            if lower.contains("overall: ready") || lower.contains("overall: installed") { return ("info.circle.fill", .blue) }
            if lower.contains("needs the loader") { return ("exclamationmark.triangle.fill", .orange) }
            return ("xmark.octagon.fill", .red)
        }()
        banner(icon: icon, color: color, text: engine.overallLine)
    }

    @ViewBuilder var phaseBanner: some View {
        switch engine.phase {
        case .running(let title):
            banner(icon: "gearshape.fill", color: .blue, text: "\(title)… enter your administrator password when asked.")
        case .done(let msg):
            banner(icon: "checkmark.seal.fill", color: .green, text: msg)
        case .failed(let msg):
            banner(icon: "exclamationmark.triangle.fill", color: .red, text: msg)
        default:
            EmptyView()
        }
    }

    func banner(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    var outputBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(engine.lastActionTitle.isEmpty ? "Script output" : "\(engine.lastActionTitle) output")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear log") {
                    engine.lastOutput = ""
                    engine.lastActionTitle = ""
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
            ScrollView {
                Text(engine.lastOutput)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(maxHeight: 160)
            .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .padding(.top, 4)
    }

    var footer: some View {
        HStack(spacing: 12) {
            Button {
                engine.recheck()
            } label: {
                Label("Re-check", systemImage: "arrow.clockwise")
            }
            .disabled(busy || engine.rootURL == nil)

            Button("Remove all", role: .destructive) {
                confirm = .removeAll
            }
            .disabled(busy || engine.rootURL == nil)

            Spacer()

            if engine.needReboot {
                Button { confirm = .reboot } label: {
                    Text("Reboot now").bold()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(14)
    }

    var credit: some View {
        HStack(spacing: 4) {
            Text("Made by").foregroundStyle(.secondary)
            Link("DrogaBox", destination: URL(string: "https://github.com/DrogaBox")!)
            Text("&").foregroundStyle(.secondary)
            Link("Izzy", destination: URL(string: "https://github.com/wh0ami7")!)
        }
        .font(.system(size: 11))
        .padding(.bottom, 10)
    }

    // MARK: - Alerts

    func alert(for action: ConfirmAction) -> Alert {
        switch action {
        case .installDecoders(let force):
            if force {
                return Alert(
                    title: Text("This macOS build is NOT validated"),
                    message: Text("The GPU driver of this macOS version has not been checked. Installing can freeze the screen or hang the GPU while playing video."),
                    primaryButton: .default(Text("I understand, install")) {
                        engine.runAction(
                            title: "Install decoder plug-ins (--force)",
                            script: "install/decoders.sh",
                            args: ["install", "--force"],
                            setsReboot: true,
                            doneMessage: "Decoder plug-ins installed. Reboot to load them."
                        )
                    },
                    secondaryButton: .cancel()
                )
            } else {
                return Alert(
                    title: Text("Install the decoder plug-ins?"),
                    message: Text("This copies the AV1 and VP9 plug-ins into the system volume and creates a new boot snapshot. You must reboot afterwards."),
                    primaryButton: .default(Text("Install")) {
                        engine.runAction(
                            title: "Install decoder plug-ins",
                            script: "install/decoders.sh",
                            args: ["install"],
                            setsReboot: true,
                            doneMessage: "Decoder plug-ins installed. Reboot to load them."
                        )
                    },
                    secondaryButton: .cancel()
                )
            }
        case .repairDecoders:
            return Alert(
                title: Text("Repair system video plug-ins?"),
                message: Text("Missing Apple plug-ins are copied back from Apple's original system snapshot, and the decoders are installed if this build is validated. You must reboot afterwards."),
                primaryButton: .default(Text("Repair")) {
                    engine.runAction(
                        title: "Repair decoder plug-ins",
                        script: "install/decoders.sh",
                        args: ["repair"],
                        setsReboot: true,
                        doneMessage: "Repaired. Reboot to finish."
                    )
                },
                secondaryButton: .cancel()
            )
        case .removeDecoders:
            return Alert(
                title: Text("Remove the decoder plug-ins?"),
                message: Text("Removes both decoder plug-ins from the system volume and creates a new boot snapshot. Reboot to apply."),
                primaryButton: .destructive(Text("Remove")) {
                    engine.runAction(
                        title: "Remove decoder plug-ins",
                        script: "install/decoders.sh",
                        args: ["uninstall"],
                        setsReboot: true,
                        doneMessage: "Decoder plug-ins removed. Reboot to apply."
                    )
                },
                secondaryButton: .cancel()
            )
        case .installLoader:
            return Alert(
                title: Text("Install VCNVTLoader.kext?"),
                message: Text("Copies VCNVTLoader.kext to your OpenCore EFI and adds its entry to config.plist (with a backup). Reboot to load it."),
                primaryButton: .default(Text("Install")) {
                    engine.runAction(
                        title: "Install loader kext",
                        script: "install/loader.sh",
                        args: ["install"],
                        setsReboot: true,
                        doneMessage: "Loader kext installed on EFI. Reboot to load it."
                    )
                },
                secondaryButton: .cancel()
            )
        case .removeLoader:
            return Alert(
                title: Text("Remove VCNVTLoader.kext?"),
                message: Text("Removes VCNVTLoader.kext and its config.plist entry from your OpenCore EFI. Reboot to apply."),
                primaryButton: .destructive(Text("Remove")) {
                    engine.runAction(
                        title: "Remove loader kext",
                        script: "install/loader.sh",
                        args: ["uninstall"],
                        setsReboot: true,
                        doneMessage: "Loader kext removed from EFI. Reboot to apply."
                    )
                },
                secondaryButton: .cancel()
            )
        case .installEncoder:
            return Alert(
                title: Text("Install the encoding fix?"),
                message: Text("Installs the LaunchDaemon service (works immediately) and VCNEncodeFloor.kext on your OpenCore EFI (requires reboot)."),
                primaryButton: .default(Text("Install")) {
                    engine.runAction(
                        title: "Install encoding fix",
                        script: "install/encoder.sh",
                        args: ["install", "--efi", "auto"],
                        setsReboot: true,
                        doneMessage: "Encoding fix installed. Reboot to load the kext."
                    )
                },
                secondaryButton: .cancel()
            )
        case .removeEncoder:
            return Alert(
                title: Text("Remove the encoding fix?"),
                message: Text("Removes the LaunchDaemon service and VCNEncodeFloor.kext from your OpenCore EFI. Reboot to unload the kext."),
                primaryButton: .destructive(Text("Remove")) {
                    engine.runAction(
                        title: "Remove encoding fix",
                        script: "install/encoder.sh",
                        args: ["uninstall", "--efi", "auto"],
                        setsReboot: true,
                        doneMessage: "Encoding fix removed. Reboot to finish."
                    )
                },
                secondaryButton: .cancel()
            )
        case .installSensors:
            return Alert(
                title: Text("Install GPUSensors.kext?"),
                message: Text("Copies GPUSensors.kext to your OpenCore EFI and adds its entry to config.plist (with a backup). Reboot to load it."),
                primaryButton: .default(Text("Install")) {
                    engine.runAction(
                        title: "Install GPU sensors",
                        script: "install/sensors.sh",
                        args: ["install"],
                        setsReboot: true,
                        doneMessage: "GPU sensors kext installed on EFI. Reboot to load it."
                    )
                },
                secondaryButton: .cancel()
            )
        case .removeSensors:
            return Alert(
                title: Text("Remove GPUSensors.kext?"),
                message: Text("Removes GPUSensors.kext and its config.plist entry from your OpenCore EFI. Reboot to apply."),
                primaryButton: .destructive(Text("Remove")) {
                    engine.runAction(
                        title: "Remove GPU sensors",
                        script: "install/sensors.sh",
                        args: ["uninstall"],
                        setsReboot: true,
                        doneMessage: "GPU sensors kext removed from EFI. Reboot to apply."
                    )
                },
                secondaryButton: .cancel()
            )
        case .removeAll:
            return Alert(
                title: Text("Remove all GPU components?"),
                message: Text("Runs install/undo.sh --yes to remove every installed kext, the encoding fix service, and the decoder plug-ins. Reboot afterwards. Kept: the log /var/log/vcnencodefix.log and the config.plist backups next to config.plist on the EFI."),
                primaryButton: .destructive(Text("Remove all")) {
                    engine.runAction(
                        title: "Remove all components",
                        script: "install/undo.sh",
                        args: ["--yes"],
                        setsReboot: true,
                        doneMessage: "All installed components removed. Reboot to finish."
                    )
                },
                secondaryButton: .cancel()
            )
        case .reboot:
            return Alert(
                title: Text("Reboot now?"),
                message: Text("Save your work first. Other apps will be asked to quit."),
                primaryButton: .default(Text("Reboot")) { engine.reboot() },
                secondaryButton: .cancel(Text("Later"))
            )
        }
    }
}

// MARK: - Plan sheet

struct PlanSheetView: View {
    let plan: PlanResult
    let onCancel: () -> Void
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: plan.exitCode == 0 ? "checklist" : "xmark.octagon.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(plan.exitCode == 0 ? Color.accentColor : Color.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.nothingToDo ? "Nothing to install" : plan.exitCode == 0 ? "Install plan" : "Cannot install")
                        .font(.system(size: 15, weight: .bold))
                    Text(plan.nothingToDo
                         ? "Everything you asked for is already in place on this Mac."
                         : plan.exitCode == 0
                         ? "Review what install/install.sh will do, then click Install."
                         : "install/install.sh plan exited with status \(plan.exitCode). Nothing can be installed.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ScrollView {
                Text(plan.output)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(minHeight: 200, maxHeight: 320)
            .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )

            HStack {
                Spacer()
                Button(plan.canInstall ? "Cancel" : "Close", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                if plan.canInstall {
                    Button("Install", action: onInstall)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(18)
        .frame(width: 520)
    }
}

// MARK: - App

@main
enum Launcher {
    static func main() {
        // --print-payload: says where the parts inside this app are and exits, without
        // opening a window (Tools/make-dmg.sh runs it on the app it puts in the DMG).
        // Exit status 0 when Contents/Resources/GPU holds them, 1 when it does not.
        if CommandLine.arguments.dropFirst().contains("--print-payload") {
            if let root = Engine.bundledRoot() {
                print("bundled: \(root.path)")
                exit(0)
            }
            print("no parts inside this app: Contents/Resources/\(Engine.bundledFolderName)/install is missing")
            exit(1)
        }
        RyzenStatusGPUApp.main()
    }
}

struct RyzenStatusGPUApp: App {
    init() { NSApplication.shared.setActivationPolicy(.regular) }
    var body: some Scene {
        Window("RyzenStatus GPU", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
