// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import Foundation

/// The Settings pages. Lives here (Foundation-only) so the visibility rules
/// below and the unit tests can reason about pages without pulling SwiftUI in.
enum SettingsPage: Hashable, CaseIterable {
    case general, features, energy, monitor
    case mouse, switcher, dock, keyDebounce, cutPaste, autoQuit, cleaner, uninstaller, urlCleaner, homebrew, appUpdates, media, clipboard, windowLayout, shelf, quickTools, textSnippets, screenshot, radialMenu, nowPlaying
    case superKey
    case whatsAppDownloads
    case shortcuts, advanced, about, releaseNotes, support, fans, amdPower, amdOverclocking, sensors, dashboard, amdValidation
    case killProcess, notch, commandBar
    case portManager
    case quitProtection
}

/// Stable, non-localized identities for destinations inside shared Settings
/// pages. Raw values may be persisted or used by UI identifiers, so cases can
/// be added but never renamed.
///
/// RyzenStatus: upstream's page mapping is kept where the page exists here.
/// Dock tools have their own page as upstream, the recorder keeps a page of its own,
/// and the window maximizer has no section outside the Features hub yet.
/// Upstream's `fanControl` anchor is left out: fan control is the AMD layer's.
enum SettingsSectionAnchor: String, CaseIterable, Hashable {
    case panelConfiguration
    case mixer
    case audioPriority
    case musicBlocking
    case keepAwake
    case brightness
    case extraBrightness
    case bluetoothSleep
    case scrollDirection
    case scrollZoom
    case focusFollowsMouse
    case smoothScroll
    case linearScroll
    case mouseAcceleration
    case mouseNavigation
    case mouseButtonShortcuts
    case middleClick
    case mouseClickDebounce
    case switcher
    case dock
    case dockClick
    case spacesOrder
    case finderCutPaste
    case finderRename
    case clipboardHistory
    case pastePlain
    case quickLauncher
    case quickToggles
    case quitApps
    case screenshot
    case screenRecorder
    case colorPicker
    case screenOCR
    case micMute
    case cameraPreview
    case wallpaper
    case worldClock
    case scratchpad
    case cleaningMode
    case soundOutputSwitcher
    case keyboardBrightnessShortcuts
    case windowMaximizer

    var page: SettingsPage {
        switch self {
        case .panelConfiguration, .mixer, .audioPriority, .musicBlocking,
             .soundOutputSwitcher:
            return .general
        case .keepAwake, .brightness, .extraBrightness, .bluetoothSleep: return .energy
        case .scrollDirection, .scrollZoom, .focusFollowsMouse, .smoothScroll, .linearScroll, .mouseAcceleration, .mouseNavigation,
             .mouseButtonShortcuts, .middleClick, .mouseClickDebounce:
            return .mouse
        case .switcher: return .switcher
        case .dock, .dockClick, .spacesOrder: return .dock
        case .windowMaximizer: return .windowLayout
        case .finderCutPaste, .finderRename: return .cutPaste
        case .clipboardHistory, .pastePlain: return .clipboard
        case .quickLauncher, .quickToggles, .quitApps, .micMute, .cameraPreview, .wallpaper, .worldClock, .scratchpad,
             .cleaningMode:
            return .quickTools
        // Every tool that starts from the screen shares one page, as upstream.
        case .screenshot, .screenRecorder, .colorPicker, .screenOCR: return .screenshot
        case .keyboardBrightnessShortcuts: return .shortcuts
        }
    }
}

/// A feature's nearest configuration surface. The optional anchor distinguishes
/// a feature section on a shared page; nil means the page itself is the target.
struct FeatureSettingsDestination: Hashable {
    let page: SettingsPage
    let sectionAnchor: SettingsSectionAnchor?

    init(_ page: SettingsPage, sectionAnchor: SettingsSectionAnchor? = nil) {
        self.page = page
        self.sectionAnchor = sectionAnchor
    }

    var hasValidSectionAnchor: Bool {
        sectionAnchor == nil || sectionAnchor?.page == page
    }
}

struct SettingsDestinationRequest: Equatable {
    let id: UUID
    let destination: FeatureSettingsDestination
}

/// A one-shot request to reveal a specific feature's row inside the Features
/// hub, correlated with the destination request that carries it by sharing
/// the same request id.
struct SettingsFeatureTargetRequest: Equatable {
    let id: UUID
    let feature: AppFeature
}

/// Whether the Settings window can be seen. Closing it keeps the window and
/// its last page alive, so a page that animates on its own pauses on this
/// instead of drawing for nobody until the app quits. Kept apart from the
/// router so a covered or reopened window does not redraw every page.
final class SettingsWindowVisibility: ObservableObject {
    static let shared = SettingsWindowVisibility()
    @Published private(set) var isVisible = false

    func set(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
    }
}

