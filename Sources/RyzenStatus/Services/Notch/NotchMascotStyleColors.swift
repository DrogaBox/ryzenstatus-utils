// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The colour picked for each figure, remembered by the figure rather than
/// by the place it was picked in. A cat painted orange as the companion is
/// still orange when it comes out as the friend, drops by on a visit, or is
/// picked as the companion again after a while as another figure.
///
/// Settings keeps writing the companion's and the friend's colours where it
/// always has; `track(in:)` watches those as preferences change. A colour
/// changed for a figure is remembered for it, and a figure picked anew takes
/// back the colour it had last.
enum NotchMascotStyleColors {
    /// One figure's colour: a palette, or a hand-picked hex that wins over it.
    struct Paint: Equatable {
        var palette: NotchMascotPalette
        var custom: NotchMascotColor?

        /// How it is stored: the palette's name, or "#RRGGBB".
        var stored: String { custom.map { "#" + $0.hex } ?? palette.rawValue }

        init(palette: NotchMascotPalette, custom: NotchMascotColor? = nil) {
            self.palette = palette
            self.custom = custom
        }

        init?(stored: String) {
            if stored.hasPrefix("#") {
                guard let color = NotchMascotColor(hex: String(stored.dropFirst())) else { return nil }
                self.init(palette: .pearl, custom: color)
            } else {
                guard let palette = NotchMascotPalette(rawValue: stored) else { return nil }
                self.init(palette: palette)
            }
        }

        /// `look` in this colour.
        func paint(_ look: NotchMascotLook) -> NotchMascotLook {
            var look = look
            look.palette = palette
            look.customColor = custom
            return look
        }
    }

    /// The colour remembered for `style`, if one was ever picked for it.
    static func paint(for style: NotchMascotStyle, in defaults: UserDefaults = .standard) -> Paint? {
        (defaults.dictionary(forKey: DefaultsKey.notchMascotStyleColors)?[style.rawValue] as? String).flatMap(Paint.init(stored:))
    }

    static func remember(_ paint: Paint, for style: NotchMascotStyle, in defaults: UserDefaults = .standard) {
        var all = defaults.dictionary(forKey: DefaultsKey.notchMascotStyleColors) ?? [:]
        guard all[style.rawValue] as? String != paint.stored else { return }
        all[style.rawValue] = paint.stored
        defaults.set(all, forKey: DefaultsKey.notchMascotStyleColors)
    }

    // MARK: Following Settings

    /// A slot Settings paints: the companion's or the friend's.
    private struct Slot {
        let style: String
        let palette: String
        let custom: String
    }

    private static let companion = Slot(style: DefaultsKey.notchMascotStyle, palette: DefaultsKey.notchMascotPalette,
                                        custom: DefaultsKey.notchMascotCustomColor)
    private static let friend = Slot(style: DefaultsKey.notchMascotDesktopFriend, palette: DefaultsKey.notchMascotFriendPalette,
                                     custom: DefaultsKey.notchMascotFriendCustomColor)

    /// What each slot held when last looked at: its figure and its colour.
    private static var seen: [String: (style: NotchMascotStyle?, paint: Paint?)] = [:]
    private static let lock = NSLock()

    /// Remembers a colour changed in Settings for the figure that wears it,
    /// and brings back the remembered colour of a figure newly picked. Runs
    /// as preferences change; what it writes changes nothing on the next run.
    static func track(in defaults: UserDefaults = .standard) {
        lock.lock()
        defer { lock.unlock() }
        for slot in [companion, friend] {
            let style = NotchMascotStyle(rawValue: defaults.string(forKey: slot.style) ?? "")
            let worn = current(slot, in: defaults)
            let before = seen[slot.style]
            seen[slot.style] = (style, worn)
            guard let style else { continue }
            guard let before else {
                // The first look: what is worn now is what it was picked in.
                if let worn, paint(for: style, in: defaults) == nil { remember(worn, for: style, in: defaults) }
                continue
            }
            if before.style != style, before.paint == worn {
                // Another figure, the colour untouched: it wears its own again.
                if let own = paint(for: style, in: defaults), own != worn {
                    write(own, to: slot, in: defaults)
                    seen[slot.style] = (style, own)
                }
            } else if before.paint != worn, let worn {
                remember(worn, for: style, in: defaults)
            }
        }
    }
    /// The colour a slot wears; the friend's is nil while it wears the companion's.
    private static func current(_ slot: Slot, in defaults: UserDefaults) -> Paint? {
        let custom = NotchMascotColor(hex: defaults.string(forKey: slot.custom) ?? "")
        let palette = NotchMascotPalette(rawValue: defaults.string(forKey: slot.palette) ?? "")
        if custom == nil, palette == nil { return nil }
        return Paint(palette: palette ?? .pearl, custom: custom)
    }

    private static func write(_ paint: Paint, to slot: Slot, in defaults: UserDefaults) {
        defaults.set(paint.custom?.hex ?? "", forKey: slot.custom)
        defaults.set(paint.palette.rawValue, forKey: slot.palette)
    }
}
