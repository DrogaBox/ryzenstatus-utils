// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CryptoKit
import Foundation

/// The DMG carries the "RyzenStatus GPU" installer with the GPU parts inside it. Three
/// promises are checked here, on the files in the repository:
/// - the installer stays out of the top of the DMG (old updaters copy the first .app
///   they find there), and the seeded window layout places every item at the top;
/// - the committed parts (ReleaseAssets/GPU-Package.zip) are the pinned ones: the hash of
///   their SHA256SUMS is the one in make-dmg.sh, every file matches it, and the scripts in
///   it are the repository's;
/// - the installer looks for its parts inside itself first, and the parts are where and
///   what it looks for.
enum GPUInstallerDMGTests {
    static func run(_ suite: TestSuite) {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let script = text(root, "Tools/make-dmg.sh")
        suite.expect(!script.isEmpty, "Tools/make-dmg.sh is readable from the repository root")
        layout(suite, root, script)
        let parts = unpackParts(root)
        defer { if let parts { try? FileManager.default.removeItem(at: parts.deletingLastPathComponent()) } }
        suite.expect(parts != nil, "ReleaseAssets/GPU-Package.zip unpacks to one GPU/ folder")
        if let parts {
            pinned(suite, root, script, parts)
            installerFinds(suite, root, script, parts)
        }
    }

    // MARK: The DMG layout

    private static func layout(_ suite: TestSuite, _ root: URL, _ script: String) {
        let folder = first("GPU_FOLDER=\"([^\"]+)\"", in: script)
        suite.expect(folder == "GPU RX 6000", "the GPU folder of the DMG is \"GPU RX 6000\" (got \(folder ?? "none"))")
        // Every .app the script puts in the staging folder: only RyzenStatus.app at the top,
        // the installer one level down.
        let staged = all("\"\\$STAGING/([^\"]*\\.app)\"", in: script)
        let atTop = Set(staged.filter { !$0.contains("/") })
        suite.expect(atTop == ["$APP_NAME.app"] && staged.contains("$GPU_FOLDER/$GPU_APP_NAME.app"),
                     "the only .app staged at the top of the DMG is RyzenStatus.app, the installer is in the folder (got \(staged))")
        suite.expect(script.contains("GPU_APP=\"$STAGING/$GPU_FOLDER/$GPU_APP_NAME.app\"")
                         && script.contains("ditto \"$GPU_APP_BUILD\" \"$GPU_APP\""),
                     "the installer is staged inside the GPU folder")
        suite.expect(script.contains("find . -maxdepth 1 -name '*.app'")
                         && script.contains("[[ \"$ROOT_APPS\" == \"./$APP_NAME.app \" ]]"),
                     "the finished image is refused unless RyzenStatus.app is its only top-level app")

        // The AppleScript positions, the seeded .DS_Store and the background agree.
        var applescript: [String: [Int]] = [:]
        for match in groups("set position of item \"([^\"]+)\" of container window to \\{(\\d+), (\\d+)\\}", in: script) {
            let name = match[0].replacingOccurrences(of: "$APP_NAME", with: "RyzenStatus")
                .replacingOccurrences(of: "$GPU_FOLDER", with: folder ?? "")
            applescript[name] = [Int(match[1]) ?? -1, Int(match[2]) ?? -1]
        }
        let topItems: Set<String> = ["RyzenStatus.app", "Applications", "Kexts", "README.txt", "GPU RX 6000"]
        suite.expect(Set(applescript.keys) == topItems,
                     "the AppleScript places every item at the top of the DMG (got \(applescript.keys.sorted()))")
        let store = (try? Data(contentsOf: root.appendingPathComponent("Tools/dmg-layout.DS_Store")))
            .flatMap(DSStore.records)
        suite.expect(store != nil, "Tools/dmg-layout.DS_Store can be read")
        if let store {
            var seeded: [String: [Int]] = [:]
            var bounds = ""
            for record in store {
                if record.kind == "Iloc", record.value.count >= 8 {
                    seeded[record.name] = [Int(record.value.uint32(at: 0)), Int(record.value.uint32(at: 4))]
                }
                if record.name == ".", record.kind == "bwsp",
                   let plist = try? PropertyListSerialization.propertyList(from: record.value, format: nil),
                   let dict = plist as? [String: Any] {
                    bounds = dict["WindowBounds"] as? String ?? ""
                }
            }
            suite.expect(seeded == applescript,
                         "the seeded .DS_Store holds the AppleScript's positions (\(seeded) vs \(applescript))")
            let size = groups("\\{\\{-?\\d+, -?\\d+\\}, \\{(\\d+), (\\d+)\\}\\}", in: bounds).first ?? []
            let box = groups("set the bounds of container window to \\{(\\d+), (\\d+), (\\d+), (\\d+)\\}", in: script)
                .first.map { $0.compactMap { Int($0) } } ?? []
            let background = text(root, "Tools/MakeDMGBackground.swift")
            let backgroundSize = groups("widthPt: CGFloat = (\\d+), heightPt: CGFloat = (\\d+)", in: background).first ?? []
            suite.expect(box.count == 4 && size == ["\(box[2] - box[0])", "\(box[3] - box[1])"] && size == backgroundSize,
                         "window size: .DS_Store \(size), AppleScript \(box), background \(backgroundSize) agree")
        }
        let readme = text(root, "Tools/dmg-README.txt")
        suite.expect(readme.components(separatedBy: "GPU RX 6000").count == 3
                         && readme.contains("Kexts/GPU-NOTICE.md") && readme.contains("Arrastra RyzenStatus"),
                     "the DMG README, in English and Spanish, says where the installer is and where the licenses are")
        suite.expect(script.contains("cp Tools/dmg-README.txt \"$STAGING/README.txt\""),
                     "make-dmg.sh puts the README at the top of the DMG")
    }

