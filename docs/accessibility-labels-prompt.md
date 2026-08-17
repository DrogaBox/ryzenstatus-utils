# Accessibility audit & fix: `.accessibilityLabel()` on icon-only buttons

You are auditing the macOS menu-bar app **RyzenStatus** (Swift 6, SwiftUI).
Your task: find every **icon-only button** that has a `.help(...)` tooltip but
no `.accessibilityLabel(...)`, add the missing label following the house
pattern, and report everything you did and judged.

## Platform fact (verified, do not relitigate)

Apple's official documentation for `help(_:)` says:

> "Adding help to a view configures the view's **accessibility hint** and its
> help tag (also called a **tooltip**) in macOS or visionOS."

So `.help(...)` sets the tooltip and the accessibility *hint* — it does **not**
set the accessibility *label*. VoiceOver announces the label as the element's
identity; hints are supplementary and only spoken when hint verbosity is on.
An icon-only button with only `.help(...)` therefore has no label and VoiceOver
reads it as just "button". An explicit `.accessibilityLabel(...)` is required.

(Note: the repo's `.Jules/palette.md` was corrected to state exactly this.
Ignore any older text elsewhere that claims `.help` automatically becomes the
label — that was the misconception this pass is fixing.)

## Where to look

SwiftUI views live under `Sources/RyzenStatus/UI/` (menu panel, settings,
shelf, switcher, media, scratchpad, quick launcher, permission overlay, etc.).
The reliable way to find candidates: search for `.help(` across the sources,
then read enough surrounding context (the whole Button) to judge each case.

## House pattern to apply

Mirror the `.help(...)` string into `.accessibilityLabel(...)` immediately
after it, same indentation, same expression (including ternaries), e.g.:

```swift
.buttonStyle(.plain)
.help(isPinned ? l10n.s.dockPreviewUnpinPanel : l10n.s.dockPreviewPinPanel)
.accessibilityLabel(isPinned ? l10n.s.dockPreviewUnpinPanel : l10n.s.dockPreviewPinPanel)
```

Reference implementations already in the repo: `NowPlayingPopupView`'s
`transportButton`/`clusterButton`, `ClipboardQuickPanelView`, `PanelClipboardView`,
`ShelfView.pinButton`, `KeepAwakeIconPicker`, `CutFeedbackView`.

## Judgment rules — apply these to every candidate

**INCLUDE (fix):** buttons whose visible label is only an `Image` (or a `Label`
with `.labelStyle(.iconOnly)`), that have `.help(...)`, and lack
`.accessibilityLabel(...)`. This includes icon-only buttons whose label swaps
between symbols (e.g. `pin.fill`/`pin`, `eye.fill`/`eye.slash.fill`,
`xmark.circle`/`xmark.circle.fill`).

**EXCLUDE (do not touch):**
- Buttons with visible `Text` or a `Label` with text — SwiftUI derives the
  accessibility label from the text automatically.
- `.help(...)` on non-button views: `Text` badges/capsules with tooltips,
  `Picker`s, `Toggle`s with visible labels, drag handles (`PanelDragHandle`),
  anything already marked `.accessibilityHidden(true)`.
- Anything that already has `.accessibilityLabel(...)`, even when the label
  string deliberately differs from the help text (e.g. QuickLauncher's edit
  button labels itself "Settings" while the tooltip says "Edit items").
- `.help(...)` on elements inside context menus (menu items carry their text).

Use the existing localization pattern (`l10n.s.*`, `FeatureStrings.*(...)`,
`text.*`) — never hardcode English, never invent strings. Mirror the exact
expression already used in `.help(...)`.

## Scope

Primary: the `.help`-without-label fixes above.

Secondary (use your own judgment, report separately): icon-only buttons that
have **neither** `.help(...)` **nor** `.accessibilityLabel(...)`. For these,
decide per case: if clearly interactive, add a sensible label (localized if a
string exists, otherwise a matching `l10n`/feature-strings entry following the
repo's localization convention); if decorative or status-only, leave untouched
(or mark `.accessibilityHidden(true)` only when that is clearly correct). Do
not add labels to non-interactive status glyphs — a label on a decorative icon
is worse than no label.

## Constraints

- Make the fewest changes that address the request. No reformatting, no
  reordering, no refactors, no touching SPDX headers or unrelated code.
- Only SwiftUI `View` files in `Sources/RyzenStatus/UI/` (and anywhere else a
  match is found) — no service/core changes.
- Verify your work: run the project build (`./build.sh` or `swift build` per
  the repo's build script) and `./build.sh --test`, and report the results.

## Deliverables

1. **Findings list** — every icon-only button with `.help(...)` missing
   `.accessibilityLabel(...)`: file + line, the button, the exact string you
   mirrored. This is the primary result; it must be complete.
2. **Applied diffs** — summary of files touched and count of labels added.
3. **Secondary pass** — icon-only buttons found with no `.help` and no label,
   with your per-case decision (fixed / left, and why).
4. **Checked-and-correct list** — spots you verified already have labels or
   correctly don't need them (especially the previously-covered areas:
   NowPlaying popup + track content, ClipboardQuickPanelView, PanelClipboardView,
   FansSettingsView, FanCurveEditor, ProcessUsageRow, KeepAwakeIconPicker,
   WindowGestureControls, SwitcherView + DockPreviewPanelView, QuickLauncherView,
   ScratchpadView, CutFeedbackView, BrightnessSection's DisplayPowerButton,
   PanelLayout's PanelInlineHideButton, MonitorSettings metric toggles,
   WindowLayoutSettings shortcut-clear, DockPreviewIntroView, AppUpdatesListView).
5. **Build results** — output summary of the build and `./build.sh --test`.

A prior manual pass found roughly two dozen spots across ~14 files — your audit
should independently confirm that count and report anything it missed or any
false positive you rejected, with reasoning. Your judgment wins over this hint;
it exists only as a cross-check.
