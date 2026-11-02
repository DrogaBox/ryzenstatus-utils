# Changelog

## [1.75.3] — 2026-11-01 — kexts 3.40.0 (No kext changes)

### Fixed

- **A companion no longer gets lost off screen**: riding on a window you drag past the edge of your displays, a companion now lets go at the edge and drops onto the screen instead of being carried out of sight, where it could neither fall nor go back to the island until the app restarted. One left off screen when a display goes away also comes back onto the nearest screen before heading home.

## [1.75.2] — 2026-11-01 — kexts 3.40.0 (No kext changes)

### Fixed

- **Companion items sit where they belong on every companion**: each drawn companion now knows where its hands, feet, back, nose and mouth are, and every item is placed by them. Shoes, boots, booties and the rosin box go on its own feet instead of over its face; held things sit in its hand at a size that suits it; wings and the jetpack come out of its back, behind the body, instead of covering it; the parrot perches on its shoulder; the clown nose, moustache and pacifier find its real nose and mouth, beak and snout included; the bow tie sits at the collar of the companions whose body is drawn apart from the head; the banana peel waits on the ground by its foot.

## [1.75.1] — 2026-11-01 — kexts 3.40.0 (No kext changes)

### Changed

- **A lighter app while things move on screen**: the scroll and pointer features keep track of RyzenStatus's own windows without asking the window server for the whole window order on every pass of the event loop, so animations, the dashboard and the desktop companion cost far less CPU.
- **A lighter dashboard**: the process list remembers which app each process belongs to and its name instead of looking them up again every second, and the main dashboard tab no longer redraws the whole page for a list it does not show. Disk readings reuse each volume's purgeable space figure for 30 seconds instead of asking macOS to work it out on every sample.
- **A lighter island**: the Dynamic Island works out which sections are on only when a setting changes, not on every pointer move.
- **Up-to-date documentation**: the README, the driver README, the troubleshooting guide and the permissions guide describe the AMD power rework, the processors each family covers, the boot arguments and the Automation access Now Playing needs.

## [1.75.0] — 2026-11-01 — kexts 3.40.0

**The AMD power rework.** This is the biggest AMD release so far: the whole power stack, driver and app, was rebuilt from the ground up.

**Why rebuild it.** RyzenStatus's AMD power layer grew up on a single chip, the Ryzen 5000, and every other Ryzen was talking to it in a borrowed accent: the same SMU commands, the same registers, the same assumptions, whether they fit or not. Adding one more switch on top of that would only have stretched it further. So the layer was taken apart and rebuilt around what each processor actually is: the driver asks the CPU what it supports, speaks its family's own language, and the app builds its controls from those answers instead of from a model name.

**What you get.**

- **A power layer for every Ryzen.** The driver carries the SMU command set of each family, from the first Ryzen and Threadripper chips through Ryzen 9000 and the mobile APUs, and every control appears only where your processor accepts it.
- **A cooler, quieter idle.** Auto EPP now moves whole presets: in Eco it switches boost off, so an idle CPU settles at base clock and voltage, and boost returns the moment there is work. Idle cores also spend more time in CC6.
- **Energy preference that reaches the CPU.** On chips that publish CPPC only through ACPI, such as Ryzen 5000 desktop parts, the driver now writes the energy preference through the firmware's own channel.
- **Presets that know your processor.** Eco, Balance, Performance and Extreme carry the real power and temperature limits for your CPU's class, and you can build, export and import your own profiles, ZenTune backups included.
- **Settings that stay put.** Your preset is applied again after sleep and every time the driver loads, and an optional adaptive power limit keeps temperatures in check under long loads.

Install the kexts from this release together with the app: the new controls need both.

### Added

- **Power presets for your CPU**: Eco, Balance, Performance and Extreme set the PPT/TDC/EDC and temperature limits ZenTune publishes for your processor's class (desktop X3D, E, X 9-series, X and standard parts, desktop and mobile APUs), together with deep idle, boost and energy preference. Each preset card lists the values that apply on your CPU.
- **Auto EPP moves whole presets**: Eco below the idle threshold, Performance above the load threshold, Balance in between, each applied in full for your CPU. Eco switches Core Performance Boost off, so an idle processor drops to base clock, base voltage and a much lower temperature; boost comes back as soon as there is work. The preset in use is highlighted while Auto EPP runs, and switching Auto EPP off puts back your own preset.
- **Custom profiles**: build your own combinations of power limits, temperature limit, PBO scalar, all-core Curve Optimizer, boost ceiling, boost, deep idle and energy preference; apply, edit, export them to a file and import them back, or import a ZenTune backup.
- **Adaptive power limit**: optionally lowers the package power limit 5 W at a time while the CPU is above a target temperature, and raises it back to the active profile's limit once it is cooler and busy.
- **Deep idle (CC6)**: the driver sends idle cores to CC6 itself, through the firmware's C-state address, so they spend more of their idle time there than the firmware alone gives them. Switch it on and off in Settings › AMD Ryzen Power › Advanced energy; it takes effect at once, and the app puts your choice back whenever the driver loads. The driver reads the firmware's C-state address and leaves it as it is; the `amdcstate=1` boot argument forbids deep idle, and `-amdnoidle` leaves the idle loop to macOS.
- **Energy preference through MSRs or ACPI**: the driver probes the CPPC registers themselves, and on processors that publish CPPC only through ACPI, such as Ryzen 5000 desktop chips, it finds each core's `_CPC` and the PCC channel in the PCCT and writes the energy preference there. Hardware Validation shows which path your CPU uses, what the driver found, and can read the CPPC values back from the firmware.
- **SMU support for every family**: power limits, temperature limit, PBO scalar, OC mode and the PM table use the command set of each family: Ryzen 1000/2000 and Threadripper 1000/2000, Ryzen 3000 and Threadripper 3000, Ryzen 5000 and Threadripper 5000, Ryzen 7000/9000 and Threadripper 7000, and the Raven Ridge, Picasso, Renoir, Cezanne, Rembrandt and Phoenix APUs (whose power limit is set as the STAPM, fast and slow limits). A control a CPU does not accept says so instead of being offered.
- **More overclocking controls**: OC core voltage, an all-core Curve Optimizer margin and a boost frequency ceiling, each shown only where the CPU accepts it.
- **Hardware Validation lists what your CPU accepts**: every power control the driver reports for this processor, the deep idle state and the ACPI CPPC discovery report.

### Changed

- **Your preset survives sleep and restarts**: the saved preset or custom profile is applied again after wake and when the driver loads.
- **Boost switch always available**: the Core Performance Boost switch stays usable while Auto EPP is on.
- **PPM and LPM** follow each family's rules, leaving alone the P-state register that Ryzen 3000 and newer reserve for the firmware.
- **Copy AMD Boot-Args** no longer adds `amdcstate`, since deep idle is switched in the app.
- **Now Playing** keeps running when a player refuses or fails a query.

## [1.74.0] — 2026-11-01 — kexts 3.39.0

### Fixed

- **Auto EPP works again**: the driver once more hands the processor to CPPC autonomous mode and writes the energy preference to every core, so an idle CPU drops its clocks and temperature again instead of running at full speed. Auto EPP, the manual energy profile and the power presets reach the processor again, the `-amdcppcactive` boot argument is honoured from boot, and the mode and preference come back after sleep. Above 95 °C the driver still switches to power saving until the CPU cools to 85 °C.
- **No more fake "Max"**: while Auto EPP has not applied anything yet, or the driver cannot apply it, the energy profile no longer shows maximum performance.
- **Preferred cores**: the per-core CPPC ranking now reads each core's highest performance instead of its lowest, which was the same on every core.

## [1.73.2] — 2026-10-31 — kexts 3.38.0 (No kext changes)

### Added

- **GPU fan on the Fans page**: Fans and cooling now shows the speed your graphics card's driver reports for its fan, read-only, with a note that macOS cannot change it. It shows even when no motherboard fans are found.

### Fixed

- **Sensors and processor details are translated**: the Sensors page, its sensor names and the processor details sheet were still in English. They now follow the app's language in all 15 languages.
- **Performance insights are translated**: the memory leak, CPU load, memory pressure and temperature cards now follow the app's language.
- **One decimal mark everywhere**: watts, volts and amps on the Sensors page now use your region's decimal mark, like the temperatures already did.

## [1.73.1] — 2026-10-31 — kexts 3.38.0 (No kext changes)

### Fixed

- **No more false "fan stopped" alerts**: an empty fan header can pick up a stray reading now and then, and one such reading was enough for the alert to treat it as a fan that later stopped. A fan now counts only after turning steadily for 10 seconds, it must read zero for 6 seconds before the alert fires, and a fan whose duty is 0 % (stopped on purpose by a curve or by hand) never counts. Hidden fans stay out of the alert, as before.

## [1.73.0] — 2026-10-31 — kexts 3.38.0 (No kext changes)

This release is a full review of the app around the driver: fan and power writes run in order and report what really happened, the dashboards stop sampling when nobody is looking, and the island, the companions and Now Playing use less energy and work better with Reduce Motion, VoiceOver and a locked screen.

### Added

- **Repair permissions** (Settings > Advanced): after an update, macOS can leave the microphone, system audio, camera, calendars or Automation switched on but no longer working for the new version. This ties the permissions you already gave back to the installed version, without granting anything new. It needs Full Disk Access.
- **GPU fan speed**: the speed your graphics card's driver reports for its fan now shows on the Sensors page and in the panel's GPU details. It cannot be set from macOS; the card's firmware runs it.

### Fixed

- **Manual fans stay manual**: a fan you set by hand no longer falls back to the BIOS curve after a curve upload or a reconnect, and it gets its duty back after one.
- **Fan, power and overclocking writes run in order**: mode switches, manual duties, curves and fan mappings go through one ordered chain off the main thread, and so do PBO, cHTC, overclocking and Curve Optimizer writes. A write is never dropped because a sync was running, and every failure is reported and followed by a fresh read.
- **Curve Optimizer**: Apply all and Reset write only the cores that differ from the last good readback, and a failed read shows "—" instead of zeros.
- **Honest results**: EPP is no longer sent to a driver that ignores it, and the settings say so. P-state writes that are refused or ignored are reverted and reported.
- **Fan curve editor**: points stay between their neighbours, unsaved edits and curves in use ask before they are thrown away, and a curve that was not saved says so.
- **Process inspector**: Force Quit checks that it is still the same process before it acts, and says when the process could not be stopped. The path, the CPU reading and the description no longer show invented values, and the inspector is now translated.
- **Missing values show "—"**: the dashboards no longer invent a CPU percentage, clocks, power or 16 GB of VRAM when a reading is missing.
- **Hardware alerts**: the thermal and power alerts play their sound only when the island shows them, the power alert needs three readings in a row, and the fan stall alert can now fire.
- **Now Playing**: scripts to the music apps run one at a time, lyrics and animated artwork no longer race, and the animated cover pauses when it cannot be seen. A leave reminder that could not show is tried again.
- **The island opens smoothly**, without the small jump at the end.
- **Companions**: saved progress and gold survive damaged or older preferences and are written at once when spent, and a display change that briefly leaves no screen no longer trips up a companion out on the desktop.

### Changed

- **Less work in the background**: the Settings pages, the dashboard and the panel's core grid sample only while they are on screen, and one shared 3 s driver poll serves all of them. Now Playing polling and the companions' background life pause while the screen is locked or asleep. Network rates use 64-bit counters.
- **One process listing**: the process manager and the rankings share one `ps` run, and memory is the resident size everywhere.
- **Reduce Motion and Low Power Mode**: the companions hold still, the animated cover and the title marquee stop, and the popup snaps instead of animating.
- **Accessibility**: labels and values for the core rings, the AMD pickers, the column toggles, the charts and the fan curve points; the Now Playing popup has actions, and Esc closes the detached window.
- **Collapsible sections open from their whole header**, not just the small arrow.
- **Monitor intervals** are 1, 2 and 5 seconds; a shorter saved interval becomes 1 s.
- **Translations**: the new and changed texts are in all 15 languages.

## [1.72.0] — 2026-10-31 — kexts 3.38.0

This release makes the driver safer for every other app on the system and lets the CPU rest while nobody is watching. It also publishes the power of the CPU cores to other apps.

> [!WARNING]
> **This release updates the kexts.** `AMDRyzenCPUPowerManagement.kext` and `SMCAMDProcessor.kext` move from 3.37.0 to **3.38.0**. Replace both together in `EFI/OC/Kexts/` and reboot.

### Added

- **CPU cores power in other apps**: `SMCAMDProcessor.kext` publishes the summed power of the CPU cores as the `PC0C` and `PCPC` SMC keys, the ones iStat Menus, Stats and HWMonitor show as CPU cores power.

### Fixed

- **Instruction counts no longer freeze**: when a core's instructions-retired counter wrapped, its count stopped updating for hours; the driver now carries the wrap.
- **Floating-point registers of other apps**: the driver's once-a-second sample interrupts every CPU, and it did some of its math with floating-point registers while there. xnu does not save an interrupted program's floating-point registers for that, so a busy app could find one of its values changed. All of that math now runs afterwards on the driver's own thread, and a new check on the built kext fails if floating point ever comes back to those paths.
- **Load alert no longer freezes the app**: when the driver reported problems at load, the alert held the app's sampling until it was dismissed. It now opens on its own thread.

### Changed

- **The CPU rests when nothing is watching**: with no app reading the per-core data for 10 seconds, the driver stops interrupting every core. Package temperature, power and fan control keep running, and full sampling is back within half a second when an app asks again. The first reading after a pause is a fresh one, never an average over the pause.
- **Less busy waiting**: SMU and GPU mailbox commands that take longer than a millisecond now wait with the CPU free instead of spinning for up to 25 ms.
- **Timers that coalesce**: the driver's periodic timers allow a small leeway, so macOS can group them with other wakeups.
- **Fan speeds for SMC readers come from a lock-free cache**, so an SMC read never waits behind the fan chip.

## [1.71.0] — 2026-10-31 — kexts 3.37.0

This release adds per-core power and puts the core voltage in the SMC. It also keeps the fans right after sleep, and the driver wakes the CPU far less often while the app is open.

> [!WARNING]
> **This release updates the kexts.** `AMDRyzenCPUPowerManagement.kext` and `SMCAMDProcessor.kext` move from 3.36.1 to **3.37.0**. Replace both together in `EFI/OC/Kexts/` and reboot.

### Added

- **Power of every core**: the driver reads each core's own energy counter, the one Linux turbostat and zenpower read, and the Sensors page lists the watts of every core with their total under the CCD temperatures.
- **Core voltage in other apps**: `SMCAMDProcessor.kext` publishes the core voltage as the `VC0C` SMC key, so iStat Menus, Stats and HWMonitor show it too. It appears only on CPUs whose voltage the driver can read (Zen to Zen 3).

### Fixed

- **Fans after sleep**: firmware can put the Super I/O chip back to its power-on state on wake. On ITE chips that switched the tachometers to a mode that misreads slow fans, and on Nuvoton chips it could lock the fan registers again. The driver now redoes its chip setup after every wake, re-reads the fans and re-applies the fan curves at once, as Linux does.
- **Log noise**: a failed package energy read is logged once per boot instead of on every sample.

### Changed

- **Far fewer CPU wakeups**: the driver mistook the dozen calls of one app refresh for a client asking every few milliseconds, so it sampled every CPU about five times a second while the app was open. It now samples about as often as the app actually refreshes.
- **Less SMU traffic**: the SMU's metrics table is copied to memory only while the AMD Power page is reading it, instead of every second.
- **Fewer fan register writes**: a fan curve whose speed has not changed is written to the chip every 5 seconds instead of twice a second.

## [1.70.1] — 2026-10-31 — kexts 3.36.1

This release makes the fan speeds and the SoC voltage that came with kexts 3.36.0 show up where they should.

> [!WARNING]
> **This release updates the kexts.** `AMDRyzenCPUPowerManagement.kext` and `SMCAMDProcessor.kext` move from 3.36.0 to **3.36.1**. Replace both together in `EFI/OC/Kexts/` and reboot.

### Fixed

- **Fan speeds missing from the SMC**: `SMCAMDProcessor.kext` handed its keys to VirtualSMC in the order it created them, but VirtualSMC finds a key by binary search and needs them sorted. The fan keys (`F0Ac`, `F1Ac`, …) and some temperature keys were listed but could not be read by name, so iStat Menus, Stats, HWMonitor and the Sensors page never saw the fans. The plugin now sorts its keys before registering, as acidanthera's own plugins do.
- **No SoC voltage on Raven, Rome, Matisse and Vermeer**: these chips report the SoC plane with its telemetry-off bit set even though the reading is valid, so the driver discarded it. It now reads the SoC plane on those models regardless, as LibreHardwareMonitor does, and the Sensors page shows "SoC Voltage" next to the core voltage.
- **"6 RPM" fan**: the Sensors page listed the fan count key (`FNum`) as a fan spinning at as many RPM as there are fans. The fan list now shows only the speed of each fan.

## [1.70.0] — 2026-10-31 — kexts 3.36.0

This release updates both kernel extensions, with per-core idle residency on every Zen generation, core and SoC voltages, fan speeds in the SMC and driver settings that survive sleep. It also brings every companion into the same wardrobe and puts the process lists back in order.

> [!WARNING]
> **This release updates the kexts.** `AMDRyzenCPUPowerManagement.kext` and `SMCAMDProcessor.kext` move from 3.35.1 to **3.36.0**. The provider's class layout changed, so both must be replaced together: copy both kexts from the DMG into `EFI/OC/Kexts/`, replacing the old ones, keep Lilu and VirtualSMC up to date, and reboot.

### Added

- **Per-core idle residency on Zen 3 and newer**: the per-core idle dots in the CPU grid (selector 32) were only ever filled on Zen 1 and Zen 2, where the driver owns the idle loop; on every newer CPU they stayed empty. The driver now measures each logical CPU's C0 share from the MPERF counter against the TSC in every sampling window, the way Linux turbostat does, so the figure is live on Vermeer, Cezanne, Raphael, Granite Ridge and every other Zen, at the cost of one register read per CPU per tick.
- **Core and SoC voltages**: the driver reads the VRM's SVI2 telemetry planes, the registers LibreHardwareMonitor and zenpower read, on Zen, Zen+, Zen 2 and Zen 3 (new read-only selector 59), and the Sensors page shows "CPU Core Voltage" and "SoC Voltage" under the CPU. Zen 4 and Zen 5 use SVI3, which is not decoded, so they show no voltage rows.
- **Fans in the SMC**: `SMCAMDProcessor.kext` now publishes the Super I/O fan headers as SMC keys (`FNum`, `F0Ac`, `F1Ac`, …, the same keys SMCSuperIO uses), so iStat Menus, Stats, HWMonitor and the app's own Sensors page see fan speeds without any extra kext. The keys are read-only: fan control stays behind the driver's privilege model. The driver now probes the Super I/O chip itself at load, instead of waiting for the app, and re-reads the tachometers at most once a second whoever asks.
- **Every family 19h part has a profile**: Milan and Chagall (Threadripper 5000), Genoa and Storm Peak (Threadripper 7000) and the Zen 4c parts are now named in the boot log and the app instead of "Unknown", and the app's generation table follows the same ranges (family 19h model 0xA0 is Zen 4c, not Zen 5).
- **Every companion dresses up**: a few companions that used to come as fixed figures are now drawn like the rest. They take any colour, wear every item, join the duo combos that need an item, wave and cheer with their arms, and have desktop routines of their own.

### Fixed

- **Driver settings lost after sleep**: on wake, firmware hands the cores back with its own MSR values, so the deep C-state policy from `amdcstate` and the instructions-retired counter enable written at boot were gone until the next reboot, and the per-core instruction and frequency counters resumed from reset baselines. The driver now re-applies the per-core programming on its first tick after wake and restarts every counter window.
- **No logging inside CPU rendezvous**: the first sampling tick and the P-state table dump logged from inside `mp_rendezvous_no_intrs`, with interrupts off on every CPU; a thread interrupted while holding the log lock would have hung the machine. Failures are now counted inside and logged afterwards from the work loop.
- **Package power spike at start and after wake**: the first energy sample after boot or wake compared the counter against zero, or against a value the SMU reset during sleep, and published one absurd wattage; the first read now only seeds the counter.
- **Driver init order**: the IOKit superclass is initialised before symbol resolution, so a failed init tears down a fully constructed object.
- **One SMU round trip less at boot**: the firmware version read by the boot diagnostic is kept instead of being asked again by the timer.
- **Process lists back in order**: with the Mac in a language that writes decimals with a comma, such as Spanish, the top processes in the menu panel and the Process Manager showed every process at 0% in the order they started. They show real usage again, heaviest first.
- **Whole hands**: the hologram's and the android's hands no longer show a gap where they meet the arm.

### Changed

- **Fan readings every second**: the app's fan list used to get fresh tachometer and duty readings only every fourth poll (about every six seconds); the driver now keeps one shared cache refreshed at most once a second, which is also what the SMC keys serve.
- Removed two SMU read helpers nothing called.

## [1.69.0] — 2026-10-30 — kexts 3.35.1 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.1. Only the application changes.

This release brings two new companions, each with a body, gait and routines of its own.

- **Hologram**: a girl made of light, cast by a small projector at her feet. She is drawn in a single hue, with a visor over her eyes and scanlines across her. She skips along lightly, waves with a hand on her hip, raises both arms to cheer and folds them to sleep. Her projection flickers when she reacts.
- **Android**: a sleek android that floats a hand above the floor on a jet of light and glides instead of walking. The gauge on its chest fills with the real CPU load: one cell at rest, all four flat out, dark while it sleeps. It flashes when the android reacts.
- **Routines of their own**: out on the desktop, the hologram cuts out and lights up again further along, glitches like a bad signal, and sends you a greeting. The android scans your windows, fires its thrusters and recharges cell by cell.
- **Items, colours and growing close**: both wear every item and take every colour. Each gains bond its own way, has its own power for the arcade games, longs for its own treat and has its own colour of energy.
- **Twenty-two new duo combos**: a new "Hologram and Android" family pairs them with each other, with other companions and with items from the wardrobe and the shop.
- **Named in every language**: both companions are named in all fifteen languages of the app.
- **Your date of birth**: the birthday setting now takes the date you were born, year included, and on the day the companion shows how many years you turn. A birthday on the 29th of February is celebrated on the 28th in other years. A birthday set before keeps working.
- **Scarves round the neck**: the scarf now sits round every companion's neck instead of over its mouth and nose.
- **Markings keep their colour**: a kitsune's brow mark, a penguin's cheeks and a swan's chest no longer turn the plain colour of the body when the companion's mood changes.

## [1.68.2] — 2026-10-30 — kexts 3.35.1 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.1. Only the application changes.

This release stops the desktop companions bouncing on top of windows.

- **Standing still on windows**: up on a window, a companion now stands still on its top edge. Before, it lost track of the window under it many times a second and kept hopping in place, looking as if it floated above the edge; it now rides the window when you move it and drops only when the window closes, hides or is covered.

## [1.68.1] — 2026-10-30 — kexts 3.35.1 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.1. Only the application changes.

This release fixes how the desktop companions climb onto windows and explains permissions macOS will not ask for.

- **Leaps that land**: a companion leaping onto a window now clears its edge at any refresh rate, 60 Hz included, and across a stuttered frame; a leap that comes up just short catches the edge and pulls itself up instead of hanging in the air and dropping back.
- **No more bouncing off windows**: falling or jumping down from a window on its own, a companion no longer bounces off the pointer while you work in the window below; the pointer only catches it when you drop or throw it yourself.
- **Feet on the edge**: standing on a window, a companion always stays on its top edge, never a little above it.
- **Clear permissions on systems that block prompts**: when the Mac boots with AMFI turned off, macOS never asks for the camera, the microphone or the calendar on behalf of an app Apple did not sign; Settings now says so instead of offering a Request button that does nothing.
- **Microphone and calendar under the hardened runtime**: builds signed with the hardened runtime now carry the microphone and calendar entitlements, so those prompts can appear there.

## [1.68.0] — 2026-10-30 — kexts 3.35.1 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.1. Only the application changes.

This release brings two new companions, each with a body, gait and routines of its own.

- **Kitsune**: a spirit fox with tall ears, a pale mask and a red mark on its brow. It starts with one tail and grows another every six levels of its bond, up to nine. Its tails sway at rest, stream behind it as it trots, fan out like a crest when it is happy and curl round its paws when it sleeps; its ears flick as it blinks.
- **Penguin**: an emperor penguin in a tuxedo, with golden cheeks and an orange beak. It waddles from foot to foot, swinging one flipper then the other, flaps hard when excited and sleeps standing with its flippers tucked in.
- **Routines of their own**: out on the desktop the kitsune calls blue foxfire, pounces nose first like a fox hunting under snow and plays its leaf trick; the penguin belly-slides along the floor, tries very hard to fly and brings you a pebble.
- **Their own way of growing close**: each gains bond its own way, has its own power for the arcade games, longs for its own food and has its own colour of energy.
- **Sixteen new duo combos**: a new "Kitsune and Penguin" family pairs them with each other, with other companions and with items from the wardrobe and the shop.
- **Named in every language**: both companions are named in all fifteen languages of the app.

## [1.67.0] — 2026-10-30 — kexts 3.35.1 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.1. Only the application changes.

This release fills the companion shop with toys and a little luck.

- **Twelve new toys**: a propeller cap, a shoulder parrot, spring shoes, a skateboard, an umbrella, a yo-yo, a bubble wand, a magnet, lucky dice, a fortune cookie, a snow globe and an instant camera join the shop, drawn, named in every language and priced by rarity.
- **Each with its own thing to do**: out on the desktop and in the island, every toy is used in its own way, and opens duo combos with a move of its own.
- **A little luck**: the dice roll and the cookie reads a fortune, different each time, and now and then they pay out gold, a few times a day at most.
- **Twelve new duo combos**: a new "Toys and luck" family of combos pairs the toys with each other and with the rest of the wardrobe.
- **Dance gear in the shop**: the seven dance and rehearsal items can now turn up in the shop; before, they never did, so they could not be bought.

## [1.66.1] — 2026-10-30 — kexts 3.35.1 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.1. Only the application changes.

This release fixes two desktop companion issues.

- **No more endless bouncing on windows**: a companion landing on a window no longer keeps bouncing when the pointer rests on that window's title bar, and a run of bounces now always comes to rest.
- **Grab it at any time**: the desktop companions can be picked up again while they play together; grabbing one ends the play at once.

## [1.66.0] — 2026-10-29 — kexts 3.35.1 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.1. Only the application changes.

This release brings a round of new tools and many fixes across the app.

- **Pinch to zoom**: a new mouse option zooms with a modifier and the scroll wheel, as a trackpad pinch does.
- **Quit apps window**: quit several apps at once from one window, opened from Quick Toggles or the command bar; the app you were using is preselected.
- **Package commands in your terminal**: Homebrew and MacPorts commands now open in the terminal app you use for scripts, with no Automation permission for Terminal; any password is still typed in the terminal, never in the app.
- **MacPorts on Intel**: the Homebrew installer now refuses Intel Macs, so without Homebrew already installed the package manager uses MacPorts and no longer offers an installer that cannot run. An existing Homebrew installation can still be chosen.
- **Command-line backups**: settings backups can be exported and restored from the command line.
- **Event countdown**: choose how long before an event the island starts counting down.
- **App switcher**: a shortcut that shows every window of all apps, up to ten columns, and a Liquid Glass look on macOS 26.
- **Clipboard history**: each entry shows the icon of the app it was copied from.
- **Claude account**: the AI agents view can follow a chosen Claude account.
- **Stage Manager**: the window layout can keep room for the Stage Manager strip.
- **Screen sharing audio**: the mixer protects the call audio while you share your screen in Discord or Teams.
- **Auto Quit**: menu bar apps that also live in the Dock can be allowed to quit.
- **Scroll to adjust**: the volume and brightness levels move with the scroll wheel, and keys move them smoothly.
- **Island**: an option to open the island on hover over full-screen apps, and it stays hidden over full-screen games; it also stays steady while displays are rearranged.
- **Fixes**: Bluetooth device tracking no longer affects other features, the level bars keep their width, the Monitor settings page no longer freezes, and many smaller fixes in screenshots, the app switcher, the mixer, the command bar, the clipboard and the mouse tools.

## [1.65.0] — 2026-10-29 — kexts 3.35.1 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.1. Only the application changes.

This release lets the companion feel what your Mac is doing, keep special days and play with you.

- **Reacts to your Mac**: the companion now shows when the CPU boosts under a sustained load, runs hot or sits cold, when the battery runs low and when it is plugged in again, and when the network drops and comes back, each with a moment of its own on the desktop and in the island. They follow the existing automatic-reaction categories.
- **Special days**: the companion celebrates a few days of the year, and your birthday if you set it with the new "Celebrate my birthday" option in its settings.
- **A Play menu**: right-click the desktop companion for Rock, Paper, Scissors (a few wins a day pay out gold), a laser pointer it chases around the screen, a fishing trip by the Dock and a game of hide and seek.
- **Cravings and feeding**: now and then it shows what it longs for, and minds being ignored; drop food on it from Finder or a browser and it eats it. Only file names are read, never their contents.
- **More to discover with the pointer**: a few new ways to play with the companion using the pointer, left for you to find.
- **Dancers dance alone**: the dancer companions now perform solo moves of their own, with the rehearsal habits real dancers know.
- **New sounds**: a few more synthesized sounds go with these moments.

