# RyzenStatus — Fans system: independent audit + redesign spec (READ-ONLY)

You are the **independent architect** on a three-agent team rewriting the fan & cooling control system of **RyzenStatus** (macOS menu-bar app, Swift 6, SwiftUI, macOS 14+). A second agent (Gemini) will implement a total rewrite; a third agent will orchestrate and cross-check. Your job: **produce the diagnostic + design contract they will build against**. This is a READ-ONLY task — do NOT edit any file. Report only.

The user's complaints about the current fan system: **slow, inaccurate, and hard to understand and use.**

## Your deliverables

### 1. Independent diagnosis (evidence-based)
Read these and audit them:
- `Sources/RyzenStatus/Services/AMD/FanCurveController.swift` (the userspace control loop)
- `Sources/RyzenStatus/Services/AMD/FanCurveModels.swift`
- `Sources/RyzenStatus/Services/AMD/AMDFanCurvePresets.swift` (incl. `AMDFanCurveInput` packing)
- `Sources/RyzenStatus/UI/Settings/FansSettingsView.swift` and `FanCurveEditor.swift`
- `Sources/RyzenStatus/Services/AMD/ProcessorModel.swift` fan section (~L1359-1445)
- `Sources/RyzenStatus/Core/AMDKextSelectors.swift`
- The kext's native fan-curve driver: `SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/AMDRyzenCPUPowerManagement.cpp` (~L1560-1620) + `AMDRyzenCPUPMUserClient.cpp` (selectors 95/96/101/102) + `AMDRyzenCPUPowerManagement.hpp` (`MAX_FAN_CURVES`, `FanCurveConfig`)

For each of the user's three complaints (slow / inaccurate / hard to use), list concrete causes with file+line evidence. Specifically evaluate:
- The 2-second `Task.detached` control loop and its latency, CPU cost, and IOKit churn.
- The hypothesis that the app **re-implements in userspace** (its own LUT eval, `stepPWM`, `applyHysteresis`) what the kext already does **natively in-kernel** (EMA smoothing, LUT lookup, hysteresis, ramp limiting, per-fan mapping via selectors 101/102) — and whether the kext-native path has any callers at all.
- Read accuracy: RPM read-back (selector 93), the `throttle<<8 | autoFlag` decode (selector 94), temperature sourcing fallback chains, the 1.5 s UI poll timer.
- UX confusion: the -1/-2 sentinel-tag dropdown, overlapping "BIOS/Auto" / "Manual Override" / "Curve" states, the hidden fan list, hardcoded English strings, the "auto-map first curve" magic.
- State bugs: ghost states between UI bookkeeping and kext reality, reset-to-auto paths (AppDelegate quit hook), privilege-error handling.

### 2. Redesign spec (the contract)
Produce a precise, implementation-ready spec the rewrite must satisfy:
- **Architecture**: should the kext's native curve driver (selectors 101/102) be the primary control path, with userspace limited to telemetry/editing/mapping/manual override? Or argue for a different split — but justify it against the latency/accuracy/CPU evidence. Define the data flow end to end (curve edit → LUT pack → upload → fan map → kernel drives → read-back → UI).
- **State model**: explicit control-mode enum (Auto / Curve / Manual), per-fan snapshot with real kext state, single source of truth for settings (mirror `AmdSettingsStore`).
- **API surface**: the new controller's public API (what the views call), with signatures.
- **UI model**: per-fan card structure, curve list + editor with LUT preview and live temp marker, master toggle semantics, hidden/rename fans.
- **Error & privilege model**: how `kIOReturnNotPrivileged` and missing kext surface in the UI.
- **Safety invariants**: reset-to-auto on quit/disable, thermal guard, GPU-fan limitation, no second IOKit connection.
- **Migration plan**: which UserDefaults keys stay, which are renamed with a migration (following the repo's `migrateLegacy…`/`currentMigrationVersion` pattern).
- **Test plan**: the pure-logic checks that must land in the Foundation-only harness.

### 3. Compatibility checklist (the "do not break" list)
Confirm and itemize every app↔kext contract the rewrite must preserve:
- Selector numbers 90-96 and 101/102 and their argument shapes (from `AMDKextSelectors.swift` + the kext user client).
- The 272-byte packed `FanCurveInput` layout (4×UInt32 + 256×UInt8) and the kext's `structureInputSize != sizeof(FanCurveInput)` rejection.
- `MAX_FAN_CURVES = 4`; fan bounds (16, and `getNumberOfFans()`); curveIdx -1..3.
- Privilege semantics (`kIOReturnNotPrivileged` without root/`-amdpnopchk`).
- Kext version gate ≥ 1.0.0.
- Single IOKit connection via `ProcessorModel.safeIOConnectCallMethod` (LPC bus contention history).
- The menu panel fan read (`AmdControlSection`) that shares the same path.
- The 13-language localization contract in `FanControlFeatureStrings`.
- The `resetFansToAutoSync()` call on quit in `AppDelegate`.

### 4. Review checklist
A checklist with explicit PASS/FAIL criteria the orchestrator will use to evaluate Gemini's rewrite (per compatibility item + per design requirement + the three user complaints). Make each item falsifiable ("verify X in file Y").

## Report format
Sections: 1) Diagnosis with evidence · 2) Redesign spec · 3) Compatibility checklist · 4) Review checklist · 5) Anything in the current system you would KEEP as-is and why. Be opinionated and precise; no fluff.
