// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

enum IStatsWidgetTests {
    static func run(_ suite: TestSuite) {
        visibility(suite)
        families(suite)
        refresh(suite)
        kinds(suite)
    }

    private typealias Switches = IStatsCardKind.Switches
    private typealias Families = IStatsCardKind.Families

    /// The widgets answer to their own switches. The panel used to ask the
    /// classic cards' ones, so with those off every widget vanished.
    private static func visibility(_ suite: TestSuite) {
        suite.expect(IStatsCardKind.anyVisible(Switches()), "with nothing hidden the widgets have a place")
        suite.expect(!IStatsCardKind.anyVisible(Switches(cpu: false, cores: false, memory: false, gpu: false)),
                     "with every card hidden they leave it")
        suite.expect(IStatsCardKind.anyVisible(Switches(cpu: false, cores: false, memory: true, gpu: false)),
                     "one card is enough to keep it")
        let noCPU = Switches(cpu: false, cores: true, memory: false, gpu: false)
        suite.expect(!IStatsCardKind.cores.isVisible(noCPU), "the core grid goes with the CPU card")
        suite.expect(!IStatsCardKind.anyVisible(noCPU), "a core grid alone, its CPU card hidden, shows nothing")
        suite.expect(IStatsCardKind.cores.isVisible(Switches()) && IStatsCardKind.cpu.isVisible(Switches(cores: false)),
                     "hiding the grid leaves the CPU card")
    }

    private static func families(_ suite: TestSuite) {
        let noGPU = Families(cpu: true, memory: true, gpu: false)
        suite.expect(!IStatsCardKind.gpu.isAvailable(noGPU) && !IStatsCardKind.gpu.isVisible(Switches(), families: noGPU),
                     "a card whose family is off does not show, whatever its switch says")
        suite.expect(!IStatsCardKind.anyVisible(Switches(cpu: false, cores: false, memory: false, gpu: true), families: noGPU),
                     "and does not hold the place by itself")
        let noCPU = Families(cpu: false, memory: true, gpu: true)
        suite.expect(!IStatsCardKind.cpu.isAvailable(noCPU) && !IStatsCardKind.cores.isAvailable(noCPU)
                     && IStatsCardKind.memory.isAvailable(noCPU), "the CPU family takes both of its cards")
    }

    private static func refresh(_ suite: TestSuite) {
        let start = Date(timeIntervalSinceReferenceDate: 820_000_000)
        suite.expect(IStatsProcessRefresh.isDue(last: nil, now: start, configured: 1), "the first reading is always due")
        suite.expect(!IStatsProcessRefresh.isDue(last: start, now: start.addingTimeInterval(0.6), configured: 1),
                     "a beat inside the interval reads nothing")
        suite.expect(IStatsProcessRefresh.isDue(last: start, now: start.addingTimeInterval(1), configured: 1),
                     "the lists read again once the interval has passed")
        suite.expect(!IStatsProcessRefresh.isDue(last: start, now: start.addingTimeInterval(2), configured: 5),
                     "a longer interval in Settings is respected")
        suite.expect(IStatsProcessRefresh.interval(configured: 0) == 0.5, "an interval of zero does not read on every beat")
        suite.expect(IStatsProcessRefresh.isDue(last: start, now: start.addingTimeInterval(-30), configured: 1),
                     "a clock set back does not freeze the lists")
    }

    private static func kinds(_ suite: TestSuite) {
        let all = Families()
        suite.expect(IStatsProcessRefresh.kinds(Switches(), families: all, editing: false) == [.cpu, .memory, .gpu],
                     "every list on screen is read")
        let onlyMemory = Switches(cpu: false, cores: false, memory: true, gpu: false)
        suite.expect(IStatsProcessRefresh.kinds(onlyMemory, families: all, editing: false) == [.memory],
                     "a hidden card costs no reading")
        suite.expect(IStatsProcessRefresh.kinds(onlyMemory, families: all, editing: true) == [.cpu, .memory, .gpu],
                     "while arranging, the dimmed cards show their lists too")
        suite.expect(IStatsProcessRefresh.kinds(Switches(), families: Families(cpu: true, memory: true, gpu: false),
                                                editing: true) == [.cpu, .memory],
                     "a family that is off is never read")
    }
}
