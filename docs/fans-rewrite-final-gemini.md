# RyzenStatus — Fans system: FINAL implementation order (total rewrite)

You are implementing the **total rewrite of the fan & cooling control system** of **RyzenStatus** (macOS menu-bar app, Swift 6, SwiftUI, macOS 14+). This order is the result of three independent audits (architecture/UX, hardware-correctness, and the repo maintainer) — every requirement below is **verified against the kext source and the repo**. Implement exactly this; do not relitigate. The user's complaints: **slow, inaccurate, hard to understand and use** — the rewrite fixes all three at the architectural level.

## Ground rules

- Read the repo files before writing. Preserve SPDX GPL headers, `///` doc comments, house patterns.
- **App-side only**: do NOT modify `SMCAMDProcessor_Source/` and do NOT change any selector, struct layout, or app↔kext ABI.
- Do NOT commit. Leave changes uncommitted for review.
- All user-facing copy through the localization contract (13 languages). No hardcoded UI strings.
- Builds: exactly one at a time. `./build.sh --test` first (it does `rm -rf build`), then `./build.sh`. Never concurrently.

## Architecture mandates (non-negotiable)

1. **Kext-native curves are the ONLY curve-control path.** Upload LUTs via selector 101 and map fans via selector 102. The kext's `evaluateFanCurves()` (500 ms kernel cadence, EMA α=0.2, LUT lookup, hysteresis, ramp limit, thermal guard 85 °C / PWM 200) drives the fans. **Delete the 2-second `Task.detached` userspace control loop** (`FanCurveController.controlTask`) and its `stepPWM`/`applyHysteresis` math entirely — they are dead code; the kext owns ramp and hysteresis.
2. **Manual override = one-shot writes only**: slider drag → debounce ~60 ms → `setFanSpeed` (selector 95); release/reset → `setFanMode(auto:)` (selector 96). No loop, no periodic re-write.
3. **Wake handling**: on `NSWorkspace.didWakeNotification`, re-upload all active curves (selector 101) and re-apply mappings (selector 102). Keep the observer pattern from the current controller.
4. **GPU temperature injection (selector 103 — NEW)**: the kext exposes `case 103` (scalar float, clamped [0,120] °C, requires privilege) that writes `provider->gpuTempC` used by GPU-sourced curves. The kext also self-updates it from its own GPU readings, but on machines where the kext lacks GPU detection the app has better data (IOAcceleratorCache). **Add `gpuTempWrite = 103` to `AMDKextSelectors`, add a `setKextGPUTemp(_:)` wrapper in `ProcessorModel`, and push the app's GPU temperature periodically while any GPU-sourced curve is active** (fall back gracefully if the call fails — it is an enhancement, not a hard dependency).
5. **UI state must come from kext read-back** (selector 94 `throttle<<8 | autoFlag`), never from app-side bookkeeping, for display. Persistence keeps the user's *intent*; the kext is the source of truth for reality.
6. **No second IOKit connection**: every call through `ProcessorModel.shared.safeIOConnectCallMethod` + `iokitLock`. Do not bypass.

## Compatibility contract — DO NOT BREAK (verified)

- Selectors (AMDKextSelectors.swift must match kext): 90 fanInit, 91 fanCountRead, 92 fanName (string), 93 fanSpeedRead (RPM, UInt64 array; kext refreshes hardware every 4th call), 94 fanCtrlRead (`throttle<<8 | autoFlag`, bit0 1=Auto; kext calls `updateFanControl()` every 4th read), 95 fanSpeedWrite `[fanIndex, pwm 0-255]`, 96 fanModeWrite `[fanIndex]` (restore default/auto), 101 fanCurveLUTWrite (272-byte struct), 102 fanToCurveMap `[fanIndex, curveIndex]`, **103 gpuTempWrite `[float bitPattern]` (NEW)**.
- `AMDFanCurveInput` = 272 packed bytes: `curveIndex UInt32, sourceSensor UInt32, hysteresis UInt32, rampRate UInt32` + `lut[256] UInt8`. Kext rejects `structureInputSize != sizeof(FanCurveInput)`. Little-endian host order. **Keep `packedData()` as-is; add unit tests locking the bytes.**
- `MAX_FAN_CURVES = 4`. fanIndex `< 16` AND `< superIO->getNumberOfFans()`. curveIndex in [-1, 3]; `-1` crosses as `UInt64(bitPattern: Int64(-1))`.
- Writes (95/96/101/102/103) return `kIOReturnNotPrivileged` (0xe00002c1) without root or `-amdpnopchk`. Read selectors always work.
- Kext version gate ≥ 1.0.0 stays (alert+quit if older).
- Persistence keys: `customCurves` (JSON `[FanCurve]`), `fanMappings` (JSON `[Int:Int]`, -1=auto), `fanCurvesEditorEnabled` (Bool, DefaultsKey), `HiddenFanIDs` (`[Int]`), `FanName_<id>` (String). The menu panel `AmdControlSection` (~L346) reads fans via `ProcessorModel` — keep that read path working.
- `AppDelegate` (~L186) calls the reset-to-auto on quit — keep the call site; the method must remain `nonisolated` and synchronous.

