// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

struct PackageManagerView: View {
    var onClose: (() -> Void)? = nil
    @AppStorage(DefaultsKey.packageManagerProvider) private var provider = PackageManagerProvider.automatic.rawValue
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var brew = HomebrewManager.shared
    private var text: PackageManagerStrings { FeatureStrings.packageManager(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(text.title, selection: $provider) {
                Text(text.automatic).tag(PackageManagerProvider.automatic.rawValue)
                Text("MacPorts").tag(PackageManagerProvider.macPorts.rawValue)
                if homebrewOffered {
                    Text("Homebrew").tag(PackageManagerProvider.homebrew.rawValue)
                }
            }
            .disabled(brew.operation != nil)
            .padding(.horizontal, 12)
            Text(homebrewOffered ? text.caption : text.intelCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            Divider()
            if PackageManagerProvider.current == .macPorts {
                MacPortsView(onClose: onClose)
            } else if let onClose {
                PanelHomebrewView(onClose: onClose)
            } else {
                HomebrewSettings()
            }
        }
        .padding(.top, 8)
        .onAppear {
            // A Homebrew choice left from before has no row to show on an
            // Intel Mac without it; the picker falls back to Automatic.
            if !homebrewOffered, provider == PackageManagerProvider.homebrew.rawValue {
                provider = PackageManagerProvider.automatic.rawValue
            }
        }
    }

    private var homebrewOffered: Bool { PackageManagerProvider.homebrewOffered }
}

private struct MacPortsPendingAction: Identifiable {
    let action: MacPortsSupport.Action
    let package: String?
    var id: String { action.rawValue + ":" + (package ?? "") }
}

private struct MacPortsView: View {
    var onClose: (() -> Void)?
    @ObservedObject private var ports = MacPortsManager.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var query = ""
    @State private var pending: MacPortsPendingAction?
    private var text: PackageManagerStrings { FeatureStrings.packageManager(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("MacPorts", systemImage: "shippingbox")
                    .font(.headline)
                Spacer()
                if let onClose {
                    Button(action: onClose) { Image(systemName: "xmark.circle") }
                        .help(l10n.s.uninstallerCancel)
                        .accessibilityLabel(l10n.s.uninstallerCancel)
                }
            }
            if !ports.available {
                Text(text.missing).font(.caption).foregroundStyle(.secondary)
                Link(l10n.s.homebrewInstallHomebrew.replacingOccurrences(of: "Homebrew", with: "MacPorts"),
                     destination: URL(string: "https://www.macports.org/install.php")!)
                Button(l10n.s.homebrewRefresh) { ports.refresh() }
            } else {
                HStack {
                    TextField(l10n.s.homebrewSearchPlaceholder, text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { ports.search(query) }
                    Button(l10n.s.homebrewSearchButton) { ports.search(query) }
                        .disabled(MacPortsSupport.searchArguments(query) == nil || ports.busy)
                    Button { ports.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .help(l10n.s.homebrewRefresh)
                        .accessibilityLabel(l10n.s.homebrewRefresh)
                        .disabled(ports.busy)
                }
                HStack {
                    Button(l10n.s.homebrewUpdateHomebrew.replacingOccurrences(of: "Homebrew", with: "MacPorts")) {
                        pending = MacPortsPendingAction(action: .selfupdate, package: nil)
                    }
                    Button(l10n.s.homebrewUpgradeAll) {
                        pending = MacPortsPendingAction(action: .upgradeAll, package: nil)
                    }
                    .disabled(!ports.installed.contains(where: \.isOutdated))
                    if ports.busy { ProgressView().controlSize(.small) }
                }
                .disabled(ports.busy)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if !ports.searchResults.isEmpty {
                            Text(l10n.s.homebrewSearchResults).font(.headline)
                            ForEach(ports.searchResults) { package in row(package, searchResult: true) }
                            Divider()
                        }
                        Text("\(l10n.s.homebrewInstalled) · \(ports.installed.count)").font(.headline)
                        if ports.installed.isEmpty, !ports.busy {
                            Text(l10n.s.homebrewNoPackages).foregroundStyle(.secondary)
                        }
                        ForEach(ports.installed) { package in row(package, searchResult: false) }
                    }
                }
            }
            if let error = ports.error, !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            if let command = ports.handedOffCommand {
                Text(text.handoff).font(.caption).foregroundStyle(.secondary)
                Text(command).font(.caption.monospaced()).textSelection(.enabled)
            }
        }
        .padding(12)
        .onAppear {
            if onClose != nil { PanelInteractionState.shared.viewKeepsPopoverOpen = true }
            ports.refresh()
        }
        .onDisappear {
            if onClose != nil { PanelInteractionState.shared.viewKeepsPopoverOpen = false }
            PanelInteractionState.shared.isPresentingPopoverModal = false
        }
        .onChange(of: pending?.id) { _, value in
            if onClose != nil { PanelInteractionState.shared.isPresentingPopoverModal = value != nil }
        }
        .sheet(item: $pending) { request in
            VStack(alignment: .leading, spacing: 14) {
                Text("MacPorts").font(.headline)
                Text(text.privilege)
                Text(MacPortsSupport.shellCommand(action: request.action, package: request.package) ?? "")
                    .font(.body.monospaced()).textSelection(.enabled)
                HStack {
                    Button(l10n.s.uninstallerCancel) { pending = nil }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(l10n.s.homebrewOpenTerminal) {
                        pending = nil
                        ports.handOff(request.action, package: request.package)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24).frame(width: 440)
        }
    }

    private func row(_ package: MacPortsPackage, searchResult: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(package.name).fontWeight(.medium)
                if let installed = package.installedVersion {
                    Text(installed).font(.caption.monospaced()).foregroundStyle(.secondary)
                } else if let version = package.latestVersion {
                    Text(version).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if package.isOutdated, let latest = package.latestVersion {
                    Text("→ \(latest)").font(.caption).foregroundStyle(.orange)
                }
                if !package.description.isEmpty {
                    Text(package.description).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if searchResult, !ports.installed.contains(where: { $0.name == package.name }) {
                Button(l10n.s.homebrewInstall) {
                    pending = MacPortsPendingAction(action: .install, package: package.name)
                }
            } else if !searchResult {
                if package.isOutdated {
                    Button(l10n.s.homebrewUpgrade) {
                        pending = MacPortsPendingAction(action: .upgrade, package: package.name)
                    }
                }
                Button(l10n.s.homebrewUninstall, role: .destructive) {
                    pending = MacPortsPendingAction(action: .uninstall, package: package.name)
                }
            }
        }
        .disabled(ports.busy)
        .padding(.vertical, 4)
    }
}
