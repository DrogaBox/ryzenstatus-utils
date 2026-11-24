# Installing

Command-line tools and one list. Build first (`./build.sh` at the top of the repository);
nothing here builds anything.

## Before you start

- Keep a USB stick that boots your current OpenCore EFI.
- **Decoders:** written to macOS's sealed system volume; requires `csrutil authenticated-root disable` from Recovery.
- **Kexts:** go into your OpenCore EFI after **Lilu 1.7.0 or newer** enabled in `config.plist`.
- **Code trust (for decoders):** you need one of AMFIPass, VCNVTLoader (built here), or plug-ins signed with a certificate authority of your own that this Mac trusts; see [decode/loader/README.md](../decode/loader/README.md).
- **Encoding service (optional):** needs SIP Debugging Restrictions off (bit `0x4` of `csr-active-config`); see [encode/README.md](../encode/README.md).
- **macOS build:** only validated builds in `install/validated-builds.json` run, because an unvalidated driver call can hang the GPU until a reboot.

Start with:

```bash
install/check.sh          # everything, one line per part and one for the whole; changes nothing
install/install.sh plan   # what this Mac needs, and why; changes nothing
sudo install/install.sh   # installs exactly that, then reboot
# After the reboot:
install/check.sh          # should say "Overall: working."
```

