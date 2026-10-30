// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import CoreGraphics

/// The tops of other apps' windows, where the companion out on the desktop
/// climbs, walks and rides. Only where a window is and which app owns it is
/// read, never its title or what it shows, so no permission is needed. The
/// rules are pure and tested without a window; `NotchMascotWindowReader`
/// reads the windows themselves. Points are the screen's, y growing upward.
enum NotchMascotLedges {
    /// A window on screen, front to back as the window server lists them.
    struct Window: Equatable {
        var id: CGWindowID
        var pid: pid_t
        var frame: CGRect
    }

    /// The part of a window's top edge that can be seen and stood on.
    struct Ledge: Equatable {
        var window: CGWindowID
        var pid: pid_t
        var y: CGFloat
        var minX: CGFloat
        var maxX: CGFloat

        var width: CGFloat { maxX - minX }

        /// Whether feet at `x` are over it.
        func holds(_ x: CGFloat) -> Bool { x >= minX && x <= maxX }
    }

    /// Windows narrower or shorter than this are left alone: palettes,
    /// popovers and tooltips are no place to stand.
    static let minimumWindow = CGSize(width: 160, height: 90)
    /// A visible stretch of edge narrower than this is not worth a climb.
    static let minimumLedge: CGFloat = 70

    /// The ledges among `windows`, listed front to back, on the screens'
    /// usable areas `areas`. A window's top is cut wherever a window in front
    /// of it covers the band from the edge up to `headroom` above it, where
    /// the companion would stand, and it is no ledge at all within
    /// `headroom` of the menu bar or too close to the floor to need a climb.
    static func ledges(in windows: [Window], areas: [CGRect], headroom: CGFloat) -> [Ledge] {
        var result: [Ledge] = []
        for (index, window) in windows.enumerated() {
            guard window.frame.width >= minimumWindow.width, window.frame.height >= minimumWindow.height else { continue }
            let y = window.frame.maxY
            guard let area = areas.first(where: { $0.minX <= window.frame.midX && window.frame.midX <= $0.maxX
                                                   && $0.minY <= y && y <= $0.maxY + 1 }),
                  y <= area.maxY - headroom, y - area.minY >= headroom * 0.6
            else { continue }
            var pieces = [max(area.minX, window.frame.minX)...min(area.maxX, window.frame.maxX)]
            for front in windows[..<index] where front.frame.minY < y + headroom && front.frame.maxY > y - 2 {
                pieces = subtract(front.frame.minX...front.frame.maxX, from: pieces)
                if pieces.isEmpty { break }
            }
            for piece in pieces where piece.upperBound - piece.lowerBound >= minimumLedge {
                result.append(Ledge(window: window.id, pid: window.pid, y: y,
                                    minX: piece.lowerBound, maxX: piece.upperBound))
            }
        }
        return result
    }

    /// `pieces` with `cut` taken out of each.
    static func subtract(_ cut: ClosedRange<CGFloat>, from pieces: [ClosedRange<CGFloat>]) -> [ClosedRange<CGFloat>] {
        pieces.flatMap { piece -> [ClosedRange<CGFloat>] in
            guard cut.lowerBound < piece.upperBound, cut.upperBound > piece.lowerBound else { return [piece] }
            var left: [ClosedRange<CGFloat>] = []
            if cut.lowerBound > piece.lowerBound { left.append(piece.lowerBound...cut.lowerBound) }
            if cut.upperBound < piece.upperBound { left.append(cut.upperBound...piece.upperBound) }
            return left
        }
    }

    /// The ledge under feet at `point`, the highest one it stands on within
    /// `tolerance`, if any.
    static func ledge(under point: CGPoint, in ledges: [Ledge], tolerance: CGFloat = 1.5) -> Ledge? {
        ledges.filter { $0.holds(point.x) && abs($0.y - point.y) <= tolerance }.max { $0.y < $1.y }
    }

    /// The ledge a body falling from `previous` to `point` comes down on:
    /// the highest whose edge it crossed, with its feet over it.
    static func landing(from previous: CGPoint, to point: CGPoint, in ledges: [Ledge]) -> Ledge? {
        ledges.filter { $0.holds(point.x) && $0.y <= previous.y + 0.5 && $0.y >= point.y }.max { $0.y < $1.y }
    }

    // MARK: Climbing

    /// How high above the higher end a leap rises: low enough that it comes
    /// down onto the edge without bouncing off it.
    static let leapClearance: CGFloat = 16
    /// Ledges farther than this to either side are too far to leap to.
    static let leapReach: CGFloat = 640

    /// The launch velocity that carries a body from `start` to `target`
    /// under `gravity`, rising `clearance` above the higher of the two, with
    /// its sideways speed fading by `drag` every 16 ms as it flies.
    static func leap(from start: CGPoint, to target: CGPoint, gravity: CGFloat, drag: CGFloat,
                     clearance: CGFloat = leapClearance) -> CGVector {
        let apex = max(start.y, target.y) + clearance
        let rise = apex - start.y
        let up = (2 * gravity * rise).squareRoot()
        let time = up / gravity + (2 * (apex - target.y) / gravity).squareRoot()
        // Distance under drag: v·∫ e^(r·t) dt over the flight, r = ln(drag)/16 ms.
        let rate = log(drag) / 0.016
        let reach = rate == 0 ? time : (exp(rate * time) - 1) / rate
        return CGVector(dx: (target.x - start.x) / max(0.01, reach), dy: up)
    }

