// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import IOKit

/// The dashboards and metrics services: which samples count, which pages
/// keep sampling, how process rows and adapter rates are read, which
/// hardware writes a bulk action sends, and the strings they show. Pure
/// functions are tested directly; a source check stands in only where the
/// rule lives in wiring with no pure seam.
enum DashboardMetricsTests {
    static func run(_ suite: TestSuite) {
        coreLoadBaselines(suite)
        coreTopology(suite)
        temperatureBridge(suite)
        alertNeeds(suite)
        kextPollRules(suite)
        adapterRates(suite)
        monitorIntervals(suite)
        pageActivity(suite)
        processTable(suite)
        monitorWindow(suite)
        curveOptimizerPlan(suite)
        longHistoryFallback(suite)
        fanCurveGeometry(suite)
        energyAndSummaries(suite)
        writeStatus(suite)
        stringParity(suite)
        wiring(suite)
    }

    // MARK: - SystemMonitor

    private static func tick(_ user: UInt64, _ system: UInt64, _ idle: UInt64) -> CPUTickSample {
        CPUTickSample(user: user, system: system, idle: idle, nice: 0)
    }

    private static func coreLoadBaselines(_ suite: TestSuite) {
        let now = [tick(100, 0, 100), tick(100, 0, 100)]
        let before = [tick(0, 0, 0), tick(0, 0, 0)]
        suite.expect(SystemMonitor.coreLoads(current: now, previous: [], elapsed: 1) == nil,
                     "no per-core baseline publishes no cores")
        suite.expect(SystemMonitor.coreLoads(current: now, previous: [tick(0, 0, 0)], elapsed: 1) == nil,
                     "a changed CPU count is a new baseline")
        suite.expect(SystemMonitor.coreLoads(current: now, previous: before, elapsed: 13) == nil,
                     "a gap over 12.5 s is a new baseline, not a gap-long average")
        suite.expect(SystemMonitor.coreLoads(current: now, previous: before, elapsed: nil) == nil,
                     "an unknown baseline time is no baseline")
        let loads = SystemMonitor.coreLoads(current: now, previous: before, elapsed: SystemMonitor.maximumTickGap)
        suite.expect(loads?.count == 2, "a usable baseline gives one load per core")
        suite.expectClose(loads?.first??.busy ?? -1, 0.5, "half the ticks busy is 50 %")
        let wrapped = SystemMonitor.coreLoads(current: [tick(5, 0, 5)], previous: [tick(10, 0, 10)], elapsed: 1)
        suite.expect(wrapped?.count == 1 && wrapped?.first.map { $0 == nil } == true,
                     "a core whose counters went backwards gets no load")
    }

    private static func coreTopology(_ suite: TestSuite) {
        let smt = SystemMonitor.coreTopology(logicalCount: 12, physicalCount: 6)
        suite.expect(smt.map(\.physicalIndex) == [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5],
                     "with SMT the two threads of a core sit next to each other")
        suite.expect(smt.map(\.isLogical) == (0..<12).map { $0 % 2 == 1 },
                     "every second thread is the logical sibling")
        let noSMT = SystemMonitor.coreTopology(logicalCount: 8, physicalCount: 8)
        suite.expect(noSMT.map(\.physicalIndex) == Array(0..<8) && noSMT.allSatisfy { !$0.isLogical },
                     "without SMT every logical CPU is a core")
        suite.expect(SystemMonitor.coreTopology(logicalCount: 0, physicalCount: 8).isEmpty,
                     "no CPUs reported is no topology")
        suite.expect(SystemMonitor.hostPhysicalCoreCount >= 1, "the kernel's core count is at least one")
    }

    private static func temperatureBridge(_ suite: TestSuite) {
        suite.expectClose(SystemMonitor.temperatureBridge(stride: 1, intervalSeconds: 1), 12,
                          "the bridge never drops under 12 s")
        suite.expectClose(SystemMonitor.temperatureBridge(stride: 5, intervalSeconds: 1), 12,
                          "a 5 s stride still bridges 12 s")
        suite.expectClose(SystemMonitor.temperatureBridge(stride: 3, intervalSeconds: 5), 33,
                          "a slow background stride bridges a couple of gaps")
    }

