# Which cards

Everything here depends on Apple's own AMD driver. Apple shipped it for the cards in its
Macs, so the question for a card is not "is it fast enough" but "does macOS drive it at
all, and with which video block".

## Supported: Navi 21

Radeon RX 6800, RX 6800 XT, RX 6900 XT (PCI device 0x73BF). Apple's driver knows this chip,
its video block (VCN 3) can decode AV1 and VP9, and the encoding fix was measured on it.

Also expected to work, never run: the RX 6950 XT and the RX 6900 XT XTXH (device 0x73A5 and
0x73AF), which need OpenCore to present them as 0x73BF, as they already do to get Apple's
driver at all. Same for the Radeon Pro W6800 and W6900X.

Setups that load `AMDRadeonX6800HWLibs` instead of `AMDRadeonX6000HWLibs` (for example with
NootRX): the encoding kext hooks both libraries (the function it changes is the same code),
but it was only run with X6000.

## Possible, not done: Navi 23

RX 6600, 6600 XT, 6650 XT (PCI device 0x73E0 to 0x73EF, 0x73FF). The video block is the
same generation, but nothing in this repository has run on a Navi 23 card:

- **Decoders (`decode/`):** never run on Navi 23, and the first AV1 job on a new card can
  hang the GPU until a reset. `install/decoders.sh` prints a warning on non-Navi-21 GPUs
  and does not block installation. Before installing anything into the system volume, test
  in a separate process with `probe_ctx`, `decode_ivf` and `decode_vp9` (see
  [decode/tests/gpu/README.md](../decode/tests/gpu/README.md)).
- **Encoding fix (`encode/`):** since 1.2.4, `VCNEncodeFloor.kext` checks Navi 23's own
  clock levels (two published RX 6600 XT tables: VCLK 690/1429 MHz, DCLK 572/1250 MHz; the
  132297 floor lands inside them). This was checked statically only and has never run on a
  card. `install/encoder.sh` stops on a non-Navi-21 GPU (no `--force` flag); the package's
  own `encode/dist/VCNEncodeFix-<version>/install.sh` also stops unless `--force` is passed
  to skip the GPU check.
- **GPU sensors (`sensors/`):** `install/sensors.sh` stops on a non-Navi-21 GPU. Inside
  `GPUSensors.kext`, `PP_EnableAllPMLogSensors` is only set on Navi 21 cards; if the kext
  is loaded by hand on a Navi 23 card that uses `AMDRadeonX6000HWLibs` or
  `AMDRadeonX6800HWLibs`, the PMLog hook itself does not check the GPU model and would only
  copy whatever default table the driver fills (never tested on Navi 23).
- **Loader kext (`decode/loader/`):** `VCNVTLoader.kext` and `install/loader.sh` do not
  check the GPU model or touch the AMD driver; the kext only handles AMFI library
  validation for the decoder plug-ins.

If a test boot with any kext hangs, add its off switch to OpenCore `boot-args` (or boot
your rescue USB EFI): `-vcnflooroff` (encoding kext), `-gpusensoff` (GPU sensors kext),
`-vcnvtoff` (loader kext).

## Out

| Cards | Why |
|---|---|
| RX 6700, 6700 XT, 6750 XT (Navi 22) | Apple has no driver for this chip; only third-party kexts make it work, and whether they enable the video block is unknown |
| RX 6400, 6500 XT (Navi 24), RX 7000, RX 9000 | no Apple driver |
| RX 5500 to 5700 XT (Navi 10 and 14) | the video block has no AV1 decoding; the encoding fix was not studied there |
