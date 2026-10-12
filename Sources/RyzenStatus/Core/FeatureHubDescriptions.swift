// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The one-line description each Features hub row shows. Lives here
/// (Foundation-only) rather than beside the hub's SwiftUI view, so the unit
/// harness can pin that every feature has its own text: the island once
/// shipped with every module row repeating the island's description.
extension AppFeature {
    func hubDescription(_ hub: FeatureHubStrings,
                        language: AppLanguage = L10n.shared.language) -> String {
        let s = Strings.localized(language)
        switch self {
        case .switcher: return hub.descSwitcher
        case .dockPreview: return hub.descDockPreview
        case .dockClick: return hub.descDockClick
        case .windowMaximizer: return hub.descWindowMaximizer
        case .windowLayout: return hub.descWindowLayout
        case .autoQuit: return hub.descAutoQuit
        case .scrollInverter: return hub.descScrollInverter
        case .smoothScroll: return hub.descSmoothScroll
        case .mouseNavigation: return hub.descMouseNavigation
        case .middleClick: return hub.descMiddleClick
        case .keyboardDebounce: return hub.descKeyboardDebounce
        case .textSnippets: return FeatureStrings.snippets(language).hubDescription
        case .clipboardHistory: return hub.descClipboardHistory
        case .pastePlain: return hub.descPastePlain
        case .finderCutPaste: return hub.descFinderCutPaste
        case .finderRename: return FeatureStrings.finderRename(language).hubDescription
        case .shelf: return hub.descShelf
        case .urlCleaner: return hub.descURLCleaner
        case .diskImageInstaller:
            return FeatureStrings.diskImageInstaller(language).hubDescription
        case .mixer: return hub.descMixer
        case .soundOutputSwitcher: return hub.descSoundOutputSwitcher
        case .audioPriority: return hub.descAudioPriority
        case .micMute: return hub.descMicMute
        case .musicBlock: return hub.descMusicBlock
        case .nowPlaying: return hub.descNowPlaying
        case .keepAwake: return hub.descKeepAwake
        case .brightness: return FeatureStrings.brightness(language).hubDescription
        case .extraBrightness: return hub.descExtraBrightness
        case .bluetoothSleep: return FeatureStrings.bluetoothSleep(language).hubDescription
        case .quickLauncher: return hub.descQuickLauncher
        case .quickToggles: return FeatureStrings.quickToggles(language).hubDescription
        case .colorPicker: return hub.descColorPicker
        case .screenOCR: return hub.descScreenOCR
        case .screenshot: return FeatureStrings.screenshot(language).hubDescription
        case .screenRecorder: return FeatureStrings.recorder(language).hubDescription
        case .cameraPreview: return FeatureStrings.cameraPreview(language).hubDescription
        case .radialMenu: return FeatureStrings.radialMenu(language).hubDescription
        case .scratchpad: return FeatureStrings.scratchpad(language).hubDescription
        case .killProcess: return FeatureStrings.killProcess(language).hubDescription
        case .wallpaper: return FeatureStrings.wallpaper(language).hubDescription
        case .portManager: return FeatureStrings.portManager(language).hubDescription
        case .cleaningMode: return hub.descCleaningMode
        case .mediaTools: return hub.descMediaTools
        case .cleaner: return hub.descCleaner
        case .uninstaller: return hub.descUninstaller
        case .homebrew: return FeatureStrings.packageManager(language).caption
        case .appUpdates: return FeatureStrings.appUpdates(language).hubDescription
        case .monitorCPU: return hub.descMonitorCPU
        case .monitorGPU: return hub.descMonitorGPU
        case .monitorMemory: return hub.descMonitorMemory
        case .monitorNetwork: return hub.descMonitorNetwork
        case .monitorDisk: return hub.descMonitorDisk
        case .mouseButtonShortcuts: return hub.descMouseButtons
        case .superKey: return hub.descSuperKey
        case .quitWindowProtection: return FeatureStrings.quitProtection(language).description
        case .scrollHorizontal: return s.scrollHorizontalCaption
        case .focusFollowsMouse: return s.focusFollowsMouseCaption
        case .linearScroll: return s.linearScrollCaption
        case .mouseAcceleration: return s.mouseAccelerationCaption
        case .mouseClickDebounce: return FeatureStrings.mouseClickDebounce(language).caption
        case .spacesOrder: return s.spacesOrderCaption
        case .monitorPower: return hub.descMonitorPower
        case .whatsAppDownloads: return FeatureStrings.whatsAppDownloads(language).hubDescription
        case .monitorInsights: return "Automated diagnostic cards for memory leaks, Rosetta 2 cost, and CPU runaway processes."
        case .monitorAnalytics: return "Linear regression metrics, performance trends, and long-term CPU/GPU/RAM statistics."
        case .monitorEnergy: return "Per-process energy impact breakdown, battery health flow, and process wakeup stats."
        case .monitorNetworkDetails: return "Local network device scanner, per-adapter bandwidth, and open socket inspector."
        case .connectedDevices: return FeatureStrings.connectedDevices(language).hubDescription
        case .commandBar: return FeatureStrings.commandBar(language).hubDescription
        case .notch: return NotchStrings.notch(language).description
        // Each island module says what it does, not what the island is.
        case .notchCalendar: return FeatureStrings.notchCalendar(language).description
        case .notchAgents: return FeatureStrings.notchAgents(language).hubDescription
        case .notchNotifications: return FeatureStrings.notchNotifications(language).description
        case .notchGestures: return hub.descNotchGestures
        case .notchTimer: return FeatureStrings.notchActivities(language).timerDescription
        case .notchAccessories: return FeatureStrings.notchActivities(language).accessoryDescription
        case .notchLyrics: return FeatureStrings.notchMusicExtras(language).lyricsDescription
        case .notchDownloads: return FeatureStrings.notchFiles(language).downloadsDescription
        case .notchWatch: return FeatureStrings.notchWatch(language).description
        case .notchMascot: return hub.descNotchMascot
        case .notchLiveEqualizer: return FeatureStrings.notchMusicExtras(language).liveEqualizerDescription
        case .notchQueue: return FeatureStrings.notchMusicExtras(language).queueDescription
        }
    }
}

