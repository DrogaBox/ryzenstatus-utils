// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Carbon.HIToolbox
import Foundation

/// Every UserDefaults key used by the app, in one place.
enum DefaultsKey {}

/// Bump `currentFeatureSet` when first-run feature defaults need a quiet marker.
enum OnboardingInfo {
    // 2: system monitor, configurable panel and menu bar metrics.
    // 3: app languages and support settings.
    // 4: navigable menu panel sections.
    static let currentFeatureSet = 4
}

enum DockPreviewIntroInfo {
    static let releaseVersion = "3.0.4"
}

/// The one-time tour of a release's headline features, shown right after the
/// update. Each row deep links to the exact Settings page or opens the tool
/// itself, so a new feature is one click from being tried instead of buried.
enum UpdateHighlightsInfo {
    /// The single release whose first launch shows the tour; any other
    /// version never shows it. Bump deliberately for releases with headline
    /// features worth a tour.
    static let releaseVersion = "3.1.14"

    static func shouldShow(appVersion: String, lastSeenVersion: String?) -> Bool {
        appVersion == releaseVersion && lastSeenVersion != releaseVersion
    }
}

enum SupportUpdateIntroInfo {
    /// The single release whose first launch shows the update intro. It used
    /// to track AppInfo.version, which re-showed the ask on every update; now a
    /// release only shows it when this constant is deliberately bumped.
    static let releaseVersion = "3.1.13"
    static let installCommand = "brew install --cask ryzenstatus"
    static let migrationCommand = "brew untap --force ryzenstatus/tap"

    static func shouldShow(appVersion: String, lastSeenVersion: String?) -> Bool {
        appVersion == releaseVersion && lastSeenVersion != releaseVersion
    }
}

enum SupportUpdateIntroStep: Equatable {
    case homebrew
    case community
    case support

    var next: SupportUpdateIntroStep? {
        switch self {
        case .homebrew: return .community
        case .community: return .support
        case .support: return nil
        }
    }

    var previous: SupportUpdateIntroStep? {
        switch self {
        case .homebrew: return nil
        case .community: return .homebrew
        case .support: return .community
        }
    }
}

enum KeepAwakeIconTint: String, CaseIterable, Identifiable {
    case orange, green, blue, purple, pink, none

    var id: String { rawValue }

    static var current: KeepAwakeIconTint {
        Defaults.sanitizedKeepAwakeIconTint(
            UserDefaults.standard.string(forKey: DefaultsKey.keepAwakeIconTint)
        )
    }

    func title(_ strings: Strings) -> String {
        switch self {
        case .orange: return strings.keepAwakeIconTintOrange
        case .green: return strings.keepAwakeIconTintGreen
        case .blue: return strings.keepAwakeIconTintBlue
        case .purple: return strings.keepAwakeIconTintPurple
        case .pink: return strings.keepAwakeIconTintPink
        case .none: return strings.keepAwakeIconTintNone
        }
    }
}

enum KeepAwakeActiveIcon: String, CaseIterable, Identifiable {
    case ryzenstatus, coffee, eye, moon, light

    var id: String { rawValue }

    static var current: KeepAwakeActiveIcon {
        Defaults.sanitizedKeepAwakeActiveIcon(
            UserDefaults.standard.string(forKey: DefaultsKey.keepAwakeActiveIcon)
        )
    }

    var systemSymbolName: String? {
        switch self {
        case .ryzenstatus: return nil
        case .coffee: return "cup.and.saucer.fill"
        case .eye: return "eye.fill"
        case .moon: return "moon.fill"
        case .light: return "lightbulb.fill"
        }
    }

    /// Nudge down the menu bar canvas, in points. Symbols carrying their mass
    /// above the shape's middle — steam over a cup, a bulb over its base — read
    /// as sitting high when their ink is centered geometrically.
    var menuBarDrop: CGFloat {
        switch self {
        case .coffee: return 1
        case .light: return 0.5
        case .ryzenstatus, .eye, .moon: return 0
        }
    }

    func title(_ strings: Strings) -> String {
        switch self {
        case .ryzenstatus: return strings.keepAwakeActiveIconRyzenStatus
        case .coffee: return strings.keepAwakeActiveIconCoffee
        case .eye: return strings.keepAwakeActiveIconEye
        case .moon: return strings.keepAwakeActiveIconMoon
        case .light: return strings.keepAwakeActiveIconLight
        }
    }
}

/// Thumbnail size for the app switcher and Dock preview, scaled from one user
/// preference so both grow together. Captures scale by the same factor, so
/// larger previews stay sharp.
enum PreviewSizing {
    static func sanitized(_ value: String) -> String {
        Defaults.allowedPreviewSizes.contains(value) ? value : "normal"
    }

    static func scale(for value: String) -> CGFloat {
        switch sanitized(value) {
        case "small": return 0.75
        case "large": return 1.4
        case "xlarge": return 1.8
        default: return 1.0
        }
    }

    static var scale: CGFloat {
        scale(for: UserDefaults.standard.string(forKey: DefaultsKey.previewSize) ?? "normal")
    }

    /// The app switcher's own size. Its key is registered and migrated from
    /// Dock Preview's together with the switcher port; until then an unset
    /// value follows Dock Preview's, which is what both share today.
    static var switcherScale: CGFloat {
        scale(for: UserDefaults.standard.string(forKey: DefaultsKey.switcherPreviewSize)
            ?? UserDefaults.standard.string(forKey: DefaultsKey.previewSize) ?? "normal")
    }
}

enum Defaults {
    static let finderBundleIdentifier = "com.apple.finder"
    /// Continuity / Calls on Mac. Quitting Phone when its UI flickers window-less
    /// during an incoming relay disconnects the call. Kept in the mandatory
    /// exception list even when Phone.app is absent; the settings UI hides the
    /// row until the app is installed.
    static let phoneBundleIdentifier = "com.apple.mobilephone"
    static let mandatoryAutoQuitExceptionBundleIDs = [
        finderBundleIdentifier,
        phoneBundleIdentifier,
    ]

