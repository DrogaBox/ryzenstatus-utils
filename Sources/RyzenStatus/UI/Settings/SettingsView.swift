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
/// Directory construction is much more expensive than selecting an existing
/// row. Rebuild only when its language, icon source or availability changes.
private final class SettingsDirectoryCache {
    private struct Key: Equatable {
        let language: AppLanguage
        let superKeySource: SuperKeySource
        let featureRevision: Int
    }

    private var navigationKey: Key?
    private(set) var sections: [SettingsSidebarSection] = []
    private(set) var items: [SettingsSidebarItem] = []
    private var searchKey: Key?
    private var searchItems: [SettingsSearchItem] = []

    func navigation(strings: Strings, language: AppLanguage,
                    superKeySource: SuperKeySource, featureRevision: Int,
                    isAvailable: (AppFeature) -> Bool) -> [SettingsSidebarSection] {
        let key = Key(language: language, superKeySource: superKeySource,
                      featureRevision: featureRevision)
        if navigationKey != key {
            sections = SettingsDirectory.sidebarSections(
                strings, language: language, superKeySource: superKeySource,
                isAvailable: isAvailable)
            items = sections.flatMap(\.items)
            navigationKey = key
        }
        return sections
    }

    func search(strings: Strings, language: AppLanguage,
                superKeySource: SuperKeySource, featureRevision: Int) -> [SettingsSearchItem] {
        let key = Key(language: language, superKeySource: superKeySource,
                      featureRevision: featureRevision)
        if searchKey != key {
            searchItems = SettingsDirectory.searchItems(
                strings, language: language, superKeySource: superKeySource)
            searchKey = key
        }
        return searchItems
    }
}

