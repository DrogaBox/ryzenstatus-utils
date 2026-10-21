// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Darwin
import Foundation

private final class BoundedProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()

    init(limit: Int) { self.limit = max(0, limit) }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        let available = max(0, limit - data.count)
        if available > 0 { data.append(chunk.prefix(available)) }
    }

    func value() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

/// Cancellation owns one process launch; the lock closes the gap between
/// cancelling a queued request and that request launching its child.
final class BoundedProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func cancel() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        cancelled = true
        let child = process
        lock.unlock()
        guard let child, child.isRunning else { return }
        child.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }

    func launch(_ child: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled, process == nil else { throw CancellationError() }
        try child.run()
        process = child
    }

    func release(_ child: Process) {
        lock.lock()
        defer { lock.unlock() }
        if process === child { process = nil }
    }
}

private struct BoundedChild {
    let pid: pid_t
    let terminate: () -> Void
    let status: () -> Int32
}

private final class BoundedExitStatus: @unchecked Sendable {
    var raw: Int32 = 0
}

enum BoundedProcessRunner {
    struct Result {
        let status: Int32
        let output: Data
        let timedOut: Bool
    }

    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval,
                    maxOutputBytes: Int, environment: [String: String]? = nil,
                    cancellation: BoundedProcessCancellation? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        // Assigning nil explicitly can clear the inherited environment on
        // Foundation. Leave it untouched unless the caller supplies exports.
        if let environment { process.environment = environment }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        defer { cancellation?.release(process) }
        return collect(from: pipe, timeout: timeout, maxOutputBytes: maxOutputBytes) { finished in
            // Never park waitUntilExit on a global-pool thread: timed-out
            // children would exhaust that pool and starve later app work.
            process.terminationHandler = { _ in finished.signal() }
            if let cancellation { try cancellation.launch(process) }
            else { try process.run() }
            return BoundedChild(pid: process.processIdentifier,
                                terminate: { if process.isRunning { process.terminate() } },
                                status: { process.terminationStatus })
        }
    }

    /// A shell spawned by a Terminal-launched app must not inherit its
    /// controlling TTY. A separate session and /dev/null input prevent .zshrc
    /// from taking that terminal over. Children remain bounded and reaped.
    static func runInNewSession(_ path: String, _ arguments: [String], timeout: TimeInterval,
                                maxOutputBytes: Int, environment: [String: String]? = nil) -> Result {
        let pipe = Pipe()
        return collect(from: pipe, timeout: timeout, maxOutputBytes: maxOutputBytes) { finished in
            defer { try? pipe.fileHandleForWriting.close() }
            let pid = try spawnInNewSession(path, arguments, environment: environment,
                                            output: pipe.fileHandleForWriting.fileDescriptor)
            let exitStatus = BoundedExitStatus()
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: exitQueue)
            source.setEventHandler {
                var raw: Int32 = 0
                while waitpid(pid, &raw, 0) == -1 && errno == EINTR {}
                exitStatus.raw = raw
                source.cancel()
                finished.signal()
            }
            source.resume()
            return BoundedChild(pid: pid,
                // This child owns its process group. Stop shell descendants
                // too, so a slow startup helper does not outlive a timeout.
                terminate: { kill(-pid, SIGTERM) },
                status: {
                    let signal = exitStatus.raw & 0x7f
                    return signal == 0 ? (exitStatus.raw >> 8) & 0xff : signal
                })
        }
    }

    private static let exitQueue = DispatchQueue(label: "com.ryzenstatus.bounded-process-exit")

    private static func collect(from pipe: Pipe, timeout: TimeInterval, maxOutputBytes: Int,
                                launch: (DispatchSemaphore) throws -> BoundedChild) -> Result {
        let output = BoundedProcessOutput(limit: maxOutputBytes)
        let drained = DispatchSemaphore(value: 0)
        let reader = pipe.fileHandleForReading
        reader.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { drained.signal() }
            else { output.append(chunk) }
        }
        let finished = DispatchSemaphore(value: 0)
        let child: BoundedChild
        do { child = try launch(finished) }
        catch {
            reader.readabilityHandler = nil
            try? reader.close()
            try? pipe.fileHandleForWriting.close()
            return Result(status: -1, output: Data(), timedOut: false)
        }
        let boundedTimeout = timeout.isFinite ? max(0, timeout) : 0
        var didFinish = finished.wait(timeout: .now() + boundedTimeout) == .success
        let timedOut = !didFinish
        if timedOut {
            child.terminate()
            didFinish = finished.wait(timeout: .now() + 0.5) == .success
            if !didFinish {
                kill(child.pid, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.5)
            }
        }
        // A descendant may retain stdout; never leave its reader alive forever.
        _ = drained.wait(timeout: .now() + 0.2)
        reader.readabilityHandler = nil
        try? reader.close()
        return Result(status: timedOut ? -1 : child.status(), output: output.value(), timedOut: timedOut)
    }

    private static func spawnInNewSession(_ path: String, _ arguments: [String],
                                          environment: [String: String]?, output: Int32) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else { throw POSIXError(.ENOMEM) }
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT
                                                    | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        sigdelset(&defaultSignals, SIGKILL)
        sigdelset(&defaultSignals, SIGSTOP)
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw POSIXError(.ENOMEM) }
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, output, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, output, STDERR_FILENO)
        let argv = ([path] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let envp = (environment ?? ProcessInfo.processInfo.environment)
            .map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { envp.forEach { free($0) } }
        var pid: pid_t = 0
        let error = posix_spawn(&pid, path, &actions, &attributes, argv, envp)
        guard error == 0 else { throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EINVAL) }
        return pid
    }
}
