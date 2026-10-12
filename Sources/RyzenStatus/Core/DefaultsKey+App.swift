// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

extension DefaultsKey {
    static let panelShowAmdPower = "panelShowAmdPower"
    static let appearance = "appAppearance"               // AppAppearance.rawValue
    static let liquidGlassEnabled = "liquidGlassEnabled"  // Liquid Glass visual styling on macOS 26+
    static let mouseSpacesGestureEnabled = "mouseSpacesGestureEnabled"
    static let mouseSpacesGestureButton = "mouseSpacesGestureButton"
    static let whatsAppDownloadsEnabled = "whatsAppDownloadsEnabled"
    static let diskEjectExcludedVolumes = "diskEjectExcludedVolumes"
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
    static let dockPreviewOpenDelay = "dockPreviewOpenDelay"
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
    static let audioPriorityOutputEnabled = "audioPriorityOutputEnabled"
    static let audioPriorityInputEnabled = "audioPriorityInputEnabled"
    static let audioPriorityOutputUIDs = "audioPriorityOutputUIDs"    // [String] ordered device UIDs
    static let audioPriorityInputUIDs = "audioPriorityInputUIDs"     // [String] ordered device UIDs
    static let audioPriorityDeviceNames = "audioPriorityDeviceNames" // [uid: name] last-known names
    static let finderCutPasteEnabled = "finderCutPasteEnabled"
    static let finderRenameEnabled = "finderRenameEnabled"
    static let finderRenameShortcut = "finderRenameShortcut"
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
    static let shelfDockPlacement = "shelfDockPlacement"   // ShelfDockPlacement raw value
    static let shelfEdgeDragEnabled = "shelfEdgeDragEnabled"
    static let shelfClearOnClose = "shelfClearOnClose"
    static let shelfShortcutAddsFinderSelection = "shelfShortcutAddsFinderSelection"
    static let extraBrightnessEnabled = "extraBrightnessEnabled"
    static let extraBrightnessLevel = "extraBrightnessLevel"   // Int percent 0-100
    static let bluetoothSleepEnabled = "bluetoothSleepEnabled"
    static let bluetoothEnabled = "bluetoothEnabled"
    static let bluetoothSleepRestoreOnWake = "bluetoothSleepRestoreOnWake"
    // Set only while RyzenStatus owes a Bluetooth restore, so a Mac shut down
    // while asleep still gets it back on the next launch.
    static let bluetoothSleepRestorePending = "bluetoothSleepRestorePending"
    static let brightnessControlEnabled = "brightnessControlEnabled" // sliders for every display
    static let brightnessKeysEnabled = "brightnessKeysEnabled" // brightness keys act on the display under the pointer
    static let brightnessOSDEnabled = "brightnessOSDEnabled" // brightness adjustment overlay
    static let musicBlockEnabled = "musicBlockEnabled"
    static let musicBlockReplacementPath = "musicBlockReplacementPath"  // app bundle path ("" = none)
    static let nowPlayingEnabled = "nowPlayingEnabled"
    static let nowPlayingMenuBarText = "nowPlayingMenuBarText" // legacy: show the track next to the menu bar icon
    static let nowPlayingMenuBarMode = "nowPlayingMenuBarMode" // NowPlayingMenuBarMode.rawValue (0 icon, 1 artist, 2 song, 3 artist+song)
    static let nowPlayingMenuBarProgress = "nowPlayingMenuBarProgress" // thin progress strip under the menu bar text
    static let nowPlayingMarquee = "nowPlayingMarquee" // scroll overflowing menu bar text (pause, scroll, loop)
    static let nowPlayingMarqueeSlide = "nowPlayingMarqueeSlide" // slide the text in when the track changes
    static let nowPlayingArtworkSize = "nowPlayingArtworkSize" // popup artwork tile size in pt (120–260)
    static let nowPlayingUnloadWhenHidden = "nowPlayingUnloadWhenHidden" // drop the popup content while the popover is hidden
    static let nowPlayingPreferredProvider = "nowPlayingPreferredProvider" // NowPlayingProvider.rawValue (0 auto, 1 music, 2 spotify)
    static let nowPlayingOpenInApp = "nowPlayingOpenInApp" // click the track title to activate its app
    static let nowPlayingShowArtwork = "nowPlayingShowArtwork" // artwork in the menu panel section
    static let nowPlayingArtworkAnimation = "nowPlayingArtworkAnimation" // crossfade when the artwork changes
    static let nowPlayingMiniMode = "nowPlayingMiniMode" // popup shows the compact artwork-first layout
    static let nowPlayingDetachedOnTop = "nowPlayingDetachedOnTop" // detached window floats above other apps
    static let nowPlayingDetachedSize = "nowPlayingDetachedSize" // NowPlayingDetachedSize.rawValue (0 small, 1 medium, 2 large)
    static let nowPlayingDetachedOriginX = "nowPlayingDetachedOriginX" // last dragged position of the detached window
    static let nowPlayingDetachedOriginY = "nowPlayingDetachedOriginY"
    static let nowPlayingDetailsPane = "nowPlayingDetailsPane"
    static let nowPlayingAnimatedArtwork = "nowPlayingAnimatedArtwork" // stream Apple Music editorial animated artwork over the cover
    static let nowPlayingAnimatedArtworkQuality = "nowPlayingAnimatedArtworkQuality" // NowPlayingAnimatedArtworkQuality.rawValue (0 adaptive, 1 max, 2 data saver)
    static let nowPlayingTheme = "nowPlayingTheme" // NowPlayingThemeStyle.rawValue (artworkAdaptive | frosted | midnight | warmStudio | highContrast | graphite)
    static let nowPlayingArtworkColorIntensity = "nowPlayingArtworkColorIntensity" // how strongly theme colors tint the popup (0.5–1.8)
    static let nowPlayingArtworkBlend = "nowPlayingArtworkBlend" // how much artwork colors blend into preset themes (0–1)
    static let nowPlayingPopupShortcut = "nowPlayingPopupShortcut" // GlobalShortcut storage value: toggle the popup popover
    static let nowPlayingPopupShortcutEnabled = "nowPlayingPopupShortcutEnabled"
    static let nowPlayingDetachedShortcut = "nowPlayingDetachedShortcut" // GlobalShortcut storage value: toggle the detached window
    static let nowPlayingDetachedShortcutEnabled = "nowPlayingDetachedShortcutEnabled"
    static let panelShowNowPlaying = "panelShowNowPlaying"
    static let cleanerScheduleFrequency = "cleanerScheduleFrequency"    // off | daily | weekly
    static let cleanerScheduleHour = "cleanerScheduleHour"
    static let cleanerScheduleMinute = "cleanerScheduleMinute"
    static let cleanerScheduleWeekday = "cleanerScheduleWeekday"        // 1 Sunday ... 7 Saturday
    static let cleanerScheduleNotify = "cleanerScheduleNotify"
    static let cleanerLastAutoRun = "cleanerLastAutoRun"                // Double, epoch seconds
    static let cleanerBadgeSeen = "cleanerBadgeSeen"
    static let killProcessCommandBarEnabled = "killProcessCommandBarEnabled"
    static let killProcessGroupRelated = "killProcessGroupRelated"
    static let killProcessSortBy = "killProcessSortBy" // cpu | memory | name | pid
    static let killProcessSortAscending = "killProcessSortAscending"
    static let cleanerScreenshotAgeDays = "cleanerScreenshotAgeDays"            // Int days, 0 turns the search off
    static let cleanerLastAutoFreed = "cleanerLastAutoFreed"            // Int bytes
    static let cleanerLastAutoFailed = "cleanerLastAutoFailed"          // Int items left behind by the last automatic pass
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
    // Homebrew: "Update all" skips formulas that brew would compile from
    // source on this Mac (node, llvm, ...), avoiding hours-long builds.
    static let homebrewSkipHeavyFormulas = "homebrewSkipHeavyFormulas"
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
    static let mediaVideoSizing = "mediaVideoSizing"
    static let mediaVideoTargetMegabytes = "mediaVideoTargetMegabytes"
    static let mediaGIFStart = "mediaGIFStart"
    static let mediaGIFEnd = "mediaGIFEnd"
    static let mediaGIFQuality = "mediaGIFQuality"
    static let mediaGIFWidth = "mediaGIFWidth"
    static let mediaGIFFPS = "mediaGIFFPS"
    static let mediaGIFLoops = "mediaGIFLoops"
    static let mediaGIFSizing = "mediaGIFSizing"
    static let mediaGIFTargetMegabytes = "mediaGIFTargetMegabytes"
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
    static let clipboardHistoryQuickPreview = "clipboardHistoryQuickPreview"
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
    static let scratchpadDocument = "scratchpadDocument"
    static let micMuteActive = "micMuteActive"               // mic muted by the app (survives relaunch)
    static let micMuteSavedVolume = "micMuteSavedVolume"     // input volume to restore on unmute (pre 3.2.0 state)
    static let micMuteSavedVolumes = "micMuteSavedVolumes"   // [device uid: input volume] to restore on unmute
    static let micMuteSavedChannelVolumes = "micMuteSavedChannelVolumes" // [device uid: [channel: input volume]] to restore on unmute
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
    static let linearScrollExceptions = "linearScrollExceptions"
    static let focusFollowsMouseExceptions = "focusFollowsMouseExceptions"

