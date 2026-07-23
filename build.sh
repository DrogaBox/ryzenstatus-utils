#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RyzenStatus

# Builds RyzenStatus, assembles the .app bundle, signs it and (with --install)
# installs it into /Applications.
#
# The bundle is staged in a temporary directory outside ~/Documents: folders synced
# by File Provider gain xattrs (com.apple.provenance etc.) that invalidate codesign.
set -euo pipefail
cd "$(dirname "$0")"

# Flags: --dev builds the local-only "RyzenStatus (Developer)" variant (its own
# bundle id, so it coexists with the official app); --install puts it in /Applications.
DEV=0
INSTALL=0
TEST=0
for arg in "$@"; do
    case "$arg" in
        --dev)     DEV=1 ;;
        --install) INSTALL=1 ;;
        --test)    TEST=1 ;;
    esac
done

if (( DEV )); then
    APP_NAME="RyzenStatus (Developer)"
    EXECUTABLE="RyzenStatusDeveloper"
else
    APP_NAME="RyzenStatus"
    EXECUTABLE="RyzenStatus"
fi
TARGET="x86_64-apple-macosx14.0"
ENTITLEMENTS="Resources/RyzenStatus.entitlements"
LEGACY_IDENTITY="RyzenStatus Utils Signing"

developer_id_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | grep 'Developer ID Application' \
        | head -1 \
        | sed -E 's/.*"(.*)".*/\1/' || true
}

finalize_installed_bundle_after_child() {
    local bundle="$1"
    local devid
    devid="$(developer_id_identity)"

    echo "▸ Finalizing installed signature…"
    sleep 3
    if [[ -n "$devid" ]]; then
        /usr/bin/codesign --force --strip-disallowed-xattrs --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS" --sign "$devid" "$bundle"
    elif security find-identity -p codesigning 2>/dev/null | grep -q "$LEGACY_IDENTITY"; then
        /usr/bin/codesign --force --strip-disallowed-xattrs --sign "$LEGACY_IDENTITY" "$bundle"
    else
        /usr/bin/codesign --force --strip-disallowed-xattrs --sign - "$bundle"
    fi
    /usr/bin/codesign --verify --deep --strict "$bundle"
    echo "✓ Signature ready: $bundle"
}

if (( INSTALL && ! TEST )) && [[ "${RYZENSTATUS_INSTALL_CHILD:-0}" != "1" ]]; then
    RYZENSTATUS_INSTALL_CHILD=1 "$0" "$@"
    child_status=$?
    if (( child_status != 0 )); then
        exit "$child_status"
    fi
    finalize_installed_bundle_after_child "/Applications/$APP_NAME.app"
    exit 0
fi

# Prefer the macOS 26 SDK when present: the 27 SDK turns SwiftUI property wrappers
# into macros (SwiftUIMacros plugin) that the Command Line Tools cannot load yet.
PINNED_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
if [[ -d "$PINNED_SDK" ]]; then
    SDK="$PINNED_SDK"
else
    SDK="$(xcrun --show-sdk-path)"
fi

