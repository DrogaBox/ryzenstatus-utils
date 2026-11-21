# What has been tested, and what has not

Each line says who ran what, on which card and macOS build. "Static" means checked without
running on a GPU: compared in a disassembler, run on the CPU, or tested with files.

## Decoders

| Check | Result | Version | Where |
|---|---|---|---|
| AV1 conformance streams decoded bit for bit (43 clips, portrait sizes up to 2160x3840) | pass | 0.2 | RX 6800 XT, Tahoe 26.7.3 |
| VP9 conformance streams decoded bit for bit (18 clips) | pass | 0.2 | RX 6800 XT, Tahoe 26.7.3 |
| VP9 `vp90-2-05-resize` (changes size: frames 4 to 6 are 282x173 inter frames predicted from 352x288 references) | all 10 frames match libvpx's own reference (`vp90-2-05-resize.ivf.md5`, listed in libvpx's `test/test-data.sha1`). FFmpeg's FATE reference differs on frames 4 to 6 because that test scales every frame to 352x288 before hashing (`-s 352x288` in `tests/fate/vpx.mak`); it was taken for a decoder fault from 2026-11-06 until 2026-11-18 | pass | 0.1 to 0.3.2 | RX 6800 XT, Tahoe 26.7.3 |
| YouTube 4K60 AV1 in Safari and Chrome | plays, 6 frames dropped of 2509 | 0.1 | RX 6800 XT, Tahoe 26.7.1 |
| Daily use, Safari and Chrome | no decoder errors in the system log over three days | 0.2 | RX 6800 XT, Tahoe 26.7.3 |
| AV1 vectors and playback | pass | 0.1 | RX 6900 XT, Sequoia 15.8.2 (Izzy) |
| VP9 check clip (640x360, 30 frames) | 0 mismatches | 0.2 | RX 6900 XT, Sequoia 15.8.2 (Izzy) |
| Driver of 15.8.3 and 26.7.3 | same binary (same UUID) as 15.8.2 and 26.7.2 | static | |
| Parser reads the public test streams as 0.2 did | identical digests | 0.3.0 | static, `tests/run.sh` |
| Parser on damaged input, under sanitizers | no finding in 14100 damaged copies of 47 local streams, and 4500 of the 15 public ones in `tests/run.sh` | 0.3.0 | static |
| Only AMD's accelerator is taken | rule tested; on a Mac with no iGPU the choice is the same as 0.2 | 0.3.0 | static, RX 6800 XT |
| Installed in the system and decoded through VideoToolbox (no test loading): 8 AV1 conformance vectors, 32 AV1 clips at portrait and odd sizes up to 2160x3840, 4 VP9 clips | 0 mismatches, 0 errors, hardware decoder in use, no GPU error in the log | 0.3.0 | RX 6800 XT, Tahoe 26.7.3, 2026-11-17 |
| Plug-ins' VideoToolbox side with a stand-in decoder: frames emitted, calls from inside the output callback, invalidate, second start, other codec's format | pass | 0.3.1 | static, `tests/run.sh` |
| A refused VP9 header leaves the parser's state as it was | pass | 0.3.1 | static, `tests/run.sh` |
| The wait for each decode command: done, still running, driver error, odd status, and the one-second limit, against a made-up driver | pass | 0.3.2 | static, `tests/run.sh` (waittest) |
| 0.3.2 in a test process (`decode_ivf`, `decode_vp9`, nothing installed): 8 AV1 conformance vectors and three 4K AV1 clips, 16 VP9 conformance clips | 0 mismatches (`05-resize` against libvpx's reference, see above); firmware result 0 on every AV1 frame checked (4K, film grain, 10-bit) | 0.3.2 | RX 6800 XT, Tahoe 26.7.3, 2026-11-18 |
| 0.3.2 against 0.3.1, same clips, no pixels read | AV1 4K 121.6 against 123.3 fps and 111.4 against 112.3 fps; VP9 4K 151.7 against 152.6 frames/s (p50 6.04 against 6.00 ms): within about 1 % | 0.3.2 | RX 6800 XT, Tahoe 26.7.3, 2026-11-18 |
| Each decoder session against a made-up driver (both codecs): accelerator, driver, pool and context released once, in Apple's order (context, pool, driver, accelerator), also after a failed CreateDriver, pool allocation or CreateContexts; a pool never allocated is never freed; a driver without `AVD_DestroyAVDAccelerator`; a pool with a missing buffer; a failed accelerator create that leaves its result set; a command that never finishes, a failed `QueryAVDCommandStatus` and a failed `ScheduleAVDCommands` are device failures that stop the session; after the first two the session is closed on the background queue, not on the caller's thread | pass | 0.3.3 | static, `tests/run.sh` (sessiontest) |
| Plug-ins: a device failure is reported as `kVTVideoDecoderMalfunctionErr`, bad data as `kVTVideoDecoderBadDataErr`, no memory as `kVTAllocationFailedErr`; no format accepted after a failed start, a device failure or invalidate; `canAcceptFormatDescription` does not wait for a running decode; a start that invalidate overtakes closes its new session | pass | 0.3.3 | static, `tests/run.sh` (plugintest) |
| 0.3.2 installed (`install/loader.sh` with the EFI found automatically, `install/decoders.sh`), rebooted: YouTube 3840x2160 @ 60 in Chrome, AV1 and VP9 | `install/check.sh` working; both at 60 fps with 0 frames dropped over 20 s; 14 jumps back and forth, one of them dropped 31 frames (the first jump to a part not loaded yet; the same jump three more times dropped none); every `stats` line said "firmware errors 0" (51 lines); video clock back to 0 after closing, no GPU error, no crash report | 0.3.2 | RX 6800 XT, Tahoe 26.7.3, 2026-11-18 |
| Machine with an Intel iGPU active | the cause was confirmed on a user's iMac19,1 (UHD 630 listed first); decoding with 0.3.0 not run there | | |
| Installed with `install/decoders.sh`, loader kext rebuilt for the new plug-ins, rebooted | `install/check.sh` says working; the plug-ins on the system volume are 0.3.1 | 0.3.1 | RX 6800 XT, Tahoe 26.7.3, 2026-11-18 |
| 4K AV1 in Safari | plays in hardware | 0.3.1 | RX 6800 XT, Tahoe 26.7.3, 2026-11-18 |
| YouTube 3840x2160 @ 60 AV1 in Chrome | 3 frames dropped of 1245; ten jumps back and forth, playback resumed after each with no frame dropped around them | 0.3.1 | RX 6800 XT, Tahoe 26.7.3, 2026-11-18 |
| YouTube 3840x2160 @ 60 VP9 in Chrome (AV1 hidden from the page so it falls back to VP9) | 0 frames dropped of 2191, decode about 8 ms a frame, decoder process about 3 % of one core | 0.3.1 | RX 6800 XT, Tahoe 26.7.3, 2026-11-18 |
| Two tabs at once: two 4K60 AV1 videos, and two 3840x2160 VP9 files | each tab its own session, both at full rate, 0 frames dropped | 0.3.1 | RX 6800 XT, Tahoe 26.7.3, 2026-11-18 |
| Closing a tab while it plays (AV1 and VP9) | the other tab keeps playing; after the last one the video engine's clock goes back to 0; no decoder error line, no GPU error, no crash report | 0.3.1 | RX 6800 XT, Tahoe 26.7.3, 2026-11-18 |
| 3840x2160 VP9 files in Chrome, eight jumps back and forth | playback resumed after each, 0 frames dropped of 1426 | 0.3.1 | RX 6800 XT, Tahoe 26.7.3, 2026-11-18 |

The jumps and tab checks ran in Chrome, which loads the plug-ins in `VTDecoderXPCService`;
Safari can also run them inside `com.apple.WebKit.GPU`. The plug-in code is the same in both.

Not tested at all: 0.3.3 on any GPU (its release of the accelerator, the new teardown
order, the background close of a stuck session and the new error codes are checked only
against a made-up driver; `AVD_DestroyAVDAccelerator` was read in the 25G342 driver only,
not in Sequoia's); 0.3.2 in Safari; the one-second limit on a real stuck command; 0.3.0 to
0.3.3 on any card other than the RX 6800 XT; Sonoma; any card other than the two above; a
Chrome stall reported by a user on Sequoia 15.8.3 (videos that sometimes do not start until
Chrome restarts; a log was asked for). 0.3.3 fixes the most likely cause found in the code
(every session left its accelerator, three IOKit connections, open until the process
ended); that this was the user's problem is not shown.

## GPU sensors

| Check | Result |
|---|---|
| What each value of the driver's PMLog is | Read in the driver (the filler, its printer and the reader behind PerformanceStatistics); they agree with AMD's ADL_PMLOG numbering |
| First bytes of the routed function, AMDRadeonX6000HWLibs and AMDRadeonX6800HWLibs, 15.8.2, 15.8.3, 26.7.2, 26.7.3 and this Mac | Identical, accepted |
| Imports of the kext | All found in this kernel or in Lilu |
| Booted, RX 6800 XT, Tahoe 26.7.3, 2026-11-18 | Loaded from OpenCore on the first boot, active, about one reading a second at idle. The driver fills 12 of the table's values (ids 1, 2, 8, 14, 15, 19, 20, 21, 23, 27, 40, 41); memory and VR temperatures, SOC and memory voltages, throttler status and the video and fabric clocks come back empty |
| Against PerformanceStatistics | The same values for memory clock, fan, board power and hotspot; PCIe generation 3 and 8 lanes, the same as the root port's link |
| 0.2.0: the driver's setting PP_EnableAllPMLogSensors | Read in the driver: one use, at the start of the power management, through a registry callback that reads the GPU device's properties; the values it adds are already read every second. Booted 2026-11-18 on the RX 6800 XT: the GPU device shows the setting at 1 and the driver fills all 26 published ids; memory VR 0 and 1 temperatures read 0 on that card. Video clocks: 0 at idle, 362/316 MHz while a video plays (2026-11-18) |

## Encoding fix

| Check | Result | Version | Where |
|---|---|---|---|
| OBS HEVC 3840x2160 @ 60 | 55 % repeated frames before, 0.3 % after | 1.0.1 | RX 6800 XT, Tahoe 26.7.3 |
| OBS HEVC 3840x4320 @ 30 and 5120x2160 @ 30 | real time, no repeated frames, no GPU errors | 1.0.1 | RX 6800 XT, Tahoe 26.7.3 |
| Kext loaded from the EFI at every boot | yes (built as 1.2.0 it is byte-identical to the kext in use) | 1.2.0 | RX 6800 XT, Tahoe 26.7.3 |
| Service | installed and running | 1.2.2 | RX 6800 XT, Tahoe 26.7.3 |
| Service reopens its log after a rotation | the line after a rename goes to a new file | 1.2.3 | run as a user process, not installed |
| Test script (preset, floor, wide) | 4K60 at 104 fps, 3840x4320 p50 19.6 ms, 5120x2160 at 72 fps | 1.2.1 | RX 6900 XT, Sequoia 15.8.3, reported by a user |
| Wide patch run on the CPU at the call site of each validated build (14.8.9, 15.8.2/15.8.3, 26.7.3), widths up to 16384 | pass | 1.2.3 | static, `encode/tests` |
| OpenCore config editing (23 cases) | pass | 1.2.3 | static |
| `install/encoder.sh install --efi` as root, then a reboot | kext 1.2.3 loaded from the EFI, service 1.2.3 running and patching each new encoder | 1.2.3 | RX 6800 XT, Tahoe 26.7.3, 2026-11-18 |
| Test script (preset, floor) | 4K60 at 101.6 fps, 3840x4320 p50 21.7 ms, 0 errors, no GPU messages | 1.2.3 | RX 6800 XT, Tahoe 26.7.3, 2026-11-18 |
| The same while Safari decodes a 4K AV1 video | 4K60 at 72.7 fps, 3840x4320 p50 26.5 ms: decoding and encoding share the video engine, so measure with nothing else playing | 1.2.3 | RX 6800 XT, Tahoe 26.7.3, 2026-11-18 |
| Kext sets the floor only on chips whose clock levels were read: Navi 21 (0x73A0 to 0x73AF, 0x73BF) and Navi 23 (0x73E0 to 0x73EF, 0x73FF); others off | booted on Navi 21: "active: encode"; `floor_test` passes on 20 device-ids; Navi 23 levels from two published RX 6600 XT tables, not run on a card | 1.2.4 | RX 6800 XT, Tahoe 26.7.3, 2026-11-18 |
| `install/encoder.sh install --efi auto` as root, then a reboot; the package's `test.sh` | kext 1.2.4 and service 1.2.4 (unchanged since 1.2.3 except its version) loaded; test 1 (preset, HEVC 4K, 300 frames) 102.1 fps; test 2 (floor, 3840x4320, 60 CPU-filled frames) p50 21.3 ms; no GPU messages from the kernel. The kext's own "GPUs:" log line was not found in the unified log | 1.2.4 | RX 6800 XT, Tahoe 26.7.3, 2026-11-18 |

Not tested: the uninstall scripts as root; Sonoma 14.8.9 and Sequoia 15.8.2 on a GPU; RX 6800 and RX
6900 XT with Apple's X6000 library; the `balance` and `quality` presets; power use while
encoding.

## Install options

| Option | State |
|---|---|
| With AMFIPass or `amfi_get_out_of_my_way=0x1` (the bundles are ad-hoc signed) | what the public installer has always done |
| Bundles signed with an own certificate authority and a kext that makes macOS trust it, AMFIPass loaded | runs on the test machine, Tahoe 26.7.3 |
| The same with AMFIPass switched off (`-amfipassoff`) | one boot, 2026-11-18, RX 6800 XT, Tahoe 26.7.3: Safari played VP9 at 3840x2160 and a WebKit test page played AV1 at 3840x2160, both in hardware inside `com.apple.WebKit.GPU`; the encoding fix service kept running; no signature refusal in the log |
| Ad-hoc bundles with nothing else (no AMFIPass, no kext) | refused, as expected: an ad-hoc library is not mapped into a program with library validation (measured with a test program, same boot) |
| Ad-hoc bundles with the loader kext 1.1.0, no AMFIPass | one boot, 2026-11-18, RX 6800 XT, Tahoe 26.7.3: kext active; Safari played YouTube AV1 and VP9 at 3840x2160 in hardware (plug-ins mapped in `VTDecoderXPCService` and `com.apple.WebKit.GPU`); the kext's counter went up with each load; an unlisted ad-hoc library stayed refused. Entry check passes on the AMFI of 14.8.9, 15.8.2, 26.7.2 and 26.7.3. Not tried on Sequoia |
| The installers in that mode (`-amfipassoff`, loader needed) | 2026-11-18, Tahoe 26.7.3: decoders 0.3.2 and the loader installed with `install/loader.sh` and `install/decoders.sh`, rebooted; `install/check.sh` says "Overall: working", the loader "Needed on this Mac: yes" and active (94 plug-in loads let through since that boot); `install/install.sh plan` finds nothing left to install. Not tried from a Mac that never had AMFIPass |
| The encoding fix service, ad-hoc signed, without AMFIPass | 2026-11-18, RX 6800 XT, Tahoe 26.7.3, boot with `-amfipassoff` (AMFIPass loaded but off, AMFI on): the 1.2.4 service installed by `install/encoder.sh` is ad-hoc signed with no entitlements and runs as a LaunchDaemon; it patched each encoder (preset and wide active) and `test.sh` gave 102 fps and p50 21.3 ms. Needs SIP's Debugging Restrictions off, as always |

Putting the loader kext on the EFI: `install/loader.sh` (2026-11-18). Tried on made-up EFI
folders (tests/loader_install.sh) and on a copy of the test machine's EFI, then run for real
on the test machine's EFI partition (`install/loader.sh install --efi diskNsM`, followed by
`install/decoders.sh install` and `install/encoder.sh install --efi diskNsM`, 2026-11-18):
the kexts on the partition matched the package, the config passed its checks, and after the reboot
VCNVTLoader 1.1.0 and VCNEncodeFloor 1.2.3 loaded from it. Not run on a Mac whose EFI is on
another disk.
