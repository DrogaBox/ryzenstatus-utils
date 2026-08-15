// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// Settings for the Now Playing feature: the master toggle, the menu bar
/// display mode (mirroring a full now-playing app), the preferred provider,
/// the progress strip and the panel artwork. Every change re-syncs the live
/// service so the menu bar reacts without a restart.
struct NowPlayingSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.nowPlayingEnabled) private var enabled = false
    @AppStorage(DefaultsKey.nowPlayingMenuBarMode) private var menuBarMode = NowPlayingMenuBarMode.artistSong.rawValue
    @AppStorage(DefaultsKey.nowPlayingMenuBarProgress) private var menuBarProgress = false
    @AppStorage(DefaultsKey.nowPlayingMarquee) private var marquee = true
    @AppStorage(DefaultsKey.nowPlayingMarqueeSlide) private var marqueeSlide = true
    @AppStorage(DefaultsKey.nowPlayingPreferredProvider) private var provider = NowPlayingProvider.auto.rawValue
    @AppStorage(DefaultsKey.nowPlayingOpenInApp) private var openInApp = true
    @AppStorage(DefaultsKey.nowPlayingShowArtwork) private var showArtwork = true
    @AppStorage(DefaultsKey.nowPlayingArtworkAnimation) private var animateArtwork = true
    @AppStorage(DefaultsKey.nowPlayingArtworkSize) private var artworkSize: Double = 140
    @AppStorage(DefaultsKey.nowPlayingUnloadWhenHidden) private var unloadWhenHidden = true

    private var strings: NowPlayingStrings {
        FeatureStrings.nowPlaying(l10n.language)
    }

    var body: some View {
        Form {
            Section {
                Toggle(strings.pageTitle, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        NowPlayingService.shared.syncWithPreferences()
                    }
            } footer: {
                Text(strings.hubDescription)
            }

            if enabled {
                Section {
                    Picker(strings.menuBarModeLabel, selection: $menuBarMode) {
                        Text(strings.menuBarModeIconOnly).tag(NowPlayingMenuBarMode.iconOnly.rawValue)
                        Text(strings.menuBarModeArtist).tag(NowPlayingMenuBarMode.artist.rawValue)
                        Text(strings.menuBarModeSong).tag(NowPlayingMenuBarMode.song.rawValue)
                        Text(strings.menuBarModeBoth).tag(NowPlayingMenuBarMode.artistSong.rawValue)
                    }
                    .onChange(of: menuBarMode) { _, _ in NowPlayingService.shared.applyPreferenceChanges() }
                    
                    Toggle(strings.menuBarProgress, isOn: $menuBarProgress)
                    .onChange(of: menuBarProgress) { _, _ in NowPlayingService.shared.applyPreferenceChanges() }

                    Toggle(strings.marqueeToggle, isOn: $marquee)
                    .onChange(of: marquee) { _, _ in NowPlayingService.shared.applyPreferenceChanges() }
                    Toggle(strings.marqueeSlideToggle, isOn: $marqueeSlide)
                    .onChange(of: marqueeSlide) { _, _ in NowPlayingService.shared.applyPreferenceChanges() }
                    .disabled(!marquee)
                    
                    Picker(strings.providerLabel, selection: $provider) {
                        Text(strings.providerAuto).tag(NowPlayingProvider.auto.rawValue)
                        Text(strings.providerMusic).tag(NowPlayingProvider.music.rawValue)
                        Text(strings.providerSpotify).tag(NowPlayingProvider.spotify.rawValue)
                    }
                    .onChange(of: provider) { _, _ in NowPlayingService.shared.applyPreferenceChanges() }
                    Toggle(strings.openInAppToggle, isOn: $openInApp)
                } footer: {
                    Text(strings.openInAppCaption)
                }

                Section {
                    Toggle(strings.artworkToggle, isOn: $showArtwork)
                    Toggle(strings.artworkAnimationToggle, isOn: $animateArtwork)
                        .disabled(!showArtwork)
                    HStack {
                        Text(strings.artworkSizeLabel)
                        Slider(value: $artworkSize, in: 120...260, step: 10) {
                            Text(strings.artworkSizeLabel)
                        }
                        .onChange(of: artworkSize) { _, _ in
                            NowPlayingPopupController.shared.applyArtworkSizeChange()
                        }
                        Text("\(Int(artworkSize)) pt")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                    .disabled(!showArtwork)
                    Toggle(strings.unloadWhenHiddenToggle, isOn: $unloadWhenHidden)
                    Button(strings.clearMediaCacheButton) {
                        NowPlayingService.shared.clearMediaCache()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
