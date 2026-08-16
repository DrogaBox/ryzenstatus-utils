## 2024-05-24 - Accessibility labels on SwiftUI Icon Buttons
**Learning:** In SwiftUI (macOS 11+ / iOS 14+), the `.help(...)` modifier automatically generates and acts as the accessibility label for VoiceOver if an explicit `.accessibilityLabel(...)` is not provided. Duplicating the string into an explicit accessibility label modifier provides zero actual accessibility benefit and is entirely redundant.
**Action:** Avoid blindly pairing `.help` with `.accessibilityLabel` in modern SwiftUI apps unless the screen reader needs a distinctly different explanation than the visual tooltip.