/// Settings window with named tools in the sidebar. The detail keeps each
/// tool's existing settings and section anchor.
struct SettingsView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.superKeySource) private var superKeySourceRaw =
        SuperKeySource.capsLock.rawValue
    @State private var searchQuery = ""
    @State private var activeSearchIndex: Int?
    @State private var directoryCache = SettingsDirectoryCache()
    @State private var collapsedSectionIDs: Set<Int> = []
    @State private var navigationFromSidebar = false
    /// The row just picked in the sidebar, until the router has taken it.
    @State private var sidebarPick: SettingsSidebarItem.ID?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @FocusState private var sidebarSearchFocused: Bool

    private struct SearchResultsSnapshot: Equatable {
        let query: String
        let groups: [SettingsSearchGroup]

        var isBlank: Bool {
            query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var items: [SettingsSearchSuggestion] {
            groups.flatMap { group in
                (group.parentMatches ? [group.parentSuggestion] : []) + group.suggestions
            }
        }

        var ids: [SettingsSearchSuggestion.ID] { items.map(\.id) }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.query == rhs.query && lhs.ids == rhs.ids
        }
    }

    private var sidebarSections: [SettingsSidebarSection] {
        directoryCache.navigation(
            strings: l10n.s, language: l10n.language,
            superKeySource: SuperKeySource.sanitized(superKeySourceRaw),
            featureRevision: features.revision,
            isAvailable: { features.isAvailable($0) })
    }

    private var sidebarItems: [SettingsSidebarItem] {
        _ = sidebarSections
        return directoryCache.items
    }

    private var sidebarSelection: Binding<SettingsSidebarItem.ID?> {
        Binding(
            get: {
                sidebarPick ?? SettingsSidebarSupport.selection(
                    for: router.destination, in: sidebarItems,
                    preferredID: router.sidebarFeature.map { .feature($0) })
            },
            // The list sets its selection during a view update, where the
            // router must not publish, so the pick is routed once it ends.
            set: { selectedID in
                guard let selectedID,
                      sidebarItems.contains(where: { $0.id == selectedID }) else { return }
                sidebarPick = selectedID
            }
        )
    }

    private func routeSidebarPick(_ selectedID: SettingsSidebarItem.ID?) {
        guard let selectedID else { return }
        sidebarPick = nil
        guard let item = sidebarItems.first(where: { $0.id == selectedID }) else { return }
        let feature: AppFeature?
        if case .feature(let selectedFeature) = selectedID {
            feature = selectedFeature
        } else {
            feature = nil
        }
        navigationFromSidebar = true
        router.request(item.destination, sidebarFeature: feature)
    }

    var body: some View {
        let searchResults: SearchResultsSnapshot = {
            guard hasSearchQuery else { return SearchResultsSnapshot(query: searchQuery, groups: []) }
            return SearchResultsSnapshot(
                query: searchQuery,
                groups: SettingsSearchSupport.groupedMatchingItems(
                    query: searchQuery,
                    items: directoryCache.search(
                        strings: l10n.s, language: l10n.language,
                        superKeySource: SuperKeySource.sanitized(superKeySourceRaw),
                        featureRevision: features.revision),
                    isAvailable: { features.isAvailable($0) }))
        }()

        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar(searchResults: searchResults)
                .navigationSplitViewColumnWidth(min: 198, ideal: 210, max: 240)
        } detail: {
            // NavigationSplitView's detail slot sometimes queries its content
            // for an unconstrained ideal size (settling the divider, or on a
            // page switch). `List` answers that with its full content height
            // rather than a viewport size the way `ScrollView` does, and
            // `.frame(maxHeight: .infinity)` only bounds a size it is given,
            // not one it is asked to report - so a few hundred rows (Kill
            // Process) grew the whole window. `GeometryReader` reports the
            // real space it was actually given for normal layout, and ~zero
            // when asked for an unconstrained ideal size, breaking the chain.
            GeometryReader { geometry in
                detail
                    .settingsSectionFocus(for: router.page)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            // SwiftUI adds its sidebar button only to windows it creates, and
            // this one is AppKit's. Without it, a sidebar dragged shut could
            // only be dragged back from a one-point strip at the window's
            // edge, and a full-screen window could only peek at it.
            ToolbarItem(placement: .navigation) {
                let strings = SettingsNavigationStrings.localized(l10n.language)
                let title = sidebarShown ? strings.hideSidebar : strings.showSidebar
                Button(action: toggleSidebar) {
                    Label(title, systemImage: "sidebar.left")
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .help(title)
            }
            ToolbarItemGroup(placement: .navigation) {
                let strings = SettingsNavigationStrings.localized(l10n.language)
                Button {
                    router.goBack(isPageVisible: isPageVisible)
                } label: {
                    Label(strings.back, systemImage: "chevron.backward")
                }
                .disabled(!router.canGoBack(isPageVisible: isPageVisible))
                .help(strings.back)

                Button {
                    router.goForward(isPageVisible: isPageVisible)
                } label: {
                    Label(strings.forward, systemImage: "chevron.forward")
                }
                .disabled(!router.canGoForward(isPageVisible: isPageVisible))
                .help(strings.forward)
            }
        }
        .frame(minWidth: 772, maxWidth: .infinity, minHeight: 528, maxHeight: .infinity)
        .onAppear {
            ensureVisiblePage()
            expandSelectedSection()
        }
        .onChange(of: features.revision) { _, _ in ensureVisiblePage() }
        .onChange(of: searchResults, initial: true) { previous, current in
            updateSearchSelection(previous: previous, current: current)
        }
        .onChange(of: router.requestID) { _, _ in
            searchQuery = ""
            activeSearchIndex = nil
            ensureVisiblePage()
        }
    }

    /// macOS 27 backs the pinned sidebar search field with a hard top scroll
    /// edge, so rows fade out cleanly under it. On macOS 26 that effect does
    /// not render inside split-view sidebars and the pinned field has no
    /// backing of its own, so rows slid legibly across the placeholder
    /// (issues #183, #254); there the field lives on a fixed header above the
    /// list, where rows can never reach it. Earlier systems keep the classic
    /// opaque sidebar chrome.
    @ViewBuilder
    private func sidebar(searchResults: SearchResultsSnapshot) -> some View {
#if compiler(>=6.2)
        if #available(macOS 27, *) {
            sidebarList(searchResults: searchResults)
                .searchable(text: $searchQuery,
                            placement: .sidebar,
                            prompt: l10n.s.settingsSearchPlaceholder)
                .scrollEdgeEffectStyle(.hard, for: .top)
        } else if #available(macOS 26, *) {
            VStack(spacing: 0) {
                SidebarSearchField(query: $searchQuery, isFocused: $sidebarSearchFocused)
                sidebarList(searchResults: searchResults)
            }
        } else {
            sidebarList(searchResults: searchResults)
                .searchable(text: $searchQuery,
                            placement: .sidebar,
                            prompt: l10n.s.settingsSearchPlaceholder)
        }
#else
        sidebarList(searchResults: searchResults)
            .searchable(text: $searchQuery,
                        placement: .sidebar,
                        prompt: l10n.s.settingsSearchPlaceholder)
