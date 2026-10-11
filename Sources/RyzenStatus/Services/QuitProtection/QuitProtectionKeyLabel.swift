// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Carbon.HIToolbox

/// What the current keyboard layout's Command table types on a key.
///
/// macOS resolves Command-Q and Command-W through that table, and it differs
/// from the bare one on every layout that types a non-Latin script: on Russian
/// and on Greek the key at keycode 12 types something else bare and still
/// answers Command-Q. Quit Protection asks this before the bare character, so
/// it guards the key that really quits.
///
/// Main thread only: deriving a label asks Text Input Services, which traps
/// the process off it. The service's tap runs on the main run loop. Answers
/// are cached per key until the selected input source changes.
enum QuitProtectionKeyLabel {
    private static var cache: [Int64: String?] = [:]
    private static var layoutObserver: NSObjectProtocol?

    static func commandLabel(for keyCode: Int64) -> String? {
        guard Thread.isMainThread else { return nil }
        observeLayoutChangesIfNeeded()
        if let cached = cache[keyCode] { return cached }
        let label = derivedCommandLabel(for: keyCode)
        cache[keyCode] = label
        return label
    }

    private static func observeLayoutChangesIfNeeded() {
        guard layoutObserver == nil else { return }
        layoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            cache.removeAll()
        }
    }

    private static func derivedCommandLabel(for keyCode: Int64) -> String? {
        guard let code = UInt16(exactly: keyCode),
              let layoutData = currentLayoutData()
        else { return nil }
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        // UCKeyTranslate wants the modifier state shifted down out of the
        // Carbon event's high byte.
        let modifierState = UInt32((cmdKey >> 8) & 0xFF)
        let status = layoutData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> OSStatus in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress
            else { return OSStatus(paramErr) }
            return UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), modifierState,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let label = String(utf16CodeUnits: chars, count: length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.count == 1,
              let scalar = label.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar)
        else { return nil }
        return label
    }

    /// An input method answers the current-layout call with the companion
    /// layout it types through; the ASCII capable layout under it is the
    /// physical keyboard. A plain layout is asked directly.
    private static func currentLayoutData() -> Data? {
        let source = inputMethodIsActive
            ? TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
            : TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        guard let source,
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        return Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
    }

    private static var inputMethodIsActive: Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let type = TISGetInputSourceProperty(source, kTISPropertyInputSourceType)
        else { return false }
        let value = Unmanaged<CFString>.fromOpaque(type).takeUnretainedValue() as String
        return value != (kTISTypeKeyboardLayout as String)
    }
}
