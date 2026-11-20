// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CryptoKit
import Foundation

/// GPU/ was copied from a private repository. Nothing in it may carry a path of the
/// machine it was made on or point back at the private repositories, and its licenses
/// travel with it.
enum GPUFolderTests {
    static func run(_ suite: TestSuite) {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("GPU")
        let files = files(under: root)
        suite.expect(files.count > 100, "the GPU folder is found from the repo root (\(files.count) files)")
        for needed in ["LICENSE", "NOTICE.md", "README.md", "install/sensors.sh",
                       "tools/driver/kcfunc.py", "sensors/kext/control_logic.hpp"] {
            suite.expect(files[needed] != nil, "GPU/\(needed) is there")
        }
        privateText(suite, files)
        licenses(suite, files)
    }

    /// Every file of GPU/ that git would track, by path relative to GPU/, as text. Build
    /// output, fetched dependencies and test media are skipped: they are never committed.
    static func files(under root: URL) -> [String: String] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [:] }
        let skippedFolders: Set<String> = ["build", "dist", ".build", "__pycache__"]
        let prefix = root.standardizedFileURL.path + "/"
        var found: [String: String] = [:]
        for case let url as URL in walk {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { continue }
            let relative = String(path.dropFirst(prefix.count))
            if values?.isDirectory == true {
                if skippedFolders.contains(url.lastPathComponent) || relative == "deps" || relative == "tests/media" {
                    walk.skipDescendants()
                }
                continue
            }
            if values?.isSymbolicLink == true || values?.isRegularFile != true { continue }
            if url.lastPathComponent == ".DS_Store" || url.pathExtension == "o" { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            found[relative] = String(decoding: data, as: UTF8.self)
        }
        return found
    }

    /// The places in `text` that match `pattern`, as line numbers.
    static func lines(matching pattern: String, in text: String, caseInsensitive: Bool = false) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
        else { return [-1] }
        let whole = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: whole.length)).map { match in
            whole.substring(to: match.range.location).components(separatedBy: "\n").count
        }
    }

    /// SHA-256 of the private trust kext's name, lowercased (13 letters). The test looks
    /// for the name by this digest so that the public repository never spells it out.
    static let privateKextNameDigest = "04b277c8d2d0a99fcd9d9847c912c9d857b2533e51408793735060fcb83ffa09"
    static let privateKextNameLength = 13

    /// Line numbers where a run of letters and digits contains the private kext's name,
    /// in any case: every window of the name's length is hashed and compared.
    static func linesNamingPrivateKext(in text: String) -> [Int] {
        var found: [Int] = []
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            let words = line.lowercased().split(whereSeparator: { !($0.isASCII && ($0.isLetter || $0.isNumber)) })
            let hit = words.contains { word in
                let chars = Array(word)
                guard chars.count >= privateKextNameLength else { return false }
                for start in 0...(chars.count - privateKextNameLength) {
                    let window = String(chars[start..<(start + privateKextNameLength)])
                    let digest = SHA256.hash(data: Data(window.utf8)).map { String(format: "%02x", $0) }.joined()
                    if digest == privateKextNameDigest { return true }
                }
                return false
            }
            if hit { found.append(index + 1) }
        }
        return found
    }

    private static func privateText(_ suite: TestSuite, _ files: [String: String]) {
        var homePaths: [String] = []
        var trust: [String] = []
        var repoLinks: [String] = []
        var oldName: [String] = []
        for (path, text) in files.sorted(by: { $0.key < $1.key }) {
            // A home folder path. The scripts that look for one in binaries hold "/Users/"
            // followed by "|" or "[", which this does not match.
            homePaths += lines(matching: "/Users/[A-Za-z0-9._-]", in: text).map { "\(path):\($0)" }
            trust += linesNamingPrivateKext(in: text).map { "\(path):\($0)" }
            repoLinks += lines(matching: "github\\.com/DrogaBox/DrogaBox", in: text, caseInsensitive: true)
                .map { "\(path):\($0)" }
            // The kext registers its IOKit classes under these two names, and the app,
            // gpusensors and gpucontrol look them up by them: they stay.
            oldName += lines(matching: "DrogaBoxGPU(?!Sensors|ControlClient)", in: text).map { "\(path):\($0)" }
        }
        suite.expect(homePaths.isEmpty, "no file in GPU/ holds a home folder path: \(homePaths)")
        suite.expect(trust.isEmpty, "no file in GPU/ names the private trust kext: \(trust)")
        suite.expect(repoLinks.isEmpty, "no file in GPU/ links a private repository: \(repoLinks)")
        suite.expect(oldName.isEmpty, "no file in GPU/ names the private repository: \(oldName)")
    }

    private static func licenses(_ suite: TestSuite, _ files: [String: String]) {
        suite.expect(files["LICENSE"]?.hasPrefix("MIT License") == true, "GPU/LICENSE is the MIT license")
        let notice = files["NOTICE.md"] ?? ""
        suite.expect(notice.contains("Copyright (c) 2016-2018, vit9696")
                         && notice.contains("Redistributions in binary form must reproduce the above copyright notice"),
                     "GPU/NOTICE.md carries Lilu's BSD 3-Clause license, which goes with every kext")
        suite.expect(notice.contains("https://github.com/wh0ami7/vcn-video-decoders") && notice.contains("MIT License"),
                     "GPU/NOTICE.md keeps the notice of the input checks from vcn-video-decoders")
        suite.expect(notice.contains("`decode/vp9/ac_vcn_vp9_default.h` comes from Mesa"),
                     "GPU/NOTICE.md keeps the notice of the VP9 tables")
        suite.expect(notice.contains("Apple Public Source License 2.0"),
                     "GPU/NOTICE.md names the license of the MacKernelSDK parts linked into the kexts")
        suite.expect(files["decode/vp9/ac_vcn_vp9_default.h"]?.contains("Advanced Micro Devices") == true,
                     "the VP9 tables keep their own license header")
        suite.expect(files["tools/package.sh"]?.contains("cp README.md LICENSE NOTICE.md") == true,
                     "the package carries LICENSE and NOTICE.md next to the kexts")
        let readme = (try? String(contentsOfFile: FileManager.default.currentDirectoryPath + "/README.md",
                                  encoding: .utf8)) ?? ""
        suite.expect(readme.contains("GPU/LICENSE") && readme.contains("GPU/NOTICE.md")
                         && readme.contains("SMCAMDProcessor_Source/LICENSE"),
                     "the README says which folder carries which license")
    }
}
