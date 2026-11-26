# Changelog

The encoding fix keeps its own history in `encode/CHANGELOG.md`.

## JPEG decoder 1.0.0 (RyzenStatus 1.90.0)

- New, optional, macOS 26.7.3 only: `VCNJpeg.kext` (`jpeg/`) and the VideoToolbox plug-in
  `JPEGVCNDecoder.bundle` (`decode/jpeg/`) decode JPEG and Motion JPEG (`jpeg`, `dmb1`) on
  the JPEG block of the VCN, which Apple's driver carries but never starts. Baseline 4:2:0
  and 4:2:2; anything else goes to Apple's software decoder.
- The kext creates the JPEG queue and a 128 MiB block of buffers (`vcnjpegpool=<MiB>`, 8 to
  128) when the driver starts its video queues, and powers the block only while pictures
  arrive: PowerPlay client 21 and the queue start with the first picture, both are given
  back two seconds after the last one.
- Off by default: `install/install.sh --with-jpeg`, or `install/jpeg.sh install` and
  `install/decoders.sh install --jpeg`. The package carries them only when built with
  `VCNVT_JPEG_DECODER=1`. The loader kext lists the JPEG plug-in too.
- It comes from the test kext that decoded through the same plug-in on an RX 6800 XT
  (4:2:0, 4:2:2 and `dmb1` at 1280x720, under 5 ms a frame, within 1 of FFmpeg). The
  product kext ran once on an RX 6800 XT with 26.7.3 (2026-11-25, started from a separate
  OpenCore config): four VideoToolbox cases decoded on the GPU at 74 to 75 dB against the
  reference, 90 frames through `avconvert`, and the block powered off two seconds after the
  last picture.
- `install.sh --with-jpeg` takes the kext as installed only when the config.plist it installs
  to lists it: a kext started from another config file (one picked in OpenCore for one boot)
  was skipped before, though the next normal boot would not load it.

## GPU sensors 0.9.0 (RyzenStatus 1.90.0; host tests only)

- A program may now hold a raised GFX minimum clock (OD8 id 1) with the rest of the OD8
  state: `gpucontrol hold gfxmin 1500 -- <command>`, `gpucontrol check gfxmin 1500`. It is
  taken only inside the card's own range for it (the 0x9f entry: 500 to 2800 MHz on the test
  RX 6800 XT, stock 500) and never above the GFX maximum of the same state (the stock one, or
  the lowered one held with it): the driver's own rule (`PhwComm_OD8_SetGfxClockLimits`: both
  requested, each in its range, minimum at most the maximum). Anything else is refused with
  the new reason `GfxMinRange` (12), never clamped. It goes back to stock in the same cases
  as the rest of OD8 (release, close, 30 s of silence, a wake), through the same stock pair.
- It is the first setting that can make the card warmer at idle, so it is taken only while
  the fan watchdog has fresh readings, and the watchdog runs while it is held: 95 C, or no
  readings for 10 s, puts stock back and turns writing off. The "too hot with the fan under
  90 %" rule stays with a held curve, because the stock fan climbs slowly by design.
- The read-back allows the minimum to read up to 25 MHz lower than sent, never higher, as
  for the maximum. Whether the firmware ever rounds it is not known yet.
- The channel stays version 2: `setOd8` takes 14 scalars (the 14th is the minimum) as well as
  the 0.7.0 form of 13, `status` sets flag 512 (`kFlagGfxMin`), `OD8WriteState` gains `Held`
  bit 16, `GfxMinHeld` and `Takes` (23: what `setOd8` takes). An older kext refuses the
  14-scalar form with a wrong-count error; `gpucontrol` and the app send it only with a
  minimum.
