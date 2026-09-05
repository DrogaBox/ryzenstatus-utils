# KEXT_FINDINGS.md — Audit reconciliation ledger (kernel wave 1.20.0)

> Generated 2026-09-05 by the implementing agent per `KEXT_WAVE_PLAN.md`.
> Evidence verified against the working tree at base `b83204ae`.
> Companion archive: `AUDIT_ARCHIVE.md` (untracked copy of the scrubbed 1.15.1 audit).

## 1. Verdict table

| ID | Claim (source audit) | Status | Evidence @ b83204ae |
|---|---|---|---|
| F-05 | GPU power polling stalls shared workloop; reachable from any process's SMC read | **OPEN — CRITICAL** | `Keyimplementations.cpp:61-74` `RGPUPowerValue::readAccess()` → `getGPUPower()` (`AMDRyzenCPUPowerManagement.cpp:1709`) → `AMDGPU.cpp:586` `getPower()` → `smu9GetPower()` busy-wait ≤100 ms (`AMDGPU.cpp:46-47, 396-402, 417-421`) under `gpuLock`, on the reading process's thread |
| F-07 | User client stores `fOwningTask` without retain; UAF window | **OPEN** | `AMDRyzenCPUPMUserClient.cpp:23` plain store; deref at `:91` (`hasPrivilege`); KRN-24 added `clientClose()` only (`:77-80`) |
| N-01 | (new, this wave) cases 28/29 copy uninitialized stack on per-GPU failure | **OPEN** | `AMDRyzenCPUPMUserClient.cpp:915` & case 29: `provider->getGPUTemperature(i, &dataOut[i])` return value ignored → element never written on `kIOReturnNoDevice` |
| F-09 | P-state takeover runs in telemetry-only mode | **FIXED-BY-KRN** | `pmAMDRyzen.c:141-166` `pmRyzen_init(allowDispatch)` skips `pmRyzen_init_PState()`/`PState_reset()` when false; caller `AMDRyzenCPUPowerManagement.cpp:658` passes `pmDispatchAllowed` from CPU profile (`:515-516`, "Telemetry-only" log `:541`); writes still gated by `legacyPstateAllowed` (`:1477-1481`) |
| F-13k | `ccdTemperatures` lock-domain mix | **REJECTED (unreproducible)** | Writer: provider timer `AMDRyzenCPUPowerManagement.cpp:376-382` (single command gate); readers via `getCCDTemp` (`:1175`, fresh SMN read, no shared-array dependency) and SMC `TempCore::readAccess` (`Keyimplementations.cpp:21-32`, fallback to package temp). No observed cross-domain shared mutable state |
| F-14k | Kernel resolver: hardcoded base + misleading "unsafe wrmsr" log | **FIXED-BY-KRN** | `kernel_resolver.c:36-59` anchors KASLR on `_mh_execute_header` with `_version` fallback; no hardcoded base; no "unsafe wrmsr" string anywhere in `symresolver/` (grep 0) |
| F-15k | SMC mailbox: no arbitration with native AMD driver | **WONTFIX (documented limitation)** | Arbitration requires a cross-driver protocol Apple/AMD do not provide on macOS; `smuCmdLock` serializes our own sequences (`hpp:410`, `cpp:1223-1259`). Revisit only if users report coexistence faults |
| F-22k | Manual-mode fan slider stops tracking real PWM | **FIXED-BY-cb050584** | `FansSettingsView.swift` `.onChange(of: fan.throttlePWM)` now tracks live duty whenever the slider is not being dragged; the old `controlMode != .manual` guard froze it |
| B-13 | App requests 10 P-state clocks, kext returns 8 | **OPEN** | App `ProcessorModel.swift:752` `kernelGetFloats(count: 10, selector: pStateDefClock)`; kext case 1 exports exactly 8 floats (`UserClient.cpp:368-402`) |
| B-25 | Watchdog detects kext reload but never reconnects | **OPEN** | App-side; `kextloadAlerts` plumbing (KRN-12/R-6) alerts once; no teardown/reopen path — scheduled as C-9 |
| B-30 | Fan curves re-uploaded + privilege-error spam per refresh | **OPEN — app-side** | `FanCurveController.swift:20, 26, 123-124, 292, 434-435` unconditional `syncCurvesToKext()`/`syncMappingsToKext()`; no change-detection |

## 2. KRN-17 / KRN-20 / KRN-21 / KRN-22 disposition

Method: full diff of `85865a17` (640 lines, 11 files) extracted to `/tmp/krn-full.diff`;
every hunk mapped to the 26 documented DARE claims:

