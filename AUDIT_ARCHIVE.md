# RyzenStatus — Full Codebase Audit

**Repository:** https://github.com/DrogaBox/ryzenstatus-utils
**Audit date:** 2026-08-28 · **Revision audited:** `491461f` (v1.15.1)
**Scope:** entire repository — Swift app (`Sources/`, ~155K LOC), kernel extension (`SMCAMDProcessor_Source/`, ~9K LOC C++), build/tooling scripts, tests.
**Method:** six parallel deep-audit tracks (app/core, monitor+metrics+AMD, capture stack, file-ops/security, input/event-taps, UI+kext), line-level review of every module with ±30-line verification of each candidate finding; live API probes where behavior depended on external services (iTunes Lookup API). False positives were chased down and discarded — a list is kept at the end of this report.
**Deliverables:** this report (`AUDIT.md`), 40 applied patches (`audit-fixes.patch`, already merged into the working tree), and a phased remediation plan.

---

## 1. Executive Summary

RyzenStatus is an unusually well-engineered macOS menu-bar utility for its size. The codebase consistently shows defense-in-depth on destructive operations, disciplined IOKit object hygiene, generation-token race protection, a compiler-checked localization contract across 12 languages, and issue-number-annotated comments that document *why* each subtle constant exists. No force-unwrap/`try!`/`as!` crash farms were found anywhere in the app; the classic multi-display math traps (CG vs NS origins, retina scale, flipped rects) check out everywhere they were traced.

The defects that remain fall into a small number of recurring patterns:

