# GPU control

Settings › GPU control changes an AMD Radeon RX 6000 card's power limit, fan, clocks and
voltage through the optional GPUSensors.kext (see [GPU/sensors](../GPU/sensors/README.md)).
This page lists every control, the range it takes, what it does and what can go wrong.

Every value comes from the card itself: the ranges are the ones its own firmware tables
publish to the driver (the OverDrive data, the same limits AMD's Radeon Software offers on
Windows). Nothing here is a number written into the app for one card, and the kext refuses
anything outside those ranges instead of rounding it.

Some things hold for all of it:

- Changes are closed until an administrator allows them (Allow GPU Changes), and they stay
  allowed only until the Mac restarts or you close them again. With Allow changes after restart too,
  asking for your password once lets remembered settings come back after a restart as well.
- One program holds one change at a time. When `gpucontrol hold` from Terminal holds the card,
  Settings › GPU control says it is RyzenStatus's own tool instead of "Another program has the control".
  The kext puts the card back to stock on its own when RyzenStatus quits or crashes, when it stops
  answering for 30 seconds, after every sleep, and on restart. Nothing is stored on the card.
- The power limit and the OverDrive settings (fan, clocks, voltage) are never held at the
  same time: while one is held, the other answers "busy".
- Whatever raises a clock or the power limit, and the fan curve, are held under a watchdog
  that reads the hotspot temperature every second. At 95 °C, or when the readings stop for
  10 seconds, it puts stock back and closes changes until restart. While any setting is held,
  GPUSensors takes the card's readings itself once a second so the watchdog stays active even
  when no other tool is polling the card.

## Which cards

| Card | What the page does |
|---|---|
| RX 6800 XT (Navi 21, 73BF rev C1) | everything below; the card the kext was built and tested on |
| RX 6900 XT (Navi 21, 73BF rev C0) | readings only: the kext reads it the same way and never writes |
| RX 6800, RX 6950 XT, Pro W6800 / W6900X, every Navi 23 (RX 6600, 6600 XT, 6650 XT, Pro W6600) | not read by the control yet; the sensors still work |

NVIDIA cards and NullMoth are not supported or tested.

A control only shows when the kext says it takes it and the card offers it (its OverDrive
feature bit is set).

## Power limit

From the card's minimum up to the limit it started with, in 10 W steps. The minimum is
worked out the way Linux does it: the start-up limit less the card's own power percent
(225 W on a card that starts at 240 W). Less power means less heat and lower clocks under
load.

## Fan curve and zero RPM

Five points, temperature and speed. The kext only takes curves that give at least as much
air as the stock curve at every point and reach 100 % well below the card's target
temperature. Zero RPM can only be turned off (the fan always spins).

While a custom curve is held, the Zero RPM switch sends the change at once with that curve,
as the clock and voltage controls do; otherwise it is part of the curve that Apply curve
sends. The switch is sent only when the whole state the card would get passes the rules, and
when it does not, the section says why next to the switch and nothing is sent.

## GFX maximum and minimum clock

The maximum can be lowered from stock down to 1500 MHz. The minimum can be raised from its
stock value up to the maximum in force: it keeps the clock up at idle, so the card draws
more power and runs warmer.

## GFX voltage (undervolt)

From the card's stock voltage down to its own minimum, in 25 mV steps (on the test RX 6800
XT: 1075 mV stock, 881 mV minimum, so 1050, 1025 ... 900). It only lowers. The value is the
highest voltage the GPU may use; the driver turns it into an offset (the firmware's
VddGfxOffset) that moves the whole voltage curve down by the difference, so the card runs
cooler and draws less at every clock. It needs SMU firmware 58.41.0 or later, as on Linux
(the test card has 58.76.0).

The page suggests a starting point of stock minus 25 mV (1050 mV on the test card). It is
only filled in, never applied by itself, and it is a value to test, not a promise.

What can go wrong: too low a voltage makes the GPU unstable. A game or benchmark freezes,
the driver resets, or the screen goes black and the Mac has to be restarted. Nothing is
damaged: after the restart the card starts at stock. With Remember on, RyzenStatus sends
the same voltage again at launch and after a wake: if a voltage froze the Mac, turn Remember
off or set the voltage back to stock before you test again. Every chip is different.

How to use it: go down 25 mV at a time, run a game or a benchmark for a while after each
step, and once you find the lowest value that is stable, go back up 10 to 20 mV and keep
that.

