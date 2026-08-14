// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// The detached popup anchored to the now-playing menu bar item: an ambient
/// blurred backdrop of the cover, a large artwork tile that reveals each new
/// track, the track metadata with a seekable progress bar, and transport
/// controls. The track body of the menu panel section is its smaller sibling
/// (NowPlayingTrackContent); this view is the full presentation.
struct NowPlayingPopupView: View {
    /// Fixed card dimensions; the presenter clamps the height to the space
    /// below the menu bar item but the width never changes.
    static let cardWidth: CGFloat = 420
    static let cardHeight: CGFloat = 236
    private static let tileSize: CGFloat = 140
    private static let backdropMaxOpacity: Double = 0.24

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NowPlayingService.shared
    @AppStorage(DefaultsKey.nowPlayingOpenInApp) private var openInApp = true
    @AppStorage(DefaultsKey.nowPlayingShowArtwork) private var showArtwork = true
    @AppStorage(DefaultsKey.nowPlayingArtworkAnimation) private var animateArtwork = true

    // The artwork currently on screen; kept in view state so the outgoing
    // cover can be crossfaded underneath the incoming one.
    @State private var displayedArtwork: NSImage?
    @State private var outgoingArtwork: NSImage?
    @State private var outgoingOpacity: Double = 0
    @State private var currentBackdropOpacity: Double = 1
    @State private var backdropTeardown: DispatchWorkItem?
    // Fade-in reveal of the hero tile.
    @State private var revealOpacity: Double = 1
    @State private var revealScale: CGFloat = 1
    @State private var revealBlur: CGFloat = 0
    // Suppress the transition for the very first display of a popup open.
    @State private var hasDisplayedArtwork = false

    @State private var isSeeking = false
    @State private var seekPosition: TimeInterval = 0

    private var strings: NowPlayingStrings {
        FeatureStrings.nowPlaying(l10n.language)
    }

    private var currentTrackIdentityKey: String {
        "\(service.snapshot.displayTitle)|\(service.snapshot.displayArtist)|\(service.snapshot.duration ?? 0)"
    }

