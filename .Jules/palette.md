## 2024-08-19 - Accessible Tooltips with Shortcuts
**Learning:** Pairing `.screenshotSafeHelp("Label  (Shortcut)")` with `.accessibilityLabel("Label")` provides a good UX balance: visual users see both the action name and the keyboard shortcut in the tooltip, while VoiceOver users only hear the action name, preventing the redundant reading of the shortcut in the accessible label.
**Action:** Use this pattern for icon-only buttons that have keyboard shortcuts, ensuring they are both discoverable visually and accessible cleanly.