    private static func alertNeeds(_ suite: TestSuite) {
        func needs(_ keys: Set<String>, available: Set<AppFeature> = [.monitorCPU, .monitorMemory, .monitorDisk,
                                                                        .monitorPower, .monitorGPU],
                   battery: Bool = true) -> SystemMonitorPanelNeeds {
            SystemMonitorPanelNeeds.alerts(boolFor: { keys.contains($0) },
                                           isAvailable: { available.contains($0) },
                                           hasInternalBattery: battery)
        }
        suite.expect(needs([]) == SystemMonitorPanelNeeds.none, "no alert samples nothing")
        suite.expect(needs([DefaultsKey.monitorAlertBattery], battery: false) == SystemMonitorPanelNeeds.none,
                     "a battery alert on a desktop samples nothing")
        let battery = needs([DefaultsKey.monitorAlertBattery])
        suite.expect(battery.battery && battery.cpu && battery.cpuTemperature
                     && !battery.gpu && !battery.network && !battery.disk && !battery.system,
                     "a battery alert samples the battery plus what the thermal check reads")
        let gpuPower = needs([DefaultsKey.monitorAlertGPUPower])
        suite.expect(gpuPower.gpu && !gpuPower.gpuTemperature && !gpuPower.memory,
                     "the GPU power alert rides the GPU read that brings the kext power")
        let memory = needs([DefaultsKey.monitorAlertMemory])
        suite.expect(memory.memory && !memory.disk && !memory.network, "a memory alert samples memory")
        suite.expect(needs([DefaultsKey.monitorAlertDisk], available: []) == SystemMonitorPanelNeeds.none,
                     "an alert whose metric the hub switched off samples nothing")
        suite.expect(!needs([DefaultsKey.monitorAlertCPU]).peripheralBattery,
                     "no alert wakes the peripheral battery sampler")
    }

    private static func kextPollRules(_ suite: TestSuite) {
        suite.expect(AmdPowerControlsModel.historySampleDue(last: nil, now: 5), "the first sample is always due")
        suite.expect(!AmdPowerControlsModel.historySampleDue(last: 10, now: 12),
                     "a second surface's sync 2 s later adds no history sample")
        suite.expect(AmdPowerControlsModel.historySampleDue(last: 10, now: 12.5),
                     "2.5 s after the last sample the next one is due")
        suite.expect(AmdPowerControlsModel.pmDecodeIsLive(snapshotValid: true, snapshotAgeMs: 1_000),
                     "a valid, fresh PM snapshot is live")
        suite.expect(!AmdPowerControlsModel.pmDecodeIsLive(snapshotValid: true, snapshotAgeMs: 60_000),
                     "an old PM snapshot is not shown as live")
        suite.expect(!AmdPowerControlsModel.pmDecodeIsLive(snapshotValid: false, snapshotAgeMs: 0),
                     "an invalid PM snapshot is not shown as live")
    }

    private static func adapterRates(_ suite: TestSuite) {
        suite.expectClose(NetworkScannerService.rate(previous: 1_000, current: 3_000, elapsed: 2), 1_000,
                          "bytes over seconds")
        suite.expectClose(NetworkScannerService.rate(previous: 5, current: 1, elapsed: 1), 0,
                          "a counter that went backwards is no burst")
        suite.expectClose(NetworkScannerService.rate(previous: 0, current: 10, elapsed: 0), 0,
                          "no elapsed time is no rate")
        let big = UInt64(1) << 33
        suite.expectClose(NetworkScannerService.rate(previous: big, current: big + 4_096, elapsed: 1), 4_096,
                          "64-bit counters past 4 GiB still give the delta")
    }

    private static func monitorIntervals(_ suite: TestSuite) {
        suite.expect(Defaults.allowedMonitorIntervals == [1.0, 2.0, 5.0],
                     "only intervals that sample as often as they say are offered")
        suite.expectClose(Defaults.sanitizedMonitorInterval(0.5), 1, "a stored 0.5 s becomes 1 s")
        suite.expectClose(Defaults.sanitizedMonitorInterval(0.7), 1, "a stored 0.7 s becomes 1 s")
    }

