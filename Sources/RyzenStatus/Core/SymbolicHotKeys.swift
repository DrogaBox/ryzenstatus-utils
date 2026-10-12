// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Darwin
import Foundation

/// One row of the WindowServer's symbolic hotkey table as it stands right now.
struct LiveSystemShortcut: Equatable {
    let id: Int32
    let shortcut: GlobalShortcut
    let enabled: Bool
    let requiresFunctionKey: Bool

    init(id: Int32, shortcut: GlobalShortcut, enabled: Bool,
         requiresFunctionKey: Bool = false) {
        self.id = id
        self.shortcut = shortcut
        self.enabled = enabled
        self.requiresFunctionKey = requiresFunctionKey
    }

    init(id: Int32, keyCode: Int64, flags: CGEventFlags, enabled: Bool) {
        self.init(id: id, shortcut: GlobalShortcut(keyCode: keyCode,
                                                   modifiers: GlobalShortcutModifiers(cgFlags: flags)),
                  enabled: enabled, requiresFunctionKey: flags.contains(.maskSecondaryFn))
    }
}

/// The WindowServer's own shortcut table, reached through the same private
/// SkyLight calls the App Switcher's take-over uses. Every symbol is resolved
/// at runtime and every reader tolerates its absence, so a macOS that drops
/// them leaves the app on its plist fallback rather than crashing.
enum SymbolicHotKeys {
    typealias SetEnabledFunction = @convention(c) (Int32, Bool) -> CGError
    typealias IsEnabledFunction = @convention(c) (Int32) -> Bool
    typealias GetValueFunction =
        @convention(c) (Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>) -> CGError

    /// Writes go through `SystemShortcutTakeover.apply`, which owns the
    /// write-ahead marker and the restore-after-crash bookkeeping. Nothing
    /// else should call this directly.
    static let setEnabled: SetEnabledFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSetSymbolicHotKeyEnabled") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SetEnabledFunction.self)
    }()
    static let isEnabled: IsEnabledFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSIsSymbolicHotKeyEnabled") else {
            return nil
        }
        return unsafeBitCast(symbol, to: IsEnabledFunction.self)
    }()
    static let getValue: GetValueFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSGetSymbolicHotKeyValue") else {
            return nil
        }
        return unsafeBitCast(symbol, to: GetValueFunction.self)
    }()

    /// macOS 26 populates ids up to 255; scanning the headroom costs a few
    /// milliseconds of WindowServer round trips per full read, which the
    /// recorder pays on a save, and spares a hardcoded ceiling.
    static let scanRange: Range<Int32> = 0..<512

    /// The key code an entry carries when no key is assigned to it.
    static let unassignedKeyCode: UInt32 = 0xFFFF

    /// Every populated row, read fresh: System Settings can change the table
    /// while a shortcut field is open. `nil` when the private calls are gone.
    /// A caller that already knows its ids should use `entries(for:)` instead
    /// of paying for the whole scan.
    static func liveEntries() -> [LiveSystemShortcut]? {
        guard let getValue, let isEnabled else { return nil }
        return scanRange.compactMap { entry(id: $0, getValue: getValue, isEnabled: isEnabled) }
    }

    /// The rows for a known set of ids, in the same shape as `liveEntries()`,
    /// at one round trip per id instead of one per possible id.
    static func entries(for ids: Set<Int32>) -> [LiveSystemShortcut]? {
        guard let getValue, let isEnabled else { return nil }
        return ids.sorted().compactMap { entry(id: $0, getValue: getValue, isEnabled: isEnabled) }
    }

    private static func entry(id: Int32, getValue: GetValueFunction,
                              isEnabled: IsEnabledFunction) -> LiveSystemShortcut? {
        var character: UInt32 = 0
        var keyCode: UInt32 = 0
        var modifiers: UInt32 = 0
        guard getValue(id, &character, &keyCode, &modifiers) == .success,
              keyCode != unassignedKeyCode else { return nil }
        let flags = SpaceHopSupport.eventFlags(fromCarbonModifiers: modifiers)
        return LiveSystemShortcut(
            id: id, keyCode: Int64(keyCode), flags: flags, enabled: isEnabled(id))
    }
}

/// WindowServer identifiers for the app and window switcher actions. Read
/// them from the table, not from memory: 28 is "save picture of screen as a
/// file", and mapping the reverse window key there once let a switcher
/// shortcut on the 3 key switch the macOS screenshot key off.
/// RyzenStatus keeps this enum here rather than in `SwitcherSupport.swift`
/// (upstream's home for it): `GlobalShortcut` reads it, and the command bar
/// harness compiles `GlobalShortcut` without the switcher.
enum SwitcherNativeSymbolicHotKey: Int32, CaseIterable, Hashable {
    case commandTab = 1
    case commandShiftTab = 2
    case nextWindow = 27
    case previousWindow = 220

    /// The ids the switcher ever asks the WindowServer about.
    static let ids = Set(allCases.map(\.rawValue))
}
