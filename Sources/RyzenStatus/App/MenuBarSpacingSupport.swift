// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// How tightly the menu bar metric blocks pack together. The standard reserve
/// keeps every number rock-steady by sizing blocks for their largest possible
/// value, which reads as wide gaps on short values (user feedback); compact
/// hugs the current number instead.
enum MenuBarMetricSpacing: String, CaseIterable {
    case standard, compact

    static var current: MenuBarMetricSpacing {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.menuBarMetricSpacing) ?? ""
        return MenuBarMetricSpacing(rawValue: Defaults.sanitizedMenuBarMetricSpacing(raw)) ?? .standard
    }
}
/// How a metric is drawn in the menu bar.
///
/// Text styles: a small label above the value, label and value on one line,
/// the value alone, or a symbol and the value. For readings with two values
/// (temperature and power, network, disk activity, frequency) the label-above
/// style is two lines with the name beside them, and value-only is the two
/// lines alone. Graph styles replace a usage reading with a gauge, a ring, a
/// history graph or one bar per core. "classic" is a former duplicate of
/// values that old settings may still carry; it reads as values.
enum MenuBarMetricAppearance: String, CaseIterable {
    case values, inline, valueOnly, iconValue, bars, pie, sparkline, histogram, classic

    /// Drawn as text, so a temperature can join it in the same block.
    var isText: Bool {
        switch self {
        case .values, .inline, .valueOnly, .iconValue, .classic: return true
        case .bars, .pie, .sparkline, .histogram: return false
        }
    }

    /// Every metric has a style of its own.
    static let styledMetrics: [MenuBarMetric] = MenuBarMetric.allCases

    /// The styles one metric can be drawn in, text styles first. A symbol is
    /// offered only where it is unique to the metric: there is no GPU symbol,
    /// and a thermometer or a bolt would read the same for CPU and GPU.
    static func allowed(for metric: MenuBarMetric) -> [MenuBarMetricAppearance] {
        switch metric {
        case .cpu: return [.values, .inline, .valueOnly, .bars, .pie, .sparkline, .histogram]
        case .gpu: return [.values, .inline, .valueOnly, .bars, .pie, .sparkline]
        case .memory: return [.values, .inline, .valueOnly, .iconValue, .bars, .pie, .sparkline]
        case .diskUsage: return [.values, .inline, .valueOnly, .iconValue, .bars, .pie]
        case .network: return [.values, .inline, .valueOnly, .sparkline]
        case .battery, .connectedDevices: return [.values, .inline, .valueOnly, .iconValue]
        default: return [.values, .inline, .valueOnly]
        }
    }

    /// What each metric showed before it had a choice, so an install that
    /// never picks a style keeps its menu bar as it was.
    static func defaultStyle(for metric: MenuBarMetric) -> MenuBarMetricAppearance {
        switch metric {
        case .cpuFrequency, .cpuTempPower, .gpuTempPower, .diskActivity: return .valueOnly
        case .battery: return .iconValue
        default: return .values
        }
    }

    /// Registered values for every per-metric style key.
    static var registeredStyleDefaults: [String: Any] {
        Dictionary(uniqueKeysWithValues: styledMetrics.map { ($0.styleKey, defaultStyle(for: $0).rawValue as Any) })
    }

    /// Whether the metric shows two values (two lines unless drawn inline).
    static func isDual(_ metric: MenuBarMetric) -> Bool {
        switch metric {
        case .cpuFrequency, .cpuTempPower, .gpuTempPower, .network, .diskActivity: return true
        default: return false
        }
    }

    /// The stored style of one metric, limited to the styles it offers.
    static func stored(for metric: MenuBarMetric, in defaults: UserDefaults = .standard) -> MenuBarMetricAppearance {
        var style = MenuBarMetricAppearance(rawValue: defaults.string(forKey: metric.styleKey) ?? "")
            ?? defaultStyle(for: metric)
        if style == .classic { style = .values }
        // Older builds drew every graph style on network as its history
        // graph, and "histogram" as history on GPU and memory.
        if !allowed(for: metric).contains(style) {
            switch (metric, style) {
            case (.network, .bars), (.network, .pie), (.network, .histogram),
                 (.gpu, .histogram), (.memory, .histogram):
                style = .sparkline
            default:
                style = defaultStyle(for: metric)
            }
        }
        return style
    }