1. **Designed-but-unwired safety mechanisms.** Several complete, correct fixes exist as dead code while the bug they solve still ships: the audio wedged-engine watchdog (`engineRenderVerdict`), the `BoostLimiter` (issue #326 crackle still present), the switcher middle-click containment helpers, the smooth-scroll carry helpers, the menu-bar grace window, and the clipboard ignored-apps list. This is the most dangerous category: dead "safety" code looks like a fix.
2. **One hard kext/app interface mismatch.** Selector 103 (GPU temp injection) encodes a float bit-pattern on the app side but converts by value in the kext, so every GPU-sourced fan curve evaluated against a constant 120 °C — fans pinned at max. **(patched)**
3. **Kernel-surface hardening gaps.** Selector 100 disclosed ~128 bytes of uninitialized kernel heap to unprivileged callers; selectors 90/98 allowed unprivileged SuperIO port I/O and a firmware-lock write; `pmRyzen_doPState_reset` could index out of bounds on >64-CPU systems; `AMDGPUDevice` had a refcount bug and an unretained `IOPCIDevice`. **(all patched)**
4. **Main-thread compute in UI hot paths.** The recorder's composer plan rebuild, full-res PNG encodes on preview Save/Copy, a 1 Hz full-Form re-render on the AMD settings page, and AX enumeration riding inside the keyboard-holding ⌘Tab tap.
5. **Two silently broken features.** The Mac App Store update source returned results for only the first bundle ID per request (~95 % of apps never checked — verified live), and the clipboard "ignored apps" list was never consulted by the capture pipeline. **(both patched)**

**Totals:** **190 findings** — 1 Blocking, 31 Major, 74 Minor, 58 Suggestion, 26 Info. **40 fixes are already applied** in this tree (Section 4); the remaining Majors carry concrete fix plans (Section 5).

| Severity | Count | Meaning |
|---|---|---|
| **Blocking** | 1 | Actively harmful in normal use; fix before any release |
| **Major** | 31 | Real user-visible defect, security gap, or hang/leak risk |
| **Minor** | 74 | Incorrect behavior in edge cases, small leaks, i18n gaps |
| **Suggestion** | 58 | Robustness, testability, and API-hygiene improvements |
| **Info** | 26 | Verified-OK notes, docs, and observations — no action required |

**Top 10 must-know items:**

| # | ID | Summary | Sev | Status |
|---|---|---|---|---|
| 1 | B-01 | GPU temp injection float encoding mismatch → GPU fan curves pinned at max PWM | Blocking | **PATCHED** |
| 2 | F-01 | Kext selector 100 leaks ~128 B of kernel heap, unprivileged trigger | Major | **PATCHED** |
| 3 | D-12 | App Store update source checks ~1 in 20 apps (batched lookup broken, verified live) | Major | **PATCHED** |
| 4 | D-15 | Clipboard "ignored apps" list never wired into capture (privacy promise unkept) | Major | **PATCHED** |
| 5 | E-01 | Audio mixer wedged-engine watchdog exists but is dead code → app stays silent after wake | Major | planned |
| 6 | E-02 | BoostLimiter never connected → >100 % boost hard-clips (issue #326 still ships) | Major | planned |
| 7 | F-03/F-04 | Kext selectors 90/98 perform port I/O / firmware-lock writes without privilege gating | Major | **PATCHED** |
| 8 | D-18 | Snippet expansion reads pasteboard on the event-tap thread → system-wide input freeze behind password prompts | Major | **PATCHED** |
| 9 | D-16 | Clipboard history JSON + images written 0644, bypassing PrivateFileStore | Major | **PATCHED** |
| 10 | E-03 | Minimize-restore pulse storm: ~150 main-thread AX round-trips per minimize | Major | **PATCHED** |

---

## 2. Findings by Severity

### 2.1 Blocking

- **B-01 — GPU temperature injection (selector 103) sends an IEEE-754 bit pattern; kext converts by value.**
  `Services/AMD/ProcessorModel.swift:1445` vs `AMDRyzenCPUPMUserClient.cpp` case 103.
  55.0 °C as bit pattern = 0x425C0000 = 1,114,112,000; the kext does `float t = (float)scalarInput[0]` → 1.1e9 → clamps to 120.0 °C. Every `FanCurveController` curve with a GPU source evaluated against a constant 120 °C: fans pinned at max PWM, silently, with no error returned. *Fix:* send `UInt64(clamped)` (value, not `bitPattern`). **PATCHED**, with a comment requiring app/kext to stay in sync and a round-trip unit test recommended once both sides ship.

### 2.2 Major (31)

App/Core: **A-01** GPU alert toggles dead when only GPU alerts enabled (`monitorAlertPairs` missing GPU entries → sink stopped). **PATCHED**
**A-02** Separate-menu-bar-items mode silently drops CPU/GPU power, frequency and temp+power metrics (`metricStatusGroups` folds them into a group that only renders CPU+temp). Planned — see §5.
**A-03** Menu-bar grace window machinery fully implemented but never wired: every transient nil reading removed and reinstalled the status item, forcing full bar re-layout + placement-default writes per tick. **PATCHED**
**A-04** Release-version gate constants (3.x) inconsistent with the shipping 1.15.1 scheme across `Defaults.swift`, `AppDelegate.swift`, `UpdateShowcaseMedia.swift` — all "what's new" intro flows depend on which scheme ships. Planned — see §5.

Monitor/AMD: **B-02** `AutoEppService`/`C6ResidencyService` state mutated from detached tasks and MainActor without synchronization; a stale EPP write can clobber Gaming Mode's Extreme preset.
**B-03** GPU fan RPM reported as 0 whenever GPU temp < 50 °C — a fabricated reading for every card idling below 50. **PATCHED**
**B-04** Per-process GPU breakdown mis-scales `IOAccelerator` utilization (≤1.0 treated as fraction) and uses a stale sample timestamp for WindowServer attribution.
**B-05** `gpuTimePerPid()` serializes *every* registry property of every IOAccelerator user client into dictionaries up to 1×/s (plus full AppleSmartBattery dict per power tick) — hundreds of allocations/second; switch to `IORegistryEntryCreateCFProperty` targeted reads.
**B-06** `Shell.run` has no timeout (the diskutil/nettop paths got BUG-06/13 fixes; this one didn't) — one hung `ps` permanently freezes the CPU/memory process lists.

Capture: **C-01** `RecorderComposer.makePlan` (whole-recording resample + zero-phase filtfilt + spring sweeps) built on the main actor per preview rebuild — 0.5–2 s UI freezes mid-drag on long takes. One-task change; see §5.
**C-02** Preview Save/Copy PNG-encode full-res captures on the main thread (~0.5–2 s hard freeze on 5K captures).
**C-04** `RecorderWriter` silently drops audio samples under backpressure → audible gaps + desync for the rest of the take.
**C-08** Pointer/typing track timebase offset from the writer zero by capture spin-up latency → cursor lands a frame behind.

FileOps/Security: **D-01** Scheduled auto-clean performs unattended destructive cleanup, including launchd-plist removal that can pop an admin prompt at 3 AM and caches of running apps.
**D-10** Self-updater accepts ad-hoc signatures — the verification gate is forgeable for ad-hoc releases; no checksum pinning.
**D-12** iTunes `bundleId=` comma batching returns only the first result — 19 of every 20 MAS apps never checked (verified live). **PATCHED** (one request per bundle ID)
**D-15** Clipboard ignored-apps feature completely unwired — copies from listed apps still recorded. **PATCHED**
**D-16** Clipboard history JSON + image PNGs bypass `PrivateFileStore`, world-readable on multi-user Macs. **PATCHED**
**D-18** Snippet `{{clipboard}}` read on the tap thread; a wedged pasteboard server freezes all input. **PATCHED** (needsClipboard gate + shared pasteboard lane)
**D-25** URL cleaner round-trips the query through decoded `queryItems`, corrupting `%2B`/`+` semantics (`q=C%2B%2B` → `q=C++` → "C C" server-side) — and the clipboard auto-clean wrote the corrupted URL back. **PATCHED** (splice `percentEncodedQuery`)

Input/Audio: **E-01** Wedged-engine watchdog dead code — audio stays muted after wake until restart. See §5.
**E-02** BoostLimiter dead code — >100 % boost hard-clips. See §5.
**E-03** ~150-queue-deep main-thread AX pulse ladder per minimize. **PATCHED** (9-probe back-off ladder)
**E-04** Switcher AX enumeration (5 s budget) runs inside the keyboard-holding ⌘Tab tap; Dock pinned panels re-run it every 0.75 s on main.
**E-05** DockClick runs unbounded AX work inside the active tap on mouse-down (budget is per-call, not per-event).
**E-06** Switcher middle-click closed the highlighted window regardless of pointer position; containment helpers existed unused. **PATCHED**

UI/Kext: **F-01** Selector-100 packet zero-fill missing — kernel heap disclosure. **PATCHED**
**F-02** `pmRyzen_doPState_reset` OOB on >64 CPUs. **PATCHED**
**F-03** Selector 90 cleared the NCT67XX firmware I/O-space lock unprivileged. **PATCHED** (privilege-threaded `allowUnlock`; read-only probe preserved)
**F-04** Selector 98 raw SuperIO register read unprivileged. **PATCHED**
**F-05** GPU power polling stalls the shared IOWorkLoop up to ~1 s/sample and runs inside any process's SMC read (`RGPUPowerValue::readAccess`).
**F-06** `AMDGPUDevice` extra retain leaks the object; `IOPCIDevice*` stored unretained → UAF on GPU rebind. **PATCHED**
**F-07** User client keeps `fOwningTask`/`proc` references it doesn't own; no `clientClose`.
**F-08** PStateDef write selector bypassed the per-CPU capability profile. **PATCHED**
**F-17** AMD settings Form re-renders entirely at 1 Hz (`@ObservedObject SystemMonitor.shared` at the page root; ~1,050-line body).

### 2.3 Minor (74) — grouped

App: A-05 (main status item not removed in `deinit`) **PATCHED** · A-06 (detach `willClose` observer tokens leak per cycle) **PATCHED** · A-07 (`markSupportUpdateIntroSeenIfCurrentUpdate` missing version guard) **PATCHED** · A-08 (hardcoded English tooltips: "CPU Temp + Power (2-Line)", countdown "min") · A-13 (uninstall.sh misses `Application Support` private data) **PATCHED** · A-14 (pt-PT → pt-BR collapse) · A-10/A-11 (build.sh mktemp leak; make_app.sh missing entitlements/resources) **PATCHED both** · A-22 (x86_64 pin undocumented; `--install` re-signs twice).

Monitor/AMD: B-07 (TelemetryLogger buffers forever after write error; colons in CSV names; no rotation) · B-08 (stale WindowServer PID cache) **PATCHED** · B-09 (C6 one bogus sample after wake; fixed by B-02's sync) · B-10 (NetworkScanner never prunes vanished interfaces) **PATCHED** · B-11 (SMC connection never retried after first failure) · B-12 (per-core logical↔physical mapping convention mismatch app↔kext packet) · B-13 (10 P-state clocks requested, kext returns 8) · B-14 (stale GPU capabilities on count→0) · B-15 (SMC dump UUID churn breaks list identity) **PATCHED** · B-16 (VRAM cadence coupled to memory policy) · B-17 (fallback hardcodes 16 physical cores / `processorCount/2`) · B-18 (SpeedTest allocates 100 MB upload buffer) · B-22 (sync IOKit walk inside IOAcceleratorCache actor) · B-23 (MaxCapacityProbe latches `running` forever on hung system_profiler) · B-24 (SMC writeValue Bool variant skips length check) **PATCHED** · B-25 (kext watchdog detects reloaded kext but never reconnects) · B-27 (PeripheralBatterySampler undrained 64 KB pipe → truncated JSON) · B-30 (fan curves re-uploaded + privilege-error spam per refresh) · B-31 (Gaming Mode hides icon before privilege verdict).

Capture: C-03 (trim drags flood undo stack + sync `edit.json` write per mouse-move) · C-05 (lastVideoSample pins a pool pixel buffer) · C-06 (capture engine state mutated from three threads) · C-07 (`start()` failure abandons half-configured SCStream) · C-09 (double-press during 120 ms start window → confusing "failed" HUD) · C-10 (cursor pixel capture + FNV hash under the sampler lock) · C-11 (GIF export declares N frames, writes fewer) · C-12/C-15 (composition audio insert failures silently swallowed → holes/desync) · C-13 (mic input device never follows default-device change mid-recording) · C-14 (click-ring sprite re-rasterized per frame; cache thrash at 64 entries) · C-16 (screenshot editor undo stack: up to 60 full-res CGImages ×2) · C-17 ("open last capture" decodes full-res PNG on main) · C-18 (drag-out PNG encoded synchronously) · C-19 (display scale fallback `?? 2` mis-crops on mixed-scale setups when NSScreen momentarily missing) · C-21 (failed mic-mute gives no feedback) · C-22 (pinned captures retain full-res images, uncapped) · C-23 (MediaService convertVideo leaves partial output on cancel) · C-24 (MediaService semaphore waits uncancellable) · C-25 (avconvert progress is a wall-clock guess) · C-26 (WhatsApp counter conflates replaced files with failures) · C-27 (ImageThumbnailer sync path on hot callers).

FileOps: D-02 ("Empty Trash" wipes items added after scan) · D-03 (AppUninstaller terminate() never awaited before Finder delete) · D-04 (SelfUninstall silently relaunches after cancelled admin prompt) · D-06 (`brew search` treats `-`-leading query as flags) **PATCHED** · D-07 (sudoers dir chmod 0755 reset + duplicate legacy path) **PATCHED** · D-08 (unbounded waits for pmset/tccutil) · D-11 (legacy-signed releases can never self-update) · D-13 (first-DMG asset picked; unauthenticated API on hourly timer) · D-19 (synthetic keystroke chunks split surrogate pairs) **PATCHED** · D-21 (Shelf drop reads pasteboard + encodes PNG on main; no NSFilePromiseReceiver) · D-22 (Shelf index persisted as one JSON blob in UserDefaults — up to ~40 MB plist rewrites) · D-23 (batch tile drag offers only first leaf) · D-24 (orphaned shelf payload files swept only at launch) · D-28 (AutoQuit re-parses every running app's bundle per check) · D-29 (Homebrew streaming log drops UTF-8 chunks split across pipe reads) **PATCHED** · D-30 (startUpgrade leaks its observer when Homebrew busy; silent no-op click).

Input: E-08 (per-pinned-panel private WindowPreviewProvider — N×64 MB caches) · E-09 (scroll inversion loses fixed-point deltas on high-res wheels) **PATCHED** · E-10 (smooth-scroll glide drops fractional pixels; carry helpers unused) · E-11 (inconsistent synthetic modifier handling across three services) · E-12 (MiddleClick lost-release timeout leaves target app's middle button stuck) **PATCHED** · E-13 (Carbon handlers never removed) · E-14 (WindowLayout AX writes inside drag tap) · E-16 (switcher tap creation failure silent) · E-17 (quit removes windows before termination confirmed) · E-18 (mixer reconcile skipped when list unchanged) **PATCHED** · E-19 (NowPlaying AppleScript polling every 2 s) · E-20 (animated-artwork semaphore chain on serial queue) · E-21 (preview warming does full AX enumeration per activation) · E-25 (menuBarScreenTopY recomputed per mouse-move) · E-26 (pinned panel re-renders on frame-only diffs).

UI/Kext: F-09 (P-state takeover runs in telemetry-only mode) · F-10 (EfiRuntimeServices instance never released) **PATCHED** · F-11 (SuperIO failure paths leave config port open) **PATCHED** · F-12 (structureOutputSize inflated beyond caller buffer, 27 sites) **PATCHED** · F-13 (ccdTemperatures lock-domain mix) · F-14 (kernel resolver hardcoded base; wrong "unsafe wrmsr" log) · F-15 (SMC mailbox no arbitration with native AMD driver) · F-18 (~650 lines of dead monitoring views with 1 Hz timers + sync kext calls, never mounted) · F-19 (Fans page wipes monitor sampling needs instead of registering as panel client) **PATCHED** · F-20 (FanCurveEditor: 2 Mach IPCs + 256-entry LUT per render tick) · F-21 (applied-confirmation race on double apply) **PATCHED** · F-22 (manual-mode slider stops tracking real PWM) · F-23 (same observer leak as A-06) **PATCHED** · F-24 (`MenuBarMetricsPreview` `let _ =` dependency-hacks) · F-25 (hardcoded strings in a 12-locale app: ThreadGrid Spanish, CPUDetails, MonitorAlerts GPU labels, AmdPower tags) · F-26 (AmdPowerControlsModel: 4–6 blocking IOConnect calls on MainActor from a 3 s timer) · F-29 (MakeIcon O(W·H) `colorAt` allocations) · F-30 (DMG subtitle baked in).

### 2.4 Suggestion (58) — highlights

- **A-16** Zero test coverage on `metricStatusGroups` / `MenuBarRenderer.blockSegments` — exactly where A-02-class regressions live. Extract + pin outputs.
- **A-17** Menu-bar metric blocks are images with no accessibility representation; add `accessibilityValue` from pre-stringified segments.
- **A-18** "Quiet alerting": threshold-tinted metric blocks reusing MonitorAlertService + TemperatureAlertGate.
- **A-19** "Slot doctor": extend `verifyIconReappeared` into a self-healing recovery loop.
- **A-20** Encrypted settings-backup envelope (HKDF + AES.GCM, formatVersion 2).
- **B-20** Route temp alerts through the (already built, unit-testable) `TemperatureAlertGate` for consistent hysteresis.
- **B-29** `MonitorSamplingPolicy.strideCache` unbounded key space if intervals become slider-controlled.
- **D-31** `ResponsibleProcess.icon(for:)` caches by pid (reuse shows stale icon).
- **E-38** Dead-code cluster (written-for-tests safety logic) — wire or delete with issue refs.
- **F-27** Cache `sidebarSections` per language+revision instead of rebuilding per keystroke.

### 2.5 Feature suggestions (roadmap-ready)

| ID | Feature | Why it's cheap | Effort |
|---|---|---|---|
| A-18 | Quiet alerting (menu-bar dot/tint) | Alert state already computed per tick; block-image cache key just needs an `alert` flag | M |
| B-35.1 | Per-core frequency graph | `CoreSnapshot.freqMHz` already flows per tick through the stride pipeline | S |
| B-35.2 | Preset "applied-at" stamp + drift detection | `withPresetTransaction` already persists per-component kext statuses | S |
| B-35.3 | Telemetry export (CSV/JSON, last N minutes) | `TelemetryLogger` + history arrays already hold everything | S |
| B-35.4 | Silicon-quality strip over per-core grid | `getCPPCScore()` + `AMDCoreRanking` implemented and tested | S |
| B-35.5 | C6 residency as a menu-bar metric | C6ResidencyService computes clean 0–100 %; one `MonitorSamplingKind` slot | S |
| C-34 | Animated WebP / HEVC-α export | Composer plan already rendered; removes GIF frame budget | M |
| C-35 | J/K/L shuttle + frame-nudge trim keys | Fits existing key monitor pattern | S |
| C-36 | ⌥-snap selection to hovered window | Geometry already computed per panel | S |
| C-37 | OCR "copy as TSV" | Line indices already kept per word | M |
| E-41 | Two-phase switcher (instant panel from cache, refresh in flight) | Removes the keyboard-hold cost of E-04 from the perceptible path | L |
| E-42 | Change-driven Dock pinned panels (CGWindowList delta + AXObserver) | Correct AXObserver lifecycle already demonstrated | M |
| E-43 | Per-app scroll profiles via existing exception infra | `MouseExceptionScope` + sanitized list plumbing exist | M |
| E-45 | Brightness-key HUD for silent no-route branches | BrightnessOSD reusable, generation-guarded | S |
| D.2 | Clipboard privacy TTL (auto-expire unpinned) | PNG sweep exists; per-entry purge closes history-remembers-everything | S |
| D.3 | Cleaner "undo window" (session log + put-back) | Everything already goes to Trash | M |
| D.5 | Update verification transparency (+ `latest.json` SHA-256) | Enables the D-10 fix | S |

## 3. Module Health Summary

| Module | Verdict |
|---|---|
| App (menu bar, panel lifecycle) | Excellent craft — anchor-drift correction, owner-aware observers, bounded caches — held back by *unwired* features (A-03) and version-gate drift (A-04) |
| Core (Defaults, localization, shortcuts) | Strongest layer: ~460 keys cross-checked, 7 migrations, sanitizer per user-facing value; the two bugs found were table-completeness errors |
| SystemMonitor/Metrics/AMD | Good crash safety, careful unit conversions; three perf hot spots and two actor-race spots; honest BUG-fix annotations |
| Recorder/QuickTools/Media | Best-in-class temp-file/permission/QR discipline; residual risk concentrated in main-thread compute and capture-engine races |
| Cleaner/Uninstall/Homebrew | Defense-in-depth exemplary (identity re-verification, symlink walks, scan-root allowlists); scheduler auto-run policy is the weak point |
| Update (self-update) | Staged/reversible installer is textbook; ad-hoc signature gate is the gap |
| Input/event-tap services | Above-bar tap lifecycle discipline; issues are AX volume on main thread and unwired helpers |
| Audio | Solid routing/mixer architecture; two dead safety mechanisms (E-01/E-02) are the worst finds |
| Display/KeepAwake/NowPlaying | Gamma math overflow-safe, assertion lifecycle complete; private-API usage degrades gracefully everywhere |
| UI/SwiftUI | Consistent architecture, no Combine leaks, correct timer invalidation in live pages; debt = 1 Hz re-renders, dead views, i18n stragglers |
| Kext C++ | Structurally sound with prior audit trail; three defect classes: unprivileged surface, lifetime bugs, workloop stalls — all but F-05/F-07 patched |

