// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

extension DefaultsKey {
    static let panelShowAmdPower = "panelShowAmdPower"
    static let appearance = "appAppearance"               // AppAppearance.rawValue
    static let language = "appLanguage"                   // AppLanguage.rawValue
    static let clamshellPreferred = "clamshellPreferred"  // apply closed-lid mode to every session
    static let onboardingStep = "onboardingStep"          // resume point if onboarding is interrupted
    static let featuresOnboardingVersion = "featuresOnboardingVersion" // last feature-tour marker handled
    static let lastUpdateIntroVersion = "lastUpdateIntroVersion"
    static let dockPreviewIntroVersion = "dockPreviewIntroVersion"
    static let supportUpdateIntroVersion = "supportUpdateIntroVersion"
    static let updateHighlightsSeenVersion = "updateHighlightsSeenVersion"
    static let updateShowcaseIntroVersion = "updateShowcaseIntroVersion"
    static let updateShowcaseMediaOverride = "updateShowcaseMediaOverride"
    static let defaultDuration = "defaultDurationMinutes" // 0 = indefinite
    static let batteryLimit = "batteryLimitPercent"       // 0 = never
    static let keepAwakeAutoStart = "keepAwakeAutoStart"  // start Keep Awake when the app launches
    static let keepAwakeExternalDisplay = "keepAwakeExternalDisplay"
    static let keepAwakeConnectedToPower = "keepAwakeConnectedToPower"
    static let keepAwakeMouseJiggleEnabled = "keepAwakeMouseJiggleEnabled"
    static let keepAwakeMouseJiggleInterval = "keepAwakeMouseJiggleIntervalMinutes"
    static let hotkeyEnabled = "hotkeyEnabled"
    static let launchAtLoginWanted = "launchAtLoginWanted"  // the user's choice; the system record can be lost
    static let keepAwakeShortcut = "keepAwakeShortcut"    // GlobalShortcut storage value
    static let keepAwakeIconTint = "keepAwakeIconTint"    // KeepAwakeIconTint.rawValue
    static let keepAwakeActiveIcon = "keepAwakeActiveIcon" // KeepAwakeActiveIcon.rawValue
    static let showCountdown = "showCountdownInMenuBar"
    static let statusItemPlacementGeneration = "statusItemPlacementGeneration"
    static let hasOnboarded = "hasOnboarded"
    static let sleepDisabledFlag = "ryzenstatusDisabledSleep"   // internal guard for pmset disablesleep
    static let scrollInverterEnabled = "scrollInverterEnabled"
    static let smoothScrollEnabled = "smoothScrollEnabled"
    static let smoothScrollStep = "smoothScrollStep"      // pixels per wheel tick
    static let mouseNavigationEnabled = "mouseNavigationEnabled" // side buttons trigger Back and Forward
    static let switcherEnabled = "switcherEnabled"
    static let switcherShortcut = "switcherShortcut"      // GlobalShortcut storage value
    static let switcherWindowShortcut = "switcherWindowShortcut" // GlobalShortcut storage value
    static let switcherIconRowMode = "switcherIconRowMode"
    static let switcherSimpleMode = "switcherSimpleMode"  // app-only row without window captures
    static let switcherMergeTabs = "switcherMergeTabs"     // show one switcher entry per app (collapse all of an app's windows)
    static let switcherWindowlessApps = "switcherWindowlessApps" // SwitcherWindowlessApps raw value
    static let switcherAppRules = "switcherAppRules" // [bundle id: SwitcherAppRule raw value]
    static let windowPreviewExcludedApps = "windowPreviewExcludedApps" // pause thumbnail capture while these apps are in front
    static let switcherCurrentSpaceOnly = "switcherCurrentSpaceOnly" // list only windows on the desktop the user is in
    static let whatsAppDownloadsAutomaticEnabled = "whatsAppDownloadsAutomaticEnabled"
    static let whatsAppDownloadsCategories = "whatsAppDownloadsCategories"
    static let whatsAppDownloadsRetentionDays = "whatsAppDownloadsRetentionDays"
    static let whatsAppDownloadsNotify = "whatsAppDownloadsNotify"
    static let whatsAppDownloadsIncludeExisting = "whatsAppDownloadsIncludeExisting"
    static let whatsAppDownloadsAutomaticStartDate = "whatsAppDownloadsAutomaticStartDate"
    static let whatsAppDownloadsLastAutoRun = "whatsAppDownloadsLastAutoRun"
    static let whatsAppDownloadsLastCleanup = "whatsAppDownloadsLastCleanup"
    static let whatsAppDownloadsLastCleanupCount = "whatsAppDownloadsLastCleanupCount"
    static let whatsAppDownloadsLastCleanupBytes = "whatsAppDownloadsLastCleanupBytes"
    static let whatsAppDownloadsLastCleanupFailed = "whatsAppDownloadsLastCleanupFailed"
    static let whatsAppDownloadsLastCleanupAutomatic = "whatsAppDownloadsLastCleanupAutomatic"
    static let whatsAppDownloadsExclusions = "whatsAppDownloadsExclusions"
    static let whatsAppDownloadsAccessConfirmed = "whatsAppDownloadsAccessConfirmed"
    static let whatsAppOrganizerEnabled = "whatsAppOrganizerEnabled"
    static let whatsAppOrganizerDestinationPath = "whatsAppOrganizerDestinationPath"
    static let whatsAppOrganizerDelayMinutes = "whatsAppOrganizerDelayMinutes"
    static let whatsAppOrganizerCategories = "whatsAppOrganizerCategories"
    static let whatsAppOrganizerLayout = "whatsAppOrganizerLayout"
    static let whatsAppOrganizerDuplicateAction = "whatsAppOrganizerDuplicateAction"
    static let whatsAppOrganizerRecords = "whatsAppOrganizerRecords"
    static let whatsAppOrganizerUndoTransaction = "whatsAppOrganizerUndoTransaction"
    static let whatsAppOrganizerLastRun = "whatsAppOrganizerLastRun"
    static let whatsAppOrganizerLastMoved = "whatsAppOrganizerLastMoved"
    static let whatsAppOrganizerLastDuplicates = "whatsAppOrganizerLastDuplicates"
    static let whatsAppOrganizerLastFailed = "whatsAppOrganizerLastFailed"
    static let switcherShowWindowlessFinder = "switcherShowWindowlessFinder"
    static let dockPreviewEnabled = "dockPreviewEnabled"
    static let dockPreviewBackgroundOpacity = "dockPreviewBackgroundOpacity"
    static let dockClickMinimize = "dockClickMinimize"    // click the active app's Dock icon to minimize its windows
    static let dockClickCycleWindows = "dockClickCycleWindows" // click the active app's Dock icon to cycle through its windows
    static let middleClickEnabled = "middleClickEnabled"  // three-finger PHYSICAL click on the trackpad acts as a middle click
    static let middleClickTapFingers = "middleClickTapFingers"  // 0 = off (default); 3 or 4 = a light tap with that many fingers also middle-clicks (issue #161)
    static let previewSize = "previewSize"                // app switcher + dock preview thumbnail size
    static let autoCheckUpdates = "autoCheckUpdates"
    static let checkPrereleases = "checkPrereleases"       // include pre-releases when checking
    static let releaseNotesOnUpdate = "releaseNotesOnUpdate" // show What's New after an update
    static let appVolumes = "appVolumes"                  // [bundle id: 0...2]
    static let appOutputDevices = "appOutputDevices"      // [bundle id: audio device UID]
    static let mixerShowFinder = "mixerShowFinder"
    static let mixerLowerVolumeOnHeadphonesDisconnect = "mixerLowerVolumeOnHeadphonesDisconnect"
    static let mixerHeadphonesDisconnectVolumePercent = "mixerHeadphonesDisconnectVolumePercent"
    static let soundOutputSwitcherEnabled = "soundOutputSwitcherEnabled"
    static let soundOutputSwitcherShortcut = "soundOutputSwitcherShortcut"
    static let soundOutputSwitcherDeviceUIDs = "soundOutputSwitcherDeviceUIDs"
    static let preferredInputDevice = "preferredInputDevice" // audio input device UID
    static let finderCutPasteEnabled = "finderCutPasteEnabled"
    static let autoQuitEnabled = "autoQuitEnabled"
    static let autoQuitExceptions = "autoQuitExceptions"  // [bundle id] kept running
    static let shelfEnabled = "shelfEnabled"
    static let shelfShortcutEnabled = "shelfShortcutEnabled"
    static let shelfShortcut = "shelfShortcut"            // GlobalShortcut storage value
    static let shelfShakeToOpen = "shelfShakeToOpen"
    static let shelfDropZoneEnabled = "shelfDropZoneEnabled"
    static let shelfCloseAfterDrop = "shelfCloseAfterDrop"
    static let shelfRemoveAfterDrop = "shelfRemoveAfterDrop"
    static let shelfAutomaticExclusions = "shelfAutomaticExclusions" // [bundle id] blocks automatic opening only
    static let extraBrightnessEnabled = "extraBrightnessEnabled"
    static let extraBrightnessLevel = "extraBrightnessLevel"   // Int percent 0-100
    static let brightnessControlEnabled = "brightnessControlEnabled" // sliders for every display
    static let brightnessKeysEnabled = "brightnessKeysEnabled" // brightness keys act on the display under the pointer
    static let brightnessOSDEnabled = "brightnessOSDEnabled" // brightness adjustment overlay
    static let musicBlockEnabled = "musicBlockEnabled"
    static let musicBlockReplacementPath = "musicBlockReplacementPath"  // app bundle path ("" = none)
    static let nowPlayingEnabled = "nowPlayingEnabled"
    static let nowPlayingMenuBarText = "nowPlayingMenuBarText" // legacy: show the track next to the menu bar icon
    static let nowPlayingMenuBarMode = "nowPlayingMenuBarMode" // NowPlayingMenuBarMode.rawValue (0 icon, 1 artist, 2 song, 3 artist+song)
    static let nowPlayingMenuBarProgress = "nowPlayingMenuBarProgress" // thin progress strip under the menu bar text
    static let nowPlayingPreferredProvider = "nowPlayingPreferredProvider" // NowPlayingProvider.rawValue (0 auto, 1 music, 2 spotify)
    static let nowPlayingOpenInApp = "nowPlayingOpenInApp" // click the track title to activate its app
    static let nowPlayingShowArtwork = "nowPlayingShowArtwork" // artwork in the menu panel section
    static let panelShowNowPlaying = "panelShowNowPlaying"
    static let cleanerScheduleFrequency = "cleanerScheduleFrequency"    // off | daily | weekly
    static let cleanerScheduleHour = "cleanerScheduleHour"
    static let cleanerScheduleMinute = "cleanerScheduleMinute"
    static let cleanerScheduleWeekday = "cleanerScheduleWeekday"        // 1 Sunday ... 7 Saturday
    static let cleanerScheduleNotify = "cleanerScheduleNotify"
    static let cleanerLastAutoRun = "cleanerLastAutoRun"                // Double, epoch seconds
    static let cleanerBadgeSeen = "cleanerBadgeSeen"
    static let cleanerLastAutoFreed = "cleanerLastAutoFreed"            // Int bytes
    static let processListRefreshInterval = "processListRefreshInterval" // process list breakdown refresh rate (seconds)
    static let settingsWindowWidth = "settingsWindowWidth"     // last user-chosen content size (0 = unset)
    static let settingsWindowHeight = "settingsWindowHeight"
    static let shelfItems = "shelfItems"                  // Data: [ShelfPersistedItem] JSON
    static let urlCleanerEnabled = "urlCleanerEnabled"
    static let windowMaximizeEnabled = "windowMaximizeEnabled"
    static let keyboardDebounceEnabled = "keyboardDebounceEnabled"
    static let keyboardDebounceWindowMs = "keyboardDebounceWindowMs"
    static let keyboardDebounceKeyWindows = "keyboardDebounceKeyWindows" // comma-separated keyCode:ms
    static let panelUtilityCleaning = "panelUtilityCleaning"
    static let panelUtilityURLCleaner = "panelUtilityURLCleaner"
    static let panelUtilityUninstaller = "panelUtilityUninstaller"
    static let panelUtilityCleaner = "panelUtilityCleaner"
    static let panelUtilityHomebrew = "panelUtilityHomebrew"
    static let panelUtilityAppUpdates = "panelUtilityAppUpdates"
    static let appUpdatesCheckFrequency = "appUpdatesCheckFrequency"  // off | daily | weekly
    static let appUpdatesIncludeHomebrewApps = "appUpdatesIncludeHomebrewApps"
    static let appUpdatesIncludeAppStore = "appUpdatesIncludeAppStore"
    static let appUpdatesNotify = "appUpdatesNotify"
    static let appUpdatesLastCheck = "appUpdatesLastCheck"            // Double, epoch seconds
    static let appUpdatesLastCount = "appUpdatesLastCount"
    static let panelUtilityMedia = "panelUtilityMedia"
    static let panelUtilityClipboard = "panelUtilityClipboard"
    static let panelUtilityWindowLayout = "panelUtilityWindowLayout"
    static let panelControlMouseScroll = "panelControlMouseScroll"
    static let panelControlMouseNavigation = "panelControlMouseNavigation"
    static let panelControlSwitcher = "panelControlSwitcher"
    static let panelControlDockPreview = "panelControlDockPreview"
    static let panelControlCutPaste = "panelControlCutPaste"
    static let panelControlAutoQuit = "panelControlAutoQuit"
    static let panelControlShelf = "panelControlShelf"
    static let panelControlWindowMaximize = "panelControlWindowMaximize"
    static let panelControlKeyDebounce = "panelControlKeyDebounce"
    static let panelControlDockClick = "panelControlDockClick"
    static let panelControlDockClickCycle = "panelControlDockClickCycle"
    static let panelControlMiddleClick = "panelControlMiddleClick"
    static let panelControlTextSnippets = "panelControlTextSnippets"
    static let panelControlRadialMenu = "panelControlRadialMenu"
    static let panelControlSuperKey = "panelControlSuperKey"
    // Quick-control categories start collapsed and remember being opened.
    static let panelControlWindowsExpanded = "panelControlWindowsExpanded"
    static let panelControlInputExpanded = "panelControlInputExpanded"
    static let panelControlFilesExpanded = "panelControlFilesExpanded"
    // Show/hide whole panel sections that have no monitorShow* key of their own.
    static let panelShowKeepAwake = "panelShowKeepAwake"
    static let panelShowBrightness = "panelShowBrightness"
    static let panelShowUtilities = "panelShowUtilities"
    static let panelShowControls = "panelShowControls"
    static let panelShowToggles = "panelShowToggles"
    static let panelAccordionMode = "panelAccordionMode"
    // Quick toggles tab: per-action visibility (the order lives in panelToggleOrder).
    static let panelToggleDarkMode = "panelToggleDarkMode"
    static let panelToggleEmptyTrash = "panelToggleEmptyTrash"
    static let panelToggleEjectDisks = "panelToggleEjectDisks"
    static let panelToggleHiddenFiles = "panelToggleHiddenFiles"
    static let panelToggleDesktopIcons = "panelToggleDesktopIcons"
    static let panelToggleLockScreen = "panelToggleLockScreen"
    static let panelToggleDisplayOff = "panelToggleDisplayOff"
    static let panelToggleScreenSaver = "panelToggleScreenSaver"

