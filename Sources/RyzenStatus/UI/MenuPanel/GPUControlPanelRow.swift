// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// The GPU power limit in the menu bar panel (plan 7.2): a standard menu
/// `Picker` with the page's values and the state in one line ("Settings":
/// what changes with the moment goes where the task is). Only with a kext
/// that has the write path; a limit left on shows here every time the panel
/// opens.
struct GPUControlPanelRow: View {
    @ObservedObject private var service = GPUControlService.shared
    @ObservedObject private var sensors = GPUSensorsService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        if GPUControlVisibility.visible(hasWritePath: sensors.hasWritePath,
                                        hasUnsupportedCard: sensors.hasUnsupportedCard,
                                        fake: service.mode == .fake) {
            GPUControlPanelRowContent(
                input: GPUControlPageInput(service: service),
                strings: FeatureStrings.gpuControlPage(l10n.language),
                choosePower: { service.choosePower($0) })
                .onAppear { service.viewerAppeared() }
                .onDisappear { service.viewerDisappeared() }
        }
    }
}

struct GPUControlPanelRowContent: View {
    let input: GPUControlPageInput
    let strings: GPUControlPageStrings
    let choosePower: (Int) -> Void

    var body: some View {
        let choices = GPUControlPageLogic.powerChoices(facts: input.facts, state: input.state)
        let shown = input.facts.flatMap { GPUControlPageLogic.shownWatts(facts: $0, snapshot: input.snapshot) }
        VStack(alignment: .leading, spacing: 4) {
            if choices.isEmpty {
                // No start-up value yet: no empty pop-up, only the state.
                LabeledContent(strings.panelLabel) {
                    Text(strings.waitingForDriver).foregroundStyle(.secondary)
                }
            } else {
                Picker(strings.panelLabel, selection: Binding(
                    get: { shown ?? choices[0] },
                    set: { choosePower($0) })) {
                    ForEach(choices, id: \.self) { watts in
                        Text(watts == choices[0] ? String(format: strings.bootFormat, watts)
                                                 : String(format: strings.wattsFormat, watts))
                            .tag(watts)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!input.canChoose || !(input.state?.acceptsChoices ?? false) || input.isPending)
            }
            Text(input.stateTitle(strings, short: true))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
