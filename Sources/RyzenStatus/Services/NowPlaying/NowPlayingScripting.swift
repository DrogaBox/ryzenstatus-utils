// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import CoreServices
import Foundation

// Generic Apple Event scripting for players outside the AppleScript
// providers (Music, Spotify, Kaset): their own scripting dictionary says
// which playback commands and which shuffle switch they offer, and events
// are addressed to the running process so consent belongs to this app.

/// Apple Events stay in this process so consent belongs to this app. Addressing
/// the running PID cannot fall through to the system's currently playing video.
enum NowPlayingScripting {
    struct Target: Equatable {
        let pid: Int32
        let bundleIdentifier: String
        let bundleURL: URL
        /// Nil when Launch Services did not start the player, as for a process
        /// launchd spawned; the bundle checks still bind the process identity.
        let launched: Date?

        init?(_ playback: NowPlayingPlayback) {
            guard let pid = playback.track.appPID, let bundle = playback.track.appBundleIdentifier,
                  let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
                  app.bundleIdentifier == bundle, let url = app.bundleURL else { return nil }
            self.pid = pid; bundleIdentifier = bundle; bundleURL = url; launched = app.launchDate
        }

        var isCurrent: Bool {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
            return app.bundleIdentifier == bundleIdentifier && app.bundleURL == bundleURL && app.launchDate == launched
        }
    }

    enum Access { case granted, consent, denied, unavailable }
    struct Availability {
        let target: Target
        let capabilities: NowPlayingScriptingCapabilities
        let access: Access
    }

    static func inspect(_ target: Target) -> Availability? {
        guard target.isCurrent, let capabilities = NowPlayingScriptingCapabilities.load(bundleURL: target.bundleURL) else { return nil }
        return Availability(target: target, capabilities: capabilities, access: access(to: target))
    }

    /// The answers of the last few seconds, by process. The system call below
    /// can block for a second or more, and every preference change in the app
    /// asks again, so a recent answer is reused. A new permission shows within
    /// the few seconds it takes to ask again.
    private static let accessLock = NSLock()
    private static var recentAccess: [Int32: (access: Access, at: CFAbsoluteTime)] = [:]
    private static let accessLifetime: CFTimeInterval = 8

    static func access(to target: Target) -> Access {
        guard target.isCurrent else { return .unavailable }
        let now = CFAbsoluteTimeGetCurrent()
        accessLock.lock()
        if let known = recentAccess[target.pid], now - known.at < accessLifetime, known.access != .unavailable {
            accessLock.unlock()
            return known.access
        }
        accessLock.unlock()
        let address = NSAppleEventDescriptor(processIdentifier: target.pid)
        let answer: Access
        switch AEDeterminePermissionToAutomateTarget(address.aeDesc, typeWildCard, typeWildCard, false) {
        case noErr: answer = .granted
        case OSStatus(errAEEventWouldRequireUserConsent): answer = .consent
        case OSStatus(errAEEventNotPermitted): answer = .denied
        default: answer = .unavailable
        }
        accessLock.lock()
        recentAccess[target.pid] = (answer, now)
        if recentAccess.count > 16 { recentAccess = recentAccess.filter { now - $0.value.at < accessLifetime } }
        accessLock.unlock()
        return answer
    }

    /// Forgets the recent answer for `pid`, after the person was asked or
    /// asked to look again, so the next check reads the system's answer.
    static func forgetAccess(for pid: Int32) {
        accessLock.lock()
        recentAccess[pid] = nil
        accessLock.unlock()
    }

