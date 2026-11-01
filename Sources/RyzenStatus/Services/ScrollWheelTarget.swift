// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import CoreGraphics

/// AppKit state is published on main; the pointer tap only reads the cache
/// and occasionally the WindowServer list. It never waits for main.
final class ScrollWheelTarget {
    static let shared = ScrollWheelTarget()

    private let cache = ScrollWheelTargetCache(ownProcessID: ProcessInfo.processInfo.processIdentifier)
    private var observers: [NSObjectProtocol] = []

    /// `NSApplication.didUpdateNotification` follows every pass of the event
    /// loop, and the window order (`NSApp.orderedWindows`) is a synchronous
    /// WindowServer query: asked on every pass it took a tenth of the main
    /// thread whenever something on screen moved. The order is asked again
    /// only when the set of windows or the key window changes, or once the
    /// last answer is half a second old. Frames and visibility cost nothing
    /// and are read on every pass.
    private static let orderLifetime: CFTimeInterval = 0.5
    private var orderedWindowIDs: [CGWindowID] = []
    private var orderedFor: (windows: [CGWindowID], key: Int)?
    private var orderedAt: CFTimeInterval = 0

    private init() {}

    func setEnabled(_ enabled: Bool) {
        precondition(Thread.isMainThread)
        cache.setEnabled(enabled)
        guard enabled else {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            orderedFor = nil
            return
        }
        refresh()
        guard observers.isEmpty else { return }
        for name in [NSApplication.didUpdateNotification, NSWindow.didChangeOcclusionStateNotification,
                     NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in self?.refresh() })
        }
    }

    private func refresh() {
        let windows = NSApp.windows.compactMap { window -> ScrollWheelTargetCache.OwnWindow? in
            guard let id = CGWindowID(exactly: window.windowNumber) else { return nil }
            return .init(id: id, frame: window.frame, visible: window.isVisible && !window.isMiniaturized,
                         alpha: Double(window.alphaValue), ignoresMouseEvents: window.ignoresMouseEvents,
                         level: window.level.rawValue)
        }.sorted { $0.id < $1.id }
        let shown = (windows: windows.filter(\.visible).map(\.id), key: NSApp.keyWindow?.windowNumber ?? 0)
        let now = CACurrentMediaTime()
        if orderedFor.map({ $0 != shown }) ?? true || now - orderedAt >= Self.orderLifetime {
            orderedWindowIDs = NSApp.orderedWindows.compactMap { CGWindowID(exactly: $0.windowNumber) }
            orderedFor = shown
            orderedAt = now
        }
        cache.update(ownWindows: windows, orderedWindowIDs: orderedWindowIDs)
    }

    func contains(_ point: CGPoint) -> Bool {
        cache.contains(point)
    }

    var clickThroughWindowIDs: Set<CGWindowID> { cache.clickThroughWindowIDs }
}
