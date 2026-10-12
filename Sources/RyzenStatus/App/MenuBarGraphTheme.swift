// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The palette the menu bar graphs (history, cores, ring and network) draw
/// with. Light and dark pick their theme separately: a color that reads on
/// the dark graph pill of a light menu bar can disappear on a dark one.
enum MenuBarGraphTheme: String, CaseIterable {
    case system, mono
    case blue, green, aqua, red, purple, indigo, yellow, pink, orange, graphite
    case softYellow, softGreen, softBlue, softPink, softPurple, softOrange

    static func current(dark: Bool, defaults: UserDefaults = .standard) -> MenuBarGraphTheme {
        let key = dark ? DefaultsKey.menuBarGraphThemeDark : DefaultsKey.menuBarGraphThemeLight
        let raw = Defaults.sanitizedMenuBarGraphTheme(defaults.string(forKey: key) ?? "")
        return MenuBarGraphTheme(rawValue: raw) ?? .system
    }
}

/// What sits behind a graph on a light menu bar. A dark pill keeps the
/// saturated theme colors legible on any wallpaper; an outline keeps the
/// graph as light as the rest of the bar. Dark menu bars always use the outline.
enum MenuBarGraphLightBackground: String, CaseIterable {
    case filled, outline

    static func current(_ defaults: UserDefaults = .standard) -> MenuBarGraphLightBackground {
        let raw = Defaults.sanitizedMenuBarGraphLightBackground(
            defaults.string(forKey: DefaultsKey.menuBarGraphLightBackground) ?? "")
        return MenuBarGraphLightBackground(rawValue: raw) ?? .filled
    }
}

/// Width of a history graph box. One column per point, so this is also how
/// many seconds of history the graph shows at the default sampling cadence.
enum MenuBarGraphHistoryWidth: String, CaseIterable {
    case narrow, standard, wide

    var points: CGFloat {
        switch self {
        case .narrow: return 28
        case .standard: return 40
        case .wide: return 56
        }
    }

    static func current(_ defaults: UserDefaults = .standard) -> MenuBarGraphHistoryWidth {
        let raw = Defaults.sanitizedMenuBarGraphHistoryWidth(
            defaults.string(forKey: DefaultsKey.menuBarGraphHistoryWidth) ?? "")
        return MenuBarGraphHistoryWidth(rawValue: raw) ?? .standard
    }
}

/// Where the upload and download columns grow inside the network graph.
enum MenuBarNetworkGraphLayout: String, CaseIterable {
    /// Upload rises from the middle, download hangs below it.
    case mirrored
    /// Upload hangs from the top edge, download rises from the bottom edge.
    case split
    /// Both rise: upload in the top half, download in the bottom half.
    case rising

    static func current(_ defaults: UserDefaults = .standard) -> MenuBarNetworkGraphLayout {
        let raw = Defaults.sanitizedMenuBarNetworkGraphLayout(
            defaults.string(forKey: DefaultsKey.menuBarNetworkGraphLayout) ?? "")
        return MenuBarNetworkGraphLayout(rawValue: raw) ?? .mirrored
    }
}

/// The three colors one graph needs: the main series, and the companions
/// stacked or paired series (system time, upload, wired memory) use.
struct MenuBarGraphColors: Equatable {
    let primary: MenuBarUsageBarSupport.RGB
    let secondary: MenuBarUsageBarSupport.RGB
    let tertiary: MenuBarUsageBarSupport.RGB
}

enum MenuBarGraphPalette {
    typealias RGB = MenuBarUsageBarSupport.RGB

    /// The macOS accent hues, so the default theme matches whatever accent
    /// the user already chose for the system.
    static let blue = rgb(0x007AFF)
    static let green = rgb(0x62BA46)
    static let aqua = rgb(0x15E4FC)
    static let red = rgb(0xFF5257)
    static let purple = rgb(0xA550A7)
    static let indigo = rgb(0x5E5CE6)
    static let yellow = rgb(0xFFC600)
    static let pink = rgb(0xF74F9E)
    static let orange = rgb(0xF7821B)
    static let graphite = rgb(0x8C8C8C)

