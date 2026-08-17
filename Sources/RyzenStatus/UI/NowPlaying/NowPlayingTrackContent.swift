// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// The shared now-playing body — artwork, track/artist/album, a seekable
/// progress bar, transport controls and the jump-to-app button — used by
/// the menu panel section. (The menu bar popup renders its own card:
/// backdrop, glow tile and the regular↔mini morph need a bespoke layout.)
struct NowPlayingTrackContent: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NowPlayingService.shared
    @AppStorage(DefaultsKey.nowPlayingOpenInApp) private var openInApp = true
    @AppStorage(DefaultsKey.nowPlayingShowArtwork) private var showArtwork = true
    @AppStorage(DefaultsKey.nowPlayingArtworkAnimation) private var animateArtwork = true
    @State private var isSeeking = false
    @State private var seekPosition: TimeInterval = 0
    @State private var seekResetWork: DispatchWorkItem?

    /// Edge of the artwork square in the panel section.
    private static let artworkSize: CGFloat = 46

    private var currentTrackIdentityKey: String {
        "\(service.snapshot.displayTitle)|\(service.snapshot.displayArtist)|\(service.snapshot.duration ?? 0)"
    }

    private var strings: NowPlayingStrings {
        FeatureStrings.nowPlaying(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if showArtwork {
                    artworkView
                }
                VStack(alignment: .leading, spacing: 2) {
                    titleView
                    Text(service.snapshot.displayArtist)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let album = service.snapshot.album, !album.isEmpty {
                        Text(album)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if let appName = service.snapshot.appName {
                        Text(appName)
                            .font(.system(size: 9))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            progressBar

            HStack(spacing: 14) {
                Spacer()
                if service.supportsPlaybackModes {
                    shuffleButton
                }
                transportButton("backward.fill", action: service.previousTrack,
                                help: strings.previousLabel)
                playPauseButton
                transportButton("forward.fill", action: service.nextTrack,
                                help: strings.nextLabel)
                if service.supportsPlaybackModes {
                    repeatButton
                }
                Spacer()
            }
            .padding(.vertical, 2)

            if openInApp, let appName = service.snapshot.appName {
                Button {
                    service.openSourceApp()
                } label: {
                    Label("\(strings.openInAppLabel): \(appName)",
                          systemImage: "arrow.up.forward.app")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .onChange(of: currentTrackIdentityKey) { _, _ in
            isSeeking = false
        }
        .onChange(of: service.snapshot.elapsed) { _, newElapsed in
            if isSeeking {
                let elapsed = newElapsed ?? 0.0
                if abs(Double(elapsed) - Double(seekPosition)) <= 2.5 {
                    isSeeking = false
                }
            }
        }
    }

    /// The track title is the affordance to jump into the source app, the
    /// same interaction the original now-playing apps expose.
    private var titleView: some View {
        Group {
            if openInApp {
                Button {
                    service.openSourceApp()
                } label: {
                    Text(service.snapshot.displayTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(strings.openInAppCaption)
            } else {
                Text(service.snapshot.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var progressBar: some View {
        let duration = service.snapshot.duration ?? 0
        let elapsed = service.snapshot.elapsed ?? 0
        let displayPosition = isSeeking ? seekPosition : elapsed
        return VStack(spacing: 2) {
            Slider(value: Binding(
                get: { displayPosition },
                set: { seekPosition = $0 }
            ), in: 0...max(duration, 1)) {
                Text(strings.seekLabel)
            } onEditingChanged: { editing in
                if editing {
                    seekResetWork?.cancel()
                    seekResetWork = nil
                    isSeeking = true
                } else {
                    service.seek(to: seekPosition)
                    // Clear after a timeout in case the elapsed update never matches
                    let reset = DispatchWorkItem { isSeeking = false }
                    seekResetWork?.cancel()
                    seekResetWork = reset
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: reset)
                }
            }
            .disabled(duration <= 0)
            .controlSize(.mini)
            .labelsHidden()

            HStack {
                Text(NowPlayingSnapshot.timeLabel(displayPosition))
                Spacer()
                Text(NowPlayingSnapshot.timeLabel(duration))
            }
            .font(.system(size: 8.5, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
    }

    /// The artwork crossfades when the track changes: the artwork identity
    /// (pixel fingerprint) re-identifies the image so the outgoing cover fades
    /// into the incoming one instead of snapping — and the same cover never
    /// fades in twice when the view reappears.
    private var artworkView: some View {
        ZStack {
            artworkImage
                .id(service.artworkIdentity)
                .transition(.opacity)
        }
        .frame(width: Self.artworkSize, height: Self.artworkSize)
        .animation(animateArtwork ? .easeInOut(duration: 0.25) : nil,
                   value: service.artworkIdentity)
    }

    @ViewBuilder
    private var artworkImage: some View {
        let cornerRadius: CGFloat = 6
        if let artwork = service.artworkImage {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.artworkSize, height: Self.artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .accessibilityLabel("\(service.snapshot.displayTitle) — \(service.snapshot.displayArtist)")
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: Self.artworkSize, height: Self.artworkSize)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(strings.pageTitle)
        }
    }

    private var playPauseButton: some View {
        Button {
            service.togglePlayPause()
        } label: {
            Image(systemName: service.snapshot.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.accentColor.opacity(0.16)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(service.snapshot.isPlaying ? strings.pauseLabel : strings.playLabel)
        .accessibilityLabel(service.snapshot.isPlaying ? strings.pauseLabel : strings.playLabel)
    }

    /// Shuffle mirrors the provider state the service confirms after each
    /// toggle; the accent tint marks it on.
    private var shuffleButton: some View {
        Button {
            service.toggleShuffle()
        } label: {
            Image(systemName: "shuffle")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 26, height: 26)
                .foregroundStyle(service.snapshot.isShuffleEnabled
                                 ? Color.accentColor : Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(strings.shuffleLabel)
        .accessibilityLabel(strings.shuffleLabel)
    }

    /// Music cycles off → all → one, Spotify off ↔ all; the help text
    /// names the state currently on screen.
    private var repeatButton: some View {
        Button {
            service.cycleRepeatMode()
        } label: {
            Image(systemName: service.snapshot.repeatMode.symbolName)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 26, height: 26)
                .foregroundStyle(service.snapshot.repeatMode.isEnabled
                                 ? Color.accentColor : Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(repeatHelp)
        .accessibilityLabel(repeatHelp)
    }

    private var repeatHelp: String {
        switch service.snapshot.repeatMode {
        case .off: return strings.repeatOffLabel
        case .all: return strings.repeatAllLabel
        case .one: return strings.repeatOneLabel
        }
    }

    private func transportButton(_ symbol: String,
                                 action: @escaping () -> Void,
                                 help: String) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
