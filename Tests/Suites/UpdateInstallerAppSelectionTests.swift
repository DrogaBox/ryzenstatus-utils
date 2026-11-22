// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

// The installer used to copy the first .app `find` returned at the DMG root.
// Release DMGs also carry a GPU installer app and a `Kexts/` folder, so the
// choice must be `RyzenStatus.app` by name. These run the selection the real
// installer script embeds against fake mounted DMG folders, then stage the
// pick with the same `ditto` the script uses.
enum UpdateInstallerAppSelectionTests {
    static func run(_ suite: TestSuite) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("ryzenstatus-dmg-pick-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        func makeApp(_ url: URL, identifier: String) {
            let contents = url.appendingPathComponent("Contents")
            try? fm.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist = """
                <?xml version="1.0" encoding="UTF-8"?>
                <plist version="1.0"><dict>
                <key>CFBundleIdentifier</key><string>\(identifier)</string>
                </dict></plist>
                """
            try? Data(plist.utf8).write(to: contents.appendingPathComponent("Info.plist"))
        }

        func makeKexts(_ mount: URL) -> URL {
            let kexts = mount.appendingPathComponent("Kexts")
            let binary = kexts.appendingPathComponent("GPUSensors.kext/Contents/MacOS")
            try? fm.createDirectory(at: binary, withIntermediateDirectories: true)
            try? Data("kext".utf8).write(to: binary.appendingPathComponent("GPUSensors"))
            return kexts
        }

        // Every path under a folder with its size and modification date, so a
        // read-only pass leaves it exactly equal.
        func snapshot(_ url: URL) -> [String] {
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
            guard let walker = fm.enumerator(at: url, includingPropertiesForKeys: keys) else { return [] }
            return walker.compactMap { item -> String? in
                guard let file = item as? URL else { return nil }
                let values = try? file.resourceValues(forKeys: Set(keys))
                let date = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
                return "\(file.path)|\(values?.fileSize ?? -1)|\(date)"
            }.sorted()
        }

        // Runs the installer's own selection text with MNT set, then stages the
        // pick with ditto (as the installer does) and prints SRC.
        func pick(_ mount: URL, stage: URL) -> (src: String, stagedIdentifier: String) {
            let script = """
                MNT="$1"; STAGE="$2"
                \(UpdateInstallerSupport.appSelectionScript)
                if [ -n "$SRC" ]; then /usr/bin/ditto "$SRC" "$STAGE" || exit 3; fi
                printf '%s' "$SRC"
                """
            let result = BoundedProcessRunner.run("/bin/sh", ["-c", script, "pick", mount.path, stage.path],
                                                  timeout: 10, maxOutputBytes: 64 * 1024)
            let plist = NSDictionary(contentsOf: stage.appendingPathComponent("Contents/Info.plist"))
            let identifier = plist?["CFBundleIdentifier"] as? String ?? ""
            return (result.status == 0 ? String(decoding: result.output, as: UTF8.self) : "<status \(result.status)>",
                    identifier)
        }

        let appName = UpdateInstallerSupport.dmgAppBundleName
        suite.expect(appName == "RyzenStatus.app", "the DMG's app bundle is RyzenStatus.app, got \(appName)")

        // 1. Installer app next to the real app at the root, created first so a
        //    directory-order pick would see it before RyzenStatus.app.
        do {
            let mount = root.appendingPathComponent("side-by-side")
            makeApp(mount.appendingPathComponent("RyzenStatus GPU.app"), identifier: "com.ryzenstatus.gpuinstaller")
            makeApp(mount.appendingPathComponent(appName), identifier: "com.ryzenstatus.utils")
            let kexts = makeKexts(mount)
            let before = snapshot(mount)
            let stage = root.appendingPathComponent("stage-1")
            let picked = pick(mount, stage: stage)
            suite.expect(picked.src == mount.appendingPathComponent(appName).path,
                         "with RyzenStatus GPU.app at the root the installer still picks RyzenStatus.app, got \(picked.src)")
            suite.expect(picked.stagedIdentifier == "com.ryzenstatus.utils",
                         "the staged copy is the monitor app, not the GPU installer, got \(picked.stagedIdentifier)")
            suite.expect(snapshot(mount) == before && fm.fileExists(atPath: kexts.path),
                         "picking and staging leaves the DMG contents, Kexts/ included, untouched")
            suite.expect(!fm.fileExists(atPath: stage.appendingPathComponent("Kexts").path)
                            && !fm.fileExists(atPath: stage.appendingPathComponent("RyzenStatus GPU.app").path),
                         "only the app bundle is staged, never Kexts/ or the GPU installer")
        }

