// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Every feature the Features hub can switch off entirely. The raw value is
/// the stable identity persisted inside the availability key, so cases can be
/// added but never renamed.
///
/// Availability is a layer ABOVE each feature's own enable key: an unavailable
/// feature disappears from Settings, the menu panel and the menu bar, and its
/// service tears down (and never instantiates on the next launch). Turning a
/// feature back on restores whatever enabled state it had, because the enable
/// keys are never touched.
enum AppFeature: String, CaseIterable {
    // Windows and Dock
    case switcher, dockPreview, dockClick, windowMaximizer, windowLayout, autoQuit
    case spacesOrder
    // Mouse and keyboard
    case scrollInverter, smoothScroll, mouseNavigation, middleClick, keyboardDebounce, textSnippets,
         mouseButtonShortcuts, superKey
    case quitWindowProtection
    case scrollHorizontal, scrollZoom, focusFollowsMouse, linearScroll, mouseAcceleration, mouseClickDebounce
    // Clipboard and files
    case clipboardHistory, pastePlain, finderCutPaste, shelf, urlCleaner
    case finderRename
    case diskImageInstaller
    // Sound
    case mixer, soundOutputSwitcher, micMute, musicBlock, nowPlaying
    case audioPriority
    // Energy and display
    case keepAwake, brightness, extraBrightness
    case bluetoothSleep
    // Tools
    case quickLauncher, quickToggles, quitApps, colorPicker, screenOCR, cleaningMode, mediaTools,
         cleaner, uninstaller, homebrew, appUpdates, whatsAppDownloads, screenshot, screenRecorder, cameraPreview, radialMenu, scratchpad, killProcess, commandBar
    case wallpaper
    case portManager
    case worldClock
    // Dynamic Island
    case notch, notchCalendar, notchNotifications, notchGestures, notchTimer, notchAccessories, notchLyrics,
         notchLiveEqualizer, notchQueue, notchDownloads, notchAgents, notchWatch, notchMascot
    // System monitor, one entry per metric family (temperatures live with
    // their parent metric: CPU temp with CPU, battery temp with power).
    case monitorCPU, monitorGPU, monitorMemory, monitorNetwork, monitorDisk, monitorPower,
         monitorInsights, monitorAnalytics, monitorEnergy, monitorNetworkDetails
    case connectedDevices
}

/// Hub sections, in display order.
enum FeatureGroup: String, CaseIterable {
    case windowsDock, mouseKeyboard, clipboardFiles, sound, energyDisplay, tools, dynamicIsland, monitor
}

/// System permissions surfaced by the hub's transparency portal.
enum AppPermission: String, CaseIterable {
    case accessibility, screenRecording, fullDiskAccess, filesAndFolders, notifications,
         automationFinder, audioCapture, microphone, camera, calendar
}

extension AppFeature {
    var group: FeatureGroup {
        switch self {
        case .switcher, .dockPreview, .dockClick, .windowMaximizer, .windowLayout, .autoQuit:
            return .windowsDock
        case .scrollInverter, .smoothScroll, .mouseNavigation, .middleClick, .keyboardDebounce,
             .textSnippets, .mouseButtonShortcuts, .superKey:
            return .mouseKeyboard
        case .quitWindowProtection:
            return .mouseKeyboard
        case .scrollHorizontal, .scrollZoom, .focusFollowsMouse, .linearScroll, .mouseAcceleration, .mouseClickDebounce:
            return .mouseKeyboard
        case .spacesOrder:
            return .windowsDock
        case .clipboardHistory, .pastePlain, .finderCutPaste, .shelf, .urlCleaner:
            return .clipboardFiles
        case .diskImageInstaller:
            return .clipboardFiles
        case .finderRename:
            return .clipboardFiles
        case .mixer, .soundOutputSwitcher, .micMute, .musicBlock, .nowPlaying:
            return .sound
        case .audioPriority:
            return .sound
        case .keepAwake, .brightness, .extraBrightness:
            return .energyDisplay
        case .bluetoothSleep:
            return .energyDisplay
        case .quickLauncher, .quickToggles, .quitApps, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
             .cleaner, .uninstaller, .homebrew, .appUpdates, .whatsAppDownloads, .screenshot, .screenRecorder, .cameraPreview, .radialMenu, .scratchpad, .killProcess, .commandBar:
            return .tools
        case .wallpaper:
            return .tools
        case .portManager:
            return .tools
        case .worldClock:
            return .tools
        case .notch, .notchCalendar, .notchNotifications, .notchGestures, .notchTimer, .notchAccessories,
             .notchLyrics, .notchLiveEqualizer, .notchQueue, .notchDownloads, .notchAgents, .notchWatch,
             .notchMascot:
            return .dynamicIsland
        case .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
             .monitorInsights, .monitorAnalytics, .monitorEnergy, .monitorNetworkDetails:
            return .monitor
        case .connectedDevices:
            return .monitor
        }
    }

