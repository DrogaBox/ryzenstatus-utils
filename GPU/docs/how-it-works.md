# How it works

This page explains each part for a reader who knows macOS internals but not this code. It
says what the code does and where to look. What has run on which card is in
[status.md](status.md); this page only repeats a test result where it explains a design
choice.

Four parts, each independent of the others except where noted:

| Part | Runs in | Apple code it works with |
|---|---|---|
| AV1 and VP9 decoders | VideoToolbox's decoder processes | `AMDRadeonVADriver2`, the AMD video driver library |
| VCNVTLoader (`decode/loader/`) | the kernel, as a Lilu plug-in | AppleMobileFileIntegrity (AMFI) |
| Encoding fix | the kernel (VCNEncodeFloor) and a root service (vcnencodefix) | `AMDRadeonX6000HWLibs` or `AMDRadeonX6800HWLibs`; `AMDRadeonVADriver2` and `AppleGVAHEVCEncoder` inside `VTEncoderXPCService` |
| GPU sensors (`sensors/`) | the kernel, as a Lilu plug-in | `AMDRadeonX6000HWLibs` or `AMDRadeonX6800HWLibs` |

Every part checks the exact build of the Apple code it touches and does nothing on any
other build. [macos-updates.md](macos-updates.md) says what that means when macOS updates.

## The decoders

### How VideoToolbox finds them

Each decoder is a bundle (`AV1VCNDecoder.bundle`, `VP9VCNDecoder.bundle`). Its
`Info.plist` has a `CMClassImplementations` entry of class
`com.apple.videotoolbox.videodecoder` that names:

- the codec it decodes (`VTCodecType` `av01` or `vp09`) and `VTIsHardwareAccelerated`;
- the factory function VideoToolbox calls to make a decoder
  (`AV1VCN_VTDecoder_CreateInstance`, `VP9VCN_VTDecoder_CreateInstance`);
- the architecture, x86_64 only.