        // 2. Installer inside "GPU RX 6000/", as the 1.86.0 DMG ships it.
        do {
            let mount = root.appendingPathComponent("gpu-folder")
            let gpuFolder = mount.appendingPathComponent("GPU RX 6000")
            makeApp(gpuFolder.appendingPathComponent("RyzenStatus GPU.app"), identifier: "com.ryzenstatus.gpuinstaller")
            makeApp(mount.appendingPathComponent(appName), identifier: "com.ryzenstatus.utils")
            let kexts = makeKexts(mount)
            let gpuBefore = snapshot(gpuFolder)
            let kextsBefore = snapshot(kexts)
            let picked = pick(mount, stage: root.appendingPathComponent("stage-2"))
            suite.expect(picked.src == mount.appendingPathComponent(appName).path
                            && picked.stagedIdentifier == "com.ryzenstatus.utils",
                         "with the installer in GPU RX 6000/ the installer picks RyzenStatus.app, got \(picked.src)")
            suite.expect(!gpuBefore.isEmpty && snapshot(gpuFolder) == gpuBefore,
                         "the GPU RX 6000 folder is left untouched")
            suite.expect(!kextsBefore.isEmpty && snapshot(kexts) == kextsBefore,
                         "the Kexts folder is left untouched")
        }

        // 3. No RyzenStatus.app at the root: nothing is picked, even with other
        //    apps around, and the script turns that into fail-no-app-in-dmg.
        do {
            let mount = root.appendingPathComponent("missing")
            makeApp(mount.appendingPathComponent("RyzenStatus GPU.app"), identifier: "com.ryzenstatus.gpuinstaller")
            makeApp(mount.appendingPathComponent("GPU RX 6000/RyzenStatus GPU.app"),
                    identifier: "com.ryzenstatus.gpuinstaller")
            makeApp(mount.appendingPathComponent("Other/\(appName)"), identifier: "com.ryzenstatus.utils")
            _ = makeKexts(mount)
            let stage = root.appendingPathComponent("stage-3")
            let picked = pick(mount, stage: stage)
            suite.expect(picked.src.isEmpty && !fm.fileExists(atPath: stage.path),
                         "without RyzenStatus.app at the root nothing is picked or staged, got \(picked.src)")
        }

        // 4. A symlink named RyzenStatus.app is refused.
        do {
            let mount = root.appendingPathComponent("symlink")
            let elsewhere = root.appendingPathComponent("elsewhere/\(appName)")
            makeApp(elsewhere, identifier: "com.ryzenstatus.utils")
            try? fm.createDirectory(at: mount, withIntermediateDirectories: true)
            try? fm.createSymbolicLink(at: mount.appendingPathComponent(appName), withDestinationURL: elsewhere)
            let picked = pick(mount, stage: root.appendingPathComponent("stage-4"))
            suite.expect(picked.src.isEmpty, "a symlink in place of RyzenStatus.app is not picked, got \(picked.src)")
        }

