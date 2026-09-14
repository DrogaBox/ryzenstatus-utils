# The Super I/O fan layer

This document explains the part of `AMDRyzenCPUPowerManagement.kext` that reads
and controls physical fans, why it is easy to get wrong, and what is actually
verified on hardware versus assumed. Read it before changing anything under
`SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/SuperIO/`.

The short version: this code drives real fans through an open-loop path with no
RPM feedback in the control decision. A mistake here does not raise an exception
or turn a test red. It shows up as hot silicon, or as a stalled pump.

## What the layer is

A Super I/O chip is a small controller on the motherboard that owns the fan
headers, the tachometers, and a set of temperature and voltage sensors. It is
reached through legacy LPC I/O ports, not PCI. Two families are supported:

| Family | Driver | Parts |
|---|---|---|
| Nuvoton | `ISSuperIONCT668X`, `ISSuperIONCT67XXFamily` | NCT6771F … NCT6799D, NCT668X |
| ITE | `ISSuperIOIT86XXEFamily` | IT8688E, IT8686E, IT8665E, IT8689E |

`ISSuperIOSMCFamily` is the base class. Anything added there needs an inline
default so a family that does not implement it keeps working unchanged — see
`getFanRPMValid()` for the pattern.

## How a chip is identified

`ISSuperIOIT86XXEFamily::getDevice()` probes ports `0x2E` and `0x4E`, reads the
device-ID bytes, and matches them against the four IDs above. The composed value
is handed to the constructor as `chipIntel`, so **the running chip is known at
runtime**. Any behaviour that differs per chip must branch on that value rather
than on an assumption about which board this is.

The chip is logged at load:

```
probe IT86XXE
IT8665E chip identified
SMC Chip id:86 revision:65
```

On macOS that goes to the unified log, not to `dmesg` — `dmesg` is a Linux habit
and returns nothing useful here:

```sh
log show --last boot --predicate 'eventMessage CONTAINS "chip identified"'
```

The kext does not publish the chip in the IORegistry, so `ioreg` will not tell
you either. If you need it without the log, infer it from behaviour: see the
register-map section below.

## Two register maps, not one

This is the trap that cost the most time. The ITE parts do **not** share one
register layout. Linux's `it87` driver — the community's de-facto datasheet for
these chips — carries two tables and selects per chip in `it87_init_regs()`:

```c
static const u8 IT87_REG_FAN[]        = { 0x0d, 0x0e, 0x0f, 0x80, 0x82, 0x4c };
static const u8 IT87_REG_FANX[]       = { 0x18, 0x19, 0x1a, 0x81, 0x83, 0x4d };
static const u8 IT87_REG_PWM[]        = { 0x15, 0x16, 0x17, 0x7f, 0xa7, 0xaf };

static const u8 IT87_REG_FAN_8665[]   = { 0x0d, 0x0e, 0x0f, 0x80, 0x82, 0x93 };
static const u8 IT87_REG_FANX_8665[]  = { 0x18, 0x19, 0x1a, 0x81, 0x83, 0x94 };
static const u8 IT87_REG_PWM_8665[]   = { 0x15, 0x16, 0x17, 0x1e, 0x1f, 0x92 };
```

`it8686 / it8688 / it8689 / it8628` take the first set. `it8665 / it8655 / it8625`
take the second. Only two things differ, and both matter:

| Channel | Tachometer | PWM control mode |
|---|---|---|
| 0–2 | same in both | same in both |
| 3 | same in both | `0x7f` vs **`0x1e`** |
| 4 | same in both | `0xa7` vs **`0x1f`** |
| 5 | `0x4c/0x4d` vs **`0x93/0x94`** | `0xaf` vs **`0x92`** |

The **duty** register table is chip-independent — Linux keeps one
`IT87_REG_PWM_DUTY` for the whole family — which is why a duty reading can be
correct on a chip whose tachometer reading is not.

