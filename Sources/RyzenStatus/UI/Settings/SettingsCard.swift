// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

// The card-style building blocks the Dynamic Island page is drawn with. The
// rest of this fork's Settings pages are grouped Forms; the island's page lays
// out its own tabs, editor and previews, so it keeps the cards it was designed
// with. Only the pieces that page uses are here.

/// One rounded group of related controls, with an optional heading.
struct SettingsCard<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let title {
                Text(title).font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Where a row's text column starts, so follow-up controls can line up with it.
let settingsRowTextInset: CGFloat = 26 + 12

/// Icon, title, one line of explanation and the control on the right. A nil
/// symbol shows a generic menu bar glyph.
struct SettingsRow<Accessory: View>: View {
    let symbol: String?
    let title: String
    let badge: String?
    let caption: String?
    let accessory: Accessory

    init(symbol: String?, title: String, badge: String? = nil, caption: String? = nil,
         @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.title = title
        self.badge = badge
        self.caption = caption
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol ?? "menubar.rectangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor))
                            .accessibilityHidden(true)
                    }
                }
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
    }
}

/// A switch for an option that needs another feature. While it cannot be
/// used, its feature uninstalled or something else ruling it out, the option
/// reads greyed and off, since a disabled switch looks like one that is just
/// off, and a readable line under it says why.
struct SettingsFeatureSwitchRow: View {
    let symbol: String
    let title: String
    var caption: String? = nil
    @Binding var isOn: Bool
    let feature: AppFeature
    /// False while something else rules the option out, as the caption says.
    var enabled = true
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared

    var body: some View {
        let installed = features.isAvailable(feature)
        let usable = installed && enabled
        VStack(alignment: .leading, spacing: 6) {
            SettingsRow(symbol: symbol, title: title, caption: usable ? caption : nil) {
                Toggle(title, isOn: usable ? $isOn : .constant(false)).labelsHidden().toggleStyle(.switch)
            }
            .disabled(!usable)
            .saturation(usable ? 1 : 0)
            .opacity(usable ? 1 : 0.45)
            if !installed {
                HStack(spacing: 10) {
                    Text(feature.enableReason(l10n))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(FeatureStrings.notchEditor(l10n.language).openFeatures) { feature.showInFeatures() }
                        .controlSize(.small)
                }
                .padding(.leading, settingsRowTextInset)
            } else if !usable, let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, settingsRowTextInset)
            }
        }
    }
}

/// A row that picks one of a few options: segments beside the title while the
/// row fits on one line, under the title otherwise, and a menu there when the
/// segments don't fit either. A row wider than its column would center the page
/// and cut it on both sides.
struct SettingsChoiceRow<Value: Hashable, Options: View>: View {
    let symbol: String?
    let title: String
    @Binding var selection: Value
    let options: Options

    init(symbol: String?, title: String, selection: Binding<Value>, @ViewBuilder options: () -> Options) {
        self.symbol = symbol
        self.title = title
        _selection = selection
        self.options = options()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            SettingsRow(symbol: symbol, title: title) {
                picker.pickerStyle(.segmented).fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(symbol: symbol, title: title) { EmptyView() }
                ViewThatFits(in: .horizontal) {
                    picker.pickerStyle(.segmented).fixedSize()
                    picker.pickerStyle(.menu).fixedSize()
                }
                .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private var picker: some View {
        Picker(title, selection: $selection) { options }.labelsHidden()
    }
}

/// A switch pushed to the trailing edge with its label at the leading one,
/// so a shared control that carries its own label lines up with the rows
/// around it on a card page.
struct TrailingSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 12)
            Toggle(isOn: configuration.$isOn) { EmptyView() }
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

extension AppFeature {
    /// Why an option that needs this feature cannot be used: it is
    /// uninstalled in the Features hub.
    func enableReason(_ l10n: L10n) -> String {
        FeatureStrings.notchEditor(l10n.language).enableFeature(hubTitle(l10n.s, hub: FeatureStrings.hub(l10n.language)))
    }

    /// Features, for an option that needs this feature. The hub here has no
    /// per-row anchor, so the page itself is the destination.
    @MainActor
    func showInFeatures() {
        SettingsRouter.shared.page = .features
    }
}
