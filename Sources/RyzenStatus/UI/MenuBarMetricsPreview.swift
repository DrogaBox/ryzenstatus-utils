// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// A live miniature of the menu bar corner. It shows the very images the
/// status item draws, rendered by `MenuBarRenderer` for a light or dark menu
/// bar that follows the window, so a choice in Settings shows its real cost
/// before it occupies the actual menu bar.
struct MenuBarMetricsPreview: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @StateObject private var model = MenuBarPreviewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var settings = model.settings
        settings.appearanceName = appearance.name.rawValue
        let rendered = MenuBarRenderer.render(for: monitor.snapshot,
                                              metrics: model.metrics,
                                              settings: settings,
                                              widthMemory: model.widthMemory)
        let ink: Color = dark ? .white : .black

        return HStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(systemName: "wifi")
                .foregroundStyle(ink.opacity(0.85))
            if PowerSampler.hasInternalBattery {
                Image(systemName: "battery.75percent")
                    .foregroundStyle(ink.opacity(0.85))
            }
            HStack(spacing: 4) {
                glyph(ink)
                    .frame(width: BlackHoleGlyph.pointSize.width,
                           height: BlackHoleGlyph.pointSize.height)
                if rendered.string.length > 0 {
                    MenuBarTitleStrip(title: rendered.string, appearance: appearance)
                        .fixedSize()
                }
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(dark ? Color(white: 0.16) : Color(white: 0.9))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rendered.string.string)
    }

    private func glyph(_ ink: Color) -> some View {
        Group {
            if let image = BlackHoleGlyph.image(active: true) {
                Image(nsImage: image).renderingMode(.template)
            } else {
                Image(systemName: "circle.fill")
            }
        }
        .foregroundStyle(ink)
    }
}

/// Re-reads the menu bar preferences when any default changes, and publishes
/// only when something the renderer uses actually changed.
@MainActor
private final class MenuBarPreviewModel: ObservableObject {
    @Published private(set) var settings = MenuBarRenderSettings.current()
    @Published private(set) var metrics = MenuBarMetric.enabled(in: .standard)
    /// The preview's own width memory: a reading it shows never widens a
    /// block in the real menu bar.
    let widthMemory = MenuBarWidthMemory()
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                          object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func reload() {
        let newSettings = MenuBarRenderSettings.current()
        if newSettings != settings { settings = newSettings }
        let newMetrics = MenuBarMetric.enabled(in: .standard)
        if newMetrics != metrics { metrics = newMetrics }
    }
}

/// The rendered title in an AppKit label with a fixed appearance, so the
/// block images and dynamic colors resolve exactly as in the status item.
private struct MenuBarTitleStrip: NSViewRepresentable {
    let title: NSAttributedString
    let appearance: NSAppearance

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byClipping
        field.setAccessibilityElement(false)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.appearance = appearance
        let full = NSMutableAttributedString(attributedString: title)
        full.addAttribute(.font, value: MenuBarRenderer.statusFont(),
                          range: NSRange(location: 0, length: full.length))
        field.attributedStringValue = full
    }
}
