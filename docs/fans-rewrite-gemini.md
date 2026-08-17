# RyzenStatus — Fans system TOTAL REWRITE (from zero)

You are rewriting the **fan & cooling control system** of **RyzenStatus** (macOS menu-bar app, Swift 6, SwiftUI, macOS 14+ floor) **from scratch**. This is NOT a patch or refactor of the existing code: design a new system and implement it, deleting/replacing the old fan subsystem. The user's complaints are: **slow, inaccurate, and hard to understand/use**. Your rewrite must fix all three at the architectural level.

## Ground rules

- The repo is the source of truth; read files before writing. Preserve SPDX GPL headers, `///` doc comments, house patterns.
- Do NOT commit anything. Leave changes uncommitted for review.
- Do NOT modify the kext (`SMCAMDProcessor_Source/`) and do NOT change any IOKit selector, struct layout, or the app↔kext ABI. The rewrite is **app-side only**.
- All user-facing copy goes through the localization contract (see below). No hardcoded UI strings.
- Add/extend `./build.sh --test` harness checks for all pure logic (see Tests).
- Exactly one build at a time: never run `./build.sh` and `./build.sh --test` concurrently (`--test` starts with `rm -rf build`). Tests first, then the app build.

## The core problem you must fix (verified in the repo)

The kext `AMDRyzenCPUPowerManagement` already ships a **complete in-kernel fan-curve driver** (`SMCAMDProcessor_Source/.../AMDRyzenCPUPowerManagement.cpp` ~L1560-1620): per-fan curve mapping (`fanToCurveMap`), EMA temperature smoothing (alpha 0.2), 256-point LUT lookup, hysteresis, ramp-rate limiting, thermal guard (85 °C → ≥80 % PWM), running every SuperIO sample tick (sub-second, in kernel).

The current app (`Sources/RyzenStatus/Services/AMD/FanCurveController.swift`) **reimplements all of this in userspace**: a `Task.detached` control loop that sleeps 2 s per tick, re-derives hysteresis/ramp with its own `stepPWM`/`applyHysteresis`, evaluates the LUT in Swift, and writes PWM via IOKit every change (selector 95). The kext-native path (`ProcessorModel.setKextFanCurve` selector 101 + fan mapping selector 102) exists but has **zero callers**.

That duplication is why the system is slow (2 s latency), inaccurate (userspace re-derivation vs. kernel-native control), and wasteful (app CPU + IOKit churn every 2 s).

**Your architecture must make the kext's native curve driver the primary control path**: upload the user's curves as LUTs (selector 101) and map fans to curve slots (selector 102); the kernel then drives the fans at kernel speed with zero app involvement. Userspace keeps only: reading telemetry, editing/persisting curves, mapping UX, the manual-override slider (selector 95/96), and a light validation/watchdog. **Eliminate the 2-second userspace control loop.**

## Compatibility contract — DO NOT BREAK (verified against the kext source)

### IOKit selectors (Sources/RyzenStatus/Core/AMDKextSelectors.swift — must match kext exactly)
- 90 `fanInit`, 91 `fanCountRead`, 92 `fanName` (string), 93 `fanSpeedRead` (per-fan RPM as `UInt64` array), 94 `fanCtrlRead` (packs `throttle<<8 | autoFlag` per fan; autoFlag bit 0 = 1 Auto / 0 Manual).
- 95 `fanSpeedWrite` = `overrideFanControl(fanSel, pwm)` — scalar args `[fanIndex, pwm 0-255]`.
- 96 `fanModeWrite` = `setDefaultFanControl(fanSel)` — scalar arg `[fanIndex]`, restores BIOS/Auto.
- 101 `fanCurveLUTWrite` — struct input (see ABI below).
- 102 `fanToCurveMap` — scalar args `[fanIndex, curveIndex]`; `curveIndex = -1` unmaps and restores auto. Kext bounds: `fanIdx < 16` and `< superIO->getNumberOfFans()`; `curveIdx in [-1, MAX_FAN_CURVES)`.

