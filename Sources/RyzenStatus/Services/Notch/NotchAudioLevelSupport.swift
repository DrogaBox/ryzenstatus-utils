// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The arithmetic behind the island's live music bars, kept free of Core
/// Audio so the tests can exercise it: which spectrum bins form each band,
/// how a band's energy becomes a bar height, and how heights move over time.
enum NotchAudioLevelSupport {
    static let bandCount = 7
    /// Band edges in hertz, roughly a third of an octave apart from the bass
    /// up to the air, which is what a seven-bar meter usually shows.
    static let bandEdgesHz: [Double] = [50, 120, 250, 500, 1000, 2000, 4500, 12_000]
    /// The finer spectrum the island's visualizer draws, mirrored around its
    /// middle: ten bands from the bass to the treble, each edge about 1.7
    /// times the last, which keeps every band on spectrum bins of its own.
    static let spectrumEdgesHz: [Double] = [60, 105, 180, 310, 530, 920, 1600, 2700, 4700, 8100, 14_000]
    static var spectrumBandCount: Int { spectrumEdgesHz.count - 1 }
    /// Levels below this many decibels under full scale read as silence.
    static let floorDecibels = 60.0
    /// Updates per second. Enough for motion, few enough to stay cheap.
    static let updatesPerSecond = 30.0
    static let silenceGrace = 8.0
    static let processSettle = 0.25

    static func fallsBack(heard: Bool, elapsed: TimeInterval) -> Bool {
        !heard && elapsed >= silenceGrace
    }

    /// What a change in the player's audio processes asks of its tap.
    enum TapChange: Equatable {
        case none
        case rebuild
        case restart
    }

    static func tapChange<Process: Hashable>(tapped: Set<Process>, current: Set<Process>) -> TapChange {
        if current == tapped { return .none }
        if !tapped.isSubset(of: current) { return .restart }
        return .rebuild
    }

    /// Remembers the single play a silent tap was given up on.
    struct SilentFallbackRecord: Equatable {
        let pid: Int32
        let bundle: String?
        let title: String?
        let artist: String?

        func matches(pid: Int32, bundle: String?, title: String?, artist: String?) -> Bool {
            self.pid == pid && self.bundle == bundle && self.title == title && self.artist == artist
        }
    }

    /// Remembers the single play a silent tap was given up on.
    struct SilenceMemory: Equatable {
        private var givenUp: NowPlayingTrackIdentity?

        func reads(_ identity: NowPlayingTrackIdentity) -> Bool { identity != givenUp }
        mutating func giveUp(on identity: NowPlayingTrackIdentity) { givenUp = identity }
        mutating func rearm() { givenUp = nil }
    }

