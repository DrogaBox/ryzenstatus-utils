# Implementation Brief — Post-Audit Remediation (F-27…F-30 follow-ups)

> Handoff document for the implementing agent. Everything below was verified against the
> working tree on 2026-09-05. Do not re-derive the audit verdicts; execute the tasks.

Repo: **RyzenStatus** (Freebuff Desktop checkout), branch `main`, base f4106f92 (v1.18.0).
The working tree has **7 uncommitted modified files** in `Sources/RyzenStatus/` implementing
second-opinion audit fixes:

| Finding | Summary | Verdict |
|---|---|---|
| F-27 | Data race on `ProcessorModel.shared.connect` — replaced all 6 external reads with `nonisolated var isConnected` (lock-guarded) | ✅ verified, keep as-is |
| F-28 | Blocking kext IPC on `@MainActor` — `C6ResidencyService.poll()` and `AmdPowerControlsModel.syncFromKext()` now wrap IPC in `Task.detached` | ✅ verified, keep as-is |
| F-29 | Fan picker synthesized names — `loadFanPicker()` now uses `getFans(includeNames: true)` | ✅ verified, keep as-is (see constraint 2) |
| F-30 | Doc comment corrected: kext selector 28 returns integer °C, not SP78 | ✅ verified, keep as-is |

Your job is **Tasks 1–5** below, then the verification checklist.

---

## Hard constraints (read first)

1. **Do NOT touch anything under `SMCAMDProcessor_Source/`.** It must remain byte-identical
   to HEAD (`git diff --stat -- SMCAMDProcessor_Source/` must stay empty).
2. **Do NOT change `AmdControlSection.loadFanPicker()` to `includeNames: false`.** The audit
   suggested this as a latency optimization, but it is **wrong**:
   `ProcessorModel.getFans(includeNames: false)` skips BOTH the kext hardware-name reads AND
   the `FanName_<i>` UserDefaults overrides (see `ProcessorModel.swift:1406-1412`), so the
   picker would show synthesized "Fan N" labels again, undoing F-29. The extra kext calls
   (3 + numFans) are inherent to the name fix and acceptable.
3. **The project builds via `./build.sh` (zsh).** The script relies on
   `Sources/RyzenStatus/**/*.swift` globs, which do NOT expand under bash — always run
   builds through the script, never with `sh`/`bash build.sh`.
4. **`./build.sh --test` compiles a fixed file list** of pure-helper files (no IOKit, no UI,
   no AppKit) into a custom `@main` test harness (`Tests/MetricsTests.swift`, 3,741 checks).
   It does NOT compile the AMD service files. Preserve that property when adding test files.
5. Toolchain: `swiftc`, target `x86_64-apple-macosx14.0`, SDK via
   `xcrun --sdk macosx --show-sdk-path` (same as build.sh).
6. Known compiler bug to ignore: a full-project strict-concurrency typecheck reports exactly
   2 hard errors — `UI/MenuPanel/MenuPanelView.swift:800` and one follow-on — both
   "failed to produce diagnostic for expression; please submit a bug report". These are
   Swift compiler diagnostic-rendering bugs, **not real code errors**. Do not "fix" them.

---

## Task 1 — Wire `closeDriver()` into teardown (real bug surfaced by the review)

**Verified fact:** `ProcessorModel.closeDriver()` (`ProcessorModel.swift:421`) has **zero
call sites**. The audit assumed it runs from `applicationWillTerminate` — it does not.
Consequences: the F-24 watchdog-cancellation fix is currently dead code, and the watchdog
task keeps issuing `IOServiceGetMatchingService` calls during shutdown.

1. `Sources/RyzenStatus/App/AppDelegate.swift` — `applicationWillTerminate` currently ends
   with `KeepAwakeManager.shared.deactivate(reason: .quit)` (line ~208). Append AFTER it:

   ```swift
   // AUDIT F-27 residual: close the kext connection and cancel the watchdog task.
   // Must run AFTER every other kext user above (FanCurveController.resetFansToAutoSync(),
   // C6ResidencyService.stop(), etc.) — closing the connection kills all later IPC.
   ProcessorModel.shared.closeDriver()
   ```

2. `Sources/RyzenStatus/Services/AMD/ProcessorModel.swift` — above the
   `nonisolated(unsafe) private var kextWatchdogTask` declaration (line 19), add:

   ```swift
   // Written only from init() and closeDriver(), both main-thread contexts; safe under
   // that single-thread contract (applicationWillTerminate → closeDriver runs after init
   // has long returned).
   ```

---

## Task 2 — Close all 20 strict-concurrency diagnostics in the AMD layer

