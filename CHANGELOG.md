# Changelog

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
