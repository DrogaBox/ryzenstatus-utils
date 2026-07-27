// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

struct WhatsAppDownloadsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var manager = WhatsAppDownloadManager.shared
    @ObservedObject private var scheduler = WhatsAppDownloadScheduler.shared
    @ObservedObject private var organizer = WhatsAppDownloadOrganizer.shared
    @ObservedObject private var permissions = Permissions.shared

    @AppStorage(DefaultsKey.whatsAppDownloadsAutomaticEnabled) private var automatic = false
    @AppStorage(DefaultsKey.whatsAppDownloadsCategories) private var categoriesRaw = "image,video,audio"
    @AppStorage(DefaultsKey.whatsAppDownloadsRetentionDays) private var retentionDays = 7
    @AppStorage(DefaultsKey.whatsAppDownloadsNotify) private var notify = true
    @AppStorage(DefaultsKey.whatsAppDownloadsLastCleanup) private var lastCleanup = 0.0
    @AppStorage(DefaultsKey.whatsAppDownloadsLastCleanupCount) private var lastCount = 0
    @AppStorage(DefaultsKey.whatsAppDownloadsLastCleanupBytes) private var lastBytes: Int64 = 0
    @AppStorage(DefaultsKey.whatsAppDownloadsLastCleanupFailed) private var lastFailed = 0
    @AppStorage(DefaultsKey.whatsAppDownloadsLastCleanupAutomatic) private var lastAutomatic = false
    @AppStorage(DefaultsKey.whatsAppDownloadsAutomaticStartDate) private var autoStartDate = 0.0
    @AppStorage(DefaultsKey.whatsAppDownloadsIncludeExisting) private var includeExisting = false
    @AppStorage(DefaultsKey.whatsAppOrganizerEnabled) private var organizerEnabled = false
    @AppStorage(DefaultsKey.whatsAppOrganizerDelayMinutes) private var organizerDelay = 5
    @AppStorage(DefaultsKey.whatsAppOrganizerLayout) private var layout = "flat"
    @AppStorage(DefaultsKey.whatsAppOrganizerDuplicateAction) private var duplicateAction = "trashNew"
    @AppStorage(DefaultsKey.whatsAppOrganizerLastRun) private var organizerLastRun = 0.0
    @AppStorage(DefaultsKey.whatsAppOrganizerLastMoved) private var organizerLastMoved = 0
    @AppStorage(DefaultsKey.whatsAppOrganizerLastDuplicates) private var organizerLastDuplicates = 0
    @AppStorage(DefaultsKey.whatsAppOrganizerLastFailed) private var organizerLastFailed = 0

    @State private var firstRunSheet = false
    @State private var showOrganizerDestination = false
    @State private var showManualScanResults = false
    @State private var previousAutomatic = false

    private var strings: WhatsAppDownloadStrings { FeatureStrings.whatsAppDownloads(l10n.language) }
    private var organizerStrings: WhatsAppOrganizerStrings { .localized(l10n.language) }

    var body: some View {
        Form {
            Section(strings.folder) {
                Text(strings.intro)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                switch manager.accessStatus {
                case .unknown, .denied:
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(strings.accessDenied)
                            .font(.caption)
                    }
                case .available:
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(strings.accessReady)
                            .font(.caption)
                    }
                }
            }

            Section(strings.fileTypes) {
                categoriesPicker
                Picker(strings.retention, selection: $retentionDays) {
                    ForEach(WhatsAppDownloadSupport.allowedRetentionDays, id: \.self) { days in
                        Text(String(format: strings.daysFormat, days)).tag(days)
                    }
                }
                Text(strings.retentionCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(strings.automatic, isOn: $automatic)
                    .onChange(of: automatic) { _, newValue in
                        if newValue {
                            checkFirstRun()
                        }
                        scheduler.syncWithPreferences()
                        if !newValue { scheduler.stop() }
                    }
                if automatic {
                    Text(strings.automaticCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(strings.notify, isOn: $notify)
                    activitySection
                }
            }

            Section(organizerStrings.title) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(organizerStrings.experimental)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    Text(strings.intro)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle(organizerStrings.enabled, isOn: $organizerEnabled)
                    .onChange(of: organizerEnabled) { _, _ in
                        organizer.syncWithPreferences()
                        if !organizerEnabled { organizer.stop() }
                    }
                if organizerEnabled {
                    destinationSection
                    Picker(organizerStrings.organization, selection: $layout) {
                        Text(organizerStrings.flat).tag("flat")
                        Text(organizerStrings.byType).tag("category")
                        Text(organizerStrings.byMonth).tag("month")
                    }
                    Picker(organizerStrings.delay, selection: $organizerDelay) {
                        ForEach(WhatsAppDownloadSupport.allowedOrganizerDelayMinutes, id: \.self) { min in
                            Text(String(format: organizerStrings.minutesFormat, min)).tag(min)
                        }
                    }
                    Picker(organizerStrings.duplicateAction, selection: $duplicateAction) {
                        Text(organizerStrings.trashDuplicate).tag("trashNew")
                        Text(organizerStrings.keepBoth).tag("keepBoth")
                        Text(organizerStrings.replaceExisting).tag("replaceExisting")
                    }
                    Text(organizerStrings.duplicateCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    organizerActionButtons
                    organizerActivitySection
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $firstRunSheet) { firstRunSheetContent }
        .sheet(isPresented: $showManualScanResults) { manualScanResults }
        .onAppear {
            if manager.accessStatus == .unknown { manager.scan() }
        }
    }

    private var categoriesPicker: some View {
        let categories = WhatsAppDownloadSupport.decodedCategories(categoriesRaw)
        let binding = Binding<Set<WhatsAppDownloadCategory>>(
            get: { categories },
            set: { categoriesRaw = WhatsAppDownloadSupport.encodedCategories($0) }
        )
        return Group {
            ForEach(WhatsAppDownloadCategory.allCases) { category in
                Toggle(categoryLabel(category),
                       isOn: Binding(
                        get: { binding.wrappedValue.contains(category) },
                        set: { newValue in
                            var current = binding.wrappedValue
                            if newValue { current.insert(category) }
                            else { current.remove(category) }
                            binding.wrappedValue = current
                        }
                       ))
            }
        }
    }

    private func categoryLabel(_ category: WhatsAppDownloadCategory) -> String {
        switch category {
        case .image: return strings.image
        case .video: return strings.video
        case .audio: return strings.audio
        case .document: return strings.document
        case .archive: return strings.archive
        case .other: return strings.other
        }
    }

    private var activitySection: some View {
        Group {
            if lastCleanup > 0 {
                Text(String(format: strings.lastRunFormat,
                           Date(timeIntervalSince1970: lastCleanup), lastCount,
                           ByteCountFormatter.string(fromByteCount: lastBytes, countStyle: .file),
                           lastFailed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(strings.neverRun)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let next = scheduler.nextFire {
                Text(String(format: strings.nextRunFormat, next))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(organizerStrings.destination)
                Spacer()
                Button(organizerStrings.chooseFolder) { showOrganizerDestination = true }
                    .fileImporter(isPresented: $showOrganizerDestination,
                                 allowedContentTypes: [.folder]) { result in
                        if case let .success(url) = result {
                            if !organizer.setDestination(url) {
                                // invalid destination
                            }
                        }
                    }
                Button(organizerStrings.useDefault) {
                    organizer.setDestination(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(organizerStrings.invalidDestination)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var organizerActionButtons: some View {
        HStack {
            Button(organizerStrings.organizeNow) { organizer.runNow() }
                .disabled(organizer.isBusy)
            if organizer.canUndo {
                Button(organizerStrings.undo) { organizer.undoLastRun() }
                    .disabled(organizer.isBusy)
            }
        }
    }

    private var organizerActivitySection: some View {
        Group {
            if case let .done(moved, dupes, failed) = organizer.phase {
                if moved > 0 || dupes > 0 || failed > 0 {
                    Text(String(format: organizerStrings.resultFormat, moved, dupes, failed))
                        .font(.caption)
                }
            } else if case .waiting = organizer.phase {
                Text(organizerStrings.waiting)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if case .organizing = organizer.phase {
                Text(organizerStrings.working)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if organizerLastRun > 0 {
                Text(String(format: organizerStrings.lastRunFormat,
                           Date(timeIntervalSince1970: organizerLastRun),
                           organizerLastMoved, organizerLastDuplicates, organizerLastFailed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(organizerStrings.neverRun)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func checkFirstRun() {
        guard autoStartDate <= 0 else { return }
        let manager = WhatsAppDownloadManager.shared
        if manager.phase != .results { manager.scan() }
        firstRunSheet = true
    }

    private var firstRunSheetContent: some View {
        VStack(spacing: 16) {
            Text(strings.firstTitle).font(.headline)
            Text(String(format: strings.firstMessageFormat, manager.eligibleCount))
                .font(.body)
                .multilineTextAlignment(.center)
                .padding()
            HStack(spacing: 12) {
                Button(strings.futureOnly) {
                    autoStartDate = Date().timeIntervalSince1970
                    firstRunSheet = false
                }
                .buttonStyle(.bordered)
                Button(strings.includeExisting) {
                    includeExisting = true
                    autoStartDate = Date().timeIntervalSince1970
                    firstRunSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 380)
    }

    private var manualScanResults: some View {
        NavigationStack {
            List {
                if manager.candidates.isEmpty {
                    Text(strings.noFiles)
                        .foregroundStyle(.secondary)
                }
                ForEach(manager.candidates) { candidate in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(candidate.name).font(.body)
                            Text(categoryLabel(candidate.category))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: candidate.size,
                                                       countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(strings.keep) { showManualScanResults = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(format: strings.cleanSelectedFormat,
                                 manager.selectedCount,
                                 ByteCountFormatter.string(fromByteCount: manager.selectedBytes,
                                                          countStyle: .file))) {
                        manager.cleanSelected(automatic: false)
                        showManualScanResults = false
                    }
                    .disabled(manager.selectedCount == 0)
                }
            }
        }
        .frame(width: 500, height: 400)
    }
}
