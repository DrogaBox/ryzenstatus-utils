# Tests that use the driver or the GPU

These programs test the AV1 and VP9 decoders on a real AMD Radeon RX 6000, and help to
validate a new macOS build of Apple's AMD video driver (`AMDRadeonVADriver2`).
`tests/run.sh` never runs them. You run them by hand, on a booted machine.

## Read this first: the GPU can hang

A wrong message to the video block of the GPU can hang the GPU. The screen freezes and the
Mac has to be reset. Before any run marked "can hang" below:

- save your work and close what matters;
- run the smallest clip first, and one program at a time;
- write down what you are about to run (a line in a text file is enough), so that after a
  reset you know which run did it. Do not repeat that run before you know why it hung;
- after a run, `/usr/bin/log show --last 5m --predicate 'process == "kernel"' | grep -i -E 'gpu|vcn|amd'`
  shows the kernel's GPU messages.

| Program | Talks to the driver | Can hang the GPU | Switch that arms it |
|---------|---------------------|------------------|---------------------|
| `decode_ivf` | yes | **yes** | `VCNAV1_ALLOW_GPU=yes-i-know-it-can-hang` |
| `decode_vp9` | yes | **yes** | `VCNVP9_SESSION=vp9` and `VCNVP9_ALLOW_GPU=yes-i-know-it-can-hang` |
| `decode_legacy` | yes | **yes** | `VCNLEGACY_ALLOW_GPU=yes-i-know-it-can-hang` |
| `vtlegacytest` | yes, through VideoToolbox | **yes** | `VCNLEGACY_ALLOW_GPU=yes-i-know-it-can-hang` (without it, it only cuts the stream into samples) |
| `vtav1test` | yes, through VideoToolbox | **yes** | none: a decode run is armed |
| `vtvp9test` | yes, through VideoToolbox | **yes** | none: a decode run is armed |
| `vtjpegtest` | yes, through VideoToolbox and the VCNJpeg kext | **yes** | none: a decode run is armed (`-apple` runs on the CPU only) |
| `mkmjpeg422` | no | no | none |
| `vtchurn` | yes, through VideoToolbox | **yes** | none: every session decodes |
| `probe_ctx` | yes | low risk: it opens a session, it decodes nothing | none |
| `tools/driver/dryrun.py`, `dryrun_vp9.py` | yes, under lldb | the driver's own setup goes out; our commands do not | the scripts arm the program themselves |
| `driveruuid` | loads the driver's code only | no | none |
| `vp9dump` | no | no | none |
| `vc1info` | no | no | none |
| `tools/driver/dscdiff.py`, `vcnmsg.py`, `mk4k.py`, `mkvp9.py`, `rawpatch` | no | no | none |
| `mkfield.py` | no | no | none |
| `av1hdr.py` | no | no | none |

The switches must have exactly these values. Anything else leaves the program unarmed: it
stops with "GPU submission disabled" before it sends anything.