Context: `swiftc -typecheck -strict-concurrency=complete` over the whole project reports
~4,000 diagnostics, but only **20 touch the AMD layer**. Fix exactly these (they are the
ratchet's baseline — see Task 3); do not attempt whole-project cleanup.

### 2a. `Sources/RyzenStatus/Services/AMD/ProcessorModel.swift`

Three nested lock-guarded classes need `@unchecked Sendable`. Each is already fully
NSLock-guarded, so this is sound:

- `final class TerminationState` (~line 33) → `final class TerminationState: @unchecked Sendable`
- `final class PowerCache` (~line 87) → `final class PowerCache: @unchecked Sendable`
- `final class GPUCache` (~line 176) → `final class GPUCache: @unchecked Sendable`

This clears the `nonisolated let/var` warnings at lines 60, 115, 185 and the cascading
"non-sendable … cannot exit nonisolated context" warnings at 61, 118, 120, 123, 127, 148,
189, 194, 198, 344, 425.

### 2b. `Sources/RyzenStatus/Services/AMD/IOAcceleratorCache.swift`

The `[String: Any]` snapshot is non-Sendable and crosses the actor boundary (warnings at
lines 41, 44, 45, 82, plus `ProcessorModel.swift:1170` where `snapshot()` is awaited from
actor-isolated context). Introduce a value wrapper near the top of the file:

```swift
/// Sendable box for the heterogeneous PerformanceStatistics snapshot.
/// Values are immutable once boxed; @unchecked is sound because the only
/// mutable store lives behind OSAllocatedUnfairLock inside the actor.
struct GPUStatsSnapshot: @unchecked Sendable {
    let values: [String: Any]
}
```

Change the actor's storage/public API to traffic in `GPUStatsSnapshot` (`_stats`, `stats`,
`snapshot()`, `cachedStatsSync()`), then update all consumers to read `.values`.
**Grep first:** `grep -rn "cachedStatsSync\|\.shared\.stats\|IOAcceleratorCache.shared" Sources/`
to enumerate every call site before changing the API.

### 2c. `Sources/RyzenStatus/UI/MenuPanel/AmdControlSection.swift` (line ~313)

`.onChange(of: selectedFanId)` calls `updateFanRpm()` from a synchronous nonisolated
closure — the ONLY AMD-UI strict warning. Wrap it:

```swift
.onChange(of: selectedFanId) { _, _ in
    Task { @MainActor in updateFanRpm() }
}
```

---

## Task 3 — Concurrency ratchet gate (CI)

Create **`Tools/concurrency-gate.sh`** (zsh, same style as build.sh) and make it
executable (`chmod +x`):

```zsh
#!/bin/zsh
# Concurrency ratchet: fails if any strict-concurrency diagnostic originates
# from the AMD layer. Non-AMD diagnostics are tolerated (pre-existing debt;
# see HANDOFF_F27-F30.md for the full-project picture).
set -uo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --sdk macosx --show-sdk-path)"
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT
swiftc -typecheck -O -num-threads 8 -target x86_64-apple-macosx14.0 -sdk "$SDK" \
  -strict-concurrency=complete Sources/RyzenStatus/**/*.swift > /dev/null 2> "$OUT"
PATTERN='Sources/RyzenStatus/(Services/AMD/|UI/MenuPanel/AmdControlSection|UI/Settings/AmdPower)'
HITS=$(grep -E "$PATTERN" "$OUT" | grep -cE "(error|warning):" || true)
echo "AMD-layer strict-concurrency diagnostics: $HITS"
if (( HITS != 0 )); then
  grep -E "$PATTERN" "$OUT" | grep -E "(error|warning):"
  exit 1
fi
```

Note: this must run under **zsh** (glob expansion, constraint 3). CI runners default to
bash for `run:` steps — invoke it as `zsh Tools/concurrency-gate.sh` or rely on the shebang
via direct execution (`./Tools/concurrency-gate.sh`), which honors the shebang.

In **`.github/workflows/ci.yml`**, after the "Unit tests" step, add:

```yaml
      - name: AMD concurrency gate
        run: ./Tools/concurrency-gate.sh
```

Budget ~3 min on CI; it runs the same full typecheck the project already tolerates.
(There is also a `sdk15` job on Xcode 16 / Swift < 6.2 — leave that job untouched; the
gate belongs only in the `build` job.)

---

## Task 4 — Unit tests for the patched AMD logic

The existing suite covers NONE of the patched files (constraint 4). Fix by extraction:

### 4a. New file `Sources/RyzenStatus/Services/AMD/C6Sampling.swift`