    static let temperatureUnit = "temperatureUnit"          // celsius | fahrenheit
    // Menu panel layout — the order the major sections appear in and which are
    // collapsed, both comma-joined section ids (see PanelSectionID). Absent keys
    // mean the canonical order and nothing collapsed, so no defaults registration.
    static let panelSectionOrder = "panelSectionOrder"
    static let panelUtilityOrder = "panelUtilityOrder"
    static let panelControlOrder = "panelControlOrder"
    static let panelToggleOrder = "panelToggleOrder"
    static let panelSystemOrder = "panelSystemOrder"
    static let panelNetworkOrder = "panelNetworkOrder"
    static let panelDiskOrder = "panelDiskOrder"
    static let panelPowerOrder = "panelPowerOrder"
    static let panelNavigationEnabled = "panelNavigationEnabled" // legacy: the panel always navigates by sections since 3.1.8
    static let updateLastInstallFailure = "updateLastInstallFailure" // last installer step that failed (fail-copy etc.)
    static let windowLayoutHiddenActions = "windowLayoutHiddenActions" // comma-separated action ids hidden from the grid
    static let panelCollapsedSections = "panelCollapsedSections"
    static let panelCollapsedResetVersion = "panelCollapsedResetVersion"

    // Media utility — local video, GIF, image and OCR tools.
    static let mediaLastTool = "mediaLastTool"
    static let mediaVideoStart = "mediaVideoStart"
    static let mediaVideoEnd = "mediaVideoEnd"
    static let mediaVideoQuality = "mediaVideoQuality"
    static let mediaVideoMaxDimension = "mediaVideoMaxDimension"
    static let mediaVideoFPS = "mediaVideoFPS"
    static let mediaVideoKeepAudio = "mediaVideoKeepAudio"
    static let mediaVideoCodec = "mediaVideoCodec"
    static let mediaGIFStart = "mediaGIFStart"
    static let mediaGIFEnd = "mediaGIFEnd"
    static let mediaGIFQuality = "mediaGIFQuality"
    static let mediaGIFWidth = "mediaGIFWidth"
    static let mediaGIFFPS = "mediaGIFFPS"
    static let mediaGIFLoops = "mediaGIFLoops"
    static let mediaImageQuality = "mediaImageQuality"
    static let mediaImageMaxDimension = "mediaImageMaxDimension"
    static let mediaImageFormat = "mediaImageFormat"
    static let mediaImageStripMetadata = "mediaImageStripMetadata"
    static let mediaTextAccurate = "mediaTextAccurate"
    static let mediaTextLanguageCorrection = "mediaTextLanguageCorrection"