## [1.64.0] — 2026-10-29 — kexts 3.35.1 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.1. Only the application changes.

This release adds more to the desktop's surprises.

- **More rare surprises**: many more unusual things can now happen around the companion while it is out on the desktop — some at any hour, some only at certain times of day. It meets each one in its own way. As before, what they are is for you to discover.
- **Room to move**: those that need the floor wait until the companion is off the windows, and what passes by now always finishes its way across the screen.
- **New sounds**: a few more synthesized sounds go with these moments.

## [1.63.0] — 2026-10-29 — kexts 3.35.1 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.1. Only the application changes.

This release makes the desktop a little less predictable.

- **Rare surprises on the desktop**: once in a long while, while the companion is out on the desktop, something unusual may happen around it, and it reacts in its own way. Some depend on the time of day. What they are is for you to discover.
- **The friend notices too**: when both companions are out, the other one reacts to what it sees.
- **New sounds**: a few new synthesized sounds go with these moments.

## [1.62.0] — 2026-10-29 — kexts 3.35.1 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.1. Only the application changes.

This release gives every wearable something of its own to do when the companion is alone.

- **Every item has its own use**: now and then the companion does its own thing with what it wears — the boomerang goes out and comes back, the lute plays, the sword is drawn and swung, the bow fires arrows, the dumbbells get lifted, the rubber duck squeaks, the banana peel slips it up, the ice cream gives it brain freeze, the sleep mask sends it off to doze, and so on for the whole wardrobe. No two items are used alike.
- **The magic mushroom makes it grow**: eaten, the mushroom makes the companion grow half again its size for a while, flickering big and small as in the old games, and it shrinks back when the effect wears off.
- **On the desktop and in the island**: out on the desktop it really throws, swings and jumps; resting in the closed island, it shows the same use with its reactions, bursts and markers.
- **Try it from Settings**: a new "Use item" button under the companion preview plays what it does with the item it wears, and has it do it on the desktop too when it is out.

## [1.61.0] — 2026-10-29 — kexts 3.35.1 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.1. Only the application changes.

This release gives every duo combo its own choreography: what each companion wears now opens the combo with a move of its own, and every combo ends with a finale of the two together.

- **A move for everything worn**: each wearable now has its own signature move, prop and burst — the sword charges, the shield braces, the boots leap high, the banana peel slips, the lute struts, the disco ball spins, and so on for the whole wardrobe.
- **Combos staged move by move**: a combo opens with each companion's signature move, plays its own exchange and closes with a finale of the two together — swapping places mid-air, leaping over each other, bumping heads, chasing, bowing or spinning side by side. No two combos made of different things play out alike, and the same pair always ends the same way.
- **On the desktop and in the island**: out on the desktop the companions really jump, charge, sneak and spin; in the closed island, where they cannot leave their places, each move shows as its own reaction.
- **Combo hints in Settings**: under the companion preview, a line tells what the item it wears pairs with, names the combos already found, counts the rest and suggests one to try on the friend.

## [1.60.0] — 2026-10-29 — kexts 3.35.1 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.1. Only the application changes.

This release lets the desktop companion live among your windows: it climbs onto them, walks their top edge, rides along when you drag one, hides behind them to peek out and reacts to the app you are using.

- **Companions climb onto windows**: out on the desktop, the companion leaps onto the top edge of other apps' windows, walks along them and jumps across or back down. Dropped or thrown over a window, it lands on top of it.
- **Rides on dragged windows**: drag the window it stands on and it rides along, leaning into the motion; drag a window up close beside it and it jumps on. When the window closes, is minimized, moves behind another window or leaves it no room, it falls.
- **Hide and peek**: standing on a window, it now and then ducks down behind it and peeks over the edge, popping back out when the pointer comes close.
- **Reacts to the app in front**: browsers, editors and terminals, music and video players, chat apps, design tools, Finder and games each get their own reaction, and now and then it goes over and climbs onto the app's window to read along, watch or groove.
- **New setting**: "Climb onto windows" in the companion's desktop settings, on by default. Only where windows are and which app owns them is read, never their titles or contents, so no extra permission is needed.
- **Shake to dizzy**: shaking the companion back and forth while carrying it leaves it dizzy for a moment after you let go.
- **Four dance companions**: a swan, a ballerina, a danseur and a contemporary dancer join the companions, with dance wardrobe items.

## [1.59.0] — 2026-10-24 — kexts 3.35.1 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.1. Only the application changes.

This release introduces multi-metric trend carousels in the island capsule, island-only pure notch mode, feathered glass backdrops, independent per-companion progression and species affinities, a streamlined companion settings layout, and a compact standalone wardrobe viewer.

### Fixed

- **Companion settings recursion crash**: resolved an issue where evaluating companion level could trigger recursive look resolution, eliminating potential stack exhaustion when navigating companion settings.
- **Desktop companion hit-testing non-interference**: tightened the hit-testing geometry of the desktop companion window to strictly encompass the figure silhouette, ensuring background windows and controls receive clicks without interference.

### Added

- **Multi-metric trend carousel in the capsule**: the Dynamic Island capsule center can now rotate smoothly between selected metrics (CPU, RAM, Fan, and Temperature) at customizable intervals with trend direction indicators and carousel transitions.
- **Island-only mode (pure notch)**: added the option to run exclusively with the Dynamic Island, cleanly hiding the menu bar status icon while preserving complete popover navigation and controls through the notch.
- **Feathered blur backdrop**: integrated a gaussian feathered glass backdrop behind the notch island that blends smoothly with the display bezel curvature.
- **Independent per-companion progression & species affinities**:
  - Each companion species now tracks its own level, bond milestones, and experience independently.
  - Companions have distinct species affinities for gaining experience through care, companionship, and daily activity.
  - Interactions with a desktop friend credit the friend's own profile, while interactions with the leader companion credit the leader.
  - The Story tab now provides dedicated progress bars and relationship milestones for both the active companion and the friend.
- **Reorganized companion settings**:
  - Friend selection and color customization now live directly in the Appearance section.
  - Friend accessory customization is now located in the Wardrobe section and respects the friend's unlocked level.
  - The Behavior section is now focused purely on roam, excursion, dress-up, and pair interaction toggles.
- **Compact standalone wardrobe viewer**:
  - Replaced the large capsule tiles in the wardrobe with high-density 44×44pt vector item tiles.
  - Shows 10+ items per row with unlock badges, level requirements, and instant stage previews, significantly reducing vertical scrolling.

## [1.58.0] — 2026-10-24 — kexts 3.35.1 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.1. Only the application changes.

This release introduces three new desktop companions, an anatomical overhaul of the dog companion, independent companion transformations, fixes for music hover interactions, and twenty-five new Tamagotchi-inspired duo synergies and dynamic item interactions.

### Fixed

- **Music hover no longer eclipses companions**: hovering over the island while music plays no longer expands over the companion dancer or collapses its interactive area, preserving smooth drag-and-drop targeting to the desktop.
- **Dog companion anatomy redesign**: completely remodeled the dog companion with recognizable floppy ears that arch over the crown and droop over the cheeks, an expressive snout, a `:3` smile, front paws, and a wagging tail.

### Added

- **Three new companions**:
  - **Carpincho (Capybara)**: The zen master of the island, balancing a citrus on its crown and relaxing with onsen bubbles and warm steam.
  - **Dragón (Pocket Dragon)**: A tiny dragon with golden horns, bat wings, and playful flame breath.
  - **Ranita (Bouncy Frog)**: A high-leaping frog with swift reflexes, throat-puff croaks, and rain-dancing moves.
- **Independent companion transformations**: both the leader and friend can now independently choose their transformation form (including "none" / "off", specific unlocked forms, or a rerollable random dice mode).
- **Twenty-five new synergies & duo interactions (207 → 232)**:
  - *Species Synergies*: Onsen Nap, Orange Share, Boba Harmony, Hot Spring Duo, Perch of Peace, Tiny Flame, Midnight Ramen, Dragon Hoard, Flame & Jelly, Spark Fetch, Lily Hop, Quick Reflex, Tea on a Leaf, Rain Dance, and Pond Pals.
  - *Dynamic Wardrobe Combos*: LAN Party (Game Controller + Headphones), Sweet Afternoon (Boba Tea + Ice Cream Cone), Orbital Team (Laser Visor + Jetpack), Mystery Solved (Detective Lens + Top Hat), Flambé Feast (Chef Hat + Fireball), Royal Audience (Crown + King Scepter), Alchemy Duet (Witch Hat + Magic Tome), Disco Grooves (Disco Ball + Sunglasses), Buried Secret (Eye Patch + Golden Key), and Zen Garden (Flower + Onigiri).
- **Synthesized sound effects for new markers**: procedural audio cues for markers including `ZEN`, `CHILL`, `BOBA`, `WARM`, `PEACE`, `ROAR`, `TOAST`, `SHINY`, `POOF`, `SPARK`, `CROAK`, `CATCH`, `SLURP`, `RAIN`, `SPLASH`, `GG`, `SWEET`, `ORBIT`, `AHA`, `CHEF`, `HAIL`, `HEX`, `FUNK`, and `AHOY`.

## [1.57.0] — 2026-10-24 — kexts 3.35.1 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.1. Only the application changes.

The island gains proactive hardware alerts and sound cues, and the companions learn to play with their own wardrobe. Along the way, the island's hand-set length and the companion's picked accessory both hold again.

### Fixed

- **No companion left in the capsule while it plays on the desktop**: the resting capsule now asks the desktop companions themselves whether they are out, so a drag to the desktop can never leave one of them still drawn up in the island — before, a companion out on the desktop could appear twice at once.
- **The island's hand-set length holds**: the resting capsule no longer grows past the camera housing when the companions rest on it — a width narrowed by hand stays narrowed — and grabbing a companion no longer swallows clicks meant for the capsule beside it. Settings now also says that the size's width shapes the open island, while the resting capsule keeps its own fit.
- **What you pick is what it wears**: a season's costume (the October witch hat, the December Santa hat) no longer overrides the accessory chosen for the companion. The costume shows when nothing is picked, and an explicit pick always wins.

### Added

- **Hardware alerts in the island**: thermal spikes, PPT saturation and a stalled fan under load now surface through the island as red notices with their own switch, so a Ryzen system's bad moments are seen without opening a monitor.
- **Sound cues**: short audio cues for island actions and hardware alerts, with their own switch in the island settings.
- **Dress-up play**: out on the desktop, now and then each companion digs into everything it owns — level unlocks and shop curiosities alike — and wears whatever it feels like for a minute, then goes back to what you picked. A new pick from Settings shows at once, and the play has its own switch.
- **Four new companions**: Fénix, a flame bird with a two-lick crest, swept wings and a hooked beak; Ajolote, a pink salamander whose six gill fronds fan out of its wide flat head; Perrito, a floppy-eared dog with a wagging tail; and Ratita, a mouse with big round ears and a long thin tail. All four join everything at once — the desk, the island plays, dress-up, the shop's wardrobe and all the combos.
- **Color for each companion by hand**: a color picker beside the swatches paints any companion any color at all, and the friend can take its own palette or its own hand-picked color instead of its companion's.
- **The glutton gets its mouth**: Devourer's wide open mouth is drawn at last, where it was only an oval with eyes.
- **Seventeen new combos (190 → 207)**: Bubble Bath, The Prank Duo, Rude Awakening, Balloon Ride, The Chest Game, Hot & Cold, House Party and First Contact; Ash to Ember, Bubble Lounge, Steam & Spark and Fire Drill for the new figures; and Fetch, Squeak Peek, Cat & Dog, Cat and Mouse and Best Friends for the pets — dog, cat and mouse finally have their classic rows.

## [1.56.0] — 2026-10-23 — kexts 3.35.1

A security and reliability pass across the AMD kernel extensions and release pipeline: fan curves now stay active when read-only tools or secondary clients close their connection, Threadripper CPUs with more than 64 threads are clamped safely in every selector, ITE Super I/O probing stays strictly read-only for unprivileged callers, and release DMGs publish their SHA-256 checksums.

> [!WARNING]
> **This release updates the kexts.** `AMDRyzenCPUPowerManagement.kext` and `SMCAMDProcessor.kext` move from 3.35.0 to **3.35.1**. Copy both kexts from the DMG into `EFI/OC/Kexts/`, replacing the old ones, keep Lilu and VirtualSMC up to date, and reboot so the new kernel hardening takes effect.

### Fixed

- **Companion independent drag-to-desktop**: fixed an issue where dragging one mascot (left companion or right friend) down to the desktop prevented the other mascot from being dragged down due to mismatched capsule coordinate hit-testing and capsule track width shrinkage. Both companions can now be independently dragged down or returned in any order.
- **Removed confusing placards & text signs**: eliminated nonsensical floating arcade text signs (such as `"THX"` / `"THANKS"` popping up when throwing snowballs, or `"SPEED"`, `"SNIF"`, `"BYE"`, `"DOOR"`, `"GATE"`). Floating arcade markers now strictly show standard game rewards (`+100`, `+200`, `+500`, `1UP`, `♥ +1`) or clean visual effects.
- **Removed upward arrow during peek**: eliminated the disconnected network download arrow that inappropriately flashed over the mascot during peek or mimic reactions.
- **Fan curves no longer reset when a read-only client disconnects**: running `RyzenStatus --selftest`, `RyzenStatus --sensors` or any unprivileged monitor alongside the app previously triggered the dead-man fan reset when that second connection closed, dropping active fan curves back to motherboard automatic mode. Only a client connection that actually modified fan control now resets fan state on close.
- **CPUs with more than 64 cores or threads**: selectors 2 (effective frequencies) and 21 (CPPC preferred-core scores) now clamp physical and logical core counts to `CPUInfo::MaxCpus` (`64`), preventing out-of-bounds reads on 64-core / 128-thread Threadripper systems.
- **ITE Super I/O probing without root**: probing an `IT86XXE` chip on selector 90 no longer writes to the 16-bit tachometer configuration register (`0x0c`) when the caller is unprivileged, matching the Nuvoton privilege gate.
- **Spurious `DENIED select 90` kernel log messages**: unprivileged `fanInit` calls no longer emit a false-positive `DENIED` warning in the kernel log while checking whether optional Super I/O unlock writes are permitted.

### Added

- **Dynamic roaming secret doors & treasure chests**: when companions are out on the desktop, secret doors and rare treasure chests now appear dynamically across random coordinates on the screen's floor instead of being locked to the top-center notch position. Both companions dynamically turn, run, and hop toward the target to open it, bursting sparkling gold coins and celebratory reactions.
- **Sword clash & duel sound effects**: added synthesized sound effects for swordplay in mascot duels, including blade swings (`whoosh`), metal clashes (`clash`), strike impacts (`boom`), and victory chimes.

### Changed

- **Pinned kext packaging and release checksums**: `Tools/make-dmg.sh` now always packages the pinned `ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip` archive unless `ALLOW_LOCAL_KEXTS=1` is set explicitly, and GitHub releases include the `.dmg` SHA-256 checksum in the release notes.
- **Documentation and selector parity**: `SECURITY.md` and `README.md` accurately document the ad-hoc signing policy, the security trade-off of `-amdpnopchk`, the read-only NVRAM C-state helper, and support for macOS 14 Sonoma through macOS 26 Tahoe; `AMDKextSelector` is now verified against every `case` in `AMDRyzenCPUPMUserClient.cpp` during the test suite.

## [1.55.2] — 2026-10-21 — kexts 3.35.0 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.0. Only the application's validation version pin changes.

### Changed

- **Companion settings in sections**: the page groups its cards under Appearance, Accessories, Your story and Behavior instead of one long column, and the list of moments to try folds away.
- **The shop is easy to reach**: it now sits at the top of the Accessories section in the companion settings, with your gold, the four items on show and the new-stock button. Right-clicking the companion on the desktop has a Shop item that opens it there. Before, it could only be reached from the companion's card in the island, which shows only on displays with a camera notch.
- **Shop items stay a surprise**: the accessories list shows only what you already own; the rest appear in the shop.

### Fixed

- **Constant lag in 1.55.1**: the companion paid its daily gold every few seconds instead of once a day, and each payment rewrote the preferences and made the island rebuild itself. The daily gold is paid once, and the gold balance is saved in batches with the rest of its state. The companion settings page no longer redraws every preview each time the hourglass moves.

## [1.55.1] — 2026-10-21 — kexts 3.35.0 (No kext changes)

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.0. Only the application's validation version pin changes.

### Added

- **Companion shop**: the island companion's accessories are now bought with gold in a shop, with a random stock of four, rarities from common to legendary, and a reroll. Levels stay for the transformations; what you already unlocked is kept.
- **24 new curiosities** with funny, sad and wild interactions, and 55 new combos for them and for the new companions.
- **Two new companions**: one swallows what is thrown at it and spits it back as stars or powers, the other copies the look of its partner.
- **Sound for the interactions**: synthesized, switchable off, with a volume control and stereo placement that follows where the interaction happens on screen.
- **Eyes and pointer-following** for the sprite companions, which now turn toward the cursor.

### Fixed

- Lag on the companion settings page and while dragging a companion: saves are batched, the play layer no longer animates while idle, and the Automation permission query is cached.

## [1.55.0] — 2026-10-21 — kexts 3.35.0 (No kext changes)

A large pass over the little things: the island opens from the keyboard and shows what happened while it was hidden, updates now say what changed for each feature you use, the screenshot editor gains a spotlight and a canvas that grows, and the switcher, mixer, dock preview and auto-quit stop getting in the way. The companions also grow a Wonder Boy side: hearts and an hourglass to look after, gold, secret doors in the island, thirty-two more things to wear, a catalog of 135 combos for the pair and an arcade card to play them from.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.0. Only the application's validation version pin changes.

### Added

- **What changed, feature by feature**: after an update the digest now reads our `CHANGELOG.md` and groups the notes under the features they belong to, so a change to the mixer, the island or the uninstaller is listed where you would look for it instead of in one long list. The preview toggle in Settings › Updates shows it before a release too.
- **Update exceptions**: Settings › Updates lists apps that should never be offered an update again, and the checks skip them from then on.
- **Clipboard history for a number of days**: history items can now expire on their own, so the list keeps the last few days instead of the last few hundred copies.
- **Markdown task lists in the scratchpad**: the preview draws real checkboxes, clicking one ticks the line in the text, and list shortcuts keep the boxes on their own lines.
- **An uninstaller that explains itself**: iPhone and iPad apps dragged onto it are accepted, and an app that cannot be removed now says why — part of macOS, sharing files with the system, inside another app, RyzenStatus itself, a link to an app kept elsewhere, or not an app at all. The picker says up front that Apple's own apps are not listed.
- **A spotlight tool and a growing canvas**: the screenshot editor dims everything around a chosen region, expands the canvas for pasted or drawn content, and keeps pasted images editable after they land.
- **Copy text from the quick preview**: the capture preview reads the text in the shot, so a screenshot of a message or a code snippet can be copied without opening the editor.
- **Screenshot tools in your order**: the rail remembers the order you give the tools and the number keys follow it, with nine tools reachable from the keyboard.
- **A switcher column limit**: the grid stops at the number of columns you pick, or fits the display when left automatic.
- **The island from the keyboard**: a shortcut opens and closes it, a hidden island still shows activities and notices, and the shelf closes it when an item is dragged out.
- **The player's icon when a track has no cover**: the island shows the app that is playing instead of an empty square, without borrowing the cover-art tint.
- **Limits for separate Codex accounts**: each account gets its own reading, and the usage page no longer mixes them.
- **Silence after headphones disconnect**: the mixer can drop the output level instead of jumping to full volume.
- **135 combos for the pair**: what the two wear or are brings a play of its own — tributes, duels, spells, feasts, music, heists, hardware jokes, twins in the same hat, figure-to-figure combos and eight mini-quests. They play in the closed island and out on the desktop alike, and Settings counts how many have been found.
- **Thirty-two more things to wear**, one unlocked each level from nineteen to fifty: arms, helms, boots, wings, a jetpack, snacks and gadgets, all drawn as vectors.
- **Hearts, an hourglass and gold**: three to ten heart containers, a vitality hourglass that runs down very slowly, and gold found by living with it. Under thirty percent, snacks grow in the track and score arcade points.
- **Secret doors**: a shop, an inn, a tavern, a wizard's hut and a boss's lair open behind the camera now and then, or from the Pocket Card.
- **The Pocket Card**: a click on the companion in the open island shows its hearts, hourglass, gold, class and combo, with buttons to throw fruit, open a door, run the combo and change what the two wear.
- **Abilities by figure**: a ceiling walk, fireball breath, a glide, a dive and a springboard, acted out in the island and on the desktop.
- **Both companions in Settings**: the stage shows the pair, with a button to try the combo.

### Changed

- **Auto-quit reads the screen**: an app that still shows a window keeps running, and a window taken to the Dock is no longer counted as closed.
- **Dock preview hit-tests the Dock itself**, so a hung app cannot freeze the main thread while a preview is opened.
- **Quit protection forwards the confirmed quit** to apps on remote screens instead of leaving them open.
- **Dock icons of apps running as several processes** now resolve to the right icon instead of the first process's.
- **Window layout snaps windows moved with the modifier drag**, not only those resized at an edge.
- **The mixer follows perceived loudness**, pauses an AirPlay stream with playback, and mutes an output when its level reaches zero.
- **A mirroring display gets its own brightness controls** and its own overlay.
- **The island's height matches the physical notch by default**, and a custom width applies to every page.
- **The switcher pauses window capture while the Screen is locked**, reads the cycle flag per window, and unhides only apps that were hidden.
- **Secure input is explained where it matters**: the switcher says why ⌘Tab opens the macOS switcher, and the settings name the app that holds it.
- **Permissions stay suspended**: a tap suspended by Cleaning Mode or by a missing permission no longer restarts itself.

### Fixed

- **False update offers**: versions with numeric suffixes and builds from different channels no longer look newer than the installed one.
- **Large calculator answers** keep every digit instead of being rounded in the command bar.
- **Command bar rows** copy a script's output when the row was reached by part of its name, and find Xcode's Instruments and Device Hub.
- **Clipboard filtering catches credential names** that continue past the first word, and transient pastes cancel after a newer copy.
- **Screenshots in short windows** keep every tool reachable, and the capture dim covers the whole display.
- **GIF exports stream with bounded memory**, and a window recording keeps only the app's own sound.
- **Smooth scrolling glides on its own window**, so page scrolling in another app no longer stutters.
- **The mouse wheel is left alone** over a Launchpad or Dock entry, keypad digits reach number shortcuts, and a Java runtime is matched by its path as well as its identifier.
- **The monitor samples power immediately** when the power source changes.
- **Displays ignore DDC replies meant for another control**, and windows stay in their Mission Control desktop.
- **The port manager shows port and PID numbers whole**, and the feature hub keeps its scroll position when a feature is opened.
- **Island details**: the Japanese stopwatch name stays whole on macOS 15, the focus ring no longer shows when it opens, music takes priority over an idle companion, and a timed capture can dismiss under an island.
- A capsule with a reading in its middle no longer offsets where the companions are caught or return to.
- A hide that came due during a play, or a pat in the island, no longer cuts it short; a pat now counts, rests the hide timer and makes the other companion hop.
- Two companions wearing the same thing now play together, and the pair out on the desktop use what they wear.
- A friend pulled out first is no longer left alone when the companion comes home.
- A floating island opened below the menu bar now perches both companions, side by side.
- Things thrown across the island leave and land at the figures' own height, in a high arc, and stay out of sight over the camera.

## [1.54.0] — 2026-10-16 — kexts 3.35.0 (No kext changes)

The companion and its friend play together in the island too, eight new items join the wardrobe, and the friend can wear the item you pick for it.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.0. Only the application's validation version pin changes.

### Added

- **They play in the island**: resting together, now and then the two play across the room between them: they wave to each other, toss hearts, stars and notes, rally a spark until one misses it, play a copying game the friend loses on its last move, dance to the music, doze off at night and play peekaboo. In a floating island they play inside the capsule; beside the camera, what they toss flies behind it. Under Reduce Motion they still act it out, but nothing flies. They follow the They play together switch.
- **What they wear plays too**: each item brings a play of its own when one of them wears it: a magic trick from the top hat, a bow to the crown, a shared beat from the headphones, a snowball fight from the beanie, a game of catch from the cap, a quickdraw from the cowboy hat, a blessing from the halo, a prank from the little horns, a treat from the chef's hat, treasure from the eye patch, a spell from the witch hat, a present from the Santa hat and a party from the party hat, among others.
- **Eight new items**: a cap, a bow tie, a monocle, a cowboy hat, a halo, little horns, a chef's hat and an eye patch, one at each level from eleven to eighteen.
- **Pick what the friend wears**: Settings › Companion › What the friend wears picks any unlocked item for it, or leaves it to the friend as before. A costume or the Gaming Mode headband still dresses both alike.

### Fixed

- **The friend left a floating island that had something in its middle**: with the song, the visualizer or another reading in the capsule's middle, the friend was not shown. The capsule now keeps room for both, the companion at its end and the friend at the other.

## [1.53.1] — 2026-10-16 — kexts 3.35.0 (No kext changes)

Fans keep their reading: a fan turning at a steady speed no longer shows "— RPM" now and then.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.0. Only the application's validation version pin changes.

### Fixed

- **Fans showing "— RPM" at random**: a fan turning at a steady speed could be taken for an unconnected header and lose its reading. The kext re-reads the fan chip on one request in four and repeats its last value in between, and the app counted those repeats as a frozen sensor. A reading is now treated as frozen only when it has not changed for 90 seconds.

## [1.53.0] — 2026-10-16 — kexts 3.35.0 (No kext changes)

The companion and its friend live together on the desktop: they duel with blades of light, throw energy at each other, dance to the music, play tag and nap side by side. The friend wears an item of its own, comes out from a floating island too and rests at the capsule's other end. Cristóbal and the White Rabbit are kept for the companion named DrogaBox.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.0. Only the application's validation version pin changes.

### Added

- **They play together**: now and then the two out on the desktop start something together, each time with its own twist:
  - a duel with blades of light, two to four clashes in a shower of sparks, won by either or ended with a bow;
  - a blast of gathered energy that the other holds off with its own until both burst, takes and is thrown back by, jumps over or knocks back;
  - powering up in bursts of aura, which the other matches or fizzles out at;
  - a dance-off with notes flying, then both together;
  - high fives, tag, leapfrog, hugs, a copying game the friend loses on its last move, a star handed over as a gift, and naps side by side.

  What they just did is less likely next, music calls for dancing and the small hours for a nap. The energy and the blades take the colour of the companion's transformation, crackle with lightning from the second golden form on, and grow with the bond. A press on either, or either going home, ends a play at once. A new switch, **They play together**, turns it off. Reduce Motion and Low Power Mode keep them still.
- **A life between plays**: patting one makes the other come over, hop up for a pat of its own or cheer. A hard fall brings the other running with a heart. One dozing off alone is joined by the other after a yawn. Both bob along while music plays, as the companion does in the island.
- **The friend's own take**: in the island and on the desktop, the friend answers what the companion reacts to a moment later with a reaction of its own, rather than the same one at the same time.
- **The friend's own item**: the friend wears its own accessory among those the level unlocks, worn elsewhere on it than the companion's and always the same for its figure. Seasonal costumes and the Gaming Mode headband the two wear alike.
- **Both companions in the capsule**: with a friend picked, a floating island keeps the companion at the end on its side and the friend at the other, as the wings do beside a camera. With nothing else to show, the floating style still draws them below the menu bar, and the friend stays there while the companion is out. With no friend picked, the companion rests in the middle as before.

### Changed

- **The comic's characters by name**: Cristóbal and the White Rabbit are offered as a style or a friend only to the companion named DrogaBox. A companion with another name that wore one goes back to the minimal style.

### Fixed

- **The friend never came out from a floating island**: it came out only after the companion walked out on its own, and only where it had a place to rest in the island, which a capsule never gave it. It now comes out with the companion whenever the island keeps no place for it, pulled out or not, and joins a companion already out when it is picked.

## [1.52.1] — 2026-10-16 — kexts 3.35.0 (No kext changes)

A drawn companion is seen again when it comes out onto the desktop.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.0. Only the application's validation version pin changes.

### Fixed

- **A drawn companion vanished on the desktop**: the cat, the robot and the other drawn companions are as big on the desktop as the window was first made for, so the window never got a size and they left the island for an empty window, taking the friend along with them. The window now takes its size the first time, whatever the companion.

## [1.52.0] — 2026-10-16 — kexts 3.35.0 (No kext changes)

The White Rabbit's sign speaks your language: in every language but Spanish, the words on its cardboard sign are written in the language the app uses.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.0. Only the application's validation version pin changes.

### Changed

- **The White Rabbit's sign in your language**: its sign said HOLA, VOY, QUÉ TAL, ¡SÍ!, PENSANDO, EN CAMINO and ¡LISTO! REVISÁ whatever the app's language. In the fourteen other languages its frames now carry a blank sign with the words written onto it, in heavy rounded capitals sized to the sign, following it frame by frame. In Spanish it keeps the comic's own lettering.

