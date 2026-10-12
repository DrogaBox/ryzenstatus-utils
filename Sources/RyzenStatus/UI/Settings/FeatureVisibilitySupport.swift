// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The Settings pages. Lives here (Foundation-only) so the visibility rules
/// below and the unit tests can reason about pages without pulling SwiftUI in.
enum SettingsPage: Hashable, CaseIterable {
    case general, features, energy, monitor
    case mouse, switcher, keyDebounce, cutPaste, autoQuit, cleaner, uninstaller, urlCleaner, homebrew, appUpdates, media, clipboard, windowLayout, shelf, quickTools, textSnippets, screenshot, screenRecorder, radialMenu, nowPlaying
    case mouseButtonShortcuts, superKey
    case whatsAppDownloads
    case shortcuts, advanced, about, releaseNotes, support, fans, amdPower, amdOverclocking, sensors, dashboard, amdValidation
    case killProcess, notch, commandBar
    case portManager
    case quitProtection
}

/// Which hub features keep each Settings page alive. A page with several
/// features only disappears when ALL of them are switched off in the hub.
enum FeatureVisibilitySupport {
    static let monitorFeatures: [AppFeature] = [
        .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
        .monitorInsights, .monitorAnalytics, .monitorEnergy, .monitorNetworkDetails,
    ]

    /// Features gating a page; empty means the page is part of the app and
    /// always shows (General, Shortcuts, About and friends).
    static func features(for page: SettingsPage) -> [AppFeature] {
        switch page {
        case .energy: return [.keepAwake, .brightness, .extraBrightness, .bluetoothSleep]
        // The panel configuration on this page also carries the mixer block
        // (with the output switcher inside it) and the Connected Devices row,
        // so those keep the page alive even with every metric switched off.
        case .monitor: return monitorFeatures + [.mixer, .soundOutputSwitcher, .connectedDevices]
        case .mouse: return [.scrollInverter, .smoothScroll, .mouseNavigation, .middleClick,
                             .scrollHorizontal, .focusFollowsMouse, .linearScroll, .mouseAcceleration,
                             .mouseClickDebounce]
        case .switcher: return [.switcher, .dockPreview, .dockClick, .spacesOrder]
        case .windowLayout: return [.windowLayout, .windowMaximizer]
        case .autoQuit: return [.autoQuit]
        case .clipboard: return [.clipboardHistory, .pastePlain]
        case .cutPaste: return [.finderCutPaste, .finderRename]
        case .shelf: return [.shelf]
        case .media: return [.mediaTools]
        case .quickTools: return [.quickLauncher, .quickToggles, .colorPicker, .screenOCR, .micMute,
                                  .cameraPreview, .scratchpad, .wallpaper]
        case .urlCleaner: return [.urlCleaner]
        case .homebrew: return [.homebrew]
        case .appUpdates: return [.appUpdates]
        case .cleaner: return [.cleaner]
        case .whatsAppDownloads: return [.whatsAppDownloads]
        case .uninstaller: return [.uninstaller]
        case .keyDebounce: return [.keyboardDebounce]
        case .mouseButtonShortcuts: return [.mouseButtonShortcuts]
        case .superKey: return [.superKey]
        case .textSnippets: return [.textSnippets]
        case .screenshot: return [.screenshot]
        case .screenRecorder: return [.screenRecorder]
        case .radialMenu: return [.radialMenu]
        case .nowPlaying: return [.nowPlaying]
        case .killProcess: return [.killProcess]
        case .portManager: return [.portManager]
        case .quitProtection: return [.quitWindowProtection]
        case .commandBar: return [.commandBar]
        case .notch: return [.notch]
        case .general, .features, .shortcuts, .advanced, .about, .releaseNotes, .support, .fans, .amdPower, .amdOverclocking, .sensors, .dashboard, .amdValidation:
            return []
        }
    }

    static func isPageVisible(_ page: SettingsPage,
                              isAvailable: (AppFeature) -> Bool) -> Bool {
        let gate = features(for: page)
        return gate.isEmpty || gate.contains(where: isAvailable)
    }
}

extension AppFeature {
    /// The Settings page where the feature is configured. Exhaustive by
    /// design: adding an AppFeature does not compile until it has a home,
    /// and the unit harness checks that the home has a row in the directory
    /// and stays visible while the feature is installed.
    ///
    /// `.features` is the documented allow-list: features with nothing to
    /// configure beyond the hub's own switch, so the hub row is their page.
    var settingsPage: SettingsPage {
        switch self {
        case .switcher, .dockPreview, .dockClick, .spacesOrder: return .switcher
        case .windowLayout, .windowMaximizer: return .windowLayout
        case .autoQuit: return .autoQuit
        case .quitWindowProtection: return .quitProtection
        case .scrollInverter, .smoothScroll, .mouseNavigation, .middleClick, .scrollHorizontal,
             .focusFollowsMouse, .linearScroll, .mouseAcceleration, .mouseClickDebounce:
            return .mouse
        case .mouseButtonShortcuts: return .mouseButtonShortcuts
        case .superKey: return .superKey
        case .keyboardDebounce: return .keyDebounce
        case .textSnippets: return .textSnippets
        case .clipboardHistory, .pastePlain: return .clipboard
        case .finderCutPaste, .finderRename: return .cutPaste
        case .shelf: return .shelf
        case .urlCleaner: return .urlCleaner
        // Inside another page: the General page's sound sections.
        case .musicBlock, .audioPriority: return .general
        // Inside another page: the Monitor page's panel configuration.
        case .mixer, .soundOutputSwitcher, .connectedDevices: return .monitor
        case .keepAwake, .brightness, .extraBrightness, .bluetoothSleep: return .energy
        case .quickLauncher, .quickToggles, .colorPicker, .screenOCR, .micMute, .cameraPreview,
             .scratchpad, .wallpaper:
            return .quickTools
        case .mediaTools: return .media
        case .cleaner: return .cleaner
        case .uninstaller: return .uninstaller
        case .homebrew: return .homebrew
        case .appUpdates: return .appUpdates
        case .whatsAppDownloads: return .whatsAppDownloads
        case .killProcess: return .killProcess
        case .portManager: return .portManager
        case .commandBar: return .commandBar
        case .screenshot: return .screenshot
        case .screenRecorder: return .screenRecorder
        case .radialMenu: return .radialMenu
        case .nowPlaying: return .nowPlaying
        // Every island module is a section of the island's page, and the
        // companion is one of its tabs.
        case .notch, .notchCalendar, .notchNotifications, .notchGestures, .notchTimer,
             .notchAccessories, .notchLyrics, .notchLiveEqualizer, .notchQueue, .notchDownloads,
             .notchWatch, .notchMascot:
            return .notch
        case .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk,
             .monitorPower:
            return .monitor
        // Tabs of the Performance dashboard, which is always listed.
        case .monitorInsights, .monitorAnalytics, .monitorEnergy, .monitorNetworkDetails:
            return .dashboard
        // Allow-list, nothing to configure: the installer's preferences have
        // no Settings surface (upstream also points it at the hub), and
        // Cleaning Mode is a one-shot action from the panel and the launcher.
        case .diskImageInstaller, .cleaningMode:
            return .features
        }
    }
}
