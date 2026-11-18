// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit

/// Every preference the menu bar renderer reads, taken once per refresh.
///
/// The renderer used to ask UserDefaults again inside each block and image
/// helper, so one title could mix values read at different moments. One
/// snapshot keeps a render consistent, lets the status item skip a refresh
/// whose inputs did not change, and lets the Settings preview render with
/// its own appearance without touching the real bar.
struct MenuBarRenderSettings: Equatable {
    var styles: [MenuBarMetric: MenuBarMetricAppearance]
    var combineTemperatures: Bool
    var graphShowsValue: Bool
    var spacing: MenuBarMetricSpacing
    var memoryStyle: MemoryMenuBarStyle
    var memoryMetric: MonitorMemoryMetric
    var networkUploadFirst: Bool
    /// MB/s or Mbps, read with the rest so the preview follows a change at once.
    var networkInBits: Bool
    var temperatureUnit: TemperatureUnit
    var usageBarMediumThreshold: Int
    var usageBarHighThreshold: Int
    var usageBarNormalColor: String
    var usageBarElevatedColor: String
    var usageBarCriticalColor: String
    var historyWidth: MenuBarGraphHistoryWidth
    var historySpaced: Bool
    var networkGraphLayout: MenuBarNetworkGraphLayout
    /// Theme, light background and accent: everything besides the samples
    /// that changes a graph's pixels (see `MenuBarGraphPainter.cacheToken`).
    var graphToken: String
    /// The appearance the images are drawn for. The status button's own
    /// appearance follows the menu bar over the wallpaper, which on macOS 26
    /// need not match the app's.
    var appearanceName: String

    func style(for metric: MenuBarMetric) -> MenuBarMetricAppearance {
        styles[metric] ?? .values
    }

    /// Usage and temperature share one block only while the usage reading is
    /// drawn as text. Decided once per component from the usage metric's own
    /// style, so the order of the pinned list can never draw a reading twice.
    func combinesTemperature(of component: MenuBarComponent) -> Bool {
        guard combineTemperatures else { return false }
        switch component {
        case .cpu: return style(for: .cpu).isText
        case .gpu: return style(for: .gpu).isText
        case .battery: return true
        }
    }

    static func current(defaults: UserDefaults = .standard,
                        appearance: NSAppearance? = nil) -> MenuBarRenderSettings {
        var styles: [MenuBarMetric: MenuBarMetricAppearance] = [:]
        for metric in MenuBarMetricAppearance.styledMetrics {
            styles[metric] = MenuBarMetricAppearance.stored(for: metric, in: defaults)
        }
        // Callers that draw pass the appearance they draw for (the status
        // button's, the preview's); without one, aqua keeps this free of
        // main-actor state.
        let resolvedAppearance = appearance ?? NSAppearance(named: .aqua)!
        return MenuBarRenderSettings(
            styles: styles,
            combineTemperatures: defaults.bool(forKey: DefaultsKey.menuBarCombineTemperatures),
            graphShowsValue: defaults.bool(forKey: DefaultsKey.menuBarGraphShowsValue),
            spacing: MenuBarMetricSpacing(
                rawValue: Defaults.sanitizedMenuBarMetricSpacing(
                    defaults.string(forKey: DefaultsKey.menuBarMetricSpacing) ?? "")) ?? .standard,
            memoryStyle: MemoryMenuBarStyle(
                rawValue: Defaults.sanitizedMenuBarMemoryStyle(
                    defaults.string(forKey: DefaultsKey.menuBarMemoryStyle) ?? "")) ?? .percent,
            memoryMetric: MonitorMemoryMetric(
                rawValue: Defaults.sanitizedMonitorMemoryMetric(
                    defaults.string(forKey: DefaultsKey.monitorMemoryMetric) ?? "")) ?? .used,
            networkUploadFirst: defaults.bool(forKey: DefaultsKey.menuBarNetworkUploadFirst),
            networkInBits: (defaults.string(forKey: DefaultsKey.networkSpeedUnit) ?? "") == NetworkSpeedUnit.bits.rawValue,
            temperatureUnit: TemperatureUnit(rawValue: defaults.string(forKey: DefaultsKey.temperatureUnit) ?? "")
                ?? .celsius,
            usageBarMediumThreshold: defaults.integer(forKey: DefaultsKey.menuBarUsageBarMediumThreshold),
            usageBarHighThreshold: defaults.integer(forKey: DefaultsKey.menuBarUsageBarHighThreshold),
            usageBarNormalColor: MenuBarUsageBarSupport.sanitizedColorHex(
                defaults.string(forKey: DefaultsKey.menuBarUsageBarNormalColor),
                fallback: MenuBarUsageBarSupport.defaultNormalColor),
            usageBarElevatedColor: MenuBarUsageBarSupport.sanitizedColorHex(
                defaults.string(forKey: DefaultsKey.menuBarUsageBarElevatedColor),
                fallback: MenuBarUsageBarSupport.defaultElevatedColor),
            usageBarCriticalColor: MenuBarUsageBarSupport.sanitizedColorHex(
                defaults.string(forKey: DefaultsKey.menuBarUsageBarCriticalColor),
                fallback: MenuBarUsageBarSupport.defaultCriticalColor),
            historyWidth: MenuBarGraphHistoryWidth.current(defaults),
            historySpaced: defaults.bool(forKey: DefaultsKey.menuBarGraphHistorySpaced),
            networkGraphLayout: MenuBarNetworkGraphLayout.current(defaults),
            graphToken: MenuBarGraphPainter.cacheToken(defaults: defaults),
            appearanceName: resolvedAppearance.name.rawValue)
    }

