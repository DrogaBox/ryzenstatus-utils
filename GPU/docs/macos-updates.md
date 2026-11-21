# When macOS updates

Every part of this repository checks the exact build of the Apple code it works with, and
does nothing on a build it was not checked against. So an update can switch a feature off,
but it should not make one misbehave. The first part of this page is for someone who has
the parts installed. The second part is for whoever adds support for a new build.

[how-it-works.md](how-it-works.md) explains what each check looks at.

## For a user

### What the update does to each part

| Part | Where it lives | After an update |
|---|---|---|
| Decoders | the system volume | Gone. Install them again (below) |
| VCNVTLoader | your OpenCore EFI | Still there. It acts only if AMFI's function starts as it expects |
| Encoding fix | the service in `/usr/local/libexec` and `/Library/LaunchDaemons`, the kext on your EFI | Still there. Both halves stay off on a build they were not validated for |
| GPU sensors | your OpenCore EFI | Still there. It acts only if the driver's function starts as it expects |

**The decoders are lost.** `install/decoders.sh install` put them into a changed copy of
the system volume and booted from a new snapshot of it. A macOS update writes a new system
volume from Apple's files, and the plug-ins are not in it. Until you install them again,
Safari decodes AV1 and VP9 in software.

**The decoders refuse a driver they do not know.** When a video starts, each plug-in reads
the build identifier of Apple's AMD video driver and refuses to open a session if that
identifier is not on its list. So plug-ins installed on a build whose driver they do not
know (with `--force`, for example) do nothing, and Safari decodes in software. The plug-in
logs the refusal:

```bash
/usr/bin/log show --last 10m --predicate 'subsystem == "com.droga.vtav1vcn"'
/usr/bin/log show --last 10m --predicate 'subsystem == "com.droga.vtvp9vcn"'
```

A line such as `vcnav1_create: AMDRadeonVADriver2 build ... not validated` (AV1) or
`... not validated for VP9` (VP9) means this.

**The encoding fix stays off** on a build that is not listed for it. The kext reports
`off: AMDRadeonX6000HWLibs build not validated` (or `X6800`), and the service leaves
Apple's encoder alone. Hardware encoding still works, at the speed it has without the fix.

### Before you update

Look for the new build in `install/validated-builds.json` of the latest version of this
repository. `install/check_lists.sh` prints the list in short form, one build per line,
and changes nothing:

```bash
install/check_lists.sh
```

- `av1` and `vp9` say `true` (decoded correctly on a card) or `"untested-on-gpu"` (the
  driver was checked, nobody has decoded with it yet): the decoders can be installed on
  that build.
- `false`, or a build that is not in the list: the decoders will not work there yet. If
  you update anyway, Safari decodes in software until a version that lists the build.
- `encode` says `true` when the encoding fix was checked on that build.

### After the update

1. Get the version of this repository that lists the new build, and build it
   (`./build.sh`; see [building.md](building.md)).
2. Run the overall check. It changes nothing and needs no `sudo`:

   ```bash
   install/check.sh
   ```

   It prints one line per part and an `Overall:` line. `install/check.sh --full` also
   shows every single check.
3. Do what the decoders' line says:
   - **ready**: `sudo install/decoders.sh install`, then reboot.
   - **blocked, this macOS build is not validated**: wait for a version that lists it.
     `sudo install/decoders.sh install --force` exists, but only for someone who has checked
     the new driver: a wrong message to an unchecked driver can hang the GPU until a
     reboot. And when the driver itself changed, the plug-ins refuse it anyway, so
     `--force` gives you plug-ins that do nothing.
   - a check marked **FAIL** for authenticated-root: run
     `csrutil authenticated-root disable` from Recovery, then run the check again.
   - **blocked, Apple's plug-ins are damaged**: `sudo install/decoders.sh repair`, then
     reboot. See [install/README.md](../install/README.md) first.
4. If the loader kext's line says the running kext was built for other plug-ins, or tells
   you to run `sudo install/loader.sh install`, do that as well. The kext lets through only
   the exact plug-ins it was built with, so new plug-ins need the kext of the same build.
   Do both before the one reboot.
5. If the encoding fix's line says an update is ready, run
   `sudo install/encoder.sh install`, adding `--efi auto` (or `--efi diskNsM`) when the kext is part of the
   update.
   Steps 3 to 5 can also be done in one go: `install/install.sh plan` lists what this Mac
   needs, and `sudo install/install.sh` installs it (add `--with-encoder` or
   `--with-sensors` for those parts).
6. After the reboot, run `install/check.sh` again. `Overall: working` means the decoders
   are installed and macOS lets Safari use them. It ends with status 0 only then.

Each part has its own check if you want more detail: `install/decoders.sh check`,
`install/loader.sh check`, `install/encoder.sh check`, `install/sensors.sh check`. For the
encoding fix, `doctor.sh` in the package folder (`encode/dist/VCNEncodeFix-<version>`)
says why a half is off.

### The kexts on the EFI

