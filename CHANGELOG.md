# Changelog

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