    static var isSupported: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.notchLiveEqualizer)
    }

    /// The bins of a real spectrum with `size / 2` usable bins that belong to
    /// each band. Every band keeps at least one bin, and bin 0, the DC
    /// offset, belongs to none.
    static func bandRanges(sampleRate: Double, size: Int, edges: [Double] = bandEdgesHz) -> [Range<Int>] {
        let usable = max(2, size / 2)
        let binWidth = sampleRate > 0 && size > 0 ? sampleRate / Double(size) : 1
        var ranges: [Range<Int>] = []
        for band in 0..<max(0, edges.count - 1) {
            var lower = Int((edges[band] / binWidth).rounded(.down))
            var upper = Int((edges[band + 1] / binWidth).rounded(.down))
            lower = min(max(lower, 1), usable - 1)
            upper = min(max(upper, lower + 1), usable)
            ranges.append(lower..<upper)
        }
        return ranges
    }

    /// Bin ranges for each band.
    static func bandBins(sampleRate: Double, fftSize: Int) -> [Range<Int>] {
        bandRanges(sampleRate: sampleRate, size: fftSize)
    }

    /// Each band's mean magnitude on a decibel scale with a floor, as a
    /// value from 0 to 1. Magnitudes are relative to full scale.
    static func bandLevels(magnitudes: [Float], bands: [Range<Int>]) -> [Double] {
        bands.map { band in
            let clipped = band.clamped(to: 0..<magnitudes.count)
            guard !clipped.isEmpty else { return 0 }
            var sum: Float = 0
            for bin in clipped { sum += magnitudes[bin] }
            let mean = Double(sum) / Double(clipped.count)
            guard mean > 0 else { return 0 }
            let decibels = 20 * log10(mean)
            return min(1, max(0, (decibels + floorDecibels) / floorDecibels))
        }
    }

    /// Which band a bar reads when there are fewer bars than bands: the bars
    /// sample the bands evenly rather than all crowding into the bass.
    static func barIndex(_ bar: Int, of bars: Int, bands: Int) -> Int {
        guard bars > 0, bands > 0 else { return 0 }
        let position = (Double(bar) + 0.5) / Double(bars) * Double(bands)
        return min(bands - 1, max(0, Int(position.rounded(.down))))
    }

    /// What one reading of the player's sound gives: the bars' few bands
    /// and the visualizer's finer spectrum.
    struct Reading: Equatable {
        var bands: [Double]
        var spectrum: [Double]
    }

    /// How loud the bass is in a spectrum, from 0 to 1: its two lowest bands.
    static func bass(_ spectrum: [Double]?) -> Double {
        guard let spectrum, !spectrum.isEmpty else { return 0 }
        let low = spectrum.prefix(2)
        return min(1, max(0, low.reduce(0, +) / Double(low.count)))
    }

    /// The level each of `bars` mirrored bars shows: the bass in the
    /// middle, the treble at both ends.
    static func mirrored(_ spectrum: [Double], bars: Int) -> [Double] {
        guard bars > 0, !spectrum.isEmpty else { return [] }
        let half = Double(bars) / 2
        return (0..<bars).map { bar in
            let fromMiddle = abs(Double(bar) + 0.5 - half) / half
            let band = min(spectrum.count - 1, Int(fromMiddle * Double(spectrum.count)))
            return spectrum[band]
        }
    }

    /// A peak cap rests on each bar's highest point and sinks slowly after it.
    struct PeakHold {
        static let hold: CFTimeInterval = 0.35
        static let fall = 0.9
        private(set) var peaks: [Double] = []
        private var heldUntil: [CFTimeInterval] = []

        init() {}

        mutating func next(_ levels: [Double], at time: CFTimeInterval, step: Double) -> [Double] {
            if peaks.count != levels.count {
                peaks = levels
                heldUntil = Array(repeating: time + Self.hold, count: levels.count)
                return peaks
            }
            for index in levels.indices {
                if levels[index] >= peaks[index] {
                    peaks[index] = levels[index]
                    heldUntil[index] = time + Self.hold
                } else if time > heldUntil[index] {
                    peaks[index] = max(levels[index], peaks[index] - Self.fall * step)
                }
            }
            return peaks
        }
    }

    /// Bars rise fast and fall slowly, and the loudest band sets the scale so
    /// a quiet album still fills the meter. The scale itself relaxes slowly.
    struct Smoother {
        static let attack = 0.55
        static let decay = 0.12
        static let ceilingDecay = 0.995
        static let peakTarget = 0.92
        private var levels: [Double] = []
        private var ceiling = 0.05

        init() {}

        mutating func next(_ raw: [Double]) -> [Double] {
            if levels.count != raw.count { levels = Array(repeating: 0, count: raw.count) }
            ceiling = max(raw.max() ?? 0, ceiling * Self.ceilingDecay, 0.05)
            let gain = Self.peakTarget / ceiling
            for index in raw.indices {
                let target = min(1, max(0, raw[index] * gain))
                let rate = target > levels[index] ? Self.attack : Self.decay
                levels[index] += (target - levels[index]) * rate
            }
            return levels
        }
    }
}