- AMDGPU.cpp (9 hunks) → KRN-05/06/07/08/09/10/11 (polling, CTF bit, temp offset, SMU timeouts).
- UserClient.cpp (4) → KRN-08 (clamp), KRN-12 (SInt32), KRN-19 (matching_dict), KRN-24 (clientClose).
- Provider .cpp (13) → KRN-01, 02, 13, 14, 15, 16, 19, 23, 25, 26, 27, 28, 29, 30.
- pmAMDRyzen.c (2) → KRN-13 (allowDispatch gate), KRN-23 (P1 dfsid validation).
- Info.plists (2) → KRN-03 (ABI 3.34.0 sync).

**Verdict: no orphan hunks remain. KRN-17, KRN-20, KRN-21, KRN-22 were never
implemented** (no code, no claim, no changelog prose in §1.16.0 matching extra
topics). Their themes are unknowable — the KRN report was never committed and
commit `85865a17` predates the repo's current owner-squat history. Treat the
numbering as retired; do not reuse the IDs.

## 3. Fresh-eyes buffer/arith sweep (Phase A-4)

Sweep performed over `AMDRyzenCPUPMUserClient.cpp` (49 cases), `AMDGPU.cpp`,
`Keyimplementations.cpp`, provider timer paths. Result:

- All struct-output cases now carry the F-12/F-16 guard triple (reject / report
  min / bounds-clamped copy) — with the single exception pattern N-01 above
  (per-element kernel-call failures).
- `case 4` comment says "[power, temp, pstateCur, …]" — output layout matches; no fix.
- `case 93`/`case 94` increments `fanUpdateCounter` twice per combined poll —
  cosmetic (throttle sampling cadence), not a defect; noted, no action.
- No additional new findings beyond N-01.

## 4. Phase B execution status (2026-09-05)

- **FIX-1 (F-05) — DONE.** `Keyimplementations.cpp` RGPUTempValue/RGPUPowerValue
  now read `provider->gpuTemperatures/gpuPowers` (command-gate timer cache);
  UserClient cases 28/29 serve the same arrays. No live `getGPU*` calls remain on
  reader threads. Both kexts compile clean (Release, Xcode 26).
- **FIX-2 (F-07) — DONE.** `task_reference()` in `initWithTask`, balanced in
  new `free()` override; `mach/task.h` include added.
- **FIX-3 (N-01) — DONE.** Cases 28/29 copy only from the zero-initialized,
  timer-refreshed cache — no uninitialized element can reach userspace.
- **C-1 — DONE (kext selector 32 + app publisher).**
- **C-9 / B-25 — DONE (app-side reconnect + `KextReconnected` notification).**
- Remaining OPEN: none from the original suspect list — B-13/B-30/F-22k
  closed in follow-up commit `cb050584`. Deferred feature work (not findings):
  per-fan manual-control UI polish and the Zen 4 Curve Optimizer research
  (owner-hardware-gated).

## 5. Feature candidates (Phase C shortlist with register-level evidence)

| ID | Feature | Kext evidence | New selector/SMC | UI |
|---|---|---|---|---|
| C-1 | Per-core C6 residency | `pmAMDRyzen.c:77-89, 258-327` per-CPU `eff_idleaccd/eff_timeaccd` | selector 32 | Per-core grid overlay |
| C-2 | Per-core IPC + eff-freq | selector 5 (`deltaInstructions`), case 2 (`effFreq_perCore`), provider `lastMPERF/lastAPERF` | selector 33 | Freq graph + IPC badge |
| C-3 | Full P-state table + current | cases 0/1/4, `pstateCur` | existing (fix B-13) | AMD Power settings |
| C-4 | Zen 4 Curve Optimizer | `cpp:666-669` (mailbox 0x55, blocked UNVERIFIED) | existing 110/111 behind capability bitmap | Curve Optimizer page (owner-gated) |
| C-5 | Silicon ranking strip | selector 21 + app `AMDCoreRanking` | existing | Per-core grid header |
| C-6 | Per-fan manual control | cases 94/95/96/97 (`UserClient.cpp:1187-1317`) | existing | Fans & Cooling sliders |
| C-7 | GPU enrichment via SMC keys | `SMCAMDProcessor.cpp:47-59` `TGx*/PGx*` | existing SMC keys | GPU panel prefers kext values |
| C-8 | Baseboard identity | selector 16 (2×64B strings) + selector 26 | existing | About row |
| C-9 | Kext-reload self-heal | `kextloadAlerts`/`kunc_alert` (`UserClient.cpp:115-130`) | none (app-side) | Toast + auto-reconnect |