Until kext 3.34.17 this driver had only the first table and applied it to all
four parts. On an IT8665E that produced two distinct faults:

1. The sixth tachometer read `0x4c/0x4d`, which hold something else on that
   chip, so a healthy fan or pump reported a nonsense RPM.
2. Worse, `overrideFanControl()` and `setDefaultFanControl()` **wrote** the
   control-mode byte of channels 3–5 into `0x7f/0xa7/0xaf` instead of
   `0x1e/0x1f/0x92` — arbitrary writes into EC registers whose function on that
   chip is unknown.

The fix keeps both tables and resolves three pointers in the constructor from
`chipIntel`. A chip that is not an IT8665E keeps its exact previous behaviour.

### Diagnosing a wrong register map from behaviour

You do not need the chip ID to spot this. Compare the six channels against each
other:

- If exactly the **sixth** tachometer is implausible while the other five are
  sane, and duty reads sensibly on all six, you are on an IT8665E-class chip
  being read with the IT8688E table. Channel 5 is the only tachometer register
  that differs between the tables, so the fault localises to it.
- Convert the reported RPM back to a counter with `counter = 1.35e6 / (2 × RPM)`
  and compare its high byte against the other channels'. A healthy fan at
  800–1700 RPM has a high byte of `0x01`–`0x03`. A high byte an order of
  magnitude away means the byte is not a tachometer extension at all.

Worked example from the 5900XT reference machine, where the pump reported
40 RPM: counter ≈ 16875 = `0x41EB`, so the high byte read `0x41` against
`0x01`–`0x03` on its neighbours. Using the low byte alone gives
`1.35e6 / (2 × 0xEB)` ≈ **2872 RPM**, a credible pump speed.

## Fan headers are not all fans

The driver reports six channels with hardcoded generic names
(`kFAN_READABLE_STRS`: `CPU Fan`, `System 1 Fan`, `System 2 Fan`, `PCH Fan`,
`CPU OPT Fan`, `System 3 Fan`). Those names are **not** read from the board.
A real motherboard maps its own headers onto those channels however it likes, and
on an ASUS ROG Crosshair VII Hero one of them is `AIO_PUMP`.

This matters because the app can map a fan curve onto any channel:

- A **pump** should run at or near 100 % duty. Throttling it reduces coolant
  flow, which raises CPU temperature under load — the opposite of what a fan
  curve is for.
- `kCURVE_MIN_ACTIVE_PWM = 40` (≈15.7 %) is a sensible floor for a fan and far
  too low for a pump.
- The emergency guard only raises duty at ≥85 °C, which is after the damage a
  slow pump would already be doing.

The Super I/O cannot tell a pump from a fan; both are PWM outputs with a
tachometer. So this cannot be fixed in the driver — it has to be known by
whoever configures the curve. **Identify which channel is your pump and leave it
under BIOS control.**

A misread tachometer makes this worse in a second way: a pump reporting 40 RPM
looks permanently stalled to every RPM-based heuristic — the rotor-start floor in
selector 95, and any frozen-fan detector — so a healthy pump trips all of them at
once.

## Why duty and RPM come from different places

Under BIOS SmartFan / SmartGuardian control the chip runs the fan itself and, on
many firmware versions, does not update the register that holds the commanded
duty. It reads 0 even though the fan is spinning. So:

- **RPM** always comes from the tachometer registers, via `updateFanRPMS()`.
- **Duty** comes from the duty register, via `updateFanControl()` — and when that
  register reads 0 while the tachometer says the fan is spinning, the driver
  falls back to estimating duty as `RPM / peakRPM × 255`.

The estimate is a display convenience, not a control input. Two consequences
worth knowing:

- `fanPeakRPMs` is *learned* from observation, so the estimate is only meaningful
  once the fan has been seen near its maximum — typically the boot ramp. Early
  after boot the estimate reads high.
