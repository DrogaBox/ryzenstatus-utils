#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RyzenStatus

# Packages the built app into a styled, distributable DMG
# (dist/RyzenStatus-<version>.dmg): a window with the app icon, an arrow and
# the Applications folder for drag-and-drop install. Run ./build.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="RyzenStatus"
APP="build/stage/$APP_NAME.app"
VOLUME="$APP_NAME"
STAGING=""
WORK=""
MOUNT=""
KEXT_TEMP=""

cleanup() {
    if [[ -n "$MOUNT" ]]; then
        hdiutil detach "$MOUNT" -quiet 2>/dev/null \
            || hdiutil detach "$MOUNT" -force -quiet 2>/dev/null \
            || true
    fi
    [[ -n "$STAGING" ]] && rm -rf "$STAGING"
    [[ -n "$WORK" ]] && rm -rf "$WORK"
    [[ -n "$KEXT_TEMP" ]] && rm -rf "$KEXT_TEMP"
}
trap cleanup EXIT

if [[ ! -d "$APP" ]]; then
    echo "✗ $APP not found — run ./build.sh first" >&2
    exit 1
fi
xattr -cr "$APP"
codesign --verify --deep --strict "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="dist/RyzenStatus-$VERSION.dmg"

echo "▸ Rendering installer background…"
swift Tools/MakeDMGBackground.swift build/dmg-background.png

echo "▸ Staging DMG contents…"
STAGING="$(mktemp -d)"
ditto "$APP" "$STAGING/$APP_NAME.app"
xattr -cr "$STAGING/$APP_NAME.app"
codesign --verify --deep --strict "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
# Include our kexts for EFI/OC/Kexts/
KEXT_DRIVER="SMCAMDProcessor_Source/build/dmg-kexts/AMDRyzenCPUPowerManagement.kext"
KEXT_PLUGIN="SMCAMDProcessor_Source/build/dmg-kexts/SMCAMDProcessor.kext"
KEXT_SOURCE_LOCAL=""
if [[ -d "$KEXT_DRIVER" && -d "$KEXT_PLUGIN" ]]; then
    KEXT_SOURCE_LOCAL="1"
fi
if [[ ! -d "$KEXT_DRIVER" || ! -d "$KEXT_PLUGIN" ]] && [[ -f "ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip" ]]; then
    EXPECTED_SHA="93c88a224fc37be5923aef19bf8375cd0306d27f4d19f2dd970387b5663abced"
    ACTUAL_SHA="$(shasum -a 256 "ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip" | awk '{print $1}')"
    if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
        echo "✗ Error: ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip SHA-256 mismatch ($ACTUAL_SHA != $EXPECTED_SHA)" >&2
        exit 1
    fi
    KEXT_TEMP="$(mktemp -d)"
    ditto -x -k "ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip" "$KEXT_TEMP"
    KEXT_DRIVER="$KEXT_TEMP/AMDRyzenCPUPowerManagement.kext"
    KEXT_PLUGIN="$KEXT_TEMP/SMCAMDProcessor.kext"
    echo "  ✓ Prebuilt AMD kexts verified and extracted from ReleaseAssets"
fi
if [[ -d "$KEXT_DRIVER" && -d "$KEXT_PLUGIN" ]]; then
    mkdir -p "$STAGING/Kexts"
    ditto "$KEXT_DRIVER" "$STAGING/Kexts/AMDRyzenCPUPowerManagement.kext"
    ditto "$KEXT_PLUGIN" "$STAGING/Kexts/SMCAMDProcessor.kext"
    rm -rf "$KEXT_TEMP"
    KEXT_TEMP=""
    # S11: report provenance and version of what actually got packaged.
    #
    # The SHA-256 gate above only runs when SMCAMDProcessor_Source/build/dmg-kexts/
    # is absent. On a maintainer machine that directory usually exists and is
    # gitignored, so locally built kexts were packaged with no verification and no
    # output saying so — `git status` clean, versioned state at one version, DMG
    # shipping another. That local path is legitimate (it is how new kexts reach
    # the test machine for hardware validation); what was wrong is that it was
    # silent.
    # PlistBuddy writes "File Doesn't Exist, Will Create:" to STDOUT (not stderr),
    # so 2>/dev/null cannot suppress it — guard on the file instead, or a broken
    # bundle would report that notice as its version string.
    PACKAGED_KEXT_PLIST="$STAGING/Kexts/AMDRyzenCPUPowerManagement.kext/Contents/Info.plist"
    if [[ -f "$PACKAGED_KEXT_PLIST" ]]; then
        PACKAGED_KEXT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
            "$PACKAGED_KEXT_PLIST" 2>/dev/null || echo 'unknown')"
    else
        PACKAGED_KEXT_VERSION="unknown"
    fi
    echo "  ✓ AMDRyzenCPUPowerManagement.kext $PACKAGED_KEXT_VERSION added to DMG"
    if [[ -n "$KEXT_SOURCE_LOCAL" ]]; then
        echo "  ⚠ Source: LOCAL BUILD (SMCAMDProcessor_Source/build/dmg-kexts/) — SHA gate NOT applied."
        echo "    These binaries are unverified. Do not publish this DMG until the"
        echo "    hardware probes pass; see .kiro/steering/hardware-safety.md."
    else
        echo "    Source: ReleaseAssets zip, SHA-256 verified."
    fi
    echo "  ✓ SMCAMDProcessor.kext added to DMG"
