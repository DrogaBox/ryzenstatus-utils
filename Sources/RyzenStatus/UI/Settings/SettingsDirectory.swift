// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// One Settings page as the sidebar and the command bar present it.
struct SettingsDirectoryItem: Identifiable {
    let page: SettingsPage
    let title: String
    let icon: String
    /// Labels of options living inside the page, so a search finds a page by
    /// what it contains, in the user's language.
    var keywords: [String] = []
    var id: SettingsPage { page }
}

/// The single map of the Settings window: sections, pages, titles, icons and
/// search keywords. The sidebar draws its rows from these pages and the command
/// bar searches them; one list, so a page added here is findable everywhere.
/// Foundation-only, so the unit harness pins the map without SwiftUI.
enum SettingsDirectory {
    /// Pages with no row anywhere. None today: every page the window can show
    /// has a row, the Dynamic Island included. A page that should stay out of
    /// the sidebar and the command bar is listed here, so the coverage check
    /// in the unit harness still adds up.
    static let pagesWithoutRow: Set<SettingsPage> = []

    /// Pages an action row in the command bar already opens. Kept beside the
    /// map so the bar's coverage is one fact: every page the directory lists,
    /// plus these, plus `pagesWithoutRow`, is every page the window can show.
    static let pagesCoveredByActionRows: Set<SettingsPage> = [
        .general, .cleaner, .uninstaller, .appUpdates,
    ]