    // Mouse extras ported from upstream (all off by default).
    static let scrollHorizontalEnabled = "scrollHorizontalEnabled"
    static let scrollHorizontalModifier = "scrollHorizontalModifier" // ScrollHorizontalModifier.rawValue
    static let focusFollowsMouseEnabled = "focusFollowsMouseEnabled"
    static let focusFollowsMouseDelay = "focusFollowsMouseDelayMilliseconds"
    static let focusFollowsMouseRaise = "focusFollowsMouseRaise"
    static let focusFollowsMouseWaitForStop = "focusFollowsMouseWaitForStop"
    static let linearScrollEnabled = "linearScrollEnabled" // every mouse wheel notch scrolls the same lines
    static let linearScrollLines = "linearScrollLines"     // lines per wheel notch while linear scrolling is on
    static let mouseAccelerationDisabled = "mouseAccelerationDisabled" // linear pointer mode for mice; restored on quit
    static let mouseClickDebounceEnabled = "mouseClickDebounceEnabled"
    static let mouseClickDebounceWindowMs = "mouseClickDebounceWindowMs"
    static let spacesOrderEnabled = "spacesOrderEnabled" // keeps macOS from rearranging Spaces by recent use (Dock mru-spaces)
    static let spacesOrderRestore = "spacesOrderRestore" // local recovery; never backed up: "absent" or "on", the mru-spaces state to put back, or "off" when there was nothing to put back
    static let spacesOrderRestartPending = "spacesOrderRestartPending" // local recovery; never backed up: "<Dock pid> <fixed|rearranging> <absent|on|off>…"
    static let panelControlFocusFollowsMouse = "panelControlFocusFollowsMouse"
    static let panelControlLinearScroll = "panelControlLinearScroll"
    static let panelControlMouseAcceleration = "panelControlMouseAcceleration"
    static let panelControlMouseClickDebounce = "panelControlMouseClickDebounce"
    static let panelControlSpacesOrder = "panelControlSpacesOrder"

