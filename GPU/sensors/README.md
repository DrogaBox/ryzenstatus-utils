# GPU sensors

`GPUSensors.kext` shows the sensor readings that Apple's AMD driver takes on a Navi 21
card (RX 6800, 6800 XT, 6900 XT) and then throws away. `gpusensors` prints them.

macOS publishes seven GPU statistics by itself in the I/O Registry under
`PerformanceStatistics`: GPU and memory clocks, fan speed and percentage, activity, board
power, and one temperature. That temperature is the **hotspot**, the hottest point of the
chip.

Apple's driver reads those values from its **PMLog** (the power management log, a table of
sensor readings its power management library fills using AMD's ADL_PMLOG numbering). The
table has room for about 40 values. By default the driver fills 12 of them on an RX 6800
XT, which add to what macOS already shows:

- edge temperature (the one most tools call "GPU temperature")
- GFX voltage
- memory activity
- the PCIe link generation and lanes the card is actually running at

The driver reads more than that every second and drops it: the memory temperature, the
temperatures of the voltage regulators (GFX and the two for memory), the SOC and memory
voltages, the throttler status (why the card is holding its clocks back) and the SOC, video
and fabric clocks. Version 0.2.0 turns on the driver's own setting that keeps them all
(see [Why the driver fills only 12 values](#why-the-driver-fills-only-12-values)). On an
RX 6800 XT it brings back the memory and GFX VR temperatures, the SOC and memory voltages,
the SOC and fabric clocks and the throttler status; the two memory VR temperatures read 0
on that card.

## How it works

The driver asks its power management library for a table of readings, the PMLog. The kext
stands behind the one function that hands that table back (`_PEM_CWDDEPM_QueryPMLogData`
in `AMDRadeonX6000HWLibs`, or `AMDRadeonX6800HWLibs` on cards set up that way). It calls
Apple's function first, with the same arguments, and returns its answer unchanged. When
the answer is good, it keeps a copy.

It never asks the GPU or its power firmware anything itself. The readings are the ones the
driver takes anyway, at the driver's own pace. A monitor that reads them (`gpusensors`,
`ioreg`, or another app such as RyzenStatus) only reads the I/O Registry. It adds no work
for the card, and any number of monitors can read at once.

The kext only acts when the function starts with the exact 17 bytes seen in macOS 15.8.2,
15.8.3, 26.7.2 and 26.7.3, which are the same in both libraries. On any other build it does
nothing, and `Status` says why. It does not change what macOS itself publishes.

For the sensors, the one thing it changes in the driver is a setting of the driver itself:
`PP_EnableAllPMLogSensors`, set to 1 on each Navi 21 card, before the power management
starts and only once the function above is routed. The driver reads it once and has no
other use for it; with it, the driver copies into the table the values it already reads
every second. A value given in the OpenCore DeviceProperties is left as it is (0 keeps the
driver's own list), and `-gpusensnoall` leaves the setting alone.

The GPU control (below under Install) routes more functions of the same library: 0.3.0
watches `Phw_SwSmu_WorkLoadPolicyManager`, and with `gpuprofile` sets a second driver setting,
`PP_WorkLoadPolicyMask`, right before `AtiPowerPlayServices::ppInitialize`; 0.4.0 also watches
`Phw_SwSmu_GetPowerLimit`, `smu_11_0_7_set_power_limit`, `ppSleep` and `ppWake`. Every one of
them passes its calls through unchanged. 0.5.0 routes `ppInitialize` always (still
pass-through) and is the first version that sends something to the GPU: it calls the driver's
own `AtiPowerPlayServices::ppCWDDE` to lower the power limit, only when a program asks
and an administrator armed it (see [The power limit](#the-power-limit-050)).

## Build

```bash
tools/bootstrap.sh       # once: the pinned Lilu and kernel SDK
sensors/build.sh         # sensors/build/GPUSensors.kext, gpusensors and gpucontrol
```

## Use

```bash
sensors/build/gpusensors             # one reading
sensors/build/gpusensors --watch 1   # every second
sensors/build/gpusensors --json      # for scripts and apps
sensors/build/gpusensors --compare   # side by side with what macOS publishes
ioreg -r -c DrogaBoxGPUSensors -l    # the raw properties
```

The properties of `DrogaBoxGPUSensors` are:

| Property | What it is |
|---|---|
| `Status`, `StatusCode` | `active`, `waiting for ...`, or `off: ...` with the reason |
| `Library` | which of the two driver libraries it found |
| `AllSensors` | what became of `PP_EnableAllPMLogSensors`: `requested`, `already set (OpenCore DeviceProperties)`, `off: set to 0 in the OpenCore DeviceProperties`, `off: -gpusensnoall`, or `not set: ...` with the reason |
| `Control` | the GPU control (0.3.0): `watching the profile requests`, `waiting for ...`, or `off: ...` with the reason |
| `Profile` | the boot power profile: `not asked: macOS keeps its 16 (compute)`, `set before the power management started`, `asked: waiting for ...`, `refused: ...`, `off`, or `not set: ...` with the reason |
| `ProfileSet` | the profile put on the card, only once every allowed card took it |
| `ProfileRequests` | `{ Last, Seen, Calls }`: the profile the driver's own clients asked for (before `PP_WorkLoadPolicyMask` replaces it), every bit seen since boot, and how many times |
| `Power` | the power watch (0.4.0): `watching the power limit, sleep and wake`, `watching in part: see PowerWatch`, `waiting for ...`, or `off...` with the reason |
| `PowerWatch` | `BootW` (the limit the card booted with, as the framebuffer read it), `LastReadW` and `Reads` (it reads again after each wake), `Sent`, `LastSentW`, `LastSentSource`, `LastSentResult` (limits sent to the power firmware by anyone; result 0 = sent), `Sleeps`, `Wakes`; each only when its function is watched, `BootW` and `LastReadW` once read, `LastSent*` once `Sent` is above 0 |
| `Write` | the power limit write path (0.5.0): `off until restart: see WriteState`, `read only: this card can only be read (see WriteState)` (0.8.0, an RX 6900 XT), `waiting for ...`, `closed: sudo gpucontrol arm opens it until restart`, or `armed: ...` (nothing held, a program holds a lower limit, a program holds a fan or clock change (see `OD8Write`), a program is setting a limit, going back, between sleep and wake) |
| `WriteState` | `WriteOff` and `WriteOffText` (why writing is off, 0 and empty when it is not; 15 = `ReadOnlyCard` since 0.8.0), `Armed`, `Owned`, `HeldW` (the limit now: the start-up one when nothing is held), `Changes` and `Reverts` (confirmed since boot), `LastReply` (the last `set`'s answer, numbered as in `control_logic.hpp`) |
| `PowerRangeState` | the card's power range (0.8.0): `from the card: start-up limit less its OD8 power percent`, `not known yet: waiting for a clean OD8 read`, `not known: ...` (the start-up limit is not read or not believable, or the OD8 power entry is not as expected), `the card offers no lower power limit: only the start-up limit`, `waiting for the driver's library` or `off...` |
| `PowerRange` | (0.8.0) `Known` (1 once the floor is known), `FloorW` and `MaxW` (the lowest and highest limit `set` takes, W; only when known; equal when the card offers nothing lower), `StepW` (10), `PercentMin` and `PercentMax` (the card's OD8 power percent, signed 32-bit like the OD8 settings: -6 and 9 on the test RX 6800 XT; once OD8 was read). Published on a read-only card too (its own floor, for reading only: nothing is taken there). See [The power limit](#the-power-limit-050) |
| `OD8State` | OD8, read only (0.6.0): `read`, `read, but an entry is not as expected`, `not available: ...`, `no data: ...`, `not read: ...`, `stopped: ...`, `waiting ...` or `off: ...` |
| `OD8` | once tried: `Reads`, `Tries`, `LastResult`, `LastReadAgeS`, `Caps`, `NotAllowed`, `StockOdd`, `DefaultsMoved`, `CurrentMoved`, `FanCurveStock`, `FanCurve` (five [C, %] pairs) and `Settings` by name (`Feature`, `Min`, `Max`, `Stock`, `Current`); `OddEntry` and `OddEscape` when an answer was not as expected. See [OD8, read only](#od8-read-only-060) |
| `OD8Write` | OD8 writes (0.7.0): `off until restart: see WriteState`, `read only: this card can only be read (see WriteState)` (0.8.0), `waiting for a clean OD8 read (OD8State)`, `closed: sudo gpucontrol arm opens it until restart`, or `armed: ...` (OD8 at stock, a program holds a fan or clock change, going back to stock, the last call was not taken) |
| `OD8WriteState` | `Held` (1 fan curve, 2 zero RPM off, 4 GFX max, 8 not confirmed, 16 GFX min since 0.9.0), `Changes` and `Reverts` (confirmed since boot), `LastCheck` and `LastCheckText` (why the last OD8 request was refused, 0 = none), `SentPower` (power limit sends seen during OD8 calls), `FanCurveHeld` (C × 1000 + %), `GfxMaxHeld` and `GfxMinHeld` (0.9.0) while held, `Takes` (0.9.0: what `setOd8` takes, in `Held` bits, 23). See [OD8 writes](#od8-writes-070) |
| `Samples` | readings copied since boot |
| `SampleAgeMs` | how old the last reading is; with `Sensors`, `Units` and `PMLog` it is absent once the copy is older than 5 s (the driver stopped sampling: the card is asleep, powered down, or its driver is gone) |
| `Sensors` | `{ name: value }`, in the units of `Units` |
| `Units` | `{ name: unit }` |
| `PMLog` | `{ "id": value }` for the same readings as `Sensors`, by AMD's id |

The kext brings these up to date when its whole property table is read: in code,
`IORegistryEntryCreateCFProperties` (what `ioreg -l` does). `IORegistryEntryCreateCFProperty`
for one key returns what the last whole read left, which can be minutes old. An app should
read the whole table once and take every value from it, which also gives one moment for all.

Only ids the driver writes a reading to are published. Some ids are marked filled by the
driver but never get a value (VCE and VCN clocks, SOC power and current, GFX and SOC
temperature, GFX power and current, and a few without a name); with every sensor on they
would read 0, so they are left out.

Without the kext, `gpusensors` shows what macOS publishes by itself and says that the rest
needs the kext.

## Install

```bash
install/sensors.sh check            # changes nothing
sudo install/sensors.sh install     # then reboot
```

The kext goes in your OpenCore EFI, after Lilu. `install/sensors.sh` puts it there with a
backup of `config.plist`, and `uninstall` takes it off; see
[install/README.md](../install/README.md). Boot arguments: `-gpusensoff` turns it off,
`-gpusensnoall` keeps the driver's own list of sensors, `-gpusensdbg` logs more, and
`-gpusensbeta` lets it start on a kernel newer than Tahoe.

The GPU control (0.3.0) only acts on an RX 6800 XT (device 73BF, revision C1), and only routes
a driver function that starts with the bytes it expects (`gpuprofile` needs both of its
functions to). `gpuprofile=0`, `2` or `16` sets the power firmware's workload profile for the whole boot: 0 lets the driver choose (the
video profile while video plays, the firmware's default otherwise, close to what Linux does),
2 is power saving, 16 is what macOS sets on every Navi 21. Without it the profile stays 16 and
the control only watches. Not booted with `gpuprofile` yet. `-gpuctloff` turns the control off and keeps the sensors. Nothing
in 0.3.0 sends anything to the GPU or its firmware, and there is no power limit yet.

The power watch (0.4.0) has the same RX 6800 XT gate and the same `-gpuctloff` switch. It
only reads what passes through the four functions and sends nothing. Not booted yet. In
`AMDRadeonX6800HWLibs` (cards set up that way) `smu_11_0_7_set_power_limit` starts
differently, so there it is left out and `Power` says `watching in part`.

## The power limit (0.5.0)

Booted and run on an RX 6800 XT (macOS 26.7.3, 2026-11-19): 230 W and 200 W were held
around a 60 s GPU load and the start-up limit came back each time (see
[What has been checked](#what-has-been-checked)).

```bash
sensors/build/gpucontrol status                           # anyone
sudo sensors/build/gpucontrol arm                         # opens writing until restart
sensors/build/gpucontrol hold power 230 -- gpubench 60    # 230 W while the command runs
sensors/build/gpucontrol disarm                           # closes it again (0.8.0), anyone
```

What the kext lets a program do, and nothing else:

- Lower the GPU's package power limit, from the card's own minimum up to the limit the
  card started with, in 10 W steps. Since 0.8.0 the minimum is the one Linux amdgpu uses
  (`power1_cap_min`, `sienna_cichlid_init_ppt_limits`): the start-up limit less the
  lower bound of the card's OD8 power percent, read from the first clean OD8 read after
  boot. On the test RX 6800 XT that is 240 W less 6 % = 225 W, so 230 W is the only
  lower value (0.5.0 to 0.7.2 took a fixed 200 W, and the card did take 200 W); a stock
  264 W table gives 248 W. `PowerRange` publishes it. Until the floor is known (OD8 not
  read cleanly yet, or its power entry not as expected) every change is refused
  ("not known"), and a card that offers no power percent takes nothing lower. Anything
  else is refused, never clamped: below the floor, not a 10 W step, and anything above
  the start-up limit. Asking for the start-up limit itself is the same as `release`.
  Never raise anything: there is no way to ask for more than the card started with.
- One program at a time; another program's `set` hears "busy". At most one change every
  2 s.
- Only after `sudo gpucontrol arm` since the last restart (the caller must be root).
  `gpucontrol disarm` (0.8.0) closes it again without a restart. Any program may: closing
  can only make it safer, and only `arm` (root) opens it again. It is refused ("a change
  is still applied or being handled") while a program holds a change, a way back runs, a
  request is waiting or running, or anything may not be at its start-up value yet, so go
  back first. After it every change is refused as
  before `arm`.
  `-gpuctloff` keeps it closed for good, and so does anything the kext cannot check:
  writing needs exactly one AMD GPU and it must be an RX 6800 XT (73BF rev C1),
  `AMDRadeonX6000HWLibs`, every 0.4.0 watcher routed, `ppCWDDE` starting with the 24 bytes
  it expects, and the start-up limit read and between 200 and 300 W (a check of the read,
  not the floor). A second PowerPlay object or hwmgr also turns it off until restart.
  `WriteState` says why.
- An RX 6900 XT (73BF rev C0, 0.8.0) is read exactly like the RX 6800 XT: the same
  routes, the start-up limit, the OD8 table and the stock values, and `PowerRange`. Writing
  never opens on it, whoever asks: `WriteOff` 15 (`ReadOnlyCard`) from the card scan on,
  `arm`, `set` and `setOd8` answer "off", `gpuprofile` is not applied, every sender (0x2a,
  0x6e, 0xa1) refuses, and the only escapes it can reach are the read-only 0x9f and 0xa0.
  `OD8State` "read" does not mean writable: look at `WriteState`. If something later also
  stops the reads (the library is not the one expected, a route or `ppCWDDE` missing, the
  worker cannot start, a second power object, teardown), `WriteOff` shows that reason
  instead of 15; the card stays read only. A C0 next to another Navi 21 is two cards:
  `WriteOff` 2 (`NotOneCard`), and the senders still refuse.

How it sends: the only driver function it calls is `AtiPowerPlayServices::ppCWDDE`, the one
the framebuffer uses for its own escapes, with two escapes: 0x2a (is the GPU up) and then
0x6e (set the package power limit) with the watts. Both calls run on one kernel thread of
the kext, one at a time, never from inside a driver function and never from the program's
thread (the program waits 5 s at most for the answer). The driver has no range check of
its own for 0x6e; the kext checks the range where it builds the request.
How it keeps out of a sleep: the driver's 0x6e path has no sleep check of its own. So the
routed `ppSleep`, before the driver's own sleep starts, marks the sleep under the kext's
lock and waits for a call of the kext that is already running, 3 s at most (one stuck
power-firmware message is bounded at 2 s). The kext checks that mark and starts each call
under the same lock, so a call either ends before the sleep starts or is not made. If a
call still runs after 3 s, the kext logs it and lets the sleep go on. Nothing is sent again
until the driver's `ppWake` has returned, the framebuffer has read the limit again (or 10
s passed) and 2 s more have passed, the time the framebuffer needs to finish its own wake
work.

How it checks: every limit sent to the power firmware passes through
`smu_11_0_7_set_power_limit`, which the kext watches. A 0x6e counts as done only when that
watcher saw, on the kext's own thread, exactly one send of those watts that the firmware
took. If it did not, the kext sends the start-up limit once and turns writing off until
restart. If 0x2a says the GPU is not up, nothing is sent and the program hears "GPU asleep or
not ready"; if the driver could not send the 0x6e, the start-up limit goes back and the
program hears "busy". Nothing is retried.

When the start-up limit goes back:

| When | What the kext does |
|---|---|
| the program releases, or asks for the start-up limit | at once |
| the program quits, crashes or is killed (its connection closes) | at once |
| the program says nothing for 30 s (`hold` says "alive" every 5 s) | at 30 s |
| `set` gets no answer in 5 s, or is interrupted | whatever that program held goes back |
| the Mac sleeps | nothing is sent between sleep and wake; the program loses the hold |
| the Mac wakes, and a change was held before the sleep | 2 s after the framebuffer has read the limit again (or after 10 + 2 s) |
| a dark wake ends in another sleep before that | nothing; it waits for the next wake |
| the GPU is busy or not up during a way back | tried 3 times, 500 ms apart; then writing is off until restart |
| power-off, restart, or the GPU goes away | nothing more is sent |
| restart | nothing is kept: the card starts with its own limit |

`gpucontrol hold` releases when the command ends, on Ctrl-C, SIGTERM (passed on to the
command) and SIGHUP, and asks for the same limit again after a sleep. If `gpucontrol`
itself is killed, the kext sees the connection close and goes back on its own.

The channel is an IOUserClient on `DrogaBoxGPUSensors` (type 0), with scalars only:
`status`, `arm`, `set(watts)`, `alive`, `release`, since 0.7.0 `setOd8`, and since 0.8.0
`disarm` (selector 6, `{version}` in, one reply out, any caller) (version 2;
0.5.0 and 0.6.0 were version 1; 0.8.0 only adds, so it stays 2; so does 0.9.0, whose
`setOd8` also takes a 14th scalar, the GFX minimum, and still takes the 13 of 0.7.0). Every call passes the
version first; another version is refused. 0.8.0 adds two answers: 19 "a change is still
applied or being handled" (disarm) and 20 "the card's minimum power limit is not known"
(set, only below the start-up value: above it is "above the start-up limit" either way). `set` and
`setOd8` answer "off" (writing off or a read-only card) and then "not armed" before they
look at any value they carry, so an absurd value still gets the real reason. The GFX
clock of `setOd8` is no longer cut at 5000 MHz on the wire (only what the 32-bit field
cannot carry is malformed): its first check is the card's stock maximum. The numbers and
answers are in `sensors/kext/control_logic.hpp` ("channel").

## OD8, read only (0.6.0)

Booted on an RX 6800 XT (macOS 26.7.3, 2026-11-19): read cleanly at boot and after a wake
(see [What has been checked](#what-has-been-checked)).

```bash
sensors/build/gpucontrol od8      # anyone; prints the kext's OD8 properties
```

OD8 is the driver's overdrive data: the fan curve (5 points), zero RPM, GFX clock range,
memory clock, power percent and a few more, each with a min, max, default and current
value. 0.6.0 only reads it, with the two escapes the driver answers from its own memory
(0x9f ranges and defaults, 0xa0 current values; no message to the power firmware). It reads
2 s after the framebuffer's first read of the power limit, and again after each wake. The
first complete read after boot is kept as "stock" (`StockOdd` 1 if its defaults were not as
expected). After a failed read the numbers stay those of the last complete one;
`LastReadAgeS` says how old they are. Signed values (`PowerPercent` min -6) show in `ioreg` as
unsigned 32-bit numbers; `gpucontrol od8` prints them signed.

OD8 is read by the power limit's worker, so it runs only where writing could: one AMD GPU,
an RX 6800 XT on `AMDRadeonX6000HWLibs`, every watcher routed. With `-gpuctloff`, on
`AMDRadeonX6800HWLibs` (NootRX setups) or when the worker cannot start, `OD8State` says it
is off.

`OD8State` says what happened: read, not available (the driver refused: OD8 is off on this
card), no data (the GPU was asleep), or stopped (an answer that does not fit what the
driver was read to do; then nothing more is read until restart). `OD8` has the numbers:
`Settings` by name (`GfxMaxMHz`, `FanZeroRpm`, `FanCurve1C`, `FanCurve1Pct`, ...) with
`Feature` (0 = not offered on this card), `Min`, `Max`, `Stock`, `Current`;
`FanCurveStock` and `FanCurve` as five [C, %] pairs; `DefaultsMoved` and `CurrentMoved`
since boot. The fan curve the driver reports at stock is made up by the driver: at stock the
firmware holds a target temperature instead of following a curve.

Changing OD8 is 0.7.0, below.

## OD8 writes (0.7.0, 0.7.1)

Booted and run on an RX 6800 XT (macOS 26.7.3, 2026-11-19): every kind of change was held
and taken back, also across a sleep (see [What has been checked](#what-has-been-checked)).

```bash
sudo sensors/build/gpucontrol arm
sensors/build/gpucontrol check fan 30:20,40:36,44:52,46:68,48:100          # sends nothing
sensors/build/gpucontrol hold fan 30:20,40:36,44:52,46:68,48:100 -- gpubench 60
sensors/build/gpucontrol hold zerorpm off -- sleep 30
sensors/build/gpucontrol hold gfxmax 2300 -- gpubench 60
```

What a program may hold, through the power limit's channel and owner rules, and nothing
else:

- A fan curve of five points (C:%), all at once, only while the watchdog below has a
  PMLog copy at most 2 s old. It must give at least the stock curve's
  air at each of its own points and at each stock point, start at 30 C or below, rise
  (speeds never fall), stay in the driver's range (25-100 C, 20-100 %), and reach 100 % at
  48 C or below. The stock fan holds 70 C on the hotspot sensor, and the edge sensor reads
  16 to 22 C below it at load (measured 2026-11-19, gpubench 60 s at 240 W); in case the
  curve reads the edge sensor, the kext takes the 22. So the stock curve itself is
  refused: it reaches 100 % only at 70 C.
- Zero RPM off (the fan spins at idle).
- A lower GFX maximum, from 1500 MHz up to the stock one.
- A raised GFX minimum (0.9.0), inside the card's own range for it (500 to 2800 MHz on the
  test card, stock 500) and never above the GFX maximum of the same state. It keeps the clock
  up at idle, so it is the one setting that can make the card warmer: it is taken only while
  the watchdog below has a fresh PMLog copy, and the watchdog's 95 C limit and its missing
  readings rule hold it as they hold a curve (not the 75 C rule, which needs a curve: the
  stock fan climbs slowly by design). `gpucontrol hold gfxmin 1500 -- <command>`.

Memory clock, voltage and power percent are never written. The memory maximum cannot be
lowered on this card anyway: its 0x9f minimum is the stock value (2000 MHz), and a memory
clock change blanks the display. The fan minimum speed and target temperature are not
offered by the driver while it offers the curve (feature 0; the driver skips them). A request
that fails a check is refused with the reason, never clamped; `gpucontrol check` runs the
same checks on the published OD8 and says what would be taken. OD8 and the power limit are
never held together.

How it sends: on the kext's worker thread, each change reads 0x9f and 0xa0 fresh and checks
that OD8 is still what it read at boot (the GFX pair may drift 25 MHz, as it does across a
wake; everything else exactly). Then one 0xa1 carries the whole wanted state: the ten curve
entries every time (the driver's fan mode depends on all ten being sent), zero RPM, and
the GFX pair. Stock is the all-ten reset, zero RPM on and the GFX pair at stock. The call
asks the driver not to keep it for its replay after wake.

How it checks: 0x9f and 0xa0 are read again. Every sent entry must read as sent (GFX max
may read up to 25 MHz lower, never higher), every other entry as before, and the driver's
replay list must still be empty. Otherwise the stock call goes out at once and writing is
off until restart. Whenever writing goes off while a change may still be on the card (for
any reason), the stock call is tried up to 3 times, 500 ms apart, once; then nothing more
is sent and `OD8WriteState` `Held` keeps 8 (not confirmed).

While a curve is held, a watchdog reads the hotspot and fan speed once a second from the
kext's own PMLog copy. Hotspot 75 C or more with the fan under 90 % for 5 s, hotspot 95
C at any fan speed (0.7.2; stock reaches 90-91 C in a 5 minute load at 240 W), or no
readings for 10 s: the stock call goes out and writing is off until restart. The fan percent is the RPM over the table's maximum (1208 RPM reads 34 %
with 3500), so full PWM may read a little under 100. It runs in the kernel, so it does not
depend on `gpucontrol`; it stops once writing is off.

Everything goes back to stock in the same cases as the power limit (release, the program
closes or crashes, 30 s of silence, a wake). Restart keeps nothing.

GPU recovery: on macOS 26.7.3 the driver's only recovery is an engine reset in the
accelerator (`AMDAccelChannel::resetHardwareAndReplay`), which never tells PowerPlay. An
escape during it is a normal firmware message, not refused, and the read-back still checks
it. The kext does not route it.

## What has been checked

| What | Result |
|---|---|
| Which values the driver fills, and what each one is | Read in the driver: the function that fills the table, the function that prints it, and the function that reads seven values out of it for `PerformanceStatistics`. All three agree with AMD's public ADL_PMLOG numbering |
| The function's first bytes in both libraries of 15.8.2, 15.8.3, 26.7.2 and 26.7.3, and on this Mac | Identical; accepted by `pmlogtest` (`tests/run.sh` checks this Mac every run) |
| The kext's imports | All found in this kernel or in Lilu (`tools/kextlinks.sh`) |
| Running on a card (0.1.0) | RX 6800 XT, macOS 26.7.3, 2026-11-18: loaded from OpenCore on the first boot, `Status` active, readings from the first seconds. Filled ids: 1, 2, 8, 14, 15, 19, 20, 21, 23, 27, 40, 41 |
| Running on a card (0.2.0, every sensor on) | RX 6800 XT, macOS 26.7.3, 2026-11-18: `Status` active, `AllSensors` requested, and the GPU device shows `PP_EnableAllPMLogSensors = 1`, so the driver read the setting the kext put there. All 26 published ids are filled. New at idle: memory temperature 40-44 C, GFX VR temperature 36-37 C, SOC voltage 950 mV, memory voltage 850 mV, SOC clock 800 MHz, fabric clock (see below), throttler status 0. Zero in 16 s of idle: memory VR 0 and 1 temperatures (always 0; not known whether the board wires them), the four video clocks (no video playing) |
| Fabric clock at idle (0.2.0) | Moves between about 94 and 1291 MHz from one second to the next. That is how the driver reads it: the fabric clock is the firmware's average after deep sleep (`AverageFclkFrequencyPostDs`, offset 58 of the metrics table, named by the driver's own debug print), so the time the fabric sleeps pulls it down. The GFX clock works the same way below 16 % activity (it switches from the average before deep sleep to the one after), which is why it reads near 0 at idle while macOS shows a higher figure. The memory clock is twice the average memory clock after deep sleep. Read in `smu_11_0_7_query_pm_log` and `Phw_CommPMLog_PopulateData`, macOS 26.7.3 |
| Against what macOS publishes (`gpusensors --compare`, idle) | Memory clock 1986/1990 MHz, fan 1201/1202 RPM and 34/34 %, board power 28/28 W, hotspot 41/40 C. GFX clock and activity differ at idle (28 against 108 MHz, 0 against 4 %): they move faster than the two reads |
| PCIe codes | Link speed 2 and lanes 8 match the link of the PCIe root port above the card (`IOPCIExpressLinkStatus`: generation 3, 8 lanes). AMD counts the generation from 0, so 2 is PCIe 3.0; `gpusensors` shows both |
| Units | Temperatures in degrees C, clocks in MHz, power in W, fan in RPM and %, activity in %, GFX voltage in mV (856 at idle) |
| Running on a card (0.3.0, watching only) | RX 6800 XT, macOS 26.7.3, 2026-11-19, no `gpuprofile`: `Control` watching the profile requests, `Profile` not asked, `PP_WorkLoadPolicyMask` still 16; in the first minute `ProfileRequests` showed 7 calls, all asking 0 (no particular profile). Sensors as with 0.2.0; the display driver's I2C and HDCP messages in the log were the same with 0.2.0 |
| How often | About once a second at idle: `Samples` went from 53 to 64 in 10 s and `SampleAgeMs` never passed 950 ms |
| The power limit's decisions (0.5.0) | `controltest`, 186 checks on the CPU: range, the two escapes' bytes, how answers and sends are read, one pending request (also given up while its call runs), stale requests after a way back, 3 tries for a way back, the 30 s deadline, the wait after wake, its 2 s margin and a new sleep during them, the reasons that keep writing off |
| The functions 0.5.0 routes or calls, on this Mac | `tools/driver/ctlentries.py` against the 26.7.3 kernel collection: the six routed functions and `ppCWDDE` start with the bytes the kext expects; `ppCWDDE` is the same in `AMDRadeonX6800HWLibs` |
| The routed functions pass everything through (0.5.0) | Read in the built kext's disassembly: each one calls the original with the same arguments and returns its result |
| Writing on a card (0.5.0) | RX 6800 XT, macOS 26.7.3, 2026-11-19, start-up limit 240 W. `hold power 230 -- gpubench --sustain 60`: sent and confirmed, back to 240 W at the end (`WriteState` 1 change, 1 way back); sustained power 228.1 W against 240.6 W in a 240 W run four days earlier, 2.2 % less compute, temperature peak 81 against 83 C. Then `hold power 200`: 199.4 W (10 s windows 197-201 W), 5.3 % less compute, temperature peak 72 C, fan peak 2688 against about 3500 RPM; back to 240 W (2 changes, 2 ways back). No GPU errors in the kernel log. The room temperature was not measured |
| The OD8 readout's decisions (0.6.0) | `controltest`, 31 more checks (217): the two escapes' headers and buffers (count 38, sentinel), no data / refused / not initialized / wrong size, each kind of entry that does not fit, which answers are tried again, the feature bit of every setting id |
| Reading OD8 on a card (0.6.0) | RX 6800 XT, macOS 26.7.3, 2026-11-19, the test card's 240 W / 1075 mV power table: read on the first try at boot, no odd entry, replay list still empty. `Caps` 0x33f0d, `NotAllowed` 0xfffcc0f2; GFX max 500-2800 MHz, stock 2354; GFX min 500; memory max 2000-2150, stock 2000; power percent -6 to 9; zero RPM on; stock curve 30/20, 50/36, 56/52, 63/68, 70/100 (C/%), made up by the driver from the 70 C target. After one sleep and wake: read again cleanly, GFX max current 2354 → 2359 MHz (the driver re-reads the firmware's table at resume), everything else the same |
| The OD8 write decisions (0.7.0) | `controltest`, 58 more checks (275), with the card's real 0x9f/0xa0 values: every refusal, the 0xa1 builder for each request shape, the stock call (also with moved defaults), the read-back, the watchdog's decisions. An independent review also ran 18.8 M random accepted curves against the stock curve every 0.25 C: none gave less air |
| `gpucontrol check` against the card's published OD8 (0.7.0 tool, 0.6.0 kext) | `fan 30:25,40:50,45:70,48:85,50:100` taken; the stock curve refused (100 % at 70 C); `zerorpm off gfxmax 2300` taken; `gfxmax 2400` refused (above stock) |
| The sensor gap (test 0, 2026-11-19) | gpubench 60 s at the 240 W start-up limit, stock fan, read only: hotspot - edge at load 16 to 22 C (median 18), peak hotspot 81 C, edge 59 C, fan 3511 RPM = 100 %. The stock fan does not jump to 100 % at 70 C hotspot: it climbs slowly (75 % at 76 C, 89 % at 78 C, 96 % at 80 C). 0.7.1 takes the 22 |
| Booting 0.7.0 | RX 6800 XT, macOS 26.7.3, 2026-11-19: OD8 read on the first try, no odd entry, replay list empty, `OD8Write` closed, `OD8WriteState` Held 0 |
| Zero RPM off on a card (0.7.1) | RX 6800 XT, macOS 26.7.3, 2026-11-19: held 30 s at idle and taken back; `FanZeroRpm` read 0 while held and 1 after; replay list empty. The fan did not change: it already turns at idle (edge 39 C, above the 30 C stop temperature) |
| A fan curve on a card (0.7.1) | `hold fan 30:20,40:36,44:52,46:68,48:100`, 20 s idle then gpubench 60 s at 240 W: read back as sent, taken back at the end, watchdog quiet. Idle about 2000 RPM (stock 1203). At the start of the load the fan went from 1982 to 3539 RPM in 4 s (the stock loop takes about 50 s to pass 90 %). Hotspot 67-69 C for the first 30 s (stock 70-75), 82 C at 60 s (stock 81): at 240 W the cooler is at its limit with the fan at 100 % either way. Compute and power as at stock (228.5 W). Edge stayed at 52 C or more whenever the hotspot was at 70 C or more. Which sensor the curve follows is still not known |
| GFX max on a card (0.7.1) | `hold gfxmax 2300` during gpubench 60 s, stock fan: GFX clock 2237-2247 MHz, 198.1 W (stock 228.5), 5 % less compute, hotspot peak 72 C (stock 82-83); the stock maximum came back at the end |
| Power limit and OD8 at once (0.7.1) | With 230 W held, an OD8 change was refused ("busy") and the 230 W stayed; with zero RPM off held, a power limit was refused. Curve + zero RPM off + GFX max 2300 in one call: all three read back, all three taken back |
| OD8 across a sleep (0.7.1) | Zero RPM off, and then the curve, held while the Mac slept. The curve was still on the card right after the wake (fan 1950 RPM); 2 s later the kext had put stock back by itself (1329, then 1201 RPM), `gpucontrol hold` asked again and the curve came back; stock again at the end. The GPU log lines at sleep are the same as with nothing held |
| A long load at stock (2026-11-19) | gpubench --sustain 300 at the 240 W start-up limit, stock fan, read only: 232.5 W, no compute errors; hotspot 85 C after 80 s, 88 C after 2 minutes, 90-91 C after 5 and still rising about 0.7 C a minute; edge 62 C at most; stock fan 96-100 %. 220 of the 300 s at 85 C or more, which is why the watchdog's limit went from 85 to 95 C in 0.7.2 |
| The 0.9.0 decisions | `controltest`, 371 checks on the CPU (was 336): the GFX minimum against the card's real 0x9f (500 to 2800, never above the stock or the lowered maximum, the range from the entry, not a constant), the call it builds (the pair with the minimum, memory and fan entries untouched), the shapes never sent (minimum above the maximum, the pair split, a minimum of 0), its read-back (up to 25 MHz lower, never higher), the 14- and 13-scalar wire forms and every other count, the watchdog without a curve (only 95 C and no readings count). `curve-cases.jsonl` grew by 20 GFX minimum cases, the first 100 unchanged. Four mutations of the new rules each failed the tests. Not booted |
| The 0.8.0 decisions | `controltest`, 336 checks on the CPU (was 277): the floor from the card's real 0x9f (225 W at 240 W, 248 W at 264 W, Linux's integer division), no floor and every change refused when OD8 is not read, odd or its power entry is not as expected; disarm taken from any caller, administrator or not, refused while a change, its way back or an unconfirmed state is there, and closed afterwards (arm still needs an administrator); a read-only card readable, never armable or changeable, its worker started; `set` and `setOd8` answering "off" / "not armed" before any value, absurd ones included; the GFX clock refused by the card's stock maximum, not the wire; the scan's decision for one read-only card and for a mixed machine; which reason `WriteOff` keeps; a request counted as being handled only while waiting or running. Each new check was broken on purpose once and failed. Not booted |
| The floor's source on this Mac (0.8.0) | `PP_PhmSoftPowerPlayTable` in ioreg, read 2026-11-20: overdrive table revision 0x81, power limit cap set, `POWERPERCENTAGE` max 9 min 6, `SocketPowerLimitAc[0]` 240; the kext's 0x9f gives -6 to 9 and the start-up read 240 W. Linux's formula read in `sienna_cichlid_ppt.c` (master, and v6.6, which had no minimum) |
| The stock GFX maximum across wakes | The driver's default moves between 2354 and 2359 MHz at a wake, in both directions (seen three times); the way back sends the lower of the first read and the fresh one |

## Why the driver fills only 12 values

Read in `AMDRadeonX6000HWLibs` of macOS 26.7.3 (2026-11-18). The driver decides once, when
it starts, which values it will copy into the table. The request it sends every second
carries no list: the function ignores its input.

- The list comes from a fixed table for this chip family (`_smu_11_0_7_supported_sensors`).
  It leaves off the SOC, video and fabric clocks, the memory and voltage-regulator
  temperatures, the SOC and memory voltages and the throttler status. For two device ids
  only, 0x73AE and 0x73A1, the driver adds back the memory temperature, the video clocks,
  the SOC and memory voltages and the throttler status. The RX 6800 XT is 0x73BF.
- The values left off are still read: every second the driver copies the power firmware's
  whole metrics table and extracts them, then drops them when it fills the PMLog.
- Before using that table the driver reads the setting `PP_EnableAllPMLogSensors` (the
  same kind of setting as the other `PP_` keys on the GPU). When it is not 0, every value
  the driver knows is filled, including some it never writes, which then read 0.

- The setting is read through the driver's registry callback (`AppleMcilGetRegister` in
  `AMDRadeonX6000Framebuffer`), which looks the key up in the GPU device's properties when
  it is asked, the same place the other `PP_` keys and the OpenCore DeviceProperties are.
  That it is the PCI device itself was inferred from the code; 0.2.0 showed it on an RX
  6800 XT, where the setting the kext puts there reaches the driver.
- The setting is read in one place only, and the ids it adds are filled from values the
  driver has already read (the memory voltage from a register the driver already reads for
  the GFX voltage). Nothing new is asked of the power firmware.

Seen working with 0.2.0 on an RX 6800 XT (2026-11-18): the property set on the PCI device
reaches the driver, and every new id is filled. The memory VR temperatures read 0 on that
card. The video clocks, memory activity and throttler status were only seen at idle.

## What the throttler status (id 35) means

It is not the power firmware's own throttler word, nor Linux's `INDEP_THROTTLER_*` bits. The
driver builds a 3-bit value from the firmware's per-limiter throttling percentages
(`ThrottlingPercentage[]` of the metrics table) and the PMLog keeps its low 3 bits. Read in
`AMDRadeonX6000HWLibs` of macOS 26.7.3 (`smu_11_0_7_map_smu_throttler_status`, called from
`smu_11_0_7_query_pm_log`; the compares are unsigned in the disassembly), 2026-11-18:

| Bit | Value | Set when | Threshold (default) |
|---|---|---|---|
| power | 1 | any of the four package power limits (PPT0 to PPT3) is at or above the threshold | `SMU_Power_Throttle_Indicator_Threshold` (80) |
| thermal | 2 | any of edge, hotspot, memory, GFX VR, liquid 0 and 1, PLX is at or above it | `SMU_Thermal_Throttle_Indicator_Threshold` (90) |
| current | 4 | the GFX current limit (TDC_GFX) is at or above it | `SMU_Current_Throttle_Indicator_Threshold` (80) |

The memory and SOC VR limits, TDC_SOC, FIT, PPM and APCC are not looked at. The thresholds
are driver settings read once at start; whether anything overrides them on a given Mac, and
what the firmware's percentages mean exactly, was not checked, and no load test was run.
`AMDRadeonX6800HWLibs` was not read. So 0 at idle is expected; under a heavy load, 1 means
the card is at its power limit.

## Limits

- Navi 21 on Sequoia 15 and Tahoe 26.
- It shows what the driver reads, when the driver reads it. The driver reads from a
  repeating timer (`AMDRadeonX6000_AMDHardware::handleHWPerfPollTimer`, which calls
  `samplePMStatistics` and sets itself again), about once a second at idle.
  `SampleAgeMs` says how fresh each reading is.