extension AppFeature {
    /// The hub itself is the honest fallback for features without a separate
    /// configuration surface, but linking a row back to its current page would
    /// present a chevron that appears to do nothing.
    var hasNavigableSettingsDestination: Bool {
        settingsDestination.page != .features
    }

    /// Exhaustive by design: adding an AppFeature requires choosing its
    /// Settings destination before the project compiles. Mapped onto the
    /// pages RyzenStatus has (see `SettingsSectionAnchor`).
    var settingsDestination: FeatureSettingsDestination {
        switch self {
        case .switcher: return FeatureSettingsDestination(.switcher, sectionAnchor: .switcher)
        case .dockPreview: return FeatureSettingsDestination(.dock, sectionAnchor: .dock)
        case .dockClick: return FeatureSettingsDestination(.dock, sectionAnchor: .dockClick)
        case .spacesOrder: return FeatureSettingsDestination(.dock, sectionAnchor: .spacesOrder)
        case .windowMaximizer: return FeatureSettingsDestination(.features)
        case .windowLayout: return FeatureSettingsDestination(.windowLayout)
        case .autoQuit: return FeatureSettingsDestination(.autoQuit)
        case .quitWindowProtection: return FeatureSettingsDestination(.quitProtection)

        case .scrollInverter, .scrollHorizontal:
            return FeatureSettingsDestination(.mouse, sectionAnchor: .scrollDirection)
        case .scrollZoom:
            return FeatureSettingsDestination(.mouse, sectionAnchor: .scrollZoom)
        case .focusFollowsMouse:
            return FeatureSettingsDestination(.mouse, sectionAnchor: .focusFollowsMouse)
        case .smoothScroll:
            return FeatureSettingsDestination(.mouse, sectionAnchor: .smoothScroll)
        case .linearScroll:
            return FeatureSettingsDestination(.mouse, sectionAnchor: .linearScroll)
        case .mouseAcceleration:
            return FeatureSettingsDestination(.mouse, sectionAnchor: .mouseAcceleration)
        case .mouseNavigation:
            return FeatureSettingsDestination(.mouse, sectionAnchor: .mouseNavigation)
        case .mouseButtonShortcuts:
            return FeatureSettingsDestination(.mouse, sectionAnchor: .mouseButtonShortcuts)
        case .middleClick:
            return FeatureSettingsDestination(.mouse, sectionAnchor: .middleClick)
        case .mouseClickDebounce:
            return FeatureSettingsDestination(.mouse, sectionAnchor: .mouseClickDebounce)
        case .keyboardDebounce: return FeatureSettingsDestination(.keyDebounce)
        case .textSnippets: return FeatureSettingsDestination(.textSnippets)
        case .superKey: return FeatureSettingsDestination(.superKey)

        case .clipboardHistory:
            return FeatureSettingsDestination(.clipboard, sectionAnchor: .clipboardHistory)
        case .pastePlain:
            return FeatureSettingsDestination(.clipboard, sectionAnchor: .pastePlain)
        case .finderCutPaste:
            return FeatureSettingsDestination(.cutPaste, sectionAnchor: .finderCutPaste)
        case .finderRename:
            return FeatureSettingsDestination(.cutPaste, sectionAnchor: .finderRename)
        case .shelf: return FeatureSettingsDestination(.shelf)
        case .urlCleaner: return FeatureSettingsDestination(.urlCleaner)
        case .diskImageInstaller: return FeatureSettingsDestination(.features)

        case .mixer:
            return FeatureSettingsDestination(.general, sectionAnchor: .mixer)
        case .soundOutputSwitcher:
            return FeatureSettingsDestination(.general, sectionAnchor: .soundOutputSwitcher)
        case .audioPriority:
            return FeatureSettingsDestination(.general, sectionAnchor: .audioPriority)
        case .micMute:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .micMute)
        case .musicBlock:
            return FeatureSettingsDestination(.general, sectionAnchor: .musicBlocking)
        case .nowPlaying: return FeatureSettingsDestination(.nowPlaying)

        case .keepAwake:
            return FeatureSettingsDestination(.energy, sectionAnchor: .keepAwake)
        case .brightness:
            return FeatureSettingsDestination(.energy, sectionAnchor: .brightness)
        case .extraBrightness:
            return FeatureSettingsDestination(.energy, sectionAnchor: .extraBrightness)
        case .bluetoothSleep:
            return FeatureSettingsDestination(.energy, sectionAnchor: .bluetoothSleep)

        case .quickLauncher:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .quickLauncher)
        case .quickToggles:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .quickToggles)
        case .quitApps:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .quitApps)
        case .colorPicker:
            return FeatureSettingsDestination(.screenshot, sectionAnchor: .colorPicker)
        case .screenOCR:
            return FeatureSettingsDestination(.screenshot, sectionAnchor: .screenOCR)
        case .cleaningMode:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .cleaningMode)
        case .mediaTools: return FeatureSettingsDestination(.media)
        case .cleaner: return FeatureSettingsDestination(.cleaner)
        case .uninstaller: return FeatureSettingsDestination(.uninstaller)
        case .killProcess: return FeatureSettingsDestination(.killProcess)
        case .portManager: return FeatureSettingsDestination(.portManager)
        case .homebrew: return FeatureSettingsDestination(.homebrew)
        case .appUpdates: return FeatureSettingsDestination(.appUpdates)
        case .whatsAppDownloads: return FeatureSettingsDestination(.whatsAppDownloads)
        case .screenshot: return FeatureSettingsDestination(.screenshot, sectionAnchor: .screenshot)
        case .cameraPreview:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .cameraPreview)
        case .wallpaper:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .wallpaper)
        case .worldClock:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .worldClock)
        case .notch, .notchCalendar, .notchNotifications, .notchGestures, .notchTimer, .notchAccessories,
             .notchLyrics, .notchQueue, .notchLiveEqualizer, .notchDownloads, .notchAgents, .notchWatch,
             .notchMascot:
            return FeatureSettingsDestination(.notch)
        case .radialMenu: return FeatureSettingsDestination(.radialMenu)
        case .scratchpad:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .scratchpad)
        case .commandBar: return FeatureSettingsDestination(.commandBar)
        case .screenRecorder: return FeatureSettingsDestination(.screenshot, sectionAnchor: .screenRecorder)

        case .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
             .monitorInsights, .monitorAnalytics, .monitorEnergy, .monitorNetworkDetails, .connectedDevices:
            return FeatureSettingsDestination(.monitor)
        }
    }
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
                             .scrollHorizontal, .scrollZoom, .focusFollowsMouse, .linearScroll, .mouseAcceleration,
                             .mouseButtonShortcuts, .mouseClickDebounce]
        case .switcher: return [.switcher]
        case .dock: return [.dockPreview, .dockClick, .spacesOrder]
        case .windowLayout: return [.windowLayout, .windowMaximizer]
        case .autoQuit: return [.autoQuit]
        case .clipboard: return [.clipboardHistory, .pastePlain]
        case .cutPaste: return [.finderCutPaste, .finderRename]
        case .shelf: return [.shelf]
        case .media: return [.mediaTools]
        case .quickTools: return [.quickLauncher, .quickToggles, .quitApps, .micMute,
                                  .cameraPreview, .scratchpad, .wallpaper, .worldClock]
        case .urlCleaner: return [.urlCleaner]
        case .homebrew: return [.homebrew]
        case .appUpdates: return [.appUpdates]
        case .cleaner: return [.cleaner]
        case .whatsAppDownloads: return [.whatsAppDownloads]
        case .uninstaller: return [.uninstaller]
        case .keyDebounce: return [.keyboardDebounce]
        case .superKey: return [.superKey]
        case .textSnippets: return [.textSnippets]
        case .screenshot: return [.screenshot, .screenRecorder, .screenOCR, .colorPicker]
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

    /// Whether one of `page`'s features is among `activeFeatures`, the live
    /// users of a permission from `AppFeature.activeFeatures(using:)`. A page
    /// that several features share asks for the grant while any of them uses it.
    static func isPermissionNeeded(on page: SettingsPage,
                                   activeFeatures: [AppFeature]) -> Bool {
        features(for: page).contains(where: activeFeatures.contains)
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
        case .switcher: return .switcher
        case .dockPreview, .dockClick, .spacesOrder: return .dock
        case .windowLayout, .windowMaximizer: return .windowLayout
        case .autoQuit: return .autoQuit
        case .quitWindowProtection: return .quitProtection
        case .scrollInverter, .smoothScroll, .mouseNavigation, .middleClick, .scrollHorizontal, .scrollZoom,
             .focusFollowsMouse, .linearScroll, .mouseAcceleration, .mouseClickDebounce,
             .mouseButtonShortcuts:
            return .mouse
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
        case .quickLauncher, .quickToggles, .quitApps, .micMute, .cameraPreview,
             .scratchpad, .wallpaper, .worldClock:
            return .quickTools
        case .colorPicker, .screenOCR: return .screenshot
        case .mediaTools: return .media
        case .cleaner: return .cleaner
        case .uninstaller: return .uninstaller
        case .homebrew: return .homebrew
        case .appUpdates: return .appUpdates
        case .whatsAppDownloads: return .whatsAppDownloads
        case .killProcess: return .killProcess
        case .portManager: return .portManager
        case .commandBar: return .commandBar
        case .screenshot, .screenRecorder: return .screenshot
        case .radialMenu: return .radialMenu
        case .nowPlaying: return .nowPlaying
        // Every island module is a section of the island's page, and the
        // companion is one of its tabs.
        case .notch, .notchCalendar, .notchNotifications, .notchGestures, .notchTimer,
             .notchAccessories, .notchLyrics, .notchLiveEqualizer, .notchQueue, .notchDownloads,
             .notchAgents, .notchWatch, .notchMascot:
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