        // Runs the installer's own swap text: $APP installed, $STAGE verified
        // copy, $DEST the DMG's bundle name in the same folder.
        func swap(app: URL, dest: URL, stage: URL) -> String {
            let script = """
                exec 2>/dev/null
                note() { :; }
                APP="$1"; DEST="$2"; STAGE="$3"; PID=4242; ASUSER=""; LAUNCH="$APP"
                \(UpdateInstallerSupport.swapScript)
                printf '%s' "$LAUNCH"
                """
            let result = BoundedProcessRunner.run("/bin/sh", ["-c", script, "swap", app.path, dest.path, stage.path],
                                                  timeout: 10, maxOutputBytes: 64 * 1024)
            return result.status == 0 ? String(decoding: result.output, as: UTF8.self) : "<status \(result.status)>"
        }
        func identifier(_ app: URL) -> String {
            let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
            return plist?["CFBundleIdentifier"] as? String ?? ""
        }
        func entries(_ dir: URL) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        }

        // 5. Installed copy differs from the DMG's name only in case. On the
        //    default (case-insensitive) volume both names are one directory:
        //    the old cleanup compared strings and deleted the new app.
        do {
            let dir = root.appendingPathComponent("case-only")
            let installed = dir.appendingPathComponent("Ryzenstatus.app")
            let dest = dir.appendingPathComponent(appName)
            let stage = dir.appendingPathComponent(".\(appName).update-new")
            makeApp(installed, identifier: "old")
            makeApp(stage, identifier: "new")
            let caseInsensitive = fm.fileExists(atPath: dest.path)
            let launch = swap(app: installed, dest: dest, stage: stage)
            suite.expect(identifier(dest) == "new" && launch == dest.path,
                         "a case-only rename keeps the newly installed app (case-insensitive volume: \(caseInsensitive)), "
                            + "launch \(launch), left \(entries(dir))")
            suite.expect(entries(dir) == [appName],
                         "after a case-only rename exactly RyzenStatus.app is left (case-insensitive volume: "
                            + "\(caseInsensitive)), got \(entries(dir))")
        }

        // 6. A real rename (another name) still removes the old bundle.
        do {
            let dir = root.appendingPathComponent("rename")
            let installed = dir.appendingPathComponent("RyzenStatus Utils.app")
            let dest = dir.appendingPathComponent(appName)
            let stage = dir.appendingPathComponent(".\(appName).update-new")
            makeApp(installed, identifier: "old")
            makeApp(stage, identifier: "new")
            let launch = swap(app: installed, dest: dest, stage: stage)
            suite.expect(identifier(dest) == "new" && launch == dest.path && entries(dir) == [appName],
                         "a real rename installs RyzenStatus.app and removes the old-named bundle, got \(entries(dir))")
        }

        // 7. Same name: replaced in place, backup and stage gone.
        do {
            let dir = root.appendingPathComponent("in-place")
            let installed = dir.appendingPathComponent(appName)
            let stage = dir.appendingPathComponent(".\(appName).update-new")
            makeApp(installed, identifier: "old")
            makeApp(stage, identifier: "new")
            let launch = swap(app: installed, dest: installed, stage: stage)
            suite.expect(identifier(installed) == "new" && launch == installed.path && entries(dir) == [appName],
                         "a plain update replaces the bundle in place, got \(entries(dir))")
        }

        // 8. A failed swap keeps the old bundle (case-only names) and
        //    relaunches it.
        do {
            let dir = root.appendingPathComponent("rollback")
            let installed = dir.appendingPathComponent("Ryzenstatus.app")
            let dest = dir.appendingPathComponent(appName)
            makeApp(installed, identifier: "old")
            let launch = swap(app: installed, dest: dest,
                              stage: dir.appendingPathComponent(".missing.update-new"))
            suite.expect(identifier(installed) == "old" && launch == installed.path && entries(dir).count == 1,
                         "a failed swap keeps the old bundle and relaunches it, got \(entries(dir)), "
                            + "identifier \(identifier(installed)), launch \(launch)")
        }

        do {
            let script = UpdateInstallerSupport.installerScript(allowAdhoc: true)
            suite.expect(script.components(separatedBy: UpdateInstallerSupport.swapScript).count == 2,
                         "the installer embeds the tested swap text exactly once")
        }

        // 9. The real installer embeds exactly this selection, with the
        //    failure marker right after it, in both signing modes.
        for allowAdhoc in [false, true] {
            let script = UpdateInstallerSupport.installerScript(allowAdhoc: allowAdhoc)
            let selection = UpdateInstallerSupport.appSelectionScript
            suite.expect(script.components(separatedBy: selection).count == 2,
                         "the installer (allowAdhoc \(allowAdhoc)) embeds the app selection exactly once")
            suite.expect(script.contains(selection + "\nLAUNCH=\"$APP\"\nif [ -z \"$SRC\" ]; then\n    note fail-no-app-in-dmg"),
                         "an empty pick ends in fail-no-app-in-dmg (allowAdhoc \(allowAdhoc))")
            suite.expect(!script.contains("-name '*.app'") && !script.contains("/usr/bin/find"),
                         "the installer no longer copies the first .app it finds (allowAdhoc \(allowAdhoc))")
            suite.expect(!script.contains("Kexts") && !script.contains("GPU RX 6000"),
                         "the installer never names Kexts/ or the GPU folder (allowAdhoc \(allowAdhoc))")
            let mountLines = script.split(separator: "\n").filter { $0.contains("$MNT") }
            let allowed = mountLines.allSatisfy { line in
                line.contains("mktemp") || line.contains("/bin/mkdir \"$MNT\"") || line.contains("hdiutil")
                    || line.contains("rmdir")
                    || line.contains("$MNT/\(appName)")
            }
            suite.expect(allowed,
                         "the mounted DMG is only mounted, read at RyzenStatus.app and detached: \(mountLines)")
        }
    }
}
