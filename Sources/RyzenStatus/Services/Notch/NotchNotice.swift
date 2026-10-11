// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Foundation

struct NotchNotice: Equatable {
    let event: NotchEvent
    let title: String
    let detail: String
    let symbol: String
    var level: Double? = nil
    var notification: NotchNotificationContent? = nil
    var notificationID: UUID? = nil
    /// With the companion on, it takes the symbol's place in the notice and
    /// plays this, so the notice itself is its reaction.
    var mascot: NotchMascotReaction? = nil
    /// A banner that replaces one still on screen keeps at least its wings,
    /// so a burst of messages does not resize the island with each one.
    var minimumWings = NotchNoticeWings.zero

    /// Each side as wide as what it shows, so neither ends in a band of
    /// empty black: the island reaches further toward its wider side.
    var preferredWings: NotchNoticeWings { preferredWings(wrapsMessage: false) }

    /// The sides this notice takes beside a camera, as its strip draws them.
    func wings(in geometry: NotchGeometry) -> NotchNoticeWings {
        geometry.noticeWings(preferredWings(
            wrapsMessage: NotchNotificationBannerLayout.messageLines(stripHeight: geometry.stripHeight) > 1))
    }

    func preferredWings(wrapsMessage: Bool) -> NotchNoticeWings {
        if let notification {
            let fitted = NotchNotificationBannerLayout.wings(for: notification, wrapsMessage: wrapsMessage)
            return NotchNoticeWings(leading: max(minimumWings.leading, fitted.leading),
                                    trailing: max(minimumWings.trailing, fitted.trailing))
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let leading = ((level == nil ? title : detail) as NSString).size(withAttributes: [.font: font]).width
        // A level's wings are as wide as its mark and its reading; the meter
        // takes the same width on the other side.
        if level != nil, event != .accessory {
            let wing = ceil(Self.levelInset + 18 + 8 + leading)
            return NotchNoticeWings(leading: wing, trailing: wing)
        }
        // Long accessory names still use bounded truncation.
        let maximum: CGFloat = event == .accessory && level == nil ? 160 : 240
        func fitted(_ content: CGFloat) -> CGFloat { min(maximum, max(Self.minimumWing, ceil(content) + 16 + cameraGap)) }
        // An empty title leaves the mark alone, without the space after it.
        let mark = fitted(leading > 0 ? leading + 18 + 8 : 18)
        guard level == nil else { return NotchNoticeWings(leading: mark, trailing: mark) }
        return NotchNoticeWings(leading: mark, trailing: fitted((detail as NSString).size(withAttributes: [.font: font]).width))
    }

    /// The wider side, for what still takes one width for both.
    var preferredWingWidth: CGFloat { preferredWings.widest }

    /// The narrowest side a text notice keeps: its curved end and some air.
    static let minimumWing: CGFloat = 36

    /// Room a level keeps inside its curved ends, as wide as its wings had
    /// when they were a fixed 80 pt.
    static let levelInset: CGFloat = 13

    /// Two lines of text sit at the island's two ends, each as far from its
    /// curved edge, so a short one leaves its spare room beside the camera
    /// rather than at one end. Levels and banners keep their own layout.
    var readsFromEnds: Bool { level == nil && notification == nil }

    /// Room text keeps from the camera; battery labels need breathing room
    /// at both the curved edge and the camera.
    var cameraGap: CGFloat { event == .battery ? 16 : readsFromEnds ? 6 : 0 }

    var accessibilityText: String {
        notification?.accessibilityText ?? [title, detail].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Room a closed notice keeps inside its curved ends, which a side as
    /// narrow as its content still clears; only a display too narrow for a
    /// side's content takes some of it.
    func inset(wing: CGFloat) -> CGFloat {
        level != nil && event != .accessory ? Self.levelInset : min(NotchNotificationBannerLayout.inset, wing / 2)
    }

    /// Where the companion stands in this notice, as an offset of its centre
    /// from the camera's: at the leading end, past the inset, since a notice
    /// that carries it reads from the ends.
    func mascotOffset(in geometry: NotchGeometry) -> CGFloat {
        let wing = wings(in: geometry).leading
        return -(geometry.noticeCameraGap / 2 + wing) + inset(wing: wing) + NotchMascotSupport.noticeSize / 2
    }

    func previewContentHeight(width: CGFloat) -> CGFloat {
        guard let notification else { return 0 }
        return NotchNotificationPreviewLayout.contentHeight(for: notification, width: width)
    }
}