    /// Where on `ledge` it aims for, coming from `x`: the nearest spot at
    /// least `margin` in from either end, nudged by `jitter` in -1...1.
    static func spot(on ledge: Ledge, from x: CGFloat, margin: CGFloat, jitter: CGFloat) -> CGFloat {
        let low = ledge.minX + margin, high = ledge.maxX - margin
        guard low < high else { return (ledge.minX + ledge.maxX) / 2 }
        let nearest = min(high, max(low, x))
        return min(high, max(low, nearest + jitter * min(80, (high - low) / 2)))
    }

    /// The ledge it climbs from `position`: within reach, above it and not
    /// the one it stands on, those of the app in front first.
    static func climbTarget(from position: CGPoint, in ledges: [Ledge], standingOn current: CGWindowID?,
                            preferring pid: pid_t?, minimumWidth: CGFloat, random: () -> Double) -> Ledge? {
        let reachable = ledges.filter {
            $0.window != current && $0.y > position.y + 30 && $0.width >= minimumWidth
                && distance(from: position.x, to: $0) <= leapReach
        }
        guard !reachable.isEmpty else { return nil }
        if let pid, random() < 0.7, let own = reachable.filter({ $0.pid == pid }).min(by: {
            distance(from: position.x, to: $0) < distance(from: position.x, to: $1)
        }) {
            return own
        }
        return reachable[min(reachable.count - 1, Int(random() * Double(reachable.count)))]
    }

    static func distance(from x: CGFloat, to ledge: Ledge) -> CGFloat {
        x < ledge.minX ? ledge.minX - x : x > ledge.maxX ? x - ledge.maxX : 0
    }

    /// Whether a window that moved from `old` to `new` came near enough to
    /// feet at `feet` for it to jump on and hitch a ride: its top edge
    /// within a leap above, and the feet under it or close beside.
    static func hitchable(old: CGRect, new: CGRect, feet: CGPoint, figure: CGFloat) -> Bool {
        let moved = hypot(new.minX - old.minX, new.maxY - old.maxY) >= 6
        let above = new.maxY - feet.y
        let beside = feet.x >= new.minX - 60 && feet.x <= new.maxX + 60
        return moved && beside && above >= figure * 0.8 && above <= figure * 3.2
    }

    // MARK: The app in front

    /// What kind of app is in front, for the companion to react to.
    enum AppKind: Equatable {
        case browser, music, video, code, chat, files, design, game
    }

    static func kind(of bundleID: String?) -> AppKind? {
        guard let id = bundleID?.lowercased() else { return nil }
        let table: [(AppKind, [String])] = [
            (.browser, ["com.apple.safari", "com.google.chrome", "org.mozilla.firefox", "company.thebrowser.browser",
                        "com.microsoft.edgemac", "com.brave.browser", "com.operasoftware.opera", "com.vivaldi.vivaldi",
                        "app.zen-browser.zen", "org.chromium.chromium", "com.kagi.kagimacos"]),
            (.music, ["com.apple.music", "com.spotify.client", "com.apple.garageband10", "com.apple.logic10",
                      "com.tidal.desktop", "com.deezer.deezer-desktop", "com.ableton.live"]),
            (.video, ["com.apple.tv", "com.apple.quicktimeplayerx", "org.videolan.vlc", "com.colliderli.iina",
                      "com.netflix", "tv.plex.desktop", "com.apple.finalcutapp"]),
            (.code, ["com.apple.dt.xcode", "com.apple.terminal", "com.googlecode.iterm2", "com.microsoft.vscode",
                     "com.todesktop.230313mzl4w4u92", "com.panic.nova", "dev.zed.zed", "com.sublimetext.4",
                     "com.mitchellh.ghostty", "dev.warp.warp-stable", "com.jetbrains"]),
            (.chat, ["com.apple.mobilesms", "com.apple.mail", "net.whatsapp.whatsapp", "ru.keepcoder.telegram",
                     "com.tinyspeck.slackmacgap", "com.hnc.discord", "com.microsoft.teams", "us.zoom.xos",
                     "com.apple.facetime", "org.whispersystems.signal-desktop"]),
            (.files, ["com.apple.finder", "com.apple.preview"]),
            (.design, ["com.figma.desktop", "com.bohemiancoding.sketch3", "com.adobe.photoshop", "com.pixelmatorteam.pixelmator.x",
                       "com.apple.freeform", "com.seriflabs.affinitydesigner2"]),
            (.game, ["com.valvesoftware.steam", "com.openemu.openemu", "com.apple.chess"]),
        ]
        return table.first { entry in entry.1.contains { id == $0 || id.hasPrefix($0 + ".") } }?.0
    }

    /// The reaction for an app of `kind` coming to the front.
    static func reaction(to kind: AppKind) -> NotchMascotReaction {
        switch kind {
        case .browser: return .peek
        case .music: return .groove
        case .video: return .relax
        case .code: return .ready
        case .chat: return .wave
        case .files: return .lookAround
        case .design: return .perk
        case .game: return .bounce
        }
    }
}

/// Reads where the other apps' windows are from the window server.
enum NotchMascotWindowReader {
    /// The normal windows of other apps on screen, front to back, in screen
    /// points with y growing upward.
    static func windows() -> [NotchMascotLedges.Window] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }
        let own = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let frame = frame(of: info)
            else { return nil }
            return NotchMascotLedges.Window(id: id, pid: pid, frame: frame)
        }
    }

    /// Where window `id` is now, or nil once it is closed, minimized or on
    /// another Space.
    static func frame(of id: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCreateDescriptionFromArray([id] as CFArray) as? [[String: Any]],
              let info = list.first, (info[kCGWindowIsOnscreen as String] as? Bool) == true
        else { return nil }
        return frame(of: info)
    }

    private static func frame(of info: [String: Any]) -> CGRect? {
        guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else { return nil }
        // The window server counts down from the top of the main display.
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }
}
