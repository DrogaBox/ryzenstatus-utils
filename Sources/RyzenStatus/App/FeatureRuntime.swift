// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit

/// Bridges the pure feature catalog to the live singletons. Every binding is
/// a closure, so merely mentioning a feature never instantiates its service:
/// a service only comes to life when its binding runs, and syncAtLaunch skips
/// unavailable features entirely — switched off in the hub means nothing
/// loads and nothing runs after the next launch. Main thread only, like the
/// services it drives.
final class FeatureRuntime: ObservableObject {
    static let shared = FeatureRuntime()

    /// Bumped on every availability change; views observing the runtime
    /// re-read the catalog when it moves.
    @Published private(set) var revision = 0

    /// Every feature that came to life in THIS process: available at launch
    /// or installed later in the session. A feature uninstalled mid-session
    /// stops working immediately, but its (inert) singleton only leaves
    /// memory on the next launch — this set is what the hub's restart banner
    /// keys off, including the install-then-uninstall-again case.
    private var loadedThisSession = Set(AppFeature.allCases.filter(\.isAvailable))

    private init() {}

    /// True while something that loaded this session is now uninstalled, so
    /// a restart would actually unload it. Features already uninstalled when
    /// the app came up never loaded, so they need no restart.
    var needsRestartToUnload: Bool {
        loadedThisSession.contains { !$0.isAvailable }
    }