    /// Whether a temperature reading is drawn inside its usage block right
    /// now (combine on, both pinned, usage drawn as text), so its own style
    /// does not apply. The same rule as `MenuBarRenderSettings.combinesTemperature`.
    static func drawnWithUsage(_ temperature: MenuBarMetric, in defaults: UserDefaults = .standard) -> Bool {
        let usage: MenuBarMetric
        switch temperature {
        case .cpuTemperature: usage = .cpu
        case .gpuTemperature:
            // With VRAM chosen the temperature always keeps its own block
            // and style, kext or no kext: the renderer decides from the same
            // setting (MenuBarRenderSettings.gpuTemperatureSource).
            if GPUTemperatureSource.from(defaults.string(forKey: DefaultsKey.gpuTemperatureSource)) == .memory {
                return false
            }
            usage = .gpu
        case .batteryTemperature: usage = .battery
        default: return false
        }
        return defaults.bool(forKey: DefaultsKey.menuBarCombineTemperatures)
            && defaults.bool(forKey: usage.defaultsKey) && defaults.bool(forKey: temperature.defaultsKey)
            && (usage == .battery || stored(for: usage, in: defaults).isText)
    }

    /// Whether the "combine temperatures" switch can change anything: CPU or
    /// GPU usage drawn as text, or a built-in battery.
    static func combineApplies(in defaults: UserDefaults = .standard, hasBattery: Bool) -> Bool {
        stored(for: .cpu, in: defaults).isText || stored(for: .gpu, in: defaults).isText || hasBattery
    }
}

extension MenuBarMetric {
    /// The defaults key holding this metric's menu bar style.
    var styleKey: String { "menuBarMetricAppearance_\(rawValue)" }
}

enum MenuBarUsageBarSupport {
    static let defaultNormalColor = "#64D2FF"
    static let defaultElevatedColor = "#FFD60A"
    static let defaultCriticalColor = "#FF453A"
    static let defaultMediumThreshold = 70
    static let defaultHighThreshold = 90

    enum Level {
        case normal, elevated, critical
    }

    struct RGB: Equatable {
        let red: Double
        let green: Double
        let blue: Double
    }

    static func memoryFraction(used: UInt64?, total: UInt64?) -> Double? {
        guard let used, let total, total > 0 else { return nil }
        return clampedFraction(Double(used) / Double(total))
    }

    static func clampedFraction(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(1, max(0, fraction))
    }

    /// Quantizing to the number of drawable pixels keeps the image cache
    /// bounded while retaining every visible fill level.
    static func fillLevel(for fraction: Double, steps: Int) -> Int {
        guard steps > 0 else { return 0 }
        let clamped = clampedFraction(fraction)
        guard clamped > 0 else { return 0 }
        let raw = Int((clamped * Double(steps)).rounded())
        return max(1, raw)
    }

    static func thresholds(medium: Int, high: Int) -> (medium: Int, high: Int) {
        let medium = min(99, max(1, medium))
        let high = min(100, max(medium + 1, high))
        return (medium, high)
    }

    static func level(for fraction: Double,
                      mediumPercent: Int = defaultMediumThreshold,
                      highPercent: Int = defaultHighThreshold) -> Level {
        let thresholds = thresholds(medium: mediumPercent, high: highPercent)
        let percent = clampedFraction(fraction) * 100
        switch percent {
        case Double(thresholds.high)...: return .critical
        case Double(thresholds.medium)...: return .elevated
        default: return .normal
        }
    }

    static func currentLevel(for fraction: Double,
                             defaults: UserDefaults = .standard) -> Level {
        level(for: fraction,
              mediumPercent: defaults.integer(forKey: DefaultsKey.menuBarUsageBarMediumThreshold),
              highPercent: defaults.integer(forKey: DefaultsKey.menuBarUsageBarHighThreshold))
    }