`decode_legacy` and `vtlegacytest` are for the MPEG-2, VC-1 and MPEG-4 decoders
(`decode/mpeg2`, `decode/vc1`, `decode/mpeg4`, on `decode/common/vcnlegacy.c`). Both take a
whole elementary stream (`.m2v`, `.m4v`, `.vc1` with start codes, or `.rcv` for VC-1
simple/main as FFmpeg's `vc1test` muxer writes it) and write the frames as NV12 in display
order, which compares frame by frame with `ffmpeg -i <stream> -f rawvideo -pix_fmt nv12`.
`decode_legacy` drives the codec layers directly. `vtlegacytest` links the three plug-ins in
and registers them with VideoToolbox for its own process, so the plug-ins are exercised
through a real decompression session without being installed.

`VTLEGACY_DECODER` picks the decoder `vtlegacytest`'s session gets. `ours` (the default) asks
for our plug-in by its DecoderID, with hardware required. `system` registers it as an
installed copy is (VTRating 400) and lets VideoToolbox choose, as an app's session would:
an MPEG-4 stream our plug-in refuses goes on to the next decoder. `apple` uses Apple's
AppleMP4V with the hardware off and our plug-in not registered: CPU only, no switch needed,
a reference for the MPEG-4 runs. AppleMP4V decodes plain Simple profile only; it refuses
Advanced Simple, interlaced and MPEG quantisation with codecBadDataErr (-8969). Without a
DecoderID an in-process registration with no rating can lose to AppleMP4V (round 3).
`installed` registers nothing and asks for nothing: VideoToolbox picks among the plug-ins
installed in `/System/Library/Video/Plug-Ins`, as a player's session does. It prints whether
ours is listed and, after the frames, whether the process loaded the installed bundle. Apple's
MPEG-2 and MPEG-4 decoders on this Mac are software ones, so "hardware decoder: yes" is ours.

MPEG-2 field pictures are refused before the GPU unless `VCNMPEG2_ALLOW_FIELDS=1`; no
numbering has decoded them right yet (`VCNMPEG2_INDEX`, `VCNMPEG2_FIELD`, see
`decode/mpeg2/vcnmpeg2.h`).

`vtlegacytest` puts the two field pictures of an MPEG-2 frame in one sample, as an MP4 or a
transport stream does. No encoder on macOS writes field pictures (FFmpeg's `mpeg2video`
always codes frame pictures), so `mkfield.py` makes a stream of them from raw yuv420p
frames: I and P fields, with intra macroblock rows and rows that copy a reference field
(also the first field of the same frame):

```sh
ffmpeg -f lavfi -i testsrc2=size=720x576:rate=25 -frames:v 8 -pix_fmt yuv420p -f rawvideo src.yuv
python3 -I decode/tests/gpu/mkfield.py src.yuv 720 576 8 mpeg2-720x576-fields.m2v
```

## Building

```sh
decode/tests/gpu/build.sh
```

It only compiles. The programs go to `decode/build/gpu/`. `decode_ivf` and `decode_vp9` are
built with `-DVCN_DRYRUN_TOOLS`, which adds the memory dump helpers the dry runs need. The
build stops if a hook the dry runs depend on is missing.

## Test media

`tests/fetch_media.sh` downloads the public test streams into `tests/media/`. The AV1
streams come from the AOM test vectors; each one has an `.md5` reference at the same
address (for example `av1-1-b8-01-size-16x16.ivf.md5`). The VP9 references are FFmpeg's
FATE files `tests/ref/fate/vp9-*`, in the FFmpeg source tree; they go with the
`vp90-2-*.webm` streams of libvpx. No video is kept in this repository. One exception:
FATE's `vp9-05-resize` hashes every frame scaled to 352x288 (its command line has
`-s 352x288`), so the frames of other sizes never match it. Use libvpx's own reference for
that clip, `vp90-2-05-resize.ivf.md5` from libvpx's test data; `decode_vp9` reads both
formats.

`tools/driver/mk4k.py` (AV1) and `tools/driver/mkvp9.py` (VP9) make a clip of any size,
with its reference. They run on the CPU only:

```sh
python3 tools/driver/mkvp9.py /tmp/v.ivf 640 360 30
python3 tools/driver/mk4k.py /tmp/a.ivf 3840 2160 120 8
```

They need PyAV and NumPy (`pip install av numpy`). The reference is `<clip>.md5`.

## decode_ivf

Decodes an AV1 IVF file on the VCN, without VideoToolbox. It prints the MD5 of every shown
frame and compares it with a reference.

```sh
VCNAV1_ALLOW_GPU=yes-i-know-it-can-hang decode/build/gpu/decode_ivf clip.ivf clip.ivf.md5
```

- `-v` prints what the decoder session does. `-n` reads no pixels, for timing. `-o out.yuv`
  writes the frames as raw I420. `TU_TIMES=1` prints the time of each temporal unit.
- It refuses a driver build that is not in `kValidatedDrivers` (`decode/av1/vcnav1.c`).
  `VCNAV1_ALLOW_UNVALIDATED_DRIVER=1` lifts that, but only do it after a dry run passed.
- **Can hang the GPU.**

A pass: one line per frame ending in `OK`, then `clip.ivf: N frames, 0 mismatches`, and
exit status 0. Status 2 means a frame differs or is missing. Status 1 is any other error,
also a stuck session that is still closing 30 s after the end (the line says so; the
program then exits without waiting for it). `decode_vp9` does the same.

## decode_vp9

Decodes a VP9 file (IVF or WebM) on the VCN, without VideoToolbox. It compares each frame
with a FATE reference.

```sh
VCNVP9_SESSION=vp9 VCNVP9_ALLOW_GPU=yes-i-know-it-can-hang \
  decode/build/gpu/decode_vp9 vp90-2-02-size-16x16.webm vp9-02-size-16x16
```

- `-v` prints what the session does. `-n N` stops after N frames. `-b` is a benchmark: no
  pixels are read, it prints speed and memory. `-png dir N` saves every Nth frame as a
  half size PNG, for clips with no reference.
- Apple's driver has no VP9. This decoder borrows the driver's AV1 session and writes the
  VP9 messages itself. It only runs on driver builds listed in `decode/vp9/vcnvp9.c`, with
  no override.
