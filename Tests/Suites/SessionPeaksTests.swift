// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The panel's session lowest and highest readings: what counts as a
/// reading, how the ranges widen, the fastest fan, Reset and the text.
enum SessionPeaksTests {
    static func run(_ suite: TestSuite) {
        ranges(suite)
        skippedReadings(suite)
        fans(suite)
        reset(suite)
        text(suite)
        strings(suite)
    }

    private static let start = Date(timeIntervalSince1970: 1_790_000_000)

    private static func fan(_ id: Int, _ rpm: UInt64, valid: Bool = true, hidden: Bool = false) -> FanState {
        FanState(id: id, name: "Fan \(id)", rpm: rpm, throttlePWM: 0, isKextAuto: true,
                 controlMode: .auto, isHidden: hidden, rpmValid: valid)
    }

    private static func ranges(_ suite: TestSuite) {
        var peaks = SessionPeaks(startedAt: start)
        suite.expect(peaks.isEmpty && peaks.startedAt == start, "a new session holds nothing")
        peaks.record(temperatureC: 50, powerW: 40, clockGHz: 3.6)
        suite.expect(peaks.temperature == SessionRange(min: 50, max: 50), "the first reading is both ends")
        peaks.record(temperatureC: 72, powerW: 25, clockGHz: 4.8)
        peaks.record(temperatureC: 61, powerW: 30, clockGHz: 4.1)
        suite.expect(peaks.temperature == SessionRange(min: 50, max: 72), "temperature widens up")
        suite.expect(peaks.power == SessionRange(min: 25, max: 40), "power widens down")
        suite.expect(peaks.clock == SessionRange(min: 3.6, max: 4.8), "a reading inside the range changes nothing")
        suite.expect(peaks.fan == nil, "no fan reading, no fan range")
    }

    private static func skippedReadings(_ suite: TestSuite) {
        var peaks = SessionPeaks(startedAt: start)
        peaks.record(temperatureC: nil, powerW: 0, clockGHz: .nan)
        suite.expect(peaks.isEmpty, "missing, zero and NaN readings are skipped")
        peaks.record(temperatureC: 45, powerW: 20, clockGHz: 3)
        peaks.record(temperatureC: 0, powerW: -1, clockGHz: .infinity)
        suite.expect(peaks.temperature?.min == 45 && peaks.power?.min == 20 && peaks.clock?.max == 3,
                     "a zero, negative or infinite reading never becomes an end")
        suite.expect(SessionPeaks.usable(12.5) == 12.5 && SessionPeaks.usable(0) == nil, "usable keeps positives only")
        glitches(suite)
    }

    /// One bad read must never become an end of the range for good.
    private static func glitches(_ suite: TestSuite) {
        var peaks = SessionPeaks(startedAt: start)
        peaks.record(temperatureC: 55, powerW: 60, clockGHz: 4.2)
        peaks.record(temperatureC: 200, powerW: 4_096, clockGHz: 50)
        suite.expect(peaks.temperature?.max == 55 && peaks.power?.max == 60 && peaks.clock?.max == 4.2,
                     "impossible temperature, power and clock reads are dropped")
        peaks.record(fanRPM: 1_200)
        peaks.record(fanRPM: 65_535)
        suite.expect(peaks.fan == SessionRange(min: 1_200, max: 1_200), "a 65535 RPM tachometer glitch is dropped")

        func core(_ id: Int, _ mhz: Float, logical: Bool = false) -> CoreSnapshot {
            CoreSnapshot(id: id, freqMHz: mhz, loadPct: 0, isLogical: logical)
        }
        let partial = [core(0, 3_600), core(1, 0), core(2, 0), core(3, 0), core(4, 4_800, logical: true)]
        suite.expect(SessionPeaks.averageClockGHz(partial) == 3.6,
                     "cores reading 0 MHz and logical CPUs stay out of the average")
        suite.expect(SessionPeaks.averageClockGHz([core(0, 0)]) == nil, "no core with a clock, no reading")
    }

    private static func fans(_ suite: TestSuite) {
        suite.expect(SessionPeaks.fastestFanRPM([]) == nil, "no fans, no reading")
        suite.expect(SessionPeaks.fastestFanRPM([fan(0, 900), fan(1, 1400), fan(2, 700)]) == 1400,
                     "the fastest fan is the reading")
        suite.expect(SessionPeaks.fastestFanRPM([fan(0, 900), fan(1, 5000, valid: false)]) == 900,
                     "an untrusted tachometer is left out")
        suite.expect(SessionPeaks.fastestFanRPM([fan(0, 900), fan(1, 2000, hidden: true)]) == 900,
                     "a fan the user hid is left out")
        suite.expect(SessionPeaks.fastestFanRPM([fan(0, 3000, valid: false)]) == nil,
                     "only untrusted fans read as no fan")
        suite.expect(SessionPeaks.fastestFanRPM([fan(0, 0)]) == 0, "a stopped fan that reports reads zero")

        var peaks = SessionPeaks(startedAt: start)
        peaks.record(fanRPM: nil)
        suite.expect(peaks.fan == nil, "no reported fan leaves the range empty")
        peaks.record(fanRPM: 1200)
        peaks.record(fanRPM: 0)
        suite.expect(peaks.fan == SessionRange(min: 0, max: 1200), "a reported zero is a real minimum")
        peaks.record(fanRPM: nil)
        peaks.record(fanRPM: -5)
        suite.expect(peaks.fan == SessionRange(min: 0, max: 1200), "a missing or negative fan reading is skipped")
    }

    private static func reset(_ suite: TestSuite) {
        var peaks = SessionPeaks(startedAt: start)
        peaks.record(temperatureC: 80, powerW: 120, clockGHz: 4.9)
        peaks.record(fanRPM: 1500)
        let later = start.addingTimeInterval(3600)
        peaks.reset(at: later)
        suite.expect(peaks.isEmpty && peaks.startedAt == later, "Reset forgets everything and restarts the clock")
        peaks.record(temperatureC: 40, powerW: nil, clockGHz: nil)
        suite.expect(peaks.temperature == SessionRange(min: 40, max: 40), "after Reset the old peak is gone")
    }

    private static func text(_ suite: TestSuite) {
        suite.expect(SessionPeaks.rangeText(nil) { "\($0)" } == "—", "an empty range reads as a dash")
        let range = SessionRange(min: 41, max: 78)
        suite.expect(SessionPeaks.rangeText(range) { MetricFormat.temperature($0, unit: .celsius) } == "41 °C – 78 °C",
                     "the range reads lowest to highest")
        suite.expect(SessionPeaks.rangeText(range) { MetricFormat.temperature($0, unit: .fahrenheit) } == "106 °F – 172 °F",
                     "the range follows the temperature unit")
    }

    private static func strings(_ suite: TestSuite) {
        var seen = Set<String>()
        for language in AppLanguage.allCases {
            let text = FeatureStrings.sessionPeaks(language)
            let fields = [text.temperature, text.power, text.clock, text.fan, text.reset, text.resetHelp]
            suite.expect(!fields.contains(where: \.isEmpty), "\(language.rawValue): every session string is filled")
            suite.expect(text.sinceFormat.components(separatedBy: "%@").count == 2
                             && !text.sinceFormat.contains("%d"),
                         "\(language.rawValue): the start line takes the time once")
            suite.expect(text.since("21:04").contains("21:04"), "\(language.rawValue): the start line shows the time")
            if language != .enUS { seen.insert(text.resetHelp) }
        }
        suite.expect(!seen.contains(FeatureStrings.sessionPeaks(.enUS).resetHelp),
                     "no language copies the English Reset help")
    }
}
