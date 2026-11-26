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

# The release build passes the SHA-256 of the GPU parts' SHA256SUMS. A
# development checkout has no pin and the installer says the list is not pinned.
PIN="${GPU_PAYLOAD_SUMS_SHA256:-}"
if [[ -n "$PIN" && ! "$PIN" =~ '^[0-9a-f]{64}$' ]]; then
  echo "error: GPU_PAYLOAD_SUMS_SHA256 must be 64 lowercase hex characters" >&2
  exit 1
fi
PIN_FILE="build/PayloadPin.swift"
mkdir -p build
{
  print -r -- 'enum InstallerPin {'
  print -r -- "    static let payloadSumsSHA256 = \"$PIN\""
  print -r -- '}'
} > "$PIN_FILE"

# x86_64 only: the GPU parts target Intel/AMD Hackintoshes with Navi 21 GPUs.
xcrun swiftc -parse-as-library -O -warnings-as-errors \
  -target x86_64-apple-macos14.0 \
  main.swift "$PIN_FILE" -o "$APP/Contents/MacOS/RyzenStatusGPUInstaller"

if [[ ! -f assets/AppIcon.icns ]]; then
  echo "error: missing installer/assets/AppIcon.icns" >&2
  exit 1
fi

cp Info.plist "$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign -f -s - "$APP"
echo "built $APP"
