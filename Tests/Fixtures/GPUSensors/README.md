# GPUSensors.kext property fixtures

`ioreg-0.7.2-2026-11-20.plist`: the GPU control keys of `DrogaBoxGPUSensors`
on the RX 6800 XT here, kext `REL-072-2026-11-19`, macOS 26.7.3, read with
`ioreg -r -c DrogaBoxGPUSensors -l -w0 -a` on 2026-11-20 and cut to the keys
the control reads (`VersionInfo`, `Control`, `Profile`, `Power`,
`PowerWatch`, `Write`, `WriteState`, `OD8Write`, `OD8WriteState`, `OD8State`,
`OD8`). Nothing was edited by hand. Writing was closed (not armed) and nothing
was held.

`ioreg -a` writes the same CF values the app reads with
`IORegistryEntryCreateCFProperties`: the kext's negative 32-bit OD8 numbers
arrive signed (`PowerPercent.Min` = -6, `NotAllowed` = -212750), not as the
64-bit numbers plain `ioreg -l` prints.

## curve-cases.jsonl

100 OD8 states and what the kext's own `gpuctl::od8CheckWant` answers for
each, from GPUSensors.kext's `control_logic.hpp` at 0.7.2 (DrogaBoxGPU commit
e74ead6). The app's copy of the rules (`GPUControlCurveRules.swift`) must give
the same answer for every line (`GPUControlFanTests`).

Each line is `{"want": {...}, "muts": [...], "check": N}`:

- `want`: `curve`, `temp[5]`, `speed[5]`, `zeroRpmOff`, `gfx` (0 = stock).
- `muts`: changes to the card's real state before the check, by entry id
  (`od8Name` order): `freshCaps` / `firstCaps` (value), `freshEntry` /
  `firstEntry` / `bothEntry` (id, field `feature`/`min`/`max`/`def`, value),
  `cur` (id, value). They reach the codes the real table alone cannot:
  Drifted, MemoryMoved and NoFeature.
- `check`: the `Od8Check` number (33 Ok, 14 Drifted, 5 MemoryMoved,
  12 NoFeature, 9 CurveRange, 4 CurveOrder, 3 CurveFirst, 6 CurveLast,
  6 CurveCooling, 8 GfxRange). NotRead and NoReadings never come from
  `od8CheckWant`.

The base state is the card's real OD8 table as `gpucontrol check` maps it
(Stock = first read, Default = fresh read, Current = current values,
Caps 212749); the same values as `ioreg-0.7.2-2026-11-20.plist`, which the
test builds the state from.

To regenerate after a kext change, from a folder of your own:

```
clang++ -std=c++17 -O0 -I <DrogaBoxGPU>/sensors/kext -o fixturegen <DrogaBoxGPU>/sensors/tests/curve_fixturegen.cpp
./fixturegen > curve-cases.jsonl
```

then copy the file here, add the new build's `VersionInfo` to
`GPUControlCurveRules.checkedVersions`, and run `./build.sh --test`.