    private static func pageActivity(_ suite: TestSuite) {
        suite.expect(SettingsPageActivity.isActive(appeared: true, windowVisible: true),
                     "a page on screen in a visible window is live")
        suite.expect(!SettingsPageActivity.isActive(appeared: true, windowVisible: false),
                     "a closed or hidden Settings window stops the page")
        suite.expect(!SettingsPageActivity.isActive(appeared: false, windowVisible: true),
                     "a page that left stops")
        suite.expect(!SettingsPageActivity.isActive(appeared: false, windowVisible: false), "both off is off")
        suite.expect(SettingsLivePage.allCases.count == Set(SettingsLivePage.allCases.map { "\($0)" }).count,
                     "one row per page")
        suite.expect(!SettingsLivePage.amdValidation.holdsMonitorClient && !SettingsLivePage.amdValidation.holdsLiveSync,
                     "Validation takes its snapshot on request and holds nothing open")
        suite.expect(!SettingsLivePage.amdOverclocking.holdsMonitorClient && SettingsLivePage.amdOverclocking.holdsLiveSync,
                     "Overclocking reads only the kext caches")
    }

    // MARK: - Process rows

    private static func processTable(_ suite: TestSuite) {
        let output = """
          PID  PPID  %CPU    RSS COMM
          437     1  12.5  20480 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
          901   437   3,5   1024 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper
        garbage line
            0     0   0.0      0 kernel_task
           77     1   abc    100 /usr/sbin/bad
        """
        let rows = ProcessTable.parse(output)
        suite.expect(rows.count == 2, "the header, malformed lines and pid 0 are skipped, never read as zeros")
        suite.expect(rows.first?.pid == 437 && rows.first?.ppid == 1, "pid and parent pid")
        suite.expectClose(rows.first?.cpuPercent ?? -1, 12.5, "ps's %cpu as reported")
        suite.expectClose(rows.first?.rssBytes ?? -1, 20_480 * 1_024, "resident memory in bytes")
        suite.expect(rows.last?.shortName == "Google Chrome Helper",
                     "a name with spaces is kept whole")
        suite.expectClose(rows.last?.cpuPercent ?? -1, 3.5, "a comma decimal reads like a point")
        suite.expect(ProcessTable.psArguments == ["-eo", "pid,ppid,pcpu,rss,comm"],
                     "one ps listing, the one the process manager reads")
    }

    // MARK: - Monitor window

