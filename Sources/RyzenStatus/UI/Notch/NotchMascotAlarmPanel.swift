// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// The clear window a sign is shown in: it takes the keyboard without
/// bringing the app forward, so the sign can be typed into and answered
/// from the keys, and says when it loses the keyboard or Esc is pressed.
final class NotchMascotAlarmPanel: NSPanel {
    var onCancel: (() -> Void)?
    /// Sees each key pressed before the sign's controls do; true when it
    /// took the key.
    var onKey: ((NSEvent) -> Bool)?
    var onResign: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    static func make() -> NotchMascotAlarmPanel {
        let panel = NotchMascotAlarmPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovable = false
        // Over the companions and what they hold.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.collectionBehavior = NotchPanel.overlayCollectionBehavior
        return panel
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        onResign?()
    }
}

/// Where a sign's stick meets it, worked out by whoever shows the sign.
final class NotchMascotAlarmSignLayout: ObservableObject {
    /// From the window's left edge to the stick's middle.
    @Published var stickX: CGFloat = 0
    @Published var stickLength: CGFloat = 0
    /// The stick runs up from the sign, as when it hangs from the island.
    @Published var stickUp = false
}

/// Who holds a sign up, and so where it shows.
enum NotchMascotAlarmAnchor {
    /// The companion out on the desktop, the stick in its hand.
    case held(NotchMascotDesktop)
    /// Hanging under the closed island from the companion resting there,
    /// its centre on screen and its size.
    case hanging(center: CGPoint, size: CGFloat)
    /// No one: up in the middle of the main screen.
    case free

    /// The anchor for the companion now: out on the desktop, resting in
    /// the island, or neither.
    static func current(preferring desktop: NotchMascotDesktop? = nil) -> NotchMascotAlarmAnchor {
        if let desktop, desktop.isOut, !desktop.fusedAway { return .held(desktop) }
        if let lead = NotchService.shared.mascotAlarmCast?.lead, lead.isOut { return .held(lead) }
        if let rest = NotchService.shared.mascotAlarmRest { return .hanging(center: rest.center, size: rest.size) }
        return .free
    }

    /// The window for a board `board` big with `headroom` over it, and its
    /// stick, kept on the screen it shows on.
    func placement(board: CGSize, headroom: CGFloat = 0) -> (frame: CGRect, stickX: CGFloat, stickLength: CGFloat,
                                                              stickUp: Bool) {
        switch self {
        case .held(let desktop):
            let size = desktop.figureSize
            let area = desktop.playScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            // The stick at its side, from just below its hand to the board over its head.
            let stickScreenX = desktop.screenCenter.x + size * 0.42
            let stickBottom = desktop.hand(toward: 1).y - size * 0.08
            let boardBottom = max(desktop.head.y + 10, stickBottom + 24)
            let length = boardBottom - stickBottom + 4
            let x = min(max(area.minX + 4, desktop.screenCenter.x - board.width / 2), area.maxX - board.width - 4)
            let height = board.height + headroom + length
            let stickX = min(board.width - 14, max(14, stickScreenX - x))
            return (CGRect(x: x, y: stickBottom, width: board.width, height: height), stickX, length, false)
        case .hanging(let center, let size):
            let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
            let area = screen?.frame ?? .zero
            let stickTop = center.y - size * 0.15
            let boardTop = center.y - size / 2 - 22
            let length = stickTop - boardTop + 4
            let x = min(max(area.minX + 4, center.x - board.width / 2), area.maxX - board.width - 4)
            let height = board.height + length - 4
            let stickX = min(board.width - 14, max(14, center.x - x))
            return (CGRect(x: x, y: stickTop - height, width: board.width, height: height), stickX, length, true)
        case .free:
            let area = NSScreen.main?.visibleFrame ?? .zero
            let height = board.height + headroom
            return (CGRect(x: area.midX - board.width / 2, y: area.maxY - height - area.height * 0.12,
                           width: board.width, height: height), board.width / 2, 0, false)
        }
    }
}

/// A board with its stick under it, or over it when it hangs.
struct NotchMascotAlarmHeldSign<Board: View>: View {
    @ObservedObject var layout: NotchMascotAlarmSignLayout
    var headroom: CGFloat = 0
    @ViewBuilder var board: Board

    var body: some View {
        VStack(spacing: 0) {
            if layout.stickUp { stick.padding(.bottom, -4).zIndex(0) }
            Color.clear.frame(height: layout.stickUp ? 0 : headroom)
            board.zIndex(1)
            if !layout.stickUp { stick.padding(.top, -4).zIndex(0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var stick: some View {
        NotchMascotAlarmStick(length: layout.stickLength)
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: layout.stickX - 4)
    }
}
