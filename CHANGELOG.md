# Changelog

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
- **Screenshot Sharing Disabled by Default**: RyzenStatus no longer uploads screenshots to a third-party server (`screenshots.vorssaint.com`) that we do not control. Sharing now requires a developer-configured server endpoint; the share buttons stay disabled until one is set up.
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
