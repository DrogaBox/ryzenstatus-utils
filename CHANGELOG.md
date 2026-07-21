# Changelog

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