    var symbolName: String {
        switch self {
        case .switcher: return "rectangle.on.rectangle"
        case .dockPreview: return "dock.rectangle"
        case .dockClick: return "dock.arrow.down.rectangle"
        case .windowMaximizer: return "arrow.up.left.and.arrow.down.right"
        case .windowLayout: return "rectangle.3.group"
        case .autoQuit: return "xmark.rectangle"
        case .scrollInverter: return "arrow.up.arrow.down"
        case .smoothScroll: return "cursorarrow.motionlines"
        case .mouseNavigation: return "arrow.left.arrow.right"
        case .middleClick: return "computermouse"
        case .keyboardDebounce: return "keyboard"
        case .textSnippets: return "text.append"
        case .mouseButtonShortcuts: return "button.programmable"
        case .superKey: return "capslock"
        case .quitWindowProtection: return "shield.lefthalf.filled"
        case .scrollHorizontal: return "arrow.triangle.swap"
        case .scrollZoom: return "plus.magnifyingglass"
        case .focusFollowsMouse: return "cursorarrow.and.square.on.square.dashed"
        case .linearScroll: return "arrow.up.and.down.text.horizontal"
        case .mouseAcceleration: return "cursorarrow.rays"
        case .mouseClickDebounce: return "cursorarrow.click"
        case .spacesOrder: return "rectangle.split.3x1"
        case .clipboardHistory: return "doc.on.clipboard"
        case .pastePlain: return "doc.plaintext"
        case .finderCutPaste: return "scissors"
        case .finderRename: return "pencil"
        case .shelf: return "tray.full"
        case .urlCleaner: return "link"
        case .diskImageInstaller: return "externaldrive.badge.plus"
        case .mixer: return "slider.horizontal.3"
        case .soundOutputSwitcher: return "hifispeaker"
        case .audioPriority: return "list.number"
        case .micMute: return "mic.slash"
        case .musicBlock: return "music.note"
        case .nowPlaying: return "music.note"
        case .keepAwake: return "moon.zzz.fill"
        case .brightness: return "display.2"
        case .extraBrightness: return "sun.max.fill"
        case .bluetoothSleep: return "wave.3.right.circle"
        case .quickLauncher: return "wand.and.rays"
        case .quickToggles: return "togglepower"
        case .quitApps: return "xmark.app"
        case .colorPicker: return "eyedropper"
        case .screenOCR: return "text.viewfinder"
        case .cleaningMode: return "bubbles.and.sparkles"
        case .mediaTools: return "photo.on.rectangle.angled"
        case .cleaner: return "sparkles"
        case .uninstaller: return "trash"
        case .homebrew: return "shippingbox"
        case .appUpdates: return "arrow.down.app"
        case .whatsAppDownloads: return "square.and.arrow.down"
        case .screenshot: return "camera.viewfinder"
        case .screenRecorder: return "record.circle"
        case .cameraPreview: return "web.camera"
        case .radialMenu: return "circle.grid.cross"
        case .scratchpad: return "note.text"
        case .killProcess: return "xmark.octagon"
        case .portManager: return "network"
        case .commandBar: return "command"
        case .wallpaper: return "photo.on.rectangle"
        case .worldClock: return "globe"
        case .notch: return "macbook"
        case .notchGestures: return "hand.draw"
        case .notchTimer: return "timer"
        case .notchAccessories: return "battery.25percent"
        case .notchLyrics: return "quote.bubble"
        case .notchLiveEqualizer: return "waveform"
        case .notchQueue: return "list.bullet"
        case .notchDownloads: return "arrow.down.circle"
        case .notchAgents: return "sparkles"
        case .notchNotifications: return "bell"
        case .notchCalendar: return "calendar"
        case .notchWatch: return "eye"
        case .notchMascot: return "face.smiling"
        case .monitorCPU: return "cpu"
        case .monitorGPU: return "rectangle.connected.to.line.below"
        case .monitorMemory: return "memorychip"
        case .monitorNetwork: return "network"
        case .monitorDisk: return "internaldrive"
        case .monitorPower: return "bolt.fill"
        case .monitorInsights: return "lightbulb"
        case .monitorAnalytics: return "chart.xyaxis.line"
        case .monitorEnergy: return "bolt.batteryblock"
        case .monitorNetworkDetails: return "network"
        case .connectedDevices: return "cable.connector"
        }
    }