# --test: compile and run the standalone unit tests (pure helpers only: metrics,
# Homebrew parsing, defaults, localization contracts; no app, no UI, no IOKit),
# then exit. Fast and deterministic; no XCTest needed.
if (( TEST )); then
    echo "▸ Building & running unit tests against $(basename "$SDK")…"
    rm -rf build
    mkdir -p build
    swiftc -O -target "$TARGET" -sdk "$SDK" \
        Sources/RyzenStatus/Services/Media/MediaSupport.swift \
        Sources/RyzenStatus/Core/Defaults.swift \
        Sources/RyzenStatus/Core/FeatureCatalog.swift \
        Sources/RyzenStatus/Core/FeaturePresets.swift \
        Sources/RyzenStatus/Core/FeatureHubStrings.swift \
        Sources/RyzenStatus/Core/SettingsBackupSupport.swift \
        Sources/RyzenStatus/Core/BackupStrings.swift \
        Sources/RyzenStatus/Core/SnippetStrings.swift \
        Sources/RyzenStatus/Core/BrightnessStrings.swift \
        Sources/RyzenStatus/Core/QuickToggleStrings.swift \
        Sources/RyzenStatus/Core/ScreenshotStrings.swift \
        Sources/RyzenStatus/Core/CameraPreviewStrings.swift \
        Sources/RyzenStatus/Core/ScratchpadStrings.swift \
        Sources/RyzenStatus/Core/RadialMenuStrings.swift \
        Sources/RyzenStatus/Core/MenuBarAppearanceStrings.swift \
        Sources/RyzenStatus/Core/BatteryTimeStrings.swift \
        Sources/RyzenStatus/Core/KeepAwakeStrings.swift \
        Sources/RyzenStatus/Core/PermissionGuideStrings.swift \
        Sources/RyzenStatus/Services/Snippets/TextSnippetSupport.swift \
        Sources/RyzenStatus/Services/RadialMenu/RadialMenuSupport.swift \
        Sources/RyzenStatus/Services/QuickTools/ScratchpadSupport.swift \
        Sources/RyzenStatus/Core/AppInfo.swift \
        Sources/RyzenStatus/Core/GlobalShortcut.swift \
        Sources/RyzenStatus/Core/Localization.swift \
        Sources/RyzenStatus/Core/Localizations/Strings+*.swift \
        Sources/RyzenStatus/Core/FeatureStrings.swift \
        Sources/RyzenStatus/Core/ReleaseNotes.swift \
        Sources/RyzenStatus/Core/URLCleaning.swift \
        Sources/RyzenStatus/Services/GeneralPasteboardAccess.swift \
        Sources/RyzenStatus/Services/Audio/MixerRoutingSupport.swift \
        Sources/RyzenStatus/Services/DockPreview/DockPreviewSupport.swift \
        Sources/RyzenStatus/Services/Homebrew/HomebrewSupport.swift \
        Sources/RyzenStatus/Services/Clipboard/ClipboardHistorySupport.swift \
        Sources/RyzenStatus/Services/AutoQuit/AutoQuitSupport.swift \
        Sources/RyzenStatus/Services/Shelf/ShelfSupport.swift \
        Sources/RyzenStatus/Services/Update/UpdateInstallerSupport.swift \
        Sources/RyzenStatus/Services/LaunchAtLoginSupport.swift \
        Sources/RyzenStatus/UI/Settings/SettingsSearchSupport.swift \
        Sources/RyzenStatus/UI/Settings/FeatureVisibilitySupport.swift \
        Sources/RyzenStatus/App/MenuBarSpacingSupport.swift \
        Sources/RyzenStatus/App/StatusItemAnchorSupport.swift \
        Sources/RyzenStatus/Services/DockClick/DockClickSupport.swift \
        Sources/RyzenStatus/Services/Finder/CutPasteProgressSupport.swift \
        Sources/RyzenStatus/Services/MiddleClick/MiddleClickSupport.swift \
        Sources/RyzenStatus/Services/MouseNavigation/MouseNavigationSupport.swift \
        Sources/RyzenStatus/Services/QuickTools/QuickToolsSupport.swift \
        Sources/RyzenStatus/Services/QuickTools/QuickTogglesSupport.swift \
        Sources/RyzenStatus/Services/QuickTools/ScreenshotSupport.swift \
        Sources/RyzenStatus/Services/KeyboardDebounce/KeyboardDebounceSupport.swift \
        Sources/RyzenStatus/Services/ScrollWheelSupport.swift \
        Sources/RyzenStatus/Services/SmoothScrollSupport.swift \
        Sources/RyzenStatus/Services/Switcher/SwitcherModels.swift \
        Sources/RyzenStatus/Services/Switcher/SwitcherSupport.swift \
        Sources/RyzenStatus/Services/Metrics/MetricFormat.swift \
        Sources/RyzenStatus/Services/KeepAwakeAutomationSupport.swift \
        Sources/RyzenStatus/Services/SudoersSupport.swift \
        Sources/RyzenStatus/Services/Metrics/BatteryTimeSupport.swift \
        Sources/RyzenStatus/Services/Metrics/NetworkProcessSupport.swift \
        Sources/RyzenStatus/Services/Metrics/PeripheralBatterySupport.swift \
        Sources/RyzenStatus/Services/Metrics/DiskSupport.swift \
        Sources/RyzenStatus/Services/Metrics/MonitorSamplingPolicy.swift \
        Sources/RyzenStatus/Services/Metrics/MaxCapacityProbe.swift \
        Sources/RyzenStatus/Services/Metrics/TemperatureSensorSelector.swift \
        Sources/RyzenStatus/Services/WindowLayout/WindowLayoutSupport.swift \
        Sources/RyzenStatus/Services/WindowLayout/WindowGestureSupport.swift \
        Sources/RyzenStatus/Services/CleaningMode/CleaningUnlockCounter.swift \
        Sources/RyzenStatus/Services/Display/ExtraBrightnessSupport.swift \
        Sources/RyzenStatus/Services/Display/BrightnessSupport.swift \
        Sources/RyzenStatus/Services/Cleaner/CleanerSupport.swift \
        Sources/RyzenStatus/Services/Cleaner/CleanerPolicy.swift \
        Sources/RyzenStatus/Services/Cleaner/CleanerSchedule.swift \
        Tests/MetricsTests.swift \
        -o build/metrics-tests
    ./build/metrics-tests
    exit $?
