// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The island's lyrics page. Lyrics come from `NowPlayingLyricsCenter`, the
/// same engine the popup's details pane uses; online lookups wait for the
/// island's own opt-in, while the Music app's lyrics are read either way.
struct NotchLyricsView: View {
    let playback: NowPlayingPlayback
    @ObservedObject private var center = NowPlayingLyricsCenter.shared
    @ObservedObject private var importer = NotchLyricsImporter.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchLyricsOnline) private var online = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: NotchMusicExtrasStrings { FeatureStrings.notchMusicExtras(l10n.language) }

    private var lyrics: NowPlayingTimedLyrics? {
        guard center.paneState == .available, let payload = center.payload else { return nil }
        return NowPlayingTimedLyrics(payload)
    }

    private var lookup: LookupID {
        LookupID(identity: NowPlayingTrackIdentity(playback), online: online && NotchLyricsSupport.onlineEnabled())
    }

    // The verses sit on the island itself, as a player's own lyrics do, and
    // a song without them says so like the island's other empty pages.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lyrics {
                if !lyrics.lines.isEmpty, playback.hasPosition {
                    synced(lyrics)
                    // Importing is a one-off; it shares the timing row as an
                    // icon instead of a row of its own under the verses.
                    HStack(spacing: 10) {
                        importButton
                        Text(text.offset).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        // Hit the whole timing row height, not just the thin symbol.
                        Button { center.adjustOffset(by: -0.25) } label: {
                            Image(systemName: "minus")
                                .frame(width: 24, height: 18)
                                .contentShape(Rectangle())
                        }
                            .help(text.earlier).accessibilityLabel(text.earlier)
                        Button { center.resetOffset() } label: {
                            Text(center.offset, format: .number.sign(strategy: .always()).precision(.fractionLength(2)))
                                .monospacedDigit().frame(minWidth: 44)
                        }.help(text.reset).accessibilityLabel(text.reset)
                        Button { center.adjustOffset(by: 0.25) } label: {
                            Image(systemName: "plus")
                                .frame(width: 24, height: 18)
                                .contentShape(Rectangle())
                        }
                            .help(text.later).accessibilityLabel(text.later)
                    }
                    .font(.caption).buttonStyle(.borderless)
                } else {
                    if !playback.hasPosition { Text(text.noPosition).font(.caption).foregroundStyle(.secondary) }
                    ScrollView {
                        Text(lyrics.plain.isEmpty ? lyrics.lines.map(\.text).joined(separator: "\n") : lyrics.plain)
                            .font(.system(size: 15, weight: .medium)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .notchScrollEdgeFade()
                    Button { importLyrics() } label: { Label(text.importLyrics, systemImage: "doc.badge.plus") }
                        .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
                }
            } else if center.paneState == .loading {
                // A slow lookup leaves importing within reach while it waits.
                VStack(spacing: 12) {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(text.loading) }
                        .font(.callout).foregroundStyle(.secondary)
                    NotchPillButton(title: text.importLyrics, action: importLyrics)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NotchEmptyView(symbol: center.paneState == .failed ? "exclamationmark.triangle" : "quote.bubble",
                               message: emptyMessage) {
                    // A short island keeps importing as a glyph beside the
                    // next step rather than cutting either name short.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            nextStep
                            NotchPillButton(title: text.importLyrics, action: importLyrics)
                        }
                        HStack(spacing: 8) {
                            nextStep
                            NotchIconButton(symbol: "doc.badge.plus", title: text.importLyrics, action: importLyrics)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: lookup) { load(forceRefresh: false) }
    }

    private struct LookupID: Equatable {
        let identity: NowPlayingTrackIdentity
        let online: Bool
    }

    private func load(forceRefresh: Bool) {
        let track = playback.track
        center.ensureLyrics(title: track.title ?? "", artist: track.artist ?? "", album: track.album ?? "",
                            duration: playback.duration, bundleID: track.appBundleIdentifier,
                            allowNetwork: lookup.online, forceRefresh: forceRefresh)
    }

    private func importLyrics() { importer.begin(for: playback) }

    /// An import that read no lines fails even with online lookup off, so the
    /// failure stays above the disclosure the next step needs.
    private var emptyMessage: String {
        let reason: String? = center.paneState == .failed ? text.failed : online ? text.unavailable : nil
        return [reason, online ? nil : text.onlineHint].compactMap { $0 }.joined(separator: "\n")
    }

    @ViewBuilder private var nextStep: some View {
        if online {
            NotchPillButton(title: text.retry, prominent: true) { load(forceRefresh: true) }
        } else {
            NotchPillButton(title: text.online, prominent: true) { online = true }
        }
    }

    private var importButton: some View {
        // A file being added, not the usual download arrow, which reads as saving.
        Button { importLyrics() } label: { Image(systemName: "doc.badge.plus") }
            .buttonStyle(.borderless)
            .help(text.importLyrics)
            .accessibilityLabel(text.importLyrics)
    }

    private func synced(_ lyrics: NowPlayingTimedLyrics) -> some View {
        TimelineView(.explicit(lyrics.changeDates(for: playback, offset: center.offset, from: .now))) { context in
            let active = lyrics.activeIndex(at: playback.position(at: context.date), offset: center.offset)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if active == nil {
                            Text(text.waiting).font(.caption).foregroundStyle(.secondary).id("start")
                        }
                        // Every verse keeps one size, so the lines never
                        // rewrap as the song moves. The sung one lights up.
                        ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white.opacity(index == active ? 1 : 0.35))
                                .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: index == active)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .id(index)
                        }
                    }.padding(.vertical, 6)
                }
                .notchScrollEdgeFade(length: 24)
                .onChange(of: active, initial: true) { _, index in
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
                        if let index { proxy.scrollTo(index, anchor: .center) }
                        else { proxy.scrollTo("start", anchor: .top) }
                    }
                }
            }
        }
    }
}

