# AMDRyzenCPUPowerManagement & SMCAMDProcessor

The two kernel extensions behind RyzenStatus's AMD features, for AMD Zen processors (Zen 1 through Zen 5) on macOS 13 Ventura through macOS 26 Tahoe. Current version: **3.40.0**, shipped with RyzenStatus 1.75.0.

- **`AMDRyzenCPUPowerManagement.kext`** is the core driver: it reads the CPU's sensors, owns the idle loop, talks to the SMU, writes energy preference through CPPC, drives the Super I/O fan controllers and serves all of it to user space through an IOKit UserClient.
- **`SMCAMDProcessor.kext`** is a VirtualSMC plugin that publishes those readings as SMC keys, so any app that reads the SMC (iStat Menus, TG Pro, HWMonitor) sees CPU temperature, power, clocks and fans.

The RyzenStatus app is the user interface for both; this folder holds their source.

---

## What the driver does

### Power management (3.40.0)
- **SMU per family.** Each family has its own SMU command set and mailbox registers: Zen and Zen+, Zen 2, Zen 3, Threadripper 5000 (Chagall), AM5 and Threadripper 7000, and the Raven Ridge/Picasso, Renoir/Cezanne and Rembrandt/Phoenix APUs. Power limits (PPT/TDC/EDC, or STAPM/fast/slow on APUs), the cHTC temperature limit, the PBO scalar, OC mode with all-core and per-CCD frequency and voltage, Curve Optimizer (per core and all-core), a boost ceiling and the PM table go through the commands of the running family. A family without a command reports it unsupported instead of receiving another chip's command. The driver publishes what the CPU accepts as a capability report, and the app builds its controls from it.
- **Energy preference (EPP) through MSRs or ACPI.** Where the CPPC MSRs exist (probed, not trusted from CPUID), EPP is written there. Where the firmware publishes CPPC only through ACPI, as on Ryzen 5000 desktop parts, the driver reads each processor's `_CPC`, finds the PCC channel in the PCCT (or the system memory registers) and writes EPP, the request range and autonomous selection through it, the way Linux `amd-pstate` does in shared memory mode. A diagnostic report and a firmware read-back show what it found.
- **Deep idle (CC6).** The driver owns the idle loop on every family and sends idle cores to CC6 through the firmware's C-state I/O address (read from MSR `0xC0010073`, never overwritten). It is switched live from the app; `amdcstate=1` forbids it and `-amdnoidle` leaves idle to macOS.
- **Core Performance Boost and P-states.** Boost on and off for every family; the legacy P-state controls only where the family allows them (Zen 1 and Zen 2).
- **Thermal interlock.** Every SMU write is refused while the package is already hot, and a mailbox that does not answer is never overwritten mid-command.

### Telemetry
- Package and per-core power (RAPL, MSR `0xC001029A` per core), per-core effective clocks and C0 share, package and per-CCD temperatures, SVI2 voltages where available, and the SMU PM table (socket power, peak temperature, fabric and memory clocks, per-core CC6 residency) on the table versions with a known layout.
- Interrupt-context work never touches the FPU; a checker (`Tools/check-kext-fpu.py`) verifies the built binary.

### Fans
- Native RPM read-back and PWM control for Nuvoton NCT668X/NCT67XX (NCT610XD, NCT6771F, NCT6776F, NCT6779D, NCT6791D–NCT6799D, NCT6701D) and ITE IT86XXE (IT8665E, IT8686E, IT8688E, IT8689E) Super I/O chips.
- Fan curves evaluated inside the driver every 500 ms from a 256-point table, with smoothing, hysteresis, ramp limits and an emergency guard at 85 °C, so the fans keep following temperature with the app closed.

---

## Supported AMD processors

| Generation | Family / models | CPUs | SMU command set | Legacy P-states |
|---|---|---|---|---|
| Zen, Zen+ | 17h 01h, 08h | Ryzen 1000/2000, Threadripper 1000/2000 | Summit Ridge / Pinnacle Ridge | ✅ |
| Zen, Zen+ APU | 17h 11h, 12h, 18h, 20h | Raven Ridge, Picasso, Dali | Raven (STAPM/fast/slow) | ✅ |
| Zen 2 | 17h 31h, 71h | Ryzen 3000, Threadripper 3000 | Matisse | ✅ |
| Zen 2 APU | 17h 60h, 68h | Renoir, Lucienne | Renoir/Cezanne (STAPM/fast/slow) | ✅ |
| Zen 3 | 19h 21h–2Fh | Ryzen 5000 desktop | Vermeer | — |
| Zen 3 HEDT | 19h 08h | Threadripper 5000 | Chagall | — |
| Zen 3 APU | 19h 50h | Cezanne, Barcelo | Renoir/Cezanne (STAPM/fast/slow) | — |
| Zen 3+, Zen 4 APU | 19h 3Fh, 40h, 44h, 74h, 75h, 78h, 7Ch | Rembrandt, Phoenix, Hawk Point | Rembrandt/Phoenix (STAPM/fast/slow) | — |
| Zen 4 | 19h 61h; 18h | Ryzen 7000; Threadripper 7000 | AM5 | — |
| Zen 5 | 1Ah 44h | Ryzen 9000 | AM5 | — |

