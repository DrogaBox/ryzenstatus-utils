// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
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

/// Stable, non-localized identities for destinations inside shared Settings
/// pages. Raw values may be persisted or used by UI identifiers, so cases can
/// be added but never renamed.
///
/// RyzenStatus: upstream's page mapping is kept where the page exists here.
/// Dock tools live on the Switcher page, the recorder keeps a page of its own,
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
    case screenshot
    case screenRecorder
    case colorPicker
    case screenOCR
    case micMute
    case cameraPreview
    case wallpaper
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
        case .scrollDirection, .focusFollowsMouse, .smoothScroll, .linearScroll, .mouseAcceleration, .mouseNavigation,
             .middleClick, .mouseClickDebounce:
            return .mouse
        case .mouseButtonShortcuts: return .mouseButtonShortcuts
        case .switcher, .dock, .dockClick: return .switcher
        case .spacesOrder, .windowMaximizer: return .windowLayout
        case .finderCutPaste, .finderRename: return .cutPaste
        case .clipboardHistory, .pastePlain: return .clipboard
        case .quickLauncher, .quickToggles, .micMute, .cameraPreview, .wallpaper, .scratchpad, .cleaningMode,
             .colorPicker, .screenOCR:
            return .quickTools
        case .screenshot: return .screenshot
        case .screenRecorder: return .screenRecorder
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
        case .dockPreview: return FeatureSettingsDestination(.switcher, sectionAnchor: .dock)
        case .dockClick: return FeatureSettingsDestination(.switcher, sectionAnchor: .dockClick)
        case .spacesOrder: return FeatureSettingsDestination(.windowLayout, sectionAnchor: .spacesOrder)
        case .windowMaximizer: return FeatureSettingsDestination(.features)
        case .windowLayout: return FeatureSettingsDestination(.windowLayout)
        case .autoQuit: return FeatureSettingsDestination(.autoQuit)
        case .quitWindowProtection: return FeatureSettingsDestination(.quitProtection)

        case .scrollInverter, .scrollHorizontal:
            return FeatureSettingsDestination(.mouse, sectionAnchor: .scrollDirection)
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
        case .mouseButtonShortcuts: return FeatureSettingsDestination(.mouseButtonShortcuts)
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
        case .colorPicker:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .colorPicker)
        case .screenOCR:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .screenOCR)
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
        case .screenshot: return FeatureSettingsDestination(.screenshot)
        case .cameraPreview:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .cameraPreview)
        case .wallpaper:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .wallpaper)
        case .notch, .notchCalendar, .notchNotifications, .notchGestures, .notchTimer, .notchAccessories,
             .notchLyrics, .notchQueue, .notchLiveEqualizer, .notchDownloads, .notchWatch, .notchMascot:
            return FeatureSettingsDestination(.notch)
        case .radialMenu: return FeatureSettingsDestination(.radialMenu)
        case .scratchpad:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .scratchpad)
        case .commandBar: return FeatureSettingsDestination(.commandBar)
        case .screenRecorder: return FeatureSettingsDestination(.screenRecorder)

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
        case .monitor: return monitorFeatures
        case .mouse: return [.scrollInverter, .smoothScroll, .mouseNavigation, .middleClick,
                             .scrollHorizontal, .focusFollowsMouse, .linearScroll, .mouseAcceleration,
                             .mouseClickDebounce]
        case .switcher: return [.switcher, .dockPreview, .dockClick, .spacesOrder]
        case .windowLayout: return [.windowLayout]
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

    /// Whether one of `page`'s features is among `activeFeatures`, the live
    /// users of a permission from `AppFeature.activeFeatures(using:)`. A page
    /// that several features share asks for the grant while any of them uses it.
    static func isPermissionNeeded(on page: SettingsPage,
                                   activeFeatures: [AppFeature]) -> Bool {
        features(for: page).contains(where: activeFeatures.contains)
    }
}
