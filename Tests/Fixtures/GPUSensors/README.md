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