    private static func monitorWindow(_ suite: TestSuite) {
        for section in MonitorSection.allCases {
            let needs = section.monitorNeeds
            suite.expect(!needs.system, "\(section) never asks for every sampler")
            suite.expect(needs.cpu && needs.memory && needs.network && needs.gpu,
                         "\(section) keeps the live charts' families, so their history has no false gap")
        }
        suite.expect(MonitorSection.summary.monitorNeeds.disk && !MonitorSection.summary.monitorNeeds.power,
                     "the overview samples disk, which it shows, and not the battery/SMC power it never shows")
        suite.expect(!MonitorSection.processes.monitorNeeds.disk && !MonitorSection.history.monitorNeeds.power,
                     "sections that do not show disk or power do not sample them")
        suite.expect(MonitorSection.diagnostics.monitorNeeds.cpuTemperature,
                     "diagnostics reads the CPU temperature for its heat notice")

        suite.expect(MonitorSection.restored(nil) == .summary, "no saved section opens the Overview")
        suite.expect(MonitorSection.restored("bogus") == .summary, "an unknown saved section opens the Overview")
        suite.expect(MonitorSection.restored("processor", isAvailable: { _ in true }) == .processor,
                     "an available saved section reopens")
        suite.expect(MonitorSection.restored("history", isAvailable: { $0 != .history }) == .summary,
                     "a saved section whose feature is off falls back to the Overview")
        suite.expect(AppFeature.monitorInsights.monitorSection == .diagnostics
                     && AppFeature.monitorAnalytics.monitorSection == .history
                     && AppFeature.monitorEnergy.monitorSection == .processes
                     && AppFeature.monitorNetworkDetails.monitorSection == .network
                     && AppFeature.monitorCPU.monitorSection == nil,
                     "each monitor extra opens the Monitor on its own section")

        let listed = [AppUsage(pid: 1, name: "Safari", cpuPercent: 1, memoryBytes: 1),
                      AppUsage(pid: 2, name: "Mail", cpuPercent: 2, memoryBytes: 2)]
        suite.expect(ProcessesFeed.matching(listed, search: "").count == 2, "an empty search lists every app")
        suite.expect(ProcessesFeed.matching(listed, search: " saf ").map(\.pid) == [1],
                     "the search matches part of the name, any case, ignoring outer spaces")
        suite.expect(ProcessesFeed.matching(listed, search: "zzz").isEmpty, "a search with no match lists nothing")
        for language in AppLanguage.allCases {
            suite.expect(String(format: FeatureStrings.dashboard(language).processCountFormat, 37).contains("37"),
                         "\(language.rawValue) process count line shows the count")
        }

        let off = ProcessesSection.energyGate(available: false, hidden: false, hiddenByGate: false)
        suite.expect(off.hide == true && off.hiddenByGate, "with the feature off the energy column is hidden by the gate")
        let userHidden = ProcessesSection.energyGate(available: false, hidden: true, hiddenByGate: false)
        suite.expect(userHidden.hide == nil && !userHidden.hiddenByGate,
                     "a column the user hid stays the user's choice while the feature is off")
        let back = ProcessesSection.energyGate(available: true, hidden: true, hiddenByGate: true)
        suite.expect(back.hide == false && !back.hiddenByGate, "the feature coming back restores what the gate hid")
        let kept = ProcessesSection.energyGate(available: true, hidden: true, hiddenByGate: false)
        suite.expect(kept.hide == nil, "with the feature on, the user's own hide is left alone")

        let cpu = [ProcessUsage(pid: 1, name: "Busy", value: 40), ProcessUsage(pid: 2, name: "helper", value: 0)]
        let memory = [ProcessUsage(pid: 2, name: "helper", value: 900), ProcessUsage(pid: 1, name: "Busy", value: 100)]
        let realNames: [pid_t: String] = [1: "Busy App", 2: "Heavy App"]
        let apps = ProcessUsageService.combined(cpu: cpu, memory: memory) { pid, fallback in realNames[pid] ?? fallback }
        suite.expect(apps.map(\.pid) == [1, 2], "every app of the CPU ranking, in its order")
        suite.expectClose(apps.first?.memoryBytes ?? -1, 100, "an app's memory joins its CPU row")
        suite.expect(apps.map(\.name) == ["Busy App", "Heavy App"],
                     "every row carries the app's real name, the one the terminate check compares")

        suite.expect(ProcessKillRequest.make(pid: 9, name: "Safari", startedAt: 42, currentName: "Safari")?.startedAt == 42,
                     "a row that still names its app gets a request carrying the start time read now")
        suite.expect(ProcessKillRequest.make(pid: 9, name: "Safari", startedAt: 42, currentName: "Mail") == nil,
                     "a pid that now names another app gets no request")
        suite.expect(ProcessKillRequest.make(pid: 9, name: "Safari", startedAt: nil, currentName: "Safari") == nil,
                     "a process that quit gets no request")
        suite.expect(ProcessKillRequest.make(pid: 9, name: "Safari", startedAt: 42, currentName: "") == nil,
                     "a live name that cannot be read never passes for the expected app")
        suite.expect(ProcessKillRequest.make(pid: 9, name: "", startedAt: 42, currentName: "") == nil,
                     "a row with no name is never acted on")

        let none = SystemMonitorPanelNeeds()
        suite.expect(!SystemMonitor.samplesInForeground(fullMonitor: false, menuPanel: none, dashboard: none),
                     "nothing on screen samples on the background strides")
        suite.expect(SystemMonitor.samplesInForeground(fullMonitor: false, menuPanel: none,
                                                        dashboard: MonitorSection.processes.monitorNeeds),
                     "a visible Monitor window samples on the foreground strides")
        suite.expect(SystemMonitorPanelNeeds.none.merging(MonitorSection.summary.monitorNeeds) == MonitorSection.summary.monitorNeeds,
                     "the window's needs merge with no others unchanged")

        suite.expectClose(TrendChart.niceCeiling(149.1), 150, "a top grid line reads like a familiar value")
        suite.expectClose(TrendChart.niceCeiling(61), 80, "61 rounds up to 80")
        suite.expectClose(TrendChart.niceCeiling(3.2), 4, "3.2 rounds up to 4")
        suite.expectClose(TrendChart.niceCeiling(0), 1, "an empty series still has a scale")
    }

