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

# Pure contracts do not require whole-program optimization. Production build
# still uses -O; all assertions and inputs stay identical in this runner.
# The whole module (minus the app entry point), so the harness cannot drift
# when a helper gains a dependency.
swiftc -Onone -num-threads 4 -target "$TARGET" -sdk "$SDK" \
    $(find Sources/RyzenStatus -name '*.swift' ! -name main.swift | sort) \
    Tests/CommandBarTests.swift \
    Tests/CommandBar*Cases.swift \
     -o build/commandbar-tests
./build/commandbar-tests
exit $?