    // MARK: The committed parts are the pinned ones

    private static func pinned(_ suite: TestSuite, _ root: URL, _ script: String, _ parts: URL) {
        let pin = first("GPU_PAYLOAD_SUMS_SHA256=\"([0-9a-f]{64})\"", in: script)
        suite.expect(pin != nil, "make-dmg.sh pins the SHA-256 of the parts' SHA256SUMS")
        guard let sums = try? Data(contentsOf: parts.appendingPathComponent("SHA256SUMS")) else {
            suite.expect(false, "the parts hold SHA256SUMS")
            return
        }
        suite.expect(hex(sums) == pin, "the parts' SHA256SUMS is the pinned one (\(hex(sums)) vs \(pin ?? "none"))")

        var listed: [String: String] = [:]
        for line in String(decoding: sums, as: UTF8.self).split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard fields.count == 2 else { continue }
            listed[String(fields[1]).trimmingCharacters(in: .whitespaces)] = String(fields[0])
        }
        let present = regularFiles(under: parts).subtracting(["./SHA256SUMS"])
        suite.expect(Set(listed.keys) == present && present.count > 40,
                     "SHA256SUMS lists exactly the \(present.count) files of the parts")
        let wrong = listed.filter { path, hash in
            (try? Data(contentsOf: parts.appendingPathComponent(path))).map(hex) != hash
        }.keys.sorted()
        suite.expect(wrong.isEmpty, "every file of the parts matches SHA256SUMS: \(wrong)")
        suite.expect(links(under: parts).isEmpty, "the parts hold no links")

