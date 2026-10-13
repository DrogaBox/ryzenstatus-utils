// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// What the closed island's middle shows while a song plays: its name, or
/// its name for a few seconds and then bars moving with the music.
enum NotchMusicVisualizerMode: String, CaseIterable, Identifiable {
    case title
    case titleThenVisualizer
    case visualizer

    var id: String { rawValue }

    static func current(in defaults: UserDefaults = .standard) -> NotchMusicVisualizerMode {
        NotchMusicVisualizerMode(rawValue: defaults.string(forKey: DefaultsKey.notchMusicVisualizer) ?? "")
            ?? .titleThenVisualizer
    }
}

/// The rules behind the visualizer, kept pure so the tests cover them.
enum NotchMusicVisualizerSupport {
    /// How long a new song's name can stay before the bars take over.
    static let titleSecondsChoices = [3, 5, 10]
    static let defaultTitleSeconds = 5

    /// Mirrored bars: ten bands, bass in the middle, treble at both ends.
    static let barCount = 20
    static let barWidth: CGFloat = 3
    static let barGap: CGFloat = 1.8
    static var width: CGFloat { CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap }

    static func titleSeconds(in defaults: UserDefaults = .standard) -> TimeInterval {
        let stored = defaults.integer(forKey: DefaultsKey.notchMusicTitleSeconds)
        return TimeInterval(titleSecondsChoices.contains(stored) ? stored : defaultTitleSeconds)
    }

    /// Whether a new song's name shows at all before the bars.
    static func namesNewSong(_ mode: NotchMusicVisualizerMode) -> Bool { mode != .visualizer }

    /// Whether the middle shows the bars: a mode with them, a song playing,
    /// its name not asked for, and motion allowed.
    static func shows(mode: NotchMusicVisualizerMode, named: Bool, playing: Bool, reduceMotion: Bool) -> Bool {
        mode != .title && playing && !named && !reduceMotion
    }

    /// Whether the name shows because the song is paused: with a visualizer
    /// mode a paused song is named instead of keeping still bars.
    static func namesPaused(mode: NotchMusicVisualizerMode, playing: Bool) -> Bool {
        mode != .title && !playing
    }

    static func companionDances(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.notchMascotDances)
    }
}