else
    echo "  (Kexts not built — skipping)" >&2
fi
mkdir "$STAGING/.background"
cp build/dmg-background.png "$STAGING/.background/background.png"
# S11: seed the window layout from a checked-in .DS_Store.
#
# The Finder automation below is the only thing that positions the icons and
# applies the background, and it needs Automation (Apple Events) permission for
# Finder. A GitHub runner has no Finder session at all, and a local shell that
# was never granted the permission gets `-10004 privilege violation`, so BOTH
# produce an unstyled DMG while still exiting 0 — the branding silently
# disappeared with no failure anywhere.
#
# Seeding the layout here makes styling the default rather than a side effect of
# a permission: hdiutil bakes this .DS_Store into the image, and the AppleScript
# then either succeeds and refines it or fails harmlessly on top of a volume that
# already looks right. The alias inside resolves because the volume name is
# always "$VOLUME" and the background always sits at .background/background.png.
if [[ -f "Tools/dmg-layout.DS_Store" ]]; then
    cp "Tools/dmg-layout.DS_Store" "$STAGING/.DS_Store"
    echo "  ✓ Window layout seeded from Tools/dmg-layout.DS_Store"
else
    echo "  ⚠ Tools/dmg-layout.DS_Store missing — styling depends on Finder automation" >&2
fi

echo "▸ Creating writable image…"
WORK="$(mktemp -d)"
RW="$WORK/rw.dmg"
# Clear any stale mount left by a previous attempt on the same runner.
hdiutil detach "/Volumes/$VOLUME" -force 2>/dev/null || true
# hdiutil can fail transiently on CI runners; retry a few times. No -quiet, so a
# real error is visible in the build log rather than swallowed.
created=0
for attempt in 1 2 3; do
    if hdiutil create -volname "$VOLUME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -ov "$RW"; then
        created=1
        break
    fi
    echo "  hdiutil create failed (attempt $attempt of 3), retrying…" >&2
    rm -f "$RW"
    sleep 3
done
if [[ $created -ne 1 ]]; then
    echo "✗ Could not create the disk image after 3 attempts" >&2
    exit 1
fi
ATTACH_OUTPUT="$(hdiutil attach "$RW" -nobrowse)"
MOUNT="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/\/Volumes\// {print substr($0, index($0, "/Volumes/")); exit}')"
if [[ -z "$MOUNT" || ! -d "$MOUNT" ]]; then
    echo "✗ Could not find mounted volume in hdiutil output" >&2
    printf '%s\n' "$ATTACH_OUTPUT" >&2
    exit 1
fi

echo "▸ Arranging window (icons, arrow, background)…"
# Finder automation lays out the window; best-effort so a headless hiccup never
# fails the release (the DMG is still valid, just unstyled that once).
KEXT_POSITION=""
if [[ -d "$STAGING/Kexts" ]]; then
    KEXT_POSITION='set position of item "Kexts" of container window to {150, 120}'
fi
osascript <<APPLESCRIPT &
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 800, 600}
        set theOptions to the icon view options of container window
        set arrangement of theOptions to not arranged
        set icon size of theOptions to 128
        set text size of theOptions to 13
        set background picture of theOptions to file ".background:background.png"
$KEXT_POSITION
        set position of item "$APP_NAME.app" of container window to {150, 275}
        set position of item "Applications" of container window to {450, 275}

        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
STYLE_PID=$!
STYLE_STATUS=0
STYLE_TIMED_OUT=0
for _ in {1..25}; do
    if ! kill -0 "$STYLE_PID" 2>/dev/null; then
        wait "$STYLE_PID" || STYLE_STATUS=$?
        break
    fi
    sleep 1
done
if kill -0 "$STYLE_PID" 2>/dev/null; then
    STYLE_TIMED_OUT=1
    kill "$STYLE_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$STYLE_PID" 2>/dev/null || true
    wait "$STYLE_PID" 2>/dev/null || true
fi
if (( STYLE_TIMED_OUT )); then
    echo "  (window styling timed out; continuing with a valid unstyled DMG)"
elif (( STYLE_STATUS != 0 )); then
    echo "  (window styling skipped)"
fi

sync
hdiutil detach "$MOUNT" -quiet \
    || hdiutil detach "$MOUNT" -force -quiet
MOUNT=""

echo "▸ Compressing…"
mkdir -p dist
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" -quiet

echo "✓ DMG ready: $OUT"
