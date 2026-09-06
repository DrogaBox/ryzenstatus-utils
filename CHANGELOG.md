# Changelog

## [1.21.0] — 2026-09-05

### Homebrew
- **Source-build warning in the operation panel**: the streamed brew log is now watched for the signals Homebrew actually prints while compiling (no-bottle and Tier 3 notices, raw clang/make/cmake lines). The moment a formula starts building from source, the operation status shows a sticky warning — the usual explanation for an update that sits at full CPU for hours on bottle-less Macs (Intel / older macOS tiers).
- **Skip heavy formulas for Update All** (new toggle, on by default, persisted): a plain `brew upgrade` silently compiles known giants (node, llvm, gcc, python, openjdk, rust, cmake, boost, protobuf, openssl). Update All now upgrades outdated formulas through one explicit command that leaves those out (casks still included); when only heavy formulas are pending, it just refreshes. Localized for all 13 languages.

## [1.20.0] — 2026-09-05

### AMD Kernel Extensions & Audit Remediation (v3.34.2)
- **F-05 — GPU telemetry off the hot path**: the SMC plugin's `RGPUTempValue`/`RGPUPowerValue` keys and the UserClient GPU selectors (28/29) now serve the provider's cached snapshot instead of issuing live SMU-mailbox reads. The old path could busy-wait up to 100 ms holding `gpuLock` **on any process's thread** that merely read the SMC key.
- **F-07 — user-client task lifetime**: `AMDRyzenCPUPMUserClient` now retains its owning task (`task_reference`/`task_deallocate`), closing the use-after-free window in per-call privilege re-validation.
- **N-01 — zero-initialized GPU outputs**: selectors 28/29 no longer copy uninitialized stack bytes to userspace when a per-GPU read fails.
- **C-1 — per-core C6 residency (new selector 32)**: the kext now exports per-logical-core idle residency derived from its existing per-CPU accounting; `C6ResidencyService` publishes a per-core snapshot on the same cadence as the package metric.
- **C-9 — kext reload self-healing (fixes audit B-25)**: the watchdog now detects a reloaded kext service, reopens the user-client connection, re-runs initialization and posts `KextReconnected` — previously the app stayed degraded until a manual restart.
- **Kexts rebuilt from audited sources at 3.34.2** and bundled in the DMG.

### App Concurrency & Correctness (F-27…F-30)
- **Thread-safe kext connection checks** (F-27): replaced all 6 external `connect != 0` reads with the lock-guarded `isConnected` accessor across `AutoEppService`, `FanCurveController`, `AmdPowerControlsModel`, and `AmdPowerSettingsView`.
- **Blocking kext IPC off MainActor** (F-28): `C6ResidencyService.poll()` now wraps the kext read + uptime timestamp in `Task.detached`; `AmdPowerControlsModel.syncFromKext()` batches 5 IPC calls in a single detached task with re-entrancy guard.
- **Fan picker hardware names** (F-29): menu-panel fan picker now shows hardware-reported or user-custom fan names via `getFans(includeNames: true)` instead of synthesized "Fan N" labels.
- **GPU temperature doc comment** (F-30): corrected `getKextGPUTemperatures()` doc comment — kext selector 28 returns integer °C directly, not SP78 fixed-point.
- **`closeDriver()` wired into termination**: `ProcessorModel.shared.closeDriver()` is now called from `applicationWillTerminate` as the final kext teardown step, ensuring the watchdog task is actually cancelled and the IOKit connection is closed cleanly on quit.
- **Sendable conformances** (strict-concurrency): `TerminationState`, `PowerCache`, and `GPUCache` are now `@unchecked Sendable`; `IOAcceleratorCache` now returns a `GPUStatsSnapshot` wrapper instead of bare `[String: Any]`, eliminating all 20 AMD-layer diagnostics under `-strict-concurrency=complete`.
- **AMD concurrency ratchet gate** (`Tools/concurrency-gate.sh`): new CI step enforces zero strict-concurrency diagnostics in the AMD layer; added to `.github/workflows/ci.yml`.
- **C6 residency + snapEPP unit tests**: `C6Sampling` pure-math enum extracted from `C6ResidencyService`, registered in the `--test` build list, and covered by 20 new checks (first-sample, counter-reset, normal delta, clamp, no-counter, and EPP bucket edges).

## [1.18.0] — 2026-09-03

### AMD Kernel Extensions & Telemetry Hardening (v3.34.1)
- **Kernel Heap Bounds Protection**: Added strict bounds guards across CPU instruction delta, clock speed calculation, and rendezvous initialization routines on systems with >64 cores, eliminating heap out-of-bounds writes (F-13).
- **Fan Curve Downward Hysteresis Anchor**: Seeded and anchored downward fan curve hysteresis tracking against last applied duty cycle temperatures, preventing erratic PWM jitter and rapid fan cycling (F-14).
- **SuperIO NCT668X Privilege Gating**: Gated configuration register 0x30 I/O-space decode unlocking behind driver privilege checks, securing LPC bus address decoding from unprivileged mutation (F-15).
- **User-Client Buffer Underrun Rejection**: Enforced mandatory output buffer size validation across all 25 struct-output method selectors, rejecting undersized user buffers with `kIOReturnBadArgument` to prevent uninitialized kernel memory disclosure (F-16).
- **SuperIO IT86XX Probe Port Cleanup**: Completed proper close sequence (`outb(regport, 0xAA)` / `outb(regport, 0x02)`) on failed SuperIO chip identification, preventing dangling enter-state conditions on ports 0x4E/0x2E (F-18).
- **Core Metric Telemetry & Read-Side OOB Guard**: Capped selector 4 effective cores at `CPUInfo::MaxCpus`, bounding required buffer size to ≤268 B across all processors and eliminating read-side kernel heap infoleaks on >64-physical-core machines (F-26).

### Application Stability, Privacy & Architecture
- **Event Tap AX Messaging Timeouts**: Implemented strict 50 ms accessibility messaging timeouts and keystroke shortcut gating across `FinderCutPaste` and `AutoQuitService`, preventing CGEventTap auto-disablement and main thread UI hangs (F-22).
- **Pasteboard Privacy & Secret Exclusion**: Excluded reverse-DNS transient and auto-generated types (`org.nspasteboard.TransientType`, `org.nspasteboard.AutoGeneratedType`) from clipboard history, safeguarding password manager entries (F-23).
- **Thread-Safe Driver Lifecycle**: Protected IOKit driver connection checks with synchronized locking and ensured clean watchdog task cancellation on teardown, preventing background polling leaks and races (F-24).
- **Platform Alignment**: Updated release documentation and minimum system requirements to explicitly target macOS 14 Sonoma and above (F-25).

## [1.17.0] — 2026-09-02

### Performance & Core System Stability
- **IOAccelerator GPU Leak Fix**: Resolved `io_object_t` Mach port leak in `IOAcceleratorCache` by advancing iterator in the loop condition, preventing unreleased service references on early exit.
- **Shelf Tolerant Store Decoding**: Integrated tolerant deserializer for saved items, preventing single corrupt entries from resetting the entire shelf.
- **WhatsApp Download Atomic Renaming**: Optimized same-volume file moves using atomic rename instead of redundant multi-gigabyte SHA-256 rehashing.
- **Display Fingerprint Validation**: Added hardware display fingerprint check before restoring gamma curves in Extra Brightness service.
- **OCR Line Break Normalization**: Enhanced Screen OCR text joiner to optionally remove line breaks across wrapped paragraphs and Asian scripts.
- **Shared Component Hardening**: Enhanced Launch At Login reconciliation, keyboard debounce handling, responsible process mapping, and screenshot rendering.

### AMD Hardware & Custom Architecture Protected
- **Full AMD Ecosystem Intact**: Maintained all custom Zen 1–5 telemetry, `SMCAMDProcessor` kext integrations, SuperIO fan curves, and AMD power presets.
- **Dashboard Process Manager Intact**: 100% preservation of the built-in Dashboard Process Manager (`PerformanceSuiteView`, `BTopDashboardView`, `ProcessInspectorWindowController`, `ProcessGlossary`, and `LeakDetector`).
- **Network Sampler**: Maintained macOS Sequoia 64-bit `IFMIB_IFDATA` network counters and real-zero rate detection.
- **Ad-Hoc Update Acceptance**: Kept secure ad-hoc code signature acceptance for community releases.

## [1.16.0] — 2026-08-28

### AMD Power Management & Kernel Drivers
- **Compiled Kernel Extensions**: Rebuilt and bundled updated `AMDRyzenCPUPowerManagement.kext` and `SMCAMDProcessor.kext` (v3.34.0) with enhanced stability and telemetry precision.
- **SMU Mailbox Synchronization**: Synchronized multi-step SMU7/SMU9 mailbox commands under mutex locks to prevent command collisions during heavy background loads.
- **Hardware Fan Curves & Hysteresis**: Clamped fan curve hysteresis and ramp rates to hardware-safe bounds, preventing fan oscillation and sudden speed jumps.
- **Modern Zen Generation Support**: Added calibrated frequency and boost profiles for Ryzen 7000, 8000 (APUs), 9000 series, and Threadripper 7000/PRO silicon.
- **Curve Optimizer Safety**: Enforced per-core voltage offset limits within the verified `[-30, +30]` range.
- **GPU BAR Concurrency**: Resolved potential race conditions during concurrent PCI BAR register initialization for AMD Radeon GPUs.

### Audio Engine & Volume Control
- **Automatic Audio Recovery**: Added a watchdog mechanism to automatically detect stalled CoreAudio aggregates after sleep/wake cycles and restore sound output seamlessly.
- **Boost Limiter Peak Protection**: Integrated an exponential-decay peak limiter for volume amplification above 100%, preventing clipping and acoustic distortion.
- **Clean Resource Teardown**: Ensured all CoreAudio property listeners and Carbon shortcut handlers are released upon device switching and app termination.

### System Metrics & UI Experience
- **Fluid Scrolling**: Preserved fractional pixel precision during mouse-wheel inertia animations to eliminate micro-stutters during slow scrolling.
- **Thread-Safe Telemetry**: Isolated C6 residency and Auto-EPP power management routines on the main actor to prevent data races and ensure smooth 60 FPS menu bar updates.
- **Accurate CCD & GPU Thermal Monitoring**: Constrained per-CCD temperature queries and formatted discrete GPU thermal readouts directly in integer degrees Celsius.

