// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Carbon.HIToolbox
import Foundation

/// One Carbon global hotkey with the register/unregister lifecycle the quick
/// tools share. A single process-wide event handler routes presses to the
/// owning instance by id, so each tool stays a few lines.
final class QuickToolHotkey {
    private static var instances: [UInt32: QuickToolHotkey] = [:]
    private static var sharedHandler: EventHandlerRef?

    /// Unregisters every active QuickToolHotkey across the app. Called during
    /// shortcut capture so the field records the user's intended combination
    /// instead of firing a tool.
    static func unregisterAll() {
        for instance in instances.values {
            instance.unregister()
        }
    }

    private let hotKeyID: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var registeredShortcut: GlobalShortcut?
    var onPress: (() -> Void)?

    init(id: UInt32) {
        hotKeyID = id
    }

    /// Applies the wanted state; returns false when macOS refused the
    /// registration (combination taken by another app).
    ///
    /// `storageKey` is the defaults key the combination lives under. Upstream
    /// makes it required and hands it to `SystemShortcutTakeover`, which
    /// switches macOS symbolic hotkeys off while a tool holds the same keys.
    /// That take-over is not ported to this fork (it rewrites WindowServer
    /// preferences), so the key is accepted for call-site parity and unused;
    /// it stays optional so tools without an upstream counterpart need not
    /// pass one.
    @discardableResult
    func sync(enabled: Bool, shortcut: GlobalShortcut, storageKey: String? = nil) -> Bool {
        guard enabled else {
            unregister()
            return true
        }
        if hotKeyRef != nil, registeredShortcut == shortcut {
            return true
        }
        unregister()
        Self.installSharedHandlerIfNeeded()
        Self.instances[hotKeyID] = self
        let id = EventHotKeyID(signature: 0x5655_5154, id: hotKeyID) // 'VUQT'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.carbonKeyCode,
                                         shortcut.carbonModifiers,
                                         id, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            registeredShortcut = nil
            return false
        }
        hotKeyRef = ref
        registeredShortcut = shortcut
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        registeredShortcut = nil
        Self.instances.removeValue(forKey: hotKeyID)
    }

    private static func installSharedHandlerIfNeeded() {
        guard sharedHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            if let event {
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &id)
            }
            guard id.signature == 0x5655_5154,
                  let instance = QuickToolHotkey.instances[id.id]
            else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { instance.onPress?() }
            return noErr
        }, 1, &spec, nil, &sharedHandler)
    }
}