## Numeric contract (from the hardware-correctness audit — implement exactly)

| Value | UI/App scale | Kext scale | Conversion | Clamp |
|---|---|---|---|---|
| LUT point | 0-100 % | 0-255 PWM | **Convert anchors to 0-255 first** (`round(pwm*2.55)` on each anchor), interpolate in Double 0-255, then `.rounded()` per LUT entry | 0...255 |
| rampRate | 1-20 %/s | PWM units/s (0-255) | `round(rampRate * 2.55)` | 1...255 |
| hysteresis | 1-5 °C | °C (uint8) | identity | 1...255 |
| manual PWM (95) | 0-100 % | 0-255 | `round(pwm * 2.55)` | 0...255 |
| curveIndex | -1...3 | -1 or 0...3 | `UInt64(bitPattern: Int64(-1))` for auto | reject others |
| fanIndex | 0...N-1 | 0...N-1 | identity | <16 and <getNumberOfFans() |

Why LUT conversion order matters: interpolating in 0-100 then converting (`round(v*2.55)`) quantizes endpoints (33 % → 84) and can flatten slopes; converting anchors first then interpolating in 0-255 matches the shipped `AMDFanCurvePreset.interpolate` and the kext's `(int)(smoothed + 0.5f)` rounding exactly. **Test both orders and assert equality with the anchor-convert-first result.**

