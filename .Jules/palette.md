## 2024-05-18 - SwiftUI `.help()` and `.accessibilityLabel()`

**Learning:** In SwiftUI for macOS/iOS, the `.help()` modifier automatically sets the accessibility label for screen readers. Explicitly pairing `.help()` with an identical `.accessibilityLabel()` on icon-only buttons is redundant. Although previous memory mentioned adding it, code review indicated that `.help()` already handles VoiceOver on newer OS versions (macOS 11+ / iOS 14+), making explicit mirroring unnecessary.

**Action:** When adding accessibility to icon-only buttons in SwiftUI, simply using `.help()` with a localized string is sufficient for both tooltips and VoiceOver. Only use `.accessibilityLabel()` if the VoiceOver announcement needs to be distinctly different from the visual tooltip.
