// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Carbon.HIToolbox
import Combine
import os.log
import SwiftUI

// E1 stage 1: this class only ever runs on the main thread — every entry point
// is an AppKit delegate callback or a `queue: .main` notification — so stating
// that isolation lets the compiler check it instead of assuming it. Clears 389
// of the 2037 strict-concurrency diagnostics on its own; see the commit message.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusController: StatusItemController!
    private let popover = NSPopover()
    private let nowPlayingPopover = NSPopover()
    /// Whether the now-playing popup content is currently unloaded (memory
    /// setting): the popover hosts an EmptyView until the next open.
    private var nowPlayingPopupUnloaded = false
    private var popoverClosedAt = Date.distantPast
    /// The app that was in front when the panel opened, followed while it
    /// stays open, so a plain dismissal can hand activation back to it.
    private var panelActivationSource: NSRunningApplication?
    private var panelActivationObservers: [NSObjectProtocol] = []
    /// Why the panel is closing, decided by whoever asked for the close.
    private var popoverCloseReason: PanelCloseReason?
    private var popoverDismissMonitor: Any?
    private var popoverLocalDismissMonitor: Any?
    private var popoverKeyboardMonitor: Any?
    private var popoverIsClosing = false
    private var popoverIsSwitchingAnchor = false
    /// Actions opened from our panel keep the app that was actually active,
    /// even when it has no ordinary window in the current Space.
    var panelActivationSourcePID: pid_t? {
        guard let source = panelActivationSource, !source.isTerminated else { return nil }
        return source.processIdentifier
    }
    private var metricAnchorSwitchSerial = 0
    private var popoverCloseCompletions: [() -> Void] = []
    private var isTerminating = false
    /// A quit is waiting for the Command Bar to hand back the keyboard
    /// layout it borrowed (see applicationShouldTerminate).
    private var inputSourceRestorationPending = false
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var dockPreviewIntroWindow: NSWindow?
    private var supportIntroWindow: NSWindow?
    private var feedbackWindow: NSWindow?
    private var updateHighlightsWindow: NSWindow?
    private var supportIntroCanClose = false
    private var updateShowcaseWindow: NSWindow?
    private var updatePreviewWindow: NSWindow?
    private var whatsNewWindow: NSWindow?
    private var whatsNewIsReview = false
    private static let updateLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ryzenstatus",
                                          category: "update")
    private let popoverOpenDuration: TimeInterval = 0.18
    private let popoverCloseDuration: TimeInterval = 0.14

    // MARK: - Lifecycle

    /// Asking another app about its windows waits for that app to answer, and
    /// the default wait is long. An app that is busy saving, or stuck on a slow
    /// disk, would hold this one still each time, and some of those questions
    /// are asked where the whole session waits on them. The limit is set once
    /// here, low enough that a slow answer is dropped rather than felt. It is
    /// the process-wide default, so nothing else may set a timeout on the
    /// system-wide element (#938); hot paths cap their own elements lower.
    private static func boundAccessibilityWaits() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.35)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Self.boundAccessibilityWaits()
        // Pay the first AppKit process lookup before an input callback needs
        // it. Each click still resolves the current process independently.
        _ = AssistiveKeyboard.isRunning

        // Finish the on-disk rename for installs carried over from a pre-2.5
        // build, or retire a leftover old-named bundle. Returns true when we are
        // quitting to relaunch under the new name, so skip the rest of startup.
        if BundleMigration.run() { return }

        DispatchQueue.global(qos: .utility).async {
            RecorderGIFWorkspace.sweep()
        }

        // Redo a launch at login registration the system lost. The stored
        // choice is the last thing the user expressed in the app; startup
        // never turns the item off.
        LaunchAtLogin.repairAtStartup()

        // An accessory (LSUIElement) app gets no default main menu, so the standard
        // keyboard shortcuts (Cmd+H/M/W/Q and the Edit shortcuts Cmd+C/V/X/A) have
        // no menu items to fire and do nothing in the Settings window. Install one.
        installMainMenu()
        HorizontalWheelScrolling.install()
        PanelLayout.resetCollapsedSectionsOnce(for: "2.15.1")

        statusController = StatusItemController()
        StatusItemController.shared = statusController
        statusController.onLeftClick = { [weak self] in
            self?.captureStatusClick()
            self?.toggleMainPopover()
        }
        statusController.onRightClick = { [weak self] item in
            if AppFeature.keepAwake.isAvailable
                && UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakeRightClickToggle) {
                KeepAwakeManager.shared.toggle()
            } else {
                self?.showContextMenu(for: item)
            }
        }
        statusController.onMetricClick = { [weak self] metric, button in
            self?.captureStatusClick()
            self?.showMetricPanel(for: metric, anchoredTo: button)
        }
        // Opens the clipboard window, which centers on the pointer's screen
        // instead of anchoring to a status item.
        statusController.onClipboardPreviewClick = {
            ClipboardHistoryService.shared.toggleHistoryWindow()
        }
        // The shelf drop zone chip anchors itself under the menu bar icon.
        ShelfService.shared.statusItemFrameProvider = { [weak self] in
            guard let item = self?.statusController.statusItem, item.isVisible,
                  let window = self?.statusController.button?.window else { return nil }
            // A hidden menu bar parks the item's window at a fallback spot;
            // trusting it would dock the shelf there instead of where the
            // pointer is.
            let frame = window.frame
            guard StatusItemAnchorSupport.isTrustworthyStatusFrame(frame) else { return nil }
            return frame
        }
        // The now-playing menu bar item toggles its own detached popup
        // anchored to its own status item — never the main panel.
        NowPlayingService.shared.onActivate = { [weak self] button in
            self?.captureStatusClick()
            self?.showNowPlayingPopup(anchoredTo: button)
        }
        // Closing the feature (or quitting) takes its popup down with it.
        NowPlayingService.shared.onDeactivate = { [weak self] in
            self?.closeNowPlayingPopup()
            NowPlayingPopupController.shared.tearDown()
        }
        // The global hotkeys toggle the same surfaces the menu bar item
        // toggles (PlayStatus parity: ⌃⌥⌘O popover, ⌃⌥⌘D detached).
        NowPlayingService.shared.onTogglePopupHotkey = { [weak self] in
            self?.captureStatusClick()
            self?.toggleNowPlayingPopupFromHotkey()
        }
        NowPlayingService.shared.onToggleDetachedHotkey = { [weak self] in
            self?.captureStatusClick()
            self?.toggleNowPlayingDetachedFromHotkey()
        }

        setUpPopover()
        setUpNowPlayingPopover()
        AppAppearanceController.shared.apply()
        GlobalShortcut.startObservingKeyboardLayout()
        bindManagers()

        // A marker from an earlier run may name macOS shortcuts this app
        // switched off and never gave back (a crash, a forced quit). Give them
        // back before the first feature claims anything: a claim resolves what
        // every source wants together, and an unclaimed marker resolves to
        // nothing. The switcher holds none here, so nothing is kept.
        SystemShortcutTakeover.recoverIfNeeded(keeping: [])
        HotkeyManager.shared.onActivate = { KeepAwakeManager.shared.toggle() }
        HotkeyManager.shared.syncWithPreferences()

        KeepAwakeManager.shared.recoverIfNeeded {
            KeepAwakeManager.shared.activateOnLaunchIfNeeded()
        }
        // Puts the Space arrangement back when a previous run held it and
        // the feature has since been uninstalled.
        SpacesOrderHold.recoverIfNeeded()
        // One binding per feature: only available features are touched, so a
        // feature switched off in the hub never even instantiates here.
        FeatureRuntime.shared.syncAtLaunch()
        // Start global AMD Auto EPP monitoring — runs continuously in the
        // background so the CPU throttles down even when Settings are closed.
        AutoEppService.shared.start()
        // C6 residency sampling (kext selector 31) feeds the dashboard bar and
        // the AMD settings page from one shared poller.
        C6ResidencyService.shared.start()
        // Fans mapped to curves get them back now (the app hands every fan to
        // the BIOS when it quits), not when Settings › Fans is next opened.
        FanCurveController.startIfConfigured()
        // Re-apply a persisted Gaming Mode (Extreme preset + Keep Awake +
        // hidden icon) left on by a previous session.
        GamingModeService.shared.restoreIfNeeded()
        if AppFeature.monitorPower.isAvailable, PowerSampler.hasInternalBattery {
            MaxCapacityProbe.shared.refreshIfStale()
        }
        UpdateService.shared.startAutomaticChecks()
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)

        // If Accessibility is granted while the app is running (e.g. during
        // onboarding), bring the input features up without a relaunch.
        Permissions.shared.$accessibility
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in
                FeatureRuntime.shared.sync([
                    .scrollInverter, .scrollZoom, .smoothScroll, .mouseNavigation, .switcher,
                    .dockPreview, .finderCutPaste, .finderRename, .autoQuit, .dockClick,
                    .middleClick, .windowMaximizer, .keyboardDebounce, .windowLayout,
                    .textSnippets, .superKey, .brightness, .radialMenu,
                    .quitWindowProtection,
                    .scrollHorizontal, .linearScroll, .focusFollowsMouse, .mouseClickDebounce,
                    // The island reads the menu bar through Accessibility to
                    // fit beside it on a Mac without a notch.
                    .notch,
                ])
            }
            .store(in: &cancellables)

        Permissions.shared.$screenRecording
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in
                FeatureRuntime.shared.sync([.dockPreview])
            }
            .store(in: &cancellables)

        // Keep the menu titles in step with the in-app language.
        L10n.shared.$language
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.installMainMenu() }
            .store(in: &cancellables)

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: DefaultsKey.hasOnboarded) {
            showOnboarding(mode: .full)
        } else {
            // Keep the last seen version marker current. An update is queued
            // for the What's New window first, so a start that goes wrong
            // before the window opens still shows it next time.
            let previousVersion = defaults.string(forKey: DefaultsKey.lastUpdateIntroVersion)
            queueWhatsNewIfNeeded(previousVersion: previousVersion)
            defaults.set(OnboardingInfo.currentFeatureSet, forKey: DefaultsKey.featuresOnboardingVersion)
            defaults.set(AppInfo.version, forKey: DefaultsKey.lastUpdateIntroVersion)
            recoverStatusItemAfterUpdate(previousVersion: previousVersion)
            presentUpdateIntros()
        }
    }

    /// The Command Bar may have switched the keyboard to an ASCII layout while
    /// it was open. Put the person's own layout back before the process goes,
    /// or they are left typing on the borrowed one after quit.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if inputSourceRestorationPending { return .terminateLater }
        guard AppFeature.commandBar.isAvailable,
              CommandBarService.shared.hasBorrowedInputSource else { return .terminateNow }
        inputSourceRestorationPending = true
        // Terminate-later runs a modal loop, which may be nested inside a
        // main-queue callback. Schedule in both modes before approving quit.
        RunLoop.main.perform(inModes: [.default, .modalPanel]) { [weak self] in
            MainActor.assumeIsolated {
                CommandBarService.shared.restoreBorrowedInputSource()
                self?.inputSourceRestorationPending = false
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        if AppFeature.commandBar.isAvailable {
            CommandBarService.shared.restoreBorrowedInputSource()
        }
        // Takes the island down without replaying a capture it was holding:
        // the process is going, so there is nowhere left to hand it back to.
        if AppFeature.notch.isAvailable { NotchService.shared.stop(restoreCapture: false) }
        closeNowPlayingPopup()
        NowPlayingPopupController.shared.tearDown()
        if AppFeature.brightness.isAvailable {
            BrightnessService.shared.restoreDisplaysBeforeTermination()
        }
        AutoEppService.shared.stop()
        C6ResidencyService.shared.stop()
        FanCurveController.shared.resetFansToAutoSync()
        LongHistoryStore.shared.save(synchronously: true)
        ExtraBrightnessService.shared.stop()
        ProcessUsageService.shared.stopNetworkMonitoring(force: true)
        URLCleanerService.shared.stop()
        WindowMaximizer.shared.stop()
        WindowLayoutService.shared.suspend()
        KeyboardDebounceService.shared.suspend()
        // Takes the Caps Lock mapping back out before the process goes away.
        SuperKeyService.shared.suspend()
        TextSnippetService.shared.suspend()
        MiddleClickService.shared.suspend()
        SmoothScrollService.shared.suspend()
        // Wheel taps (sideways and linear scrolling ride the inverter's tap),
        // focus follows mouse and the click filter go back before the process.
        ScrollInverter.shared.suspend()
        FocusFollowsMouseService.shared.stop()
        MouseClickDebounceService.shared.suspend()
        // Pointer acceleration is a system setting: it is put back on quit.
        if AppFeature.mouseAcceleration.isAvailable
            || MouseAccelerationRecovery.hasPendingEntries() {
            MouseAccelerationService.shared.stop()
        }
        MouseNavigationService.shared.suspend()
        DockPreviewService.shared.stop()
        SoundOutputSwitcher.shared.stop()
        AppVolumeMixer.shared.stopAll()
        // Flushes any scratchpad edit still inside the save debounce.
        ScratchpadService.shared.suspend()
        // Every macOS shortcut a feature took over goes back now, whichever
        // feature held it; not all of them suspend here.
        SystemShortcutTakeover.restoreAll()
        // The clipboard history persists through an async pipeline; the last
        // mutation (often a Clear) must land before the process dies.
        if AppFeature.clipboardHistory.isAvailable {
            ClipboardHistoryService.shared.flushBeforeTermination()
        }
        KeepAwakeManager.shared.deactivate(reason: .quit)
        // Close the kext connection and cancel the watchdog task.
        // Must run AFTER every other kext user above (FanCurveController.resetFansToAutoSync(),
        // C6ResidencyService.stop(), etc.) — closing the connection kills all later IPC.
        ProcessorModel.shared.closeDriver()
    }

    /// The lifeline when the menu bar icon goes missing. Opening the app again
    /// from Finder, Spotlight or Launchpad while it's already running lands here:
    /// force the icon back and pop the panel so there's immediate proof the app is
    /// alive. Without this, a hidden icon would strand the app running with no way
    /// in. (A cold launch can't happen while running, so this is the recovery path.)
    /// Reopens that Siri and Shortcuts send on their own are ignored.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let requester = ReopenRequestSupport.currentSender()
        guard ReopenRequestSupport.isPersonOpeningApp(requester) else {
            os_log("reopen ignored from %{public}s", ReopenRequestSupport.logName(requester))
            return false
        }
        guard !flag else { return true }
        // Gaming Mode hides the status icon by design — a relaunch is the
        // guaranteed way back in, so skip the icon-recovery dance and open
        // Settings directly instead of racing the next refresh tick.
        if GamingModeService.shared.isActive {
            openSettingsWindow()
            return true
        }
        // A deliberate reopen with no windows showing is the user's recovery action.
        // Rebuild the menu bar item only when it is actually missing: the
        // pre-rebuild item has a settled frame, so iconIsOnScreen() is trustworthy
        // here (the not-ready-frame caveat below only applies to a freshly created
        // item), and a dropped icon reads off-screen/zero, so recovery still gets
        // its rebuild with fresh placement. A healthy icon is left alone: on
        // macOS 27 a rebuilt item's window can keep reporting the slot it was
        // born in (the far right of the status area) while the icon draws at the
        // user's arranged spot, and that mismatch strands the panel against the
        // screen edge and survives relaunches. An item the app took out of the
        // bar itself, for Dynamic Island, is not missing either: a rebuild
        // would only hide it again, and Settings opens below.
        if statusController?.mainItemHiddenByChoice != true, !iconIsOnScreen() {
            statusController?.recreateStatusItem(resetPlacement: true)
        }
        // Decide on the next run-loop turn: a freshly rebuilt status item has no
        // laid-out on-screen frame yet this turn, so iconIsOnScreen() would read a
        // not-ready frame and wrongly skip the panel. After layout: pop the panel
        // when the icon is genuinely on screen, else fall back to the Settings
        // window. Either way the user ALWAYS gets back in.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.iconIsOnScreen(), !self.popover.isShown {
                self.popoverClosedAt = .distantPast
                self.togglePopover()
            }
            if !self.popover.isShown {
                self.openSettingsWindow()
            }
        }
        return true
    }

    /// Whether the menu bar icon is actually visible on a screen, rather than
    /// present in the status bar but clipped or dropped by a crowded/notched menu
    /// bar (in which case the button still has a window, just not an on-screen one).
    private func iconIsOnScreen() -> Bool {
        guard let frame = statusController?.statusItem.button?.window?.frame,
              frame.width > 0, frame.height > 0 else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func bindManagers() {
        KeepAwakeManager.shared.onSessionEnded = { reason in
            let strings = L10n.shared.s
            switch reason {
            case .timer:
                Notifier.post(title: strings.notifySessionEndedTitle, body: strings.notifySessionEndedBody)
            case .battery:
                Notifier.post(title: strings.notifyBatteryTitle, body: strings.notifyBatteryBody)
            default:
                break
            }
        }
    }

    // MARK: - Main panel

    private func setUpPopover() {
        // Application-defined (not .transient) so the panel stays open while the
        // user works in our own Settings window and sees changes live. Click
        // monitors below dismiss it when it would block that same Settings window.
        popover.behavior = .applicationDefined
        // We animate the underlying popover window ourselves so applicationDefined
        // dismissal, right-click menus and live Settings previews stay predictable.
        popover.animates = false
        popover.delegate = self
        let host = NSHostingController(rootView: MenuPanelView())
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        AppAppearanceController.shared.follow(panel: popover)
        NotificationCenter.default.addObserver(self, selector: #selector(appResignedActive),
                                               name: NSApplication.didResignActiveNotification, object: nil)
    }

    private func togglePopover(anchor button: NSStatusBarButton? = nil) {
        if popover.isShown {
            closePopover(reason: .statusItem)
            return
        }
        showPopover(anchor: button)
    }

    private func toggleMainPopover() {
        // With "open the app panel in Dynamic Island" on, the menu bar item
        // opens (or closes) the same panel inside the island instead. An
        // island that cannot show right now (fullscreen, another display
        // asleep) falls back to the popover so a click is never lost.
        if NotchSupport.routesAppPanel(), NotchService.shared.acceptsSystemFeedback {
            NotchService.shared.openAppPanel(toggle: true); return
        }
        if !popover.isShown {
            MenuPanelFocus.shared.showNormalPanel()
        }
        togglePopover()
    }

    /// The now-playing item toggles its own popup; the main panel and the
    /// popup are mutually exclusive, handled in showNowPlayingPopup/showPopover.
    private func showMetricPanel(for metric: MenuBarMetric, anchoredTo button: NSStatusBarButton) {
        let detailKind = metric.detailKind
        // A metric's own item follows the same routing as the main item, as
        // long as the island still carries the section that shows metrics.
        if NotchSupport.routesAppPanel(), NotchService.shared.acceptsSystemFeedback,
           NotchSupport.modules().contains(.system) {
            NotchService.shared.showMetric(detailKind, toggle: true); return
        }
        if popover.isShown {
            if MenuPanelFocus.shared.activeMetric == detailKind {
                metricAnchorSwitchSerial &+= 1
                MenuPanelFocus.shared.clearMetricFocus()
                closePopover(animated: false, reason: .statusItem)
                return
            }
            MenuPanelFocus.shared.focus(detailKind)
            scheduleMetricAnchorSwitch(to: detailKind, anchoredTo: button)
            return
        }
        MenuPanelFocus.shared.focus(detailKind)
        showPopover(anchor: button)
    }

    private func scheduleMetricAnchorSwitch(to detailKind: MetricDetailKind, anchoredTo button: NSStatusBarButton) {
        metricAnchorSwitchSerial &+= 1
        let serial = metricAnchorSwitchSerial
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self, weak button] in
            guard let self,
                  let button,
                  self.popover.isShown,
                  self.metricAnchorSwitchSerial == serial,
                  MenuPanelFocus.shared.activeMetric == detailKind else { return }
            self.reanchorMetricPopover(to: detailKind, anchoredTo: button)
        }
    }

    private func reanchorMetricPopover(to detailKind: MetricDetailKind, anchoredTo button: NSStatusBarButton) {
        guard popover.isShown else {
            MenuPanelFocus.shared.focus(detailKind)
            showPopover(anchor: button, allowRecentClose: true, animate: false, activate: false)
            return
        }
        popoverIsSwitchingAnchor = true
        MenuPanelFocus.shared.setSwitchingMetricAnchor(true)
        let expectedMidX = statusButtonMidX(button)
        // The panel measures itself against this while the popover lays out,
        // so it has to be right before the content is asked for its size.
        PanelInteractionState.shared.anchorScreen = statusScreen(for: button)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        if let window = popover.contentViewController?.view.window,
           let targetMidX = correctedPopoverMidX(for: button) {
            beginPopoverDriftCorrection(window: window, targetMidX: targetMidX, owner: popover)
        } else {
            endPopoverDriftCorrection()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self, weak button] in
            guard let self,
                  let button,
                  self.popover.isShown,
                  self.metricAnchorSwitchSerial > 0,
                  MenuPanelFocus.shared.activeMetric == detailKind else {
                self?.popoverIsSwitchingAnchor = false
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
                return
            }
            if let expectedMidX,
               let popoverMidX = self.popover.contentViewController?.view.window?.frame.midX,
               abs(popoverMidX - expectedMidX) <= 34 {
                self.popoverIsSwitchingAnchor = false
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
                return
            }
            self.switchMetricPopover(to: detailKind, anchoredTo: button)
        }
    }

    private func statusButtonMidX(_ button: NSStatusBarButton) -> CGFloat? {
        guard let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).midX
    }

    /// Where the user last physically clicked a status button, captured at
    /// action time. The deferred metric re-shows fire up to ~0.2s after the
    /// click, and re-reading the pointer there would chase a flicked-away
    /// cursor; the captured point is immune to that. Accessibility presses
    /// (no mouse event) capture nothing, so they never "correct" toward a
    /// pointer parked anywhere on screen.
    private var lastStatusClick: (point: NSPoint, at: Date)?
    private var popoverDriftTargetMidX: CGFloat?
    private var popoverDriftObservers: [NSObjectProtocol] = []
    /// Which popover currently owns the drift correction. Both popovers
    /// share the correction state, and a closing popover's deferred
    /// popoverDidClose must not uninstall the correction the incoming
    /// popover just installed.
    private weak var popoverDriftOwner: NSPopover?

    private func captureStatusClick() {
        guard let event = NSApp.currentEvent,
              Self.statusClickEventTypes.contains(event.type),
              (0...Self.statusClickFreshness).contains(ProcessInfo.processInfo.systemUptime - event.timestamp)
        else {
            lastStatusClick = nil
            return
        }
        lastStatusClick = (NSEvent.mouseLocation, Date())
    }

    /// How long a captured click still says where the person clicked.
    private static let statusClickFreshness: TimeInterval = 0.5

    private var freshStatusClick: NSPoint? {
        guard let click = lastStatusClick,
              (0...Self.statusClickFreshness).contains(Date().timeIntervalSince(click.at)) else { return nil }
        return click.point
    }

    /// The on-screen midX the open panel must center on, or nil when the
    /// button's reported frame can be trusted. A fresh physical click landing
    /// clearly outside the frame the button claims to occupy is the macOS 27
    /// stale-frame mismatch (see StatusItemAnchorSupport): the click marks
    /// where the icon is actually drawn, so the panel centers there. The
    /// positioning rect cannot express this (AppKit intersects it with the
    /// button's bounds), so the correction moves the popover's window instead.
    private func correctedPopoverMidX(for button: NSStatusBarButton) -> CGFloat? {
        guard let click = freshStatusClick,
              let reportedMidX = statusButtonMidX(button),
              StatusItemAnchorSupport.anchorDriftX(clickX: click.x,
                                                   reportedMidX: reportedMidX,
                                                   buttonWidth: button.bounds.width) != nil
        else { return nil }
        return click.x
    }

    private static let statusClickEventTypes: Set<NSEvent.EventType> = [
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
    ]

    /// Slides the popover window so its center (and thus the arrow tip, which
    /// keeps its offset from the window) lands on the real icon, and keeps it
    /// there: NSPopover re-derives the window frame from the stale button
    /// frame on every content resize (switching panel tabs), which would
    /// fling the panel back to the phantom slot.
    private func beginPopoverDriftCorrection(window: NSWindow, targetMidX: CGFloat,
                                             owner: NSPopover) {
        endPopoverDriftCorrection()
        popoverDriftOwner = owner
        popoverDriftTargetMidX = targetMidX
        applyPopoverDriftFrame(window)
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            popoverDriftObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self, weak window] _ in
                // Registered with `queue: .main` above, so this body always runs
                // on the main thread; assumeIsolated states that to the compiler.
                MainActor.assumeIsolated {
                    guard let window else { return }
                    self?.applyPopoverDriftFrame(window)
                }
            })
        }
    }

    private func applyPopoverDriftFrame(_ window: NSWindow) {
        guard let targetMidX = popoverDriftTargetMidX else { return }
        var frame = window.frame
        var midX = targetMidX
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            let margin: CGFloat = 8
            midX = min(max(midX, visible.minX + frame.width / 2 + margin),
                       visible.maxX - frame.width / 2 - margin)
        }
        // The 2pt tolerance breaks the loop with our own setFrame's didMove.
        guard abs(frame.midX - midX) > 2 else { return }
        frame.origin.x = (midX - frame.width / 2).rounded()
        window.setFrame(frame, display: true)
    }

    private func endPopoverDriftCorrection() {
        popoverDriftObservers.forEach { NotificationCenter.default.removeObserver($0) }
        popoverDriftObservers.removeAll()
        popoverDriftTargetMidX = nil
        popoverDriftOwner = nil
    }

    private func switchMetricPopover(to detailKind: MetricDetailKind, anchoredTo button: NSStatusBarButton) {
        popoverIsSwitchingAnchor = true
        MenuPanelFocus.shared.setSwitchingMetricAnchor(true)
        removePopoverDismissMonitor()
        popoverIsClosing = true
        popover.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self, weak button] in
            guard let self else {
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
                return
            }
            guard let button else {
                self.popoverIsSwitchingAnchor = false
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
                return
            }
            self.popoverClosedAt = .distantPast
            MenuPanelFocus.shared.focus(detailKind)
            self.showPopover(anchor: button, allowRecentClose: true, animate: false, activate: false)
            DispatchQueue.main.async {
                self.popoverIsSwitchingAnchor = false
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
            }
        }
    }

    /// The display whose menu bar holds the item, so the panel caps its height
    /// against that screen rather than whichever one happens to be main.
    private func statusScreen(for button: NSStatusBarButton) -> NSScreen? {
        // Replicated menu bars (including Sidecar) can report the status
        // window on a different display. The captured click identifies the
        // actual bar, including vertically arranged screens with the same x.
        if let click = freshStatusClick,
           let clicked = NSScreen.screens.first(where: { NSMouseInRect(click, $0.frame, false) }) {
            return clicked
        }
        if let frame = button.window?.frame,
           let hosting = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) {
            return hosting
        }
        return button.window?.screen ?? NSScreen.withMenuBar
    }

    private func showPopover(anchor button: NSStatusBarButton? = nil,
                             allowRecentClose: Bool = false,
                             animate: Bool = true,
                             activate: Bool = true) {
        guard !popover.isShown else { return }
        // The click that just transient-dismissed the popover also lands here;
        // reopening would make the panel look impossible to close.
        guard allowRecentClose || Date().timeIntervalSince(popoverClosedAt) > 0.35 else { return }
        guard let button = button ?? statusController.button else { return }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            panelActivationSource = front
        }
        // The main panel and the now-playing popup never show together.
        closeNowPlayingPopup()

        // The panel measures itself against this while the popover lays out, so
        // it has to be known before the content is asked for its size.
        PanelInteractionState.shared.anchorScreen = statusScreen(for: button)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            // Keep the panel alive next to fullscreen apps and on any Space —
            // without this it blinks shut when another display is fullscreen.
            window.collectionBehavior.insert([.fullScreenAuxiliary, .canJoinAllSpaces])
            if let panel = window as? NSPanel {
                panel.hidesOnDeactivate = false
            }
            window.contentView?.layoutSubtreeIfNeeded()
            window.makeKey()
            if let targetMidX = correctedPopoverMidX(for: button) {
                beginPopoverDriftCorrection(window: window, targetMidX: targetMidX, owner: popover)
            } else {
                endPopoverDriftCorrection()
            }
            if animate {
                animatePopoverOpen(window)
            } else {
                popoverIsClosing = false
                window.alphaValue = 1
            }
        }
        if activate {
            beginPanelActivationTracking()
            NSApp.activate(ignoringOtherApps: true)
        }
        // Only arm the dismiss monitor if the popover actually presented — otherwise
        // popoverDidClose never fires and the global monitor would leak indefinitely.
        guard popover.isShown else { return }
        installPopoverDismissMonitor()
    }

    func isOverStatusItem(_ point: NSPoint) -> Bool {
        statusController.containsStatusItem(at: point)
    }

    private func installPopoverDismissMonitor() {
        removePopoverDismissMonitor()
        // A global monitor only sees events delivered to OTHER apps, so a click in
        // another app or on the desktop dismisses the panel.
        popoverDismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            guard !PanelInteractionState.shared.preventsPopoverDismissal else { return }
            guard self.statusController.containsStatusItem(at: NSEvent.mouseLocation) == false else { return }
            self.closePopover(reason: .outsideClick)
        }

        // Local events cover our own Settings window. Keep Settings + panel open
        // when they sit side by side for live reordering, but close the panel if it
        // overlaps Settings and the user clicks Settings to get it out of the way.
        popoverLocalDismissMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if self.shouldDismissPopover(forLocalEvent: event) {
                self.closePopover(reason: .outsideClick)
            }
            return event
        }

        popoverKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handlePopoverKeyDown(event)
        }
    }

    private func removePopoverDismissMonitor() {
        if let monitor = popoverDismissMonitor {
            NSEvent.removeMonitor(monitor)
            popoverDismissMonitor = nil
        }
        if let monitor = popoverLocalDismissMonitor {
            NSEvent.removeMonitor(monitor)
            popoverLocalDismissMonitor = nil
        }
        if let monitor = popoverKeyboardMonitor {
            NSEvent.removeMonitor(monitor)
            popoverKeyboardMonitor = nil
        }
    }

    private func shouldDismissPopover(forLocalEvent event: NSEvent) -> Bool {
        guard !PanelInteractionState.shared.preventsPopoverDismissal else { return false }
        guard event.window === settingsWindow,
              let settingsFrame = settingsWindow?.frame,
              let popoverFrame = popover.contentViewController?.view.window?.frame else {
            return false
        }
        return settingsFrame.intersects(popoverFrame)
    }

    private func handlePopoverKeyDown(_ event: NSEvent) -> NSEvent? {
        if popover.isShown, event.keyCode == UInt16(kVK_Escape) {
            closePopover(reason: .escape)
            return nil
        }

        guard popover.isShown,
              PanelInteractionState.shared.viewKeepsPopoverOpen,
              isPlainPopoverHoldKey(event),
              let window = popover.contentViewController?.view.window else {
            return event
        }

        // Text controls inside the popover, especially the Homebrew search
        // field, need Space/Return delivered through AppKit's normal field
        // editor path so delegates and target/actions can submit correctly.
        if isTextEditingActive(in: window) {
            return event
        }

        if NSApp.keyWindow === window || event.window === window {
            window.firstResponder?.keyDown(with: event)
            return nil
        }
        return event
    }

    private func isPlainPopoverHoldKey(_ event: NSEvent) -> Bool {
        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(blockedModifiers).isEmpty else { return false }
        return event.keyCode == 49 || event.keyCode == 36 || event.keyCode == 76
    }

    private func isTextEditingActive(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        if responder is NSTextView || responder is NSTextField {
            return true
        }
        guard let fieldEditor = window.fieldEditor(false, for: nil) else { return false }
        return responder === fieldEditor
    }

    @objc private func appResignedActive() {
        // Leaving the app entirely (e.g. ⌘Tab) dismisses the panel; switching to
        // our own Settings window keeps the app active, so it stays open.
        if popover.isShown, !PanelInteractionState.shared.preventsPopoverDismissal {
            guard statusController.containsStatusItem(at: NSEvent.mouseLocation) == false else { return }
            closePopover(reason: .outsideClick)
        }
    }

    @objc private func appBecameActive() {
        // Coming back to the app is a good moment to surface a fresh release.
        // (Menu bar icon recovery happens on a deliberate reopen, not here: this
        // fires on every activation, so rebuilding here would cause churn/flicker.)
        UpdateService.shared.checkIfStale()
        restoreAfterAppStoreHandoff()
    }

    /// The app update list can only hand a store purchase over to the App
    /// Store. With no Dock icon there is no way back to the window that sent
    /// the person there, so returning brings it forward again, on the page
    /// they left, with the list already reading the truth.
    private func restoreAfterAppStoreHandoff() {
        guard AppFeature.appUpdates.isAvailable else { return }
        let service = AppUpdatesService.shared
        service.applicationBecameActive()
        guard service.consumeUpdateHandoffReturn(),
              settingsWindow?.isVisible == true else { return }
        openSettingsWindow()
    }

    /// Closing the panel also folds an open Dynamic Island, which may be
    /// showing the same panel. The island passes `preservingNotch` when it
    /// closes the popover on its own way open.
    func closePopover(animated: Bool = true, after delay: TimeInterval = 0,
                      preservingNotch: Bool = false,
                      reason: PanelCloseReason = .action,
                      completion: (() -> Void)? = nil) {
        if !preservingNotch, NotchSupport.isEnabled() { NotchService.shared.collapse() }
        if popover.isShown { popoverCloseReason = reason }
        if delay <= 0 {
            closePopoverNow(animated: animated, completion: completion)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.closePopoverNow(animated: animated, completion: completion)
        }
    }

    private func closePopoverNow(animated: Bool, completion: (() -> Void)?) {
        guard popover.isShown else {
            completion?()
            return
        }
        if let completion { popoverCloseCompletions.append(completion) }
        guard !popoverIsClosing else { return }
        guard animated, let window = popover.contentViewController?.view.window else {
            finishPopoverClose()
            return
        }

        popoverIsClosing = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = popoverCloseDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            // AppKit delivers an animation completion handler on the main thread,
            // but the newer SDK does not type it as main-actor-isolated, so the
            // call below needs the isolation stated. Only visible when building
            // against Xcode's SDK, not the Command Line Tools one — see the
            // commit message.
            MainActor.assumeIsolated {
                window?.alphaValue = 1
                self?.finishPopoverClose()
            }
        }
    }

    private func animatePopoverOpen(_ window: NSWindow) {
        popoverIsClosing = false
        window.alphaValue = 0

        NSAnimationContext.runAnimationGroup { context in
            context.duration = popoverOpenDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        } completionHandler: { [weak self, weak window] in
            guard let self,
                  self.popover.isShown,
                  window === self.popover.contentViewController?.view.window else { return }
            window?.alphaValue = 1
        }
    }

    private func finishPopoverClose() {
        guard popover.isShown else {
            popoverIsClosing = false
            runPopoverCloseCompletions()
            return
        }
        popoverIsClosing = true
        popover.performClose(nil)
        runPopoverCloseCompletions()
    }

    private func runPopoverCloseCompletions() {
        let completions = popoverCloseCompletions
        popoverCloseCompletions.removeAll()
        completions.forEach { $0() }
    }

    // MARK: - Now Playing popup

    private func setUpNowPlayingPopover() {
        // .transient: the popup dismisses itself on any interaction outside
        // it, so it needs no dismiss monitors of its own. The item toggles
        // on mouseDown, which sidesteps the transient close-reopen race.
        nowPlayingPopover.behavior = .transient
        nowPlayingPopover.animates = false
        nowPlayingPopover.delegate = self
        let host = NSHostingController(rootView: AnyView(NowPlayingPopupView()))
        // The popup manages its size explicitly (a fixed card, clamped to
        // the space under the menu bar); automatic sizing would fight that.
        host.sizingOptions = []
        nowPlayingPopover.contentViewController = host
        NowPlayingPopupController.shared.popover = nowPlayingPopover
        AppAppearanceController.shared.follow(panel: nowPlayingPopover)
    }

    /// The now-playing item toggles its own popup anchored to its own
    /// button. The main panel and the popup never show together; the
    /// detached floating window is the same surface as the anchored popup,
    /// so the item toggles whichever one is live — never two at once.
    private func showNowPlayingPopup(anchoredTo button: NSStatusBarButton) {
        let popupController = NowPlayingPopupController.shared
        if popupController.isDetachedVisible {
            popupController.closeDetached()
            return
        }
        if nowPlayingPopover.isShown {
            closeNowPlayingPopup()
            return
        }
        if popover.isShown {
            closePopover { [weak self, weak button] in
                guard let button else { return }
                self?.presentNowPlayingPopup(anchoredTo: button)
            }
            return
        }
        presentNowPlayingPopup(anchoredTo: button)
    }

    private func presentNowPlayingPopup(anchoredTo button: NSStatusBarButton) {
        guard !nowPlayingPopover.isShown else { return }
        NowPlayingPopupController.shared.anchorButton = button
        let rehosted = restoreNowPlayingPopupContent()
        // contentSize is only trustworthy while hidden; visible resizes go
        // through window.setFrame below.
        if rehosted {
            // Freshly rehosted SwiftUI content has no trustworthy fitting
            // size yet; take the known card size directly.
            var size = NowPlayingPopupController.shared.popoverContentSize
            if let maxHeight = availableHeight(under: button) {
                size.height = min(size.height, maxHeight)
            }
            nowPlayingPopover.contentSize = size
        } else {
            sizeNowPlayingContent(under: button)
        }
        nowPlayingPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        guard let window = nowPlayingPopover.contentViewController?.view.window else { return }
        // Keep the popup alive next to fullscreen apps and on any Space.
        window.collectionBehavior.insert([.fullScreenAuxiliary, .canJoinAllSpaces])
        window.makeKey()
        NSApp.activate(ignoringOtherApps: false)
        clampNowPlayingWindow(window, under: button)
        if let targetMidX = correctedPopoverMidX(for: button) {
            beginPopoverDriftCorrection(window: window, targetMidX: targetMidX,
                                        owner: nowPlayingPopover)
        }
        animateNowPlayingPopupOpen(window)
    }

    /// Fits the fixed card into the space between the menu bar item and the
    /// bottom of the screen; the width never changes.
    private func sizeNowPlayingContent(under button: NSStatusBarButton) {
        guard let view = nowPlayingPopover.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        var size = view.fittingSize
        if size.width < 1 || size.height < 1 {
            size = NowPlayingPopupController.shared.popoverContentSize
        }
        if let maxHeight = availableHeight(under: button) {
            size.height = min(size.height, maxHeight)
        }
        nowPlayingPopover.contentSize = size
    }

    /// The free vertical space under the status item, minus a 6pt margin.
    private func availableHeight(under button: NSStatusBarButton) -> CGFloat? {
        guard let buttonWindow = button.window else { return nil }
        let onScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let anchor = NSPoint(x: onScreen.midX, y: onScreen.minY)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return nil }
        return max(140, onScreen.minY - visible.minY - 6)
    }

    /// Keeps a freshly shown popup inside the screen: never taller than the
    /// space under the item, never closer than 6pt to the screen edges.
    private func clampNowPlayingWindow(_ window: NSWindow, under button: NSStatusBarButton) {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        let maxHeight = max(140, visible.maxY - visible.minY)
        if frame.height > maxHeight {
            frame.size.height = maxHeight
            frame.origin.y = visible.minY + 6
        }
        if frame.minX < visible.minX + 6 {
            frame.origin.x = visible.minX + 6
        }
        if frame.maxX > visible.maxX - 6 {
            frame.origin.x = visible.maxX - 6 - frame.width
        }
        if frame != window.frame {
            window.setFrame(frame, display: true)
        }
    }

    private func animateNowPlayingPopupOpen(_ window: NSWindow) {
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = popoverOpenDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        } completionHandler: { [weak self, weak window] in
            guard let self,
                  self.nowPlayingPopover.isShown,
                  window === self.nowPlayingPopover.contentViewController?.view.window else { return }
            window?.alphaValue = 1
        }
    }

    private func closeNowPlayingPopup() {
        guard nowPlayingPopover.isShown else { return }
        nowPlayingPopover.performClose(nil)
    }

    /// The popover hotkey behaves exactly like clicking the menu bar item:
    /// anchor to the status item button, honoring the same mutual exclusion.
    private func toggleNowPlayingPopupFromHotkey() {
        guard let button = NowPlayingService.shared.statusItemButton else { return }
        showNowPlayingPopup(anchoredTo: button)
    }

    /// The detached hotkey toggles the floating window; the anchored
    /// popover is the same surface, so it makes way first.
    private func toggleNowPlayingDetachedFromHotkey() {
        let popupController = NowPlayingPopupController.shared
        if popupController.isDetachedVisible {
            popupController.closeDetached()
            return
        }
        if nowPlayingPopover.isShown {
            closeNowPlayingPopup()
        }
        popupController.showDetached()
    }

    /// The popup content may have been dropped while hidden (memory setting);
    /// rehost the real view before presenting. Returns whether the content
    /// was just rehosted, so the caller can skip fitting-size measurement.
    @discardableResult
    private func restoreNowPlayingPopupContent() -> Bool {
        guard nowPlayingPopupUnloaded else { return false }
        if let host = nowPlayingPopover.contentViewController as? NSHostingController<AnyView> {
            host.rootView = AnyView(NowPlayingPopupView())
        }
        nowPlayingPopupUnloaded = false
        return true
    }

    /// Memory parity: optionally unload the popup content while the popover
    /// is hidden, hosting an EmptyView until the next open.
    private func unloadNowPlayingPopupIfPreferred() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.nowPlayingUnloadWhenHidden),
              let host = nowPlayingPopover.contentViewController as? NSHostingController<AnyView> else { return }
        host.rootView = AnyView(EmptyView())
        nowPlayingPopupUnloaded = true
    }

    // The SwiftUI panel reports which monitor sections are actually visible; the
    // popover callback only handles update freshness.
    func popoverWillShow(_ notification: Notification) {
        guard (notification.object as? NSPopover) !== nowPlayingPopover else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .menuPanelWillShow, object: nil)
        }
        SystemMonitor.shared.suppressGPUReadsForTransientUI()
        if !popoverIsSwitchingAnchor {
            UpdateService.shared.checkIfStale()
        }
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        // The now-playing popup is .transient and always yields to outside
        // clicks; only the main panel negotiates staying open.
        if popover === nowPlayingPopover { return true }
        return popoverIsClosing || !PanelInteractionState.shared.preventsPopoverDismissal
    }

    // MARK: - Popover Detachment

    /// Whether the menu panel is inside the popover (as opposed to a detached window).
    /// Checks `detachedWindowController != nil` instead of `window.isVisible` because
    /// the window is created before it's shown, so isVisible would be false during
    /// view construction in the detached window, incorrectly showing the button.
    var isPanelInPopover: Bool {
        detachedWindowController == nil
    }

    private var detachedWindowController: NSWindowController?
    // Token for the detached panel's willClose observer, removed on close.
    private var detachedCloseObserver: NSObjectProtocol?
    /// Occlusion observer token for the detached dashboard window,
    /// plus the last known visibility so the refcount-style panelClients signal
    /// is applied as a boolean edge (appear only on false→true), never as
    /// increment/decrement — willClose and didChangeOcclusion can both fire.
    private var detachedOcclusionObserver: NSObjectProtocol?
    private var detachedWindowVisible = false

    @objc func detachPanel() {
        // If already detached, re-attach: close the window and reopen the popover
        // The willCloseNotification observer handles cleanup (detachedWindowController=nil, monitor stop)
        if let window = detachedWindowController?.window {
            detachedWindowController = nil
            window.close()
            if let hostingController = popover.contentViewController as? NSHostingController<MenuPanelView> {
                hostingController.rootView = MenuPanelView(isDetachedWindow: false)
            }
            if !popover.isShown {
                MenuPanelFocus.shared.showNormalPanel()
                popoverClosedAt = .distantPast
                togglePopover()
            }
            return
        }

        if detachedWindowController == nil {
            let panelView = MenuPanelView(isDetachedWindow: true)
            let hostingController = NSHostingController(rootView: panelView)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 332, height: 600),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.contentMinSize = NSSize(width: 332, height: 220)
            window.contentMaxSize = NSSize(width: 332, height: Double.greatestFiniteMagnitude)
            window.title = "RyzenStatus"
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
            window.level = .floating
            window.contentViewController = hostingController
            window.isReleasedWhenClosed = false
            detachedWindowController = NSWindowController(window: window)

            // Keep the observer token and remove it inside the close
            // handler; each detach cycle used to register a fresh block forever.
            detachedCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
              MainActor.assumeIsolated {
                if let token = self?.detachedCloseObserver {
                    NotificationCenter.default.removeObserver(token)
                    self?.detachedCloseObserver = nil
                }
                // Remove the occlusion observer before signalling the
                // disappear, so a final occlusion callback cannot re-appear the
                // panel client after the window is gone.
                if let occToken = self?.detachedOcclusionObserver {
                    NotificationCenter.default.removeObserver(occToken)
                    self?.detachedOcclusionObserver = nil
                }
                self?.detachedWindowVisible = false
                self?.detachedWindowController = nil
                // Full monitor surface: a panel client, so the popover
                // lifecycle cannot wipe these needs while the window is open.
                SystemMonitor.shared.panelDidDisappear()
              }
            }

            // Stand down when the detached dashboard is not actually
            // visible. The window is .floating + .canJoinAllSpaces, so it stays
            // "open" while fully covered by another window or sitting on another
            // Space — and panelDidDisappear() was only wired to
            // willCloseNotification, so it kept sampling and re-rendering at
            // full foreground cadence. AppKit computes occlusion for us.
            //
            // panelDidAppear/Disappear are refcount-style clients, so this edge
            // is applied through a boolean: appear once on false→true, disappear
            // once on true→false. A missing or non-window object is ignored.
            detachedOcclusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] note in
              // Registered with `queue: .main`, so this body always runs on the
              // main thread; assumeIsolated states that to the compiler.
              MainActor.assumeIsolated {
                guard let win = note.object as? NSWindow else { return }
                let visible = win.occlusionState.contains(.visible)
                guard let self, visible != self.detachedWindowVisible else { return }
                self.detachedWindowVisible = visible
                if visible {
                    SystemMonitor.shared.panelDidAppear()
                } else {
                    SystemMonitor.shared.panelDidDisappear()
                }
              }
            }
        }

        closePopoverNow(animated: true, completion: { [weak self] in
            guard let self else { return }
            self.detachedWindowController?.showWindow(nil)
            if let window = self.detachedWindowController?.window, !window.isVisible {
                window.center()
            }
            self.detachedWindowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // Ensure monitor is active (panel client, immune to popover wipes)
            SystemMonitor.shared.panelDidAppear()
        })
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        if popover === nowPlayingPopover { return false }
        return true
    }

    func popoverDidClose(_ notification: Notification) {
        let closingPopover = notification.object as? NSPopover
        if closingPopover === nowPlayingPopover {
            // Owner-aware: the outgoing popover's deferred close must not
            // tear down the correction the incoming popover just installed.
            if popoverDriftOwner === closingPopover {
                endPopoverDriftCorrection()
            }
            unloadNowPlayingPopupIfPreferred()
            return
        }
        if !popoverIsSwitchingAnchor {
            SystemMonitor.shared.setMenuPanelNeeds(.none)
        }
        if !popoverIsSwitchingAnchor {
            MenuPanelFocus.shared.clearMetricFocus()
            // Non-forced stop: the shortened lease lets nettop wind down on its
            // own within a few seconds while keeping the delta baseline, so a
            // quick reopen shows per-app rows immediately instead of re-priming.
            ProcessUsageService.shared.stopNetworkMonitoring()
            ProcessUsageService.shared.clearCachedRows()
            ResponsibleProcess.clearIconCache()
        }
        removePopoverDismissMonitor()
        if popoverDriftOwner === closingPopover {
            endPopoverDriftCorrection()
        }
        PanelInteractionState.shared.viewKeepsPopoverOpen = false
        PanelInteractionState.shared.isPresentingPopoverModal = false
        if !popoverIsSwitchingAnchor {
            // Nothing measures itself against a screen with the panel closed.
            PanelInteractionState.shared.anchorScreen = nil
        }
        popoverClosedAt = popoverIsSwitchingAnchor ? .distantPast : Date()
        popoverIsClosing = false
        if !popoverIsSwitchingAnchor {
            returnActivation(to: endPanelActivationTracking(), after: popoverCloseReason)
        }
        popoverCloseReason = nil
        runPopoverCloseCompletions()
    }

    /// Remembers the app in front as the panel opens with activation, and
    /// follows it while the panel is shown. The observers live only as long
    /// as the panel.
    private func beginPanelActivationTracking() {
        endPanelActivationTracking()
        let ownPID = NSRunningApplication.current.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication
        // Opened while RyzenStatus was already in front (from Settings, say):
        // there is nothing to hand back when the panel closes.
        panelActivationSource = front?.processIdentifier == ownPID ? nil : front
        let center = NSWorkspace.shared.notificationCenter
        panelActivationObservers = [
            center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                               object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updatePanelActivationSource(.activeSpaceChanged) }
            },
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                               object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.updatePanelActivationSource(.appActivated(app)) }
            },
        ]
    }

    private func updatePanelActivationSource(_ change: PanelActivationChange<NSRunningApplication>) {
        let ownPID = NSRunningApplication.current.processIdentifier
        panelActivationSource = StatusItemAnchorSupport.panelActivationSource(
            after: change, current: panelActivationSource,
            isOwnApp: { $0.processIdentifier == ownPID })
    }

    /// Stops following activation and returns the app remembered last.
    @discardableResult
    private func endPanelActivationTracking() -> NSRunningApplication? {
        let center = NSWorkspace.shared.notificationCenter
        panelActivationObservers.forEach { center.removeObserver($0) }
        panelActivationObservers.removeAll()
        let source = panelActivationSource
        panelActivationSource = nil
        return source
    }

    /// Closing the panel leaves RyzenStatus active, and macOS keeps reporting
    /// it as the frontmost app until something else is focused, which
    /// misleads window managers and anything that follows the active app.
    private func returnActivation(to source: NSRunningApplication?, after closeReason: PanelCloseReason?) {
        guard let source, closeReason?.dismissesWithoutTakeover == true else { return }
        // One turn later, so the close animation has finished and anything the
        // dismissal itself focused has become key.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.popover.isShown, !source.isTerminated,
                  StatusItemAnchorSupport.shouldReturnActivation(
                      to: source.processIdentifier,
                      ownPID: NSRunningApplication.current.processIdentifier,
                      frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                      ownWindowIsKey: NSApp.keyWindow != nil || NSApp.modalWindow != nil,
                      closeReason: closeReason),
                  !self.handbackWouldSwitchDesktop(to: source.processIdentifier)
            else { return }
            ActivationHandoff.yield(to: source)
            if !source.activate(from: NSRunningApplication.current, options: []) {
                source.activate(options: [])
            }
        }
    }

    /// Reads the Spaces of the app's normal windows from the window server.
    /// Windows the app has ordered out (minimized, or kept after a close) do
    /// not make activation travel, so they are left out.
    private func handbackWouldSwitchDesktop(to pid: pid_t) -> Bool {
        guard SpaceWindowBridge.canResolveSpaces,
              let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let windowSpaces: [[UInt64]] = info.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            else { return nil }
            let windowID = CGWindowID(number)
            guard SpaceWindowBridge.isWindowOrderedIn(windowID) != false else { return nil }
            return SpaceWindowBridge.spaces(of: windowID)
        }
        return StatusItemAnchorSupport.handbackWouldSwitchDesktop(
            windowSpaces: windowSpaces,
            visibleSpaces: SpaceWindowBridge.topology()?.visibleSpaces)
    }

    // MARK: - Context menu (right click)

    private func showContextMenu(for item: NSStatusItem) {
        // The panel uses applicationDefined dismissal, so a right-click while it's
        // open won't close it on its own — and the menu would try to open behind it.
        // Close it first so the context menu always appears.
        if popover.isShown {
            closePopover { [weak self] in self?.presentContextMenu(for: item) }
            return
        }

        presentContextMenu(for: item)
    }

    private func presentContextMenu(for item: NSStatusItem) {
        let manager = KeepAwakeManager.shared
        let strings = L10n.shared.s
        let menu = NSMenu()

        if AppFeature.keepAwake.isAvailable {
            let toggleItem = NSMenuItem(title: manager.isActive ? strings.menuDisableAwake : strings.menuEnableAwake,
                                        action: #selector(menuToggleAwake),
                                        keyEquivalent: "")
            toggleItem.target = self
            menu.addItem(toggleItem)
        }

        if AppFeature.keepAwake.isAvailable, !manager.isActive {
            let durationsItem = NSMenuItem(title: strings.menuActivateFor, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            let options: [(String, Int)] = [(strings.minutes15, 15), (strings.minutes30, 30),
                                            (strings.hour1, 60), (strings.hours2, 120),
                                            (strings.hours4, 240), (strings.hours8, 480),
                                            (strings.indefinitely, 0)]
            for (label, minutes) in options {
                let item = NSMenuItem(title: label, action: #selector(menuActivateDuration(_:)), keyEquivalent: "")
                item.target = self
                item.tag = minutes
                submenu.addItem(item)
            }
            durationsItem.submenu = submenu
            menu.addItem(durationsItem)
        }

        if AppFeature.cleaningMode.isAvailable {
            let cleaningItem = NSMenuItem(title: strings.cleaningMenuItem,
                                          action: #selector(menuCleaningMode), keyEquivalent: "")
            cleaningItem.target = self
            menu.addItem(cleaningItem)
        }

        if menu.items.isEmpty == false {
            menu.addItem(.separator())
        }

        let settingsItem = NSMenuItem(title: strings.menuSettings, action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: strings.menuAbout, action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        if AppFeature.uninstaller.isAvailable {
            let uninstallItem = NSMenuItem(title: strings.uninstallerMenuItem,
                                           action: #selector(menuOpenUninstaller), keyEquivalent: "")
            uninstallItem.target = self
            menu.addItem(uninstallItem)
        }

        if AppFeature.shelf.isAvailable, UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled) {
            let shelfItem = NSMenuItem(title: strings.shelfMenuItem,
                                       action: #selector(menuOpenShelf), keyEquivalent: "")
            shelfItem.target = self
            menu.addItem(shelfItem)
        }

        let updatesItem = NSMenuItem(title: strings.menuCheckUpdates, action: #selector(menuCheckUpdates), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: strings.menuQuit, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func menuToggleAwake() {
        KeepAwakeManager.shared.toggle()
    }

    @objc private func menuCleaningMode() {
        CleaningModeManager.shared.activate()
    }

    @objc private func menuActivateDuration(_ sender: NSMenuItem) {
        KeepAwakeManager.shared.activate(minutes: sender.tag)
    }

    @objc private func menuOpenSettings() {
        openSettingsWindow()
    }

    @MainActor
    @objc private func menuOpenUninstaller() {
        SettingsRouter.shared.page = .uninstaller
        openSettingsWindow()
    }

    @objc private func menuOpenShelf() {
        ShelfService.shared.expandDocked()
    }

    @objc private func menuCheckUpdates() {
        UpdateService.shared.check(manual: true)
        openSettingsWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: L10n.shared.s.aboutDescription,
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    // MARK: - Application menu

    /// Builds and installs the standard application menu (App / Edit / Window).
    ///
    /// Because the app runs as an accessory, AppKit never gives it the default main
    /// menu a regular app gets, so `NSApp.mainMenu` stays nil and the standard key
    /// equivalents (which live on menu items) never resolve. That is why nothing
    /// happens for Cmd+H/M/W/Q or Cmd+C/V/X/A inside the Settings window. A minimal
    /// standard menu restores them. The menu bar only appears while one of the
    /// app's own windows is focused; otherwise the app is as invisible as before.
    /// Most items use the responder chain (nil target) so they act on the key
    /// window or the focused text field; About and Settings route to our handlers.
    func installMainMenu() {
        let strings = L10n.shared.s
        let mainMenu = NSMenu()

        // Application menu (the bold, app-named first menu).
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let about = NSMenuItem(title: strings.menuAbout, action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())

        let settings = NSMenuItem(title: strings.menuSettings, action: #selector(menuOpenSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())

        appMenu.addItem(NSMenuItem(title: strings.menuHide,
                                   action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: strings.menuHideOthers,
                                    action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: strings.menuShowAll,
                                   action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: strings.menuQuit,
                                   action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Edit menu, so text fields in Settings respond to the editing shortcuts.
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: strings.menuEdit)
        editMenuItem.submenu = editMenu

        editMenu.addItem(NSMenuItem(title: strings.menuUndo, action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: strings.menuRedo, action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: strings.menuCut, action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: strings.menuCopy, action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: strings.menuPaste, action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: strings.menuSelectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        // Drivers and other running copies of RyzenStatus may translate side
        // buttons into menu commands before this process ever receives a raw
        // mouse event, so Settings answers the Back and Forward commands too.
        let navigationMenuItem = NSMenuItem()
        navigationMenuItem.submenu = SettingsWindow.navigationMenu(language: L10n.shared.language)
        mainMenu.addItem(navigationMenuItem)

        // Window menu (Minimize / Zoom / Close). Settings is .miniaturizable so
        // Cmd+M actually minimizes; AppKit manages enabling once windowsMenu is set.
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: strings.menuWindow)
        windowMenuItem.submenu = windowMenu

        windowMenu.addItem(NSMenuItem(title: strings.menuMinimize,
                                      action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: strings.menuZoom,
                                      action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: strings.menuClose,
                                      action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Windows

    func openSettingsWindow() {
        // Intentionally does NOT close the panel: the panel uses applicationDefined
        // dismissal, so it stays open beside Settings for a live preview.
        // Capture the destination before activation changes the key window.
        let targetScreen = (popover.isShown
            ? popover.contentViewController?.view.window?.screen
            : nil) ?? NSScreen.withMouse
        let createdWindow = settingsWindow == nil
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView())
            let window = SettingsWindow(contentViewController: host)
            window.isMouseButtonCaptureActive = { MouseButtonShortcutService.isCaptureActive }
            // .miniaturizable so the Window menu's Minimize (Cmd+M) actually works.
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            host.view.widthAnchor.constraint(greaterThanOrEqualToConstant: SettingsWindowSupport.minContentWidth).isActive = true
            host.view.heightAnchor.constraint(greaterThanOrEqualToConstant: SettingsWindowSupport.minContentHeight).isActive = true
            let minFrame = window.frameRect(forContentRect: NSRect(
                x: 0, y: 0,
                width: SettingsWindowSupport.minContentWidth,
                height: SettingsWindowSupport.minContentHeight
            )).size
            window.minSize = minFrame
            window.contentMinSize = NSSize(width: SettingsWindowSupport.minContentWidth,
                                           height: SettingsWindowSupport.minContentHeight)
            let visible = targetScreen?.visibleFrame ?? NSScreen.pointerVisibleFrame
            let size = SettingsWindowSupport.initialContentSize(
                savedWidth: UserDefaults.standard.double(forKey: DefaultsKey.settingsWindowWidth),
                savedHeight: UserDefaults.standard.double(forKey: DefaultsKey.settingsWindowHeight),
                availableHeight: Double(visible.height - 40))
            window.setContentSize(NSSize(width: size.width, height: size.height))
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.hidesOnDeactivate = false
            window.canHide = false
            window.delegate = self
            settingsWindow = window
        }
        settingsWindow?.title = L10n.shared.s.settingsTitle
        if let window = settingsWindow {
            positionSettingsWindow(window, force: createdWindow)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        // Reopening on the very page that was showing at close never runs
        // that page's own onAppear, since its view was never removed from
        // the hierarchy; the window itself is the only reliable signal here.
        SecureInputMonitor.shared.setSettingsWindowOpen(true)
        SettingsWindowVisibility.shared.set(true)
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.settingsWindow else { return }
            self.positionSettingsWindow(window, force: false)
        }
    }

    /// Feedback opens a prefilled GitHub issue; this window only drafts it.
    func openFeedbackWindow(kind: FeedbackKind = .bug) {
        closePopover()
        let host = NSHostingController(rootView: FeedbackView(initialKind: kind) { [weak self] in
            self?.feedbackWindow?.close()
        })
        if let window = feedbackWindow {
            window.contentViewController = host
        } else {
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable]
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.delegate = self
            window.center()
            feedbackWindow = window
        }
        feedbackWindow?.title = FeatureStrings.feedback(L10n.shared.language).windowTitle
        NSApp.activate(ignoringOtherApps: true)
        feedbackWindow?.makeKeyAndOrderFront(nil)
    }

    private func positionSettingsWindow(_ window: NSWindow, force: Bool) {
        window.contentView?.layoutSubtreeIfNeeded()
        let popoverWindow = popover.isShown ? popover.contentViewController?.view.window : nil
        let visible = (popoverWindow?.screen ?? window.screen)?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let margin: CGFloat = 40
        let availableWidth = max(1, visible.width - margin)
        let availableHeight = max(1, visible.height - margin)
        let minFrame = window.frameRect(forContentRect: NSRect(
            x: 0, y: 0,
            width: SettingsWindowSupport.minContentWidth,
            height: SettingsWindowSupport.minContentHeight
        )).size
        let width = min(max(window.frame.width, minFrame.width), availableWidth)
        let height = min(max(window.frame.height, minFrame.height), availableHeight)
        var frame = force
            ? NSRect(x: visible.midX - width / 2,
                     y: visible.midY - height / 2,
                     width: width,
                     height: height)
            : NSRect(x: window.frame.minX,
                     y: window.frame.minY,
                     width: width,
                     height: height)

        if let popoverFrame = popoverWindow?.frame,
           visible.intersects(popoverFrame),
           frame.intersects(popoverFrame) {
            let placement = SettingsWindowSupport.panelPlacement(
                preferredFrame: frame, panelFrame: popoverFrame, visibleFrame: visible)
            frame = placement.frame
            if placement.closesPanel {
                closePopover()
            }
        } else if force {
            frame.origin.x = min(max(frame.origin.x, visible.minX + margin / 2), visible.maxX - width - margin / 2)
            frame.origin.y = min(max(frame.origin.y, visible.minY + margin / 2), visible.maxY - height - margin / 2)
        }
        window.setFrame(frame.integral, display: false)
    }

    /// Only the first launch of a newer version gets this bounded check.
    /// Replacing the app can leave macOS without a place for its item, and the
    /// person then has no icon to click. Normal launches and activations must
    /// not disturb an arranged menu bar.
    private func recoverStatusItemAfterUpdate(previousVersion: String?) {
        guard let previousVersion, !AppInfo.isDeveloperBuild,
              let previous = UpdateServiceSupport.SemanticVersion(raw: previousVersion),
              let current = UpdateServiceSupport.SemanticVersion(raw: AppInfo.version), current > previous,
              let item = statusController?.statusItem else { return }
        let screens = NSScreen.screens.map(\.frame)
        guard !screens.isEmpty else { return }
        verifyPostUpdateStatusItem(item, screenFrames: screens,
                                   deadline: Date().addingTimeInterval(30))
    }

    private func verifyPostUpdateStatusItem(_ item: NSStatusItem,
                                            screenFrames: [CGRect],
                                            deadline: Date,
                                            attemptsLeft: Int = 12,
                                            recreated: Bool = false) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reshowVerifyInterval) { [weak self, weak item] in
            // Reopening or explicitly recovering the app replaces this item,
            // cancelling these callbacks. A sleep, display change or hidden bar
            // is not evidence of failed placement, so those stop the check too.
            guard let self, let item, self.statusController?.statusItem === item,
                  !self.isTerminating, !self.isReshowingStatusItem,
                  !self.popover.isShown, item.menu == nil, item.isVisible,
                  self.statusController?.mainItemHiddenByChoice != true,
                  NSEvent.pressedMouseButtons == 0,
                  Date() < deadline,
                  !UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHideIconWithMetrics),
                  NSScreen.screens.map(\.frame) == screenFrames,
                  NSMenu.menuBarVisible(),
                  NSApp.currentSystemPresentationOptions.intersection(
                    [.autoHideMenuBar, .hideMenuBar, .fullScreen]).isEmpty,
                  let session = CGSessionCopyCurrentDictionary() as? [String: Any],
                  SessionActivitySupport.isOnConsole(session),
                  !KeepAwakeAutomationSupport.isScreenLocked(sessionDictionary: session),
                  Self.runningMenuBarManagerName() == nil else { return }
            if self.iconIsOnScreen() {
                self.logStatusItemPlacement("post-update appeared")
                return
            }
            guard attemptsLeft <= 1 else {
                self.verifyPostUpdateStatusItem(item, screenFrames: screenFrames, deadline: deadline,
                                                attemptsLeft: attemptsLeft - 1, recreated: recreated)
                return
            }
            // Preserve the autosave identity and position. The more disruptive
            // reset remains exclusive to the person's explicit recovery action.
            guard !recreated else {
                self.logStatusItemPlacement("post-update still hidden")
                return
            }
            self.logStatusItemPlacement("post-update recreating")
            self.statusController?.recreateStatusItem()
            if let replacement = self.statusController?.statusItem {
                self.verifyPostUpdateStatusItem(replacement, screenFrames: screenFrames,
                                                deadline: deadline, recreated: true)
            }
        }
    }

    /// Rebuilds the menu bar item so the icon reappears when the OS has dropped it
    /// from a crowded or notched menu bar. Backs the "Show menu bar icon" button.
    /// The rebuild can silently lose to a full bar or to a menu bar manager app
    /// stuffing the fresh item into its hidden section, so
    /// after the frame settles this checks the icon really made it on screen
    /// and, if not, says so instead of looking like the button did nothing.
    func reshowStatusItem() {
        // The button is an explicit "I want the icon back": neither hiding
        // option (with metrics, or Dynamic Island standing in) may
        // immediately re-hide what the user just asked to see (and then trip
        // the "still hidden" alert).
        UserDefaults.standard.set(false, forKey: DefaultsKey.menuBarHideIconWithMetrics)
        UserDefaults.standard.set(false, forKey: DefaultsKey.notchHidesMenuBarIcon)
        guard !isReshowingStatusItem else { return }
        isReshowingStatusItem = true
        // First keep the spot the person arranged; only a rebuild that still
        // does not show gives it up below.
        statusController?.recreateStatusItem()
        logStatusItemPlacement("rebuilt")
        verifyIconReappeared(attemptsLeft: Self.reshowVerifyAttempts)
    }

    /// macOS places a rebuilt status item on its own schedule, and a busy bar
    /// can take longer than one look to settle. Judging it once meant a slow
    /// placement read as a failure and the person was told the bar was full
    /// when it was not (issue #369). A newborn item also reports a zero-height
    /// frame for a few seconds; that settling grace is separate from the
    /// "still hidden" countdown so recovery does not burn the arranged spot
    /// while macOS is still placing the window.
    private var isReshowingStatusItem = false
    private static let reshowVerifyAttempts = 6
    nonisolated private static let reshowSettlingGraceAttempts = 8
    private static let reshowVerifyInterval: TimeInterval = 0.8

    private func iconIsSettling() -> Bool {
        StatusItemAnchorSupport.isSettlingStatusFrame(
            statusController?.statusItem.button?.window?.frame)
    }

    private func verifyIconReappeared(attemptsLeft: Int,
                                      settlingGraceLeft: Int = AppDelegate.reshowSettlingGraceAttempts,
                                      placementWasReset: Bool = false) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reshowVerifyInterval) { [weak self] in
            guard let self else { return }
            // A later choice to hide the icon cancels the explicit recovery.
            guard !UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHideIconWithMetrics),
                  !StatusItemController.islandHidesStatusIcon(
                    in: .standard,
                    hiddenInFullscreen: self.statusController?.islandHiddenInFullscreen == true)
            else {
                self.isReshowingStatusItem = false
                return
            }
            if self.iconIsOnScreen() {
                self.isReshowingStatusItem = false
                self.logStatusItemPlacement("appeared")
                return
            }
            if StatusItemPlacementSupport.shouldKeepWaitingForSettlement(
                isOnScreen: false,
                isSettling: self.iconIsSettling(),
                settlingGraceLeft: settlingGraceLeft) {
                self.logStatusItemPlacement("settling")
                self.verifyIconReappeared(attemptsLeft: attemptsLeft,
                                          settlingGraceLeft: settlingGraceLeft - 1,
                                          placementWasReset: placementWasReset)
                return
            }
            guard attemptsLeft <= 1 else {
                self.verifyIconReappeared(attemptsLeft: attemptsLeft - 1,
                                          settlingGraceLeft: settlingGraceLeft,
                                          placementWasReset: placementWasReset)
                return
            }
            // With the app switched off under System Settings > Menu Bar >
            // "Allow in the Menu Bar" (macOS 26), macOS never places the item
            // whatever its identity, so a reset would only burn the arranged
            // spot. Name the switch instead of blaming a full menu bar.
            if MenuBarAllowanceSupport.currentAllowance() == .disallowed {
                self.isReshowingStatusItem = false
                self.logStatusItemPlacement("disallowed by system")
                let s = L10n.shared.s
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = s.menuBarIconStillHiddenTitle
                alert.informativeText = s.menuBarIconDisallowedBody
                alert.runModal()
                return
            }
            // Keeping the arranged spot did not bring the icon back, so the
            // saved position is itself part of what macOS will not show. Start
            // the item over under a new identity and look again before telling
            // anyone there is nothing left to try.
            guard placementWasReset else {
                self.logStatusItemPlacement("resetting placement")
                self.statusController?.recreateStatusItem(resetPlacement: true)
                self.verifyIconReappeared(attemptsLeft: Self.reshowVerifyAttempts,
                                          settlingGraceLeft: Self.reshowSettlingGraceAttempts,
                                          placementWasReset: true)
                return
            }
            self.isReshowingStatusItem = false
            self.logStatusItemPlacement("still hidden")
            let s = L10n.shared.s
            var body = s.menuBarIconStillHiddenBody
            if let manager = Self.runningMenuBarManagerName() {
                body += "\n\n" + String(format: s.menuBarIconManagerHintFormat, manager, manager)
            }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = s.menuBarIconStillHiddenTitle
            alert.informativeText = body
            alert.runModal()
        }
    }

    private func logStatusItemPlacement(_ stage: String) {
        let window = statusController?.statusItem.button?.window
        let frame = window?.frame ?? .zero
        let placement = "\(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.width))x\(Int(frame.height))"
        let screens = NSScreen.screens.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" }
            .joined(separator: ",")
        let visible = statusController?.statusItem.isVisible ?? false
        let manager = Self.runningMenuBarManagerName() ?? "none"
        os_log("reshow %{public}s window=%{public}s frame=%{public}s visible=%{public}s screens=%{public}s organizer=%{public}s",
               type: .default, stage, window != nil ? "yes" : "no", placement, visible ? "yes" : "no", screens, manager)
    }

    /// Known menu bar organizers, by bundle id; any of them can be holding
    /// the icon in its hidden section, which explains it never reappearing
    /// on this machine. The hint names whichever one is running by its own
    /// localized app name.
    private static let menuBarManagerBundlePrefixes = [
        "com.jordanbaird.Ice",
        "com.surteesstudios.Bartender",
        "com.dwarvesv.minimalbar",
        "com.mortenjust.Dozer",
    ]

    private static func runningMenuBarManagerName() -> String? {
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier else { continue }
            if menuBarManagerBundlePrefixes.contains(where: { bundleID.hasPrefix($0) }) {
                return app.localizedName
            }
        }
        return nil
    }

    /// Quits and reopens the app. Full Disk Access only applies to a fresh
    /// process, so this is how the uninstaller picks up a just-granted grant.
    func relaunchApp() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.3; /usr/bin/open \"$1\"", "ryzenstatus-relaunch", path]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            // If spawn failed, do not terminate to prevent leaving the user with a dead app.
        }
    }

    func showOnboarding(mode: OnboardingMode = .full) {
        closePopover()
        if let window = onboardingWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: OnboardingView(mode: mode) { [weak self] in
            self?.markOnboardingComplete()
            Notifier.requestPermission()
            self?.onboardingWindow?.close()
        })
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = mode.title(L10n.shared.s)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerOnboardingWindow(window)
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.onboardingWindow else { return }
            self.centerOnboardingWindow(window)
        }
    }

    /// On launch after an update, keep the short support prompt visible once per
    /// version. The changelog itself is already shown before download.
    private func presentUpdateIntros() {
        if showWhatsNewIfNeeded() { return }
        if showUpdateHighlightsIfNeeded() { return }
        if showSupportUpdateIntroIfNeeded() { return }
        if showUpdateShowcaseIntroIfNeeded() { return }
        showDockPreviewIntroIfNeeded()
    }

    private func showUpdateHighlightsIfNeeded() -> Bool {
        guard UpdateHighlightsInfo.shouldShow(
            appVersion: AppInfo.version,
            lastSeenVersion: UserDefaults.standard.string(forKey: DefaultsKey.updateHighlightsSeenVersion)
        ) else { return false }
        // If every featured item was uninstalled in the hub there is nothing
        // to tour; mark it seen and stay quiet instead of showing an empty
        // window.
        guard UpdateHighlightsView.hasContent else {
            markUpdateHighlightsSeen()
            return false
        }
        showUpdateHighlights()
        return true
    }

    private func showUpdateHighlights() {
        closePopover()
        if let window = updateHighlightsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: UpdateHighlightsView(
            onFinish: { [weak self] in
                self?.markUpdateHighlightsSeen()
                self?.updateHighlightsWindow?.close()
            }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = L10n.shared.s.highlightsTitle
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerUpdateShowcaseWindow(window)
        updateHighlightsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.updateHighlightsWindow else { return }
            self.centerUpdateShowcaseWindow(window)
        }
    }

    private func markUpdateHighlightsSeen() {
        UserDefaults.standard.set(UpdateHighlightsInfo.releaseVersion,
                                  forKey: DefaultsKey.updateHighlightsSeenVersion)
    }

    /// Records an update the What's New window still has to cover. A second
    /// update before it opens keeps the older starting point.
    private func queueWhatsNewIfNeeded(previousVersion: String?) {
        // The Developer build takes its version from whichever worktree built
        // it, so its versions jump around; it previews with a launch flag.
        guard !AppInfo.isDeveloperBuild else { return }
        let pending = WhatsNewInfo.pendingVersion(
            current: AppInfo.version, previous: previousVersion,
            seen: UserDefaults.standard.string(forKey: DefaultsKey.whatsNewSeenVersion),
            pending: UserDefaults.standard.string(forKey: DefaultsKey.whatsNewPendingVersion))
        UserDefaults.standard.set(pending, forKey: DefaultsKey.whatsNewPendingVersion)
    }

    private func showWhatsNewIfNeeded() -> Bool {
        guard !isTerminating,
              let previous = UserDefaults.standard.string(forKey: DefaultsKey.whatsNewPendingVersion)
        else { return false }
        // Turned off in Settings, or nothing in the update touches what this
        // Mac uses: the update counts as read.
        guard UserDefaults.standard.bool(forKey: DefaultsKey.releaseNotesOnUpdate),
              showWhatsNew(from: previous) else {
            markWhatsNewSeen()
            return false
        }
        return true
    }

    private func markWhatsNewSeen() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.whatsNewPendingVersion)
        UserDefaults.standard.set(AppInfo.version, forKey: DefaultsKey.whatsNewSeenVersion)
        UserDefaults.standard.set(WhatsNewInfo.knownFeaturesValue, forKey: DefaultsKey.whatsNewKnownFeatures)
    }

    /// Opens What's New for the changes since `previous`. Returns false, and
    /// opens nothing, when none of them concern this Mac's features.
    @discardableResult
    func showWhatsNew(from previous: String, includeUnreleased: Bool = false, isReview: Bool = false) -> Bool {
        if let window = whatsNewWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return true
        }
        let defaults = UserDefaults.standard
        let digest = ReleaseDigest.make(from: previous, to: AppInfo.version,
                                        changelog: ReleaseNotes.bundledChangelog() ?? "",
                                        includeUnreleased: includeUnreleased)
        let strings = L10n.shared.s
        let language = L10n.shared.language
        let hub = FeatureStrings.hub(language)
        let sections = WhatsNewSupport.sections(
            digest: digest,
            newFeatures: WhatsNewInfo.newFeatures(
                known: defaults.string(forKey: DefaultsKey.whatsNewKnownFeatures),
                isSupported: { $0.isHardwareSupported }),
            sidebarItems: SettingsDirectory.sidebarItems(strings, language: language,
                                                         isAvailable: { $0.isAvailable }),
            isAvailable: { $0.isAvailable },
            title: { $0.hubTitle(strings, hub: hub) },
            generalTitle: strings.tabGeneral)
        guard sections.hasContentForYou || (isReview && !sections.rows.isEmpty) else { return false }
        closePopover()
        let visible = NSScreen.pointerVisibleFrame
        let rows = sections.rows
        let host = NSHostingController(rootView: WhatsNewDigestView(
            digest: digest, sections: sections, availableSize: visible.size,
            retitle: {
                // Titles follow a language change made while the window is open.
                let strings = L10n.shared.s
                let language = L10n.shared.language
                let hub = FeatureStrings.hub(language)
                return WhatsNewSupport.titles(
                    of: rows,
                    sidebarItems: SettingsDirectory.sidebarItems(strings, language: language,
                                                                 isAvailable: { _ in true }),
                    title: { $0.hubTitle(strings, hub: hub) },
                    generalTitle: strings.tabGeneral)
            },
            onOpenSettings: { [weak self] in self?.openSettingsFromWhatsNew() },
            onFinish: { [weak self] in self?.whatsNewWindow?.close() }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = strings.tabReleaseNotes
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        centerWhatsNewWindow(window)
        whatsNewIsReview = isReview
        whatsNewWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.whatsNewWindow else { return }
            self.centerWhatsNewWindow(window)
        }
        return true
    }

    /// Settings opens beside What's New, so the change just read and the
    /// option it mentions are both on screen.
    private func openSettingsFromWhatsNew() {
        openSettingsWindow()
    }

    private func showUpdateShowcaseIntroIfNeeded() -> Bool {
        guard AppInfo.version == UpdateShowcaseInfo.releaseVersion else {
            UpdateShowcaseInfo.cleanupCache()
            return false
        }
        guard UserDefaults.standard.string(forKey: DefaultsKey.updateShowcaseIntroVersion)
                != UpdateShowcaseInfo.releaseVersion else {
            UpdateShowcaseInfo.cleanupCache()
            return false
        }
        showUpdateShowcaseIntro()
        return true
    }

    private func showUpdateShowcaseIntro() {
        closePopover()
        if let window = updateShowcaseWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: UpdateShowcaseIntroView(
            onClose: { [weak self] in
                self?.markUpdateShowcaseIntroSeen()
                self?.updateShowcaseWindow?.close()
            }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = L10n.shared.s.updateShowcaseTitle
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerUpdateShowcaseWindow(window)
        updateShowcaseWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.updateShowcaseWindow else { return }
            self.centerUpdateShowcaseWindow(window)
        }
    }

    private func showSupportUpdateIntroIfNeeded() -> Bool {
        // Same shape as the showcase gate: the window belongs to one specific
        // release. Any other version never shows it, so an update that is not
        // that release cannot resurrect the ask.
        guard SupportUpdateIntroInfo.shouldShow(
            appVersion: AppInfo.version,
            lastSeenVersion: UserDefaults.standard.string(forKey: DefaultsKey.supportUpdateIntroVersion)
        ) else { return false }
        showSupportUpdateIntro()
        return true
    }

    private func showSupportUpdateIntro() {
        closePopover()
        if let window = supportIntroWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: UpdateSupportIntroView(
            onFinish: { [weak self] in
                self?.supportIntroCanClose = true
                self?.markSupportUpdateIntroSeen()
                self?.supportIntroWindow?.close()
            }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = L10n.shared.s.homebrewOfficialIntroTitle
        window.styleMask = [.titled, .fullSizeContentView]
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        supportIntroCanClose = false
        centerSupportIntroWindow(window)
        supportIntroWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.supportIntroWindow else { return }
            self.centerSupportIntroWindow(window)
        }
    }

    /// True on the release that introduced Dock Preview, or any later one.
    private var isAtLeastDockPreviewRelease: Bool {
        let current = AppInfo.version
        let intro = DockPreviewIntroInfo.releaseVersion
        return current == intro || UpdateService.isNewer(current, than: intro)
    }

    private func showDockPreviewIntroIfNeeded() {
        // Show on the Dock Preview release or any later version, so users who
        // skip versions still get it once, and never re-show it once seen.
        guard isAtLeastDockPreviewRelease else { return }
        guard UserDefaults.standard.string(forKey: DefaultsKey.dockPreviewIntroVersion) == nil else { return }
        showDockPreviewIntro()
    }

    private func showDockPreviewIntro() {
        closePopover()
        if let window = dockPreviewIntroWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: DockPreviewIntroView(
            onDismiss: { [weak self] in
                self?.markDockPreviewIntroSeen()
                self?.dockPreviewIntroWindow?.close()
            },
            onEnable: { [weak self] in
                UserDefaults.standard.set(true, forKey: DefaultsKey.dockPreviewEnabled)
                DockPreviewService.shared.syncWithPreferences()
                self?.markDockPreviewIntroSeen()
                self?.dockPreviewIntroWindow?.close()
            }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = L10n.shared.s.dockPreviewName
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerDockPreviewIntroWindow(window)
        dockPreviewIntroWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.dockPreviewIntroWindow else { return }
            self.centerDockPreviewIntroWindow(window)
        }
    }

    private func centerOnboardingWindow(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        let visible = (window.screen ?? popover.contentViewController?.view.window?.screen)?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let margin: CGFloat = 40
        let availableWidth = max(1, visible.width - margin)
        let availableHeight = max(1, visible.height - margin)
        let width = min(max(window.frame.width, 540), availableWidth)
        let height = min(max(window.frame.height, 600), availableHeight)
        let frame = NSRect(x: visible.midX - width / 2,
                           y: visible.midY - height / 2,
                           width: width,
                           height: height)
        window.setFrame(frame.integral, display: false)
    }

    private func centerDockPreviewIntroWindow(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        let visible = (window.screen ?? popover.contentViewController?.view.window?.screen)?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let margin: CGFloat = 40
        let availableWidth = max(1, visible.width - margin)
        let availableHeight = max(1, visible.height - margin)
        let width = min(max(window.frame.width, 660), availableWidth)
        let height = min(max(window.frame.height, 600), availableHeight)
        let frame = NSRect(x: visible.midX - width / 2,
                           y: visible.midY - height / 2,
                           width: width,
                           height: height)
        window.setFrame(frame.integral, display: false)
    }

    private func centerWhatsNewWindow(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        let visible = (window.screen ?? popover.contentViewController?.view.window?.screen)?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let margin: CGFloat = 40
        let availableWidth = max(1, visible.width - margin)
        let availableHeight = max(1, visible.height - margin)
        let width = min(max(window.frame.width, 640), availableWidth)
        let height = min(max(window.frame.height, 600), availableHeight)
        let frame = NSRect(x: visible.midX - width / 2,
                           y: visible.midY - height / 2,
                           width: width,
                           height: height)
        window.setFrame(frame.integral, display: false)
    }

    private func centerSupportIntroWindow(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        let visible = (window.screen ?? popover.contentViewController?.view.window?.screen)?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let margin: CGFloat = 40
        let availableWidth = max(1, visible.width - margin)
        let availableHeight = max(1, visible.height - margin)
        let width = min(max(window.frame.width, 560), availableWidth)
        let height = min(max(window.frame.height, 430), availableHeight)
        let frame = NSRect(x: visible.midX - width / 2,
                           y: visible.midY - height / 2,
                           width: width,
                           height: height)
        window.setFrame(frame.integral, display: false)
    }

    private func centerUpdateShowcaseWindow(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        let visible = (window.screen ?? popover.contentViewController?.view.window?.screen)?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let margin: CGFloat = 40
        let availableWidth = max(1, visible.width - margin)
        let availableHeight = max(1, visible.height - margin)
        let width = min(CGFloat(680), availableWidth)
        let height = min(CGFloat(600), availableHeight)
        let frame = NSRect(x: visible.midX - width / 2,
                           y: visible.midY - height / 2,
                           width: width,
                           height: height)
        window.setFrame(frame.integral, display: false)
    }

    /// The pre-install update preview, shown before any download from BOTH the
    /// Settings install button and the menu panel's update banner (the blue
    /// button most people use), so the changelog is seen first unless the
    /// person chose to skip it. In the Developer build `downloadAndInstall()`
    /// is a no-op, so confirming is safe.
    func showUpdatePreview() {
        guard case let .available(version) = UpdateService.shared.state else { return }
        if let window = updatePreviewWindow {
            closePopover()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        // The panel stays open, so its banner shows the download's progress.
        guard UserDefaults.standard.bool(forKey: DefaultsKey.showReleaseNotesBeforeUpdate) else {
            if AppInfo.isDeveloperBuild {
                // The Developer build never installs; say so instead of
                // ignoring the click.
                Self.updateLog.log("release notes skipped; the Developer build does not install updates")
            }
            UpdateService.shared.downloadAndInstall()
            return
        }
        closePopover()
        let host = NSHostingController(rootView: UpdatePreviewView(
            version: version,
            notes: UpdateService.shared.availableNotes,
            onUpdate: { [weak self] in
                self?.updatePreviewWindow?.close()
                UpdateService.shared.downloadAndInstall()
            },
            onCancel: { [weak self] in
                self?.updatePreviewWindow?.close()
            }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = L10n.shared.s.tabReleaseNotes
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerWhatsNewWindow(window)
        updatePreviewWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.updatePreviewWindow else { return }
            self.centerWhatsNewWindow(window)
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        if sender === settingsWindow {
            let minFrame = sender.frameRect(forContentRect: NSRect(
                x: 0, y: 0,
                width: SettingsWindowSupport.minContentWidth,
                height: SettingsWindowSupport.minContentHeight
            )).size
            return NSSize(
                width: max(frameSize.width, minFrame.width),
                height: max(frameSize.height, minFrame.height)
            )
        }
        return frameSize
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        saveSettingsWindowSize(window)
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        // Minimized, on another Space or covered, Settings draws for nobody too.
        SettingsWindowVisibility.shared.set(window.isVisible && window.occlusionState.contains(.visible))
    }

    /// Remembers the user-chosen Settings size (as content size, so the
    /// restore is title bar independent).
    private func saveSettingsWindowSize(_ window: NSWindow) {
        guard let size = window.contentView?.frame.size else { return }
        guard SettingsWindowSupport.isValidContentSize(width: Double(size.width),
                                                      height: Double(size.height)) else { return }
        UserDefaults.standard.set(Double(size.width), forKey: DefaultsKey.settingsWindowWidth)
        UserDefaults.standard.set(Double(size.height), forKey: DefaultsKey.settingsWindowHeight)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === supportIntroWindow else { return true }
        return supportIntroCanClose || isTerminating
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            // Covers size changes that end without a live resize (zoom).
            saveSettingsWindowSize(window)
            // Whatever page was showing, its own onDisappear does not always
            // run before the window finishes closing; stop the poll from
            // here too rather than let it run until the app quits. The
            // page's own demand is left alone, so it resumes on its own the
            // moment the window reopens, on this page or any other.
            SecureInputMonitor.shared.setSettingsWindowOpen(false)
            SettingsWindowVisibility.shared.set(false)
            return
        }
        if window === onboardingWindow {
            onboardingWindow = nil
            // Closing the window mid-flow counts as "skip" — but quitting (e.g.
            // the relaunch macOS forces after granting Screen Recording) must NOT,
            // so the flow can resume where it stopped.
            guard !isTerminating else { return }
            markOnboardingComplete()
        }
        if window === dockPreviewIntroWindow {
            dockPreviewIntroWindow = nil
            guard !isTerminating else { return }
            markDockPreviewIntroSeen()
        }
        if window === supportIntroWindow {
            supportIntroWindow = nil
            supportIntroCanClose = false
            guard !isTerminating else { return }
            markSupportUpdateIntroSeen()
        }
        if window === updateShowcaseWindow {
            updateShowcaseWindow = nil
            guard !isTerminating else { return }
            markUpdateShowcaseIntroSeen()
        }
        if window === updateHighlightsWindow {
            updateHighlightsWindow = nil
            guard !isTerminating else { return }
            markUpdateHighlightsSeen()
        }
        if window === whatsNewWindow {
            whatsNewWindow = nil
            let isReview = whatsNewIsReview
            whatsNewIsReview = false
            guard !isTerminating, !isReview else { return }
            markWhatsNewSeen()
        }
        if window === updatePreviewWindow {
            updatePreviewWindow = nil
        }
    }

    /// Marks both the first run and this version's feature tour as seen, so
    /// neither reappears on the next launch.
    private func markOnboardingComplete() {
        UserDefaults.standard.set(true, forKey: DefaultsKey.hasOnboarded)
        UserDefaults.standard.set(OnboardingInfo.currentFeatureSet, forKey: DefaultsKey.featuresOnboardingVersion)
        UserDefaults.standard.set(AppInfo.version, forKey: DefaultsKey.lastUpdateIntroVersion)
        markDockPreviewIntroSeenIfCurrentUpdate()
        markSupportUpdateIntroSeenIfCurrentUpdate()
        markUpdateShowcaseIntroSeenIfCurrentUpdate()
        // A clean install that just saw everything in onboarding should not
        // then get the update tour; only people who updated get it.
        markUpdateHighlightsSeen()
        // Nor treat the features it was just offered as new on the next
        // update, or a restored backup's older version as an update.
        if UserDefaults.standard.string(forKey: DefaultsKey.whatsNewKnownFeatures) == nil {
            UserDefaults.standard.set(WhatsNewInfo.knownFeaturesValue, forKey: DefaultsKey.whatsNewKnownFeatures)
        }
        UserDefaults.standard.set(
            WhatsNewInfo.later(UserDefaults.standard.string(forKey: DefaultsKey.whatsNewSeenVersion), AppInfo.version),
            forKey: DefaultsKey.whatsNewSeenVersion)
    }

    private func markDockPreviewIntroSeenIfCurrentUpdate() {
        // A clean install that just finished onboarding on the Dock Preview
        // release (or later) should not then be shown the intro popup.
        guard isAtLeastDockPreviewRelease else { return }
        markDockPreviewIntroSeen()
    }

    private func markDockPreviewIntroSeen() {
        UserDefaults.standard.set(AppInfo.version, forKey: DefaultsKey.dockPreviewIntroVersion)
    }

    private func markSupportUpdateIntroSeenIfCurrentUpdate() {
        // Mirror markUpdateShowcaseIntroSeenIfCurrentUpdate — without
        // the version guard, completing onboarding on any release pre-seeds the
        // "seen" key and permanently silences a future support intro bump for
        // exactly the audience it was made for.
        guard AppInfo.version == SupportUpdateIntroInfo.releaseVersion else { return }
        markSupportUpdateIntroSeen()
    }

    private func markSupportUpdateIntroSeen() {
        UserDefaults.standard.set(SupportUpdateIntroInfo.releaseVersion,
                                  forKey: DefaultsKey.supportUpdateIntroVersion)
    }

    private func markUpdateShowcaseIntroSeenIfCurrentUpdate() {
        guard AppInfo.version == UpdateShowcaseInfo.releaseVersion else { return }
        markUpdateShowcaseIntroSeen()
    }

    private func markUpdateShowcaseIntroSeen() {
        UserDefaults.standard.set(UpdateShowcaseInfo.releaseVersion,
                                  forKey: DefaultsKey.updateShowcaseIntroVersion)
    }
}
