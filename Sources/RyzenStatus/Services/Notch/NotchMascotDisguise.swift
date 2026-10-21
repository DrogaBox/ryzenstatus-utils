// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The shifter copies whoever it plays with: while a play runs in the island
/// it takes the other's figure and what it wears, and goes back to being a
/// blob when the play is over. Readable from anywhere, since every look is
/// resolved through it.
enum NotchMascotDisguise {
    private static let lock = NSLock()
    private static var copy: (style: NotchMascotStyle, accessory: NotchMascotAccessory)?

    static var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return copy != nil
    }

    /// The figure and the clothes a shifter shows in a disguise of `other`.
    static func begin(copying other: NotchMascotLook) {
        guard other.style != .shifter else { return }
        lock.lock()
        copy = (other.style, other.accessory)
        lock.unlock()
    }

    static func end() {
        lock.lock()
        copy = nil
        lock.unlock()
    }

    /// `look` as it shows now: a shifter in a disguise wears the copy.
    static func apply(to look: NotchMascotLook) -> NotchMascotLook {
        guard look.style == .shifter else { return look }
        lock.lock()
        let current = copy
        lock.unlock()
        guard let current else { return look }
        var disguised = look
        disguised.style = current.style
        disguised.accessory = current.accessory
        return disguised
    }

    /// Disguises the shifter of the pair, if there is exactly one, as the other.
    static func beginForPair(leader: NotchMascotLook, friend: NotchMascotLook?) {
        guard let friend else { return }
        if leader.style == .shifter { begin(copying: friend) } else if friend.style == .shifter { begin(copying: leader) }
    }
}
