// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// Where the popup body lives: inside the anchored popover (regular ↔ mini
/// morph) or inside the detached floating window (always the artwork-first
/// layout, scaled by the size preset).
enum NowPlayingPopupCluster {
    case popover
    case detached
}

/// The now-playing popup body: an ambient blurred backdrop of the cover, a
/// large artwork tile that reveals each new track, the track metadata with a
/// seekable progress bar, and transport controls. Two layouts share one
/// animation pipeline — the wide regular card and the square mini card — and
/// the same view also fills the detached floating window.
struct NowPlayingPopupView: View {
    static let miniSize = NSSize(width: 380, height: 380)
    /// The mini card is square; the tile keeps a fixed chrome margin, so
    /// every size derives from the width alone.
    static let miniChromeMargin: CGFloat = 144
    private static let backdropMaxOpacity: Double = 0.24

    var cluster: NowPlayingPopupCluster = .popover

    @ObservedObject private var controller = NowPlayingPopupController.shared
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

    // Layout crossfade between the regular and the mini card.
    @State private var regularOpacity: Double = 1
    @State private var miniOpacity: Double = 0
    @State private var mountedLayouts: Set<NowPlayingPopupLayout> = []
    @State private var layoutTeardown: DispatchWorkItem?
    @State private var hasCrossfadedLayout = false

    @State private var isSeeking = false
    @State private var seekPosition: TimeInterval = 0
    @State private var isHovering = false

    private var strings: NowPlayingStrings {
        FeatureStrings.nowPlaying(l10n.language)
    }

    private var currentTrackIdentityKey: String {
        "\(service.snapshot.displayTitle)|\(service.snapshot.displayArtist)|\(service.snapshot.duration ?? 0)"
    }

    /// The layout currently on top: the popover morphs between both, the
    /// detached window is always artwork-first.
    private var activeLayout: NowPlayingPopupLayout {
        if cluster == .detached { return .mini }
        return controller.isMini ? .mini : .regular
    }

    /// The regular card follows the artwork size setting; mini stays square.
    private var regularSize: NSSize { NowPlayingPopupController.regularSize }

    private var cardSize: NSSize {
        if cluster == .detached {
            let width = controller.detachedSize.width
            return NSSize(width: width, height: width)
        }
        return controller.isMini ? Self.miniSize : regularSize
    }