Foundation only — no AppKit/IOKit imports, so it can join the `--test` list:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Pure C6 residency sampling math, extracted from C6ResidencyService.poll()
/// (AUDIT F-28) so it can be unit tested without a kext connection.
enum C6Sampling {
    /// Folds one kext sample into the baseline state.
    /// - Parameters:
    ///   - raw: cumulative C6 residency counter in microseconds (kext selector 31)
    ///   - now: sample timestamp (`ProcessInfo.processInfo.systemUptime`)
    ///   - lastRaw/lastTimestamp: previous baseline (0/0 = no baseline yet)
    /// - Returns: `(pct, lastRaw, lastTimestamp)` — `pct` is nil when the window
    ///   isn't ready (first sample, counter reset, or no counter); the returned
    ///   baseline is always the state to store.
    static func sample(raw: UInt64, now: TimeInterval,
                       lastRaw: UInt64, lastTimestamp: TimeInterval)
        -> (pct: Double?, lastRaw: UInt64, lastTimestamp: TimeInterval) {
        guard raw > 0 else { return (nil, 0, 0) }                  // no counter
        if lastRaw > 0 && raw < lastRaw { return (nil, raw, now) } // counter reset
        var pct: Double? = nil
        if lastRaw > 0 && lastTimestamp > 0 {
            let deltaUs = Double(raw - lastRaw)
            let elapsedUs = (now - lastTimestamp) * 1_000_000
            if elapsedUs > 0 { pct = min(100, max(0, (deltaUs / elapsedUs) * 100.0)) }
        }
        return (pct, raw, now)
    }
}
```

Refactor `C6ResidencyService.poll()` to call it and keep the existing
`abs(percentage - newPct) >= 0.1` hysteresis in `poll()`. **Behavior must be identical**
to the current implementation (zero-reset → zero + zeroed baseline; reset → skip sample +
re-anchor; first sample → baseline only).

### 4b. Register it in `build.sh --test`

Add `Sources/RyzenStatus/Services/AMD/C6Sampling.swift \` to the `--test` file list, next
to the other `Sources/RyzenStatus/Services/AMD/` entries (e.g. after
`AMDCpuGeneration.swift`).

### 4c. Append tests to `Tests/MetricsTests.swift`

Append a `// MARK: C6 residency sampling` section using the existing `expect`/`expectClose`
helpers (file is a custom `@main` harness — no XCTest). Required cases:

- **First sample** (`lastRaw=0, lastTimestamp=0`) → `pct == nil`, baseline becomes `(raw, now)`.
- **Counter reset** (`raw < lastRaw`, `lastRaw > 0`) → `pct == nil`, baseline re-anchored to `(raw, now)`.
- **Normal delta** → known percentage, e.g. `raw` advances 500_000 µs over 1.0 s → 50%.
- **Clamp bounds**: delta exceeding elapsed → 100; negative elapsed (`elapsedUs <= 0`) → `pct == nil`.
- **No counter** (`raw == 0`) → `pct == nil` and baseline zeroed `(0, 0)`.

Then a `// MARK: AMDPowerPreset.snapEPP` subsection (the enum is already in the `--test`
list; existing preset tests live around line 6694): assert the bucket edges 0, 84/85,
169/170, 254/255 snap to the four preset EPP values (255/128/32/0 per the existing tests).

---

## Task 5 — Polish

1. `Sources/RyzenStatus/Services/AMD/ProcessorModel.swift:1127` — promote the
   `// AUDIT F-30: kext returns integer °C directly, no SP78 conversion` line to `///`
   so it joins the DocC comment (audit Risk 4).
2. `Sources/RyzenStatus/UI/Settings/AmdPowerControlsModel.swift` — the comment above
   `isSyncingFromKext` (~line 29) currently explains only the onChange loop guard. Extend
   it with the contract: *"Writes arriving while a sync is in flight are intentionally
   dropped; the 3 s panel timer re-syncs and reconciles published state."* (audit Risk 2).
3. `CHANGELOG.md` — add a `## [Unreleased]` section at the top summarizing:
   - F-27: thread-safe kext connection checks across all 6 call sites (`isConnected`).
   - F-28: blocking kext IPC moved off MainActor (C6 poll, `syncFromKext` batched).
   - F-29: menu-panel fan picker now shows hardware/custom fan names.
   - F-30: corrected GPU-temperature doc comment (integer °C, no SP78 conversion).
   - `closeDriver()` wired into termination (watchdog cancellation now actually runs).
   - AMD concurrency ratchet gate + new C6/snapEPP unit tests.

---

## Verification checklist (all must pass)

```bash
./build.sh --test                     # existing checks + new C6/snapEPP checks pass
./build.sh                            # full app compiles and bundles
./Tools/concurrency-gate.sh           # exits 0, prints "AMD-layer strict-concurrency diagnostics: 0"
git diff --stat -- SMCAMDProcessor_Source/   # empty output
grep -rn "includeNames: false" Sources/RyzenStatus/UI/MenuPanel/AmdControlSection.swift  # no match
```

---

## Explicitly out of scope (do not do)

- The audit's F-29 `includeNames: false` "optimization" — it would break the name fix (constraint 2).
- Audit Risks 1–3 (double `Task.detached` hops, mid-sync write drops, double sync on
  Settings open) — pre-existing, benign, documented by Task 5.2 instead.
- Whole-project `-strict-concurrency` adoption (~4k diagnostics) — the ratchet freezes the
  AMD layer; the rest is separate debt.
- The `MenuPanelView.swift:800` compiler-bug "errors" — not fixable in user code (constraint 6).
