# RyzenStatus — NowPlaying hardening: leak audit, ultra review, keyboard accessibility, unit tests

You are working on **RyzenStatus**, a macOS menu-bar app (Swift 6, SwiftUI, macOS floor 14 — see Package.swift). This is one combined work order with five phases. **Do the phases in order.** Each phase ends with a report section; your final reply contains all phase reports.

## Ground rules (verify against the repo — line numbers drift)

- The repo is the source of truth, not this brief. Read files before editing.
- Preserve existing style: SPDX GPL headers, `///` doc comments, house patterns.
- Do NOT commit anything. Leave all changes uncommitted for human review.
- Do NOT touch, revert, or reformat the **19 already-modified files** from the previous accessibility pass (Core/Localization.swift, all of Core/Localizations/, UI/Cleaner/CleanerView.swift, UI/MenuPanel/ClipboardQuickPanelView.swift, UI/MenuPanel/MenuPanelView.swift, UI/MenuPanel/MixerSection.swift, UI/MenuPanel/PanelUninstallerView.swift, UI/MenuPanel/ProcessDetailSheet.swift, UI/Uninstall/UninstallerView.swift). That work is already verified; your changes must not conflict with it.
- If a fix is user-visible, add a CHANGELOG.md entry following its style. Otherwise don't.
- Do not invent localization strings: new user-facing copy must be added to the `Strings` memberwise-init contract in all 13 languages (pt-BR + en-US live in Core/Localization.swift; the other 12 in Core/Localizations/Strings+<Language>.swift). A missing key breaks compilation.

## Build discipline (critical)

`./build.sh --test` starts with `rm -rf build`, so it destroys any concurrent app build. **Never run `./build.sh` and `./build.sh --test` at the same time.** Run them sequentially (tests first), and only after a phase that changed code. Exactly one build process at a time, ever.

## Verified facts — do not relitigate

These were confirmed against the SDK/repo by a prior audit; treat them as correct unless you find hard evidence otherwise:

- MediaRemote raw command values: next = 4, prev = 5, seek = 20 (NowPlayingSupport.swift).
- `MRMediaRemoteSendCommand` takes 2 args (no queue argument exists in that API).
- CF "Get"-function ownership rule: `MRMediaRemoteGetNowPlayingInfo` returns +0, so the code uses `takeUnretainedValue()` (documented in a comment).
- macOS 15.4+ blocks the private MediaRemote read API; the code detects this (`readsBlockedBySystem`) and falls back to AppleScript via NowPlayingAutomation. That fallback is intentional.
- The snapshot's `==` compares artwork by identity proxy (byte count + first 64 bytes) — intentional, not a bug.
- `appNameCache` resolves `NSRunningApplication` off the main thread and is invalidated via NSWorkspace notifications — intentional.
- The `pollGeneration` guard in NowPlayingService is the house pattern for dropping stale poll completions — keep it.

## Repo layout (anchors; locate fresh)

- Services: Sources/RyzenStatus/Services/NowPlaying/{NowPlayingService, NowPlayingSupport, NowPlayingTheme, NowPlayingAnimatedArtwork, NowPlayingLyricsCenter, NowPlayingLyricsSupport, NowPlayingPopupController, NowPlayingAutomation}.swift
- UI: Sources/RyzenStatus/UI/NowPlaying/{NowPlayingSection, NowPlayingTrackContent, NowPlayingPopupView}.swift; settings in UI/Settings/NowPlayingSettings.swift; strings in Core/NowPlayingStrings.swift; defaults + migration in Core/Defaults.swift / DefaultsKey+App.swift.
- Test harness: `./build.sh --test` compiles a Foundation-only set (already includes NowPlayingSupport, NowPlayingAutomation, NowPlayingLyricsSupport, NowPlayingTheme, NowPlayingAnimatedArtwork, NowPlayingStrings, Defaults, DefaultsKey+App) with Tests/MetricsTests.swift as the runner. No XCTest, no AppKit in the harness.

## Phase 1 — Leak & retain-cycle audit (read-only)

Audit the whole NowPlaying stack for memory issues. Inventory and verify every:

- Timer: `marqueeTimer` (20 Hz state machine in NowPlayingService: `MarqueePhase`, `updateMarquee`, `stopMarquee`), the popup morph timer (~120 Hz solver), any others. Confirm each is invalidated on every exit path (stop, disable, deinit, track change) and not leaked by retain cycles.
- Observer registrations: NSWorkspace (didLaunch/didTerminateApplication), NSNotificationCenter (now-playing info, app termination), DistributedNotificationCenter, KVO. Confirm removeObserver on every deregistration path.
- AVPlayer / AVPlayerItem / time observers in NowPlayingAnimatedArtwork (keyless pipeline: iTunes Search API → album-page scrape → HLS variant → AVPlayer crossfade). Check for retain cycles (player ↔ delegate closures), observer teardown on track change / disable / deinit, and playback-session cleanup.
- Network tasks (URLSession data tasks, async tasks): cancellation on teardown, no completion-after-deinit.
- Closures capturing self strongly where weak is required; @escaping closures; DispatchQueue hops (service queue → main) that can outlive stop() — the pollGeneration guard exists for this; verify every other async path has an equivalent guard.
- Any dlopen/dlsym/CF/IOKit handles that must be released (house precedent: a mach_host_self() port leak was fixed elsewhere).