- A lower GFX voltage (OD8 id 37, the firmware's `VddGfxOffset`): `gpucontrol hold volt 1050
  -- <command>`. Read end to end in HWLibs 25G342: the driver offers it with
  `PP_OD8VoltageSliderSupport` (the Navi 21 default, 1) as a range from swsmu+328 to swsmu+332
  (881 to 1075 mV on the test card, stock 1075), stages value minus the top as the OD table's
  `VddGfxOffset` (int16 mV, written whole to the firmware) and reads it back as top plus
  offset. So it is a millivolt cap that moves the whole voltage curve down, and it cannot go
  above the top. Linux writes the same field and needs SMU firmware 58.41.0 or later (the
  test card: 58.76.0). The kext takes it lower only (at or below stock, at or above the card's
  minimum) in 25 mV steps from stock, reads it back exactly, and sends the stock value in
  every other call so a way back never leaves an offset behind. Refused: `VoltRange` (13);
  not offered or not allowed now: `NoFeature`.
- Raises, only when the request asks for them and only inside the card's own OverDrive
  range: a GFX maximum above stock up to the 0x9f maximum (2800 MHz here) with `setOd8` flag
  4, `gpucontrol hold gfxmax 2500 overclock -- <command>`; and a power limit above the
  start-up one with `set`'s new 3-scalar form (flag 1), `gpucontrol hold power 260 raise --
  <command>`, up to `PowerRange.CeilW` = start-up limit x (100 + the 0x9f power percent) /
  100, the way Linux takes `power1_cap_max`, the percent cut at +15 (261 W on the test card,
  +9 %). The driver's 0x6e path has no ceiling of its own (it sends SMU message 0x32 with the
  watts as given), so this is the only one. One step past either maximum is refused
  (`GfxRange`; the new reply 21 `AboveCeiling`). Each raise is taken only while the watchdog
  has fresh readings (new reply 22 `NoReadings` for `set`) and is held under it: 95 C or no
  readings for 10 s puts stock back and turns writing off (new `WriteOff` 16
  `PowerWatchdog` for the power limit).
- The channel stays version 2: `setOd8` also takes 15 scalars (the 15th is the voltage),
  `set` also takes 3, `status` sets flags 1024 (`kFlagVolt`) and 2048 (`kFlagRaise`),
  `OD8WriteState` gains `Held` bits 32 (voltage) and 64 (GFX maximum above stock), `VoltHeld`,
  and `Takes` 119; `PowerRange` gains `CeilW`. An older kext refuses the new counts.
- Not added, and why (read in the 25G342 driver, 2026-11-25): the memory maximum (id 8) and
  fast memory timings (id 14, AC timing). Both start with `PhwComm_OD8_StartMemoryOverclock`
  -> `PECI_StartGPUMemoryOverclock`, an IRI call 0x110018 to the display driver, and on macOS
  that interface is `AtiAppleDalServices::dalIriFunction`, which has no case for 0x110018 (nor
  0x110019, the end) and answers status 1, so the start fails. A memory maximum then makes
  `PhwComm_OD8_ApplySettings` return before the OD table is written (the whole call fails
  and the new clock stays staged), and fast timings are recorded but never programmed
  (nothing could be read back). Also not added: the fan minimum speed (id 10) and fan target
  temperature (id 12), which the driver does not offer while the fan curve is offered
  (feature 0, and `PhwComm_OD8_SetGenericSetting` skips a setting whose feature is 0).
- `gpucontrol status` names a held GFX maximum above stock "GFX max raised" (it said
  "lowered" for every held maximum) and shows a held voltage as "GFX voltage lowered".

## Decoders 0.3.7 (RyzenStatus 1.90.0)

Everything since 0.3.5, the last release. The sleep part was host-tested only; the rest as
said in each item.

- Colour and HDR metadata: every AV1 and VP9 picture now carries its colour primaries,
  transfer function and matrix, plus the mastering display colour volume and content light
  level when the stream or the container has them. Before, BT.2020 PQ video was shown as
  untagged video (washed out, no HDR). AV1 takes them from the sequence header first and the
  container where the header says nothing, and keeps the `HDR_MDCV` and `HDR_CLL` metadata
  OBUs (a cut or unknown one changes nothing); VP9 takes the container first, then the
  bitstream's `color_space` (VP9 has no transfer function of its own). Host tests only; not
  run on the GPU yet.
- New, optional, macOS 26.7.2 and 26.7.3 (and 26.7.4, same driver code): MPEG-2, VC-1 and
  MPEG-4 part 2 decoders (`decode/mpeg2/`, `decode/vc1/`, `decode/mpeg4/`), installed only
  with `install/decoders.sh install --legacy` or `install/install.sh --with-legacy-decoders`;
  installed, they replace Apple's decoders for these formats. Run on an RX 6800 XT with 26.7.3
  through VideoToolbox: VC-1 bit-exact (advanced profile I/P/B, WMV3 main, 1080i frame and
  field interlaced), MPEG-2 frame pictures 58.8 dB or better, MPEG-4 I/P 59 to 67 dB.
  Refused before the GPU: MPEG-4 B-VOPs (they stall the firmware, on Linux as well) and MPEG-2
  field pictures (the firmware writes their chroma as zeros; Mesa does not decode them on this
  card either).
- MPEG-4: a B-VOP whose TRD is 0 is never sent (direct mode divides by it), the size goes to
  the firmware aligned to 16 as Mesa does (1920x1080 as 1920x1088; the pictures keep the real
  size), and the quantizer matrices always go in stream order.

- A system sleep. 0.3.6 made things worse in the first real sleep test on this Mac (RX 6800 XT, Tahoe
  26.7.3): it noticed the sleep (132 s asleep), but every session from before it then
  failed all its frames with -12911, and the new sessions after the wake lost their first
  frames to the refusal below. The same test with 0.3.5, which knows nothing of sleeps,
  kept decoding on the old sessions after the wake with every frame matching its reference.
- So an AV1 or VP9 session from before a sleep now keeps decoding, as 0.3.5 did, and at its
  next key frame (AV1: a key frame that refreshes every reference slot; VP9: a key frame, or
  an intra-only frame that refreshes every slot and resets every probability context) its
  driver objects are replaced inside the same decoder: the old accelerator is closed without
  the driver's own teardown and a new accelerator, driver, context and bitstream pool are
  opened, and the key frame decodes on them. No frame is dropped and the host sees no error.
- Only when the old session fails after the wake (a driver call, a command that does not
  finish, a firmware error) is it replaced at once; that frame and the ones up to the next
  key frame are then dropped (no picture, no error), at most 600 of them. A command that did
  not finish has its accelerator closed on the background thread. Right after a wake a
  command on the old session may take up to 15 s instead of 1 s (in the test one frame of
  each decode took about 10 s and then decoded correctly).
- -12911 is left for a replacement that fails, or no key frame within those 600 frames.
- A new session no longer refuses to open while one from before a sleep is still open.
- The MPEG-2, VC-1 and MPEG-4 decoders are unchanged: their sessions from before a sleep
  still stop as in 0.3.6.
- Each replacement leaves the old driver handle and its bitstream pool (up to 96 MiB) in the
  process, as the quiet close already did.

## Decoders 0.3.6 (not released; replaced by 0.3.7)

- A decode session from before a system sleep is no longer used after it. A user reported
  that with the AV1 and VP9 decoders a wake from sleep hung the Mac a while later, with
  glitches before it, and that a VP9 video came out red and broken in Chrome right after a
  wake while Safari played it fine. Apple's kernel driver keeps a decoder's video context
  across a sleep but restarts the video engine under it, and nothing tells the program
  (see "A system sleep" in `docs/how-it-works.md`). The plug-ins now notice a sleep from the
  time the Mac spent asleep or the time of its last wake, with no notification. A session
  opened before it writes and sends nothing more: its frames fail as a malfunction
  (-12911), so VideoToolbox makes a new session, and the host gets a working decoder again
  or falls back to software. Closing such a session leaves out the driver's own teardown,
  which would send the restarted engine a command for the lost session and wait for it
  with no time limit; only the accelerator's connections are closed, on a background
  thread. The MPEG-2, VC-1 and MPEG-4 decoders share the code and get the same.
- While such a session is still open in a process, no new session opens there, in any of
  the plug-ins: VideoToolbox decodes the new stream in software until the old sessions are
  closed. The reporter's log showed why: a browser's decoder process kept two VP9 sessions
  open across a sleep, the AV1 session it opened after the wake never decoded a frame, and
  the Mac hung after the next wake.
- `vtvp9test` has `-renew` (a new session for every `-loop` pass, in the same process) and
  prints a line per pass with the time; `vtav1test` gets `-loop` and `-renew` too. They are
  for the sleep test in `docs/testing.md`.
- Not run across a real sleep yet.

## macOS 26.7.4 (25G422) (RyzenStatus 1.90.0)

- Decoders: `AMDRadeonVADriver2` of 26.7.4 has a new UUID,
  `F7D8F5849EC139DB857C769697294957`, added to `kValidatedDrivers` in `decode/av1/vcnav1.c`,
  `decode/vp9/vcnvp9.c` and `decode/common/vcnlegacy.c` (MPEG-2, VC-1, MPEG-4), and 25G422 to
  `install/validated-builds.json` with `av1`, `vp9` and `legacy` set to `"untested-on-gpu"`
  and `jpeg` false (the VCNJpeg kext knows only 26.7.3's HWLibs and AMDRadeonX6000). Checked from the installer before updating (its cryptex
  rebuilt with `rawpatch`): the driver's 2760 functions are identical to 26.7.3's and every
  section is the same except one Apple build path in `__cstring`. Not decoded on a card on
  26.7.4 yet. New plug-ins mean new code directory hashes, so the loader kext must ship with
  them.

## Decoders 0.3.5 (RyzenStatus 1.89.0)

- The `stats` line's slow-frame count now uses the stream's own frame time. It used to count
  every frame whose queue wait plus decode passed a fixed 16.7 ms, so a 30 fps video showed
  60 to 80 "slow" frames out of 120 while it played with time to spare (a user's 4K30 log
  on r/hackintosh), and queue waits, which are normal with up to four frames in flight,
  made 60 fps look worse than it was. Now a frame counts only when its decode alone takes
  longer than the frame time, read from the sample's duration or, when the caller gives
  none, from the step between presentation times (steps over 100 ms are seeks and are
  skipped; 60 fps is assumed until a time is known). The line shows the average frame time
  it used over those 120 frames: `decode over frame time (avg 33.4 ms) 0`. Samples that
  carry only a hidden frame (FFmpeg sends those one by one) do not change the frame time,
  and a new session learns it again. Decoding itself is unchanged.
- The frame time is the stream's, not the wall clock's: at 2x playback each frame really
  has half of it, so a frame can count as fine and still arrive late.

## GPU sensors 0.8.1 (RyzenStatus 1.88.0; host tests only, not booted)

- Readings older than 5 s are no longer published. Before, a failed read, a sleeping card or a
  powered-down GPU left the last PMLog copy in `Sensors`, `Units`, `PMLog` and `SampleAgeMs`
  for good; the app already hid it after 5 s, but ioreg and scripts saw the old numbers. Now
  those four properties go away until Apple's driver samples again. `Samples` keeps counting
  since boot.
- The kept copy is dropped on wake, so a reading from before the sleep cannot show up as
  current after it. This rides on the GPU control's wake route; with `-gpuctloff` the 5 s
  rule still applies.
- The kext still never reads the GPU itself: it only copies what Apple's driver asked for,
  and the GPU control already refuses driver calls between sleep and wake.
- The GPU control no longer waits at shutdown or restart for a driver call that is still running, and waits at most 2 s when the GPU goes away. Before, a stuck call could hold that step forever. It is not the cause of the known restart hang after a sleep, which started before the GPU control existed.

## Decoders 0.3.4 (RyzenStatus 1.88.0)

- The VP9 decoder now declares a rating (`VTRating` 400 in its `CMMatchingInfo`, the value
  Apple gives its own hardware decoders). On a Mac with an Intel iGPU of the Kaby Lake or
  Ice Lake families active next to the Radeon, macOS also offers Apple's Intel VP9 decoder
  (AppleGVAVPXDecoder, which needs the iGPU's `IOGVAXDecode` key). Both declared the same
  codec, hardware and version, and VideoToolbox breaks that tie by an internal hash order
  that put Apple's first; on a user's Mac with a UHD 630 it decoded one frame and stalled,
  so ours never got the video. Read in VideoToolbox with IDA (Tahoe 26.7.x and Sequoia
  15.8.2): candidates are sorted by GPU preference, Apple-internal flag, then `VTRating`,
  then the hardware flag, and a missing rating counts as 0. Checked through the real
  selection code with two stand-in decoders: with the rating, ours is tried first. If ours
  fails to start, VideoToolbox still falls back to Apple's. Macs without such an iGPU see no
  change. Not run on a Mac with an Intel iGPU.
- The AV1 decoder moves to 0.3.4 with it; macOS has no Apple AV1 hardware decoder to
  compete with, so its only changes are the header check and the shift guard below.
- Both parsers now refuse frame headers outside the format's limits: an AV1 frame with more
  than 14 luma or 10 chroma film grain points, or a VP9 frame with more than 64 tile
  columns (libvpx refuses those too). Such streams were never valid; the hardware only has
  room for 14 and 10 grain points. The AV1 parser also refuses a subexponential value
  (`decode_subexp`) long enough to shift an int past its width, instead of overflowing. A
  refused header leaves the reference frames as they were, as for any other bad header.

## Decoders 0.3.3 (RyzenStatus 1.86.0)

Run on an RX 6800 XT with Tahoe 26.7.3 on 2026-11-21: YouTube 4K60 in Safari, AV1 and VP9,
decode about 6.5-7 ms per frame and no firmware errors; ffmpeg 9.1 through VideoToolbox on
1080p clips with 139 (AV1) and 22 (VP9) hidden frames, every frame the same as software
decoding, one session per clip. The items below were first checked on the CPU, against a
made-up driver.

- Each session now releases its accelerator with `AVD_DestroyAVDAccelerator`, which the
  driver exports and the decoders never called. Read in the 25G342 driver (IDA):
  `DeleteDriver` does not release it, and Apple's own decoders (AppleGVA) call
  `DeleteDriver`, then `AVD_DestroyAVDAccelerator`. Each accelerator holds three IOKit
  connections to the GPU driver (device, shared memory, video context), so every session
  until now left three of them open until the process ended. Chrome decodes every video of
  every tab in one long-lived process; this fits a user's report of videos that sometimes
  would not start until Chrome was restarted, but that this was the cause is not shown.
  The accelerator is also released when a session start fails after it was made. A driver
  build without that export is logged once and the session goes on as before.
- The teardown order is Apple's: delete the context, free the bitstream pool, delete the
  driver, destroy the accelerator, release the service. The pool is freed only when it was
  allocated.
- A sample that fails because the GPU did not finish a command, or because a driver call
  failed, is reported as `kVTVideoDecoderMalfunctionErr` (-12911) instead of
  `kVTVideoDecoderBadDataErr` (-12909), so the host can fall back to another decoder. Bad
  data is kept for streams that cannot be decoded as they are; a pixel buffer that cannot
  be made is `kVTAllocationFailedErr`. A failed driver call now stops the session like a
  timeout: nothing more is sent, later frames fail at once.
- A session whose command never finished is closed on a background queue, with a log line
  before and after. Read in the driver: deleting its context sends the engine a
  destroy-session command and waits in the kernel for it, behind the stuck one;
  `DeleteDriver` does the same for any context left, and `AVD_DestroyAVDAccelerator`
  waits for the video context first. VideoToolbox's invalidate no longer waits for that.
  The session's pictures are released only after the driver is done with them. A failed
  `QueryAVDCommandStatus` is handled the same way: the command went out and may still be
  on the GPU. Once such a close is queued, the plug-in stays loaded until the process ends,
  so the queue never runs code the host has unloaded.
- The first non-zero firmware result of a session is logged at once (error level, with
  the value); the count stays in the `stats` line.
- Session start and end lines give the counts of this process: sessions started, ended
  and still live (the end line is at info level: `log show --info`). A start that fails
  is not counted.
- VP9: the wrapped copy of the driver's factory class is built once instead of at every
  session start; a driver whose factory class changes fails the session start instead.
  The check that stops the process when the AV1 processor class is not the expected one
  now logs a fault line first.
- A session start that fails leaves no format behind, and `canAcceptFormatDescription`
  answers no for a decoder with no session, after invalidate or after a device failure, so
  VideoToolbox makes a new decoder instead of reusing a dead one. It no longer waits for a
  frame being decoded: it used to wait behind the GPU, up to the one-second limit.
- A session start sets up its new session (configuration, pixel buffer attributes) before
  anything else can reach it. A start that an invalidate overtakes closes the new session
  again and returns `kVTInvalidSessionErr`, instead of leaving it open on a dead decoder.
- New test `decode/tests/sessiontest.c` (both codecs, made-up driver): every part released
  once and in order, also after each failed create step and after a stuck command or a
  failed `QueryAVDCommandStatus` (closed on the background queue, not on the caller's
  thread); a pool with a missing buffer; a failed accelerator create that leaves its
  result set; a driver without the destroy export; device and stream failures.
  `plugintest` checks the malfunction and out-of-memory statuses, that no format is
  accepted after a failed start, a device failure or invalidate, that
  `canAcceptFormatDescription` does not wait for a running decode, and a start that
  invalidate overtakes. `vcn_wait_command` moved to `decode/common/vcnsession.c`.
- Second review, fixed on the CPU only (not run on a GPU, nothing loaded in the system):
  - The accelerator is asked for the one service it gets: `validMask` 1 (`services[0]`)
    instead of 0xffffffff over an array of eight. Read in the 25G342 driver (IDA,
    `AVD_CreateAVDAccelerator`): it opens only `services[index]`, refuses with 5 unless
    bit `index` is set and that entry is not 0, and never reads the mask again. AppleGVA
    passes 0xffffffff, which passes the same check. Not checked on the GPU: no real
    `CreateAVDAccelerator` has run with the new mask.
  - Read in the driver, and written down in `decode/common/avd.h` with the addresses: a
    failed `CreateAVDAccelerator` frees the accelerator itself and leaves the result NULL,
    so the session destroys nothing (what it did before, now read rather than assumed);
    only after a failed `initDriverCapability` does the driver leave its three IOKit
    connections open, and no caller can release them. A failed `CreateDriver` returns no
    handle and keeps what it made; there is nothing to delete. A bitstream pool that fails
    part way is freed by the driver itself, and a second free would crash, so the session
    still frees only a pool whose allocation returned 0.
  - An invalidate, or the last release, on another thread no longer returns while a
    `decodeFrame` call is still on its way into the queue (waiting for a slot): it refuses
    new frames first, waits for the calls already inside, then drains the queue. A call
    that gets its slot after invalidate began refuses its frame (`kVTInvalidSessionErr`),
    and `canAcceptFormatDescription` says no from the moment invalidate begins. Invalidate
    from inside the output callback waits for no call, since a call waiting for a slot may
    be waiting for that very frame. New `plugintest` case: a decode held between its slot
    and the queue while another thread invalidates; it fails on the earlier code. Another
    holds a decode after its check for invalidate and before it queues its frame:
    invalidate waits for it and the frame is emitted (a guard; it fails if the call leaves
    the count before queuing). Whether VideoToolbox ever calls `decodeFrame` while
    invalidating is not known.
  - The last release from inside the output callback (finalize on the decode queue, which
    can wait for nothing) no longer frees what the frames still queued and a call waiting
    for the queue go on to use: that state lives apart from CoreMedia's storage, counted,
    and the last one out frees it; the session ends once, under the decode lock, and the
    frames left emit nothing. New `plugintest` case: finalize from the callback with two
    frames queued and a synchronous decode waiting on another thread; it checks that
    nothing more is emitted, every sample is let go of and the session ends once, not
    during a decode, and the address sanitizer stops it on a use after free. On the
    earlier code it stops inside finalize, where libdispatch traps on the semaphore freed
    while frames still hold slots. Whether VideoToolbox ever releases a decoder from inside
    its output callback is not known.
  - VP9: a driver handle whose VAContext pointer is NULL fails the session start instead
    of being read through.
  - `sessiontest` also checks the release order after each failed create step, that no
    command is sent after a failed `ScheduleAVDCommands`, the service request as the
    driver checks it, and (VP9) the NULL VAContext.
- GPU test programs: `vtchurn` registers the bundle under its own decoder ID and its
  sessions ask for that one, so an installed plug-in cannot serve them; its growth is per
  session that started. `decode_ivf` and `decode_vp9` wait at most 30 s for a stuck
  session to close, then say so and exit with status 1.

## Decoders 0.3.2 (not released)

- Each decode command is waited for with a limit of one second. The driver's own wait has
  no time limit in user space (read in the 25G342 driver), so a command the GPU never
  finished could hold the session; after a kernel timeout it might also come back as done
  with the result of an earlier frame (read, not seen). Now the decoder asks without blocking, about every
  quarter of a millisecond, and only makes the blocking call once the command is done. A
  command still running after one second stops the session: nothing more is sent to the
  GPU, and every later frame of that session fails at once.
- The firmware's result for each frame, which was never read, is counted and shown in the
  `stats` log line as "firmware errors". The frame is not refused for it yet: what each
  value means for the picture has not been checked on a GPU.
- The query entry's second field was taken for a poll interval (and could be set with
  `VCNAV1_QMODE`); the driver never reads it. The setting is gone.
- New test `decode/tests/waittest.c`: the wait against a made-up driver, timeout included.

## Decoders 0.3.1 (not released)

- A call made from inside the output callback (finish delayed frames, invalidate, a
  synchronous decode) trapped, and more asynchronous decodes than the queue holds hung
  for ever. They now run without waiting for the queue that is running the callback, and
  finish delayed frames also waits for frames queued from the callback meanwhile.
- After invalidate, frames are refused and nothing more is emitted. A second session
  start no longer leaks the first decoder session. A format of another codec with the same
  size is no longer accepted. A NULL sample, format or result pointer is refused, and a
  failed allocation in the factory is an error instead of a decoder without a queue.
- AV1: a temporal unit that shows no frame is emitted as dropped, with no error, as VP9
  does. A sample that fails after showing a frame hands back no picture (both codecs).
- AV1: a sequence header inside the stream is checked like av1C (profile 0, 8 or 10 bits,
  4:2:0) before anything goes to the GPU; it was only checked in av1C. A frame inside the
  av1C configOBUs is refused instead of decoded at session start, and an unsupported
  sequence header there refuses the session, so VideoToolbox can pick another decoder.
- AV1: a reference slot that a header emptied is no longer handed to the driver with its
  old DPB index, which could be the slot the frame was being decoded into. A frame too big
  for a bitstream buffer or with a tile out of range is refused before a DPB slot is taken.
- VP9: an inter frame whose reference has another bit depth is refused (the driver would
  allocate its DPB again at the new depth while the frame reads from it). A refused
  header leaves the colour config, loop filter deltas and segmentation as they were. A
  frame that ends where its headers end, with no tile data, is refused.
- Both: every bitstream buffer of the driver pool is checked at session start, the
  session size is checked before it reaches the driver, and a pixel buffer without an
  IOSurface is refused. When memory runs out while the pixel buffer attributes are built,
  the session start fails instead of going on with half of them (or with none).
- New tests in `tests/run.sh`: `vp9state` (refused VP9 headers) and `plugintest` (the
  VideoToolbox side of both plug-ins with a stand-in decoder session). The parsers read the
  public test streams exactly as 0.3.0 did. Nothing of this was run on a GPU.

## Installers and gpusensors (not released)

- `decoders.sh install` and `repair` copy each plug-in under another name, check it, and only
  then put it in place of the old one: a copy that fails half way leaves the installed plug-in
  as it was. The system volume they mount is unmounted again when they end.
- The `config.plist` editor (`install/ocentry.c`) checks every allocation, and a path too long
  for its temporary or backup name stops with an error instead of using a cut name.
- `undo.sh` also finds the encoding fix's kext on a mounted EFI when the service is gone and
  the kext is not loaded, refuses an `--efi` value that is not a partition like `disk0s1`, and
  prints its `--efi` errors (they started with "--", which `print` took for an option).
- `check.sh --help` prints its help like the other tools (it was refused as a usage error).
- Run with sudo, safer: `decoders.sh repair` mounted Apple's snapshot on a fixed folder in
  `/private/var/tmp` and used whatever was already mounted there, so another user could have
  put their own plug-ins in its place; it now mounts on a new folder of root's (`mktemp`)
  and removes it after. The quarantine flag is cleared with `xattr -s`, so a link in the
  package no longer makes root clear it on the link's target. The `config.plist` editor
  makes its temporary file new (`O_EXCL` after removing the name), so a link planted at that
  name is not written through (checked: the link's target stays as it was). Every installer
  runs the system's own tools only (`PATH` set in `common.zsh`), whatever PATH sudo kept.
- `gpusensors` read each property on its own, which returns what the last whole read of
  the kext's properties left (by `ioreg -l`, say), so it could show the same reading for
  minutes. It now reads the whole table once per run: fresh, and one moment for all.
  It also takes macOS's readings from the accelerator with AMD's keys, not from an
  Intel iGPU, and refuses `--watch` intervals that are not numbers from 0.1 to 3600 and
  two modes at once.
- Installers: an option that takes a value refuses an empty one (`--efi-folder ""` used to
  fall back to the booted EFI), and `--json` only goes with `check`. JSON output escapes
  tabs and line breaks.
- Kext install on the EFI: when an entry with other settings is replaced, a failed add
  puts config.plist back as it was, and Ctrl-C is held back between the two edits; the
  free-space check counts config.plist; leftover `.new`/`.old` folders are cleaned. A
  failed delete in uninstall is an error, not "Done."; an unmount Spotlight holds is
  tried again.
- `sensors.sh check`: a library without the PMLog function is a FAIL, not "could not look";
  with no build it says "(not built)" and no longer calls the EFI copy outdated; a running
  kext with FAIL checks says that they stop a new install. `loader.sh check` does the same,
  and says it cannot tell whether an EFI kext lists the plug-ins when none are built.
- `decoders.sh install` right after `loader.sh install` failed: the loader had unmounted
  the EFI, and only mounted EFIs were looked at for a loader waiting for the reboot. As
  root it now also looks into the unmounted ones (read-only, unmounted again), and checks
  the entry with kextentry (enabled, after an enabled Lilu).
- `decoders.sh`: install checks Apple's plug-ins on the volume it writes, not only on the
  live one; repair removes a loose `Contents` of any kind and completes an Apple bundle
  that is there but incomplete; uninstall with nothing installed no longer makes a boot
  snapshot; "installed" says unknown, not outdated, when there is no build to compare.
- `encoder.sh`: a disabled entry, one before Lilu, other settings or a disabled Lilu no
  longer count as "listed"; install refuses such an EFI before changing anything (it used
  to install the service and the kext and then fail at the config edit). "Installed and
  working" also needs the running kext to be the package's version and active. The EFI is
  unmounted however a run ends, and uninstall no longer needs Lilu on the EFI.
- `check.sh` ends with 0 only when the decoders work now; ready (install) and installed
  (reboot) end with 2, as its help says.
- Options that do nothing with a command are refused: `--efi` with `check`, `--force`
  outside install and repair. Replacing an EFI entry leaves one backup, not two.

## GPU sensors 0.8.0 (RyzenStatus 1.86.0)

Booted on an RX 6800 XT with Tahoe 26.7.3 on 2026-11-21 and driven from the GPU control page:
the card's own power range (225 to 240 W), a refused 220 W, back to the start-up limit, the
GFX maximum at 2300 MHz, the fan curve with zero RPM off, and closing changes without a
password. `controltest` checks the rest on the CPU.

- `Write` says what a program holds. It said "a program holds a lower limit" for a fan or
  clock change too, because one program holds one thing at a time and both count as a
  change. Now: "holds a lower limit" only when a lower power limit is confirmed, "holds a
  fan or clock change (OD8Write); the power limit is the start-up one" for an OD8 change,
  and "is setting a limit" while a power request is still on its way.
- `disarm` (channel selector 6, `gpucontrol disarm`) closes writing again without a
  restart. Any program may call it, administrator or not: closing can only make it safer,
  and opening again still needs `arm` as root. It is refused with its own answer
  (19, "a change is still applied or being handled") while a program holds a change, a way
  back runs, a request is waiting or running, or a power limit or OD8 state may not be back
  at its start-up value (an answer only waiting to be collected does not count). Afterwards every change is
  refused as before `arm`, and `arm` opens it again. An older kext refuses the selector.
- The minimum power limit is the card's own, as Linux amdgpu computes it
  (`sienna_cichlid_init_ppt_limits`): the start-up limit less the lower bound of the OD8
  power percent from the first clean 0x9f after boot, integer division. It was a fixed 200 W.
  On the test RX 6800 XT (240 W, -6 %) the floor is 225 W, so 200 to 220 W are now
  refused and 230 W is the only lower value. Until the floor is known (OD8 not read cleanly,
  an odd first read, or a power entry not as expected) every lower request is refused
  (answer 20, "the card's minimum power limit is not known"; above the start-up limit is
  still "above the start-up limit"); going back to the start-up limit never
  needs it. A card without the power percent feature takes nothing lower. New properties
  `PowerRange` (`FloorW`, `MaxW`, `StepW`, `PercentMin`, `PercentMax`, `Known`; also on a
  read-only card) and `PowerRangeState`. The 200-300 W check of the start-up read stays (it is a read check).
- An RX 6900 XT (73BF rev C0) is now read like the RX 6800 XT (routes, start-up limit, OD8,
  stock values, power range) and never written: new `WriteOff` 15, `ReadOnlyCard`, set from
  the card scan on; `arm`, `set` and `setOd8` answer "off" for it, the boot profile is not
  applied, and the senders of 0x2a, 0x6e and 0xa1, the way back, the off-back and the
  watchdog each check it again. `Write` and `OD8Write` say "read only" (and "waiting for the
  driver's library" until it comes). A later reason that also stops the reads replaces 15
  in `WriteOff`; a C0 next to another Navi 21 is `NotOneCard`.
- `set` and `setOd8` answer "off" and then "not armed" before they look at any value they
  carry: an absurd value no longer gets "above the start-up limit" or "malformed" from a
  closed or read-only control.
- `setOd8`'s GFX clock is no longer cut at 5000 MHz on the wire; only a value the 32-bit
  field cannot carry is malformed (2^32 is still refused, never read as stock). Its first
  check is the card's stock maximum.
- Channel version stays 2: the selector and the answers are only added.
- `readBackMatches` is gone: no code ever called it (the 0x6e is confirmed by the
  `smu_11_0_7_set_power_limit` watcher, `classifySend`); its comment described a read-back
  the kext never did. Since 0.5.0.
- `controltest` runs 336 checks (was 277).

## GPU sensors 0.7.2 (not released; booted on an RX 6800 XT 2026-11-19, no OD8 write sent with it)

- The fan watchdog's limit at any fan speed is 95 C (was 85 C). A 5 minute load at stock
  (gpubench --sustain 300, 240 W, 2026-11-19) passes 85 C after 80 s and ends at 90-91 C
  with the stock fan at 96-100 %, so 85 C would have taken every curve back in any load
  longer than that, with stock just as hot. The other rule is unchanged (75 C or more
  with the fan under 90 % for 5 s).
- `controltest` runs 277 checks (was 276).

## GPU sensors 0.7.1 (not released; booted and run on an RX 6800 XT, 2026-11-19)

Run on the card: zero RPM off, a fan curve during a 60 s load, GFX max 2300 MHz during a
60 s load, all three in one call, a power limit and an OD8 change at once (refused), and
zero RPM off and the curve each held across a sleep. Ten changes, ten ways back, the
replay list empty every time, no new lines in the GPU's kernel log. Results in
`sensors/README.md` ("What has been checked").

- `gpucontrol od8` and `check` read OD8 from one copy of the whole property table; a
  single key returned what the last whole read left, so `od8` showed the values from
  before a change while it was held.
- The fan curve must reach 100 % at 48 C or below (was 50 C): test 0 on the card
  (2026-11-19, gpubench 60 s at 240 W, stock fan) measured the hotspot 16 to 22 C above
  the edge sensor at load (median 18), and the kext now takes the 22.
- `controltest` runs 276 checks (was 275).

## GPU sensors 0.7.0 (not released; booted on an RX 6800 XT 2026-11-19, no OD8 write sent)

OD8 writes: a program may hold a fan curve with more air than stock, zero RPM off, and a
lower GFX maximum while a command runs. Checked on the CPU only (`controltest`) and with
`gpucontrol check` against what 0.6.0 read on the card; nothing has been sent to a GPU.

- Same channel and owner rules as the power limit: `sudo gpucontrol arm` first, one
  program at a time, "alive" every 5 s, and the way back on release, close, 30 s of
  silence and after a wake. A power change and an OD8 change are never held together
  (the second one hears "busy").
- What can be asked, and nothing else: a fan curve of five points that gives at least the
  stock curve's air at every point (checked at the user's points and at the stock ones),
  starts at 30 C or below, rises, and reaches 100 % at 48 C or below (the 70 C target
  minus 22 C, the largest hotspot - edge gap measured at load, in case the curve reads
  the edge sensor); zero RPM off;
  GFX max from 1500 MHz up to stock. A curve is only taken while the watchdog has a
  PMLog copy at most 2 s old. Memory, voltage and power percent are never written; the
  GFX minimum is only sent at its stock value. Anything else is refused with the reason
  (`Od8Refused`, and `OD8WriteState` `LastCheck`), never clamped.
- Each change: fresh 0x9f + 0xa0, every check, then one 0xa1 built from the whole wanted
  state (all ten curve entries in every call; stock is the all-ten reset, zero RPM at
  stock and the GFX pair at stock), sent with the no-replay flag. Then both are read back:
  every sent entry must read as sent (GFX max may read up to 25 MHz lower, never higher),
  every other entry unchanged, and the driver's replay list (`PP_CNEscapeInput`) still
  empty. A call that fails or reads back wrong is followed at once by the stock call, and
  writing goes off until restart. Whenever writing goes off with a change possibly still on
  the card (for any reason), the stock call is tried up to 3 times, 500 ms apart, once;
  then nothing more is sent.
- A watchdog, once a second while a curve is held, from the kext's own PMLog copy:
  hotspot at the target + 5 C with the fan under 90 % for 5 s (the fan percent is RPM over
  the table's maximum, so full PWM can read under 100), or hotspot 85 C, or no readings
  for 10 s, and the stock call goes out and writing goes off until restart. It does not
  depend on `gpucontrol` staying alive, and stops once writing is off.
- Channel version 2 (new call `setOd8`, 13 scalars in, 2 out); a version 1 program hears
  "old channel", whatever counts it passes. New properties `OD8Write` and `OD8WriteState`; `gpucontrol status` shows the
  OD8 state.
- New commands `gpucontrol hold [fan C:%,...] [zerorpm off] [gfxmax MHz] -- <command>`
  and `gpucontrol check ...` (runs the kext's checks on the published OD8, sends nothing).
- GPU recovery: on this macOS the driver's only recovery (an engine reset in the
  accelerator) never tells PowerPlay, so an escape during it is a normal firmware message
  and the read-back still checks it. Not routed in this version.
- `controltest` runs 275 checks (was 217).

## GPU sensors 0.6.0 (not released; booted on an RX 6800 XT, 2026-11-19)

OD8 (the driver's overdrive data: fan curve, clock and power ranges), read only. Nothing is
sent to the power firmware and nothing is changed; checked on the CPU only (`controltest`).

- The worker sends two more escapes through `ppCWDDE`, both read-only in the driver
  (they copy its own OD8 data, no firmware message): 0x9f (each setting's feature bit,
  min, max and default) and 0xa0 (each setting's current value). It reads them 2 s after
  the framebuffer's first read of the power limit at boot, and again after each wake, once
  the wake wait and its margin are over and any way back is done. Never from a routed
  function or a program's thread.
- Both answers start with a count the caller presets, not a size; the driver clears
  count-sized memory before clamping it, so the kext always presets exactly 38 and the
  buffers have the exact sizes (928, 164). The header asks the driver not to keep the call
  for its replay after wake (the driver never keeps these two anyway). A sentinel where the driver always writes tells "asleep,
  nothing written" from data.
- Every 0x9f entry is checked against what the driver was read to do (the feature bit of
  each setting id, reserved words 0, min not above max); the first one that does not fit
  is published as `OddEntry`/`OddEscape`. A wrong size or an unknown answer stops the reads
  until restart. A refusal (0xE00002BC: OD8 off on this card, or the lock busy), "not
  initialized" or no data is tried 3 times, 1 s apart.
- An odd 0x9f still sends 0xa0, so the published numbers always come from one read.
- The first complete read after boot is kept as "stock" (`StockOdd` 1 when its defaults
  were not as expected); later reads say whether the defaults or the current values moved
  since boot. After a failed read the numbers stay those of the last complete one
  (`LastReadAgeS`).
- OD8 is read by the write path's worker, so it runs only where writing could: exactly
  one AMD GPU, an RX 6800 XT on `AMDRadeonX6000HWLibs`, every watcher routed. With
  `-gpuctloff`, on `AMDRadeonX6800HWLibs` (NootRX setups) or when the worker cannot start,
  `OD8State` says it is off (the reason is in `WriteState`).
- New properties `OD8State` and `OD8` (`Reads`, `Tries`, `LastResult`, `LastReadAgeS`, `Caps`,
  `NotAllowed`, `StockOdd`, `DefaultsMoved`, `CurrentMoved`, `FanCurveStock`, `FanCurve`, and `Settings` by name with
  `Feature`, `Min`, `Max`, `Stock`, `Current`). New command `gpucontrol od8` prints them.
- The framebuffer's first read of the power limit now always wakes the worker (before, only
  when the value was out of range).
- `controltest` runs 217 checks (was 186).

## GPU sensors 0.5.0 (not released; booted on an RX 6800 XT, 2026-11-19)

The first version that writes to the GPU. Booted and run on the test RX 6800 XT on
2026-11-19: `hold power 230` and `hold power 200` around a 60 s GPU load, each sent and
confirmed, and the start-up limit (240 W) came back at the end (sustained power 228.1 and
199.4 W, against 240.6 W in a 240 W run). Before that it was checked on the CPU: the
decisions in `controltest`, the kext's build, its imports against this kernel, and the bytes
of every driver function it routes or calls against this Mac's 26.7.3 kernel collection.

- One program at a time may LOWER the package power limit, from 200 W up to the limit the
  card started with, in 10 W steps. Anything else is refused, never clamped. The start-up
  limit itself means "go back": it is never a change.
- Writing starts closed at every boot. `sudo gpucontrol arm` opens it until restart (the
  caller must be root). It stays off for good with `-gpuctloff`, unless there is exactly one
  AMD GPU and it is an RX 6800 XT (73BF rev C1), on `AMDRadeonX6000HWLibs`, with every
  watcher of 0.4.0 routed and `ppCWDDE` starting as expected; it turns off until restart
  when a second PowerPlay object or hwmgr shows up, or the start-up limit read is outside
  200-300 W. Until that limit has been read, `arm` is refused (it does not wait).
- The only driver function called is `AtiPowerPlayServices::ppCWDDE`, with two escapes:
  0x2a (is the GPU up) before every 0x6e (set the package power limit). Each call runs on
  one kernel thread of the kext, never from a routed function and never from a program's
  thread. A program's `set` waits 5 s at most.
- Each 0x6e is confirmed by the watcher of `smu_11_0_7_set_power_limit` on the kext's own
  thread: exactly one send, of those watts, taken by the firmware. A change that is not
  confirmed sends the start-up limit once and turns writing off until restart. When 0x2a says
  the GPU is not up nothing is sent and the program hears "GPU asleep or not ready"; a 0x6e
  the driver could not send goes back and the program hears "busy". Changes are never retried.
- The start-up limit goes back when the program releases, closes or crashes, after 30 s
  without its "alive" (every 5 s), and after a wake that followed a change (2 s after the
  framebuffer has read the limit again, or after 10 + 2 s: the driver's own escapes wait
  until the framebuffer's wake work ends, and that read is its first step). Nothing is sent
  between sleep and wake.
- Sleep handshake: the driver's 0x6e path has no sleep check of its own, so the routed
  `ppSleep` (entered with no AMD lock held) marks the sleep under the kext's lock and waits,
  3 s at most, for a call of the kext already running; each call checks that mark and starts
  under the same lock. A call either ends before the sleep starts or is not made. A call
  that outlives 3 s is logged and the sleep goes on. Nothing is sent until `ppWake` has
  returned.
- A way back is tried 3 times, 500 ms apart, while the GPU is busy or not up; after that
  writing is off until restart. At power-off, restart or when the GPU goes away, nothing
  more is sent.
- `ppInitialize` is now routed always (still pass-through), to keep the PowerPlay object.
- New IOUserClient on `DrogaBoxGPUSensors` (channel version 1: status, arm, set, alive,
  release) and new properties `Write` and `WriteState`.
- New command `gpucontrol`: `status`, `arm`, and `hold power <W> -- <command>`, which holds
  the limit while the command runs and always releases (when it ends, on Ctrl-C, SIGTERM,
  SIGHUP; if `gpucontrol` itself is killed, the kext goes back on its own).
- `controltest` runs 186 checks (was 100); `tools/driver/ctlentries.py` also checks `ppCWDDE`.

## GPU sensors 0.4.0 (not released; booted on an RX 6800 XT, 2026-11-19)

- The power limit, watched only: the limit the framebuffer reads at boot and after each wake
  (`Phw_SwSmu_GetPowerLimit`; its first answer is the boot limit), every limit sent to the
  power firmware whoever sends it (`smu_11_0_7_set_power_limit`), and each sleep and wake
  (`AtiPowerPlayServices::ppSleep`, `ppWake`). Every call goes through unchanged and nothing
  is called or sent. Each function is routed on its own bytes, checked against 26.7.3.
- New properties `Power` and `PowerWatch`.

## GPU sensors 0.3.0 (not released; booted on an RX 6800 XT, 2026-11-19)

The first step of the GPU control, inside the same kext.

- With the boot argument `gpuprofile=0`, `2` or `16`, the kext sets `PP_WorkLoadPolicyMask`
  on the card right before the power management starts. macOS sets 16 (compute) on every
  Navi 21 and the driver then ignores the profile its own clients ask for; 0 gives that choice
  back to the driver (the video profile while video plays). Not booted with the argument yet.
- The kext watches the profile the driver's clients ask for and publishes it in
  `ProfileRequests`, unchanged.
- Only on an RX 6800 XT (73BF revision C1), and each function only when it starts as expected
  (`gpuprofile` needs both); `-gpuctloff` turns it off. New properties `Control`, `Profile`,
  `ProfileSet`, `ProfileRequests`; `gpusensors` shows the first two.
- The rules for the power limit to come (lower only, at least 200 W, one change every 2 s, put
  back after a sleep, on close and on a stalled app) are in `sensors/kext/control_logic.hpp` with
  100 checks in `sensors/tests/controltest.cpp`; the kext does not use them yet.

## GPU sensors 0.2.0 (not released; booted on an RX 6800 XT, 2026-11-18)

- The kext sets the driver's own setting `PP_EnableAllPMLogSensors` on each Navi 21 card,
  before the power management starts, so the driver keeps the readings it already takes
  and used to drop: memory temperature, the GFX and memory voltage-regulator temperatures,
  SOC and memory voltage, throttler status, and the SOC, video and fabric clocks. A value
  from the OpenCore DeviceProperties is left alone; `-gpusensnoall` keeps the driver's
  list. The new property `AllSensors` says what happened.
- Ids the driver marks filled but never writes are no longer published, in `Sensors` or in
  `PMLog`, so they cannot show up as 0.
- `gpusensors` shows the PCIe generation ("2 (PCIe 3.0)") and the `AllSensors` state.

## GPU sensors 0.1.0 (not released)

New, in `sensors/`. `GPUSensors.kext` publishes the readings Apple's AMD driver takes on a
Navi 21 card and does not show. On an RX 6800 XT with Tahoe 26.7.3 the driver fills 12
values, which add edge temperature, GFX voltage, memory activity and the PCIe link to what
macOS shows. It copies the driver's own table when the driver reads it (about once a second)
and never asks the card anything. `gpusensors` shows the readings, as a table, as JSON or
side by side with what macOS publishes. Booted on that Mac on 2026-11-18.

## VCNVTLoader 1.1.0 (not released)

The kext that lets the decoder plug-ins load without AMFIPass, now in `decode/loader/`.

- Only the library validation exception is left. The CoreMedia patch of 1.0.0 never ran and
  is gone.
- The list of allowed plug-in builds is written when the kext is built, from the plug-ins
  just built, `released-builds.txt` and any bundle named on the command line. 1.0.0 was built
  from a list kept by hand, which went stale.
- The AMFI function is only routed when its first instructions are the plain prologue read
  in 14.8.9, 15.8.2, 26.7.2 and 26.7.3; a function already routed by something else is left
  alone.
- The route is a long jump, so a kext loaded later can route the same function too. A short
  one, which 1.0.0 used, makes Lilu panic in that case.
- State and a counter of plug-ins let through: `ioreg -r -c VCNVTLoader -l`. `Status` and
  `StatusCode` come from one read, so they always agree.
- The bytes compared at the start of the two AMFI functions must be inside AMFI's image;
  Lilu only checks that the function address is.
- Runs on Sequoia and Tahoe only, like the decoders.
- 2026-11-18: first boot, RX 6800 XT, Tahoe 26.7.3, AMFIPass off: Safari decodes AV1 and VP9
  in hardware through the ad-hoc plug-ins.

## Decoders 0.3.0 (not released)

- Only AMD's accelerator is handed to the driver. With an Intel iGPU active, the decoders
  could pick Intel's accelerator, which AMD's driver refuses, and nothing decoded.
- Bounds and null checks in the AV1 and VP9 parsers, the driver sessions and the
  VideoToolbox glue, most of them by Izzy. Fixes undefined behaviour (a left shift of a
  negative value) in the AV1 global motion parameters.
- AV1: a refused sample no longer leaves a half-read frame that a later tile group could
  complete and send to the GPU, and a refused header no longer changes the reference
  state. Tile groups must follow each other and empty tiles are refused.
- AV1: every reference of an inter frame must hold a decoded picture, and frames larger
  than the session are refused, as VP9 already did.
- VP9: the debugger-only path to the driver now also needs the dry-run marker.
- The accelerator taken from IOKit is released when a session ends.
- The parsers read valid streams exactly as 0.2 did (checked with the conformance streams).
- The debug memory dump helpers are no longer compiled into the bundles.
- Builds are reproducible and hold no path of the build machine.
- 2026-11-17: installed on the test machine (RX 6800 XT, Tahoe 26.7.3).

## Decoders 0.2

Installed on the test machine since 2026-11-11 (RX 6800 XT, Tahoe 26.7.3).

## Installers (not released)

- `install/decoders.sh check` no longer asks for AMFIPass. It finds what lets the plug-ins
  into Safari on this Mac (AMFIPass, VCNVTLoader, an own certificate authority, or AMFI
  switched off) and, for the two that depend on the exact plug-ins, asks macOS whether it
  would load them, with the new `lvprobe`, which loads nothing.
- An AMFIPass that is loaded but switched off by `-amfipassoff` or `-liluoff` no longer counts
  as running.
- `amfi_get_out_of_my_way=0` no longer counts as AMFI switched off.
- New `install/loader.sh`: puts VCNVTLoader on the OpenCore EFI and takes it off again,
  with no file to edit by hand. It finds the EFI OpenCore started from, checks everything
  before the first change (the kext lists the plug-ins, Lilu 1.7.0 or newer and enabled,
  room on the partition), copies the kext, adds its entry after Lilu with a backup of
  `config.plist`, and checks the result. `check` ends in one line: working, installed and
  waiting for a reboot, ready, or what is in the way.
- The editor of OpenCore's `config.plist` (`install/ocentry.c`) is now shared by the
  encoding fix and the loader kext. The encoding fix's own tests give the same results.
- What the three scripts had in common is in `install/common.zsh`.
- New `install/sensors.sh` for the GPU sensors kext. Putting a kext on the EFI and taking it
  off is now one piece of code, `install/efikext.zsh`, used by `loader.sh` and `sensors.sh`;
  the config editor is `kextentry <kext>`, which knows both kexts. The sensors installer
  also checks for a Navi 21 card and that this Mac's driver function starts as the kext
  expects.

## Repository

- 2026-11-17: the decoders and the encoding fix move into this repository, with pinned
  dependencies, one formatting style, a cleanliness check and a test suite that needs no
  GPU. The imported code was checked against the copies in use before any change.
- 2026-11-18: a fresh clone builds and passes every test (`tools/bootstrap.sh`,
  `./build.sh`, `tests/run.sh --quick`). `tools/kextlinks.sh` checks, without loading
  anything, that every symbol the kexts import exists in the running kernel or in Lilu.
  `tools/driver/kcfunc.py` reads the first bytes of any function of a kext in a kernel
  collection; `amficheck.py` now uses it. `.github/workflows/ci.yml` runs the same from a
  clean clone on GitHub's macOS 26 Intel runner (not run yet: the repository has no
  remote).
- Checks that could pass when the thing checked was broken: the "no path of this machine"
  checks passed when `strings` failed (`strings | grep || true`), the build-twice checks
  compared two empty hashes when the read failed (`local x=$(...)` always has status 0), and
  `tools/kextlinks.sh` passed with no kext named or when `nm` failed. All fixed. The encoding
  fix's binaries now get the path check too, and a run that skipped checks says which ones
  instead of "all tests passed".
- `tools/package.sh` refuses a tree with uncommitted changes before it builds, leaves out
  `install/check_lists.sh` (it needs the decoders' sources), and refuses binaries that hold a
  path of this machine (a `DEBUG=1` build packaged with `--no-build`).
- `decode/build.sh` and `encode/build.sh` assemble each bundle and the encoder package under
  another name and put them in place only when everything worked, so a failed build no longer
  leaves half a bundle. `sensors/build.sh` checks for the kext SDK before building anything.
  The encoder's `SHA256SUMS` is sorted the same everywhere (`LC_ALL=C`).
- Tests that let a bug through: `plugintest` passed with a plug-in that never released the
  pictures it emitted (now it checks the stand-in picture's count at the end; checked by
  removing that release, which it now catches). The loader install test ignored the exit
  status of `check --json` and did not see an empty folder left by a refusal. The encoder's
  EFI test accepted a refusal that exited 0 and any error code where `install/encoder.sh`
  needs 3. `wide_test` runs under the sanitizers like the other test programs, and
  `parsedigest --mutate` no longer divides by zero on a file with no frame.
