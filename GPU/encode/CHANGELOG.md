# Changelog

## 1.2.6 (RyzenStatus 1.89.0)

- Service (`hevc10`, on by default; `--no-hevc10` turns it off): fixes two bugs in
  `AMDRadeonVADriver2` that broke 10-bit HEVC (Main10) hardware encodes on VCN 3:
  - `Vcn3Encoder::setInputAndOutputFormatParams` sent 8-bit NV12 in the VCN input format
    packet even for a 10-bit HEVC session (producing a green striped picture, ~7 dB PSNR),
    because the encoder context receives NV12 and its `x420` branch leaves the packing
    format at 0. It now sets 10-bit and P010 from the session's 10-bit SPS flag (8-bit
    HEVC, H.264 and RGB are unchanged).
  - `AVDVcn3HevcEncDataProcessor::setupDeblocking` copied only `pps_cb/cr_qp_offset` (0, 0)
    into the VCN deblocking packet and ignored `slice_cr_qp_offset = -3` (which
    `AppleGVAHEVCEncoder` sets for 10-bit and the driver writes into the bitstream), scaling
    Cr by ~0.73x (V PSNR 20.4 dB). It now adds the slice's cb/cr QP offsets to the
    picture's before sending the packet, as Mesa does (0 + 0 for 8-bit).
- Validated only on macOS 26.7.3 (`25G342`, `AMDRadeonVADriver2` UUID
  `1181E2CA-31B3-3DF0-90E2-3AE70552D753`). Tested live on an RX 6800 XT (1080p60 `p010le`
  `testsrc2`, `hevc_videotoolbox -profile:v main10 -allow_sw 0`): PSNR Y 47.0, U 43.7,
  V 46.1 dB, no GPU errors.
- Kext + service Main10 gate (`hw.vcnhevc10`, root-only sysctl): with `-vcnhevc10` in
  `boot-args`, the 1.2.6 kext validates the accelerator at match time and holds Main10
  back (`VCNHEVC10` = `waiting for vcnencodefix service`) until `vcnencodefix watch`
  confirms the `hevc10` driver patch is active and SIP allows access, then writes `1` to
  `hw.vcnhevc10` to publish `IOGVAHEVCEncode` = `"2"` and profile 2. If the macOS build
  is not validated, `--no-hevc10` is passed, or the service stops, the service writes `0`
  and the kext restores the original properties (`off: service says the driver patch is
  not active`) so VideoToolbox never routes 10-bit HEVC to an unpatched driver. Needs the
  1.2.6 kext on the EFI and a reboot; without the new kext (or on a Mac without the kext),
  `vcnencodefix` logs once that `hw.vcnhevc10` is not present and nothing changes.

## 1.2.5 (not released)

- Kext: added an experimental, opt-in boot argument `-vcnhevc10` (off by default, not run
  on a GPU yet). When set, the kext watches for `AMDRadeonX6000_AMDGraphicsAccelerator`
  instances on supported AMD GPUs and sets `IOGVAHEVCEncode` to `"2"` (if below 2) and adds
  profile 2 (HEVC Main10) to a copied `IOGVAHEVCEncodeCapabilities` dictionary. Its state
  is published in the `VCNHEVC10` property on `IOResources` (`off`, `set on <class>`, or
  `not set: <reason>`). Without `-vcnhevc10`, behavior is unchanged.

## 1.2.4 (not released)

- The kext sets the clock floor only on chips whose video clock levels were read, so the
  floor stays inside them. The same driver family runs chips whose top levels are below
  the floor (an RX 5600 XT table: VCLK 1267, DCLK 1086 MHz, against 1322 and 1225), and
  1.2.3 sent it to every chip. Now:
  - Navi 21 (device-id 0x73A0 to 0x73AF, 0x73BF): 132297 as before. This Mac's own
    table (`PP_PhmSoftPowerPlayTable`) has VCLK 363/1400 and DCLK 317/1225 MHz.
  - Navi 23, the RX 6600 family (0x73E0 to 0x73EF, 0x73FF): the same value, which lands
    inside its levels: two published RX 6600 XT tables have VCLK 690/1429 and DCLK
    572/1250 MHz. Not run on a card; the state says so.
  - Any other AMD GPU (RX 5000, Navi 22): off, unless `vcnfloor=N` is on the boot
    arguments, which is taken as the user's own value. When Lilu cannot list the GPUs, it
    works as before.
- The chip rule is in `kext/floor_logic.hpp`; `tests/floor_test.cpp` checks it against
  every AMD 0x73xx device-id in pci.ids (0x73F0 is Navi 33, not Navi 23) and the floor
  against each table's levels.
