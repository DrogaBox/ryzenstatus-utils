// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import SwiftUI

/// The Monitor window's sections, in toolbar order.
enum MonitorSection: String, CaseIterable, Identifiable {
    case summary, processes, processor, network, history, diagnostics

    var id: String { rawValue }

    func title(_ strings: MonitorWindowStrings) -> String {
        switch self {
        case .summary: return strings.summary
        case .processes: return strings.processes
        case .processor: return strings.processor
        case .network: return strings.network
        case .history: return strings.history
        case .diagnostics: return strings.diagnostics
        }
    }

    /// The monitor families the section shows. CPU, memory, network and GPU
    /// load stay on in every section, so the live two-minute charts keep a
    /// continuous history while you move between sections; the rest is
    /// sampled only where it is on screen. Never `.system`, which samples
    /// everything.
    var monitorNeeds: SystemMonitorPanelNeeds {
        var needs = SystemMonitorPanelNeeds()
        needs.cpu = true
        needs.memory = true
        needs.network = true
        needs.gpu = true
        switch self {
        case .summary:
            // CPU and GPU power come with the kext read the CPU and GPU
            // families already make, so the battery/SMC power sampler stays
            // off.
            needs.disk = true
            needs.cpuTemperature = true
            needs.gpuTemperature = true
        case .processor, .diagnostics:
            // Diagnostics: the 85 °C rule reads the CPU temperature.
            needs.cpuTemperature = true
        case .history:
            HistoryMetric.stored.addNeeds(to: &needs)
        case .processes, .network:
            break
        }
        return needs
    }

    /// The same feature gates the old Dashboard tabs had.
    var isAvailable: Bool {
        switch self {
        case .summary, .processes, .processor: return true
        case .network: return AppFeature.monitorNetworkDetails.isAvailable || AppFeature.monitorNetwork.isAvailable
        case .history: return AppFeature.monitorAnalytics.isAvailable
        case .diagnostics: return AppFeature.monitorInsights.isAvailable
        }
    }

    /// The section to open from a saved raw value: one that no longer exists
    /// or whose feature is off falls back to the Overview.
    static func restored(_ raw: String?, isAvailable: (MonitorSection) -> Bool = { $0.isAvailable }) -> MonitorSection {
        guard let section = raw.flatMap(MonitorSection.init(rawValue:)), isAvailable(section) else { return .summary }
        return section
    }
}

extension AppFeature {
    /// The Monitor section a monitor extra lives in, so the Feature Hub,
    /// the Command Bar and search can open the window right there.
    var monitorSection: MonitorSection? {
        switch self {
        case .monitorInsights: return .diagnostics
        case .monitorAnalytics: return .history
        case .monitorEnergy: return .processes
        case .monitorNetworkDetails: return .network
        default: return nil
        }
    }
}

/// What the Monitor window shows and whether anyone can see it. While the
/// window is visible the monitor samples only the families of the section on
/// screen, and the 3 s kext poll runs only for the Processor section; hidden,
/// minimized, covered or closed, both are handed back, so nothing samples
/// for a window nobody sees.
@MainActor
final class MonitorWindowState: ObservableObject {
    static let sectionKey = "monitorWindowSection"

    @Published var section: MonitorSection {
        didSet {
            guard section != oldValue else { return }
            UserDefaults.standard.set(section.rawValue, forKey: Self.sectionKey)
            sync()
        }
    }
    @Published private(set) var isVisible = false
    /// The process search, kept here so it survives a trip to another
    /// section, as it does in Activity Monitor's tabs.
    @Published var processSearch = ""
    /// The process table's sort order and selection, kept here for the same
    /// reason: the table's own state goes away with the section.
    @Published var processSortOrder = [KeyPathComparator(\ProcessTableRow.cpu, order: .reverse)]
    @Published var processSelection: pid_t?

    /// Menu commands for the process table, which acts on the selection.
    enum Command { case inspect, terminate }
    let commands = PassthroughSubject<Command, Never>()
    /// Set by the process table, read when the View menu validates.
    var canInspectSelection = false
    var canTerminateSelection = false

    private var heldNeeds = SystemMonitorPanelNeeds.none
    private var holdsLiveSync = false

    init() {
        section = MonitorSection.restored(UserDefaults.standard.string(forKey: Self.sectionKey))
    }

