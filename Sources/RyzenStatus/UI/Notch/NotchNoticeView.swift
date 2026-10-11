// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// Feedback keeps the central camera area clear on physical and simulated notches.
struct NotchNoticeView: View {
    let notice: NotchNotice
    let geometry: NotchGeometry
    var hidesMascot = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var wings: NotchNoticeWings { notice.wings(in: geometry) }
    private var tint: Color {
        switch notice.event {
        case .timer: return .orange
        default: return .white
        }
    }
    private var textTint: Color { notice.event == .timer ? .orange : .white }
    private var companionReaction: NotchMascotReaction? {
        NotchMascotSupport.isEnabled() ? notice.mascot : nil
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .padding(.leading, notice.inset(wing: wings.leading))
                .padding(.trailing, notice.cameraGap)
                .frame(width: wings.leading, height: geometry.stripHeight)
                .clipped()
            Color.clear.frame(width: geometry.noticeCameraGap)
            trailing
                .padding(.trailing, notice.inset(wing: wings.trailing))
                .padding(.leading, notice.cameraGap)
                .frame(width: wings.trailing, height: geometry.stripHeight)
                .clipped()
        }
        .foregroundStyle(.white)
        .frame(height: geometry.stripHeight)
        .offset(x: (wings.trailing - wings.leading) / 2)
        .animation(reduceMotion ? nil : .spring(duration: NotchMotion.steadyWidth.duration, bounce: 0),
                   value: notice.preferredWings)
        .transaction { $0.disablesAnimations = false }
        .id(notice.event)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.accessibilityText)
    }

    @ViewBuilder private var leading: some View {
        if let content = notice.notification {
            HStack(spacing: NotchNotificationBannerLayout.spacing) {
                NotchNotificationAppIcon(app: content.app, size: min(NotchNotificationBannerLayout.iconSize, geometry.stripHeight - 4))
                Text(content.compactTitle)
                    .font(Font(NotchNotificationBannerLayout.titleFont as CTFont))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(spacing: 8) {
                Group {
                    if let reaction = companionReaction {
                        let size = NotchMascotSupport.noticeSize
                        NotchMascotView(look: NotchMascotSupport.look(), mood: NotchService.shared.mascotRestingMood,
                                        size: size, reaction: NotchMascotSupport.reacts() ? reaction : nil)
                            .frame(width: size, height: size)
                            .offset(y: 0.5)
                            .id("\(notice.event)|\(notice.title)|\(notice.detail)|\(reaction.rawValue)")
                            .transition(.identity)
                            .opacity(hidesMascot ? 0 : 1)
                            .animation(nil, value: hidesMascot)
                    } else if notice.event == .track {
                        NotchTrackArtwork(size: min(18, geometry.stripHeight - 6))
                    } else {
                        Image(systemName: notice.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: 18)
                Text(notice.level == nil ? notice.title : notice.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(textTint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(notice.event == .track ? .tail : .middle)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: notice.readsFromEnds ? .leading : .trailing)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: notice.detail)
            .transaction { $0.disablesAnimations = false }
        }
    }

    @ViewBuilder private var trailing: some View {
        if let content = notice.notification {
            Text(content.compactDetail)
                .font(Font(NotchNotificationBannerLayout.messageFont as CTFont))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(NotchNotificationBannerLayout.messageLines(stripHeight: geometry.stripHeight))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else if let level = notice.level {
            NotchMeter(value: level, height: 5, tint: tint)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: level)
                .transaction { $0.disablesAnimations = false }
        } else {
            Text(notice.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(textTint.opacity(0.8))
                .lineLimit(1)
                .truncationMode(notice.event == .accessory ? .middle : .tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct NotchTrackArtwork: View {
    @ObservedObject private var music = NotchMusicService.shared
    let size: CGFloat

    var body: some View { NotchArtwork(image: music.artwork, size: size) }
}

struct NotchExpandedLevelView: View {
    let notice: NotchNotice

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notice.symbol)
                .frame(width: 18)
            NotchMeter(value: notice.level ?? 0, height: 5, tint: .white)
                .frame(maxWidth: 96)
            Text(notice.detail)
                .monospacedDigit()
                .fixedSize()
        }
        .font(.system(size: 11, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.accessibilityText)
    }
}
