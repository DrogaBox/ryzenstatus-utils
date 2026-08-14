## 2024-08-13 - [Adding Accessibility Labels to Undo/Redo Buttons]
**Learning:** Found that the Undo and Redo icon-only buttons in the screen recording and screenshot editors lacked `accessibilityLabel`s, though they had tooltips for visual users. By adding `.accessibilityLabel(l10n.s.menuUndo)` and `.accessibilityLabel(l10n.s.menuRedo)`, I've made these crucial destructive/constructive actions apparent to screen reader users, completing a critical a11y improvement.
**Action:** When creating icon-only buttons with tooltips (`screenshotSafeHelp` or similar), always ensure they have an equivalent `accessibilityLabel`.

## 2024-09-02 - [Fixing Buried Interactions with VoiceOver `.combine`]
**Learning:** When using `.accessibilityElement(children: .combine)` on a complex container containing a button, and overriding the text with `.accessibilityLabel`, the combined element is read as static text. VoiceOver users lose the `isButton` trait and any ability to trigger the nested control. Additionally, representing boolean toggles with `.accessibilityValue("1")` or `"0"` is extremely confusing for VoiceOver users.
**Action:** For clickable cards and complex rows, use `.accessibilityElement(children: .ignore)`, explicitly add `.accessibilityAddTraits(.isButton)` (and optionally `.isSelected` for toggle states), and expose the action using `.accessibilityAction { ... }`.