/// The file chooser behind "Import lyrics". Presentation only: it keeps the
/// island up while the chooser is open and hands the picked file to
/// `NowPlayingLyricsCenter`, which reads and caches it for the track.
final class NotchLyricsImporter: ObservableObject {
    static let shared = NotchLyricsImporter()
    @Published private(set) var panel: NSOpenPanel?
    var isImporting: Bool { panel != nil }

    private init() {}

    func cancel() {
        panel?.cancel(nil)
        panel = nil
    }

    func begin(for playback: NowPlayingPlayback) {
        let track = NowPlayingTrackIdentity(playback)
        guard NotchLyricsSupport.isEnabled(), panel == nil,
              let parent = NotchService.shared.presentationWindow,
              canReturnToLyrics(parent) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = FeatureStrings.notchMusicExtras(L10n.shared.language).importHint
        // An attached sheet moves/reskins a borderless island. Keep the chooser
        // independent and above its parent instead, without changing the pin.
        panel.level = NSWindow.Level(rawValue: parent.level.rawValue + 1)
        // Like the sheet it replaces, it stays up while another app is active.
        panel.hidesOnDeactivate = false
        self.panel = panel
        panel.begin { [weak self, weak panel, weak parent] response in
            guard let self, let panel, self.panel === panel else { return }
            let selectedURL = panel.url
            self.panel = nil
            guard let parent, self.canReturnToLyrics(parent) else { return }
            if response == .OK, let url = selectedURL,
               let current = NowPlayingService.shared.playback, NowPlayingTrackIdentity(current) == track {
                NowPlayingLyricsCenter.shared.importLyrics(
                    from: url, title: current.track.title ?? "", artist: current.track.artist ?? "",
                    album: current.track.album ?? "", duration: current.duration)
            }
            // Dismissal restores the old key window after this callback.
            DispatchQueue.main.async { [weak self, weak parent] in
                guard let self, let parent, self.panel == nil, self.canReturnToLyrics(parent) else { return }
                NotchService.shared.open(.music, feedback: false)
            }
        }
        // isImporting keeps the music surface alive through activation and
        // pointer exit. Completion restores focus after native dismissal.
        NSApp.activate(ignoringOtherApps: true)
        // Activation alone can leave the nonactivating island holding focus.
        panel.makeKeyAndOrderFront(nil)
    }

    private func canReturnToLyrics(_ window: NSWindow) -> Bool {
        let notch = NotchService.shared
        return NotchLyricsSupport.isEnabled()
            && notch.acceptsUserInteraction && notch.presentationWindow === window && window.isVisible
            && notch.expanded && notch.selected == .music && !notch.showingAppPanel
            && notch.selectedMetric == nil && notch.captureControls == nil
    }
}
