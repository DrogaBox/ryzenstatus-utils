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
# Pin what SHIPS, not the container it arrived in.
#
# This replaced an EXPECTED_SHA on the zip archive. That pin had two problems.
# It verified the container: a legitimate rebuild from byte-identical binaries
# produced a different archive hash (proven — `ditto -c -k` is deterministic, but
# the archive embeds each entry's mtime, so fresh build timestamps alone change
# it), which trained whoever hit it to paste the new hash in and moved the gate
# toward decoration. And it only ran on the zip path, so the local-build path it
# could not see was the one that actually shipped.
#
# These four hashes are the two Mach-O binaries and the two Info.plists — the
# bytes the kernel loads and the identity it loads them under. They survive any
# repackaging and they cover BOTH provenance paths, because the check now runs on
# the staged bundles rather than on the archive.
KEXT_PIN_DRIVER_MACHO="4b3585b9d008d4ba18994818728640f1899b7c6689254bd7956b578fbf488389"
KEXT_PIN_DRIVER_PLIST="71d923d3bdd3e59e27f390fe8bafb6b15e73445f2cab5090d0d46e3404aaa11e"
KEXT_PIN_PLUGIN_MACHO="f7dfa57d0bfb8c6aa99f48a614f89a7ba13e825ae2ed17b781b4098933f5746a"
KEXT_PIN_PLUGIN_PLIST="6183894d72ae2a3ab182436fe1af0dd9521116ca0c855af0b4cf029adadb10ca"
if [[ ! -d "$KEXT_DRIVER" || ! -d "$KEXT_PLUGIN" ]] && [[ -f "ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip" ]]; then
    # Structural pre-check: assert the archive's top level is exactly the two
    # kext bundles. Unlike a hash this never needs updating on a rebuild, and it
    # catches the driver-only bug — a zip refreshed with only the driver — here, with a
    # message that names the cause, instead of downstream as a missing path.
    ZIP_ROOTS="$(unzip -Z1 "ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip" \
        | awk -F/ 'NF>0 {print $1}' | sort -u)"
    EXPECTED_ROOTS="$(printf 'AMDRyzenCPUPowerManagement.kext\nSMCAMDProcessor.kext\n')"
    if [[ "$ZIP_ROOTS" != "$EXPECTED_ROOTS" ]]; then
        echo "✗ Error: ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip does not contain exactly the two expected kexts." >&2
        echo "  expected at archive root:" >&2
        printf '%s\n' "$EXPECTED_ROOTS" | sed 's/^/    /' >&2
        echo "  found:" >&2
        printf '%s\n' "$ZIP_ROOTS" | sed 's/^/    /' >&2
        exit 1
    fi
    KEXT_TEMP="$(mktemp -d)"
    ditto -x -k "ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip" "$KEXT_TEMP"
    KEXT_DRIVER="$KEXT_TEMP/AMDRyzenCPUPowerManagement.kext"
    KEXT_PLUGIN="$KEXT_TEMP/SMCAMDProcessor.kext"
    echo "  ✓ Prebuilt AMD kexts extracted from ReleaseAssets (2 bundles, as expected)"
