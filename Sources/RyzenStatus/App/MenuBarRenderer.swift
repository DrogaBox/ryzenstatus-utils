// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit

/// A live reading the user can pin next to the menu bar icon.
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, cpuTemperature, gpuTemperature, cpuPower, gpuPower, cpuFrequency, cpuTempPower, gpuTempPower, batteryTemperature, network, diskUsage, diskActivity, battery, batteryTime, peripheralBattery, power, connectedDevices

    var id: String { rawValue }

    var defaultsKey: String {
        switch self {
        case .cpu: return DefaultsKey.menuBarCPU
        case .gpu: return DefaultsKey.menuBarGPU
        case .memory: return DefaultsKey.menuBarMemory
        case .cpuTemperature: return DefaultsKey.menuBarCPUTemperature
        case .gpuTemperature: return DefaultsKey.menuBarGPUTemperature
        case .cpuPower: return DefaultsKey.menuBarCPUPower
        case .gpuPower: return DefaultsKey.menuBarGPUPower
        case .cpuFrequency: return DefaultsKey.menuBarCPUFrequency
        case .cpuTempPower: return DefaultsKey.menuBarCPUTempPower
        case .gpuTempPower: return DefaultsKey.menuBarGPUTempPower
        case .batteryTemperature: return DefaultsKey.menuBarBatteryTemperature
        case .network: return DefaultsKey.menuBarNetwork
        case .diskUsage: return DefaultsKey.menuBarDiskUsage
        case .diskActivity: return DefaultsKey.menuBarDiskActivity
        case .battery: return DefaultsKey.menuBarBattery
        case .batteryTime: return DefaultsKey.menuBarBatteryTime
        case .peripheralBattery: return DefaultsKey.menuBarPeripheralBattery
        case .power: return DefaultsKey.menuBarPower
        case .connectedDevices: return DefaultsKey.menuBarConnectedDevices
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "rectangle.connected.to.line.below"
        case .memory: return "memorychip"
        case .cpuTemperature: return "cpu"
        case .gpuTemperature: return "rectangle.connected.to.line.below"
        case .cpuPower: return "bolt.fill"
        case .gpuPower: return "bolt.fill"
        case .cpuFrequency: return "waveform.path.ecg"
        case .cpuTempPower: return "thermometer"
        case .gpuTempPower: return "thermometer.snowflake"
        case .batteryTemperature: return "battery.100"
        case .network: return "network"
        case .diskUsage: return "internaldrive"
        case .diskActivity: return "internaldrive.fill"
        case .battery: return "battery.100"
        case .batteryTime: return "clock"
        case .peripheralBattery: return "keyboard"
        case .power: return "powerplug.fill"
        case .connectedDevices: return "cable.connector"
        }
    }

    func title(_ strings: Strings) -> String {
        switch self {
        case .cpu: return strings.monitorShowCPU
        case .gpu: return strings.monitorShowGPU
        case .memory: return strings.monitorShowMemory
        case .cpuTemperature: return strings.monitorShowCPUTemperature
        case .gpuTemperature: return strings.monitorShowGPUTemperature
        case .cpuPower: return strings.cpuPowerMetricTitle
        case .gpuPower: return strings.gpuPowerMetricTitle
        case .cpuFrequency: return strings.cpuFrequencyMetricTitle
        case .cpuTempPower: return strings.cpuTempPowerMetricTitle
        case .gpuTempPower: return strings.gpuTempPowerMetricTitle
        case .batteryTemperature: return strings.monitorShowBatteryTemperature
        case .network: return strings.monitorShowNetwork
        case .diskUsage: return strings.monitorItemDiskUsage
        case .diskActivity: return strings.monitorItemDiskActivity
        case .battery: return strings.batteryLabel
        case .batteryTime: return FeatureStrings.batteryTime(L10n.shared.language).title
        case .peripheralBattery: return strings.monitorShowPeripheralBattery
        case .power: return strings.monitorShowPowerLabel
        case .connectedDevices: return FeatureStrings.connectedDevices(L10n.shared.language).title
        }
    }

    static let defaultOrder: [MenuBarMetric] = [
        .cpu, .cpuTemperature, .cpuPower, .cpuFrequency, .cpuTempPower,
        .gpu, .gpuTemperature, .gpuPower, .gpuTempPower,
        .memory,
        .battery, .batteryTime, .batteryTemperature, .peripheralBattery,
        .network, .diskUsage, .diskActivity, .connectedDevices, .power,
    ]

    static func order(in defaults: UserDefaults) -> [MenuBarMetric] {
        let raw = defaults.string(forKey: DefaultsKey.menuBarMetricOrder) ?? ""
        return Defaults.sanitizedMenuBarMetricOrder(raw).compactMap(MenuBarMetric.init(rawValue:))
    }

    static func setOrder(_ order: [MenuBarMetric], in defaults: UserDefaults = .standard) {
        let raw = order.map(\.rawValue).joined(separator: ",")
        defaults.set(raw, forKey: DefaultsKey.menuBarMetricOrder)
    }

    /// The hub feature this metric belongs to; temperatures ride with their
    /// parent metric. A pinned metric whose feature is off in the hub stays
    /// pinned in defaults but stops rendering (and sampling) until it returns.
    var feature: AppFeature {
        switch self {
        case .cpu, .cpuTemperature, .cpuPower, .cpuFrequency, .cpuTempPower: return .monitorCPU
        case .gpu, .gpuTemperature, .gpuPower, .gpuTempPower: return .monitorGPU
        case .memory: return .monitorMemory
        case .network: return .monitorNetwork
        case .diskUsage, .diskActivity: return .monitorDisk
        case .battery, .batteryTime, .batteryTemperature, .peripheralBattery, .power: return .monitorPower
        case .connectedDevices: return .connectedDevices
        }
    }

    var isAvailableOnCurrentHardware: Bool {
        switch self {
        case .battery, .batteryTime, .batteryTemperature:
            return PowerSampler.hasInternalBattery
        default:
            return true
        }
    }

    static func enabled(in defaults: UserDefaults) -> [MenuBarMetric] {
        order(in: defaults).filter {
            defaults.bool(forKey: $0.defaultsKey)
                && defaults.bool(forKey: $0.feature.availabilityKey)
                && $0.isAvailableOnCurrentHardware
        }
    }

    static func anyEnabled(in defaults: UserDefaults) -> Bool {
        allCases.contains {
            defaults.bool(forKey: $0.defaultsKey)
                && defaults.bool(forKey: $0.feature.availabilityKey)
                && $0.isAvailableOnCurrentHardware
        }
    }
}

/// How the Memory metric appears in the menu bar: a colored pressure dot, the
/// percentage of RAM in use, or both.
enum MemoryMenuBarStyle: String, CaseIterable {
    case dot, percent, both

    static var current: MemoryMenuBarStyle {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.menuBarMemoryStyle) ?? ""
        let style = Defaults.sanitizedMenuBarMemoryStyle(raw)
        return MemoryMenuBarStyle(rawValue: style) ?? .percent
    }

    var showsDot: Bool { self == .dot || self == .both }
    var showsPercent: Bool { self == .percent || self == .both }
}

