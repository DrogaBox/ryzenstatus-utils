// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// One entry in the Settings sidebar. New features add a case here and a row in
/// the Features section, so every feature gets its own page.
/// Selects the visible Settings page; the menu bar uses it to open Settings
/// directly on a specific page.
///
/// Upstream's destination API is carried here too: `request(_:)` selects a
/// page and, optionally, a section on it, with a fresh request identity even
/// when the same destination is asked for twice, and a back/forward history.
/// Pages opt into the landing highlight with `settingsSectionFocus(for:)`.
@MainActor
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()

    private struct HistoryEntry {
        let destination: FeatureSettingsDestination
        let sidebarFeature: AppFeature?
    }

    @Published var page: SettingsPage = .general {
        didSet {
            guard page != oldValue else { return }
            destination = FeatureSettingsDestination(page)
            sidebarFeature = nil
            pendingDestinationRequest = nil
            pendingFeatureTarget = nil
            if !isTraversingHistory {
                history.removeSubrange((historyIndex + 1)..<history.count)
                history.append(HistoryEntry(destination: destination, sidebarFeature: nil))
                historyIndex += 1
            }
        }
    }
    @Published private(set) var destination = FeatureSettingsDestination(.general)
    @Published private(set) var sidebarFeature: AppFeature?
    @Published private(set) var requestID = UUID()
    @Published private(set) var pendingDestinationRequest: SettingsDestinationRequest?
    /// One-shot hint for the Features hub: which feature row to reveal once
    /// the requested page lands. Always set (to nil when no target is given)
    /// on every `request`, so a stale target from an earlier search can never
    /// leak into a later, unrelated navigation.
    @Published private(set) var pendingFeatureTarget: SettingsFeatureTargetRequest?
    /// One-shot hint for the Dynamic Island page, so a section of the island
    /// can open its own options. Consumed and cleared on arrival.
    @Published var notchModule: NotchModule?
    /// One-shot hint for the Dynamic Island page to show the companion's tab,
    /// where its settings live. Consumed and cleared on arrival.
    @Published var notchCompanion = false

    private var history = [HistoryEntry(destination: FeatureSettingsDestination(.general),
                                        sidebarFeature: nil)]
    private var historyIndex = 0
    private var isTraversingHistory = false

    private init() {}

    /// `replacingVisit` swaps what the current visit shows without adding a
    /// history entry, for a fallback when the visited tool went away.
    func request(_ destination: FeatureSettingsDestination, targetFeature: AppFeature? = nil,
                 sidebarFeature: AppFeature? = nil, replacingVisit: Bool = false) {
        // Any request, history included, drops a companion hint nobody took.
        notchCompanion = false
        let requestID = UUID()
        let samePage = page == destination.page
        page = destination.page
        self.destination = destination
        self.sidebarFeature = sidebarFeature?.settingsDestination == destination ? sidebarFeature : nil
        let entry = HistoryEntry(destination: destination, sidebarFeature: self.sidebarFeature)
        // Section requests refine the current page visit, not a new history
        // entry. General and Energy show one tool per anchor, so switching
        // tools there is a visit of its own.
        if samePage && !isTraversingHistory && !replacingVisit
            && Self.anchorSelectsTool(on: destination.page)
            && history[historyIndex].destination != destination {
            history.removeSubrange((historyIndex + 1)..<history.count)
            history.append(entry)
            historyIndex += 1
        } else {
            history[historyIndex] = entry
        }
        pendingDestinationRequest = SettingsDestinationRequest(id: requestID,
                                                               destination: destination)
        pendingFeatureTarget = targetFeature.map {
            SettingsFeatureTargetRequest(id: requestID, feature: $0)
        }
        self.requestID = requestID
    }

    private static func anchorSelectsTool(on page: SettingsPage) -> Bool {
        page == .general || page == .energy
    }

    func goBack(isPageVisible: (SettingsPage) -> Bool = { _ in true }) {
        navigateHistory(step: -1, isPageVisible: isPageVisible)
    }

    func goForward(isPageVisible: (SettingsPage) -> Bool = { _ in true }) {
        navigateHistory(step: 1, isPageVisible: isPageVisible)
    }

    func canGoBack(isPageVisible: (SettingsPage) -> Bool = { _ in true }) -> Bool {
        historyTarget(step: -1, isPageVisible: isPageVisible) != nil
    }

    func canGoForward(isPageVisible: (SettingsPage) -> Bool = { _ in true }) -> Bool {
        historyTarget(step: 1, isPageVisible: isPageVisible) != nil
    }

    private func navigateHistory(step: Int, isPageVisible: (SettingsPage) -> Bool) {
        guard let index = historyTarget(step: step, isPageVisible: isPageVisible) else { return }
        historyIndex = index
        isTraversingHistory = true
        notchModule = nil
        let entry = history[index]
        request(entry.destination, sidebarFeature: entry.sidebarFeature)
        isTraversingHistory = false
    }

    private func historyTarget(step: Int, isPageVisible: (SettingsPage) -> Bool) -> Int? {
        var index = historyIndex + step
        while history.indices.contains(index) {
            if isPageVisible(history[index].destination.page) { return index }
            index += step
        }
        return nil
    }

    /// Clears only the request a view actually handled. A newer request that
    /// arrived while the destination page was being installed must survive.
    func consumeDestinationRequest(id: UUID) {
        guard pendingDestinationRequest?.id == id else { return }
        pendingDestinationRequest = nil
    }

    /// Clears only the feature target a view actually revealed. Mirrors
    /// `consumeDestinationRequest`: a newer request that arrived while the
    /// Features hub was still laying out must survive.
    func consumeFeatureTarget(id: UUID) {
        guard pendingFeatureTarget?.id == id else { return }
        pendingFeatureTarget = nil
    }
}

