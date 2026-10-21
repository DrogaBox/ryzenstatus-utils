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
    /// Feature ownership for keyword rows on shared pages. `nil` means the
    /// setting belongs to the page itself and remains searchable whenever the
    /// page is visible.
    var keywordFeatures: [AppFeature?] = []
    var id: SettingsPage { page }

    init(page: SettingsPage, title: String, icon: String,
         keywords: [String] = [],
         featureKeywords: [(feature: AppFeature, titles: [String])] = []) {
        self.page = page
        self.title = title
        self.icon = icon
        self.keywords = keywords + featureKeywords.flatMap(\.titles)
        keywordFeatures = Array(repeating: nil, count: keywords.count)
            + featureKeywords.flatMap { entry in
                Array(repeating: Optional(entry.feature), count: entry.titles.count)
            }
    }
}

/// The single map of the Settings window: sections, pages, icons and search
/// keywords. The sidebar draws its tool list from these pages; the command bar
/// searches them. One list, so a page added here is findable everywhere.
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

    /// The AMD Ryzen pages: the machine this app is built around, so they get
    /// a section of their own right below the essentials.
    private static let amdPages: Set<SettingsPage> = [
        .dashboard, .fans, .amdPower, .amdOverclocking, .sensors, .amdValidation,
    ]

    /// Shared pages whose tools cover the page without a separate overview row.
    private static let toolOnlyPages: Set<SettingsPage> = [
        .energy, .mouse, .switcher, .dock, .clipboard, .cutPaste, .quickTools, .screenshot,
    ]

    /// Keep the directory's destinations, but show the most useful groups
    /// first and separate everyday controls from the longer tool list.
    static func sidebarSections(_ s: Strings,
                                language: AppLanguage,
                                superKeySource: SuperKeySource = SuperKeyService.shared.source,
                                isAvailable: (AppFeature) -> Bool) -> [SettingsSidebarSection] {
        let hub = FeatureStrings.hub(language)
        let grouped: [SettingsSidebarSection] = sections(
            s, language: language, superKeySource: superKeySource
        ).enumerated().compactMap { index, section -> SettingsSidebarSection? in
                let items = section.items.flatMap { pageItem -> [SettingsSidebarItem] in
                    var rows = SettingsSidebarSupport.items(
                        page: pageItem.page, title: pageItem.title, icon: pageItem.icon,
                        preferredFeatures: pageItem.keywordFeatures.compactMap { $0 },
                        includePage: !toolOnlyPages.contains(pageItem.page),
                        isAvailable: isAvailable) { feature in
                            if feature == .clipboardHistory {
                                return FeatureStrings.commandBar(language).sourceClipboard
                            }
                            return feature.hubTitle(s, hub: hub)
                        }
                    if pageItem.page == .general {
                        rows.insert(SettingsSidebarItem(
                            id: .setting(.panelConfiguration),
                            destination: FeatureSettingsDestination(
                                .general, sectionAnchor: .panelConfiguration),
                            title: s.menuBarSection, icon: "menubar.rectangle"), at: 1)
                    }
                    if pageItem.page == .shortcuts, isAvailable(.brightness),
                       BrightnessService.keyboardLightIsSupported {
                        let destination = FeatureSettingsDestination(
                            .shortcuts, sectionAnchor: .keyboardBrightnessShortcuts)
                        rows.append(SettingsSidebarItem(
                            id: .setting(.keyboardBrightnessShortcuts), destination: destination,
                            title: FeatureStrings.brightness(language).keyboardLight,
                            icon: "keyboard"))
                    }
                    return rows
                }
                guard !items.isEmpty else { return nil }
                return SettingsSidebarSection(id: index, title: section.title, items: items)
            }
        guard let essentials = grouped.first(where: { $0.id == 0 }) else { return grouped }
        let categories = FeatureStrings.settingsCategories(language)
        // Monitor keeps its tool rows, such as Fan Control, beside it.
        let core = essentials.items.filter { item in
            switch item.id {
            case .page(.general), .page(.features),
                 .setting(.panelConfiguration): return true
            default: return item.destination.page == .monitor
            }
        }
        // The companion lives in the island, and its settings in a tab of the
        // island's page rather than a row of their own.
        let islandPages: Set<SettingsSidebarItem.ID> = [.page(.notch)]
        let island = grouped.first(where: { $0.id == 4 })?.items.filter {
            islandPages.contains($0.id)
        } ?? []
        let sound: [SettingsSidebarItem] = essentials.items.filter { item in
            item.destination.page == .general
                && item.destination.sectionAnchor != nil
                && item.destination.sectionAnchor != .panelConfiguration
        }
        let energy: [SettingsSidebarItem] = essentials.items.filter {
            $0.destination.page == .energy
        }
        func rows(_ id: Int) -> [SettingsSidebarItem] {
            grouped.first(where: { $0.id == id })?.items ?? []
        }
        let byGroup = SettingsSidebarSupport.featureGroupRows(
            windowsControls: rows(1), utilities: rows(4).filter {
                !islandPages.contains($0.id)
            })
        let amd = essentials.items.filter { amdPages.contains($0.destination.page) }
        let featured = [
            SettingsSidebarSection(id: 0, title: categories.essentials,
                                   items: Array(core.prefix(3)) + island + Array(core.dropFirst(3))),
            SettingsSidebarSection(id: 9, title: "AMD Ryzen", items: amd),
            SettingsSidebarSection(id: 4, title: categories.utilities, items: byGroup.utilities),
            SettingsSidebarSection(id: 6, title: hub.groupSound, items: sound + byGroup.sound),
            SettingsSidebarSection(id: 7, title: hub.groupEnergyDisplay, items: energy),
            SettingsSidebarSection(id: 1, title: hub.groupWindowsDock, items: byGroup.windowsDock),
            SettingsSidebarSection(id: 8, title: hub.groupMouseKeyboard, items: byGroup.mouseKeyboard),
            SettingsSidebarSection(id: 2, title: categories.files, items: rows(2) + byGroup.files),
        ]
        let remaining = grouped.filter { ![0, 1, 2, 4].contains($0.id) }
        return [featured[0]] + featured.dropFirst().filter { !$0.items.isEmpty } + remaining
    }

    static func sidebarItems(_ s: Strings,
                             language: AppLanguage,
                             superKeySource: SuperKeySource = SuperKeyService.shared.source,
                             isAvailable: (AppFeature) -> Bool) -> [SettingsSidebarItem] {
        sidebarSections(s, language: language, superKeySource: superKeySource,
                        isAvailable: isAvailable).flatMap(\.items)
    }

    /// Destination-aware rows for focused Settings and Command Bar search.
    static func searchItems(_ s: Strings,
                            language: AppLanguage,
                            superKeySource: SuperKeySource = SuperKeyService.shared.source) -> [SettingsSearchItem] {
        let pageItems = sections(s, language: language, superKeySource: superKeySource)
            .flatMap(\.items).map { item in
                SettingsSearchItem(id: .page(item.page),
                                   destination: FeatureSettingsDestination(item.page),
                                   title: item.title,
                                   icon: item.icon,
                                   keywords: item.keywords,
                                   keywordFeatures: item.keywordFeatures)
            }
        let hub = FeatureStrings.hub(language)
        let featureItems = SettingsSearchSupport.featureItems(language: language) { feature in
            feature.hubTitle(s, hub: hub)
        }
        var items = SettingsSearchSupport.combinedItems(pageItems: pageItems,
                                                        featureItems: featureItems)
        items.append(SettingsSearchItem(
            id: .setting(.panelConfiguration),
            destination: FeatureSettingsDestination(
                .general, sectionAnchor: .panelConfiguration),
            title: s.menuBarSection, icon: "menubar.rectangle",
            keywords: [s.showMenuBarIcon, FeatureStrings.generalSettings(language).menuBarIconTitle, "SF Symbols"]))
        if BrightnessService.keyboardLightIsSupported {
            items.append(SettingsSearchSupport.keyboardBrightnessShortcutItem(language: language))
        }
        return items
    }

    static func sections(_ s: Strings,
                         language: AppLanguage,
                         superKeySource: SuperKeySource = SuperKeyService.shared.source)
        -> [(title: String, items: [SettingsDirectoryItem])] {
        let categories = FeatureStrings.settingsCategories(language)
        let quitProtection = FeatureStrings.quitProtection(language)
        return [
            (categories.essentials, [
                SettingsDirectoryItem(page: .general, title: s.tabGeneral, icon: "gearshape",
                                       keywords: [s.launchAtLogin, s.languageLabel,
                                                  FeatureStrings.appearance(language).label,
                                                  FeatureStrings.appearance(language).dark,
                                                  FeatureStrings.bluetoothUsage(language).title, "Bluetooth",
                                                  FeatureStrings.feedback(language).sectionTitle,
                                                  FeatureStrings.feedback(language).commandBug,
                                                  FeatureStrings.feedback(language).commandFeature],
                                       featureKeywords: [
                                        (.musicBlock, [s.musicBlockTitle, s.musicBlockSection]),
                                       ]),
                // Searching any feature name lands here even when the feature
                // is hidden, so the hub is always the way back.
                SettingsDirectoryItem(page: .features, title: FeatureStrings.hub(language).pageTitle,
                                       icon: "square.grid.2x2",
                                       featureKeywords: AppFeature.allCases.map {
                                        ($0, [$0.hubTitle(s, hub: FeatureStrings.hub(language))])
                                       }),
                SettingsDirectoryItem(page: .energy, title: s.tabEnergy, icon: "bolt.fill",
                                       featureKeywords: [
                                        (.keepAwake, [s.keepAwakeTitle, s.clamshellTitle,
                                                      s.defaultDurationLabel, s.showCountdown,
                                                      s.keepAwakeActiveIconLabel,
                                                      s.keepAwakeActiveIconCoffee,
                                                      s.keepAwakeActiveIconEye,
                                                      FeatureStrings.keepAwakeAutomation(language)
                                                        .externalDisplayToggle,
                                                      FeatureStrings.keepAwakeAutomation(language)
                                                        .powerToggle,
                                                      FeatureStrings.keepAwakeAutomation(language)
                                                        .pauseWhenLockedToggle,
                                                      FeatureStrings.keepAwakeDisplaySleep(language)
                                                        .allowDisplaySleep]),
                                        (.brightness, [FeatureStrings.brightness(language).pageTitle,
                                                       FeatureStrings.brightness(language).osdToggle,
                                                       FeatureStrings.brightness(language).keyStep,
                                                       FeatureStrings.brightness(language).keyStepHalf,
                                                       FeatureStrings.brightness(language).keyStepQuarter]),
                                        (.extraBrightness, [s.extraBrightnessName]),
                                        (.bluetoothSleep, [FeatureStrings.bluetoothSleep(language).pageTitle,
                                                           FeatureStrings.bluetoothSleep(language).enable]),
                                       ]),
                SettingsDirectoryItem(page: .monitor, title: s.tabMonitor, icon: "chart.line.uptrend.xyaxis",
                                       keywords: [s.menuBarSpacingLabel, s.menuBarHideIconToggle],
                                       featureKeywords: [
                                        (.monitorMemory, [s.monitorMemoryPressureDot]),
                                        (.monitorNetwork, [FeatureStrings.monitorLayout(language).networkSpeedUnit]),
                                       ]),
                SettingsDirectoryItem(page: .dashboard, title: FeatureStrings.performanceSuite(language).dashboardTab,
                                      icon: "gauge.with.dots.needle.bottom.100percent"),
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
                                       featureKeywords: [
                                        (.scrollInverter, [s.invertMouseScroll, s.invertVerticalScroll,
                                                           s.invertHorizontalScroll]),
                                        (.scrollHorizontal, [s.scrollHorizontalName,
                                                            s.scrollHorizontalModifierLabel]),
                                        (.middleClick, [s.middleClickTapPicker]),
                                        (.focusFollowsMouse, [s.focusFollowsMouseName,
                                                              s.focusFollowsMouseDelay,
                                                              s.focusFollowsMouseRaise,
                                                              s.focusFollowsMouseWaitForStop]),
                                        (.smoothScroll, [s.smoothScrollName]),
                                        (.linearScroll, [s.linearScrollName, s.linearScrollLinesLabel]),
                                        (.mouseAcceleration, [s.mouseAccelerationName]),
                                        (.mouseNavigation, [s.mouseNavigationEnable]),
                                        (.mouseButtonShortcuts,
                                         [FeatureStrings.mouseButtons(language).pageTitle,
                                          FeatureStrings.mouseButtons(language).sideWheelLeftName,
                                          FeatureStrings.mouseButtons(language).sideWheelRightName,
                                          FeatureStrings.mouseExceptions(language).listTitle]),
                                        (.mouseClickDebounce,
                                         [FeatureStrings.mouseClickDebounce(language).title,
                                          FeatureStrings.mouseClickDebounce(language).windowLabel,
                                          "debounce"]),
                                       ]),
                SettingsDirectoryItem(page: .switcher, title: s.tabSwitcher, icon: "rectangle.on.rectangle",
                                       featureKeywords: [
                                        (.switcher, [s.switcherEnable, s.switcherInstantSelection,
                                                     s.switcherWindowlessApps,
                                                     s.switcherShowShortcutHints, s.switcherMaxColumns,
                                                     FeatureStrings.switcherAppRules(language).listTitle,
                                                     FeatureStrings.switcherAppRules(language)
                                                        .showWithoutWindows,
                                                     FeatureStrings.switcherAppRules(language).windowsOnly,
                                                     FeatureStrings.switcherAppRules(language).hidden,
                                                     FeatureStrings.windowPreviewExclusions(language).listTitle]),
                                       ]),
                SettingsDirectoryItem(page: .dock, title: FeatureStrings.settingsPages(language).dockTitle,
                                       icon: "dock.rectangle",
                                       featureKeywords: [
                                        (.dockPreview, [s.dockPreviewName, s.dockPreviewEnable,
                                                        s.dockPreviewOpenDelay,
                                                        s.dockPreviewBackgroundOpacity,
                                                        s.dockPreviewQuitAppOnClose,
                                                        s.dockPreviewKeepDockVisible,
                                                        s.dockPreviewOrderByCreation,
                                                        FeatureStrings.windowPreviewExclusions(language).listTitle]),
                                        (.dockClick, [FeatureStrings.hub(language).titleDockClick,
                                                      s.dockClickMinimize, s.dockClickHide,
                                                      s.dockClickCycleWindows]),
                                        (.spacesOrder, [s.spacesOrderName]),
                                       ]),
                SettingsDirectoryItem(page: .windowLayout,
                                      title: FeatureStrings.windowLayout(language).title,
                                      icon: "rectangle.3.group",
                                      featureKeywords: [
                                        (.windowLayout, [s.dockClickCycleWindows,
                                                         FeatureStrings.windowLayout(language).edgeSnapEnable,
                                                         FeatureStrings.windowLayout(language).gestureEnable,
                                                         FeatureStrings.windowLayout(language).gestureResize,
                                                         FeatureStrings.windowLayoutIgnoredApps(language).listTitle]),
                                        (.windowMaximizer,
                                         [s.windowMaximizeName,
                                          FeatureStrings.windowMaximizerExclusions(language).listTitle]),
                                      ]),
                SettingsDirectoryItem(page: .autoQuit, title: s.autoQuitName, icon: "xmark.rectangle",
                                      keywords: [s.autoQuitEnable]),
                SettingsDirectoryItem(page: .quitProtection,
                                      title: quitProtection.name,
                                      icon: "shield.lefthalf.filled",
                                      keywords: [quitProtection.description, "⌘Q", "⌘W",
                                                 quitProtection.hold, quitProtection.doublePress,
                                                 quitProtection.extraModifier]),
            ]),
            (categories.files, [
                SettingsDirectoryItem(page: .clipboard, title: FeatureStrings.clipboard(language).title,
                                       icon: "doc.on.clipboard",
                                       featureKeywords: [
                                        (.clipboardHistory, [FeatureStrings.clipboard(language).limit,
                                                             FeatureStrings.clipboard(language).historyLayout,
                                                             FeatureStrings.clipboard(language).skipSensitive,
                                                             FeatureStrings.clipboard(language).pasteImageAsFile,
                                                             FeatureStrings.clipboard(language).autoClearEnable,
                                                             FeatureStrings.clipboard(language).autoClearOnSleep,
                                                             FeatureStrings.clipboard(language)
                                                                .autoClearOnDisplaySleep,
                                                             FeatureStrings.clipboard(language)
                                                                .autoClearOnScreenLock,
                                                             FeatureStrings.clipboardIgnoredApps(language)
                                                                .listTitle]),
                                        (.pastePlain, [s.pastePlainName]),
                                       ]),
                SettingsDirectoryItem(page: .cutPaste,
                                       title: FeatureStrings.finderRename(language).pageTitle,
                                       icon: "filemenu.and.selection",
                                       featureKeywords: [
                                        (.finderCutPaste, [s.cutPasteEnable]),
                                        (.finderRename,
                                         [FeatureStrings.finderRename(language).enableLabel]),
                                       ]),
                SettingsDirectoryItem(page: .shelf, title: s.shelfName, icon: "tray.full",
                                      keywords: [s.shelfEnable, s.shelfDropZoneToggle, s.shelfEdgeToggle,
                                                 s.shelfClearOnClose, s.shelfShortcutFinderSelection,
                                                 FeatureStrings.notch(language).title,
                                                 FeatureStrings.notchEditor(language).separate]),
                SettingsDirectoryItem(page: .media, title: s.mediaName, icon: "photo.on.rectangle.angled",
                                      keywords: ["PDF", "GIF", "PNG", "JPEG", "convert", "resize", "watermark",
                                                 "rename", "profile", "fit", "fill", "crop",
                                                 s.mediaStartConvertPDF, s.ocrName]),
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
                SettingsDirectoryItem(page: .cleaner, title: s.cleanerName, icon: "sparkles",
                                      keywords: [s.cleanerScheduleTitle]),
                SettingsDirectoryItem(page: .whatsAppDownloads,
                                      title: FeatureStrings.whatsAppDownloads(language).title,
                                      icon: "square.and.arrow.down",
                                      keywords: ["WhatsApp", "downloads", "cleanup", "organizer",
                                                 FeatureStrings.whatsAppDownloads(language).automatic,
                                                 FeatureStrings.whatsAppDownloads(language).fileTypes]),
                SettingsDirectoryItem(page: .homebrew, title: FeatureStrings.packageManager(language).title,
                                      icon: "shippingbox", keywords: ["MacPorts", "Homebrew", "port", "brew"]),
                SettingsDirectoryItem(page: .uninstaller, title: s.uninstallerName, icon: "trash"),
                SettingsDirectoryItem(page: .killProcess,
                                      title: FeatureStrings.killProcess(language).pageTitle,
                                      icon: "xmark.octagon",
                                      keywords: ["force quit", "process", "cpu", "memory", "kill"]),
                SettingsDirectoryItem(page: .portManager,
                                      title: FeatureStrings.portManager(language).title,
                                      icon: "network",
                                      keywords: ["port", "ports", "listening", "socket", "PID", "kill port"]),
            ]),
            (categories.utilities, [
                SettingsDirectoryItem(page: .notch,
                                      title: FeatureStrings.notch(language).title,
                                      icon: "macbook",
                                      keywords: [FeatureStrings.notch(language).description,
                                                 FeatureStrings.notchEditor(language).hideMenuBarIcon,
                                                 FeatureStrings.notchActivities(language).keepAwakeActivity,
                                                 FeatureStrings.notchActivities(language).hideTimerCountdown,
                                                 FeatureStrings.notchCalendar(language).weekNumbers,
                                                 FeatureStrings.hub(language).titleNotchMascot,
                                                 "notch", "camera", "music", "clipboard",
                                                 FeatureStrings.notchAgents(language).title, "Claude", "Codex", "OpenCode", "GitHub Copilot", "AI", "tokens",
                                                 FeatureStrings.notchAgents(language).resetsCard,
                                                 FeatureStrings.notchLockScreen(language).title,
                                                 FeatureStrings.notchLockScreen(language).sounds]
                                          // The fit card only appears with a camera housing to fit.
                                          + (NotchSupport.hasNotchedDisplay ? [FeatureStrings.notch(language).cameraFit] : [])
                                          + (NotchSupport.hasDisplayWithoutNotch
                                             ? [FeatureStrings.notch(language).withoutNotch,
                                                FeatureStrings.notch(language).capsuleFit] : [])),
                SettingsDirectoryItem(page: .commandBar,
                                      title: FeatureStrings.commandBar(language).pageTitle,
                                      icon: "command",
                                      keywords: [FeatureStrings.commandBar(language).openButton,
                                                 FeatureStrings.commandBar(language).searchPlaceholder,
                                                 FeatureStrings.commandBar(language).appCenterTitle,
                                                 FeatureStrings.commandBar(language).appAliasLabel]),
                SettingsDirectoryItem(page: .quickTools, title: s.quickToolsTab, icon: "wand.and.rays",
                                       featureKeywords: [
                                        (.quickLauncher, [s.launcherName]),
                                        (.micMute, [s.micMuteName, s.micMuteMenuBarToggle]),
                                        (.quickToggles, [FeatureStrings.quickToggles(language).pageTitle,
                                                         FeatureStrings.quickToggles(language)
                                                            .darkModeToDark,
                                                         FeatureStrings.quickToggles(language)
                                                            .emptyTrashTitle,
                                                         FeatureStrings.brightness(language)
                                                            .keyboardLight]),
                                        (.cameraPreview,
                                         [FeatureStrings.cameraPreview(language).pageTitle]),
                                        (.wallpaper,
                                         [FeatureStrings.wallpaper(language).pageTitle]),
                                        (.worldClock,
                                         [FeatureStrings.worldClock(language).pageTitle,
                                          FeatureStrings.worldClock(language).addCity]),
                                        (.scratchpad, [FeatureStrings.scratchpad(language).pageTitle]),
                                        (.cleaningMode, [s.cleaningMenuItem, s.cleaningKeepScreenVisibleToggle]),
                                       ]),
                SettingsDirectoryItem(page: .screenshot,
                                       title: FeatureStrings.screenshot(language).screenCaptureTitle,
                                       icon: "camera.viewfinder",
                                       featureKeywords: SettingsSearchSupport
                                        .screenCaptureFeatureKeywords(s, language: language)),
                SettingsDirectoryItem(page: .urlCleaner, title: s.urlCleanerName, icon: "link"),
                SettingsDirectoryItem(page: .nowPlaying,
                                      title: FeatureStrings.nowPlaying(language).pageTitle,
                                      icon: "music.note",
                                      keywords: [FeatureStrings.nowPlaying(language).menuBarModeLabel,
                                                 FeatureStrings.nowPlaying(language).providerLabel,
                                                 FeatureStrings.nowPlaying(language).artworkToggle,
                                                 FeatureStrings.nowPlaying(language).artworkAnimationToggle]),
                SettingsDirectoryItem(page: .keyDebounce, title: s.keyDebounceName, icon: "keyboard"),
                SettingsDirectoryItem(page: .superKey,
                                      title: FeatureStrings.superKey(language).pageTitle,
                                      icon: superKeySource.systemImage,
                                      keywords: SuperKeySource.allCases.map {
                                          FeatureStrings.superKey(language).sourceLabel($0)
                                      }),
                SettingsDirectoryItem(page: .textSnippets,
                                      title: FeatureStrings.snippets(language).pageTitle,
                                      icon: "text.append",
                                      keywords: [FeatureStrings.snippets(language).triggerLabel,
                                                 FeatureStrings.snippets(language).addButton,
                                                 FeatureStrings.snippets(language).soundPickerLabel,
                                                 FeatureStrings.snippets(language).soundToggle]),
                SettingsDirectoryItem(page: .radialMenu,
                                      title: FeatureStrings.radialMenu(language).pageTitle,
                                      icon: "circle.grid.cross",
                                      keywords: [FeatureStrings.radialMenu(language).addButton,
                                                 FeatureStrings.radialMenu(language).kindApp,
                                                 FeatureStrings.radialMenu(language).kindMedia,
                                                 FeatureStrings.radialMenu(language).kindSubmenu,
                                                 FeatureStrings.radialMenu(language).mouseTriggerRequirement]),
            ]),
            (categories.app, [
                SettingsDirectoryItem(page: .shortcuts, title: s.shortcutsPageTitle, icon: "command",
                                      keywords: [s.hotkeyToggle]),
                SettingsDirectoryItem(page: .advanced, title: s.tabAdvanced, icon: "wrench.and.screwdriver"),
                SettingsDirectoryItem(page: .about, title: s.tabAbout, icon: "info.circle",
                                      keywords: [s.reviewIntro, s.reviewHighlights]),
                SettingsDirectoryItem(page: .releaseNotes, title: s.tabReleaseNotes, icon: "sparkles"),
                SettingsDirectoryItem(page: .support, title: s.tabSupport, icon: "heart.fill",
                                      keywords: [s.donateButton, s.supportIntroStarButton,
                                                 s.discordIntroJoinButton,
                                                 s.communityIntroFollowButton]),
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