They are not on the system volume, so the update leaves them in place. Each one checks the
Apple code it hooks every time it starts:

- **VCNVTLoader** acts only when the two AMFI functions it uses start the way they did in
  the builds it was checked with. Otherwise `ioreg -r -c VCNVTLoader -l` shows a `Status`
  that starts with `off:`, `install/loader.sh check` says the kext is loaded but does
  nothing, AMFI refuses the plug-ins, and Safari decodes in software.
- **GPUSensors** reads one driver function only when its first 17 bytes are the expected
  ones. Otherwise its `Status` is `off: function does not start as expected`;
  `sensors/build/gpusensors` still shows what macOS publishes by itself.
- **VCNEncodeFloor** acts only on the power library builds it lists, as above.

They start only on the macOS versions in their Lilu settings: VCNVTLoader and GPUSensors on
Sequoia 15 and Tahoe 26, VCNEncodeFloor on Sonoma 14 to Tahoe 26. The boot arguments
`-vcnvtbeta`, `-gpusensbeta` and `-vcnfloorbeta` lift only that version limit, not the
build checks above. Each kext has its own off switch too: `-vcnvtoff`, `-gpusensoff`,
`-vcnflooroff`.

## For the maintainer

A new macOS build gets support part by part. Nothing here is automatic: each list is
changed by hand, after the checks below. Apple's files and anything made from them (kernel
collections, shared caches, disk images, disassembly, `dscdiff.py` output) stay out of this
repository.

Write down what was run, on which card and build, in [status.md](status.md).

### The decoders: the driverUUID rule

The decoders work with one Apple file, `AMDRadeonVADriver2`. Its build identifier (its
`LC_UUID`) decides everything:

- The same UUID as a build already in the list means the same binary. The new build only
  needs an entry in `install/validated-builds.json`. No code changes.
- A new UUID means a new driver. Its decode path must be compared and run on a card before
  the UUID goes into any list.

The UUID is listed in three places, and they must agree:

| File | What it holds |
|---|---|
| `install/validated-builds.json` | One entry per macOS build: `build`, `product`, `name`, `driverUUID`, `av1`, `vp9`, `encode`. The installers read it |
| `kValidatedDrivers` in `decode/av1/vcnav1.c` | The driver UUIDs the AV1 plug-in accepts |
| `kValidatedDrivers` in `decode/vp9/vcnvp9.c` | The driver UUIDs the VP9 plug-in accepts |

In the JSON, `av1` and `vp9` are `true` once the build decoded the conformance streams
correctly on a card, `"untested-on-gpu"` when the driver was checked but nobody decoded
with it yet, and `false` when the plug-in refuses this driver. A build may be listed with
both `false` for the encoding fix alone (Sonoma 14.8.9 is).

`install/check_lists.sh` compares the JSON with the two C lists and fails when a build
marked usable has a driver missing from a C list, when a C list holds a driver no usable
build names, when one driver is usable for one build and `false` for another, or when an
entry is malformed. `tests/run.sh` runs it on every run.

#### Validating a new build

The steps are in [decode/tests/gpu/README.md](../decode/tests/gpu/README.md), "Validating a
new macOS build". In short:

1. Read the driver's UUID.
   - On a Mac running that build: `decode/build/gpu/driveruuid` (built by
     `decode/tests/gpu/build.sh`; it loads the driver's code to read the header and sends
     nothing to the GPU).
   - Before installing it: turn the update's system image patch into a disk image with
     `decode/build/gpu/rawpatch <patch> <out.dmg>` (for example the patch
     `payloadv2/image_patches/cryptex-system-x86_64`), mount it read-only, and run
     `dscdiff.py info` on its shared cache:
     ```bash
     python3 tools/driver/dscdiff.py info \
       <mount>/System/Library/dyld/dyld_shared_cache_x86_64h AMDRadeonVADriver2
     ```
2. Same UUID as a listed build: add the entry to `install/validated-builds.json` with that
   `driverUUID`, and `av1` and `vp9` set to `"untested-on-gpu"` until someone decodes on
   that build (15.8.3 is listed so, with the same driver as 15.8.2). Run
   `install/check_lists.sh`. Done.
3. New UUID: compare the driver with a validated one,
   `python3 tools/driver/dscdiff.py diff <old cache> <new cache> AMDRadeonVADriver2`
   (needs `pip install capstone`). It masks code that only moved. Review every changed
   function on the decode path, and `VAContext::submitDataBuffers`, which the dry runs
   trap.
