#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RyzenStatus

# Builds and runs the command bar's pure-logic tests.
#
# `./build.sh --test` compiles a pinned list of sources and that list is frozen,
# so the command bar's modules cannot join it. This runner pins the bar's pure
# modules next to the local files they depend on and runs the same kind of flat
# harness: no app, no UI, no IOKit, no XCTest. `./build.sh --test` keeps
# covering everything it covered before; run both.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v swiftc >/dev/null 2>&1; then
    echo "Error: swiftc is not installed or not in PATH."
    exit 1
fi

# Same pins as build.sh: the macOS 26 SDK when present, since the 27 SDK turns
# SwiftUI property wrappers into macros the Command Line Tools cannot load.
PINNED_SDK=$(xcrun --sdk macosx --show-sdk-path)
if [[ -d "$PINNED_SDK" ]]; then
    SDK="$PINNED_SDK"
else
    SDK="$(xcrun --show-sdk-path)"
fi
TARGET="x86_64-apple-macosx14.0"

echo "▸ Building & running command bar tests against $(basename "$SDK")…"
mkdir -p build
rm -f build/commandbar-tests

# `enum DefaultsKey {}` is declared at the top of Core/Defaults.swift, a file that
# also registers the default value of every preference in the app and therefore
# drags the whole app into this harness. The type is empty in the real tree too:
# `DefaultsKey+App.swift` and `DefaultsKey+Monitor.swift` are what add the keys.
# So the runner states the same empty namespace in its own build directory, and
# nothing in the repository duplicates it.
cat > build/CommandBarDefaultsKeyNamespace.swift <<'SWIFT'
enum DefaultsKey {}
SWIFT

swiftc -O -num-threads 8 -target "$TARGET" -sdk "$SDK" \
    Sources/RyzenStatus/Core/Localization.swift \
    Sources/RyzenStatus/Core/Localizations/Strings+*.swift \
    Sources/RyzenStatus/Core/FeatureStrings.swift \
    Sources/RyzenStatus/Core/CommandBarStrings.swift \
    Sources/RyzenStatus/Core/DefaultsKey+App.swift \
    Sources/RyzenStatus/Core/DefaultsKey+Monitor.swift \
    Sources/RyzenStatus/Core/GlobalShortcut.swift \
    Sources/RyzenStatus/Core/SymbolicHotKeys.swift \
    Sources/RyzenStatus/Services/Switcher/SpaceHopSupport.swift \
    Sources/RyzenStatus/Core/RecentCaptureStrings.swift \
    Sources/RyzenStatus/Core/FeatureCatalog.swift \
    Sources/RyzenStatus/Core/FeatureHubStrings.swift \
    Sources/RyzenStatus/Core/BrightnessStrings.swift \
    Sources/RyzenStatus/Core/QuickToggleStrings.swift \
    Sources/RyzenStatus/Core/KillProcessStrings.swift \
    Sources/RyzenStatus/Core/BluetoothSleepStrings.swift \
    Sources/RyzenStatus/Core/ConnectedDevicesStrings.swift \
    Sources/RyzenStatus/Core/DiskImageInstallerStrings.swift \
    Sources/RyzenStatus/Core/PortManagerStrings.swift \
    Sources/RyzenStatus/Core/QuitProtectionStrings.swift \
    Sources/RyzenStatus/Core/WallpaperStrings.swift \
    Sources/RyzenStatus/Core/DefaultsKey+DesktopTools.swift \
    Sources/RyzenStatus/Core/QuitProtectionSupport.swift \
    Sources/RyzenStatus/Core/FinderRenameStrings.swift \
    Sources/RyzenStatus/Core/MouseClickDebounceStrings.swift \
    Sources/RyzenStatus/Core/AppUpdateStrings.swift \
    Sources/RyzenStatus/Core/WhatsAppDownloadStrings.swift \
    Sources/RyzenStatus/Core/NotchStrings.swift \
    Sources/RyzenStatus/Core/NotchCalendarStrings.swift \
    Sources/RyzenStatus/Core/ScreenshotStrings.swift \
    Sources/RyzenStatus/Core/RecorderStrings.swift \
    Sources/RyzenStatus/Core/CameraPreviewStrings.swift \
    Sources/RyzenStatus/Core/RadialMenuStrings.swift \
    Sources/RyzenStatus/Core/SnippetStrings.swift \
    Sources/RyzenStatus/Core/ScratchpadStrings.swift \
    Sources/RyzenStatus/Core/NowPlayingStrings.swift \
    Sources/RyzenStatus/Core/URLCleaning.swift \
    Sources/RyzenStatus/Services/RadialMenu/RadialMenuSupport.swift \
    Sources/RyzenStatus/Services/QuickTools/ScratchpadSupport.swift \
    Sources/RyzenStatus/Services/CommandBar/CommandBarSupport.swift \
    Sources/RyzenStatus/Services/CommandBar/CommandBarUnits.swift \
    Sources/RyzenStatus/Services/CommandBar/CommandBarDates.swift \
    Sources/RyzenStatus/Services/CommandBar/CommandBarMath.swift \
    Sources/RyzenStatus/Services/CommandBar/CommandBarEmoji.swift \
    Sources/RyzenStatus/Services/CommandBar/CommandBarQueryMemory.swift \
    Sources/RyzenStatus/Services/CommandBar/CommandBarPreferences.swift \
    Sources/RyzenStatus/Services/CommandBar/CommandBarRowShortcuts.swift \
    build/CommandBarDefaultsKeyNamespace.swift \
    Tests/CommandBarTests.swift \
    Tests/CommandBar*Cases.swift \
    -o build/commandbar-tests
./build/commandbar-tests
exit $?