    /// Relaunches the app in place: a detached `open` fires after the process
    /// exits, so the fresh instance starts without the uninstalled features.
    func relaunchApp() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.3; /usr/bin/open \"$1\"", "ryzenstatus-relaunch", path]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            // If spawn failed, do not terminate
        }
    }

    func isAvailable(_ feature: AppFeature) -> Bool { feature.isAvailable }

    var availableCount: Int { AppFeature.allCases.filter(\.isAvailable).count }

    /// Flipping availability runs the feature's binding immediately: off
    /// tears every resource down on the spot, on restores whatever enabled
    /// state the feature had (its own keys are never touched).
    func setAvailable(_ feature: AppFeature, _ available: Bool) {
        guard feature.isAvailable != available else { return }
        UserDefaults.standard.set(available, forKey: feature.availabilityKey)
        if available { loadedThisSession.insert(feature) }
        Self.bindings[feature]?()
        finishAvailabilityChange()
    }

    /// Applies a hub preset: its features become the installed set, with
    /// their enable keys switched on so they work right away, and everything
    /// else uninstalls. Nothing is deleted, so any feature returns with one
    /// click, settings intact.
    func apply(_ preset: FeaturePreset) {
        for key in preset.enableKeys {
            UserDefaults.standard.set(true, forKey: key)
        }
        for feature in AppFeature.allCases
        where feature.isAvailable != preset.features.contains(feature) {
            let joins = preset.features.contains(feature)
            UserDefaults.standard.set(joins, forKey: feature.availabilityKey)
            if joins { loadedThisSession.insert(feature) }
            Self.bindings[feature]?()
        }
        // Features that stayed installed still need a sync: their enable
        // keys may have just flipped on. Syncs are idempotent, so a repeat
        // for the ones handled above costs nothing.
        for feature in preset.features {
            Self.bindings[feature]?()
        }
        finishAvailabilityChange()
    }

    /// Bulk install or uninstall for the hub's "all" buttons: one revision
    /// bump, every changed feature's binding run.
    func setAllAvailable(_ available: Bool) {
        var changed = false
        for feature in AppFeature.allCases where feature.isAvailable != available {
            UserDefaults.standard.set(available, forKey: feature.availabilityKey)
            if available { loadedThisSession.insert(feature) }
            Self.bindings[feature]?()
            changed = true
        }
        if changed { finishAvailabilityChange() }
    }

    /// Launch path: replaces the old unconditional sync block. Only available
    /// features get their binding run, so nothing else even instantiates.
    func syncAtLaunch() {
        // Debug builds trip here when a feature is neither bound nor listed
        // as deliberately unbound; the unit harness checks the same rule.
        assert(Set(Self.bindings.keys).isDisjoint(with: AppFeature.featuresWithoutRuntimeBinding)
                && Set(Self.bindings.keys).union(AppFeature.featuresWithoutRuntimeBinding)
                    == Set(AppFeature.allCases),
               "every AppFeature needs a FeatureRuntime binding or a documented exemption")
        // Island preferences are read together. Its extension bindings all
        // resync the same service; doing that once per installed extension
        // rebuilt observers and presentation repeatedly before the first frame.
        let installed = Set(AppFeature.allCases.filter(\.isAvailable))
        let islandModules = installed.filter { $0.rawValue.hasPrefix("notch") }
        let monitorFeatures: Set<AppFeature> = [.monitorCPU, .monitorGPU, .monitorMemory,
                                               .monitorNetwork, .monitorDisk, .monitorPower]
        for feature in AppFeature.allCases where installed.contains(feature) {
            if !islandModules.contains(feature), !monitorFeatures.contains(feature) {
                Self.bindings[feature]?()
            }
        }
        if !installed.isDisjoint(with: monitorFeatures) { Self.syncMonitor() }
        if installed.contains(.notch) {
            NotchService.shared.syncWithPreferences()
        } else {
            // Retain each extension's teardown when the parent isn't installed.
            for feature in AppFeature.allCases where islandModules.contains(feature) {
                Self.bindings[feature]?()
            }
        }
    }

    /// Re-syncs a set of features (used by the permission sinks); skips
    /// unavailable ones so their singletons never come to life.
    func sync(_ features: [AppFeature]) {
        for feature in features where feature.isAvailable {
            Self.bindings[feature]?()
        }
    }

    /// One bump for Settings, then the surfaces that list other features
    /// catch up: the Command Bar drops rows of features that just left the
    /// hub (so a pin cannot linger as a bare id), and a running Dynamic Island
    /// re-reads which of its sections and extensions are still installed.
    /// Each is only touched while installed, so an uninstalled one never
    /// comes to life from here.
    private func finishAvailabilityChange() {
        revision += 1
        if AppFeature.commandBar.isAvailable { CommandBarService.shared.noteHubChange() }
        if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
    }

    /// What each feature must re-evaluate when its availability (or a
    /// permission it depends on) changes. On-demand tools (uninstaller,
    /// homebrew, cleaning mode, quick toggles, kill process) hold no
    /// resources, so they have no binding — their surfaces simply follow
    /// availability in the UI. Media only binds so uninstalling it can cancel
    /// work already in flight.
    private static let bindings: [AppFeature: () -> Void] = [
        .switcher: {
            AppActivationTracker.shared.syncWithFeatures()
            AppSwitcher.shared.syncWithPreferences()
        },
        .dockPreview: {
            MainActor.assumeIsolated {
                DockPreviewService.shared.syncWithPreferences()
            }
        },
        .dockClick: { DockClickService.shared.syncWithPreferences() },
        .windowMaximizer: { WindowMaximizer.shared.syncWithPreferences() },
        .windowLayout: {
            AppActivationTracker.shared.syncWithFeatures()
            WindowLayoutService.shared.syncWithPreferences()
        },
        .autoQuit: { AutoQuitService.shared.syncWithPreferences() },
        .scrollInverter: { ScrollInverter.shared.syncWithPreferences() },
        .smoothScroll: { SmoothScrollService.shared.syncWithPreferences() },
        // Sideways and linear scrolling share the inverter's wheel tap; the
        // glide applies them too while smooth scrolling swallows the wheel.
        .scrollHorizontal: {
            ScrollInverter.shared.syncWithPreferences()
            SmoothScrollService.shared.syncWithPreferences()
        },
        .linearScroll: {
            ScrollInverter.shared.syncWithPreferences()
            SmoothScrollService.shared.syncWithPreferences()
        },
        .focusFollowsMouse: { FocusFollowsMouseService.shared.syncWithPreferences() },
        .mouseAcceleration: { MouseAccelerationService.shared.syncWithPreferences() },
        .mouseClickDebounce: { MouseClickDebounceService.shared.syncWithPreferences() },
        .spacesOrder: { SpacesOrderHold.shared.syncWithPreferences() },
        .mouseNavigation: { MouseNavigationService.shared.syncWithPreferences() },
        .middleClick: { MiddleClickService.shared.syncWithPreferences() },
        .keyboardDebounce: { KeyboardDebounceService.shared.syncWithPreferences() },
        .textSnippets: {
            TextSnippetService.shared.syncWithPreferences()
            SnippetLibraryService.shared.syncWithPreferences()
        },
        .mouseButtonShortcuts: { MouseButtonShortcutService.shared.syncWithPreferences() },
        .superKey: { SuperKeyService.shared.syncWithPreferences() },
        .quitWindowProtection: { QuitProtectionService.shared.syncWithPreferences() },
        .diskImageInstaller: { DiskImageInstallerService.shared.syncWithPreferences() },
        .wallpaper: { WallpaperService.shared.syncWithPreferences() },
        .clipboardHistory: {
            ClipboardHistoryService.shared.syncWithPreferences()
            ClipboardAutoClearService.shared.syncWithPreferences()
        },
        .pastePlain: { PastePlainService.shared.syncWithPreferences() },
        .finderCutPaste: { FinderCutPaste.shared.syncWithPreferences() },
        .finderRename: { FinderRenameService.shared.syncWithPreferences() },
        .shelf: {
            ShelfService.shared.syncWithPreferences()
            // The island's media drop lives on the shelf; it only exists
            // while the island is installed (the island's own stop ends it).
            if AppFeature.notch.isAvailable { NotchFileToolsService.shared.syncWithPreferences() }
        },
        .mediaTools: {
            if AppFeature.notch.isAvailable { NotchFileToolsService.shared.syncWithPreferences() }
            // Only a job in flight is cancelled: cancelling an idle service
            // would leave a stale "cancelled" state for the next install.
            guard !AppFeature.mediaTools.isAvailable,
                  case .running = MediaService.shared.state else { return }
            MediaService.shared.cancel()
        },
        .urlCleaner: { URLCleanerService.shared.syncWithPreferences() },
        .mixer: {
            AppVolumeMixer.shared.syncWithPreferences()
            AudioInputDeviceManager.shared.syncWithPreferences()
        },
        .soundOutputSwitcher: { SoundOutputSwitcher.shared.syncWithPreferences() },
        .audioPriority: {
            // Priority owns no CoreAudio listener stack of its own: the
            // mixer's device observers stay alive for it even when the
            // Volume mixer is not installed, then the policy starts or stops.
            AppVolumeMixer.shared.syncWithPreferences()
            AudioInputDeviceManager.shared.syncWithPreferences()
            AudioPriorityService.shared.syncWithPreferences()
        },
        .micMute: { MicMuteService.shared.syncWithPreferences() },
        .musicBlock: { MusicLaunchBlocker.shared.syncWithPreferences() },
        .nowPlaying: { NowPlayingService.shared.syncWithPreferences() },
        .keepAwake: {
            KeepAwakeManager.shared.syncWithFeatures()
            HotkeyManager.shared.syncWithPreferences()
        },
        .brightness: { BrightnessService.shared.syncWithPreferences() },
        .extraBrightness: { ExtraBrightnessService.shared.syncWithPreferences() },
        .bluetoothSleep: { BluetoothSleepService.shared.syncWithPreferences() },
        .quickLauncher: { QuickLauncherService.shared.syncWithPreferences() },
        // One capture surface serves all four screen tools; it re-reads which
        // of them are installed whenever any one changes.
        .colorPicker: { ScreenCaptureService.shared.syncWithPreferences() },
        .screenOCR: {
            ScreenCaptureService.shared.syncWithPreferences()
            ScreenTextService.shared.syncWithPreferences()
        },
        .screenshot: {
            ScreenCaptureService.shared.syncWithPreferences()
            ScreenshotService.shared.syncWithPreferences()
            // The recent captures palette and its shortcut serve screenshots
            // and recordings alike; it reads both features itself.
            RecentCaptureService.shared.syncWithPreferences()
        },
        .cameraPreview: { CameraPreviewService.shared.syncWithPreferences() },
        .radialMenu: { RadialMenuService.shared.syncWithPreferences() },
        .scratchpad: { ScratchpadService.shared.syncWithPreferences() },
        .cleaner: { CleanerScheduler.shared.syncWithPreferences() },
        // Upstream rides these on the cleaner; this fork gives WhatsApp
        // downloads its own hub entry, and both services already gate on it.
        // Without this binding the daily pass and the organizer only came to
        // life when their Settings toggles moved, never after a relaunch.
        .whatsAppDownloads: {
            WhatsAppDownloadScheduler.shared.syncWithPreferences()
            WhatsAppDownloadOrganizer.shared.syncWithPreferences()
            // Only on uninstall: this fork's organizer runs on its own switch,
            // independent of the downloads switch upstream gates it on.
            if !AppFeature.whatsAppDownloads.isAvailable {
                WhatsAppDownloadManager.shared.reset()
                WhatsAppDownloadOrganizer.shared.stop()
            }
        },
        // Registers the global shortcut at launch, after a shortcut recording
        // (ShortcutCapture re-syncs this feature) and on install; uninstalling
        // drops the panel, the hotkeys and every cached row.
        .commandBar: { CommandBarService.shared.syncWithPreferences() },
        // Uninstalling drops the IOKit plug/unplug notifications and the
        // cached list; installing resumes for a panel row still on screen.
        // Port Manager has no binding: it runs `lsof` only while open.
        .connectedDevices: { ConnectedDevicesMonitor.shared.syncWithPreferences() },
        // Dynamic Island. The island itself starts here when it is installed
        // and switched on; every extension re-syncs a running island (or
        // stops its own service when the island is gone) so a hub flip takes
        // effect at once. Agents are not part of this fork.
        .notch: { NotchService.shared.syncWithPreferences() },
        .notchGestures: {
            if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
        },
        .notchTimer: {
            if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
            else { NotchTimerService.shared.stop() }
        },
        .notchAccessories: {
            if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
            else { NotchAccessoryService.shared.stop() }
        },
        .notchLyrics: {
            if !NotchLyricsSupport.isEnabled() { NotchLyricsImporter.shared.cancel() }
        },
        // .notchQueue has no binding: the queue is read from
        // NowPlayingService, and a running island re-reads the switch on its own.
        .notchLiveEqualizer: { NotchAudioLevelService.shared.syncWithPreferences() },
        .notchNotifications: {
            if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
            else { NotchNotificationService.shared.stop() }
        },
        .notchDownloads: {
            if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
            else { NotchDownloadService.shared.stop() }
        },
        .notchCalendar: {
            if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
            else { NotchCalendarService.shared.stop() }
        },
        .notchAgents: {
            if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
            else { AgentUsageService.shared.stop() }
        },
        .notchWatch: {
            if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
            else { NotchWatchService.shared.stop() }
        },
        // Leaving folds the wings it rests in, and coming back greets.
        .notchMascot: {
            if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
        },
        .monitorCPU: { FeatureRuntime.syncMonitor() },
        .monitorGPU: { FeatureRuntime.syncMonitor() },
        .monitorMemory: { FeatureRuntime.syncMonitor() },
        .monitorNetwork: { FeatureRuntime.syncMonitor() },
        .monitorDisk: { FeatureRuntime.syncMonitor() },
        .monitorPower: { FeatureRuntime.syncMonitor() },
        .appUpdates: { AppUpdatesService.shared.syncWithPreferences() },
        // .screenRecorder is declared in FeatureCatalog but had no
        // binding here, so only the Settings UI ever tore it down. Disabling the
        // feature via a preset, a settings-backup import or a reset left the
        // service running.
        .screenRecorder: {
            ScreenCaptureService.shared.syncWithPreferences()
            ScreenRecorderService.shared.syncWithPreferences()
            RecentCaptureService.shared.syncWithPreferences()
        },
    ]

    private static func syncMonitor() {
        SystemMonitor.shared.planDidChange()
        Task { @MainActor in
            MonitorAlertService.shared.syncWithPreferences()
        }
    }
}
