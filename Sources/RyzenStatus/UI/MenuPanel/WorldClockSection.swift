// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// World clocks tab in the menu panel: one row per chosen city, west to east.
struct WorldClockSection: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.worldClockZones) private var storedZones = ""
    var collapsible = true

    private var text: WorldClockStrings { FeatureStrings.worldClock(l10n.language) }

    var body: some View {
        PanelSection(.worldClock, title: text.pageTitle, collapsible: collapsible) {
            // A minute is the finest the rows show, so that is how often they redraw.
            TimelineView(.everyMinute) { context in
                let zones = WorldClockSupport.sorted(WorldClockSupport.zones(from: storedZones), at: context.date)
                VStack(alignment: .leading, spacing: 8) {
                    if zones.isEmpty {
                        Text(text.emptyHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(zones, id: \.self) { identifier in
                            if let zone = TimeZone(identifier: identifier) {
                                row(zone, at: context.date)
                            }
                        }
                    }
                    Button {
                        SettingsRouter.shared.request(AppFeature.worldClock.settingsDestination)
                        appDelegate()?.openSettingsWindow()
                    } label: {
                        Label(text.editClocks, systemImage: "globe")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    private func row(_ zone: TimeZone, at date: Date) -> some View {
        let local = TimeZone.autoupdatingCurrent
        let shift = WorldClockSupport.dayShift(at: date, zone: zone, local: local)
        let offset = zone.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)
        let day = shift > 0 ? text.tomorrow : shift < 0 ? text.yesterday : text.today
        let daytime = WorldClockSupport.isDaytime(at: date, zone: zone)
        return HStack(spacing: 8) {
            Image(systemName: daytime ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 11))
                .foregroundStyle(daytime ? Color.orange : Color.indigo)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(WorldClockSupport.cityName(zone.identifier))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("\(day) · \(WorldClockSupport.offsetLabel(seconds: offset))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(time(date, in: zone))
                .font(.system(size: 15, weight: .medium).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    private func time(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = l10n.language.formattingLocale()
        formatter.timeZone = zone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// The list of chosen cities with a search to add more, for the Settings page.
struct WorldClockEditor: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.worldClockZones) private var storedZones = ""
    @State private var query = ""

    private var text: WorldClockStrings { FeatureStrings.worldClock(l10n.language) }
    private var zones: [String] { WorldClockSupport.zones(from: storedZones) }

    var body: some View {
        ForEach(zones, id: \.self) { identifier in
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(WorldClockSupport.cityName(identifier))
                    Text(identifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    storedZones = WorldClockSupport.stored(zones.filter { $0 != identifier })
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(text.remove)
                .accessibilityLabel(text.remove)
            }
        }
        if zones.count >= WorldClockSupport.maxClocks {
            Text(text.limitReached)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            TextField(text.addCity, text: $query, prompt: Text(text.searchPlaceholder))
            let results = WorldClockSupport.matches(query, excluding: zones,
                                                    locale: l10n.language.formattingLocale())
            if !query.trimmingCharacters(in: .whitespaces).isEmpty, results.isEmpty {
                Text(text.noMatches)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(results.prefix(8), id: \.self) { identifier in
                Button {
                    storedZones = WorldClockSupport.stored(zones + [identifier])
                    query = ""
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text(WorldClockSupport.cityName(identifier))
                        Spacer()
                        Text(identifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