Report: prioritized findings with severity, evidence (file + symbol + why it leaks), and for each a verdict — CONFIRMED (fix in Phase 3) or UNCONFIRMED (needs empirical check like MallocStackLogging; do NOT fix, just report). Do not fix anything in this phase.

## Phase 2 — Ultra review: completeness / correctness / impact (read-only)

Review the NowPlaying feature as a whole (the 8 service files + 3 UI files + settings + strings + defaults migration) against the original audit's deliverable checklist:

- The prioritized findings list (critical/high/medium/low) — is every one actually addressed in the code?
- The manual QA checklist (~15 scenarios: enable/disable live toggle, ghost-track-after-disable, provider pinning, mode/progress applied instantly, dark/light + forced appearance, long-title truncation, paused vs idle, track change mid-seek, live-radio slider disabled, artwork on/off, source-app jump, legacy-key migration on upgrade, zero idle cost, VoiceOver label, app launched while already playing) — for each, confirm from the code that it works, or flag the gap.
- The "verified correct" list — confirm nothing regressed.

Output: a gap list (CONFIRMED gaps only) — anything the checklist says should work but the code doesn't deliver, with evidence. No fixes in this phase.

## Phase 3 — Fix confirmed findings from Phases 1 and 2

Implement fixes ONLY for CONFIRMED findings. Rules: minimal diffs; house patterns; add `///` doc comments explaining the *why* (this repo's standard); no refactors beyond the fix; if a fix changes user-visible behavior, call it out in the report. Leave UNCONFIRMED items out of the code.

## Phase 4 — Keyboard & focus accessibility pass

Extend the accessibility work (labels already done in two passes) to keyboard navigation and focus:

- Menu panel (UI/MenuPanel/MenuPanelView.swift and its sections): Escape closes; obvious focus gaps; sensible tab order; any icon-only button that should have a keyboard shortcut.
- NowPlaying popup (UI/NowPlaying/NowPlayingPopupView.swift): transport buttons (play/pause, prev, next, shuffle, repeat) get keyboardShortcut where they don't conflict; slider keyboard-accessible; Escape closes. NOTE: the popup is a nonactivating NSPanel — verify whether it can become key; if full keyboard access can't work there without changing the panel's activation policy, report that as a finding instead of breaking the nonactivating behavior.
- Sheets (ProcessDetailSheet, UninstallerView, CleanerView, and other detached sheets): verify Escape-to-cancel already works via the system; add `.keyboardShortcut(.cancelAction)` / `.defaultAction` only where the system doesn't already provide it.
- Status item button: no new shortcut (menu bar), but verify the accessibility label from the previous pass is intact.
- Do not add shortcuts that collide with global/system shortcuts. When in doubt, report instead of changing.

## Phase 5 — Unit tests for the pure logic

Extend the existing harness (Tests/MetricsTests.swift + the file list in build.sh). No new test infrastructure, no XCTest, no AppKit in the harness — follow the existing `check(...)`/counter style. Cover:

- LRC parser (NowPlayingLyricsSupport.swift): timestamp formats (mm:ss.xx, [mm:ss], multi-line tags), sorted lines, malformed input, scoring (if present), edge cases (empty, metadata-only, out-of-order timestamps).
- Artwork identity proxy: snapshot equality (same artwork data → equal; changed first 64 bytes → different; same prefix/different tail → equal) and the fingerprint memoization.
- Progress quantization used in the render cache key (verify the exact expression — likely `Int(progress * 100)` — and test its boundaries).
- Marquee state machine: it lives inside NowPlayingService (not in the harness). Extract the pure state logic into a Foundation-only type (e.g., a MarqueePhase machine) that the service uses, add it to build.sh's file list, and test slide-in → hold → scroll → loop transitions, overflow vs. no-overflow, and teardown. Keep the extraction minimal and behavior-identical.
- Defaults migration v6 (`migrateLegacyNowPlayingMenuBarMode` in Core/Defaults.swift — already in the harness): test the legacy-key → iconOnly migration with a `UserDefaults(suiteName:)` suite — idempotent, and the "explicitly set" flag behavior. Follow the existing Defaults tests' style.

Each new test must run green in `./build.sh --test` (report the new total check count). If a target can't be exercised Foundation-only, leave it out and say why.

## Final report format

Sections, in order: Phase 1 findings (with severity + CONFIRMED/UNCONFIRMED) · Phase 2 gap list · Phase 3 fixes applied (files + line counts) · Phase 4 changes and any panel-keyboard finding · Phase 5 tests added + new total checks · Build results (test then app, sequential, one at a time) · Anything you deliberately rejected and why. Keep it factual; no fluff.
