# Troubleshooting

A quick guide to the snags people hit most. If none of it helps, jump to [reporting a useful bug](#reporting-a-useful-bug) at the end.

The permission and uninstall commands below all point at RyzenStatus's bundle identifier, `com.ryzenstatus.utils`.

## The app will not open

Since RyzenStatus is an open-source tool and is not signed with a paid Apple Developer ID, macOS Gatekeeper will stop it on the first launch. To open it, do one of these:

1. Right click, or Control click, RyzenStatus in Applications, choose Open, and confirm.
2. Or open System Settings, Privacy and Security, find the note about RyzenStatus being blocked, and click Open Anyway.

RyzenStatus lives in the menu bar, so once it starts, look for its icon up there rather than in the Dock.

## A feature does nothing, or a permission will not stick

Most features lean on a macOS permission, which the [permissions guide](PERMISSIONS.md) lays out. When something does nothing, walk through this.

1. Open System Settings, Privacy and Security.
2. Find the permission the feature needs and make sure RyzenStatus is listed and switched on.
3. If it is listed and still quiet, toggle it off and back on.

RyzenStatus keeps an eye on Accessibility and Screen Recording, so features tend to wake up within a second or two of a grant, with no relaunch needed.

If a permission is switched on but stopped working after an update, open Settings › Advanced and use **Repair permissions**: it ties the permissions you already gave back to the installed version, without granting anything new. It needs Full Disk Access.

On a Hackintosh booted with AMFI relaxed (`amfi_get_out_of_my_way`), macOS may refuse a permission without ever showing its prompt. If a feature stays quiet and no prompt appeared, look for RyzenStatus in the matching System Settings list and switch it on there.

### Accessibility

This one powers the scroll direction inverter, Window Layout, the switcher, Dock Preview, Finder cut and paste and quit on close. If they do nothing, open System Settings, Privacy and Security, Accessibility and confirm RyzenStatus is switched on. If you rebuilt the app yourself, its signature can shift and macOS may treat it as a different app, so remove the old RyzenStatus entry with the minus button and grant it again. For steady local signing while you develop, see the [contributing guide](../CONTRIBUTING.md).

### Screen Recording

This one feeds window titles and thumbnails in the switcher and Dock Preview. If previews fall back to app icons or Dock Preview stays unavailable, switch RyzenStatus on in System Settings, Privacy and Security, Screen Recording. macOS may ask you to quit and reopen the app after you grant it.

### System Audio Recording

This one powers per app volume and output routing in the mixer. If the mixer says it needs permission, open System Settings, Privacy and Security, Screen and System Audio Recording, and switch RyzenStatus on. Audio is processed only for the local mixer.

### Microphone

This one powers microphone audio recording in Screen Recorder. If a screen recording has no voice track after enabling the microphone toggle, open System Settings, Privacy and Security, Microphone, and confirm RyzenStatus is switched on.

### Camera

This one powers the floating Camera Preview mirror. If the preview window shows a permission prompt, open System Settings, Privacy and Security, Camera, and allow RyzenStatus.

### Automation

Now Playing, Finder cut and paste, the uninstaller and Homebrew's Terminal handoff may ask for Automation. If a Finder move or Terminal handoff does nothing after a denial, open System Settings, Privacy and Security, Automation, and allow RyzenStatus for the app it needs to control.

### Now Playing shows nothing while music plays

Since macOS 15.4, Now Playing reads Music and Spotify by asking them directly, which needs Automation. Open System Settings, Privacy and Security, Automation, and switch on Music (or Spotify) under RyzenStatus. If RyzenStatus is not listed there, play a song, open the Dynamic Island once so the app asks, and check again.

## AMD controls

- **A control says your processor does not accept it.** The driver reports what each family supports, and the app only offers those controls. The table of families and command sets is in the [driver README](../SMCAMDProcessor_Source/README.md#supported-amd-processors).
- **Changes are refused.** Hardware writes need root, or the `-amdpnopchk` boot argument on a trusted personal machine. Reading telemetry needs neither.
- **The app warns about the driver version.** Install the two kexts from the same release as the app, into `EFI/OC/Kexts`, and restart. [Updating the AMD kexts](KEXTS.md) has the steps, with a way back if the Mac does not boot.
- **The Mac restarts while booting after a kext update.** Add `-amdoff` to OpenCore's boot-args so the CPU kext does not start, or boot your backup EFI; then restore the old kexts. [Updating the AMD kexts](KEXTS.md#4-if-the-mac-does-not-boot) has both steps.
- **You want to know whether the energy preference reaches the CPU.** Settings › AMD Ryzen › Hardware Validation shows the path it takes (CPPC MSRs or ACPI) and can read the values back from the firmware.
- **Deep idle cannot be switched on.** The `amdcstate=1` or `-amdnoidle` boot arguments forbid it; remove them and restart.
- **Two programs fight over fan control.** With kext 3.42.0, programs talking to the CPU kext coordinate fan writes so they no longer undo each other.

If another driver also attaches to the AMD host bridge at 00:00.0 to reach the SMU, the two drivers cannot share a lock, and their SMU mailbox commands could overlap. RyzenStatus checks for that before each of those writes and pauses its own power-limit, Curve Optimizer and preset writes while the other driver is there; sensors and readings keep working. Hardware Validation shows the same warning until the other driver is removed and the Mac restarts.

## AMD Radeon RX 6000 GPU & Video

NVIDIA cards and NullMoth are not supported or tested.

- **GPU control says changes are refused or busy.** Hardware writes need an administrator password via Allow GPU Changes, or the `-amdpnopchk` boot argument. Power limit and OverDrive settings (clocks, fan, voltage) cannot be held at the same time. The hotspot temperature watchdog puts stock settings back and closes changes if hotspot hits 95 °C or if sensor readings stop for 10 seconds.
- **Only readings show, with no controls to change.** Only the RX 6800 XT writes. The RX 6900 XT is read-only, and other Navi cards are not supported for writes yet. Hardware Validation shows whether GPUSensors.kext is loaded and found a supported card.
- **Video playback after a system sleep.** GPU decoders (0.3.9) drop in-flight frames during sleep and start clean at the next key frame. If a video player hung after a wake on an older release, update the decoders using the GPU installer.
- **Safari or apps do not load the video decoders.** The decoders require library validation to be relaxed, either through AMFIPass, VCNVTLoader, an internal CA, or AMFI switched off (`amfi=0x80`, `-amfipassoff`, or `-liluoff`). The GPU installer checks your AMFI configuration and guides the setup.

## Resetting permissions

To wipe RyzenStatus's granted permissions and let macOS ask again from scratch, pick one of these.

- **From the app.** Settings under Advanced has a reset that clears every permission you granted, the login item and the closed lid rule, while leaving the app installed.
- **From Terminal.** Reset all of RyzenStatus's privacy permissions at once.

  ```sh
  tccutil reset All com.ryzenstatus.utils
  ```

  Or reset a single kind, for example.

  ```sh
  tccutil reset Accessibility com.ryzenstatus.utils
  tccutil reset ScreenCapture com.ryzenstatus.utils
  ```

## Clean uninstall

The bundled script takes out everything RyzenStatus added, the app itself, its preferences and saved state, the login item, its privacy grants, and the optional closed lid `sudoers` rule.

```sh
./Tools/uninstall.sh
```

Run it from a clone of the repository, or download the single script from the repo. Would you rather do it by hand? Quit RyzenStatus, drag it from Applications to the Trash, then clear its permissions.

```sh
tccutil reset All com.ryzenstatus.utils
```

## Reporting a useful bug

A clear report gets fixed faster. Try to include the following.

- **What you did**, what you expected, and what actually happened.
- **Your versions**, both the RyzenStatus version from Settings under About and your macOS version.
- **Steps to reproduce**, as specific as you can make them.
- **A screenshot or short screen recording**, when the issue is something you can see.

If you have a build from source, the self test prints a quick health summary that is handy to paste in.

```sh
./build/RyzenStatus --selftest
```

Open a report from the [new issue](https://github.com/DrogaBox/ryzenstatus-utils/issues/new/choose) page, and see [support](../SUPPORT.md) for every way to get help.
