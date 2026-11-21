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
    /// `valueColorHex` colors a highlighted value; nil uses the text color.
    case metricBlock(label: String, value: String, minimumValue: String, widthKey: String,
                     pressure: MemoryPressure?, valueColorHex: String?)
    /// Label (optional) and value on one line.
    case inlineBlock(label: String?, value: String, minimumValue: String, widthKey: String,
                     pressure: MemoryPressure?, valueColorHex: String?)
    /// A symbol and a value.
    case iconBlock(symbol: String, value: String, minimumValue: String, widthKey: String, valueColorHex: String?)
    case usageBarBlock(label: String, fraction: Double?, pressure: MemoryPressure?)
    /// Two values in two lines, with an optional stacked name beside them.
    case dualBlock(label: String?, lines: [String], reservedLines: [String], kind: String)
    case batteryBlock(percent: Int, isCharging: Bool)
    /// A pre-rendered block; `key` is its image cache key.
    case customImage(NSImage, key: String)
}

/// A rendered title, a key that changes exactly when the title would look
/// different, and the words VoiceOver reads for it. Comparing attributed
/// strings cannot tell: every render builds new text attachments, and two
/// attachments holding the same image never compare equal, so the status
/// item used to rewrite and re-lay out its title on every monitor tick.
struct MenuBarRender {
    let string: NSAttributedString
    let key: String
    let spoken: String

    static let empty = MenuBarRender(string: NSAttributedString(), key: "", spoken: "")
}

/// Builds the compact content shown next to the icon.
///
/// Output is a list of segments turned into an attributed string of cached
/// block images. Labels are intentionally abbreviated because the menu bar is
/// a scarce space, especially on notched MacBooks.
enum MenuBarRenderer {
    private static let statusFontSize: CGFloat = 11.6
    private static let dualFontSize: CGFloat = 9.5
    private static let dualLineHeight: CGFloat = 10.0
    private static let blockHeight: CGFloat = 20
    /// Width of the stacked three letter name beside bars, graphs and
    /// two-line readings.
    private static let stackedLabelWidth: CGFloat = 7
    private static let stackedLabelFontSize: CGFloat = 7
    /// The small name above a value. 8 pt is the smallest text iStat Menus
    /// draws in a menu bar of this height; the old 6.6 pt was hard to read.
    private static let aboveLabelFontSize: CGFloat = 8
    private static let inlineLabelFontSize: CGFloat = 10
    private static let valueFontSize: CGFloat = 12

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

    /// The font of the two-line readings (frequency, temperature and power,
    /// network, disk activity).
    static func rateLineFont(narrow: Bool = false) -> NSFont {
        textFont(size: dualFontSize, weight: .semibold, narrow: narrow)
    }

    static func statusFont() -> NSFont {
        NSFont.monospacedSystemFont(ofSize: statusFontSize, weight: .medium)
    }

    /// SF with fixed-width digits, condensed for the narrow text option.
    private static func textFont(size: CGFloat, weight: NSFont.Weight, narrow: Bool) -> NSFont {
        fontTable[FontKey(size: size, weight: weight.rawValue, narrow: narrow)]
            ?? makeTextFont(size: size, weight: weight, narrow: narrow)
    }

    private struct FontKey: Hashable {
        let size: CGFloat
        let weight: CGFloat
        let narrow: Bool
    }

    /// Every text font the blocks use, made once: fonts are immutable, so the
    /// table is safe to read from drawing handlers on any thread.
    private static let fontTable: [FontKey: NSFont] = {
        var table: [FontKey: NSFont] = [:]
        let uses: [(CGFloat, NSFont.Weight)] = [(aboveLabelFontSize, .medium), (inlineLabelFontSize, .medium),
                                                (valueFontSize, .semibold), (dualFontSize, .semibold)]
        for (size, weight) in uses {
            for narrow in [false, true] {
                table[FontKey(size: size, weight: weight.rawValue, narrow: narrow)] =
                    makeTextFont(size: size, weight: weight, narrow: narrow)
            }
        }
        return table
    }()

    private static let stackedLabelFont = NSFont.systemFont(ofSize: stackedLabelFontSize, weight: .bold)
    private static let overlayFont = NSFont.monospacedDigitSystemFont(ofSize: 7.8, weight: .heavy)
    private static let ringOverlayFont = NSFont.monospacedDigitSystemFont(ofSize: 7.8 * 0.72, weight: .heavy)

