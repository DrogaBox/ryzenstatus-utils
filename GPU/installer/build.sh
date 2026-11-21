#!/bin/zsh
# Build "DrogaBoxGPU Installer.app": SwiftUI front end for install/*.sh.
# Output: installer/build/DrogaBoxGPU Installer.app
set -euo pipefail
cd "${0:A:h}"

APP="build/DrogaBoxGPU Installer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# x86_64 only: DrogaBoxGPU targets Intel/AMD Hackintoshes with Navi 21 GPUs.
xcrun swiftc -parse-as-library -O -warnings-as-errors \
  -target x86_64-apple-macos15.0 \
  main.swift -o "$APP/Contents/MacOS/DrogaBoxGPUInstaller"

if [[ ! -f assets/AppIcon.icns ]]; then
  echo "error: missing installer/assets/AppIcon.icns" >&2
  exit 1
fi

cp Info.plist "$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign -f -s - "$APP"
echo "built $APP"