- `VCNVP9_SESSION=av1` is only for the dry run. Without the dry-run script it is refused.
- **Can hang the GPU.**

A pass: one line per frame ending in `OK`, then `N frames, 0 mismatches`, and exit status 0.

## vtjpegtest

Motion JPEG through VideoToolbox, every frame compared with FFmpeg's decode (within 2: the
block's IDCT rounds a little differently). It needs `VCNJpeg.kext` running
([jpeg/README.md](../../../jpeg/README.md)).

```bash
ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=30 -frames:v 30 -pix_fmt yuvj420p -c:v mjpeg -q:v 3 -f mjpeg c420.mjpeg
ffmpeg -i c420.mjpeg -f rawvideo -pix_fmt yuvj420p r420.yuv
decode/build/gpu/vtjpegtest -apple c420.mjpeg r420.yuv 1280 720 420            # CPU only: checks the clip
decode/build/gpu/vtjpegtest -load decode/build/JPEGVCNDecoder.bundle c420.mjpeg r420.yuv 1280 720 420
decode/build/gpu/vtjpegtest -system c420.mjpeg r420.yuv 1280 720 420           # the installed plug-in
```

`-dmb1` sends the same pictures as OpenDML. `mkmjpeg422` writes the 4:2:2 sampling webcams
use (luma 2x1), which FFmpeg does not write.

## vtav1test and vtvp9test

They decode through the public VideoToolbox API, the way Safari does. They test the plug-in
bundles, not only the decoder core.

```sh
decode/build/gpu/vtav1test list
decode/build/gpu/vtav1test -load decode/build/AV1VCNDecoder.bundle clip.ivf clip.ivf.md5 \
  -id <decoder ID from list>
decode/build/gpu/vtvp9test -load decode/build/VP9VCNDecoder.bundle v.ivf v.ivf.md5 \
  -id <decoder ID from list>
```

- `list` shows which AV1 or VP9 decoders VideoToolbox knows. It decodes nothing.
- `-load` registers a bundle in this process only. Nothing is installed. It stops if the
  bundle cannot be registered. Pass `-id` with the decoder ID that `list` prints for it,
  or VideoToolbox may pick the installed decoder instead of the one you loaded.
- `-n` reads no pixels. `-a` decodes asynchronously. `-pace fps` feeds frames at a fixed
  rate and reports how late they come out. `vtvp9test` also has `-loop N` (the file N times
  in one session), `-frames N` and `-sw` (does not ask for hardware). `vtav1test -sw` decodes
  in software only: it turns hardware decoders off and stops before the first frame if
  VideoToolbox gives one anyway. (Apple's software AV1 decoder refused every stream here on
  macOS 26.7.3, 8-bit too: -12906.)
- `-attach` prints the colour attachments of the first picture (pixel format, primaries,
  transfer function, matrix, mastering display, light level) and again whenever they change.
- `vtvp9test -color P,T,M` gives the format description the colour a container would (the
  vpcC record and the colour extensions, H.273 code points; `9,16,9` = BT.2020 PQ), as
  Safari passes a WebM Colour element; `-hdr` adds a typical HDR10 mastering display and
  light level. Without `-color` the format says nothing (vpcC 2,2,2) and the plug-in has only
  the bitstream's color_space, which names no transfer function.
- These programs have no switch of their own: the plug-in arms itself. **A decode run can
  hang the GPU**, as soon as a hardware decoder is installed or loaded.

A pass: `UsingHardwareAcceleratedVideoDecoder = true`, then
`N frames, 0 mismatches, 0 errors`, and exit status 0.

### HDR test clips

FFmpeg makes the clips. Its libaom wrapper writes the colour of the sequence header but no
HDR metadata OBUs, so `av1hdr.py` adds an HDR_MDCV and an HDR_CLL OBU to every temporal unit
with a sequence header (P3 primaries, D65, 1000 / 0.005 cd/m2, MaxCLL 1000, MaxFALL 400):

```sh
SP=setparams=color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc:range=tv
ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=30 -t 2 -vf $SP,format=yuv420p10le \
  -c:v libaom-av1 -cpu-used 8 -row-mt 1 -g 30 -f ivf av1-pq.ivf
python3 -I decode/tests/gpu/av1hdr.py av1-pq.ivf av1-hdr10.ivf
ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=30 -t 2 -vf $SP,format=yuv420p10le \
  -c:v libvpx-vp9 -profile:v 2 -deadline realtime -cpu-used 8 -g 30 vp9-hdr10.webm
decode/build/gpu/vtav1test -load decode/build/AV1VCNDecoder.bundle av1-hdr10.ivf -n -attach \
  -id <decoder ID from list>
decode/build/gpu/vtvp9test -load decode/build/VP9VCNDecoder.bundle vp9-hdr10.webm -n -attach \
  -color 9,16,9 -hdr -id <decoder ID from list>
```