    var availabilityKey: String { DefaultsKey.featureAvailable(rawValue) }

    var isBeta: Bool { false }

    /// Availability read straight from defaults. Existing features stay
    /// available on update; explicit beta opt-ins may start unavailable.
    func isAvailable(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: availabilityKey)
    }

    var isAvailable: Bool {
        isAvailable(in: .standard)
    }

    /// The feature's own enable keys; any one being true means the feature is
    /// engaged. Empty means the feature works on demand (a panel tile, a
    /// context-menu action), so being available already counts as engaged for
    /// the permissions portal.
    var enabledKeys: [String] {
        switch self {
        case .switcher: return [DefaultsKey.switcherEnabled]
        case .dockPreview: return [DefaultsKey.dockPreviewEnabled]
        case .dockClick: return [DefaultsKey.dockClickMinimize,
                                 DefaultsKey.dockClickHide,
                                 DefaultsKey.dockClickCycleWindows]
        case .windowMaximizer: return [DefaultsKey.windowMaximizeEnabled]
        case .autoQuit: return [DefaultsKey.autoQuitEnabled]
        case .scrollInverter: return [DefaultsKey.scrollInverterEnabled,
                                      DefaultsKey.scrollInverterHorizontalEnabled]
        case .smoothScroll: return [DefaultsKey.smoothScrollEnabled]
        case .mouseNavigation: return [DefaultsKey.mouseNavigationEnabled]
        case .middleClick: return [DefaultsKey.middleClickEnabled]
        case .keyboardDebounce: return [DefaultsKey.keyboardDebounceEnabled]
        case .textSnippets: return [DefaultsKey.textSnippetsEnabled, DefaultsKey.snippetLibraryEnabled]
        case .mouseButtonShortcuts: return [DefaultsKey.mouseButtonShortcutsEnabled]
        case .superKey: return [DefaultsKey.superKeyEnabled]
        case .quitWindowProtection:
            return [DefaultsKey.quitProtectionQuitEnabled, DefaultsKey.quitProtectionCloseEnabled]
        case .radialMenu: return [DefaultsKey.radialMenuEnabled]
        case .scrollHorizontal: return [DefaultsKey.scrollHorizontalEnabled]
        case .scrollZoom: return [DefaultsKey.pinchZoomEnabled]
        case .focusFollowsMouse: return [DefaultsKey.focusFollowsMouseEnabled]
        case .linearScroll: return [DefaultsKey.linearScrollEnabled]
        case .mouseAcceleration: return [DefaultsKey.mouseAccelerationDisabled]
        case .mouseClickDebounce: return [DefaultsKey.mouseClickDebounceEnabled]
        case .spacesOrder: return [DefaultsKey.spacesOrderEnabled]
        case .clipboardHistory: return [DefaultsKey.clipboardHistoryEnabled]
        case .pastePlain: return [DefaultsKey.pastePlainEnabled]
        // Pasting an image as a file runs through the same Finder tap.
        case .finderCutPaste: return [DefaultsKey.finderCutPasteEnabled,
                                      DefaultsKey.finderPasteImageAsFile]
        case .finderRename: return [DefaultsKey.finderRenameEnabled]
        case .shelf: return [DefaultsKey.shelfEnabled]
        case .urlCleaner: return [DefaultsKey.urlCleanerEnabled]
        case .soundOutputSwitcher: return [DefaultsKey.soundOutputSwitcherEnabled]
        case .audioPriority: return [DefaultsKey.audioPriorityOutputEnabled,
                                     DefaultsKey.audioPriorityInputEnabled]
        case .musicBlock: return [DefaultsKey.musicBlockEnabled]
        case .nowPlaying: return [DefaultsKey.nowPlayingEnabled]
        case .brightness: return [DefaultsKey.brightnessControlEnabled]
        case .extraBrightness: return [DefaultsKey.extraBrightnessEnabled]
        case .bluetoothSleep: return [DefaultsKey.bluetoothSleepEnabled]
        case .commandBar: return [DefaultsKey.commandBarEnabled]
        case .notch: return [DefaultsKey.notchEnabled]
        case .notchGestures: return [DefaultsKey.notchGesturesEnabled]
        case .notchTimer: return [DefaultsKey.notchTimerEnabled]
        case .notchAccessories: return [DefaultsKey.notchAccessoriesEnabled]
        case .notchLyrics: return [DefaultsKey.notchLyricsEnabled]
        case .notchLiveEqualizer: return [DefaultsKey.notchLiveEqualizer]
        case .notchQueue: return [DefaultsKey.notchQueueEnabled]
        case .notchDownloads: return [DefaultsKey.notchDownloadsEnabled]
        case .notchAgents: return [DefaultsKey.notchAgentsEnabled]
        case .notchNotifications: return [DefaultsKey.notchNotificationsEnabled]
        case .notchCalendar: return [DefaultsKey.notchCalendarEnabled]
        case .notchWatch: return [DefaultsKey.notchWatchEnabled]
        case .notchMascot: return [DefaultsKey.notchMascotEnabled]
        // On demand: a panel tile and a Settings page, or a System card row.
        case .portManager, .connectedDevices: return []
        // On demand: the installer answers each mounted image, and the
        // wallpaper gallery acts only when a picture is chosen.
        case .diskImageInstaller, .wallpaper:
            return []
        // On demand: the rows redraw only while the panel shows them.
        case .worldClock:
            return []
        case .windowLayout, .mixer, .micMute, .keepAwake,
             .quickLauncher, .quickToggles, .quitApps, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
             .cleaner, .uninstaller, .homebrew, .appUpdates, .whatsAppDownloads, .screenshot, .screenRecorder, .cameraPreview, .scratchpad, .killProcess,
             .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
             .monitorInsights, .monitorAnalytics, .monitorEnergy, .monitorNetworkDetails:
            return []
        }
    }

    /// Which permissions the feature can use at all. Whether it is using them
    /// RIGHT NOW is answered by `activeFeatures(using:)`, which also applies
    /// the dynamic rules (simple-mode switcher needs no screen recording, the
    /// monitor only notifies when an alert is on, and so on).
    var permissions: [AppPermission] {
        switch self {
        case .scrollInverter, .smoothScroll, .mouseNavigation, .middleClick, .keyboardDebounce,
             .textSnippets, .mouseButtonShortcuts, .superKey, .dockClick, .windowMaximizer,
             .windowLayout, .autoQuit, .cleaningMode, .pastePlain, .radialMenu:
            return [.accessibility]
        case .finderCutPaste: return [.accessibility, .automationFinder]
        // The tap reads Finder's focused element to leave text fields alone.
        case .finderRename: return [.accessibility]
        // Device priority only changes the default devices; Bluetooth on
        // sleep only flips the controller's power. Neither needs a grant.
        case .audioPriority, .bluetoothSleep: return []
        // The tap watches ⌘Q and ⌘W only, through Accessibility.
        case .quitWindowProtection: return [.accessibility]
        // Wheel and click taps, and the window under the pointer, all go
        // through Accessibility.
        case .scrollHorizontal, .scrollZoom, .focusFollowsMouse, .linearScroll, .mouseClickDebounce:
            return [.accessibility]
        // Pointer acceleration is an IOKit HID property and the Spaces order
        // a Dock preference; neither needs a grant.
        case .mouseAcceleration, .spacesOrder: return []
        // Copying into Applications needs no grant this fork tracks (upstream
        // lists App Management, which this catalog does not model); the
        // gallery reads Apple's stills and pictures the user picked.
        case .diskImageInstaller, .wallpaper: return []
        // Time zones are part of Foundation; nothing is asked of macOS.
        case .worldClock: return []
        // Only emptying the Trash asks the Finder; every other quick toggle
        // (dark mode included) works without a permission.
        case .quickToggles: return [.automationFinder]
        // Each app gets the ordinary quit request it would from its own menu.
        case .quitApps: return []
        case .switcher: return [.accessibility, .screenRecording]
        case .dockPreview: return [.accessibility, .screenRecording]
        case .screenOCR: return [.screenRecording]
        case .screenshot: return [.screenRecording]
        // The sound of the Mac rides the same grant the pixels do. Microphone
        // access stays contextual, and Accessibility only keeps typing timing.
        case .screenRecorder: return [.screenRecording, .accessibility, .microphone]
        case .cameraPreview: return [.camera]
        case .keepAwake: return [.accessibility]
        case .brightness: return [.accessibility]
        case .cleaner: return [.fullDiskAccess, .filesAndFolders, .notifications]
        case .uninstaller: return [.fullDiskAccess, .automationFinder]
        // Commands open in the default terminal app, which asks nothing of this one.
        case .homebrew: return []
        case .appUpdates: return [.notifications]
        case .whatsAppDownloads: return [.filesAndFolders, .notifications]
        case .mixer, .notchLiveEqualizer: return [.audioCapture]
        case .monitorCPU, .monitorMemory, .monitorDisk, .monitorPower: return [.notifications]
        // GPU alerts send notifications (MonitorAlertService.evaluate
        // handles both GPU keys), so the feature must advertise them or the
        // permissions portal and activeFeatures stay blind to GPU alerting.
        case .monitorGPU: return [.notifications]
        case .notchCalendar: return [.calendar]
        case .notchNotifications: return [.accessibility]
        case .notchDownloads: return [.filesAndFolders]
        // Agents reads the CLIs' own history files and the Claude app's saved
        // limits; none of that needs a macOS permission.
        case .notchAgents: return []
        case .notchWatch: return [.screenRecording, .notifications]
        case .notch: return [.accessibility]
        // Port Manager reads `lsof` and terminates through Kill Process;
        // Connected Devices reads the IOKit registry. Neither needs a grant.
        case .portManager, .connectedDevices: return []
        case .clipboardHistory, .shelf, .urlCleaner, .soundOutputSwitcher, .musicBlock, .nowPlaying,
             .extraBrightness, .quickLauncher, .colorPicker, .micMute, .mediaTools,
             .scratchpad, .killProcess, .monitorNetwork, .commandBar,
             .notchGestures, .notchTimer, .notchAccessories, .notchLyrics, .notchMascot, .notchQueue,
             .monitorInsights, .monitorAnalytics, .monitorEnergy, .monitorNetworkDetails:
            return []
        }
    }

    /// Broad grants worth explaining during first run. Permissions used only
    /// by an optional sub-feature stay contextual, at the moment that control
    /// is actually used.
    var onboardingPermissions: [AppPermission] {
        switch self {
        case .keepAwake, .brightness, .radialMenu, .quickToggles, .cleaner,
             .uninstaller, .homebrew, .appUpdates, .mixer, .cameraPreview,
             .micMute:
            return []
        default:
            return permissions.filter { $0 == .accessibility || $0 == .screenRecording }
        }
    }

    static func features(in group: FeatureGroup) -> [AppFeature] {
        allCases.filter { $0.group == group }
    }

    /// Registered defaults preserve existing features on update. New opt-in
    /// features and explicit betas ship uninstalled.
    static var availabilityDefaults: [String: Any] {
        Dictionary(uniqueKeysWithValues: allCases.map {
            ($0.availabilityKey, !optInFeatures.contains($0))
        })
    }

    /// Features an update must not install on its own: they arrive through
    /// the Features page. The disk image installer would start offering to
    /// install every image that is opened, and the wallpaper gallery would
    /// grow the panel by a tab.
    static let optInFeatures: Set<AppFeature> = [
        .diskImageInstaller, .wallpaper,
        // A new panel tab arrives only when asked for.
        .worldClock,
        // Upstream ships these opt-in: they change how every window, wheel or
        // Space behaves, so an update must not install them on its own.
        .focusFollowsMouse, .scrollHorizontal, .scrollZoom, .linearScroll, .spacesOrder,
        // Quitting apps from a window is asked for, never installed by an update.
        .quitApps,
        // Without the mixer it would add its own panel section.
        .audioPriority,
    ]

    /// Features FeatureRuntime deliberately has no binding for. Every other
    /// feature must have one, or flipping it in the hub (or a preset, or a
    /// backup import) would leave its service running or never start it after
    /// a relaunch. The unit harness reads FeatureRuntime's binding table and
    /// checks the two lists add up to every case, so a newly ported feature
    /// cannot ship unwired.
    static let featuresWithoutRuntimeBinding: Set<AppFeature> = [
        // On-demand tools: they hold no resources and their surfaces simply
        // follow availability in the UI.
        .uninstaller, .homebrew, .cleaningMode, .killProcess,
        // Runs `lsof` only while its page or panel row is open.
        .portManager,
        // A view that reads the saved cities when it draws.
        .worldClock,
        // This fork's queue keeps no state; a running island re-reads the switch.
        .notchQueue,
        // Performance dashboard tabs: views that read availability on render,
        // with no sampler of their own.
        .monitorInsights, .monitorAnalytics, .monitorEnergy, .monitorNetworkDetails,
    ]

    /// Features that are available, engaged and using `permission` right now.
    /// Readers are injectable so the logic stays testable without touching
    /// real UserDefaults.
    static func activeFeatures(using permission: AppPermission,
                               isAvailable: (AppFeature) -> Bool,
                               boolFor: (String) -> Bool,
                               stringFor: (String) -> String?,
                               dataFor: (String) -> Data? = { _ in nil }) -> [AppFeature] {
        allCases.filter { feature in
            guard feature.permissions.contains(permission), isAvailable(feature) else { return false }
            let keys = feature.enabledKeys
            guard keys.isEmpty || keys.contains(where: boolFor) else { return false }
            switch (feature, permission) {
            case (.switcher, .screenRecording):
                return !boolFor(DefaultsKey.switcherSimpleMode)
            case (.radialMenu, .accessibility):
                return RadialMenuSupport.needsAccessibility(
                    RadialMenuSupport.decode(dataFor(DefaultsKey.radialMenuItems)))
                    || RadialMenuMouseTrigger.sanitized(
                        stringFor(DefaultsKey.radialMenuMouseButton)) != .off
            case (.keepAwake, .accessibility):
                return boolFor(DefaultsKey.keepAwakeMouseJiggleEnabled)
            case (.brightness, .accessibility):
                // A finer key step answers the keys from the same tap.
                return boolFor(DefaultsKey.brightnessKeysEnabled)
                    || boolFor(DefaultsKey.brightnessOSDEnabled)
                    || BrightnessSupport.KeyStep.sanitized(stringFor(DefaultsKey.brightnessKeyStep)) != .standard
            case (.monitorCPU, .notifications):
                return boolFor(DefaultsKey.monitorAlertCPU) || boolFor(DefaultsKey.monitorAlertCPUTemperature)
            case (.monitorMemory, .notifications):
                return boolFor(DefaultsKey.monitorAlertMemory)
            case (.monitorDisk, .notifications):
                return boolFor(DefaultsKey.monitorAlertDisk)
            case (.monitorPower, .notifications):
                return boolFor(DefaultsKey.monitorAlertBattery)
            // GPU alert toggles must register as active notification
            // consumers just like the other monitor families.
            case (.monitorGPU, .notifications):
                return boolFor(DefaultsKey.monitorAlertGPUTemperature)
                    || boolFor(DefaultsKey.monitorAlertGPUPower)
            case (.cleaner, .notifications):
                return (stringFor(DefaultsKey.cleanerScheduleFrequency) ?? "off") != "off"
                    && boolFor(DefaultsKey.cleanerScheduleNotify)
            case (.appUpdates, .notifications):
                return (stringFor(DefaultsKey.appUpdatesCheckFrequency) ?? "off") != "off"
                    && boolFor(DefaultsKey.appUpdatesNotify)
            case (.whatsAppDownloads, .notifications):
                return false
            case (.notchLiveEqualizer, .audioCapture):
                return isAvailable(.notch) && boolFor(DefaultsKey.notchEnabled)
                    && !(stringFor(DefaultsKey.notchHiddenModules) ?? "").split(separator: ",").contains("music")
            default:
                return true
            }
        }
    }

    /// Monitor alert keys and the metric feature each one belongs to. An
    /// alert only counts while its metric is available in the hub.
    static let monitorAlertPairs: [(key: String, feature: AppFeature)] = [
        (DefaultsKey.monitorAlertCPU, .monitorCPU),
        (DefaultsKey.monitorAlertCPUTemperature, .monitorCPU),
        (DefaultsKey.monitorAlertMemory, .monitorMemory),
        (DefaultsKey.monitorAlertDisk, .monitorDisk),
        (DefaultsKey.monitorAlertBattery, .monitorPower),
        // Without these pairs, enabling only GPU alerts left
        // anyEnabled() == false, so MonitorAlertService.syncWithPreferences()
        // stopped the snapshot sink and the Settings toggles did nothing.
        (DefaultsKey.monitorAlertGPUTemperature, .monitorGPU),
        (DefaultsKey.monitorAlertGPUPower, .monitorGPU),
    ]

    static func anyMonitorAlertEnabled(isAvailable: (AppFeature) -> Bool,
                                       boolFor: (String) -> Bool) -> Bool {
        monitorAlertPairs.contains { boolFor($0.key) && isAvailable($0.feature) }
    }

    /// Runtime convenience over the injectable core.
    static func activeFeatures(using permission: AppPermission,
                               defaults: UserDefaults = .standard) -> [AppFeature] {
        activeFeatures(using: permission,
                       isAvailable: { defaults.bool(forKey: $0.availabilityKey) },
                       boolFor: { defaults.bool(forKey: $0) },
                       stringFor: { defaults.string(forKey: $0) },
                       dataFor: { defaults.data(forKey: $0) })
    }
}