    /// The History metric decides one live family, so a new choice resyncs.
    func historyMetricChanged() {
        sync()
    }

    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        sync()
    }

    /// What the window holds for a section and a visibility: the section's
    /// families and, on Processor only, the 3 s kext poll; nothing at all
    /// while nobody can see the window.
    nonisolated static func holds(section: MonitorSection,
                                  isVisible: Bool) -> (needs: SystemMonitorPanelNeeds, liveSync: Bool) {
        guard isVisible else { return (.none, false) }
        return (section.monitorNeeds, section == .processor)
    }

    private func sync() {
        let (wantsNeeds, wantsLiveSync) = Self.holds(section: section, isVisible: isVisible)
        if wantsNeeds != heldNeeds {
            heldNeeds = wantsNeeds
            SystemMonitor.shared.setDashboardNeeds(wantsNeeds)
        }
        if wantsLiveSync != holdsLiveSync {
            holdsLiveSync = wantsLiveSync
            if wantsLiveSync { AmdPowerControlsModel.shared.beginLiveSync() } else { AmdPowerControlsModel.shared.endLiveSync() }
        }
    }
}

/// Owns the Monitor window. Closing it releases the window and its views,
/// so nothing keeps refreshing behind a closed window; covered, minimized or
/// on another Space, the window is occluded and the state stops the samplers.
@MainActor
final class MonitorWindowController: NSObject, NSWindowDelegate {
    static let shared = MonitorWindowController()

    private var window: NSWindow?
    private var state: MonitorWindowState?
    private var occlusionObserver: NSObjectProtocol?
    private var titleSubscription: AnyCancellable?

    private override init() {}

    func show(section: MonitorSection? = nil) {
        if let window, let state {
            if let section, section.isAvailable { state.section = section }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // The same read as a new window: occlusion notifications report
            // changes, so a state that missed one is set right here too.
            state.setVisible(window.occlusionState.contains(.visible))
            return
        }
        let state = MonitorWindowState()
        if let section, section.isAvailable { state.section = section }
        let host = NSHostingController(rootView: MonitorWindowView(state: state))
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.toolbarStyle = .unified
        // The section control names where you are; like Calendar, the title
        // text gives the centered control its room. The title still names
        // the window in the Window menu and Mission Control.
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        // Six text segments plus Inspect, Terminate and search fit without
        // overflowing the toolbar (HIG Toolbars) in the longest languages.
        window.contentMinSize = NSSize(width: 980, height: 520)
        window.setContentSize(NSSize(width: 1000, height: 660))
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        // A frame saved by an older build can be narrower than today's
        // minimum; restoring does not clamp it, so it is clamped here and
        // kept on screen.
        let minimum = window.frameRect(forContentRect: NSRect(origin: .zero, size: window.contentMinSize)).size
        var frame = window.frame
        frame.size.width = max(frame.width, minimum.width)
        frame.size.height = max(frame.height, minimum.height)
        frame = window.constrainFrameRect(frame, to: window.screen ?? NSScreen.main)
        if frame != window.frame { window.setFrame(frame, display: false) }
        window.setFrameAutosaveName(Self.frameName)

        // Title = current section, in the app's current language.
        titleSubscription = state.$section
            .combineLatest(L10n.shared.$language)
            .receive(on: DispatchQueue.main)
            .sink { [weak window] section, language in
                let strings = MonitorWindowStrings.localized(language)
                window?.title = section.title(strings) + " — " + strings.windowTitle
            }

        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak window, weak state] _ in
            MainActor.assumeIsolated {
                guard let window, let state else { return }
                state.setVisible(window.occlusionState.contains(.visible))
            }
        }

        self.window = window
        self.state = state
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Only occlusion says whether anyone can see it: a window opened
        // behind another one starts hidden, and the notification above
        // reports every later change.
        state.setVisible(window.occlusionState.contains(.visible))
    }

    private static let frameName = "RyzenStatusMonitorWindow"

    // MARK: View menu

    /// The View menu: Open Monitor (always available, so a closed window can
    /// come back), every section with ⌘1…⌘6, then Inspect (⌘I) and
    /// Terminate, so each toolbar command also lives in the menu bar (HIG
    /// Toolbars › macOS). Section and process items act while the Monitor
    /// window is key.
    static func viewMenuItem(language: AppLanguage) -> NSMenuItem {
        let strings = MonitorWindowStrings.localized(language)
        let suite = FeatureStrings.performanceSuite(language)
        let item = NSMenuItem()
        let menu = NSMenu(title: strings.viewMenu)
        item.submenu = menu
        let open = NSMenuItem(title: strings.openMonitor, action: #selector(openMonitor(_:)), keyEquivalent: "0")
        open.target = shared
        menu.addItem(open)
        menu.addItem(.separator())
        for (index, section) in MonitorSection.allCases.enumerated() {
            let entry = NSMenuItem(title: section.title(strings), action: #selector(selectSection(_:)),
                                   keyEquivalent: String(index + 1))
            entry.target = shared
            entry.representedObject = section.rawValue
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let inspect = NSMenuItem(title: suite.inspectButton, action: #selector(inspectSelection(_:)), keyEquivalent: "i")
        inspect.target = shared
        menu.addItem(inspect)
        let terminate = NSMenuItem(title: suite.killButton + "…", action: #selector(terminateSelection(_:)),
                                   keyEquivalent: "")
        terminate.target = shared
        menu.addItem(terminate)
        return item
    }

    private var isKey: Bool { window?.isKeyWindow == true }

    @objc private func openMonitor(_ sender: NSMenuItem) { show() }

    @objc private func selectSection(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let section = MonitorSection(rawValue: raw),
              section.isAvailable else { return }
        state?.section = section
    }

    @objc private func inspectSelection(_ sender: NSMenuItem) { state?.commands.send(.inspect) }

    @objc private func terminateSelection(_ sender: NSMenuItem) { state?.commands.send(.terminate) }

    /// The SDK marks this delegate method main-actor (`NS_SWIFT_UI_ACTOR` in
    /// NSWindow.h), so it is a plain method of this main-actor class.
    /// Cleaning up right here, not in a later task, keeps a window reopened
    /// in the same turn from being forgotten by the cleanup of the one that
    /// closed.
    func windowWillClose(_ notification: Notification) {
        guard let window, notification.object as AnyObject? === window else { return }
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
        occlusionObserver = nil
        titleSubscription = nil
        state?.setVisible(false)
        state = nil
        self.window = nil
    }
}

extension MonitorWindowController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(openMonitor(_:)) { return true }
        guard isKey, let state else {
            item.state = .off
            return false
        }
        switch item.action {
        case #selector(selectSection(_:)):
            let section = (item.representedObject as? String).flatMap(MonitorSection.init(rawValue:))
            item.state = section == state.section ? .on : .off
            return section?.isAvailable ?? false
        case #selector(inspectSelection(_:)):
            return state.section == .processes && state.canInspectSelection
        case #selector(terminateSelection(_:)):
            return state.section == .processes && state.canTerminateSelection
        default:
            return true
        }
    }
}