The setparams filter matters: without it FFmpeg 9.1 writes the matrix but leaves the
primaries and the transfer function unspecified. Expected for both clips: `x420`,
`ITU_R_2020`, `SMPTE_ST_2084_PQ`, `ITU_R_2020`, the 24 mastering display bytes
`33c286c4 1d4c0bb8 84d03e80 3d134042 00989680 00000032` and the light level `03e80190`.

## vtchurn

Creates and closes many sessions in one process, as a browser does over a day, and counts
the process's Mach port names and its IOKit user-client connections (the
`IOUserClientCreator` entries `ioreg` lists for its pid) at the start, after the first
session, every 50 sessions and at the end.

```sh
decode/build/gpu/vtchurn -load decode/build/AV1VCNDecoder.bundle av1 clip.ivf -n 200
decode/build/gpu/vtchurn -load decode/build/VP9VCNDecoder.bundle vp9 clip.ivf -n 200
```

- Each session decodes the first `-frames` frames (3), then is invalidated and released.
- The bundle is registered under its own ID, `com.droga.vtchurn.av1` or `.vp9`.
  VideoToolbox lists it as `com.droga.vtchurn.av1.av01` (the ID and the codec; a
  `DecoderID` in the registration is not used, seen on Tahoe 26.7.3) and every session
  asks for that decoder, so an installed plug-in cannot serve it. `-id` asks for another
  one, as for `vtav1test`.
- The first line gives the pid, for the plug-in's log lines of the run. The last lines give
  the growth per session that started after the first one (n/a with fewer than two), and
  the decoder plug-in images loaded in the process: there should be one.
- A decoder that releases what it opens grows by about 0 per session. 0.3.2 never released
  its accelerator (three IOKit connections a session, read in the driver, not measured).
- **Every session decodes on the GPU: it can hang the GPU.**

## probe_ctx

The first check on a new driver build. It opens the driver the way the decoders do, takes
AMD's accelerator (`vcn_find_accelerator()`, the same rule as the decoders), asks for one
decode context and deletes it. No picture is decoded.

```sh
decode/build/gpu/probe_ctx                 # AV1, 1920x1080
decode/build/gpu/probe_ctx 800 4 3840 2160 # HEVC, 4K
```

- Arguments: function (hex: `1000000` AV1, `800` HEVC, `8` H.264), mode, width, height.
- Mode 4 is the first VCN instance, the one the decoders use. AV1 with any other mode is
  refused before the driver is opened: the second instance has no AV1 on Navi 21, and AV1
  there hangs the GPU.
- No switch. Low risk, but it does open a session on the video block.

A pass: `CreateContexts(...) -> 0 context=0x...`, then `DeleteContexts -> 0`, and exit status
0. Status 2 means the driver refused the context.

## driveruuid

Prints the build identifier (UUID) of the installed `AMDRadeonVADriver2`. This is the value
the decoders look for in `kValidatedDrivers`. It loads the driver's code to read it, and
sends nothing to the GPU.

## vp9dump

Checks that the VP9 parser reads a file, with no driver and no GPU. For each frame it walks
the tile sizes: they only end exactly at the end of the frame when the headers were read
right. Run it on a new clip before you give that clip to the GPU.

```sh
decode/build/gpu/vp9dump v.ivf -v
```

A pass: `tiles_bad=0` on the last line, and exit status 0.

## vc1info

Says what a VC-1 advanced profile stream holds, with the plug-in's own parser and no driver
or GPU: the size, the interlace flag, and for each frame its coding mode and type (`p`
progressive, `f` frame-interlaced, `F` field-interlaced, then `P`/`B`/`I`/`b` for BI/`S` for
skipped, and for a field-interlaced frame the type of its second field).

```sh
decode/build/gpu/vc1info clip.vc1 16
```

Exit status 0 when the first 16 frames (all, without the number) include a field-interlaced
one, 3 when they do not, 1 when the parser stops on an error. `vc1info clip.vc1 16 cut.vc1`
also writes those 16 frames with their headers to `cut.vc1`, so FFmpeg and the GPU decode the
same short clip. Anything before the first sequence header (a stream copied out of a transport
stream in the middle) is skipped and left out of the cut.

## Dry runs: tools/driver/dryrun.py and dryrun_vp9.py

They run `decode_ivf` or `decode_vp9` under lldb. The real driver builds the real command,
the script copies it to a file, and then kills the process before the command reaches the
kernel. Use them before the first GPU run on a new driver build.