Telemetry, fans, boost and deep idle work on every family the AMD Vanilla patches boot. Energy preference uses the CPPC MSRs where the CPU has them and ACPI CPPC where the firmware publishes it (Ryzen 5000 desktop parts use ACPI); the path each CPU really uses is shown in RyzenStatus under **Settings › AMD Ryzen › Hardware Validation**. Per-core Curve Optimizer needs a verified fuse core map and is offered on Ryzen 5000 desktop parts; elsewhere the all-core margin is used where the family has it.

---

## Installation & OpenCore setup

### Kext loading order
1. `Lilu.kext`
2. `VirtualSMC.kext`
3. `AMDRyzenCPUPowerManagement.kext` (core driver, required)
4. `SMCAMDProcessor.kext` (VirtualSMC sensor plugin)

The prebuilt pair ships inside every RyzenStatus release, in the disk image and as `AMDRyzenCPUPowerManagement-Kexts.zip`. Install both from the same release as the app.

### OpenCore requirements
- OpenCore 0.7.1 or newer with the AMD Vanilla kernel patches.
- `ProvideCurrentCpuInfo` enabled.

### Boot arguments
- **`-amdpnopchk`**: lets RyzenStatus write (fans, EPP, presets, Curve Optimizer) without running as root. Any local process can then issue privileged writes through the UserClient, so use it only on a trusted personal machine. Without it, telemetry still works and writes need root.
- **`-amdcppcactive`**: starts CPPC autonomous mode at boot, before the app runs; the app then sends the EPP it wants.
- **`amdcstate=1`**: forbids deep idle (CC6).
- **`-amdnoidle`**: leaves the idle loop to macOS (`hlt` only), for troubleshooting.
- **`amdpp1ratio=<percent>`**: on Zen 1 and Zen 2, sets the P1 state as a percentage of P0 (80 by default).
- **`-amdpdbg`**: verbose driver logging, for troubleshooting.

### Privilege model
Any process may open the UserClient to **read** telemetry. **Writes** require root or `-amdpnopchk`. Authorization never depends on the process name.

---

## Helping with new CPUs

Register maps, SMU commands and temperature offsets change between families and cannot be guessed. If your CPU is missing from the table, or a control says it is unsupported on a chip that should have it, open an issue in the [RyzenStatus repository](https://github.com/DrogaBox/ryzenstatus-utils/issues) with:

- the CPU model and, from **Hardware Validation**, the capability list, the EPP path and the ACPI CPPC report;
- the driver log from the last boot: `sudo dmesg | grep AMDRyzen`;
- your motherboard and Super I/O chip, for fan support.

Writing to the wrong SMU or SMN address can leave the SMU in a bad state until a CMOS clear, so a control stays off on a family until its commands are known.

---

## Credits & Community Acknowledgements

### Original Authors & Contributors
- **trulyspinach** for the original framework and kext base.
- **aluveitie** for improvements and macOS Sequoia/Tahoe adaptations.
- **mauricelos**, **Lorys89**, **mbarbierato** for SMC SuperIO chip drivers.

### AMD-OSX Community Recognition
Special recognition to the AMD-OSX community for research, development, and testing:
- **Shaneee**: Core developer and administrator of AMD-OSX.
- **AlGrey**: Developer of the core AMD Vanilla kernel patches.
- **Edhawk**, **CorpGhost**, **Royal**: Forum moderators, ACPI experts, and community support leaders.
- **AMD-OSX Discord Community Testers**: Special thanks to fabiosun, Kackvogel 4K, Can, and MacOSx11 for extensive hardware testing across Zen 4 and Zen 5 silicon.

---

## Why This Matters

### For AMD CPU users on macOS

AMD never had native Apple support. While Intel and Apple Silicon users have power management, temperature sensors, and fan control built into the operating system, AMD users rely entirely on kexts like this one for their system to function properly. Without this driver:

- **No CPU telemetry**: You cannot read temperature, frequency, voltage, or power draw from your processor.
- **No fan control**: Fans either run at 100% constantly or fail to respond to actual temperature.
- **No efficient power management**: The CPU stays at high frequencies at all times, increasing power draw and heat.
- **No VirtualSMC sensors**: Apps like iStat Menus, TG Pro, or HWMonitor cannot read any motherboard sensors.

This software **replaces the entire monitoring and control layer** that Apple should have provided for AMD. Without it, a Ryzentosh is a blind, loud, and inefficient system.

## Safety Disclaimer & Liability

> [!CAUTION]
> **WARNING & DISCLAIMER OF LIABILITY:**
> This software interacts directly with low-level CPU hardware registers, Model-Specific Registers (MSRs), and the System Management Unit (SMU) to control CPU voltages, frequencies, and power limits. Incorrect settings can cause system instability, data loss, kernel panics, or permanent hardware damage.
>
> By using this software, you agree that **absolute responsibility rests entirely with the user**. The authors and contributors assume no liability whatsoever for any damage, loss, or side effects to your hardware, software, or personal property—regardless of whether it results in a crashed computer, data corruption, the end of the world, or an alien invasion. Use at your own risk.
