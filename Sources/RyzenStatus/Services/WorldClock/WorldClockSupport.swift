// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The cities chosen for the world clocks and the arithmetic their rows need.
/// Pure and injectable so the harness can check it with fixed dates.
enum WorldClockSupport {
    static let maxClocks = 12

    /// The saved time zone identifiers, in order, without unknown or repeated
    /// ones and at most `maxClocks`.
    static func zones(from stored: String?) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for part in (stored ?? "").split(separator: ",") {
            let identifier = part.trimmingCharacters(in: .whitespaces)
            guard TimeZone(identifier: identifier) != nil, seen.insert(identifier).inserted else { continue }
            result.append(identifier)
            if result.count == maxClocks { break }
        }
        return result
    }

    static func stored(_ zones: [String]) -> String {
        zones.joined(separator: ",")
    }

    /// The city part of an identifier: "America/Argentina/Buenos_Aires" →
    /// "Buenos Aires", "UTC" → "UTC".
    static func cityName(_ identifier: String) -> String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// Clocks west to east, so the list reads like a map; ties by city.
    static func sorted(_ zones: [String], at date: Date) -> [String] {
        zones.sorted { lhs, rhs in
            let left = TimeZone(identifier: lhs)?.secondsFromGMT(for: date) ?? 0
            let right = TimeZone(identifier: rhs)?.secondsFromGMT(for: date) ?? 0
            if left != right { return left < right }
            return cityName(lhs).localizedStandardCompare(cityName(rhs)) == .orderedAscending
        }
    }

    /// Hours ahead of (or behind) the Mac's zone: "+5 h", "−3:30 h", "+0 h".
    static func offsetLabel(seconds: Int) -> String {
        let sign = seconds < 0 ? "−" : "+"
        let minutes = abs(seconds) / 60
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(sign)\(hours) h" : String(format: "%@%d:%02d h", sign, hours, rest)
    }

    /// -1, 0 or +1: the calendar day in `zone` against the day in `local`.
    static func dayShift(at date: Date, zone: TimeZone, local: TimeZone) -> Int {
        func dayNumber(_ timeZone: TimeZone) -> Int {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            guard let day = utc.date(from: parts) else { return 0 }
            return Int((day.timeIntervalSince1970 / 86_400).rounded(.down))
        }
        return max(-1, min(1, dayNumber(zone) - dayNumber(local)))
    }

    /// Whether it is daytime there, roughly: from six in the morning to six in
    /// the evening.
    static func isDaytime(at date: Date, zone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return (6..<18).contains(calendar.component(.hour, from: date))
    }

    /// Time zones whose city, identifier or localized name contain `query`,
    /// ignoring case and accents; the chosen ones are left out.
    static func matches(_ query: String, excluding chosen: [String], locale: Locale,
                        limit: Int = 40) -> [String] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let excluded = Set(chosen)
        var result: [String] = []
        for identifier in TimeZone.knownTimeZoneIdentifiers where !excluded.contains(identifier) {
            let localized = TimeZone(identifier: identifier)?.localizedName(for: .generic, locale: locale) ?? ""
            if cityName(identifier).range(of: needle, options: options) != nil
                || identifier.range(of: needle, options: options) != nil
                || localized.range(of: needle, options: options) != nil {
                result.append(identifier)
                if result.count == limit { break }
            }
        }
        return result.sorted { cityName($0).localizedStandardCompare(cityName($1)) == .orderedAscending }
    }
}