    // MARK: - Curve Optimizer

    private static func curveOptimizerPlan(_ suite: TestSuite) {
        suite.expect(CurveOptimizerWritePlan.changedCores(draft: [0, -5, 0], readback: nil).isEmpty,
                     "without a valid readback no difference is known, so nothing is written")
        suite.expect(CurveOptimizerWritePlan.changedCores(draft: [0, -5, 0], readback: [0, -5, 0]).isEmpty,
                     "no change writes nothing")
        suite.expect(CurveOptimizerWritePlan.changedCores(draft: [0, -7, 0], readback: [0, -5, 0]) == [1],
                     "only the changed core is written")
        suite.expect(CurveOptimizerWritePlan.coresToReset(readback: [0, -5, 3], coreCount: 3) == [1, 2],
                     "reset writes only cores the kext reports as non-zero")
        suite.expect(CurveOptimizerWritePlan.coresToReset(readback: [0, 0], coreCount: 2).isEmpty,
                     "everything at zero leaves nothing to reset")
        suite.expect(CurveOptimizerWritePlan.coresToReset(readback: nil, coreCount: 4) == [0, 1, 2, 3],
                     "with an unknown readback the reset the user asked for covers every core")
    }

    // MARK: - Long history

    private static func longHistoryFallback(_ suite: TestSuite) {
        let filled = LongHistoryStore.filledFromCoarse(fine: [.nan, 2, .nan], coarse: [1, 9, .nan])
        suite.expect(filled[0] == 1 && filled[1] == 2 && filled[2].isNaN,
                     "a bucket the fine ring lacks takes the minute ring's value; a real gap stays a gap")

        var coarse = LongHistoryTier(step: LongHistoryStore.coarseStep, capacity: LongHistoryStore.coarseCapacity)
        for minute in 0...60 { coarse.record(0.25, at: TimeInterval(minute * 60)) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("long-history-test-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try LongHistoryStore.encode([coarse]).write(to: url)
        } catch {
            suite.expect(false, "the long-history fixture could be written")
            return
        }
        let store = LongHistoryStore(fileURL: url, now: 3_600)
        suite.expect(store.averages(.cpu, range: .oneHour, end: 3_600).contains { $0.isFinite },
                     "after a relaunch the hour graph shows the saved minutes")
        store.record(.cpu, 0.5, at: 3_601)
        let tenMinutes = store.averages(.cpu, range: .tenMinutes, end: 3_602)
        suite.expect(tenMinutes.dropLast().contains { $0.isFinite },
                     "the minutes before launch stay on the ten-minute graph once new samples arrive")
    }

    // MARK: - Fan curve editor

    private static func fanCurveGeometry(_ suite: TestSuite) {
        let points = [FanCurvePoint(temp: 40, pwm: 30), FanCurvePoint(temp: 60, pwm: 50), FanCurvePoint(temp: 80, pwm: 90)]
        let low = FanCurveGeometry.clampedPoint(index: 1, temp: 10, pwm: 5, sorted: points, floor: 16)
        suite.expectClose(low.temp, 41, "a dragged point stays 1 °C above its left neighbour")
        suite.expectClose(low.pwm, 30, "and never below its left neighbour's duty")
        let high = FanCurveGeometry.clampedPoint(index: 1, temp: 95, pwm: 99, sorted: points, floor: 16)
        suite.expectClose(high.temp, 79, "a dragged point stays 1 °C below its right neighbour")
        suite.expectClose(high.pwm, 90, "and never above its right neighbour's duty")
        let edge = FanCurveGeometry.clampedPoint(index: 0, temp: -5, pwm: 2, sorted: points, floor: 16)
        suite.expect(edge.temp == 0 && edge.pwm == 16, "the first point stops at 0 °C and the floor")
        let tight = [FanCurvePoint(temp: 40, pwm: 60), FanCurvePoint(temp: 41, pwm: 50), FanCurvePoint(temp: 42, pwm: 40)]
        let pinned = FanCurveGeometry.clampedPoint(index: 1, temp: 50, pwm: 55, sorted: tight, floor: 16)
        suite.expect(pinned.temp == 41 && pinned.pwm == 60,
                     "crossed bounds (an older falling curve) pin the point to the lower bound")
        suite.expect(FanCurveGeometry.insertedPoint(temp: 40.5, pwm: 50, sorted: points, floor: 16) == nil,
                     "no new point closer than 1 °C to another")
        suite.expect(FanCurveGeometry.insertedPoint(temp: 41, pwm: 50, sorted: points, floor: 16) != nil,
                     "exactly 1 °C apart is allowed")
        let inserted = FanCurveGeometry.insertedPoint(temp: 70, pwm: 20, sorted: points, floor: 16)
        suite.expectClose(inserted?.pwm ?? -1, 50, "a new point's duty sits between its neighbours'")
    }

    // MARK: - Energy, summaries, formatting

    private static func energyAndSummaries(_ suite: TestSuite) {
        suite.expectClose(EnergyImpactService.score(cpuPct: 10, gpuPct: 2), 13,
                          "the estimate is CPU plus 1.5 × GPU, with no flat bonus for apps")
        suite.expectClose(EnergyImpactService.score(cpuPct: 0, gpuPct: 0), 0, "an idle process scores nothing")
        let summary = MetricSeriesSummary.summary([1, 3, .nan, 2])
        suite.expect(summary != nil, "a series with finite samples has a summary")
        suite.expectClose(summary?.average ?? -1, 2, "the average ignores non-finite samples")
        suite.expectClose(summary?.peak ?? -1, 3, "peak")
        suite.expectClose(summary?.last ?? -1, 2, "latest finite sample")
        suite.expect(MetricSeriesSummary.summary([]) == nil, "an empty series has no average, not 0")
        suite.expect(MetricSeriesSummary.summary([.nan]) == nil, "only gaps is no summary")

        let previous = MetricFormat.locale
        MetricFormat.locale = Locale(identifier: "en_US_POSIX")
        defer { MetricFormat.locale = previous }
        suite.expect(MetricFormat.temperaturePrecise(45.44, unit: .celsius) == "45.4 °C",
                     "the precise option shows one decimal and the unit")
        suite.expect(MetricFormat.temperaturePrecise(0, unit: .fahrenheit) == "32.0 °F",
                     "the precise option follows the temperature unit")
    }

    private static func writeStatus(_ suite: TestSuite) {
        let s = DashboardFeatureStrings.enUS
        suite.expect(AmdWriteStatus.text(kIOReturnNotReady, strings: s) == s.statusNotReady
                     && s.statusNotReady.contains("not ready"),
                     "NotReady says the driver may not be ready, not only above 75 °C")
        suite.expect(AmdWriteStatus.text(kIOReturnNotPermitted, strings: s) == s.statusSmuRejected,
                     "a refused write has its own line")
        suite.expect(AmdWriteStatus.text(kIOReturnNotPermitted, strings: s, notPermitted: s.statusEnableOcFirst)
                     == s.statusEnableOcFirst, "a control can name what a refusal means there")
        suite.expect(AmdWriteStatus.text(kIOReturnBadArgument, strings: s, badArgument: s.statusInvalidCore)
                     == s.statusInvalidCore, "a bad argument names the control's input")
        suite.expect(AmdWriteStatus.text(ProcessorModel.kIOReturnNotPrivilegedCode, strings: s) == s.statusRequiresRoot,
                     "a privilege refusal asks for root or the boot flag")
        suite.expect(AmdWriteStatus.text(kern_return_t(bitPattern: 0xE000_0FFF), strings: s) == "Failed (0xE0000FFF)",
                     "an unknown code is shown, never swallowed")
    }

    // MARK: - Strings

    private static func specifiers(in format: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "%(?:%|[0-9.]*(?:l|ll)?[@dDuUxXfFeEgGcCsSp])") else { return [] }
        let range = NSRange(format.startIndex..., in: format)
        return regex.matches(in: format, range: range).compactMap { match -> String? in
            guard let r = Range(match.range, in: format) else { return nil }
            let token = String(format[r])
            return token == "%%" ? nil : String(token.last!)
        }
    }