    // Clipboard history — text only, opt-in and local.
    static let clipboardHistoryEnabled = "clipboardHistoryEnabled"
    static let clipboardHistoryEntries = "clipboardHistoryEntries"
    static let clipboardHistoryLimit = "clipboardHistoryLimit"
    static let clipboardHistorySkipSensitive = "clipboardHistorySkipSensitive"
    static let clipboardHistoryIncludeImagesFiles = "clipboardHistoryIncludeImagesFiles" // capture copied images and files too
    // Quick tools: paste as plain text, color picker, screen OCR, mic mute.
    static let pastePlainEnabled = "pastePlainEnabled"
    static let pastePlainShortcut = "pastePlainShortcut"
    static let colorPickerShortcutEnabled = "colorPickerShortcutEnabled"
    static let colorPickerShortcut = "colorPickerShortcut"
    static let colorPickerFormat = "colorPickerFormat"       // hex | rgb | hsl | swiftui
    static let colorPickerBareHex = "colorPickerBareHex"     // copy HEX without the leading #
    static let screenOCRShortcutEnabled = "screenOCRShortcutEnabled"
    static let screenOCRShortcut = "screenOCRShortcut"
    static let screenOCRDetectQRCodes = "screenOCRDetectQRCodes" // QR content wins over OCR text
    static let micMuteShortcutEnabled = "micMuteShortcutEnabled"
    static let micMuteShortcut = "micMuteShortcut"
    static let cameraPreviewShortcutEnabled = "cameraPreviewShortcutEnabled"
    static let cameraPreviewShortcut = "cameraPreviewShortcut"
    static let scratchpadShortcutEnabled = "scratchpadShortcutEnabled"
    static let scratchpadShortcut = "scratchpadShortcut"
    static let scratchpadRetention = "scratchpadRetention"   // never | day | week | month
    static let scratchpadCloseOnClickOutside = "scratchpadCloseOnClickOutside" // dismiss pad on click outside
    static let micMuteActive = "micMuteActive"               // mic muted by the app (survives relaunch)
    static let micMuteSavedVolume = "micMuteSavedVolume"     // input volume to restore on unmute (pre 3.2.0 state)
    static let micMuteSavedVolumes = "micMuteSavedVolumes"   // [device uid: input volume] to restore on unmute
    static let micMuteMutedDevices = "micMuteMutedDevices"   // uids of the devices this app muted
    static let micMuteMenuBarIndicator = "micMuteMenuBarIndicator" // badge the status icon while muted
    static let quickLauncherShortcutEnabled = "quickLauncherShortcutEnabled"
    static let quickLauncherShortcut = "quickLauncherShortcut"
    static let quickLauncherItemOrder = "quickLauncherItemOrder"
    static let quickLauncherHiddenItems = "quickLauncherHiddenItems"
    static let panelUtilityQuickLauncher = "panelUtilityQuickLauncher"
    static let panelUtilityColorPicker = "panelUtilityColorPicker"
    static let panelUtilityScreenOCR = "panelUtilityScreenOCR"
    static let panelUtilityMicMute = "panelUtilityMicMute"
    static let panelUtilityCameraPreview = "panelUtilityCameraPreview"
    static let panelUtilityScratchpad = "panelUtilityScratchpad"
    static let clipboardHistoryShortcutEnabled = "clipboardHistoryShortcutEnabled"
    static let clipboardHistoryIgnoredApps = "clipboardHistoryIgnoredApps" // apps whose copies are never saved
    static let clipboardHistoryShortcut = "clipboardHistoryShortcut"
    // Screenshot capture and editor.
    static let screenshotShortcutEnabled = "screenshotShortcutEnabled"
    static let screenshotShortcut = "screenshotShortcut"
    static let screenshotFreeze = "screenshotFreeze"
    static let screenshotSaveFolder = "screenshotSaveFolder"
    static let screenshotIncludePointer = "screenshotIncludePointer"
    static let screenshotDownscale = "screenshotDownscale"
    static let screenshotDelay = "screenshotDelay"
    static let screenshotLastTool = "screenshotLastTool"
    static let screenshotLastColor = "screenshotLastColor"
    static let screenshotLastStroke = "screenshotLastStroke"
    static let screenshotLastSticker = "screenshotLastSticker"
    static let screenshotAnnotationShadows = "screenshotAnnotationShadows"
    static let screenshotToolOrder = "screenshotToolOrder"
    static let screenshotToolShortcutsEnabled = "screenshotToolShortcutsEnabled"
    static let screenshotBackdropStyle = "screenshotBackdropStyle"
    static let screenshotBackdropPresets = "screenshotBackdropPresets"
    static let screenshotOpenEditorDirectly = "screenshotOpenEditorDirectly"
    static let screenshotFullScreenShortcutEnabled = "screenshotFullScreenShortcutEnabled"
    static let screenshotFullScreenShortcut = "screenshotFullScreenShortcut"
    static let screenshotLastCaptureShortcutEnabled = "screenshotLastCaptureShortcutEnabled"
    static let screenshotLastCaptureShortcut = "screenshotLastCaptureShortcut"
    static let screenshotShowLastRegion = "screenshotShowLastRegion"
    static let screenshotCopyToClipboard = "screenshotCopyToClipboard"
    static let screenshotSaveSubfolder = "screenshotSaveSubfolder"
    static let screenshotFileNamePattern = "screenshotFileNamePattern"
    static let screenshotFileNumberStart = "screenshotFileNumberStart"
    static let screenshotFileNumberNext = "screenshotFileNumberNext"
#if DEBUG
    static let screenshotSharingDeveloperEndpoint = "screenshotSharingDeveloperEndpoint"
#endif
    static let screenshotDefaultAction = "screenshotDefaultAction"