    static var dockPreviewBackgroundOpacity: Double {
        get {
            let val = UserDefaults.standard.double(forKey: DefaultsKey.dockPreviewBackgroundOpacity)
            return val == 0 ? 0.85 : max(0.40, min(1.0, val))
        }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.dockPreviewBackgroundOpacity)
        }
    }

    static let allowedDurations = [0, 15, 30, 60, 120, 240, 480]
    static let allowedKeepAwakeMouseJiggleIntervals = [1, 2, 5, 10, 15]
    static let allowedBatteryLimits = [0, 5, 10, 15, 20]
    static let allowedMonitorIntervals: [Double] = [0.5, 0.7, 1.0, 2.0, 5.0]
    static let defaultKeyboardDebounceWindowMs = 5
    static let defaultSnippetSoundName = "Tink"
    static let allowedKeyboardDebounceWindowRange = 0...500
    /// Stepper increment for the keyboard debounce window. Kept at 1 ms so
    /// magnetic-keyboard users can pick values below the old 5 ms UI step
    /// without changing the stored range.
    static let keyboardDebounceWindowStep = 1
    static let defaultMouseClickDebounceWindowMs = 25
    static let allowedMouseClickDebounceWindowRange = 5...100
    static let allowedMenuBarPresets = ["dense"]
    static let allowedMenuBarMetricSpacings = ["standard", "compact"]
    static let allowedMenuBarMetricAppearances = ["values", "bars", "pie", "sparkline", "histogram", "classic"]
    static let defaultMenuBarMetricOrder = [
        "cpu", "cpuTemperature", "cpuPower", "cpuFrequency", "cpuTempPower",
        "gpu", "gpuTemperature", "gpuPower", "gpuTempPower",
        "memory",
        "battery", "batteryTime", "batteryTemperature", "peripheralBattery",
        "network", "diskUsage", "diskActivity", "connectedDevices", "power",
    ]
    static let allowedMenuBarLabelStyles = ["compact", "classic"]
    static let allowedMenuBarMemoryStyles = ["dot", "percent", "both"]
    static let allowedMonitorMemoryMetrics = ["used", "app"]
    static let allowedPreviewSizes = ["small", "normal", "large", "xlarge"]
    static let allowedClipboardHistoryLimits = [20, 50, 100, 250, 500, 1_000, 10_000, 0]
    static let allowedClipboardHistoryRetentionDays = [1, 7, 30, 90, 365, 0]
    static let allowedClipboardAutoClearDelayRange = 5...3_600
    static let defaultClipboardAutoClearDelay = 20
    static let allowedClipboardMenuBarPreviewLengthRange = 5...50
    static let defaultClipboardMenuBarPreviewLength = 20
    static let allowedMonitorAlertCooldowns = [2, 5, 15, 30, 60]

    static let registeredDefaults: [String: Any] = [
        DefaultsKey.clamshellPreferred: false,
        DefaultsKey.appearance: AppAppearance.fallback.rawValue,
        DefaultsKey.liquidGlassEnabled: false,
        DefaultsKey.mouseSpacesGestureEnabled: false,
        DefaultsKey.mouseSpacesGestureButton: 0,
        DefaultsKey.whatsAppDownloadsEnabled: false,
        DefaultsKey.diskEjectExcludedVolumes: [String](),
        // Disk image installer.
        DefaultsKey.diskImageInstallerUseUserApplications: false,
        DefaultsKey.diskImageInstallerTrashesDownload: true,
        DefaultsKey.diskImageInstallerRevealsApp: false,
        // Quit/close protection.
        DefaultsKey.quitProtectionQuitEnabled: false,
        DefaultsKey.quitProtectionQuitMode: QuitProtectionMode.hold.rawValue,
        DefaultsKey.quitProtectionQuitHoldDurationMs: QuitProtectionSupport.defaultHoldDurationMilliseconds,
        DefaultsKey.quitProtectionQuitDoubleIntervalMs: QuitProtectionSupport.defaultDoublePressIntervalMilliseconds,
        DefaultsKey.quitProtectionQuitExtraModifier: QuitProtectionExtraModifier.shift.rawValue,
        DefaultsKey.quitProtectionQuitScope: QuitProtectionScope.all.rawValue,
        DefaultsKey.quitProtectionQuitExceptions: [String](),
        DefaultsKey.quitProtectionQuitShowFeedback: true,
        DefaultsKey.quitProtectionCloseEnabled: false,
        DefaultsKey.quitProtectionCloseMode: QuitProtectionMode.hold.rawValue,
        DefaultsKey.quitProtectionCloseHoldDurationMs: QuitProtectionSupport.defaultHoldDurationMilliseconds,
        DefaultsKey.quitProtectionCloseDoubleIntervalMs: QuitProtectionSupport.defaultDoublePressIntervalMilliseconds,
        DefaultsKey.quitProtectionCloseExtraModifier: QuitProtectionExtraModifier.shift.rawValue,
        DefaultsKey.quitProtectionCloseScope: QuitProtectionScope.all.rawValue,
        DefaultsKey.quitProtectionCloseExceptions: [String](),
        DefaultsKey.quitProtectionCloseShowFeedback: true,
        // Wallpaper gallery.
        DefaultsKey.panelShowWallpaper: true,
        DefaultsKey.wallpaperApplyAllDisplays: true,
        DefaultsKey.wallpaperFilter: "all",
        // World clocks.
        DefaultsKey.panelShowWorldClock: true,
        DefaultsKey.worldClockZones: "",
        DefaultsKey.whatsAppDownloadsAutomaticEnabled: false,
        DefaultsKey.whatsAppDownloadsCategories: "image,video,audio",
        DefaultsKey.whatsAppDownloadsRetentionDays: 7,
        DefaultsKey.whatsAppDownloadsNotify: true,
        DefaultsKey.whatsAppDownloadsIncludeExisting: false,
        DefaultsKey.whatsAppDownloadsAutomaticStartDate: 0.0,
        DefaultsKey.whatsAppDownloadsLastAutoRun: 0.0,
        DefaultsKey.whatsAppDownloadsLastCleanup: 0.0,
        DefaultsKey.whatsAppDownloadsLastCleanupCount: 0,
        DefaultsKey.whatsAppDownloadsLastCleanupBytes: 0,
        DefaultsKey.whatsAppDownloadsLastCleanupFailed: 0,
        DefaultsKey.whatsAppDownloadsLastCleanupAutomatic: false,
        DefaultsKey.whatsAppDownloadsExclusions: [String](),
        DefaultsKey.whatsAppDownloadsAccessConfirmed: false,
        DefaultsKey.whatsAppOrganizerEnabled: false,
        DefaultsKey.whatsAppOrganizerDestinationPath: "",
        DefaultsKey.whatsAppOrganizerDelayMinutes: 5,
        DefaultsKey.whatsAppOrganizerCategories: "image,video,audio,document,archive,other",
        DefaultsKey.whatsAppOrganizerLayout: "flat",
        DefaultsKey.whatsAppOrganizerDuplicateAction: "trashNew",
        DefaultsKey.whatsAppOrganizerRecords: Data(),
        DefaultsKey.whatsAppOrganizerUndoTransaction: Data(),
        DefaultsKey.whatsAppOrganizerLastRun: 0.0,
        DefaultsKey.whatsAppOrganizerLastMoved: 0,
        DefaultsKey.whatsAppOrganizerLastDuplicates: 0,
        DefaultsKey.whatsAppOrganizerLastFailed: 0,
        DefaultsKey.defaultDuration: 0,
        DefaultsKey.batteryLimit: 10,
        DefaultsKey.keepAwakeAutoStart: false,
        DefaultsKey.keepAwakeRightClickToggle: false,
        DefaultsKey.keepAwakeAllowDisplaySleep: false,
        DefaultsKey.keepAwakeExternalDisplay: false,
        DefaultsKey.keepAwakeConnectedToPower: false,
        DefaultsKey.keepAwakeMouseJiggleEnabled: false,
        DefaultsKey.keepAwakeMouseJiggleInterval: 5,
        DefaultsKey.hotkeyEnabled: true,
        DefaultsKey.launchAtLoginWanted: false,
        DefaultsKey.keepAwakeShortcut: "control+option+command:40",
        DefaultsKey.keepAwakeIconTint: KeepAwakeIconTint.orange.rawValue,
        DefaultsKey.keepAwakeActiveIcon: KeepAwakeActiveIcon.ryzenstatus.rawValue,
        DefaultsKey.showCountdown: false,
        DefaultsKey.scrollInverterEnabled: false,
        DefaultsKey.scrollInverterHorizontalEnabled: false,
        DefaultsKey.smoothScrollEnabled: false,
        DefaultsKey.smoothScrollStep: 40,
        // Mouse extras ported from upstream: every switch starts off.
        DefaultsKey.scrollHorizontalEnabled: false,
        DefaultsKey.scrollHorizontalModifier: ScrollHorizontalModifier.shift.rawValue,
        DefaultsKey.focusFollowsMouseEnabled: false,
        DefaultsKey.focusFollowsMouseDelay: 250, // FocusFollowsMouseSupport.defaultDelayMilliseconds
        DefaultsKey.focusFollowsMouseRaise: true,
        DefaultsKey.focusFollowsMouseWaitForStop: true,
        DefaultsKey.linearScrollEnabled: false,
        DefaultsKey.linearScrollLines: ScrollWheelSupport.defaultLinesPerNotch,
        DefaultsKey.mouseAccelerationDisabled: false,
        DefaultsKey.mouseClickDebounceEnabled: false,
        DefaultsKey.mouseClickDebounceWindowMs: defaultMouseClickDebounceWindowMs,
        DefaultsKey.spacesOrderEnabled: false,
        DefaultsKey.panelControlFocusFollowsMouse: true,
        DefaultsKey.panelControlLinearScroll: true,
        DefaultsKey.panelControlMouseAcceleration: true,
        DefaultsKey.panelControlMouseClickDebounce: true,
        DefaultsKey.panelControlSpacesOrder: true,
        DefaultsKey.mouseNavigationEnabled: false,
        DefaultsKey.switcherEnabled: true,
        DefaultsKey.switcherShortcut: "command:48",
        DefaultsKey.switcherWindowShortcut: GlobalShortcut.switcherWindowDefault.storageValue,
        DefaultsKey.switcherIconRowMode: false,
        DefaultsKey.switcherSimpleMode: false,
        DefaultsKey.switcherMergeTabs: false,
        DefaultsKey.switcherShowWindowlessFinder: true,
        DefaultsKey.switcherWindowlessApps: SwitcherWindowlessApps.fallback.rawValue,
        DefaultsKey.switcherAppRules: [String: String](),
        DefaultsKey.windowPreviewExcludedApps: [String](),
        DefaultsKey.switcherCurrentSpaceOnly: false,
        DefaultsKey.switcherSearchPinEnabled: false, // S pins the search field open, off by default
        DefaultsKey.dockPreviewEnabled: false,
        DefaultsKey.dockPreviewBackgroundOpacity: 0.85,
        DefaultsKey.dockPreviewOpenDelay: 200,
        DefaultsKey.dockClickMinimize: false,
        DefaultsKey.dockClickHide: false,
        DefaultsKey.dockClickCycleWindows: false,
        DefaultsKey.middleClickEnabled: false,
        DefaultsKey.middleClickTapFingers: 0,
        DefaultsKey.previewSize: "normal",
        DefaultsKey.autoCheckUpdates: true,
        DefaultsKey.checkPrereleases: false,
        DefaultsKey.releaseNotesOnUpdate: true,
        DefaultsKey.showReleaseNotesBeforeUpdate: true,
        DefaultsKey.updateShowcaseIntroVersion: "",
        DefaultsKey.updateShowcaseMediaOverride: "",
        DefaultsKey.mixerShowFinder: true,
        DefaultsKey.mixerLowerVolumeOnHeadphonesDisconnect: false,
        DefaultsKey.mixerHeadphonesDisconnectVolumePercent: defaultMixerHeadphonesDisconnectVolumePercent,
        DefaultsKey.soundOutputSwitcherEnabled: false,
        DefaultsKey.soundOutputSwitcherShortcut: GlobalShortcut.soundOutputSwitcherDefault.storageValue,
        // Upstream ships audio priority as an opt-in feature with both lists
        // on. Here every feature is installed by default, so the automatic
        // switching itself stays off until the user turns a list on: an
        // update must never start changing the audio devices on its own.
        DefaultsKey.audioPriorityOutputEnabled: false,
        DefaultsKey.audioPriorityInputEnabled: false,
        DefaultsKey.audioPriorityOutputUIDs: [String](),
        DefaultsKey.audioPriorityInputUIDs: [String](),
        DefaultsKey.audioPriorityDeviceNames: [String: String](),
        DefaultsKey.finderRenameEnabled: false,
        DefaultsKey.finderRenameShortcut: GlobalShortcut.finderRenameDefault.storageValue,
        // Finder never benefits from being "quit" (it just relaunches), so
        // it's excepted out of the box.
        DefaultsKey.autoQuitExceptions: mandatoryAutoQuitExceptionBundleIDs,
        // When the shelf is on, the shake gesture is on too (still toggleable).
        DefaultsKey.shelfShortcutEnabled: true,
        DefaultsKey.shelfShortcut: "control+option+command:2",
        DefaultsKey.shelfShakeToOpen: true,
        // On by default (owner's call): it costs nothing until the shelf itself
        // is on, and then the shelf lives handily under the menu bar icon.
        DefaultsKey.shelfDropZoneEnabled: true,
        // Closing after a drop is new behavior, so it arrives OFF for people
        // who already rely on the panel staying put; removing after a drop
        // keeps the value shipped releases always had.
        DefaultsKey.shelfCloseAfterDrop: false,
        DefaultsKey.shelfRemoveAfterDrop: true,
        DefaultsKey.shelfAutomaticExclusions: [String](),
        DefaultsKey.extraBrightnessEnabled: false,
        DefaultsKey.extraBrightnessLevel: 100,
        DefaultsKey.bluetoothSleepEnabled: false,
        DefaultsKey.bluetoothEnabled: true,
        DefaultsKey.bluetoothSleepRestoreOnWake: true,
        DefaultsKey.bluetoothSleepRestorePending: false,
        DefaultsKey.brightnessControlEnabled: false,
        DefaultsKey.brightnessKeysEnabled: false,
        DefaultsKey.brightnessOSDEnabled: false,
        DefaultsKey.musicBlockEnabled: false,
        DefaultsKey.musicBlockReplacementPath: "",
        DefaultsKey.nowPlayingEnabled: false,
        DefaultsKey.nowPlayingMenuBarText: true,
        DefaultsKey.nowPlayingMenuBarMode: NowPlayingMenuBarMode.artistSong.rawValue,
        DefaultsKey.nowPlayingMenuBarProgress: false,
        DefaultsKey.nowPlayingMarquee: false,
        DefaultsKey.nowPlayingMarqueeSlide: true,
        DefaultsKey.nowPlayingArtworkSize: 140.0,
        DefaultsKey.nowPlayingUnloadWhenHidden: true,
        DefaultsKey.nowPlayingPreferredProvider: NowPlayingProvider.auto.rawValue,
        DefaultsKey.nowPlayingOpenInApp: true,
        DefaultsKey.nowPlayingShowArtwork: true,
        DefaultsKey.nowPlayingArtworkAnimation: true,
        DefaultsKey.nowPlayingMiniMode: false,
        DefaultsKey.nowPlayingDetachedOnTop: true,
        DefaultsKey.nowPlayingDetachedSize: 1,
        DefaultsKey.nowPlayingDetailsPane: false,
        DefaultsKey.nowPlayingAnimatedArtwork: true,
        DefaultsKey.nowPlayingAnimatedArtworkQuality: 0,
        DefaultsKey.nowPlayingTheme: NowPlayingThemeStyle.artworkAdaptive.rawValue,
        DefaultsKey.nowPlayingArtworkColorIntensity: 1.0,
        DefaultsKey.nowPlayingArtworkBlend: 0.28,
        DefaultsKey.nowPlayingPopupShortcut: GlobalShortcut.nowPlayingPopupDefault.storageValue,
        DefaultsKey.nowPlayingPopupShortcutEnabled: true,
        DefaultsKey.nowPlayingDetachedShortcut: GlobalShortcut.nowPlayingDetachedDefault.storageValue,
        DefaultsKey.nowPlayingDetachedShortcutEnabled: true,
        DefaultsKey.panelShowNowPlaying: true,
        DefaultsKey.cleanerScheduleFrequency: "off",
        DefaultsKey.cleanerScheduleHour: 9,
        DefaultsKey.cleanerScheduleMinute: 0,
        DefaultsKey.cleanerScheduleWeekday: 2,
        DefaultsKey.cleanerScheduleNotify: true,
        DefaultsKey.cleanerBadgeSeen: false,
        DefaultsKey.cleanerLastAutoRun: 0.0,
        DefaultsKey.cleanerLastAutoFreed: 0,
        DefaultsKey.cleanerLastAutoFailed: 0,
        DefaultsKey.cleanerScreenshotAgeDays: CleanerPolicy.defaultScreenshotAgeDays,
        DefaultsKey.killProcessCommandBarEnabled: true,
        DefaultsKey.killProcessGroupRelated: true,
        DefaultsKey.killProcessSortBy: "cpu",
        DefaultsKey.killProcessSortAscending: false,
        DefaultsKey.urlCleanerEnabled: false,
        DefaultsKey.mouseButtonShortcutsEnabled: false,
        DefaultsKey.superKeyEnabled: false,
        DefaultsKey.superKeySoloAction: SuperKeySoloAction.none.rawValue,
        DefaultsKey.superKeyMappingApplied: false,
        DefaultsKey.snippetLibraryEnabled: false,
        DefaultsKey.snippetLibraryShortcut: GlobalShortcut.snippetLibraryDefault.storageValue,
        DefaultsKey.textSnippetsEnabled: false,
        DefaultsKey.snippetSoundEnabled: false,
        DefaultsKey.snippetSoundName: defaultSnippetSoundName,
        DefaultsKey.radialMenuEnabled: false,
        DefaultsKey.radialMenuShortcut: GlobalShortcut.radialMenuDefault.storageValue,
        DefaultsKey.radialMenuAtPointer: true,
        DefaultsKey.radialMenuMouseButton: RadialMenuMouseTrigger.off.rawValue,
        DefaultsKey.windowMaximizeEnabled: false,
        DefaultsKey.keyboardDebounceEnabled: false,
        DefaultsKey.keyboardDebounceWindowMs: defaultKeyboardDebounceWindowMs,
        DefaultsKey.keyboardDebounceKeyWindows: "",
        DefaultsKey.panelUtilityCleaning: true,
        DefaultsKey.notchEnabled: false,
        DefaultsKey.notchDisplay: "automatic",
        DefaultsKey.notchSilhouette: "capsule",
        DefaultsKey.notchCapsuleFitWidth: 0.0,
        DefaultsKey.notchCapsuleFitHeight: 0.0,
        DefaultsKey.notchCapsuleFitDrop: 0.0,
        DefaultsKey.notchOpenOnHover: false,
        DefaultsKey.notchHideInFullscreen: false,
        DefaultsKey.notchHideUntilHover: false,
        DefaultsKey.notchCoversMenus: true,
        DefaultsKey.notchLowBatteryTint: false,
        DefaultsKey.notchLowBatteryThreshold: 10,
        DefaultsKey.notchLowBatteryEarly: false,
        DefaultsKey.notchLowBatteryEarlyThreshold: 20,
        DefaultsKey.notchLowBatteryMenuBar: true,
        DefaultsKey.notchHoverDelay: 0.25,
        DefaultsKey.notchCloseDelay: 0.3,
        DefaultsKey.notchReturnHome: false,
        DefaultsKey.notchHomeModule: "controls",
        DefaultsKey.notchOpensActivity: true,
        DefaultsKey.notchHiddenModules: "",
        DefaultsKey.notchModuleOrder: "",
        DefaultsKey.notchQuickAccessLayout: Data(),
        DefaultsKey.notchVolume: true,
        DefaultsKey.notchMicrophone: true,
        DefaultsKey.notchBrightness: true,
        DefaultsKey.notchBattery: true,
        DefaultsKey.notchClipboard: true,
        DefaultsKey.notchClipboardWindow: true,
        DefaultsKey.notchCapture: true,
        DefaultsKey.notchTrackChange: true,
        DefaultsKey.notchMusicActivity: false,
        DefaultsKey.notchShowInCaptures: true,
        DefaultsKey.notchLockScreen: false,
        DefaultsKey.notchLockSounds: false,
        DefaultsKey.notchMascotEnabled: false,
        DefaultsKey.notchMascotVisits: true,
        DefaultsKey.notchMascotReactions: true,
        DefaultsKey.notchMascotStyle: "minimal",
        DefaultsKey.notchMascotShape: "ball",
        DefaultsKey.notchMascotPalette: "pearl",
        DefaultsKey.notchMascotSide: "left",
        DefaultsKey.notchMascotVisitFrequency: "normal",
        DefaultsKey.notchMascotHidesWhenIdle: true,
        DefaultsKey.notchMascotPerch: true,
        DefaultsKey.notchMascotDesktop: false,
        DefaultsKey.notchMascotExcursions: true,
        DefaultsKey.notchMascotDesktopFriend: "",
        DefaultsKey.notchMascotDesktopPlay: true,
        DefaultsKey.notchMascotFriendAccessory: "",
        DefaultsKey.notchMascotAutomatic: true,
        DefaultsKey.notchMascotAutoLoad: true,
        DefaultsKey.notchMascotAutoMusic: true,
        DefaultsKey.notchMascotAutoRest: true,
        DefaultsKey.notchMascotAutoCoffee: true,
        DefaultsKey.notchMascotAutoNetwork: true,
        DefaultsKey.notchMascotAutoEvents: true,
        DefaultsKey.notchMascotAutoAntics: true,
        DefaultsKey.notchMascotAccessory: "none",
        DefaultsKey.notchMascotName: "",
        DefaultsKey.notchMascotSeasonal: true,
        DefaultsKey.notchMascotForm: "auto",
        DefaultsKey.notchMascotSpeech: true,
        DefaultsKey.notchMascotHardware: true,
        DefaultsKey.notchCommandBar: true,
        DefaultsKey.notchCommandBarStyle: "droplet",
        DefaultsKey.notchHideInCaptures: false,
        DefaultsKey.notchTimerEnabled: true,
        DefaultsKey.notchTimerMode: "timer",
        DefaultsKey.notchTimerMinutes: 15,
        DefaultsKey.notchTimerSoundEnabled: true,
        DefaultsKey.notchHideTimerCountdown: false,
        DefaultsKey.notchPomodoroFocusMinutes: 25,
        DefaultsKey.notchPomodoroShortBreakMinutes: 5,
        DefaultsKey.notchPomodoroLongBreakMinutes: 15,
        DefaultsKey.notchPomodoroLongBreakInterval: 4,
        DefaultsKey.notchPomodoroTotalSessions: 4,
        DefaultsKey.notchCameraEnabled: true,
        DefaultsKey.notchAccessoriesEnabled: true,
        DefaultsKey.notchCalendarEnabled: true,
        DefaultsKey.notchCalendarCountdown: false,
        DefaultsKey.notchCalendarTimeLeft: false,
        DefaultsKey.notchCalendarWeekNumbers: false,
        DefaultsKey.notchCalendarExcluded: [String](),
        DefaultsKey.notchAgentsEnabled: false,
        DefaultsKey.notchLyricsEnabled: true,
        DefaultsKey.notchLyricsOnline: false,
        DefaultsKey.notchLiveEqualizer: false,
        DefaultsKey.notchMusicVisualizer: "titleThenVisualizer", // NotchMusicVisualizerMode.titleThenVisualizer
        DefaultsKey.notchMusicVisualizerStyle: "retro", // NotchMusicVisualizerStyle.retro
        DefaultsKey.notchMusicTitleSeconds: 5,
        DefaultsKey.notchMascotDances: true,
        DefaultsKey.notchQueueEnabled: true,
        DefaultsKey.notchDownloadsEnabled: true,
        DefaultsKey.notchWatchEnabled: true,
        DefaultsKey.notchWatchSound: true,
        DefaultsKey.notchWatchCondition: "changes",
        DefaultsKey.notchGesturesEnabled: true,
        DefaultsKey.notchHoverExpands: false,
        DefaultsKey.notchKeyboardLight: false,
        DefaultsKey.notchHidesMenuBarIcon: false,
        DefaultsKey.notchKeepAwakeActivity: true,
        DefaultsKey.notchNotificationsEnabled: true,
        DefaultsKey.notchDismissNativeNotifications: false,
        DefaultsKey.panelControlNotch: true,
        DefaultsKey.uninstallerCommandBarEnabled: false,
        DefaultsKey.commandBarEnabled: false,
        DefaultsKey.commandBarShortcutEnabled: false,
        DefaultsKey.commandBarCompactMode: false,
        DefaultsKey.commandBarASCIILayoutEnabled: false,
        DefaultsKey.commandBarDisabledSources: "",
        DefaultsKey.commandBarAliases: "",
        DefaultsKey.commandBarPins: "",
        DefaultsKey.commandBarHidden: "",
        DefaultsKey.commandBarFileScopes: "",
        DefaultsKey.commandBarFileIgnores: "",
        DefaultsKey.commandBarShortcut: GlobalShortcut.commandBarDefault.storageValue,
        DefaultsKey.commandBarPositionOffset: "",
        DefaultsKey.commandBarEmojiSkinTone: "",
        DefaultsKey.panelUtilityCommandBar: true,
        DefaultsKey.panelUtilityPortManager: true,
        DefaultsKey.panelUtilityURLCleaner: true,
        DefaultsKey.panelUtilityUninstaller: true,
        DefaultsKey.panelUtilityCleaner: true,
        DefaultsKey.panelUtilityHomebrew: true,
        DefaultsKey.panelUtilityAppUpdates: true,
        // The list itself costs nothing until it is opened; only the
        // background check keeps a timer, so it starts off.
        DefaultsKey.appUpdatesCheckFrequency: AppUpdatesSupport.CheckFrequency.off.rawValue,
        DefaultsKey.appUpdatesIncludeHomebrewApps: true,
        DefaultsKey.appUpdatesIncludeAppStore: true,
        DefaultsKey.appUpdatesNotify: true,
        DefaultsKey.appUpdatesLastCheck: 0.0,
        DefaultsKey.appUpdatesLastCount: 0,
        DefaultsKey.panelUtilityMedia: true,
        DefaultsKey.panelUtilityClipboard: true,
        DefaultsKey.panelUtilityWindowLayout: true,
        DefaultsKey.panelControlMouseScroll: true,
        DefaultsKey.panelControlMouseNavigation: true,
        DefaultsKey.panelControlSwitcher: true,
        DefaultsKey.panelControlDockPreview: true,
        DefaultsKey.panelControlCutPaste: true,
        DefaultsKey.panelControlAutoQuit: true,
        DefaultsKey.panelControlShelf: true,
        DefaultsKey.panelControlWindowMaximize: true,
        DefaultsKey.panelControlKeyDebounce: true,
        DefaultsKey.panelControlDockClick: true,
        DefaultsKey.panelControlDockClickHide: true,
        DefaultsKey.panelControlDockClickCycle: true,
        DefaultsKey.panelControlMiddleClick: true,
        DefaultsKey.panelControlTextSnippets: true,
        DefaultsKey.panelControlSuperKey: true,
        DefaultsKey.panelControlRadialMenu: true,
        DefaultsKey.panelControlWindowsExpanded: false,
        DefaultsKey.panelControlInputExpanded: false,
        DefaultsKey.panelControlFilesExpanded: false,
        DefaultsKey.panelShowAmdPower: true,
        DefaultsKey.panelShowKeepAwake: true,
        DefaultsKey.panelShowBrightness: true,
        DefaultsKey.panelShowUtilities: true,
        DefaultsKey.panelShowControls: true,
        DefaultsKey.panelShowToggles: true,
        DefaultsKey.panelToggleDarkMode: true,
        DefaultsKey.panelToggleEmptyTrash: true,
        DefaultsKey.panelToggleEjectDisks: true,
        DefaultsKey.panelToggleHiddenFiles: true,
        DefaultsKey.panelToggleDesktopIcons: true,
        DefaultsKey.panelToggleLockScreen: true,
        DefaultsKey.panelToggleDisplayOff: true,
        DefaultsKey.panelToggleScreenSaver: true,
        // Menu bar metrics start off (the icon stays clean) and are opt-in.
        // The panel shows every monitoring block by default; users hide what
        // they don't want.
        DefaultsKey.monitorInterval: 1.0,
        DefaultsKey.temperatureUnit: TemperatureUnit.celsius.rawValue,
        DefaultsKey.menuBarCPU: true,
        DefaultsKey.menuBarGPU: true,
        DefaultsKey.menuBarCPUPower: false,
        DefaultsKey.menuBarGPUPower: false,
        DefaultsKey.menuBarCPUFrequency: false,
        DefaultsKey.menuBarMemory: true,
        DefaultsKey.menuBarNetwork: true,
        DefaultsKey.menuBarCPUTemperature: false,
        DefaultsKey.menuBarGPUTemperature: false,
        DefaultsKey.menuBarBatteryTemperature: false,
        DefaultsKey.menuBarBatteryTime: false,
        DefaultsKey.menuBarDiskUsage: false,
        DefaultsKey.menuBarDiskActivity: false,
        DefaultsKey.menuBarPeripheralBattery: false,
        DefaultsKey.menuBarPreset: "dense",
        DefaultsKey.menuBarMetricSpacing: "compact",  // owner's call: compact by default in 3.1.8
        DefaultsKey.menuBarMetricAppearance: "values",
        DefaultsKey.menuBarUsageBarNormalColor: "#64D2FF",
        DefaultsKey.menuBarUsageBarElevatedColor: "#FFD60A",
        DefaultsKey.menuBarUsageBarCriticalColor: "#FF453A",
        DefaultsKey.menuBarUsageBarMediumThreshold: 70,
        DefaultsKey.menuBarUsageBarHighThreshold: 90,
        DefaultsKey.menuBarHideIconWithMetrics: false,
        DefaultsKey.menuBarLayoutMode: "modern",
        DefaultsKey.menuBarGraphShowsValue: false,
        DefaultsKey.menuBarGraphThemeLight: "system",
        DefaultsKey.menuBarGraphThemeDark: "system",
        DefaultsKey.menuBarGraphLightBackground: "filled",
        DefaultsKey.menuBarGraphHistoryWidth: "standard",
        DefaultsKey.menuBarGraphHistorySpaced: false,
        DefaultsKey.menuBarNetworkGraphLayout: "mirrored",
        DefaultsKey.windowLayoutHiddenActions: "",
        DefaultsKey.menuBarMetricOrder: defaultMenuBarMetricOrder.joined(separator: ","),
        DefaultsKey.menuBarCombineTemperatures: true,
        DefaultsKey.menuBarSeparateMetrics: false,
        DefaultsKey.menuBarSeparateMetricsCaptionVisible: true,
        DefaultsKey.menuBarNetworkUploadFirst: false,
        DefaultsKey.menuBarLabelStyle: "compact",
        DefaultsKey.menuBarMemoryStyle: "percent",
        DefaultsKey.monitorMemoryMetric: "used",
        DefaultsKey.monitorShowSystem: true,
        DefaultsKey.monitorShowNetwork: true,
        DefaultsKey.monitorShowDisk: true,
        DefaultsKey.monitorShowPower: true,
        DefaultsKey.monitorShowMixer: true,
        DefaultsKey.panelNavigationEnabled: true,
        DefaultsKey.monitorGraphCPU: true,
        DefaultsKey.monitorGraphGPU: true,
        DefaultsKey.monitorGraphMemory: true,
        DefaultsKey.monitorGraphNetwork: true,
        DefaultsKey.monitorGraphDisk: true,
        DefaultsKey.monitorGraphPower: true,
        DefaultsKey.monitorGraphBattery: true,
        // Every per-item block shows by default; users hide what they don't want.
        DefaultsKey.monitorSysTemps: true,
        DefaultsKey.monitorSysCPU: true,
        DefaultsKey.monitorSysGPU: true,
        DefaultsKey.monitorSysBattery: true,
        DefaultsKey.monitorSysMemory: true,
        DefaultsKey.monitorSysAlerts: true,
        DefaultsKey.monitorSysUptime: true,
        DefaultsKey.monitorSysConnectedDevices: true,
        DefaultsKey.monitorNetSpeed: true,
        DefaultsKey.monitorNetApps: true,
        DefaultsKey.monitorNetTotals: true,
        DefaultsKey.monitorNetTest: true,
        DefaultsKey.monitorNetLatency: true,
        // Both reach outside the Mac, so they start off.
        DefaultsKey.networkPingEnabled: false,
        DefaultsKey.networkPublicIPEnabled: false,
        DefaultsKey.monitorDiskUsage: true,
        DefaultsKey.monitorDiskActivity: true,
        DefaultsKey.monitorDiskSMART: true,
        DefaultsKey.monitorDiskProtection: true,
        DefaultsKey.monitorDiskTools: true,
        DefaultsKey.monitorDiskApps: true,
        DefaultsKey.monitorDiskNetworkVolumes: true,
        DefaultsKey.monitorPwrSystem: true,
        DefaultsKey.monitorPwrAdapter: true,
        DefaultsKey.monitorPwrBattery: true,
        DefaultsKey.monitorPwrTimeRemaining: true,
        DefaultsKey.monitorPwrHealth: true,
        DefaultsKey.monitorAlertCPU: false,
        DefaultsKey.monitorAlertCPUTemperature: false,
        DefaultsKey.monitorAlertGPUTemperature: false,
        DefaultsKey.monitorAlertGPUPower: false,
        DefaultsKey.monitorAlertMemory: false,
        DefaultsKey.monitorAlertDisk: false,
        DefaultsKey.monitorAlertBattery: false,
        DefaultsKey.monitorAlertCPUThreshold: 90,
        DefaultsKey.monitorAlertCPUTemperatureThreshold: 90,
        DefaultsKey.monitorAlertGPUTemperatureThreshold: 85,
        DefaultsKey.monitorAlertGPUPowerThreshold: 250,
        DefaultsKey.monitorAlertDiskFreePercent: 10,
        DefaultsKey.monitorAlertBatteryPercent: 15,
        DefaultsKey.monitorAlertCooldownMinutes: 15,
        DefaultsKey.mediaLastTool: MediaTool.videoCompressor.rawValue,
        DefaultsKey.mediaVideoStart: 0.0,
        DefaultsKey.mediaVideoEnd: 0.0,
        DefaultsKey.mediaVideoQuality: 0.68,
        DefaultsKey.mediaVideoMaxDimension: 1280,
        DefaultsKey.mediaVideoFPS: 30.0,
        DefaultsKey.mediaVideoKeepAudio: true,
        DefaultsKey.mediaVideoCodec: MediaVideoCodec.h264.rawValue,
        DefaultsKey.mediaVideoSizing: MediaSizingMode.resolution.rawValue,
        DefaultsKey.mediaVideoTargetMegabytes: 20,
        DefaultsKey.mediaGIFStart: 0.0,
        DefaultsKey.mediaGIFEnd: 0.0,
        DefaultsKey.mediaGIFQuality: 0.74,
        DefaultsKey.mediaGIFWidth: 720,
        DefaultsKey.mediaGIFFPS: 12.0,
        DefaultsKey.mediaGIFLoops: true,
        DefaultsKey.mediaGIFSizing: MediaSizingMode.resolution.rawValue,
        DefaultsKey.mediaGIFTargetMegabytes: 10,
        DefaultsKey.mediaImageQuality: 0.72,
        DefaultsKey.mediaImageMaxDimension: 1600,
        DefaultsKey.mediaImageFormat: MediaImageFormat.jpeg.rawValue,
        DefaultsKey.mediaImageStripMetadata: true,
        DefaultsKey.mediaTextAccurate: true,
        DefaultsKey.mediaTextLanguageCorrection: true,
        DefaultsKey.clipboardHistoryEnabled: false,
        DefaultsKey.clipboardHistoryLimit: 50,
        DefaultsKey.clipboardHistoryFilterSensitiveText: false,
        DefaultsKey.clipboardHistoryRetentionDays: 0,
        DefaultsKey.clipboardHistoryIncludeImagesFiles: true,
        DefaultsKey.clipboardHistoryQuickPreview: false,
        DefaultsKey.pastePlainEnabled: false,
        DefaultsKey.pastePlainShortcut: GlobalShortcut.pastePlainDefault.storageValue,
        DefaultsKey.colorPickerShortcutEnabled: false,
        DefaultsKey.colorPickerShortcut: GlobalShortcut.colorPickerDefault.storageValue,
        DefaultsKey.colorPickerFormat: "hex",
        DefaultsKey.colorPickerBareHex: false,
        DefaultsKey.screenOCRShortcutEnabled: false,
        DefaultsKey.screenOCRShortcut: GlobalShortcut.screenOCRDefault.storageValue,
        DefaultsKey.screenOCRDetectQRCodes: true,
        DefaultsKey.micMuteShortcutEnabled: false,
        DefaultsKey.micMuteShortcut: GlobalShortcut.micMuteDefault.storageValue,
        DefaultsKey.cameraPreviewShortcutEnabled: false,
        DefaultsKey.cameraPreviewShortcut: GlobalShortcut.cameraPreviewDefault.storageValue,
        DefaultsKey.scratchpadShortcutEnabled: false,
        DefaultsKey.scratchpadShortcut: GlobalShortcut.scratchpadDefault.storageValue,
        DefaultsKey.scratchpadRetention: ScratchpadRetention.never.rawValue,
        DefaultsKey.scratchpadCloseOnClickOutside: false,
        DefaultsKey.micMuteActive: false,
        DefaultsKey.micMuteSavedVolume: 0.75,
        DefaultsKey.micMuteMenuBarIndicator: true,  // owner's call: on by default in 3.1.8 (badge only shows while muted)
        DefaultsKey.quickLauncherShortcutEnabled: true,
        DefaultsKey.quickLauncherShortcut: GlobalShortcut.quickLauncherDefault.storageValue,
        DefaultsKey.quickLauncherHiddenItems: "",
        DefaultsKey.panelUtilityQuickLauncher: true,
        DefaultsKey.panelUtilityColorPicker: true,
        DefaultsKey.panelUtilityScreenOCR: true,
        DefaultsKey.panelUtilityMicMute: true,
        DefaultsKey.panelUtilityCameraPreview: true,
        DefaultsKey.panelUtilityScratchpad: true,
        DefaultsKey.clipboardHistoryShortcutEnabled: true,
        DefaultsKey.clipboardHistoryIgnoredApps: [String](),
        DefaultsKey.clipboardHistoryShortcut: GlobalShortcut.clipboardDefault.storageValue,
        DefaultsKey.screenshotShortcutEnabled: false,
        DefaultsKey.screenshotShortcut: GlobalShortcut.screenshotDefault.storageValue,
        DefaultsKey.screenshotFreeze: true,
        DefaultsKey.screenshotHideRyzenStatusWindows: true,
        DefaultsKey.screenshotSaveFolder: "",
        DefaultsKey.screenshotIncludePointer: false,
        DefaultsKey.screenshotDownscale: false,
        DefaultsKey.screenshotDelay: 0,
        DefaultsKey.screenshotLastTool: "arrow",
        DefaultsKey.screenshotLastColor: "red",
        DefaultsKey.screenshotLastStroke: "medium",
        DefaultsKey.screenshotLastSticker: "check",
        DefaultsKey.screenshotAnnotationShadows: false,
        DefaultsKey.screenshotToolOrder: ScreenshotSupport.Tool.defaultOrderStorage,
        DefaultsKey.screenshotToolShortcutsEnabled: true,
        DefaultsKey.screenshotBackdropStyle: "",
        DefaultsKey.screenshotBackdropPresets: "[]",
        DefaultsKey.screenshotOpenEditorDirectly: false,
        DefaultsKey.screenshotFullScreenShortcutEnabled: false,
        DefaultsKey.screenshotFullScreenShortcut: GlobalShortcut.screenshotFullScreenDefault.storageValue,
        DefaultsKey.screenshotLastCaptureShortcutEnabled: false,
        DefaultsKey.screenshotLastCaptureShortcut: GlobalShortcut.screenshotLastCaptureDefault.storageValue,
        DefaultsKey.screenshotShowLastRegion: false,
        DefaultsKey.screenshotCopyToClipboard: false,
        DefaultsKey.screenshotSaveSubfolder: "",
        DefaultsKey.screenshotFileNamePattern: "",
        DefaultsKey.screenshotFileNumberStart: 1,
        DefaultsKey.screenshotFileNumberNext: 1,

        DefaultsKey.screenshotDefaultAction: "",
        DefaultsKey.recorderShortcutEnabled: false,
        DefaultsKey.recorderShortcut: GlobalShortcut.screenRecorderDefault.storageValue,
        DefaultsKey.recorderCountdown: 3,
        DefaultsKey.recorderQuality: "balanced",
        DefaultsKey.recorderFrameRate: 60,
        DefaultsKey.recorderSystemAudio: true,
        DefaultsKey.recorderSaveFolder: "",
        DefaultsKey.recorderOpenEditor: true,
        DefaultsKey.recorderGIFSize: "medium",
        DefaultsKey.recorderGIFFrameRate: 12,
        DefaultsKey.recorderEditorPresets: Data(),
        DefaultsKey.panelUtilityScreenshot: true,
        DefaultsKey.windowLayoutShortcutsEnabled: false,
        DefaultsKey.windowGestureEnabled: false,
        DefaultsKey.windowGestureModifiers: WindowGestureSupport.defaultModifierStorageValue,
        DefaultsKey.windowGestureRaiseWindow: false,
        DefaultsKey.windowLayoutShortcutLeft: GlobalShortcut.windowLayoutLeftDefault.storageValue,
        DefaultsKey.windowLayoutShortcutRight: GlobalShortcut.windowLayoutRightDefault.storageValue,
        DefaultsKey.windowLayoutShortcutTop: GlobalShortcut.windowLayoutTopDefault.storageValue,
        DefaultsKey.windowLayoutShortcutBottom: GlobalShortcut.windowLayoutBottomDefault.storageValue,
        DefaultsKey.windowLayoutShortcutTopLeft: GlobalShortcut.windowLayoutTopLeftDefault.storageValue,
        DefaultsKey.windowLayoutShortcutTopRight: GlobalShortcut.windowLayoutTopRightDefault.storageValue,
        DefaultsKey.windowLayoutShortcutBottomLeft: GlobalShortcut.windowLayoutBottomLeftDefault.storageValue,
        DefaultsKey.windowLayoutShortcutBottomRight: GlobalShortcut.windowLayoutBottomRightDefault.storageValue,
        DefaultsKey.windowLayoutShortcutMaximize: GlobalShortcut.windowLayoutMaximizeDefault.storageValue,
        DefaultsKey.windowLayoutShortcutMarginMaximize: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutCenter: GlobalShortcut.windowLayoutCenterDefault.storageValue,
        DefaultsKey.windowLayoutShortcutRestore: GlobalShortcut.windowLayoutRestoreDefault.storageValue,
        DefaultsKey.windowLayoutShortcutLeftThird: GlobalShortcut.windowLayoutLeftThirdDefault.storageValue,
        DefaultsKey.windowLayoutShortcutCenterThird: GlobalShortcut.windowLayoutCenterThirdDefault.storageValue,
        DefaultsKey.windowLayoutShortcutRightThird: GlobalShortcut.windowLayoutRightThirdDefault.storageValue,
        DefaultsKey.windowLayoutShortcutLeftTwoThirds: GlobalShortcut.windowLayoutLeftTwoThirdsDefault.storageValue,
        DefaultsKey.windowLayoutShortcutRightTwoThirds: GlobalShortcut.windowLayoutRightTwoThirdsDefault.storageValue,
        DefaultsKey.windowLayoutShortcutPreviousDisplay: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutNextDisplay: GlobalShortcut.windowLayoutNextDisplayDefault.storageValue,
        DefaultsKey.windowLayoutShortcutTopLeftSixth: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutTopCenterSixth: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutTopRightSixth: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutBottomLeftSixth: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutBottomCenterSixth: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutBottomRightSixth: WindowLayoutAction.clearedShortcutStorageValue,
        // AMD EPP thresholds
        DefaultsKey.autoEppIdleThreshold: 25,
        DefaultsKey.autoEppLoadThreshold: 50,
        // AMD control toggles default to the hardware-friendly state; the kext
        // echo overwrites them on first view appear. No default for
        // `amdPowerPreset`: nothing is highlighted until the user applies one.
        DefaultsKey.amdCpbEnabled: true,
        DefaultsKey.amdPpmEnabled: false,
        DefaultsKey.amdLpmEnabled: false,
        DefaultsKey.showFansInAmdPower: true,
        // Per-core PM-table telemetry collapsed by default; expands on demand.
        DefaultsKey.showPmTableCoresInPanel: false,
        // Optional per-core columns default off — the base row stays minimal.
        DefaultsKey.showPmCoreVoltage: false,
        DefaultsKey.showPmCoreC0: false,
        DefaultsKey.showPmCoreCC6: false,
        // Classic core grid renders load (the classic fill) until the
        // user switches the card to an SMU metric.
        DefaultsKey.panelCoreGridMetric: "load",
        // Detail views open on the live graph; long ranges are picked there.
        DefaultsKey.metricDetailHistoryRange: 0,
        // Panel history graphs open on the last hour, as iStat Menus does.
        DefaultsKey.panelHistoryRange: 3_600,
        // Gaming Mode — off by default; hiding the icon is the default behavior.
        DefaultsKey.gamingModeActive: false,
        DefaultsKey.gamingModeHideMenuBar: true,
        // Ported from upstream fe24c17 (block A). Literal values stand in
        // for upstream types whose areas are not ported yet; each names the
        // constant it mirrors.
        DefaultsKey.notchLiquidGlassEnabled: false,
        DefaultsKey.dimScreenOnLidClose: false,
        DefaultsKey.keepAwakeRunningApps: false,
        DefaultsKey.keepAwakeRunningAppBundleIDs: [String](),
        DefaultsKey.keepAwakeAutomationRequireAll: false,
        DefaultsKey.keepAwakePauseWhenLocked: false,
        DefaultsKey.keepAwakeSwitchUsesUntil: false,
        DefaultsKey.keepAwakeUntilTime: 0.0,
        DefaultsKey.smoothScrollResponse: 65, // SmoothScrollSupport.defaultResponse upstream
        DefaultsKey.smoothScrollCoast: 0, // SmoothScrollSupport.defaultCoast upstream
        DefaultsKey.mouseButtonShortcuts: [String: String](),
        DefaultsKey.mouseSpacesGestureFollowsDrag: false,
        DefaultsKey.superKeySource: SuperKeySource.capsLock.rawValue,
        DefaultsKey.superKeyModifiers: SuperKeySupport.defaultModifierStorageValue,
        DefaultsKey.smoothScrollExceptions: [String](),
        DefaultsKey.linearScrollExceptions: [String](),
        DefaultsKey.scrollInverterExceptions: [String](),
        DefaultsKey.focusFollowsMouseExceptions: [String](),
        DefaultsKey.mouseNavigationExceptions: [String](),
        DefaultsKey.mouseButtonExceptions: [String](),
        DefaultsKey.middleClickExceptions: [String](),
        DefaultsKey.superKeyExceptions: [String](),
        DefaultsKey.switcherTakeOverSystemShortcuts: false,
        DefaultsKey.switcherMinimizedPlacement: WindowSwitchMinimizedPlacement.normal.rawValue,
        DefaultsKey.switcherTreatHiddenAppsLikeMinimized: true,
        DefaultsKey.switcherShowFullscreenWindows: true,
        DefaultsKey.switcherShowShortcutHints: true,
        DefaultsKey.switcherAppearanceDelay: SwitcherSupport.defaultAppearanceDelayMilliseconds,
        DefaultsKey.switcherInstantSelection: false,
        DefaultsKey.switcherScreenPlacement: "pointer", // SwitcherScreenPlacement.fallback upstream
        DefaultsKey.switcherCurrentDisplayOnly: false,
        DefaultsKey.minimalWindowPreviews: false,
        DefaultsKey.dockPreviewCurrentSpaceOnly: false,
        DefaultsKey.dockPreviewKeepDockVisible: false,
        DefaultsKey.dockPreviewQuitAppOnClose: false,
        DefaultsKey.dockPreviewOrderByCreation: false,
        DefaultsKey.includeBetaUpdates: false,
        DefaultsKey.mixerHideInactiveApps: false,
        DefaultsKey.mixerAppArrangement: "",
        DefaultsKey.preciseVolumeRollerEnabled: false,
        DefaultsKey.shelfDockPlacement: ShelfDockPlacement.menuBar.rawValue,
        // New Shelf behavior stays opt-in for existing users.
        DefaultsKey.shelfEdgeDragEnabled: false,
        DefaultsKey.shelfClearOnClose: false,
        DefaultsKey.shelfShortcutAddsFinderSelection: false,
        DefaultsKey.brightnessKeyStep: "standard", // BrightnessSupport.KeyStep.standard upstream
        DefaultsKey.displayBrightnessShortcutsEnabled: false,
        DefaultsKey.displayBrightnessDecreaseShortcut: "shift+command:27",
        DefaultsKey.displayBrightnessIncreaseShortcut: "shift+command:24",
        DefaultsKey.keyboardBrightnessShortcutsEnabled: false,
        DefaultsKey.keyboardBrightnessDecreaseShortcut: "option+command:27",
        DefaultsKey.keyboardBrightnessIncreaseShortcut: "option+command:24",
        DefaultsKey.musicBlockPlayReplacement: true,
        DefaultsKey.urlCleanerCustomParameters: "",
        DefaultsKey.urlCleanerSiteParameters: "",
        DefaultsKey.urlCleanerDisabledParameters: "",
        DefaultsKey.notchShowPlayingMusic: true,
        DefaultsKey.notchIncludeOtherPlayers: true,
        DefaultsKey.notchPreferredPlayer: "",
        DefaultsKey.notchIdleContent: "music", // NotchIdleContent.music
        DefaultsKey.notchCapsuleCenter: "song", // NotchCapsuleCenter.song
        DefaultsKey.notchCapsuleMetric: "cpuTemperature", // NotchCapsuleMetric.cpuTemperature
        DefaultsKey.notchHiddenControls: "keyboardLight,microphone,screenshot,recording,speedTest,panel,commandBar,scratchpad", // NotchControlItem.defaultHidden
        DefaultsKey.notchScratchpadControlHidden: false,
        DefaultsKey.notchKeyboardLightControlHidden: false,
        DefaultsKey.notchControlOrder: "",
        DefaultsKey.notchSize: "spacious", // NotchSize.spacious
        DefaultsKey.notchOutlineEnabled: false,
        DefaultsKey.notchHideMenuBarGap: true,
        DefaultsKey.notchCustomWidth: 440.0, // NotchSize.defaultWidth
        DefaultsKey.notchCustomHeight: 480.0, // NotchSize.defaultHeight
        DefaultsKey.notchCameraFitWidth: 0.0,
        DefaultsKey.notchCameraFitHeight: 0.0,
        DefaultsKey.notchHapticFeedback: true,
        DefaultsKey.notchProgressiveBlur: false,
        DefaultsKey.notchLeaveAlert: false,
        DefaultsKey.notchLeaveTransport: "automobile",
        DefaultsKey.notchFocusEnabled: false,
        DefaultsKey.notchTranslucentBackground: false,
        DefaultsKey.notchShelf: true,
        DefaultsKey.notchDragReveal: true,
        DefaultsKey.notchCaptureControls: true,
        DefaultsKey.notchQuickPanel: true,
        DefaultsKey.notchAppPanel: false,
        DefaultsKey.notchScratchpad: true,
        DefaultsKey.notchAgentsClaude: true,
        DefaultsKey.notchAgentsCodex: true,
        DefaultsKey.notchAgentsOpenCode: true,
        DefaultsKey.notchAgentsCopilot: true,
        DefaultsKey.notchAgentsCardOrder: "",
        DefaultsKey.notchAgentsHiddenCards: "",
        DefaultsKey.notchAgentsPeriod: "today", // AgentPeriod.today upstream
        DefaultsKey.notchAgentsLimitDisplay: "remaining", // NotchAgentLimitDisplay.remaining upstream
        DefaultsKey.notchAgentsLimitFocus: "mostUsed", // NotchAgentLimitFocus.mostUsed upstream
        DefaultsKey.notchAgentsLiveActivity: true,
        DefaultsKey.notchAgentsReadout: "elapsed", // NotchAgentReadout.elapsed upstream
        DefaultsKey.notchAgentsFinishAlert: true,
        DefaultsKey.notchAgentsFinishMinimum: 60.0, // NotchAgentSupport.defaultFinishMinimum upstream
        DefaultsKey.notchAgentsLimitAlert: true,
        DefaultsKey.notchAgentsLimitThreshold: 80.0, // NotchAgentSupport.defaultLimitThreshold upstream
        DefaultsKey.notchAgentsDailyBudget: 0.0,
        DefaultsKey.notchAgentsPriceUpdates: true,
        DefaultsKey.notchInputSource: true,
        DefaultsKey.radialMenuActivationMode: "pressOrHold", // RadialMenuActivationMode.pressOrHold upstream
        DefaultsKey.windowMaximizeExcludedApps: [String](),
        DefaultsKey.cleaningModeKeepScreenVisible: false,
        DefaultsKey.packageManagerProvider: "automatic",
        DefaultsKey.homebrewGroupDependencies: true,
        DefaultsKey.appUpdatesIncludeOnlineCatalog: true,
        DefaultsKey.appUpdatesRules: "[]",
        DefaultsKey.appUpdatesNotifiedIDs: [String](),
        DefaultsKey.panelControlMouseButtonShortcuts: true,
        DefaultsKey.panelToggleKeyboardLight: true,
        DefaultsKey.menuBarConnectedDevices: false,
        DefaultsKey.menuBarIconSymbol: "",
        DefaultsKey.windowLayoutWindowGap: 0,
        DefaultsKey.windowLayoutScreenGap: 0,
        DefaultsKey.windowLayoutMarginPercent: 5.0,
        DefaultsKey.windowLayoutSideRepeatCyclesThirds: false,
        DefaultsKey.menuBarDiskStyle: "percent",
        DefaultsKey.monitorGraphScale: true,
        DefaultsKey.monitorSysCPUCores: true,
        DefaultsKey.monitorNetAddresses: true,
        DefaultsKey.networkSpeedUnit: NetworkSpeedUnit.bytes.rawValue,
        DefaultsKey.monitorPwrTemperature: true,
        DefaultsKey.monitorAlertBatteryTemperature: false,
        DefaultsKey.monitorAlertBatteryTemperatureThreshold: 40,
        DefaultsKey.mediaImageResizeKind: MediaImageResizeKind.maxDimension.rawValue,
        DefaultsKey.mediaImageResizeWidth: 1600,
        DefaultsKey.mediaImageResizeHeight: 1200,
        DefaultsKey.mediaImageExactResizeMode: MediaImageExactResizeMode.stretch.rawValue,
        DefaultsKey.mediaImageWatermarkKind: MediaImageWatermarkKind.off.rawValue,
        DefaultsKey.mediaImageWatermarkText: "",
        DefaultsKey.mediaImageWatermarkLogoPath: "",
        DefaultsKey.mediaImageWatermarkPosition: MediaImageWatermarkPosition.bottomRight.rawValue,
        DefaultsKey.mediaImageWatermarkOpacity: 0.45,
        DefaultsKey.mediaImageWatermarkMargin: 32,
        DefaultsKey.mediaImageWatermarkScale: 0.18,
        DefaultsKey.mediaImageRenamePattern: "",
        DefaultsKey.mediaImageBackground: MediaImageBackground.transparent.rawValue,
        DefaultsKey.mediaImagePreserveModificationDate: false,
        DefaultsKey.mediaImageSaveInSubfolder: false,
        DefaultsKey.mediaImageProfiles: "[]",
        DefaultsKey.mediaImageSelectedProfileID: "",
        DefaultsKey.windowLayoutIgnoredApps: [String](),
        DefaultsKey.clipboardHistoryLayout: "list", // ClipboardHistoryLayout.list upstream
        DefaultsKey.clipboardHistoryWindowWidth: 0.0,
        DefaultsKey.clipboardHistoryWindowHeight: 0.0,
        DefaultsKey.clipboardHistoryMenuBarPreview: false,
        DefaultsKey.clipboardHistoryMenuBarPreviewLength: Defaults.defaultClipboardMenuBarPreviewLength,
        DefaultsKey.clipboardAutoClearOnDelay: false,
        DefaultsKey.clipboardAutoClearDelay: Defaults.defaultClipboardAutoClearDelay,
        DefaultsKey.clipboardAutoClearOnSleep: false,
        DefaultsKey.clipboardAutoClearOnDisplaySleep: false,
        DefaultsKey.clipboardAutoClearOnScreenLock: false,
        DefaultsKey.finderCutPasteShowHUD: true,
        DefaultsKey.finderPasteImageAsFile: false,
        DefaultsKey.screenOCRRemoveLineBreaks: false,
        DefaultsKey.scratchpadBackgroundOpacity: 0.0,
        DefaultsKey.scratchpadTextSize: ScratchpadSupport.defaultTextSize,
        DefaultsKey.recorderMicrophone: false,
        DefaultsKey.recorderAutomaticZoom: true,
        DefaultsKey.recorderSharingEnabled: true,
        DefaultsKey.panelUtilityScreenRecorder: true,
        DefaultsKey.screenshotShowCaptureMenuOnShortcut: true,
        DefaultsKey.recorderShowCaptureMenuOnShortcut: true,
        DefaultsKey.screenOCRShowCaptureMenuOnShortcut: true,
        DefaultsKey.colorPickerShowCaptureMenuOnShortcut: true,
        DefaultsKey.unifiedScreenCaptureShortcutMigrated: false,
        DefaultsKey.restoredScreenCaptureShortcutsMigrated: false,
        DefaultsKey.recentCapturesShortcutEnabled: false,
        DefaultsKey.recentCapturesShortcut: GlobalShortcut.recentCapturesDefault.storageValue,
        DefaultsKey.screenshotClipboardShortcutEnabled: false,
        DefaultsKey.screenshotClipboardShortcut: GlobalShortcut.screenshotClipboardDefault.storageValue,
        DefaultsKey.screenshotHighlightWindows: true,
        DefaultsKey.screenshotLoupeStartsOn: false,
        DefaultsKey.screenshotLoupeRememberZoom: false,
        DefaultsKey.screenshotLoupeDefaultZoom: 1.0,
        DefaultsKey.screenshotLoupeLastZoom: 1.0,
        DefaultsKey.screenshotLoupeSteppedZoomByDefault: false,
        DefaultsKey.screenshotLastTextSize: 19, // ScreenshotSupport.defaultTextSize upstream
        DefaultsKey.screenshotLastBlurLevel: 3, // ScreenshotSupport.BlurStrength.defaultLevel upstream
        DefaultsKey.screenshotLastBlurStyle: "pixelate",
        DefaultsKey.screenshotLastBlurTextOnly: false,
        DefaultsKey.screenshotLastArrowStyle: "filled",
        DefaultsKey.screenshotToolShortcuts: "",
        DefaultsKey.screenshotWatermarkStyle: "",
        DefaultsKey.screenshotWatermarkPresets: "[]",
        DefaultsKey.screenshotAddToShelf: false,
        DefaultsKey.screenshotPreviewPosition: ScreenshotSupport.QuickPreviewPosition.automatic.rawValue,
        DefaultsKey.screenshotPreviewTakesFocus: true,
        DefaultsKey.screenshotUploadShortcutEnabled: false,
        DefaultsKey.screenshotUploadShortcut: GlobalShortcut.screenshotUploadDefault.storageValue,
        DefaultsKey.screenshotUploadDuration: 3_600, // ScreenshotShareDuration.oneHour
        DefaultsKey.screenshotPreviewEnabled: true,
        DefaultsKey.screenshotPreviewDuration: 3, // ScreenshotSupport.defaultConfirmationPreviewDuration upstream
        DefaultsKey.screenshotSharingEnabled: true,
        DefaultsKey.windowDirectionalEnabled: false,
        DefaultsKey.windowDirectionalShortcut: GlobalShortcut.windowDirectionalDefault.storageValue,
        DefaultsKey.pointerDisplayEnabled: false,
        DefaultsKey.pointerDisplayShortcut: GlobalShortcut.pointerNextDisplayDefault.storageValue,
        DefaultsKey.windowEdgeSnapEnabled: false,
        DefaultsKey.windowEdgeSnapDisabledZones: "",
        DefaultsKey.windowEdgeSnapZoneActions: "",
        DefaultsKey.windowLayoutShortcutCenterHalf: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutCenterTwoThirds: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutTopThird: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutMiddleThird: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutBottomThird: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutTopTwoThirds: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutBottomTwoThirds: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutTopQuarter: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutUpperMiddleQuarter: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutLowerMiddleQuarter: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutBottomQuarter: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutLeftQuarter: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutLeftMiddleQuarter: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutRightMiddleQuarter: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutRightQuarter: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutFullScreen: WindowLayoutAction.clearedShortcutStorageValue,
    ]

    private static let currentMigrationVersion = 7

    static func register() {
        let defaults = UserDefaults.standard
        // Upstream runs these before registering, so `object(forKey:)` still
        // tells a saved choice from a registered default.
        migrateClipboardSensitiveTextOptIn(in: defaults)
        migrateBatteryTemperatureVisibility(in: defaults)
        var defaultValues = registeredDefaults
#if DEBUG
        defaultValues[DefaultsKey.screenshotSharingDeveloperEndpoint] = ""
#endif
        defaults.register(defaults: defaultValues)
        defaults.register(defaults: AppFeature.availabilityDefaults)
        // Idempotent repairs upstream runs on every launch.
        migrateSilentHeadphonesDisconnectVolume(in: defaults)
        recheckBrightnessDDCWriteOnlyPaths(in: defaults)
        // The "all apps" output choice now lasts one session; a saved one
        // would move apps that chose their own output after every launch.
        defaults.removeObject(forKey: DefaultsKey.mixerUniversalOutputDevice)

        let lastVersion = defaults.integer(forKey: "_migrationVersion")
        guard lastVersion < currentMigrationVersion else { return }

        if lastVersion < 1 { migrateLegacyMenuBarTemperatureMetric(in: defaults) }
        if lastVersion < 2 { migrateLegacySwitcherWindowShortcut(in: defaults) }
        if lastVersion < 3 { migrateLegacyKeyboardDebounceWindow(in: defaults) }
        if lastVersion < 4 { migrateUtilityOrderForScreenshot(in: defaults) }
        if lastVersion < 5 { migrateUtilityOrderForAppUpdates(in: defaults) }
        if lastVersion < 6 { migrateLegacyNowPlayingMenuBarMode(in: defaults) }
        if lastVersion < 7 { migrateLegacyFanSubsystem(in: defaults) }

        defaults.set(currentMigrationVersion, forKey: "_migrationVersion")
    }

    /// Start text filtering off for existing installations as well. A distinct
    /// key keeps older backups from re-enabling the previous on-by-default
    /// heuristic, while preserving choices made after this update.
    static func migrateClipboardSensitiveTextOptIn(in defaults: UserDefaults) {
        defaults.removeObject(forKey: "clipboardHistorySkipSensitive")
    }

    static func migrateLegacyFanSubsystem(in defaults: UserDefaults) {
        // 1. Migrate customCurves -> customCurves_v2
        if let oldData = defaults.data(forKey: "customCurves") {
            struct LegacyCurvePoint: Decodable {
                let id: UUID?
                let temp: Double
                let pwm: Double
            }
            struct LegacyCurve: Decodable {
                let id: UUID?
                let name: String
                let points: [LegacyCurvePoint]
                let sourceSensor: Int?
                let hysteresis: Double?
                let rampRate: Double?
            }

            if let decoded = try? JSONDecoder().decode([LegacyCurve].self, from: oldData) {
                let newCurves: [FanCurveDefinition] = decoded.prefix(4).enumerated().map { idx, old in
                    let pts = old.points.map { FanCurvePoint(id: $0.id ?? UUID(), temp: $0.temp, pwm: $0.pwm) }
                    let sensor = (old.sourceSensor == 1) ? FanSensor.gpu : FanSensor.cpu
                    let hyst = UInt8(min(5, max(1, Int(old.hysteresis ?? 2.0))))
                    let ramp = UInt8(min(20, max(1, Int(old.rampRate ?? 5.0))))
                    return FanCurveDefinition(
                        id: old.id ?? UUID(),
                        name: old.name,
                        kextSlot: idx,
                        points: pts,
                        sourceSensor: sensor,
                        hysteresis: hyst,
                        rampRate: ramp
                    )
                }
                if let encoded = try? JSONEncoder().encode(newCurves) {
                    defaults.set(encoded, forKey: DefaultsKey.customCurvesV2)
                }
            }
            defaults.removeObject(forKey: "customCurves")
        }

        // 2. Migrate fanMappings -> fanMappings_v2
        if let oldMapData = defaults.data(forKey: "fanMappings") {
            if let decoded = try? JSONDecoder().decode([Int: Int].self, from: oldMapData) {
                var sanitized: [Int: Int] = [:]
                for (fanId, curveIdx) in decoded {
                    if curveIdx >= -1 && curveIdx < 4 {
                        sanitized[fanId] = curveIdx
                    } else {
                        sanitized[fanId] = -1
                    }
                }
                if let encoded = try? JSONEncoder().encode(sanitized) {
                    defaults.set(encoded, forKey: DefaultsKey.fanMappingsV2)
                }
            }
            defaults.removeObject(forKey: "fanMappings")
        }
    }

    static func migrateBatteryTemperatureVisibility(in defaults: UserDefaults) {
        guard defaults.object(forKey: DefaultsKey.monitorPwrTemperature) == nil else { return }
        defaults.set(defaults.object(forKey: DefaultsKey.monitorSysTemps) as? Bool ?? true,
                     forKey: DefaultsKey.monitorPwrTemperature)
    }

    /// Discovery used to send one request per read, which reads a monitor that
    /// answers only paired requests as write-only. That verdict is cached and
    /// never re-probed, so it would outlive the fix: drop the cache once.
    static func recheckBrightnessDDCWriteOnlyPaths(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.brightnessDDCWriteOnlyPathsRechecked) else {
            return
        }
        defaults.set(true, forKey: DefaultsKey.brightnessDDCWriteOnlyPathsRechecked)
        defaults.removeObject(forKey: DefaultsKey.brightnessDDCWriteOnlyPaths)
    }

    static func migrateLegacyNowPlayingMenuBarMode(in defaults: UserDefaults) {
        if let legacy = defaults.object(forKey: DefaultsKey.nowPlayingMenuBarText) as? Bool {
            if !legacy {
                defaults.set(NowPlayingMenuBarMode.iconOnly.rawValue, forKey: DefaultsKey.nowPlayingMenuBarMode)
            }
            defaults.removeObject(forKey: DefaultsKey.nowPlayingMenuBarText)
        }
    }

    static func migrateLegacySwitcherWindowShortcut(in defaults: UserDefaults) {
        let wrongDeveloperDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_Grave),
                                                   modifiers: [.control, .option, .command]).storageValue
        guard defaults.string(forKey: DefaultsKey.switcherWindowShortcut) == wrongDeveloperDefault else {
            return
        }
        defaults.set(GlobalShortcut.switcherWindowDefault.storageValue,
                     forKey: DefaultsKey.switcherWindowShortcut)
    }

    static func migrateLegacyKeyboardDebounceWindow(in defaults: UserDefaults) {
        guard let storedWindow = defaults.object(forKey: DefaultsKey.keyboardDebounceWindowMs) as? Int,
              storedWindow == 30 || storedWindow == 10,
              defaults.bool(forKey: DefaultsKey.keyboardDebounceEnabled) == false,
              (defaults.string(forKey: DefaultsKey.keyboardDebounceKeyWindows) ?? "").isEmpty
        else { return }
        defaults.set(defaultKeyboardDebounceWindowMs, forKey: DefaultsKey.keyboardDebounceWindowMs)
    }

    static func migrateUtilityOrderForScreenshot(in defaults: UserDefaults) {
        guard let storedOrder = defaults.object(forKey: DefaultsKey.panelUtilityOrder) as? String else {
            return
        }
        let ids = storedOrder.split(separator: ",").map(String.init)
        guard !ids.contains("screenshot") else { return }
        defaults.set((["screenshot"] + ids).joined(separator: ","),
                     forKey: DefaultsKey.panelUtilityOrder)
    }

    /// App updates joins the panel next to the other app-management tools
    /// instead of at the end of a long list, without disturbing the rest of
    /// a layout the user arranged.
    static func migrateUtilityOrderForAppUpdates(in defaults: UserDefaults) {
        guard let storedOrder = defaults.object(forKey: DefaultsKey.panelUtilityOrder) as? String else {
            return
        }
        defaults.set(utilityOrderWithAppUpdates(storedOrder).joined(separator: ","),
                     forKey: DefaultsKey.panelUtilityOrder)
    }

    static func utilityOrderWithAppUpdates(_ storedOrder: String) -> [String] {
        var ids = storedOrder.split(separator: ",").map(String.init)
        guard !ids.contains("appUpdates") else { return ids }
        let anchor = ids.firstIndex(of: "cleaner") ?? min(1, ids.count)
        ids.insert("appUpdates", at: anchor)
        return ids
    }

    static func sanitizedDefaultDuration(_ minutes: Int) -> Int {
        allowedDurations.contains(minutes) ? minutes : 0
    }

    static func sanitizedBatteryLimit(_ percent: Int) -> Int {
        allowedBatteryLimits.contains(percent) ? percent : 10
    }

    static func sanitizedKeepAwakeMouseJiggleInterval(_ minutes: Int) -> Int {
        allowedKeepAwakeMouseJiggleIntervals.contains(minutes) ? minutes : 5
    }

    static func sanitizedKeepAwakeIconTint(_ rawValue: String?) -> KeepAwakeIconTint {
        guard let rawValue,
              let tint = KeepAwakeIconTint(rawValue: rawValue) else {
            return .orange
        }
        return tint
    }

    static func sanitizedKeepAwakeActiveIcon(_ rawValue: String?) -> KeepAwakeActiveIcon {
        guard let rawValue,
              let icon = KeepAwakeActiveIcon(rawValue: rawValue) else {
            return .ryzenstatus
        }
        return icon
    }

    /// A typed symbol name without the spaces around it; empty keeps the
    /// RyzenStatus glyph. Whether this Mac has the symbol is left to the menu
    /// bar drawing, since a backup can carry a name from a newer macOS.
    static func sanitizedMenuBarIconSymbol(_ rawValue: String?) -> String {
        rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// What the menu bar icon field saves as it is typed: a name this Mac has
    /// a symbol for, nothing for the RyzenStatus icon, and otherwise the name
    /// the field opened with, so a typo never leaves a valid half behind.
    static func menuBarIconSymbolToSave(typed: String?, opening: String,
                                        exists: (String) -> Bool) -> String {
        let name = sanitizedMenuBarIconSymbol(typed)
        return name.isEmpty || exists(name) ? name : opening
    }

    /// The symbols the menu bar icon gallery offers after the RyzenStatus icon:
    /// solid shapes that still read at menu bar size, all present on macOS 14
    /// (some under older names, which later versions still accept). Keep
    /// Awake's symbols stay out, so an active session still stands out.
    static let menuBarIconGallery = [
        "bolt.fill", "star.fill", "heart.fill", "flame.fill", "sparkles", "leaf.fill",
        "drop.fill", "snowflake", "sun.max.fill", "moon.stars.fill", "cloud.fill", "mountain.2.fill",
        "circle.fill", "square.fill", "triangle.fill", "diamond.fill", "hexagon.fill", "seal.fill",
        "circle.lefthalf.filled", "circle.hexagongrid.fill", "infinity",
        "command", "cpu.fill", "memorychip.fill", "gauge.with.dots.needle.67percent",
        "fanblades.fill", "gearshape.fill", "terminal.fill", "waveform",
        "wand.and.stars", "key.fill", "crown.fill", "gamecontroller.fill", "headphones",
        "music.note", "paperplane.fill", "pawprint.fill", "cat.fill", "hare.fill", "tortoise.fill",
    ]

    static func sanitizedMonitorInterval(_ raw: Double) -> Double {
        // Find the closest allowed value
        allowedMonitorIntervals.min(by: { abs($0 - raw) < abs($1 - raw) }) ?? 1.0
    }

    /// Tap-to-middle-click accepts exactly three or four fingers; anything
    /// else means the option is off.
    static func sanitizedMiddleClickTapFingers(_ raw: Int) -> Int {
        raw == 3 || raw == 4 ? raw : 0
    }

    static func sanitizedKeyboardDebounceWindow(_ milliseconds: Int) -> Int {
        allowedKeyboardDebounceWindowRange.contains(milliseconds)
            ? milliseconds
            : defaultKeyboardDebounceWindowMs
    }

    static func sanitizedMouseClickDebounceWindow(_ milliseconds: Int) -> Int {
        allowedMouseClickDebounceWindowRange.contains(milliseconds)
            ? milliseconds
            : defaultMouseClickDebounceWindowMs
    }

    /// Clamps rather than falling back to the default: a typed 4 becoming 5 is
    /// the correction the person meant, a typed 4 becoming 20 is not.
    static func sanitizedClipboardAutoClearDelay(_ seconds: Int) -> Int {
        min(max(seconds, allowedClipboardAutoClearDelayRange.lowerBound),
            allowedClipboardAutoClearDelayRange.upperBound)
    }

    /// Same clamping reasoning as sanitizedClipboardAutoClearDelay above.
    static func sanitizedClipboardMenuBarPreviewLength(_ characters: Int) -> Int {
        min(max(characters, allowedClipboardMenuBarPreviewLengthRange.lowerBound),
            allowedClipboardMenuBarPreviewLengthRange.upperBound)
    }

    static func sanitizedMenuBarPreset(_ preset: String) -> String {
        allowedMenuBarPresets.contains(preset) ? preset : "dense"
    }

    static func sanitizedMenuBarMetricSpacing(_ spacing: String) -> String {
        // Corrupt values fall back to the registered default (compact).
        allowedMenuBarMetricSpacings.contains(spacing) ? spacing : "compact"
    }

    static func sanitizedMenuBarMetricAppearance(_ appearance: String) -> String {
        allowedMenuBarMetricAppearances.contains(appearance) ? appearance : "values"
    }

    static func sanitizedMenuBarGraphTheme(_ theme: String) -> String {
        MenuBarGraphTheme(rawValue: theme)?.rawValue ?? MenuBarGraphTheme.system.rawValue
    }

    static func sanitizedMenuBarGraphLightBackground(_ background: String) -> String {
        MenuBarGraphLightBackground(rawValue: background)?.rawValue ?? MenuBarGraphLightBackground.filled.rawValue
    }

    static func sanitizedMenuBarGraphHistoryWidth(_ width: String) -> String {
        MenuBarGraphHistoryWidth(rawValue: width)?.rawValue ?? MenuBarGraphHistoryWidth.standard.rawValue
    }

    static func sanitizedMenuBarNetworkGraphLayout(_ layout: String) -> String {
        MenuBarNetworkGraphLayout(rawValue: layout)?.rawValue ?? MenuBarNetworkGraphLayout.mirrored.rawValue
    }

    static func sanitizedMenuBarMetricOrder(_ raw: String) -> [String] {
        let defaults = defaultMenuBarMetricOrder
        var seen = Set<String>()
        var result: [String] = []
        for rawValue in raw.split(separator: ",").map({ String($0) }) {
            let values = rawValue == "temperature"
                ? ["cpuTemperature", "gpuTemperature", "batteryTemperature"]
                : [rawValue]
            for value in values {
                guard defaults.contains(value), !seen.contains(value) else { continue }
                seen.insert(value)
                result.append(value)
            }
        }
        for value in defaults where !seen.contains(value) {
            result.append(value)
        }
        return result
    }

    private static func migrateLegacyMenuBarTemperatureMetric(in defaults: UserDefaults) {
        guard let domainName = Bundle.main.bundleIdentifier,
              let domain = defaults.persistentDomain(forName: domainName),
              let legacyEnabled = domain[DefaultsKey.menuBarTemperature] as? Bool
        else { return }

        let newKeys = [
            DefaultsKey.menuBarCPUTemperature,
            DefaultsKey.menuBarGPUTemperature,
            DefaultsKey.menuBarBatteryTemperature,
        ]
        let alreadyMigrated = newKeys.contains { domain[$0] != nil }
        if legacyEnabled, !alreadyMigrated {
            for key in newKeys {
                defaults.set(true, forKey: key)
            }
        }
        if let rawOrder = domain[DefaultsKey.menuBarMetricOrder] as? String {
            defaults.set(sanitizedMenuBarMetricOrder(rawOrder).joined(separator: ","),
                         forKey: DefaultsKey.menuBarMetricOrder)
        }
        defaults.removeObject(forKey: DefaultsKey.menuBarTemperature)
    }

    static func sanitizedMenuBarLabelStyle(_ style: String) -> String {
        allowedMenuBarLabelStyles.contains(style) ? style : "compact"
    }

    static func sanitizedMenuBarMemoryStyle(_ style: String) -> String {
        allowedMenuBarMemoryStyles.contains(style) ? style : "percent"
    }

    static func sanitizedMonitorMemoryMetric(_ metric: String) -> String {
        allowedMonitorMemoryMetrics.contains(metric) ? metric : "used"
    }

    static func sanitizedClipboardHistoryLimit(_ value: Int) -> Int {
        allowedClipboardHistoryLimits.contains(value) ? value : 50
    }

    static func sanitizedClipboardHistoryRetentionDays(_ value: Int) -> Int {
        allowedClipboardHistoryRetentionDays.contains(value) ? value : 0
    }

    static func sanitizedMonitorAlertCooldown(_ value: Int) -> Int {
        allowedMonitorAlertCooldowns.contains(value) ? value : 15
    }

    static func sanitizedPercent(_ value: Int, fallback: Int, range: ClosedRange<Int>) -> Int {
        range.contains(value) ? value : fallback
    }

    static func sanitizedBundleIdentifierList(_ bundleIDs: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in bundleIDs {
            // A mouse exception list also carries the path of a program that
            // has no bundle identifier (issue #1009), and a file name may
            // legally end in a space. Trimming one would store a spelling the
            // running program never reports, so only an identifier is trimmed.
            let bundleID = MouseAppExceptionSupport.isExecutablePathIdentity(raw)
                ? raw
                : raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty, !seen.contains(bundleID) else { continue }
            seen.insert(bundleID)
            result.append(bundleID)
        }
        return result
    }

    static func sanitizedAutoQuitExceptions(_ bundleIDs: [String]) -> [String] {
        sanitizedBundleIdentifierList(mandatoryAutoQuitExceptionBundleIDs + bundleIDs)
    }

    static func sanitizedDiskExclusionList(_ list: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in list {
            let item = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = item.lowercased()
            guard !item.isEmpty, seen.insert(lower).inserted else { continue }
            result.append(item)
        }
        return result
    }

    static func sanitizedPanelItemOrder(_ raw: String, defaultOrder: [String]) -> [String] {
        let allowed = Set(defaultOrder)
        var seen = Set<String>()
        var result: [String] = []
        for id in raw.split(separator: ",").map(String.init) {
            guard allowed.contains(id), seen.insert(id).inserted else { continue }
            result.append(id)
        }
        for id in defaultOrder where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    static func sanitizedAppVolume(_ volume: Double) -> Double {
        guard volume.isFinite else { return 1 }
        return min(max(volume, 0), 2)
    }

    /// The volume the speakers are set to when headphones disconnect. It is a
    /// protection against a sudden blast, not a mute, so it never goes low
    /// enough to leave the sound inaudible.
    static let minimumMixerHeadphonesDisconnectVolumePercent = 10
    static let defaultMixerHeadphonesDisconnectVolumePercent = 25

    static func sanitizedMixerHeadphonesDisconnectVolumePercent(_ percent: Int) -> Int {
        min(max(percent, minimumMixerHeadphonesDisconnectVolumePercent), 100)
    }

    /// The option shipped with a stored value of 0, so ticking the box without
    /// touching the stepper silenced the speakers on the next disconnect. A
    /// value below the floor becomes the sane default.
    static func migrateSilentHeadphonesDisconnectVolume(in defaults: UserDefaults) {
        guard let stored = defaults.object(forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent) as? Int,
              stored < minimumMixerHeadphonesDisconnectVolumePercent else { return }
        defaults.set(defaultMixerHeadphonesDisconnectVolumePercent,
                     forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent)
    }

    static func sanitizedAppOutputDeviceUID(_ value: Any?) -> String? {
        MixerRoutingSupport.sanitizedDeviceUID(value)
    }

    static func sanitizedAppOutputDevices(_ raw: [String: Any]) -> [String: String] {
        MixerRoutingSupport.sanitizedRouteMap(raw)
    }

    static func sanitizedSoundOutputSwitcherDeviceUIDs(_ raw: [Any]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in raw {
            guard let uid = MixerRoutingSupport.sanitizedDeviceUID(value),
                  seen.insert(uid).inserted else { continue }
            result.append(uid)
        }
        return result
    }

    static func sanitizedPreferredInputDeviceUID(_ value: Any?) -> String? {
        MixerRoutingSupport.sanitizedDeviceUID(value)
    }

    static let audioPriorityMaxListSize = 64

    static func sanitizedAudioPriorityUIDs(_ raw: [Any]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in raw {
            guard let uid = MixerRoutingSupport.sanitizedDeviceUID(value),
                  seen.insert(uid).inserted else { continue }
            result.append(uid)
            if result.count >= audioPriorityMaxListSize { break }
        }
        return result
    }

    static func sanitizedAudioPriorityDeviceNames(_ raw: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (rawUID, rawName) in raw {
            guard let uid = MixerRoutingSupport.sanitizedDeviceUID(rawUID),
                  let name = MixerRoutingSupport.sanitizedDeviceUID(rawName) else { continue }
            result[uid] = name
        }
        return result
    }
}