### Struct ABI (do not change)
- `AMDFanCurveInput` (Sources/RyzenStatus/Services/AMD/AMDFanCurvePresets.swift) = **272 packed bytes**: `curveIndex UInt32, sourceSensor UInt32, hysteresis UInt32, rampRate UInt32` + `lut[256] UInt8` (index = °C, value = PWM 0-255 on the SMC scale). The kext rejects any input where `structureInputSize != sizeof(FanCurveInput)` (packed, little-endian — host order is correct on macOS).
- `MAX_FAN_CURVES = 4` (kext hpp L84). Kext defaults: hysteresis 2, rampRate 5, `curveSmoothedTemp = 40.0f`.
- The kext's `FanCurveConfig` (hpp L85) is `{ uint8_t lut[256]; uint8_t sourceSensor; uint8_t hysteresis; uint8_t rampRate; }` — you do not touch it, but your app-side curve model must map onto it 1:1 when packing.

### Privilege & safety (preserve the existing semantics)
- All write selectors (95/96/101/102) return `kIOReturnNotPrivileged` (0xe00002c1) without root or the `-amdpnopchk` boot-arg. `ProcessorModel.privilegeHint(for:)` exists; surface privilege errors clearly in the UI (as `AmdPresetController` does for power presets).
- The kext enforces a thermal guard (85 °C → ≥80 % PWM); do not fight it in userspace.
- GPU fan: never controllable (vBIOS owns it). GPU-temp-sourced curves can only drive case/CPU headers; the kext falls back to CPU temp when GPU temp is unavailable — your model/UI must reflect this.
- On quit/termination the app MUST restore every mapped/overridden fan to automatic control (currently `AppDelegate` calls `FanCurveController.shared.resetFansToAutoSync()`). Preserve this guarantee with the new architecture (also on settings-window close, toggle off, and app terminate).
- Keep the kext version gate (≥ 1.0.0, alert+quit if older) and the single IOKit connection via `ProcessorModel` (`safeIOConnectCallMethod` + `iokitLock`). **Never open a second IOKit connection** (SuperIO/LPC bus contention — the repo history records crashes in external tools like AMD Power Gadget from duplicated calls).

### Persistence (keep keys; migrate only if you rename)
- `customCurves` — JSON `[FanCurve]` (Codable: `id` UUID, `name`, `points` [{id UUID, temp, pwm}], `sourceSensor` 0=cpu/1=gpu, `hysteresis`, `rampRate`; custom CodingKeys exclude the cached LUT).
- `fanMappings` — JSON `[Int:Int]` fanId → curveIndex (-1 = auto).
- `fanCurvesEditorEnabled` — Bool master toggle (DefaultsKey).
- `HiddenFanIDs` — `[Int]`; `FanName_<fanId>` — String. (Raw keys; either keep or migrate via `Defaults.migrateLegacy…` following the existing v6 pattern and `currentMigrationVersion`.)
- The menu panel `AmdControlSection` (Sources/RyzenStatus/UI/MenuPanel/AmdControlSection.swift ~L346) reads fan RPMs through `ProcessorModel` — keep that read path working.

### Localization contract
- `FanControlFeatureStrings` in Sources/RyzenStatus/Core/FanControlStrings.swift — 13-language memberwise init (pt-BR + en-US in FanControlStrings.swift, 12 more in Core/Localizations/). The current UI hardcodes many English strings ("SMC Fan Control", "Loading fan sensors…", "BIOS / Auto", "Manual Override", "Curve:", "↩ Reset to Auto", "Override", "Dynamic Next-Gen Fan Curves", the GPU guide, etc.) — your rewrite must route ALL user-facing copy through the contract: reuse existing keys where they fit, extend the struct with new keys, and fill every language. A missing key breaks compilation.

## Files you own (rewrite/replace)