    static func currentColorHex(for level: Level,
                                defaults: UserDefaults = .standard) -> String {
        switch level {
        case .normal:
            return sanitizedColorHex(defaults.string(forKey: DefaultsKey.menuBarUsageBarNormalColor),
                                     fallback: defaultNormalColor)
        case .elevated:
            return sanitizedColorHex(defaults.string(forKey: DefaultsKey.menuBarUsageBarElevatedColor),
                                     fallback: defaultElevatedColor)
        case .critical:
            return sanitizedColorHex(defaults.string(forKey: DefaultsKey.menuBarUsageBarCriticalColor),
                                     fallback: defaultCriticalColor)
        }
    }

    static func sanitizedColorHex(_ raw: String?, fallback: String) -> String {
        let fallback = normalizedColorHex(fallback) ?? defaultNormalColor
        guard let raw, let normalized = normalizedColorHex(raw) else { return fallback }
        return normalized
    }

    static func rgb(for raw: String?, fallback: String) -> RGB {
        let hex = sanitizedColorHex(raw, fallback: fallback)
        let digits = String(hex.dropFirst())
        let value = UInt64(digits, radix: 16) ?? 0
        return RGB(red: Double((value >> 16) & 0xFF) / 255,
                   green: Double((value >> 8) & 0xFF) / 255,
                   blue: Double(value & 0xFF) / 255)
    }

