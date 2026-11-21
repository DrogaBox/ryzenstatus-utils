# DrogaBoxGPU Installer

SwiftUI front end for the command-line installers in [install/](../install/README.md).

## Build

Requires Xcode Command Line Tools (`swiftc` and `codesign`).

```bash
zsh installer/build.sh
```

The app is written to `installer/build/DrogaBoxGPU Installer.app` and ad-hoc signed.
The app icon is `installer/assets/AppIcon.icns`, rendered from `installer/assets/render.swift`.

## How it works

- On launch, the app locates the DrogaBoxGPU folder (the one containing `install/`) relative to itself, or asks you to pick it once.
- **Install what this Mac needs** runs `install/install.sh plan` (with `--with-encoder` / `--with-sensors` when checked) without root, shows the plan in a sheet, and only runs `install/install.sh` with administrator privileges if you confirm.
- **Re-check** runs `install/decoders.sh check --json`, `install/loader.sh check --json`, `install/encoder.sh check --json`, `install/sensors.sh check --json`, and `install/check.sh` without administrator privileges.
- Each component has its own collapsible section with **Install** (or **Update** / **Repair**) and **Remove** buttons. Click anywhere on a section's header row to expand or collapse its checks.
- Actions that modify the system volume, LaunchDaemons, or OpenCore EFI run the corresponding script once through a macOS administrator prompt and display the script's full output.
- **Remove all** runs `install/undo.sh --yes` after confirmation.