    /// The colour a usage bar fills with at `fraction`.
    func usageBarColorHex(for fraction: Double) -> String {
        switch MenuBarUsageBarSupport.level(for: fraction,
                                            mediumPercent: usageBarMediumThreshold,
                                            highPercent: usageBarHighThreshold) {
        case .normal: return usageBarNormalColor
        case .elevated: return usageBarElevatedColor
        case .critical: return usageBarCriticalColor
        }
    }
}

/// The hardware components whose usage and temperature may share one block.
enum MenuBarComponent {
    case cpu, gpu, battery
}

/// Highest digit count each block has shown this session, so a spike to three
/// digits widens that block once and keeps it there instead of letting the
/// width oscillate while the value hovers at the boundary. Keyed by metric,
/// not by label: CPU usage and CPU power both read "CPU", and a 105 W reading
/// used to make the usage block reserve three digits for the whole session.
/// The Settings preview owns a separate memory so it never teaches the bar.
///
/// Touched only on the main thread: the status item and the preview render
/// there. Not `@MainActor`, because the renderer's static helpers that read
/// it also build the image drawing handlers, which must stay nonisolated;
/// the precondition below checks the promise instead. Read it only while
/// building a block, never inside an image drawing handler, which may run
/// later and on another thread.
final class MenuBarWidthMemory: @unchecked Sendable {
    static let shared = MenuBarWidthMemory()

    private var digitHighWater: [String: Int] = [:]

    /// The reserve compact mode uses for a metric block: the current value's
    /// shape, widened to at least `MenuBarSpacingSupport.compactMinimumDigits`
    /// digits and to the block's session high-water mark.
    func compactReserve(key: String, value: String) -> String {
        dispatchPrecondition(condition: .onQueue(.main))
        let digits = value.filter(\.isNumber).count
        let floor = MenuBarSpacingSupport.compactFloor(currentDigits: digits, highWater: digitHighWater[key])
        digitHighWater[key] = floor
        return MenuBarSpacingSupport.digitMatchedReserve(for: value, minimumDigits: floor)
    }
}

/// One-time conversion of the menu bar style settings to explicit per-metric
/// values.
///
/// Before this, the five per-metric style keys were not registered, so a
/// metric nobody had picked a style for inherited the old global style key,
/// which lost its control in 1.4.3; Settings meanwhile showed "Values". The
/// renderer also read the same stored value differently per metric. Writing
/// what each metric actually shows today keeps every bar as it was, in values
/// an older build still understands.
enum MenuBarStyleMigration {
    /// Not registered and not exported: a backup carries the style keys
    /// themselves, and importing one re-runs the conversion when they are
    /// missing (see `SettingsBackup.apply`).
    static let markerKey = "menuBarStyleMigration1"

    /// Keys the conversion reads, so callers can collect them from defaults
    /// or from a backup file.
    static var inputKeys: [String] {
        [DefaultsKey.menuBarMetricAppearance, DefaultsKey.menuBarLayoutMode]
            + MenuBarMetricAppearance.styledMetrics.map(\.styleKey)
    }