    private static func stringParity(_ suite: TestSuite) {
        let english = Mirror(reflecting: DashboardFeatureStrings.enUS).children
            .compactMap { child in child.label.map { ($0, child.value as? String ?? "") } }
        suite.expect(!english.isEmpty, "the dashboard strings have fields")
        for language in AppLanguage.allCases {
            let fields = Mirror(reflecting: DashboardFeatureStrings.current(language)).children
                .compactMap { child in child.label.map { ($0, child.value as? String ?? "") } }
            for (index, (name, value)) in fields.enumerated() {
                suite.expect(!value.trimmingCharacters(in: .whitespaces).isEmpty,
                             "\(language.rawValue).\(name) is filled")
                if index < english.count {
                    suite.expect(specifiers(in: value) == specifiers(in: english[index].1),
                                 "\(language.rawValue).\(name) keeps the English format specifiers")
                }
            }
        }
        for language in AppLanguage.allCases {
            let suiteStrings = FeatureStrings.performanceSuite(language)
            suite.expect(!suiteStrings.energyScoreColumn.isEmpty, "\(language.rawValue) names the energy score")
            let monitor = MonitorWindowStrings.localized(language)
            let english = Mirror(reflecting: MonitorWindowStrings.localized(.enUS)).children.map { ($0.label ?? "", $0.value as? String ?? "") }
            let fields = Mirror(reflecting: monitor).children.map { ($0.label ?? "", $0.value as? String ?? "") }
            suite.expect(fields.map(\.0) == english.map(\.0), "\(language.rawValue) Monitor strings have every field")
            for (index, field) in fields.enumerated() where index < english.count {
                suite.expect(!field.1.isEmpty, "\(language.rawValue).\(field.0) is filled in")
                suite.expect(specifiers(in: field.1) == specifiers(in: english[index].1),
                             "\(language.rawValue).\(field.0) keeps the English format specifiers")
            }
            suite.expect(MonitorSection.allCases.allSatisfy { !$0.title(monitor).isEmpty } && !monitor.viewMenu.isEmpty,
                         "\(language.rawValue) names every Monitor section and the View menu")
            suite.expect(specifiers(in: monitor.activeCoresFormat) == ["d", "d"]
                         && specifiers(in: monitor.averagePeakFormat) == ["@", "@"]
                         && specifiers(in: monitor.pptLimitFormat) == ["@"],
                         "\(language.rawValue) Monitor formats keep their specifiers")
        }
        suite.expect(FeatureStrings.performanceSuite(.enUS).energyScoreColumn.contains("Est."),
                     "the energy score is called an estimate")
    }