    // Screen recorder - records the picked area, keeps the untouched master
    static let recorderShortcutEnabled = "recorderShortcutEnabled"
    static let recorderShortcut = "recorderShortcut"
    static let recorderCountdown = "recorderCountdown"
    static let recorderQuality = "recorderQuality"
    static let recorderFrameRate = "recorderFrameRate"
    static let recorderSystemAudio = "recorderSystemAudio"
    static let recorderSaveFolder = "recorderSaveFolder"
    static let recorderOpenEditor = "recorderOpenEditor"
    static let recorderGIFSize = "recorderGIFSize"
    static let recorderGIFFrameRate = "recorderGIFFrameRate"
    static let recorderEditorPresets = "recorderEditorPresets"

    static let panelUtilityScreenshot = "panelUtilityScreenshot"

    // Window Layout — snapping, global shortcuts and optional pointer gestures.
    static let windowLayoutShortcutsEnabled = "windowLayoutShortcutsEnabled"
    static let windowGestureEnabled = "windowGestureEnabled"
    static let windowGestureModifiers = "windowGestureModifiers"
    static let windowGestureRaiseWindow = "windowGestureRaiseWindow"
    static let windowLayoutShortcutLeft = "windowLayoutShortcutLeft"
    static let windowLayoutShortcutRight = "windowLayoutShortcutRight"
    static let windowLayoutShortcutTop = "windowLayoutShortcutTop"
    static let windowLayoutShortcutBottom = "windowLayoutShortcutBottom"
    static let windowLayoutShortcutTopLeft = "windowLayoutShortcutTopLeft"
    static let windowLayoutShortcutTopRight = "windowLayoutShortcutTopRight"
    static let windowLayoutShortcutBottomLeft = "windowLayoutShortcutBottomLeft"
    static let windowLayoutShortcutBottomRight = "windowLayoutShortcutBottomRight"
    static let windowLayoutShortcutMaximize = "windowLayoutShortcutMaximize"
    static let windowLayoutShortcutCenter = "windowLayoutShortcutCenter"
    static let windowLayoutShortcutRestore = "windowLayoutShortcutRestore"
    static let windowLayoutShortcutLeftThird = "windowLayoutShortcutLeftThird"
    static let windowLayoutShortcutCenterThird = "windowLayoutShortcutCenterThird"
    static let windowLayoutShortcutRightThird = "windowLayoutShortcutRightThird"
    static let windowLayoutShortcutLeftTwoThirds = "windowLayoutShortcutLeftTwoThirds"
    static let windowLayoutShortcutRightTwoThirds = "windowLayoutShortcutRightTwoThirds"
    static let windowLayoutShortcutNextDisplay = "windowLayoutShortcutNextDisplay"
    static let windowLayoutShortcutTopLeftSixth = "windowLayoutShortcutTopLeftSixth"
    static let windowLayoutShortcutTopCenterSixth = "windowLayoutShortcutTopCenterSixth"
    static let windowLayoutShortcutTopRightSixth = "windowLayoutShortcutTopRightSixth"
    static let windowLayoutShortcutBottomLeftSixth = "windowLayoutShortcutBottomLeftSixth"
    static let windowLayoutShortcutBottomCenterSixth = "windowLayoutShortcutBottomCenterSixth"
    static let windowLayoutShortcutBottomRightSixth = "windowLayoutShortcutBottomRightSixth"

