// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// Shared look & feel: brand colors, card styling and the brand mark.
enum Theme {
    /// Near-black background behind the brand mark. Neutral greys into black, no
    /// colour cast, with just a hint of depth so the badge does not read as flat.
    static let spaceGradient = LinearGradient(
        colors: [Color(white: 0.10),
                 Color(white: 0.04),
                 Color.black],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum PanelMetricColor {
    static func green(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.00, green: 0.44, blue: 0.18) : .green
    }

    static func cyan(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.00, green: 0.43, blue: 0.54) : .cyan
    }

    static func mint(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.00, green: 0.44, blue: 0.40) : .mint
    }

    static func yellow(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.56, green: 0.36, blue: 0.00) : .yellow
    }

    static func red(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.68, green: 0.08, blue: 0.10) : .red
    }

    static func orange(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.68, green: 0.30, blue: 0.00) : .orange
    }

    static func pink(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.68, green: 0.06, blue: 0.34) : .pink
    }

    static func purple(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.58, green: 0.15, blue: 0.76) : Color(red: 0.75, green: 0.35, blue: 0.95)
    }

    static func indigo(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.28, green: 0.22, blue: 0.68) : Color(red: 0.40, green: 0.38, blue: 0.92)
    }
}

private struct NotchPresentationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var notchPresentation: Bool {
        get { self[NotchPresentationKey.self] }
        set { self[NotchPresentationKey.self] = newValue }
    }
}

enum PanelSurface {
    static func baseFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.68) : Color.black.opacity(0.42)
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.38) : Color.white.opacity(0.075)
    }

    static func controlFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.055) : Color.white.opacity(0.085)
    }

    static func border(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.09) : Color.white.opacity(0.11)
    }

    static func suiteCardFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(NSColor.controlBackgroundColor) : Color.white.opacity(0.06)
    }

    /// A control that sits ON a glass surface rather than in it: the system's
    /// own round toggles read as physical because they are lighter than what
    /// is behind them and carry their own shadow.
    static func raisedFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.88) : Color.white.opacity(0.14)
    }

    static func raisedBorder(for scheme: ColorScheme) -> Color {
        let raised = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        return scheme == .light
            ? Color.black.opacity(raised ? 0.22 : 0.07)
            : Color.white.opacity(raised ? 0.32 : 0.16)
    }

    static func raisedShadow(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.14) : Color.black.opacity(0.38)
    }

    /// The lit edge of a glass surface: bright where the light comes from,
    /// gone by the bottom. Without it a translucent panel reads as paper.
    static func rimHighlight(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(colors: [Color.white.opacity(scheme == .light ? 0.95 : 0.30),
                                Color.white.opacity(scheme == .light ? 0.12 : 0.04)],
                       startPoint: .top,
                       endPoint: .bottom)
    }
}

func sectionTitle(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .kerning(0.5)
        .foregroundStyle(.secondary)
}

extension View {
    /// The rounded card background used by every panel section. Inside the
    /// island it becomes the notch control surface; `interactive` tells that
    /// surface whether the card reacts to the pointer.
    func panelCard(interactive: Bool = true, padded: Bool = true) -> some View {
        modifier(PanelCardModifier(interactive: interactive, padded: padded))
    }

    /// The structured card container used by Performance Suite dashboard sections.
    func suiteCard(padding: CGFloat = 12) -> some View {
        modifier(SuiteCardModifier(padding: padding))
    }

    /// A restrained glass base for the menu panel: still translucent, but with a
    /// stable tint so text and controls do not depend too much on the wallpaper.
    func panelGlassSurface(cornerRadius: CGFloat = 18) -> some View {
        background(PanelGlassSurface(cornerRadius: cornerRadius))
    }
}

private struct SuiteCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PanelSurface.suiteCardFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
            )
    }
}

private struct PanelCardModifier: ViewModifier {
    var interactive: Bool
    var padded = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.notchPresentation) private var notchPresentation

    func body(content: Content) -> some View {
        if notchPresentation {
            content.padding(padded ? 12 : 0).modifier(NotchControlSurface(cornerRadius: 18, interactive: interactive))
        } else {
        content
            .padding(padded ? 10 : 0)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PanelSurface.cardFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
            )
        }
    }
}

private struct PanelGlassSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(PanelSurface.baseFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.8)
            )
    }
}

@MainActor
func appDelegate() -> AppDelegate? {
    NSApp.delegate as? AppDelegate
}

/// The official mark (Resources/Brand/logo.png, trimmed at build time),
/// tintable for light or dark surfaces.
struct BrandMark: View {
    var width: CGFloat
    var tint: Color = .white

    private static let mark: NSImage? = {
        guard let url = Bundle.main.url(forResource: "BrandMark", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if let mark = Self.mark {
            Image(nsImage: mark)
                .renderingMode(.template)
                .interpolation(.high)
                .antialiased(true)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint)
                .frame(width: width)
        } else {
            Image(systemName: "circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint)
                .frame(width: width * 0.5)
        }
    }
}

/// Squircle badge with the mark on the space gradient — the app's face in the
/// About tab and onboarding.
struct BrandBadge: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Theme.spaceGradient)
            BrandMark(width: size * 0.8)
        }
        .frame(width: size, height: size)
    }
}