Community reports (RX 6800 XT): ComputerBase took its card from 1.15 V to 1.025 V stable
and it crashed below that
([computerbase.de](https://www.computerbase.de/2020-11/amd-radeon-rx-6800-xt-oc-uv/));
Igor's Lab calls values up to 1075 mV sensible for an XT and advises staying 10 to 20 mV
above the lowest stable voltage.

## Overclock

A separate section, off until you turn on Allow overclocking. It raises things above stock,
always inside the card's own OverDrive limits and never past them:

- **GFX maximum above stock**, up to the card's own maximum (2800 MHz on the RX 6800 XT,
  the same cap Radeon Software has). The firmware may round it down a few MHz.
- **Power limit above the start-up limit**, up to the start-up limit plus the card's own
  power percent, and never more than +15 % (AMD's own cap on these cards). On the test card
  that is 240 W + 9 % = 261 W (its table offers +9 %).

There are no suggested values here. Inside AMD's limits nothing can burn, but a value can be
unstable: freezes and driver resets mean the clock is too high for the voltage. Everything
goes back to stock when you turn the section off, when RyzenStatus quits, on restart and
after sleep. With Remember on, a raised GFX maximum is sent again at launch and after a
wake, only while Allow overclocking is on; a raised power limit is sent again after a wake,
never at launch. The watchdog holds every raise (95 °C).

More clock rarely gains anything without more power, and the two are held separately (see
above). Raising the clock on a card with a lowered power limit mostly adds heat.

Community reports: a reference RX 6800 XT with +15 % power typically holds about 2400 MHz,
some cards 2500, for about 5 % more performance and about 15 % more power (KitGuru, Igor's
Lab, Guru3D). Igor's Lab advises not to go past about 330 W for the chip. Raise one thing at
a time, 25 MHz at a time, and test each step.

## Profiles

Profiles, at the bottom of the page, keeps the setups you use under names: a quiet desktop, a
gaming one. A profile holds what the page can hold — a power limit, or the whole fan, clock and
voltage state (fan curve, zero RPM, GFX maximum and minimum, voltage) — saved from what the kext
confirmed, exactly what Remember would keep. Names are unique and trimmed; deleting asks first.

Load sends it the way the controls above do: the same limits, the same watchdog, the same refusal
on the page, and with Remember on the loaded setup comes back at launch and after a wake like any
other change. A profile also records the card it was made on (its PCI device id and the stock
limits the kext reported). On another card, or after those limits moved, it is still listed and
still loads, but every value is checked against the card in front of you: one it does not take is
left out and the section says which — a raised GFX maximum, and a power limit above the start-up
one, go out only while Allow overclocking is on.

Profiles live in the app's preferences on this Mac; nothing is written to the card.

## Not offered: memory clock and fast memory timings

The cards offer a higher memory clock (2000 to 2150 MHz on the RX 6800 XT) and a "fast
timings" switch, but on macOS the driver cannot apply either. Both start with a call that
asks the display driver to prepare for a memory overclock, and Apple's part of the driver
does not implement that call, so the driver gives up: a memory clock is never written (and
the request fails), and fast timings are recorded without ever being programmed. The kext
therefore never sends them, and the page has no control for them. Read in the driver of
macOS 26.7.3 (25G342), 2026-11-25.

For reference, community reports on Windows: around 2100 to 2112 MHz many RDNA2 cards start
to show artifacts or get slower instead of faster, and 2150 MHz with fast timings is the
edge (TechPowerUp RX 6000 owners club, Overclockers UK; Guru3D advises backing down 25 MHz
at the first white dots). On the test card memory overclocking was unstable on Windows too.

## Other RX 6000 cards (community reports)

These are for when the control supports them; today only the RX 6800 XT writes.

- **RX 6900 XT**: always power-limited, so overclocking gains little (about 5 to 7 % in
  games); reference cards cap memory at 2150 MHz and fast timings vary from card to card
  (TechPowerUp's RX 6900 XT review, TheFPSReview, KitGuru).
- **RX 6600 XT**: memory often reaches 2250 to 2300 MHz, but pushed too far it retries
  transfers and gets slower without any artifact, so benchmark instead of looking for
  artifacts (TechPowerUp's MSI RX 6600 XT review); fast timings caused artifacts and crashes
  for some users (Steam forum); without a higher power limit an overclock shows no gain.

For every card: change one thing at a time, in 25 mV or 25 MHz steps, and undervolt before
you overclock.
