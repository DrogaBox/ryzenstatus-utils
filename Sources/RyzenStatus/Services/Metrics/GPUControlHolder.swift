// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import IOKit
import os

/// Who holds the GPU control when this app does not (security review S-5,
/// corrected for our own tool).
///
/// The kext's status has two bits that matter here: `Owned` ("some program
/// holds a change") and `Mine` ("the program asking does"). Neither says
/// *which* program, so the app called every other holder "another program" —
/// including `gpucontrol`, the tool RyzenStatus GPU installs, which is exactly
/// what holds the OD8 table (and the fan curve in it) when the owner runs
/// `gpucontrol hold` in a terminal. The kext cannot answer it either: its
/// client number is an opaque counter (`++gNextClient`, kern_control.cpp),
/// not a pid, and nothing in the status carries one.
///
/// No new kext field is needed: the kernel publishes `IOUserClientCreator`
/// ("pid 1234, gpucontrol") on every user client of a service, the same
/// property `ProcessUsageService` reads on the GPU accelerators. The app
/// lists the clients attached to `DrogaBoxGPUSensors`, drops its own pid, and
/// checks that every remaining one runs the gpucontrol it installs (the path
/// and the signature the arm button already checks). All of them ours: the
/// hold is ours. Anything else attached: another program, as before.
///
/// This is wording, not a security boundary: writing is open to every program
/// on the Mac once armed (`readyWarning` says so), and a program that wanted
/// to pretend to be ours could. What it fixes is the warning being wrong
/// about our own tool.
enum GPUControlHolder: Equatable, Sendable {
    /// Nothing holds the control (`Owned` clear).
    case none
    /// This app's own connection holds it (`Mine`).
    case app
    /// The gpucontrol that RyzenStatus installs holds it, and it is the only
    /// program attached besides this app.
    case tool
    /// A program the app cannot vouch for: another program.
    case other

    /// Held by the tool this app installs, not by another program.
    var isOwnTool: Bool { self == .tool }
}

/// The decision, without IOKit: `GPUControlHolderProbe` supplies the pids.
enum GPUControlHolderLogic {
    /// - `mine` and `owned`: the status's two flags.
    /// - `attachedPids`: the pids of the service's user clients.
    /// - `ownPid`: this app's pid, left out.
    /// - `isOwnTool`: whether a pid runs the gpucontrol the app installs.
    static func classify(mine: Bool, owned: Bool, attachedPids: [Int32], ownPid: Int32,
                         isOwnTool: (Int32) -> Bool) -> GPUControlHolder {
        guard owned else { return .none }
        if mine { return .app }
        let others = attachedPids.filter { $0 != ownPid }
        // A hold with no other client listed (a kill in flight, a
        // properties-only read): nothing the app can vouch for.
        guard !others.isEmpty else { return .other }
        return others.allSatisfy(isOwnTool) ? .tool : .other
    }

    /// The pid in an `IOUserClientCreator` value ("pid 1234, gpucontrol"), or
    /// nil for anything else. The kernel writes it as `pid %d, %s`, so the
    /// digits run up to the comma. Pid 0 is "nobody", never a client.
    static func pid(fromCreator creator: String) -> Int32? {
        guard creator.hasPrefix("pid ") else { return nil }
        let digits = creator.dropFirst(4).prefix { $0.isNumber }
        guard !digits.isEmpty, let pid = Int32(digits), pid > 0 else { return nil }
        return pid
    }
}

/// The real answer: IOKit for the clients, `proc_pidpath` and the arm button's
/// signature check for the program.
enum GPUControlHolderProbe {
    /// The kext's service class (GPU/sensors/kext/Info.plist).
    static let serviceClass = "DrogaBoxGPUSensors"

    /// The pids of the user clients attached to every service of that class.
    static func attachedPids(serviceClass: String = serviceClass) -> [Int32] {
        var pids: [Int32] = []
        var services = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(serviceClass),
                                           &services) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(services) }
        var service = IOIteratorNext(services)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(services)
            }
            var clients = io_iterator_t()
            guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &clients) == KERN_SUCCESS
            else { continue }
            defer { IOObjectRelease(clients) }
            var client = IOIteratorNext(clients)
            while client != 0 {
                defer {
                    IOObjectRelease(client)
                    client = IOIteratorNext(clients)
                }
                // Targeted read: the whole property dictionary of a user
                // client is large and is not needed.
                guard let ref = IORegistryEntryCreateCFProperty(client, "IOUserClientCreator" as CFString,
                                                               kCFAllocatorDefault, 0),
                      let creator = ref.takeRetainedValue() as? String,
                      let pid = GPUControlHolderLogic.pid(fromCreator: creator)
                else { continue }
                pids.append(pid)
            }
        }
        return pids
    }

    /// Whether `pid` runs the gpucontrol the app installs: the path the app
    /// runs and the signature it checks, nothing else. A copy elsewhere, or a
    /// program of the same name, is another program.
    static func runsOwnTool(_ pid: Int32, path: String = GPUControlArmTool.installedPath,
                            signatureIdentifier: (String) -> String? = GPUControlArmTool.signingIdentifier) -> Bool {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0,
              String(cString: buffer) == path else { return false }
        return signatureIdentifier(path) == GPUControlArmTool.identifier
    }

    private struct Answer {
        var at: TimeInterval
        var holder: GPUControlHolder
    }

    /// The last answer: the page reads `facts` on every redraw, and a registry
    /// walk each time would be waste. Three seconds is well inside the kext's
    /// five, the gap between `gpucontrol hold`'s own words to the kext.
    private static let last = OSAllocatedUnfairLock(initialState: Answer(at: -.greatestFiniteMagnitude, holder: .other))

    /// Who holds it now. Only asked while the kext says a program does and it
    /// is not this one; the seams are the tests'.
    static func current(mine: Bool, owned: Bool, ownPid: Int32 = getpid(),
                        now: TimeInterval = ProcessInfo.processInfo.systemUptime,
                        ttl: TimeInterval = 3,
                        attached: () -> [Int32] = { attachedPids() },
                        isOwnTool: (Int32) -> Bool = { runsOwnTool($0) }) -> GPUControlHolder {
        guard owned, !mine else { return .none }
        let answer = last.withLock { $0 }
        if now >= answer.at, now - answer.at < ttl { return answer.holder }
        let holder = GPUControlHolderLogic.classify(mine: false, owned: true, attachedPids: attached(),
                                                    ownPid: ownPid, isOwnTool: isOwnTool)
        last.withLock { $0 = Answer(at: now, holder: holder) }
        return holder
    }
}