/// Which memory figure the monitor displays across the menu bar and panel.
enum MonitorMemoryMetric: String, CaseIterable {
    case used, app

    static var current: MonitorMemoryMetric {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.monitorMemoryMetric) ?? ""
        let metric = Defaults.sanitizedMonitorMemoryMetric(raw)
        return MonitorMemoryMetric(rawValue: metric) ?? .used
    }

    func value(in snapshot: SystemSnapshot) -> UInt64? {
        MetricFormat.selectedMemory(used: snapshot.memoryUsed,
                                    app: snapshot.memoryAppUsed,
                                    metric: rawValue)
    }

    func history(in snapshot: SystemSnapshot) -> [Double] {
        self == .app ? snapshot.memoryAppHistory : snapshot.memoryHistory
    }

    func title(in strings: Strings) -> String {
        self == .app ? strings.memoryMetricApp : strings.memoryMetricUsed
    }
}


/// One drawable piece of the menu bar title: glue text between blocks, or a
/// block the renderer draws as a cached image.
enum MenuBarSegment {
    case text(String)
    /// A label above a value. `widthKey` names the block for the compact
    /// width memory (the metric, not the label, which several share).
    case metricBlock(label: String, value: String, minimumValue: String, widthKey: String, pressure: MemoryPressure?)
    case usageBarBlock(label: String, fraction: Double?, pressure: MemoryPressure?)
    case networkBlock(down: String, up: String)
    case diskActivityBlock(read: String, write: String)
    case batteryBlock(percent: Int, isCharging: Bool)
    /// A pre-rendered block; `key` is its image cache key.
    case customImage(NSImage, key: String)
}

/// A rendered title and a key that changes exactly when the title would
/// look different. Comparing attributed strings cannot tell: every render
/// builds new text attachments, and two attachments holding the same image
/// never compare equal, so the status item used to rewrite and re-lay out
/// its title on every monitor tick.
struct MenuBarRender {
    let string: NSAttributedString
    let key: String

    static let empty = MenuBarRender(string: NSAttributedString(), key: "")
}

/// Builds the compact content shown next to the icon.
///
/// Output is a list of segments turned into an attributed string of cached
/// block images. Labels are intentionally abbreviated because the menu bar is
/// a scarce space, especially on notched MacBooks.
enum MenuBarRenderer {
    private static let statusFontSize: CGFloat = 11.6
    private static let rateFontSize: CGFloat = 9.2
    private static let rateLineHeight: CGFloat = 10.0
    private static let blockHeight: CGFloat = 20
    private static let stackedLabelWidth: CGFloat = 6