- The installers still stop on a card that is not a Navi 21; their message now says what
  the kext does on Navi 23.
- Booted on an RX 6800 XT (26.7.3): state "active: encode", `test.sh` 102 fps (preset) and
  p50 21.3 ms (floor), the same as 1.2.3. Not run on a Navi 23.

## 1.2.3 (not released)

- Scripts: `install.sh`, `uninstall.sh`, `doctor.sh` and `test.sh` run the system's own tools only (`PATH`
  set), whatever PATH sudo kept, and clear the quarantine flag with `xattr -s` so a link in the package does
  not make root clear it on the link's target.
- Kext: the log of the first 32 floored requests now takes its slot atomically, so two encode sessions at once
  cannot go past the cap.
- Tool: `patch <pid>` and `--interval` refuse anything that is not a whole number (atoi read `abc` as 0). The
  pid list survives a failed allocation, the log reopen keeps standard output when `open()` returns 1 or 2, and
  the free space checked for the wide patch must also be inside the file.
- config.plist editing (`efi`): every allocation is checked, and a path too long for the temporary or backup
  name stops with an error instead of using a cut name.
- watch: an encoder service macOS refuses access to (SIP Debugging Restrictions on) was asked again on every
  full scan, four times a second, with one log line each time, for as long as it ran. It is now logged once and
  remembered like a patched service. A failed allocation of the pid lists no longer leaves a NULL list in use,
  and `--interval` takes 20 to 60000 ms (a negative value used to become a huge one).
- vcnencodefix and vtenc are built for macOS 14.0 again. 1.2.2 built them for 26.0, so on Sonoma and Sequoia, which
  the patch tables cover, they would not start at all. Built clean for 14.0 with no availability warning; not run on
  14 or 15 here.

- The service reopens its log after newsyslog rotated it. launchd opens the log once and newsyslog renames it at
  1 MB, so the service went on writing into the renamed file and /var/log/vcnencodefix.log stayed empty until the
  next restart (test.sh --wide then skipped its encode). Tried: the line after a rename goes to a new file.
- install.sh checks everything that can refuse before the first change: OpenCore on the EFI, Lilu and its version
  (1.7.0 or newer, from the kext's own requirement), Lilu enabled, a config entry it can write (a disabled entry,
  one before Lilu or with other settings is refused instead of failing after the service and the kext were
  already replaced), and free space. The service files are staged first and the old service is only stopped once
  that worked; the script waits for launchd to let go of it before starting the new one. The kext is swapped
  through a .old copy with Ctrl-C held back. Exit status 2 when the service does not stay running.
- uninstall.sh checks --efi before removing anything, removes the launchd plists before the binary (a plist left
  alone would start a missing binary every 30 s), fails when the kext cannot be deleted, and removes leftover
  .new/.old copies. Empty, relative and "/" --efi paths are handled in both.
- doctor.sh shows the service's options and whether the installed binary is the package's, reads the boot
  arguments the kernel started with, and always ends with 0.
- test.sh --wide only counts log lines written during the test (an old line about a reused pid could let a
  5120-wide encode through unpatched), stops its encode if the test is interrupted, refuses unknown options and
  returns failures.
- The config editor: efi-check no longer says "add updates it" for an old entry before Lilu, which add refuses; an
  entry removed from a file with CRLF line ends keeps the rest of the file as it was.
- efi_test.sh resolves its arguments before changing folder and refuses a missing tool or sample, which had let two
  refusal tests pass.

## 1.2.2

- The service needs SIP's Debugging Restrictions off (bit 0x4 of csr-active-config). With them on, macOS refuses
  the service access to Apple's encoder process even as root, so nothing was patched and the log only said
  "task_for_pid failed ((os/kern) failure)". This was never documented: the test machine had SIP fully relaxed. In
  15.8.3's AMFI (checked in IDA), root only gets the task port of such a process when csr_check(CSR_ALLOW_TASK_FOR_PID)
  allows it.
- `vcnencodefix status` (and so doctor.sh and install.sh) shows an "access" line: allowed, or REFUSED with what to
  change. install.sh warns but still installs. The service logs a warning at start and names SIP in each refused
  access.
- README: the requirement, how to set it in OpenCore, and a troubleshooting entry.
- The service ran as a launchd Background job, i.e. at priority 4. When the CPU was busy it could notice a new encoder
  service late: once 1.6 s after launch while OBS started a 5120x2160 recording, and up to 561 ms with every core
  loaded (normally 25-100 ms). OBS sends its first frame about 260 ms after the launch, and an unpatched encode wider
  than 4096 stalls the GPU. The job is now ProcessType Interactive. Its CPU use stays about 0.5% of one core.