        // The scripts and lists in the parts are the repository's: a change to them needs a
        // new zip (Tools/build-gpu-assets.sh), or the DMG would ship the old ones.
        let gpu = root.appendingPathComponent("GPU")
        var functional = ["tools/driver/kcfunc.py", "encode/VERSION", "install/validated-builds.json"]
        let install = (try? FileManager.default.contentsOfDirectory(atPath: gpu.appendingPathComponent("install").path)) ?? []
        functional += install.filter { ($0.hasSuffix(".sh") || $0.hasSuffix(".zsh")) && $0 != "check_lists.sh" }
            .map { "install/\($0)" }
        let stale = functional.filter { path in
            let repo = try? Data(contentsOf: gpu.appendingPathComponent(path))
            return repo == nil || repo != (try? Data(contentsOf: parts.appendingPathComponent(path)))
        }
        suite.expect(functional.count > 10 && stale.isEmpty,
                     "the parts carry the repository's scripts and lists; rebuild the zip for: \(stale)")
        suite.expect(!FileManager.default.fileExists(atPath: parts.appendingPathComponent("install/check_lists.sh").path),
                     "the parts leave out check_lists.sh, which needs the decoders' sources")
        for tool in ["sensors/build/gpucontrol", "sensors/build/gpusensors", "decode/build/kextentry"] {
            suite.expect(FileManager.default.isExecutableFile(atPath: parts.appendingPathComponent(tool).path),
                         "the parts carry \(tool), executable")
        }
    }

    // MARK: The installer finds the parts inside itself

    private static func installerFinds(_ suite: TestSuite, _ root: URL, _ script: String, _ parts: URL) {
        let main = text(root, "GPU/installer/main.swift")
        suite.expect(main.contains("static let bundledFolderName = \"GPU\"")
                         && main.contains("Bundle.main.resourceURL")
                         && main.contains("resources.appendingPathComponent(bundledFolderName, isDirectory: true)"),
                     "the installer looks for its parts in Contents/Resources/GPU")
        if let initStart = main.range(of: "    init() {"),
           let bundled = main.range(of: "Self.bundledRoot()", range: initStart.upperBound..<main.endIndex),
           let near = main.range(of: "Self.findRootNearBundle()", range: initStart.upperBound..<main.endIndex) {
            suite.expect(bundled.lowerBound < near.lowerBound,
                         "the installer takes the parts inside itself before any folder near it")
        } else {
            suite.expect(false, "the installer's Engine.init() looks inside the app and then near it")
        }
        suite.expect(main.contains("if engine.rootURL != nil && !engine.rootInBundle {"),
                     "the app from the DMG offers no folder choice")
        suite.expect(main.contains("self.suggestion = OptionalSuggestion(encoder: enc, sensors: sns)")
                         && main.contains(".onReceive(engine.$suggestion)")
                         && main.contains("self.sensors = Self.isOlder(running, than: sns.version)"),
                     "the guided install ticks an optional part that is installed in an older version")
        appWording(suite, root)
        suite.expect(script.contains("ditto \"$GPU_PARTS\" \"$GPU_APP/Contents/Resources/GPU\""),
                     "make-dmg.sh puts the parts in Contents/Resources/GPU of the installer it ships")
        suite.expect(script.components(separatedBy: "RyzenStatusGPUInstaller\" --print-payload").count == 3,
                     "make-dmg.sh asks the installer, staged and in the finished image, where its parts are")
        // What Engine.isValidRoot asks of the folder.
        let fm = FileManager.default
        suite.expect(fm.isExecutableFile(atPath: parts.appendingPathComponent("install/decoders.sh").path)
                         && fm.fileExists(atPath: parts.appendingPathComponent("install/check.sh").path),
                     "the parts are a folder the installer accepts: install/decoders.sh runs, install/check.sh is there")

        let plistData = (try? Data(contentsOf: root.appendingPathComponent("GPU/installer/Info.plist"))) ?? Data()
        let plist = (try? PropertyListSerialization.propertyList(from: plistData, format: nil)) as? [String: Any] ?? [:]
        let build = text(root, "GPU/installer/build.sh")
        suite.expect(plist["CFBundleName"] as? String == "RyzenStatus GPU"
                         && plist["CFBundleDisplayName"] as? String == "RyzenStatus GPU"
                         && main.contains("Window(\"RyzenStatus GPU\", id: \"main\")"),
                     "the installer is called RyzenStatus GPU")
        suite.expect(plist["CFBundleExecutable"] as? String == "RyzenStatusGPUInstaller"
                         && build.contains("-o \"$APP/Contents/MacOS/RyzenStatusGPUInstaller\"")
                         && build.contains("APP=\"build/RyzenStatus GPU.app\""),
                     "the installer's executable and bundle name match its build script")
        suite.expect(plist["LSMinimumSystemVersion"] as? String == "14.0" && build.contains("-target x86_64-apple-macos14.0"),
                     "the installer runs on macOS 14 and newer, in Info.plist and in the build")
        suite.expect(plist["CFBundleIdentifier"] as? String == "com.ryzenstatus.gpu-installer",
                     "the installer's bundle id is com.ryzenstatus.gpu-installer")
        toolsOffered(suite, root, main)
        scriptCalls(suite, main, parts)
        windowStates(suite, main, parts)
    }

    /// Every script the installer runs, with every literal argument it passes, is in the
    /// parts it ships, and the script takes that argument: a renamed script or command
    /// fails here, not after the administrator password. Read from main.swift's
    /// `script: "…", args: […]` pairs and from the guided install's flags.
    private static func scriptCalls(_ suite: TestSuite, _ main: String, _ parts: URL) {
        let calls = groups("script: \"([^\"]+)\",\\s*args: \\[([^\\]]*)\\]", in: main)
        suite.expect(calls.count >= 14, "main.swift's script calls are found (\(calls.count))")
        let scripts = Set(all("script: \"([^\"]+)\"", in: main))
        for script in scripts.sorted() {
            suite.expect(FileManager.default.fileExists(atPath: parts.appendingPathComponent(script).path),
                         "the parts carry \(script), which the installer runs")
        }
        var missing: [String] = []
        for call in calls {
            let source = (try? String(contentsOf: parts.appendingPathComponent(call[0]), encoding: .utf8)) ?? ""
            let args = all("\"([^\"]*)\"", in: call[1])
            for (i, arg) in args.enumerated() where !takes(source, arg, after: i > 0 ? args[i - 1] : nil) {
                missing.append("\(call[0]) \(arg)")
            }
        }
        // The guided install: install.sh plan, and the two flags the boxes add.
        let install = (try? String(contentsOf: parts.appendingPathComponent("install/install.sh"), encoding: .utf8)) ?? ""
        for flag in ["plan"] + Set(all("append\\(\"(--with-[a-z]+)\"\\)", in: main)).sorted()
        where !takes(install, flag, after: nil) {
            missing.append("install/install.sh \(flag)")
        }
        suite.expect(main.contains("var args = [\"plan\"]") && main.components(separatedBy: "append(\"--with-").count == 5,
                     "the guided install passes plan, --with-encoder and --with-sensors to install/install.sh")
        suite.expect(missing.isEmpty, "every argument the installer passes is one its script takes: \(missing)")
    }

    /// True when a zsh script takes an argument: a case label for it ("arg)", "a|arg)"), or,
    /// for the value of an option (--efi auto), a comparison with it.
    private static func takes(_ source: String, _ arg: String, after previous: String?) -> Bool {
        let label = NSRegularExpression.escapedPattern(for: arg)
        if !groups("(?m)^\\s*(?:[A-Za-z0-9_-]+\\|)*(\(label))(?:\\|[A-Za-z0-9_-]+)*\\)", in: source).isEmpty {
            return true
        }
        return previous?.hasPrefix("--") == true && source.contains("== \(arg) ]]")
    }

    /// What the window says after an action: a cancelled password prompt is not a failure,
    /// a restart that does not happen says why, a check is one pass of check.sh, and the GPU
    /// sensors' commands can be removed without the kext.
    private static func windowStates(_ suite: TestSuite, _ main: String, _ parts: URL) {
        suite.expect(main.contains("== -128 {\n                return .cancelled")
                         && main.contains("case .cancelled:\n                    // The password prompt was cancelled")
                         && main.contains("case .cancelled(let msg):\n            banner(icon: \"info.circle\", color: .secondary"),
                     "a cancelled password prompt shows as cancelled, in a neutral banner, not as failed")
        suite.expect(main.contains("s.executeAndReturnError(&e)\n        guard let e else { return }")
                         && main.contains("case -1743:"),
                     "Reboot now says why when the restart does not happen")
        suite.expect(main.contains("args: [\"--json-dir\", dir.path]")
                         && !main.contains("args: [\"check\", \"--json\"]"),
                     "a check is one pass of check.sh, which writes the parts' JSON answers")
        suite.expect(main.contains("onRemove: { confirm = kextThere ? .removeSensors : .removeSensorsTools }")
                         && main.contains("removeDisabled: busy || (!kextThere && !toolsInstalled)"),
                     "the GPU sensors' Remove takes gpucontrol and gpusensors when the kext is gone")
        let undo = (try? String(contentsOf: parts.appendingPathComponent("install/undo.sh"), encoding: .utf8)) ?? ""
        suite.expect(undo.contains("elif [[ $tools == yes ]]; then steps+=(\"install/sensors.sh uninstall-tools\"); fi"),
                     "Remove all takes gpucontrol and gpusensors off when the sensors kext is gone")
    }

    /// gpucontrol and gpusensors go to /usr/local/bin even when the sensors kext is current:
    /// sensors.sh says so in its check (tools, toolsOnly), the sensors row then offers just
    /// them, the guided install ticks the sensors for them, and install.sh copies only them.
    private static func toolsOffered(_ suite: TestSuite, _ root: URL, _ main: String) {
        let sensors = text(root, "GPU/install/sensors.sh")
        let install = text(root, "GPU/install/install.sh")
        suite.expect(sensors.contains("\\\"tools\\\":\\\"$TOOLS_STATE\\\",\\\"toolsOnly\\\":"),
                     "sensors.sh check --json says where gpucontrol and gpusensors stand (tools, toolsOnly)")
        suite.expect(main.contains("let toolsOnly: Bool?")
                         && main.contains("onInstall: { confirm = toolsOnly ? .installSensorsTools : .installSensors }")
                         && main.contains("installDisabled: busy || (!toolsOnly && (!sns.canInstall || upToDate))")
                         && main.contains("args: [\"tools\"]"),
                     "the GPU sensors row offers Install tools / Update tools when only the commands need copying")
        suite.expect(main.contains("if let sns = sensors, sns.toolsOnly == true {"),
                     "the guided install ticks GPU sensors when only the commands need copying")
        suite.expect(install.contains("tools)    /bin/zsh \"$SELF_DIR/sensors.sh\" tools ;;")
                         && install.contains("for part in loader decoders encoder sensors jpeg tools; do"),
                     "install.sh copies just the commands, last, when the sensors kext is in place")
    }

    /// The scripts tell the app's copy from a checkout by where common.zsh sits: inside
    /// "<name>.app/Contents/Resources/GPU" their messages name the app's buttons.
    private static func appWording(_ suite: TestSuite, _ root: URL) {
        let common = root.appendingPathComponent("GPU/install/common.zsh")
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("gpu-wording-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        var seen: [String: String] = [:]
        for (label, folder) in [("app", "RyzenStatus GPU.app/Contents/Resources/GPU"), ("checkout", "GPU")] {
            let install = base.appendingPathComponent(folder).appendingPathComponent("install", isDirectory: true)
            try? FileManager.default.createDirectory(at: install, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: common, to: install.appendingPathComponent("common.zsh"))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-f", "-c", "source \"$1\"; print -r -- \"$IN_APP $(pick dev app)\"", "zsh",
                                 install.appendingPathComponent("common.zsh").path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { continue }
            let out = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            seen[label] = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        suite.expect(seen["app"] == "1 app" && seen["checkout"] == "0 dev",
                     "inside the app the scripts use the app's words, in a checkout the commands (\(seen))")
    }

    // MARK: Helpers

    /// Unpacks the committed zip into a new temporary folder; returns its GPU/ folder.
    private static func unpackParts(_ root: URL) -> URL? {
        let zip = root.appendingPathComponent("ReleaseAssets/GPU-Package.zip")
        // Resolved (/var is a link to /private/var), so the paths found under it keep its prefix.
        let dest = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("gpu-parts-\(UUID().uuidString)", isDirectory: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, dest.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        let top = (try? FileManager.default.contentsOfDirectory(atPath: dest.path)) ?? []
        guard process.terminationStatus == 0, top == ["GPU"] else {
            try? FileManager.default.removeItem(at: dest)
            return nil
        }
        return dest.appendingPathComponent("GPU", isDirectory: true)
    }

    private static func text(_ root: URL, _ path: String) -> String {
        (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    private static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Regular files under a folder, as "./relative/path", like the lines of SHA256SUMS.
    private static func regularFiles(under dir: URL) -> Set<String> {
        var found: Set<String> = []
        let prefix = dir.standardizedFileURL.path + "/"
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let walk = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: keys) else { return [] }
        for case let url as URL in walk {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true, values?.isSymbolicLink != true {
                found.insert("./" + url.standardizedFileURL.path.dropFirst(prefix.count))
            }
        }
        return found
    }

    private static func links(under dir: URL) -> [String] {
        guard let walk = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return [] }
        var found: [String] = []
        for case let url as URL in walk where (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            found.append(url.lastPathComponent)
        }
        return found
    }

    private static func groups(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let whole = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: whole.length)).map { match in
            (1..<match.numberOfRanges).map { whole.substring(with: match.range(at: $0)) }
        }
    }

    private static func first(_ pattern: String, in text: String) -> String? {
        groups(pattern, in: text).first?.first
    }

    private static func all(_ pattern: String, in text: String) -> [String] {
        groups(pattern, in: text).compactMap(\.first)
    }
}