VideoToolbox reads these entries from `/System/Library/Video/Plug-Ins` without checking who
signed the bundle. In `/Library/Video/Plug-Ins` it only accepts bundles signed by Apple.
That is why the installer puts them on the system volume (see
[The installers](#the-installers)).

The factory builds a decoder object with CoreMedia's private plug-in interface
(`CMDerivedObjectCreate` with a `CMBaseClass` and a `VTVideoDecoderClass`). The layout of
those tables was recovered from Apple's own plug-ins and is described at the top of
`decode/av1/AV1VCNDecoder.c`. VideoToolbox then calls, among others:

- `startSession`, with the format description. The AV1 plug-in reads `av1C` and refuses
  anything but profile 0, 8 or 10 bits, 4:2:0. The VP9 plug-in reads `vpcC`. Both open a
  driver session here (below) and set the pixel buffer attributes of their output.
- `decodeFrame`, once per sample. Samples go to a serial dispatch queue, so frames are
  decoded and handed back in the order they came. At most four wait in the queue; the
  video engine still runs one command at a time. A synchronous call runs on the same
  queue, which keeps the order.
- `invalidate` and `finishDelayedFrames`. A call made from inside the output callback runs
  directly instead of waiting for the queue that is running the callback.

When `startSession` fails, the plug-in returns an error
(`kVTVideoDecoderNotAvailableNowErr` when the driver session could not be opened,
`kVTVideoDecoderUnsupportedDataFormatErr` for a stream it cannot decode). VideoToolbox can
then pick another decoder.

Safari and Chrome load the plug-ins in `VTDecoderXPCService`; Safari can also load them in
`com.apple.WebKit.GPU`. The code is the same in both.

Each plug-in logs to the unified log, subsystem `com.droga.vtav1vcn` or
`com.droga.vtvp9vcn`: one line per session start, an error line for each refused session
or sample, and a `stats` line every 120 frames (decode and queue times, the deepest queue,
and the count of firmware errors).

### The driver's function table

Apple's AMD video driver is a user-space library,
`/System/Library/Extensions/AMDRadeonVADriver2.bundle/Contents/MacOS/AMDRadeonVADriver2`.
Apple's own decoders (AppleGVA) use it for H.264 and HEVC. Its interface is not public;
`decode/common/avd.h` holds the part of it that was recovered, with only the fields the
decoders need named.

A session is opened like this (`vcnav1_create` in `decode/av1/vcnav1.c`):

1. `dlopen` the driver and read its `LC_UUID`. The decoder refuses to go on unless that
   UUID is in its own list, `kValidatedDrivers` (see [The driver check](#the-driver-check)).
2. Find the accelerator to hand to the driver: the first `IOAccelerator` whose `IOGVACodec`
   property starts with `AMD` (`vcn_find_accelerator` in `decode/common/vcndriver.c`). On
   a Mac with an active Intel iGPU, Intel's accelerator can come first in the list, and
   AMD's driver refuses it.
3. Call `AVD_CreateAVDAccelerator`, the one exported entry point. It returns a table of 16
   functions: `CreateDriver`, `DeleteDriver`, `CreateContexts`, `DeleteContexts`, the
   bitstream and pixel buffer pool functions, `ScheduleAVDCommands`,
   `QueryAVDCommandStatus` and the parameter getters and setters.
4. `CreateDriver`, then `AllocateBitstreamBufferPool`: four buffers of 0x1800000 bytes,
   used in turn, one per frame. Every buffer must come back with an address.
5. `CreateContexts` with one function description: AV1 (`0x1000000`), decode, mode 4, the
   session's maximum size, input `rawb`, output `NV12`. Mode 4 selects the first VCN
   instance. Modes 3 and 5 select the second one, which has no AV1 on Navi 21; AV1 there
   hangs the GPU.

The AV1 plug-in opens the session at no less than 4096x2304, so a stream that changes size
inside that does not need a new session, and at no more than 8192x4352. The VP9 plug-in
uses 4096x2304 and refuses larger streams; nothing has run VP9 above that on a GPU.

For each frame the decoder fills a parameter block (sequence header, frame header,
reference map, tile table, output surface) and sends one command with
`ScheduleAVDCommands`. The output is a fresh `CVPixelBuffer` from a pool whose IOSurfaces
have the layout checked on the engine: rows aligned to 256 bytes, height padded to a
multiple of 64, planes aligned to 4096. For portrait AV1 the rows are widened until the
pitch reaches the padded height: with a smaller pitch the driver leaves the picture blank
and reports no error. The decoder keeps nine reference slots (the DPB) and counts how many
reference entries point at each one, so a slot is reused only when no reference needs it.

### The wait for each frame (0.3.2)

After `ScheduleAVDCommands` the decoder waits for the command with
`QueryAVDCommandStatus`. As read in the 25G342 driver, that function has two forms. With
`wait = 0` it returns at once: status 1 done, 2 still running. With `wait != 0` it blocks
in the kernel until the command is done, with no time limit in user space, and then
returns the firmware's result for the frame.

Before 0.3.2 the decoder used the blocking form only, so a command the GPU never finished
could hold the session. Now `vcn_wait_command` (`decode/common/vcnsession.c`) asks without
blocking about every quarter of a millisecond, and makes the blocking call only once the
command is done. If a command is still running after one second
(`VCN_COMMAND_TIMEOUT_MS`), the session stops: nothing more goes to the GPU, and every
later frame of that session fails at once.

The firmware's result is counted and shown in the `stats` line as "firmware errors". A
frame is not refused for it, because what each value means for the picture has not been
checked on a GPU. The one-second limit has been tested on the CPU against a made-up driver
(`decode/tests/waittest.c`); it has not been tested on a real stuck command.

### Closing a session (0.3.3)

A session holds an accelerator (`AVD_CreateAVDAccelerator`: three IOKit connections, to the
device, its shared memory and a video context), a driver on it, the driver's bitstream
pool and one decode context. They are closed in the order Apple's own decoders use, read in
AppleGVA and the 25G342 driver: `DeleteContexts`, `FreeBitstreamBufferPool` (only when the
pool was allocated), `DeleteDriver`, `AVD_DestroyAVDAccelerator`, then the accelerator
service. Before 0.3.3 the accelerator was never destroyed: `DeleteDriver` does not do it,
so each session left its three connections open until the process ended
(`decode/common/vcnsession.c`).

Each of these steps can wait in the kernel while a command is still on the engine: deleting
a context sends the engine a destroy-session command and waits for it. A session whose
command never finished, or whose `QueryAVDCommandStatus` failed after the command went
out, is therefore closed on a background queue, with a log line before and after, and
VideoToolbox's invalidate returns at once. The plug-in then stays loaded until the process
ends. A failed driver call or a stuck command is reported to VideoToolbox as a malfunction
(`kVTVideoDecoderMalfunctionErr`), not as bad data, so the host can use another decoder;
`canAcceptFormatDescription` says no from then on. It reads the format under a lock of its
own, so it never waits for a frame the GPU is decoding.

### The parsers

The engine decodes the tile data; the host must read the headers. Each decoder has its own
parser, written for this project and kept apart from the driver code so the tests can run
it on any Mac:

- `decode/av1/av1parse.c` reads AV1 OBUs (sequence header, frame header, tile groups,
  sections 5.3 to 5.12 and 7.20 to 7.21 of the AV1 specification) and keeps the reference
  state between frames.
- `decode/vp9/vp9parse.c` splits VP9 superframes and reads the uncompressed header. The
  firmware reads the compressed header and the tiles itself, and keeps the probability
  contexts.

Both check their input before anything reaches the GPU: sizes against the session, tile
indexes, references that must hold a decoded picture, bit depth and chroma format. A
refused sample or header leaves the parser's state as it was. `tests/run.sh` reads the
public conformance streams with both parsers and compares every header, tile and reference
state with recorded digests, and runs them on damaged copies under the address and
undefined-behaviour sanitizers ([testing.md](testing.md)).

### VP9: borrowing the AV1 session

Apple's driver has no VP9 path. The VCN firmware does decode VP9, so the VP9 decoder opens
an AV1 session and replaces the driver code that builds the firmware messages
(`decode/vp9/vcnvp9.c`):

1. While `CreateContexts` runs, the decoder wraps one function of the driver's factory,
   `createDecodeDataProcessor`. The factory's table pointer is swapped for the length of
   that one call, under a lock.
2. When the factory makes the AV1 processor during that call, the wrapper points that one
   object at a copy of its class table in which five entries are the decoder's own:
   - the session create message gets VP9's codec number;
   - the DPB size and the context size are Mesa's numbers for VP9 on VCN 2 and later (the
     DPB is always sized for 8K, so it never has to be reallocated when the stream
     changes size, which would lose the references);
   - the context buffer starts with VP9's default probabilities
     (`decode/vp9/ac_vcn_vp9_default.h`);
   - the decode message is VP9's, in the layout of Mesa's `ac_vcn_dec.h`
     (`decode/vp9/vp9msg.h`), with the same index entries the driver sends for AV1.
3. Everything else is the driver's own: buffers, submission, the wait and the result.

If a later AV1 processor comes with another class table than the first one did, the
process stops (`abort`) rather than go on. The VP9 decoder has its own copy of
`kValidatedDrivers`, and the object offsets it uses were read in the 26.7.2 driver and
compared with the Sequoia one.

### The driver check

A wrong message to the video engine can hang the GPU until a reboot, and the parameter
layouts above were read from specific driver builds. So each decoder compares the
`LC_UUID` of the loaded `AMDRadeonVADriver2` with `kValidatedDrivers` in
`decode/av1/vcnav1.c` and `decode/vp9/vcnvp9.c`. On any other UUID the session does not
open and the log says `AMDRadeonVADriver2 build <uuid> not validated`. The same UUIDs are
in `install/validated-builds.json`, by macOS build; `install/check_lists.sh` fails when the
two lists disagree.

The plug-ins arm themselves. The test programs `decode_ivf` and `decode_vp9` use the same
code but must be armed by hand with an environment variable. See
[decode/tests/gpu/README.md](../decode/tests/gpu/README.md).

## Getting the plug-ins past AMFI

`VTDecoderXPCService` and `com.apple.WebKit.GPU` are Apple platform programs with library
validation: AMFI only lets them map code signed by Apple. The plug-ins are built ad-hoc
signed, so on a stock Mac AMFI refuses them even from the system folder. Something has to
vouch for them, and one of these is enough:

| Way | What it does | Where it was tried |
|---|---|---|
| AMFIPass | A separate kext. With it running, the plug-ins load | What the public installer has always relied on |
| Your own certificate authority | A separate kext, not part of RyzenStatus, makes macOS trust a CA of your own; the plug-ins are signed with it | Tahoe 26.7.3, also with AMFIPass switched off |
| VCNVTLoader (`decode/loader/`) | Allows exactly the plug-in builds listed inside it | Tahoe 26.7.3 with AMFIPass switched off; not booted on Sequoia |

A fourth way, `amfi_get_out_of_my_way=0x1`, switches AMFI off for everything; the installer
recognises it but does not advise it.

### VCNVTLoader

Every library validation refusal goes through one AMFI function,
`_library_validation_failure`, which returns non-zero when Apple's own exceptions allow the
library after all. VCNVTLoader routes that function through Lilu
(`decode/loader/kern_amfi.cpp`):

- If the library being mapped has a code directory hash (the `CDHash` that
  `codesign -dvvv` prints) on the kext's list, it returns "allowed".
- For anything else it calls Apple's function with the same arguments, so every other
  refusal stays as it was.

The hash covers the plug-in's code, its `Info.plist` and its resources, so a listed hash is
one exact build. The exception is tied to the build, not to the program or the folder.

The list is written when the kext is built (`decode/loader/build.sh`), from three places:
the plug-ins in `decode/build/`, the published releases in
`decode/loader/released-builds.txt` (none yet), and any bundle named on the command line.
That is why the kext and the plug-ins must come from the same build: a plug-in with one
changed byte has a new hash, and an older kext refuses it.

The kext routes the function only when its first instructions are a plain prologue (pushes,
`mov rbp, rsp`, `sub rsp`) and the hash accessor it calls starts with the 13 bytes read in
the AMFI of 14.8.9, 15.8.2, 26.7.2 and 26.7.3 (`decode/loader/allow_logic.hpp`). The
route is a long jump, so another Lilu plug-in can route the same function later; if another
one got there first, VCNVTLoader stays off. It only starts on Sequoia and Tahoe. Its state
is in `ioreg -r -c VCNVTLoader -l`: `Status`, `AllowedBuilds` and `Overrides` (plug-ins
let through since boot).

The kext does nothing for the encoding fix's service.

## The encoding fix

The fix has two halves. Each one works without the other.
[encode/README.md](../encode/README.md) has the measurements and the install steps.

### VCNEncodeFloor: the clock floor

Each hardware encode session on Navi 21 sends AMD's power manager one clock request when it
starts (`PEM_CWDDEPM_PMRequest` in the HWLibs kext). The request has a field for a minimum
video clock (`VclkFloor`) that Apple's encoder leaves at 0, so the video engine (VCN) can
stay at its lowest level for the whole session.

VCNEncodeFloor is a Lilu plug-in that routes `PEM_CWDDEPM_PMRequest`
(`encode/kext/kern_start.cpp`). For a request from a VCN client with `VclkFloor` 0 and a
non-zero minimum memory clock, it passes on a copy with `VclkFloor` set to 132297 (in units
of 10 kHz). Only the encoder fills the memory clock field; the decoder's request leaves it
at 0, so decoding is left alone unless `-vcnfloorall` is set (not tested). The firmware
rounds that floor up to its 1400 MHz video clock level, and the same value sets the decode
clock's minimum to 1225 MHz, its top level. Only this value was tested. The floor ends with
the session's power client, so the card idles as before.

macOS has two Navi 21 power libraries, `AMDRadeonX6000HWLibs` and `AMDRadeonX6800HWLibs`
(the second with NootRX). The function is the same code in both, and the kext hooks
whichever loads; it has only run with X6000. It routes the function only when the library's
`LC_UUID` is in its per-build tables (`kX6000Builds`, `kX6800Builds`). On 15.8.x and
26.7.3 it finds the function by symbol. On 14.8.9, whose libraries are stripped, it uses a
fixed offset and first compares 32 bytes there. Its state is the `VCNEncodeFloor` property
of `IOResources`.

The floor must stay inside each chip's own video clock levels: the firmware takes the
value / 100 as the VCLK minimum in MHz, rounded up to a level, and its low 16 bits as the
DCLK minimum. The same driver family runs chips whose top levels are below 1322/1225 MHz
(an RX 5600 XT table tops out at 1267/1086). So from 1.2.4 the kext lists the GPUs
through Lilu when it starts and sets the floor only when every AMD GPU is a chip whose
clock table was read (`encode/kext/floor_logic.hpp`): Navi 21 (this Mac's table, VCLK
363/1400 and DCLK 317/1225) and Navi 23, the RX 6600 family (two published RX 6600 XT
tables, VCLK 690/1429 and DCLK 572/1250; not run on a card). On any other GPU its state
starts with `off:`, unless `vcnfloor=N` is on the boot arguments, which is taken as the
user's own value. If Lilu cannot list the GPUs, it works as before. 1.2.4 has been booted on
Navi 21 only.

### vcnencodefix: the service

A root LaunchDaemon (`com.droga.vcnencodefix`) watches for `VTEncoderXPCService`
processes, where macOS runs hardware encoders, and changes a few instructions in each one's
memory, the way a debugger sets a breakpoint: the page is made copy-on-write in that process
only, and the process is suspended for the write. Nothing on disk changes. The two patches
are in `encode/tool/patches.c`:

- **preset**, in `AMDRadeonVADriver2`: the driver reads the encoder preset from a field
  that nothing in Apple's code sets, so the firmware uses its slow default. The load
  becomes the constant for `speed` (or `balance` or `quality`, which were not measured).
- **wide**, in `AppleGVAHEVCEncoder`: every HEVC frame runs a statistics compute kernel
  with one thread group of width/16 threads. That pipeline allows at most 256 threads per
  group, so above 4096 pixels wide the GPU stalls on every frame. Right before the
  dispatch, the patch splits the same grid into more, smaller groups. Up to 4096 wide the
  arguments are exactly the original ones.

Before writing, the service checks that the image's `LC_UUID` is a validated build, that
the bytes to change occur exactly once and are the expected ones (or already patched), and
that no thread is running them. The driver is in the dyld shared cache, at the same address
in every process. The HEVC plug-in is loaded by each encoder process with its first HEVC
session, so the service watches each new process's image list every 10 ms and patches the
plug-in as soon as it appears.

Reading and writing another process's memory needs SIP's Debugging Restrictions off (bit
`0x4` of `csr-active-config`); with them on, macOS refuses even root, and
`vcnencodefix status` says `access REFUSED`. The kext half does not need this.

## The GPU sensors

Apple's driver asks its power library for a table of sensor readings, the PMLog, about once
a second, keeps seven values for `PerformanceStatistics` and drops the rest.
`GPUSensors.kext` (`sensors/kext/`) routes the function that hands the table back,
`_PEM_CWDDEPM_QueryPMLogData`. It calls Apple's function first with the same arguments,
returns its answer unchanged, and keeps a copy when the table is filled. It never asks the
GPU or its firmware anything itself.

The table is 2052 bytes: a header, then for each of 256 ids a "supported" flag and a value,
in AMD's ADL_PMLOG numbering (`sensors/kext/pmlog_logic.hpp`). On an RX 6800 XT the driver
fills 12 ids by default. The kext also sets the driver's own setting
`PP_EnableAllPMLogSensors` to 1 on each Navi 21 card before the power management starts, so
the driver keeps the values it already reads every second; a value given in the OpenCore
DeviceProperties is left alone, and `-gpusensnoall` leaves the setting alone.
[sensors/README.md](../sensors/README.md) explains why the driver fills only 12 values and
what each one is.

The readings are properties of `DrogaBoxGPUSensors` in the I/O Registry (`Sensors`,
`Units`, `PMLog`, `Samples`, `SampleAgeMs`, `Status`). They are rebuilt when the whole
property table is read, which is what `ioreg -l` and `sensors/build/gpusensors` do.

The kext routes the function only when its first 17 bytes are the ones seen in both
libraries of 15.8.2, 15.8.3, 26.7.2 and 26.7.3; otherwise `Status` says
`off: function does not start as expected`. It starts on Sequoia and Tahoe only.

## The installers

Everything in `install/` is a zsh script with `--help`. The `check` commands change
nothing and need no `sudo`. Details are in [install/README.md](../install/README.md).

- `decoders.sh` puts the two plug-ins in `/System/Library/Video/Plug-Ins`. The system
  volume is a sealed snapshot, so `install` mounts it writable at
  `/System/Volumes/Update/mnt1`, copies each bundle under a temporary name, checks its code
  signature hash and swaps it in, then runs `bless --create-snapshot`. The change takes
  effect at the next boot. It needs authenticated-root disabled. `check` also finds what
  lets the plug-ins past AMFI on this Mac and, for VCNVTLoader and an own CA, asks macOS
  whether it would load these exact plug-ins with `decode/build/lvprobe`, which makes the
  same two kernel calls dyld makes before mapping a library and stops there.
- `loader.sh` and `sensors.sh` put their kext in `EFI/OC/Kexts` and add one entry to
  `Kernel > Add` in OpenCore's `config.plist`, after Lilu. The shared code is
  `install/efikext.zsh`; the editor is `decode/build/kextentry`. A backup of
  `config.plist` is written first, and the edit is checked: the new file must be the old
  one plus the entry. The kext is copied before the entry is added, and removed after it.
- `encoder.sh` runs its checks and hands over to the encoding fix package's own
  `install.sh`, which installs the service and, with `--efi`, the kext.
- `install.sh` puts all of it together: `install.sh plan` (no `sudo`) runs every part's
  `check` and lists what this Mac still needs (the loader only without AMFIPass and with
  AMFI on; the encoding fix and the sensors only when asked for). If any needed part is
  blocked it installs nothing. With `sudo` it finds the OpenCore EFI once, hands it to
  every EFI part, installs in order (loader, decoders, encoding fix, sensors) and stops at
  the first failure.
- `undo.sh` removes whatever it finds installed, each part with its own `uninstall`, EFI
  parts first.
- `check.sh` runs the `check` of each part and prints one line per part and one for the
  whole. It counts the loader kext only when this Mac needs it (no AMFIPass, AMFI not
  switched off). It ends with status 0 only when the decoders work now.

`decoders.sh` and `encoder.sh` refuse a macOS build that is not in
`install/validated-builds.json`; `loader.sh` and `sensors.sh` check the macOS version, and
`sensors.sh` also the driver function's first bytes. The plug-ins and the kexts check again
on their own when they run.
