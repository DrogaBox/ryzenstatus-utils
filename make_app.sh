#!/bin/zsh
set -e

echo "Building RyzenStatus in Release..."
swift build -c release --product RyzenStatus

for asset in build/AppIcon.icns build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png; do
    if [[ ! -f "$asset" ]]; then
        echo "error: missing $asset — run ./build.sh first to generate icon assets" >&2
        exit 1
    fi
done

APP_NAME="RyzenStatus"
EXECUTABLE="RyzenStatus"
STAGE="$HOME/Desktop/$APP_NAME.app"

echo "Creating app bundle at $STAGE..."
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

BIN_PATH="$(swift build -c release --show-bin-path)/RyzenStatus"
cp "$BIN_PATH" "$STAGE/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"

for lproj in Resources/*.lproj(N); do
    cp -R "$lproj" "$STAGE/Contents/Resources/"
done

printf 'APPL????' > "$STAGE/Contents/PkgInfo"
cp build/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
cp build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png "$STAGE/Contents/Resources/"
cp CHANGELOG.md "$STAGE/Contents/Resources/CHANGELOG.md"
# AUDIT A-11: ship the same resources as build.sh — the Dock-preview
# onboarding movie and highlight images were missing from this bundle,
# which made SwiftPM builds behave differently from release builds.
if [[ -f Resources/Gifs/dockPreview.gif ]]; then
    mkdir -p "$STAGE/Contents/Resources/Gifs"
    cp Resources/Gifs/dockPreview.gif "$STAGE/Contents/Resources/Gifs/"
fi
if [[ -d Resources/Images ]]; then
    mkdir -p "$STAGE/Contents/Resources/Images"
    cp Resources/Images/* "$STAGE/Contents/Resources/Images/" 2>/dev/null || true
fi

echo "Signing App Bundle..."
# AUDIT A-11: sign with the same entitlements the official bundle uses.
codesign --force --sign - --entitlements Resources/ZenStatus.entitlements "$STAGE"
echo "Done! The app is at $STAGE"
