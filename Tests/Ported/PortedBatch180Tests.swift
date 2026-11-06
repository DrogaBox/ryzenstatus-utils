// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// Pure checks for the 1.80.0 batch: the window-layout Minimize action, the
/// switcher's mixed windowless order, the Dock middle-click helpers, the
/// Finder's Trash warning and the timer's typed durations.
enum PortedBatch180Tests {
    static func run(_ suite: TestSuite) {
        let registered = Defaults.registeredDefaults

        // Minimize is offered wherever placements are. It moves no frame and
        // claims no combination.
        suite.expect(WindowLayoutAction.allCases.contains(.minimize)
                && WindowLayoutAction.minimize.shortcutID == 71
                && WindowLayoutAction(shortcutID: 71) == .minimize,
               "minimize exists and answers to its own shortcut id")
        suite.expect(WindowLayoutAction.minimize.defaultShortcut == nil
                && registered[DefaultsKey.windowLayoutShortcutMinimize] as? String
                    == WindowLayoutAction.clearedShortcutStorageValue,
               "minimize starts with no combination of its own")
        suite.expect(WindowLayoutAction.minimize.targetCapability == .minimize,
               "minimize only needs a window that can be minimized, not a movable frame")
        let minimizeCurrent = CGRect(x: 120, y: 90, width: 640, height: 480)
        let minimizeVisible = CGRect(x: 0, y: 40, width: 1440, height: 860)
        suite.expect(WindowLayoutGeometry.rect(for: .minimize, current: minimizeCurrent,
                                              visibleFrame: minimizeVisible,
                                              windowGap: 16, screenGap: 32) == minimizeCurrent
                && WindowLayoutGeometry.displayCrossing(for: .minimize, previousAction: .minimize) == nil,
               "minimize keeps the window frame and never crosses displays")
        suite.expect(!WindowEdgeSnapPlacementGroup.placements.contains(.minimize),
               "minimize is not offered as an edge snap placement")
        for language in AppLanguage.allCases {
            suite.expect(!FeatureStrings.windowLayout(language).minimize.isEmpty,
                   "minimize is named in \(language.rawValue)")
        }

        // Mixed order dissolves the windowless section without touching the order.
        suite.expect(registered[DefaultsKey.switcherWindowlessAppsMixedOrder] as? Bool == false
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.switcherWindowlessAppsMixedOrder),
               "windowless apps keep their own section by default and the choice travels with backups")
        suite.expect(SwitcherSupport.windowlessAppDividerPIDs(items: [], windowlessAppsMixedOrder: true) == [],
               "mixed order draws no divider")

        // Dock middle-click.
        suite.expect(registered[DefaultsKey.dockClickNewWindow] as? Bool == false
                && registered[DefaultsKey.panelControlDockClickNewWindow] as? Bool == true,
               "opening a new window on Dock middle-click is opt-in and visible in Quick Controls by default")
        suite.expect(DockClickSupport.middleClickAction(hasModifiers: false, newWindowEnabled: true) == .newWindow
                && DockClickSupport.middleClickAction(hasModifiers: false, newWindowEnabled: false) == .passThrough
                && DockClickSupport.middleClickAction(hasModifiers: true, newWindowEnabled: true) == .passThrough,
               "middle-clicking a Dock icon opens a new window only when enabled and unmodified")
        suite.expect(DockClickSupport.repeatDecision(lastAction: .newWindow, elapsed: 0.1) == .swallow
                && DockClickSupport.repeatDecision(lastAction: .newWindow, elapsed: 0.5) == .deriveFromState,
               "Dock middle-click swallows bounce clicks within the debounce gap and opens another window afterwards")
        suite.expect(DockClickSupport.isVerifiedNewWindow(identifier: "newWindow:")
                && DockClickSupport.isVerifiedNewWindow(identifier: "newWindowForTab:")
                && !DockClickSupport.isVerifiedNewWindow(identifier: "newDocument:")
                && !DockClickSupport.isVerifiedNewWindow(identifier: nil),
               "Dock new-window menu check recognizes standard AppKit new-window identifiers")
        suite.expect(DockClickSupport.isPlainNewCommand(commandCharacter: "N", modifiers: 0)
                && DockClickSupport.isPlainNewCommand(commandCharacter: "n", modifiers: 0)
                && !DockClickSupport.isPlainNewCommand(commandCharacter: "N", modifiers: 1)
                && !DockClickSupport.isPlainNewCommand(commandCharacter: "T", modifiers: 0)
                && !DockClickSupport.isPlainNewCommand(commandCharacter: nil, modifiers: 0),
               "Dock new-window fallback matches only an unmodified Command-N menu item")
        suite.expect(DockClickSupport.newlyOpenedWindowID(before: [10, 20], afterFrontToBack: [30, 20, 10]) == 30
                && DockClickSupport.newlyOpenedWindowID(before: [10, 20], afterFrontToBack: [20, 10]) == nil
                && DockClickSupport.newlyOpenedWindowID(before: [], afterFrontToBack: [50]) == 50,
               "Dock middle-click identifies the newly created window on the front of the screen")

        // The Finder's Trash warning: no stored value means the Finder warns.
        suite.expect(QuickTogglesSupport.finderWarnsBeforeEmptyingTrash(nil)
                && QuickTogglesSupport.finderWarnsBeforeEmptyingTrash(true as CFBoolean)
                && !QuickTogglesSupport.finderWarnsBeforeEmptyingTrash(false as CFBoolean),
               "the Trash confirmation follows the Finder's own warning setting")

        // Timer durations: stored minutes keep an earlier choice, seconds add precision.
        suite.expect(NotchTimerSupport.durationSeconds(minutes: 15, seconds: 0) == 900
                && NotchTimerSupport.durationSeconds(minutes: 1439, seconds: 59) == 86_399
                && NotchTimerSupport.durationSeconds(minutes: 5000, seconds: 90) == 86_399
                && NotchTimerSupport.durationSeconds(minutes: -3, seconds: -1) == 0,
               "timer durations stay within a day")
        suite.expect(NotchTimerSupport.component("07", maximum: 59) == 7
                && NotchTimerSupport.component("60", maximum: 59) == nil
                && NotchTimerSupport.component("1a", maximum: 59) == nil
                && NotchTimerSupport.component("123", maximum: 59) == nil
                && NotchTimerSupport.component("", maximum: 59) == 0,
               "typed clock components accept only digits within range")
        suite.expect(registered[DefaultsKey.notchTimerSeconds] as? Int == 0,
               "the timer starts with no extra seconds")
    }
}