/// System-Settings-style window: a sidebar of pages on the left, the selected
/// page on the right. Scales cleanly as features are added, and gives each
/// feature a page of its own with room for examples and advanced options.
struct SettingsView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var superKey = SuperKeyService.shared
    @State private var searchQuery = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 198, ideal: 210, max: 240)
        } detail: {
            // The detail slot can ask its content for an unconstrained ideal
            // size; a page that wraps a ScrollView in a VStack (Dynamic
            // Island) then answers with its full content height and grows
            // the window past the screen, so it never scrolls. GeometryReader
            // reports the space actually given and breaks that chain.
            GeometryReader { geometry in
                detail
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 840, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .onAppear { ensureVisiblePage() }
        .onChange(of: features.revision) { _, _ in ensureVisiblePage() }
    }

    /// macOS 27 backs the pinned sidebar search field with a hard top scroll
    /// edge, so rows fade out cleanly under it. On macOS 26 that effect does
    /// not render inside split-view sidebars and the pinned field has no
    /// backing of its own, so rows slid legibly across the placeholder
    /// (issues #183, #254); there the field lives on a fixed header above the
    /// list, where rows can never reach it. Earlier systems keep the classic
    /// opaque sidebar chrome.
    @ViewBuilder
    private var sidebar: some View {
#if compiler(>=6.2)
        if #available(macOS 27, *) {
            sidebarList
                .searchable(text: $searchQuery,
                            placement: .sidebar,
                            prompt: l10n.s.settingsSearchPlaceholder)
                .scrollEdgeEffectStyle(.hard, for: .top)
        } else if #available(macOS 26, *) {
            VStack(spacing: 0) {
                SidebarSearchField(query: $searchQuery)
                sidebarList
            }
        } else {
            sidebarList
                .searchable(text: $searchQuery,
                            placement: .sidebar,
                            prompt: l10n.s.settingsSearchPlaceholder)
        }
#else
        sidebarList
            .searchable(text: $searchQuery,
                        placement: .sidebar,
                        prompt: l10n.s.settingsSearchPlaceholder)
