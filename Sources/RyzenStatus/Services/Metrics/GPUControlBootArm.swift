// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Darwin
import Foundation

/// "Allow changes after restart too": a LaunchDaemon that runs
/// `gpucontrol arm` once at each start-up, so GPU changes are allowed again
/// after a restart without the password.
///
/// It opens nothing the button does not: the same command, the same tool,
/// as root, once per start-up. GPUSensors.kext keeps every rule of its own
/// (one program at a time, the way back on release, after 30 s of silence and
/// after a wake, the watchdogs, writing off after a failure until restart),
/// and "Close Changes" still closes it until the next start-up. Turning the
/// option off removes the daemon; it does not close what is open now.
///
/// The script checks, at every start-up and before it runs anything, what
/// `GPUControlArmTool.availability` checks before the app offers the button:
/// the tool and every folder above it root's alone (no group or other write,
/// no access control list), the tool a plain file without setuid or setgid,
/// its signature intact with our identifier. Anything else and it stops
/// without running the tool: a folder that became writable by a user later
/// (a package manager taking /usr/local/bin, say) never gets a program of
/// that user run as root. No tool (the GPU commands removed) is the same
/// quiet stop.
///
/// The kext answers "not ready" until the driver has read the start-up limit,
/// some seconds into the start-up, so the script tries again every 5 s for
/// 10 min at most, then gives up until the next start-up.
enum GPUControlBootArm {
    /// Under the app's bundle identifier, so it reads as RyzenStatus's in
    /// System Settings > General > Login Items & Extensions.
    static let label = "com.ryzenstatus.utils.gpu-arm"
    static let plistPath = "/Library/LaunchDaemons/" + label + ".plist"
    static let folders = ["/usr/local/bin", "/usr/local", "/usr", "/"]
    static let tries = 120
    static let pauseSeconds = 5

    /// The script launchd runs as root. The parameters are for the tests: the
    /// app always writes the defaults.
    static func script(tool: String = GPUControlArmTool.installedPath,
                       folders: [String] = folders,
                       ownerUID: UInt32 = 0,
                       identifier: String = GPUControlArmTool.identifier,
                       tries: Int = tries,
                       pause: Int = pauseSeconds) -> String {
        let list = ([tool] + folders).map(shellQuoted).joined(separator: " ")
        return """
        tool=\(shellQuoted(tool))
        [ -f "$tool" ] && [ ! -L "$tool" ] || exit 0
        for f in \(list); do
          [ -e "$f" ] && [ ! -L "$f" ] || exit 0
          [ -z "$(/usr/bin/find "$f" -maxdepth 0 \\( ! -user \(ownerUID) -o -perm +022 \\) -print)" ] || exit 0
          [ -z "$(/bin/ls -lde "$f" | /usr/bin/sed -n 2p)" ] || exit 0
        done
        [ -z "$(/usr/bin/find "$tool" -maxdepth 0 -perm +6000 -print)" ] || exit 0
        /usr/bin/codesign --verify -R=\(shellQuoted("identifier \"\(identifier)\"")) "$tool" 2>/dev/null || exit 0
        i=0
        while [ "$i" -lt \(tries) ]; do
          "$tool" arm >/dev/null 2>&1 && exit 0
          i=$((i + 1))
          /bin/sleep \(pause)
        done
        exit 0
        """
    }

    /// The daemon's property list: runs once when loaded, that is at each
    /// start-up and right after it is installed.
    static func plistData(script: String = script()) -> Data {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/bin/sh", "-c", script],
            "RunAtLoad": true,
        ]
        // A fixed dictionary of strings and a Bool: serialization cannot fail.
        return (try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)) ?? Data()
    }

    /// The administrator command that installs the daemon and loads it, which
    /// also allows changes now. The property list travels as base64, so the
    /// command holds nothing to quote but letters, digits, + / and =. A list
    /// that does not check or load is removed again. (`install` cannot read a
    /// pipe: "Inappropriate file type or format"; `base64 -o` writes the file
    /// itself, root's under root's umask, then owner and mode are set anyway.)
    static var installCommand: String {
        let encoded = plistData().base64EncodedString()
        return "/bin/launchctl bootout system/\(label) 2>/dev/null; "
            + "(umask 022 && /bin/rm -f \(plistPath) && "
            + "/bin/echo '\(encoded)' | /usr/bin/base64 -D -o \(plistPath)) && "
            + "/usr/sbin/chown root:wheel \(plistPath) && /bin/chmod 0644 \(plistPath) && "
            + "/usr/bin/plutil -lint -s \(plistPath) && "
            + "/bin/launchctl bootstrap system \(plistPath) || { /bin/rm -f \(plistPath); exit 1; }"
    }

    /// Unloads the daemon (stopping a start-up's tries still running) and
    /// removes it. What is allowed now stays allowed until "Close Changes" or
    /// a restart.
    static var removeCommand: String {
        "/bin/launchctl bootout system/\(label) 2>/dev/null; /bin/rm -f \(plistPath)"
    }

    /// Installed: the file is there. Only root can put it there, so a file
    /// owned by anyone else is not counted (and the start-up ignores it too:
    /// launchd loads only root's daemons).
    static func isInstalled(lookup: GPUControlArmTool.Lookup = GPUControlArmTool.lstatInfo) -> Bool {
        guard let info = lookup(plistPath) else { return false }
        return info.kind == .regular && info.uid == 0
    }

    /// One shell word, in single quotes.
    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