- You can tell an estimate from a real register read by watching them together:
  a real duty stays fixed while RPM jitters by a few counts; an estimate moves
  with RPM.

## The selector 93 / 94 cadence

Super I/O access is slow port I/O, so the user client rate-limits it: selectors
93 and 94 each act only on every fourth call. `getFans()` calls 93 and then 94
in one pass.

Those two counters must be **separate**, and it is not a style preference.
`OSIncrementAtomic` returns the pre-increment value. With one shared counter,
each `getFans()` consumes exactly two values, so the parity each selector sees
never changes: starting from 0, selector 93 always reads an even value and
selector 94 always reads an odd one. The gate is `% 4 == 0`, which only an even
value can satisfy — so **selector 94's branch was unreachable from boot** and
`updateFanControl()` was never called at all. Every fan reported `pwm 0` because
`fanThrottles` was never written after initialisation.

```
getFans   sel 93 sees   fires   sel 94 sees   fires
   1           0        yes          1         no
   2           2         no          3         no
   3           4        yes          5         no
   4           6         no          7         no
```

Fixed in 3.34.16 with a dedicated `fanCtrlUpdateCounter`. If you add a third
selector on this path, give it its own counter too.

## Verifying a change

Nothing in this layer is covered by CI. `*.xcodeproj` is gitignored, so a clean
clone cannot build the kext at all and the CI workflow never tries. Every change
here is validated by hand on the maintainer's machine.

Two rules that exist because breaking them cost real time:

**Bump the kext version before testing, not after.** Two different binaries
carrying the same version number are indistinguishable to `kextstat`, and then a
failed probe cannot be told apart from the old binary still being loaded. The
version bump is a debugging tool, not a release step. `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` live in
`SMCAMDProcessor_Source/Config/Version.xcconfig`; the kext `Info.plist` files
reference them, so never edit the plists.

**Confirm what actually loaded.** `kextstat | grep -i ryzen` before believing any
measurement. On a machine with more than one EFI partition, the one you edited is
not necessarily the one that booted.

Then read duty and RPM:

```sh
./build/RyzenStatus --sensors
```

Note that `--sensors` is not a passive observer. It opens and closes a user
client, and `clientClose()` releases **all** fans to BIOS control, so it destroys
any probe state and writes its own `clientClose released` line to the log. It
also advances the rate-limit counters itself, which means it perturbs the very
cadence it is measuring. Use it before and after a probe, never in the middle —
read live values from the app's UI instead.

## Known gaps

Ranked, and honest about what has been reproduced:

- **ITE tachometer readings are not validated.** Unlike the Nuvoton drivers,
  which reject `0xFFFF` and anything above a plausibility ceiling and track a
  per-fan validity flag, `ISSuperIOIT86XXEFamily::updateFanRPMS()` collapses
  stopped, unconnected, and garbage into the same `0`, retains no last-good
  value, and lets unvalidated samples poison `fanPeakRPMs`.
- **`activeFansOnSystem` is hardcoded to 6** for every ITE part
  (`ISSuperIOIT86XXEFamily.cpp`), where Linux derives fan presence from
  configuration bits and can skip channels. A board with five wired headers gets
  a sixth phantom channel.
- **No bank selection.** Linux marks IT8665E, IT8655E, IT8625E, IT8686E,
  IT8688E and IT8689E with `FEAT_BANK_SEL` and switches banks around every
  access. This driver has no bank handling and operates in whichever bank
  firmware left selected.
- **The constructor mutates the chip before any privilege check**:
  `writeByte(0x0c, readByte(0x0c) | 0x3f)` enables 16-bit tachometer mode for all
  six channels at load time, with no gate.
- **`getFanRPMValid()` returns the base-class `true` for ITE**, because ITE
  tracks no validity. That is deliberate and preserves existing behaviour, but it
  means the rotor-start floor treats an ITE tachometer as trustworthy when it is
  not.