#endif
    }

    private var sidebarList: some View {
        List(selection: $router.page) {
            // One list for the whole window: the sidebar draws it and the
            // command bar searches it.
            let sections = SettingsDirectory.sections(l10n.s, language: l10n.language,
                                                      superKeySource: superKey.source)
            ForEach(sections, id: \.title) { section in
                let items = section.items.filter {
                    FeatureVisibilitySupport.isPageVisible($0.page) { $0.isAvailable }
                        && SettingsSearchSupport.matches(query: searchQuery, title: $0.title,
                                                         keywords: $0.keywords)
                }
                if !items.isEmpty {
                    Section(section.title) {
                        ForEach(items) { item in
                            Label(item.title, systemImage: item.icon).tag(item.page)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// The selected page can leave the sidebar when its last feature is
    /// switched off in the hub; fall back to the hub itself, where the
    /// feature can be brought back.
    private func ensureVisiblePage() {
        if !FeatureVisibilitySupport.isPageVisible(router.page, isAvailable: { $0.isAvailable }) {
            router.page = .features
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch router.page {
        case .general: GeneralSettings()
        case .features: FeatureHubSettings()
        case .textSnippets: TextSnippetsSettings()
        case .radialMenu: RadialMenuSettings()
        case .energy: EnergySettings()
        case .monitor: MonitorSettings()
        case .mouse: MouseSettings()
        case .mouseButtonShortcuts: MouseButtonSettings()
        case .superKey: SuperKeySettings()
        case .switcher: SwitcherSettings()
        case .keyDebounce: KeyboardDebounceSettings()
        case .cutPaste: CutPasteSettings()
        case .autoQuit: AutoQuitSettings()
        case .cleaner: CleanerSettings()
        case .uninstaller: UninstallerView()
        case .killProcess: KillProcessView()
        case .portManager: PortManagerView()
        case .quitProtection: QuitProtectionSettings()
        case .commandBar: CommandBarSettings()
        case .urlCleaner: URLCleanerSettings()
        case .homebrew: HomebrewSettings()
        case .appUpdates: AppUpdatesSettings()
        case .whatsAppDownloads: WhatsAppDownloadsSettings()
        case .media: MediaSettings()
        case .clipboard: ClipboardSettings()
        case .quickTools: QuickToolsSettings()
        case .nowPlaying: NowPlayingSettings()
        case .screenshot: ScreenshotSettings()
        case .screenRecorder: ScreenRecorderSettings()
        case .windowLayout: WindowLayoutSettings()
        case .shelf: ShelfSettings()
        case .shortcuts: ShortcutsSettings()
        case .advanced: AdvancedSettings()
        case .about: AboutSettings()
        case .releaseNotes: ReleaseNotesSettings()
        case .support: SupportSettings()
        case .fans: FansSettingsView()
        case .amdPower: AmdPowerSettingsView()
        case .amdOverclocking: AmdOverclockingSettingsView()
        case .amdValidation: AmdValidationSettingsView()
        case .dashboard: PerformanceSuiteView(monitor: SystemMonitor.shared)
        case .sensors: SensorsView()
        case .notch: NotchSettings()
        }
    }
}

// MARK: - General

struct GeneralSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var hotkeys = HotkeyManager.shared
    @ObservedObject private var appearance = AppAppearanceController.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?
    @AppStorage(DefaultsKey.hotkeyEnabled) private var hotkeyEnabled = true
    @AppStorage(DefaultsKey.showCountdown) private var showCountdown = false
    @AppStorage(DefaultsKey.musicBlockEnabled) private var musicBlockEnabled = false
    @AppStorage(DefaultsKey.musicBlockReplacementPath) private var musicBlockReplacementPath = ""
    @AppStorage(DefaultsKey.panelAccordionMode) private var accordionMode = false

    var body: some View {
        Form {
            Section {
                Toggle(l10n.s.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLogin.setEnabled(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                    .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Picker(l10n.s.languageLabel, selection: $l10n.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                Picker(FeatureStrings.appearance(l10n.language).label, selection: $appearance.appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title(FeatureStrings.appearance(l10n.language))).tag(option)
                    }
                }
            }
            Section(l10n.s.menuBarSection) {
                if AppFeature.keepAwake.isAvailable {
                    Toggle(l10n.s.showCountdown, isOn: $showCountdown)
                }
                Button(l10n.s.showMenuBarIcon) {
                    appDelegate()?.reshowStatusItem()
                }
                Text(l10n.s.showMenuBarIconCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // The panel hosts more than monitoring, so its layout editor lives
            // here with the app-wide options rather than on the Monitor page
            // (which the hub can hide entirely).
            Section(l10n.s.monitorOrderSection) {
                PanelOrderEditor()
                Toggle(l10n.s.panelAccordionMode, isOn: $accordionMode)
                Text(l10n.s.monitorOrderHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if AppFeature.keepAwake.isAvailable {
                Section(l10n.s.globalHotkeySection) {
                    Toggle(l10n.s.hotkeyToggle, isOn: $hotkeyEnabled)
                        .onChange(of: hotkeyEnabled) { _, enabled in
                            HotkeyManager.shared.setEnabled(enabled)
                        }
                    ShortcutPreferenceRow(role: .keepAwake, isEnabled: hotkeyEnabled) {
                        HotkeyManager.shared.syncWithPreferences()
                    }
                    if hotkeyEnabled, hotkeys.registrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text(l10n.s.hotkeyCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if AppFeature.musicBlock.isAvailable {
                Section(l10n.s.musicBlockSection) {
                    Toggle(l10n.s.musicBlockTitle, isOn: $musicBlockEnabled)
                        .onChange(of: musicBlockEnabled) { _, _ in
                            MusicLaunchBlocker.shared.syncWithPreferences()
                        }
                    if musicBlockEnabled {
                        HStack {
                            Text(l10n.s.musicBlockReplacementLabel)
                            Spacer()
                            Text(musicBlockReplacementName)
                                .foregroundStyle(.secondary)
                            Button(l10n.s.musicBlockChooseApp) { chooseMusicReplacement() }
                            if !musicBlockReplacementPath.isEmpty {
                                Button {
                                    musicBlockReplacementPath = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help(l10n.s.urlCleanerClearButton)
                            }
                        }
                    }
                    SettingsCaptionText(l10n.s.musicBlockCaption)
                }
            }
            if AppFeature.audioPriority.isAvailable {
                Section(l10n.s.audioPrioritySection) {
                    AudioPriorityDisclosure(initiallyExpanded: true, showsHeader: false)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var musicBlockReplacementName: String {
        guard !musicBlockReplacementPath.isEmpty else { return l10n.s.musicBlockReplacementNone }
        let name = FileManager.default.displayName(atPath: musicBlockReplacementPath)
        return (name as NSString).deletingPathExtension
    }

    private func chooseMusicReplacement() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Picking the blocked app itself would start a launch-and-kill loop.
        if let bundleID = Bundle(url: url)?.bundleIdentifier,
           MusicLaunchBlocker.blockedBundleIDs.contains(bundleID) { return }
        musicBlockReplacementPath = url.path
    }
}

// MARK: - Updates

struct UpdatesView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var updates = UpdateService.shared
    @AppStorage(DefaultsKey.autoCheckUpdates) private var autoCheck = true
    @AppStorage(DefaultsKey.checkPrereleases) private var checkPrereleases = false

    var body: some View {
        Section(l10n.s.updatesSection) {
            Toggle(l10n.s.autoCheckToggle, isOn: $autoCheck)
                .onChange(of: autoCheck) { _, value in
                    UpdateService.shared.autoCheckEnabled = value
                }

            Toggle("Include pre-releases (betas)", isOn: $checkPrereleases)
                .font(.caption)
                .onChange(of: checkPrereleases) { _, _ in
                    // Re-check with the new setting on next automatic check
                }

            statusRow

            HStack {
                Button(l10n.s.checkNowButton) {
                    updates.check(manual: true)
                }
                .disabled(isBusy)

                if case .available = updates.state {
                    Button(l10n.s.updateInstallButton) {
                        appDelegate()?.showUpdatePreview()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let lastChecked = updates.lastChecked {
                Text("\(l10n.s.updateLastChecked) \(Self.format(lastChecked))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch updates.state {
        case .idle:
            EmptyView()
        case .checking:
            label(l10n.s.updateChecking, system: "arrow.triangle.2.circlepath", tint: .secondary)
        case .upToDate:
            label(l10n.s.updateUpToDate, system: "checkmark.circle.fill", tint: .green)
        case let .available(version):
            label("\(l10n.s.updateAvailablePrefix) \(version)", system: "arrow.down.circle.fill", tint: .accentColor)
        case let .downloading(progress):
            if let progress {
                label("\(l10n.s.updateDownloading) \(Int(progress * 100))%",
                      system: "arrow.down.circle", tint: .secondary)
            } else {
                label(l10n.s.updateDownloading, system: "arrow.down.circle", tint: .secondary)
            }
        case .installing:
            label(l10n.s.updateInstalling, system: "gearshape.2.fill", tint: .secondary)
        case let .failed(reason):
            label("\(l10n.s.updateFailedPrefix) \(reason)", system: "exclamationmark.triangle.fill", tint: .orange)
        }
    }

    private func label(_ text: String, system: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: system).foregroundStyle(tint)
            Text(text).font(.callout)
            Spacer()
        }
    }

    private var isBusy: Bool {
        switch updates.state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    private static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Energy

struct EnergySettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var extraBrightness = ExtraBrightnessService.shared
    @ObservedObject private var brightness = BrightnessService.shared
    @AppStorage(DefaultsKey.brightnessControlEnabled) private var brightnessEnabled = false
    @AppStorage(DefaultsKey.brightnessKeysEnabled) private var brightnessKeysEnabled = false
    @AppStorage(DefaultsKey.brightnessOSDEnabled) private var brightnessOSDEnabled = false
    @AppStorage(DefaultsKey.extraBrightnessEnabled) private var extraBrightnessEnabled = false
    @AppStorage(DefaultsKey.extraBrightnessLevel) private var extraBrightnessLevel = 100
    @AppStorage(DefaultsKey.defaultDuration) private var defaultDuration = 0
    @AppStorage(DefaultsKey.batteryLimit) private var batteryLimit = 10
    @AppStorage(DefaultsKey.keepAwakeAutoStart) private var keepAwakeAutoStart = false
    @AppStorage(DefaultsKey.keepAwakeIconTint) private var keepAwakeIconTint = KeepAwakeIconTint.orange.rawValue
    @AppStorage(DefaultsKey.keepAwakeActiveIcon) private var keepAwakeActiveIcon = KeepAwakeActiveIcon.ryzenstatus.rawValue
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleEnabled) private var keepAwakeMouseJiggle = false
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleInterval) private var keepAwakeMouseJiggleInterval = 5
    @AppStorage(DefaultsKey.bluetoothSleepEnabled) private var bluetoothSleepEnabled = false
    @AppStorage(DefaultsKey.bluetoothSleepRestoreOnWake) private var bluetoothSleepRestoreOnWake = true

    var body: some View {
        Form {
            if AppFeature.keepAwake.isAvailable {
                Section(l10n.s.sessionSection) {
                    Picker(l10n.s.defaultDurationLabel, selection: $defaultDuration) {
                        Text(l10n.s.minutes15).tag(15)
                        Text(l10n.s.minutes30).tag(30)
                        Text(l10n.s.hour1).tag(60)
                        Text(l10n.s.hours2).tag(120)
                        Text(l10n.s.hours4).tag(240)
                        Text(l10n.s.hours8).tag(480)
                        Text(l10n.s.indefinite).tag(0)
                    }
                    SettingsToggleWithCaption(title: l10n.s.keepAwakeAutoStart,
                                              caption: l10n.s.keepAwakeAutoStartCaption,
                                              isOn: $keepAwakeAutoStart)
                }
                Section(automationStrings.automationSection) {
                    SettingsCaptionText(automationStrings.automationCaption)
                    KeepAwakeAutomationEditor()
                }
                Section(l10n.s.batteryProtectionSection) {
                    Picker(l10n.s.batteryDisableBelow, selection: $batteryLimit) {
                        Text(l10n.s.batteryNever).tag(0)
                        Text("5%").tag(5)
                        Text("10%").tag(10)
                        Text("15%").tag(15)
                        Text("20%").tag(20)
                    }
                    SettingsCaptionText(l10n.s.batteryProtectionCaption)
                }
                Section(l10n.s.keepAwakeTitle) {
                    KeepAwakeIconPicker(iconValue: $keepAwakeActiveIcon,
                                        tintValue: $keepAwakeIconTint)
                    SettingsToggleWithCaption(title: l10n.s.keepAwakeMouseJiggle,
                                              caption: l10n.s.keepAwakeMouseJiggleCaption,
                                              isOn: $keepAwakeMouseJiggle)
                    if keepAwakeMouseJiggle {
                        Picker(l10n.s.keepAwakeMouseJiggleInterval, selection: $keepAwakeMouseJiggleInterval) {
                            ForEach(Defaults.allowedKeepAwakeMouseJiggleIntervals, id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                        if !permissions.accessibility {
                            PermissionRow(kind: .accessibility)
                        }
                    }
                }
                Section(l10n.s.clamshellSection) {
                    Toggle(l10n.s.clamshellTitle, isOn: $awake.clamshellPreferred)
                        .disabled(awake.clamshellSetupInProgress)
                    if awake.clamshellSetupInProgress {
                        Text(l10n.s.configuring)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if awake.clamshellSetupFailed {
                        Text(l10n.s.sudoersFailed)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    SettingsCaptionText(l10n.s.clamshellExplanation)
                }
            }
            if AppFeature.brightness.isAvailable {
                let strings = FeatureStrings.brightness(l10n.language)
                Section(strings.pageTitle) {
                    SettingsToggleWithCaption(title: strings.enable,
                                              caption: strings.enableCaption,
                                              isOn: $brightnessEnabled)
                        .onChange(of: brightnessEnabled) { _, _ in
                            BrightnessService.shared.syncWithPreferences()
                        }
                    if brightnessEnabled {
                        if brightness.displays.isEmpty {
                            SettingsCaptionText(strings.noDisplays)
                        } else {
                            ForEach(brightness.displays) { display in
                                brightnessRow(display)
                            }
                        }
                        if let failure = brightness.displayControlFailure {
                            SettingsCaptionText(displayControlFailureText(failure, strings: strings))
                                .foregroundStyle(.red)
                        }
                        SettingsToggleWithCaption(title: strings.keysToggle,
                                                  caption: strings.keysCaption,
                                                  isOn: $brightnessKeysEnabled)
                            .onChange(of: brightnessKeysEnabled) { _, isOn in
                                if isOn { Permissions.shared.requestAccessibility() }
                                BrightnessService.shared.syncWithPreferences()
                            }
                        if brightness.brightnessOSDSupported {
                            SettingsToggleWithCaption(title: strings.osdToggle,
                                                      caption: strings.osdCaption,
                                                      isOn: $brightnessOSDEnabled)
                                .onChange(of: brightnessOSDEnabled) { _, isOn in
                                    if isOn { Permissions.shared.requestAccessibility() }
                                    BrightnessService.shared.syncWithPreferences()
                                }
                        }
                        if (brightnessKeysEnabled || brightnessOSDEnabled),
                           !permissions.accessibility {
                            PermissionRow(kind: .accessibility)
                        }
                        SettingsCaptionText(strings.externalCaption)
                    }
                }
            }
            if AppFeature.extraBrightness.isAvailable {
                Section(l10n.s.extraBrightnessName) {
                    if extraBrightness.supported {
                        Toggle(l10n.s.extraBrightnessName, isOn: $extraBrightnessEnabled)
                            .onChange(of: extraBrightnessEnabled) { _, _ in
                                ExtraBrightnessService.shared.syncWithPreferences()
                            }
                        SettingsCaptionText(l10n.s.extraBrightnessCaption)
                        if extraBrightnessEnabled {
                            HStack {
                                Text(l10n.s.extraBrightnessLevelLabel)
                                Slider(value: extraBrightnessLevelBinding, in: 10...100, step: 5)
                                Text("\(extraBrightnessLevel)%")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 52, alignment: .trailing)
                            }
                        }
                    } else {
                        SettingsCaptionText(l10n.s.extraBrightnessUnsupported)
                    }
                }
            }
            if AppFeature.bluetoothSleep.isAvailable {
                bluetoothSleepSection
            }
        }
        .formStyle(.grouped)
        .onAppear {
            defaultDuration = Defaults.sanitizedDefaultDuration(defaultDuration)
            batteryLimit = Defaults.sanitizedBatteryLimit(batteryLimit)
            keepAwakeIconTint = Defaults.sanitizedKeepAwakeIconTint(keepAwakeIconTint).rawValue
            keepAwakeActiveIcon = Defaults.sanitizedKeepAwakeActiveIcon(keepAwakeActiveIcon).rawValue
            keepAwakeMouseJiggleInterval = Defaults.sanitizedKeepAwakeMouseJiggleInterval(keepAwakeMouseJiggleInterval)
            awake.refreshPasswordlessStatus()
            // Displays may have changed since launch (docked, clamshell);
            // re-check so the section never shows a stale availability.
            ExtraBrightnessService.shared.syncWithPreferences()
            BrightnessService.shared.refresh()
        }
    }

    private func brightnessRow(_ display: BrightnessDisplay) -> some View {
        HStack(spacing: 10) {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(display.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if display.isActive, display.method != nil {
                Slider(value: Binding(get: { display.brightness },
                                      set: { BrightnessService.shared.setBrightness(
                                          $0, for: display.id,
                                          showOSD: brightnessOSDEnabled) }),
                       in: 0...1)
                    .disabled(brightness.isDisplayPending(display.id))
                    .accessibilityLabel(display.name)
                Text("\(Int((display.brightness * 100).rounded()))%")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            } else {
                Spacer()
                if !display.isActive {
                    Text(FeatureStrings.brightness(l10n.language).displayOff)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
            DisplayPowerButton(display: display)
        }
    }

    // MARK: Bluetooth on sleep

    private var bluetoothSleepSection: some View {
        let strings = FeatureStrings.bluetoothSleep(l10n.language)
        return Section(strings.pageTitle) {
            if BluetoothSleepService.isSupported {
                Toggle(strings.enable, isOn: $bluetoothSleepEnabled)
                    .onChange(of: bluetoothSleepEnabled) { _, _ in
                        BluetoothSleepService.shared.syncWithPreferences()
                    }
                SettingsCaptionText(strings.enableCaption)
                if bluetoothSleepEnabled {
                    Toggle(strings.restoreToggle, isOn: $bluetoothSleepRestoreOnWake)
                    SettingsCaptionText(strings.restoreCaption)
                }
            } else {
                SettingsCaptionText(strings.unsupported)
            }
        }
    }

    private var extraBrightnessLevelBinding: Binding<Double> {
        Binding(get: { Double(extraBrightnessLevel) },
                set: { newValue in
                    extraBrightnessLevel = Int(newValue)
                    ExtraBrightnessService.shared.levelDidChange()
                })
    }

    private var automationStrings: KeepAwakeAutomationStrings {
        FeatureStrings.keepAwakeAutomation(l10n.language)
    }
}

// MARK: - Mouse

struct MouseSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var inverter = ScrollInverter.shared
    @ObservedObject private var smoothScroll = SmoothScrollService.shared
    @ObservedObject private var mouseNavigation = MouseNavigationService.shared
    @ObservedObject private var middleClick = MiddleClickService.shared
    @AppStorage(DefaultsKey.scrollInverterEnabled) private var inverterEnabled = false
    @AppStorage(DefaultsKey.smoothScrollEnabled) private var smoothScrollEnabled = false
    @AppStorage(DefaultsKey.smoothScrollStep) private var smoothScrollStep = SmoothScrollSupport.defaultStep
    @AppStorage(DefaultsKey.mouseNavigationEnabled) private var mouseNavigationEnabled = false
    @AppStorage(DefaultsKey.middleClickEnabled) private var middleClickEnabled = false
    @AppStorage(DefaultsKey.middleClickTapFingers) private var middleClickTapFingers = 0

    var body: some View {
        Form {
            if AppFeature.scrollInverter.isAvailable {
                Section(l10n.s.scrollSection) {
                    Toggle(l10n.s.invertMouseScroll, isOn: $inverterEnabled)
                        .onChange(of: inverterEnabled) { _, _ in
                            ScrollInverter.shared.syncWithPreferences()
                        }
                    if inverterEnabled, inverter.isRunning {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(l10n.s.scrollActiveNow)
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    if inverterEnabled {
                        MouseExceptionsList(scope: .scrollDirection)
                    }
                    Text(l10n.s.invertMouseScrollCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(l10n.s.scrollTrackpadNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if AppFeature.smoothScroll.isAvailable {
                Section(l10n.s.smoothScrollName) {
                    Toggle(l10n.s.smoothScrollName, isOn: $smoothScrollEnabled)
                        .onChange(of: smoothScrollEnabled) { _, _ in
                            SmoothScrollService.shared.syncWithPreferences()
                        }
                    Text(l10n.s.smoothScrollCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if smoothScrollEnabled {
                        HStack {
                            Slider(value: smoothScrollStepBinding,
                                   in: Double(SmoothScrollSupport.stepRange.lowerBound)...Double(SmoothScrollSupport.stepRange.upperBound),
                                   step: 10) {
                                Text(l10n.s.smoothScrollStepLabel)
                            }
                            Text("\(SmoothScrollSupport.sanitizedStep(smoothScrollStep))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                        MouseExceptionsList(scope: .smoothScroll)
                    }
                }
            }
            if AppFeature.mouseNavigation.isAvailable {
                Section(l10n.s.mouseNavigationSection) {
                    Toggle(l10n.s.mouseNavigationEnable, isOn: $mouseNavigationEnabled)
                        .onChange(of: mouseNavigationEnabled) { _, _ in
                            MouseNavigationService.shared.syncWithPreferences()
                        }
                    Text(l10n.s.mouseNavigationCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if mouseNavigationEnabled, mouseNavigation.isRunning {
                        Label(l10n.s.mouseNavigationActiveNow, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            if AppFeature.middleClick.isAvailable {
                Section(l10n.s.middleClickSection) {
                    Toggle(l10n.s.middleClickEnable, isOn: $middleClickEnabled)
                        .onChange(of: middleClickEnabled) { _, _ in
                            MiddleClickService.shared.syncWithPreferences()
                        }
                    Text(l10n.s.middleClickEnableCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if middleClickEnabled {
                        Picker(l10n.s.middleClickTapPicker, selection: $middleClickTapFingers) {
                            Text(l10n.s.middleClickTapOff).tag(0)
                            Text(l10n.s.middleClickTapThreeFingers).tag(3)
                            Text(l10n.s.middleClickTapFourFingers).tag(4)
                        }
                        .onChange(of: middleClickTapFingers) { _, _ in
                            MiddleClickService.shared.syncWithPreferences()
                        }
                        Text(l10n.s.middleClickTapCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if middleClickEnabled, middleClick.systemDragGestureConflict {
                        Text(l10n.s.middleClickDragConflict)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            // Upstream mouse features: sideways scrolling, focus follows
            // mouse, linear scrolling, acceleration and the click filter.
            MouseExtrasSections()
            if accessibilityNoteVisible {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            MiddleClickService.shared.refreshDragGestureConflict()
        }
    }

    /// Only features that are on AND still available can ask for the
    /// permission note; a hub-disabled one no longer needs anything.
    private var accessibilityNoteVisible: Bool {
        let anyEngaged = (inverterEnabled && AppFeature.scrollInverter.isAvailable)
            || (smoothScrollEnabled && AppFeature.smoothScroll.isAvailable)
            || (mouseNavigationEnabled && AppFeature.mouseNavigation.isAvailable)
            || (middleClickEnabled && AppFeature.middleClick.isAvailable)
            || MouseExtrasSections.needsAccessibility()
        return anyEngaged && !permissions.accessibility
    }

    private var smoothScrollStepBinding: Binding<Double> {
        Binding(
            get: { Double(SmoothScrollSupport.sanitizedStep(smoothScrollStep)) },
            set: { smoothScrollStep = Int($0) }
        )
    }
}

// MARK: - Switcher

struct SwitcherSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var dockPreview = DockPreviewService.shared
    @AppStorage(DefaultsKey.switcherEnabled) private var switcherEnabled = true
    @AppStorage(DefaultsKey.switcherShortcut) private var switcherShortcutStorage = GlobalShortcut.switcherDefault.storageValue
    @AppStorage(DefaultsKey.switcherIconRowMode) private var switcherIconRowMode = false
    @AppStorage(DefaultsKey.switcherSimpleMode) private var switcherSimpleMode = false
    @AppStorage(DefaultsKey.switcherMergeTabs) private var switcherMergeTabs = false
    @AppStorage(DefaultsKey.switcherSearchPinEnabled) private var switcherSearchPinEnabled = false
    @AppStorage(DefaultsKey.switcherAppearanceDelay) private var switcherAppearanceDelay = SwitcherSupport.defaultAppearanceDelayMilliseconds
    @AppStorage(DefaultsKey.switcherWindowlessApps) private var switcherWindowlessApps = SwitcherWindowlessApps.fallback.rawValue
    @AppStorage(DefaultsKey.dockPreviewEnabled) private var dockPreviewEnabled = false
    @AppStorage(DefaultsKey.dockPreviewOpenDelay) private var dockPreviewOpenDelay = DockPreviewSupport.defaultOpenDelayMilliseconds
    @AppStorage(DefaultsKey.dockClickMinimize) private var dockClickMinimize = false
    @AppStorage(DefaultsKey.dockClickCycleWindows) private var dockClickCycleWindows = false
    @AppStorage(DefaultsKey.previewSize) private var previewSize = "normal"

    private var switcherEngaged: Bool { switcherEnabled && AppFeature.switcher.isAvailable }
    private var dockPreviewEngaged: Bool { dockPreviewEnabled && AppFeature.dockPreview.isAvailable }
    private var switcherShortcutDisplayString: String {
        (GlobalShortcut(storageValue: switcherShortcutStorage) ?? .switcherDefault).displayString
    }

    var body: some View {
        Form {
            if AppFeature.switcher.isAvailable {
                Section {
                    switcherContent
                } header: {
                    Text(l10n.s.switcherSection)
                }
            }
            if AppFeature.dockPreview.isAvailable || AppFeature.dockClick.isAvailable {
                Section {
                    if AppFeature.dockPreview.isAvailable {
                        Toggle(l10n.s.dockPreviewEnable, isOn: $dockPreviewEnabled)
                            .onChange(of: dockPreviewEnabled) { _, _ in
                                DockPreviewService.shared.syncWithPreferences()
                            }
                        Text(dockPreviewCaption)
                            .font(.caption)
                            .foregroundStyle(dockPreviewWarning ? .orange : .secondary)
                        if dockPreviewEnabled {
                            HStack {
                                Text(l10n.s.dockPreviewOpenDelay)
                                Spacer()
                                TextField("", value: dockPreviewOpenDelayBinding,
                                          formatter: Self.dockPreviewOpenDelayFormatter)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 64)
                                Stepper("", value: dockPreviewOpenDelayBinding,
                                        in: DockPreviewSupport.openDelayMillisecondsRange,
                                        step: 50)
                                    .labelsHidden()
                                Text(verbatim: "ms")
                                    .foregroundStyle(.secondary)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            Text(l10n.s.dockPreviewOpenDelayCaption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if AppFeature.dockClick.isAvailable {
                        Toggle(l10n.s.dockClickMinimize, isOn: $dockClickMinimize)
                            .onChange(of: dockClickMinimize) { _, _ in
                                DockClickService.shared.syncWithPreferences()
                            }
                        Text(l10n.s.dockClickMinimizeCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle(l10n.s.dockClickCycleWindows, isOn: $dockClickCycleWindows)
                            .onChange(of: dockClickCycleWindows) { _, _ in
                                DockClickService.shared.syncWithPreferences()
                            }
                        Text(l10n.s.dockClickCycleWindowsCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(l10n.s.dockPreviewName)
                }
            }
            if AppFeature.switcher.isAvailable || AppFeature.dockPreview.isAvailable {
                Section {
                    Picker(l10n.s.previewSizeLabel, selection: $previewSize) {
                        Text(l10n.s.previewSizeNormal).tag("normal")
                        Text(l10n.s.previewSizeLarge).tag("large")
                        Text(l10n.s.previewSizeXLarge).tag("xlarge")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: previewSize) { _, _ in
                        AppSwitcher.shared.syncWithPreferences()
                    }
                    WindowPreviewExclusionsList()
                } header: {
                    Text(l10n.s.previewSizeLabel)
                }
            }
            SpacesOrderSection()
            if switcherEngaged || dockPreviewEngaged {
                if !permissions.accessibility {
                    Section(l10n.s.permissionRequired) {
                        PermissionRow(kind: .accessibility)
                    }
                }
                if !permissions.screenRecording,
                   SwitcherSupport.needsScreenRecording(switcherEnabled: switcherEngaged,
                                                        simpleMode: switcherSimpleMode,
                                                        dockPreviewEnabled: dockPreviewEngaged) {
                    Section {
                        PermissionRow(kind: .screenRecording)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var switcherContent: some View {
        Group {
            Toggle(l10n.s.switcherEnable, isOn: $switcherEnabled)
                .onChange(of: switcherEnabled) { _, _ in
                    AppSwitcher.shared.syncWithPreferences()
                }
            Text(l10n.s.switcherEnableCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            ShortcutPreferenceRow(role: .switcher,
                                  isEnabled: switcherEnabled,
                                  label: l10n.s.switcherShortcutHintApps) {
                AppSwitcher.shared.syncWithPreferences()
            }
            ShortcutPreferenceRow(role: .switcherWindow,
                                  isEnabled: switcherEnabled,
                                  label: l10n.s.switcherShortcutHintWindows) {
                AppSwitcher.shared.syncWithPreferences()
            }
            Text(l10n.s.switcherWindowShortcutCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: l10n.s.switcherUsageHintFormat,
                        GlobalShortcutRole.switcher.savedShortcut.displayString))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Group {
            HStack {
                Text(l10n.s.switcherAppearanceDelay)
                Slider(value: switcherAppearanceDelayBinding,
                       in: Double(SwitcherSupport.appearanceDelayMillisecondsRange.lowerBound)
                           ... Double(SwitcherSupport.appearanceDelayMillisecondsRange.upperBound),
                       step: 25)
                    .disabled(!switcherEnabled)
                Text("\(sanitizedSwitcherAppearanceDelay) ms")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
            }
            Text(l10n.s.switcherAppearanceDelayCaption)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(l10n.s.switcherSearchPin, isOn: $switcherSearchPinEnabled)
                .disabled(!switcherEnabled)
            Text(l10n.s.switcherSearchPinCaption)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(l10n.s.switcherSimpleMode, isOn: $switcherSimpleMode)
                .disabled(!switcherEnabled)
                .onChange(of: switcherSimpleMode) { _, _ in
                    AppSwitcher.shared.syncWithPreferences()
                }
            Text(l10n.s.switcherSimpleModeCaption)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(String(format: l10n.s.switcherIconRowMode, switcherShortcutDisplayString),
                   isOn: $switcherIconRowMode)
                .disabled(!switcherEnabled || switcherSimpleMode)
                .onChange(of: switcherIconRowMode) { _, _ in
                    AppSwitcher.shared.syncWithPreferences()
                }
            Text(l10n.s.switcherIconRowModeCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Group {
            Toggle(l10n.s.switcherMergeTabs, isOn: $switcherMergeTabs)
                .disabled(!switcherEnabled)
            Text(l10n.s.switcherMergeTabsCaption)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(l10n.s.switcherWindowlessApps, selection: $switcherWindowlessApps) {
                Text(l10n.s.switcherWindowlessAppsOff).tag(SwitcherWindowlessApps.off.rawValue)
                Text(l10n.s.switcherWindowlessAppsFinder).tag(SwitcherWindowlessApps.finder.rawValue)
                Text(l10n.s.switcherWindowlessAppsAll).tag(SwitcherWindowlessApps.all.rawValue)
            }
            .disabled(!switcherEnabled)
            Text(l10n.s.switcherWindowlessAppsCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            SwitcherAppRulesList()
        }
    }

    private var dockPreviewCaption: String {
        guard dockPreviewEnabled else { return l10n.s.dockPreviewEnableCaption }
        if !permissions.accessibility { return "\(l10n.s.permissionRequired): \(l10n.s.permissionAccessibility)" }
        if !permissions.screenRecording { return "\(l10n.s.permissionRequired): \(l10n.s.permissionScreenRecording)" }
        switch dockPreview.blockedReason {
        case .dockUnavailable: return l10n.s.dockPreviewDockUnavailable
        default:
            return l10n.s.dockPreviewEnableCaption
        }
    }

    private var sanitizedSwitcherAppearanceDelay: Int {
        SwitcherSupport.sanitizedAppearanceDelay(milliseconds: switcherAppearanceDelay)
    }

    private var switcherAppearanceDelayBinding: Binding<Double> {
        Binding(
            get: { Double(sanitizedSwitcherAppearanceDelay) },
            set: {
                switcherAppearanceDelay = SwitcherSupport.sanitizedAppearanceDelay(
                    milliseconds: Int($0.rounded()))
            }
        )
    }

    private var dockPreviewWarning: Bool {
        dockPreviewEnabled && dockPreview.blockedReason != nil
    }

    private var dockPreviewOpenDelayBinding: Binding<Int> {
        Binding(
            get: { DockPreviewSupport.sanitizedOpenDelay(milliseconds: dockPreviewOpenDelay) },
            set: { dockPreviewOpenDelay = DockPreviewSupport.sanitizedOpenDelay(milliseconds: $0) }
        )
    }

    private static let dockPreviewOpenDelayFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = NSNumber(value: DockPreviewSupport.openDelayMillisecondsRange.lowerBound)
        formatter.maximum = NSNumber(value: DockPreviewSupport.openDelayMillisecondsRange.upperBound)
        formatter.usesGroupingSeparator = false
        return formatter
    }()
}


// MARK: - About

struct AboutSettings: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Form {
            Section {
                aboutContent
            }

            UpdatesView()
        }
        .formStyle(.grouped)
    }

    private var aboutContent: some View {
        VStack(spacing: 14) {
            BrandBadge(size: 76)
            VStack(spacing: 3) {
                Text(AppInfo.name)
                    .font(.title2.bold())
                Text("\(l10n.s.versionPrefix) \(AppInfo.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if AppInfo.isDeveloperBuild, let commit = AppInfo.buildCommit {
                    // Dev-only: which source commit this build came from. Never shipped.
                    Text(commit)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
            Text(l10n.s.aboutDescription)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            // KEXT_WAVE C-8: baseboard identity (kext selector 16) + kext
            // version, surfaced only when the kext reported valid data.
            if ProcessorModel.shared.identityCache.boardValid {
                VStack(spacing: 2) {
                    Text("\(ProcessorModel.shared.identityCache.boardName) — \(ProcessorModel.shared.identityCache.boardVendor)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if !ProcessorModel.shared.identityCache.kextVersion.isEmpty {
                        Text("AMDRyzenCPUPowerManagement \(ProcessorModel.shared.identityCache.kextVersion)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            HStack(spacing: 12) {
                Button(l10n.s.reviewIntro) {
                    appDelegate()?.showOnboarding()
                }
                Link(l10n.s.viewOnGitHub, destination: AppInfo.repositoryURL)
            }
            Text(AppInfo.copyright)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Release notes

struct ReleaseNotesSettings: View {
    @ObservedObject private var l10n = L10n.shared
    private let notes = ReleaseNotes.current

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.s.obWhatsNewTitle)
                    .font(.title2.bold())
                Text(versionLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if notes.sections.isEmpty {
                        fallbackNote
                    } else {
                        ForEach(Array(notes.sections.enumerated()), id: \.offset) { _, section in
                            releaseSection(section)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var versionLine: String {
        if let date = notes.date {
            return "v\(notes.version) · \(date)"
        }
        return "v\(notes.version)"
    }

    private var fallbackNote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, alignment: .center)
            Text(l10n.s.obWhatsNewFallback)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func releaseSection(_ section: ReleaseNoteSection) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if !section.title.isEmpty {
                Text(section.title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
            }
            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                releaseItem(item, sectionTitle: section.title)
            }
        }
    }

    @ViewBuilder
    private func releaseItem(_ item: ReleaseNoteItem, sectionTitle: String) -> some View {
        switch item {
        case let .paragraph(text):
            Text(text)
                .font(.system(size: 12.8))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        case let .bullet(text):
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: iconName(for: sectionTitle))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18, alignment: .center)
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .image(image):
            if let nsImage = releaseNoteImage(image) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    )
                    .accessibilityLabel(image.alt)
                    .padding(.leading, 27)
            }
        }
    }

    private func releaseNoteImage(_ image: ReleaseNoteImage) -> NSImage? {
        var path = image.path
        if let resourcesRange = path.range(of: "Resources/") {
            path = String(path[resourcesRange.lowerBound...])
        }
        if path.hasPrefix("Resources/") {
            path.removeFirst("Resources/".count)
        }
        let nsPath = path as NSString
        let ext = nsPath.pathExtension
        let name = (nsPath.deletingPathExtension as NSString).lastPathComponent
        let directory = nsPath.deletingLastPathComponent
        guard !name.isEmpty, !ext.isEmpty else { return nil }
        let subdirectory = directory.isEmpty || directory == "." ? nil : directory
        guard let url = Bundle.main.url(forResource: name,
                                        withExtension: ext,
                                        subdirectory: subdirectory) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func iconName(for title: String) -> String {
        switch title.lowercased() {
        case "added": return "plus.circle.fill"
        case "changed": return "slider.horizontal.3"
        case "fixed": return "checkmark.circle.fill"
        default: return "circle.fill"
        }
    }
}

// MARK: - Support / donate

/// A calm, visual page inviting people to support the project. Nothing is
/// nagged or gated: the message and a single PayPal button that opens
/// the donate page in the browser.
struct SupportSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var quote: String = MovieQuotes.randomQuote()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 16) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Theme.spaceGradient)
                        .frame(width: 84, height: 84)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 33))
                        .foregroundStyle(.white)
                }
                Text(l10n.s.donateHeading)
                    .font(.title2.bold())
                Text(l10n.s.donateMessage)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                DonateButton()
                    .padding(.top, 4)
                Text(l10n.s.donateThanks)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)

            Text("“\(quote)”")
                .font(.system(size: 11, weight: .medium))
                .italic()
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.trailing)
                .padding(.trailing, 24)
                .padding(.bottom, 20)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        quote = MovieQuotes.randomQuote(excluding: quote)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            quote = MovieQuotes.randomQuote()
        }
    }
}

/// The PayPal call to action for the Support page. Opens the donate
/// page in the default browser.
struct DonateButton: View {
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(AppInfo.donateURL)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill").font(.system(size: 15))
                Text(l10n.s.donateButton)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(Capsule().fill(Color(red: 1.0, green: 0.84, blue: 0.0)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared settings rows

private struct SettingsCaptionText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsToggleWithCaption: View {
    let title: String
    let caption: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                SettingsCaptionText(caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Shared permission row

enum PermissionKind {
    case accessibility
    case screenRecording
    case microphone
}

/// Status + actions for one TCC permission; shared by Settings and onboarding.
struct PermissionRow: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    let kind: PermissionKind

    private var granted: Bool {
        switch kind {
        case .accessibility: return permissions.accessibility
        case .screenRecording: return permissions.screenRecording
        case .microphone: return permissions.microphone == .granted
        }
    }

    private var name: String {
        switch kind {
        case .accessibility: return l10n.s.permissionAccessibility
        case .screenRecording: return l10n.s.permissionScreenRecording
        case .microphone:
            return FeatureStrings.recorder(l10n.language).microphonePermissionName
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(granted ? .green : .orange)
                Text(name)
                Spacer()
                Text(granted ? l10n.s.permissionGranted : l10n.s.permissionMissing)
                    .font(.caption)
                    .foregroundStyle(granted ? .green : .orange)
            }
            if !granted {
                HStack(spacing: 8) {
                    Button(l10n.s.permissionRequest) {
                        switch kind {
                        case .accessibility:
                            permissions.requestAccessibility()
                        case .screenRecording:
                            permissions.requestScreenRecording()
                        case .microphone:
                            permissions.requestMicrophone()
                        }
                    }
                    Button(l10n.s.permissionOpenSettings) {
                        switch kind {
                        case .accessibility:
                            permissions.openAccessibilitySettings()
                        case .screenRecording:
                            permissions.openScreenRecordingSettings()
                        case .microphone:
                            permissions.openMicrophoneSettings()
                        }
                    }
                }
                .controlSize(.small)
            }
        }
    }
}

/// Search field for the macOS 26 sidebar, styled after the system pill.
/// It sits on a fixed header outside the List, so scrolling rows can never
/// cross it (issues #183, #254). Esc and the clear button empty the query,
/// matching the system field.
private struct SidebarSearchField: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var query: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(l10n.s.settingsSearchPlaceholder, text: $query)
                .textFieldStyle(.plain)
                .onExitCommand { query = "" }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(l10n.s.urlCleanerClearButton)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

/// Secure Event Input blocks every synthetic keystroke. Typing a snippet
/// trigger then does nothing at all, while the snippet library and the
/// Command Bar's typing actions beep; none of the four paths says what is
/// wrong or who is holding it. This row is the only place the app explains
/// that, and it names the holder when the session can attribute it.
///
/// Both call sites instantiate it only once secure input is on, and the
/// snippets page waits for one of its own toggles as well, so the `.off`
/// branch below is there to keep the switch exhaustive and for nothing else.
/// What drives the feature is the polling demand on each page; see
/// `SecureInputObservation`.
struct SecureInputRow: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SecureInputMonitor.shared

    var body: some View {
        switch monitor.holder {
        case .off:
            EmptyView()
        case .app(let name, _):
            row(caption: String(format: l10n.s.secureInputHeldFormat, name)) {
                Button(String(format: l10n.s.secureInputRevealFormat, name)) {
                    monitor.revealHolder()
                }
                .controlSize(.small)
            }
        case .unattributed:
            row(caption: l10n.s.secureInputUnattributed) { EmptyView() }
        case .unknown:
            row(caption: l10n.s.secureInputUnidentified) { EmptyView() }
        }
    }

    private func row<Action: View>(caption: String,
                                   @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text(l10n.s.secureInputTitle)
                Spacer()
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            action()
        }
    }
}

/// Keeps secure input polled for as long as the page is on screen and
/// `isActive` holds, e.g. the snippets page only while one of its own
/// toggles is on, since with both off nothing this row could report can
/// show. The demand cannot live on `SecureInputRow`: nothing would
/// register it until the state it reports had already been reached.
private struct SecureInputObservation: ViewModifier {
    let isActive: Bool
    @State private var demandID = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { SecureInputMonitor.shared.setObservingSurface(demandID, visible: isActive) }
            .onDisappear { SecureInputMonitor.shared.setObservingSurface(demandID, visible: false) }
            .onChange(of: isActive) { _, active in
                SecureInputMonitor.shared.setObservingSurface(demandID, visible: active)
            }
    }
}

extension View {
    func observesSecureInput(isActive: Bool = true) -> some View {
        modifier(SecureInputObservation(isActive: isActive))
    }
}
