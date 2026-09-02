// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Darwin
import Foundation

/// Cheap front-to-back WindowServer lookup used before asking another app
/// about its Accessibility tree. This keeps ordinary mouse clicks away from
/// cross-process waits while still pinning a later drag to the same window.
enum WindowServerWindowHitTest {
    static func candidate(at point: CGPoint,
                          pidIsEligible: (pid_t) -> Bool = { _ in true }) -> WindowServerWindowCandidate? {
        WindowServerSupport.windowCandidate(in: WindowServerSupport.onScreenWindowInfo(),
                                            at: point,
                                            ownProcessID: getpid(),
                                            pidIsEligible: pidIsEligible)
    }
}

struct WindowServerWindowCandidate {
    let pid: pid_t
    let windowID: CGWindowID
    let frame: CGRect
}

/// Cheap front-to-back WindowServer lookup used before asking another app
/// about its Accessibility tree. This keeps ordinary mouse clicks away from
/// cross-process waits while still pinning a later drag to the same window.
enum WindowServerWindowHitTest {
    static func candidate(at point: CGPoint,
                          pidIsEligible: (pid_t) -> Bool = { _ in true }) -> WindowServerWindowCandidate? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for window in windows {
            guard let bounds = bounds(from: window),
                  bounds.width >= 80, bounds.height >= 80,
                  point.x >= bounds.minX, point.x <= bounds.maxX,
                  point.y >= bounds.minY, point.y <= bounds.maxY,
                  let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != getpid(),
                  pidIsEligible(pid),
                  let number = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            else { continue }
            return WindowServerWindowCandidate(pid: pid,
                                                windowID: CGWindowID(number),
                                                frame: bounds)
        }
        return nil
    }

    private static func bounds(from window: [String: Any]) -> CGRect? {
        guard let raw = window[kCGWindowBounds as String] as? [String: Any],
              let x = (raw["X"] as? NSNumber)?.doubleValue,
              let y = (raw["Y"] as? NSNumber)?.doubleValue,
              let width = (raw["Width"] as? NSNumber)?.doubleValue,
              let height = (raw["Height"] as? NSNumber)?.doubleValue else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

enum WindowServerTrafficLightHitTest {
    // Cheap WindowServer gate before AX hit-testing. Some apps can stall when
    // queried through Accessibility in the middle of ordinary mouse clicks.
    static func candidate(at point: CGPoint,
                          button: TrafficLightButton,
                          pidIsEligible: (pid_t) -> Bool = { _ in true }) -> TrafficLightCandidate? {
        WindowServerSupport.trafficLightCandidate(in: WindowServerSupport.onScreenWindowInfo(),
                                                  at: point,
                                                  button: button,
                                                  ownProcessID: getpid(),
                                                  pidIsEligible: pidIsEligible)
    }
}