/// The Monitor window's root: the section control in the toolbar (HIG
/// Segmented controls › macOS: view switching belongs in a toolbar or a tab
/// view, never in the window body) and the visible section under it.
struct MonitorWindowView: View {
    @ObservedObject var state: MonitorWindowState
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var runtime = FeatureRuntime.shared

    private var sections: [MonitorSection] { MonitorSection.allCases.filter(\.isAvailable) }

    var body: some View {
        let strings = MonitorWindowStrings.localized(l10n.language)
        content
            .frame(minWidth: 980, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity, alignment: .topLeading)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker(strings.section, selection: $state.section) {
                        ForEach(sections) { section in
                            Text(section.title(strings)).tag(section)
                                .help(section.title(strings))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .onChange(of: runtime.revision) { _, _ in
                if !state.section.isAvailable { state.section = .summary }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch state.section {
        case .summary:
            SummarySection(isVisible: state.isVisible)
        case .processor:
            ProcessorSection(isVisible: state.isVisible)
        case .processes:
            ProcessesSection(state: state)
        case .network:
            MonitorNetworkSection(isVisible: state.isVisible)
        case .history:
            HistorySection(state: state)
        case .diagnostics:
            DiagnosticsSection(isVisible: state.isVisible)
        }
    }
}

/// The Settings page for the Dashboard row: the Dashboard lives in its own
/// window (HIG Settings: the settings window holds settings), so the page
/// offers the button that opens it, without taking focus on its own.
struct MonitorLauncherPage: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let strings = MonitorWindowStrings.localized(l10n.language)
        ContentUnavailableView {
            Label(strings.windowTitle, systemImage: "gauge.with.dots.needle.33percent")
        } description: {
            Text(strings.openMonitorCaption)
        } actions: {
            Button(strings.openMonitor) { MonitorWindowController.shared.show() }
                .buttonStyle(.borderedProminent)
        }
    }
}