    // Mouse button shortcuts: programmable mouse buttons.
    static let mouseButtonShortcutsEnabled = "mouseButtonShortcutsEnabled"
    static let mouseButtonShortcuts = "mouseButtonShortcuts"  // Data: [String: String] JSON

    // Super Key: keyboard source remapping.
    static let superKeyEnabled = "superKeyEnabled"
    static let superKeySource = "superKeySource"                // SuperKeySource.rawValue
    static let superKeyModifiers = "superKeyModifiers"          // storage format for modifier combinations
    static let superKeySoloAction = "superKeySoloAction"        // SuperKeySoloAction.rawValue
    static let superKeyMappingApplied = "superKeyMappingApplied"  // internal guard
    static let superKeyMappedSource = "superKeyMappedSource"    // source key of currently applied mapping

    // Snippet library: text expansion library.
    static let snippetLibraryEnabled = "snippetLibraryEnabled"
    static let snippetLibraryShortcut = "snippetLibraryShortcut"  // GlobalShortcut storage value

    // Text snippets: type a trigger, get the expansion.
    static let textSnippetsEnabled = "textSnippetsEnabled"
    static let textSnippets = "textSnippets"              // Data: [TextSnippet] JSON
    static let snippetSoundEnabled = "snippetSoundEnabled"
    static let snippetSoundName = "snippetSoundName"      // file name in /System/Library/Sounds

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
    static let showPmTableCoresInPanel = "showPmTableCoresInPanel" // Bool, per-core clock/temp/power disclosure in the AMD Power panel section
    static let showPmCoreVoltage = "showPmCoreVoltage"           // Bool, per-core SMU voltage column in the panel rows
    static let showPmCoreC0 = "showPmCoreC0"                     // Bool, per-core C0 residency column in the panel rows
    static let showPmCoreCC6 = "showPmCoreCC6"                   // Bool, per-core CC6 residency column in the panel rows
    static let fanCurvesEditorEnabled = "fanCurvesEditorEnabled"   // Bool, Fans & Cooling curve editor toggle (persisted)
    static let customCurvesV2 = "customCurves_v2"                 // Data: [FanCurveDefinition] JSON
    static let fanMappingsV2 = "fanMappings_v2"                   // Data: [Int: Int] JSON (fanId -> curveSlot, -1 = auto)
    // Hardware validation (Wave V) — probe checklist statuses + recorded samples
    // as one JSON blob, so a probe cycle that spans reboots keeps its evidence.
    static let validationRecord = "hardwareValidationRecord"       // String: HardwareValidation.Record JSON
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
    static let switcherAppearanceDelay = "switcherAppearanceDelay"
    static let dockClickHide = "dockClickHide"
    static let urlCleanerCustomParameters = "urlCleanerCustomParameters"
    static let panelControlDockClickHide = "panelControlDockClickHide"
    static let screenshotClipboardShortcutEnabled = "screenshotClipboardShortcutEnabled"
    static let screenshotClipboardShortcut = "screenshotClipboardShortcut"
    static let recentCapturesShortcutEnabled = "recentCapturesShortcutEnabled"
    static let recentCapturesShortcut = "recentCapturesShortcut"
    static let screenshotShowCaptureMenuOnShortcut = "screenshotShowCaptureMenuOnShortcut"
    static let recorderShowCaptureMenuOnShortcut = "recorderShowCaptureMenuOnShortcut"
    static let screenOCRShowCaptureMenuOnShortcut = "screenOCRShowCaptureMenuOnShortcut"
    static let colorPickerShowCaptureMenuOnShortcut = "colorPickerShowCaptureMenuOnShortcut"
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