    /// Sections in sidebar order, each page with the title, the icon and the
    /// words a search can find it by.
    static func sections(_ s: Strings,
                         language: AppLanguage,
                         superKeySource: SuperKeySource) -> [(title: String, items: [SettingsDirectoryItem])] {
        let categories = FeatureStrings.settingsCategories(language)
        let hub = FeatureStrings.hub(language)
        return [
            (categories.essentials, [
                SettingsDirectoryItem(page: .dashboard, title: FeatureStrings.performanceSuite(language).dashboardTab,
                                      icon: "gauge.with.dots.needle.bottom.100percent"),
                SettingsDirectoryItem(page: .general, title: s.tabGeneral, icon: "gearshape",
                                      keywords: [s.launchAtLogin, s.languageLabel, s.showMenuBarIcon,
                                                 s.musicBlockTitle, s.musicBlockSection,
                                                 s.audioPrioritySection]),
                // Searching any feature name lands here even when the feature
                // is hidden, so the hub is always the way back.
                SettingsDirectoryItem(page: .features, title: hub.pageTitle,
                                      icon: "square.grid.2x2",
                                      keywords: AppFeature.allCases.map { $0.hubTitle(s, hub: hub) }),
                SettingsDirectoryItem(page: .energy, title: s.tabEnergy, icon: "bolt.fill",
                                      keywords: [s.keepAwakeTitle, s.clamshellTitle,
                                                 s.defaultDurationLabel, s.extraBrightnessName,
                                                 s.keepAwakeActiveIconLabel,
                                                 s.keepAwakeActiveIconCoffee,
                                                 s.keepAwakeActiveIconEye,
                                                 FeatureStrings.brightness(language).pageTitle,
                                                 FeatureStrings.brightness(language).osdToggle,
                                                 FeatureStrings.keepAwakeAutomation(language)
                                                     .externalDisplayToggle,
                                                 FeatureStrings.keepAwakeAutomation(language).powerToggle,
                                                 FeatureStrings.bluetoothSleep(language).pageTitle,
                                                 FeatureStrings.bluetoothSleep(language).enable]),
                SettingsDirectoryItem(page: .monitor, title: s.tabMonitor, icon: "chart.line.uptrend.xyaxis",
                                      keywords: [s.menuBarSpacingLabel, s.menuBarHideIconToggle,
                                                 s.monitorMemoryPressureDot]),
                SettingsDirectoryItem(page: .fans, title: FeatureStrings.fanControl(language).sidebarTitle,
                                      icon: "fanblades.fill"),
                SettingsDirectoryItem(page: .amdPower, title: FeatureStrings.amdPower(language).sidebarTitle,
                                      icon: "cpu.fill"),
                SettingsDirectoryItem(page: .amdOverclocking, title: "AMD Overclocking", icon: "flame.fill",
                                      keywords: ["overclock", "PBO", "curve optimizer", "voltage",
                                                 "frequency", "cHTC", "smu", "undervolt"]),
                SettingsDirectoryItem(page: .sensors, title: FeatureStrings.fanControl(language).sensorsSidebarTitle,
                                      icon: "thermometer.sun.fill"),
                SettingsDirectoryItem(page: .amdValidation, title: FeatureStrings.validation(language).sidebarTitle,
                                      icon: "checkmark.seal",
                                      keywords: ["validation", "probe", "kextstat", "hardware",
                                                 "selftest", "validación"]),
            ]),
            (categories.windowsControls, [
                SettingsDirectoryItem(page: .mouse, title: s.tabMouse, icon: "computermouse",
                                      keywords: [s.invertMouseScroll, s.middleClickTapPicker,
                                                 s.smoothScrollName, s.mouseNavigationEnable,
                                                 hub.titleMouseButtons, hub.titleSuperKey,
                                                 s.scrollHorizontalName, s.scrollHorizontalModifierLabel,
                                                 s.focusFollowsMouseName, s.focusFollowsMouseDelay,
                                                 s.focusFollowsMouseRaise, s.focusFollowsMouseWaitForStop,
                                                 s.linearScrollName, s.linearScrollLinesLabel,
                                                 s.mouseAccelerationName,
                                                 FeatureStrings.mouseClickDebounce(language).title,
                                                 FeatureStrings.mouseClickDebounce(language).windowLabel]),
                SettingsDirectoryItem(page: .mouseButtonShortcuts, title: hub.titleMouseButtons,
                                      icon: "button.programmable",
                                      keywords: ["mouse", "button", "shortcut"]),
                SettingsDirectoryItem(page: .superKey, title: hub.titleSuperKey, icon: superKeySource.systemImage,
                                      keywords: ["caps lock", "remap", "keyboard"]),
                SettingsDirectoryItem(page: .switcher, title: s.tabSwitcher, icon: "rectangle.on.rectangle",
                                      keywords: [s.switcherEnable, s.dockClickMinimize,
                                                 s.dockClickCycleWindows, s.spacesOrderName]),
                SettingsDirectoryItem(page: .windowLayout, title: FeatureStrings.windowLayout(language).title,
                                      icon: "rectangle.3.group",
                                      keywords: [s.dockClickCycleWindows,
                                                 FeatureStrings.windowLayout(language).gestureEnable,
                                                 FeatureStrings.windowLayout(language).gestureResize]),
                SettingsDirectoryItem(page: .autoQuit, title: s.autoQuitName, icon: "xmark.rectangle",
                                      keywords: [s.autoQuitEnable]),
                SettingsDirectoryItem(page: .quitProtection,
                                      title: FeatureStrings.quitProtection(language).name,
                                      icon: "shield.lefthalf.filled",
                                      keywords: [FeatureStrings.quitProtection(language).description, "⌘Q", "⌘W",
                                                 FeatureStrings.quitProtection(language).hold,
                                                 FeatureStrings.quitProtection(language).doublePress,
                                                 FeatureStrings.quitProtection(language).extraModifier]),
            ]),
            (categories.files, [
                SettingsDirectoryItem(page: .clipboard, title: FeatureStrings.clipboard(language).title,
                                      icon: "doc.on.clipboard",
                                      keywords: [FeatureStrings.clipboard(language).limit,
                                                 FeatureStrings.clipboard(language).skipSensitive]),
                SettingsDirectoryItem(page: .cutPaste, title: s.cutPasteName, icon: "scissors",
                                      keywords: [s.cutPasteEnable,
                                                 FeatureStrings.finderRename(language).hubTitle,
                                                 FeatureStrings.finderRename(language).enableLabel]),
                SettingsDirectoryItem(page: .shelf, title: s.shelfName, icon: "tray.full",
                                      keywords: [s.shelfEnable, s.shelfDropZoneToggle]),
                SettingsDirectoryItem(page: .media, title: s.mediaName, icon: "photo.on.rectangle.angled",
                                      keywords: ["PDF", "GIF", s.mediaStartConvertPDF, s.ocrName]),
            ]),
            // Everything about the apps installed on the Mac lives together:
            // what is out of date, what is junk and what should go.
            (categories.appManagement, [
                SettingsDirectoryItem(page: .appUpdates,
                                      title: FeatureStrings.appUpdates(language).pageTitle,
                                      icon: "arrow.down.app",
                                      keywords: [FeatureStrings.appUpdates(language).checkNow,
                                                 FeatureStrings.appUpdates(language).frequencyLabel,
                                                 FeatureStrings.appUpdates(language).appStoreBadge,
                                                 s.homebrewName]),
                SettingsDirectoryItem(page: .whatsAppDownloads,
                                      title: FeatureStrings.whatsAppDownloads(language).title,
                                      icon: "square.and.arrow.down",
                                      keywords: ["WhatsApp", "downloads", "cleanup", "organizer"]),
                SettingsDirectoryItem(page: .cleaner, title: s.cleanerName, icon: "sparkles",
                                      keywords: [s.cleanerScheduleTitle]),
                SettingsDirectoryItem(page: .homebrew, title: s.homebrewName, icon: "shippingbox"),
                SettingsDirectoryItem(page: .killProcess,
                                      title: FeatureStrings.killProcess(language).pageTitle,
                                      icon: "xmark.octagon",
                                      keywords: [FeatureStrings.killProcess(language).searchPlaceholder]),
                SettingsDirectoryItem(page: .portManager,
                                      title: FeatureStrings.portManager(language).title,
                                      icon: "network",
                                      keywords: [FeatureStrings.portManager(language).filter,
                                                 "port", "ports", "listening", "socket", "PID", "lsof"]),
                SettingsDirectoryItem(page: .commandBar,
                                      title: FeatureStrings.commandBar(language).pageTitle,
                                      icon: "command",
                                      keywords: [FeatureStrings.commandBar(language).openButton,
                                                 FeatureStrings.commandBar(language).searchPlaceholder,
                                                 FeatureStrings.commandBar(language).appCenterTitle,
                                                 FeatureStrings.commandBar(language).sourcesTitle]),
                SettingsDirectoryItem(page: .uninstaller, title: s.uninstallerName, icon: "trash"),
            ]),
            (categories.utilities, [
                // The companion is a tab of this page, so its name finds it too.
                SettingsDirectoryItem(page: .notch,
                                      title: FeatureStrings.notch(language).title,
                                      icon: "macbook",
                                      keywords: [FeatureStrings.notch(language).description,
                                                 FeatureStrings.notch(language).enable,
                                                 FeatureStrings.notchCalendar(language).weekNumbers,
                                                 hub.titleNotchGestures, hub.titleNotchMascot,
                                                 "notch"]),
                SettingsDirectoryItem(page: .quickTools, title: s.quickToolsTab, icon: "wand.and.rays",
                                      keywords: [s.launcherName, s.colorPickerName,
                                                 s.micMuteName, s.ocrName,
                                                 s.colorPickerBareHexToggle, s.micMuteMenuBarToggle,
                                                 FeatureStrings.quickToggles(language).pageTitle,
                                                 FeatureStrings.quickToggles(language).darkModeToDark,
                                                 FeatureStrings.quickToggles(language).emptyTrashTitle,
                                                 FeatureStrings.cameraPreview(language).pageTitle,
                                                 FeatureStrings.scratchpad(language).pageTitle,
                                                 FeatureStrings.wallpaper(language).pageTitle]),
                SettingsDirectoryItem(page: .screenshot,
                                      title: FeatureStrings.screenshot(language).pageTitle,
                                      icon: "camera.viewfinder",
                                      keywords: [FeatureStrings.screenshot(language).freezeToggle,
                                                 FeatureStrings.screenshot(language).pinButton,
                                                 FeatureStrings.screenshot(language).toolPixelate,
                                                 FeatureStrings.screenshot(language).toolArrow]),
                SettingsDirectoryItem(page: .screenRecorder,
                                      title: FeatureStrings.recorder(language).pageTitle,
                                      icon: "record.circle",
                                      keywords: ["screen", "recording", "recorder", "video"]),
                SettingsDirectoryItem(page: .urlCleaner, title: s.urlCleanerName, icon: "link"),
                SettingsDirectoryItem(page: .nowPlaying,
                                      title: FeatureStrings.nowPlaying(language).pageTitle,
                                      icon: "music.note",
                                      keywords: [FeatureStrings.nowPlaying(language).menuBarModeLabel,
                                                 FeatureStrings.nowPlaying(language).providerLabel,
                                                 FeatureStrings.nowPlaying(language).artworkToggle,
                                                 FeatureStrings.nowPlaying(language).artworkAnimationToggle]),
                SettingsDirectoryItem(page: .keyDebounce, title: s.keyDebounceName, icon: "keyboard"),
                SettingsDirectoryItem(page: .textSnippets, title: FeatureStrings.snippets(language).pageTitle,
                                      icon: "text.append",
                                      keywords: [FeatureStrings.snippets(language).triggerLabel,
                                                 FeatureStrings.snippets(language).addButton,
                                                 FeatureStrings.snippets(language).soundPickerLabel,
                                                 FeatureStrings.snippets(language).soundToggle]),
                SettingsDirectoryItem(page: .radialMenu, title: FeatureStrings.radialMenu(language).pageTitle,
                                      icon: "circle.grid.cross",
                                      keywords: [FeatureStrings.radialMenu(language).addButton,
                                                 FeatureStrings.radialMenu(language).kindApp,
                                                 FeatureStrings.radialMenu(language).kindMedia,
                                                 FeatureStrings.radialMenu(language).kindSubmenu]),
            ]),
            (categories.app, [
                SettingsDirectoryItem(page: .shortcuts, title: s.shortcutsPageTitle, icon: "command",
                                      keywords: [s.hotkeyToggle]),
                SettingsDirectoryItem(page: .advanced, title: s.tabAdvanced, icon: "wrench.and.screwdriver"),
                SettingsDirectoryItem(page: .about, title: s.tabAbout, icon: "info.circle",
                                      keywords: [s.reviewIntro]),
                SettingsDirectoryItem(page: .releaseNotes, title: s.tabReleaseNotes, icon: "sparkles"),
                SettingsDirectoryItem(page: .support, title: s.tabSupport, icon: "heart.fill"),
            ]),
        ]
    }

    /// Every page the directory lists, in sidebar order.
    static func allItems(_ s: Strings,
                         language: AppLanguage,
                         superKeySource: SuperKeySource) -> [SettingsDirectoryItem] {
        sections(s, language: language, superKeySource: superKeySource).flatMap(\.items)
    }

    /// The rows the command bar offers: everything the directory lists except
    /// the pages an action row already opens, which would otherwise appear
    /// twice leading to the same place.
    static func commandBarItems(_ s: Strings,
                                language: AppLanguage,
                                superKeySource: SuperKeySource,
                                excluding covered: Set<SettingsPage>) -> [SettingsDirectoryItem] {
        allItems(s, language: language, superKeySource: superKeySource)
            .filter { !covered.contains($0.page) }
    }
}
