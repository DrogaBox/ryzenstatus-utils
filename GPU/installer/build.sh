#!/bin/zsh
# Build "RyzenStatus GPU.app": SwiftUI front end for install/*.sh.
# Output: installer/build/RyzenStatus GPU.app
#
# The app built here holds no parts: it finds install/ in the folders above it, or asks for
# the folder once (development). Tools/make-dmg.sh puts the verified parts
# (ReleaseAssets/GPU-Package.zip) into Contents/Resources/GPU of its own copy and signs it
# again; that copy is the one the DMG ships.
set -euo pipefail
cd "${0:A:h}"

APP="build/RyzenStatus GPU.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# x86_64 only: the GPU parts target Intel/AMD Hackintoshes with Navi 21 GPUs.
xcrun swiftc -parse-as-library -O -warnings-as-errors \
  -target x86_64-apple-macos14.0 \
  main.swift -o "$APP/Contents/MacOS/RyzenStatusGPUInstaller"

if [[ ! -f assets/AppIcon.icns ]]; then
  echo "error: missing installer/assets/AppIcon.icns" >&2
  exit 1
fi

cp Info.plist "$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign -f -s - "$APP"
echo "built $APP"