## [1.51.0] — 2026-10-16 — kexts 3.35.0 (No kext changes)

Two companions can share the island: the friend you pick rests in the wing on the camera's other side, and each one comes out onto the desktop and goes back in on its own.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.0. Only the application's validation version pin changes.

### Changed

- **A friend in the island**: the friend picked under A friend keeps it company (Companion settings) now lives in the closed island too, resting in the wing on the camera's other side. Drag either one down to bring it out onto the desktop; drop it back on the island, double-click it or pick Back to the Island and it flies back to its own wing. On a walk of its own, your companion still takes its friend along and brings it back. The friend steps out of sight while your companion walks over its wing. A floating capsule has room for one companion only, so there the friend rests out of view.
- **The White Rabbit's size**: on the desktop it stands half Cristóbal's height, as in the comic.
- **The White Rabbit's signs**: "¡LISTO! REVISÁ" now shows only when something finishes well, such as an agent's task or a download. Thinking, it holds up "PENSANDO", and looking about or yawning it shows "HOLA". Cristóbal reads his finished page with a thumbs-up for the same moments.

## [1.50.0] — 2026-10-16 — kexts 3.35.0 (No kext changes)

Cristóbal reads at a glance in the island: drawn small, he shows his top half, face, glasses and mug, instead of a tiny whole figure.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.0. Only the application's validation version pin changes.

### Changed

- **Cristóbal up close in the island**: in the closed island, the menu bar and notices, where a companion is only a few points tall, Cristóbal is drawn from the waist up and fades out at the bottom, so his face, his waves and his coffee show at twice the size. On the desktop and in the Settings previews he stands whole. The White Rabbit stays whole everywhere, so its sign always reads.

## [1.49.0] — 2026-10-16 — kexts 3.35.0 (No kext changes)

The companion no longer has to go out alone: pick a friend and two companions roam the desktop together, Cristóbal and the White Rabbit among them.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.0. Only the application's validation version pin changes.

### Added

- **Comes out with a friend**: with Come out onto the desktop on, pick a second companion under Comes out with a friend (Companion settings). It hops out of the island just after yours, on the other side, and wanders on its own; when the two are far apart one walks over to the other, and when they meet they wave. It shares your companion's level, so it wears the same accessory and transformation, and its pats count toward the same bond. Pat it, carry it and throw it like the first. Double-click it or pick Back to the Island from its menu and it goes in by itself; it follows yours in when yours goes home. Reactions to what the Mac does play on both.

## [1.48.0] — 2026-10-16 — kexts 3.35.0 (No kext changes)

The companion can leave the island: drag it down out of the closed island and it walks around your desktop, where you can pat it, carry it, throw it and watch it bounce, and send it home with a double click. Two new companions join the styles: Cristóbal Sincronía and the White Rabbit, from the author's own comic.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.0. Only the application's validation version pin changes.

### Added

- **Companion on the desktop**: with Come out onto the desktop on (Companion settings), drag the companion down out of the closed island and it grows to desktop size and hangs from the pointer. Let go, it falls to the bottom of the screen, bounces off its sides and lands; flung, it flies and slides to a stop. On its own it stands, looks about, walks along the bottom of the screen and dozes, and its eyes follow the pointer when it comes near. A click pats it, a moment's rest of the pointer brings out its hearts, and pats count toward its level as in the island. Double-click it, drop it back on the island or pick Back to the Island from its menu and it flies home and hops out to its place. Reactions to what the Mac does play where it stands while it is out.
- **Walks on its own**: with Go for walks on its own on, now and then a visit takes it out of the island by itself for a minute or two, and it goes back in unless you play with it. Reduce Motion and Low Power Mode keep it still.
- **Cristóbal Sincronía and the White Rabbit**: two sprite companions drawn frame by frame, from the author's comic. They walk, hop, wave, think and fret in the island, the menu bar, notices and on the desktop, playing a row of their sheet for each mood and reaction. Accessories, colors and transformations apply to the drawn companions only.

### Fixed

- **AMD Ryzen Power panel**: the section now sits in the same rounded card as the other panel sections, instead of looking loose on the panel.
- **Sprite outlines**: Cristóbal's frames lost the faint cyan fringe left around his outline, stray specks are gone, and both characters have a softer edge.

## [1.47.1] — 2026-10-16 — kexts 3.35.0 (No kext changes)

Notifications in the Dynamic Island are more dependable: they show up when they arrive, and closing one in the island closes the system's banner too.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.0. Only the application's validation version pin changes.

### Fixed

- **System banners left on screen**: with Hide the system banner on, the island looked for the banner's close button by its English name, so on a Mac in another language the system's banner stayed up next to the island's. It now uses the name Notification Center shows in your language.
- **Closing in the island**: the close button on a message, in the inbox or on the held preview, and Clear all now also close the system's banner while it is still on screen, alerts included. Messages that already went to Notification Center stay there.
- **Messages that never appeared**: a read of Notification Center that ran out of time while a banner slid in is tried again a moment later, instead of waiting for the next banner. A message with the same words as an earlier one is no longer taken for that one, and a message that arrives while the volume or another busier notice has the island waits for its turn instead of going straight to the inbox.

## [1.47.0] — 2026-10-15 — kexts 3.35.0 (No kext changes)

The Dynamic Island now follows your fingers: pull it open or closed on the trackpad and it stretches with them, then settles the way you were heading. A song's cover flies from the closed island into the music page, the island stays open while you type in it, and a file carried to the top of a full-screen app lands on the island instead of the menu bar.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.35.0. Only the application's validation version pin changes.

### Added

- **Pull to open and close**: with Dynamic Island gestures on, a vertical swipe on the trackpad stretches the closed island down with your fingers, with a rubbery give, and an open one gives way a little upward. Lifting decides: a quick flick opens or closes it, a slower pull goes the way it was heading, and a short one springs back. A mouse wheel still opens and closes it in one step, and so does Reduce Motion.
- **Cover flight**: opening the island from the closed music capsule, the song's cover flies from the capsule into the music page and lands on its artwork, instead of fading out on one side and in on the other. Reduce Motion keeps the fade.

### Changed

- **Typing keeps the island open**: an island opened by hovering no longer closes when the pointer drifts off while you type in one of its fields, such as the Scratchpad or the Clipboard search. A click away, Escape or switching apps still closes it, and an island you only looked at still closes as the pointer leaves.
- **Activity picker**: one highlight glides under the pointer from choice to choice, instead of each choice lighting up on its own.

### Fixed

- **Full screen with Show over the menus off**: the menu bar coming down in a full-screen app no longer covers the island while it is open or taking a dragged file, so a file carried to the top edge lands on the island instead of the menu bar. At rest the island still makes way for the menus.

## [1.46.0] — 2026-10-14 — kexts 3.35.0

A full review of both kexts against the Linux drivers and the reference SMU tools: Curve Optimizer now uses the command and core numbering the firmware expects, SMU requests follow the firmware's protocol, GPU power reads no longer hang older Radeons, and the app stops counting GPU time twice.

> [!WARNING]
> **This release updates the kexts.** Unlike the last few releases, `AMDRyzenCPUPowerManagement.kext` and `SMCAMDProcessor.kext` move from 3.34.17 to **3.35.0**. Updating the app alone is not enough: copy both kexts from the DMG into `EFI/OC/Kexts/`, replacing the old ones, keep Lilu and VirtualSMC up to date, and reboot. Until you do, the old kexts keep running and the Curve Optimizer, SMU and GPU fixes below do not apply. Keep a copy of your current EFI so you can boot from it if anything goes wrong.

### Added

- **Load average**: clicking CPU in the panel (and the CPU view of a separate menu bar metric) shows the 1, 5 and 15 minute load averages as a share of the CPU's threads, each colored green, yellow, orange or red by level; 100% means every thread had work and more means work was waiting.
- **Long history**: clicking CPU, GPU or Memory in the panel shows a history graph above the process list, and Network and Disk have a folded History line under their graph. A menu picks the last 10 minutes up to 30 days, always as 120 averaged columns; hovering a column shows its value and time. With separate menu bar metrics, each metric's own view has the same menu. Only what RyzenStatus already measures is kept, nothing is sampled in the background for it, and the month is saved on this Mac so it survives a restart.
- **World clocks**: an optional panel tab with the time in the cities you choose, west to east, each with its day, the difference from your own time and a sun or moon. Cities are picked with a search in Settings → Quick tools; turn the tab on in Features.
- **Apps using disk**: the Disk section lists the apps reading and writing the most right now, with their read and write rates.
- **Network volumes**: mounted file shares (SMB, AFP, NFS, WebDAV) appear in the Disk section with their server, free space and an eject button. The block shows only while a share is mounted, and reading it never waits on a server that stopped answering.
- **Public IP (optional)**: the address block can show the address the internet sees. It is off until you click Show, and then asks Cloudflare at most every ten minutes.
- **Latency (optional)**: a new Network block pings 1.1.1.1 every five seconds, with a small graph, once you start it and only while the panel shows it.
- **Page ins and page outs**: the memory section and its detail view show how much memory has been read in from and written out to disk since boot.

### Changed

- **System panel**: every block works on its own, whichever are shown and in whatever order. Clicking a CPU or GPU card unfolds its details right under the cards, even with the usage rows hidden. GPU video memory moved from Memory to the GPU details, and Memory shows pressure and use at a glance, with compressed, cached, swap and page traffic unfolding on click. The "Temperatures" title only appears while arranging the panel.
- **Core rings in the panel**: the per-core view draws each core as a small ring that fills clockwise with its load, clock, temperature or power, with the value in the middle. Rows divide the core count evenly where they can (12, 10, 9 or 7 per row) and otherwise hold 8, so a 16-core Ryzen shows two rows of eight.

### Fixed

- **Older Radeon GPUs could hang the kext**: reading GPU power took a lock that the register reads then tried to take again, which stopped the kext's work loop on Polaris, Vega 10 and older GCN cards. Each read now takes the lock once.
- **GPU families follow Linux amdgpu**: GCN 1 cards read their temperature from the right register space, Tonga and Fiji use the correct SMC index pair, and Fiji and Vega M are recognised. Power is read only where the GPU reports it (Polaris, Vega M, Vega 10), now with the right scale, and a reading is skipped while macOS's own driver is using the GPU's mailbox instead of interrupting it.
- **Curve Optimizer on Ryzen 5000**: offsets go through the MP1 mailbox with command 0x35, as the firmware expects, and each core is addressed by its physical position, read from the CPU's fuses, so CPUs with disabled cores get the offset on the core you picked.
- **SMU requests**: the kext waits for the SMU to be free, never overwrites a request in progress, and passes all six arguments. Busy, missing-prerequisite, unknown-command, failure and timeout answers are told apart and named in the app.
- **OC mode and fixed frequencies**: OC mode, the all-core frequency and the per-CCD frequency send the arguments the firmware expects; the per-CCD frequency is applied to every core of the physical CCD you chose.
- **CPU temperatures**: Tctl and the CCD temperatures use the same offsets and per-model layout as Linux, for up to 8 CCDs.
- **Package temperature**: the dashboard and the menu panel showed a PM table field that reads above every sensor and even drops under load (a peak, not the current temperature), so the package looked 20–25 °C hotter than it was. They now show the temperature the SMU regulates against its thermal limit, and the old field stays in the PM table details as "Peak temp".
- **C-state warning**: AMD Ryzen Power warned that NVRAM and the running kext disagreed exactly when they agreed (C6 off in both, the default), and stayed quiet when they really differed.
- **Sensors**: the GPU die and GPU proximity keys were both listed as "GPU Core / Die"; they now carry their own names.
- **Per-core grid**: a parked core (under 6 % of the time active) hid its temperature and power along with its clock, so most cores showed a dash at idle. Only the clock is hidden now; temperature and power, which stay valid on a parked core, are shown, as the reference monitor does.
- **Package C6**: the value shown as C6 residency was a configuration register, not a time measurement, and is no longer reported.
- **Super I/O**: ITE fan tachometers are validated and configuration mode is exited properly; Nuvoton NCT668X chips are identified and released as in the Linux driver.
- **Sleep and wake**: Curve Optimizer, PBO, cHTC and OC settings are re-read after sleep instead of trusting values from before it.
- **GPU per process**: each GPU was counted twice, so per-process GPU time was doubled. It is now counted once.
- **Sensors** lists the CCD temperatures the kext publishes, named as CCDs, instead of inventing per-core rows.
- **Clipboard**: copy actions and the snippet clipboard read no longer touch the clipboard from the main thread, so a slow app on the clipboard cannot freeze RyzenStatus.

## [1.45.0] — 2026-10-13 — kexts 3.34.17 (No kext changes)

The Dynamic Island learns new moves and new looks: swipe sideways through what it shows and flick notices away, pick a retro, LED, mirror or wave visualizer that also plays beside the companion, and let the island say when a Focus turns on or when it is time to leave for your next event. Long song names scroll, dark covers keep their edges, and the floating capsule sits centred in the menu bar at the size you choose.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.34.17. Only the application's validation version pin changes.

### Added

- **Visualizer styles**: Retro, bars rising from the floor with the bass on the left, green into yellow into red, and grey caps that rest on the peaks; LED, bars of lit blocks in the cover's colour with one block left floating at the peak, like a 90s hi-fi; Mirror, the bars of 1.44.0 growing up and down from the middle; and Wave, one glowing line over the spectrum. Pick one in Settings › Dynamic Island › Content › Music, next to a live preview. Retro is the new default.
- **Visualizer beside the companion**: with the capsule resting on the companion and the song in its middle, a new song is named for a few seconds and then the visualizer takes its place, as it does in the music capsule.
- **Swipe gestures**: with Dynamic Island gestures on, swiping sideways on the closed island switches between the activities it shows (or skips the song on the music capsule), and swiping up flicks a notice away.
- **Time to leave**: before a calendar event that has a place, the island tells you when to set off, from the travel time there by car, on foot or by transit. Turn it on under Settings › Dynamic Island › Content › Calendar. Your location is asked for only while it is on and is used only for the route through Apple Maps.
- **Focus on the island**: the island shows when a Focus turns on or off, with the name and symbol you gave it. Turn it on in Settings › Dynamic Island › Activity › Indicators.
- **Blur behind the open island**: the top of the screen blurs and darkens behind the open island, fading out below it, so what it shows reads over a busy window. It is in Settings › Dynamic Island › Layout and stays off with Reduce Transparency.
- **Floating capsule size**: Capsule fit now works with the floating style too. Width narrows it and height makes it smaller, evenly above and below so it stays centred in the menu bar.

### Changed

- **Long song names scroll** in the capsule, pausing at their start each time round, instead of being cut short. With Reduce Motion they are still cut short.
- **Hovering names the song again**: moving the pointer onto the closed island shows the song's name and starts its seconds over before the visualizer returns.
- **Covers**: a dark cover has its deepest shadows lifted just off black so it keeps its edges on the island, and a new cover turns over like a card.
- **Apple Music streaming queue**: when Music plays from Apple Music outside your library, the queue page now says that Music does not share what plays next there, and that an album or playlist from your library shows it.

### Fixed

- **Floating capsule centring**: the floating style's capsule sat half a point low in the menu bar, because it centred on the bar including its bottom hairline. It now keeps the same margin above and below, as the capsule style does.

## [1.44.0] — 2026-10-13 — kexts 3.34.17 (No kext changes)

The Dynamic Island gets a music visualizer: a new song is named for a few seconds, then mirrored bars move with the music in the middle of the capsule while the companion dances to the bass at its end.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.34.17. Only the application's validation version pin changes.

### Added

- **Music visualizer in the Dynamic Island**: on a capsule island, a new song's name shows for a few seconds and then 20 mirrored bars take the middle, bass in the centre and treble at both ends, in the cover's colour, each with a peak cap that rests and sinks slowly. They follow the real sound with "Bars follow the music" on and keep their own motion otherwise. Resting the pointer on them or pausing names the song again. Pick between the song name, the name then the visualizer, or the visualizer only, and how long the name stays (3, 5 or 10 seconds), in Settings › Dynamic Island › Music.
- **The companion dances**: while the visualizer plays it stands at the end of the island and nods to the bass. It can be turned off in the same place.

## [1.43.0] — 2026-10-13 — kexts 3.34.17 (No kext changes)

The companion grows up: it now reaches level 50, and levels 20, 30, 40 and 50 unlock four transformations with their own auras and a full transformation scene, and petting it finally shows. The Dynamic Island queue page lists what Apple Music plays next.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.34.17. Only the application's validation version pin changes.

### Added

- **Up next from Apple Music in the Dynamic Island**: the queue page lists the next songs of the playlist or album Music is playing from (up to 25), and clicking one plays it. Music does not share its own Up Next list, so songs you add with Play Next or Play Later are not shown, and with shuffle on the page says the order is not shared. Other players still show the queue as unavailable.
- **Companion transformations**: the companion now grows to level 50, and levels 20, 30, 40 and 50 unlock four transformations: golden aura, golden lightning, golden fury and divine aura. Each one recolours it and wraps it in its own aura of flames, lightning and sparks. When one unlocks it plays a full transformation: it crouches and trembles while sparks crackle, then bursts out in a flash and a shock wave. In Settings › Dynamic Island › Companion you can pick any unlocked form, turn them off, or watch the transformation again.

### Changed

- **Petting the companion shows**: while the pointer rests on it, it closes its eyes in a smile and sways. Each pat that counts sends up hearts and the experience it earned, and the wait between pats that count drops from 30 to 10 seconds.

## [1.42.0] — 2026-10-13 — kexts 3.34.17 (No kext changes)

Settings get their new layout: a grouped sidebar with search suggestions, the General page in cards with the menu bar panel editor and a menu bar icon you can pick from the system symbols, the Monitor page reorganized around a live preview, and AMD Ryzen pages gathered in a section of their own. The Features page offers to tidy away features you never switched on, the image converter gains profiles, resizing, renaming and watermarks, the URL cleaner learns per-site rules, and the menu bar panel hands focus back to the app you were using when it closes.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.34.17. Only the application's validation version pin changes.

### Added

- **Menu bar icon**: pick any system symbol to stand in for the RyzenStatus mark, from a gallery or by name, in Settings › General › Menu bar panel. The keep-awake states draw on top of the symbol you chose.
- **Menu bar panel editor**: a miniature of the panel next to its sections, dragged into order with a switch each, in Settings › General › Menu bar panel, with the accordion mode beside it.
- **URL cleaner rules**: every rule is listed and can be switched off on its own, by site or everywhere, and you can add a parameter for one site only. The panel cleans as you type or paste, and every surface says which parameters it took out.
- **Image converter**: saved profiles, exact or proportional resizing, fit and fill, background colour, renaming with tokens, text or logo watermarks, an output subfolder and keeping the original modification date.
- **Scratchpad**: Markdown preview, text size, background opacity and find in the pad.
- **Features page**: features installed but never switched on are offered for removal in one batch, with Undo, or kept for good. Removing the Dynamic Island asks whether its extensions go too, and the island's row is marked experimental.
- **Network speed unit** in Settings › Monitor: bytes (MB/s) or bits (Mbps), used by the panel, the metric details and the menu bar.

### Changed

- **Settings sidebar**: tools sit in groups (Utilities, Sound, Energy and Display, Windows and Dock, Mouse and Keyboard, Files) with one row per tool, the AMD Ryzen pages (dashboard, fans, AMD Ryzen Power, overclocking, sensors and validation) have a section of their own under the essentials, and search suggests the exact setting, grouped by page, with the arrow keys.
- **General** is laid out in cards: launch at login with approval guidance, language, appearance with previews of each mode, Liquid Glass, the Keep Awake shortcut, feedback and the Use Bluetooth switch.
- **Monitor** is laid out in cards: the menu bar preview stays pinned at the top while you change what it shows, then the panel, its graphs, and the readings both share.
- **Launch at login** is read and changed off the main thread, since Service Management can stall while answering.
- **Music app blocking** only blocks a launch a media key explains: each key explains one launch, a click or key press after it takes precedence, and the replacement player starts playing when the key was Play.
- **Updates** refuse a downloaded app whose version is not the release that was offered, and the What's New video download is bounded while it runs.

### Fixed

- **Closing the menu bar panel** with Esc or by clicking the icon again gives activation back to the app you were using, unless that would switch desktops. RyzenStatus used to stay the active app until something else was clicked.
- **Show menu bar icon** keeps the spot you arranged and only starts the icon over under a new identity when keeping it does not work. It no longer places the icon 64 pt from the edge, right under the system battery item, and it waits for macOS to finish placing the icon before saying it is still hidden.
- **After an update**, the first launch checks that the menu bar icon made it on screen and rebuilds it once, keeping its spot, if not.
- **Panel on the right display**: with a menu bar on several displays (or Sidecar), the panel and Settings open on the display you clicked.
- **Inactive menu bar**: metric items and a hidden icon now dim with the rest of the menu bar on an inactive display.
- **Shelf placement** ignores the parked frame a hidden menu bar leaves behind, and clicks on hidden menu bar items no longer count as clicks on the icon.
- **Calendar permission** shows its name and explanation in your language instead of English.
- **Portuguese** donation texts were in Spanish.
- **Settings backups** no longer carry folders chosen on one Mac (save folders, file scopes, bookmarks) or one Mac's history, such as the Command Bar's usage and the WhatsApp organizer's records.

## [1.41.0] — 2026-10-13 — kexts 3.34.17 (No kext changes)

The Dynamic Island's companion grows with you: it has a name, a level and a story, dresses up from a wardrobe that unlocks as it levels, wears costumes for the season, follows your AMD hardware and says a word of its own now and then.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.34.17.

### Added

- **Your story with the companion**: give it a name and watch it grow. Pats, every day you spend together and each moment it reacts to add up to ten levels, with daily caps so growth follows your time together rather than how often the pointer rests on it. Settings shows its level and progress, its age, pats, moments and days together, and can start over.
- **Accessories**: a bow, glasses, a scarf, headphones, a beanie, a flower, a top hat, sunglasses and a crown, one unlocked at each level and picked in Settings. They ride on the head or sit on the face and move with it.
- **Seasonal costumes**, on by default: a witch's hat the last week of October, a Santa hat around Christmas, a party hat at New Year and on the day it came out, a year on.
- **Follows your AMD hardware**, on by default: the fan companion spins at your CPU fan's real speed from the kext, the chip's mark glows with package power against its PPT limit, and it puts on a headband and cheers when Gaming Mode starts.
- **Its own notices**, on by default: a greeting for the time of day the first time you are around each day, a word when it reaches a new level (naming what it unlocked), and celebrations at a week, 30 days, 100 days and every year together. Switched off, it still plays the reaction without a notice.
- **Local IP address** in the menu panel's Network card: each connected interface's IPv4 address with the system's name for it (Wi-Fi, Ethernet). It is read from the Mac's own interface list only while the card is on screen, and nothing leaves the machine. It can be hidden from the card's edit mode or from Settings › Monitor.

### Changed

- **Menu bar power keeps its interval**: with the system draw pinned to the menu bar, it is read at the chosen interval instead of on the slower stride battery charge and time use, so the watts no longer lag behind.
- **Desktops without a battery** no longer listen for power source changes.
- **Quit on close** catches apps that create their first window a moment after launching, retries an app that is still busy with short delays (0.15 s to 10 s instead of 5 s to 160 s), keeps menu bar and background apps running when their settings window closes, covers apps nested inside an excepted app and guest app windows of an excepted virtual machine host, and hides the built-in Phone exception on Macs without the Phone app.

### Fixed

- **GPU temperature and GPU power alerts never fired**: the timer that waits for a sustained reading was restarted on every sample. They now notify once the reading has held for 12 s.
- **Alert temperatures use your unit**: CPU, GPU and sustained-load notifications showed Celsius even with Fahrenheit selected.
- **CPU usage after a pause**: when the CPU reading was not needed for a while (nothing on screen asked for it), the first reading back averaged the whole pause. It is now discarded, like the first reading after sleep.
- **Network**: a failed counter read no longer shows as a drop to zero and then a spike, the per-app list stops a stuck `nettop` after a bounded time, and the speed test checks the server's HTTP answers before measuring.
- **Disk**: free space counts what macOS can purge, as Finder does, without asking mounted disk images (which filled the log with errors), `diskutil` runs with a time limit, and a corrupt SMART value can no longer crash the app.
- **Battery time** can no longer overflow on a nonsensical estimate.
- **Bluetooth battery scan**: a long `system_profiler` report could block until its timeout and come back cut off. It is now read while the command runs.
- **Launch at login waiting for approval**: when System Settings still has the login item switched off, turning the option on says where to approve it instead of silently flipping back, and startup no longer registers over it.
- **Settings next to the menu panel**: when Settings cannot open beside the panel without covering it, the panel closes instead of being covered.
- **Cleaning Mode**: the overlay no longer flickers, Esc unlocking accepts a wider window and lets modifier keys reset it, a click that started before unlocking finishes before the overlay goes, mouse click debounce is paused with the rest, and switching to another user ends the session safely.
- **Keyboard debounce** hands its event tap back when you switch users, and ignores keys the app itself types.
- **Event taps** are invalidated when they are torn down, so their ports are released.
- **App exception lists** accept apps picked from the running list, and executables only where the list supports them.
- **Process names**: system processes in the GPU list showed as "pid 100" on recent macOS; their executable name is shown instead.
- **Updates** stage the new copy under a hidden name, so Spotlight does not index a half-copied app.
- **Uninstalling** also removes the app's caches and network storage, and reports whether normal sleep and the Space arrangement setting were restored.
- **Clean URL** custom parameter field takes clicks across its whole row and has a Save button.
- **Command Bar**: days until 29 February count to the next leap year.

## [1.40.0] — 2026-10-12 — kexts 3.34.17 (No kext changes)

The graphs outside the menu bar now match it: the menu panel, the iStats widgets, the metric details, the Dynamic Island and both dashboards draw their history as columns, newest on the right, in the graph theme picked for their appearance, and the AMD Ryzen Power graphs get steady scales. Fan curves now come back at launch, and the manual-fan thermal guard and GPU-sourced curves keep working with Settings closed.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.34.17. Only the application's validation version pin changes.

### Changed

- **AMD Ryzen Power graphs**: package power is drawn against the PPT limit when the PM table reports it (otherwise against its busiest sample rounded up to 25 W, at least 50 W), and package temperature against 0–100 °C, stretching in 10 °C steps above that. Each graph shows its latest value and the top of its scale. They used to rescale to their own busiest sample, so a steady reading always sat at the top, and the smoothed line could overshoot the frame. The per-core clock and temperature graphs are one-point columns.
- **Menu panel graphs**: CPU shows system time behind user time. Network and disk put upload or writes above and download or reads below, laid out like the menu bar network graph, each direction scaled to its own busiest visible sample, so a slow upload stays readable next to a fast download; the arrows next to the rates take the graph's colors. System power shows the top of its scale.
- **Metric details** (menu panel and Dynamic Island): CPU stacks system and user time and adds the average clock below it on its own scale, memory shows app memory in front of the rest of used memory, and network and disk use the two-direction graph.
- **iStats widgets**: the CPU card adds a load history, and its per-core bars show system time behind user time. Its legend's User figure is now user time (it showed the total load), next to System and the core count. Core and memory rings, histories and legends use the graph theme. Memory lists app, used, compressed and free memory and adds a history, and the GPU card adds a history. Card titles that were fixed in English are translated.
- **Dynamic Island**: the CPU, GPU and memory cards show a small history instead of a level bar once two samples are in, orange while the reading is high.
- **Dashboards**: Performance Suite and the btop-style dashboard draw columns in each metric's own color, and the analytics charts get quarter guide lines and a scale label. The btop network graph covers the whole history instead of the last 24 samples, each direction on its own scale.
- **Smaller app**: the release build no longer ships its debugging symbol table, which was more than half of the executable. The installed app drops from 85 MB to 37 MB and the download from 24.8 MB to 18.5 MB, with no change in behavior.

### Fixed

- **Fan curves after a relaunch**: the app hands every fan back to the BIOS when it quits, and on the next launch it only put fans back on their curves once Settings › Fans was opened. They go back on their curves at launch now.
- **Manual fans and GPU-sourced curves with Settings closed**: the emergency guard that raises a manual fan at 85 °C, and the GPU temperature that GPU-sourced curves follow, were only updated while Settings › Fans was open. They now run every 3 s in the background whenever a fan is in manual mode or follows a GPU-sourced curve, and the GPU temperature is read from the kext on each pass instead of from a cache that only refreshed while the system monitor was sampling.
- **After the kext connection is reopened** (the kext reloaded, or a connection that stopped answering after sleep), the fans are read again and the curves and mappings uploaded anew. Closing the old connection used to leave every fan on BIOS control until the next wake.
- **Fan speed in the AMD Ryzen Power panel**: it was read once when the panel opened, usually before the fan list had loaded, so it showed 0 RPM, and again only when another fan was picked. It now updates live while the fan row is expanded, shows a dash for a tachometer that cannot be trusted, uses the names given in Settings and leaves hidden fans out.
- **Clearing a fan's name** kept showing the old one until the fan list was reloaded, and the hardware validation report fingerprinted the Super I/O chip from the names you gave the fans instead of the hardware labels.
- Turning fan curves off shows every fan on Auto right away, and a slow first fan read can no longer be cancelled by the next poll and leave the Fans page loading.
- **Auto EPP** could leave a preset's EPP in place after being turned back on, because it skipped writing a target it had already written before. It also steps up to more performance at once but waits three polls (4.5 s) before stepping down, so load hovering around a threshold no longer flips the EPP every 1.5 s, and its target names are translated.
- **Gaming Mode turned off right after launch** now waits for the Extreme preset it is still re-applying, so the previous preset is restored reliably.
- **Boot-args** are read from NVRAM without starting a process, and the AMD flags are matched as whole arguments: a longer argument that merely contains `-amdpnopchk` no longer counts as it.
- The average above the CPU, GPU and memory analytics charts in Performance Suite lost its percent sign.