    /// Themes the system accent is matched against, in tie-break order.
    static let baseThemes: [MenuBarGraphTheme] = [
        .green, .blue, .aqua, .red, .purple, .indigo, .yellow, .pink, .orange, .graphite,
    ]

    /// Main color plus two companions picked to stay distinct from it and
    /// from each other when stacked in a few points of height.
    static func baseColors(of theme: MenuBarGraphTheme) -> MenuBarGraphColors? {
        switch theme {
        case .green: return MenuBarGraphColors(primary: green, secondary: pink, tertiary: blue)
        case .blue: return MenuBarGraphColors(primary: blue, secondary: pink, tertiary: yellow)
        case .aqua: return MenuBarGraphColors(primary: aqua, secondary: pink, tertiary: yellow)
        case .red: return MenuBarGraphColors(primary: red, secondary: blue, tertiary: yellow)
        case .purple: return MenuBarGraphColors(primary: purple, secondary: blue, tertiary: yellow)
        case .indigo: return MenuBarGraphColors(primary: indigo, secondary: red, tertiary: yellow)
        case .yellow: return MenuBarGraphColors(primary: yellow, secondary: blue, tertiary: pink)
        case .pink: return MenuBarGraphColors(primary: pink, secondary: blue, tertiary: yellow)
        case .orange: return MenuBarGraphColors(primary: orange, secondary: blue, tertiary: pink)
        case .graphite: return MenuBarGraphColors(primary: graphite, secondary: blue, tertiary: pink)
        case .system, .mono, .softYellow, .softGreen, .softBlue, .softPink, .softPurple, .softOrange:
            return nil
        }
    }

    /// Muted variants keep their base theme's companions.
    static func softVariant(of theme: MenuBarGraphTheme) -> (main: RGB, base: MenuBarGraphTheme)? {
        switch theme {
        case .softYellow: return (rgb(0xF3B036), .yellow)
        case .softGreen: return (rgb(0x427E82), .green)
        case .softBlue: return (rgb(0x507791), .blue)
        case .softPink: return (rgb(0xCD565A), .pink)
        case .softPurple: return (rgb(0x5D6291), .purple)
        case .softOrange: return (rgb(0xEF8056), .orange)
        default: return nil
        }
    }

    /// `accent` feeds the system theme; `mono` is the single tone the mono
    /// theme draws with, which the caller picks to contrast with the graph box.
    static func colors(for theme: MenuBarGraphTheme, accent: RGB, mono: RGB) -> MenuBarGraphColors {
        if theme == .mono {
            return MenuBarGraphColors(primary: mono, secondary: mono, tertiary: mono)
        }
        if theme == .system {
            let companions = baseColors(of: nearestBaseTheme(to: accent)) ?? baseColors(of: .blue)!
            return MenuBarGraphColors(primary: accent,
                                      secondary: companions.secondary,
                                      tertiary: companions.tertiary)
        }
        if let soft = softVariant(of: theme), let base = baseColors(of: soft.base) {
            return MenuBarGraphColors(primary: soft.main, secondary: base.secondary, tertiary: base.tertiary)
        }
        return baseColors(of: theme) ?? baseColors(of: .blue)!
    }

    /// A custom accent borrows the companions of the closest built-in theme,
    /// so an off-palette accent still gets a pairing that was chosen to contrast.
    static func nearestBaseTheme(to color: RGB) -> MenuBarGraphTheme {
        var best = MenuBarGraphTheme.blue
        var bestDistance = Double.infinity
        for theme in baseThemes {
            guard let main = baseColors(of: theme)?.primary else { continue }
            let dr = (color.red - main.red) * 255
            let dg = (color.green - main.green) * 255
            let db = (color.blue - main.blue) * 255
            let distance = dr * dr + dg * dg + db * db
            if distance < bestDistance {
                bestDistance = distance
                best = theme
            }
        }
        return best
    }

    private static func rgb(_ hex: UInt32) -> RGB {
        RGB(red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
