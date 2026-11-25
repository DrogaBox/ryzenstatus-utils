// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

enum SudoersSupport {
    /// True when a `pmset -g` report lists lid sleep as disabled.
    static func sleepDisabled(inPmsetOutput output: String) -> Bool {
        output.range(of: #"SleepDisabled\s+1"#, options: .regularExpression) != nil
    }

    /// The closed-lid NOPASSWD rule, granted by uid (`#uid` user spec). A
    /// username would have to be sanitized against sudoers *and* shell
    /// metacharacters — short names on SSO-enrolled Macs can be full email
    /// addresses — while a uid interpolates as bare digits, which
    /// neither interpreter can read as anything else.
    static func clamshellRule(uid: uid_t) -> String {
        "#\(uid) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 1, /usr/bin/pmset disablesleep 0"
    }

    /// The administrator command that writes the rule. The old one piped the
    /// rule into `install -m 0440 /dev/stdin`, and `install` refuses a source
    /// that is not a regular file: "Inappropriate file type or format", exit
    /// 71, whoever runs it. The rule never got written and the closed-lid
    /// setup always failed.
    ///
    /// Now the rule travels as base64 (nothing to quote but letters, digits,
    /// + / and =) and `base64 -o` writes it to a name with a dot, which sudo
    /// skips in /etc/sudoers.d. It is made root's and 0440, checked with
    /// `visudo -c`, and only then moved over the real name in one rename, so
    /// sudo never reads a half-written or unchecked rule. Earlier-named rules
    /// go first; any failure removes both files.
    static func installCommand(rule: String, rulePath: String, legacyPaths: [String]) -> String {
        let staged = stagedPath(for: rulePath)
        let encoded = Data((rule + "\n").utf8).base64EncodedString()
        let legacy = legacyPaths.isEmpty ? "" : "rm -f \(legacyPaths.joined(separator: " ")) && "
        return "mkdir -p /etc/sudoers.d && \(legacy)rm -f \(staged) && "
            + "(umask 077 && /bin/echo '\(encoded)' | /usr/bin/base64 -D -o \(staged)) && "
            + "/usr/sbin/chown root:wheel \(staged) && /bin/chmod 0440 \(staged) && "
            + "/usr/sbin/visudo -c -f \(staged) && /bin/mv -f \(staged) \(rulePath) "
            + "|| { rm -f \(staged) \(rulePath); exit 1; }"
    }

    /// Next to the rule, with a dot in its name: sudo ignores it.
    static func stagedPath(for rulePath: String) -> String {
        let url = URL(fileURLWithPath: rulePath)
        return url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".new").path
    }
}