    /// Text and gauge blocks: their keys repeat as values come and go, so
    /// they are worth keeping around.
    private static let blockImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        // The keys embed live metric values, so continuously changing numbers
        // mint new entries all day; the byte ceiling keeps that harmless.
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    /// Graph blocks: their keys carry the visible samples, which scroll on
    /// every tick, so an entry is almost never reused. A small cache of their
    /// own keeps them from pushing the reusable text blocks out.
    private static let graphImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 24
        cache.totalCostLimit = 1024 * 1024
        return cache
    }()

    // Cache colors to prevent repeated string parsing and hex-to-rgb conversion on every render tick
    private static let colorCache = NSCache<NSString, NSColor>()

    /// Estimated bitmap bytes of a rendered block at 2x backing scale.
    private static func blockImageCost(_ image: NSImage) -> Int {
        max(1, Int(image.size.width * image.size.height) * 16)
    }

    static func statusFont() -> NSFont {
        NSFont.monospacedSystemFont(ofSize: statusFontSize, weight: .medium)
    }

    /// The blocks for `metrics`, joined with the spacing glue.
    static func segments(for snapshot: SystemSnapshot,
                         metrics: [MenuBarMetric],
                         settings: MenuBarRenderSettings,
                         widthMemory: MenuBarWidthMemory = .shared) -> [MenuBarSegment] {
        blockSegments(for: snapshot, metrics: metrics, settings: settings, widthMemory: widthMemory)
    }

    /// The attributed title for the status item, with its change key. Only
    /// alert dots and usage fills get fixed colors; text and graph blocks use
    /// dynamic system colors resolved when the button draws them.
    static func render(for snapshot: SystemSnapshot,
                       metrics: [MenuBarMetric],
                       settings: MenuBarRenderSettings,
                       widthMemory: MenuBarWidthMemory = .shared) -> MenuBarRender {
        let segments = blockSegments(for: snapshot, metrics: metrics, settings: settings, widthMemory: widthMemory)
        guard !segments.isEmpty else { return .empty }
        let result = NSMutableAttributedString()
        var keyParts: [String] = []
        keyParts.reserveCapacity(segments.count)
        for segment in segments {
            switch segment {
            case let .text(string):
                result.append(NSAttributedString(string: string))
                keyParts.append("t:" + string)
            case let .metricBlock(label, value, minimumValue, widthKey, pressure):
                let block = metricBlockImage(label: label, value: value, minimumValue: minimumValue,
                                             widthKey: widthKey, pressure: pressure,
                                             settings: settings, widthMemory: widthMemory)
                result.append(attachment(block.image, yOffset: -5.7))
                keyParts.append(block.key)
            case let .usageBarBlock(label, fraction, pressure):
                let block = usageBarBlockImage(label: label, fraction: fraction, pressure: pressure, settings: settings)
                // The gauge outline fills the image symmetrically, so the
                // offset centers the image itself on the status font's box.
                result.append(attachment(block.image, yOffset: -5.6))
                keyParts.append(block.key)
            case let .networkBlock(down, up):
                let block = networkBlockImage(down: down, up: up, settings: settings)
                result.append(attachment(block.image, yOffset: -5.5))
                keyParts.append(block.key)
            case let .diskActivityBlock(read, write):
                let block = diskActivityBlockImage(read: read, write: write, settings: settings)
                result.append(attachment(block.image, yOffset: -5.5))
                keyParts.append(block.key)
            case let .batteryBlock(percent, isCharging):
                let block = batteryBlockImage(percent: percent, isCharging: isCharging, settings: settings)
                result.append(attachment(block.image, yOffset: -5.5))
                keyParts.append(block.key)
            case let .customImage(image, key):
                result.append(attachment(image, yOffset: -5.5))
                keyParts.append(key)
            }
        }
        return MenuBarRender(string: result, key: keyParts.joined(separator: "\u{1F}"))
    }

    /// macOS 26 lays out button titles dominated by tall attachments about
    /// 0.25pt higher than macOS 27, where every block offset below was
    /// calibrated; older systems get a downward nudge so the blocks center
    /// on the menu bar like the system's own icons.
    private static let legacyBlockAttachmentNudge: CGFloat = {
        if #unavailable(macOS 27) { return -0.25 }
        return 0
    }()

    private static func attachment(_ image: NSImage, yOffset: CGFloat) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0,
                                   y: yOffset + legacyBlockAttachmentNudge,
                                   width: image.size.width,
                                   height: image.size.height)
        return NSAttributedString(attachment: attachment)
    }

    private struct BlockImage {
        let image: NSImage
        let key: String
    }

    // MARK: - Blocks

    private static func blockSegments(for snapshot: SystemSnapshot,
                                      metrics: [MenuBarMetric],
                                      settings: MenuBarRenderSettings,
                                      widthMemory: MenuBarWidthMemory) -> [MenuBarSegment] {
        var groups: [[MenuBarSegment]] = []
        let enabled = Set(metrics)
        var renderedCPU = false
        var renderedGPU = false
        var renderedBattery = false
        let showsGraphValue = settings.graphShowsValue

        for metric in metrics {
            switch metric {
            case .cpu, .cpuTemperature:
                if settings.combinesTemperature(of: .cpu) {
                    guard !renderedCPU else { break }
                    renderedCPU = true
                    if let block = combinedBlock(component: "CPU",
                                                 widthKey: "cpu",
                                                 usage: enabled.contains(.cpu) ? snapshot.cpuUsage.map(percent) : nil,
                                                 temperature: enabled.contains(.cpuTemperature)
                                                    ? snapshot.cpuTemperature.map { temperatureCompact($0, settings) } : nil,
                                                 settings: settings) {
                        groups.append([block])
                    }
                    break
                }
                guard metric == .cpu else {
                    if let temperature = snapshot.cpuTemperature {
                        groups.append([temperatureBlock("CPU", temperature, widthKey: "cpuTemperature", settings)])
                    }
                    break
                }
                guard let usage = snapshot.cpuUsage else { break }
                let valueText = showsGraphValue ? percent(usage) : nil
                switch settings.style(for: .cpu) {
                case .histogram where !snapshot.cores.isEmpty:
                    groups.append([coreHistogramBlock(cores: snapshot.cores, valueText: valueText, settings: settings)])
                case .pie:
                    let userShare = max(0, usage - (snapshot.cpuSystemUsage ?? 0))
                    groups.append([ringBlock(label: "CPU", values: [usage, userShare], valueText: valueText,
                                             settings: settings)])
                case .sparkline:
                    // System time stacks over user time, as in the cores graph.
                    let userHistory = MenuBarGraphGeometry.userShares(total: snapshot.cpuHistory,
                                                                      system: snapshot.cpuSystemHistory)
                    groups.append([historyBlock(label: "CPU", series: [snapshot.cpuHistory, userHistory],
                                                valueText: valueText, settings: settings)])
                case .bars:
                    groups.append([.usageBarBlock(label: "CPU", fraction: usage, pressure: nil)])
                default:
                    groups.append([.metricBlock(label: "CPU", value: percent(usage), minimumValue: "100%",
                                                widthKey: "cpu", pressure: nil)])
                }
            case .gpu, .gpuTemperature:
                if settings.combinesTemperature(of: .gpu) {
                    guard !renderedGPU else { break }
                    renderedGPU = true
                    // A VRAM temperature is not the GPU's: it gets its own
                    // labelled block instead of riding on the GPU group.
                    let showsVRAM = snapshot.gpuDisplayLabel != "GPU"
                    let displayTemperature = enabled.contains(.gpuTemperature)
                        ? snapshot.gpuDisplayCelsius.map { temperatureCompact($0, settings) } : nil
                    if let block = combinedBlock(component: "GPU",
                                                 widthKey: "gpu",
                                                 usage: enabled.contains(.gpu) ? snapshot.gpuUsage.map(percent) : nil,
                                                 temperature: showsVRAM ? nil : displayTemperature,
                                                 settings: settings) {
                        groups.append([block])
                    }
                    if showsVRAM, let temperature = snapshot.gpuDisplayCelsius, enabled.contains(.gpuTemperature) {
                        groups.append([temperatureBlock(snapshot.gpuDisplayLabel, temperature,
                                                        widthKey: "gpuTemperature", settings)])
                    }
                    break
                }
                guard metric == .gpu else {
                    if let temperature = snapshot.gpuDisplayCelsius {
                        groups.append([temperatureBlock(snapshot.gpuDisplayLabel, temperature,
                                                        widthKey: "gpuTemperature", settings)])
                    }
                    break
                }
                guard let usage = snapshot.gpuUsage else { break }
                let valueText = showsGraphValue ? percent(usage) : nil
                switch settings.style(for: .gpu) {
                case .pie:
                    groups.append([ringBlock(label: "GPU", values: [usage], valueText: valueText, settings: settings)])
                case .sparkline, .histogram:
                    groups.append([historyBlock(label: "GPU", series: [snapshot.gpuHistory], valueText: valueText,
                                                settings: settings)])
                case .bars:
                    groups.append([.usageBarBlock(label: "GPU", fraction: usage, pressure: nil)])
                default:
                    groups.append([.metricBlock(label: "GPU", value: percent(usage), minimumValue: "100%",
                                                widthKey: "gpu", pressure: nil)])
                }
            case .cpuPower:
                if let cpuPower = snapshot.cpuPower, cpuPower > 0 {
                    groups.append([.metricBlock(label: "CPU", value: String(format: "%.0fW", cpuPower),
                                                minimumValue: "199W", widthKey: "cpuPower", pressure: nil)])
                }
            case .gpuPower:
                if let gpuPower = snapshot.gpuPower, gpuPower > 0 {
                    groups.append([.metricBlock(label: "GPU", value: String(format: "%.0fW", gpuPower),
                                                minimumValue: "999W", widthKey: "gpuPower", pressure: nil)])
                }
            case .cpuFrequency:
                let peak = snapshot.peakCPUFreq ?? (snapshot.cores.map { Double($0.freqMHz) }.max() ?? 0)
                let avg = snapshot.avgCPUFreq ?? (snapshot.cores.isEmpty ? 0 : snapshot.cores.map { Double($0.freqMHz) }.reduce(0, +) / Double(snapshot.cores.count))
                let maxStr = String(format: "%.1fG", max(peak, avg) / 1000.0)
                let avgStr = String(format: "%.1fG", avg / 1000.0)
                let block = stackedRatesImage(lines: [maxStr, avgStr],
                                              reservedLines: ["0.0G", "0.0G"],
                                              cacheKey: "cpuFreq|\(maxStr)|\(avgStr)|\(settings.appearanceName)")
                groups.append([.customImage(block.image, key: block.key)])
            case .cpuTempPower:
                let temp = snapshot.cpuTemperature.map { temperatureCompact($0, settings) } ?? "--°"
                let pwr = snapshot.cpuPower.map { String(format: "%.0fW", $0) } ?? "--W"
                let block = stackedRatesImage(lines: [temp, pwr],
                                              reservedLines: ["000°", "000W"],
                                              cacheKey: "cpuTempPwr|\(temp)|\(pwr)|\(settings.appearanceName)")
                groups.append([.customImage(block.image, key: block.key)])
            case .gpuTempPower:
                let tempValue = snapshot.gpuDisplayCelsius.map { temperatureCompact($0, settings) } ?? "--°"
                let labelled = snapshot.gpuDisplayLabel != "GPU"
                let temp = labelled ? snapshot.gpuDisplayLabel + " " + tempValue : tempValue
                let pwr = snapshot.gpuPower.map { String(format: "%.0fW", $0) } ?? "--W"
                // The image is sized from the reserved lines, so a labelled
                // VRAM line reserves room for its label too.
                let reservedTemp = labelled ? snapshot.gpuDisplayLabel + " 000°" : "000°"
                let block = stackedRatesImage(lines: [temp, pwr],
                                              reservedLines: [reservedTemp, "000W"],
                                              cacheKey: "gpuTempPwr|\(temp)|\(pwr)|\(settings.appearanceName)")
                groups.append([.customImage(block.image, key: block.key)])
            case .memory:
                let memoryStyle = settings.memoryStyle
                let memoryValue = settings.memoryMetric.value(in: snapshot)
                let usedFraction = MenuBarUsageBarSupport.memoryFraction(used: snapshot.memoryUsed,
                                                                         total: snapshot.memoryTotal)
                let appFraction = MenuBarUsageBarSupport.memoryFraction(used: snapshot.memoryAppUsed,
                                                                        total: snapshot.memoryTotal)
                let memoryGraphValue = showsGraphValue
                    ? MetricFormat.menuBarMemoryPercent(used: memoryValue, total: snapshot.memoryTotal)
                    : nil
                let style = settings.style(for: .memory)
                // Used memory is the whole and app memory the part, so the
                // graphs show app memory in the theme's main color under the
                // rest of what is in use.
                if style == .sparkline || style == .histogram, !snapshot.memoryHistory.isEmpty {
                    groups.append([historyBlock(label: "RAM",
                                                series: [snapshot.memoryHistory, snapshot.memoryAppHistory],
                                                valueText: memoryGraphValue,
                                                settings: settings)])
                } else if style == .pie, let usedFraction {
                    groups.append([ringBlock(label: "RAM",
                                             values: [usedFraction] + (appFraction.map { [$0] } ?? []),
                                             valueText: memoryGraphValue,
                                             settings: settings)])
                } else if style == .bars {
                    groups.append([.usageBarBlock(label: "RAM",
                                                  fraction: MenuBarUsageBarSupport.memoryFraction(used: memoryValue,
                                                                                                  total: snapshot.memoryTotal),
                                                  pressure: memoryStyle.showsDot ? snapshot.memoryPressure : nil)])
                } else {
                    let value = memoryStyle.showsPercent
                        ? MetricFormat.menuBarMemoryPercent(used: memoryValue, total: snapshot.memoryTotal)
                        : ""
                    groups.append([.metricBlock(label: "RAM",
                                                value: value,
                                                minimumValue: memoryStyle.showsPercent ? "100%" : "",
                                                widthKey: "memory",
                                                pressure: memoryStyle.showsDot ? snapshot.memoryPressure : nil)])
                }
            case .network:
                if let down = snapshot.netDownBytesPerSec, let up = snapshot.netUpBytesPerSec {
                    if settings.style(for: .network) == .values {
                        groups.append([.networkBlock(down: MetricFormat.networkRateCompact(down),
                                                     up: MetricFormat.networkRateCompact(up))])
                    } else {
                        groups.append([networkDualGraphBlock(downHistory: snapshot.netDownHistory,
                                                             upHistory: snapshot.netUpHistory,
                                                             settings: settings)])
                    }
                }
            case .diskUsage:
                if let disk = primaryDisk(from: snapshot.disk) {
                    if settings.style(for: .diskUsage) == .bars {
                        groups.append([.usageBarBlock(label: "DSK", fraction: disk.usedFraction, pressure: nil)])
                    } else {
                        groups.append([.metricBlock(label: "DSK", value: percent(disk.usedFraction),
                                                    minimumValue: "100%", widthKey: "diskUsage", pressure: nil)])
                    }
                }
            case .diskActivity:
                if let activity = diskActivity(from: snapshot.disk) {
                    groups.append([.diskActivityBlock(read: MetricFormat.bytesPerSecCompact(activity.read),
                                                      write: MetricFormat.bytesPerSecCompact(activity.write))])
                }
            case .battery, .batteryTemperature:
                if settings.combinesTemperature(of: .battery) {
                    guard !renderedBattery else { break }
                    renderedBattery = true
                    let charge = enabled.contains(.battery)
                        ? snapshot.power?.chargePercent.map { "\(max(0, min(100, $0)))%" }
                        : nil
                    let temperature = enabled.contains(.batteryTemperature)
                        ? snapshot.batteryTemperature.map { temperatureCompact($0, settings) }
                        : nil
                    if charge != nil, temperature != nil,
                       let value = combinedComponentValue(primary: charge, temperature: temperature) {
                        groups.append([.metricBlock(label: "BAT", value: value, minimumValue: "100% 999°",
                                                    widthKey: "battery", pressure: nil)])
                    } else if let chargePercent = enabled.contains(.battery) ? snapshot.power?.chargePercent : nil {
                        groups.append([.batteryBlock(percent: chargePercent,
                                                     isCharging: snapshot.power?.isCharging ?? false)])
                    } else if let temperature {
                        groups.append([.metricBlock(label: temperatureLabel("BAT", settings), value: temperature,
                                                    minimumValue: "999°", widthKey: "batteryTemperature",
                                                    pressure: nil)])
                    }
                    break
                }
                guard metric == .battery else {
                    if let temperature = snapshot.batteryTemperature {
                        groups.append([temperatureBlock("BAT", temperature, widthKey: "batteryTemperature", settings)])
                    }
                    break
                }
                if let charge = snapshot.power?.chargePercent {
                    groups.append([.batteryBlock(percent: charge, isCharging: snapshot.power?.isCharging ?? false)])
                }
            case .batteryTime:
                if let power = snapshot.power,
                   let seconds = power.timeRemainingSeconds,
                   let value = BatteryTimeSupport.formatted(seconds: seconds) {
                    groups.append([.metricBlock(label: "BAT", value: value, minimumValue: "99h 59m",
                                                widthKey: "batteryTime", pressure: nil)])
                } else if let power = snapshot.power,
                          power.hasBattery, !power.externalConnected, !power.isCharging {
                    groups.append([.metricBlock(label: "BAT", value: "...", minimumValue: "99h 59m",
                                                widthKey: "batteryTime", pressure: nil)])
                }
            case .peripheralBattery:
                if let metricValue = PeripheralBatterySupport.menuBarMetric(for: snapshot.peripheralBatteries) {
                    groups.append([.metricBlock(label: metricValue.label, value: metricValue.value,
                                                minimumValue: "100%+9", widthKey: "peripheralBattery",
                                                pressure: nil)])
                }
            case .power:
                if let watts = snapshot.power?.systemWatts {
                    groups.append([.metricBlock(label: "PWR", value: MetricFormat.wattsCompact(watts),
                                                minimumValue: "999W", widthKey: "power", pressure: nil)])
                }
            case .connectedDevices:
                // The list has its own event-driven owner rather than a field
                // in the AMD monitor's snapshot; nothing shows until it has
                // been read once.
                let devices = ConnectedDevicesMonitor.shared
                // With nothing connected the item leaves the menu bar.
                if devices.hasLoadedOnce, devices.count > 0 {
                    groups.append([.metricBlock(label: FeatureStrings.connectedDevices(L10n.shared.language).menuBarLabel,
                                                value: "\(devices.count)", minimumValue: "99",
                                                widthKey: "connectedDevices", pressure: nil)])
                }
            }
        }
        return blockJoined(groups, settings: settings)
    }


    private static func combinedBlock(component: String,
                                      widthKey: String,
                                      usage: String?,
                                      temperature: String?,
                                      settings: MenuBarRenderSettings) -> MenuBarSegment? {
        guard let value = combinedComponentValue(primary: usage, temperature: temperature) else { return nil }
        // The width memory follows what the block shows: a temperature alone
        // must not inherit the four digits "23% 58°" taught the pair.
        let contentKey = widthKey + (usage != nil ? "+usage" : "") + (temperature != nil ? "+temp" : "")
        return .metricBlock(label: combinedComponentLabel(component, hasPrimary: usage != nil,
                                                          hasTemperature: temperature != nil, settings),
                            value: value,
                            minimumValue: minimumCombinedValue(primary: usage != nil, temperature: temperature != nil),
                            widthKey: contentKey,
                            pressure: nil)
    }

    private static func temperatureBlock(_ component: String,
                                         _ celsius: Double,
                                         widthKey: String,
                                         _ settings: MenuBarRenderSettings) -> MenuBarSegment {
        .metricBlock(label: temperatureLabel(component, settings),
                     value: temperatureCompact(celsius, settings),
                     minimumValue: "999°",
                     widthKey: widthKey,
                     pressure: nil)
    }

    private static func blockJoined(_ groups: [[MenuBarSegment]], settings: MenuBarRenderSettings) -> [MenuBarSegment] {
        let glue = MenuBarSpacingSupport.blockGlue(spacing: settings.spacing)
        var segments: [MenuBarSegment] = []
        for group in groups {
            if !segments.isEmpty { segments.append(.text(glue)) }
            segments.append(contentsOf: group)
        }
        return segments
    }

    // MARK: - Text blocks

    private static func metricBlockImage(label: String,
                                         value: String,
                                         minimumValue reservedValue: String,
                                         widthKey: String,
                                         pressure: MemoryPressure?,
                                         settings: MenuBarRenderSettings,
                                         widthMemory: MenuBarWidthMemory) -> BlockImage {
        // Compact spacing hugs the value's digit count (with a stability
        // floor, see MenuBarWidthMemory) instead of the metric's absolute
        // maximum; the reserve participates in the cache key, so both modes
        // cache correctly side by side.
        let minimumValue = settings.spacing == .compact
            ? widthMemory.compactReserve(key: widthKey, value: value)
            : reservedValue
        let pressureKey = pressure.map(String.init(describing:)) ?? "none"
        let key = "metric|\(label)|\(value)|\(minimumValue)|\(pressureKey)|\(settings.appearanceName)"
        let cacheKey = key as NSString
        if let cached = blockImageCache.object(forKey: cacheKey) { return BlockImage(image: cached, key: key) }

        let labelFont = NSFont.systemFont(ofSize: 6.6, weight: .medium)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .semibold)
        let sizingLabelAttrs: [NSAttributedString.Key: Any] = [.font: labelFont]
        let sizingValueAttrs: [NSAttributedString.Key: Any] = [.font: valueFont]
        let labelSize = (label as NSString).size(withAttributes: sizingLabelAttrs)
        let valueSize = (value as NSString).size(withAttributes: sizingValueAttrs)
        let minimumValueSize = (minimumValue as NSString).size(withAttributes: sizingValueAttrs)
        let dotDiameter: CGFloat = pressure == nil ? 0 : 4.8
        let dotGap: CGFloat = pressure == nil || value.isEmpty ? 0 : 4
        let reservedValueWidth = max(valueSize.width, minimumValueSize.width)
        let reservedGroupWidth = dotDiameter + dotGap + reservedValueWidth
        let drawnGroupWidth = dotDiameter + dotGap + valueSize.width
        let width = ceil(max(labelSize.width, reservedGroupWidth) + 0.5)
        let height: CGFloat = 21
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()
            let labelAttrs = dynamicTextAttributes(font: labelFont)
            let valueAttrs = dynamicTextAttributes(font: valueFont)
            (label as NSString).draw(at: NSPoint(x: (width - labelSize.width) / 2, y: 12.0),
                                     withAttributes: labelAttrs)
            var valueX = (width - drawnGroupWidth) / 2
            if let pressure {
                let dotRect = NSRect(x: valueX, y: 3.5, width: dotDiameter, height: dotDiameter)
                nsColor(for: pressure).setFill()
                NSBezierPath(ovalIn: dotRect).fill()
                valueX += dotDiameter + dotGap
            }
            (value as NSString).draw(at: NSPoint(x: valueX, y: -0.8), withAttributes: valueAttrs)
            return true
        }
        image.isTemplate = false
        blockImageCache.setObject(image, forKey: cacheKey, cost: blockImageCost(image))
        return BlockImage(image: image, key: key)
    }

    private static func usageBarBlockImage(label: String,
                                           fraction: Double?,
                                           pressure: MemoryPressure?,
                                           settings: MenuBarRenderSettings) -> BlockImage {
        let innerSteps = 15
        let fillLevel = fraction.map { MenuBarUsageBarSupport.fillLevel(for: $0, steps: innerSteps) }
        let fillColorHex = fraction.map { settings.usageBarColorHex(for: $0) } ?? "missing"
        let pressureKey = pressure.map(String.init(describing:)) ?? "none"
        let levelKey = fillLevel.map(String.init) ?? "missing"
        let key = "usageBar|\(label)|\(levelKey)|\(fillColorHex)|\(pressureKey)|\(settings.appearanceName)"
        let cacheKey = key as NSString
        if let cached = blockImageCache.object(forKey: cacheKey) { return BlockImage(image: cached, key: key) }

        let size = usageBarSize(showsPressure: pressure != nil)
        let labelFont = NSFont.systemFont(ofSize: 6.1, weight: .semibold)
        let labelAttributes = dynamicTextAttributes(font: labelFont)
        let labelWidth: CGFloat = stackedLabelWidth
        let labelGap: CGFloat = 2
        let dotDiameter: CGFloat = pressure == nil ? 0 : 4.4
        let dotGap: CGFloat = pressure == nil ? 0 : 2.2
        let barWidth: CGFloat = 9
        let barHeight: CGFloat = 18
        let barX = labelWidth + labelGap + dotDiameter + dotGap
        let barY = (size.height - barHeight) / 2

        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()

            let characters = Array(label.prefix(3)).map(String.init)
            let rowHeight = (size.height - 2) / 3
            for (index, character) in characters.enumerated() {
                let characterSize = (character as NSString).size(withAttributes: labelAttributes)
                let x = (labelWidth - characterSize.width) / 2
                let y = size.height - 1 - rowHeight * CGFloat(index + 1)
                    + (rowHeight - characterSize.height) / 2
                (character as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: labelAttributes)
            }

            if let pressure {
                let dotRect = NSRect(x: labelWidth + labelGap,
                                     y: (size.height - dotDiameter) / 2,
                                     width: dotDiameter,
                                     height: dotDiameter)
                nsColor(for: pressure).setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }

            let outlineRect = NSRect(x: barX + 0.5,
                                     y: barY + 0.5,
                                     width: barWidth - 1,
                                     height: barHeight - 1)
            let outline = NSBezierPath(roundedRect: outlineRect, xRadius: 2.2, yRadius: 2.2)
            NSColor.labelColor.setStroke()
            outline.lineWidth = 1.15
            outline.stroke()

            let innerRect = outlineRect.insetBy(dx: 1.6, dy: 1.6)
            let clampedFrac = min(1.0, max(0.0, fraction ?? 0.0))
            if clampedFrac > 0 {
                let fillHeight = max(1.0, innerRect.height * CGFloat(clampedFrac))
                let fillRect = NSRect(x: innerRect.minX,
                                      y: innerRect.minY,
                                      width: innerRect.width,
                                      height: fillHeight)
                usageBarColor(hex: fillColorHex).setFill()
                NSBezierPath(roundedRect: fillRect, xRadius: 1.2, yRadius: 1.2).fill()
            } else if fraction == nil {
                NSColor.secondaryLabelColor.setStroke()
                let dash = NSBezierPath()
                dash.move(to: NSPoint(x: innerRect.minX + 0.3, y: innerRect.midY))
                dash.line(to: NSPoint(x: innerRect.maxX - 0.3, y: innerRect.midY))
                dash.lineWidth = 1
                dash.stroke()
            }
            return true
        }
        image.isTemplate = false
        blockImageCache.setObject(image, forKey: cacheKey, cost: blockImageCost(image))
        return BlockImage(image: image, key: key)
    }

    private static func usageBarSize(showsPressure: Bool) -> CGSize {
        CGSize(width: 19 + (showsPressure ? 7 : 0), height: blockHeight)
    }

    private static func usageBarColor(hex: String) -> NSColor {
        if let cached = colorCache.object(forKey: hex as NSString) { return cached }
        let rgb = MenuBarUsageBarSupport.rgb(for: hex,
                                             fallback: MenuBarUsageBarSupport.defaultNormalColor)
        let color = NSColor(srgbRed: CGFloat(rgb.red),
                            green: CGFloat(rgb.green),
                            blue: CGFloat(rgb.blue),
                            alpha: 1)
        colorCache.setObject(color, forKey: hex as NSString)
        return color
    }

    private static func networkBlockImage(down: String, up: String, settings: MenuBarRenderSettings) -> BlockImage {
        let uploadFirst = settings.networkUploadFirst
        let key = "network|\(down)|\(up)|\(uploadFirst)|\(settings.appearanceName)"
        let lines = uploadFirst ? ["↑\(up)", "↓\(down)"] : ["↓\(down)", "↑\(up)"]
        return stackedRatesImage(label: "NET",
                                 lines: lines,
                                 reservedLines: ["↓000B", "↑000B"],
                                 cacheKey: key)
    }

    private static func diskActivityBlockImage(read: String,
                                               write: String,
                                               settings: MenuBarRenderSettings) -> BlockImage {
        stackedRatesImage(label: nil,
                          lines: ["R\(read)", "W\(write)"],
                          reservedLines: ["R000B", "W000B"],
                          cacheKey: "diskActivity|\(read)|\(write)|\(settings.appearanceName)")
    }

    private static func stackedRatesImage(label: String? = nil,
                                          lines: [String],
                                          reservedLines: [String],
                                          cacheKey key: String) -> BlockImage {
        let cacheKey = key as NSString
        if let cached = blockImageCache.object(forKey: cacheKey) { return BlockImage(image: cached, key: key) }

        let font = NSFont.monospacedSystemFont(ofSize: rateFontSize, weight: .semibold)
        let lineHeight = rateLineHeight
        let candidates = reservedLines.isEmpty ? lines : reservedLines
        let rateWidth = rateBlockWidth(candidates: candidates)
        let height = blockHeight

        let hasLabel = label != nil && !(label?.isEmpty ?? true)
        let labelWidth: CGFloat = hasLabel ? stackedLabelWidth : 0
        let labelGap: CGFloat = hasLabel ? 3.0 : 0
        let totalWidth = labelWidth + labelGap + rateWidth

        let imageSize = NSSize(width: totalWidth, height: height)
        let image = NSImage(size: imageSize, flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()

            // 1. Vertical stacked label if present (e.g. "NET")
            if let label, !label.isEmpty {
                let labelFont = NSFont.systemFont(ofSize: 6.1, weight: .bold)
                let labelAttrs = dynamicTextAttributes(font: labelFont)
                let characters = Array(label.prefix(3)).map(String.init)
                let rowHeight = (height - 2) / 3
                for (index, character) in characters.enumerated() {
                    let characterSize = (character as NSString).size(withAttributes: labelAttrs)
                    let x = (labelWidth - characterSize.width) / 2
                    let y = height - 1 - rowHeight * CGFloat(index + 1) + (rowHeight - characterSize.height) / 2
                    (character as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: labelAttrs)
                }
            }

            // 2. Rate lines on the right
            let startX = labelWidth + labelGap
            let attrs = dynamicTextAttributes(font: font)
            let textSize = ((reservedLines.first ?? lines.first ?? "") as NSString).size(withAttributes: attrs)
            let contentHeight = lineHeight + textSize.height
            let bottomY = (imageSize.height - contentHeight) / 2
            for (index, line) in lines.enumerated() {
                let y = bottomY + lineHeight * CGFloat(1 - index)
                let lineSize = (line as NSString).size(withAttributes: attrs)
                let x = startX + max(0.5, rateWidth - lineSize.width - 0.5)
                (line as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
            }
            return true
        }
        image.isTemplate = false
        blockImageCache.setObject(image, forKey: cacheKey, cost: blockImageCost(image))
        return BlockImage(image: image, key: key)
    }

    private static func rateBlockWidth(candidates: [String]) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: rateFontSize, weight: .semibold)
        let sizingAttrs: [NSAttributedString.Key: Any] = [.font: font]
        let contentWidth = candidates.map { ($0 as NSString).size(withAttributes: sizingAttrs).width }.max() ?? 22
        return ceil(contentWidth + 1.0)
    }

    private static func batteryBlockImage(percent: Int,
                                          isCharging: Bool,
                                          settings: MenuBarRenderSettings) -> BlockImage {
        let clampedPercent = max(0, min(100, percent))
        let key = "battery|\(clampedPercent)|\(isCharging)|\(settings.appearanceName)"
        let cacheKey = key as NSString
        if let cached = blockImageCache.object(forKey: cacheKey) { return BlockImage(image: cached, key: key) }

        let symbolName = batterySymbol(for: percent, isCharging: isCharging)
        let symbolPointSize: CGFloat = 15.5
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .semibold)
        let value = "\(clampedPercent)%"
        let sizingValueAttrs: [NSAttributedString.Key: Any] = [.font: valueFont]
        let valueSize = (value as NSString).size(withAttributes: sizingValueAttrs)
        let reservedValueSize = max(valueSize.width, ("100%" as NSString).size(withAttributes: sizingValueAttrs).width)
        let symbolWidth: CGFloat = 18
        let gap: CGFloat = 4
        let height = blockHeight
        let imageSize = NSSize(width: ceil(symbolWidth + gap + reservedValueSize), height: height)
        // Resolve the symbol once, before the drawing block, and reuse it on
        // every frame the cache misses for; minting SF symbols inside a draw
        // closure re-resolves on each redraw.
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
        let image = NSImage(size: imageSize, flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()
            if let symbol {
                let symbolSize = symbol.size
                // draw(in:) stretches the image to exactly fill the rect, so
                // both dimensions scale together to keep the glyph's own
                // proportions.
                let scale = min(symbolWidth / symbolSize.width, 1)
                let drawSize = NSSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
                let symbolRect = NSRect(x: 0,
                                        y: (height - drawSize.height) / 2,
                                        width: drawSize.width,
                                        height: drawSize.height)
                symbol.draw(in: symbolRect)
            }
            let valueAttrs = dynamicTextAttributes(font: valueFont)
            let valueY = (height - valueSize.height) / 2
            (value as NSString).draw(at: NSPoint(x: symbolWidth + gap, y: valueY),
                                     withAttributes: valueAttrs)
            return true
        }
        image.isTemplate = false
        blockImageCache.setObject(image, forKey: cacheKey, cost: blockImageCost(image))
        return BlockImage(image: image, key: key)
    }

    private static func dynamicTextAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.labelColor]
    }

    static func batterySymbol(for percent: Int, isCharging: Bool) -> String {
        if isCharging { return "battery.100.bolt" }
        switch percent {
        case 85...: return "battery.100"
        case 60..<85: return "battery.75"
        case 35..<60: return "battery.50"
        case 10..<35: return "battery.25"
        default: return "battery.0"
        }
    }

    // MARK: - Graph blocks

    /// The frame every graph block shares: the stacked three letter label on
    /// the left, then the graph box with one point free above and below.
    private struct GraphBlockLayout {
        let height: CGFloat
        let labelWidth: CGFloat
        let box: NSRect

        var imageSize: NSSize { NSSize(width: box.maxX, height: height) }
        var plotHeight: CGFloat { box.height - MenuBarGraphGeometry.plotInset * 2 }
        var plotWidth: CGFloat { box.width - MenuBarGraphGeometry.plotInset * 2 }

        init(boxWidth: CGFloat) {
            height = MenuBarRenderer.blockHeight
            labelWidth = MenuBarRenderer.stackedLabelWidth
            // A whole point origin keeps one point columns on pixel boundaries.
            box = NSRect(x: ceil(labelWidth + 3), y: 1, width: boxWidth, height: height - 2)
        }

        static var square: GraphBlockLayout { GraphBlockLayout(boxWidth: MenuBarRenderer.blockHeight - 2) }
    }

    private static func drawStackedLabel(_ label: String, layout: GraphBlockLayout) {
        let labelFont = NSFont.systemFont(ofSize: 6.1, weight: .bold)
        let labelAttrs = dynamicTextAttributes(font: labelFont)
        let rowHeight = (layout.height - 2) / 3
        for (index, character) in label.prefix(3).map(String.init).enumerated() {
            let characterSize = (character as NSString).size(withAttributes: labelAttrs)
            let x = (layout.labelWidth - characterSize.width) / 2
            let y = layout.height - 1 - rowHeight * CGFloat(index + 1) + (rowHeight - characterSize.height) / 2
            (character as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: labelAttrs)
        }
    }

    /// Fractions snapped to half point steps of the plot. The image is drawn
    /// from the snapped values, so a cache hit is pixel identical to a fresh
    /// render; anything above zero keeps at least one step, like the columns.
    private static func snapped(_ values: [Double], plotHeight: CGFloat) -> [Double] {
        let steps = Double(max(1, plotHeight * 2))
        return values.map { value in
            guard value.isFinite, value > 0 else { return 0 }
            return max(1, (min(1, value) * steps).rounded()) / steps
        }
    }

    private static func sampleKey(_ values: [Double]) -> String {
        values.map { String(Int(($0 * 1000).rounded())) }.joined(separator: ",")
    }

    private static func graphSegment(key: String,
                                     size: NSSize,
                                     draw: @escaping (MenuBarGraphPainter.Style) -> Void) -> MenuBarSegment {
        let cacheKey = key as NSString
        if let cached = graphImageCache.object(forKey: cacheKey) { return .customImage(cached, key: key) }
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()
            draw(MenuBarGraphPainter.currentStyle())
            return true
        }
        image.isTemplate = false
        graphImageCache.setObject(image, forKey: cacheKey, cost: blockImageCost(image))
        return .customImage(image, key: key)
    }

    private static func networkDualGraphBlock(downHistory: [Double],
                                              upHistory: [Double],
                                              settings: MenuBarRenderSettings) -> MenuBarSegment {
        let layout = GraphBlockLayout(boxWidth: settings.historyWidth.points)
        let spaced = settings.historySpaced
        let graphLayout = settings.networkGraphLayout
        let count = MenuBarGraphGeometry.historySampleCount(plotWidth: layout.plotWidth, spaced: spaced)
        let downs = Array(downHistory.suffix(count))
        let ups = Array(upHistory.suffix(count))
        let half = (layout.plotHeight - 1) / 2
        let downScale = MenuBarGraphGeometry.dualScale(downs)
        let upScale = MenuBarGraphGeometry.dualScale(ups)
        let downFractions = snapped(downs.map { $0 / downScale }, plotHeight: half)
        let upFractions = snapped(ups.map { $0 / upScale }, plotHeight: half)
        let key = ["netDual", sampleKey(downFractions), sampleKey(upFractions),
                   "\(layout.box.width)", "\(spaced)", graphLayout.rawValue,
                   settings.graphToken, settings.appearanceName].joined(separator: "|")
        return graphSegment(key: key, size: layout.imageSize) { graphStyle in
            drawStackedLabel("NET", layout: layout)
            MenuBarGraphPainter.drawBox(layout.box, style: graphStyle)
            MenuBarGraphPainter.drawDualHistory(upload: upFractions,
                                                download: downFractions,
                                                layout: graphLayout,
                                                uploadColor: graphStyle.secondary,
                                                downloadColor: graphStyle.primary,
                                                in: layout.box,
                                                spaced: spaced)
        }
    }

    private static func drawGraphValueOverlay(valueText: String,
                                              in rect: NSRect,
                                              graphStyle: MenuBarGraphPainter.Style,
                                              fontScale: CGFloat = 1.0) {
        guard !valueText.isEmpty else { return }
        let fontSize: CGFloat = 7.8 * fontScale
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .heavy)
        let onDark = graphStyle.overlaysOnDarkSurface
        let shadow = NSShadow()
        shadow.shadowColor = (onDark ? NSColor.black : NSColor.white).withAlphaComponent(0.85)
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = 1.0

        let mainAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: onDark ? NSColor.white : NSColor.black,
            .shadow: shadow
        ]
        let valSize = (valueText as NSString).size(withAttributes: mainAttrs)
        let vx = floor(rect.minX + (rect.width - valSize.width) / 2.0)
        let vy = floor(rect.minY + (rect.height - valSize.height) / 2.0)
        (valueText as NSString).draw(at: NSPoint(x: vx, y: vy), withAttributes: mainAttrs)
    }

    private static func coreHistogramBlock(cores: [CoreSnapshot],
                                           valueText: String?,
                                           settings: MenuBarRenderSettings) -> MenuBarSegment {
        let totals = MenuBarGraphGeometry.physicalCoreLoads(cores)
        let systems = MenuBarGraphGeometry.physicalCoreLoads(cores, percent: { $0.systemPct })
        let layout = GraphBlockLayout(boxWidth: MenuBarGraphGeometry.coreBoxWidth(coreCount: totals.count))
        let loads = snapped(totals, plotHeight: layout.plotHeight)
        let userLoads = snapped(MenuBarGraphGeometry.userShares(total: totals, system: systems),
                                plotHeight: layout.plotHeight)
        let key = ["cores", sampleKey(loads), sampleKey(userLoads), valueText ?? "",
                   settings.graphToken, settings.appearanceName].joined(separator: "|")
        return graphSegment(key: key, size: layout.imageSize) { graphStyle in
            drawStackedLabel("CPU", layout: layout)
            MenuBarGraphPainter.drawBox(layout.box, style: graphStyle)
            MenuBarGraphPainter.drawCoreBars(series: [loads, userLoads],
                                             colors: [graphStyle.secondary, graphStyle.primary],
                                             in: layout.box)
            if let valueText {
                drawGraphValueOverlay(valueText: valueText, in: layout.box, graphStyle: graphStyle)
            }
        }
    }

    /// `values` are cumulative fractions like the history series: with two,
    /// the first (the whole) takes the secondary color and the second (the
    /// part) the theme's main color.
    private static func ringBlock(label: String,
                                  values: [Double],
                                  valueText: String?,
                                  settings: MenuBarRenderSettings) -> MenuBarSegment {
        let layout = GraphBlockLayout.square
        let angles = values.map { value -> Double in
            guard value.isFinite, value > 0 else { return 0 }
            return max(1, (min(1, value) * 360).rounded()) / 360
        }
        let key = ["ring", label, sampleKey(angles), valueText ?? "",
                   settings.graphToken, settings.appearanceName].joined(separator: "|")
        return graphSegment(key: key, size: layout.imageSize) { graphStyle in
            drawStackedLabel(label, layout: layout)
            MenuBarGraphPainter.drawBox(layout.box, style: graphStyle, circular: true)
            let colors = angles.count > 1 ? [graphStyle.secondary, graphStyle.primary] : [graphStyle.primary]
            MenuBarGraphPainter.drawRing(values: angles, colors: colors, in: layout.box)
            if let valueText {
                drawGraphValueOverlay(valueText: valueText, in: layout.box, graphStyle: graphStyle, fontScale: 0.72)
            }
        }
    }

    /// `series` are cumulative fractions (see `MenuBarGraphPainter.drawHistory`);
    /// with two, the part takes the theme's main color over the secondary whole.
    private static func historyBlock(label: String,
                                     series: [[Double]],
                                     valueText: String?,
                                     settings: MenuBarRenderSettings) -> MenuBarSegment {
        let layout = GraphBlockLayout(boxWidth: settings.historyWidth.points)
        let spaced = settings.historySpaced
        let count = MenuBarGraphGeometry.historySampleCount(plotWidth: layout.plotWidth, spaced: spaced)
        let visible = series.map { snapped(Array($0.suffix(count)), plotHeight: layout.plotHeight) }
        let key = ["history", label, visible.map(sampleKey).joined(separator: "/"), valueText ?? "",
                   "\(layout.box.width)", "\(spaced)",
                   settings.graphToken, settings.appearanceName].joined(separator: "|")
        return graphSegment(key: key, size: layout.imageSize) { graphStyle in
            drawStackedLabel(label, layout: layout)
            MenuBarGraphPainter.drawBox(layout.box, style: graphStyle)
            let colors = visible.count > 1 ? [graphStyle.secondary, graphStyle.primary] : [graphStyle.primary]
            MenuBarGraphPainter.drawHistory(series: visible, colors: colors, in: layout.box, spaced: spaced)
            if let valueText {
                drawGraphValueOverlay(valueText: valueText, in: layout.box, graphStyle: graphStyle)
            }
        }
    }

    // MARK: - Helpers

    private static func primaryDisk(from reading: DiskReading?) -> DiskDeviceReading? {
        guard let devices = reading?.devices, !devices.isEmpty else { return nil }
        return devices.first(where: { $0.isInternal }) ?? devices.first
    }

    private static func diskActivity(from reading: DiskReading?) -> (read: Double, write: Double)? {
        let devices = reading?.uniqueIODevices ?? []
        guard !devices.isEmpty else { return nil }
        let readValues = devices.compactMap(\.readBytesPerSec)
        let writeValues = devices.compactMap(\.writeBytesPerSec)
        guard !readValues.isEmpty || !writeValues.isEmpty else { return nil }
        return (readValues.reduce(0, +), writeValues.reduce(0, +))
    }

    static func nsColor(for pressure: MemoryPressure) -> NSColor {
        switch pressure {
        case .normal: return .systemGreen
        case .warning: return .systemYellow
        case .critical: return .systemRed
        case .unknown: return .secondaryLabelColor
        }
    }

    /// A compact 0...1 fraction: "5%", "47%", "100%".
    private static func percent(_ fraction: Double) -> String {
        let value = Int((max(0, min(1, fraction)) * 100).rounded())
        return "\(value)%"
    }

    private static func temperatureCompact(_ celsius: Double, _ settings: MenuBarRenderSettings) -> String {
        MetricFormat.temperatureCompact(celsius, unit: settings.temperatureUnit)
    }

    private static func temperatureLabel(_ component: String, _ settings: MenuBarRenderSettings) -> String {
        component + MetricFormat.temperatureUnitSuffix(settings.temperatureUnit)
    }

    private static func combinedComponentLabel(_ component: String,
                                               hasPrimary: Bool,
                                               hasTemperature: Bool,
                                               _ settings: MenuBarRenderSettings) -> String {
        if hasPrimary { return component }
        return hasTemperature ? temperatureLabel(component, settings) : component
    }

    private static func combinedComponentValue(primary: String?, temperature: String?) -> String? {
        var values: [String] = []
        if let primary { values.append(primary) }
        if let temperature { values.append(temperature) }
        return values.isEmpty ? nil : values.joined(separator: " ")
    }

    private static func minimumCombinedValue(primary: Bool, temperature: Bool) -> String {
        switch (primary, temperature) {
        case (true, true): return "100% 999°"
        case (true, false): return "100%"
        case (false, true): return "999°"
        case (false, false): return ""
        }
    }
}
