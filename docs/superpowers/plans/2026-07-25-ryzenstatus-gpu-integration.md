# RyzenStatus GPU Monitoring — Integration Plan

> **Date:** 2026-07-25
> **Updated:** 2026-08-07 — implementation verified against the codebase
> **Status:** ✅ Implemented (Tasks 1–6 complete). Task 7 (hardware verification) pending.

**Goal:** Replace IOAccelerator-based GPU readings with direct kext MMIO readings (selectors 27-30) for more reliable temperature, power, and multi-GPU support.

**Architecture:** ProcessorModel gains new kext GPU read methods; SystemMonitor uses them; UI layers (Dashboard, Sensors, Menu Panel) consume the same snapshot fields — no UI changes needed for basic integration.

## Implementation Summary

The plan is fully implemented and shipped (kext v3.34.0; app releases v1.8.0/v1.8.1, see CHANGELOG):

- **Kext** — `AMDRyzenCPUPMUserClient.cpp` implements selectors 27–30; `AMDRyzenCPUPowerManagement.cpp` detects up to 16 `AMDGPUDevice` entries and samples MMIO temperature/power; `AMDGPU.cpp` performs the MMIO reads.
- **App** — `ProcessorModel` exposes the four `getKextGPU*()` read methods plus a thread-safe `GPUCache`; `SystemMonitor` builds per-GPU `GPUDeviceSnapshot`s and uses kext data as the **primary** source for GPU temperature/power (overriding IOAccelerator); `SensorsView` and `Dashboard` render per-GPU rows/cards, charts, and a multi-GPU selector; `FanCurveController` prefers `lastKextGPUTemperature`.

> **Deviations from the original plan (implementation choices):**
> - Kext GPU fields were **not** added to `TelemetrySnapshot`; they live in the nonisolated `GPUCache` on `ProcessorModel` so `SystemMonitor` and the fan controller read them without actor hops.
> - `SamplingPlan` gained **no** `needKextGPU` flag; kext GPU reads are gated by the existing `needAMDPower` flag.
> - `GPUDeviceSnapshot.supportsPower` uses **bit 0 of the selector-30 capabilities bitmap** (`gpuCache.capabilities`), with the old `power > 0` heuristic as fallback for kexts that do not report capabilities. Note: the kext packs each GPU's bitmap as a little-endian `uint64`, so `getKextGPUCapabilities()` reads `UInt64`s and reduces each slot to its low byte (per-GPU `UInt8` array).

## Current State

| Source | What it reads | Reliability |
|--------|--------------|-------------|
| SMC keys TGxx | GPU temperature | Good (when SMCAMDProcessor has them) |
| IOAccelerator PerformanceStatistics | Utilization, VRAM, fan, freq, power | Unreliable — often returns 0 or nil on AMD dGPUs |
| PowerCache (kext CPU power) | CPU package power | Good (already integrated) |
| **Kext selectors 27–30** | GPU count, temp, power, capabilities (MMIO) | **Primary source — integrated** |

## New Kext Selectors (27-30) — ✅ Implemented

| Selector | Output | Description |
|----------|--------|-------------|
| 27 | `scalarOutput[0] = gpuCount` | Number of AMD GPUs detected |
| 28 | `UInt16[gpuCount]` | GPU temperatures in SP78 format |
| 29 | `float[gpuCount]` | GPU power in watts |
| 30 | `uint64_t[gpuCount]` | Capabilities bitmap per GPU (bit 0 = supportsPower); Swift reduces each 8-byte slot to its low byte |

---

### Task 1: Add kext GPU read methods to ProcessorModel.swift — ✅ DONE

**Files:**
- `Sources/RyzenStatus/Services/AMD/ProcessorModel.swift`

**Status:** Completed. Implements the four read methods, a thread-safe `GPUCache` (count/temperatures/powers/capabilities), `refreshKextGPUStats()` called from `refreshPowerCache()`, and nonisolated accessors `lastKextGPUTemperature`, `lastKextGPUPower`, `lastKextGPUCount`.

- [x] `getKextGPUTemperatures()` → `[UInt16]` using selector 28
- [x] `getKextGPUPowers()` → `[Float]` using selector 29
- [x] `getKextGPUCount()` → `Int` using selector 27
- [x] `getKextGPUCapabilities()` → `[UInt8]` using selector 30
- [x] Thread-safe GPU cache: `GPUCache` (count, temperatures, powers, capabilities)
- [x] `refreshKextGPUStats()` called during telemetry refresh (`refreshPowerCache()`)
- [~] Stored properties on `ProcessorModel` + `TelemetrySnapshot` kext fields — *superseded by the nonisolated `GPUCache`*

---

### Task 2: Integrate kext GPU readings into SystemMonitor — ✅ DONE