fi

if [[ ! -f "build/$EXECUTABLE" ]]; then
    echo "▸ Compiling (release) against $(basename "$SDK")…"
    mkdir -p build
    swiftc -O -num-threads 16 -target "$TARGET" -sdk "$SDK" \
        Sources/RyzenStatus/**/*.swift \
        -o "build/$EXECUTABLE"
fi

echo "▸ Generating app icon…"
swift Tools/MakeIcon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset
xattr -c -r build/AppIcon.iconset build/AppIcon.icns build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png 2>/dev/null || true

echo "▸ Assembling and signing bundle…"
STAGE="$(mktemp -d)/$APP_NAME.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "build/$EXECUTABLE" "$STAGE/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
cp CHANGELOG.md "$STAGE/Contents/Resources/CHANGELOG.md"
for lproj in Resources/*.lproj(N); do
    cp -R "$lproj" "$STAGE/Contents/Resources/"
done
if (( DEV )); then
    # A distinct identity so the Developer build installs and runs next to the
    # official app, with its own permissions, preferences and login item.
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.ryzenstatus.utils.dev" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName RyzenStatus (Developer)" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName RyzenStatus (Developer)" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXECUTABLE" "$STAGE/Contents/Info.plist"
    # Stamp the source commit + build time so the running dev app shows (in About)
    # exactly which code it was compiled from. Lets you verify it matches HEAD before
    # testing, instead of unknowingly running a stale build. Dev-only; never shipped.
    SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    [[ -n "$(git status --porcelain 2>/dev/null)" ]] && SHA="$SHA-dirty"
    /usr/libexec/PlistBuddy -c "Add :RyzenStatusBuildCommit string '$SHA · $(date '+%Y-%m-%d %H:%M')'" "$STAGE/Contents/Info.plist"
    echo "  stamped dev build: $SHA"
fi
printf 'APPL????' > "$STAGE/Contents/PkgInfo"
cp build/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
cp build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png "$STAGE/Contents/Resources/"
if [[ -f Resources/Gifs/dockPreview.gif ]]; then
    mkdir -p "$STAGE/Contents/Resources/Gifs"
    cp Resources/Gifs/dockPreview.gif "$STAGE/Contents/Resources/Gifs/"
fi
if [[ -d Resources/Images ]]; then
    mkdir -p "$STAGE/Contents/Resources/Images"
    cp Resources/Images/* "$STAGE/Contents/Resources/Images/"
fi
xattr -c -r "$STAGE" 2>/dev/null || true

# Signing, in order of preference:
#   1. Developer ID Application — the real, Apple-issued identity used for
#      notarized releases. Signed with the hardened runtime (required for
#      notarization), the app's entitlements and a secure timestamp. Gives a
#      stable, team-based designated requirement, so permissions persist across
#      updates AND Gatekeeper shows no "unverified developer" warning.
#   2. "RyzenStatus Utils Signing" — the legacy stable self-signed identity, kept
#      as a fallback so contributors without a Developer ID still get a constant
#      designated requirement across their local builds.
#   3. Ad-hoc — fresh clone with no identity at all.
DEVID="$(developer_id_identity)"
codesign_target() {
    local target="$1"
    if [[ -n "$DEVID" ]]; then
        codesign --force --strip-disallowed-xattrs --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS" --sign "$DEVID" "$target"
    elif security find-identity -p codesigning 2>/dev/null | grep -q "$LEGACY_IDENTITY"; then
        codesign --force --strip-disallowed-xattrs --sign "$LEGACY_IDENTITY" "$target"
    else
        codesign --force --strip-disallowed-xattrs --sign - "$target"
    fi
}

sign_bundle() {
    local bundle="$1"
    local executable="$bundle/Contents/MacOS/$EXECUTABLE"

    if [[ -n "$DEVID" ]]; then
        echo "  signing with Developer ID (hardened runtime): $DEVID"
    elif security find-identity -p codesigning 2>/dev/null | grep -q "$LEGACY_IDENTITY"; then
        echo "  signing with legacy self-signed identity: $LEGACY_IDENTITY"
    else
        echo "  signing ad-hoc (no identity installed — run Tools/setup-signing.sh)"
    fi
    codesign_target "$bundle"

    # If local filesystem metadata invalidates the first signature, sign once
    # more. The installed Developer bundle is signed again after the final copy.
    if ! codesign --verify --deep --strict "$bundle" >/dev/null 2>&1; then
        echo "  re-signing after filesystem metadata settled"
        xattr -c -r "$bundle" 2>/dev/null || true
        codesign_target "$bundle"
    fi
    [[ -f "$executable" ]] && codesign --verify --strict "$executable"
    codesign --verify --deep --strict "$bundle"
}

sign_installed_bundle() {
    local bundle="$1"
    wait_for_install_metadata "$bundle"
    sign_bundle "$bundle"
}

sign_bundle "$STAGE"

process_is_running() {
    local proc="$1"
    if (( ${#proc} > 15 )); then
        pgrep -f "/Contents/MacOS/$proc" >/dev/null 2>&1
    else
        pgrep -x "$proc" >/dev/null 2>&1
    fi
}

stop_process() {
    local proc="$1"
    if (( ${#proc} > 15 )); then
        pkill -f "/Contents/MacOS/$proc" 2>/dev/null || true
    else
        pkill -x "$proc" 2>/dev/null || true
    fi
    for _ in {1..50}; do
        if ! process_is_running "$proc"; then
            return 0
        fi
        sleep 0.1
    done
    echo "✗ $proc is still running — quit it and retry" >&2
    return 1
}

wait_for_install_metadata() {
    local bundle="$1"
    local missing
    for _ in {1..50}; do
        missing=0
        while IFS= read -r file; do
            if ! xattr -p com.apple.provenance "$file" >/dev/null 2>&1; then
                missing=1
                break
            fi
        done < <(find "$bundle/Contents" -type f ! -path "*/_CodeSignature/*")
        if (( missing == 0 )); then
            return 0
        fi
        sleep 0.1
    done
}

mkdir -p "build/stage"
BUILD_STAGE="build/stage/$APP_NAME.app"
rm -rf "$BUILD_STAGE"
ditto --noextattr --noqtn "$STAGE" "$BUILD_STAGE"
xattr -c -r "$BUILD_STAGE" 2>/dev/null || true
if ! codesign --verify --deep --strict "$BUILD_STAGE" >/dev/null 2>&1; then
    if xattr -lr "$BUILD_STAGE" 2>/dev/null | grep -Eq 'com\.apple\.(FinderInfo|ResourceFork|provenance|fileprovider)'; then
        echo "  build/stage copy has local filesystem metadata; temp bundle was verified"
    else
        codesign --verify --deep --strict "$BUILD_STAGE"
    fi
fi
echo "✓ Bundle ready: $BUILD_STAGE"

if (( INSTALL )); then
    echo "▸ Installing into /Applications…"
    stop_process "$EXECUTABLE"
    # Remove the pre-rename apps so two menu bar items never coexist. Same bundle
    # id, so macOS keeps the granted permissions for the new bundle.
    for legacy in "RyzenStatus:RyzenStatus" "RyzenStatus Utils:RyzenStatusUtils"; do
        name="${legacy%%:*}"; proc="${legacy##*:}"
        if [[ -d "/Applications/$name.app" ]]; then
            stop_process "$proc"
            rm -rf "/Applications/$name.app"
            echo "  (legacy $name.app removed)"
        fi
    done
    INSTALL_DEST="/Applications/$APP_NAME.app"
    rm -rf "$INSTALL_DEST"
    ditto --noextattr --noqtn "$STAGE" "$INSTALL_DEST"
    sign_installed_bundle "$INSTALL_DEST"
    echo "✓ Installed: $INSTALL_DEST"
fi
