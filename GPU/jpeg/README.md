# JPEG decoder

`VCNJpeg.kext` decodes JPEG and Motion JPEG on the JPEG block of the VCN of a Navi 21 card
(RX 6800, 6800 XT, 6900 XT). Apple's driver carries the code that runs this block but never
starts it. The VideoToolbox plug-in `JPEGVCNDecoder.bundle` (`decode/jpeg/`) hands pictures
to the kext. Apps that play or read Motion JPEG through VideoToolbox (`jpeg` and `dmb1`:
webcam recordings, some cameras' clips) then decode on the GPU instead of the CPU.

It is optional, off by default, and for **macOS 26.7.3 (25G342) only**. On any other build the
kext does nothing, and VideoToolbox uses Apple's software decoder as before.

Still pictures opened by Preview, Photos or Safari do not go through VideoToolbox. They are
not changed.

## How it works

- When the driver starts its video queues, the kext creates the JPEG queue next to them and
  takes one block of buffers (128 MiB by default) from the same allocator. Both have to
  happen then: memory taken from it later lands on addresses the accelerator already uses.
- A program reaches the kext through the accelerator's video context: the connection every
  program that decodes video may open. The kext answers only its own requests there, and
  checks every size and every JPEG before the block sees it.
- One program decodes at a time. It loses its turn after 2 s without a request, or after 5 s
  in all (then it waits 2 s before it may take it again), and a program that was turned
  away gets the next turn. The kext does not pick programs: VideoToolbox runs the plug-in
  inside whichever program decodes Motion JPEG.
- When a turn ends, the kext clears the picture and the JPEG it was given.
- The block is powered only while pictures arrive. The first one asks PowerPlay for it the
  way the driver asks for a VCN session, and starts the queue. Two seconds after the last
  picture the kext stops the queue and gives the power back.
- A picture that does not finish within 3 s, or that writes past its buffer, stops the
  decoder until the next restart. New sessions then go to Apple's software decoder.
- When the driver loads, the kext checks the UUID of `AMDRadeonX6000HWLibs` and of
  `AMDRadeonX6000` and the start of every function it uses. If anything differs, it stays
  off.

The state is on IOResources:

```bash
ioreg -rd1 -c IOResources | grep VCNJpeg
```

`State` is `ready, block off` when it is waiting for pictures, `decoding, block on` while it
works, and `off: <reason>` or `stuck: ...` when it does not decode. `Jobs`, `PowerOns` and
`Failures` count since boot.

## Install

```bash
install/jpeg.sh check                          # changes nothing
sudo install/install.sh --with-jpeg            # the kext on the EFI, the plug-in on the system volume
```

Or part by part: `sudo install/jpeg.sh install` and `sudo install/decoders.sh install --jpeg`.
Then reboot.

Boot arguments:
- `-vcnjpegoff` turns the kext off.
- `vcnjpegpool=<MiB>` sizes the block of buffers, from 8 to 128. The default, 128, holds a
  48-megapixel 4:2:0 picture. A 4K 4:2:2 frame needs about 24.

## What it takes

Baseline JPEG, 8 bits, three components, 4:2:0 or 4:2:2, up to 16384 x 16384 (within the
buffer). Motion JPEG without Huffman tables of its own gets the standard ones.

Progressive JPEG, 4:4:4, grey and CMYK are refused. VideoToolbox then uses Apple's software
decoder.

Restart intervals (DRI) stay in the JPEG the block is given, as Mesa gives them on Linux:
the block reads them from the stream, there is no register for them.

Not tried on the GPU yet: whether the block ever reads the JPEG past the write pointer the
kext sets (the read buffer's size is "unbounded", `0xfffffff0`, as on Linux). If it does,
it reads zeros, because the rest of the JPEG buffer is cleared. A JPEG with a restart
interval has not been decoded on the GPU either.

## Build and test

```bash
jpeg/build.sh tests      # the kext and the host tests (needs tools/bootstrap.sh once)
jpeg/tests/run.sh        # the tests: commands, the door, when the block is powered
```

`jpeg/tests/run.sh` also compares the decode job with the commands of Apple's own driver
code and of Mesa when it has them: `KDK=` points at the KDK of 26.7.3, `MESA_DIR=` at a
copy of Mesa. Without them, those parts are skipped.

The GPU test is `decode/tests/gpu/vtjpegtest`: it decodes Motion JPEG clips through
VideoToolbox and compares every frame with FFmpeg's.

`kext/hwlibs_expect.hpp` (the functions the kext checks at load) comes from the KDK
through `tools/gen_expect.py`. A new macOS build gets its own table only after the code
that uses each function was read again; see [docs/macos-updates.md](../docs/macos-updates.md).