    static func hex(red: Double, green: Double, blue: Double) -> String {
        let components = [red, green, blue].map {
            Int((clampedFraction($0) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", components[0], components[1], components[2])
    }

    private static let hexAllowedCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEF")

    private static func normalizedColorHex(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard digits.count == 6,
              digits.unicodeScalars.allSatisfy({ hexAllowedCharacterSet.contains($0) })
        else { return nil }
        return "#" + digits
    }

}

enum MenuBarSpacingSupport {
    /// Idle CPU/GPU readings live right at the one-to-two digit boundary
    /// (4% one tick, 10% the next); reserving the bare current digit count
    /// made the whole bar wobble on every crossing. Two digits cover 0-99
    /// without ever moving.
    static let compactMinimumDigits = 2

    /// A finite Keep Awake countdown is the only menu-bar content whose text
    /// changes just because time passed. Everything else refreshes from its
    /// publisher or preference change, so no timer should live at rest.
    static func needsTitleRefreshTimer(keepAwakeActive: Bool,
                                       showsCountdown: Bool,
                                       hasEndDate: Bool) -> Bool {
        keepAwakeActive && showsCountdown && hasEndDate
    }

    static func compactFloor(currentDigits: Int, highWater: Int?) -> Int {
        max(currentDigits, compactMinimumDigits, highWater ?? 0)
    }

    /// A same-width stand-in for the value ("14%" gives "88%"), padded with
    /// extra digits in front of the first number until `minimumDigits` is
    /// met ("4%" with a minimum of 2 gives "88%"). Values without digits are
    /// returned shape-for-shape.
    static func digitMatchedReserve(for value: String, minimumDigits: Int = 0) -> String {
        var out = ""
        var digitCount = value.filter(\.isNumber).count
        var padded = false
        for character in value {
            if character.isNumber, !padded {
                while digitCount < minimumDigits {
                    out.append("8")
                    digitCount += 1
                }
                padded = true
            }
            out.append(character.isNumber ? "8" : character)
        }
        return out
    }

    /// The glue string drawn between two metric blocks.
    static func blockGlue(spacing: MenuBarMetricSpacing) -> String {
        switch spacing {
        case .standard: return " "
        case .compact: return "\u{200A}"
        }
    }

    /// What the main item's title is made of, as a key that changes exactly
    /// when the title would look different: the glyph spacing, a running
    /// countdown and the metrics' render key (see `MenuBarRender`).
    static func titleKey(glyphHidden: Bool, countdown: String, metricsKey: String) -> String {
        [glyphHidden ? "-" : "+", countdown, metricsKey].joined(separator: "\u{1E}")
    }

    /// Whether a status item's title must be written again. Every write
    /// re-lays out and redraws the status window, so an unchanged key on a
    /// title that is already drawn is skipped. A nil or empty last key means
    /// nothing has been written since the item was made or its memo reset,
    /// and an empty button title means something else cleared it: both
    /// write. Shared by the main item and the separate metric items.
    static func needsTitleWrite(key: String, lastWrittenKey: String?, currentTitleLength: Int) -> Bool {
        guard let lastWrittenKey, !lastWrittenKey.isEmpty else { return true }
        return key != lastWrittenKey || currentTitleLength == 0
    }

    /// Whether the app glyph may hide so the menu bar shows metrics only
    /// (user request). Every gate protects the same invariant: the status
    /// item must never end up with no image and no text, and hiding must
    /// never swallow a signal the user opted into.
    /// - `metricsEnabled` keeps a countdown-only title from hiding the glyph.
    /// - `renderedTitleLength` covers the launch gap where metrics are on
    ///   but the first sample has not landed yet (empty title).
    /// - `separateMetrics` keeps the glyph when metrics live in their own
    ///   status items and the main one would otherwise be empty.
    /// - `mustShowForSignal` brings the glyph back while it carries a signal
    ///   (update available, a running Keep Awake, mic muted indicator).
    static func shouldHideStatusIcon(optionEnabled: Bool,
                                     separateMetrics: Bool,
                                     metricsEnabled: Bool,
                                     renderedTitleLength: Int,
                                     mustShowForSignal: Bool) -> Bool {
        optionEnabled
            && !separateMetrics
            && metricsEnabled
            && renderedTitleLength > 0
            && !mustShowForSignal
    }

    /// Whether a running Keep Awake session needs the glyph that metrics
    /// hide: the tinted or swapped glyph is the session's only mark there.
    /// Untinted, the app's own mark looks the same idle and active.
    static func keepAwakeSignals(active: Bool, tint: KeepAwakeIconTint, style: KeepAwakeActiveIcon) -> Bool {
        active && (tint != .none || style != .ryzenstatus)
    }

    /// Whether the whole main status item may hide in the separate-items
    /// mode, where each metric is its own clickable item and the main one
    /// carries only the glyph. It may only vanish while at least one metric
    /// item is actually installed (the panel stays reachable through them),
    /// its own title is empty (an active countdown renders there and must
    /// not disappear), and no signal needs the glyph back.
    static func shouldHideMainStatusItem(optionEnabled: Bool,
                                         separateMetrics: Bool,
                                         metricItemsShown: Int,
                                         renderedTitleLength: Int,
                                         mustShowForSignal: Bool) -> Bool {
        optionEnabled
            && separateMetrics
            && metricItemsShown > 0
            && renderedTitleLength == 0
            && !mustShowForSignal
    }

    /// Whether Dynamic Island may take the whole main item out of the bar,
    /// not just its glyph. Only while the item has no text of its own and is
    /// not about to get any: when metrics render inside the main item, their
    /// first reading (or a tick that renders nothing) leaves the title empty
    /// for a moment, and hiding the item then makes the menu bar drop it and
    /// insert it again as a blank slot of its saved width until it redraws.
    /// So with metrics in the main item, the island hides only the glyph and
    /// the item grows in place when the readings arrive.
    static func islandHidesMainStatusItem(islandHides: Bool,
                                          separateMetrics: Bool,
                                          metricsEnabled: Bool,
                                          renderedTitleLength: Int) -> Bool {
        islandHides
            && renderedTitleLength == 0
            && (separateMetrics || !metricsEnabled)
    }

    /// How many refreshes in a row a metric may render nothing before its item
    /// goes. Long enough to ride out a sensor that skips a tick, short enough
    /// that a reading which stops for good does not leave an empty slot behind.
    /// Refreshes come from the monitor tick and from anything else that redraws
    /// the bar, so this is a small number of seconds, not an exact delay.
    static let emptyMetricRendersBeforeRemoval = 5

    /// Whether a pinned metric keeps its own item in the menu bar right now.
    /// A reading that is momentarily unavailable renders nothing for a tick,
    /// and taking the item away and putting it back for that is both a
    /// visible flicker and the churn the menu bar copes with worst. An item
    /// that already exists stays and goes blank, until the reading has been
    /// missing long enough to call it gone.
    static func keepsMetricStatusItem(hasRenderedTitle: Bool,
                                      itemExists: Bool,
                                      consecutiveEmptyRenders: Int = 0) -> Bool {
        if hasRenderedTitle { return true }
        if !itemExists { return false }
        return consecutiveEmptyRenders < emptyMetricRendersBeforeRemoval
    }
}

enum StatusItemPlacementSupport {
    static let mainAutosaveName = "RyzenStatusMenuBarItem"
    static let maxPlacementGeneration = 10_000

    static func placementGeneration(in defaults: UserDefaults) -> Int {
        min(max(defaults.integer(forKey: DefaultsKey.statusItemPlacementGeneration), 0),
            maxPlacementGeneration)
    }

    static func mainAutosaveName(in defaults: UserDefaults) -> String {
        autosaveName(forGeneration: placementGeneration(in: defaults))
    }

    static func autosaveName(forGeneration generation: Int) -> String {
        let generation = min(max(generation, 0), maxPlacementGeneration)
        guard generation > 0 else { return mainAutosaveName }
        return "\(mainAutosaveName).\(generation)"
    }

    static func preferredPositionKey(for autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }

    /// The visibility macOS remembers for one item identity, in both the
    /// spellings it has used. Left behind, either keeps the item marked as
    /// hidden, which is the state the recovery exists to undo.
    private static func clearRememberedVisibility(of name: String, in defaults: UserDefaults) {
        defaults.removeObject(forKey: "NSStatusItem Visible \(name)")
        defaults.removeObject(forKey: "NSStatusItem VisibleCC \(name)")
    }

    private static func clearPreferredPosition(of name: String, in defaults: UserDefaults) {
        defaults.removeObject(forKey: preferredPositionKey(for: name))
    }

    private static func clearAllRememberedState(of name: String, in defaults: UserDefaults) {
        clearRememberedVisibility(of: name, in: defaults)
        clearPreferredPosition(of: name, in: defaults)
    }

    /// Undoes a remembered hidden state while leaving the arranged position
    /// alone. An item that starts over with no saved position is born at the
    /// left end of the status area, against the notch, which is the first
    /// zone macOS drops from a crowded bar — so the spot the
    /// person already arranged is worth far more than a fresh identity, and
    /// is only given up when keeping it demonstrably fails.
    static func clearRememberedVisibility(in defaults: UserDefaults) {
        clearRememberedVisibility(of: mainAutosaveName(in: defaults), in: defaults)
    }

    static func bumpPlacementGeneration(in defaults: UserDefaults) {
        let previousGeneration = placementGeneration(in: defaults)
        // Sweep every identity this install may have minted. Leaving Visible /
        // Preferred keys behind for older generations is how recovery quietly
        // accumulates junk without helping the next attempt.
        for generation in 0...previousGeneration {
            clearAllRememberedState(of: autosaveName(forGeneration: generation), in: defaults)
        }
        let nextGen = (previousGeneration % maxPlacementGeneration) + 1
        defaults.set(nextGen, forKey: DefaultsKey.statusItemPlacementGeneration)
        let nextName = mainAutosaveName(in: defaults)
        clearAllRememberedState(of: nextName, in: defaults)
    }

    /// Whether a status item's window frame says the icon is actually in a
    /// menu bar. Intersecting a screen is not enough: an item macOS declines
    /// to place at all (macOS 26 with the app switched off under System
    /// Settings > Menu Bar > "Allow in the Menu Bar") keeps its window at the
    /// bottom-left origin of the main display, sized like a real item, which
    /// intersects that screen and used to pass for "appeared". Only a
    /// frame sitting in the menu bar band of an attached screen counts.
    static func isPlacedStatusFrame(_ frame: CGRect, screenFrames: [CGRect]) -> Bool {
        StatusItemAnchorSupport.isTrustworthyStatusFrame(frame, screenFrames: screenFrames)
    }

    /// While macOS is still settling a newborn status window, recovery must
    /// keep waiting instead of escalating to an identity reset or the
    /// "still hidden" alert.
    static func shouldKeepWaitingForSettlement(isOnScreen: Bool,
                                               isSettling: Bool,
                                               settlingGraceLeft: Int) -> Bool {
        !isOnScreen && isSettling && settlingGraceLeft > 0
    }
}
