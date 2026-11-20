// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import IOKit

/// What opening the channel came to.
enum GPUControlChannelOpen: Equatable, Sendable {
    case open
    /// No `DrogaBoxGPUSensors` service: the kext is not loaded.
    case noService
    /// The service is there and would not open (a kext before 0.5.0 has no
    /// channel). Nothing was opened.
    case refused(Int32)
    /// This connection was closed. It is never opened again: a new one would
    /// be another program to the kext.
    case closed
}

/// One connection to the control channel of GPUSensors.kext.
///
/// The kext gives every connection its own client number and counts a change
/// as held by the connection that asked for it, so everything one program
/// does (`status`, `set`, `setOD8`, `alive`, `release`) goes through the same
/// connection. Closing it puts the start-up values back at once, and so does
/// the program ending.
///
/// The calls block: `set` and `setOD8` wait up to 5 s for the kext's worker.
/// Nothing here may run on the main thread; `GPUControlController` owns the
/// queue. `release` may be called from another thread while a `set` waits: it
/// wins, and the waiting call answers "cancelled".
protocol GPUControlChannel: AnyObject, Sendable {
    /// Opens the connection once. Asking again while it is open answers
    /// `.open`; after `close()` it answers `.closed` for good.
    func open() -> GPUControlChannelOpen
    /// One call of the user client: scalars in (the version first), at most
    /// `outputCount` scalars out. Nil when the call itself failed, which the
    /// kext does for wrong counts and IOKit for a dead connection.
    func call(_ selector: GPUControlWire.Selector, input: [UInt64], outputCount: Int) -> [UInt64]?
    func close()
}

/// The typed calls, the same for the kext and for its model.
extension GPUControlChannel {
    /// Nil when the kext did not answer with a whole status.
    func status() -> GPUControlChannelStatus? {
        call(.status, input: [GPUControlWire.channelVersion], outputCount: GPUControlWire.statusCount)
            .flatMap(GPUControlChannelStatus.init(scalars:))
    }

    /// Asks for a power limit in watts. The start-up value is the way back.
    func setPower(watts: UInt32) -> GPUControlAnswer? {
        answer(.set, input: [GPUControlWire.channelVersion, UInt64(watts)])
    }

    /// Asks for a whole OD8 state. Nil also when the state cannot be written
    /// as scalars; `GPUControlOD8Want.scalars()` says so beforehand.
    func setOD8(_ want: GPUControlOD8Want) -> GPUControlAnswer? {
        guard let input = want.scalars() else { return nil }
        return answer(.setOD8, input: input)
    }

    /// The owner's "still here", every 5 s while it holds a change.
    func alive() -> GPUControlAnswer? {
        answer(.alive, input: [GPUControlWire.channelVersion])
    }

    /// Goes back to the start-up values. Answers at once; the way back runs
    /// on the kext's worker afterwards.
    func release() -> GPUControlAnswer? {
        answer(.release, input: [GPUControlWire.channelVersion])
    }

    private func answer(_ selector: GPUControlWire.Selector, input: [UInt64]) -> GPUControlAnswer? {
        guard let out = call(selector, input: input, outputCount: selector.outputCount), !out.isEmpty else { return nil }
        // The second scalar counts only with "refused": the kext zeroes it otherwise.
        let refused = out[0] == GPUControlReply.od8Refused.rawValue
        return GPUControlAnswer(replyCode: out[0], checkCode: refused && out.count > 1 ? out[1] : 0)
    }
}

/// The real channel: the only code in the app that opens the kext's user
/// client. Nothing creates one yet; the app connects it in one place, at
/// launch, and tests and harnesses never do.
final class KextGPUControlChannel: GPUControlChannel, @unchecked Sendable {
    private let state = NSCondition()
    private var connection: io_connect_t = 0
    private var wasClosed = false
    /// Calls running now. `close()` waits for them, so a port name is never
    /// used after it was given back.
    private var callsInFlight = 0

    func open() -> GPUControlChannelOpen {
        state.lock()
        defer { state.unlock() }
        if wasClosed { return .closed }
        if connection != 0 { return .open }
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching(GPUSensorsReading.serviceClass))
        guard service != 0 else { return .noService }
        defer { IOObjectRelease(service) }
        var opened: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &opened)
        guard result == KERN_SUCCESS, opened != 0 else { return .refused(result) }
        connection = opened
        return .open
    }

    func call(_ selector: GPUControlWire.Selector, input: [UInt64], outputCount: Int) -> [UInt64]? {
        state.lock()
        guard connection != 0, outputCount > 0 else {
            state.unlock()
            return nil
        }
        let port = connection
        callsInFlight += 1
        state.unlock()
        defer {
            state.lock()
            callsInFlight -= 1
            state.broadcast()
            state.unlock()
        }
        var output = [UInt64](repeating: 0, count: outputCount)
        var count = UInt32(outputCount)
        let result = IOConnectCallScalarMethod(port, selector.rawValue, input, UInt32(input.count), &output, &count)
        guard result == KERN_SUCCESS, count <= UInt32(outputCount) else { return nil }
        return Array(output.prefix(Int(count)))
    }

    func close() {
        state.lock()
        defer { state.unlock() }
        // Closed for good, also when it was never opened: a later open()
        // must not make a second connection.
        wasClosed = true
        guard connection != 0 else { return }
        // No new call starts from here on.
        let port = connection
        connection = 0
        while callsInFlight > 0 { state.wait() }
        IOServiceClose(port)
    }

    deinit { close() }
}
