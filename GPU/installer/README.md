# RyzenStatus GPU

SwiftUI front end for the command-line installers in [install/](../install/README.md). It
ships in the RyzenStatus DMG, in the folder `GPU RX 6000`, and is opened from there.

## Build

Requires Xcode Command Line Tools (`swiftc` and `codesign`).

```bash
zsh installer/build.sh
```

The app is written to `installer/build/RyzenStatus GPU.app` and ad-hoc signed. It runs on
macOS 14 or newer (x86_64); on macOS 14 only the encoding fix is validated
(`install/validated-builds.json`), so the other parts stay off there.
The app icon is `installer/assets/AppIcon.icns`, rendered from `installer/assets/render.swift`.

## Where it finds the parts

- **In the DMG:** `Tools/make-dmg.sh` (at the top of the RyzenStatus repository) builds the
  app with this script, puts the parts from `ReleaseAssets/GPU-Package.zip` into
  `Contents/Resources/GPU` after checking them against the pinned `SHA256SUMS`, and signs
  the app again. The app uses that folder first, wherever the app is (the mounted DMG,
  Applications, a translocated copy), and then offers no folder choice.
- **Development:** an app built here has no parts inside. It looks for the folder that
  contains `install/` above itself (so `installer/build/` inside `GPU/` works), then in the
  current folder, then in the folder chosen last time, and otherwise asks for it
  (**Choose Folder…**, and **Change Folder…** in the header).
- `RyzenStatusGPUInstaller --print-payload` says whether the app carries its parts and
  where, and exits without opening a window (status 0 yes, 1 no).

## How it works

- **Install what this Mac needs** runs `install/install.sh plan` (with `--with-encoder` / `--with-sensors` when checked) without root, shows the plan in a sheet, and only runs `install/install.sh` with administrator privileges if you confirm.
- **Re-check** runs `install/check.sh --json-dir DIR` once, without administrator privileges: it checks each part once, prints the summary, and writes each part's `check --json` answer into `DIR`, a folder of the app's own in the temporary folder that it deletes afterwards.
- Each component has its own collapsible section with **Install** (or **Update** / **Repair**) and **Remove** buttons. Click anywhere on a section's header row to expand or collapse its checks.
- Actions that modify the system volume, LaunchDaemons, or OpenCore EFI run the corresponding script once through a macOS administrator prompt and display the script's full output.
- **Remove all** runs `install/undo.sh --yes` after confirmation.
- Cancelling the administrator password prompt is shown as cancelled (nothing was changed), not as a failure. When **Reboot now** cannot restart the Mac (for example, no permission to control System Events), the window says why.
- When GPUSensors.kext is gone but our `gpucontrol` or `gpusensors` is still in `/usr/local/bin`, the GPU sensors' **Remove** runs `install/sensors.sh uninstall-tools`, which removes only those.