Kext behaviors you MUST account for (verified in `evaluateFanCurves()`):
- **`targetPWM == 0` → `setDefaultFanControl()`**: a 0-PWM LUT value returns the fan to BIOS control — it does NOT stop the fan. The curve editor must either clamp the minimum PWM to 1 (≈0.4 %) or explicitly label 0 as "Auto/BIOS" in the UI. Pick one and state it.
- **`currentPWM == 0 && targetPWM != 0` skips the ramp limit**: a stopped fan jumps instantly to target. UX note only (can't fix app-side).
- **Hysteresis is falling-only and compares raw temp vs previous EMA**: sharp drops (> hysteresis °C between kernel ticks) bypass the hold. Document this in the UI copy (don't promise hysteresis that doesn't exist on spikes).
- **Thermal guard uses RAW temp** (`rawSourceTemp >= 85.0f` → PWM ≥ 200). Do NOT re-implement the guard in Swift.
- **Do NOT "fix" the kext's ramp math** — an audit claim about `uint8_t` overflow in `(uint8_t)(currentPWM + limit)` is unreachable: the branch requires `target − current > limit`, so `currentPWM + limit < target ≤ 255`. Leave the kext untouched.

## State model & API (from the architecture audit — adopt this shape)

```swift
enum FanControlMode: Int, Codable, Sendable { case auto = 0, curve = 1, manual = 2 }

struct FanState: Identifiable, Sendable {
    let id: Int                       // SuperIO fan index
    var name: String
    var rpm: UInt64                   // selector 93
    var throttlePWM: UInt8            // selector 94 bits [15:8]
    var isKextAuto: Bool              // selector 94 bit 0
    var controlMode: FanControlMode   // derived + persisted
    var mappedCurveIndex: Int?        // 0-3, nil = auto
    var manualPWM: UInt8?             // non-nil in .manual
    var isHidden: Bool
    var customName: String?
}

struct FanCurveDefinition: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var kextSlot: Int                 // 0..<4, assigned on upload
    var points: [FanCurvePoint]       // edit-time (0-100 % PWM)
    var sourceSensor: FanSensor       // 0=cpu, 1=gpu
    var hysteresis: UInt8             // °C
    var rampRate: UInt8               // UI scale %/s — CONVERTED on pack
}
```

- Controller: `@MainActor final class FanController: ObservableObject` (singleton `shared`), `@Published` `fans`, `curves`, `privilegeError`, `kextMissing`; methods `saveCurve`, `deleteCurve`, `setFanMode(_:fanId:curveId:)`, `setManualPWM(_:fanId:)`, `resetAllToAutoSync()` (nonisolated, synchronous), `setAllAuto`, `setAllMaxSpeed`, `setCustomName`, `setHidden`, `startPolling/stopPolling` (1.5 s read-back, cancel in-flight before starting a new one — selectors 91/93/94 only).
- **`setFanMode` must never contain the current no-op bug**: the old `setFanMode(auto: false)` returned `true` without calling the kext. Manual mode = write selector 95; auto = selector 96 (+ selector 102 with -1 if the fan was curve-mapped). Track intent app-side, display reality from read-back.

## UI model

- **FansSettingsView**: privilege/kext banner on top (when `privilegeError != nil`); per-fan cards; "All Auto" / "Max Speed" (with confirmation) global actions; collapsible curve editor below.
- **FanControlCard**: editable name; RPM + PWM % badge; mode pill (teal Auto / orange "Curve: name" / cyan "Manual: %"); **one** mode selector (Auto / Custom Curve submenu / Manual — NO `-2` sentinel tags, NO overlapping states); manual slider visible only in `.manual`; "Reset to Auto" in `.manual`/`.curve`. **Wire every write's `kern_return_t`; on `kIOReturnNotPrivileged` set `privilegeError` and show inline guidance (root or `-amdpnopchk`).**
- **InteractiveFanCurveEditor**: curve tabs + name editing + Add/Delete (**max 4 curves**, enforce in UI); sensor segmented (CPU/GPU; GPU only when a discrete GPU exists); hysteresis slider 1-5 °C; ramp slider 1-20 %/s (converted on pack); 2-D canvas with draggable points (tap add, double-click/context delete), **live temperature marker** (vertical line at current sensor temp, updated each poll), **LUT preview** (thin gray line of the actual 256-point LUT that will upload), temperature axis 0-110 °C; 0-PWM handling per the numeric contract.
- **Menu panel (AmdControlSection)**: fan RPM visible by default (`showFansInAmdPower` default `true`), mode dot per fan.
- **"Auto-map first curve" magic**: when the master toggle turns on with no mappings, either prompt the user to pick fan+curve or show an explicit confirmation ("Fan 1 → Silent"). No silent magic.

## Localization

Extend `FanControlFeatureStrings` (Core/FanControlStrings.swift) with every new string and fill **all 13 languages** (enUS/ptBR in FanControlStrings.swift; tr, ru, es, de, fr, it, ja, ko, zhHans, zhTW, zhHK in Core/Localizations/). Existing keys stay. No hardcoded strings — the current UI's English literals ("SMC Fan Control", "BIOS / Auto", "↩ Reset to Auto", "Dynamic Next-Gen Fan Curves", GPU guide, etc.) all move into the contract. Memberwise init breaks compilation if a language is missed — that is the safety net.

## Migration (one-time, follow the existing `migrateLegacy…`/`currentMigrationVersion` pattern — currently v6 → bump)

- `customCurves` (JSON `[FanCurve]`) → new key (e.g. `customCurves_v2`, `[FanCurveDefinition]`): convert, assign `kextSlot` 0...3 sequentially, clamp hysteresis/rampRate to UInt8 (UI scale, converted on pack), then delete the old key.
- `fanMappings` (JSON `[Int:Int]`) → new keys for intent (`fanStates`, `fanCurveSlots`).
- Keep unchanged: `HiddenFanIDs`, `FanName_<id>`, `fanCurvesEditorEnabled` (DefaultsKey — do not rename).
- Idempotent; gate on the version flag; remove old keys after success.

## Tests (extend `./build.sh --test` harness — Foundation-only, no AppKit, no kext)

- `AMDFanCurveInput.packedData()`: 272 bytes, field order, little-endian, LUT pad/trim to 256.
- LUT conversion: anchors-convert-first vs interpolate-then-convert — assert equality with convert-first; clamp 0-255; monotonic anchors → monotonic LUT; single-point and empty curves.
- rampRate conversion: `round(x*2.55)` cases (1→3, 20→51, boundaries), clamp 1-255.
- Mapping: compact-on-delete, unmap -1, out-of-range → auto.
- Migration: `[FanCurve] → [FanCurveDefinition]` (name preserved, slots assigned, old key removed, idempotent).
- `FanControlMode` raw values stable (0/1/2).
- `FanState.controlMode` derivation from read-back fields.
- Localization completeness: all 13 languages satisfy the `FanControlFeatureStrings` memberwise init.

## Deliverables (final report)

1. Architecture summary: what you deleted (the loop, stepPWM/applyHysteresis), what you built, how kext-native replaces userspace.
2. Compatibility checklist: every contract row above with "preserved" + evidence (file:line).
3. Selector 103: how you wired GPU temp injection and its fallback.
4. Files touched with line counts; new/removed files.
5. Tests added + new total check count (`./build.sh --test`).
6. App build result (`./build.sh`).
7. The 0-PWM UX decision you made (clamp-to-1 vs label-as-Auto) and why.
8. Anything deliberately left out and why.
