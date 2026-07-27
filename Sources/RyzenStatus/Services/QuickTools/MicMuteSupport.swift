// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The decisions behind a global microphone mute, kept apart from the audio
/// calls so they can be pinned down by tests: which devices the mute has to
/// reach, which ones it must never touch, and how a device gets its level back.
enum MicMuteSupport {
    /// The app's own private mixing device. It carries a tapped app's audio,
    /// not a microphone, and muting it would silence the very thing the mixer
    /// is rendering.
    static let ownDeviceName = "RyzenStatus Mixer"

    /// The level a device falls back to when nothing was ever saved for it:
    /// loud enough to be usable, quiet enough not to startle.
    static let fallbackVolume: Float = 0.75

    static func isOwnDevice(name: String) -> Bool {
        name == ownDeviceName
    }

    /// A level worth remembering. Saving a zero would make the unmute restore
    /// silence, which is how a re-applied mute could strand a microphone.
    static func shouldSaveVolume(_ volume: Float?) -> Bool {
        guard let volume else { return false }
        return volume > 0.01
    }

    static func volumeToRestore(uid: String,
                                saved: [String: Double],
                                legacy: Double) -> Float {
        if let value = saved[uid], value > 0.01 { return Float(value) }
        if legacy > 0.01 { return Float(legacy) }
        return fallbackVolume
    }

    /// Which devices an unmute has to touch. Normally only the ones this app
    /// muted, so a microphone the user silenced in System Settings stays
    /// silenced. With nothing recorded (settings restored onto another Mac, or
    /// a state from before this was tracked) every present device is restored:
    /// leaving someone muted with no way back is the worse failure.
    static func restoreTargets(recorded: [String], present: [String]) -> [String] {
        guard !recorded.isEmpty else { return present }
        let wanted = Set(recorded)
        return present.filter { wanted.contains($0) }
    }
}