    // Per-app exceptions for mouse features.
    static let smoothScrollExceptions = "smoothScrollExceptions"  // [String]
    static let scrollInverterExceptions = "scrollInverterExceptions"
    static let mouseNavigationExceptions = "mouseNavigationExceptions"
    static let mouseButtonExceptions = "mouseButtonExceptions"
    static let middleClickExceptions = "middleClickExceptions"

    // Mouse button shortcuts: programmable mouse buttons.
    static let mouseButtonShortcutsEnabled = "mouseButtonShortcutsEnabled"
    static let mouseButtonShortcuts = "mouseButtonShortcuts"  // Data: [String: String] JSON

    // Super Key: Caps Lock remapping.
    static let superKeyEnabled = "superKeyEnabled"
    static let superKeySoloAction = "superKeySoloAction"      // SuperKeySoloAction.rawValue
    static let superKeyMappingApplied = "superKeyMappingApplied"  // internal guard

    // Snippet library: text expansion library.
    static let snippetLibraryEnabled = "snippetLibraryEnabled"
    static let snippetLibraryShortcut = "snippetLibraryShortcut"  // GlobalShortcut storage value

    // Text snippets: type a trigger, get the expansion.
    static let textSnippetsEnabled = "textSnippetsEnabled"
    static let textSnippets = "textSnippets"              // Data: [TextSnippet] JSON

