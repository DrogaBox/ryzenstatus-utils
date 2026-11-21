# VCNVTLoader

A small kernel extension (Lilu plug-in) that lets the AV1 and VP9 decoder plug-ins load on
a Mac that does not run AMFIPass.

## Do you need it?

Safari decodes video in two Apple programs, `com.apple.WebKit.GPU` and
`VTDecoderXPCService`. macOS only lets them load code signed by Apple. The plug-ins built
here are not signed by Apple, so something has to tell macOS to accept them. There are
three ways, and you need exactly one:

| Your Mac | What to use | This kext |
|---|---|---|
| Runs AMFIPass, or boots with `amfi_get_out_of_my_way=0x1` | Nothing more. The plug-ins already load | Not needed |
| Trusts a certificate authority (CA) of your own, through a kext that adds it to macOS's checks | Sign the plug-ins with your CA | Not needed |
| Neither | **VCNVTLoader** | Needed |

With a CA of your own, sign copies of the plug-ins, so that `decode/build` stays the build
VCNVTLoader knows, and install the copies:

```bash
mkdir ~/signed-decoders
cp -R decode/build/AV1VCNDecoder.bundle decode/build/VP9VCNDecoder.bundle ~/signed-decoders/
# sign both copies with your CA, then, after the reboot that loads the kext trusting it:
sudo install/decoders.sh install --bundles ~/signed-decoders
```

That kext is not part of RyzenStatus.

The kext is open source and does one thing. It does not turn any protection off: it adds
one exception to one check, for the exact plug-in builds listed inside it. The exception
is tied to the build, not to Safari: any program with the same check may load those exact
plug-ins, from any folder.

## What it does

When macOS refuses to load a library into a protected program, the refusal goes through
one function of AppleMobileFileIntegrity. The kext stands in front of that function. If
the library is one of the listed plug-in builds, it answers "allowed". For anything else
it calls Apple's function, so every other refusal stays as it was.

A build is identified by its code directory hash (what `codesign -dvvv` prints as
`CDHash`). The hash covers the plug-in's code, its `Info.plist` and its resources: change
one byte of the plug-in and it is refused again.

The kext only acts when the function it stands in front of starts the way it did in the
macOS builds that were read. On any other build it does nothing and says so.

## Build

```bash
tools/bootstrap.sh          # once: fetches the pinned Lilu and kernel SDK
decode/build.sh             # the plug-ins
decode/loader/build.sh      # the kext, listing the plug-ins just built
```

The result is `decode/build/VCNVTLoader.kext`. **The kext and the plug-ins go together.**
If you rebuild the plug-ins, rebuild the kext and install both: a kext built for other
plug-ins refuses yours.

To also allow bundles from somewhere else, name them:
`decode/loader/build.sh /path/AV1VCNDecoder.bundle`. Builds of published releases are
listed in `released-builds.txt` and are always allowed.

## Install

```bash
install/loader.sh check            # changes nothing
sudo install/loader.sh install     # then reboot
```

It goes in `EFI/OC/Kexts`, with an entry in `config.plist` under Kernel > Add, after Lilu.
`install/loader.sh` does both, with a backup of `config.plist`, and checks the result; see
[install/README.md](../../install/README.md). `install/decoders.sh check` also knows the
kext: it tells you whether the one that is running, or the one on a mounted EFI, accepts
the plug-ins you are about to install.

## Check that it works

```bash
ioreg -r -c VCNVTLoader -l | grep -E '"(Status|AllowedBuilds|Overrides)"'
```

- `Status = "active"`: the exception is in place.
- `AllowedBuilds`: how many plug-in builds the kext lists.
- `Overrides`: how many times a listed plug-in was let through since boot. It goes up
  when Safari starts playing an AV1 or VP9 video. On a Mac with AMFIPass it stays at 0,
  because the plug-ins are never refused there.

Any `Status` that starts with `off:` means the kext changed nothing, and why.
`waiting for AMFI` after the Mac has started means the same: the kext never got to act.
`off: another kext already handles this AMFI function` is what you see next to a kext that
changed the same function first; the plug-ins are then in that kext's hands.

## Switches

Boot arguments: `-vcnvtoff` turns the kext off, `-vcnvtdbg` logs more, `-vcnvtbeta` lets it
start on a kernel newer than the last one it was checked on.

## What has been checked

| What | Result |
|---|---|
| The two AMFI functions, in the kernel collections of 14.8.9 (23J631), 15.8.2 (24H232), 26.7.2 (25G332) and 26.7.3 (25G342) | Same names, same first instructions; accepted by the kext's entry check (`tools/driver/amficheck.py` and `loadertest`) |
| Version 1.0.0 of the same exception, on 26.7.3 with AMFIPass off | A listed ad-hoc plug-in loaded into a protected program; unlisted ad-hoc libraries were still refused |
| Version 1.1.0 (this code), RX 6800 XT, Tahoe 26.7.3, AMFIPass switched off, ad-hoc plug-ins 0.3.0 installed (2026-11-18) | `Status = active`. Safari played YouTube in AV1 and VP9 at 3840x2160 in hardware, with the plug-ins mapped in `VTDecoderXPCService` and `com.apple.WebKit.GPU`; `Overrides` went up with each load; another ad-hoc library was still refused; nothing about the plug-ins in the kernel log |
| 15.8.3 and 26.7.1 | Not checked: no kernel collection of those builds at hand |
| Sequoia 15 on a real machine | Not booted there |

## Limits

- It is for the decoder plug-ins only. It does nothing for the encoding fix.
- macOS versions: Sequoia 15 and Tahoe 26, the ones the decoders support.
- Each release of the plug-ins needs a kext that lists it.
- Built against Lilu 1.7.2; the test machine runs Lilu 1.7.3.
