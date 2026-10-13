// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// The island's queue page, reading `NowPlayingService.upcoming`. No
/// provider shares its upcoming songs yet, so it usually says so and offers
/// to open the player, where its queue lives.
struct NotchQueueView: View {
    let playback: NowPlayingPlayback
    @ObservedObject private var service = NowPlayingService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchMusicExtrasStrings { FeatureStrings.notchMusicExtras(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text.queue).font(.callout.weight(.semibold))
            if let queue = service.upcoming, !queue.items.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(queue.items) { item in
                            HStack(spacing: 10) {
                                NotchArtwork(image: nil, size: 34)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
                                    if !item.artist.isEmpty { Text(item.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(.vertical, 8)
                        }
                    }
                }
                .notchScrollEdgeFade()
            } else {
                NotchEmptyView(symbol: "list.bullet", message: service.upcoming == nil ? text.queueUnavailable : text.queueEmpty) {
                    NotchPillButton(title: text.openPlayer, prominent: true) { NowPlayingApplication.open(playback.track) }
                }
            }
        }
        // The title sits as far below the player as the first verse would.
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
