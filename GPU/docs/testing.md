# Testing

## Without a GPU

```bash
tests/run.sh            # everything
tests/run.sh --quick    # 30 damaged copies per stream instead of 300
```

It never opens the GPU, loads a kext or changes the system. It checks:

1. the repository is clean and formatted;
2. the decoders build, twice, to the same bytes, with no path of the build machine inside;
3. the AV1 and VP9 parsers read 15 public conformance streams exactly as recorded in
   `tests/expected-digests.txt`. The digest covers every header the parser produced, the
   tile table, the tile bytes and the reference state after each frame. A change that makes
   the parser read a valid stream differently changes the digest;
4. the parsers survive libvpx's deliberately invalid streams and 300 randomly damaged
   copies of each stream, built with the address and undefined-behaviour sanitizers, and
   a refused AV1 sample or VP9 header leaves the parser's state as it was;
5. the plug-ins' VideoToolbox side, with the decoder session replaced by a stand-in: the
   frames they emit (shown, dropped, failed), calls made from inside the output callback,
   a second session start, a format of another codec, invalidate;
6. the rule that hands only AMD's accelerator to the driver;
7. the loader kext: its decisions (which hashes it lets through, which function entries it
   accepts), that it builds twice to the same bytes and lists the plug-ins just built, and
   that it accepts the AMFI functions of the Mac the tests run on; and that
   `install/loader.sh` installs, replaces, refuses and uninstalls it on made-up EFI
   folders, and that `install/sensors.sh` puts the sensors kext next to it and takes it off
   alone (`tests/loader_install.sh`, 32 cases, no partition is mounted);
8. the GPU sensors: they build twice to the same bytes, their decisions (which buffers are
   a filled sensor table, the names of the ids the driver reads), and that the kext accepts
   the driver function of the Mac the tests run on;
9. every symbol the three kexts import exists in the running kernel or in Lilu
   (`tools/kextlinks.sh`; nothing is loaded);
10. the encoding fix: its wide patch run on the CPU at each validated build's call site, and the
    OpenCore config editing on copies of a sample config.

The streams are downloaded by `tests/fetch_media.sh` and checked against
`tests/media-sha256.txt`; no video is committed.

To check the loader kext against another macOS build, give its boot kernel collection to
`tools/driver/amficheck.py` and the result to the test:

```bash
python3 tools/driver/amficheck.py 15.8.2_24H232=/path/BootKernelExtensions.kc > entries.txt
decode/build/tests/loadertest entries.txt
```

When a parser change is meant to change how valid streams are read, regenerate the
digests and explain why in the commit:

```bash
decode/build.sh tests
decode/build/tests/parsedigest tests/media/av1/*.ivf tests/media/vp9/*.ivf > tests/expected-digests.txt
```

## With a GPU

These run only on a booted machine with a supported card, by hand. Save your work first:
a wrong message to the video engine can hang the GPU until a reboot. Write down who ran
them, when, on which card and macOS build, and add the result to `docs/status.md`.

- Decoding against references, in a test process, without installing anything: see
  `decode/tests/gpu/README.md`.
- Encoding: `test.sh` (two short encodes with reference numbers, three with `--wide`) and
  `doctor.sh`, run from the built package folder `encode/dist/VCNEncodeFix-<version>`
  (the copies in `encode/scripts` look for `bin/vtenc` next to themselves). Close any video
  first: decoding shares the video engine, and a 4K video playing during the test brought
  the first test from about 100 fps down to 73.
- GPU sensors, after the reboot that starts the kext: `install/sensors.sh check` must end
  in "working"; `sensors/build/gpusensors --compare` must show the same values as macOS
  for the seven readings both publish (values that move, like clocks and power, may differ
  a little between the two reads); `ioreg -r -c DrogaBoxGPUSensors -l` read a few times
  in a row shows how often the driver refreshes them (`Samples`, `SampleAgeMs`).
  `gpusensors` must say "All of the driver's sensors: requested" (or the reason it is
  off), `ioreg -r -n GFX0 -l | grep PP_EnableAllPMLogSensors` must show 1, and the
  memory temperature, GFX VR temperature, SOC and memory voltages and SOC clock must not
  be 0. Then the same with the card busy (a video for the video clocks, a game for the
  throttler status and memory activity), and the kernel log for `gpusens` lines.
- Decoders in a browser, after any change to the plug-ins' queue or invalidate code (after
  `install/loader.sh install` with the new plug-ins' hashes, `install/decoders.sh install`
  and a reboot): AV1 and VP9 at 4K and 4K60, seeking back and forth, closing the tab while
  it plays, and two tabs at once. YouTube gives AV1 when it can; to get VP9, make the page
  report AV1 as unsupported (`MediaSource.isTypeSupported` and
  `navigator.mediaCapabilities.decodingInfo` answering no for `av01`) before opening the
  video inside the same page. `video.getVideoPlaybackQuality()` gives decoded and dropped
  frames; the plug-ins log one `stats` line every 120 frames (subsystems
  `com.droga.vtav1vcn` and `com.droga.vtvp9vcn`), and closing the last tab must bring the
  video clocks in `gpusensors` back to 0. Done for 0.3.1 on 2026-11-18 (see
  `docs/status.md`).
- Decoders 0.3.2, the timed wait for each frame (`vcn_wait_command`): the conformance
  clips with `decode_ivf` and `decode_vp9` must still match bit for bit, the time per frame
  (`TU_TIMES=1`) must stay close to 0.3.1's, and YouTube 4K60 must still play with almost
  no dropped frames. The `stats` lines must show "firmware errors 0" on good streams; any
  other count says which firmware results come with a normal picture. The timeout itself
  is only tested on the CPU (`waittest`). Test process part done 2026-11-18 (see
  `docs/status.md`), and installed with YouTube 4K60 and the `stats` lines the same day.
- Decoders 0.3.3, the release of the accelerator and the new teardown: the conformance
  clips must still match bit for bit; in one process, 200 sessions created and closed
  must leave the process's Mach ports and IOKit connections where they started (on
  0.3.2, from the reading of the driver, they should grow by three connections a
  session); YouTube in Chrome must still play, and the plug-ins' `session ... ended`
  lines (`log show --info`) must show "live" going back to 0 when the tabs close. Only
  `sessiontest` (made-up driver) has run.
- What the driver does on a failure was read in IDA (25G342, 2026-11-18), not run:
  `FreeBitstreamBufferPool` after a failed allocation does nothing (a half-built pool
  never comes back: the driver crashes first), a failed `CreateContexts` with one entry
  leaves no context to delete, and `QueryAVDCommandStatus` with `.wait = 0` returns at
  once (status 1 done, 2 running). Still open: how long the kernel's own wait can last
  after a GPU restart.
- Everything at once: `install/check.sh` ends in one line.