`install.sh` looks at the Mac first: the macOS build, the card, whether AMFI is off or
AMFIPass is running, Lilu, SIP, and what is already installed. It installs the decoders,
and the loader kext only when nothing else lets the plug-ins in. The encoding fix and the
GPU sensors are optional: add `--with-encoder` and `--with-sensors`. With the sensors kext
already current, `--with-sensors` copies only `gpucontrol` and `gpusensors` to
`/usr/local/bin` when they are missing there or differ. It finds the EFI
partition OpenCore started from (or the only one that holds OpenCore), or takes `--efi`.
`plan` looks at the EFI partitions too, without mounting any: when more than one mounted
EFI partition holds OpenCore and OpenCore does not say which one it started from, the plan
is blocked and says what to do, before any password.
When any part asked for cannot be installed, it installs nothing and says why. The one
exception is a check that a step of the same run settles: when all the decoders wait for is
the loader kext (none yet, or one built for other plug-ins) and the loader kext can go in,
it goes in first and the decoders right after it, in one run; they load after the reboot.
A step that fails stops the rest, and `sudo install/undo.sh` takes everything off (see
[Undo everything](#undo-everything)). A loader kext put in just before the decoders stays
when they fail: it lets in only these plug-ins and the next run needs it.

| File | What it is |
|---|---|
| `install.sh` | Decides what this Mac needs and runs the tools below in order. `plan` only says what it would do |
| `check.sh` | Runs every `check` below once and sums them up. It counts the loader kext only when this Mac needs it. `--full` also shows every single check; `--json-dir DIR` also writes each part's `check --json` answer to `DIR/<part>.json`, from the same look (the app uses it) |
| `undo.sh` | Takes off everything below that it finds installed, each part with its own `uninstall`, EFI parts first, after one confirmation, and `gpucontrol` and `gpusensors` from `/usr/local/bin` (ours only) even when the sensors kext is gone already. `--dry-run` only lists the steps. It never picks a partition that is not of type EFI (a rescue USB stick) by itself |
| `decoders.sh` | Installs, repairs or removes the AV1 and VP9 decoder plug-ins |
| `loader.sh` | Puts VCNVTLoader, the kext the plug-ins need on a Mac without AMFIPass, on your EFI, or takes it off |
| `sensors.sh` | Puts GPUSensors, the optional kext that shows the GPU readings macOS hides, on your EFI, or takes it off |
| `encoder.sh` | Installs or removes the optional encoding fix |
| `validated-builds.json` | The list of macOS builds that were checked. Both tools read it |
| `check_lists.sh` | Checks that this list agrees with the lists compiled into the decoders |

Every tool has `--help`. The `check` commands change nothing and need no `sudo`. Run them
first.

## Undo everything

To remove every part this repository installed, in a safe order (EFI kexts first, decoders
last):

```bash
install/undo.sh --dry-run                      # list what would be removed; changes nothing
sudo install/undo.sh [--efi diskNsM]           # remove all installed parts, then reboot (--yes skips the prompt)
```

Or remove individual parts (then reboot after any EFI or system-volume change):

- Decoders: `sudo install/decoders.sh uninstall`
- Loader kext: `sudo install/loader.sh uninstall [--efi diskNsM]`
- GPU sensors kext: `sudo install/sensors.sh uninstall [--efi diskNsM]`
- Encoding fix: `sudo install/encoder.sh uninstall [--efi diskNsM|auto]`

If the Mac does not boot after a change:

- Boot your rescue USB EFI and copy the backup (`config.plist.backup-<date>-<time>-pre-*`,
  saved next to `EFI/OC/config.plist` before each EFI edit) back over `EFI/OC/config.plist`.
- Or add the kext off switches to OpenCore `boot-args`: `-vcnflooroff` (encoding kext),
  `-vcnvtoff` (loader kext), `-gpusensoff` (GPU sensors kext).
- To revert the system volume to Apple's original snapshot:
  `sudo bless --mount / --last-sealed-snapshot`, then reboot. **Warning:** this drops
  every other change made to the system volume, not only the decoder plug-ins.

## The decoders

```bash
install/decoders.sh check                 # is this Mac ready? changes nothing
sudo install/decoders.sh install          # then reboot
sudo install/decoders.sh uninstall        # then reboot
sudo install/decoders.sh repair           # only if check tells you to
```

The MPEG-2, VC-1 and MPEG-4 plug-ins are built and the loader kext lists them, but they are
installed only with `--legacy` (or `VCNVT_LEGACY_DECODERS=1`; `install.sh
--with-legacy-decoders` passes it on). They have not run through VideoToolbox on a GPU yet.
With `--legacy`, `check` also looks at the `legacy` column of `validated-builds.json`, and
`install` puts all five plug-ins in place. `uninstall` always removes all five. The DMG
carries the three only when it is built with `VCNVT_LEGACY_DECODERS=1`.

### What `check` looks at

The checks run in this order. `install` runs the same checks and stops if one fails.

| Check | What it means |
|---|---|
| macOS version | The builds of Sequoia 15 and Tahoe 26 listed in `install/validated-builds.json` |
| GPU driver validated | Your exact macOS build must be in `validated-builds.json`. The decoders talk to Apple's AMD video driver. A wrong message to it can hang the GPU until a reboot, so a build nobody checked is refused |
| Authenticated-root disabled | macOS normally refuses to boot from a system volume that was changed. `csrutil authenticated-root status` must say `disabled`. You turn it off from Recovery with `csrutil authenticated-root disable` |
| macOS accepts the plug-ins | Safari decodes video in protected Apple programs that refuse plug-ins not signed by Apple. One of the four options below must allow these exact plug-ins; `check` verifies them before anything is installed |
| Supported AMD GPU | A warning only. Radeon RX 6800, 6800 XT and 6900 XT (Navi 21), plus RX 6950 XT and RX 6900 XT XTXH when OpenCore presents them as `0x73BF` (never run); see [docs/hardware.md](../docs/hardware.md) |
| System video plug-ins intact | Apple's own plug-ins must all be in `/System/Library/Video/Plug-Ins`. If some are missing, `repair` puts them back |
| Decoder bundles present | `decode/build` must hold both plug-ins. Run `./build.sh decode` |

How **macOS accepts the plug-ins** is checked:

- **AMFIPass** running.
- **VCNVTLoader** (`decode/loader/`, open source, accepts only these plug-ins) on your EFI,
  built together with the plug-ins. A `VCNVTLoader` on an EFI, enabled after an enabled Lilu
  in its `config.plist`, counts even if you have not rebooted into it yet, and `check` says so.
- The plug-ins signed with **your own certificate authority**, and a kext loaded that makes
  macOS trust it (not part of RyzenStatus).
- AMFI switched off with `amfi_get_out_of_my_way=0x1` (not advised: it switches the
  protection off for everything).
- **Verification and EFI scanning:** when neither AMFIPass nor `amfi_get_out_of_my_way=0x1`
  applies, `check` asks macOS itself whether it would load these exact plug-ins (with
  `decode/build/lvprobe`, which loads nothing), so a kext built for other plug-ins or an
  untrusted signature is caught beforehand. `check` looks at mounted EFI partitions only; as
  root, `install` and `repair` also mount unmounted EFI partitions read-only to look
  (`loader.sh install` unmounts the one it used).

`check` also says whether the plug-ins are installed now, and whether they are the same
code as the ones in `decode/build`.

`check --json` prints the same result as one JSON object. It always ends with status 0.
The plain `check` ends with 0 when `install` would go ahead, 3 when only the macOS build
is in the way, and 2 for anything else.

### What `install` changes

The system volume is the read-only disk macOS boots from. It cannot be changed while it
runs. So `install` works on a second, writable mount of it and makes a new boot snapshot:

1. It mounts the system volume at `/System/Volumes/Update/mnt1`.
2. It copies `AV1VCNDecoder.bundle` and `VP9VCNDecoder.bundle` into
   `System/Library/Video/Plug-Ins` on that mount, each first under a temporary name
   (`.bundle.new`). Only a copy that is complete and has the same code signature hash as
   the one it was built with replaces the older one. The script can delete these folders and
   nothing else.
3. It checks again, in place, that each plug-in has that code signature hash.
4. It deletes a copy of the two plug-ins in `/Library/Video/Plug-Ins`, if there is one.
   macOS ignores our plug-ins there. This step takes effect at once.
5. It runs `bless --create-snapshot`. That makes a snapshot of the changed volume and
   tells the Mac to boot from it next time.

You must reboot. Until then the running system is the old snapshot. Apart from step 4,
nothing has changed for it. The script unmounts `/System/Volumes/Update/mnt1` when it
ends, if it mounted it.

Why the system folder: macOS loads video plug-ins from `/System/Library/Video/Plug-Ins`
without checking who signed them. In `/Library/Video/Plug-Ins` it only accepts plug-ins
signed by Apple.

`--force` installs on a macOS build that is not in the list. Do not use it unless you have
checked that build's driver yourself. The plug-ins also carry their own list of drivers
and stay off on a driver that is not in it. So on a build with a new driver, `--force`
gives you plug-ins that do nothing.

### What `repair` does

Use it only when `check` says that Apple's plug-ins are damaged or missing.

1. It finds Apple's original snapshot of the system volume (its name starts with
   `com.apple.os.update-`) and mounts it read-only in a new folder of root's (made with
   `mktemp`), which it removes afterwards.