### Security, Packaging & System Hygiene
- **Hardened Subprocess Execution**: Protected background process calls with strict execution timeouts and pipe buffer drainage to prevent system stalls.
- **Secure File Exports**: Enforced strict POSIX 0600 file permissions on data exports and settings backups, with automated 300-second keychain auto-locking.
- **Installer & Packaging Integrity**: DMG packaging verified with SHA-256 checks and clean uninstaller support.

## [1.15.2] — 2026-08-28

### Security & Hardening (Codebase Audit)
- **GPU Fan Curve Temperature Injection**: Fixed value conversion mismatch in user-client selector 103 ensuring GPU-sourced fan curves track live temperature readings accurately.
- **Kernel Heap Protection**: Zero-filled telemetry packets in selector 100 to eliminate uninitialized memory disclosures; added `cpu_number()` bounds checks on >64 CPU systems.
- **SuperIO & Firmware Safety**: Gated NCT67XX firmware I/O-space unlock and raw register access behind privilege checks, and ensured configuration ports are safely closed on verify failure.
- **IOPCIDevice Lifecycle**: Fixed `AMDGPUDevice` reference counting and released Lilu EFI runtime service instances on teardown.

### App Correctness & Performance
- **Mac App Store Updates**: Updated iTunes Lookup querying to check all installed App Store applications individually, resolving batch truncation.
- **Clipboard Ignored Apps & Security**: Activated frontmost application exclusion during clipboard capture and enforced POSIX 0600/0700 permissions on history storage.
- **Text Snippets & Pasteboard**: Offloaded `{{clipboard}}` expansion from the active event tap thread and chunked keyboard injection along Unicode grapheme boundaries.
- **URL Cleaner Fidelity**: Switched query parameter cleaning to splice raw percent-encoded pairs, preserving original URL escape semantics.
- **AX Optimization**: Replaced dense 150-probe minimize-restore loop with a responsive 9-step back-off ladder.
- **Input & Window Management**: Constrained App Switcher middle-click closing to panel bounds, preserved fixed-point mouse wheel deltas, and added stuck-button safety timeouts.
- **Status Item Stability**: Connected consecutive empty-render grace windows to eliminate status bar layout jitter during transient sampling gaps.

## [1.15.1] — 2026-08-27

### UI & Layout Optimization
- **Menu Panel Spacing**: Eliminated excess empty margins at the top and bottom of the status popover. Removed rigid frame constraints to allow the panel to shrink-wrap naturally around content and scroll views.
- **Header Alignment**: Re-anchored the top header in a `ZStack` so the brand mark stays centered while the detach button is cleanly pinned to the top right.
- **Top Safe Area**: Reclaimed top padding using `.ignoresSafeArea(.container, edges: .top)` for a tight, native fit underneath the menu bar anchor.

### Compiler & Concurrency Hardening
- **Swift 6 Concurrency Compliance**: Marked thumbnail decoders (`ImageThumbnailer` and `VideoThumbnailer`) as `@MainActor` with detached background decoding to prevent `NSImage` non-Sendable warnings across task boundaries.
- **Zero Warnings**: 100% clean compilation across all modules and full unit test suite (3,742 assertions).

## [1.15.0] — 2026-08-27

### Deep Cleaner & Uninstaller Overhaul
- **Enhanced Leftover Matching Engine**: Complete rewrite of candidate scanning with `FileIdentity`, `stripKnownSuffix`, and multi-depth directory traversal. Accurately identifies app leftovers in Library, Preferences, Caches, Application Support, Containers, and receipt databases.
- **Safety & Symlink Protection**: Strict boundary checks prevent deletion outside scanned roots; symlink escapes and path replacement attacks are detected and rejected.
- **Confidence Badges & Reveal in Finder**: Leftover items display clear confidence indicators (`Exact` vs `Related`) and include direct Finder reveal buttons to inspect files before removal.

### SuperKey & Keyboard Customization
- **Multi-Source SuperKey**: Support for multiple trigger keys (Caps Lock, Right Option, and dedicated keys) with configurable modifier output combinations (`superKeyModifiers`).
- **Dynamic Key Descriptions & Modifiers**: Customizable modifier toggles (Command, Option, Control, Shift) with instant live preview and support in Menu Panel and Settings.

### Clipboard History Expansion
- **Extended Capacity**: Added support for 10,000 items and Unlimited history storage.
- **Automatic History Trimming**: Dynamic database trimming on limit changes ensures instant cleanup and fast sqlite search responsiveness.

### Media & Playback Fixes
- **NowPlaying Radial Menu Fix**: Fixed double-click toggle bug in the mouse radial menu where clicking Play/Pause caused immediate conflicting state toggles, ensuring seamless play/pause behavior for Apple Music, Spotify, and system media.

### App Switcher Enhancements
- **Adjustable Appearance Delay**: Added slider setting (0 to 500 ms, 100 ms default) in App Switcher settings to customize delay before the switcher overlay appears on hotkey press.

### Localization & Quality of Life
- **Complete 13-Language Updates**: All new strings, captions, and settings translated natively across English, Spanish, Brazilian Portuguese, German, French, Italian, Japanese, Korean, Russian, Turkish, Simplified Chinese, Traditional Chinese (HK), and Traditional Chinese (TW).
- **3,742 Unit Checks**: 100% test pass rate across the full standalone test suite.

## [1.14.0] — 2026-08-26