    // MARK: - Wiring

    private static func source(_ path: String, _ suite: TestSuite) -> String {
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        suite.expect(!text.isEmpty, "\(path) is readable")
        return text
    }

    private static func wiring(_ suite: TestSuite) {
        let processes = source("Sources/RyzenStatus/UI/Dashboard/ProcessesSection.swift", suite)
        suite.expect(!processes.contains("SIGTERM") && processes.contains("KillProcessService.shared.kill(")
                     && processes.contains("startedAt: request.startedAt"),
                     "the process table's kill goes through KillProcessService, to the start time read on request")
        for path in ["Sources/RyzenStatus/UI/Settings/MonitorSettings.swift",
                     "Sources/RyzenStatus/UI/Settings/AmdOverclockingSettingsView.swift",
                     "Sources/RyzenStatus/UI/Settings/SensorsView.swift"] {
            suite.expect(!source(path, suite).contains("@AppStorage(\""), "\(path) keys come from DefaultsKey")
        }
        let kill = source("Sources/RyzenStatus/Services/KillProcess/KillProcessService.swift", suite)
        let usage = source("Sources/RyzenStatus/Services/SystemMonitor/ProcessUsageService.swift", suite)
        suite.expect(kill.contains("ProcessTable.parse(") && usage.contains("ProcessTable.parse("),
                     "both process lists read the one shared ps parser")
    }
}