    var body: some View {
        Group {
            if service.snapshot.hasTrack {
                trackBody
            } else {
                emptyState
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(alignment: .topTrailing) { hoverCluster }
        .onHover { isHovering = $0 }
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
        .onChange(of: controller.isMini) { _, toMini in
            guard cluster == .popover, hasCrossfadedLayout else { return }
            crossfadeLayout(toMini: toMini)
        }
        .onAppear {
            displayedArtwork = service.artworkImage
            hasDisplayedArtwork = true
            outgoingArtwork = nil
            currentBackdropOpacity = 1
            settleReveal()
            mountedLayouts = [activeLayout]
            regularOpacity = activeLayout == .regular ? 1 : 0
            miniOpacity = activeLayout == .mini ? 1 : 0
            hasCrossfadedLayout = true
        }
    }

    /// The detached window is borderless, so it paints its own card surface;
    /// the popover brings its own chrome.
    @ViewBuilder
    private var cardBackground: some View {
        if cluster == .detached {
            Rectangle().fill(.regularMaterial)
        }
    }

    // MARK: - Layouts

    private var trackBody: some View {
        ZStack(alignment: .top) {
            if cluster == .detached {
                miniBody(width: cardSize.width)
            } else {
                if mountedLayouts.contains(.regular) {
                    regularBody
                        .opacity(regularOpacity)
                }
                if mountedLayouts.contains(.mini) {
                    miniBody(width: Self.miniSize.width)
                        .opacity(miniOpacity)
                }
            }
        }
        .frame(width: cardSize.width, height: cardSize.height, alignment: .top)
    }

    /// The wide card: artwork tile left, metadata and progress right,
    /// transport row underneath.
    private var regularBody: some View {
        let size = regularSize
        return ZStack(alignment: .top) {
            backdrop(width: size.width, height: size.height)
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    if showArtwork {
                        artworkTile(size: NowPlayingPopupController.artworkTileSize,
                                    cornerRadius: 16, outerRadius: 22)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        titleView(fontSize: 13, alignment: .leading)
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
                controlsRow
            }
            .padding(18)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    /// The square artwork-first card used by mini mode and the detached
    /// window: dominant centered cover, metadata and transport below.
    private func miniBody(width: CGFloat) -> some View {
        let tileSize = width - Self.miniChromeMargin
        return ZStack(alignment: .top) {
            backdrop(width: width, height: width)
            VStack(spacing: 10) {
                if showArtwork {
                    artworkTile(size: tileSize, cornerRadius: 18, outerRadius: 24)
                }
                titleView(fontSize: 14, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(artistAlbumLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
                progressView
                controlsRow
            }
            .padding(18)
        }
        .frame(width: width, height: width, alignment: .top)
    }

    /// Ambient wash of the cover behind everything: the outgoing and the
    /// current image crossfade independently underneath the content.
    private func backdrop(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            if let outgoing = outgoingArtwork {
                backdropLayer(outgoing, width: width, height: height)
                    .opacity(outgoingOpacity)
            }
            if let current = displayedArtwork {
                backdropLayer(current, width: width, height: height)
                    .opacity(currentBackdropOpacity)
            }
        }
        .frame(width: width, height: height)
        .blur(radius: 26)
        .scaleEffect(1.12)
        .saturation(1.06)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func backdropLayer(_ image: NSImage, width: CGFloat, height: CGFloat) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .clipped()
            .opacity(Self.backdropMaxOpacity)
    }

    /// The large cover: outer chrome ring, the image inset 6pt, a diffused
    /// glow bleeding past the edges and a deep shadow.
    private func artworkTile(size: CGFloat, cornerRadius: CGFloat, outerRadius: CGFloat) -> some View {
        ZStack {
            if let artwork = displayedArtwork {
                // Diffused glow just outside the tile.
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .blur(radius: 18)
                    .opacity(0.55)
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: size / 5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
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
    private func titleView(fontSize: CGFloat, alignment: Alignment) -> some View {
        Group {
            if openInApp, service.snapshot.appBundleID != nil {
                Button {
                    service.openSourceApp()
                } label: {
                    Text(service.snapshot.displayTitle)
                        .font(.system(size: fontSize, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(strings.openInAppCaption)
            } else {
                Text(service.snapshot.displayTitle)
                    .font(.system(size: fontSize, weight: .semibold))
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Hover cluster

    /// The controls that appear when the pointer rests on the card: mini
    /// toggle and detach in the popover, pin/size/close in the window.
    @ViewBuilder
    private var hoverCluster: some View {
        if isHovering {
            HStack(spacing: 4) {
                if cluster == .popover {
                    clusterButton(
                        systemName: controller.isMini
                            ? "arrow.up.left.and.arrow.down.right"
                            : "arrow.down.right.and.arrow.up.left",
                        help: controller.isMini ? strings.regularModeLabel : strings.miniModeLabel
                    ) {
                        controller.toggleMini()
                    }
                    clusterButton(systemName: "macwindow", help: strings.detachLabel) {
                        controller.detachPopover()
                    }
                } else {
                    clusterButton(
                        systemName: controller.detachedOnTop ? "pin.fill" : "pin",
                        help: strings.alwaysOnTopLabel,
                        isHighlighted: controller.detachedOnTop
                    ) {
                        controller.detachedOnTop.toggle()
                    }
                    sizeMenu
                    clusterButton(systemName: "xmark", help: strings.closeLabel) {
                        controller.closeDetached()
                    }
                }
            }
            .padding(6)
            .background(Capsule().fill(.thinMaterial))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .padding(8)
            .transition(.opacity)
        }
    }

    private func clusterButton(systemName: String,
                               help: String,
                               isHighlighted: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .foregroundStyle(isHighlighted ? Color.accentColor : Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var sizeMenu: some View {
        Menu {
            Picker(strings.sizeLabel, selection: $controller.detachedSize) {
                Text(strings.sizeSmall).tag(NowPlayingPopupController.DetachedSize.small)
                Text(strings.sizeMedium).tag(NowPlayingPopupController.DetachedSize.medium)
                Text(strings.sizeLarge).tag(NowPlayingPopupController.DetachedSize.large)
            }
        } label: {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .foregroundStyle(Color.secondary)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(strings.sizeLabel)
        .accessibilityLabel(strings.sizeLabel)
    }

    // MARK: - Layout crossfade

    /// The regular↔mini morph crossfades the two layouts while the window
    /// frame driver runs: the outgoing layout leaves quickly, the incoming
    /// one arrives slightly delayed so the swap reads as one motion.
    private func crossfadeLayout(toMini: Bool) {
        layoutTeardown?.cancel()
        let incoming: NowPlayingPopupLayout = toMini ? .mini : .regular
        let outgoing: NowPlayingPopupLayout = toMini ? .regular : .mini
        mountedLayouts.insert(incoming)
        if toMini {
            miniOpacity = 0
        } else {
            regularOpacity = 0
        }
        withAnimation(.easeOut(duration: 0.14)) {
            if outgoing == .regular {
                regularOpacity = 0
            } else {
                miniOpacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.easeOut(duration: 0.16)) {
                if incoming == .mini {
                    miniOpacity = 1
                } else {
                    regularOpacity = 1
                }
            }
        }
        let teardown = DispatchWorkItem { mountedLayouts.remove(outgoing) }
        layoutTeardown = teardown
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26, execute: teardown)
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

/// The two popup card layouts the popover morphs between.
enum NowPlayingPopupLayout: Hashable {
    case regular
    case mini
}
