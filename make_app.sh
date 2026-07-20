#!/bin/zsh
set -e

echo "Building RyzenStatus in Release..."
swift build -c release --product RyzenStatus

APP_NAME="RyzenStatus"
EXECUTABLE="RyzenStatus"
STAGE="$HOME/Desktop/$APP_NAME.app"

echo "Creating app bundle at $STAGE..."
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

cp .build/x86_64-apple-macosx/release/RyzenStatus "$STAGE/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"

for lproj in Resources/*.lproj(N); do
    cp -R "$lproj" "$STAGE/Contents/Resources/"
done

printf 'APPL????' > "$STAGE/Contents/PkgInfo"
cp build/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
cp build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png "$STAGE/Contents/Resources/" 2>/dev/null || true
cp CHANGELOG.md "$STAGE/Contents/Resources/CHANGELOG.md" 2>/dev/null || true

echo "Signing App Bundle..."
codesign --force --sign - "$STAGE"
echo "Done! The app is at $STAGE"
