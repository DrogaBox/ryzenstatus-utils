// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

// MARK: - Scaffold

/// One feature page in onboarding: a hero illustration, the benefit, how to use
/// it, an optional enable toggle and an optional footer (a permission row,
/// etc.). Tools that need no activation (the uninstaller) pass no toggle.
struct ShowcaseScaffold<Hero: View, Footer: View>: View {
    let title: String
    let benefit: String
    let enableLabel: String?
    let enabled: Binding<Bool>?
    let howTo: [HowToRow]
    let onToggle: () -> Void
    let hero: Hero
    let footer: Footer

    init(title: String,
         benefit: String,
         enableLabel: String? = nil,
         enabled: Binding<Bool>? = nil,
         howTo: [HowToRow],
         onToggle: @escaping () -> Void = {},
         @ViewBuilder hero: () -> Hero,
         @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.benefit = benefit
        self.enableLabel = enableLabel
        self.enabled = enabled
        self.howTo = howTo
        self.onToggle = onToggle
        self.hero = hero()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack { Theme.spaceGradient; hero }
                .frame(height: 180)
                .clipped()

            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.system(size: 19, weight: .bold))
                Text(benefit)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(howTo) { row($0) }
                }
                .padding(.top, 2)

                Spacer(minLength: 4)

                if let enabled, let enableLabel {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(enableLabel, isOn: enabled)
                            .toggleStyle(.switch)
                            .onChange(of: enabled.wrappedValue) { _, _ in onToggle() }
                        footer
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                } else {
                    footer
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func row(_ row: HowToRow) -> some View {
        // Keys take their natural width (a 4-key combo like ⌃⌥⌘D must never be
        // clipped into the text), and the text wraps in whatever space is left,
        // so nothing overlaps at any scale or language.
        HStack(alignment: .top, spacing: 10) {
            if let keys = row.keys {
                ShortcutCaps(keys: keys)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.tint)
                    .frame(width: 22, alignment: .leading)
                    .padding(.top, 1)
            }
            Text(row.text)
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct HowToRow: Identifiable {
    let id = UUID()
    let keys: [String]?
    let text: String
}

// MARK: - Feature steps

// MARK: - Hero illustrations

private struct HeroKey: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(minWidth: 20, minHeight: 22)
            .padding(.horizontal, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.32)))
    }
}

private struct HeroKeys: View {
    let keys: [String]
    var body: some View {
        HStack(spacing: 3) { ForEach(keys, id: \.self) { HeroKey(label: $0) } }
    }
}

/// A small window with its three title-bar buttons, the close one highlighted.
/// Drawn by hand so the buttons stay aligned in the title bar at any scale. A
/// red circle overlaid on the `macwindow` symbol used to land off in the corner.
struct QuickPanelShowcaseStep: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ShowcaseScaffold(
            title: l10n.s.launcherName,
            benefit: l10n.s.launcherCaption,
            howTo: [HowToRow(keys: GlobalShortcut.quickLauncherDefault.keyCaps, text: l10n.s.launcherOpenNow),
                    HowToRow(keys: nil, text: l10n.s.launcherKeysHint),
                    HowToRow(keys: nil, text: l10n.s.launcherEditHint)],
            hero: { QuickPanelHero() },
            footer: {
                Button {
                    QuickLauncherService.shared.show()
                } label: {
                    Label(l10n.s.launcherOpenNow, systemImage: "square.grid.2x2")
                }
                .controlSize(.small)
            }
        )
    }
}

private struct QuickPanelHero: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                chip("bolt.fill")
                chip("mic.slash.fill")
                chip("eyedropper")
                chip("doc.on.clipboard")
            }
            HeroKeys(keys: GlobalShortcut.quickLauncherDefault.keyCaps)
        }
        .foregroundStyle(.white)
    }

    private func chip(_ symbol: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.16))
                .frame(width: 38, height: 38)
            Image(systemName: symbol).font(.system(size: 16))
        }
    }
}
