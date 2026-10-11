// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// One-click starting points for the Features hub. A preset is a shape, not a
/// prison: applying one installs and engages its features and uninstalls the
/// rest, but nothing is deleted — every feature keeps its settings and comes
/// back with one click, exactly like any hub install.
enum FeaturePreset: String, CaseIterable, Identifiable {
    case essential, windows, battery

    var id: String { rawValue }

    /// The features the preset keeps installed.
    var features: Set<AppFeature> {
        switch self {
        case .essential:
            return [.mixer, .keepAwake,
                    .monitorCPU, .monitorGPU, .monitorMemory,
                    .monitorNetwork, .monitorDisk, .monitorPower,
                    .monitorInsights, .monitorAnalytics, .monitorEnergy, .monitorNetworkDetails]
        case .windows:
            return [.switcher, .windowLayout, .dockPreview, .dockClick, .windowMaximizer]
        case .battery:
            // The lean monitor: battery, memory pressure and the processor,
            // with nothing that listens to input events.
            return [.monitorCPU, .monitorMemory, .monitorPower]
        }
    }

    /// Enable keys switched on along with the install, so the preset's
    /// features actually work instead of arriving as more toggles to find.
    /// Presets whose features are on-demand need none.
    var enableKeys: [String] {
        switch self {
        case .essential, .battery:
            return []
        case .windows:
            return [DefaultsKey.switcherEnabled,
                    DefaultsKey.dockPreviewEnabled,
                    DefaultsKey.dockClickMinimize,
                    DefaultsKey.windowMaximizeEnabled]
        }
    }

    var symbolName: String {
        switch self {
        case .essential: return "star.fill"
        case .windows: return "macwindow.on.rectangle"
        case .battery: return "battery.75percent"
        }
    }
}

/// The honest, curated cost label each feature earns in the hub: what the
/// feature keeps alive WHILE IT IS ON. Uninstalled features load nothing at
/// all, which is the hub's own promise. Static by design — pretending to
/// measure per-feature cost live would be theater.
enum FeatureEnergyProfile: String {
    /// Nothing at rest: on-demand tools, shortcut-driven actions and
    /// system-notification listeners.
    case idle
    /// A mouse event tap (scrolls, clicks or pointer moves).
    case mouse
    /// A pointer gesture that works with either a trackpad or mouse.
    case pointer
    /// A keyboard event tap.
    case keyboard
    /// Both input taps.
    case inputs
    /// Samples or polls on an interval while active or visible.
    case periodic
}

extension AppFeature {
    var energyProfile: FeatureEnergyProfile {
        switch self {
        case .scrollInverter, .smoothScroll, .windowMaximizer, .middleClick,
             .mouseNavigation, .dockPreview, .dockClick, .shelf,
             .mouseButtonShortcuts:
            return .mouse
        case .switcher, .keyboardDebounce, .finderCutPaste, .superKey:
            return .keyboard
        case .textSnippets, .autoQuit:
            return .inputs
        case .windowLayout:
            return UserDefaults.standard.bool(forKey: DefaultsKey.windowGestureEnabled) ? .pointer : .idle
        case .radialMenu:
            // With a side button configured the trigger is a mouse tap;
            // shortcut-only costs nothing at rest.
            return RadialMenuMouseTrigger.sanitized(
                UserDefaults.standard.string(forKey: DefaultsKey.radialMenuMouseButton)) == .off
                ? .idle : .mouse
        case .clipboardHistory, .urlCleaner, .extraBrightness, .nowPlaying,
             .monitorCPU, .monitorGPU, .monitorMemory,
             .monitorNetwork, .monitorDisk, .monitorPower,
             .monitorInsights, .monitorAnalytics, .monitorEnergy, .monitorNetworkDetails:
            return .periodic
        case .pastePlain, .mixer, .soundOutputSwitcher, .micMute,
             .musicBlock, .keepAwake, .brightness, .quickLauncher, .quickToggles, .colorPicker,
             .screenOCR, .cleaningMode, .mediaTools, .cleaner, .uninstaller, .homebrew,
             .whatsAppDownloads, .screenshot, .screenRecorder,
             .cameraPreview, .scratchpad, .killProcess, .commandBar,
             .notch, .notchCalendar, .notchNotifications, .notchGestures, .notchTimer,
             .notchAccessories, .notchLyrics, .notchLiveEqualizer, .notchQueue, .notchDownloads, .notchWatch, .notchMascot:
            // The process table is only sampled while its page is open.
            return .idle
        // Port Manager runs `lsof` only while its page or panel is open.
        // Connected Devices never polls here: it reads once and then follows
        // IOKit plug and unplug events while its panel row is on screen.
        case .portManager, .connectedDevices:
            return .idle
        // The tap only watches Command-Q and Command-W.
        case .quitWindowProtection:
            return .keyboard
        // Wheel, pointer and click taps.
        case .scrollHorizontal, .focusFollowsMouse, .linearScroll, .mouseClickDebounce:
            return .mouse
        // One system setting written when switched; nothing runs at rest.
        case .mouseAcceleration, .spacesOrder:
            return .idle
        // The rename shortcut is answered by a keyboard tap.
        case .finderRename:
            return .keyboard
        // Device priority follows CoreAudio notifications; Bluetooth on
        // sleep only waits for the sleep and wake notifications.
        case .audioPriority, .bluetoothSleep:
            return .idle
        // The installer answers each mounted image; the gallery acts only
        // when a picture is chosen.
        case .diskImageInstaller, .wallpaper:
            return .idle
        case .appUpdates:
            // The list is on demand; only a background schedule keeps a timer.
            return AppUpdatesSupport.CheckFrequency.sanitized(
                UserDefaults.standard.string(forKey: DefaultsKey.appUpdatesCheckFrequency)) == .off
                ? .idle : .periodic
        }
    }
}