/// Just enough of the .DS_Store format (a "Bud1" buddy-allocated B-tree) to list its
/// records: name, record kind (Iloc, bwsp, ...) and value bytes (for a blob, without its
/// length).
enum DSStore {
    struct Record {
        let name: String
        let kind: String
        let value: Data
    }

    static func records(_ data: Data) -> [Record]? {
        let bytes = [UInt8](data)
        guard bytes.count > 36, bytes[0..<8].elementsEqual([0, 0, 0, 1, 0x42, 0x75, 0x64, 0x31]) else { return nil }
        func u32(_ at: Int) -> Int? {
            guard at >= 0, at + 4 <= bytes.count else { return nil }
            return Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16 | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3])
        }
        guard let rootOffset = u32(8), let count = u32(4 + rootOffset) else { return nil }
        let root = 4 + rootOffset
        var addresses: [Int] = []
        for i in 0..<count {
            guard let address = u32(root + 8 + 4 * i) else { return nil }
            addresses.append(address)
        }
        func block(_ id: Int) -> Int? { id < addresses.count ? 4 + (addresses[id] & ~0x1F) : nil }
        var p = root + 8 + 4 * ((count + 255) / 256 * 256)
        guard let tocCount = u32(p) else { return nil }
        p += 4
        var dsdb: Int?
        for _ in 0..<tocCount {
            guard p < bytes.count else { return nil }
            let length = Int(bytes[p])
            let name = String(decoding: bytes[min(p + 1, bytes.count)..<min(p + 1 + length, bytes.count)], as: UTF8.self)
            if name == "DSDB" { dsdb = u32(p + 1 + length) }
            p += 5 + length
        }
        guard let dsdb, let master = block(dsdb), let rootNode = u32(master) else { return nil }

        var out: [Record] = []
        var visited = 0
        func walk(_ id: Int) -> Bool {
            visited += 1
            guard visited < 1_000, let node = block(id), let child = u32(node), let records = u32(node + 4) else { return false }
            var q = node + 8
            for _ in 0..<records {
                if child != 0 {
                    guard let left = u32(q), walk(left) else { return false }
                    q += 4
                }
                guard let length = u32(q), q + 4 + 2 * length + 8 <= bytes.count else { return false }
                let nameBytes = Data(bytes[(q + 4)..<(q + 4 + 2 * length)])
                let name = String(data: nameBytes, encoding: .utf16BigEndian) ?? ""
                q += 4 + 2 * length
                let kind = String(decoding: bytes[q..<(q + 4)], as: UTF8.self)
                let type = String(decoding: bytes[(q + 4)..<(q + 8)], as: UTF8.self)
                q += 8
                let size: Int
                switch type {
                case "long", "shor", "type": size = 4
                case "bool": size = 1
                case "comp", "dutc": size = 8
                case "blob": guard let n = u32(q) else { return false }; size = 4 + n
                case "ustr": guard let n = u32(q) else { return false }; size = 4 + 2 * n
                default: return false
                }
                guard q + size <= bytes.count else { return false }
                let start = type == "blob" ? q + 4 : q
                out.append(Record(name: name, kind: kind, value: Data(bytes[start..<(q + size)])))
                q += size
            }
            return child == 0 || walk(child)
        }
        return walk(rootNode) ? out : nil
    }
}

private extension Data {
    func uint32(at offset: Int) -> UInt32 {
        let b = [UInt8](self)
        guard offset + 4 <= b.count else { return 0 }
        return UInt32(b[offset]) << 24 | UInt32(b[offset + 1]) << 16 | UInt32(b[offset + 2]) << 8 | UInt32(b[offset + 3])
    }
}