2. It copies every Apple plug-in that is missing back into the system folder, and completes
   one that is there without its `Contents/Info.plist` from Apple's copy. It never deletes a
   plug-in. The only thing it deletes is a stray `Contents` (folder, file or link) directly
   inside `Plug-Ins`.
3. It installs the two decoders as `install` does. On a macOS build that is not in the
   list it skips this step, unless you pass `--force`.
4. It makes the new boot snapshot. Reboot.

### What `uninstall` does

It deletes the two decoder plug-ins from the mounted system volume and makes a new boot
snapshot. Reboot. Apple's plug-ins are not touched. When neither plug-in is there it says so
and makes no snapshot.

### How to undo

- `sudo install/decoders.sh uninstall`, then reboot.
- Or go back to Apple's original system volume: `sudo bless --mount / --last-sealed-snapshot`,
  then reboot. This also drops every other change that was made to your system volume.
- To remove all parts together, see [Undo everything](#undo-everything).

### If something goes wrong

- A step fails before the snapshot is made: the script says so and stops. Your running
  system and the snapshot it boots from are unchanged. Fix the cause and run the same
  command again.
- `bless` fails: the files are already changed on the mount, but no snapshot was made, so
  the next boot does not use them. Run the same command again.
- Video stops working after the reboot: uninstall, or use the second way under "How to
  undo".
- The Mac does not boot after an install or uninstall (it stops right after OpenCore,
  before the Apple logo): start macOS Recovery and open Terminal. Find your system volume
  with `diskutil list` (the one named like your Mac's disk, without "- Data"), then:

  ```bash
  diskutil unmount /Volumes/<your volume>
  mkdir -p /Volumes/sysrw
  mount -t apfs -o nobrowse /dev/diskXsY /Volumes/sysrw
  bless --mount /Volumes/sysrw --bootefi --last-sealed-snapshot
  ```

  Use your volume's name and its `diskXsY`. Restart: the Mac boots the last sealed
  snapshot, from before the change. `bless --mount /` does not work in Recovery, because
  that volume is read-only there.

## The loader kext

Only for a Mac without AMFIPass. `install/decoders.sh check` says whether yours needs it
(the check "macOS accepts the plug-ins").

```bash
install/loader.sh check                 # changes nothing; ends in one line
sudo install/loader.sh install          # then reboot
sudo install/loader.sh uninstall        # then reboot
```

Install the decoders and the kext from the same build: the kext lets through only the
plug-ins it was built with. The order does not matter, as long as both are done before the
reboot.

### Which EFI

Without `--efi` the script takes the EFI partition OpenCore says it started from. OpenCore
only says so when `Misc > Security > ExposeSensitiveData` has bit `0x1`; otherwise the
script takes the only partition that holds OpenCore. When there are several and it cannot
tell, it lists them and stops: run it again with `--efi diskNsM`. `--efi-folder DIR` works
on a folder that holds `EFI/OC` instead, such as a USB stick that is already mounted, or a
copy. `check` says so before any install, when it can tell without mounting anything: a
check row "EFI partition to install on" appears when more than one mounted EFI partition
holds OpenCore.

### What `install` checks first

Nothing is changed until all of these hold:

| Check | Why |
|---|---|
| The kext is built and lists the plug-ins in `decode/build` | a kext built for other plug-ins refuses them |
| macOS is Sequoia 15 or Tahoe 26 | the kext only starts there |
| The EFI holds OpenCore and Lilu 1.7.0 or newer, enabled in `config.plist` | the kext is a Lilu plug-in |
| `config.plist` is an XML OpenCore config that can be read | OpenCore needs XML |
| There is room on the partition | the copy is made next to the old one first |

`check` also says whether the kext is needed at all: with AMFIPass running or AMFI switched
off, the plug-ins load without it.

### What `install` changes

All of it on the EFI partition:

1. The kext is copied to `EFI/OC/Kexts/VCNVTLoader.kext.new`, compared with the original,
   and swapped in. A copy that was there before is replaced; the same build is left alone.
2. One entry is added to `Kernel > Add` in `config.plist`, after Lilu. A backup named
   `config.plist.backup-<date>-<time>-pre-vcnvtloader` is written next to it first. The
   edit is checked: the new file must be the old one plus the entry, nothing else. An entry
   that was there with other settings (switched off, for example) is replaced.
3. The result is read back as OpenCore will find it.

The partition is mounted if needed and unmounted again, also when the script stops early.
The kext is copied before its entry is added, and `uninstall` removes the entry before the
kext, so an interrupted run never leaves an entry that points to a missing kext.

### If the Mac does not start

Start it from another EFI (the USB stick) and copy the backup over
`EFI/OC/config.plist`, or add `-vcnvtoff` to the boot arguments. The install prints the
name of the backup. See [Undo everything](#undo-everything) to remove all parts.

## The GPU sensors

Optional, and independent of everything else here. See
[sensors/README.md](../sensors/README.md) for what it shows.

```bash
install/sensors.sh check                 # changes nothing; ends in one line
sudo install/sensors.sh install          # then reboot
sudo install/sensors.sh uninstall        # then reboot
sudo install/sensors.sh uninstall-tools  # only gpucontrol and gpusensors, when the kext is gone
```

It puts the kext on the EFI the same way `loader.sh` does (the code is shared:
`efikext.zsh`), with the same choice of EFI, the same backup of `config.plist` and the same
rescue (boot-arg `-gpusensoff`; see [Undo everything](#undo-everything)). Before anything is
changed it also checks that the card is a Navi 21, and that the driver function the kext
reads from starts on this Mac as the kext expects.

## The encoding fix

This part is optional and separate. It never touches the decoders or the system volume.
It has two halves:

- **The service.** A small program that runs in the background and corrects two settings
  in Apple's encoder process. It works at once, with no reboot.
- **The kext.** `VCNEncodeFloor.kext`, a kernel extension that OpenCore loads at boot. It
  keeps the video engine's clocks up while encoding. It needs Lilu and a reboot.

```bash
install/encoder.sh check                                 # changes nothing
sudo install/encoder.sh install                          # the service only
sudo install/encoder.sh install --efi auto               # find the OpenCore EFI automatically
sudo install/encoder.sh install --efi disk0s1            # or name the partition, then reboot
sudo install/encoder.sh uninstall --efi disk0s1          # remove both (--efi auto also works), then reboot
```

`--efi` accepts a partition identifier (`diskNsM`, as listed by `check`) or `auto` (the
partition OpenCore says it started from, else the only EFI partition with OpenCore), for
both `install` and `uninstall`. Unlike `loader.sh` and `sensors.sh`, `encoder.sh` does not
take `--efi-folder`, and unlike the standalone package's `install.sh`, it does not take a
mount point such as `/Volumes/EFI`.

### What `check` looks at

| Check | What it means |
|---|---|
| Encoding fix package present | `encode/dist/VCNEncodeFix-<version>` exists and its files match their checksums. Run `./build.sh encode` |
| macOS build validated for encoding | Your macOS build must have `"encode": true` in `validated-builds.json` |
| Encoder files match | The service found the exact code it corrects in Apple's files |
| Access to the encoder process | A warning only. The service needs SIP's "Debugging Restrictions" off (bit `0x4` in `csr-active-config`). See `encode/README.md`, Requirements. The kext works without it |
| Navi 21 GPU | Radeon RX 6800, 6800 XT and 6900 XT (Navi 21), plus RX 6950 XT and RX 6900 XT XTXH when OpenCore presents them as `0x73BF` (never run); see [docs/hardware.md](../docs/hardware.md). Stops on any other card |
| Lilu loaded | A warning only. The kext needs Lilu. The service does not |

`install/encoder.sh` stops if the `Navi 21 GPU` check fails and has no `--force` option.
To test on another card (such as Navi 23), run the package's own installer directly with
`--force` (`sudo encode/dist/VCNEncodeFix-<version>/install.sh --force [--efi /Volumes/EFI]`):
`--force` skips only the GPU check and still checks the macOS build patches and EFI.

It also shows whether the service is installed and running, whether the kext is loaded,
and, for each EFI partition that is mounted, whether it holds OpenCore, the config entry
and the kext. `check` never mounts a partition.

### What `install` changes

`encoder.sh` runs the checks, then hands over to the package's own `install.sh`.

The service:

- `/usr/local/libexec/vcnencodefix` (the program)
- `/Library/LaunchDaemons/com.droga.vcnencodefix.plist` (starts it at boot)
- `/etc/newsyslog.d/vcnencodefix.conf` and `/var/log/vcnencodefix.log` (its log)
- An earlier test version named `com.droga.vcnpreset` is removed if it is there.

With `--efi`, also the kext:

- The partition is mounted if it is not, and unmounted again at the end.
- It must hold `EFI/OC/config.plist`, `EFI/OC/OpenCore.efi` and `EFI/OC/Kexts/Lilu.kext`
  (1.7.0 or newer, enabled in `config.plist`), and enough free space. An entry for the kext
  that is disabled, before Lilu or with other settings is refused (exit status 3): fix or
  remove it by hand. If any of this fails, nothing is changed, the service included.
- `VCNEncodeFloor.kext` is copied into `EFI/OC/Kexts`.
- One entry is added to Kernel > Add in `config.plist`, or the MinKernel of an entry written
  by an earlier version is updated. A copy of the file is saved first, next to it, as
  `config.plist.backup-<date>-<time>-pre-vcnencodefix`. The edit is checked afterwards.

### How to undo

- `sudo install/encoder.sh uninstall` removes the service. The log file is kept.
- `sudo install/encoder.sh uninstall --efi diskNsM` (or `--efi auto`) also removes the kext
  and its config entry. The kext stays loaded until you reboot.
- If the Mac does not start after adding the kext: boot another EFI (your USB stick), then
  either add `-vcnflooroff` to boot-args or copy the backup over `EFI/OC/config.plist`.
- To remove all parts together, see [Undo everything](#undo-everything).

## The list of validated builds

`validated-builds.json` has one entry per macOS build:

| Field | Meaning |
|---|---|
| `build`, `product`, `name` | The macOS build, for example `25G342`, `26.7.3`, `Tahoe 26.7.3` |
| `driverUUID` | The identifier of that build's AMD video driver (`AMDRadeonVADriver2`). Two builds with the same value have the same driver |
| `av1`, `vp9` | `true`: decoded correctly on a real card. `"untested-on-gpu"`: the driver was checked but nobody ran it yet. `false`: the decoder refuses this driver |
| `legacy` | The same, for the MPEG-2, VC-1 and MPEG-4 plug-ins, which share one list |
| `encode` | `true`: the encoding fix was checked on this build |

The decoders carry their own copy of the driver identifiers (`kValidatedDrivers` in
`decode/av1/vcnav1.c`, `decode/vp9/vcnvp9.c` and `decode/common/vcnlegacy.c`). When you add a
build, change every place,
then run:

```bash
install/check_lists.sh
```

It prints both lists and fails if they name different drivers.

## Testing the refusals

`VCNVT_FAKE_BUILD=<build>` makes the checks see another macOS build. For example
`VCNVT_FAKE_BUILD=99Z999 install/decoders.sh check` shows the answer for a build that is
not in the list. It is for testing only.