extension AppPermission {
    var symbolName: String {
        switch self {
        case .accessibility: return "accessibility"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .filesAndFolders: return "folder.badge.person.crop"
        case .fullDiskAccess: return "externaldrive.badge.person.crop"
        case .notifications: return "bell.badge"
        case .automationFinder: return "gearshape.2"
        case .audioCapture: return "waveform"
        case .microphone: return "mic"
        case .camera: return "camera"
        case .calendar: return "calendar"
        }
    }
}

/// The name every surface shows for a feature. Lives here (Foundation-only,
/// beside the catalog itself) so the Settings directory and the unit harness
/// can name a feature without pulling the hub's SwiftUI view in.
extension AppFeature {
    /// Titles reuse the strings users already see across the app; only names
    /// with no clean existing form live in the hub strings.
    func hubTitle(_ s: Strings, hub: FeatureHubStrings,
                  language: AppLanguage = L10n.shared.language) -> String {
        switch self {
        case .switcher: return s.switcherSection
        case .dockPreview: return s.dockPreviewName
        case .dockClick: return hub.titleDockClick
        case .windowMaximizer: return s.windowMaximizeName
        case .windowLayout: return FeatureStrings.windowLayout(language).title
        case .autoQuit: return s.autoQuitName
        case .scrollInverter: return s.invertMouseScroll
        case .smoothScroll: return s.smoothScrollName
        case .mouseNavigation: return hub.titleMouseNavigation
        case .middleClick: return s.middleClickSection
        case .keyboardDebounce: return s.keyDebounceName
        case .mouseButtonShortcuts: return hub.titleMouseButtons
        case .superKey: return hub.titleSuperKey
        case .quitWindowProtection: return FeatureStrings.quitProtection(language).name
        case .scrollHorizontal: return s.scrollHorizontalName
        case .scrollZoom: return s.zoomSection
        case .focusFollowsMouse: return s.focusFollowsMouseName
        case .linearScroll: return s.linearScrollName
        case .mouseAcceleration: return s.mouseAccelerationName
        case .mouseClickDebounce: return FeatureStrings.mouseClickDebounce(language).title
        case .spacesOrder: return s.spacesOrderName
        case .textSnippets: return FeatureStrings.snippets(language).pageTitle
        case .clipboardHistory: return FeatureStrings.clipboard(language).title
        case .pastePlain: return s.pastePlainName
        case .finderCutPaste: return s.cutPasteName
        case .finderRename: return FeatureStrings.finderRename(language).hubTitle
        case .shelf: return s.shelfName
        case .urlCleaner: return s.urlCleanerName
        case .diskImageInstaller: return FeatureStrings.diskImageInstaller(language).title
        case .mixer: return s.mixerSection
        case .soundOutputSwitcher: return s.soundOutputSwitcherTitle
        case .audioPriority: return hub.titleAudioPriority
        case .micMute: return s.micMuteName
        case .musicBlock: return hub.titleMusicBlock
        case .nowPlaying: return hub.titleNowPlaying
        case .keepAwake: return s.keepAwakeTitle
        case .brightness: return FeatureStrings.brightness(language).pageTitle
        case .extraBrightness: return s.extraBrightnessName
        case .bluetoothSleep: return FeatureStrings.bluetoothSleep(language).pageTitle
        case .quickLauncher: return s.launcherName
        case .quickToggles: return FeatureStrings.quickToggles(language).pageTitle
        case .quitApps: return s.quitAppsName
        case .colorPicker: return s.colorPickerName
        case .screenOCR: return s.ocrName
        case .screenshot: return FeatureStrings.screenshot(language).pageTitle
        case .screenRecorder: return FeatureStrings.recorder(language).pageTitle
        case .cameraPreview: return FeatureStrings.cameraPreview(language).pageTitle
        case .radialMenu: return FeatureStrings.radialMenu(language).pageTitle
        case .scratchpad: return FeatureStrings.scratchpad(language).pageTitle
        case .killProcess: return FeatureStrings.killProcess(language).pageTitle
        case .wallpaper: return FeatureStrings.wallpaper(language).pageTitle
        case .portManager: return FeatureStrings.portManager(language).title
        case .worldClock: return FeatureStrings.worldClock(language).pageTitle
        case .cleaningMode: return s.cleaningMenuItem
        case .mediaTools: return s.mediaName
        case .cleaner: return s.cleanerName
        case .uninstaller: return s.uninstallerName
        case .homebrew: return FeatureStrings.packageManager(language).title
        case .appUpdates: return FeatureStrings.appUpdates(language).pageTitle
        case .monitorCPU: return s.monitorShowCPU
        case .monitorGPU: return s.monitorShowGPU
        case .monitorMemory: return s.monitorShowMemory
        case .monitorNetwork: return s.monitorShowNetwork
        case .monitorDisk: return s.diskSection
        case .monitorPower: return s.powerSection
        case .whatsAppDownloads: return FeatureStrings.whatsAppDownloads(language).title
        case .monitorInsights: return "Smart Performance Insights"
        case .monitorAnalytics: return "Analytics & Trend History"
        case .monitorEnergy: return "Energy Impact & Battery Flow"
        case .monitorNetworkDetails: return "Network Scanner & Details"
        case .connectedDevices: return FeatureStrings.connectedDevices(language).title
        case .commandBar: return FeatureStrings.commandBar(language).pageTitle
        case .notch: return NotchStrings.notch(language).title
        case .notchCalendar: return FeatureStrings.notchCalendar(language).title
        case .notchNotifications: return hub.titleNotchNotifications
        case .notchGestures: return hub.titleNotchGestures
        case .notchTimer: return hub.titleNotchTimer
        case .notchAccessories: return hub.titleNotchAccessories
        case .notchLyrics: return hub.titleNotchLyrics
        case .notchDownloads: return hub.titleNotchDownloads
        case .notchAgents: return FeatureStrings.notchAgents(language).title
        case .notchWatch: return hub.titleNotchWatch
        case .notchMascot: return hub.titleNotchMascot
        case .notchLiveEqualizer: return hub.titleNotchLiveEqualizer
        case .notchQueue: return hub.titleNotchQueue
        }
    }
}