    // Dynamic Island / Notch keys
    static let notchEnabled = "notchEnabled"
    static let notchSize = "notchSize"
    static let notchDisplay = "notchDisplay"
    static let notchSilhouette = "notchSilhouette"
    static let notchCustomWidth = "notchCustomWidth"
    static let notchCustomHeight = "notchCustomHeight"
    static let notchCameraFitWidth = "notchCameraFitWidth"
    static let notchCameraFitHeight = "notchCameraFitHeight"
    static let notchCapsuleFitWidth = "notchCapsuleFitWidth"
    static let notchCapsuleFitHeight = "notchCapsuleFitHeight"
    static let notchCapsuleFitDrop = "notchCapsuleFitDrop"
    static let notchHideMenuBarGap = "notchHideMenuBarGap"
    static let notchOutlineEnabled = "notchOutlineEnabled"
    static let notchCoversMenus = "notchCoversMenus"
    static let notchOpenOnHover = "notchOpenOnHover"
    static let notchHoverExpands = "notchHoverExpands"
    static let notchHoverDelay = "notchHoverDelay"
    static let notchCloseDelay = "notchCloseDelay"
    static let notchHideUntilHover = "notchHideUntilHover"
    static let notchHideInFullscreen = "notchHideInFullscreen"
    static let notchHapticFeedback = "notchHapticFeedback"
    static let notchIdleContent = "notchIdleContent"
    static let notchCapsuleCenter = "notchCapsuleCenter"
    static let notchCapsuleMetric = "notchCapsuleMetric"
    static let notchShowPlayingMusic = "notchShowPlayingMusic"
    static let notchReturnHome = "notchReturnHome"
    static let notchHomeModule = "notchHomeModule"
    static let notchOpensActivity = "notchOpensActivity"
    static let notchHiddenModules = "notchHiddenModules"
    static let notchModuleOrder = "notchModuleOrder"
    static let notchControlOrder = "notchControlOrder"
    static let notchHiddenControls = "notchHiddenControls"
    static let notchQuickAccessLayout = "notchQuickAccessLayout"
    static let notchQuickAccessSide = "notchQuickAccessSide"
    static let notchQuickAccessSecond = "notchQuickAccessSecond"
    static let notchQuickAccessThird = "notchQuickAccessThird"
    static let notchQuickPanel = "notchQuickPanel"
    static let notchAppPanel = "notchAppPanel"
    static let notchScratchpad = "notchScratchpad"
    static let notchShelf = "notchShelf"
    static let notchDragReveal = "notchDragReveal"
    static let notchCaptureControls = "notchCaptureControls"
    static let notchVolume = "notchVolume"
    static let notchMicrophone = "notchMicrophone"
    static let notchBrightness = "notchBrightness"
    static let notchBattery = "notchBattery"
    static let notchClipboard = "notchClipboard"
    static let notchClipboardWindow = "notchClipboardWindow"
    static let notchCapture = "notchCapture"
    static let notchTrackChange = "notchTrackChange"
    static let notchShowInCaptures = "notchShowInCaptures"
    static let notchHideInCaptures = "notchHideInCaptures"
    static let notchLowBatteryTint = "notchLowBatteryTint"
    static let notchLowBatteryThreshold = "notchLowBatteryThreshold"
    static let notchLowBatteryEarly = "notchLowBatteryEarly"
    static let notchLowBatteryEarlyThreshold = "notchLowBatteryEarlyThreshold"
    static let notchLowBatteryMenuBar = "notchLowBatteryMenuBar"
    static let notchTimerEnabled = "notchTimerEnabled"
    static let notchTimerMode = "notchTimerMode"
    static let notchTimerMinutes = "notchTimerMinutes"
    static let notchTimerSoundEnabled = "notchTimerSoundEnabled"
    static let notchHideTimerCountdown = "notchHideTimerCountdown"
    static let notchPomodoroFocusMinutes = "notchPomodoroFocusMinutes"
    static let notchPomodoroShortBreakMinutes = "notchPomodoroShortBreakMinutes"
    static let notchPomodoroLongBreakMinutes = "notchPomodoroLongBreakMinutes"
    static let notchPomodoroLongBreakInterval = "notchPomodoroLongBreakInterval"
    static let notchPomodoroTotalSessions = "notchPomodoroTotalSessions"
    static let notchCameraEnabled = "notchCameraEnabled"
    static let notchCalendarEnabled = "notchCalendarEnabled"
    static let notchCalendarCountdown = "notchCalendarCountdown"
    static let notchCalendarTimeLeft = "notchCalendarTimeLeft"
    static let notchCalendarWeekNumbers = "notchCalendarWeekNumbers"
    static let notchCalendarExcluded = "notchCalendarExcluded"
    static let notchCalendarChosenCountdowns = "notchCalendarChosenCountdowns"
    static let notchNotificationsEnabled = "notchNotificationsEnabled"
    static let notchDismissNativeNotifications = "notchDismissNativeNotifications"
    static let notchAccessoriesEnabled = "notchAccessoriesEnabled"
    static let notchDownloadsEnabled = "notchDownloadsEnabled"
    static let notchDownloadsFolderBookmark = "notchDownloadsFolderBookmark"
    static let notchWatchEnabled = "notchWatchEnabled"
    static let notchWatchSound = "notchWatchSound"
    static let notchWatchCondition = "notchWatchCondition"
    static let notchKeyboardLight = "notchKeyboardLight"
    static let notchKeyboardLightControlHidden = "notchKeyboardLightControlHidden"
    static let notchMascotEnabled = "notchMascotEnabled"
    static let notchMascotVisits = "notchMascotVisits"
    static let notchMascotReactions = "notchMascotReactions"
    static let notchMascotStyle = "notchMascotStyle"
    static let notchMascotShape = "notchMascotShape"
    static let notchMascotPalette = "notchMascotPalette"
    static let notchMascotSide = "notchMascotSide"
    static let notchMascotVisitFrequency = "notchMascotVisitFrequency"
    static let notchMascotHidesWhenIdle = "notchMascotHidesWhenIdle"
    static let notchMascotBetaInstalled = "notchMascotBetaInstalled"
    /// Automatic reactions to what the Mac does, and each kind of them.
    static let notchMascotAutomatic = "notchMascotAutomatic"
    static let notchMascotAutoLoad = "notchMascotAutoLoad"
    static let notchMascotAutoMusic = "notchMascotAutoMusic"
    static let notchMascotAutoRest = "notchMascotAutoRest"
    static let notchMascotAutoCoffee = "notchMascotAutoCoffee"
    static let notchMascotAutoNetwork = "notchMascotAutoNetwork"
    static let notchMascotAutoEvents = "notchMascotAutoEvents"
    static let notchMascotAutoAntics = "notchMascotAutoAntics"
    static let notchCommandBar = "notchCommandBar"
    static let notchCommandBarStyle = "notchCommandBarStyle"
    static let notchLockScreen = "notchLockScreen"
    static let notchLockSounds = "notchLockSounds"
    static let notchGesturesEnabled = "notchGesturesEnabled"
    static let notchLyricsEnabled = "notchLyricsEnabled"
    static let notchLyricsOnline = "notchLyricsOnline"
    static let notchLiveEqualizer = "notchLiveEqualizer"
    static let notchQueueEnabled = "notchQueueEnabled"
    static let notchMusicActivity = "notchMusicActivity"
    static let notchHidesMenuBarIcon = "notchHidesMenuBarIcon"
    static let notchKeepAwakeActivity = "notchKeepAwakeActivity"
    static let notchPreferredPlayer = "notchPreferredPlayer"
    static let notchIncludeOtherPlayers = "notchIncludeOtherPlayers"
    static let notchTranslucentBackground = "notchTranslucentBackground"
    static let notchLiquidGlassEnabled = "notchLiquidGlassEnabled"
    static let notchDefaultProfileInitialized = "notchDefaultProfileInitialized"
    static let notchInitialExtensionsInstalled = "notchInitialExtensionsInstalled"
    static let notchScratchpadControlHidden = "notchScratchpadControlHidden"
    static let panelControlNotch = "panelControlNotch"
    static let notchAgentsEnabled = "notchAgentsEnabled"
    /// Whether the uninstaller offers its rows in the command bar. Off by
    /// default: the bar's uninstall actions are opt-in.
    static let uninstallerCommandBarEnabled = "uninstallerCommandBarEnabled"
    static let commandBarEnabled = "commandBarEnabled"
    static let commandBarShortcutEnabled = "commandBarShortcutEnabled"
    static let commandBarShortcut = "commandBarShortcut"
    /// Compact mode: an empty field shows nothing but itself. Off by default.
    static let commandBarCompactMode = "commandBarCompactMode"
    /// The ASCII layout borrowed while the bar is open, restored on close. Off by default.
    static let commandBarASCIILayoutEnabled = "commandBarASCIILayoutEnabled"
    static let commandBarUsage = "commandBarUsage"           // per-command run counts, never queries
    static let commandBarQueryHabits = "commandBarQueryHabits" // keyed query digests → selected row ids
    static let commandBarQueryHabitKey = "commandBarQueryHabitKey" // local key for stable digests
    static let commandBarDisabledSources = "commandBarDisabledSources" // kinds of result switched off
    static let commandBarAliases = "commandBarAliases"       // {row id: the name the person gave it}
    static let commandBarPins = "commandBarPins"             // row keys kept at the top, in order
    static let commandBarHidden = "commandBarHidden"         // row keys the person never wants offered
    static let commandBarLinks = "commandBarLinks"           // Data: [CommandBarLink] JSON
    static let commandBarRowShortcuts = "commandBarRowShortcuts" // {row key: shortcut}
    static let commandBarPositionOffset = "commandBarPositionOffset" // "dx,dy" from the default spot
    static let commandBarEmojiSkinTone = "commandBarEmojiSkinTone" // "" is the yellow default
    /// The folders a file search looks in, one per line, written with a tilde
    /// so an exported list still points somewhere on another Mac. Empty means
    /// the bar looks for no files at all, which is the setting out of the box.
    static let commandBarFileScopes = "commandBarFileScopes"
    static let commandBarFileIgnores = "commandBarFileIgnores" // names a file search never shows
    static let panelUtilityCommandBar = "panelUtilityCommandBar"
    static let panelUtilityPortManager = "panelUtilityPortManager"
    static let mixerAppArrangement = "mixerAppArrangement"
    static let mixerHideInactiveApps = "mixerHideInactiveApps"
    static let mixerHiddenApps = "mixerHiddenApps"
    static let scratchpadTextSize = "scratchpadTextSize"
    static let networkSpeedUnit = "networkSpeedUnit"