#endif
    }

    private var hasSearchQuery: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A sidebar dragged shut reports `.detailOnly` here as well.
    private var sidebarShown: Bool { columnVisibility != .detailOnly }

    private func toggleSidebar() {
        let next: NavigationSplitViewVisibility = sidebarShown ? .detailOnly : .all
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            columnVisibility = next
        } else {
            withAnimation { columnVisibility = next }
        }
    }

    @ViewBuilder
    private func sidebarList(searchResults: SearchResultsSnapshot) -> some View {
        ScrollViewReader { proxy in
            List(selection: sidebarSelection) {
                if hasSearchQuery {
                    searchResultRows(searchResults)
                } else {
                    normalSidebarRows
                }
            }
            .listStyle(.sidebar)
            .onChange(of: sidebarPick) { _, selectedID in routeSidebarPick(selectedID) }
            .onChange(of: activeSearchIndex) { _, index in
                guard let index, searchResults.items.indices.contains(index) else { return }
                let id = searchResults.items[index].id
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    proxy.scrollTo(id)
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id) }
                }
            }
            .onChange(of: hasSearchQuery) { _, searching in
                // The list stays in place across a search so the field keeps
                // focus, which also keeps the results' scroll offset. Centering
                // the chosen tool brings it back into view; near the top, the
                // pages clamp to where a fresh list starts, and a top anchor
                // would leave the list's inset hidden.
                guard !searching else { return }
                expandSelectedSection()
                DispatchQueue.main.async { scrollSidebarToSelection(proxy) }
            }
            .onChange(of: router.requestID) { _, _ in
                // A click in the sidebar is already visible. Only external
                // routes need to reveal and scroll to their destination.
                let fromSidebar = navigationFromSidebar
                navigationFromSidebar = false
                guard !fromSidebar else { return }
                expandSelectedSection()
                DispatchQueue.main.async { scrollSidebarToSelection(proxy) }
            }
            .background {
                SearchKeyMonitor(customSearchFocused: sidebarSearchFocused) { keyCode in
                    handleSearchKey(keyCode, searchResults: searchResults.items)
                }
            }
        }
    }

    private var selectedSidebarItem: SettingsSidebarItem.ID? {
        let items = sidebarItems
        return SettingsSidebarSupport.selection(for: router.destination, in: items,
                                                preferredID: router.sidebarFeature.map { .feature($0) })
            ?? items.first?.id
    }

    private func scrollSidebarToSelection(_ proxy: ScrollViewProxy) {
        guard !hasSearchQuery, let selected = selectedSidebarItem else { return }
        proxy.scrollTo(selected, anchor: .center)
    }

    private func expandSelectedSection() {
        guard let selected = selectedSidebarItem,
              let section = sidebarSections.first(where: { section in
                  section.items.contains(where: { $0.id == selected })
              }) else { return }
        collapsedSectionIDs.remove(section.id)
    }

    @ViewBuilder
    private var normalSidebarRows: some View {
        let sections = sidebarSections
        let items = directoryCache.items
        let selectedID = SettingsSidebarSupport.selection(for: router.destination, in: items,
                                                          preferredID: router.sidebarFeature.map { .feature($0) })
        ForEach(sections) { section in
            Section {
                if !collapsedSectionIDs.contains(section.id) {
                    ForEach(section.items) { item in
                        HStack(spacing: 9) {
                            Image(systemName: item.icon)
                                .foregroundStyle(selectedID == item.id
                                    ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                                .frame(width: 18)
                            Text(item.title)
                        }
                        .tag(item.id)
                        .id(item.id)
                        .help(item.title)
                    }
                }
            } header: {
                Button {
                    if !collapsedSectionIDs.insert(section.id).inserted {
                        collapsedSectionIDs.remove(section.id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: collapsedSectionIDs.contains(section.id)
                            ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 12)
                        Text(section.title)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func searchResultRows(_ searchResults: SearchResultsSnapshot) -> some View {
        ForEach(searchResults.groups, id: \.parentSuggestion.id) { group in
            searchPageRow(group, searchResults: searchResults)
            ForEach(group.suggestions) { suggestion in
                searchSuggestionRow(suggestion, searchResults: searchResults)
            }
        }
    }

    private func searchPageRow(_ group: SettingsSearchGroup,
                               searchResults: SearchResultsSnapshot) -> some View {
        let suggestion = group.parentSuggestion
        let selectionIndex = searchResults.items.firstIndex { $0.id == suggestion.id }
        let isSelected = selectionIndex == activeSearchIndex
        return Button {
            requestSearchItem(suggestion)
        } label: {
            Label(group.pageItem.title, systemImage: group.pageItem.icon)
                .fontWeight(.semibold)
                .searchResultRowStyle(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(suggestion.id)
    }

    private func searchSuggestionRow(_ suggestion: SettingsSearchSuggestion,
                                     searchResults: SearchResultsSnapshot) -> some View {
        let selectionIndex = searchResults.items.firstIndex { $0.id == suggestion.id }
        let isSelected = selectionIndex == activeSearchIndex
        return Button {
            requestSearchItem(suggestion)
        } label: {
            Label(suggestion.title, systemImage: suggestion.icon)
                .searchResultRowStyle(isSelected: isSelected)
                .padding(.leading, 18)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(suggestion.id)
    }

    private func handleSearchKey(_ keyCode: UInt16,
                                  searchResults: [SettingsSearchSuggestion]) -> Bool {
        switch keyCode {
        case 126: // Up
            guard !searchResults.isEmpty else { return false }
            activeSearchIndex = SettingsSearchSupport.moveSelection(
                index: activeSearchIndex, delta: -1, count: searchResults.count)
            return true
        case 125: // Down
            guard !searchResults.isEmpty else { return false }
            activeSearchIndex = SettingsSearchSupport.moveSelection(
                index: activeSearchIndex, delta: 1, count: searchResults.count)
            return true
        case 36, 76: // Return / Keypad Enter
            guard let index = activeSearchIndex,
                  searchResults.indices.contains(index) else { return false }
            requestSearchItem(searchResults[index])
            return true
        default:
            return false
        }
    }

    private func updateSearchSelection(previous: SearchResultsSnapshot,
                                       current: SearchResultsSnapshot) {
        guard !current.isBlank, !current.items.isEmpty else {
            activeSearchIndex = nil
            return
        }
        if previous.query != current.query {
            activeSearchIndex = 0
        } else if previous.ids != current.ids {
            activeSearchIndex = SettingsSearchSupport.reconciledSelection(
                index: activeSearchIndex,
                previousIDs: previous.ids,
                resultIDs: current.ids)
        }
    }

    private struct SearchKeyMonitor: NSViewRepresentable {
        var customSearchFocused: Bool
        var handleKey: (UInt16) -> Bool

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            context.coordinator.install(for: view)
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            context.coordinator.customSearchFocused = customSearchFocused
            context.coordinator.handleKey = handleKey
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(customSearchFocused: customSearchFocused, handleKey: handleKey)
        }

        static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
            coordinator.removeMonitor()
        }

        final class Coordinator: NSObject {
            var customSearchFocused: Bool
            var handleKey: (UInt16) -> Bool
            private var monitor: Any?

            init(customSearchFocused: Bool, handleKey: @escaping (UInt16) -> Bool) {
                self.customSearchFocused = customSearchFocused
                self.handleKey = handleKey
            }

            func install(for view: NSView) {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                    [weak self, weak view] event in
                    guard let self, let view, let window = view.window,
                          event.window === window,
                          Self.isNavigationKey(event),
                          let editor = window.firstResponder as? NSTextView,
                          editor.isFieldEditor,
                          (customSearchFocused || Self.isSidebarSearchEditor(editor, near: view)),
                          !editor.hasMarkedText() else { return event }
                    return handleKey(event.keyCode) ? nil : event
                }
            }

            func removeMonitor() {
                guard let monitor else { return }
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }

            private static func isNavigationKey(_ event: NSEvent) -> Bool {
                let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
                guard event.modifierFlags.intersection(blockedModifiers).isEmpty else { return false }
                return [UInt16(126), 125, 36, 76].contains(event.keyCode)
            }

            private static func isSidebarSearchEditor(_ editor: NSTextView,
                                                      near monitorView: NSView) -> Bool {
                guard let searchField = editor.delegate as? NSSearchField else { return false }
                let searchMidX = searchField.convert(searchField.bounds, to: nil).midX
                let sidebarFrame = monitorView.convert(monitorView.bounds, to: nil)
                return sidebarFrame.minX...sidebarFrame.maxX ~= searchMidX
            }
        }
    }

    private func requestSearchItem(_ suggestion: SettingsSearchSuggestion) {
        activeSearchIndex = nil
        let routed = SettingsSearchSupport.route(for: suggestion)
        router.request(routed.destination, targetFeature: routed.targetFeature,
                       sidebarFeature: suggestion.item.feature)
    }

    /// The selected page can leave the sidebar when its last feature is
    /// switched off in the hub; fall back to the hub itself, where the
    /// feature can be brought back.
    private func ensureVisiblePage() {
        if !isPageVisible(router.page) {
            router.page = .features
            return
        }
        guard router.destination.sectionAnchor != nil,
              !sidebarItems.contains(where: { $0.destination == router.destination }) else { return }
        switch router.page {
        case .general:
            // General stays visible when one of its tools is uninstalled.
            router.request(FeatureSettingsDestination(.general), replacingVisit: true)
        case .energy:
            // Energy has no overview row. A history visit to an uninstalled
            // tool should show another available tool, not an empty detail.
            if let available = sidebarItems.first(where: { $0.destination.page == .energy }) {
                router.request(available.destination, replacingVisit: true)
            }
        default:
            break
        }
    }

    private func isPageVisible(_ page: SettingsPage) -> Bool {
        FeatureVisibilitySupport.isPageVisible(page, isAvailable: { $0.isAvailable })
    }

    @ViewBuilder
    private var detail: some View {
        switch router.page {
        case .general:
            if let anchor = router.destination.sectionAnchor,
               [.panelConfiguration, .mixer, .soundOutputSwitcher,
                .audioPriority, .musicBlocking].contains(anchor),
               sidebarItems.contains(where: { $0.destination == router.destination }) {
                GeneralToolSettings(anchor: anchor)
            } else {
                GeneralSettings()
            }
        case .features: FeatureHubSettings()
        case .textSnippets: TextSnippetsSettings()
        case .notch: NotchSettings()
        case .radialMenu: RadialMenuSettings()
        case .commandBar: CommandBarSettings()
        case .energy: EnergySettings(focus: router.destination.sectionAnchor)
        case .monitor: MonitorSettings()
        case .mouse: MouseSettings()
        case .switcher: SwitcherSettings()
        case .dock: DockSettings()
        case .keyDebounce: KeyboardDebounceSettings()
        case .superKey: SuperKeySettings()
        case .cutPaste: CutPasteSettings()
        case .autoQuit: AutoQuitSettings()
        case .quitProtection: QuitProtectionSettings()
        case .uninstaller: UninstallerView()
        case .killProcess: KillProcessView()
        case .portManager: PortManagerView()
        case .urlCleaner: URLCleanerSettings()
        case .cleaner: CleanerSettings()
        case .homebrew: PackageManagerView()
        case .appUpdates: AppUpdatesSettings()
        case .media: MediaSettings()
        case .clipboard: ClipboardSettings()
        case .quickTools: QuickToolsSettings()
        case .screenshot: ScreenCaptureSettings()
        case .windowLayout: WindowLayoutSettings()
        case .shelf: ShelfSettings()
        case .shortcuts: ShortcutsSettings()
        case .advanced: AdvancedSettings()
        case .about: AboutSettings()
        case .releaseNotes: ReleaseNotesSettings()
        case .support: SupportSettings()
        case .whatsAppDownloads: WhatsAppDownloadsSettings()
        case .nowPlaying: NowPlayingSettings()
        case .fans: FansSettingsView()
        case .amdPower: AmdPowerSettingsView()
        case .amdOverclocking: AmdOverclockingSettingsView()
        case .amdValidation: AmdValidationSettingsView()
        case .dashboard: PerformanceSuiteView(monitor: SystemMonitor.shared)
        case .sensors: SensorsView()
        }
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

/// Secure Event Input blocks every synthetic keystroke. Typing a snippet
/// trigger then does nothing at all, while the snippet library and the
/// Command Bar's typing actions beep; none of the four paths says what is
/// wrong or who is holding it. This row is the only place the app explains
/// that. macOS never names the holder, only the app that was active when it
/// turned on, so the row offers that app as a lead rather than as the holder.
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

/// Search field for the macOS 26 sidebar, styled after the system pill.
/// It sits on a fixed header outside the List, so scrolling rows can never
/// cross it (issues #183, #254). Esc and the clear button empty the query,
/// matching the system field.
private struct SidebarSearchField: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var query: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(l10n.s.settingsSearchPlaceholder, text: $query)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .onExitCommand { query = "" }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.s.urlCleanerClearButton)
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

private extension View {
    func searchResultRowStyle(isSelected: Bool) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
            }
    }
}
