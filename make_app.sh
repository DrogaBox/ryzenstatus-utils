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

echo "Signing App Bundle..."
codesign --force --sign - "$STAGE"
echo "Done! The app is at $STAGE"
