# VCNEncodeFix

Faster, glitch-free HEVC/H.264 hardware encoding on AMD Navi 21 GPUs (RX 6800, 6800 XT,
6900 XT; RX 6950 XT and RX 6900 XT XTXH are also expected to work when OpenCore presents
them as `0x73BF`, never run; see [docs/hardware.md](../docs/hardware.md)) in macOS
hackintoshes with OpenCore. Fixes the slow or stuttering OBS recordings at 4K60 and above.

macOS's hardware encoder for AMD leaves three things wrong on these cards:

| Problem | What you see | Fixed by |
|---|---|---|
| The video engine (VCN) is never asked for clocks, so it often stays at its lowest speed (362 instead of 1400 MHz) for the whole recording | 3840x4320 and similar sizes encode at about 10 fps; OBS falls behind and takes a minute to stop | **VCNEncodeFloor.kext** (kernel half) |
| The encoder never selects a speed preset, so the VCN runs its slowest default mode | 4K60 in OBS repeats about half of the frames ("skipped frames due to encoding lag") | **vcnencodefix** service (user-space half) |
| Every HEVC frame runs a small GPU statistics job sized by the width; above 4096 pixels wide it asks the GPU for more threads per group than it allows | Widths like 5120 or 7680 stall the GPU for seconds per frame; screen glitches | **vcnencodefix** service |

Measured on an RX 6800 XT, macOS 26.7.3, OBS 33.0.1 (HEVC, 30 s recordings):

| Recording | Before | With VCNEncodeFix |
|---|---|---|
| 3840x2160 @ 60 fps, 40 Mbps | 55 % of frames repeated | 0.3 % repeated |
| 3840x4320 @ 30 fps, 60 Mbps | about 10 fps encoded, 60 s to stop | real time, 0 repeated, 0.5 s to stop |
| 5120x2160 @ 30 fps, 60 Mbps | GPU stalls for seconds at a time, screen glitches | real time, 0 repeated, no GPU errors |
| VideoToolbox, 3840x2160, as fast as possible | 72 fps | 99 fps |
| VideoToolbox, 3840x4320, CPU-filled frames | 95 ms per frame | 22 ms per frame |
| VideoToolbox, HEVC 5120x2160, as fast as possible | GPU stalls for seconds per frame | 67 fps, no GPU errors |

In OBS, "skipped frames due to encoding lag" means OBS re-sent the previous picture because the encoder was busy:
the file has every frame, but those are duplicates. That number is the one to watch.

From 1.3.0 the service also fixes video calls (*cc*):