- The 10 ms check looked at each new pid once. launchd starts the service in a fork of itself (about 1 ms), then
  xpcproxy (about 11 ms with every core loaded), then the service, so a pid caught in one of the first two stages
  waited for the next full scan (up to 250 ms; measured up to 235 ms with every core loaded). Such a pid is now
  checked again on every tick until it becomes the service.
- The kext is unchanged from 1.2.1 except for the version number.

## 1.2.1

- install.sh --efi wrote the kext's OpenCore entry with MinKernel 25.0.0 (Tahoe), so on macOS 14 and 15 OpenCore
  skipped VCNEncodeFloor.kext and doctor.sh said "not loaded". This came from 1.0.0, when only Tahoe was supported,
  and was missed when 1.1.0 added Sonoma and Sequoia. New entries now use MinKernel 23.0.0, the same range as the
  kext's Lilu configuration.
- efi-add updates an entry written by 1.0.0 to 1.2.0 in place: it changes only that MinKernel line, verifies the
  result and keeps a backup. Running `sudo ./install.sh --efi /Volumes/EFI` again is enough. efi-check reports such
  an entry as "old entry".
- doctor.sh: on macOS 14/15, "not loaded" now points to that fix.
- The kext and the service are unchanged from 1.2.0 except for the version number.

## 1.2.0

- VCNEncodeFloor.kext also hooks AMDRadeonX6800HWLibs, the second Navi 21 power library in macOS. macOS loads
  AMDRadeonX6000HWLibs for the RX 6800 / 6800 XT / 6900 XT, but setups with NootRX load AMDRadeonX6800HWLibs instead,
  and there the clock floor stayed at "waiting for AMDRadeonX6000HWLibs". PEM_CWDDEPM_PMRequest is the same code in
  both libraries (Hex-Rays: only the source line numbers of its log calls differ), in 14.8.9, 15.8.2, 15.8.3 and
  26.7.3; 14.8.9 ships X6800HWLibs stripped too, so there it is routed at its offset after a 32-byte compare.
- Each library keeps its own trampoline, so a Mac with two Navi 21 cards that load both is handled.
- Not run on a GPU with X6800HWLibs: the floor value was measured on an RX 6800 XT, and other cards' clock levels come
  from their own VBIOS.

## 1.1.0

- Supports macOS 14.8.9 (23J631), 15.8.2 (24H232), 15.8.3 (24H241) and 26.7.3 (25G342). Each patch keeps a table of
  validated builds (LC_UUID) with the exact bytes it expects; any other build is still left alone.
  - Apple's HEVC encoder plug-in is the same file in 15.8.2 and 15.8.3; the call site moved (0x13780 on 15.8.x,
    0x142CA on 14.8.9) and on 14.8.9 two kept register moves differ. The Metal kernel uses only
    thread_position_in_grid in every build.
  - AMDRadeonVADriver2 is the same in 15.8.2 and 15.8.3; on 14.8.9 only the jump distance after the preset load
    differs. VAUveEncoder::EncodePicture reads the preset the same way in all of them.
  - AMDRadeonX6000HWLibs: 15.8.x is identical to 26.7.3 in PEM_CWDDEPM_PMRequest, PP_Cwdde and PEM_ClockChange;
    14.8.9 ships the kext without symbols, so the kext routes the function at its offset after comparing its first
    32 bytes. The payload layout (client type +16, minMclk +36, VclkFloor +60) is the same in every build.
- VCNEncodeFloor.kext loads on Sonoma to Tahoe (it was Tahoe only).
- tests: the wide-patch CPU test runs once per validated build of the plug-in.
- Only 26.7.3 has been run on a GPU. The other builds were checked in IDA and with the CPU test only.

## 1.0.1

- vcnencodefix: new encoder services are found within about 10 ms of launch instead of up to 250 ms. In OBS at
  5120x2160 the first frame arrived before the service was patched and stalled the GPU once at the start.
- vcnencodefix: log lines have milliseconds; the wide patch is applied before the preset patch.
- doctor.sh: fixed the kext state and pid display. test.sh: fixed a message error in the wide test.
## 1.0.0

First release, for macOS 26.7.3 (25G342) on Navi 21.

- VCNEncodeFloor.kext: VCN clock floor for hardware encode sessions (Lilu plugin). Checks the AMDRadeonX6000HWLibs
  build before hooking it and publishes its state on IOResources.
- vcnencodefix service: VCN speed preset for every encode; HEVC widths above 4096 no longer stall the GPU.
- install.sh / uninstall.sh, including the OpenCore config.plist entry (backup and verification).
- doctor.sh and test.sh.