```sh
lldb --batch -o "command script import tools/driver/dryrun.py" \
  -o "dryrun /tmp/dry decode/build/gpu/decode_ivf av1-1-b8-01-size-16x16.ivf"
lldb --batch -o "command script import tools/driver/dryrun_vp9.py" \
  -o "dryrun_vp9 session /tmp/dry9 decode/build/gpu/decode_vp9 vp90-2-02-size-16x16.webm"
lldb --batch -o "command script import tools/driver/dryrun_vp9.py" \
  -o "dryrun_vp9 decode /tmp/dry9 decode/build/gpu/decode_vp9 vp90-2-02-size-16x16.webm"
```

- Do not set the arming switches yourself. The AV1 script arms `decode_ivf` for this run.
  The VP9 script removes `VCNVP9_ALLOW_GPU` and sets `VCNVP9_DRYRUN=1`: `decode_vp9` opens
  the driver without the arming switch only when it sees a debugger and that marker. A
  plain debugger session gets the usual refusal.
- Before the first decode command, the program stops at a checkpoint. The script checks
  there that its trap on the driver's submit function is set, and kills the process if it is
  not. An error in the script, or a stop it did not expect, also kills the process.
- What does go out: the driver's own setup of an AV1 session. In VP9 `decode` mode the
  script first checks that the session it lets through is a plain AV1 one.
- The output folder may only hold letters, digits and `. _ / -`.
- On a driver build that is not validated, AV1 also needs
  `VCNAV1_ALLOW_UNVALIDATED_DRIVER=1` in lldb's environment. VP9 has no such override:
  add the UUID to `decode/vp9/vcnvp9.c` only after the AV1 checks and the function compare.

A pass: `[dryrun] DRY RUN OK`. Then read the dump:

```sh
VCN_DEC_H=/path/to/mesa/src/amd/common/ac_vcn_dec.h \
  python3 tools/driver/vcnmsg.py /tmp/dry/vcn_msg.bin 'width|height'
```

`vcnmsg.py` needs Mesa's `ac_vcn_dec.h`, which is not in this repository. Check that sizes,
tile layout and bit depth match the clip.

## Validating a new macOS build

1. Read the driver's UUID. On an installed build: `decode/build/gpu/driveruuid`. Before you
   install it: unpack the update's system image with `decode/build/gpu/rawpatch`
   (`rawpatch payloadv2/image_patches/cryptex-system-x86_64 /tmp/system.dmg`), mount it
   read-only, then run
   `python3 tools/driver/dscdiff.py info <mount>/System/Library/dyld/dyld_shared_cache_x86_64h AMDRadeonVADriver2`.
2. Same UUID as a build in `kValidatedDrivers`: it is the same binary. Add the macOS build to
   `install/validated-builds.json`. Done.
3. New UUID: `python3 tools/driver/dscdiff.py diff <old cache> <new cache> AMDRadeonVADriver2`.
   Review every changed function on the decode path, and `VAContext::submitDataBuffers`,
   which the dry runs trap. `diff` needs `pip install capstone`.
4. On the new build: `probe_ctx`, then the AV1 dry run, then one small GPU run
   (`decode_ivf` on a 16x16 vector), then all the vectors. Then the VP9 dry runs and runs.
5. Last, `vtav1test` and `vtvp9test` with `-load`, and the web page below.

Keep caches, disk images and `dscdiff.py` output out of this repository: they are Apple's.

## Web pages: tests/web

- `index.html` asks WebKit about AV1 and VP9 (MediaSource, mediaCapabilities, WebCodecs).
  With `?clip=<file>` it also plays the clip for six seconds and counts dropped frames.
  With a hardware decoder in place, `powerEfficient` is `true` for `av01`.
- `webtest.swift` loads `index.html` in WebKit and prints the report:
  ```sh
  xcrun swiftc -O tests/web/webtest.swift -o tests/web/build/webtest
  tests/web/build/webtest tests/web/index.html [clip.mp4]
  ```
  Exit status 0 when the page reported, 3 after 30 seconds without a report.
- `vp9.html?src=<file.webm>` is the same for VP9, to open in Safari.
- `yt-probe.js` is pasted into Safari's Web Inspector on a YouTube video page. It shows how
  the browser answers YouTube's codec questions, and which formats YouTube offers.

Without a clip these pages only ask questions. **Playing a clip uses the installed decoders
and can hang the GPU** like any other decode.

`extras/userscript/youtube-prefer-av1.user.js` is an optional userscript. It makes YouTube
pick AV1 over VP9 when a video has both.