**Files:**
- `Sources/RyzenStatus/Services/SystemMonitor/SystemMonitor.swift`

**Status:** Completed. The refresh loop builds `GPUDeviceSnapshot`s from the kext cache when `plan.needAMDPower` is set and overrides IOAccelerator-based `gpuTemperature`/`gpuPower` with kext values when > 0. IOAccelerator/SMC/APU fallbacks remain.

- [~] `SamplingPlan.needKextGPU` flag — *not added; kext reads gated by the existing `needAMDPower` flag*
- [x] Kext GPU read path alongside the existing IOAccelerator path
- [x] Priority: kext GPU values > IOAccelerator values > SMC TGxx values (kext wins; SMC/IOAccelerator remain as fallback)
- [x] `SystemSnapshot` includes kext GPU data (`gpuDevices`)
- [x] GPU history arrays (`gpuTempHistory`, `gpuPowerHistory`) fed from the final values
- [~] `readGPUUsage()` kext-power fallback — *utilization has no kext selector; keeps IOAccelerator with AMD snapshot fallback*

---

### Task 3: Add multi-GPU support to SystemSnapshot — ✅ DONE

**Files:**
- `Sources/RyzenStatus/Services/SystemMonitor/CoreSnapshot.swift`
- `Sources/RyzenStatus/Services/SystemMonitor/SystemMonitor.swift`

**Status:** Completed.

- [x] `GPUDeviceSnapshot` struct (index/temperature/power/supportsPower)
- [x] `gpuDevices: [GPUDeviceSnapshot]` on `SystemSnapshot`
- [~] Per-GPU history tracking — *single aggregate `gpuTempHistory`/`gpuPowerHistory`; no per-GPU history arrays*

---

### Task 4: Update SensorsView for multi-GPU — ✅ DONE

**Files:**
- `Sources/RyzenStatus/UI/Settings/SensorsView.swift`

**Status:** Completed. Kext devices render first (per-GPU temp + power), then global snapshot rows, then SMC TGxx sensors as fallback.

- [x] Show `SystemSnapshot.gpuDevices` as individual GPU entries
- [x] Keep existing TGxx SMC sensor display as fallback
- [x] Show GPU power per-device when available

---

### Task 5: Dashboard GPU cards refinement — ✅ DONE

**Files:**
- `Sources/RyzenStatus/UI/Settings/DashboardView.swift`

**Status:** Completed. `TopCardsView` prefers kext GPU temp/power; a multi-GPU row renders a card per device when `gpuDevices.count > 1`; `MainChartsView` includes "GPU TEMP" and "GPU POWER" charts.

- [x] `TopCardsView` uses kext GPU temp/power when available
- [x] Multi-GPU selector/cards when > 1 GPU detected
- [x] `MainChartsView` GPU temperature and power charts

---

### Task 6: Fan curves — GPU temp source — ✅ DONE

**Files:**
- `Sources/RyzenStatus/Services/AMD/FanCurveController.swift`

**Status:** Completed. The control loop prefers `ProcessorModel.shared.lastKextGPUTemperature`, then the `SystemMonitor` snapshot, then CPU temperature as a safe minimum.

- [x] Prefer kext GPU temperature over SystemMonitor snapshot
- [x] GPU sensor selection per fan curve (`.gpu` in `FanSensor` already supported)

---

### Task 7: Verification — ⏳ PENDING (hardware)

- [ ] Build: `swift build` succeeds — *compile check not yet run for this plan*
- [ ] Test with AMD dGPU connected: verify kext selectors return non-zero values
- [ ] Test without AMD dGPU: graceful fallback to existing IOAccelerator path
- [ ] Test multi-GPU: verify gpuCount > 1 case
- [ ] Verify no regressions in fan curve control
- [ ] Verify no regressions in menu bar GPU display

## Implementation Order

1. ✅ **Task 1** (ProcessorModel methods) — foundation, no UI changes
2. ✅ **Task 2** (SystemMonitor integration) — switch to kext data at the source
3. ✅ **Task 3** (Multi-GPU model) — structural addition
4. ✅ **Task 4** (SensorsView) — visible improvement
5. ✅ **Task 5** (Dashboard) — visible improvement
6. ✅ **Task 6** (Fan curves) — backend improvement
7. ⏳ **Task 7** (Verification) — validate everything

## Backward Compatibility

- All existing `SystemSnapshot` fields remain (`gpuTemperature`, `gpuPower`, etc.)
- IOAccelerator path stays as fallback when kext returns 0 or nil
- SMC TGxx keys remain as second fallback
- If kext selectors 27-30 are not implemented in the loaded kext, `IOConnectCallMethod` returns `kIOReturnUnsupported` — handled gracefully (read methods return empty arrays / 0)

## Follow-ups

- Run `swift build` to close the compile half of Task 7.
