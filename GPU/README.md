# GPU: AMD Radeon RX 6000 parts

This folder holds the plug-ins, kexts, installers and tests that RyzenStatus ships for AMD
Radeon RX 6000 cards. It keeps its own license (MIT, see [License](#license)); the rest of
the repository is GPL-3.0-or-later.

Hardware AV1 and VP9 decoding, and full-speed hardware encoding, for AMD Radeon RX 6000
graphics cards on macOS running on a PC (OpenCore, x86_64).

macOS ships a working driver for the Radeon RX 6800, 6800 XT and 6900 XT, but leaves part
of the card's video engine (VCN) unused or badly configured. This folder fills those gaps
without replacing any Apple driver:

| Part | What you get | How |
|---|---|---|
| **Decoders** (`decode/`) | Safari and Chrome play AV1 and VP9 video (YouTube up to 4K60 and 8K) on the GPU instead of the CPU | Two of macOS's VideoToolbox plug-ins that send AV1 and VP9 to the card's video engine through Apple's own driver |
| **Encoding fix** (`encode/`, optional) | Hardware HEVC/H.264 encoding at full speed: OBS at 4K60 without repeated frames, sizes wider than 4096 without GPU stalls | A small kernel extension for Lilu (a kext OpenCore loads, 1.7.0 or newer) that keeps the video engine's clocks up while encoding, and a service that corrects two settings in Apple's encoder process |
| **GPU sensors** (`sensors/`, optional) | Edge, memory and VR temperatures, voltages, throttling, video and fabric clocks, and PCIe link | A Lilu kernel extension that publishes the readings Apple's AMD driver already takes and hides, and `gpusensors` to print them |
| **Installer app** (`installer/`, optional) | Graphical front end for checking, installing, updating and removing each part | A SwiftUI app for the command-line tools in `install/` |

## Before you start

- **What it changes:** the decoders go into macOS's sealed system volume (needs `csrutil authenticated-root disable` from Recovery; see [install/README.md](install/README.md)); the kexts go into your OpenCore EFI after Lilu 1.7.0 or newer.
- **Code trust:** AMFI is macOS's check that only trusted code loads, and the decoder plug-ins are ad-hoc (signed with no certificate). You need one of AMFIPass (a third-party kext many hackintoshes run that relaxes AMFI), VCNVTLoader (built here), or plug-ins signed with a CA (a certificate authority) of your own that this Mac already trusts.
- **Encoding service (optional):** needs SIP Debugging Restrictions off (bit `0x4` of `csr-active-config`); see [encode/README.md](encode/README.md).
- **Risks:** keep a USB stick that boots your previous EFI; only validated macOS builds run, because a wrong message to the video engine can hang the GPU until a reboot.

Not affiliated with AMD or Apple. AMD and Radeon are trademarks of Advanced Micro Devices,
Inc.

## Status

| Component | Version | Run on a GPU |
|---|---|---|
| AV1 decoder (`decode/av1/`) | 0.3.4 | 0.3.3 on RX 6800 XT (Tahoe 26.7.3); 0.1 on RX 6900 XT (Sequoia 15.8.2) |
| VP9 decoder (`decode/vp9/`) | 0.3.4 | 0.3.3 on RX 6800 XT (Tahoe 26.7.3); 0.2 on RX 6900 XT (Sequoia 15.8.2) |
| Loader kext (`decode/loader/`) | 1.1.0 | RX 6800 XT (Tahoe 26.7.3) with AMFIPass off; not run on Sequoia |
| Encoding fix kext (`encode/kext/`) | 1.2.4 | RX 6800 XT (Tahoe 26.7.3); 1.2.1 reported on RX 6900 XT (Sequoia 15.8.3); Navi 23 static only |
| Encoding fix service (`encode/tool/`) | 1.2.4 | RX 6800 XT (Tahoe 26.7.3); 1.2.1 reported on RX 6900 XT (Sequoia 15.8.3) |
| GPU sensors kext (`sensors/`) | 0.8.0 | RX 6800 XT (Tahoe 26.7.3) |

Full test results, dates and what has never been tried are in [docs/status.md](docs/status.md).

## Supported hardware and macOS

- **Cards:** Radeon RX 6800, RX 6800 XT, RX 6900 XT (Navi 21). Also expected to work,
  never run: RX 6950 XT and RX 6900 XT XTXH when OpenCore presents them as `0x73BF`. See
  [docs/hardware.md](docs/hardware.md) for other RX 6000 cards and why most are out.
- **macOS:** the decoders run on Sequoia 15.8.2 and 15.8.3 and on Tahoe 26.7.1 to 26.7.3;
  the encoding fix on Sonoma 14.8.9, Sequoia 15.8.2 and 15.8.3 and Tahoe 26.7.3
  (`install/validated-builds.json`; on 14.8.9 only the encoding fix, not run on a GPU there). Every part
  checks the exact build of the Apple file it works with and stays off on any other build,
  so a macOS update can switch a feature off but cannot make it misbehave.
- **x86_64 only.** There is nothing here for Apple silicon.

## Build and test

Needs the Xcode Command Line Tools. Nothing below installs anything or touches the GPU.

```bash
tools/bootstrap.sh     # fetches the pinned kext SDK and test config into deps/ (once)
./build.sh             # builds the decoders, the loader kext, the GPU sensors and the encoding fix
tests/run.sh           # every test that needs no GPU
```

More in [docs/building.md](docs/building.md) and [docs/testing.md](docs/testing.md).

## Install

Build first (`./build.sh`); nothing in `install/` builds anything. Read
[install/README.md](install/README.md) first, and keep a USB stick that boots your previous
EFI.

```bash
install/check.sh                                        # look at this Mac; changes nothing
install/install.sh plan [--with-encoder] [--with-sensors]
sudo install/install.sh [--with-encoder] [--with-sensors] [--efi diskNsM]
```

Or build and open the installer app: `zsh installer/build.sh`, then open the app it writes
to `installer/build/` (see [installer/README.md](installer/README.md)).

After the reboot, run `install/check.sh`: it should say `Overall: working.`
Per-part commands (`decoders.sh`, `loader.sh`, `encoder.sh`, `sensors.sh`) are in
[install/README.md](install/README.md).

## Undo

```bash
install/undo.sh --dry-run                 # list what would be removed; changes nothing
sudo install/undo.sh [--efi diskNsM]      # remove all installed parts, then reboot (--yes skips the prompt)
```

If the Mac does not boot, start from your rescue USB EFI, or add
`-vcnflooroff -vcnvtoff -gpusensoff` to OpenCore's `boot-args`. More recovery options are
in [install/README.md](install/README.md#undo-everything).

## Repository layout

| Folder | What it is |
|---|---|
| `decode/` | The two decoder plug-ins: `av1/`, `vp9/`, the code they share in `common/`, the kext that lets them load without AMFIPass in `loader/`, and their tests |
| `encode/` | The encoding fix: `kext/`, the service in `tool/`, a test encoder in `vtenc/`, its scripts and tests |
| `sensors/` | The GPU sensors: a kext that publishes the readings the driver takes and hides, and `gpusensors` to show them |
| `install/` | Command-line installers and the list of validated macOS builds |
| `installer/` | Graphical installer app (SwiftUI front end for `install/`) |
| `tools/` | Dependency bootstrap, the repository cleanliness check, formatting, binary comparison, driver validation helpers |
| `tests/` | The test suite that needs no GPU, and the list of public test streams it downloads |
| `docs/` | [How it works](docs/how-it-works.md), [building](docs/building.md), [testing](docs/testing.md), [hardware](docs/hardware.md), [status](docs/status.md), [what to do when macOS updates](docs/macos-updates.md) |

## Safety

- A wrong message to the video engine can hang the GPU until a reboot. That is why every
  part refuses to run on a driver build it was not validated against, and why the test
  programs that reach the GPU must be armed by hand.
- Each kernel extension has its own off switch in boot-args (`-vcnflooroff`, `-vcnvtoff`,
  `-gpusensoff`).
- The decoder plug-ins are not signed by Apple, so macOS has to be told to accept them.
  There are three ways (AMFIPass, plug-ins signed with a CA of your own that the Mac trusts,
  or the loader kext here, which accepts only these plug-ins); [decode/loader/README.md](decode/loader/README.md)
  says which one fits your Mac. The install guide says which settings each feature needs
  and what they cost.

## Credits

Written by DrogaBox. Izzy ([wh0ami7](https://github.com/wh0ami7)) published and maintained
the decoders as *vcn-video-decoders*, tested them on an RX 6900 XT and wrote most of the
input checks in the parsers. Third-party material is listed in [NOTICE.md](NOTICE.md).

## License

MIT. See [LICENSE](LICENSE) and, for what others wrote, [NOTICE.md](NOTICE.md). The rest of
RyzenStatus is GPL-3.0-or-later; the MIT license of this folder is compatible with it.