- `Sources/RyzenStatus/Services/AMD/FanCurveController.swift` — replace with your new controller (no 2 s loop).
- `Sources/RyzenStatus/Services/AMD/FanCurveModels.swift` — replace the model layer (clean `ControlMode` enum instead of -1/-2 sentinels; snapshot type with real kext state: actual mode, target vs actual PWM, RPM).
- `Sources/RyzenStatus/Services/AMD/AMDFanCurvePresets.swift` — keep `AMDFanCurveInput` packing (ABI) and the preset anchors; refactor only if it helps.
- `Sources/RyzenStatus/UI/Settings/FansSettingsView.swift` — rewrite the UI: per-fan cards with ONE clear control-mode selector (no overlapping badge + dropdown + slider states), live RPM vs target, obvious "what drives this fan", master toggle semantics preserved, hidden-fans + renaming preserved.
- `Sources/RyzenStatus/UI/Settings/FanCurveEditor.swift` — rewrite: curve list with LUT preview, point editing, hysteresis/ramp, sensor source; make it understandable at a glance.
- `Sources/RyzenStatus/Core/FanControlStrings.swift` + the 12 language files — extend the contract with every new string.
- `Tests/MetricsTests.swift` + `build.sh` harness file list — add pure-logic checks (see Tests).
- Touch `Sources/RyzenStatus/App/AppDelegate.swift` only if the reset-to-auto-on-quit call must be renamed.
- Keep `ProcessorModel`'s fan I/O as-is (it is the ABI bridge); you may add thin wrappers in your controller but never bypass `safeIOConnectCallMethod`.

## Design requirements

1. **Primary path = kext-native curves**: on any curve edit/mapping change, pack the LUT and upload (selector 101), then map fans (selector 102). The kernel does the control. No per-tick userspace PWM writes for curve mode.
2. **Manual override stays explicit**: the slider (selector 95) + "restore auto" (selector 96) only while the user is actively overriding; state comes from the kext read-back (selector 94), not from app-side bookkeeping.
3. **One source of truth** for settings (mirror `AmdSettingsStore`/`AmdPresetController` patterns): no scattered `UserDefaults` writes, no ghost states.
4. **Fast, accurate reads**: reuse the zero-copy telemetry path (`ProcessorModel.getTelemetry()`, selector 100, `CPUSensorPacket`) and kext GPU temps; no 1.5 s `Timer` polling in the settings view if a single-shot refresh + change-driven updates suffice; never block the main thread on IOKit.
5. **Understandable UX**: the user should see, per fan: current RPM, current mode (Auto / Curve "name" / Manual 42 %), which temperature feeds it, and one obvious control. No sentinel-tag dropdowns. The curve editor should preview the LUT and show where the current temp sits on the curve.
6. **Safety invariants preserved**: reset-to-auto on quit/disable; never write a curve slot ≥ 4; never map a fan that the kext rejects; surface `kIOReturnNotPrivileged` clearly; GPU-fan messaging kept.
7. **Testable**: pure functions (LUT interpolation, packing round-trip of the 272-byte struct, mapping compaction, mode-state machine, migration) go in the Foundation-only harness.

## Tests (extend the harness — no XCTest, no AppKit)

Follow the existing `check(...)`/counter style in `Tests/MetricsTests.swift`. At minimum:
- `AMDFanCurveInput` packing: 272 bytes, field offsets, little-endian, LUT padded/trimmed to 256.
- LUT interpolation boundaries (clamp before first / after last anchor, segment interpolation, 0-255 clamp) — reuse the existing preset interpolation tests as a base.
- Hysteresis/ramp math if you keep any userspace stepper (you may drop it — then say why).
- Mapping: compact-on-delete, unmap (-1), out-of-range → auto.
- Migration of the legacy/raw defaults keys if you rename any.
- Mode-state machine (Auto → Curve → Manual → Auto) if you model it as a pure enum.

## Deliverables (final report)

1. Architecture summary: what you deleted, what you built, and how the kext-native path replaces the userspace loop.
2. Compatibility checklist: each item of the contract above with "preserved" + evidence (file/line).
3. Files touched with line counts; new/removed files.
4. Tests added + new total check count (`./build.sh --test` result).
5. App build result (`./build.sh`).
6. Anything you deliberately left out and why.