    var body: some View {
        Group {
            if service.snapshot.hasTrack {
                trackBody
            } else {
                emptyState
            }
        }
        .frame(width: Self.cardWidth)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onChange(of: service.artworkIdentity) { oldIdentity, _ in
            guard hasDisplayedArtwork else {
                displayedArtwork = service.artworkImage
                return
            }
            transitionArtwork(from: oldIdentity)
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
        .onAppear {
            displayedArtwork = service.artworkImage
            hasDisplayedArtwork = true
            outgoingArtwork = nil
            currentBackdropOpacity = 1
            settleReveal()
        }
    }

    // MARK: - Layout

    private var trackBody: some View {
        ZStack(alignment: .top) {
            backdrop
            VStack(spacing: 12) {
                heroRow
                controlsRow
            }
            .padding(18)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight, alignment: .top)
    }

    /// Ambient wash of the cover behind everything: the outgoing and the
    /// current image crossfade independently underneath the hero row.
    private var backdrop: some View {
        ZStack {
            if let outgoing = outgoingArtwork {
                backdropLayer(outgoing)
                    .opacity(outgoingOpacity)
            }
            if let current = displayedArtwork {
                backdropLayer(current)
                    .opacity(currentBackdropOpacity)
            }
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .blur(radius: 26)
        .scaleEffect(1.12)
        .saturation(1.06)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func backdropLayer(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: Self.cardWidth, height: Self.cardHeight)
            .clipped()
            .opacity(Self.backdropMaxOpacity)
    }

    private var heroRow: some View {
        HStack(spacing: 16) {
            if showArtwork {
                artworkTile
            }
            VStack(alignment: .leading, spacing: 4) {
                titleView
                Text(artistAlbumLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                progressView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The large cover: outer chrome at radius 22, the image inset 6pt at
    /// radius 16, a diffused glow bleeding past the edges and a deep shadow.
    private var artworkTile: some View {
        ZStack {
            if let artwork = displayedArtwork {
                // Diffused glow just outside the tile.
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.tileSize, height: Self.tileSize)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .blur(radius: 18)
                    .opacity(0.55)
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.tileSize, height: Self.tileSize)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: Self.tileSize, height: Self.tileSize)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 10)
        .opacity(revealOpacity)
        .scaleEffect(revealScale)
        .blur(radius: revealBlur)
        .accessibilityLabel("\(service.snapshot.displayTitle) — \(service.snapshot.displayArtist)")
    }

    /// The title is the affordance to jump into the app owning the session
    /// when that app can be resolved.
    private var titleView: some View {
        Group {
            if openInApp, service.snapshot.appBundleID != nil {
                Button {
                    service.openSourceApp()
                } label: {
                    Text(service.snapshot.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(strings.openInAppCaption)
            } else {
                Text(service.snapshot.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var artistAlbumLine: String {
        var line = service.snapshot.displayArtist
        if let album = service.snapshot.album, !album.isEmpty {
            line += " — \(album)"
        }
        return line
    }

    private var progressView: some View {
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
                    isSeeking = true
                } else {
                    service.seek(to: seekPosition)
                    // Clear after a timeout in case the elapsed update never matches.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                        isSeeking = false
                    }
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
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 34) {
            transportButton("backward.fill", action: service.previousTrack,
                            help: strings.previousLabel)
            playPauseButton
            transportButton("forward.fill", action: service.nextTrack,
                            help: strings.nextLabel)
        }
        .frame(maxWidth: .infinity)
    }

    private var playPauseButton: some View {
        Button {
            service.togglePlayPause()
        } label: {
            Image(systemName: service.snapshot.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(service.snapshot.isPlaying ? strings.pauseLabel : strings.playLabel)
        .accessibilityLabel(service.snapshot.isPlaying ? strings.pauseLabel : strings.playLabel)
    }

    private func transportButton(_ symbol: String,
                                 action: @escaping () -> Void,
                                 help: String) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(strings.emptyState)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(width: Self.cardWidth)
        .padding(.vertical, 36)
    }

    // MARK: - Artwork animation

    /// A genuinely new cover (the service only bumps identity on real
    /// changes): the old cover crossfades out inside the backdrop while the
    /// new tile fades in with a slight scale and blur settle. Identical
    /// pixels — e.g. a popup reopened on the same track — never animate.
    private func transitionArtwork(from previousIdentity: String) {
        guard animateArtwork,
              service.artworkIdentity != previousIdentity else {
            settleArtworkInstantly()
            return
        }
        outgoingArtwork = displayedArtwork
        displayedArtwork = service.artworkImage

        guard service.artworkImage != nil || outgoingArtwork != nil else {
            settleArtworkInstantly()
            return
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        // Backdrop: a true double crossfade between the two covers.
        outgoingOpacity = outgoingArtwork != nil ? 1 : 0
        currentBackdropOpacity = 0
        backdropTeardown?.cancel()
        let backdropDuration: TimeInterval = reduceMotion ? 0.18 : 0.62
        withAnimation(.timingCurve(0.20, 0.78, 0.16, 1.0, duration: backdropDuration)) {
            outgoingOpacity = 0
            currentBackdropOpacity = 1
        }
        let teardown = DispatchWorkItem { outgoingArtwork = nil }
        backdropTeardown = teardown
        DispatchQueue.main.asyncAfter(deadline: .now() + backdropDuration + 0.05,
                                      execute: teardown)

        // Hero tile: fade-in reveal.
        guard service.artworkImage != nil else {
            settleReveal()
            return
        }
        revealOpacity = 0
        revealScale = reduceMotion ? 1 : 1.018
        revealBlur = reduceMotion ? 0 : 8
        let revealDuration: TimeInterval = reduceMotion ? 0.20 : 0.46
        withAnimation(.easeInOut(duration: revealDuration)) {
            revealOpacity = 1
            revealScale = 1
            revealBlur = 0
        }
    }

    /// No animation (setting off, or nothing to animate): snap to the
    /// current artwork with all animation state settled.
    private func settleArtworkInstantly() {
        backdropTeardown?.cancel()
        backdropTeardown = nil
        displayedArtwork = service.artworkImage
        outgoingArtwork = nil
        outgoingOpacity = 0
        currentBackdropOpacity = 1
        settleReveal()
    }

    private func settleReveal() {
        revealOpacity = 1
        revealScale = 1
        revealBlur = 0
    }
}
