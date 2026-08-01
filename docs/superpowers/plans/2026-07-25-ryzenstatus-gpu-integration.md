# RyzenStatus GPU Monitoring — Integration Plan

> **Date:** 2026-07-25
> **Status:** Draft plan

**Goal:** Replace IOAccelerator-based GPU readings with direct kext MMIO readings (selectors 27-30) for more reliable temperature, power, and multi-GPU support.

**Architecture:** ProcessorModel gains new kext GPU read methods; SystemMonitor uses them; UI layers (Dashboard, Sensors, Menu Panel) consume the same snapshot fields — no UI changes needed for basic integration.

## Current State

| Source | What it reads | Reliability |
|--------|--------------|-------------|
| SMC keys TGxx | GPU temperature | Good (when SMCAMDProcessor has them) |
| IOAccelerator PerformanceStatistics | Utilization, VRAM, fan, freq, power | Unreliable — often returns 0 or nil on AMD dGPUs |
| PowerCache (kext CPU power) | CPU package power | Good (already integrated) |

## New Kext Selectors (27-30)

Once implemented in AMDRyzenCPUPowerManagement:

| Selector | Output | Description |
|----------|--------|-------------|
| 27 | `scalarOutput[0] = gpuCount` | Number of AMD GPUs detected |
| 28 | `UInt16[gpuCount]` | GPU temperatures in SP78 format |
| 29 | `float[gpuCount]` | GPU power in watts |
| 30 | `uint8_t[gpuCount]` | Capabilities bitmap (bit 0 = supportsPower) |

---

### Task 1: Add kext GPU read methods to ProcessorModel.swift

**Files:**
- Modify: `Sources/RyzenStatus/Services/AMD/ProcessorModel.swift`

**Changes:**

- [ ] Add nonisolated `kernelGetGPUTemperatures()` → `[UInt16]` using selector 28
- [ ] Add nonisolated `kernelGetGPUPowers()` → `[Float]` using selector 29  
- [ ] Add nonisolated `kernelGetGPUCount()` → `Int` using selector 27
- [ ] Add nonisolated `kernelGetGPUCapabilities()` → `[UInt8]` using selector 30
- [ ] Add stored properties for multi-GPU:
  - `var gpuTemperatures: [UInt16] = []`
  - `var gpuPowers: [Float] = []`
  - `var gpuCount: Int = 0`
  - `var gpuCapabilities: [UInt8] = []`
- [ ] Add `refreshKextGPUStats()` method called during telemetry refresh
- [ ] Update `TelemetrySnapshot` struct with kext GPU fields
- [ ] Update `refreshPowerCache()` to also refresh GPU data

---

### Task 2: Integrate kext GPU readings into SystemMonitor

**Files:**
- Modify: `Sources/RyzenStatus/Services/SystemMonitor/SystemMonitor.swift`

**Changes:**

- [ ] In `SamplingPlan`, add `needKextGPU` flag for dedicated sampling control
- [ ] In the refresh loop, add kext GPU read path alongside existing IOAccelerator path
- [ ] Priority: kext GPU values > IOAccelerator values > SMC TGxx values
- [ ] Update `SystemSnapshot` to include kext GPU data fields
- [ ] Add kext GPU history arrays: `gpuTempKextHistory`, `gpuPowerKextHistory`
- [ ] Update `readGPUUsage()` to fall back to kext power when IOAccelerator returns 0

---

### Task 3: Add multi-GPU support to SystemSnapshot

**Files:**
- Modify: `Sources/RyzenStatus/Services/SystemMonitor/SystemMonitor.swift`
- Modify: `Sources/RyzenStatus/Services/SystemMonitor/CoreSnapshot.swift` (or create GPU model)

**Changes:**

- [ ] Add `GPUDeviceSnapshot` struct:
  ```swift
  struct GPUDeviceSnapshot {
      let index: Int
      let temperature: Double  // from selector 28 (SP78 → °C)
      let power: Double        // from selector 29
      let supportsPower: Bool
  }
  ```
- [ ] Add `gpuDevices: [GPUDeviceSnapshot]` to `SystemSnapshot`
- [ ] Add per-GPU history tracking in SystemMonitor

---

### Task 4: Update SensorsView for multi-GPU

**Files:**
- Modify: `Sources/RyzenStatus/UI/Settings/SensorsView.swift`

**Changes:**

- [ ] Show `SystemSnapshot.gpuDevices` as individual GPU entries
- [ ] Keep existing TGxx SMC sensor display as fallback
- [ ] Show GPU power per-device when available

---

### Task 5: Dashboard GPU cards refinement

**Files:**
- Modify: `Sources/RyzenStatus/UI/Settings/DashboardView.swift`

**Changes:**

- [ ] In `TopCardsView`, use kext GPU temp/power when more recent than IOAccelerator
- [ ] Add optional multi-GPU selector if >1 GPU detected
- [ ] In `MainChartsView`, add GPU temperature and power charts (optional toggle)

---

### Task 6: Fan curves — GPU temp source

**Files:**
- Modify: `Sources/RyzenStatus/Services/AMD/FanCurveController.swift`

**Changes:**

- [ ] In the fan curve control loop, prefer kext GPU temperature over SystemMonitor snapshot
- [ ] Add GPU sensor selection per fan curve (already has `.gpu` in FanSensor enum)

---

### Task 7: Verification

- [ ] Build: `swift build` succeeds
- [ ] Test with AMD dGPU connected: verify kext selectors return non-zero values
- [ ] Test without AMD dGPU: graceful fallback to existing IOAccelerator path
- [ ] Test multi-GPU: verify gpuCount > 1 case
- [ ] Verify no regressions in fan curve control
- [ ] Verify no regressions in menu bar GPU display

---

## Implementation Order

1. **Task 1** (ProcessorModel methods) — foundation, no UI changes
2. **Task 2** (SystemMonitor integration) — switch to kext data at the source
3. **Task 3** (Multi-GPU model) — structural addition
4. **Task 4** (SensorsView) — visible improvement
5. **Task 5** (Dashboard) — visible improvement
6. **Task 6** (Fan curves) — backend improvement
7. **Task 7** (Verification) — validate everything

## Backward Compatibility

- All existing `SystemSnapshot` fields remain (`gpuTemperature`, `gpuPower`, etc.)
- IOAccelerator path stays as fallback when kext returns 0 or nil
- SMC TGxx keys remain as second fallback
- If kext selectors 27-30 are not implemented in the loaded kext, `IOConnectCallMethod` returns `kIOReturnUnsupported` — handle gracefully