fi
if [[ -d "$KEXT_DRIVER" && -d "$KEXT_PLUGIN" ]]; then
    mkdir -p "$STAGING/Kexts"
    ditto "$KEXT_DRIVER" "$STAGING/Kexts/AMDRyzenCPUPowerManagement.kext"
    ditto "$KEXT_PLUGIN" "$STAGING/Kexts/SMCAMDProcessor.kext"
    rm -rf "$KEXT_TEMP"
    KEXT_TEMP=""
    # Report provenance and version of what actually got packaged.
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
    # Verify the CONTENT of what was staged, on both provenance paths.
    #
    # Strict on the ReleaseAssets path: a mismatch there means the reviewed
    # binaries are not the ones about to ship, which must never be published.
    # Reporting-only on the local path: a locally built kext is EXPECTED to differ
    # (that is how a new revision reaches the test machine), so the hashes are
    # printed to be recorded rather than compared. Printing them is the point —
    # it is what makes an unverified build identifiable after the fact.
    KEXT_CONTENT_OK="1"
    check_pin() {  # $1 label, $2 path, $3 expected sha
        local actual
        actual="$(shasum -a 256 "$2" | awk '{print $1}')"
        if [[ "$actual" == "$3" ]]; then
            return 0
        fi
        KEXT_CONTENT_OK=""
        echo "    $1: $actual" >&2
        return 1
    }
    check_pin "driver Mach-O" "$STAGING/Kexts/AMDRyzenCPUPowerManagement.kext/Contents/MacOS/AMDRyzenCPUPowerManagement" "$KEXT_PIN_DRIVER_MACHO" || true
    check_pin "driver Info.plist" "$STAGING/Kexts/AMDRyzenCPUPowerManagement.kext/Contents/Info.plist" "$KEXT_PIN_DRIVER_PLIST" || true
    check_pin "plugin Mach-O" "$STAGING/Kexts/SMCAMDProcessor.kext/Contents/MacOS/SMCAMDProcessor" "$KEXT_PIN_PLUGIN_MACHO" || true
    check_pin "plugin Info.plist" "$STAGING/Kexts/SMCAMDProcessor.kext/Contents/Info.plist" "$KEXT_PIN_PLUGIN_PLIST" || true
    for signed in AMDRyzenCPUPowerManagement SMCAMDProcessor; do
        if ! codesign --verify --deep --strict "$STAGING/Kexts/$signed.kext" 2>/dev/null; then
            KEXT_CONTENT_OK=""
            echo "    $signed.kext: code signature does not verify" >&2
        fi
    done
    if [[ -n "$KEXT_SOURCE_LOCAL" ]]; then
        echo "  ⚠ Source: LOCAL BUILD (SMCAMDProcessor_Source/build/dmg-kexts/) — content pins NOT enforced."
        echo "    These binaries are unverified. Do not publish this DMG until the"
        echo "    hardware probes pass; see .kiro/steering/hardware-safety.md."
        if [[ -z "$KEXT_CONTENT_OK" ]]; then
            echo "    Content differs from the pinned release binaries (hashes above) — expected for a new kext revision."
        else
            echo "    Content matches the pinned release binaries."
        fi
    elif [[ -z "$KEXT_CONTENT_OK" ]]; then
        echo "✗ Error: staged kext content does not match the pinned release binaries." >&2
        echo "  The ReleaseAssets zip extracted successfully but its contents are not" >&2
        echo "  the reviewed ones. Refusing to build a DMG from unrecognised binaries." >&2
        echo "  If this is an intentional kext update, refresh the four KEXT_PIN_* values" >&2
        echo "  in Tools/make-dmg.sh in the same commit as the new zip." >&2
        exit 1
    else
        echo "    Source: ReleaseAssets zip, content pins + code signature verified."
    fi
    echo "  ✓ SMCAMDProcessor.kext added to DMG"
    # Assert what actually landed, instead of trusting the echoes above.
    #
    # The two `ditto` calls are covered by `set -e`, but nothing verified that the
    # staged bundles are intact — and every packaging bug found so far took the
    # shape of a success message that was not tied to the work it described.
    for staged in AMDRyzenCPUPowerManagement SMCAMDProcessor; do
        if [[ ! -f "$STAGING/Kexts/$staged.kext/Contents/Info.plist" ]]; then
            echo "✗ Error: $staged.kext was reported as added but is not present in the staged DMG" >&2
            exit 1
        fi
    done
else
    # A DMG with no kexts is a BROKEN artifact, not a warning.
    #
    # This branch used to `echo … >&2` and continue, so the script exited 0 and CI
    # stayed green while publishing a DMG whose Kexts/ folder did not exist. That
    # is exactly what happened between kext 3.34.13 and 3.34.14: the pinned zip had
    # been refreshed with only AMDRyzenCPUPowerManagement.kext, so the extracted
    # $KEXT_PLUGIN path never existed, this branch was taken on every clean clone,
    # and the release workflow would have shipped the first kext-less DMG.
    #
    # Failing loudly here is the mechanism fix; refreshing the zip was only the
    # symptom fix. Set ALLOW_NO_KEXTS=1 for the rare deliberate app-only image.
    if [[ -n "${ALLOW_NO_KEXTS:-}" ]]; then
        echo "  ⚠ No kexts staged — continuing because ALLOW_NO_KEXTS is set." >&2
        echo "    This DMG installs the app only; users must supply their own kexts." >&2
    else
        echo "✗ Error: no kexts available, so the DMG would ship without them." >&2
        echo "  Checked, and at least one is missing:" >&2
        echo "    local driver : SMCAMDProcessor_Source/build/dmg-kexts/AMDRyzenCPUPowerManagement.kext" >&2
        echo "    local plugin : SMCAMDProcessor_Source/build/dmg-kexts/SMCAMDProcessor.kext" >&2
        echo "    zip fallback : ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip" >&2
        echo "  Most likely cause: the zip is present but does not contain BOTH kexts" >&2
        echo "  at its archive root. Verify with:" >&2
        echo "    unzip -l ReleaseAssets/AMDRyzenCPUPowerManagement-Kexts.zip | grep '\.kext/$'" >&2
        echo "  To build an app-only image on purpose: ALLOW_NO_KEXTS=1 ./Tools/make-dmg.sh" >&2
        exit 1
    fi
fi
mkdir "$STAGING/.background"
cp build/dmg-background.png "$STAGING/.background/background.png"
# Seed the window layout from a checked-in .DS_Store.
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