    static func event(_ command: NowPlayingTransportCommand, playback: NowPlayingPlayback,
                      capabilities: NowPlayingScriptingCapabilities, pid: Int32) -> NSAppleEventDescriptor? {
        guard pid > 0 else { return nil }
        let address = NSAppleEventDescriptor(processIdentifier: pid)
        if case .seek(let seconds) = command {
            guard seconds.isFinite, (0...604_800).contains(seconds), let position = capabilities.position,
                  let event = propertyEvent(kAESetData, code: position.code, address: address) else { return nil }
            event.setParam(position.integer ? NSAppleEventDescriptor(int32: Int32(seconds.rounded()))
                           : NSAppleEventDescriptor(double: seconds), forKeyword: keyAEData)
            return event
        }
        guard let code = capabilities.event(for: command, isPlaying: playback.isPlaying) else { return nil }
        return NSAppleEventDescriptor(eventClass: code.eventClass, eventID: code.eventID, targetDescriptor: address,
                                      returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    }

    /// Reads the player's shuffle switch with nil, or sets it. Like seeking,
    /// only the property the player's dictionary declares is addressed.
    static func shuffleEvent(_ enabled: Bool?, capabilities: NowPlayingScriptingCapabilities,
                             pid: Int32) -> NSAppleEventDescriptor? {
        guard pid > 0, let shuffle = capabilities.shuffle,
              let event = propertyEvent(enabled == nil ? kAEGetData : kAESetData, code: shuffle,
                                        address: NSAppleEventDescriptor(processIdentifier: pid)) else { return nil }
        if let enabled { event.setParam(NSAppleEventDescriptor(boolean: enabled), forKeyword: keyAEData) }
        return event
    }

    static func shuffleAllowedEvent(capabilities: NowPlayingScriptingCapabilities, pid: Int32) -> NSAppleEventDescriptor? {
        guard pid > 0, let allowed = capabilities.shuffleAllowed else { return nil }
        return propertyEvent(kAEGetData, code: allowed, address: NSAppleEventDescriptor(processIdentifier: pid))
    }

    /// Only a Boolean answer is a state; anything else leaves it unknown.
    static func shuffleState(in reply: NSAppleEventDescriptor) -> Bool? {
        guard let value = reply.paramDescriptor(forKeyword: keyDirectObject),
              [typeTrue, typeFalse, typeBoolean].contains(value.descriptorType) else { return nil }
        return value.booleanValue
    }

    /// Nil when the player cannot be asked or does not answer with a state.
    static func shuffle(of availability: Availability) -> Bool? {
        read(shuffleEvent(nil, capabilities: availability.capabilities, pid: availability.target.pid), from: availability)
    }

    /// False only when the player says the songs playing cannot be shuffled,
    /// as some do for a radio. A player that does not say, or cannot be
    /// asked before consent, keeps the button that asks for it.
    static func shuffleAllowed(by availability: Availability) -> Bool {
        guard availability.capabilities.shuffleAllowed != nil else { return true }
        return read(shuffleAllowedEvent(capabilities: availability.capabilities, pid: availability.target.pid),
                    from: availability) != false
    }

    private static func read(_ event: NSAppleEventDescriptor?, from availability: Availability) -> Bool? {
        guard availability.target.isCurrent, access(to: availability.target) == .granted, let event,
              let reply = try? event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: 1),
              (reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0) == 0 else { return nil }
        return shuffleState(in: reply)
    }

    static func setShuffle(_ enabled: Bool, availability: Availability) -> Bool {
        guard availability.target.isCurrent, access(to: availability.target) == .granted,
              let event = shuffleEvent(enabled, capabilities: availability.capabilities, pid: availability.target.pid),
              let reply = try? event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: 1) else { return false }
        return (reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0) == 0
    }

    /// Gets or sets one property of the application itself.
    private static func propertyEvent(_ eventID: AEEventID, code: UInt32,
                                      address: NSAppleEventDescriptor) -> NSAppleEventDescriptor? {
        let specifier = NSAppleEventDescriptor.record()
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: typeProperty), forKeyword: AEKeyword(keyAEDesiredClass))
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: OSType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: code), forKeyword: AEKeyword(keyAEKeyData))
        specifier.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: AEKeyword(keyAEContainer))
        guard let property = specifier.coerce(toDescriptorType: typeObjectSpecifier) else { return nil }
        let event = NSAppleEventDescriptor(eventClass: kAECoreSuite, eventID: eventID, targetDescriptor: address,
                                           returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(property, forKeyword: keyDirectObject)
        return event
    }

    static func send(_ command: NowPlayingTransportCommand, playback: NowPlayingPlayback, availability: Availability,
                     cancellation: DispatchWorkItem, validatedAt: TimeInterval) -> Bool {
        guard !cancellation.isCancelled, availability.target.isCurrent,
              access(to: availability.target) == .granted,
              let event = event(command, playback: playback, capabilities: availability.capabilities, pid: availability.target.pid),
              !cancellation.isCancelled, availability.target.isCurrent,
              ProcessInfo.processInfo.systemUptime - validatedAt < 0.5 else { return false }
        // A timeout may occur after delivery. Never retry a playback action.
        guard let reply = try? event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: 1) else { return false }
        return (reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0) == 0
    }
}

/// Only the installed dictionary's playback vocabulary is accepted. Event codes
/// are data supplied by that dictionary, never inferred from an application's name.
struct NowPlayingScriptingCapabilities: Equatable {
    struct Event: Equatable { let eventClass: UInt32; let eventID: UInt32 }
    struct Position: Equatable { let code: UInt32; let integer: Bool }
    var commands: [String: Event] = [:]
    var position: Position?
    /// The player's own shuffle switch, a writable Boolean of the application.
    var shuffle: UInt32?
    /// Some players' read-only answer to whether the songs playing can be
    /// shuffled at all. Players that do not declare it always can.
    var shuffleAllowed: UInt32?

    var canToggle: Bool { commands["playpause"] != nil || (commands["play"] != nil && commands["pause"] != nil) }

    /// Starts playback rather than toggling it, unless the dictionary only
    /// declares the toggle.
    var playCommand: Event? { commands["play"] ?? commands["playpause"] }

    func event(for command: NowPlayingTransportCommand, isPlaying: Bool) -> Event? {
        switch command {
        case .toggle: return commands["playpause"] ?? commands[isPlaying ? "pause" : "play"]
        case .next: return commands["next track"]
        case .previous: return commands["previous track"]
        default: return nil
        }
    }