    // Radial menu: a wheel of actions on a shortcut.
    static let radialMenuEnabled = "radialMenuEnabled"
    static let radialMenuShortcut = "radialMenuShortcut"
    static let radialMenuAtPointer = "radialMenuAtPointer" // false: screen center
    static let radialMenuMouseButton = "radialMenuMouseButton" // RadialMenuMouseTrigger.rawValue
    static let radialMenuItems = "radialMenuItems"        // Data: [RadialMenuItem] JSON

    // AMD Auto EPP — thresholds for automatic EPP switching based on CPU load.
    static let autoEppEnabled = "autoEppEnabled"                 // Bool: whether software Auto EPP is active
    static let autoEppIdleThreshold = "autoEppIdleThreshold"     // 0-100, CPU load % below which → Power Save (255)
    static let autoEppLoadThreshold = "autoEppLoadThreshold"     // 0-100, CPU load % above which → Performance (0)
    // AMD Power Presets — one-tap EPP + CPB + PPM/LPM profiles.
    static let amdPowerPreset = "amdPowerPreset"                 // AMDPowerPreset.rawValue, written when applied
    // Per-toggle persistence for the Priority-1 control features.
    static let amdCpbEnabled = "amdCpbEnabled"                   // Bool, last Core Performance Boost state
    static let amdPpmEnabled = "amdPpmEnabled"                   // Bool, last PPM state
    static let amdLpmEnabled = "amdLpmEnabled"                   // Bool, last LPM state
    static let showFansInAmdPower = "showFansInAmdPower"         // Bool, fan picker DisclosureGroup expanded in the panel
    static let fanCurvesEditorEnabled = "fanCurvesEditorEnabled"   // Bool, Fans & Cooling curve editor toggle (persisted)
    // Gaming Mode — Extreme preset + Keep Awake + hidden menu bar icon.
    static let gamingModeActive = "gamingModeActive"             // Bool, persisted across launches
    static let gamingModeHideMenuBar = "gamingModeHideMenuBar"   // Bool, hide the status icon while active
    static let gamingModeRestorePreset = "gamingModeRestorePreset"   // AMDPowerPreset.rawValue, preset before the mode