    // MARK: Ported from upstream fe24c17 (block A, shared foundations)
    // Keys for areas that are still being ported live here already, so each
    // area compiles against them. Upstream keeps them in Core/Defaults.swift;
    // here they sit in this extension because the command bar harness
    // compiles this file and not Defaults.swift. Upstream fan control keys are
    // left out on purpose: fan control belongs to the AMD layer.
    static let dimScreenOnLidClose = "dimScreenOnLidClose" // dim the built-in display to zero while the lid is closed
    static let featureHubKeptFeatures = "featureHubKeptFeatures" // comma-joined AppFeature raw values
    static let brightnessUpdatePromptState = "brightnessUpdatePromptState"
    static let keepAwakeRunningApps = "keepAwakeRunningApps"
    static let keepAwakeRunningAppBundleIDs = "keepAwakeRunningAppBundleIDs"
    // Match mode over the automation conditions: false is Any (one matching
    // condition starts a session), true is All (every enabled condition has
    // to match, and losing one ends the session). Issue #1587.
    static let keepAwakeAutomationRequireAll = "keepAwakeAutomationRequireAll"
    static let keepAwakePauseWhenLocked = "keepAwakePauseWhenLocked"
    static let keepAwakeSwitchUsesUntil = "keepAwakeSwitchUsesUntil" // panel switch restarts the Until chip
    static let keepAwakeUntilTime = "keepAwakeUntilTime"  // last picked end time; 0 = none yet
    static let dimmedDisplaySavedBrightness = "ryzenstatusDimmedDisplaySavedBrightness" // internal guard for closed-lid screen dimming recovery
    static let smoothScrollResponse = "smoothScrollResponse" // 0...100, higher follows the wheel sooner
    static let smoothScrollCoast = "smoothScrollCoast" // 0...100, higher coasts the same distance out longer
    static let mouseSpacesGestureFollowsDrag = "mouseSpacesGestureFollowsDrag" // the Space moves with the hand, the way natural scrolling does
    static let superKeyExceptions = "superKeyExceptions"
    static let switcherTakeOverSystemShortcuts = "switcherTakeOverSystemShortcuts"
    // Machine state, never exported: the system shortcuts this process owns,
    // so a launch after a crash can restore them. The switcher-only key is
    // what builds before the take-over was shared wrote; it is read once,
    // folded into the shared one, and then retired.
    static let switcherNativeHotkeysSuppressed = "switcherNativeHotkeysSuppressed"
    static let systemShortcutsSuppressed = "systemShortcutsSuppressed"
    // Storage keys of shortcuts the user chose to take over from macOS. A
    // preference, exported.
    static let systemShortcutTakeOverKeys = "systemShortcutTakeOverKeys"
    static let switcherMinimizedPlacement = "switcherMinimizedPlacement"
    static let switcherTreatHiddenAppsLikeMinimized = "switcherTreatHiddenAppsLikeMinimized"
    static let switcherShowFullscreenWindows = "switcherShowFullscreenWindows"
    static let switcherInstantSelection = "switcherInstantSelection" // skip selection and reveal animations while browsing
    static let switcherScreenPlacement = "switcherScreenPlacement" // SwitcherScreenPlacement raw value: which display the panel opens on
    static let switcherCurrentDisplayOnly = "switcherCurrentDisplayOnly" // list only windows on the display under the pointer (issue #1391)
    static let minimalWindowPreviews = "minimalWindowPreviews"
    static let dockPreviewKeepDockVisible = "dockPreviewKeepDockVisible"
    static let dockPreviewRestoreAutohide = "dockPreviewRestoreAutohide" // local crash recovery; never backed up
    static let dockPreviewCurrentSpaceOnly = "dockPreviewCurrentSpaceOnly"
    static let dockPreviewQuitAppOnClose = "dockPreviewQuitAppOnClose" // the preview card's close button quits the owning app instead of closing one window
    static let dockPreviewOrderByCreation = "dockPreviewOrderByCreation" // order Dock Preview windows by ascending window ID (creation proxy) instead of last use
    static let switcherPreviewSize = "switcherPreviewSize" // app switcher thumbnail size
    static let includeBetaUpdates = "includeBetaUpdates"
    static let mixerUniversalOutputDevice = "mixerUniversalOutputDevice" // retired: all-apps output saved by 3.4.1 betas
    static let preciseVolumeRollerEnabled = "preciseVolumeRollerEnabled"
    static let finderCutPasteShowHUD = "finderCutPasteShowHUD"
    static let finderPasteImageAsFile = "finderPasteImageAsFile"
    static let brightnessKeyStep = "brightnessKeyStep" // BrightnessSupport.KeyStep raw value
    static let displayBrightnessShortcutsEnabled = "displayBrightnessShortcutsEnabled"
    static let displayBrightnessDecreaseShortcut = "displayBrightnessDecreaseShortcut"
    static let displayBrightnessIncreaseShortcut = "displayBrightnessIncreaseShortcut"
    static let keyboardBrightnessShortcutsEnabled = "keyboardBrightnessShortcutsEnabled"
    static let keyboardBrightnessDecreaseShortcut = "keyboardBrightnessDecreaseShortcut"
    static let keyboardBrightnessIncreaseShortcut = "keyboardBrightnessIncreaseShortcut"
    // Per-monitor connection paths that accept brightness writes but never
    // answer reads. Kept local so wake handling does not repeatedly probe a
    // sensitive display path.
    static let brightnessDDCWriteOnlyPaths = "brightnessDDCWriteOnlyPaths"
    // Set once the paths cached before paired discovery requests have been
    // dropped, so a monitor written off then is classified again exactly once.
    static let brightnessDDCWriteOnlyPathsRechecked = "brightnessDDCWriteOnlyPathsRechecked"
    // Per-monitor connection paths a person has told this app to dim in
    // software: the only way to know a write-only channel swallows its writes
    // is to watch the panel, which no probe can do. Issue #1589.
    static let brightnessForcedSoftwarePaths = "brightnessForcedSoftwarePaths"
    // Per-monitor connections where the lower end of the brightness slider
    // also dims the picture below the panel's hardware minimum.
    static let brightnessExtendedDimmingPaths = "brightnessExtendedDimmingPaths"
    // Displays this app switched off, so a run that ends without putting them
    // back can be repaired on the next start instead of needing a replug.
    static let displaysSwitchedOff = "displaysSwitchedOff"
    // Identity saved before disabling each display, kept separate so older
    // versions can still read the repair list of display numbers.
    static let displaysSwitchedOffFingerprints = "displaysSwitchedOffFingerprints"
    // Set while a start is under way and cleared once the app has run
    // healthily for a while, or when it is quit properly. Found still set at
    // the next start, it means the previous one died on the way up.
    static let startupDidNotFinish = "startupDidNotFinish"
    static let musicBlockPlayReplacement = "musicBlockPlayReplacement" // play after Play/Pause opens the replacement
    static let urlCleanerSiteParameters = "urlCleanerSiteParameters"       // host|name pairs added to one site
    static let urlCleanerDisabledParameters = "urlCleanerDisabledParameters" // built-in host|name pairs switched off
    static let windowMaximizeExcludedApps = "windowMaximizeExcludedApps" // [bundle id] whose green button stays native
    static let cleaningModeKeepScreenVisible = "cleaningModeKeepScreenVisible"
    // Keep the legacy homebrew feature ID; the provider preference is portable.
    static let packageManagerProvider = "packageManagerProvider" // automatic | macPorts | homebrew
    static let homebrewGroupDependencies = "homebrewGroupDependencies"
    static let appUpdatesIncludeOnlineCatalog = "appUpdatesIncludeOnlineCatalog"
    static let appUpdatesRules = "appUpdatesRules" // JSON, portable bundle-ID rules
    // Findings already announced once, so a pending update nobody installs
    // does not speak up again after every relaunch.
    static let appUpdatesNotifiedIDs = "appUpdatesNotifiedIDs"
    static let panelControlMouseButtonShortcuts = "panelControlMouseButtonShortcuts"
    static let panelToggleKeyboardLight = "panelToggleKeyboardLight"
    // Keep the existing storage key so moving the row preserves its visibility choice.
    static let panelToggleMicMute = "panelUtilityMicMute"
    static let menuBarConnectedDevices = "menuBarConnectedDevices"
    static let menuBarIconSymbol = "menuBarIconSymbol" // system symbol name drawn instead of the glyph; empty keeps the glyph
    static let menuBarDiskStyle = "menuBarDiskStyle"       // percent | free | used
    static let monitorGraphScale = "monitorGraphScale"
    static let monitorSysCPUCores = "monitorSysCPUCores"
    static let monitorNetAddresses = "monitorNetAddresses"
    static let monitorPwrTemperature = "monitorPwrTemperature"
    static let monitorAlertBatteryTemperature = "monitorAlertBatteryTemperature"
    static let monitorAlertBatteryTemperatureThreshold = "monitorAlertBatteryTemperatureThreshold"
    static let windowLayoutWindowGap = "windowLayoutWindowGap" // px between adjacent snapped windows
    static let windowLayoutScreenGap = "windowLayoutScreenGap" // px between a snapped window and the visible frame edge
    static let windowLayoutMarginPercent = "windowLayoutMarginPercent" // per-edge percentage for margin maximize
    static let windowLayoutSideRepeatCyclesThirds = "windowLayoutSideRepeatCyclesThirds" // repeated Left/Right cycles half, 2/3, 1/3 on the same display
    static let windowLayoutIgnoredApps = "windowLayoutIgnoredApps" // apps that temporarily disable window layout while focused
    static let mediaImageResizeKind = "mediaImageResizeKind"
    static let mediaImageResizeWidth = "mediaImageResizeWidth"
    static let mediaImageResizeHeight = "mediaImageResizeHeight"
    static let mediaImageExactResizeMode = "mediaImageExactResizeMode"
    static let mediaImageWatermarkKind = "mediaImageWatermarkKind"
    static let mediaImageWatermarkText = "mediaImageWatermarkText"
    static let mediaImageWatermarkLogoPath = "mediaImageWatermarkLogoPath"
    static let mediaImageWatermarkPosition = "mediaImageWatermarkPosition"
    static let mediaImageWatermarkOpacity = "mediaImageWatermarkOpacity"
    static let mediaImageWatermarkMargin = "mediaImageWatermarkMargin"
    static let mediaImageWatermarkScale = "mediaImageWatermarkScale"
    static let mediaImageRenamePattern = "mediaImageRenamePattern"
    static let mediaImageBackground = "mediaImageBackground"
    static let mediaImagePreserveModificationDate = "mediaImagePreserveModificationDate"
    static let mediaImageSaveInSubfolder = "mediaImageSaveInSubfolder"
    static let mediaImageProfiles = "mediaImageProfiles"
    static let mediaImageSelectedProfileID = "mediaImageSelectedProfileID"
    static let clipboardHistoryLayout = "clipboardHistoryLayout" // cards | list, how the history window shows entries
    static let clipboardHistoryWindowWidth = "clipboardHistoryWindowWidth" // the list window's chosen size
    static let clipboardHistoryWindowHeight = "clipboardHistoryWindowHeight"
    static let clipboardHistoryMenuBarPreview = "clipboardHistoryMenuBarPreview" // show latest copy next to the menu bar icon
    static let clipboardHistoryMenuBarPreviewLength = "clipboardHistoryMenuBarPreviewLength" // characters shown before truncating
    // Auto clear: wipes the system pasteboard on a delay or on sleep and lock.
    // Deliberately outside the clipboardHistory family, since it clears the
    // pasteboard without touching saved entries, and runs with capture off.
    static let clipboardAutoClearOnDelay = "clipboardAutoClearOnDelay"
    static let clipboardAutoClearDelay = "clipboardAutoClearDelaySeconds" // seconds since the last copy
    static let clipboardAutoClearOnSleep = "clipboardAutoClearOnSleep"
    static let clipboardAutoClearOnDisplaySleep = "clipboardAutoClearOnDisplaySleep"
    static let clipboardAutoClearOnScreenLock = "clipboardAutoClearOnScreenLock"
    static let switcherPreviewExcludedApps = "switcherPreviewExcludedApps" // pause app switcher thumbnail capture while these apps are in front
    static let screenOCRRemoveLineBreaks = "screenOCRRemoveLineBreaks"
    static let scratchpadBackgroundOpacity = "scratchpadBackgroundOpacity" // opaque fill over the pad material (ScratchpadSupport.backgroundOpacityRange)
    static let unifiedScreenCaptureShortcutMigrated = "unifiedScreenCaptureShortcutMigrated"
    static let restoredScreenCaptureShortcutsMigrated = "restoredScreenCaptureShortcutsMigrated"
    static let orphanedCaptureShortcutMigrated = "orphanedCaptureShortcutMigrated"
    static let screenshotHighlightWindows = "screenshotHighlightWindows"
    static let screenshotLoupeStartsOn = "screenshotLoupeStartsOn"
    static let screenshotLoupeRememberZoom = "screenshotLoupeRememberZoom"
    static let screenshotLoupeDefaultZoom = "screenshotLoupeDefaultZoom"
    static let screenshotLoupeLastZoom = "screenshotLoupeLastZoom"
    static let screenshotLoupeSteppedZoomByDefault = "screenshotLoupeSteppedZoomByDefault"
    static let screenshotLastTextSize = "screenshotLastTextSize"
    static let screenshotLastBlurLevel = "screenshotLastBlurLevel"
    static let screenshotLastBlurStyle = "screenshotLastBlurStyle"
    static let screenshotLastBlurTextOnly = "screenshotLastBlurTextOnly"
    static let screenshotLastArrowStyle = "screenshotLastArrowStyle"
    static let screenshotToolShortcuts = "screenshotToolShortcuts"
    static let screenshotWatermarkStyle = "screenshotWatermarkStyle"
    static let screenshotWatermarkPresets = "screenshotWatermarkPresets"
    static let screenshotAddToShelf = "screenshotAddToShelf"
    static let screenshotPreviewTakesFocus = "screenshotPreviewTakesFocus"
    static let screenshotUploadShortcutEnabled = "screenshotUploadShortcutEnabled"
    static let screenshotUploadShortcut = "screenshotUploadShortcut"
    static let screenshotUploadDuration = "screenshotUploadDuration"
    static let screenshotPreviewEnabled = "screenshotPreviewEnabled"
    static let screenshotPreviewDuration = "screenshotPreviewDuration"
    // Machine state, never exported: whether this Mac's audio system has let
    // a recording hear the Mac's sound through a process tap.
    static let recorderSystemAudioTapVerified = "recorderSystemAudioTapVerified"
    static let recorderAutomaticZoom = "recorderAutomaticZoom"
    static let panelUtilityScreenRecorder = "panelUtilityScreenRecorder"
    static let windowDirectionalEnabled = "windowDirectionalEnabled"
    static let windowDirectionalShortcut = "windowDirectionalShortcut"
    static let pointerDisplayEnabled = "pointerDisplayEnabled"
    static let pointerDisplayShortcut = "pointerDisplayShortcut"
    static let windowEdgeSnapEnabled = "windowEdgeSnapEnabled"
    static let windowEdgeSnapDisabledZones = "windowEdgeSnapDisabledZones" // comma-separated visual zone ids
    static let windowEdgeSnapZoneActions = "windowEdgeSnapZoneActions" // zone=action entries, + between split areas
    static let windowLayoutShortcutCenterHalf = "windowLayoutShortcutCenterHalf"
    static let windowLayoutShortcutCenterTwoThirds = "windowLayoutShortcutCenterTwoThirds"
    static let windowLayoutShortcutTopThird = "windowLayoutShortcutTopThird"
    static let windowLayoutShortcutMiddleThird = "windowLayoutShortcutMiddleThird"
    static let windowLayoutShortcutBottomThird = "windowLayoutShortcutBottomThird"
    static let windowLayoutShortcutTopTwoThirds = "windowLayoutShortcutTopTwoThirds"
    static let windowLayoutShortcutBottomTwoThirds = "windowLayoutShortcutBottomTwoThirds"
    static let windowLayoutShortcutTopQuarter = "windowLayoutShortcutTopQuarter"
    static let windowLayoutShortcutUpperMiddleQuarter = "windowLayoutShortcutUpperMiddleQuarter"
    static let windowLayoutShortcutLowerMiddleQuarter = "windowLayoutShortcutLowerMiddleQuarter"
    static let windowLayoutShortcutBottomQuarter = "windowLayoutShortcutBottomQuarter"
    static let windowLayoutShortcutLeftQuarter = "windowLayoutShortcutLeftQuarter"
    static let windowLayoutShortcutLeftMiddleQuarter = "windowLayoutShortcutLeftMiddleQuarter"
    static let windowLayoutShortcutRightMiddleQuarter = "windowLayoutShortcutRightMiddleQuarter"
    static let windowLayoutShortcutRightQuarter = "windowLayoutShortcutRightQuarter"
    static let windowLayoutShortcutFullScreen = "windowLayoutShortcutFullScreen"
    static let notchAgentsOptInMigrated = "notchAgentsOptInMigrated" // local migration marker; never backed up
    static let notchAgentsClaude = "notchAgentsClaude"
    static let notchAgentsCodex = "notchAgentsCodex"
    static let notchAgentsOpenCode = "notchAgentsOpenCode"
    static let notchAgentsCopilot = "notchAgentsCopilot"
    static let notchAgentsCardOrder = "notchAgentsCardOrder"
    static let notchAgentsHiddenCards = "notchAgentsHiddenCards"
    static let notchAgentsPeriod = "notchAgentsPeriod"
    static let notchAgentsLimitDisplay = "notchAgentsLimitDisplay"
    static let notchAgentsLimitFocus = "notchAgentsLimitFocus"
    static let notchAgentsLiveActivity = "notchAgentsLiveActivity"
    static let notchAgentsReadout = "notchAgentsReadout"
    static let notchAgentsFinishAlert = "notchAgentsFinishAlert"
    static let notchAgentsFinishMinimum = "notchAgentsFinishMinimum"
    static let notchAgentsLimitAlert = "notchAgentsLimitAlert"
    static let notchAgentsLimitThreshold = "notchAgentsLimitThreshold"
    static let notchAgentsDailyBudget = "notchAgentsDailyBudget"
    static let notchAgentsPriceUpdates = "notchAgentsPriceUpdates"
    static let notchInputSource = "notchInputSource"
    static let radialMenuActivationMode = "radialMenuActivationMode" // RadialMenuActivationMode.rawValue
    static let radialMenuProfiles = "radialMenuProfiles"  // Data: [RadialMenuProfile] JSON
    static let simulateBetaUI = "simulateBetaUI"
}
