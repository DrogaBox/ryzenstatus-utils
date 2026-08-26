// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// A single keyboard key drawn like a physical keycap. Used across Settings and
/// onboarding to show shortcuts such as ⌘X / ⌘V.
struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(minWidth: 20, minHeight: 22)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            )
    }
}

/// A row of keycaps for a shortcut, e.g. ["⌘", "X"].
struct ShortcutCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                KeyCap(label: key)
            }
        }
    }
}

struct FullDiskAccessNote: View {
    var compact = false
    /// Why this surface needs the permission. The scan is the usual reason;
    /// a failed removal has its own, so it says so in its own words.
    var reason: String?

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: compact ? 7 : 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(reason ?? l10n.s.uninstallerFDANote)
                    .font(compact ? .system(size: 10) : .caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(l10n.s.uninstallerFDAHint)
                .font(compact ? .system(size: 9) : .caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: compact ? 7 : 8) {
                Button(l10n.s.uninstallerFDAGrant) { permissions.requestFullDiskAccess() }
                // Shown alongside because access only takes effect on relaunch.
                Button(l10n.s.uninstallerFDARelaunch) { appDelegate()?.relaunchApp() }
            }
            .controlSize(.small)
            .font(compact ? .system(size: 10.5) : nil)
        }
        .padding(compact ? 9 : 11)
        .background(
            RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous)
                .fill(Color.primary.opacity(compact ? 0.045 : 0.05))
        )
    }
}

/// What a removal left behind, and why. Sandboxed app data lives in
/// ~/Library/Containers, which macOS keeps behind Full Disk Access; the
/// administrator prompt Finder shows covers file ownership, not that
/// permission, so those items are refused however the removal is attempted.
/// Naming them at the moment they survive is the only point where the
/// permission has visibly cost the person something.
struct UninstallFailureNote: View {
    let items: [AppUninstaller.Leftover]
    var compact = false

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared

    private static let namesShown = 4

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            Text(l10n.s.uninstallerSomeFailed)
                .font(compact ? .system(size: 10) : .caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(items.prefix(Self.namesShown)) { item in
                Text(item.name)
                    .font(compact ? .system(size: 9.5) : .caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if items.count > Self.namesShown {
                Text(String(format: l10n.s.uninstallerFailedMoreFormat,
                            items.count - Self.namesShown))
                    .font(compact ? .system(size: 9.5) : .caption2)
                    .foregroundStyle(.tertiary)
            }
            if !permissions.fullDiskAccess {
                FullDiskAccessNote(compact: compact, reason: l10n.s.uninstallerFailedNeedsFDA)
            }
        }
    }
}

/// Translucent HUD material behind floating panels (the shelf, the switcher, the
/// cut-feedback HUD). Mirrors the switcher's backdrop so every floating surface
/// matches.
///
/// The corner radius rounds the effect view's own layer, which matters for the
/// behind-window blur: SwiftUI's `.clipShape` rounds the drawn content but does
/// not clip an `NSVisualEffectView`'s behind-window material, so the blur (and
/// the borderless window's shadow, computed from it) keeps the full rectangular
/// bounds. Against a contrasty desktop that rectangle reads as a faint extra
/// outline just outside the rounded card, and whether it shows depends on what
/// is behind the window, which is why it looks intermittent. Clipping the layer
/// to the same radius as the card removes it. Pass the card's corner radius.
struct HUDBackdrop: NSViewRepresentable {
    var cornerRadius: CGFloat = 0
    var opacity: CGFloat = 1.0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSVisualEffectView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.alphaValue = opacity
    }
}