4. On the new build, in this order: `probe_ctx`; the AV1 dry run with
   `tools/driver/dryrun.py`; one small GPU run (`decode_ivf` on a 16x16 vector); all the
   vectors; then the VP9 dry runs with `tools/driver/dryrun_vp9.py` and the VP9 runs.
   On a driver that is not listed, `decode_ivf` and the AV1 dry run need
   `VCNAV1_ALLOW_UNVALIDATED_DRIVER=1` (in lldb's environment for the dry run), set only
   after a dry run passed. VP9 has no such override: add the UUID to
   `decode/vp9/vcnvp9.c` only after the AV1 checks and the function compare. Read the
   warnings in the GPU test README first: these runs can hang the GPU.
5. Last, `vtav1test` and `vtvp9test` with `-load`, and the pages in `tests/web/`.
6. Add the UUID to both `kValidatedDrivers` lists and the build to the JSON, and run
   `install/check_lists.sh`.

A change to either C list changes the plug-ins, so their code directory hashes change too.
Then:

- rebuild VCNVTLoader (`decode/loader/build.sh`) so that it lists the new plug-ins, and
  ship the two together;
- when a release is published, add the `CDHash` of both of its plug-ins to
  `decode/loader/released-builds.txt`, so a later kext still accepts them (no release has
  been published yet);
- whoever signs the plug-ins with their own certificate authority signs the new ones.

### The encoding fix: per-build tables

The encoding fix works with three Apple files, so its support is per macOS build, not per
driver UUID: Tahoe 26.7.2 has the same video driver as 26.7.3 and is still
`"encode": false`. A build needs an entry in each table below. The service and the kext
match by `LC_UUID`.

| Table | File | For |
|---|---|---|
| `kPresetBuilds` | `encode/tool/patches.c` | `AMDRadeonVADriver2`: the UUID and the bytes of the preset site |
| `kWideBuilds` | `encode/tool/patches.c` | `AppleGVAHEVCEncoder`: the UUID and the bytes of the call site |
| `kX6000Builds`, `kX6800Builds` | `encode/kext/kern_start.cpp` | The two power libraries: the UUID, and for a stripped library the function's offset and its first 32 bytes |
| the call site and cave of each build | `encode/tests/wide_test.c` | The CPU test of the wide patch |

Then set `"encode": true` for the build in `install/validated-builds.json`.

So far each build was checked by reading the code (the same fields and offsets as 26.7.3)
and by running the wide patch on the CPU at that build's call site
(`encode/build.sh` runs `wide_test`). Only 26.7.3 has run on a card here; a user reported
15.8.3 on an RX 6900 XT. Sonoma 14.8.9 and Sequoia 15.8.2 have not run on a card.

On a Mac running the new build, `install/encoder.sh check` shows in "Encoder files match"
whether the service's tables cover its files (`vcnencodefix status` says which build is not
validated), and the kext's state is the `VCNEncodeFloor` property of `IOResources`
(`ioreg -rd1 -c IOResources | grep VCNEncodeFloor`). The encoding fix keeps its own history
in `encode/CHANGELOG.md`.

### VCNVTLoader

The kext has no list of macOS builds. It accepts any AMFI whose failure function
(`_library_validation_failure`) starts with a plain prologue and whose code directory hash
accessor starts with the 13 bytes read in the builds below
(`decode/loader/allow_logic.hpp`). To check a new build before booting it, read those
functions from its boot kernel collection and give them to the test:

```bash
python3 tools/driver/amficheck.py <label>=<path>/BootKernelExtensions.kc > entries.txt
decode/build.sh tests
decode/build/tests/loadertest entries.txt
```

`tests/run.sh` does the same with the running Mac's own collection. Checked so far:
14.8.9, 15.8.2, 26.7.2 and 26.7.3. Not checked: 15.8.3 and 26.7.1. Not booted on Sequoia.

The kext's own list is of plug-in builds, not macOS builds: see the end of the decoders'
section above.

### GPUSensors

The kext has no list of macOS builds either. Its one build check is the first 17 bytes of
`_PEM_CWDDEPM_QueryPMLogData` (`kPrologue` in `sensors/kext/pmlog_logic.hpp`). To check a
new build, read the function from its system kernel collection and give it to the test:

```bash
python3 tools/driver/kcfunc.py com.apple.kext.AMDRadeonX6000HWLibs \
  _PEM_CWDDEPM_QueryPMLogData <label>=<path>/SystemKernelExtensions.kc > entries.txt
sensors/build.sh tests
sensors/build/tests/pmlogtest entries.txt
```

Do the same for `com.apple.kext.AMDRadeonX6800HWLibs`. `install/sensors.sh check` makes
the same comparison for the library the running Mac loads, and `tests/run.sh` checks the
running Mac too.

The prologue says nothing about the table itself: what each id means was read in the
driver, the fine points in that of 26.7.3 ([sensors/README.md](../sensors/README.md)).
After booting a new build, `sensors/build/gpusensors --compare` must show the same values
as macOS for the readings both publish (see [testing.md](testing.md)).

### A new macOS version

The version limits are in each kext's `PluginConfiguration` (`kern_start.cpp`):
`KernelVersion::Sequoia` to `KernelVersion::Tahoe` for VCNVTLoader and GPUSensors,
`KernelVersion::Sonoma` to `KernelVersion::Tahoe` for VCNEncodeFloor. The installers check
the version too: `decoders.sh` accepts Sequoia 15 to Tahoe 26, and `loader.sh` and
`sensors.sh` Sequoia 15 and Tahoe 26. Change these only together with the build checks
above.
