// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// The "Now Playing" card in the menu panel: artwork, track and artist, a
/// seekable progress bar with time labels, and transport controls for
/// whatever app owns the media session. The track body is shared with the
/// detached menu bar popup (NowPlayingTrackContent).
struct NowPlayingSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NowPlayingService.shared
    var collapsible = true

    private var strings: NowPlayingStrings {
        FeatureStrings.nowPlaying(l10n.language)
    }

    var body: some View {
        PanelSection(.nowPlaying, title: strings.pageTitle, collapsible: collapsible) {
            if service.snapshot.hasTrack {
                NowPlayingTrackContent()
                    .panelCard()
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(strings.emptyState)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .panelCard()
    }
}
