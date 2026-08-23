// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Decides whether a music-app launch was caused by a media key. The system
/// launches that app on play, next, previous, fast-forward and rewind when no
/// other player is around; a recent press of one of those keys is what the
/// blocker is for. Opening the app from the Dock, Spotlight or a double-click
/// has no such press, so it must be left alone.
///
/// This support type contains only pure decision logic (no timers, no observers)
/// so it can be unit-tested without any OS integration. The media key tap and
/// the timestamp are owned by `MusicLaunchBlocker`.
enum MusicLaunchSupport {
    static let systemDefinedEventTypeRawValue: UInt32 = 14
    static let auxiliaryControlButtonsSubtype = 8
    static let keyDownState = 10
    /// Launch Services needs a moment after the key to start the app.
    static let launchArmWindow: TimeInterval = 2.0

    static let playPauseKeyCode: UInt16 = 16
    static let nextTrackKeyCode: UInt16 = 17
    static let previousTrackKeyCode: UInt16 = 18
    static let fastForwardKeyCode: UInt16 = 19
    static let rewindKeyCode: UInt16 = 20

    static let musicLaunchKeyCodes: Set<UInt16> = [
        playPauseKeyCode, nextTrackKeyCode, previousTrackKeyCode,
        fastForwardKeyCode, rewindKeyCode,
    ]

    /// True for the key-down of a media key that would otherwise open the
    /// music app. Releases, auto-repeat and volume or brightness keys do not
    /// count, so those never arm the blocker.
    static func isMusicLaunchTrigger(subtype: Int, data1: Int) -> Bool {
        guard subtype == auxiliaryControlButtonsSubtype else { return false }
        let raw = UInt32(truncatingIfNeeded: data1)
        let state = Int((raw >> 8) & 0xFF)
        guard state == keyDownState, (raw & 0x1) == 0 else { return false }
        let keyCode = UInt16((raw >> 16) & 0xFFFF)
        return musicLaunchKeyCodes.contains(keyCode)
    }

    /// Returns true when the music app should be blocked. A launch is only
    /// blocked when it falls within `launchArmWindow` seconds of a media-key
    /// press. Launches from the Dock, Spotlight or a double-click have no
    /// such press and must pass through.
    static func shouldBlockLaunch(now: TimeInterval, lastTriggerAt: TimeInterval?) -> Bool {
        guard let lastTriggerAt else { return false }
        return now - lastTriggerAt <= launchArmWindow
    }
}