    private static func makeTextFont(size: CGFloat, weight: NSFont.Weight, narrow: Bool) -> NSFont {
        guard narrow else { return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) }
        let condensed = NSFont.systemFont(ofSize: size, weight: weight, width: .condensed)
        // Number spacing (type 6), monospaced numbers (selector 0).
        let descriptor = condensed.fontDescriptor.addingAttributes([
            .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: 6,
                                NSFontDescriptor.FeatureKey.selectorIdentifier: 0]],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? condensed
    }
    /// The blocks for `metrics`, joined with the spacing glue.
    static func segments(for snapshot: SystemSnapshot,
                         metrics: [MenuBarMetric],
                         settings: MenuBarRenderSettings,
                         widthMemory: MenuBarWidthMemory = .shared) -> [MenuBarSegment] {
        blockSegments(for: snapshot, metrics: metrics, settings: settings, widthMemory: widthMemory).segments
    }

    /// The attributed title for the status item, with its change key. Only
    /// alert dots, usage fills and highlighted values get fixed colors; text
    /// and graph blocks use dynamic system colors resolved when the button
    /// draws them.
    static func render(for snapshot: SystemSnapshot,
                       metrics: [MenuBarMetric],
                       settings: MenuBarRenderSettings,
                       widthMemory: MenuBarWidthMemory = .shared) -> MenuBarRender {
        let blocks = blockSegments(for: snapshot, metrics: metrics, settings: settings, widthMemory: widthMemory)
        guard !blocks.segments.isEmpty else { return .empty }
        let result = NSMutableAttributedString()
        var keyParts: [String] = []
        keyParts.reserveCapacity(blocks.segments.count)
        for segment in blocks.segments {
            switch segment {
            case let .text(string):
                result.append(NSAttributedString(string: string))
                keyParts.append("t:" + string)
            case let .metricBlock(label, value, minimumValue, widthKey, pressure, colorHex):
                let block = metricBlockImage(label: label, value: value, minimumValue: minimumValue,
                                             widthKey: widthKey, pressure: pressure, valueColorHex: colorHex,
                                             settings: settings, widthMemory: widthMemory)
                result.append(attachment(block.image, yOffset: -5.7))
                keyParts.append(block.key)
            case let .inlineBlock(label, value, minimumValue, widthKey, pressure, colorHex):
                let block = inlineBlockImage(label: label, value: value, minimumValue: minimumValue,
                                             widthKey: widthKey, pressure: pressure, valueColorHex: colorHex,
                                             settings: settings, widthMemory: widthMemory)
                result.append(attachment(block.image, yOffset: -5.5))
                keyParts.append(block.key)
            case let .iconBlock(symbol, value, minimumValue, widthKey, colorHex):
                let block = iconBlockImage(symbol: symbol, value: value, minimumValue: minimumValue,
                                           widthKey: widthKey, valueColorHex: colorHex,
                                           settings: settings, widthMemory: widthMemory)
                result.append(attachment(block.image, yOffset: -5.5))
                keyParts.append(block.key)
            case let .usageBarBlock(label, fraction, pressure):
                let block = usageBarBlockImage(label: label, fraction: fraction, pressure: pressure, settings: settings)
                // The gauge outline fills the image symmetrically, so the
                // offset centers the image itself on the status font's box.
                result.append(attachment(block.image, yOffset: -5.6))
                keyParts.append(block.key)
            case let .dualBlock(label, lines, reservedLines, kind):
                let block = dualBlockImage(label: label, lines: lines, reservedLines: reservedLines,
                                           kind: kind, settings: settings)
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
        return MenuBarRender(string: result,
                             key: keyParts.joined(separator: "\u{1F}"),
                             spoken: blocks.spoken.joined(separator: ", "))
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

    /// Collects one block per reading and the words VoiceOver says for it.
    private struct BlockList {
        var groups: [[MenuBarSegment]] = []
        var spoken: [String] = []

        mutating func add(_ segment: MenuBarSegment, spoken text: String) {
            groups.append([segment])
            spoken.append(text)
        }
    }

    private static func blockSegments(for snapshot: SystemSnapshot,
                                      metrics: [MenuBarMetric],
                                      settings: MenuBarRenderSettings,
                                      widthMemory: MenuBarWidthMemory) -> (segments: [MenuBarSegment], spoken: [String]) {
        var list = BlockList()
        let enabled = Set(metrics)
        var renderedCPU = false
        var renderedGPU = false
        var renderedBattery = false
        let showsGraphValue = settings.graphShowsValue
        let strings = L10n.shared.s

        /// A one-value reading in the metric's text style.
        func text(_ metric: MenuBarMetric, label: String, value: String, minimum: String,
                  widthKey: String? = nil, pressure: MemoryPressure? = nil,
                  fraction: Double? = nil, symbol: String? = nil, spokenTitle: String? = nil) {
            let key = widthKey ?? metric.rawValue
            let color = settings.highlightHex(for: fraction)
            let segment: MenuBarSegment
            switch settings.style(for: metric) {
            case .inline:
                segment = .inlineBlock(label: label, value: value, minimumValue: minimum, widthKey: key,
                                       pressure: pressure, valueColorHex: color)
            case .valueOnly:
                segment = .inlineBlock(label: nil, value: value, minimumValue: minimum, widthKey: key,
                                       pressure: pressure, valueColorHex: color)
            case .iconValue where symbol != nil:
                segment = .iconBlock(symbol: symbol!, value: value, minimumValue: minimum, widthKey: key,
                                     valueColorHex: color)
            default:
                segment = .metricBlock(label: label, value: value, minimumValue: minimum, widthKey: key,
                                       pressure: pressure, valueColorHex: color)
            }
            list.add(segment, spoken: "\(spokenTitle ?? metric.title(strings)) \(value)")
        }

        /// A two-value reading: two lines with or without its name, or one line.
        func dual(_ metric: MenuBarMetric, label: String, lines: [String], reserved: [String], kind: String) {
            let spoken = "\(metric.title(strings)) \(lines.joined(separator: " "))"
            switch settings.style(for: metric) {
            case .inline:
                list.add(.inlineBlock(label: label, value: lines.joined(separator: " "),
                                      minimumValue: reserved.joined(separator: " "), widthKey: metric.rawValue,
                                      pressure: nil, valueColorHex: nil), spoken: spoken)
            case .valueOnly:
                list.add(.dualBlock(label: nil, lines: lines, reservedLines: reserved, kind: kind), spoken: spoken)
            default:
                list.add(.dualBlock(label: label, lines: lines, reservedLines: reserved, kind: kind), spoken: spoken)
            }
        }

        /// Usage and temperature in one block, in the usage metric's text style.
        func combined(_ usageMetric: MenuBarMetric, component: String, usage: String?, fraction: Double?,
                      temperature: String?) {
            guard let value = combinedComponentValue(primary: usage, temperature: temperature) else { return }
            let contentKey = usageMetric.rawValue + (usage != nil ? "+usage" : "") + (temperature != nil ? "+temp" : "")
            // The width memory follows what the block shows: a temperature
            // alone must not inherit the four digits "23% 58°" taught the pair.
            text(usageMetric,
                 label: combinedComponentLabel(component, hasPrimary: usage != nil,
                                               hasTemperature: temperature != nil, settings),
                 value: value,
                 minimum: minimumCombinedValue(primary: usage != nil, temperature: temperature != nil),
                 widthKey: contentKey,
                 fraction: fraction)
        }

        for metric in metrics {
            switch metric {
            case .cpu, .cpuTemperature:
                if settings.combinesTemperature(of: .cpu, enabled: enabled) {
                    guard !renderedCPU else { break }
                    renderedCPU = true
                    let usage = enabled.contains(.cpu) ? snapshot.cpuUsage : nil
                    combined(.cpu, component: "CPU", usage: usage.map(percent), fraction: usage,
                             temperature: enabled.contains(.cpuTemperature)
                                ? snapshot.cpuTemperature.map { temperatureCompact($0, settings) } : nil)
                    break
                }
                guard metric == .cpu else {
                    if let temperature = snapshot.cpuTemperature {
                        text(.cpuTemperature, label: temperatureLabel("CPU", settings),
                             value: temperatureCompact(temperature, settings), minimum: "999°")
                    }
                    break
                }
                guard let usage = snapshot.cpuUsage else { break }
                let valueText = showsGraphValue ? percent(usage) : nil
                let spoken = "\(metric.title(strings)) \(percent(usage))"
                switch settings.style(for: .cpu) {
                case .histogram where !snapshot.cores.isEmpty:
                    list.add(coreHistogramBlock(cores: snapshot.cores, valueText: valueText, settings: settings),
                             spoken: spoken)
                case .pie:
                    let userShare = max(0, usage - (snapshot.cpuSystemUsage ?? 0))
                    list.add(ringBlock(label: "CPU", values: [usage, userShare], valueText: valueText,
                                       settings: settings), spoken: spoken)
                case .sparkline:
                    // System time stacks over user time, as in the cores graph.
                    let userHistory = MenuBarGraphGeometry.userShares(total: snapshot.cpuHistory,
                                                                      system: snapshot.cpuSystemHistory)
                    list.add(historyBlock(label: "CPU", series: [snapshot.cpuHistory, userHistory],
                                          valueText: valueText, settings: settings), spoken: spoken)
                case .bars:
                    list.add(.usageBarBlock(label: "CPU", fraction: usage, pressure: nil), spoken: spoken)
                default:
                    text(.cpu, label: "CPU", value: percent(usage), minimum: "100%", fraction: usage)
                }
            case .gpu, .gpuTemperature:
                if settings.combinesTemperature(of: .gpu, enabled: enabled) {
                    guard !renderedGPU else { break }
                    renderedGPU = true
                    let usage = enabled.contains(.gpu) ? snapshot.gpuUsage : nil
                    // Never a VRAM reading: with VRAM chosen the setting keeps
                    // the temperature out of this block (combinesTemperature),
                    // whether the kext delivers it or the macOS reading stands in.
                    let displayTemperature = enabled.contains(.gpuTemperature)
                        ? snapshot.gpuDisplayCelsius.map { temperatureCompact($0, settings) } : nil
                    combined(.gpu, component: "GPU", usage: usage.map(percent), fraction: usage,
                             temperature: displayTemperature)
                    break
                }
                guard metric == .gpu else {
                    if let temperature = snapshot.gpuDisplayCelsius {
                        text(.gpuTemperature, label: temperatureLabel(snapshot.gpuDisplayLabel, settings),
                             value: temperatureCompact(temperature, settings), minimum: "999°")
                    }
                    break
                }
                guard let usage = snapshot.gpuUsage else { break }
                let valueText = showsGraphValue ? percent(usage) : nil
                let spoken = "\(metric.title(strings)) \(percent(usage))"
                switch settings.style(for: .gpu) {
                case .pie:
                    list.add(ringBlock(label: "GPU", values: [usage], valueText: valueText, settings: settings),
                             spoken: spoken)
                case .sparkline, .histogram:
                    list.add(historyBlock(label: "GPU", series: [snapshot.gpuHistory], valueText: valueText,
                                          settings: settings), spoken: spoken)
                case .bars:
                    list.add(.usageBarBlock(label: "GPU", fraction: usage, pressure: nil), spoken: spoken)
                default:
                    text(.gpu, label: "GPU", value: percent(usage), minimum: "100%", fraction: usage)
                }
            case .cpuPower:
                if let cpuPower = snapshot.cpuPower, cpuPower > 0 {
                    text(.cpuPower, label: "CPU", value: String(format: "%.0fW", cpuPower), minimum: "199W")
                }
            case .gpuPower:
                if let gpuPower = snapshot.gpuPower, gpuPower > 0 {
                    text(.gpuPower, label: "GPU", value: String(format: "%.0fW", gpuPower), minimum: "999W")
                }
            case .cpuFrequency:
                let peak = snapshot.peakCPUFreq ?? (snapshot.cores.map { Double($0.freqMHz) }.max() ?? 0)
                let avg = snapshot.avgCPUFreq ?? (snapshot.cores.isEmpty ? 0 : snapshot.cores.map { Double($0.freqMHz) }.reduce(0, +) / Double(snapshot.cores.count))
                let maxStr = String(format: "%.1fG", locale: MetricFormat.locale, max(peak, avg) / 1000.0)
                let avgStr = String(format: "%.1fG", locale: MetricFormat.locale, avg / 1000.0)
                let reserve = String(format: "%.1fG", locale: MetricFormat.locale, 8.8)
                dual(.cpuFrequency, label: "CPU", lines: [maxStr, avgStr], reserved: [reserve, reserve], kind: "freq")
            case .cpuTempPower:
                let temp = snapshot.cpuTemperature.map { temperatureCompact($0, settings) } ?? "--°"
                let pwr = snapshot.cpuPower.map { String(format: "%.0fW", $0) } ?? "--W"
                dual(.cpuTempPower, label: "CPU", lines: [temp, pwr], reserved: ["000°", "000W"], kind: "tempPwr")
            case .gpuTempPower:
                let tempValue = snapshot.gpuDisplayCelsius.map { temperatureCompact($0, settings) } ?? "--°"
                let labelled = snapshot.gpuDisplayLabel != "GPU"
                let temp = labelled ? snapshot.gpuDisplayLabel + " " + tempValue : tempValue
                let pwr = snapshot.gpuPower.map { String(format: "%.0fW", $0) } ?? "--W"
                // The block is sized from the reserved lines, so a labelled
                // VRAM line reserves room for its label too.
                let reservedTemp = labelled ? snapshot.gpuDisplayLabel + " 000°" : "000°"
                dual(.gpuTempPower, label: "GPU", lines: [temp, pwr], reserved: [reservedTemp, "000W"], kind: "tempPwr")
            case .memory:
                let memoryStyle = settings.memoryStyle
                let memoryValue = settings.memoryMetric.value(in: snapshot)
                let usedFraction = MenuBarUsageBarSupport.memoryFraction(used: snapshot.memoryUsed,
                                                                         total: snapshot.memoryTotal)
                let appFraction = MenuBarUsageBarSupport.memoryFraction(used: snapshot.memoryAppUsed,
                                                                        total: snapshot.memoryTotal)
                let shownFraction = MenuBarUsageBarSupport.memoryFraction(used: memoryValue, total: snapshot.memoryTotal)
                let percentText = MetricFormat.menuBarMemoryPercent(used: memoryValue, total: snapshot.memoryTotal)
                let memoryGraphValue = showsGraphValue ? percentText : nil
                let spoken = "\(metric.title(strings)) \(percentText)"
                let style = settings.style(for: .memory)
                // Used memory is the whole and app memory the part, so the
                // graphs show app memory in the theme's main color under the
                // rest of what is in use.
                if style == .sparkline, !snapshot.memoryHistory.isEmpty {
                    list.add(historyBlock(label: "RAM",
                                          series: [snapshot.memoryHistory, snapshot.memoryAppHistory],
                                          valueText: memoryGraphValue,
                                          settings: settings), spoken: spoken)
                } else if style == .pie, let usedFraction {
                    list.add(ringBlock(label: "RAM",
                                       values: [usedFraction] + (appFraction.map { [$0] } ?? []),
                                       valueText: memoryGraphValue,
                                       settings: settings), spoken: spoken)
                } else if style == .bars {
                    list.add(.usageBarBlock(label: "RAM",
                                            fraction: shownFraction,
                                            pressure: memoryStyle.showsDot ? snapshot.memoryPressure : nil),
                             spoken: spoken)
                } else {
                    // A symbol alone says nothing: the icon style always
                    // shows the percentage, whatever an old "dot only" said.
                    let showsPercent = memoryStyle.showsPercent || style == .iconValue
                    text(.memory, label: "RAM",
                         value: showsPercent ? percentText : "",
                         minimum: showsPercent ? "100%" : "",
                         pressure: memoryStyle.showsDot ? snapshot.memoryPressure : nil,
                         fraction: shownFraction,
                         symbol: "memorychip")
                }
            case .network:
                if let down = snapshot.netDownBytesPerSec, let up = snapshot.netUpBytesPerSec {
                    let downText = MetricFormat.networkRateCompact(down, inBits: settings.networkInBits)
                    let upText = MetricFormat.networkRateCompact(up, inBits: settings.networkInBits)
                    if settings.style(for: .network) == .sparkline {
                        list.add(networkDualGraphBlock(downHistory: snapshot.netDownHistory,
                                                       upHistory: snapshot.netUpHistory,
                                                       settings: settings),
                                 spoken: "\(metric.title(strings)) ↓\(downText) ↑\(upText)")
                    } else {
                        let lines = settings.networkUploadFirst ? ["↑\(upText)", "↓\(downText)"]
                                                                : ["↓\(downText)", "↑\(upText)"]
                        dual(.network, label: "NET", lines: lines, reserved: ["↓000B", "↑000B"], kind: "net")
                    }
                }
            case .diskUsage:
                if let disk = primaryDisk(from: snapshot.disk) {
                    let spoken = "\(metric.title(strings)) \(percent(disk.usedFraction))"
                    switch settings.style(for: .diskUsage) {
                    case .bars:
                        list.add(.usageBarBlock(label: "DSK", fraction: disk.usedFraction, pressure: nil),
                                 spoken: spoken)
                    case .pie:
                        list.add(ringBlock(label: "DSK", values: [disk.usedFraction],
                                           valueText: showsGraphValue ? percent(disk.usedFraction) : nil,
                                           settings: settings), spoken: spoken)
                    default:
                        text(.diskUsage, label: "DSK", value: percent(disk.usedFraction), minimum: "100%",
                             fraction: disk.usedFraction, symbol: "internaldrive")
                    }
                }
            case .diskActivity:
                if let activity = diskActivity(from: snapshot.disk) {
                    dual(.diskActivity, label: "DSK",
                         lines: ["R\(MetricFormat.bytesPerSecCompact(activity.read))",
                                 "W\(MetricFormat.bytesPerSecCompact(activity.write))"],
                         reserved: ["R000B", "W000B"], kind: "disk")
                }
            case .battery, .batteryTemperature:
                let batteryStyle = settings.style(for: .battery)
                if settings.combinesTemperature(of: .battery, enabled: enabled) {
                    guard !renderedBattery else { break }
                    renderedBattery = true
                    let chargePercent = enabled.contains(.battery) ? snapshot.power?.chargePercent : nil
                    let charge = chargePercent.map { "\(max(0, min(100, $0)))%" }
                    let temperature = enabled.contains(.batteryTemperature)
                        ? snapshot.batteryTemperature.map { temperatureCompact($0, settings) }
                        : nil
                    if let chargePercent, temperature == nil, batteryStyle == .iconValue {
                        list.add(.batteryBlock(percent: chargePercent,
                                               isCharging: snapshot.power?.isCharging ?? false),
                                 spoken: "\(strings.batteryLabel) \(charge ?? "")")
                    } else if charge != nil || temperature != nil {
                        // A battery symbol has no room for a temperature, so
                        // the pair reads as a label above both values.
                        let label = combinedComponentLabel("BAT", hasPrimary: charge != nil,
                                                           hasTemperature: temperature != nil, settings)
                        let value = combinedComponentValue(primary: charge, temperature: temperature) ?? ""
                        let minimum = minimumCombinedValue(primary: charge != nil, temperature: temperature != nil)
                        let key = "battery" + (charge != nil ? "+usage" : "") + (temperature != nil ? "+temp" : "")
                        if batteryStyle == .iconValue {
                            list.add(.metricBlock(label: label, value: value, minimumValue: minimum, widthKey: key,
                                                  pressure: nil, valueColorHex: nil),
                                     spoken: "\(strings.batteryLabel) \(value)")
                        } else {
                            text(.battery, label: label, value: value, minimum: minimum, widthKey: key)
                        }
                    }
                    break
                }
                guard metric == .battery else {
                    if let temperature = snapshot.batteryTemperature {
                        text(.batteryTemperature, label: temperatureLabel("BAT", settings),
                             value: temperatureCompact(temperature, settings), minimum: "999°")
                    }
                    break
                }
                if let charge = snapshot.power?.chargePercent {
                    if batteryStyle == .iconValue {
                        list.add(.batteryBlock(percent: charge, isCharging: snapshot.power?.isCharging ?? false),
                                 spoken: "\(strings.batteryLabel) \(max(0, min(100, charge)))%")
                    } else {
                        text(.battery, label: "BAT", value: "\(max(0, min(100, charge)))%", minimum: "100%")
                    }
                }
            case .batteryTime:
                if let power = snapshot.power,
                   let seconds = power.timeRemainingSeconds,
                   let value = BatteryTimeSupport.formatted(seconds: seconds) {
                    text(.batteryTime, label: "BAT", value: value, minimum: "99h 59m")
                } else if let power = snapshot.power,
                          power.hasBattery, !power.externalConnected, !power.isCharging {
                    text(.batteryTime, label: "BAT", value: "...", minimum: "99h 59m")
                }
            case .peripheralBattery:
                if let metricValue = PeripheralBatterySupport.menuBarMetric(for: snapshot.peripheralBatteries) {
                    text(.peripheralBattery, label: metricValue.label, value: metricValue.value, minimum: "100%+9")
                }
            case .power:
                if let watts = snapshot.power?.systemWatts {
                    text(.power, label: "PWR", value: MetricFormat.wattsCompact(watts), minimum: "999W")
                }
            case .connectedDevices:
                // The list has its own event-driven owner rather than a field
                // in the AMD monitor's snapshot; nothing shows until it has
                // been read once.
                let devices = ConnectedDevicesMonitor.shared
                // With nothing connected the item leaves the menu bar.
                if devices.hasLoadedOnce, devices.count > 0 {
                    text(.connectedDevices,
                         label: FeatureStrings.connectedDevices(L10n.shared.language).menuBarLabel,
                         value: "\(devices.count)", minimum: "99", symbol: "cable.connector")
                }
            }
        }
        return (blockJoined(list.groups, settings: settings), list.spoken)
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

    /// The reserve that keeps a block's width steady: the metric's largest
    /// value with a fixed width, the session's widest value when fitting the
    /// value. Fitting is never wider than fixed: a digit-matched reserve can
    /// be ("↓88888B ↑8B" after "↓12.3M ↑4.5M"), so the narrower one wins.
    private static func reserve(for value: String, minimum: String, widthKey: String, font: NSFont,
                                settings: MenuBarRenderSettings, widthMemory: MenuBarWidthMemory) -> String {
        guard settings.spacing == .compact else { return minimum }
        return narrowerReserve(widthMemory.compactReserve(key: widthKey, value: value), minimum, font: font)
    }

    /// The narrower of a fitted and a fixed reserve in `font`; an empty fixed
    /// reserve (nothing to reserve) never wins.
    static func narrowerReserve(_ fitted: String, _ fixed: String, font: NSFont) -> String {
        guard !fixed.isEmpty else { return fitted }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        return (fitted as NSString).size(withAttributes: attrs).width
            <= (fixed as NSString).size(withAttributes: attrs).width ? fitted : fixed
    }
    /// `narrowerReserve` in the value font of the text blocks.
    static func narrowerReserve(_ fitted: String, _ fixed: String) -> String {
        narrowerReserve(fitted, fixed, font: textFont(size: valueFontSize, weight: .semibold, narrow: false))
    }

    private static func valueAttributes(font: NSFont, colorHex level: String?) -> [NSAttributedString.Key: Any] {
        let color: NSColor
        switch level {
        case "critical": color = .systemRed
        case "elevated": color = .systemOrange
        default: color = .labelColor
        }
        return [.font: font, .foregroundColor: color]
    }

    /// Where to draw a line of `font` so its digits sit centered in `height`.
    private static func centeredOrigin(for font: NSFont, in height: CGFloat) -> CGFloat {
        let digitHeight = font.capHeight
        let baseline = (height - digitHeight) / 2
        return baseline + font.descender
    }

    private static func metricBlockImage(label: String,
                                         value: String,
                                         minimumValue reservedValue: String,
                                         widthKey: String,
                                         pressure: MemoryPressure?,
                                         valueColorHex: String?,
                                         settings: MenuBarRenderSettings,
                                         widthMemory: MenuBarWidthMemory) -> BlockImage {
        let minimumValue = reserve(for: value, minimum: reservedValue, widthKey: widthKey,
                                   font: textFont(size: valueFontSize, weight: .semibold, narrow: settings.narrowText),
                                   settings: settings, widthMemory: widthMemory)
        let pressureKey = pressure.map(String.init(describing:)) ?? "none"
        let key = "metric|\(label)|\(value)|\(minimumValue)|\(pressureKey)|\(valueColorHex ?? "-")|"
            + "\(settings.narrowText)|\(settings.appearanceName)"
        let cacheKey = key as NSString
        if let cached = blockImageCache.object(forKey: cacheKey) { return BlockImage(image: cached, key: key) }

        let labelFont = textFont(size: aboveLabelFontSize, weight: .medium, narrow: settings.narrowText)
        let valueFont = textFont(size: valueFontSize, weight: .semibold, narrow: settings.narrowText)
        let labelSize = (label as NSString).size(withAttributes: [.font: labelFont])
        let valueSize = (value as NSString).size(withAttributes: [.font: valueFont])
        let minimumValueSize = (minimumValue as NSString).size(withAttributes: [.font: valueFont])
        let dotDiameter: CGFloat = pressure == nil ? 0 : 4.8
        let dotGap: CGFloat = pressure == nil || value.isEmpty ? 0 : 4
        let reservedValueWidth = max(valueSize.width, minimumValueSize.width)
        let reservedGroupWidth = dotDiameter + dotGap + reservedValueWidth
        let drawnGroupWidth = dotDiameter + dotGap + valueSize.width
        let width = ceil(max(labelSize.width, reservedGroupWidth) + 0.5)
        let height: CGFloat = 21
        // Digits have no descenders: the value's baseline sits low, the
        // label's caps sit above the value's caps with a clear gap.
        let valueBaseline: CGFloat = 1.4
        let labelBaseline: CGFloat = valueBaseline + valueFont.capHeight + 2.6
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()
            (label as NSString).draw(at: NSPoint(x: (width - labelSize.width) / 2,
                                                 y: labelBaseline + labelFont.descender),
                                     withAttributes: dynamicTextAttributes(font: labelFont))
            var valueX = (width - drawnGroupWidth) / 2
            if let pressure {
                let dotRect = NSRect(x: valueX, y: valueBaseline + (valueFont.capHeight - dotDiameter) / 2,
                                     width: dotDiameter, height: dotDiameter)
                nsColor(for: pressure).setFill()
                NSBezierPath(ovalIn: dotRect).fill()
                valueX += dotDiameter + dotGap
            }
            (value as NSString).draw(at: NSPoint(x: valueX, y: valueBaseline + valueFont.descender),
                                     withAttributes: valueAttributes(font: valueFont, colorHex: valueColorHex))
            return true
        }
        image.isTemplate = false
        blockImageCache.setObject(image, forKey: cacheKey, cost: blockImageCost(image))
        return BlockImage(image: image, key: key)
    }

    /// Label and value on one line, the value right-aligned in its reserve so
    /// digits stay put as they change.
    private static func inlineBlockImage(label: String?,
                                         value: String,
                                         minimumValue reservedValue: String,
                                         widthKey: String,
                                         pressure: MemoryPressure?,
                                         valueColorHex: String?,
                                         settings: MenuBarRenderSettings,
                                         widthMemory: MenuBarWidthMemory) -> BlockImage {
        let minimumValue = reserve(for: value, minimum: reservedValue,
                                   widthKey: widthKey + (label == nil ? "|value" : "|inline"),
                                   font: textFont(size: valueFontSize, weight: .semibold, narrow: settings.narrowText),
                                   settings: settings, widthMemory: widthMemory)
        let pressureKey = pressure.map(String.init(describing:)) ?? "none"
        let key = "inline|\(label ?? "")|\(value)|\(minimumValue)|\(pressureKey)|\(valueColorHex ?? "-")|"
            + "\(settings.narrowText)|\(settings.appearanceName)"
        let cacheKey = key as NSString
        if let cached = blockImageCache.object(forKey: cacheKey) { return BlockImage(image: cached, key: key) }

        let labelFont = textFont(size: inlineLabelFontSize, weight: .medium, narrow: settings.narrowText)
        let valueFont = textFont(size: valueFontSize, weight: .semibold, narrow: settings.narrowText)
        let labelWidth = label.map { ceil(($0 as NSString).size(withAttributes: [.font: labelFont]).width) } ?? 0
        let labelGap: CGFloat = label == nil ? 0 : 3
        let valueWidth = (value as NSString).size(withAttributes: [.font: valueFont]).width
        let reservedWidth = max(valueWidth, (minimumValue as NSString).size(withAttributes: [.font: valueFont]).width)
        let dotDiameter: CGFloat = pressure == nil ? 0 : 5
        let dotGap: CGFloat = pressure == nil || value.isEmpty ? 0 : 3
        let width = ceil(labelWidth + labelGap + dotDiameter + dotGap + reservedWidth + 0.5)
        let height = blockHeight
        let baseline = (height - valueFont.capHeight) / 2
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()
            if let label {
                (label as NSString).draw(at: NSPoint(x: 0, y: baseline + labelFont.descender),
                                         withAttributes: dynamicTextAttributes(font: labelFont))
            }
            var x = labelWidth + labelGap
            if let pressure {
                nsColor(for: pressure).setFill()
                NSBezierPath(ovalIn: NSRect(x: x, y: baseline + (valueFont.capHeight - dotDiameter) / 2,
                                            width: dotDiameter, height: dotDiameter)).fill()
                x += dotDiameter + dotGap
            }
            (value as NSString).draw(at: NSPoint(x: x + reservedWidth - valueWidth, y: baseline + valueFont.descender),
                                     withAttributes: valueAttributes(font: valueFont, colorHex: valueColorHex))
            return true
        }
        image.isTemplate = false
        blockImageCache.setObject(image, forKey: cacheKey, cost: blockImageCost(image))
        return BlockImage(image: image, key: key)
    }

    /// A symbol and a value, for readings with a symbol of their own.
    private static func iconBlockImage(symbol symbolName: String,
                                       value: String,
                                       minimumValue reservedValue: String,
                                       widthKey: String,
                                       valueColorHex: String?,
                                       settings: MenuBarRenderSettings,
                                       widthMemory: MenuBarWidthMemory) -> BlockImage {
        let minimumValue = reserve(for: value, minimum: reservedValue, widthKey: widthKey + "|icon",
                                   font: textFont(size: valueFontSize, weight: .semibold, narrow: settings.narrowText),
                                   settings: settings, widthMemory: widthMemory)
        let key = "icon|\(symbolName)|\(value)|\(minimumValue)|\(valueColorHex ?? "-")|"
            + "\(settings.narrowText)|\(settings.appearanceName)"
        let cacheKey = key as NSString
        if let cached = blockImageCache.object(forKey: cacheKey) { return BlockImage(image: cached, key: key) }

        let valueFont = textFont(size: valueFontSize, weight: .semibold, narrow: settings.narrowText)
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
        let symbolBox: CGFloat = 16
        let gap: CGFloat = 3
        let valueWidth = (value as NSString).size(withAttributes: [.font: valueFont]).width
        let reservedWidth = max(valueWidth, (minimumValue as NSString).size(withAttributes: [.font: valueFont]).width)
        let width = ceil(symbolBox + gap + reservedWidth + 0.5)
        let height = blockHeight
        let baseline = (height - valueFont.capHeight) / 2
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()
            if let symbol {
                let size = symbol.size
                let scale = min(1, symbolBox / max(size.width, 1))
                let drawSize = NSSize(width: size.width * scale, height: size.height * scale)
                symbol.draw(in: NSRect(x: (symbolBox - drawSize.width) / 2, y: (height - drawSize.height) / 2,
                                       width: drawSize.width, height: drawSize.height))
            }
            (value as NSString).draw(at: NSPoint(x: symbolBox + gap + reservedWidth - valueWidth,
                                                 y: baseline + valueFont.descender),
                                     withAttributes: valueAttributes(font: valueFont, colorHex: valueColorHex))
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
        let fillColorHex = settings.graphMonochrome
            ? "mono"
            : fraction.map { settings.usageBarColorHex(for: $0) } ?? "missing"
        let pressureKey = pressure.map(String.init(describing:)) ?? "none"
        let levelKey = fillLevel.map(String.init) ?? "missing"
        let key = "usageBar|\(label)|\(levelKey)|\(fillColorHex)|\(pressureKey)|\(settings.appearanceName)"
        let cacheKey = key as NSString
        if let cached = blockImageCache.object(forKey: cacheKey) { return BlockImage(image: cached, key: key) }

        let size = CGSize(width: stackedLabelWidth + 2 + 9 + (pressure != nil ? 6.6 : 0), height: blockHeight)
        let labelWidth: CGFloat = stackedLabelWidth
        let labelGap: CGFloat = 2
        let dotDiameter: CGFloat = pressure == nil ? 0 : 4.4
        let dotGap: CGFloat = pressure == nil ? 0 : 2.2
        let barWidth: CGFloat = 9
        let barHeight: CGFloat = 18
        let barX = labelWidth + labelGap + dotDiameter + dotGap
        let barY = (size.height - barHeight) / 2
        let monochrome = settings.graphMonochrome

        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()
            drawStackedLabel(label, width: labelWidth, height: size.height)

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
                (monochrome ? NSColor.labelColor : usageBarColor(hex: fillColorHex)).setFill()
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

    /// Two values in two lines, right-aligned, with an optional stacked name.
    private static func dualBlockImage(label: String?,
                                       lines: [String],
                                       reservedLines: [String],
                                       kind: String,
                                       settings: MenuBarRenderSettings) -> BlockImage {
        let key = "dual|\(kind)|\(label ?? "")|\(lines.joined(separator: "/"))|\(settings.narrowText)|"
            + settings.appearanceName
        let cacheKey = key as NSString
        if let cached = blockImageCache.object(forKey: cacheKey) { return BlockImage(image: cached, key: key) }

        let font = rateLineFont(narrow: settings.narrowText)
        let attrs = dynamicTextAttributes(font: font)
        let candidates = reservedLines + lines
        let rateWidth = ceil((candidates.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 22) + 1)
        let height = blockHeight
        let labelWidth: CGFloat = label == nil ? 0 : stackedLabelWidth
        let labelGap: CGFloat = label == nil ? 0 : 3
        let totalWidth = labelWidth + labelGap + rateWidth
        let imageSize = NSSize(width: totalWidth, height: height)
        // Cap heights centered in each half of the block.
        let topBaseline = height / 2 + (height / 2 - font.capHeight) / 2 - 0.3
        let bottomBaseline = (height / 2 - font.capHeight) / 2 + 0.3
        let image = NSImage(size: imageSize, flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()
            if let label {
                drawStackedLabel(label, width: labelWidth, height: height)
            }
            let startX = labelWidth + labelGap
            for (index, line) in lines.prefix(2).enumerated() {
                let baseline = index == 0 ? topBaseline : bottomBaseline
                let lineWidth = (line as NSString).size(withAttributes: attrs).width
                (line as NSString).draw(at: NSPoint(x: startX + max(0.5, rateWidth - lineWidth - 0.5),
                                                    y: baseline + font.descender),
                                        withAttributes: attrs)
            }
            return true
        }
        image.isTemplate = false
        blockImageCache.setObject(image, forKey: cacheKey, cost: blockImageCost(image))
        return BlockImage(image: image, key: key)
    }

    private static func batteryBlockImage(percent: Int,
                                          isCharging: Bool,
                                          settings: MenuBarRenderSettings) -> BlockImage {
        let clampedPercent = max(0, min(100, percent))
        let key = "battery|\(clampedPercent)|\(isCharging)|\(settings.narrowText)|\(settings.appearanceName)"
        let cacheKey = key as NSString
        if let cached = blockImageCache.object(forKey: cacheKey) { return BlockImage(image: cached, key: key) }

        let symbolName = batterySymbol(for: percent, isCharging: isCharging)
        let symbolPointSize: CGFloat = 15.5
        let valueFont = textFont(size: valueFontSize, weight: .semibold, narrow: settings.narrowText)
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
            let baseline = (height - valueFont.capHeight) / 2
            (value as NSString).draw(at: NSPoint(x: symbolWidth + gap, y: baseline + valueFont.descender),
                                     withAttributes: dynamicTextAttributes(font: valueFont))
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

    /// A three letter name stacked one letter per row, each capital centered
    /// in its third of the block.
    private static func drawStackedLabel(_ label: String, width: CGFloat, height: CGFloat) {
        let font = stackedLabelFont
        let attrs = dynamicTextAttributes(font: font)
        let rowHeight = height / 3
        for (index, character) in label.prefix(3).map(String.init).enumerated() {
            let characterWidth = (character as NSString).size(withAttributes: attrs).width
            let rowMid = height - rowHeight * (CGFloat(index) + 0.5)
            let baseline = rowMid - font.capHeight / 2
            (character as NSString).draw(at: NSPoint(x: (width - characterWidth) / 2, y: baseline + font.descender),
                                         withAttributes: attrs)
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
                                     settings: MenuBarRenderSettings,
                                     draw: @escaping (MenuBarGraphPainter.Style) -> Void) -> MenuBarSegment {
        let cacheKey = key as NSString
        if let cached = graphImageCache.object(forKey: cacheKey) { return .customImage(cached, key: key) }
        let monochrome = settings.graphMonochrome
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()
            draw(MenuBarGraphPainter.currentStyle(monochrome: monochrome))
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
                   settings.graphToken, "\(settings.graphMonochrome)", settings.appearanceName].joined(separator: "|")
        return graphSegment(key: key, size: layout.imageSize, settings: settings) { graphStyle in
            drawStackedLabel("NET", width: layout.labelWidth, height: layout.height)
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
        let font = fontScale < 1 ? ringOverlayFont : overlayFont
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
                   settings.graphToken, "\(settings.graphMonochrome)", settings.appearanceName].joined(separator: "|")
        return graphSegment(key: key, size: layout.imageSize, settings: settings) { graphStyle in
            drawStackedLabel("CPU", width: layout.labelWidth, height: layout.height)
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
                   settings.graphToken, "\(settings.graphMonochrome)", settings.appearanceName].joined(separator: "|")
        return graphSegment(key: key, size: layout.imageSize, settings: settings) { graphStyle in
            drawStackedLabel(label, width: layout.labelWidth, height: layout.height)
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
                   settings.graphToken, "\(settings.graphMonochrome)", settings.appearanceName].joined(separator: "|")
        return graphSegment(key: key, size: layout.imageSize, settings: settings) { graphStyle in
            drawStackedLabel(label, width: layout.labelWidth, height: layout.height)
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