### Stability & Anti-Freeze (GCD)
- **BoundedProcessRunner**: Added per-read byte cap and a process termination timeout using `terminationHandler` instead of a blocking `waitUntilExit` call, eliminating GCD thread-pool exhaustion from runaway subprocesses.
- **WindowEnumerator**: Replaced `waitUntilAllOperationsAreFinished()` with `NSCondition` + 5 s timeout (`accessibilityBatchBudget`), ending indefinite stalls on locked accessibility APIs during Space switches (#971).
- **Pasteboard API fully asynchronous**: `GeneralPasteboardAccess` gains an `async<T>(_:then:)` overload; every call site (`URLCleanerService`, `PanelURLCleanerView`, `URLCleanerSettings`, `ClipboardHistoryService`, `PanelClipboardView`) migrated to the async lane — eliminates the last main-thread pasteboard blocks.

### Performance & System Fixes
- **Chromium CPU protection**: `AutoQuitService` and `WindowMaximizer` query `kAXWindowsAttribute` / `isApplicationElement` before traversing Chromium accessibility trees, removing multi-second CPU spikes during page loads.
- **Gamma Dim correctness**: `BrightnessSupport` and `BrightnessService` track `dimmedDisplays` separately from display brightness, preventing gamma-curve overwrites that caused permanent screen dimming on some monitors.
- **Sudoers rule scoped to UID**: `SudoersSupport` / `ShellSupport` write `#<uid> ALL=(root) NOPASSWD:…` instead of `ALL`, enforcing least-privilege even on multi-user machines.

### UI, Thumbnails & HUD
- **Menu-bar battery icon aspect ratio**: Fixed pixel-rounding error in `MenuBarRenderer` that caused the battery icon to appear squashed on retina displays (`31a0fc33`).
- **Real video thumbnails on Shelf**: `VideoThumbnailer` uses `AVAssetImageGenerator` to grab a frame 10 % into the clip (never the raw first frame, which is typically black or a title card). Decode is fully async — drop lands instantly with the fallback icon and the real frame patches in. Restore of a saved shelf also decodes all thumbnails off the main thread, eliminating startup hold for large shelves (`cd2d781a`).
- **Image thumbnail timing fix**: `startContentThumbnails` now fires after the item is appended to `items` rather than during `fileItem` construction, removing the 50 ms race-condition timer that silently discarded frames in mixed-provider drops (`23e9c5b3`).
- **Tile inset follows `hasContentThumbnail`**: Tiles use the thumbnail inset only once a real frame exists; generic-icon items keep the padded inset regardless of `isImage` flag.
- **Clipboard rich Finder preview & persistent Inspector**: `ClipboardHistoryImageSupport` / `ClipboardHistoryEscape` added; `ClipboardImageStore` extended with Finder preview support; async completions threaded through all `copyQuickEntry`/`copyQuickEntries`/`copyOnly*` methods.
- **App Switcher navigation & session scope**: `usesWindowRow` and `shiftBackChordWindow = 0.35` added to `SwitcherSupport`; `sessionScope` is assigned before `recomputeLayouts` to avoid a first-render with wrong scope.
- **SuperKey mouse click modifiers preserved** (`20e77ea5`): `SuperKeyService` installs an HID mouse tap that injects the active SuperKey modifiers into every click and drag event, preventing modifier-strip on mouse input.
- **Pixel-snapped crop rect & new crop selection** (`890dd0be`, `449f5f62`): `ScreenshotSupport` gains `startsNewCropSelection(at:draft:within:)` and `pixelSnappedCropRect`; `ScreenshotEditorController` snaps to device-pixel boundaries and supports starting a fresh crop without an overlap drag; crop loupe uses a 14 × 14 sample centred on an edge.
- **QuickTool HUD width cap & multi-line** (`1a9f6cd7`): `QuickToolHUD` clamps width to 360 pt and wraps at 2 lines, preventing oversized popups for verbose tool output.
- **Status item anchor reliability** (`ce44088a`, `e6485ec8`): Coordinate conversion in `StatusItemAnchorSupport` / `StatusItemController` corrected for edge cases with multiple screens at different backing scales.
- **Uninstall failure note & sandboxed FDA explanation** (`7b59532f`): `UninstallerSupport`, `AppUninstaller`, `SharedUI`, `UninstallerView`, `PanelUninstallerView`, and all 12 non-English localisations updated with clear guidance when full-disk access is missing.

### New Features
- **Media compression to target file size** (`83fc0626`): Images, GIFs, and videos can now be compressed to a user-specified MB target. `MediaVideoTargetEncoder` performs multi-pass bitrate scaling with per-format reduction plans (GIF frame-drop → palette reduction → scale; video bitrate budget → scale). UI in `MediaWorkspaceView` switches between resolution mode and target-size mode.
- **Visual Date/Time variable builder for snippets** (`1ac63dc8`, `b4e7930c`): New `DateVariableBuilder` popover in Snippet Settings lets users construct `{date:…}` tokens with IANA timezone search, format previews and one-click insertion. `TextSnippetSupport` gains `-tz(…)` override syntax and ranked timezone lookup. `PlainTextEditor` extracted as a shared AppKit/SwiftUI component with undo, configurable insets, and safe selection binding — replaces the private duplicate in Scratchpad.

### Internal & Testing
- **3,742 automated unit checks** — 100 % pass rate, +114 new assertions covering pasteboard async, `startsNewCropSelection`, `pixelSnappedCropRect`, `cropLoupeSampleRect`, `DateVariableBuilder` format tokens, and IANA timezone ranking.
- **Zero external telemetry** — all network hooks remain stripped.

## [1.13.0] — 2026-08-23

### Stability & Security Improvements
- **ScreenCaptureKit Window Indexing**: Fixed a fatal `SIGTRAP` crash caused by duplicate `windowID`s returned by ScreenCaptureKit during Space switching and multi-monitor reconfiguration.
- **POSIX Sandbox Hardening**: Implemented `PrivateFileStore` to enforce secure POSIX `0o700` directories and `0o600` file permissions across Shelf storage, Screen Recorder temporary shares, and Clipboard history databases.
- **macOS 14+ Cooperative Window Activation**: Updated Dock Click window cycling to use `NSApp.yieldActivation(to:)` and `activate(from: NSRunningApplication.current, options: [])`, preventing activation warnings on macOS Sonoma and later.
- **Filmstrip Trim Handle Stabilization**: Isolated Recorder filmstrip coordinate spaces (`"recorderFilmstrip"`) with absolute positioning to eliminate drag gesture jitter during video trimming.

### Features & Usability Enhancements
- **Intelligent Music Launch Interception**: Replaced blanket app launching blocks with temporal media-key event taps, distinguishing between unintended playback key presses and intentional user launches from the Dock or Spotlight.
- **Advanced URL Tracking Cleaner**: Added platform-tailored query parameter stripping rules for YouTube, X/Twitter, Instagram, Spotify, Reddit, TikTok, Bilibili, and Xiaohongshu.
- **Sticky Footer Deduplication in Scrolling Screenshots**: Integrated tiled column pattern matching to automatically identify and eliminate fixed headers/footers during vertical screenshot stitching.
- **Middle-Click Window Close**: Middle-clicking (scroll wheel click) any window tile in App Switcher now directly closes that window.
- **Synchronous Input Source Switching**: Added Carbon TIS-based keyboard layout switching action for SuperKey solo triggers.

### Memory Telemetry & Dock Preview
- **Comprehensive Memory Breakdown**: System monitor and menu panel now report physical Compressed Memory, Cached Files, and Swap usage alongside active application memory and memory pressure.
- **Configurable Dock Preview Open Delay**: Added customizable hover latency setting (200 ms to 900 ms) with proactive window list prefetching for responsive, jitter-free dock previewing.
- **13-Language Native Localization**: Complete native translations for all new memory telemetry, dock preview settings, and controls across all 13 supported languages (EN, PT-BR, ES, DE, FR, IT, JA, KO, RU, TR, ZH-Hans, ZH-Hant-HK, ZH-Hant-TW).

### Internal & Testing
- **3,628 Automated Unit Checks**: Verified complete regression test suite with 100% pass rate.
- **Zero-Telemetry Assurance**: All telemetry, tracking, and external analytic hooks remain completely stripped.

## [1.12.0] — 2026-08-17


### Fan & Cooling Control Rewrite
- **Kernel-Native Dynamic Fan Curves**: Complete ground-up rewrite of the fan and cooling control subsystem. Dynamic curves are now evaluated directly inside the kernel (`AMDRyzenCPUPowerManagement.kext`) at a 500 ms cadence with 256-point LUT interpolation, exponential moving average smoothing ($\alpha = 0.2$), hardware hysteresis, ramp rate limiting, and an emergency thermal guard ($\ge 85$ °C $\to$ PWM $\ge 200$), completely eliminating userspace PID polling loops and CPU overhead.
- **Hardware Telemetry Read-Back**: Accurate fan speed (RPM) and duty cycle (PWM %) are derived directly from the physical SuperIO chip (NCT6775, IT86xx, etc.) via SMC read-back (selector 94).
- **GPU Temperature Bridge (Selector 103)**: Added native GPU temperature forwarding to the kernel power management client, enabling fan curves driven by discrete GPU thermal loads.
- **Interactive Curve Editor & Staged Drafts**: Redesigned curve editor featuring 256-point visual preview, live sensor tracking markers, 4-curve slot management, a safe 1% minimum duty cycle floor, and explicit "Apply Curve" and "Revert" actions to prevent unintended fan spin-ups during editing.
- **13-Language Native Localization**: Full native translations for all fan control labels, alerts, and guide dialogues across all 13 supported languages.
- **Wake & State Synchronization**: Automatic re-upload of active curve LUTs and fan mappings upon system wake (`didWakeNotification`).

### Accessibility
- **Complete VoiceOver Coverage**: every icon-only button in the app (menu panel, mixer, shelf, settings, Now Playing, clipboard, uninstaller/cleaner) now announces a proper accessibility label — 44 buttons across two passes — with new localized tooltips and labels for mixer mute/unmute and the panel back button in all 13 languages.
- **Keyboard Controls in Now Playing**: Space toggles play/pause and Escape closes the floating window from anywhere inside it.

### Now Playing Fixes
- **Marquee Scrolling Fixed**: long titles now scroll continuously (slide-in → hold → scroll → loop) instead of stalling after the first pass.
- **Animated Artwork Switching**: moving between two albums with motion artwork now reloads and crossfades the new video stream.
- **Detached Window & Network Cleanup**: the floating window deregisters its move observer on close, and cancelled lyrics requests are pruned from the in-flight set.

### Performance & Stability
- **Mach Port Leak Fixed**: the thread-grid view no longer leaks its host port handle.
- **Faster Renders**: reduced SwiftUI redraws in ThreadGridView and added a visual loading state to Homebrew search buttons.

### Internal
- **Unit Tests**: 3,628 automated checks (+386 new checks covering LUT math, 272-byte packing, ramp rate scaling, compaction, and localization).

## [1.11.2] — 2026-08-17

### Accessibility
- **Complete VoiceOver Coverage**: every icon-only button in the app (menu panel, mixer, shelf, settings, Now Playing, clipboard, uninstaller/cleaner) now announces a proper accessibility label — 44 buttons across two passes — with new localized tooltips and labels for mixer mute/unmute and the panel back button in all 13 languages.
- **Keyboard Controls in Now Playing**: Space toggles play/pause and Escape closes the floating window from anywhere inside it.

### Now Playing Fixes
- **Marquee Scrolling Fixed**: long titles now scroll continuously (slide-in → hold → scroll → loop) instead of stalling after the first pass.
- **Animated Artwork Switching**: moving between two albums with motion artwork now reloads and crossfades the new video stream.
- **Detached Window & Network Cleanup**: the floating window deregisters its move observer on close, and cancelled lyrics requests are pruned from the in-flight set.

### Performance & Stability
- **Mach Port Leak Fixed**: the thread-grid view no longer leaks its host port handle.
- **Faster Renders**: reduced SwiftUI redraws in ThreadGridView and added a visual loading state to Homebrew search buttons.

### Internal
- **77 new unit checks** (marquee engine, LRC parser, artwork fingerprint, defaults migration v6) — 3,242 total.

## [1.11.1] — 2026-08-15

### CPU & Performance Optimizations
- **Process Loop Elimination**: Resolved an event loop in BTopDashboardView and PerformanceSuiteView where process updates triggered continuous re-sampling.
- **Menu Bar Marquee Optimization**: Set marquee scrolling off by default with idle timer teardown during hold phases to eliminate background WindowServer rendering load.
- **Morph Animation Cadence**: Adjusted popover transition timer to 60Hz.

### Now Playing & UI Improvements
- **Universal Transport Controls**: Fixed play/pause and track skipping by implementing smart single dispatch for Apple Music and Spotify via AppleScript alongside MediaRemote and system media keys, eliminating double-toggle behavior.
- **Menu Bar Icon Redesign**: Converted the Now Playing status item to a native template symbol with clean typography and a refined 1.5pt progress indicator.
- **Detached Window & Mini Mode Framing**: Fixed layout headroom across all sizes (Small, Medium, Large) so artwork, title, progress bar, and all playback controls remain fully visible without clipping. Added right-click context menu for quick resizing and pin-on-top toggles.
- **Radial Menu Synchronization**: Unified radial menu media keys with NowPlayingService routing.

## [1.11.0] — 2026-08-15

### Now Playing — Adaptive Themes & Animated Artwork
- **Theme Engine**: Added dynamic background theming with 6 palette styles (Artwork Adaptive, Frosted, Midnight, Warm Studio, High Contrast, Graphite) and real-time color blending from album artwork.
- **Animated Artwork Surface**: Support for Apple Music / animated cover streams with seamless crossfading between static cover art and live video streams.

### Now Playing — Detached Floating Popup & Mini Card
- **Detachable Floating Window**: Ability to tear off the Now Playing popover into a persistent floating desk widget.
- **Mini & Regular Display Modes**: Compact mini card mode for minimal desktop presence alongside the full-featured player card.
- **Marquee & Size Settings**: Configurable title marquee scrolling speeds and artwork sizing options.

### Now Playing — Lyrics, Credits & Search
- **Synchronized & Plain Lyrics**: Integrated lyrics center with auto-fetching, line-by-line synced playback scrolling, and manual search fallback.
- **Song Credits & Metadata**: Display detailed track information including composer, release year, genre, and bitrate.
- **Provider Search**: Search and jump directly to tracks across configured media providers.

### Now Playing — Transport Controls & Shortcuts
- **Shuffle & Repeat**: Full toggle support for shuffle and repeat modes across system media sessions and player backends.
- **Global Hotkeys**: Added configurable keyboard shortcut actions for previous, next, play/pause, and shuffle/repeat toggles.

## [1.10.0] — 2026-08-14

### Now Playing — Transport Fix
- **Next / Previous Track**: fixed a critical bug where the Next Track button was sending command `kMRStop` (raw value 3) instead of `kMRNextTrack` (raw value 4), causing it to stop playback instead of skipping to the next song. Previous Track was similarly off by one. The fix affects both the Now Playing panel card and the Radial Menu media keys — skip and back now work correctly in Music, Spotify, and any other system media session.

### Now Playing — New Feature
- **Now Playing Panel**: new section in the menu panel showing the current track with artwork, artist, album, a seekable progress bar with time labels, and transport controls (previous, play/pause, next). Works with any app that publishes a system media session: Music, Spotify, browsers, video players.
- **Now Playing Menu Bar Item**: dedicated status item that shows the track title and artist in the menu bar with an optional progress strip, configurable display modes (icon only, artist, song, or both), and a click to open the panel.
- **Provider Picker**: pin the feature to Music or Spotify, or leave it on Auto to follow whichever app is playing.
- **Open in App**: click the track title or use the button to bring the source app to the front.

### Monitor — CPU Temperature
- **Menu Bar Temperature from Cold Start**: the CPU temperature now appears in the menu bar immediately on launch without needing to open the Dashboard first. Added a dual-fallback: first tries the telemetry selector, then falls back to core-metric temperature.

### Dashboard — Live Updates
- **Process List Real-Time Refresh**: the process list in the Dashboard now updates automatically in real time even when the popover is closed, driven by the system monitor's snapshot tick (every ~1 s).
- **Network Graph**: the network throughput chart in the Dashboard now activates as soon as the Dashboard window opens.
- **Scroll**: the Dashboard tab content is now scrollable so multi-core grids and long process lists don't overflow.

### Fan Curve Editor
- **Canvas Height**: the fan curve editor canvas no longer collapses to zero height; it now renders at a proper fixed height so the curve is always fully visible.

### Code Quality — Swift 6 Readiness
- Replaced all `NSLock.lock()` / `.unlock()` calls inside `async` / `Task` contexts with `withLock {}` (ProcessorModel, ProcessUsageService).
- Declared `kextWatchdogTask` as `nonisolated(unsafe)` to allow assignment from the actor's `init()`.
- Fixed `@MainActor`-isolated `updateUsage()` called from a nonisolated `Timer` callback in `ThreadGridView`.
- Captured `initFans` as an immutable `let` binding before `await` in `AmdControlSection` to satisfy Swift's sendability rules.
- Updated two deprecated `onChange(of:perform:)` calls to the macOS 14+ two-parameter form.
- Removed an unused `flags` binding in `FinderCutPaste`.

## [1.9.16] — 2026-08-09

### App Switcher — Rules & Windowless Apps
- **Per-App Rules**: choose how each app appears in the switcher — always show it without windows, windows only, or never — from Settings → Switcher, with an app picker and per-app icons.
- **Windowless Apps Choice**: replaced the single "show Finder" switch with a picker — not shown, Finder only, or all apps — for apps running with no window at all.
- **Search Pin Toggle**: typing "S" pins the search field open while the switcher is up, so typing no longer closes it or triggers special characters when the shortcut uses ⌥. Off by default; the toggle lives in Settings → Switcher.
- **Thumbnail Pauses**: window thumbnails stop updating while a chosen app is frontmost (privacy), from the preview-size section.

### App Switcher — Polish
- **No Open Window View**: selecting an app with no open windows shows its icon with "no open window" instead of an empty tile.
- **Shortcut Hints Toggle**: the hints under each tile can be hidden.

### Clipboard — Control & Editing
- **Skipped Apps**: choose apps whose copied content is never saved to the history.
- **Preview Sidebar & Editing**: preview clipboard entries in a sidebar and edit saved text (up to 20,000 characters) before reuse.

### Screenshot & Recorder
- **Screenshot**: a clipboard shortcut, an option to hide RyzenStatus windows from captures, and a preview-position picker.
- **Recorder**: microphone input with its own permission flow.
- **Sharing (developer)**: screenshots and recordings can be shared as expiring links to your own server. There is no default server and never a third-party host; see docs/SHARING_SERVER.md.

### Essentials — Input & Display
- **Dock Click to Hide**: clicking the Dock icon can hide all of the app's windows.
- **Keep Awake Options**: allow the display to sleep while keeping the system awake, and toggle keep-awake with a right-click on the menu-bar icon.
- **Scroll Inverter — Horizontal Axis**: invert horizontal scrolling direction independently.
- **URL Cleaner — Custom Parameters**: strip your own query parameters from copied links.

### Monitor
- **Memory Metric Choice**: choose which memory metric the monitor shows.

## [1.9.15] — 2026-08-09

### Essentials — Input & Stability
- **No More Frozen Input During Games**: with Dock Preview enabled, every mouse move ran a Dock Accessibility hit-test on the main thread. While a fullscreen app (e.g. a game) was frontmost, the Dock is hidden, so the hit-test fell through to AX IPC against the app under the cursor — often a game that answers accessibility slowly — with no messaging timeout, freezing the main run loop for seconds and stalling every event tap on it: clicks were missed, delayed, or read as drags (in-game clicks "not registering", apps feeling hung). The hover pipeline now only runs while the Dock is actually on screen.
- **Hover Detection Hardened**: the per-mouse-move path gates on cheap geometry before any IPC, skips the AX parent walk when the element under the cursor isn't the Dock, and caps every Accessibility round-trip at 0.2 s, so a busy or unresponsive app can never block the main thread again.

## [1.9.14] — 2026-08-08

### AMD Power — Menu Panel
- **No More Panel Blocking**: kext reads (CPPC, CPB, PPM/LPM, fans and fan count) now run off the main thread; only the UI refresh hops back, preventing micro-stutters when opening the menu.

### Essentials — Stability & Telemetry
- **Kext Selectors Documented**: the selector table now matches the kext's real semantics (101 writes the fan-curve LUT, 102 maps a fan to a curve, 17 reads HP CPUs, 18 reads LPM state) — no behavior change.
- **No More mach Port Leaks**: per-core load sampling releases the host port it acquires on every read, matching the rest of the monitor.

### Dashboard — Real Data
- **No More Hardcoded Hardware**: the BTop section and Performance Suite cards show the machine's actual CPU/GPU and VRAM instead of fixed models ("Ryzen 9 5900XT", "NAVI 21").

## [1.9.13] — 2026-08-08

### Settings — Fan & Cooling
- **Immediate Fan Loading**: the screen no longer waits for the kext's slow name lookups; it shows RPM and controls from a minimal read and applies the saved names afterwards.
- **No Duplicate Polling on Entry**: the periodic timer starts after the first read, so it no longer races the initial detection.

## [1.9.12] — 2026-08-08

### Settings — Fan & Cooling / AMD Ryzen Power
- **Reliable Tab Switching**: kext reads are now cancelled when leaving the screen, so no stale tasks keep updating a destroyed view.
- **Visible, Non-Blocking Loading**: AMD Ryzen Power shows its loading state immediately and avoids duplicate reads when switching pages quickly.
- **Controlled Fan Refresh**: periodic polls are cancelled and replaced instead of accumulating while navigating.

## [1.9.11] — 2026-08-08

### Essentials — GPU & Counters
- **No More False 100% GPU Spikes**: integer percentage values from AMD are no longer interpreted as `1` = `100%`; the card also distinguishes a pending read from a real `0%`.
- **Unified Normalization**: all GPU paths share the same conversion and validation before feeding the chart and the per-process breakdown.

## [1.9.10] — 2026-08-08

### Essentials — Network & Charts
- **Correct 64-bit Counters on Sequoia**: reading `NET_RT_IFLIST2` could truncate received bytes; it now uses `IFMIB_IFDATA`, matching `netstat`.
- **Charts Visible with Low Traffic**: network scales adapt to the real peak instead of being pinned at `1024 B/s`, and the download/upload lines stay distinguishable.

## [1.9.9] — 2026-08-08

### Essentials — Real-Time Network
- **Sampling Enabled in Performance Suite**: the dashboard requests the network metrics it displays, preventing stale cards while the history kept drawing.
- **Real Zero Kept Apart from “Measuring”**: the UI no longer turns a pending first sample into `0 B/s`, avoiding misleading readings when switching pages or resuming the monitor.

## [1.9.8] — 2026-08-08

### GPU — Coherent Readings
- **Discards Impossible Spikes**: the monitor no longer accepts high GPU load while the core clock is idle (`<100 MHz`), avoiding cases like `63%` at `15 MHz` with nearly idle GPU processes.
- **More Reliable Total & Breakdown**: the overall percentage keeps the hardware counter, while the process list keeps using the GPU time attributed by macOS without turning a spurious reading into real load.

## [1.9.7] — 2026-08-08

### DMG & GPU Monitor
- **Kexts Included**: the installer uses the official precompiled kexts from the `SMCAMDProcessor v3.34.0` release when no local build is available, and shows them inside the DMG.
- **Better-Organized Installer**: the DMG window only positions the Kexts folder when it exists, avoiding shifted icons or Finder errors.
- **GPU Without False Spikes**: non-finite or out-of-range values are discarded and an isolated `100%` is not accepted as a first sample; sustained load still climbs gradually.

## [1.9.6] — 2026-08-08

### Essentials — Responsiveness
- **Faster Settings Opening**: the global monitor now activates only the metrics the visible screen needs, instead of starting network, disk, GPU and memory work for no reason.
- **AMD Power Without Blocking the UI**: CPPC, PPM/LPM, telemetry and Curve Optimizer reads run off the main thread.
- **Nimble Fan & Controls**: fan detection and updates run in the background; names are read only when hardware is detected, not on every periodic query.
- **Optimized SMC Sensors**: the connection is reused, the key list is cached, and full reads run on a low-priority queue.

## [1.9.5] — 2026-08-08

### Sequoia (macOS 15) Compatibility
- **Runs on Sequoia**: The macOS‑26‑only SwiftUI pieces — the Liquid Glass mixer styling (`GlassEffectContainer`, `glassEffect`) and the Settings sidebar scroll edge effect (`scrollEdgeEffectStyle`) — are now compiled behind `#if compiler(>=6.2)` guards. Built with Xcode 16 / SDK 15 they fall back to the native pre‑26 UI, so the app builds and runs on macOS 15 Sequoia (and macOS 14) exactly as before. Runtime behavior on macOS 26 is unchanged — the glass mixer slider and styled sidebar still appear there.
- **CI‑proven**: A new `sdk15` CI job builds the full app against the macOS 15 SDK (Xcode 16.4) on every push, so the Sequoia fallback branch can never silently regress again.

## [1.9.4] — 2026-08-08

### Fans & Cooling — Usability & Safety
- **Fan Curve Editor as a Master Switch**: Turning the curve editor on now maps the first curve to the first fan right away, so one tap visibly starts controlling a header. Turning it off restores every mapped fan to automatic control and stops the userspace loop — no more fans staying curve-driven after the toggle is off.
- **Reliable First Tap**: The one-tap mapping retries once fan detection completes, so it no longer silently does nothing when the kext is slow to report fans on startup.
- **GPU Temp Source Hidden When Not Applicable**: The curve editor only offers the GPU temperature source when a discrete AMD GPU is present (the GPU fan is managed by the GPU itself). Hiding it is non-destructive — stored GPU-sourced curves keep their intent and are just shown as CPU.
- **Thermal Safety Guard**: The userspace fan-curve loop now enforces the same safety floor as the kext — at least 80% PWM above 85 °C — so a user-drawn curve can never leave the CPU without airflow near its thermal limit, on every supported CPU family (Zen 1–5).

### Housekeeping
- Removed dead kext fan-curve code (selectors 101/102 UI) left over in AMD Power Settings after the feature moved to Fans & Cooling.

## [1.9.3] — 2026-08-08

### Gaming Mode — Reliability
- **Pre-Gaming Preset Persistence**: Gaming Mode now remembers your actual power profile (not a fallback) when you activate it, so after a relaunch with the mode still active, turning it off restores the exact preset you were running before — even across app restarts.
- **Serialized Preset Transactions**: All power-preset writes (Settings cards, menu panel, and Gaming Mode activate/deactivate/restore) now go through a single FIFO queue in `AmdPresetController`. A fast toggle-off during activation or a restore racing a new activation can no longer interleave their persisted-key and kext writes, so the app and hardware can never disagree about which preset is active.

## [1.9.2] — 2026-08-08

### Stability & Performance (AMD Backend)
- **IOKit Performance (Micro-stutters)**: Completely rewrote the GPU communication layer. Instead of querying `IOAccelerator` synchronously ~6 times per second, RyzenStatus now uses an asynchronous cache (`IOAcceleratorCache`) that processes the entire kernel tree in the background. This definitively eliminates any stuttering or micro-stutters in the main interface or when moving the mouse during heavy GPU polling.
- **Kernel Security (Kext)**: Resolved critical vulnerabilities (`P0`) related to memory leaks (`proc_ucred`) in the IOKit client and out-of-bounds (OOB) array reads when querying VirtualSMC sysctl keys.
- **UserDefaults Centralization**: Implemented a new configuration store in the backend (`AmdSettingsStore`) to replace dozens of scattered reads and writes for power profiles (Auto EPP, Gaming Mode, Fan Curves). This prevents ghost states and race conditions between the UI and the background polling loop.
- **Polling Robustness**: Added guards to MSR and temperature reads to prevent sensor timeouts from injecting anomalous values (e.g., forcing fans to 0 RPM when receiving a false 0°C reading).
- **Internal Architecture**: All "magic" Kernel selectors (IOConnectCallStructMethod) are now strictly typed through the `AMDKextSelector` enum, making the backend cleaner and error-proof.

## [1.9.1] — 2026-08-08

### Gaming Mode
- **Gaming Mode**: One click applies the Extreme power preset, starts an indefinite Keep Awake session and hides the menu bar icon. The mode persists across launches and is re-applied on startup; turning it off restores your previous profile — including your Auto EPP preference, even after a relaunch while the mode is active.
- **Full Menu Bar Hiding**: With separate menu bar metrics enabled, Gaming Mode now hides those items too instead of leaving CPU/GPU readouts on screen.
- **Localized Section**: The Gaming Mode settings now follow the app language (English and Spanish; other languages fall back like the existing AMD Power strings).
- **Smarter Preset Restore**: Choosing a different power preset while Gaming Mode is active keeps your choice — deactivation only restores the pre-gaming profile when it hasn't been changed. Preset cards highlight what the kext is actually running while the mode is on.

### Privacy & Security
- **Strict Share Record Filtering**: Screenshot share links only surface when they point at the currently configured server — records from any other host (including the removed legacy upload server) never appear in Settings.

## [1.9.0] — 2026-08-07

### AMD Power — Full Kext Selector Integration
- **Power Presets (Eco / Balance / Performance / Extreme)**: One-tap profiles that configure EPP, Core Performance Boost and PPM/LPM together — Eco (EPP 255 + C6 + LPM), Balance (EPP 128), Performance (EPP 32) and Extreme (EPP 0). PPM and LPM stay mutually exclusive and the selection persists across launches.
- **CPB / PPM / LPM Toggles**: Core Performance Boost (selector 12), Processor Power Manager (14) and Low Power Mode (19) now persist their last state and report privilege errors clearly.
- **CCD Temperatures**: Per-CCD thermal readout (selector 20) shown as dashboard cards and inside the telemetry packet.
- **C6 Residency Meter**: Live percentage of time the package spends in C6 (selector 31) rendered as a progress bar in the dashboard and AMD Power Settings.
- **CPU Profile Readout**: The kext's architecture codename (selector 26) — e.g. "Zen 3 Vermeer" — appears in the dashboard header, with PM Dispatch / Legacy P-States / CPPC capability badges in Settings.
- **CPPC Info & Core Ranking**: Shows the active CPPC mode and current EPP value (selector 23), and marks the highest-HighestPerf threads with a star (selector 21).
- **AMD GPU Monitoring**: Dedicated AMD GPU temperature and power (selectors 27–30) appear in the dashboard and Settings, using the capabilities bitmap for power reporting — hidden when only an iGPU or NVIDIA GPU is present.
- **Telemetry Streaming**: Zero-copy 304-byte `CPUSensorPacket` (selector 100) with package power/temp, per-CCD temperatures and per-thread frequencies, read out in Settings.
- **Kext Fan Curves**: Four predefined 256-point LUTs (Silent / Balanced / Performance / Aggressive) uploaded to the kext (selector 101) and mapped to a fan header (selector 102), with a live curve preview and one-click Auto restore.
- **Curve Optimizer**: Per-core offset grid −30..+30 (selectors 110/111) with Apply All and Reset to 0, gated to Zen 3 Vermeer — Zen 4/5 shows an explanatory "use PBO in BIOS" message and the kext blocks writes above 75 °C.

## [1.8.8] — 2026-08-07

### Features & Fixes
- **32-Thread Support (Zen 3)**: Complete UI overhaul for the Core Grid dashboard to natively support and properly render up to 32 hardware threads, using responsive layouts and proper color coding for physical vs SMT cores.
- **Combined Frequency & IPS Metrics**: A new real-time graph mapping average CPU frequency against Instructions Per Second (IPS) estimates.
- **Classic Menu Revival (NF-03)**: Brought back the classic menu layout (Layout 2) without breaking the modern unified panel.
- **Robust Telemetry & Stability**: System-wide bug fixes targeting zombie `nettop` polling, thermal deadlocks, temperature hysteresis, and memory safety improvements.

## [1.8.7] — 2026-08-07

### Privacy & Security
- **Screenshot Sharing Disabled by Default**: RyzenStatus no longer uploads screenshots to any third-party server outside our control. Sharing now requires a developer-configured server endpoint; the share buttons stay disabled until one is set up.
- **Legacy Share Links Purged**: Share records created by older builds that point at the removed server are dropped from the app so no stale links surface in Settings.

## [1.8.6] — 2026-08-07

### Features & Fixes
- **GPU Power Badge Uses Kext Capabilities**: The per-GPU power badge now respects the kext's capabilities bitmap (selector 30, bit 0) — power is shown only for GPUs that actually support power reporting, instead of inferring it from a non-zero reading.
- **AMD Auto EPP Persistence & Privilege Feedback**: The Auto EPP toggle state now persists across launches in user defaults, and a clear hardware-privilege warning is shown when the kext denies the write. Removed the redundant privilege warning caption from the popover.
- **CPU Load Meter Sampling Fix**: Per-thread CPU load sampling now runs continuously across all 32 logical threads whether or not Auto EPP is active, eliminating the load-meter feedback loop.

## [1.8.5] — 2026-08-06

### Features & Fixes
- **AMD Auto EPP & CPU Load Meter Fix**: Fixed the toggle state feedback loop in AMD Power Control popover/settings and ensured real-time CPU load sampling runs continuously across all 32 hardware threads whether Auto EPP is active or inactive.
- **Screen Recorder UI Sidebar Integration**: Exposed the full Screen Recorder configuration panel, controls, and shortcut bindings under Settings > Utilities.
- **AMD Ryzen Temperature Spike Filter**: Integrated `TemperatureAlertGate` hysteresis to eliminate false high-temperature alert spikes during single-core CPU boost on AMD Zen 3.
- **Display DDC Sleep Recovery**: Automatically rebuilds I2C display routing paths upon system wake, preserving external monitor brightness controls.
- **Menu Bar Icon Recovery Retries**: Multi-attempt status item placement checks prevent icon loss when macOS delays menu bar rendering.
- **App Switcher & Scratchpad Dismissal**: Added outside-click dismissal for App Switcher and Scratchpad panels, with customizable pin floating options.

## [1.8.4] — 2026-08-05

### Features & Improvements
- **Screen Recorder & Live Video Editor**: Full screen and window recording with mouse pointer tracking, live editing timeline, composited cursor sprites, and fast export engine.
- **Scrolling Screenshots**: Automatic scroll-capture engine stitches full-page screenshots with overlap detection, max-resolution guards, and graceful partial-completion fallback.
- **System Master Volume Control**: Master output volume slider and mute toggle now appear at the top of the Audio Mixer section alongside per-app controls.
- **App Switcher Multi-Space Support**: Instant transition between multiple Desktops/Spaces, corrected Adobe window previews, and support for apps with no open windows.
- **Thermal Safety Filter**: CPU and GPU sensors now ignore bogus 0 °C readings — minimum valid chip temperature raised to 10 °C, with a 4-sample hold-last-good cache to bridge transient SMC gaps.
- **Command Bar Improvements**: Direct app controls available in the Command Bar; full-width space characters (U+3000, IDEOGRAPHIC SPACE) are now handled as whitespace for search and shortcut matching.

## [1.8.3] — 2026-08-05

### Stable Maintenance Release

### Features & Improvements
- **Localization Infrastructure**: Added comprehensive `L10n` localization keys (`istatsUser`, `istatsSystem`, `istatsProcesses`, `amdRyzenProcessorInfo`, `amdMinFrequency`, `amdMaxFrequency`, `amdAvgFrequency`) across all 11 supported languages.
- **Kext Callback Execution Order**: Adjusted GPU temperature callback execution timing in `SMCAMDProcessor.kext` prior to fan curve evaluation.
- **Volume Mixer Drag-to-Reorder**: Integrated drag-to-reorder layout support and custom block styling for application volume controls in the menu panel.
- **System Telemetry Stability**: Reinforced AMD Auto-EPP / CPPC state persistence and menu bar readout defaults.

## [1.8.2] — 2026-08-02

### Stable Release

### Features & Improvements
- **AMD Boot-Args Read & Copy**: New section in AMD Power Settings displays the current NVRAM `boot-args` state (`amdcstate`, `-amdcppcactive`, `-amdpnopchk`) as live read-only badges. A single "Copy AMD Boot-Args" button copies the full recommended string to the clipboard for pasting into your bootloader `config.plist` — the app never writes to NVRAM directly.
- **Finder Image Paste**: Pressing `⌘V` in a Finder window with no files marked for cut now saves clipboard PNG/TIFF images directly as `Pasted Image <timestamp>.png` in the current folder.
- **Clipboard Privacy**: Password manager entries (1Password, Bitwarden, TypeIt4Me, `org.nspasteboard.ConcealedType`) are automatically excluded from clipboard history — passwords are never recorded.
- **Performance Suite Dashboard**: Full `PerformanceSuiteView` with 5 navigation tabs (Dashboard, Diagnostics, Analytics, Energy, Network).
- **AMD SMT Core Topology Mapping**: Corrected XNU kernel interleaved SMT thread indexing, restoring accurate per-core load visualization across all 16 physical cores.
- **1Hz Real-Time Process Inspector**: Floating inspector window with executable path, Reveal in Finder, Copy Path, and 1Hz live telemetry.
- **Catmull-Rom Cubic Spline Waveforms**: Smooth cubic spline timeline sparklines and trend charts.
- **Dynamic CPU Hardware Detection**: Real-time `sysctlbyname("machdep.cpu.brand_string")` and core/thread topography resolution.
- **App Switcher Enhancements**: W-key window closing, thermal alert hysteresis, external disk eject support, and customizable Dock Preview opacity.

### Bug Fixes
- **Process Inspector Memory Leak**: `NSWindowDelegate` + `windowWillClose` tears down live-telemetry timers when inspector is closed.
- **Telemetry Logger Disk Exception**: File write exceptions handled gracefully during low-disk states.
- **Memory Alignment Safety**: Replaced unsafe pointer type-punning with `loadUnaligned` in `NetworkSampler`.
- **Network Process Pipe Deadlock**: Concurrent drain queue for `nettop` eliminates pipe buffer deadlocks on high-traffic connections.
- **Background Performance Suite Loading**: Data refresh offloaded to background `Task.detached` with `MainActor` UI updates.
- **Disk Sampler Timeout**: 4-second timeout with fallback process termination in `runDiskutilInfo`.
- **Accurate Energy Impact GPU Scoring**: Resolved process GPU utilization from `topGPU` instead of hardcoding zero.
- **FinderCutPaste Thread-Safety**: `NSPasteboard` data captured on calling thread before `DispatchQueue.global` — eliminates race condition crash.
- **FinderCutPaste moveInProgress Flag**: Reset correctly in all branches including the image-paste and `insertionLocation` failure paths.
- **Bitwarden Clipboard Filtering**: Added `org.bitwarden.clipboard` and `com.bitwarden.bitwarden` to the pasteboard privacy exclusion list.


## [1.7.2] — 2026-07-31


### Maintenance Release

Fourth stable release. Zero-warning compiler optimization, fan control overrides refactoring, thread safety improvements, and full test suite verification.

### Improvements & Fixes
- **Fan Control Overrides**: Updated fan curve controls to use `isOverridden` property, eliminating all compiler deprecation warnings.
- **WhatsApp Organizer**: Refactored `undoActions` declaration in download organizer.
- **Thread Safety**: App Switcher event tap and Shelf item icon rendering optimizations on main thread.
- **Drive Format Identifiers**: Added file system labels (APFS, exFAT, NTFS, FAT32, HFS+) to Disks monitoring panel.
- **Smooth Scroll**: Improved high-resolution mouse wheel support for smooth scrolling.
- **Verification**: Clean build with 0 compiler warnings and all 2,941 unit test checks passing.

## [1.7.1] — 2026-07-27

### Stable Release

Third stable release. Ports remaining upstream utility services and dependency methods.

### Features
- **Shortcut Capture**: Silences global shortcuts during recording sessions—captured keystrokes won't trigger features.
- **Shortcut Recording Tap**: Dedicated event tap for capturing keystrokes during shortcut recording.
- **UI Suspension**: Enhanced user interface suspension helper for apps during assisted workflows.

### Internal
- Added `EnhancedUserInterfaceSuspension`, `ShortcutCapture`, `ShortcutRecordingTap` utilities for shortcut recording and UI suspension.
- Added `suspendShortcut()` to ClipboardHistoryService, SoundOutputSwitcher, ShelfService.
- Added `suspendShortcuts()` to WindowLayoutService, `unregisterAll()` to QuickToolHotkey.
- Added `routeCapturing` state and `setCapturingShortcut(_:)` to AppSwitcher.
- Added `featuresToSilenceWhileRecording` to GlobalShortcutRole.

## [1.7.0] — 2026-07-27

### Stable Release

Second stable release. Adds 6 new productivity features from upstream plus GPU alert localizations and audit fixes.

### Features
- **Boost Limiter**: Automatically reduces system volume when an app starts making loud noises—perfect for unexpected full-screen videos or audio glitches.
- **Space Hop**: Automatically follows your active window when you switch to an app whose window is on a different full-screen Space, eliminating manual Space navigation.
- **Mouse Exceptions List**: Per-app exception list for Smooth Scroll and Scroll Inverter — exclude specific apps from scroll customization.
- **App Appearance**: Choose between System, Light, or Dark appearance mode per app.
- **Snippet Library**: Dedicated searchable panel for text snippets, organized by folder.
- **WhatsApp Downloads**: Full download organizer — scans Downloads for WhatsApp files, auto-cleanup with retention rules, daily/weekly scheduling, and notifications.

## [1.6.0] — 2026-07-27

### Stable Release

First stable release. Consolidates all beta features, fixes, and improvements from the beta3→beta9 cycle.

### Features
- **App Updates**: Check which installed apps have newer versions via Homebrew and Mac App Store, with background scanning and notifications.
- **Package C6 Residency Monitoring**: C6 power state monitoring via MSR 0xC0010296 — live residency percentage in Dashboard and AMD Power Settings.
- **Menu Bar W Suffix Fix**: Power metrics with 3-digit values no longer clip the "W" suffix.
- **Mouse Button Shortcuts**: Programmable extra mouse button mapping.
- **Super Key (Caps Lock Remap)**: Turn Caps Lock into a powerful modifier key.
- **Snippet Library**: Text snippet library with searchable catalog.

### Bug Fixes
- **GPU Temperature Priority (Critical)**: Kext MMIO GPU temperature (selector 28) now takes priority over IOAccelerator readings.
- **Fan Control API Rename**: `setFanSpeed(rpm:)` → `setFanSpeed(pwm:)` to reflect actual PWM (0-255) parameter.
- **Timing Monotonicity**: Replaced wall-clock `NSDate` with `ProcessInfo.systemUptime` for interval calculations.
- **Physical Core Fallback**: From hardcoded 16 to `ProcessInfo.processorCount / 2`.
- **Thread Safety**: `@MainActor` annotation added to `MonitorAlertService`.
- **Kext Version Bump**: 3.34.0 — AMDGPU MMIO monitoring, C6 residency, SuperIO 6-fan support.
- **Process List Flickering Fix**: Extended stale cache lifetime from 2s to 60s.

## [1.6.0-beta9]

### Features
- **App Updates**: New feature that checks which installed apps have a newer version available. Supports two sources:
  - Homebrew casks (including apps with their own updater, verified against the actual app bundle version)
  - Mac App Store (looks up versions via iTunes API)
- **Background Check**: Optional daily/weekly automatic scanning with notification support.
- **Panel Integration**: App Updates tile in the Utilities section showing pending updates with update-all button.
- **Settings Page**: Configure check frequency, notifications, and App Store scanning in Settings → App management.

## [1.6.0-beta8]

### Features
- **Menu Bar W Suffix Fix**: Power metrics with 3-digit values (e.g. 105W) no longer clip the "W" in menu bar blocks.
- **Initial Status Item Sizing**: Status bar now reserves enough width for power metric blocks from the first sample.

### Kexts
- **Version Bump 3.33.6 → 3.34.0**: Kext source already contained all SuperIO fixes from v3.33.8 plus C6 and AMDGPU monitoring. Bumped to 3.34.0 to reflect actual feature level and avoid confusion with the old v3.33.6 tag.
- **AMDRyzenCPUPowerManagement**: v3.34.0 — AMDGPU MMIO monitoring (selectors 27-30), C6 residency (selector 31), SuperIO 6-fan support, pmAMDRyzen cleanup.
- **SMCAMDProcessor**: v3.34.0 — GPU SMC key additions.

## [1.6.0-beta7]

### Features
- **Package C6 Residency Monitoring**: Added C6 power state monitoring — reads MSR 0xC0010296 via kext selector 31 and displays residency % live in the app.
- **C6 in Dashboard**: C6 residency card on main Dashboard for at-a-glance monitoring.
- **C6 Settings UI**: Deep C-States section in AMD Power Settings with percentage, visual bar, and boot-arg instructions.

### Fixes
- **App Kext References**: Corrected stale "SMCAMD.kext" references in Dashboard, Fans settings, and error alerts to use proper kext names.
- **Source Cleanup**: Removed all build artifacts, experiment scripts, and leftover documentation from development session.

## [1.6.0-beta6]

### Feature Parity
- **Mouse Button Shortcuts**: Added programmable mouse button configuration — remap extra mouse buttons to custom actions.
- **Super Key**: Added Caps Lock remapping — turn an unused key into a powerful modifier.
- **Snippet Library**: Added text snippet library with searchable catalog alongside the existing text snippets.
- **New Settings Pages**: Dedicated Mouse Buttons and Super Key pages with full configuration UI.

### Bug Fixes
- **GPU Temperature Priority (Critical)**: Fixed a bug where the IOAccelerator GPU temperature snapshot could overwrite the more accurate kext MMIO reading (selector 28). Kext data is now treated as primary source.
- **Fan Control API**: Renamed `setFanSpeed(rpm:)` to `setFanSpeed(pwm:)` to accurately reflect that selector 95 expects PWM values (0-255), not RPM.
- **Timing Monotonicity**: Replaced wall-clock `NSDate` with `ProcessInfo.systemUptime` in `getMetric()` and `loadMetric()` for accurate interval calculation immune to system clock changes.
- **Physical Core Fallback**: Changed fallback core count from hardcoded `16` to `ProcessInfo.processorCount / 2` for better accuracy on non-16-core machines.
- **Thread Safety**: Added `@MainActor` annotation to `MonitorAlertService` to match its actual usage pattern.
- **GPU Monitoring**: Kext selector 30 (capabilities) is now fetched alongside temperatures and powers in `refreshKextGPUStats()`, making the data available for future capability-aware logic.
- **Documentation**: Added explanatory comment to the fan zero-RPM clamp threshold (50°C conservative floor).

## [1.6.0-beta5]

- **Sampling Policy Correction**: Corrected `MonitorSamplingPolicy` foreground target interval values for deterministic per-tick sampling (functionally identical with 1s interval).
- **Menu Bar Block Alignment Fix**: Adjusted `legacyBlockAttachmentNudge` from -1.2 to -0.25 on macOS < 27 for centered menu bar metric blocks.
- **Disk Sampler Deadlock Fix**: Fixed a potential deadlock in `DiskSampler.runDiskutilInfo` by redirecting stderr to `/dev/null` and reading pipe output before `waitUntilExit()`.

## [1.6.0-beta4]

- **Full GPU Kext Pipeline**: Complete AMD GPU monitoring pipeline from kernel PCI BAR MMIO registers to the RyzenStatus UI via `AMDGPUDevice` class with multi-GPU detection (Sea Islands through Navi 3x).
- **GPU UserClient Selectors**: Implemented UserClient selectors 27-30 for GPU count, temperature, power, and capabilities via `ProcessorModel.swift`.
- **GPU Temperature & Power Charts**: GPU temperature and power telemetry now displayed in Dashboard detail views.
- **GPU-Aware Auto EPP**: `AutoEppService` detects active GPU gaming/rendering workloads to automatically apply performance EPP profiles.
- **GPU Temperature Alerts**: Debounced GPU temperature and power alerts integrated in `MonitorAlertService`.
- **Multi-GPU Support**: `SensorsView` and `SystemMonitor` updated to handle multiple discrete GPU devices via `GPUDeviceSnapshot` model.
- **Fan Curve GPU Input**: `FanCurveController` uses kext-reported GPU temperature directly without actor hop overhead.
- **Process List Flickering Fix**: Extended stale process cache lifetime from 2s to 60s, preventing process rows from disappearing during background `ps`/GPU sampling cycles.
- **Classic Card Breakdown Fix**: Eliminated background queue race condition in `SystemSection` breakdown refresh; CPU and GPU square cards are now tappable to expand the process list.
- **MonitorSamplingPolicy Test Alignment**: Corrected disk stride test expectations to match the current 8s background target interval (stride=4).

## [1.6.0-beta3]


- **Classic Cards Process List Fix**: Connected reactive notification listeners and prevented initial empty-state override when expanding CPU/GPU breakdown rows in Classic Cards view.
- **Process List Stability & Deterministic Sorting**: Implemented secondary PID sort in process breakdown lists to prevent row flickering and position jumping when process values are equal.
- **AMD GPU Process Detections**: Added kernel-level `pgrep` fallback for `WindowServer` and active Metal processes to guarantee non-empty GPU process breakdown on discrete AMD GPUs.
- **UI Expansion State & iStats Reactivity**: Retained expanded process lists across popover redraws and bound iStats widget process lists to reactive `@State` properties.

## [1.6.0-beta1]

- **PRE-FASE 0 Kext Sanity Check**: Dynamic detection of `AMDRyzenCPUPowerManagement.kext` and `SMCAMDProcessor.kext` at launch. Runs gracefully in degraded read-only mode with UI warning banner instead of forcing app termination when kexts are missing.
- **Classic Menu Bar Appearance**: Added 0% CPU/GPU overhead `.classic` menu bar appearance option.
- **32-Thread SMT Dashboard & CCD Breakdown**: Full 32-logical-thread core grid support with distinct CCD0 and CCD1 temperature telemetry (`ccd0Temperature`, `ccd1Temperature`).
- **Combined Metric Graph**: Dual-axis overlay of Peak CPU Frequency (GHz) over CPU Load (%) in metric detail views.
- **Critical Concurrency & Fan Control Fixes**: Bounds check on `telemetry.metric[1]`, `@MainActor` safety in `Task.detached`, and nonisolated synchronous fan reset on app termination.
- **Batched IOKit GPU Queries**: Replaced 6 individual `IOAccelerator` property queries with single-pass `readAllIOAcceleratorStats()`.
- **Telemetry Logger & Thermal Alerts**: Buffered async telemetry CSV/JSON logger with 10s rate-limiting, plus sustained (>30s) thermal throttling alert notifications.

## [1.5.6]

- **BTop Cyberpunk Network Sparkline Fix**: Replaced Swift Charts ordinal rendering with native `Sparkline` path engine, resolving sparkline loops and diagonal line artifacts.
- **Per-Core Dashboard Grid Alignment**: Fixed text wrapping (`47%`) and frequency truncation (`4680MHz`) in per-core cards with 52px fixed-height cell geometry.
- **Detached Popover Re-attach Handling**: Restored interactive popover view immediately upon clicking "Reattach to Menu Bar".
- **Full Multi-Language Localization**: Synchronized 11 locale files with 0 hardcoded strings, supporting English, Spanish, German, French, Italian, Turkish, Russian, Japanese, Korean, and Chinese.

## [1.5.5]

- **Audio Mixer Sleep/Wake Recovery**: Integrated `EngineRenderVerdict` & `CycleBox` IO proc render tracking to automatically detect and recover wedged audio mixer engines when the Mac wakes from sleep.
- **Crisp Graph Text Overlays**: Enlarge graph text overlays with `.heavy` bold typography and subtle outline stroke, preserving 100% graph bar visibility without dark box overlays.

## [1.5.4]

- **Clean Crisp Graph Text Overlay**: Removed black background box pill over graphs; enlarged text to `.heavy` bold font (`8.5pt` / `7.8pt`) with clean 4-directional outline shadow, preserving 100% graph bar visibility while making numbers sharp and legible.

## [1.5.3]

- **High-Contrast Graph Numerical Overlay**: Rendered a dark capsule background pill (`black 0.68 alpha`) with a 4-direction outline stroke behind numerical text overlays in menu bar graphs (Histogram, Donut/Pie, Sparkline), guaranteeing 100% legibility on light and dark menu bar themes.

## [1.5.2]

- **Persistent Hidden Fans State**: Saved hidden fan selections (`HiddenFanIDs`) to `UserDefaults`, ensuring hidden fans remain hidden when switching tabs in Settings or restarting the app.

## [1.5.1]

- **Localization of AMD Power Control Views**: Fully localized all labels, headers, tooltips, mode badges, and footers in `AmdControlSection` and `AmdPowerSettingsView` via new `AMDPowerFeatureStrings`, ensuring seamless English and Spanish UI rendering.

## [1.5.0]

- **OpenCore Boot-Arg Guidance Banner**: Added an inline informational banner in the Fans & Cooling settings section reminding users that manual fan speed control requires boot-arg `-amdpnopchk` in OpenCore `config.plist` and `SMCAMDProcessor.kext` v3.33.8+.

## [1.4.9]

- **Fixed Manual Fan Override Reset**: Resolved bug in `FanCurveController` background loop that was automatically resetting manual fan slider overrides to BIOS control every 2 seconds, allowing manual fan speed overrides (100%, etc.) to take full effect on hardware.

## [1.4.8]

- **Manual Fan Slider Target Hold**: Protected manual slider value from being reset by telemetry polling cycles in `FansSettingsView`, keeping user-selected fan speed overrides (100%, etc.) locked on screen and hardware.
- **Fan Control Picker State Sync**: Synced fan control picker status dropdown with real-time manual override state (`Manual Override` vs `BIOS / Auto`) to eliminate UI mode discrepancies.

## [1.4.7]

- **Hardware Usage Header Space Reclamation**: Removed redundant "Hardware usage" section title to maximize vertical screen space in the main popover panel.
- **Fan Control IOKit Call Deduplication**: Deduplicated setFanSpeed kernel calls in `FanCurveController` to prevent SuperIO LPC bus contention and eliminate crashes in external monitoring tools like AMD Power Gadget.
- **Reliable Fan Manual Override**: Custom slider binding ensures fan control mode only switches to manual when physically dragged by the user, preserving BIOS / Auto control upon opening settings or refreshing telemetry.

## [1.4.6]

- **Numerical Value Overlay Inside Menubar Graphs**: Option to render real-time numerical readings (`42%`, `17.2G`, `50°`) directly inside status bar graphs (Histograms, Sparklines, and Donut Pies).
- **Fan Control Auto/Manual Binding Fix**: Resolved automatic fan mode override bug in `FansSettingsView` so opening options or polling updates does not switch fans away from BIOS / Auto control.
- **Eliminated Top Popover Blank Gap**: Removed top padding gap under the popover arrow to maximize vertical space.
- **Universal SuperIO Fan Control**: Corrected manual/auto mode selector sequence for complete compatibility across all SuperIO chips (ITE, Nuvoton, Fintek) and multi-fan configurations.

## [1.4.5]

- **Restored Glass Card Footer Buttons**: Restored the original rounded glass cards with stroke borders for `Ajustes` and `Salir` footer buttons in the main panel.
- **Fixed Header Blank Space**: Removed empty update banner padding and optimized top padding under the popover arrow.
- **Always-Visible Percentage Threshold Colors**: Made Normal, Medium, and High percentage color threshold pickers always accessible in Settings across all graph modes (Bars, Histograms, Sparklines, and Pies).

## [1.4.4]

- **Full 13-Language Internationalization for iStats**: Added native compiler-checked translations for all 13 supported languages across CPU, Cores, Memory, GPU, and Process List headers.
- **Vertical Graph & Rate Labels**: Uniform stacked vertical labels (`CPU`, `NET`, `GPU`, `RAM`) on status bar graphs and rates.
- **Sleek Scrollbar-Free Popover Layout**: Hidden ugly system scrollbars over cards for a clean Control Center aesthetic.
- **Compact Branding Header**: Reduced AMD top logo and header padding to give 20px+ extra vertical room for monitoring data.

## [1.4.3]

- **RAM Process List & iStats Drag & Drop Reordering**: Added top RAM process list inside Memory card with app icons and GB/MB units. Added native drag-and-drop handles (`PanelDragHandle`) in **Edit Mode** so you can reorder all iStats cards (`CPU`, `Cores`, `Memory`, `GPU`) freely.
- **Dynamic GPU Spoofing & Multi-Core Adaptation**: GPU card dynamically calculates real VRAM, model names, and adaptive clock frequency scaling for spoofed GPUs. Core grid rendering scales dynamically for any CPU topology (4 to 64 cores/threads).
- **Individual Per-Metric Style Pickers in Settings**: Added an "Estilo Individual por Métrica" section in **Ajustes -> Monitoreo** for independent graph customization across 12 languages.

## [1.4.2]

- **Individual Per-Metric Style Pickers in Settings**: Added an "Estilo Individual por Métrica" section in **Ajustes -> Monitoreo**, allowing you to set distinct graph styles for CPU, GPU, Memory, Network, and Disk independently right from the preferences UI.

## [1.4.1]

- **Fixed iStats Card Visibility & Edit Mode Toggling**: Connected `sysCPU`, `sysMemory`, and `sysGPU` AppStorage keys to the iStats widget view and added `PanelInlineHideButton` eye icons when in **Edit Mode** so you can easily hide/show CPU, Memory, or GPU cards directly in iStats mode.

## [1.4.0]

- **iStats CPU & GPU Process Lists**: Added top process list breakdowns directly inside the CPU and GPU popover widget cards, featuring real-time app icons, app names, and precise % CPU / % GPU consumption matching the iStats Menus visual design.

## [1.3.9]

- **Clean Popover UI & Edit-Mode Style Selector**: Hidden the `[ Tarjetas | iStats ]` popover style picker from the main popover view. It now only appears when entering **Edit Mode** (or in Settings), keeping the default popover interface clean and elegant.
- **iStats Memory Card Redesign**: Upgraded the Memory card widget with twin Donut meters (`PRESSURE` & `MEMORY`) and a detailed breakdown list showing App, Wired, Compressed, and Free memory in monospaced GB units.

## [1.3.8]

- **Independent Per-Metric Menu Bar Graph Customization**: Configured `MenuBarRenderer` to resolve graph appearance styles independently for each active metric (`cpu`, `gpu`, `memory`, `network`, `diskUsage`). You can now mix and match graph types across metrics (e.g. CPU Core Histogram + GPU Donut Ring + Network Dual Graph + RAM Values).

## [1.3.7]

- **Per-Core CPU Histogram in Menu Bar**: Added a real-time per-core CPU load histogram widget for the Menu Bar. Displays individual load bars for all 16 physical cores (32 threads) inside a framed mini-container directly in the status bar when Histogram mode is selected.

## [1.3.6]

- **iStats-Style Popover Widgets & Graph Appearances**:
  - **Popover Widget View**: Added an optional iStats-style widget mode in the Popover featuring per-core load histograms, donut ring core grids (for all 16 cores / 32 threads), twin memory pressure donuts, and GPU circular gauges.
  - **Menu Bar Graph Styles**: Expanded Menu Bar appearance options to support Text Values (`values`), Usage Bar Capsules (`bars`), Donut Rings (`pie`), Real-Time Line Graphs (`sparkline`), and Bar Histograms (`histogram`).

## [1.3.5]

- **Peak-Hold CPU Frequency Smoothing**: Implemented a Peak-Hold decay filter for the Peak CPU Frequency indicator. Instant single-core boosts (e.g. 4.8 GHz) are caught immediately and decay smoothly instead of jumping erratically, ensuring the peak frequency (top line) is mathematically guaranteed to stay equal to or higher than the average frequency (bottom line).

## [1.3.4]

- **Dashboard Telemetry Enhancements**: Connected real live telemetry history buffers for CPU/GPU Temperature, CPU/GPU Power, and CPU Frequency, replacing static/simulated placeholders with real-time graphs and 1-decimal live headers.

## [1.3.3]

- **Frequency Rounding**: Rounded menu bar and system panel frequency indicators to 1 decimal place (e.g. `4.7G` / `4.2G` instead of `4.73G` / `4.22G`) for cleaner visual presentation.

## [1.3.2]

- **Process List Refresh Rate & Ghost Elimination**: Eliminated ghost/terminated processes by filtering dead PIDs (`kill(pid, 0)`), updating breakdown rows unconditionally when idle, and added a user-configurable **Process List Refresh Rate** setting (1.0s, 2.0s, 3.0s, 5.0s) in Settings -> Monitor.

## [1.3.1]

- **Default Popover Tab Fix**: Configured the menubar popover panel to open on the first tab (`.system` / CPU System Monitor) by default instead of defaulting to the last tab (`.keepAwake`).
- **GPU Process List Optimization**: Enhanced process tracking for AMD Radeon GPUs under Metal and Vulkan.

## [1.3.0]

- **Easter Egg Movie Quotes**: Added an interactive random classic movie quote in the bottom-right corner of the Support settings tab. Click the quote to cycle through quotes.

## [1.2.9]

- **Menu Bar Usage Capsules Fix**: Guaranteed a minimum 1-step fill indicator for active CPU, GPU, and RAM usage bars to prevent empty transparent capsules when load is light.
- **Auto-updated Release Notes**: Synced changelog notes across builds and settings.

## [1.2.8]

- **Metric Cards Truncation Fix**: Replaced integer truncation with rounded percentage formatting for sub-1% CPU and GPU metrics in panel cards.

## [1.2.7]

- **AMD GPU Utilization & CPU Sampling**: Fixed AMD Radeon Navi 21 IOKit property parsing (`NSNumber`/`Double`/`UInt64`) and added fallback to SMCAMDProcessor driver telemetry. Implemented physical core load average fallback for uninterrupted CPU percentage reporting.

## [1.0.6]

- **Fan control overhaul**: Fixed critical bugs in the kext SuperIO drivers (ITE 86XXE, Nuvoton NCT67XX/NCT668X) — RPM-to-PWM fallback now correctly estimates fan speed in Auto mode so the slider shows the actual RPM percentage instead of 0%.
- **Fixed `getFanAutoControlMode` for ITE chips**: Now properly checks bit 7 (SmartGuardian) instead of any non-zero byte — the app correctly distinguishes Auto vs Manual mode.
- **Fixed throttle parsing in the app**: Selector 94 data is now correctly parsed (bits 15:8 = throttle, bit 0 = autoFlag) instead of reading the wrong byte.
- **Fixed fan slider behavior**: No more snap-back, no more disappearing Reset to Auto button, no more inverted Max Speed/All Auto buttons.
- **Restored `setDefaultFanControl` ext register write**: Restoring Auto mode properly resets the PWM register for ITE chips, preventing inverted Max Speed/All Auto behavior.
- **Added peak RPM tracking**: The kext dynamically tracks each fan's peak RPM for accurate PWM estimation in Auto mode.
- **Added custom branding**: App icon, menu bar icon, and AMD images properly included in the bundle.
- **Updated DMG build**: Now includes Kexts folder with the updated kexts for easy installation.

## [1.0.5]

- **Redesigned AMD Fans & Cooling panel** to match AMD Power Gadget's exact layout — slider, control mode picker, RPM display, and Reset to Auto button.
- Added `didDrag` flag to keep the Reset to Auto button visible until the kext confirms the override.
- Simplified the slider to use `fan.throttle` directly (the kext now reports meaningful throttle values in both Auto and Manual modes).
- Removed hardcoded `rpmRef=2500` — the slider no longer uses an inaccurate RPM-to-PWM calculation.

## [1.0.4]

- Redesigned AMD dashboard with AMD Power Gadget's exact layout.
- Fixed process list collapse bug: CPU and GPU process lists no longer show the same data when both expanded.

## [1.0.3]

- **Fan Renaming**: You can now click on a fan's name in the AMD Fans & Cooling tab to assign it a custom name. Names are saved automatically.
- **Thermal Context**: Added the current CPU temperature reading directly to the top of the AMD Fans & Cooling tab so you can monitor heat while tweaking fan curves and speeds.

## [1.0.2]

- Added dynamic CPU architecture detection: now correctly differentiates between legacy (Zen/Zen+) and modern (Zen 2+ CPPC) processors for P-State support.
- Fixed a critical crash (Actor isolation) when accessing P-States on modern architectures.
- Removed legacy branding and assets from the update showcase view.

## [1.0.1]

- Fixed an issue where CPU core frequencies were displaying as 0 MHz.
- Added CCD temperature readings to the main monitoring dashboard.
- Updated the update checker repository to point to DrogaBox/ryzenstatus-utils.
- Added high-resolution application icons.

## 1.0.0

- Initial release of RyzenStatus