    // Dev-build only: force the "update available" UI for local testing.
#if DEBUG
    static let simulateUpdate = "simulateUpdate"
#endif

    // Upstream-sync keys (3.3.1+): keep these aligned with the upstream base.
    static let keepAwakeRightClickToggle = "keepAwakeRightClickToggle"
    static let keepAwakeAllowDisplaySleep = "keepAwakeAllowDisplaySleep"
    static let scrollInverterHorizontalEnabled = "scrollInverterHorizontalEnabled"
    static let switcherSearchPinEnabled = "switcherSearchPinEnabled"
    static let switcherShowShortcutHints = "switcherShowShortcutHints"
    static let dockClickHide = "dockClickHide"
    static let urlCleanerCustomParameters = "urlCleanerCustomParameters"
    static let panelControlDockClickHide = "panelControlDockClickHide"
    static let screenshotClipboardShortcutEnabled = "screenshotClipboardShortcutEnabled"
    static let screenshotClipboardShortcut = "screenshotClipboardShortcut"
    // Renamed from the upstream screenshotHide…Windows key for the fork.
    static let screenshotHideRyzenStatusWindows = "screenshotHideRyzenStatusWindows"
    static let screenshotPreviewPosition = "screenshotPreviewPosition"
    static let screenshotSharingEnabled = "screenshotSharingEnabled"
    static let recorderMicrophone = "recorderMicrophone"
    static let recorderSharingEnabled = "recorderSharingEnabled"
    static let windowLayoutShortcutMarginMaximize = "windowLayoutShortcutMarginMaximize"
    static let windowLayoutShortcutPreviousDisplay = "windowLayoutShortcutPreviousDisplay"

    /// Features hub availability layer, one key per AppFeature raw value.
    /// Registered true: unavailable features vanish from every surface and
    /// hold no resources, without ever touching their own enable keys.
    static func featureAvailable(_ id: String) -> String { "featureAvailable.\(id)" }
}