extension AppFeature {
    /// What can only run inside the Dynamic Island: they do nothing without
    /// it, so its uninstall asks whether they leave too.
    static var dynamicIslandExtensions: [AppFeature] {
        features(in: .dynamicIsland).filter { $0 != .notch }
    }

    /// Whether this Mac can run the feature. Every feature in this app runs
    /// on any supported Mac, so the gate only exists to read the same as the
    /// hub's install paths.
    var isHardwareSupported: Bool { true }

    /// Why an install is refused on this Mac, shown in place of Install.
    /// Set only while the feature is not installed, so an install that
    /// predates a check keeps its ordinary row.
    var installBlockedReason: String? {
        guard !isAvailable, !isHardwareSupported else { return nil }
        return nil
    }

    /// Switches the Features page may offer to uninstall once they turn out
    /// never used. Each one does nothing until its own switch is on, and no
    /// other feature leans on it while it is off.
    static let offeredWhenNeverSwitchedOn: [AppFeature] = [
        .dockPreview, .dockClick, .windowMaximizer, .autoQuit,
        .scrollInverter, .linearScroll, .focusFollowsMouse, .mouseAcceleration, .mouseNavigation,
        .mouseButtonShortcuts, .middleClick, .keyboardDebounce, .mouseClickDebounce, .superKey,
        .finderCutPaste,
    ]

    /// Installed features from that list whose switches are off and were never
    /// saved on this Mac: installed, but not once turned on. A switch turned
    /// on and back off is saved, so a feature someone used keeps its place.
    static func neverSwitchedOn(isAvailable: (AppFeature) -> Bool,
                                boolFor: (String) -> Bool,
                                isSaved: (String) -> Bool) -> [AppFeature] {
        offeredWhenNeverSwitchedOn.filter { feature in
            isAvailable(feature)
                && !feature.enabledKeys.isEmpty
                && !feature.enabledKeys.contains(where: boolFor)
                && !feature.enabledKeys.contains { isSaved($0) && !savedOnEveryMac.contains($0) }
        }
    }

    /// Switches a launch migration saves on every Mac, the horizontal scroll
    /// direction copying the vertical one, so a saved value there says
    /// nothing about use. Only one that is on counts.
    private static let savedOnEveryMac: Set<String> = [DefaultsKey.scrollInverterHorizontalEnabled]
}