    static func load(bundleURL: URL) -> Self? {
        guard bundleURL.isFileURL, let bundle = Bundle(url: bundleURL),
              let name = bundle.object(forInfoDictionaryKey: "OSAScriptingDefinition") as? String,
              !name.isEmpty, name.utf8.count <= 255, !name.contains("/"), !name.contains("\\"),
              let resources = bundle.resourceURL,
              let url = bundle.url(forResource: name.hasSuffix(".sdef") ? String(name.dropLast(5)) : name, withExtension: "sdef") else { return nil }
        var relationship = FileManager.URLRelationship.other
        guard (try? FileManager.default.getRelationship(&relationship,
            ofDirectoryAt: resources.resolvingSymlinksInPath(), toItemAt: url.resolvingSymlinksInPath())) != nil,
              relationship == .contains, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maximumBytes + 1) else { return nil }
        return parse(data)
    }

    static let maximumBytes = 256 * 1024

    static func parse(_ data: Data) -> Self? {
        guard data.count <= maximumBytes else { return nil }
        let reader = MusicDictionaryReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = reader
        guard parser.parse(), reader.isDictionary,
              !reader.result.commands.isEmpty || reader.result.position != nil else { return nil }
        return reader.result
    }
}

private final class MusicDictionaryReader: NSObject, XMLParserDelegate {
    var result = NowPlayingScriptingCapabilities()
    var isDictionary = false
    private var path: [String] = []
    private var elements = 0
    private var applicationDepth: Int?
    private var command: (name: String, event: NowPlayingScriptingCapabilities.Event, valid: Bool)?
    private var seenCommands = Set<String>()
    private var seenPosition = false
    private var seenShuffle = false
    private var seenShuffleAllowed = false
    private let names: Set<String> = ["playpause", "play", "pause", "next track", "previous track"]
    /// Players call it "shuffling" or "shuffle enabled". A read-only
    /// "shuffling enabled" says whether shuffle is offered at all.
    private let shuffleNames: Set<String> = ["shuffling", "shuffle enabled"]

    private func code(_ value: String?) -> UInt32? {
        guard let value, value.utf8.count == 4,
              value.utf8.allSatisfy({ (0x20...0x7E).contains($0) }) else { return nil }
        return value.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        elements += 1
        path.append(element)
        guard path.count <= 24, elements <= 4096, attributes.count <= 32 else { parser.abortParsing(); return }
        if path.count == 1 { isDictionary = element == "dictionary" }
        if path.count == 3, path.prefix(2).elementsEqual(["dictionary", "suite"]),
           (element == "class" && attributes["name"] == "application")
            || (element == "class-extension" && attributes["extends"] == "application") {
            applicationDepth = path.count
        }
        if element == "command", path == ["dictionary", "suite", "command"],
           let name = attributes["name"], names.contains(name) {
            guard let raw = attributes["code"], raw.utf8.count == 8,
                  let eventClass = code(String(raw.prefix(4))), let eventID = code(String(raw.suffix(4))) else {
                seenCommands.insert(name); result.commands[name] = nil; return
            }
            command = (name, .init(eventClass: eventClass, eventID: eventID), true)
        }
        if command != nil, element == "direct-parameter" || element == "parameter",
           attributes["optional"] != "yes" { command?.valid = false }
        if element == "property", attributes["name"] == "player position",
           let depth = applicationDepth, path.count == depth + 1 {
            defer { seenPosition = true }
            guard !seenPosition, attributes["access"] == nil || ["w", "rw"].contains(attributes["access"] ?? ""),
                  let property = code(attributes["code"]), let type = attributes["type"],
                  type == "real" || type == "integer" else { result.position = nil; return }
            result.position = .init(code: property, integer: type == "integer")
        }
        if element == "property", let name = attributes["name"], shuffleNames.contains(name),
           let depth = applicationDepth, path.count == depth + 1 {
            defer { seenShuffle = true }
            guard !seenShuffle, attributes["access"] == nil || attributes["access"] == "rw",
                  let property = code(attributes["code"]), attributes["type"] == "boolean" else { result.shuffle = nil; return }
            result.shuffle = property
        }
        if element == "property", attributes["name"] == "shuffling enabled",
           let depth = applicationDepth, path.count == depth + 1 {
            defer { seenShuffleAllowed = true }
            guard !seenShuffleAllowed, let property = code(attributes["code"]),
                  attributes["type"] == "boolean" else { result.shuffleAllowed = nil; return }
            result.shuffleAllowed = property
        }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == "command", let command {
            if !seenCommands.insert(command.name).inserted { result.commands[command.name] = nil }
            else if command.valid { result.commands[command.name] = command.event }
            self.command = nil
        }
        if applicationDepth == path.count { applicationDepth = nil }
        path.removeLast()
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { parser.abortParsing() }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { parser.abortParsing() }
}
