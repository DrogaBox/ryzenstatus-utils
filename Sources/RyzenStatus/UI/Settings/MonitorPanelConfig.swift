// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI
import UniformTypeIdentifiers

/// Reusable panel configuration: one expandable block per panel section, each
/// with a master "show in panel" toggle plus per-item toggles. Supports drag-and-drop
/// reordering of all sections (including Mixer) so users can customize section order.
/// Shared by Settings → Monitor and the onboarding panel step so the two stay identical.
/// Designed to live inside a `Form` (grouped style) in both places.
struct MonitorPanelConfig: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.panelSectionOrder) private var sectionOrderRaw = ""
    @State private var order: [PanelSectionID] = PanelLayout.order
    @State private var dragging: PanelSectionID?
    @State private var expandedBlocks = Set<PanelSectionID>()

    @AppStorage(DefaultsKey.monitorShowSystem) private var showSystem = true
    @AppStorage(DefaultsKey.monitorSysTemps) private var sysTemps = true
    @AppStorage(DefaultsKey.monitorSysCPU) private var sysCPU = true
    @AppStorage(DefaultsKey.monitorSysGPU) private var sysGPU = true
    @AppStorage(DefaultsKey.monitorSysBattery) private var sysBattery = true
    @AppStorage(DefaultsKey.monitorSysMemory) private var sysMemory = true
    @AppStorage(DefaultsKey.monitorSysUptime) private var sysUptime = true

    @AppStorage(DefaultsKey.monitorShowNetwork) private var showNetwork = true
    @AppStorage(DefaultsKey.monitorNetSpeed) private var netSpeed = true
    @AppStorage(DefaultsKey.monitorNetApps) private var netApps = true
    @AppStorage(DefaultsKey.monitorNetTotals) private var netTotals = true
    @AppStorage(DefaultsKey.monitorNetTest) private var netTest = true

    @AppStorage(DefaultsKey.monitorShowDisk) private var showDisk = true
    @AppStorage(DefaultsKey.monitorDiskUsage) private var diskUsage = true
    @AppStorage(DefaultsKey.monitorDiskActivity) private var diskActivity = true
    @AppStorage(DefaultsKey.monitorDiskSMART) private var diskSMART = true
    @AppStorage(DefaultsKey.monitorDiskProtection) private var diskProtection = true
    @AppStorage(DefaultsKey.monitorDiskTools) private var diskTools = true

    @AppStorage(DefaultsKey.monitorShowPower) private var showPower = true
    @AppStorage(DefaultsKey.monitorPwrSystem) private var pwrSystem = true
    @AppStorage(DefaultsKey.monitorPwrAdapter) private var pwrAdapter = true
    @AppStorage(DefaultsKey.monitorPwrBattery) private var pwrBattery = true
    @AppStorage(DefaultsKey.monitorPwrTimeRemaining) private var pwrTimeRemaining = true
    @AppStorage(DefaultsKey.monitorPwrHealth) private var pwrHealth = true

    @AppStorage(DefaultsKey.monitorShowMixer) private var showMixer = true
    @AppStorage(DefaultsKey.panelShowKeepAwake) private var showKeepAwake = true
    @AppStorage(DefaultsKey.panelShowBrightness) private var showBrightness = true
    @AppStorage(DefaultsKey.panelShowAmdPower) private var showAmdPower = true
    @AppStorage(DefaultsKey.panelShowUtilities) private var showUtilities = true
    @AppStorage(DefaultsKey.panelShowControls) private var showControls = true
    @AppStorage(DefaultsKey.panelShowToggles) private var showToggles = true

    var body: some View {
        VStack(spacing: 0) {
            ForEach(editableOrder) { id in
                block(for: id)
            }
        }
        .onAppear {
            order = PanelLayout.order
        }
        .onChange(of: sectionOrderRaw) { _, _ in
            order = PanelLayout.order
        }
    }

    private var editableOrder: [PanelSectionID] {
        order.filter { $0.isAvailable }
    }

    private func masterBinding(for id: PanelSectionID) -> Binding<Bool> {
        switch id {
        case .system: return $showSystem
        case .network: return $showNetwork
        case .disk: return $showDisk
        case .power: return $showPower
        case .mixer: return $showMixer
        case .keepAwake: return $showKeepAwake
        case .brightness: return $showBrightness
        case .amdPower: return $showAmdPower
        case .utilities: return $showUtilities
        case .controls: return $showControls
        case .toggles: return $showToggles
        }
    }

    @ViewBuilder
    private func block(for id: PanelSectionID) -> some View {
        let master = masterBinding(for: id)
        DisclosureGroup(isExpanded: expansionBinding(for: id)) {
            Toggle(l10n.s.monitorShowInPanel, isOn: master)
            subItems(for: id)
                .disabled(!master.wrappedValue)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Image(systemName: id.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(id.title(l10n.s))
                    .foregroundStyle(master.wrappedValue ? .primary : .secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(dragging == id ? 0.45 : 1)
            .onTapGesture {
                toggle(id)
            }
            .onDrag {
                dragging = id
                return NSItemProvider(object: id.rawValue as NSString)
            }
            .onDrop(of: [UTType.text],
                    delegate: PanelOrderDropDelegate(target: id,
                                                     order: $order,
                                                     dragging: $dragging))
        }
    }

    @ViewBuilder
    private func subItems(for id: PanelSectionID) -> some View {
        switch id {
        case .system:
            if AppFeature.monitorCPU.isAvailable || AppFeature.monitorGPU.isAvailable
                || AppFeature.monitorPower.isAvailable {
                Toggle(l10n.s.temperatures, isOn: $sysTemps)
            }
            if AppFeature.monitorCPU.isAvailable {
                Toggle(l10n.s.cpuLabel, isOn: $sysCPU)
            }
            if AppFeature.monitorGPU.isAvailable {
                Toggle(l10n.s.gpuLabel, isOn: $sysGPU)
            }
            if AppFeature.monitorPower.isAvailable {
                Toggle(l10n.s.batteryLabel, isOn: $sysBattery)
            }
            if AppFeature.monitorMemory.isAvailable {
                Toggle(l10n.s.memorySection, isOn: $sysMemory)
            }
            Toggle(l10n.s.monitorItemUptime, isOn: $sysUptime)
        case .network:
            Toggle(l10n.s.monitorItemNetSpeed, isOn: $netSpeed)
            Toggle(l10n.s.networkApps, isOn: $netApps)
            Toggle(l10n.s.monitorItemNetTotals, isOn: $netTotals)
            Toggle(l10n.s.monitorItemNetTest, isOn: $netTest)
        case .disk:
            Toggle(l10n.s.monitorItemDiskUsage, isOn: $diskUsage)
            Toggle(l10n.s.monitorItemDiskActivity, isOn: $diskActivity)
            Toggle(l10n.s.monitorItemDiskSMART, isOn: $diskSMART)
            Toggle(l10n.s.monitorItemDiskProtection, isOn: $diskProtection)
            Toggle(l10n.s.monitorItemDiskTools, isOn: $diskTools)
        case .power:
            Toggle(l10n.s.powerSystem, isOn: $pwrSystem)
            Toggle(l10n.s.powerAdapter, isOn: $pwrAdapter)
            Toggle(l10n.s.powerBattery, isOn: $pwrBattery)
            Toggle(FeatureStrings.batteryTime(l10n.language).title, isOn: $pwrTimeRemaining)
            Toggle(l10n.s.powerHealth, isOn: $pwrHealth)
        default:
            EmptyView()
        }
    }

    private func expansionBinding(for id: PanelSectionID) -> Binding<Bool> {
        Binding(
            get: { expandedBlocks.contains(id) },
            set: { expanded in
                if expanded {
                    expandedBlocks.insert(id)
                } else {
                    expandedBlocks.remove(id)
                }
            }
        )
    }

    private func toggle(_ id: PanelSectionID) {
        if expandedBlocks.contains(id) {
            expandedBlocks.remove(id)
        } else {
            expandedBlocks.insert(id)
        }
    }
}
