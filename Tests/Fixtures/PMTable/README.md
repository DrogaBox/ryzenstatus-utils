# SMU PM-table fixtures (Vermeer 0x380805)

Real captures from a Ryzen 9 5900XT (Vermeer, Family 19h) running kext
3.34.11, read back through UserClient selector 57 op 1 from the snapshot
the kext's 1 Hz timer maintains. These are the reference inputs for the
S9b parser tests in `Tests/MetricsTests.swift` (`AMDSmuPMTable.decode`).

## Row format

```
<4-hex byte offset>|32 hex chars
```

16 bytes per row, rows contiguous, 143 rows = 2288 bytes = the documented
0x380805 table size (`pmTableSizeForVersion(0x380805)` in the kext).

## Fixtures

| File | Machine state | Notes |
|------|---------------|-------|
| `vermeer-0x380805-idle-2026-09-11T2324.hex` | near-idle | core 0: ~2.55 W, C0 15.2%, CC6 0; 10 slots sleeping (non-zero CC6); PPT value 49.3 W |
| `vermeer-0x380805-lightload-2026-09-12T0121.hex` | light load | captured ~26 h later; differs in 112 bytes; PPT value 72.8 W |

The two captures pin different machine states so parser changes must stay
correct across varying telemetry, not just one frozen snapshot.

## Recapture recipe

With the kext loaded and the app's AMD Power pane healthy, capture a fresh
snapshot with a small IOKit tool (selector 56 → info; selector 57 op 1 →
chunked snapshot read, 4 KiB chunks) and save rows in the format above:

```bash
# selector 56 words: [0] version [2] size [5] snapValid [6] ageMs
# selector 57 op 1: in = {1, offset}, out = chunk bytes (≤ 4096 per call)
```

## Layout reference

Offsets pinned from ryzen_monitor `pm_tables.c` (0x380805) and
hardware-validated: package elements 0–171 (PPT limit/value, TDC, EDC,
THM, VID, FCLK/UCLK/MEMCLK …), 16-core block starting at element 172
(power/temp/clock/C0/CC6 per core), L3 block at 540.
