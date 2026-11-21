# Building

Everything builds for x86_64 with the Xcode Command Line Tools (Xcode 26.5, Apple clang 21
were used). Building installs nothing.

## Once: dependencies

```bash
tools/bootstrap.sh
```

Downloads into `deps/` (not committed), each pinned and checked by SHA-256 or commit:

- Lilu 1.7.2 DEBUG, for its plugin headers and `plugin_start.cpp`;
- MacKernelSDK at a fixed commit, for the kernel headers and `libkmod.a`;
- OpenCore 1.0.8's `Docs/Sample.plist`, for the config editing tests.

The three kexts (the loader, the GPU sensors and the encoding fix) need the first two; the
decoders and the command-line tools do not. To use copies you already have, export
`LILU_KEXT`, `MACKERNELSDK` and `OC_SAMPLE` instead.

## Build

```bash
./build.sh            # every part
./build.sh decode     # decode/build/: the two plug-ins, lvprobe and kextentry
./build.sh loader     # decode/build/VCNVTLoader.kext
./build.sh sensors    # sensors/build/GPUSensors.kext and gpusensors
./build.sh encode     # encode/build/ and the package encode/dist/VCNEncodeFix-<version>.zip
```

Versions come from `decode/VERSION`, `decode/loader/VERSION`, `sensors/VERSION` and
`encode/VERSION`.

## Reproducible builds

The same commit gives the same bytes:

- the decoders are built without debug information (set `DEBUG=1` to keep it). With it,
  the binary records the build folder, which also changes its signature hash;
- each kext embeds a build date, taken from `SOURCE_DATE_EPOCH`, which defaults to the
  date of the last commit.

`tests/run.sh` builds the decoders, the loader kext and the sensors kext and tool twice and
fails if the bytes differ.

## Comparing a build with an installed copy

An installed bundle may carry a different signature (for example one made with your own
certificate authority), so the files differ as a whole even when the code is the same.
Compare the sections instead:

```bash
tools/macho_sections.py decode/build/AV1VCNDecoder.bundle/Contents/MacOS/AV1VCNDecoder \
  /System/Library/Video/Plug-Ins/AV1VCNDecoder.bundle/Contents/MacOS/AV1VCNDecoder
```

Every line says `same` when the code and data are identical.

## Formatting and cleanliness

```bash
tools/format.sh          # formats C, C++ and Objective-C with .clang-format
tools/check_clean.sh     # run before every commit
```

`check_clean.sh` refuses binaries, archives, files over 1 MB, home folder paths, links to
file shares or forum threads and OpenCore machine identity fields. It also reads private
patterns, one regular expression per line, from `~/.config/drogabox/forbidden-patterns.txt`
(outside the repository): put your own serial numbers and names there.
`tools/check_clean.sh --history` checks every commit.