## [1.39.0] — 2026-10-12 — kexts 3.34.17 (No kext changes)

Themed menu bar graphs: history, network and memory graphs are redrawn as one-point columns, the cores graph as one bar per core and the donut as a ring, each in a box that adapts to light and dark menu bars, with palettes chosen per appearance.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.34.17. Only the application's validation version pin changes.

> **First published build since 1.36.1**: 1.37.0 and 1.38.0 were never released on their own, so this download also brings everything in their notes below: Dynamic Island, Command Bar, Kill Process, MacPorts support, the capsule center and the rest.

### Bluetooth on a Hackintosh

Three features in this release talk to Bluetooth: the Dynamic Island's accessory notices, the Bluetooth battery scan and Bluetooth sleep. On a Mac whose Bluetooth service answers slowly, which can happen on a Hackintosh, test builds of this release could keep RyzenStatus's menu bar icons from appearing for more than 20 seconds at launch, because the list of paired devices was read on the app's main thread. The release reads that list in the background, so launch no longer waits for it. What to do depends on your Mac:

- **No Bluetooth controller at all**: nothing. The app detects it, never asks the system about Bluetooth, and the switch below does not appear.
- **A Bluetooth controller that answers slowly or does not work**: turn off **Use Bluetooth** in Settings › General. The app then stops its own Bluetooth queries until you turn it back on: Dynamic Island connection notices, the Bluetooth battery scan (headphones and other devices macOS lists only under Bluetooth) and Bluetooth sleep. Mice, keyboards and trackpads whose battery macOS already reports keep showing it, with their low-battery notices. If an earlier sleep left Bluetooth off, the app still turns it back on once.
- **Working Bluetooth**: leave the switch on, which is the default. Nothing changes.

This is an app setting only. No kext is involved and nothing has to change in your EFI.

### Added

- **Graph themes** in Settings › Monitor: follow the system accent or pick one of ten palettes, six soft variants or monochrome, separately for light and dark menu bars. On a light menu bar graphs sit on a dark pill by default, or on an outline. History width, column spacing and the network layout (mirrored, top and bottom, both rising) are configurable. The bar colors and limits keep applying to the Bars style.

### Changed

- **Menu bar graphs redrawn**: history graphs are one-point columns with the newest sample on the right instead of a stretched line, network fills its box with one column per sample (the whole history width instead of the last 12 samples), upload and download each still scaled to their own busiest visible sample, cores get one bar per core in a box sized to the core count (with the kext loaded, SMT threads fold into their core), and the donut is a clean ring. CPU history, ring and cores stack system time over user time in the theme's second color. Memory now draws its history and ring too: app memory in the theme's main color, with the rest of used memory above it in the second color. No more artificial 8 % floor: idle reads as idle, any activity keeps one point.
- Graphs no longer print their value over the plot by default. Settings › Monitor › Show numeric value inside graph brings it back; anyone who already set that switch keeps their choice.

### Fixed

- **Possible crash after about 248 days awake**: per-core CPU load read the kernel's tick counters as signed 32-bit numbers, so a counter past 2^31 made the conversion trap. They are now read as the unsigned values the kernel keeps, and a reading whose busy or system counters went backwards is discarded instead of being trusted.

## [1.38.0] — 2026-10-12 — kexts 3.34.17 (No kext changes)