| Problem | What you see | Fixed by |
|---|---|---|
| Continuity Camera (an iPhone used as the Mac's camera) and FaceTime calls ask for the "FaceTime" HEVC decoder, which the AMD driver refuses | the video works, but the HEVC stream is decoded by the CPU; the log shows `[HEVC] GVA ERROR: Couldn't set the stream resolution` | **vcnencodefix** service (*cc*) |
| On a Mac Pro (MacPro7,1) or iMac Pro (iMacPro1,1) SMBIOS, FaceTime's encoder is sent to the T2 chip, which a hackintosh does not have | no outgoing video in FaceTime; the log shows `No bridgeOS device available` and `Failed to create remote video encoder with usage 42 on macOS, err = -18!` | **vcnencodefix** service (*cc*) |

## Requirements

- A Navi 21 GPU (device ID 0x73A0-0x73AF or 0x73BF). Only an RX 6800 XT has been tested.
- macOS **14.8.9 (23J631)**, **15.8.2 (24H232)**, **15.8.3 (24H241)** or **26.7.3 (25G342)**. Only 26.7.3 has been run
  on a GPU; the others were checked in IDA (same code and offsets) and with the CPU test of the wide patch. Every part
  checks the exact build of the Apple file it changes and stays off on any other build, so a macOS update cannot break
  anything; it only switches the fix off until a new version supports it.
- OpenCore with **Lilu 1.7.0 or newer** (for the kext).
- For the service: **SIP Debugging Restrictions** off (bit `0x4`, `CSR_ALLOW_TASK_FOR_PID`,
  in `csr-active-config`). The service patches Apple's encoder process the way a debugger
  does, and macOS refuses that even to root while this restriction is on: the log then
  shows `task_for_pid failed ((os/kern) failure)` and `vcnencodefix status` says
  `access REFUSED`. Check with `csrutil status`. To change it in OpenCore:
  1. Under `NVRAM > Add > 7C436110-AB2A-4BBB-A880-FE41995C9F82 > csr-active-config`, add
     `0x4` to the first byte of your current value (for example `03080000` becomes
     `07080000`; `67080000` and `FF0F0000` already have it).
  2. List `csr-active-config` under `NVRAM > Delete` for the same GUID (or reset NVRAM once).
  3. Reboot.

  The trade-off: root processes can then attach to system processes, as debuggers and
  dtrace do. The kernel half does not need this.
- Administrator access (sudo).

## Install

The zip instructions below are for the standalone release; in this repository use
`install/encoder.sh` (see [install/README.md](../install/README.md#the-encoding-fix)).

Download and unpack `VCNEncodeFix-<version>.zip`, open Terminal and `cd` into the folder.

1. **Service** (preset, wide-size and 10-bit HEVC fixes; active immediately, no reboot):

   ```
   sudo ./install.sh
   ```

2. **Kernel extension** (clock floor; needs a change in your OpenCore EFI and a reboot). Mount the EFI partition
   OpenCore boots from, then point the installer at it:

   ```
   diskutil list | grep EFI
   sudo diskutil mount disk1s1          # your EFI partition
   sudo ./install.sh --efi /Volumes/EFI # its mount point
   ```

   This copies `VCNEncodeFloor.kext` to `EFI/OC/Kexts` and adds one entry at the end of `Kernel > Add` (after Lilu).
   The installer first saves a copy of your config as `config.plist.backup-<date>-<time>-pre-vcnencodefix` next to it, and
   checks afterwards that the file equals the original plus that one entry. Then reboot.

   Keep a way to boot another EFI (a USB stick with your previous EFI) in case something goes wrong; restoring the
   backup over `EFI/OC/config.plist` undoes the change.

### Versions of the two halves

The service and the kext never talk to each other, so any 1.2.x service works with any 1.2.x kext: updating the
service alone is fine (the service 1.1.0 was installed and tested on the GPU here while the kext was still 1.0.1). A new
kext only takes effect after a reboot, and every change to its code (1.2.4 and 1.2.5 are) has to be booted once before it
counts as tested.

## Check that it works

```
./doctor.sh          # what is installed and active (sudo ./doctor.sh also shows each encoder process)
./test.sh            # two short encodes with reference numbers; writes a report to reports/
./test.sh --wide     # adds one 5120x2160 HEVC encode (only runs if the fix is confirmed active)
```

A healthy doctor output shows `VCNEncodeFloor: loaded <version>, active: encode`, the service `running`, and
`preset`, `wide`, `cc` and `hevc10` as `available`.

To check the cc fix: start the iPhone camera in any app, or a FaceTime video call, then

```
grep -E "ContinuityCaptureAgent|avconferenced" /var/log/vcnencodefix.log | tail -4   # "cc: patched (...)"
/usr/bin/log show --last 3m --predicate 'eventMessage CONTAINS "VCPDec" OR eventMessage CONTAINS "VCPEnc" OR eventMessage CONTAINS "bridgeOS"' | grep -E "Created|unsuccesful|GVA ERROR|bridgeOS"
```

`Created HW video decoder` and `Created video encoder with usage 42 on macOS` are the fix working; `[HEVC] GVA
ERROR: Couldn't set the stream resolution` or `No bridgeOS device available` mean it did not. `build/obj/ftenc_test`
(built by `build.sh`, run by hand) shows the encoder part without a call: it asks VideoProcessing for FaceTime's
encoder before and after writing the patch in its own process only.

## Uninstall

```
sudo ./uninstall.sh                      # removes the service
sudo ./uninstall.sh --efi /Volumes/EFI   # also removes the kext and its config entry (with a backup), then reboot
```

Apps that are open keep the fix until you quit them; the kext stays loaded until the next reboot.

## Options

- `sudo ./install.sh --preset balance` (or `quality`): a slower preset with better quality per bit than `speed`.
  The default `speed` is the one measured above; the others were not measured.
- `sudo ./install.sh --no-wide`, `--no-preset`, `--no-cc` or `--no-hevc10`: install with one of the four service fixes
  off.
- Boot arguments for the kext: `-vcnflooroff` turns it off; `-vcnfloorall` also applies the floor to hardware
  *decoding* (not tested); `vcnfloor=N` replaces the floor value the kext requests (default 132297; 0 is ignored;
  only the default was measured); `-vcnhevc10` (off by default; with the 1.2.6 service it gives a correct 10-bit picture on 26.7.3, see `hevc10` below) prepares
  `IOGVAHEVCEncode` = `"2"` and profile 2 (HEVC Main10) in `IOGVAHEVCEncodeCapabilities` on supported AMD
  accelerators, and with the 1.2.6 kext publishes Main10 only while the running `vcnencodefix` service reports the `hevc10` driver patch active through `hw.vcnhevc10` (waiting at `waiting for vcnencodefix service` or restoring the originals at `off: service says the driver patch is not active` if the macOS build is not validated, `--no-hevc10` is set, or the service stops; needs the 1.2.6 kext on the EFI and a reboot, and without the new kext nothing changes). Its state is in `VCNHEVC10` on `IOResources`; `-vcnfloordbg` and `-vcnfloorbeta` are
  Lilu's usual debug and newer-macOS switches.

## How it works

- **VCNEncodeFloor.kext** is a Lilu plugin. Each encode session sends AMD's power manager one clock request when it
  starts, and that request has a field for a minimum video clock that Apple's driver leaves at zero. The kext fills
  it (1400 MHz video clock, 1225 MHz decode clock) for encoder requests only. The minimum ends with the session,
  so the card idles as before. It only hooks AMD's power library if that library is the exact validated build.
- **vcnencodefix** is a small root service (LaunchDaemon `com.droga.vcnencodefix`). For every `VTEncoderXPCService`
  process (where macOS runs hardware encoders) it changes a few instructions in that process's memory, the way a
  debugger sets a breakpoint. Files on disk, the system volume and other processes are never touched.
  - *preset*: the driver reads the preset from a field nobody sets; the read becomes the constant "speed".
  - *hevc10* (26.7.3 only): the AMD library told the video engine the input was 8-bit NV12 for a 10-bit session and never passed the chroma quantizer offset the stream header declares for 10 bits (Cr -3). The service changes those two places in the driver, together or not at all. 8-bit and H.264 sessions are unaffected.
  - *wide*: just before the statistics job is sent to the GPU, the work is split into more, smaller thread groups
    (for example 2 x 160 threads instead of 1 x 320 for 5120 wide). The total work is the same, and below 4097 pixels
    wide nothing changes at all.
  - *cc*: for every `ContinuityCaptureAgent` (started when an app opens an iPhone camera) and `avconferenced`
    (FaceTime's call daemon, always running), three changes in its copy of VideoProcessing. Both decode the other
    side's video through AVConference and VideoProcessing's VCPDec, and both put `DecoderUsage = 1` in the decoder
    specification, which sends AppleGVA down its FaceTime path that the AMD driver refuses. Apple's own code already
    removes that key right before the hardware decoder (and puts it back for the software retry), but only for
    other codecs on some board-ids; the patch makes that removal run for every codec. The same key sent later as a
    session property is dropped too, by Apple's own check for it. The third change is for the encoder: on the Mac
    Pro and iMac Pro board-ids VideoProcessing sends FaceTime's encoder (usage 42) to the T2 and tells FaceTime that
    H.264 is unsupported; the patch jumps over the two board-id compares of that check, so H.264 is offered and the
    encoder is a local VideoToolbox one (the GPU's when FaceTime asks for hardware). Apple's `BridgeEncode`
    preference, which also needs a real bridge device, still works. Every other process keeps Apple's code.

  Before writing, it checks that the file is the validated build, that the bytes to change are exactly the expected
  ones, and that no thread is running them at that moment.

## Limitations

- Only the four macOS builds listed under Requirements, and only 26.7.3 was run on a GPU. Other builds: both halves
  stay off (`doctor.sh` says why).
- Only tested on one RX 6800 XT. Other Navi 21 cards use the same driver code but were not tested.
- With NootRX, macOS loads AMDRadeonX6800HWLibs instead of AMDRadeonX6000HWLibs. The kext hooks both (the function
  it changes is the same code), but it was only run with AMDRadeonX6000HWLibs.
- Power use while encoding was not measured; the clock floor keeps the video engine at full speed during an encode
  session, and only then.
- The quality cost of the `speed` preset was not measured.
- The HEVC encoder plug-in is loaded when an app creates its first HEVC session. The service finds a new encoder
  process within about 10 ms of its start and patches the plug-in within about 10 ms of it loading; OBS sends its
  first frame about 260 ms after the start (measured with 1.0.1 in OBS: patched 148 ms after the start). If a frame wider than 4096 is sent before the patch, that frame stalls
  the GPU for a few seconds (version 1.0.0 looked for new processes only every 250 ms and lost that race in OBS at
  5120x2160).
- cc knows the VideoProcessing of macOS 15.8.2 and 26.7.2/26.7.3 only; elsewhere it stays off and `status` says
  why. The decoder part was run with a real iPhone camera on an RX 6900 XT (15.8.2): `Created HW video decoder`, HEVC
  1920x1088 decoded in 5 to 9 ms a frame. The encoder part was run on its exact code in a test process on a
  MacPro7,1 SMBIOS (26.7.3, RX 6800 XT, `tests/ftenc_test.c`): before, H.264 reported unsupported and the session
  failed with -18; after, H.264 supported and the session, with hardware required, encoded 30 frames. No FaceTime
  call was tested. A process already running when the service starts is patched then, and the fix applies to the
  next decoder or encoder it creates (the next call, or stop and start the camera).
- HEVC Main only unless `-vcnhevc10` is set and the `hevc10` service fix applies (26.7.3 only; measured PSNR Y 47.0, U 43.7, V 46.1 dB). Sizes accepted by macOS are unchanged.
- The wide fix was checked by running its exact code on the CPU for every width up to 16384 (arguments identical
  to the original up to 4096 wide, the same total work above), and on the GPU at 5120x2160 only. Other widths above
  4096 were not encoded, and whether rate control behaves exactly as below 4096 was not checked.

## Troubleshooting

- `install.sh` says neither patch applies: your macOS build is not one of the supported ones, or there is no AMD
  driver.
- `VCNEncodeFloor: not loaded` after a reboot: check that OpenCore boots from the EFI you changed (its
  `EFI/OC/config.plist` must have the entry: `bin/vcnencodefix efi-check /Volumes/EFI/EFI/OC/config.plist`), that Lilu
  is loaded, and that `-vcnflooroff` is not in your boot-args. On macOS 14 or 15, an entry written by 1.2.0 or
  earlier has `MinKernel` 25.0.0 (Tahoe only) and OpenCore skips the kext: `efi-check` says "old entry", and
  `sudo ./install.sh --efi /Volumes/EFI` from 1.2.1 or later changes it to 23.0.0.
- `off: AMDRadeonX6000HWLibs build not validated` (or `X6800`): this macOS build's AMD power library differs from
  the validated ones; the kext stays off.
- `waiting for AMDRadeonX6000HWLibs or AMDRadeonX6800HWLibs` stays after boot: neither Navi 21 power library loaded,
  so the GPU is not a Navi 21 driven by macOS's AMD driver.
- The service log is full of `task_for_pid failed ((os/kern) failure)` and nothing gets patched: SIP's Debugging
  Restrictions are on (see Requirements). From 1.2.2 the line ends with ": SIP Debugging Restrictions are on" and
  `./doctor.sh` shows `access REFUSED`.
- The service log is `/var/log/vcnencodefix.log` (rotated at 1 MB).

When reporting a problem, include the report file `./test.sh` writes, or the output of `sudo ./doctor.sh`.
## Building from source

`./build.sh` builds the kext, the service and the test encoder, runs the tests and writes
`dist/VCNEncodeFix-<version>.zip`. It needs the Command Line Tools and the pinned kext SDK and OpenCore sample
config that `tools/bootstrap.sh` (at the top of the repository) fetches into `deps/`. See `docs/building.md`.