    /// What `stored` (saved values only, no registered defaults) becomes.
    /// Every per-metric style key gets an explicit value; the hidden classic
    /// layout turns into the four CPU readings it used to force.
    static func migratedValues(stored: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        let global = validStyle(stored[DefaultsKey.menuBarMetricAppearance])
        let namesStyle = global != nil
            || MenuBarMetricAppearance.styledMetrics.contains { validStyle(stored[$0.styleKey]) != nil }
        // Settings that name no style (a classic-only config file) leave the
        // current per-metric styles alone.
        for metric in MenuBarMetricAppearance.styledMetrics where namesStyle {
            let effective = validStyle(stored[metric.styleKey]) ?? global ?? "values"
            result[metric.styleKey] = shownStyle(effective, for: metric)
        }
        if stored[DefaultsKey.menuBarLayoutMode] as? String == "classic" {
            let classicMetrics: [MenuBarMetric] = [.cpu, .cpuTemperature, .cpuFrequency, .cpuPower]
            for metric in MenuBarMetric.allCases {
                result[metric.defaultsKey] = classicMetrics.contains(metric)
            }
            result[DefaultsKey.menuBarMetricOrder] = classicMetrics.map(\.rawValue).joined(separator: ",")
            // Classic forced this option off.
            result[DefaultsKey.menuBarHideIconWithMetrics] = false
            // Converted once: a backup written later must not convert again
            // and reset the readings chosen since.
            result[DefaultsKey.menuBarLayoutMode] = "modern"
        }
        return result
    }

    /// The style a metric drew for a stored value, written in the vocabulary
    /// the metric keeps understanding. Read from every branch of
    /// `MenuBarRenderer.blockSegments` as it stood before the conversion.
    static func shownStyle(_ stored: String, for metric: MenuBarMetric) -> String {
        let value = stored == "classic" ? "values" : stored
        switch metric {
        case .cpu:
            return value
        case .gpu, .memory:
            // History is the only graph these two had besides bars and the
            // ring; "histogram" drew history.
            return value == "histogram" ? "sparkline" : value
        case .network:
            // Every graph style drew the dual history graph.
            return value == "values" ? "values" : "sparkline"
        case .diskUsage:
            return value == "bars" ? "bars" : "values"
        default:
            return "values"
        }
    }

    private static func validStyle(_ raw: Any?) -> String? {
        guard let raw = raw as? String,
              Defaults.allowedMenuBarMetricAppearances.contains(raw) else { return nil }
        return raw
    }

    /// Runs the conversion once against saved values. Call before the
    /// defaults are registered, so `object(forKey:)` still tells a saved
    /// choice from a registered default.
    static func runIfNeeded(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: markerKey) else { return }
        apply(stored: collect(from: defaults), to: defaults)
        defaults.set(true, forKey: markerKey)
    }

    /// Re-applies the conversion to settings written before it existed: an
    /// imported backup or a launch config file that carries the old global
    /// style (and no per-metric ones) or the classic layout. A file that
    /// says nothing about menu bar styles leaves the current ones alone.
    static func applyAfterImport(_ settings: [String: Any], to defaults: UserDefaults) {
        guard needsConversion(settings) else { return }
        var stored: [String: Any] = [:]
        for key in inputKeys { stored[key] = settings[key] }
        apply(stored: stored, to: defaults)
    }

    /// A config file in the current vocabulary: the old global style and the
    /// classic layout become what they mean, so the launch comparison sees
    /// the converted keys and stops re-applying once they match.
    static func translatingOldKeys(_ settings: [String: Any]) -> [String: Any] {
        guard needsConversion(settings) else { return settings }
        var result = settings
        result.removeValue(forKey: DefaultsKey.menuBarMetricAppearance)
        if result[DefaultsKey.menuBarLayoutMode] as? String == "classic" {
            result.removeValue(forKey: DefaultsKey.menuBarLayoutMode)
        }
        var stored: [String: Any] = [:]
        for key in inputKeys { stored[key] = settings[key] }
        for (key, value) in migratedValues(stored: stored) where key != DefaultsKey.menuBarLayoutMode {
            result[key] = value
        }
        return result
    }

    /// Whether `settings` (a backup or config file) still speaks the old
    /// vocabulary.
    static func needsConversion(_ settings: [String: Any]) -> Bool {
        // Current exports carry all five; with fewer, the rest inherit the
        // old global style.
        let hasPerMetric = MenuBarMetricAppearance.styledMetrics.allSatisfy { settings[$0.styleKey] != nil }
        let hasGlobal = settings[DefaultsKey.menuBarMetricAppearance] != nil
        let hasClassic = settings[DefaultsKey.menuBarLayoutMode] as? String == "classic"
        return (hasGlobal && !hasPerMetric) || hasClassic
    }

    private static func collect(from defaults: UserDefaults) -> [String: Any] {
        var stored: [String: Any] = [:]
        for key in inputKeys { stored[key] = defaults.object(forKey: key) }
        return stored
    }

    private static func apply(stored: [String: Any], to defaults: UserDefaults) {
        for (key, value) in migratedValues(stored: stored) {
            defaults.set(value, forKey: key)
        }
        // The old global style no longer decides anything; a saved copy would
        // only travel in backups next to the per-metric keys.
        defaults.removeObject(forKey: DefaultsKey.menuBarMetricAppearance)
    }
}