Package-manager coexistence for Intel, safer clipboard controls, a corrected floating Dynamic Island, and most of the upstream port (shared foundations, everyday tools, windows, captures, mouse and the Dynamic Island's AI section). This release is a continuation of the upstream port, not a claim that every remaining block is complete: AMD-aware metric views, the Settings redesign, the remaining upstream test suites and native translation review are still pending.

> **Kext Note**: No changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext`. Both remain at 3.34.17. Only the application's validation version pin changes.

### Added

- **MacPorts support** in the existing package-manager Settings page, menu panel and quick launcher. Automatic selection prefers MacPorts on Intel; Homebrew remains available for existing packages and casks. No automatic migration or installation.
- Read-only MacPorts inventory, outdated packages and package search with bounded background processes. Install, upgrade, uninstall and self-update are explicitly confirmed and handed to Terminal for administrator authorization. Opening Terminal is not reported as completed installation.
- **Opt-in system clipboard clearing** after a delay, on sleep, display sleep or screen lock, independently of recording history. Saved and pinned entries are never deleted by these triggers.
- **Keep Awake until a chosen time**, with Calendar-based resolution of the next local occurrence, including daylight-saving transitions.
- Regression checks for package-name injection/pseudo-ports, clipboard configuration invalidation, state-specific island geometry and mascot priorities/cooldowns/non-finite readings.
- **AI agents in the Dynamic Island** (off by default): tokens, plan limits, API value and work in progress for Claude Code, Codex, OpenCode and GitHub Copilot, read from the history files those tools already keep on this Mac. Live strip beside the camera, lock-screen line, notices and a page of cards. Prices ship inside the app; optional daily updates come from this project's repository. Codex banked resets can be read and used, only after confirmation.
- **Feedback**: report a bug or suggest a feature from Settings › General, the panel header or the Command Bar. The app opens a prefilled GitHub issue in your browser; nothing is sent until you submit it there.
- **Connected devices in the menu bar and the island**: an optional USB device count next to the menu bar icon, its own detail page and a card in the island's System page.
- **Capsule center** for Macs without a camera: while a song plays, the middle of the capsule or floating island can show the song, a live metric (CPU or GPU temperature, CPU usage, memory or network download), both in turns, or the clock. It also works at rest: with the island resting with the companion, the capsule shows the reading beside it. With Nothing, the capsule shrinks to the cover and the bars instead of keeping an empty black block. Settings › Dynamic Island, under the shape.
- **Companion in the menu bar while the floating island is open**: instead of disappearing, it stays up in the bar where it rests, follows the pointer with its eyes, walks a little after it, hops when you click in the island and glances around when you change page. With Reduce Motion it only moves its eyes. Settings › Companion › Watch from the menu bar, on by default.
- **Use Bluetooth** switch in Settings › General (only on Macs with a Bluetooth controller): turn it off and the app stops its own Bluetooth queries, so Dynamic Island connection notices, the Bluetooth battery scan and Bluetooth sleep stop. Useful on Hackintoshes whose Bluetooth answers slowly or does not work; see *Bluetooth on a Hackintosh* under 1.39.0.
- **Input source notices** in the island when the keyboard layout changes, and a headphones symbol on the volume notice when they are the output.
- **Super Key safety guard**: a small helper takes the key mapping back out if the app is killed, so Caps Lock never stays remapped.
- Clipboard: automatic cleanup, text preview, history window with saved size, OCR in previews, image editing, optional menu bar preview item.
- Keep Awake: pause on lock, keep awake while chosen apps run, lid dimming, last-pick shortcut, battery protection.
- Displays: lid-close dimming, keyboard backlight control, brightness shortcuts for display and keyboard.
- Windows, switcher, captures and recorder from upstream: window layout gestures and exclusions, unified capture with watermark and tool picker, recorder blur, image overlay and export speed.
- Mixer: AirPlay routes and the precise volume roller.
- Radial menu: per-profile shortcuts, visual editor, Now Playing read from the app's single Now Playing engine.
- Mouse and scrolling: one Mouse page, Spaces gesture, Back/Forward side buttons in Settings, time-based smooth scrolling with response and coast, linear scrolling.

### Changed

- The package-manager feature keeps its existing storage identity and Homebrew ownership safeguards, so current installations and preferences survive the new provider selector.
- Homebrew commands inherit only supported proxy and `HOMEBREW_*` exports from a bounded login-shell session. Environment resolution stays off the main thread.
- Launch synchronizes the island once for its installed modules and plans the monitor once for its metrics instead of repeatedly initializing the same services.
- Memory in use follows upstream's definition (app + wired + compressed + tagged storage) and is read with a pure Swift decoder that understands macOS 26's newer statistics layout.
- Decimal numbers in the monitor follow your region's separator.
- Temporary-link sharing for captures and recordings stays hidden until a sharing server is configured; there is no default server.
- Synthetic input events carry RyzenStatus's own marker, so they are never confused with another app's.

### Fixed

- **Floating island on displays without a notch**: compact activities and the transparent resting companion stay in the menu bar; expanded panels move below it without covering menu items.
- Clearing recent clipboard history in Settings or the menu panel requires confirmation.
- Invalid temperature, CPU or battery values no longer drive automatic mascot warnings or animations.
- The Dynamic Island again shows volume notices and macOS notifications; both had stopped being connected during the port.
- **Slow launch on Macs with an unresponsive Bluetooth service** (test builds only): the island's accessory notices asked for the paired Bluetooth devices on the app's main thread, which could keep RyzenStatus's menu bar icons from appearing for more than 20 seconds while the system answered. The list is now read in the background.
- **Screen Recording permission after installing a new build**: macOS keeps the permission bound to the copy of the app that received it, so a newer copy found the switch on and the permission gone, and macOS never asked again. The panel's Grant Access button now closes the panel and opens System Settings, so the guide card is no longer hidden behind it. When the permission does not arrive, the card explains why and offers Start Over, which removes the old entry and asks again; once granted, it offers Relaunch, since Screen Recording applies only to a new launch.
- **Screen Recording row in the panel**: it showed Grant Access even with the permission granted, the button did nothing, the row no longer started a recording and its Recent Captures button was missing. The permission button now appears only while the permission is missing, and the row and Recent Captures work again.
- Panel dismissal accounts for the AirPlay picker, and the panel remembers which display its status item is on.

## [1.37.0] — 2026-10-11 — kexts 3.34.17 (No kext changes)

Dynamic Island, Command Bar and Kill Process arrive, the Uninstaller recognizes apps installed with Homebrew, the Cleaner finds forgotten screenshots and reports what an automatic cleanup left behind, and the app now speaks Slovak and Ukrainian.

> **Kext Note**: This release introduces no changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext` (both remain on version 3.34.17 from the S11 drop). All changes are strictly within the macOS application layer. **No kext updates in EFI or driver reinstalls are required.**

### Added

- **Dynamic Island**: An optional island at the top of the screen that brings music, controls and everyday tools together. Off by default; with it off, the separate panels work as before. Choose where it appears (automatic, built-in display, main display, follow the pointer, or all displays) and which modules it shows:
  - Now Playing with artwork, scrubber, live equalizer and optional synced lyrics from LRCLIB.
  - Brightness and volume sliders, quick controls and a per-app volume mixer.
  - Live CPU, GPU, memory, disk and network readings.
  - File shelf with drag and drop, scratchpad notes, clipboard history and screenshot previews.
  - Quick launcher tools, calendar, notifications, timer and Pomodoro, camera mirror and download progress.
  - **Watch**: turn any part of any window into a live activity, with an alert when it changes, finishes, shows the text you are waiting for or reaches a number.
  - Optionally, music and activities on the Lock Screen.

  The island uses the app's built-in Now Playing support: it never turns the menu bar Now Playing item back on, and it stops checking for media when nothing needs it.
- **Command Bar**: One field that finds and runs everything the app does. Open it with a global shortcut (⌥Space by default, off until you turn it on in Settings) or from the Dynamic Island, then type to:
  - calculate, convert units, dates, time zones and color formats;
  - search emoji and files;
  - open apps (also by the names Spotlight knows them by), windows, System Settings panes and every RyzenStatus Settings page;
  - run the app's tools and actions, including Kill Process.

  Add aliases, pins, your own links and keyboard shortcuts for individual rows; a shortcut macOS already uses is rejected with a conflict notice. Optional compact mode, and an option to switch to an ASCII keyboard layout while the bar is open. Text snippets do not expand while you type in the bar.
- **Kill Process**: A new Settings page to search running processes (sorted by CPU, with related processes grouped) and force quit, restart or end whole process trees. Also available from the Command Bar. RyzenStatus itself and vital system processes such as `kernel_task`, `launchd`, `WindowServer` and `loginwindow` are protected.
- **Homebrew-aware uninstall**: The Uninstaller recognizes apps installed by a Homebrew cask, when exactly one installed cask matches the app's location. After you confirm, the app is removed through Homebrew and the other items you selected are removed as usual. A confirmation that no longer matches the current selection is refused, so you can review and confirm again.
- **Uninstaller in the Command Bar** (opt-in): *Show in Command Bar* lets you pick and uninstall apps, including the one selected in Finder, from the Command Bar. When an app is uninstalled, its Command Bar aliases, pins, hidden rows and row shortcuts go with it, unless another copy is still installed.
- **Forgotten screenshots in the Cleaner**: A new category lists screenshots you have not opened for a set time (7, 14, 30, 60 or 90 days; 30 by default; or off) that still have the name and folder macOS gave them. Screenshots you renamed or moved never appear, and finds are always offered unchecked, with their total size.
- **WhatsApp downloads card in the Cleaner**: With WhatsApp downloads enabled, the Cleaner panel shows a collapsible card with its status and its last and next automatic cleanup, plus a button to its Settings page. With it off, the Cleaner's Settings page offers a card to turn it on.
- **Slovak and Ukrainian**: Two new interface languages, for 15 in total. Every page, including the AMD power, fan control and hardware validation pages, is translated.
- **Wallpaper gallery**: Browse and apply wallpapers from the menu bar panel, on one display or on all of them. Off until you install it from Features.
- **Quit & close protection**: Guard ⌘Q and ⌘W behind a second press or a hold, per app or everywhere, with exceptions and an on-screen hint. Also applies to the Switcher's Q and W keys.
- **Disk image installer**: Opening a downloaded `.dmg` offers to install the app it contains, optionally into `~/Applications`, then can reveal the app and move the download to the Trash. Off until you install it from Features.
- **Port Manager**: See which apps are listening on which network ports, and stop them, from Settings or a panel tile. RyzenStatus itself and system processes are protected.
- **Connected devices**: The System section of the panel lists connected USB devices.
- **Mouse extras**: Focus follows mouse, turning off mouse acceleration, linear scrolling, horizontal scrolling with a modifier key, and a click debounce filter for worn mouse buttons. All off by default.
- **Spaces order**: Keep your Spaces in a fixed order, so macOS stops rearranging them by recent use.
- **Finder rename**: A keyboard shortcut to rename the selected file in Finder.
- **Audio priority**: Rank your output and input devices so the best one connected is used automatically.
- **Bluetooth sleep**: Turn Bluetooth off when the Mac sleeps and back on when it wakes.
- **Snippet Library**: Text Snippets settings can now turn on the snippet library and set its shortcut, with a warning when the shortcut can't be registered. Snippets gain a folder, case-insensitive triggers and a "show in quick menu" option, and an optional sound when a snippet expands.

### Changed

- **Multi-line snippets paste instead of typing**: A snippet with several lines is pasted in one go. Your clipboard is saved first and restored half a second later, unless you copied something else in the meantime. The library panel no longer closes when you click the Accessibility Keyboard.
- **The menu bar panel stays open while work is running**: A Cleaner, Uninstaller or Homebrew operation in progress now keeps the panel open, even after you switch to another section. Clicking outside, opening Settings or switching apps no longer closes it mid-operation; clicking the menu bar icon or pressing Escape still does.
- **Uninstaller app selection**: The app picker lists only apps that can be removed, with each app's location. The picker, drag and drop and the Finder selection all pass the same checks: a verified bundle ID, no symbolic links, the same app that was scanned, and never a system app or RyzenStatus itself. Starting a new scan cancels the previous one, scans can be cancelled, and the buttons are locked while Homebrew is removing an app. An item counts as removed only once it is confirmed gone from disk.
- **Automatic cleanup runs unattended**: It skips the forgotten screenshot search, which reads your own folders and may ask for access, so that search only runs when you scan yourself. Orphaned startup items stay unchecked in automatic passes, as before.
- **Cleaner layout**: The schedule row wraps onto two lines when the panel is narrow, results scroll with the panel in compact mode, and the cards are ordered schedule, forgotten screenshots, WhatsApp downloads, then the Full Disk Access notice.
- **Settings**: The sidebar and the Command Bar read from one list of Settings pages, and the Super Key page icon now follows the key you chose.

### Fixed

- **Automatic cleanup failures are no longer silent**: A pass that could not move some items used to read like a quiet success. The last-run line in the Cleaner now adds "Some items couldn't be moved to the Trash." when that happens.
- **Closing the Cleaner mid-scan cancels the scan**, so it no longer comes back the next time you open the Cleaner.
- **Leftover attribution**: A file such as `com.vendor.Service.plist` is credited to `com.vendor.Service` instead of `com.vendor`, because only one file extension is stripped. Entries with a developer team prefix (`ABCDE12345.com.vendor.editor`) are credited to the app instead of the developer account.
- **No duplicate rows across categories**: A path already listed under *Leftovers from uninstalled apps* no longer reappears under *Caches* or *Logs* in the same scan.
- **Panel behind confirmation dialogs**: The panel no longer closes underneath a Homebrew or Uninstaller confirmation dialog, which could leave the next panel unresponsive.

## [1.36.1] — 2026-09-16 — kexts 3.34.17 (No kext changes)

Bug fix for the hardware validation kext revision gate resolution.

> **Kext Note**: This release introduces no changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext` (both remain on version 3.34.17 from the S11 drop). **No kext updates in EFI or driver reinstalls are required.**

### Fixed

- **Kext Revision Validation Gate (`3.34.17` vs `6`)**: Resolved a false-positive `FAIL: 6 != expected 3.34.17` in the Hardware Validation settings page. Kext selector 8 historically returned macro-expanded `MODULE_VERSION` (`"6"`, internal module ABI) rather than the marketing bundle version `3.34.17`. `ProcessorModel` and `HardwareValidation` now query the macOS kernel via `KextManagerCopyLoadedKextInfo` for the true `CFBundleVersion` / `CFBundleShortVersionString` of `wtf.spinach.AMDRyzenCPUPowerManagement`, properly evaluating the gate to `PASS`.

## [1.36.0] — 2026-09-16 — kexts 3.34.17 (No kext changes)

Hardware validation evidence surface to close pending silicon probes, frozen tachometer detector wiring, native Kaset player integration in Now Playing, and resolution of the launch hang caused by synchronous TCC prompts.

> **Kext Note**: This release introduces no changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext` (both remain on version 3.34.17 from the S11 drop). The full hardware validation cycle enabled by this release operates on existing kernel selectors, and the Now Playing integration operates entirely in the macOS user space layer. **No kext updates in EFI or driver reinstalls are required.**

### Added

- **"Hardware Validation" Page in Settings** (`checkmark.seal`): The bottleneck for `[REQUIERE-HW]` milestone items was not missing code, but that evidence had no home. Kernel logs are sandboxed from repository tooling (`log show`), and CLI utilities (`--sensors` / `--selftest`) cannot be used during a probe cycle because closing a kext client triggers `clientClose()`, returning all six fan channels to BIOS and silently clearing the state being measured. The app itself is now the structured evidence surface.
- **Preconditions Matrix with PASS/FAIL/UNKNOWN Verdicts**: Real-time diagnostic gates with actionable fix hints and technical rationale: kext revision check against pin (3.34.17), selector 100 telemetry, privileged access, fan channel topology with AIO pump identification, per-channel tachometer trust, and Super I/O family inference. The *Run Preconditions Check* button evaluates selector 58 (privileged, read-only: writes no fan, voltage, or limit). Two documented false positives are now surfaced as explicit UI gates: unprivileged runs fall back to BIOS (~15% duty, mimicking the curve floor), and frozen tachometers make a stalled fan look healthy.
- **P0–P6 Probe Checklist with Persisted State & Telemetry Sampling**: Retains validation history across reboot cycles. *Record Sample* captures a single-line snapshot (kext package temperature & power, per-channel duty %, RPM, and tachometer validity), capped at 400 bounded lines with FIFO eviction so the freshest evidence is evaluated.
- **Copyable ASCII Evidence Report**: Formatted diagnostic report containing preconditions, fan channels (mode, chip duty %, RPM, validity, pump mark), curves (source sensor and fan mapping), package power readings, and the three core safety invariants (`floor=PWM40`, `guard=85 °C/PWM200`, `failsafe=PWM160`). The block is also embedded into the SMU diagnostics bundle to ensure bug reports and probe verdicts align.
- **`HARDWARE_VALIDATION.md`** (local work document, gitignored): Step-by-step runbook for all seven probes, PASS criteria per probe, documented false positives, and roadmap checklist.
- **Native Kaset Player Integration in Now Playing**: Full support for Kaset ([sozercan/kaset](https://github.com/sozercan/kaset)), the native macOS YouTube Music and YouTube client:
  - Bundle detection for both `com.sertacozercan.Kaset` and `com.sertacozercan.kaset` with active-player priority in Auto mode over paused background sessions.
  - JSON protocol parser for `get player info` (title, artist, album, duration, position, YouTube `videoId`, and artwork URL).
  - Interactive transport controls (`playpause`, `next`, `previous`, `seek`).
  - Playback mode synchronization: shuffle toggle and 3-stage repeat cycling (`off` → `all` → `one` → `off`).
  - Intelligent search routing: recognition of 11-character YouTube video IDs, YouTube/Kaset URLs, and targeted YouTube Music web search.
  - Complete localization across all 13 supported languages.

### Fixed

- **Wired Frozen Tachometer Detector**: `AMDFanSafety.isTachometerStale` was introduced tested in 1.34.0 but lacked an active caller. `FanCurveController` now maintains a rolling per-channel RPM window and sets `rpmValid = false` when eight consecutive non-zero readings are identical (detecting disconnected headers or electrical residue that report static plausible values). The detector only revokes trust (rendering `— RPM`), never grants it, preventing the kernel stall-recovery floor from being suppressed.
- **Resolved Launch Hang on macOS 15.4+**: `MediaRemoteBridge.triggerTCCPrompt(for:)` previously executed `AEDeterminePermissionToAutomateTarget` synchronously on `@MainActor` during `applicationDidFinishLaunching`. Because this API blocks the calling thread waiting for `tccd` before the main run loop (`[NSApplication run]`) spins, the app deadlocked during launch. Calls are now dispatched to a background utility queue (`DispatchQueue.global(qos: .utility).async`) and pre-flighted with `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` to prompt only for installed media players.

### Tests

- Test suite expanded to **7,043 checks OK** (up from 6,274, +769 checks). New coverage: probe record bounded FIFO buffer, precondition gate matrix rules, Super I/O family inference, ASCII report formatting, 13-language localized string contracts, driver table pins, Kaset JSON parser unit tests (playing, paused, 3-phase repeat, shuffle), invalid payload handling, and search routing.

## [1.35.0] — 2026-09-14 — kexts 3.34.17 (No kext changes)

Modular separation of Overclocking/PBO in Settings, Dashboard telemetry deduplication, clarification on effective frequency/parked cores, and sensor cleanup.

> **Kext Note**: This release introduces no changes to `AMDRyzenCPUPowerManagement.kext` or `SMCAMDProcessor.kext` (both remain on version 3.34.17 from the S11 drop). All changes are strictly within the macOS application layer (UI, presentation, and monitoring services).

### Added & Changed

- **Overclocking and PBO Separation in Settings**: Extracted all high-risk hardware controls (OC Mode master switch `0x5A` / `0x5B`, PPT/TDC/EDC limits and PBO scalar `0x57` / `0x58`, per-core Curve Optimizer offsets `0x3D`, all-core and per-CCD clock locking `0x5C` / `0x5D`, and cHTC thermal limit `0x56`) from `AmdPowerSettingsView` into a dedicated `AmdOverclockingSettingsView` page featuring a flame icon (`flame.fill`) in the Settings sidebar.
- **Telemetry Deduplication in the Dashboard**: In the Performance Suite (Dashboard), the 32-thread BTop CPU block is now automatically hidden whenever SMU-decoded telemetry (`pmTableDecoded`) is active, avoiding duplicate per-core usage and clock frequency metrics.
- **Effective Frequency & Parked State Clarification**: In the monospaced SMU PM-table view, cores in deep CC6 sleep are now explicitly labeled as `parked`, with technical documentation clarifying why effective clock rates drop to ~200 MHz or 0 MHz due to clock gating ($CORE\_FREQEFF = \text{Freq} \times C_0\%$).
- **Live Refresh Loop**: Implemented a periodic refresh loop (every 3 seconds) using `controls.syncFromKext()` in both the Overclocking panel and Power view to synchronize readings in the background without requiring navigation away from and back to the view.
- **Sensors View Cleanup**:
  - Removed redundant global GPU rows when discrete GPU devices are already mapped.
  - Deduplicated SMC keys `TG0D` / `TG0P` (retaining Hotspot `TG0H` and VRAM `TG0M`).
  - Removed forced 16-core synthesis on 6- or 8-core processors to accurately reflect detected physical topology.
  - Replaced the obsolete stress test section with a clean CSV export utility for SMC sensors.

## [1.34.0] — 2026-09-14 — kexts 3.34.17

Wave S11 release: Super I/O dual register map, duty cycle estimator, tachometer validity, fan-curve hardware safety floor & AIO pump protection. **Hardware validated on reference AMD Ryzen 9 5900XT / ASUS ROG Crosshair VII Hero (ITE IT8665E).**

Also new: `docs/SUPERIO.md`, which documents the Super I/O fan layer —
the two ITE register maps, how to tell a pump channel from a fan channel, why duty
and RPM come from different registers, and the hardware-validation rules.

### Fixed

- **Selector 94's rate-limit gate was unreachable, so `updateFanControl()` never
  ran at all.** Confirmed on a Ryzen 9 5900XT: before the fix all six channels
  reported `pwm 0 (0.0%)` while spinning at 40–1695 RPM; after it they report the
  firmware's real duty (49.8 %, 37.6 %, 20.0 %, 20.0 %, 20.0 %, 100.0 %), stable
  across five sampling runs.

  `OSIncrementAtomic` returns the pre-increment value, and `getFans()` calls
  selector 93 then selector 94 in one pass, so each pass consumed exactly two
  values from the single shared `fanUpdateCounter` and the parity each selector
  observed never changed. From a start of 0, selector 93 always read an even value
  and selector 94 always an odd one; the gate is `% 4 == 0`, which only an even
  value satisfies. Selector 94's branch was therefore dead from boot and
  `fanThrottles` was never written after initialisation — which is why the reading
  was an exact `0` rather than a stale or wrong duty. Fixed with a dedicated
  `fanCtrlUpdateCounter`.

  This supersedes the explanation recorded in the previous revision of this
  entry, which was wrong in two ways worth stating rather than quietly deleting.
  It blamed the estimator's inputs being stale, and it claimed separate counters
  would only "improve the cadence" and were not a correctness fix; separate
  counters *are* the correctness fix, and pairing the estimator's producer with
  its consumer could not help because the gate that pairing sits inside never
  ran. It also assumed the restored readings would come from the RPM/peak
  estimator. They do not: the duty stays fixed while RPM jitters by a few counts,
  which an estimate could not do, so the chip's duty register does hold the real
  value under SmartGuardian control — it simply was never read.

- **The ITE driver used one register map for four chips that need two.** Linux's
  `it87` driver carries `IT87_REG_FAN`/`IT87_REG_PWM` for IT8686E/IT8688E/IT8689E
  and `IT87_REG_FAN_8665`/`IT87_REG_PWM_8665` for IT8665E/IT8655E/IT8625E, and
  selects per chip. This driver had only the first, applied unconditionally.

  On an IT8665E that misread the sixth tachometer from `0x4c/0x4d` — registers
  that hold something else there — and, more seriously, made
  `overrideFanControl()` and `setDefaultFanControl()` **write** the control-mode
  byte of channels 3–5 into `0x7f/0xa7/0xaf` instead of `0x1e/0x1f/0x92`, i.e.
  arbitrary writes into EC registers of unknown function. Duty readings were
  unaffected on every chip because the duty table has no per-chip variant.

  Both tables are now present and three pointers are resolved in the constructor
  from the `chipIntel` value `getDevice()` already reads off the hardware, before
  the loop that snapshots the firmware's control-mode bytes through them. A chip
  that is not an IT8665E keeps byte-identical behaviour.

- **A duty commanded to a stopped rotor is now floored (selector 95).**
  `kCURVE_MIN_ACTIVE_PWM` lived only in `evaluateFanCurves()`, and
  `overrideFanControl()` writes whatever byte it is handed straight to the PWM
  register, so the privileged manual path could latch a rotor at duty 1–39 —
  below its start threshold, on an open-loop controller with no RPM feedback, and
  below 85 °C where the thermal guard does not fire. The floor is **not**
  unconditional, which is the substance of the change: the hazard is at rotor
  START, not at maintain, so a fan the BIOS is holding at duty 20 and which is
  demonstrably turning is left alone — raising it would only add noise, and a
  blanket floor would ramp every BIOS-fixed fan on the first poll, which is
  exactly what `AMDFanSafety.guardOnlyPWM` exists to prevent. The kernel now
  decides from evidence rather than from a caller's claim: it floors only when the
  tachometer is trusted *and* reports the fan below `kFAN_STOPPED_RPM` (100, the
  same threshold the estimator already uses). When validity is unknown, behaviour
  is unchanged.

### Added

- **`getFanRPMValid(int fan)` on the Super I/O interface.** `fanRPMValid[]`
  existed in both Nuvoton drivers but never left them, so neither the kext's own
  checks nor the app could distinguish a held-over stale reading from a fresh one.
  Declared on the base class with an inline default of `true`, so the ITE family —
  which tracks no validity — keeps its current behaviour exactly.
- **Selector 94 bit 1 now carries per-fan tachometer validity (kernel half).**
  Per fan, one `uint64_t`: bits 15:8 throttle, bit 0 auto mode, bit 1
  `rpmValid`, rest zero. Bit 1 was previously written as zero and the Swift reader
  masks only bits 15:8 and bit 0, so an **older app ignores it** and the buffer
  size is unchanged. This matters because the previous release made a dead sensor *less* detectable,
  not more: the drivers now hold the last good value rather than publishing 65535,
  so a dead tach shows a plausible frozen RPM, and the app's own
  `rawRPM <= 10500` heuristic can never fire because the kext already filters
  above that threshold. The app-side consumption is intentionally not included —
  a kext revision costs a hardware validation cycle and an app revision costs
  nothing, so the expensive half ships first.

### Validation status

Both kext targets build with `** BUILD SUCCEEDED **`, zero errors and zero warnings
from any file touched.

**Confirmed and hardware-validated on the reference 5900XT (ASUS ROG Crosshair VII Hero, ITE IT8665E Super I/O):**

- `kextstat` confirms live kernel execution of `wtf.spinach.AMDRyzenCPUPowerManagement (3.34.17)` and `wtf.spinach.SMCAMDProcessor (3.34.17)`.
- The duty path works: all six channels report real firmware/SmartGuardian PWM (127 [49.8 %], 96 [37.6 %], 51 [20.0 %], 255 [100.0 %]) across repeated sampling runs while RPM jitters.
- The IT8665E register-map fix is validated on silicon: tachometer 6 reads from `0x93/0x94`, reporting real AIO pump speed (~2884 RPM) and eliminating the false 40 RPM artifact.
- Selector 94 bit 1 carries tachometer validity, decoded and consumed in Swift (`fan.rpmValid`).
- Interactive fan curve editor enforces 16% (~15.7% / PWM 40) hardware safety floor matching `kCURVE_MIN_ACTIVE_PWM` to prevent rotor stalls.
- Dedicated `BOMBA` / `PUMP` badge and warning banner for AIO liquid pump headers in `FanControlCard`.
- `MenuPanelView` decomposed and isolated to `@MainActor`, eliminating Swift 6 expression typechecker timeouts.
- Prebuilt release zip `ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip` refreshed with 3.34.17 binaries and all 4 content SHA pins updated in `Tools/make-dmg.sh`.

## [1.33.0] — 2026-09-12

### AMD Kernel + App: thermal fail-safe & IOKit lifecycle hardening
- **Kernel thermal safety**: the fan-curve EMA now validates every temperature sample on input and output against the plausible Zen window (`kTEMP_INVALID` sentinel; NaN used to be absorbing *and* permanent, pinning the fan at the coldest LUT point with the 85 °C guard disarmed). A per-curve trust flag forces **kFAILSAFE_PWM (160)** when no trustworthy reading exists this tick, instead of trusting an absent value. The emergency thermal guard is now **system-wide** — armed from the hottest trustworthy sensor, so a GPU-sourced curve can no longer hold a 95 °C CPU at the GPU curve's low duty. PWM 0 keeps its release-to-BIOS meaning, but any other request below **kCURVE_MIN_ACTIVE_PWM (40)** is raised to the floor (an open-loop duty below the rotor start threshold silently stalls the fan). The floor is applied before the guard so the guard always wins.
- **Dead-man switch**: `clientClose()` now hands every fan back to BIOS/SmartFan control under `superIOLock` — the only kernel callback guaranteed to run on SIGKILL/crash/force-quit, which the app's `applicationWillTerminate` path never reaches. A crash with a fan latched at ~1 % duty left it there indefinitely before.
- **Temperature sentinel hygiene**: `getPackageTemp()` returns `kTEMP_INVALID` instead of an ambiguous 0.0 °C (0 °C selected the coldest LUT row *and* made every `>= 85 °C` guard test false); the ring-buffer fill paths keep the previous sample rather than averaging the sentinel into `PACKAGE_TEMPERATURE_perPackage[0]`.
- **SuperIO validation**: both NCT67XX and NCT668X validate every tachometer word (0xFFFF / torn reads / out-of-range hold the last good value instead of publishing 65535 RPM), and the peak-RPM high-water mark only records plausible values — one bad read used to permanently pin the Auto-mode PWM estimator near 0 %. `readWord` on NCT67XX is tear-resistant (index re-checked after the low-byte write).
- **kext IPC hardening**: every external selector runs through one centralized validation gate (capacity/sanity checked before dispatch) in `AMDRyzenCPUPMUserClient::externalMethod`.
- **Kexts 3.34.14, shipped with hardware validation incomplete**: the kernel thermal-safety and SuperIO changes touched kernel code, and the packaged kexts move to **3.34.14** (`ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip`, SHA-256 repinned to `34ca0194…a85be08c`). Hardware validation on the reference 5900XT covered two of the four mandatory validation steps: `kextstat` confirmed 3.34.14 loaded, and the dead-man switch passed (`pkill -9` with a fan in manual produced `clientClose released 6 fan(s) to BIOS control`, and the fan returned to its BIOS idle). **The remaining two probes were not run**: the curve floor under a 1 % idle anchor, and the emergency guard armed from a GPU-sourced curve with the CPU above 85 °C. Those two behaviours therefore ship as reviewed code that has not been observed on silicon. If you run a custom fan curve on this build, watch your temperatures on the first boot.

### Packaging
- **The DMG's `Kexts/` folder was empty since 3.34.13**: `AMDRyzenCPUPowerManagement-Kexts.zip` was refreshed with only the driver — `SMCAMDProcessor.kext` was left out entirely. Because the plugin's extracted path did not exist, the packaging guard fell through to `(Kexts not built — skipping)` and produced a DMG with **no kexts at all**, two lines after printing `Prebuilt AMD kexts verified` and still exiting 0. No published release was affected (v1.31.0 predates the bad zip and carries both kexts at 3.34.12), but this release would have been the first to ship without them. The zip now contains both kexts, and packaging reports the version staged plus whether it came from the SHA-verified zip or an unverified local build.
- **DMG window layout no longer depends on Finder Automation**: icon positions and the background came solely from an AppleScript that needs Apple Events permission for Finder, and a shell without that grant produced an unstyled DMG while still exiting 0. The layout is now seeded from a checked-in `.DS_Store` that `hdiutil` bakes in beforehand, so the AppleScript is a refinement rather than the only path. Release and CI builds were unaffected — their runners can drive Finder.

### Fixed
- **Off-main kext IPC**: fan-curve uploads now coalesce on a detached task with `withHandle` handle checking instead of every mutation calling selectors inline; the hub's fan timer runs on `.common` mode so uploads survive Menu tracking; a sleep/wake observer re-syncs curves after wake; a stale-handle read heals with one immediate reconnect attempt instead of waiting for the next full refresh; `AutoEppService`/`C6ResidencyService` polling loops stop when the monitor deallocated (`self == nil` guard).
- **rpmValid telemetry**: the kext no longer launders implausible tach words (`min(rpm, 9999)` turned garbage 65535 into a believable 9999). `FanSnapshot`/`FanState` carry an explicit validity flag; the kext holds the last good value instead. `FanSnapshot`/`FanState` carry a validity flag and the fan row is ready to render "— RPM", but note the honest limitation: the kext's per-fan validity flag is internal to the SuperIO drivers and is not yet propagated across the IOKit boundary, so the app-side `rpm <= 10500` heuristic never trips in practice — a dead sensor currently shows a frozen but plausible RPM rather than an obviously wrong 65535. Propagating the flag through selector 94 (bit 1 is free) is tracked for the next wave.
- **Manual-mode duty floor raised 3 → 40**: closes the asymmetry with the kernel's curve-mode floor — the manual slider could previously command PWM 3 (~1.2 %), which stalls a rotor exactly like the bug the kernel floor fixed. `AMDFanSafety.minimumManualPWM` is now 40 and is enforced where the **user** commits duty (`setManualPWM`'s `clampManualPWM`, slider range). Hardware-**inherited** duty is exempt on purpose: the enforcement loop now applies `guardOnlyPWM` (emergency guard only, no floor) because `manualPWM` seeds from the Super I/O's current setpoint — typically a fixed BIOS duty that may legitimately sit below 40, and ramping those up on the first poll would make every update noisier with no safety gain (stall risk is at rotor start, not maintain). The slider starts at 40 while its numeric readout tracks the real duty, with a source comment pinning the intentional divergence.
- **Status-item rendering**: theme-change rebuilds only run when the theme actually changed; NowPlaying title measurement is memoized against repeated identical `NSImage(size:)` work.
- **Dashboard occlusion flag**: dashboard-open tracking uses a boolean flag (the `panelDidAppear/Disappear` refcount never reached zero while the dashboard was open, so the optimization never applied).
- **Deferred mixer process tracking**: the mixer's resident-without-use energy cost is gone — the per-app process machinery (process-list global listener + one `IsRunningOutput` listener per live audio process) now stays **dormant** until it has a purpose: it activates automatically when saved per-app state exists (its re-apply needs the tracking), or on demand the first time the mixer panel opens (`ensureProcessTracking()`, idempotent). A clean install with no saved state and no panel visit runs only the lightweight device half (output picker, headphone protection) — no process listeners at all.
- **`.screenRecorder` feature binding**: disabling the feature via preset/backup-import/reset now actually tears the service down (binding existed only in the Settings path before).
- **Auto EPP now survives sleep**: `AutoEppService` was the only AMD service with no wake handling. It skips the MSR write whenever the target EPP equals the last written value — correct in steady state, but if the SMU lost the EPP across a suspend while the target was unchanged, the write was skipped forever and the EPP silently stayed at the firmware default until the user happened to change presets. A `didWakeNotification` observer now clears the dedup sentinel so the next poll re-asserts it.
- **`--sensors` reports AMD telemetry**: the diagnostic dump only read AppleSMC `Tp`/`Te`/`Tg` keys, which VirtualSMC does not populate on an AMD system — so the command printed nothing but its header on exactly the hardware the app targets, despite being documented alongside `--selftest` as a troubleshooting tool. It now dumps the kext's own selector-100 packet first and unconditionally (package power and temperature, per-CCD temperatures, per-core effective clocks) plus per-fan RPM and duty, and the AppleSMC section is no longer fatal when unavailable. Physical core clocks are de-duplicated under SMT: the kext fills `coreFrequenciesMHz[]` indexed by logical core but sources every entry from the physical core, so a 16C/32T part previously listed 16 phantom duplicates.
- **Post-wake CPU sample**: `SystemMonitor` computes CPU utilisation as a delta between consecutive tick samples, and those bases were stale across a suspend — the first post-wake sample was computed over the entire sleep interval. The bases are now dropped on wake, which skips that one sample instead of reporting a meaningless value.
- **Tests**: suite grew to **6274 checks OK** (manual-floor vectors updated to 40 + 3 new `guardOnlyPWM` rules); `./build.sh` completes with **0 warnings** and `--selftest` OK, keeping the repo's warning-free contribution contract intact.

## [1.32.0] — 2026-09-12

### AMD Kernel + App: on-demand mailbox health diagnostics
- **New selector 58 (privileged)**: runs the kext's boot-diagnostic probes on demand — SMN aperture (raw Tctl word through the PCI 0x60/0x64 window), TestMessage echo (0x01, arg 0x42 must return 0x43) and `GetSMUVersion` (0x02) — and returns the full 48-byte raw report (all response codes, arg-window words and per-probe elapsed times) through structure output. Privileged because it adds real SMU mailbox traffic on demand (same policy as the selector-57 force-recapture); serialized under `rendezvousLock` like the capture path, `smuCmdLock` stays the inner leaf. Wire layout is pinned by a kernel `static_assert` and a fail-closed app-side size check.
- **Diagnostics bundle button** in the SMU PM Table section: runs the probes and copies a paste-able ASCII bundle (app/kext versions, SMU firmware, PM-table state, mailbox health lines, boost/scalar/OC caches) for bug reports — no more asking users to run `log show`. The rendered health lines appear under the button (green when all three probes pass, orange with the failing probe named otherwise), with a localized privilege-denied hint. Button/copy/denied strings added across all 13 locales.
- **Kexts rebuilt at 3.34.13** (kernel changes: selector 58 dispatch in `AMDRyzenCPUPMUserClient`, `runMailboxDiagnostics` on the provider, no changes to any existing command path). `ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip` refreshed and its SHA-256 repinned in `Tools/make-dmg.sh` (`93c88a22…63abced`).
- **Tests**: wire round-trip vectors (exact 48-byte layout, short/oversized buffers fail closed), per-probe verdict rules (echo mismatch, SMN aperture 0xFFFFFFFF, timeout/FAILED codes all flip the verdict), response-name decode for every documented SMU return value, string invariants ×13, and kernel-side source pins (privilege gate, wire static_assert, rendezvous serialization). Suite grew to **6271 checks OK**; strict-concurrency gate 0 diagnostics.

## [1.31.0] — 2026-09-12

### AMD App: L3 decode + SMU-native value promotion
- **L3 (GameCache) telemetry decoded** from the PM-table snapshot: per-cache effective clock, temperature, logic/VDDM power and EDC limit, from the `pm_tables.c` L3 tail blocks (0x380805/0x380804: 2 caches; 0x380904/0x380905: 1). Every layout's documented minimum size already bounds the L3 block, so the existing fail-closed size gate protects it; provenance kept honest — the two upstream-tested maps are hardware-validated against the live 5900XT fixtures, the 8-core maps stay synthetic-tested until a silicon capture lands. GameCache clocks are stored in GHz like core clocks and scale ×1000.
- **SMU-native promotion (the goal was: computed estimates give way to SMU values)**: `ProcessorModel` is now the **single owner** of the PM-table fetch+decode, refreshed on the telemetry tick into a thread-safe cache with a 6 s freshness gate (a stopped kext timer cleanly falls back to the old path). `lastCPUPowerWatts` prefers SMU SOCKET_POWER while fresh — menu bar and panel package power now come from the SMU itself instead of the kext-computed selector-100 estimate. The PM-table's per-core CORE_FREQEFF is deliberately **not** promoted into the SystemMonitor core snapshot: it is a window average (a CC6-parked core decodes to single-digit MHz) and would corrupt every current-clock aggregate — the Settings min/max/avg rows, the popover CPU card, the menu bar avg/peak and the IPS estimate; true per-core SMU clocks remain in the per-core disclosure and the dashboard grid, which render them with sleeping-core semantics. CPU temperature deliberately stays on its existing instantaneous sources: the PM table's PEAK_TEMP is a window peak, not an instantaneous reading.
- **Settings**: the SMU PM Table section renders an L3 row per cache (clock, temp, logic+VDDM power, EDC limit) under the same monospace technical-label convention.
- **Menu panel**: the per-core disclosure gains one compact L3 row per cache (clock/temp/power, full fields on hover) sized to the audited 308 pt row budget.
- **Dashboard**: the Performance Suite dashboard gains an "SMU Telemetry (PM Table)" section — socket-power and package-temperature cards with trend charts (domain scaled to the PPT limit), a fabric-clock card (FCLK/UCLK/MEMCLK), and a 4-column per-core effective-clock grid fed by the same single-owner decode on the shared 3 s sync. One new localized key across all 13 locales; the section hides entirely on old kexts or undecodable table versions.
- **Core grid, reinvented (UI alignment wave)**: the classic per-core load card in the menu panel gains a persisted metric mode — LOAD (the classic cyan→purple fill, byte-for-byte unchanged), or MHz / °C / W rendering true per-physical-core SMU cells with fixed scales (5.4 GHz / 100 °C / 25 W ceilings) so cells stay comparable; sleeping cores render flat and dim. The mode switch appears only while the SMU table decodes and cleanly falls back to LOAD otherwise. The dashboard's per-core grid gains the same voltage / C0 / CC6 column toggles as the panel disclosure, sharing the same persisted keys — both surfaces stay in sync.
- **Tests**: synthetic L3 vectors for all four versions (both cache counts, exact elements, GHz→MHz scaling), live-fixture L3 pins (cache temps/clocks/EDC on both 5900XT captures), freshness-gate boundaries, and the promotion/mapping contract. Suite grew to **6172 checks OK**; strict-concurrency gate 0 diagnostics. App-only wave — kexts unchanged at **3.34.12**, no zip/SHA churn.

### Fixed
- **Menu popover no longer flips beside the icon** when tall content hits the panel's scroll cap (SMU per-core disclosure, iStats chart editor — any capped content). The height budget now subtracts the real chrome: 40 pt margin, outer panel padding inside the section accounting — a capped window always fits the visible frame.
- **Frequency aggregates keep current-clock semantics**: the SMU PM-table's per-core CORE_FREQEFF is a window average (a CC6-parked core decodes to single-digit MHz), and an earlier draft promoted it into the core snapshot, feeding impossible values (1/894/339 MHz) to the Settings min/max/avg rows, the popover CPU card, the menu bar avg/peak and the IPS estimate. The core snapshot keeps the kext metric array; per-core SMU clocks render where sleeping-core semantics exist. A source-pin test fails the build if the override silently returns.

## [1.30.0] — 2026-09-11

### AMD Kernel: SMU PM-table plumbing
- **The kext now snapshots the SMU's own PM table** — the same metrics table ryzen_smu and HWiNFO read — through the documented Vermeer RSMU sequence: `GetPMTableVersion` (0x08, one-shot static read), `TransferTableSmu2Dram` (0x05, Arg0=0, the SMU copies the table to DRAM) and `GetDramBaseAddress` (0x06, Arg0=1/Arg1=1, 64-bit base assembled as `arg0 | arg1<<32` via a new two-argument mailbox variant `smuSendCmd2`). The whole cycle runs on the main timer's command gate, throttled to one transfer + re-map check per second.
- **Read-only, snapshot-only**: the kext maps the SMU-provided physical region read-only with a short-lived `IOMemoryDescriptor` mapping, copies it into a fixed 0x2000-byte buffer and unmaps immediately — nothing persists, and nothing in this path writes to SMU-controlled memory. Table size comes from a per-version fail-closed table (10 documented Vermeer/Chagall versions, 0x594…0x1BB0 bytes); unknown versions refuse the mapping entirely rather than guess a size.
- **Selector 56 (non-privileged)** reports the cached diagnostics: table version word, size, 64-bit physical base, snapshot validity, snapshot age and the CCD count. **Selector 57 (structure method)** reads the raw snapshot bytes chunked (app chooses chunk ≤ 0x1000) and supports a force-recapture op that runs one immediate capture cycle on the command gate.
- **App**: new “SMU PM Table” diagnostics section — version rendered BCD-style (e.g. 38.09.04), documented size or a localized “unknown version” row, physical base address, snapshot age, and an **Export snapshot…** button writing the raw bytes through NSSavePanel for bug reports and offline analysis. Version-decode helpers are unit-tested.

### AMD App: SMU PM-table decode + per-core telemetry
- **The app now decodes the captured PM table** into live telemetry: package metrics (PPT/TDC/EDC/THM limits and values, VID, socket power, FCLK/UCLK/MEMCLK, peak temp, PC6) and per-core rows (effective clock, temperature, power, C0/CC6 residency). Layout family from hattedsquirrel `pm_tables.c`: **0x380805** (16-core Vermeer, hardware-validated against two live 5900XT captures committed under `Tests/Fixtures/PMTable`), plus **0x380804 / 0x380904 / 0x380905** (old-head and 8-core siblings, proven by synthetic-capture tests at the documented elements). Fail-closed: versions without an authoritative public map (0x380705 among them) stay undecoded — a negative-control test pins that, so the app never guesses telemetry offsets.
- **Menu panel**: the AMD Power section gains a “Per-Core Telemetry (SMU)” disclosure — per-core clock/temperature/power rows with rolling 3-minute sparklines fed by the existing 3 s sync (no new timers, no extra kext traffic), an at-a-glance package summary while collapsed, and per-field column toggles (voltage, C0, CC6) persisted to defaults. Row width budget audited against the 308 pt panel: every optional column combination fits without wrapping.
- **Settings**: the SMU PM Table diagnostics section now renders the decoded package metrics and per-core rows next to the raw-hex export flow.
- **Regression pins**: the unit-test suite reads the kernel C++ sources at test time and fails the build if the on-hardware fixes ever silently regress — Vermeer RSMU mailbox registers (0x3B10524/0x3B10A40/0x3B10570), the `kIOMapAnywhere` mapping flags, and every entry of the fail-closed PM-table size table. Suite grew to **6131 checks OK**.

### Packaging
- Kexts rebuilt at **3.34.11**: fixes the Vermeer RSMU mailbox registers (response 0x3B10570, args 0x3B10A40 — response/args were mis-pinned, so every SMU command silently timed out) and adds `kIOMapAnywhere` to the PM-table kernel mapping (a fixed map at address 0 always failed → rc -15). Adds a boot-time `[SMU Diagnostic]` one-shot probe, per-command elapsed-time instrumentation, and failure logging across all SMU pollers and the PM-table capture. Verified on hardware: SMU version 0x384c00, ProcessorParameters 0x3, boost 4950 MHz, PM-table version 0x380805 (2288 B). `ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip` refreshed and its SHA-256 repinned in `Tools/make-dmg.sh`. App 1.30.0 (70).
- Refreshed again: kexts rebuilt at **3.34.12** (same on-hardware-verified fixes; version bump only, so the fixed load is unambiguous in `kextstat`), `ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip` re-signed with SHA-256 `cd14787b…cf81de6` repinned in `Tools/make-dmg.sh`. App 1.30.0 (71).

### Packaging (1.31.0)
- App **1.31.0 (74)**; kexts unchanged at **3.34.12** (app-only release, no kernel changes — the EFI kexts from 3.34.12 keep working).

## [1.29.0] — 2026-09-11

### AMD Kernel: SMU frequency overrides behind the OC gate
- **All-core frequency override**: privileged **selector 51** programs an absolute core-clock target through the Vermeer RSMU `SetOverclockFreqAllCores` command (0x5C, `freq & 0xFFFFF` MHz). The kernel validates the 400…8000 MHz envelope (doc MIN/MAX), and — new for phase 2 — **refuses unless this driver enabled OC mode itself earlier this boot** (`kIOReturnNotPermitted`): the kext only sends frequency writes after observing its own 0x5A succeed, so an OC gate opened by the BIOS or another tool never silently unlocks this path. Same thermal interlock and mapped-error policy as every write selector.
- **Per-CCD frequency overrides**: `SetOverclockFreqPerCore` (0x5D) with the pinned Vermeer mask `(ccd << 28) | ((core % 8) << 20) | freq` — which collapses to `(ccd << 28) | freq` because Vermeer has one CCX per CCD and the CCX-uniformity rule makes the CCD the SMU's real frequency granularity. The UI therefore presents **CCD rows**, not per-core sliders that would all write the same value. One mailbox round trip per CCD; a mid-sequence failure leaves earlier CCDs programmed and the cache tells the truth. The kernel builds the mask — user space never ships packed masks.
- **Selector 52 (read-only)**: the frequency-override cache — all-core plus per-CCD values last programmed by this driver this boot (0 = never written; the SMU has no read-back). Also reports the kext's start-time CCD count so the UI sizes its rows from real silicon topology.
- **Selector 49 [3] promoted** from reserved-0 to the frequency-override support flag — a compatibility-safe change: 1.28.0 apps read 0 and hide the new section; 1.29.0 apps read 1.
- **Settings UI**: a new "Frequency Override (SMU)" section directly under Overclocking Mode — all-core slider (400–8000 MHz, 25 MHz steps) + per-CCD sliders, each with its own Apply, drafts seeded once from the kext cache (PBO-draft pattern), and a cache read-back footer carrying the verification-loop hint: watch the Boost Telemetry row — the SMU's reported max frequency (0x6E) should follow your target. Controls render only when OC mode reads *enabled*; otherwise a localized "Enable OC mode first" guidance row (the kernel re-checks regardless).
- **13-locale sweep** for the new section, with format-specifier invariant tests; the strict-concurrency gate stays at 0 diagnostics.
- Kexts rebuilt at **3.34.7**; `ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip` refreshed and its SHA-256 repinned in `Tools/make-dmg.sh`. App 1.29.0 (68).

## [1.28.0] — 2026-09-11

### AMD Kernel: OC-mode gate + hardware-risk warnings
- **Overclocking Mode master switch**: the kext now drives the Vermeer RSMU OC-mode gate — `EnableOcMode` (0x5A) / `DisableOcMode` (0x5B), semantics pinned by two independent sources (the public-record command table and irusanov/ZenStates-Core, which untangled the doc's contradictory rows). **Selector 49** returns an OC capability report (fused overclocking bit from the 0x6F read, OC-mode cache and its state); privileged **selector 50** enables/disables the gate behind the same root/`-amdpnopchk` + 75 °C thermal interlock as every other write. The SMU has no read-back for the gate: the state row reflects the kext's write cache, and disabling optionally resets the PBO scalar to 1.0x (some SMU firmware does not do it automatically — documented ZenStates-Core quirk).
- **Frequency (0x5C/0x5D) and VID (0x61) writes are deliberately absent** — they land only after this gate is validated on real hardware (encodings already pinned by research).
- **Hardware-risk disclaimer**: AMD Power Settings now opens the SMU write area with a red warning banner that names the real stakes — overclocking, voltage and power-limit changes can permanently damage or kill the CPU, motherboard or memory, and the authors take no responsibility for damaged hardware (nor for anything else, including alien invasions). Enabling OC mode additionally requires an explicit confirmation dialog accepting responsibility. All 13 locales.
- **13-locale sweep** for the new strings, with format-specifier invariant tests; the strict-concurrency gate stays at 0 diagnostics.
- Kexts rebuilt at **3.34.6**; `ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip` refreshed and its SHA-256 repinned in `Tools/make-dmg.sh`. App 1.28.0 (67).

## [1.27.0] — 2026-09-11

### AMD Kernel: SMU firmware version + active scalar readback
- **SMU firmware version diagnostics**: the kext's command-gate timer performs a one-shot read of the global `GetSMUVersion` command (0x02 — per the public record, "consistent with all platforms"). **Selector 47** exposes the raw byte-packed version word plus a "polled" flag; the app decodes it in the unit-tested `AMDSmuReadback.formatSmuVersion` helper (24-bit `A.B.C`, or 32-bit `A.B.C.D` when byte 3 ≠ 0 — the same rendering the reference libsmu uses). The version shows as a diagnostics row in AMD Power Settings for the bug-report workflow.
- **Active PBO scalar readback**: the timer also polls the Vermeer RSMU `GetPBOScalar` command (0x6C) inside the boost-telemetry throttle window. **Selector 48** exposes the raw response — an IEEE-754 float in the 1.0–10.0 range (a different encoding than the 0x58 write!) — decoded app-side in `AMDSmuReadback.formatActiveScalar`. This is what the SMU itself reports as active, complementing the 0x58 write cache in the PBO section with real drift detection; out-of-range words refuse to render rather than invent a value.
- Both selectors are read-only and served exclusively from the timer cache — user-space reads never touch the SMU. All 13 locales carry the two new rows; format-specifier invariant tests extended.
- Kexts rebuilt at **3.34.5**; `ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip` refreshed and its SHA-256 repinned in `Tools/make-dmg.sh`. App 1.27.0 (66).

## [1.26.0] — 2026-09-11

### AMD Kernel: cHTC thermal limit + fused capability bits
- **cHTC limit control**: the kext now programs the package cHTC thermal limit via the Vermeer SMU `SetcHTCLimit` command (0x56, Arg0 = °C), behind the same capability gate and 85 °C package-temperature interlock as the PBO limits. New privileged **selector 46** validates the target into a 40…95 °C window (Tjmax on Vermeer); **selector 45** reads back the last value programmed this boot — the SMU has no read command for cHTC, so the kext caches on write success, exactly like the PBO limits.
- **ProcessorParameters capability bits**: the command-gate timer performs a one-shot read of the Vermeer RSMU `GetProcessorParameters` command (0x6F) — static silicon configuration, never re-issued after the first successful answer. **Selector 44** exposes the raw bitfield (bit 0 IsOverclockable, bit 1 PBO support) plus a "polled" flag, so a genuine 0-bitfield is distinguishable from "not read yet". The word is cached raw and decoded app-side in the unit-tested `AMDSmuParameters` helpers; any undocumented bits surface as raw hex instead of being silently dropped.
- **Settings UI**: a new "cHTC Thermal Limit (SMU)" section in AMD Power Settings with the slider/apply/status flow shared with the PBO controls, an applied read-back row, and fused-capability badges (overclocking unlocked, PBO support). Fail-closed banners for Zen 4 and non-Vermeer silicon.
- **13-locale sweep** for the new section, with format-specifier invariant tests; the strict-concurrency gate stays at 0 diagnostics.
- Kexts rebuilt at **3.34.4**; `ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip` refreshed and its SHA-256 repinned in `Tools/make-dmg.sh`. App 1.26.0 (65).

## [1.25.0] — 2026-09-11

### AMD Kernel: SMU boost telemetry
- **Max boost frequency & fastest core, straight from the SMU**: the kext's command-gate timer now polls the Vermeer RSMU read commands documented in the public record — `GetMaxFrequency` (0x6E) and `GetFastestCoreOfSocket` (0x59) — through the same mailbox the kext already drives. Results are cached kernel-side; user-space reads never touch the SMU (same off-the-hot-path policy as the 1.20.0 GPU fix).
- **New read-only selector 43**: returns the cached max boost frequency in MHz, the raw 0x59 response word, and a "cache valid" flag. The 0x59 word is decoded app-side in the single, unit-tested `AMDSmuBoost.decodeFastestCore` helper — the public record's decode expression is ambiguous, so the kext caches the raw word and refuses to guess.
- **Settings UI**: a new "Boost Telemetry (SMU)" section in AMD Power Settings shows the silicon's own max boost clock and which physical core is currently hitting it, refreshed every 3 s with the rest of the control sync. A fail-quiet placeholder row shows while the kext cache is cold (first poll after boot); undecodable raw words render as hex instead of a wrong core number.
- **13-locale sweep** for the new section, with format-specifier invariant tests; the strict-concurrency gate stays at 0 diagnostics.
- Kexts rebuilt at **3.34.3**; `ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip` refreshed and its SHA-256 repinned in `Tools/make-dmg.sh`.

## [1.24.0] — 2026-09-11

### AMD Kernel: Precision Boost Overdrive Limits
- **Precision Boost Overdrive (PBO) limits & scalar control**: added kernel-level support for adjusting PPT (Package Power Tracking in mW), TDC (Thermal Design Current in mA), EDC (Electrical Design Current in mA), and PBO Scalar (1.0x–10.0x) on AMD Zen 3 Vermeer CPUs via RSMU commands (`0x53`, `0x54`, `0x55`, `0x58`).
- **UserClient selectors 40, 41, 42**:
  - Selector 40: reports PBO capability, safe envelopes, and cached values.
  - Selector 41: writes PPT/TDC/EDC limits with privilege verification (`hasPrivilege`), hardware bounds validation (1–500 W / 1–500 A), and emergency thermal interlock (writes blocked if package temp > 85 °C).
  - Selector 42: writes PBO Scalar with privilege validation and 100–1000 range verification.
- **Settings UI & Safety UX**:
  - Dedicated PBO configuration section in AMD Power Settings with safety confirmation toggle, interactive sliders for PPT (W), TDC (A), EDC (A), and Scalar multiplier.
  - Read-back telemetry showing currently active limits and fail-closed banners on unsupported CPUs (Zen 4/5 APUs and legacy pre-Zen 3 models).
  - Complete 13-language localization sweep with string invariant tests.
- **Driver packaging & SHA repin**: rebuilt `AMDRyzenCPUPowerManagement.kext` and `SMCAMDProcessor.kext` (v3.34.2), updated `ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip`, and repinned the expected SHA-256 in `Tools/make-dmg.sh`.

## [1.23.0] — 2026-09-11

### AMD Kernel & Concurrency
- **Zero `nonisolated(unsafe)` in the kext bridge**: all six unsafe actor-isolation escape hatches in `ProcessorModel` were replaced with lock-guarded boxes in the project's established `PowerCache` pattern — an atomic `ConnectBox` for the IOKit handle (per-call handle snapshot in every kext call), a `WatchdogBox` for the reload-reconnect task, an `IdentityCache` for the About-panel kext version and baseboard strings, and a `FavoriteThreadsCache` for the menu-panel core-grid badges. The strict-concurrency gate remains at zero diagnostics; behavior is unchanged.
- **Curve Optimizer capability report (new read-only selector 35)**: the kext — not the app — is now the single source of truth for whether Curve Optimizer writes are accepted, exposing {supported, active SMU command ID, safe offset range}. The settings UI gates on this report first and only falls back to the app-side family/model check on pre-1.22 kexts. Curve Optimizer behavior is unchanged on Vermeer (Zen 3) and stays fail-closed on Zen 4/5; a future kernel-side enablement will no longer require an app update. New tests cover the selector's sign-extension decode of the offset range.
- Under the hood: this wave also fixed a latent kext-build breakage in the selector-34 access path by promoting the SMU-mailbox capability accessors to public members.

## [1.22.0] — 2026-09-10

### AMD Kernel: configurable deep C-States (`amdcstate`)
- The kext no longer hardcodes `0xF0` into MSR `0xC0010073` on every boot. The `amdcstate` boot-arg now decides: `amdcstate=0` keeps deep C-states (C6) enabled for power saving; `amdcstate=1` or absent disables C6 for low wake latency (previous behavior). Resolution is logged via `IOLog` at start.
- **New read-only selector 34** exposes the resolved C-state policy (`disableCStates` + raw `cstateAddrConfig`) to userspace; the app falls back to the legacy selector 22 on older kexts.

### Fan safety, now visible
- **Emergency thermal guard surfaced in the UI**: when the CPU reaches 85 °C in manual mode and the kext clamps the fan to ≥78%, the fan card now shows an orange warning instead of the slider silently snapping. A persistent caption explains the 1% (PWM 3) floor that prevents rotor stalls.
- **Kernel defense-in-depth**: the kext's UserClient fan-PWM write path (selector 95) now applies the same 85 °C → PWM 200 clamp for every caller, not only curve-mode fans.

### AMD UI & layout fixes
- **Menu panel**: the AMD section's stale height estimate (110 pt vs the real ~580 pt) no longer clips/jumps on first open; AMD got its own `cpu.fill` icon (no longer colliding with System); the fan picker no longer truncates hardware names; the 3 s SuperIO RPM poll now only runs while the fan disclosure is expanded; one-tap power presets are disabled while Auto EPP is active so the two systems stop fighting over EPP.
- **Settings**: the AMD GPU telemetry row no longer crams GPU name, power and temperature into one competing HStack; sparklines for package power and temperature (60-sample, 3-minute history) were added to the AMD panel section; both telemetry sections now label their source (SystemMonitor vs direct kext selector-100 packet); the Deep C-States row shows the **runtime kext policy** and warns in orange when NVRAM intent and the running kext disagree (e.g. old kext ignoring `amdcstate`).
- **Sensors**: "Export sensor dump" now really exports the full SMC dump as CSV; the never-implemented "Start verification" dead button was removed.

### Localization
- ~45 previously hardcoded English strings across the AMD settings view, the AMD panel section, and the Settings sidebar ("Fans & Cooling", "Sensors", "AMD Ryzen Power") are now localized across all 13 app languages, with new non-emptiness invariant tests.

## [1.21.0] — 2026-09-05

### Homebrew
- **Source-build warning in the operation panel**: the streamed brew log is now watched for the signals Homebrew actually prints while compiling (no-bottle and Tier 3 notices, raw clang/make/cmake lines). The moment a formula starts building from source, the operation status shows a sticky warning — the usual explanation for an update that sits at full CPU for hours on bottle-less Macs (Intel / older macOS tiers).
- **Skip heavy formulas for Update All** (new toggle, on by default, persisted): a plain `brew upgrade` silently compiles known giants (node, llvm, gcc, python, openjdk, rust, cmake, boost, protobuf, openssl). Update All now upgrades outdated formulas through one explicit command that leaves those out (casks still included); when only heavy formulas are pending, it just refreshes. Localized for all 13 languages.

## [1.20.0] — 2026-09-05

### AMD Kernel Extensions & Audit Remediation (v3.34.2)
- **GPU telemetry off the hot path**: the SMC plugin's `RGPUTempValue`/`RGPUPowerValue` keys and the UserClient GPU selectors (28/29) now serve the provider's cached snapshot instead of issuing live SMU-mailbox reads. The old path could busy-wait up to 100 ms holding `gpuLock` **on any process's thread** that merely read the SMC key.
- **User-client task lifetime**: `AMDRyzenCPUPMUserClient` now retains its owning task (`task_reference`/`task_deallocate`), closing the use-after-free window in per-call privilege re-validation.
- **Zero-initialized GPU outputs**: selectors 28/29 no longer copy uninitialized stack bytes to userspace when a per-GPU read fails.
- **Per-core C6 residency (new selector 32)**: the kext now exports per-logical-core idle residency derived from its existing per-CPU accounting; `C6ResidencyService` publishes a per-core snapshot on the same cadence as the package metric.
- **Kext reload self-healing**: the watchdog now detects a reloaded kext service, reopens the user-client connection, re-runs initialization and posts `KextReconnected` — previously the app stayed degraded until a manual restart.
- **Kexts rebuilt from audited sources at 3.34.2** and bundled in the DMG.

### App Concurrency & Correctness
- **Thread-safe kext connection checks**: replaced all 6 external `connect != 0` reads with the lock-guarded `isConnected` accessor across `AutoEppService`, `FanCurveController`, `AmdPowerControlsModel`, and `AmdPowerSettingsView`.
- **Blocking kext IPC off MainActor**: `C6ResidencyService.poll()` now wraps the kext read + uptime timestamp in `Task.detached`; `AmdPowerControlsModel.syncFromKext()` batches 5 IPC calls in a single detached task with re-entrancy guard.
- **Fan picker hardware names**: menu-panel fan picker now shows hardware-reported or user-custom fan names via `getFans(includeNames: true)` instead of synthesized "Fan N" labels.
- **GPU temperature doc comment**: corrected `getKextGPUTemperatures()` doc comment — kext selector 28 returns integer °C directly, not SP78 fixed-point.
- **`closeDriver()` wired into termination**: `ProcessorModel.shared.closeDriver()` is now called from `applicationWillTerminate` as the final kext teardown step, ensuring the watchdog task is actually cancelled and the IOKit connection is closed cleanly on quit.
- **Sendable conformances** (strict-concurrency): `TerminationState`, `PowerCache`, and `GPUCache` are now `@unchecked Sendable`; `IOAcceleratorCache` now returns a `GPUStatsSnapshot` wrapper instead of bare `[String: Any]`, eliminating all 20 AMD-layer diagnostics under `-strict-concurrency=complete`.
- **AMD concurrency ratchet gate** (`Tools/concurrency-gate.sh`): new CI step enforces zero strict-concurrency diagnostics in the AMD layer; added to `.github/workflows/ci.yml`.
- **C6 residency + snapEPP unit tests**: `C6Sampling` pure-math enum extracted from `C6ResidencyService`, registered in the `--test` build list, and covered by 20 new checks (first-sample, counter-reset, normal delta, clamp, no-counter, and EPP bucket edges).

## [1.18.0] — 2026-09-03

### AMD Kernel Extensions & Telemetry Hardening (v3.34.1)
- **Kernel Heap Bounds Protection**: Added strict bounds guards across CPU instruction delta, clock speed calculation, and rendezvous initialization routines on systems with >64 cores, eliminating heap out-of-bounds writes.
- **Fan Curve Downward Hysteresis Anchor**: Seeded and anchored downward fan curve hysteresis tracking against last applied duty cycle temperatures, preventing erratic PWM jitter and rapid fan cycling.
- **SuperIO NCT668X Privilege Gating**: Gated configuration register 0x30 I/O-space decode unlocking behind driver privilege checks, securing LPC bus address decoding from unprivileged mutation.
- **User-Client Buffer Underrun Rejection**: Enforced mandatory output buffer size validation across all 25 struct-output method selectors, rejecting undersized user buffers with `kIOReturnBadArgument` to prevent uninitialized kernel memory disclosure.
- **SuperIO IT86XX Probe Port Cleanup**: Completed proper close sequence (`outb(regport, 0xAA)` / `outb(regport, 0x02)`) on failed SuperIO chip identification, preventing dangling enter-state conditions on ports 0x4E/0x2E.
- **Core Metric Telemetry & Read-Side OOB Guard**: Capped selector 4 effective cores at `CPUInfo::MaxCpus`, bounding required buffer size to ≤268 B across all processors and eliminating read-side kernel heap infoleaks on >64-physical-core machines.

### Application Stability, Privacy & Architecture
- **Event Tap AX Messaging Timeouts**: Implemented strict 50 ms accessibility messaging timeouts and keystroke shortcut gating across `FinderCutPaste` and `AutoQuitService`, preventing CGEventTap auto-disablement and main thread UI hangs.
- **Pasteboard Privacy & Secret Exclusion**: Excluded reverse-DNS transient and auto-generated types (`org.nspasteboard.TransientType`, `org.nspasteboard.AutoGeneratedType`) from clipboard history, safeguarding password manager entries.
- **Thread-Safe Driver Lifecycle**: Protected IOKit driver connection checks with synchronized locking and ensured clean watchdog task cancellation on teardown, preventing background polling leaks and races.
- **Platform Alignment**: Updated release documentation and minimum system requirements to explicitly target macOS 14 Sonoma and above.

## [1.17.0] — 2026-09-02

### Performance & Core System Stability
- **IOAccelerator GPU Leak Fix**: Resolved `io_object_t` Mach port leak in `IOAcceleratorCache` by advancing iterator in the loop condition, preventing unreleased service references on early exit.
- **Shelf Tolerant Store Decoding**: Integrated tolerant deserializer for saved items, preventing single corrupt entries from resetting the entire shelf.
- **WhatsApp Download Atomic Renaming**: Optimized same-volume file moves using atomic rename instead of redundant multi-gigabyte SHA-256 rehashing.
- **Display Fingerprint Validation**: Added hardware display fingerprint check before restoring gamma curves in Extra Brightness service.
- **OCR Line Break Normalization**: Enhanced Screen OCR text joiner to optionally remove line breaks across wrapped paragraphs and Asian scripts.
- **Shared Component Hardening**: Enhanced Launch At Login reconciliation, keyboard debounce handling, responsible process mapping, and screenshot rendering.

### AMD Hardware & Custom Architecture Protected
- **Full AMD Ecosystem Intact**: Maintained all custom Zen 1–5 telemetry, `SMCAMDProcessor` kext integrations, SuperIO fan curves, and AMD power presets.
- **Dashboard Process Manager Intact**: 100% preservation of the built-in Dashboard Process Manager (`PerformanceSuiteView`, `BTopDashboardView`, `ProcessInspectorWindowController`, `ProcessGlossary`, and `LeakDetector`).
- **Network Sampler**: Maintained macOS Sequoia 64-bit `IFMIB_IFDATA` network counters and real-zero rate detection.
- **Ad-Hoc Update Acceptance**: Kept secure ad-hoc code signature acceptance for community releases.

## [1.16.0] — 2026-08-28

### AMD Power Management & Kernel Drivers
- **Compiled Kernel Extensions**: Rebuilt and bundled updated `AMDRyzenCPUPowerManagement.kext` and `SMCAMDProcessor.kext` (v3.34.0) with enhanced stability and telemetry precision.
- **SMU Mailbox Synchronization**: Synchronized multi-step SMU7/SMU9 mailbox commands under mutex locks to prevent command collisions during heavy background loads.
- **Hardware Fan Curves & Hysteresis**: Clamped fan curve hysteresis and ramp rates to hardware-safe bounds, preventing fan oscillation and sudden speed jumps.
- **Modern Zen Generation Support**: Added calibrated frequency and boost profiles for Ryzen 7000, 8000 (APUs), 9000 series, and Threadripper 7000/PRO silicon.
- **Curve Optimizer Safety**: Enforced per-core voltage offset limits within the verified `[-30, +30]` range.
- **GPU BAR Concurrency**: Resolved potential race conditions during concurrent PCI BAR register initialization for AMD Radeon GPUs.

### Audio Engine & Volume Control
- **Automatic Audio Recovery**: Added a watchdog mechanism to automatically detect stalled CoreAudio aggregates after sleep/wake cycles and restore sound output seamlessly.
- **Boost Limiter Peak Protection**: Integrated an exponential-decay peak limiter for volume amplification above 100%, preventing clipping and acoustic distortion.
- **Clean Resource Teardown**: Ensured all CoreAudio property listeners and Carbon shortcut handlers are released upon device switching and app termination.

### System Metrics & UI Experience
- **Fluid Scrolling**: Preserved fractional pixel precision during mouse-wheel inertia animations to eliminate micro-stutters during slow scrolling.
- **Thread-Safe Telemetry**: Isolated C6 residency and Auto-EPP power management routines on the main actor to prevent data races and ensure smooth 60 FPS menu bar updates.
- **Accurate CCD & GPU Thermal Monitoring**: Constrained per-CCD temperature queries and formatted discrete GPU thermal readouts directly in integer degrees Celsius.

### Security, Packaging & System Hygiene
- **Hardened Subprocess Execution**: Protected background process calls with strict execution timeouts and pipe buffer drainage to prevent system stalls.
- **Secure File Exports**: Enforced strict POSIX 0600 file permissions on data exports and settings backups, with automated 300-second keychain auto-locking.
- **Installer & Packaging Integrity**: DMG packaging verified with SHA-256 checks and clean uninstaller support.

## [1.15.2] — 2026-08-28

### Security & Hardening (Codebase Audit)
- **GPU Fan Curve Temperature Injection**: Fixed value conversion mismatch in user-client selector 103 ensuring GPU-sourced fan curves track live temperature readings accurately.
- **Kernel Heap Protection**: Zero-filled telemetry packets in selector 100 to eliminate uninitialized memory disclosures; added `cpu_number()` bounds checks on >64 CPU systems.
- **SuperIO & Firmware Safety**: Gated NCT67XX firmware I/O-space unlock and raw register access behind privilege checks, and ensured configuration ports are safely closed on verify failure.
- **IOPCIDevice Lifecycle**: Fixed `AMDGPUDevice` reference counting and released Lilu EFI runtime service instances on teardown.

### App Correctness & Performance
- **Mac App Store Updates**: Updated iTunes Lookup querying to check all installed App Store applications individually, resolving batch truncation.
- **Clipboard Ignored Apps & Security**: Activated frontmost application exclusion during clipboard capture and enforced POSIX 0600/0700 permissions on history storage.
- **Text Snippets & Pasteboard**: Offloaded `{{clipboard}}` expansion from the active event tap thread and chunked keyboard injection along Unicode grapheme boundaries.
- **URL Cleaner Fidelity**: Switched query parameter cleaning to splice raw percent-encoded pairs, preserving original URL escape semantics.
- **AX Optimization**: Replaced dense 150-probe minimize-restore loop with a responsive 9-step back-off ladder.
- **Input & Window Management**: Constrained App Switcher middle-click closing to panel bounds, preserved fixed-point mouse wheel deltas, and added stuck-button safety timeouts.
- **Status Item Stability**: Connected consecutive empty-render grace windows to eliminate status bar layout jitter during transient sampling gaps.

## [1.15.1] — 2026-08-27

### UI & Layout Optimization
- **Menu Panel Spacing**: Eliminated excess empty margins at the top and bottom of the status popover. Removed rigid frame constraints to allow the panel to shrink-wrap naturally around content and scroll views.
- **Header Alignment**: Re-anchored the top header in a `ZStack` so the brand mark stays centered while the detach button is cleanly pinned to the top right.
- **Top Safe Area**: Reclaimed top padding using `.ignoresSafeArea(.container, edges: .top)` for a tight, native fit underneath the menu bar anchor.

### Compiler & Concurrency Hardening
- **Swift 6 Concurrency Compliance**: Marked thumbnail decoders (`ImageThumbnailer` and `VideoThumbnailer`) as `@MainActor` with detached background decoding to prevent `NSImage` non-Sendable warnings across task boundaries.
- **Zero Warnings**: 100% clean compilation across all modules and full unit test suite (3,742 assertions).

## [1.15.0] — 2026-08-27

### Deep Cleaner & Uninstaller Overhaul
- **Enhanced Leftover Matching Engine**: Complete rewrite of candidate scanning with `FileIdentity`, `stripKnownSuffix`, and multi-depth directory traversal. Accurately identifies app leftovers in Library, Preferences, Caches, Application Support, Containers, and receipt databases.
- **Safety & Symlink Protection**: Strict boundary checks prevent deletion outside scanned roots; symlink escapes and path replacement attacks are detected and rejected.
- **Confidence Badges & Reveal in Finder**: Leftover items display clear confidence indicators (`Exact` vs `Related`) and include direct Finder reveal buttons to inspect files before removal.

### SuperKey & Keyboard Customization
- **Multi-Source SuperKey**: Support for multiple trigger keys (Caps Lock, Right Option, and dedicated keys) with configurable modifier output combinations (`superKeyModifiers`).
- **Dynamic Key Descriptions & Modifiers**: Customizable modifier toggles (Command, Option, Control, Shift) with instant live preview and support in Menu Panel and Settings.

### Clipboard History Expansion
- **Extended Capacity**: Added support for 10,000 items and Unlimited history storage.
- **Automatic History Trimming**: Dynamic database trimming on limit changes ensures instant cleanup and fast sqlite search responsiveness.

### Media & Playback Fixes
- **NowPlaying Radial Menu Fix**: Fixed double-click toggle bug in the mouse radial menu where clicking Play/Pause caused immediate conflicting state toggles, ensuring seamless play/pause behavior for Apple Music, Spotify, and system media.

### App Switcher Enhancements
- **Adjustable Appearance Delay**: Added slider setting (0 to 500 ms, 100 ms default) in App Switcher settings to customize delay before the switcher overlay appears on hotkey press.

### Localization & Quality of Life
- **Complete 13-Language Updates**: All new strings, captions, and settings translated natively across English, Spanish, Brazilian Portuguese, German, French, Italian, Japanese, Korean, Russian, Turkish, Simplified Chinese, Traditional Chinese (HK), and Traditional Chinese (TW).
- **3,742 Unit Checks**: 100% test pass rate across the full standalone test suite.

## [1.14.0] — 2026-08-26

### Stability & Anti-Freeze (GCD)
- **BoundedProcessRunner**: Added per-read byte cap and a process termination timeout using `terminationHandler` instead of a blocking `waitUntilExit` call, eliminating GCD thread-pool exhaustion from runaway subprocesses.
- **WindowEnumerator**: Replaced `waitUntilAllOperationsAreFinished()` with `NSCondition` + 5 s timeout (`accessibilityBatchBudget`), ending indefinite stalls on locked accessibility APIs during Space switches (#971).
- **Pasteboard API fully asynchronous**: `GeneralPasteboardAccess` gains an `async<T>(_:then:)` overload; every call site (`URLCleanerService`, `PanelURLCleanerView`, `URLCleanerSettings`, `ClipboardHistoryService`, `PanelClipboardView`) migrated to the async lane — eliminates the last main-thread pasteboard blocks.

### Performance & System Fixes
- **Chromium CPU protection**: `AutoQuitService` and `WindowMaximizer` query `kAXWindowsAttribute` / `isApplicationElement` before traversing Chromium accessibility trees, removing multi-second CPU spikes during page loads.
- **Gamma Dim correctness**: `BrightnessSupport` and `BrightnessService` track `dimmedDisplays` separately from display brightness, preventing gamma-curve overwrites that caused permanent screen dimming on some monitors.
- **Sudoers rule scoped to UID**: `SudoersSupport` / `ShellSupport` write `#<uid> ALL=(root) NOPASSWD:…` instead of `ALL`, enforcing least-privilege even on multi-user machines.

### UI, Thumbnails & HUD
- **Menu-bar battery icon aspect ratio**: Fixed pixel-rounding error in `MenuBarRenderer` that caused the battery icon to appear squashed on retina displays (`31a0fc33`).
- **Real video thumbnails on Shelf**: `VideoThumbnailer` uses `AVAssetImageGenerator` to grab a frame 10 % into the clip (never the raw first frame, which is typically black or a title card). Decode is fully async — drop lands instantly with the fallback icon and the real frame patches in. Restore of a saved shelf also decodes all thumbnails off the main thread, eliminating startup hold for large shelves (`cd2d781a`).
- **Image thumbnail timing fix**: `startContentThumbnails` now fires after the item is appended to `items` rather than during `fileItem` construction, removing the 50 ms race-condition timer that silently discarded frames in mixed-provider drops (`23e9c5b3`).
- **Tile inset follows `hasContentThumbnail`**: Tiles use the thumbnail inset only once a real frame exists; generic-icon items keep the padded inset regardless of `isImage` flag.
- **Clipboard rich Finder preview & persistent Inspector**: `ClipboardHistoryImageSupport` / `ClipboardHistoryEscape` added; `ClipboardImageStore` extended with Finder preview support; async completions threaded through all `copyQuickEntry`/`copyQuickEntries`/`copyOnly*` methods.
- **App Switcher navigation & session scope**: `usesWindowRow` and `shiftBackChordWindow = 0.35` added to `SwitcherSupport`; `sessionScope` is assigned before `recomputeLayouts` to avoid a first-render with wrong scope.
- **SuperKey mouse click modifiers preserved** (`20e77ea5`): `SuperKeyService` installs an HID mouse tap that injects the active SuperKey modifiers into every click and drag event, preventing modifier-strip on mouse input.
- **Pixel-snapped crop rect & new crop selection** (`890dd0be`, `449f5f62`): `ScreenshotSupport` gains `startsNewCropSelection(at:draft:within:)` and `pixelSnappedCropRect`; `ScreenshotEditorController` snaps to device-pixel boundaries and supports starting a fresh crop without an overlap drag; crop loupe uses a 14 × 14 sample centred on an edge.
- **QuickTool HUD width cap & multi-line** (`1a9f6cd7`): `QuickToolHUD` clamps width to 360 pt and wraps at 2 lines, preventing oversized popups for verbose tool output.
- **Status item anchor reliability** (`ce44088a`, `e6485ec8`): Coordinate conversion in `StatusItemAnchorSupport` / `StatusItemController` corrected for edge cases with multiple screens at different backing scales.
- **Uninstall failure note & sandboxed FDA explanation** (`7b59532f`): `UninstallerSupport`, `AppUninstaller`, `SharedUI`, `UninstallerView`, `PanelUninstallerView`, and all 12 non-English localisations updated with clear guidance when full-disk access is missing.

### New Features
- **Media compression to target file size** (`83fc0626`): Images, GIFs, and videos can now be compressed to a user-specified MB target. `MediaVideoTargetEncoder` performs multi-pass bitrate scaling with per-format reduction plans (GIF frame-drop → palette reduction → scale; video bitrate budget → scale). UI in `MediaWorkspaceView` switches between resolution mode and target-size mode.
- **Visual Date/Time variable builder for snippets** (`1ac63dc8`, `b4e7930c`): New `DateVariableBuilder` popover in Snippet Settings lets users construct `{date:…}` tokens with IANA timezone search, format previews and one-click insertion. `TextSnippetSupport` gains `-tz(…)` override syntax and ranked timezone lookup. `PlainTextEditor` extracted as a shared AppKit/SwiftUI component with undo, configurable insets, and safe selection binding — replaces the private duplicate in Scratchpad.

### Internal & Testing
- **3,742 automated unit checks** — 100 % pass rate, +114 new assertions covering pasteboard async, `startsNewCropSelection`, `pixelSnappedCropRect`, `cropLoupeSampleRect`, `DateVariableBuilder` format tokens, and IANA timezone ranking.
- **Zero external telemetry** — all network hooks remain stripped.

## [1.13.0] — 2026-08-23

### Stability & Security Improvements
- **ScreenCaptureKit Window Indexing**: Fixed a fatal `SIGTRAP` crash caused by duplicate `windowID`s returned by ScreenCaptureKit during Space switching and multi-monitor reconfiguration.
- **POSIX Sandbox Hardening**: Implemented `PrivateFileStore` to enforce secure POSIX `0o700` directories and `0o600` file permissions across Shelf storage, Screen Recorder temporary shares, and Clipboard history databases.
- **macOS 14+ Cooperative Window Activation**: Updated Dock Click window cycling to use `NSApp.yieldActivation(to:)` and `activate(from: NSRunningApplication.current, options: [])`, preventing activation warnings on macOS Sonoma and later.
- **Filmstrip Trim Handle Stabilization**: Isolated Recorder filmstrip coordinate spaces (`"recorderFilmstrip"`) with absolute positioning to eliminate drag gesture jitter during video trimming.

### Features & Usability Enhancements
- **Intelligent Music Launch Interception**: Replaced blanket app launching blocks with temporal media-key event taps, distinguishing between unintended playback key presses and intentional user launches from the Dock or Spotlight.
- **Advanced URL Tracking Cleaner**: Added platform-tailored query parameter stripping rules for YouTube, X/Twitter, Instagram, Spotify, Reddit, TikTok, Bilibili, and Xiaohongshu.
- **Sticky Footer Deduplication in Scrolling Screenshots**: Integrated tiled column pattern matching to automatically identify and eliminate fixed headers/footers during vertical screenshot stitching.
- **Middle-Click Window Close**: Middle-clicking (scroll wheel click) any window tile in App Switcher now directly closes that window.
- **Synchronous Input Source Switching**: Added Carbon TIS-based keyboard layout switching action for SuperKey solo triggers.

### Memory Telemetry & Dock Preview
- **Comprehensive Memory Breakdown**: System monitor and menu panel now report physical Compressed Memory, Cached Files, and Swap usage alongside active application memory and memory pressure.
- **Configurable Dock Preview Open Delay**: Added customizable hover latency setting (200 ms to 900 ms) with proactive window list prefetching for responsive, jitter-free dock previewing.
- **13-Language Native Localization**: Complete native translations for all new memory telemetry, dock preview settings, and controls across all 13 supported languages (EN, PT-BR, ES, DE, FR, IT, JA, KO, RU, TR, ZH-Hans, ZH-Hant-HK, ZH-Hant-TW).

### Internal & Testing
- **3,628 Automated Unit Checks**: Verified complete regression test suite with 100% pass rate.
- **Zero-Telemetry Assurance**: All telemetry, tracking, and external analytic hooks remain completely stripped.

## [1.12.0] — 2026-08-17


### Fan & Cooling Control Rewrite
- **Kernel-Native Dynamic Fan Curves**: Complete ground-up rewrite of the fan and cooling control subsystem. Dynamic curves are now evaluated directly inside the kernel (`AMDRyzenCPUPowerManagement.kext`) at a 500 ms cadence with 256-point LUT interpolation, exponential moving average smoothing ($\alpha = 0.2$), hardware hysteresis, ramp rate limiting, and an emergency thermal guard ($\ge 85$ °C $\to$ PWM $\ge 200$), completely eliminating userspace PID polling loops and CPU overhead.
- **Hardware Telemetry Read-Back**: Accurate fan speed (RPM) and duty cycle (PWM %) are derived directly from the physical SuperIO chip (NCT6775, IT86xx, etc.) via SMC read-back (selector 94).
- **GPU Temperature Bridge (Selector 103)**: Added native GPU temperature forwarding to the kernel power management client, enabling fan curves driven by discrete GPU thermal loads.
- **Interactive Curve Editor & Staged Drafts**: Redesigned curve editor featuring 256-point visual preview, live sensor tracking markers, 4-curve slot management, a safe 1% minimum duty cycle floor, and explicit "Apply Curve" and "Revert" actions to prevent unintended fan spin-ups during editing.
- **13-Language Native Localization**: Full native translations for all fan control labels, alerts, and guide dialogues across all 13 supported languages.
- **Wake & State Synchronization**: Automatic re-upload of active curve LUTs and fan mappings upon system wake (`didWakeNotification`).

### Accessibility
- **Complete VoiceOver Coverage**: every icon-only button in the app (menu panel, mixer, shelf, settings, Now Playing, clipboard, uninstaller/cleaner) now announces a proper accessibility label — 44 buttons across two passes — with new localized tooltips and labels for mixer mute/unmute and the panel back button in all 13 languages.
- **Keyboard Controls in Now Playing**: Space toggles play/pause and Escape closes the floating window from anywhere inside it.

### Now Playing Fixes
- **Marquee Scrolling Fixed**: long titles now scroll continuously (slide-in → hold → scroll → loop) instead of stalling after the first pass.
- **Animated Artwork Switching**: moving between two albums with motion artwork now reloads and crossfades the new video stream.
- **Detached Window & Network Cleanup**: the floating window deregisters its move observer on close, and cancelled lyrics requests are pruned from the in-flight set.

### Performance & Stability
- **Mach Port Leak Fixed**: the thread-grid view no longer leaks its host port handle.
- **Faster Renders**: reduced SwiftUI redraws in ThreadGridView and added a visual loading state to Homebrew search buttons.

### Internal
- **Unit Tests**: 3,628 automated checks (+386 new checks covering LUT math, 272-byte packing, ramp rate scaling, compaction, and localization).

## [1.11.2] — 2026-08-17

### Accessibility
- **Complete VoiceOver Coverage**: every icon-only button in the app (menu panel, mixer, shelf, settings, Now Playing, clipboard, uninstaller/cleaner) now announces a proper accessibility label — 44 buttons across two passes — with new localized tooltips and labels for mixer mute/unmute and the panel back button in all 13 languages.
- **Keyboard Controls in Now Playing**: Space toggles play/pause and Escape closes the floating window from anywhere inside it.

### Now Playing Fixes
- **Marquee Scrolling Fixed**: long titles now scroll continuously (slide-in → hold → scroll → loop) instead of stalling after the first pass.
- **Animated Artwork Switching**: moving between two albums with motion artwork now reloads and crossfades the new video stream.
- **Detached Window & Network Cleanup**: the floating window deregisters its move observer on close, and cancelled lyrics requests are pruned from the in-flight set.

### Performance & Stability
- **Mach Port Leak Fixed**: the thread-grid view no longer leaks its host port handle.
- **Faster Renders**: reduced SwiftUI redraws in ThreadGridView and added a visual loading state to Homebrew search buttons.

### Internal
- **77 new unit checks** (marquee engine, LRC parser, artwork fingerprint, defaults migration v6) — 3,242 total.

## [1.11.1] — 2026-08-15

### CPU & Performance Optimizations
- **Process Loop Elimination**: Resolved an event loop in BTopDashboardView and PerformanceSuiteView where process updates triggered continuous re-sampling.
- **Menu Bar Marquee Optimization**: Set marquee scrolling off by default with idle timer teardown during hold phases to eliminate background WindowServer rendering load.
- **Morph Animation Cadence**: Adjusted popover transition timer to 60Hz.

### Now Playing & UI Improvements
- **Universal Transport Controls**: Fixed play/pause and track skipping by implementing smart single dispatch for Apple Music and Spotify via AppleScript alongside MediaRemote and system media keys, eliminating double-toggle behavior.
- **Menu Bar Icon Redesign**: Converted the Now Playing status item to a native template symbol with clean typography and a refined 1.5pt progress indicator.
- **Detached Window & Mini Mode Framing**: Fixed layout headroom across all sizes (Small, Medium, Large) so artwork, title, progress bar, and all playback controls remain fully visible without clipping. Added right-click context menu for quick resizing and pin-on-top toggles.
- **Radial Menu Synchronization**: Unified radial menu media keys with NowPlayingService routing.

## [1.11.0] — 2026-08-15

### Now Playing — Adaptive Themes & Animated Artwork
- **Theme Engine**: Added dynamic background theming with 6 palette styles (Artwork Adaptive, Frosted, Midnight, Warm Studio, High Contrast, Graphite) and real-time color blending from album artwork.
- **Animated Artwork Surface**: Support for Apple Music / animated cover streams with seamless crossfading between static cover art and live video streams.

### Now Playing — Detached Floating Popup & Mini Card
- **Detachable Floating Window**: Ability to tear off the Now Playing popover into a persistent floating desk widget.
- **Mini & Regular Display Modes**: Compact mini card mode for minimal desktop presence alongside the full-featured player card.
- **Marquee & Size Settings**: Configurable title marquee scrolling speeds and artwork sizing options.

### Now Playing — Lyrics, Credits & Search
- **Synchronized & Plain Lyrics**: Integrated lyrics center with auto-fetching, line-by-line synced playback scrolling, and manual search fallback.
- **Song Credits & Metadata**: Display detailed track information including composer, release year, genre, and bitrate.
- **Provider Search**: Search and jump directly to tracks across configured media providers.

### Now Playing — Transport Controls & Shortcuts
- **Shuffle & Repeat**: Full toggle support for shuffle and repeat modes across system media sessions and player backends.
- **Global Hotkeys**: Added configurable keyboard shortcut actions for previous, next, play/pause, and shuffle/repeat toggles.

## [1.10.0] — 2026-08-14

### Now Playing — Transport Fix
- **Next / Previous Track**: fixed a critical bug where the Next Track button was sending command `kMRStop` (raw value 3) instead of `kMRNextTrack` (raw value 4), causing it to stop playback instead of skipping to the next song. Previous Track was similarly off by one. The fix affects both the Now Playing panel card and the Radial Menu media keys — skip and back now work correctly in Music, Spotify, and any other system media session.

### Now Playing — New Feature
- **Now Playing Panel**: new section in the menu panel showing the current track with artwork, artist, album, a seekable progress bar with time labels, and transport controls (previous, play/pause, next). Works with any app that publishes a system media session: Music, Spotify, browsers, video players.
- **Now Playing Menu Bar Item**: dedicated status item that shows the track title and artist in the menu bar with an optional progress strip, configurable display modes (icon only, artist, song, or both), and a click to open the panel.
- **Provider Picker**: pin the feature to Music or Spotify, or leave it on Auto to follow whichever app is playing.
- **Open in App**: click the track title or use the button to bring the source app to the front.

### Monitor — CPU Temperature
- **Menu Bar Temperature from Cold Start**: the CPU temperature now appears in the menu bar immediately on launch without needing to open the Dashboard first. Added a dual-fallback: first tries the telemetry selector, then falls back to core-metric temperature.

### Dashboard — Live Updates
- **Process List Real-Time Refresh**: the process list in the Dashboard now updates automatically in real time even when the popover is closed, driven by the system monitor's snapshot tick (every ~1 s).
- **Network Graph**: the network throughput chart in the Dashboard now activates as soon as the Dashboard window opens.
- **Scroll**: the Dashboard tab content is now scrollable so multi-core grids and long process lists don't overflow.

### Fan Curve Editor
- **Canvas Height**: the fan curve editor canvas no longer collapses to zero height; it now renders at a proper fixed height so the curve is always fully visible.

### Code Quality — Swift 6 Readiness
- Replaced all `NSLock.lock()` / `.unlock()` calls inside `async` / `Task` contexts with `withLock {}` (ProcessorModel, ProcessUsageService).
- Declared `kextWatchdogTask` as `nonisolated(unsafe)` to allow assignment from the actor's `init()`.
- Fixed `@MainActor`-isolated `updateUsage()` called from a nonisolated `Timer` callback in `ThreadGridView`.
- Captured `initFans` as an immutable `let` binding before `await` in `AmdControlSection` to satisfy Swift's sendability rules.
- Updated two deprecated `onChange(of:perform:)` calls to the macOS 14+ two-parameter form.
- Removed an unused `flags` binding in `FinderCutPaste`.

## [1.9.16] — 2026-08-09

### App Switcher — Rules & Windowless Apps
- **Per-App Rules**: choose how each app appears in the switcher — always show it without windows, windows only, or never — from Settings → Switcher, with an app picker and per-app icons.
- **Windowless Apps Choice**: replaced the single "show Finder" switch with a picker — not shown, Finder only, or all apps — for apps running with no window at all.
- **Search Pin Toggle**: typing "S" pins the search field open while the switcher is up, so typing no longer closes it or triggers special characters when the shortcut uses ⌥. Off by default; the toggle lives in Settings → Switcher.
- **Thumbnail Pauses**: window thumbnails stop updating while a chosen app is frontmost (privacy), from the preview-size section.

### App Switcher — Polish
- **No Open Window View**: selecting an app with no open windows shows its icon with "no open window" instead of an empty tile.
- **Shortcut Hints Toggle**: the hints under each tile can be hidden.

### Clipboard — Control & Editing
- **Skipped Apps**: choose apps whose copied content is never saved to the history.
- **Preview Sidebar & Editing**: preview clipboard entries in a sidebar and edit saved text (up to 20,000 characters) before reuse.

### Screenshot & Recorder
- **Screenshot**: a clipboard shortcut, an option to hide RyzenStatus windows from captures, and a preview-position picker.
- **Recorder**: microphone input with its own permission flow.
- **Sharing (developer)**: screenshots and recordings can be shared as expiring links to your own server. There is no default server and never a third-party host; see docs/SHARING_SERVER.md.

### Essentials — Input & Display
- **Dock Click to Hide**: clicking the Dock icon can hide all of the app's windows.
- **Keep Awake Options**: allow the display to sleep while keeping the system awake, and toggle keep-awake with a right-click on the menu-bar icon.
- **Scroll Inverter — Horizontal Axis**: invert horizontal scrolling direction independently.
- **URL Cleaner — Custom Parameters**: strip your own query parameters from copied links.

### Monitor
- **Memory Metric Choice**: choose which memory metric the monitor shows.

## [1.9.15] — 2026-08-09

### Essentials — Input & Stability
- **No More Frozen Input During Games**: with Dock Preview enabled, every mouse move ran a Dock Accessibility hit-test on the main thread. While a fullscreen app (e.g. a game) was frontmost, the Dock is hidden, so the hit-test fell through to AX IPC against the app under the cursor — often a game that answers accessibility slowly — with no messaging timeout, freezing the main run loop for seconds and stalling every event tap on it: clicks were missed, delayed, or read as drags (in-game clicks "not registering", apps feeling hung). The hover pipeline now only runs while the Dock is actually on screen.
- **Hover Detection Hardened**: the per-mouse-move path gates on cheap geometry before any IPC, skips the AX parent walk when the element under the cursor isn't the Dock, and caps every Accessibility round-trip at 0.2 s, so a busy or unresponsive app can never block the main thread again.

## [1.9.14] — 2026-08-08

### AMD Power — Menu Panel
- **No More Panel Blocking**: kext reads (CPPC, CPB, PPM/LPM, fans and fan count) now run off the main thread; only the UI refresh hops back, preventing micro-stutters when opening the menu.

### Essentials — Stability & Telemetry
- **Kext Selectors Documented**: the selector table now matches the kext's real semantics (101 writes the fan-curve LUT, 102 maps a fan to a curve, 17 reads HP CPUs, 18 reads LPM state) — no behavior change.
- **No More mach Port Leaks**: per-core load sampling releases the host port it acquires on every read, matching the rest of the monitor.

### Dashboard — Real Data
- **No More Hardcoded Hardware**: the BTop section and Performance Suite cards show the machine's actual CPU/GPU and VRAM instead of fixed models ("Ryzen 9 5900XT", "NAVI 21").

## [1.9.13] — 2026-08-08

### Settings — Fan & Cooling
- **Immediate Fan Loading**: the screen no longer waits for the kext's slow name lookups; it shows RPM and controls from a minimal read and applies the saved names afterwards.
- **No Duplicate Polling on Entry**: the periodic timer starts after the first read, so it no longer races the initial detection.

## [1.9.12] — 2026-08-08

### Settings — Fan & Cooling / AMD Ryzen Power
- **Reliable Tab Switching**: kext reads are now cancelled when leaving the screen, so no stale tasks keep updating a destroyed view.
- **Visible, Non-Blocking Loading**: AMD Ryzen Power shows its loading state immediately and avoids duplicate reads when switching pages quickly.
- **Controlled Fan Refresh**: periodic polls are cancelled and replaced instead of accumulating while navigating.

## [1.9.11] — 2026-08-08

### Essentials — GPU & Counters
- **No More False 100% GPU Spikes**: integer percentage values from AMD are no longer interpreted as `1` = `100%`; the card also distinguishes a pending read from a real `0%`.
- **Unified Normalization**: all GPU paths share the same conversion and validation before feeding the chart and the per-process breakdown.

## [1.9.10] — 2026-08-08

### Essentials — Network & Charts
- **Correct 64-bit Counters on Sequoia**: reading `NET_RT_IFLIST2` could truncate received bytes; it now uses `IFMIB_IFDATA`, matching `netstat`.
- **Charts Visible with Low Traffic**: network scales adapt to the real peak instead of being pinned at `1024 B/s`, and the download/upload lines stay distinguishable.

## [1.9.9] — 2026-08-08

### Essentials — Real-Time Network
- **Sampling Enabled in Performance Suite**: the dashboard requests the network metrics it displays, preventing stale cards while the history kept drawing.
- **Real Zero Kept Apart from “Measuring”**: the UI no longer turns a pending first sample into `0 B/s`, avoiding misleading readings when switching pages or resuming the monitor.

## [1.9.8] — 2026-08-08

### GPU — Coherent Readings
- **Discards Impossible Spikes**: the monitor no longer accepts high GPU load while the core clock is idle (`<100 MHz`), avoiding cases like `63%` at `15 MHz` with nearly idle GPU processes.
- **More Reliable Total & Breakdown**: the overall percentage keeps the hardware counter, while the process list keeps using the GPU time attributed by macOS without turning a spurious reading into real load.

## [1.9.7] — 2026-08-08

### DMG & GPU Monitor
- **Kexts Included**: the installer uses the official precompiled kexts from the `SMCAMDProcessor v3.34.0` release when no local build is available, and shows them inside the DMG.
- **Better-Organized Installer**: the DMG window only positions the Kexts folder when it exists, avoiding shifted icons or Finder errors.
- **GPU Without False Spikes**: non-finite or out-of-range values are discarded and an isolated `100%` is not accepted as a first sample; sustained load still climbs gradually.

## [1.9.6] — 2026-08-08

### Essentials — Responsiveness
- **Faster Settings Opening**: the global monitor now activates only the metrics the visible screen needs, instead of starting network, disk, GPU and memory work for no reason.
- **AMD Power Without Blocking the UI**: CPPC, PPM/LPM, telemetry and Curve Optimizer reads run off the main thread.
- **Nimble Fan & Controls**: fan detection and updates run in the background; names are read only when hardware is detected, not on every periodic query.
- **Optimized SMC Sensors**: the connection is reused, the key list is cached, and full reads run on a low-priority queue.

## [1.9.5] — 2026-08-08

### Sequoia (macOS 15) Compatibility
- **Runs on Sequoia**: The macOS‑26‑only SwiftUI pieces — the Liquid Glass mixer styling (`GlassEffectContainer`, `glassEffect`) and the Settings sidebar scroll edge effect (`scrollEdgeEffectStyle`) — are now compiled behind `#if compiler(>=6.2)` guards. Built with Xcode 16 / SDK 15 they fall back to the native pre‑26 UI, so the app builds and runs on macOS 15 Sequoia (and macOS 14) exactly as before. Runtime behavior on macOS 26 is unchanged — the glass mixer slider and styled sidebar still appear there.
- **CI‑proven**: A new `sdk15` CI job builds the full app against the macOS 15 SDK (Xcode 16.4) on every push, so the Sequoia fallback branch can never silently regress again.

## [1.9.4] — 2026-08-08

### Fans & Cooling — Usability & Safety
- **Fan Curve Editor as a Master Switch**: Turning the curve editor on now maps the first curve to the first fan right away, so one tap visibly starts controlling a header. Turning it off restores every mapped fan to automatic control and stops the userspace loop — no more fans staying curve-driven after the toggle is off.
- **Reliable First Tap**: The one-tap mapping retries once fan detection completes, so it no longer silently does nothing when the kext is slow to report fans on startup.
- **GPU Temp Source Hidden When Not Applicable**: The curve editor only offers the GPU temperature source when a discrete AMD GPU is present (the GPU fan is managed by the GPU itself). Hiding it is non-destructive — stored GPU-sourced curves keep their intent and are just shown as CPU.
- **Thermal Safety Guard**: The userspace fan-curve loop now enforces the same safety floor as the kext — at least 80% PWM above 85 °C — so a user-drawn curve can never leave the CPU without airflow near its thermal limit, on every supported CPU family (Zen 1–5).

### Housekeeping
- Removed dead kext fan-curve code (selectors 101/102 UI) left over in AMD Power Settings after the feature moved to Fans & Cooling.

## [1.9.3] — 2026-08-08

### Gaming Mode — Reliability
- **Pre-Gaming Preset Persistence**: Gaming Mode now remembers your actual power profile (not a fallback) when you activate it, so after a relaunch with the mode still active, turning it off restores the exact preset you were running before — even across app restarts.
- **Serialized Preset Transactions**: All power-preset writes (Settings cards, menu panel, and Gaming Mode activate/deactivate/restore) now go through a single FIFO queue in `AmdPresetController`. A fast toggle-off during activation or a restore racing a new activation can no longer interleave their persisted-key and kext writes, so the app and hardware can never disagree about which preset is active.

## [1.9.2] — 2026-08-08

### Stability & Performance (AMD Backend)
- **IOKit Performance (Micro-stutters)**: Completely rewrote the GPU communication layer. Instead of querying `IOAccelerator` synchronously ~6 times per second, RyzenStatus now uses an asynchronous cache (`IOAcceleratorCache`) that processes the entire kernel tree in the background. This definitively eliminates any stuttering or micro-stutters in the main interface or when moving the mouse during heavy GPU polling.
- **Kernel Security (Kext)**: Resolved critical vulnerabilities (`P0`) related to memory leaks (`proc_ucred`) in the IOKit client and out-of-bounds (OOB) array reads when querying VirtualSMC sysctl keys.
- **UserDefaults Centralization**: Implemented a new configuration store in the backend (`AmdSettingsStore`) to replace dozens of scattered reads and writes for power profiles (Auto EPP, Gaming Mode, Fan Curves). This prevents ghost states and race conditions between the UI and the background polling loop.
- **Polling Robustness**: Added guards to MSR and temperature reads to prevent sensor timeouts from injecting anomalous values (e.g., forcing fans to 0 RPM when receiving a false 0°C reading).
- **Internal Architecture**: All "magic" Kernel selectors (IOConnectCallStructMethod) are now strictly typed through the `AMDKextSelector` enum, making the backend cleaner and error-proof.

## [1.9.1] — 2026-08-08

### Gaming Mode
- **Gaming Mode**: One click applies the Extreme power preset, starts an indefinite Keep Awake session and hides the menu bar icon. The mode persists across launches and is re-applied on startup; turning it off restores your previous profile — including your Auto EPP preference, even after a relaunch while the mode is active.
- **Full Menu Bar Hiding**: With separate menu bar metrics enabled, Gaming Mode now hides those items too instead of leaving CPU/GPU readouts on screen.
- **Localized Section**: The Gaming Mode settings now follow the app language (English and Spanish; other languages fall back like the existing AMD Power strings).
- **Smarter Preset Restore**: Choosing a different power preset while Gaming Mode is active keeps your choice — deactivation only restores the pre-gaming profile when it hasn't been changed. Preset cards highlight what the kext is actually running while the mode is on.

### Privacy & Security
- **Strict Share Record Filtering**: Screenshot share links only surface when they point at the currently configured server — records from any other host (including the removed legacy upload server) never appear in Settings.

## [1.9.0] — 2026-08-07

### AMD Power — Full Kext Selector Integration
- **Power Presets (Eco / Balance / Performance / Extreme)**: One-tap profiles that configure EPP, Core Performance Boost and PPM/LPM together — Eco (EPP 255 + C6 + LPM), Balance (EPP 128), Performance (EPP 32) and Extreme (EPP 0). PPM and LPM stay mutually exclusive and the selection persists across launches.
- **CPB / PPM / LPM Toggles**: Core Performance Boost (selector 12), Processor Power Manager (14) and Low Power Mode (19) now persist their last state and report privilege errors clearly.
- **CCD Temperatures**: Per-CCD thermal readout (selector 20) shown as dashboard cards and inside the telemetry packet.
- **C6 Residency Meter**: Live percentage of time the package spends in C6 (selector 31) rendered as a progress bar in the dashboard and AMD Power Settings.
- **CPU Profile Readout**: The kext's architecture codename (selector 26) — e.g. "Zen 3 Vermeer" — appears in the dashboard header, with PM Dispatch / Legacy P-States / CPPC capability badges in Settings.
- **CPPC Info & Core Ranking**: Shows the active CPPC mode and current EPP value (selector 23), and marks the highest-HighestPerf threads with a star (selector 21).
- **AMD GPU Monitoring**: Dedicated AMD GPU temperature and power (selectors 27–30) appear in the dashboard and Settings, using the capabilities bitmap for power reporting — hidden when only an iGPU or NVIDIA GPU is present.
- **Telemetry Streaming**: Zero-copy 304-byte `CPUSensorPacket` (selector 100) with package power/temp, per-CCD temperatures and per-thread frequencies, read out in Settings.
- **Kext Fan Curves**: Four predefined 256-point LUTs (Silent / Balanced / Performance / Aggressive) uploaded to the kext (selector 101) and mapped to a fan header (selector 102), with a live curve preview and one-click Auto restore.
- **Curve Optimizer**: Per-core offset grid −30..+30 (selectors 110/111) with Apply All and Reset to 0, gated to Zen 3 Vermeer — Zen 4/5 shows an explanatory "use PBO in BIOS" message and the kext blocks writes above 75 °C.

## [1.8.8] — 2026-08-07

### Features & Fixes
- **32-Thread Support (Zen 3)**: Complete UI overhaul for the Core Grid dashboard to natively support and properly render up to 32 hardware threads, using responsive layouts and proper color coding for physical vs SMT cores.
- **Combined Frequency & IPS Metrics**: A new real-time graph mapping average CPU frequency against Instructions Per Second (IPS) estimates.
- **Classic Menu Revival (NF-03)**: Brought back the classic menu layout (Layout 2) without breaking the modern unified panel.
- **Robust Telemetry & Stability**: System-wide bug fixes targeting zombie `nettop` polling, thermal deadlocks, temperature hysteresis, and memory safety improvements.

## [1.8.7] — 2026-08-07

### Privacy & Security
- **Screenshot Sharing Disabled by Default**: RyzenStatus no longer uploads screenshots to any third-party server outside our control. Sharing now requires a developer-configured server endpoint; the share buttons stay disabled until one is set up.
- **Legacy Share Links Purged**: Share records created by older builds that point at the removed server are dropped from the app so no stale links surface in Settings.

## [1.8.6] — 2026-08-07

### Features & Fixes
- **GPU Power Badge Uses Kext Capabilities**: The per-GPU power badge now respects the kext's capabilities bitmap (selector 30, bit 0) — power is shown only for GPUs that actually support power reporting, instead of inferring it from a non-zero reading.
- **AMD Auto EPP Persistence & Privilege Feedback**: The Auto EPP toggle state now persists across launches in user defaults, and a clear hardware-privilege warning is shown when the kext denies the write. Removed the redundant privilege warning caption from the popover.
- **CPU Load Meter Sampling Fix**: Per-thread CPU load sampling now runs continuously across all 32 logical threads whether or not Auto EPP is active, eliminating the load-meter feedback loop.

## [1.8.5] — 2026-08-06

### Features & Fixes
- **AMD Auto EPP & CPU Load Meter Fix**: Fixed the toggle state feedback loop in AMD Power Control popover/settings and ensured real-time CPU load sampling runs continuously across all 32 hardware threads whether Auto EPP is active or inactive.
- **Screen Recorder UI Sidebar Integration**: Exposed the full Screen Recorder configuration panel, controls, and shortcut bindings under Settings > Utilities.
- **AMD Ryzen Temperature Spike Filter**: Integrated `TemperatureAlertGate` hysteresis to eliminate false high-temperature alert spikes during single-core CPU boost on AMD Zen 3.
- **Display DDC Sleep Recovery**: Automatically rebuilds I2C display routing paths upon system wake, preserving external monitor brightness controls.
- **Menu Bar Icon Recovery Retries**: Multi-attempt status item placement checks prevent icon loss when macOS delays menu bar rendering.
- **App Switcher & Scratchpad Dismissal**: Added outside-click dismissal for App Switcher and Scratchpad panels, with customizable pin floating options.

## [1.8.4] — 2026-08-05

### Features & Improvements
- **Screen Recorder & Live Video Editor**: Full screen and window recording with mouse pointer tracking, live editing timeline, composited cursor sprites, and fast export engine.
- **Scrolling Screenshots**: Automatic scroll-capture engine stitches full-page screenshots with overlap detection, max-resolution guards, and graceful partial-completion fallback.
- **System Master Volume Control**: Master output volume slider and mute toggle now appear at the top of the Audio Mixer section alongside per-app controls.
- **App Switcher Multi-Space Support**: Instant transition between multiple Desktops/Spaces, corrected Adobe window previews, and support for apps with no open windows.
- **Thermal Safety Filter**: CPU and GPU sensors now ignore bogus 0 °C readings — minimum valid chip temperature raised to 10 °C, with a 4-sample hold-last-good cache to bridge transient SMC gaps.
- **Command Bar Improvements**: Direct app controls available in the Command Bar; full-width space characters (U+3000, IDEOGRAPHIC SPACE) are now handled as whitespace for search and shortcut matching.

## [1.8.3] — 2026-08-05

### Stable Maintenance Release

### Features & Improvements
- **Localization Infrastructure**: Added comprehensive `L10n` localization keys (`istatsUser`, `istatsSystem`, `istatsProcesses`, `amdRyzenProcessorInfo`, `amdMinFrequency`, `amdMaxFrequency`, `amdAvgFrequency`) across all 11 supported languages.
- **Kext Callback Execution Order**: Adjusted GPU temperature callback execution timing in `SMCAMDProcessor.kext` prior to fan curve evaluation.
- **Volume Mixer Drag-to-Reorder**: Integrated drag-to-reorder layout support and custom block styling for application volume controls in the menu panel.
- **System Telemetry Stability**: Reinforced AMD Auto-EPP / CPPC state persistence and menu bar readout defaults.

## [1.8.2] — 2026-08-02

### Stable Release

### Features & Improvements
- **AMD Boot-Args Read & Copy**: New section in AMD Power Settings displays the current NVRAM `boot-args` state (`amdcstate`, `-amdcppcactive`, `-amdpnopchk`) as live read-only badges. A single "Copy AMD Boot-Args" button copies the full recommended string to the clipboard for pasting into your bootloader `config.plist` — the app never writes to NVRAM directly.
- **Finder Image Paste**: Pressing `⌘V` in a Finder window with no files marked for cut now saves clipboard PNG/TIFF images directly as `Pasted Image <timestamp>.png` in the current folder.
- **Clipboard Privacy**: Password manager entries (1Password, Bitwarden, TypeIt4Me, `org.nspasteboard.ConcealedType`) are automatically excluded from clipboard history — passwords are never recorded.
- **Performance Suite Dashboard**: Full `PerformanceSuiteView` with 5 navigation tabs (Dashboard, Diagnostics, Analytics, Energy, Network).
- **AMD SMT Core Topology Mapping**: Corrected XNU kernel interleaved SMT thread indexing, restoring accurate per-core load visualization across all 16 physical cores.
- **1Hz Real-Time Process Inspector**: Floating inspector window with executable path, Reveal in Finder, Copy Path, and 1Hz live telemetry.
- **Catmull-Rom Cubic Spline Waveforms**: Smooth cubic spline timeline sparklines and trend charts.
- **Dynamic CPU Hardware Detection**: Real-time `sysctlbyname("machdep.cpu.brand_string")` and core/thread topography resolution.
- **App Switcher Enhancements**: W-key window closing, thermal alert hysteresis, external disk eject support, and customizable Dock Preview opacity.

### Bug Fixes
- **Process Inspector Memory Leak**: `NSWindowDelegate` + `windowWillClose` tears down live-telemetry timers when inspector is closed.
- **Telemetry Logger Disk Exception**: File write exceptions handled gracefully during low-disk states.
- **Memory Alignment Safety**: Replaced unsafe pointer type-punning with `loadUnaligned` in `NetworkSampler`.
- **Network Process Pipe Deadlock**: Concurrent drain queue for `nettop` eliminates pipe buffer deadlocks on high-traffic connections.
- **Background Performance Suite Loading**: Data refresh offloaded to background `Task.detached` with `MainActor` UI updates.
- **Disk Sampler Timeout**: 4-second timeout with fallback process termination in `runDiskutilInfo`.
- **Accurate Energy Impact GPU Scoring**: Resolved process GPU utilization from `topGPU` instead of hardcoding zero.
- **FinderCutPaste Thread-Safety**: `NSPasteboard` data captured on calling thread before `DispatchQueue.global` — eliminates race condition crash.
- **FinderCutPaste moveInProgress Flag**: Reset correctly in all branches including the image-paste and `insertionLocation` failure paths.
- **Bitwarden Clipboard Filtering**: Added `org.bitwarden.clipboard` and `com.bitwarden.bitwarden` to the pasteboard privacy exclusion list.


## [1.7.2] — 2026-07-31


### Maintenance Release

Fourth stable release. Zero-warning compiler optimization, fan control overrides refactoring, thread safety improvements, and full test suite verification.

### Improvements & Fixes
- **Fan Control Overrides**: Updated fan curve controls to use `isOverridden` property, eliminating all compiler deprecation warnings.
- **WhatsApp Organizer**: Refactored `undoActions` declaration in download organizer.
- **Thread Safety**: App Switcher event tap and Shelf item icon rendering optimizations on main thread.
- **Drive Format Identifiers**: Added file system labels (APFS, exFAT, NTFS, FAT32, HFS+) to Disks monitoring panel.
- **Smooth Scroll**: Improved high-resolution mouse wheel support for smooth scrolling.
- **Verification**: Clean build with 0 compiler warnings and all 2,941 unit test checks passing.

## [1.7.1] — 2026-07-27

### Stable Release

Third stable release. Ports remaining upstream utility services and dependency methods.

### Features
- **Shortcut Capture**: Silences global shortcuts during recording sessions—captured keystrokes won't trigger features.
- **Shortcut Recording Tap**: Dedicated event tap for capturing keystrokes during shortcut recording.
- **UI Suspension**: Enhanced user interface suspension helper for apps during assisted workflows.

### Internal
- Added `EnhancedUserInterfaceSuspension`, `ShortcutCapture`, `ShortcutRecordingTap` utilities for shortcut recording and UI suspension.
- Added `suspendShortcut()` to ClipboardHistoryService, SoundOutputSwitcher, ShelfService.
- Added `suspendShortcuts()` to WindowLayoutService, `unregisterAll()` to QuickToolHotkey.
- Added `routeCapturing` state and `setCapturingShortcut(_:)` to AppSwitcher.
- Added `featuresToSilenceWhileRecording` to GlobalShortcutRole.

## [1.7.0] — 2026-07-27

### Stable Release

Second stable release. Adds 6 new productivity features from upstream plus GPU alert localizations and audit fixes.

### Features
- **Boost Limiter**: Automatically reduces system volume when an app starts making loud noises—perfect for unexpected full-screen videos or audio glitches.
- **Space Hop**: Automatically follows your active window when you switch to an app whose window is on a different full-screen Space, eliminating manual Space navigation.
- **Mouse Exceptions List**: Per-app exception list for Smooth Scroll and Scroll Inverter — exclude specific apps from scroll customization.
- **App Appearance**: Choose between System, Light, or Dark appearance mode per app.
- **Snippet Library**: Dedicated searchable panel for text snippets, organized by folder.
- **WhatsApp Downloads**: Full download organizer — scans Downloads for WhatsApp files, auto-cleanup with retention rules, daily/weekly scheduling, and notifications.

## [1.6.0] — 2026-07-27

### Stable Release

First stable release. Consolidates all beta features, fixes, and improvements from the beta3→beta9 cycle.

### Features
- **App Updates**: Check which installed apps have newer versions via Homebrew and Mac App Store, with background scanning and notifications.
- **Package C6 Residency Monitoring**: C6 power state monitoring via MSR 0xC0010296 — live residency percentage in Dashboard and AMD Power Settings.
- **Menu Bar W Suffix Fix**: Power metrics with 3-digit values no longer clip the "W" suffix.
- **Mouse Button Shortcuts**: Programmable extra mouse button mapping.
- **Super Key (Caps Lock Remap)**: Turn Caps Lock into a powerful modifier key.
- **Snippet Library**: Text snippet library with searchable catalog.

### Bug Fixes
- **GPU Temperature Priority (Critical)**: Kext MMIO GPU temperature (selector 28) now takes priority over IOAccelerator readings.
- **Fan Control API Rename**: `setFanSpeed(rpm:)` → `setFanSpeed(pwm:)` to reflect actual PWM (0-255) parameter.
- **Timing Monotonicity**: Replaced wall-clock `NSDate` with `ProcessInfo.systemUptime` for interval calculations.
- **Physical Core Fallback**: From hardcoded 16 to `ProcessInfo.processorCount / 2`.
- **Thread Safety**: `@MainActor` annotation added to `MonitorAlertService`.
- **Kext Version Bump**: 3.34.0 — AMDGPU MMIO monitoring, C6 residency, SuperIO 6-fan support.
- **Process List Flickering Fix**: Extended stale cache lifetime from 2s to 60s.

## [1.6.0-beta9]

### Features
- **App Updates**: New feature that checks which installed apps have a newer version available. Supports two sources:
  - Homebrew casks (including apps with their own updater, verified against the actual app bundle version)
  - Mac App Store (looks up versions via iTunes API)
- **Background Check**: Optional daily/weekly automatic scanning with notification support.
- **Panel Integration**: App Updates tile in the Utilities section showing pending updates with update-all button.
- **Settings Page**: Configure check frequency, notifications, and App Store scanning in Settings → App management.

## [1.6.0-beta8]

### Features
- **Menu Bar W Suffix Fix**: Power metrics with 3-digit values (e.g. 105W) no longer clip the "W" in menu bar blocks.
- **Initial Status Item Sizing**: Status bar now reserves enough width for power metric blocks from the first sample.

### Kexts
- **Version Bump 3.33.6 → 3.34.0**: Kext source already contained all SuperIO fixes from v3.33.8 plus C6 and AMDGPU monitoring. Bumped to 3.34.0 to reflect actual feature level and avoid confusion with the old v3.33.6 tag.
- **AMDRyzenCPUPowerManagement**: v3.34.0 — AMDGPU MMIO monitoring (selectors 27-30), C6 residency (selector 31), SuperIO 6-fan support, pmAMDRyzen cleanup.
- **SMCAMDProcessor**: v3.34.0 — GPU SMC key additions.

## [1.6.0-beta7]

### Features
- **Package C6 Residency Monitoring**: Added C6 power state monitoring — reads MSR 0xC0010296 via kext selector 31 and displays residency % live in the app.
- **C6 in Dashboard**: C6 residency card on main Dashboard for at-a-glance monitoring.
- **C6 Settings UI**: Deep C-States section in AMD Power Settings with percentage, visual bar, and boot-arg instructions.

### Fixes
- **App Kext References**: Corrected stale "SMCAMD.kext" references in Dashboard, Fans settings, and error alerts to use proper kext names.
- **Source Cleanup**: Removed all build artifacts, experiment scripts, and leftover documentation from development session.

## [1.6.0-beta6]

### Feature Parity
- **Mouse Button Shortcuts**: Added programmable mouse button configuration — remap extra mouse buttons to custom actions.
- **Super Key**: Added Caps Lock remapping — turn an unused key into a powerful modifier.
- **Snippet Library**: Added text snippet library with searchable catalog alongside the existing text snippets.
- **New Settings Pages**: Dedicated Mouse Buttons and Super Key pages with full configuration UI.

### Bug Fixes
- **GPU Temperature Priority (Critical)**: Fixed a bug where the IOAccelerator GPU temperature snapshot could overwrite the more accurate kext MMIO reading (selector 28). Kext data is now treated as primary source.
- **Fan Control API**: Renamed `setFanSpeed(rpm:)` to `setFanSpeed(pwm:)` to accurately reflect that selector 95 expects PWM values (0-255), not RPM.
- **Timing Monotonicity**: Replaced wall-clock `NSDate` with `ProcessInfo.systemUptime` in `getMetric()` and `loadMetric()` for accurate interval calculation immune to system clock changes.
- **Physical Core Fallback**: Changed fallback core count from hardcoded `16` to `ProcessInfo.processorCount / 2` for better accuracy on non-16-core machines.
- **Thread Safety**: Added `@MainActor` annotation to `MonitorAlertService` to match its actual usage pattern.
- **GPU Monitoring**: Kext selector 30 (capabilities) is now fetched alongside temperatures and powers in `refreshKextGPUStats()`, making the data available for future capability-aware logic.
- **Documentation**: Added explanatory comment to the fan zero-RPM clamp threshold (50°C conservative floor).

## [1.6.0-beta5]

- **Sampling Policy Correction**: Corrected `MonitorSamplingPolicy` foreground target interval values for deterministic per-tick sampling (functionally identical with 1s interval).
- **Menu Bar Block Alignment Fix**: Adjusted `legacyBlockAttachmentNudge` from -1.2 to -0.25 on macOS < 27 for centered menu bar metric blocks.
- **Disk Sampler Deadlock Fix**: Fixed a potential deadlock in `DiskSampler.runDiskutilInfo` by redirecting stderr to `/dev/null` and reading pipe output before `waitUntilExit()`.

## [1.6.0-beta4]

- **Full GPU Kext Pipeline**: Complete AMD GPU monitoring pipeline from kernel PCI BAR MMIO registers to the RyzenStatus UI via `AMDGPUDevice` class with multi-GPU detection (Sea Islands through Navi 3x).
- **GPU UserClient Selectors**: Implemented UserClient selectors 27-30 for GPU count, temperature, power, and capabilities via `ProcessorModel.swift`.
- **GPU Temperature & Power Charts**: GPU temperature and power telemetry now displayed in Dashboard detail views.
- **GPU-Aware Auto EPP**: `AutoEppService` detects active GPU gaming/rendering workloads to automatically apply performance EPP profiles.
- **GPU Temperature Alerts**: Debounced GPU temperature and power alerts integrated in `MonitorAlertService`.
- **Multi-GPU Support**: `SensorsView` and `SystemMonitor` updated to handle multiple discrete GPU devices via `GPUDeviceSnapshot` model.
- **Fan Curve GPU Input**: `FanCurveController` uses kext-reported GPU temperature directly without actor hop overhead.
- **Process List Flickering Fix**: Extended stale process cache lifetime from 2s to 60s, preventing process rows from disappearing during background `ps`/GPU sampling cycles.
- **Classic Card Breakdown Fix**: Eliminated background queue race condition in `SystemSection` breakdown refresh; CPU and GPU square cards are now tappable to expand the process list.
- **MonitorSamplingPolicy Test Alignment**: Corrected disk stride test expectations to match the current 8s background target interval (stride=4).

## [1.6.0-beta3]


- **Classic Cards Process List Fix**: Connected reactive notification listeners and prevented initial empty-state override when expanding CPU/GPU breakdown rows in Classic Cards view.
- **Process List Stability & Deterministic Sorting**: Implemented secondary PID sort in process breakdown lists to prevent row flickering and position jumping when process values are equal.
- **AMD GPU Process Detections**: Added kernel-level `pgrep` fallback for `WindowServer` and active Metal processes to guarantee non-empty GPU process breakdown on discrete AMD GPUs.
- **UI Expansion State & iStats Reactivity**: Retained expanded process lists across popover redraws and bound iStats widget process lists to reactive `@State` properties.

## [1.6.0-beta1]

- **PRE-FASE 0 Kext Sanity Check**: Dynamic detection of `AMDRyzenCPUPowerManagement.kext` and `SMCAMDProcessor.kext` at launch. Runs gracefully in degraded read-only mode with UI warning banner instead of forcing app termination when kexts are missing.
- **Classic Menu Bar Appearance**: Added 0% CPU/GPU overhead `.classic` menu bar appearance option.
- **32-Thread SMT Dashboard & CCD Breakdown**: Full 32-logical-thread core grid support with distinct CCD0 and CCD1 temperature telemetry (`ccd0Temperature`, `ccd1Temperature`).
- **Combined Metric Graph**: Dual-axis overlay of Peak CPU Frequency (GHz) over CPU Load (%) in metric detail views.
- **Critical Concurrency & Fan Control Fixes**: Bounds check on `telemetry.metric[1]`, `@MainActor` safety in `Task.detached`, and nonisolated synchronous fan reset on app termination.
- **Batched IOKit GPU Queries**: Replaced 6 individual `IOAccelerator` property queries with single-pass `readAllIOAcceleratorStats()`.
- **Telemetry Logger & Thermal Alerts**: Buffered async telemetry CSV/JSON logger with 10s rate-limiting, plus sustained (>30s) thermal throttling alert notifications.

## [1.5.6]

- **BTop Cyberpunk Network Sparkline Fix**: Replaced Swift Charts ordinal rendering with native `Sparkline` path engine, resolving sparkline loops and diagonal line artifacts.
- **Per-Core Dashboard Grid Alignment**: Fixed text wrapping (`47%`) and frequency truncation (`4680MHz`) in per-core cards with 52px fixed-height cell geometry.
- **Detached Popover Re-attach Handling**: Restored interactive popover view immediately upon clicking "Reattach to Menu Bar".
- **Full Multi-Language Localization**: Synchronized 11 locale files with 0 hardcoded strings, supporting English, Spanish, German, French, Italian, Turkish, Russian, Japanese, Korean, and Chinese.

## [1.5.5]

- **Audio Mixer Sleep/Wake Recovery**: Integrated `EngineRenderVerdict` & `CycleBox` IO proc render tracking to automatically detect and recover wedged audio mixer engines when the Mac wakes from sleep.
- **Crisp Graph Text Overlays**: Enlarge graph text overlays with `.heavy` bold typography and subtle outline stroke, preserving 100% graph bar visibility without dark box overlays.

## [1.5.4]

- **Clean Crisp Graph Text Overlay**: Removed black background box pill over graphs; enlarged text to `.heavy` bold font (`8.5pt` / `7.8pt`) with clean 4-directional outline shadow, preserving 100% graph bar visibility while making numbers sharp and legible.

## [1.5.3]

- **High-Contrast Graph Numerical Overlay**: Rendered a dark capsule background pill (`black 0.68 alpha`) with a 4-direction outline stroke behind numerical text overlays in menu bar graphs (Histogram, Donut/Pie, Sparkline), guaranteeing 100% legibility on light and dark menu bar themes.

## [1.5.2]

- **Persistent Hidden Fans State**: Saved hidden fan selections (`HiddenFanIDs`) to `UserDefaults`, ensuring hidden fans remain hidden when switching tabs in Settings or restarting the app.

## [1.5.1]

- **Localization of AMD Power Control Views**: Fully localized all labels, headers, tooltips, mode badges, and footers in `AmdControlSection` and `AmdPowerSettingsView` via new `AMDPowerFeatureStrings`, ensuring seamless English and Spanish UI rendering.

## [1.5.0]

- **OpenCore Boot-Arg Guidance Banner**: Added an inline informational banner in the Fans & Cooling settings section reminding users that manual fan speed control requires boot-arg `-amdpnopchk` in OpenCore `config.plist` and `SMCAMDProcessor.kext` v3.33.8+.

## [1.4.9]

- **Fixed Manual Fan Override Reset**: Resolved bug in `FanCurveController` background loop that was automatically resetting manual fan slider overrides to BIOS control every 2 seconds, allowing manual fan speed overrides (100%, etc.) to take full effect on hardware.

## [1.4.8]

- **Manual Fan Slider Target Hold**: Protected manual slider value from being reset by telemetry polling cycles in `FansSettingsView`, keeping user-selected fan speed overrides (100%, etc.) locked on screen and hardware.
- **Fan Control Picker State Sync**: Synced fan control picker status dropdown with real-time manual override state (`Manual Override` vs `BIOS / Auto`) to eliminate UI mode discrepancies.

## [1.4.7]

- **Hardware Usage Header Space Reclamation**: Removed redundant "Hardware usage" section title to maximize vertical screen space in the main popover panel.
- **Fan Control IOKit Call Deduplication**: Deduplicated setFanSpeed kernel calls in `FanCurveController` to prevent SuperIO LPC bus contention and eliminate crashes in external monitoring tools like AMD Power Gadget.
- **Reliable Fan Manual Override**: Custom slider binding ensures fan control mode only switches to manual when physically dragged by the user, preserving BIOS / Auto control upon opening settings or refreshing telemetry.

## [1.4.6]

- **Numerical Value Overlay Inside Menubar Graphs**: Option to render real-time numerical readings (`42%`, `17.2G`, `50°`) directly inside status bar graphs (Histograms, Sparklines, and Donut Pies).
- **Fan Control Auto/Manual Binding Fix**: Resolved automatic fan mode override bug in `FansSettingsView` so opening options or polling updates does not switch fans away from BIOS / Auto control.
- **Eliminated Top Popover Blank Gap**: Removed top padding gap under the popover arrow to maximize vertical space.
- **Universal SuperIO Fan Control**: Corrected manual/auto mode selector sequence for complete compatibility across all SuperIO chips (ITE, Nuvoton, Fintek) and multi-fan configurations.

## [1.4.5]

- **Restored Glass Card Footer Buttons**: Restored the original rounded glass cards with stroke borders for `Ajustes` and `Salir` footer buttons in the main panel.
- **Fixed Header Blank Space**: Removed empty update banner padding and optimized top padding under the popover arrow.
- **Always-Visible Percentage Threshold Colors**: Made Normal, Medium, and High percentage color threshold pickers always accessible in Settings across all graph modes (Bars, Histograms, Sparklines, and Pies).

## [1.4.4]

- **Full 13-Language Internationalization for iStats**: Added native compiler-checked translations for all 13 supported languages across CPU, Cores, Memory, GPU, and Process List headers.
- **Vertical Graph & Rate Labels**: Uniform stacked vertical labels (`CPU`, `NET`, `GPU`, `RAM`) on status bar graphs and rates.
- **Sleek Scrollbar-Free Popover Layout**: Hidden ugly system scrollbars over cards for a clean Control Center aesthetic.
- **Compact Branding Header**: Reduced AMD top logo and header padding to give 20px+ extra vertical room for monitoring data.

## [1.4.3]

- **RAM Process List & iStats Drag & Drop Reordering**: Added top RAM process list inside Memory card with app icons and GB/MB units. Added native drag-and-drop handles (`PanelDragHandle`) in **Edit Mode** so you can reorder all iStats cards (`CPU`, `Cores`, `Memory`, `GPU`) freely.
- **Dynamic GPU Spoofing & Multi-Core Adaptation**: GPU card dynamically calculates real VRAM, model names, and adaptive clock frequency scaling for spoofed GPUs. Core grid rendering scales dynamically for any CPU topology (4 to 64 cores/threads).
- **Individual Per-Metric Style Pickers in Settings**: Added an "Estilo Individual por Métrica" section in **Ajustes -> Monitoreo** for independent graph customization across 12 languages.

## [1.4.2]

- **Individual Per-Metric Style Pickers in Settings**: Added an "Estilo Individual por Métrica" section in **Ajustes -> Monitoreo**, allowing you to set distinct graph styles for CPU, GPU, Memory, Network, and Disk independently right from the preferences UI.

## [1.4.1]

- **Fixed iStats Card Visibility & Edit Mode Toggling**: Connected `sysCPU`, `sysMemory`, and `sysGPU` AppStorage keys to the iStats widget view and added `PanelInlineHideButton` eye icons when in **Edit Mode** so you can easily hide/show CPU, Memory, or GPU cards directly in iStats mode.

## [1.4.0]

- **iStats CPU & GPU Process Lists**: Added top process list breakdowns directly inside the CPU and GPU popover widget cards, featuring real-time app icons, app names, and precise % CPU / % GPU consumption matching the iStats Menus visual design.

## [1.3.9]

- **Clean Popover UI & Edit-Mode Style Selector**: Hidden the `[ Tarjetas | iStats ]` popover style picker from the main popover view. It now only appears when entering **Edit Mode** (or in Settings), keeping the default popover interface clean and elegant.
- **iStats Memory Card Redesign**: Upgraded the Memory card widget with twin Donut meters (`PRESSURE` & `MEMORY`) and a detailed breakdown list showing App, Wired, Compressed, and Free memory in monospaced GB units.

## [1.3.8]

- **Independent Per-Metric Menu Bar Graph Customization**: Configured `MenuBarRenderer` to resolve graph appearance styles independently for each active metric (`cpu`, `gpu`, `memory`, `network`, `diskUsage`). You can now mix and match graph types across metrics (e.g. CPU Core Histogram + GPU Donut Ring + Network Dual Graph + RAM Values).

## [1.3.7]

- **Per-Core CPU Histogram in Menu Bar**: Added a real-time per-core CPU load histogram widget for the Menu Bar. Displays individual load bars for all 16 physical cores (32 threads) inside a framed mini-container directly in the status bar when Histogram mode is selected.

## [1.3.6]

- **iStats-Style Popover Widgets & Graph Appearances**:
  - **Popover Widget View**: Added an optional iStats-style widget mode in the Popover featuring per-core load histograms, donut ring core grids (for all 16 cores / 32 threads), twin memory pressure donuts, and GPU circular gauges.
  - **Menu Bar Graph Styles**: Expanded Menu Bar appearance options to support Text Values (`values`), Usage Bar Capsules (`bars`), Donut Rings (`pie`), Real-Time Line Graphs (`sparkline`), and Bar Histograms (`histogram`).

## [1.3.5]

- **Peak-Hold CPU Frequency Smoothing**: Implemented a Peak-Hold decay filter for the Peak CPU Frequency indicator. Instant single-core boosts (e.g. 4.8 GHz) are caught immediately and decay smoothly instead of jumping erratically, ensuring the peak frequency (top line) is mathematically guaranteed to stay equal to or higher than the average frequency (bottom line).

## [1.3.4]

- **Dashboard Telemetry Enhancements**: Connected real live telemetry history buffers for CPU/GPU Temperature, CPU/GPU Power, and CPU Frequency, replacing static/simulated placeholders with real-time graphs and 1-decimal live headers.

## [1.3.3]

- **Frequency Rounding**: Rounded menu bar and system panel frequency indicators to 1 decimal place (e.g. `4.7G` / `4.2G` instead of `4.73G` / `4.22G`) for cleaner visual presentation.

## [1.3.2]

- **Process List Refresh Rate & Ghost Elimination**: Eliminated ghost/terminated processes by filtering dead PIDs (`kill(pid, 0)`), updating breakdown rows unconditionally when idle, and added a user-configurable **Process List Refresh Rate** setting (1.0s, 2.0s, 3.0s, 5.0s) in Settings -> Monitor.

## [1.3.1]

- **Default Popover Tab Fix**: Configured the menubar popover panel to open on the first tab (`.system` / CPU System Monitor) by default instead of defaulting to the last tab (`.keepAwake`).
- **GPU Process List Optimization**: Enhanced process tracking for AMD Radeon GPUs under Metal and Vulkan.

## [1.3.0]

- **Easter Egg Movie Quotes**: Added an interactive random classic movie quote in the bottom-right corner of the Support settings tab. Click the quote to cycle through quotes.

## [1.2.9]

- **Menu Bar Usage Capsules Fix**: Guaranteed a minimum 1-step fill indicator for active CPU, GPU, and RAM usage bars to prevent empty transparent capsules when load is light.
- **Auto-updated Release Notes**: Synced changelog notes across builds and settings.

## [1.2.8]

- **Metric Cards Truncation Fix**: Replaced integer truncation with rounded percentage formatting for sub-1% CPU and GPU metrics in panel cards.

## [1.2.7]

- **AMD GPU Utilization & CPU Sampling**: Fixed AMD Radeon Navi 21 IOKit property parsing (`NSNumber`/`Double`/`UInt64`) and added fallback to SMCAMDProcessor driver telemetry. Implemented physical core load average fallback for uninterrupted CPU percentage reporting.

## [1.0.6]

- **Fan control overhaul**: Fixed critical bugs in the kext SuperIO drivers (ITE 86XXE, Nuvoton NCT67XX/NCT668X) — RPM-to-PWM fallback now correctly estimates fan speed in Auto mode so the slider shows the actual RPM percentage instead of 0%.
- **Fixed `getFanAutoControlMode` for ITE chips**: Now properly checks bit 7 (SmartGuardian) instead of any non-zero byte — the app correctly distinguishes Auto vs Manual mode.
- **Fixed throttle parsing in the app**: Selector 94 data is now correctly parsed (bits 15:8 = throttle, bit 0 = autoFlag) instead of reading the wrong byte.
- **Fixed fan slider behavior**: No more snap-back, no more disappearing Reset to Auto button, no more inverted Max Speed/All Auto buttons.
- **Restored `setDefaultFanControl` ext register write**: Restoring Auto mode properly resets the PWM register for ITE chips, preventing inverted Max Speed/All Auto behavior.
- **Added peak RPM tracking**: The kext dynamically tracks each fan's peak RPM for accurate PWM estimation in Auto mode.
- **Added custom branding**: App icon, menu bar icon, and AMD images properly included in the bundle.
- **Updated DMG build**: Now includes Kexts folder with the updated kexts for easy installation.

## [1.0.5]

- **Redesigned AMD Fans & Cooling panel** to match AMD Power Gadget's exact layout — slider, control mode picker, RPM display, and Reset to Auto button.
- Added `didDrag` flag to keep the Reset to Auto button visible until the kext confirms the override.
- Simplified the slider to use `fan.throttle` directly (the kext now reports meaningful throttle values in both Auto and Manual modes).
- Removed hardcoded `rpmRef=2500` — the slider no longer uses an inaccurate RPM-to-PWM calculation.

## [1.0.4]

- Redesigned AMD dashboard with AMD Power Gadget's exact layout.
- Fixed process list collapse bug: CPU and GPU process lists no longer show the same data when both expanded.

## [1.0.3]

- **Fan Renaming**: You can now click on a fan's name in the AMD Fans & Cooling tab to assign it a custom name. Names are saved automatically.
- **Thermal Context**: Added the current CPU temperature reading directly to the top of the AMD Fans & Cooling tab so you can monitor heat while tweaking fan curves and speeds.

## [1.0.2]

- Added dynamic CPU architecture detection: now correctly differentiates between legacy (Zen/Zen+) and modern (Zen 2+ CPPC) processors for P-State support.
- Fixed a critical crash (Actor isolation) when accessing P-States on modern architectures.
- Removed legacy branding and assets from the update showcase view.

## [1.0.1]

- Fixed an issue where CPU core frequencies were displaying as 0 MHz.
- Added CCD temperature readings to the main monitoring dashboard.
- Updated the update checker repository to point to DrogaBox/ryzenstatus-utils.
- Added high-resolution application icons.

## 1.0.0

- Initial release of RyzenStatus
