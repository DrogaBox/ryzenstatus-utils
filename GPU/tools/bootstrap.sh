#!/bin/zsh
# Fetches what the build and the tests need, into deps/ (not committed):
#
#   deps/Lilu.kext         the DEBUG build of Lilu: its Resources folder holds the plugin
#                          headers and plugin_start.cpp. Only used to compile; the Lilu you
#                          boot with is the one already on your EFI.
#   deps/MacKernelSDK      kernel headers and libkmod.a, from acidanthera.
#   deps/OpenCore/Sample.plist
#                          OpenCore's sample config. The tests of the tool that edits
#                          config.plist run on copies of it.
#
# All three are pinned, so everyone compiles and tests against the same files:
#   Lilu 1.7.2 DEBUG and the OpenCore sample are checked by SHA-256 after the download,
#   MacKernelSDK is fetched at the commit below.
#
# Usage: tools/bootstrap.sh
# To use copies you already have, skip this script and export LILU_KEXT, MACKERNELSDK and
# OC_SAMPLE before running build.sh (see docs/building.md).
set -e
ROOT="${0:A:h:h}"
DEPS="$ROOT/deps"
LILU_VERSION=1.7.2
LILU_URL="https://github.com/acidanthera/Lilu/releases/download/$LILU_VERSION/Lilu-$LILU_VERSION-DEBUG.zip"
LILU_SHA256=e95df95d82e8b151047abf359ecd9c853755c59293e19dfcc3907da8fbd8cf89
MKSDK_URL="https://github.com/acidanthera/MacKernelSDK"
MKSDK_COMMIT=05094e5e88cec7caedbfb35e8449ed0db94bf95b
OC_VERSION=1.0.8
OC_SAMPLE_URL="https://raw.githubusercontent.com/acidanthera/OpenCorePkg/$OC_VERSION/Docs/Sample.plist"
OC_SAMPLE_SHA256=a58ca93ee0e2ac199469b696606ba96bfaafb0a7902e57de6d557548a0c96a58

mkdir -p "$DEPS"

check_sha() {  # check_sha <file> <expected> <what>
  local got=$(shasum -a 256 "$1" | awk '{print $1}')
  if [[ $got != $2 ]]; then
    print -u2 "$3 does not match the pinned SHA-256."
    print -u2 "  expected $2"
    print -u2 "  got      $got"
    rm -f "$1"
    exit 1
  fi
}

if [[ -f $DEPS/Lilu.kext/Contents/Resources/Library/plugin_start.cpp ]]; then
  print "Lilu: already in deps/"
else
  print "Lilu: downloading $LILU_VERSION DEBUG..."
  zip="$DEPS/Lilu-$LILU_VERSION-DEBUG.zip"
  curl -fsSL -o "$zip" "$LILU_URL"
  check_sha "$zip" $LILU_SHA256 "The Lilu download"
  tmp="$DEPS/.lilu-unzip"
  rm -rf "$tmp" && mkdir -p "$tmp"
  unzip -q "$zip" -d "$tmp"
  rm -rf "$DEPS/Lilu.kext"
  mv "$tmp/Lilu.kext" "$DEPS/Lilu.kext"
  rm -rf "$tmp" "$zip"
  [[ -f $DEPS/Lilu.kext/Contents/Resources/Library/plugin_start.cpp ]] || { print -u2 "the Lilu archive has no plugin SDK inside"; exit 1; }
  print "Lilu: ok"
fi

if [[ -f $DEPS/MacKernelSDK/Library/x86_64/libkmod.a ]]; then
  print "MacKernelSDK: already in deps/"
else
  print "MacKernelSDK: fetching commit ${MKSDK_COMMIT[1,7]}..."
  rm -rf "$DEPS/MacKernelSDK"
  git init -q "$DEPS/MacKernelSDK"
  git -C "$DEPS/MacKernelSDK" remote add origin "$MKSDK_URL"
  git -C "$DEPS/MacKernelSDK" fetch -q --depth 1 origin "$MKSDK_COMMIT"
  git -C "$DEPS/MacKernelSDK" checkout -q FETCH_HEAD
  [[ -f $DEPS/MacKernelSDK/Library/x86_64/libkmod.a ]] || { print -u2 "MacKernelSDK has no Library/x86_64/libkmod.a"; exit 1; }
  print "MacKernelSDK: ok"
fi

if [[ -f $DEPS/OpenCore/Sample.plist ]]; then
  print "OpenCore sample config: already in deps/"
else
  print "OpenCore sample config: downloading from $OC_VERSION..."
  mkdir -p "$DEPS/OpenCore"
  curl -fsSL -o "$DEPS/OpenCore/Sample.plist" "$OC_SAMPLE_URL"
  check_sha "$DEPS/OpenCore/Sample.plist" $OC_SAMPLE_SHA256 "The OpenCore sample config"
  print "OpenCore sample config: ok"
fi

print "Dependencies are in $DEPS"
