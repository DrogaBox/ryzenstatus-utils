#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RyzenStatus

# Imports the stable signing certificate into a keychain on CI so build.sh signs
# releases with the same identity used locally. This keeps the bundle's
# designated requirement constant, so users keep their granted permissions
# across updates. No-op (and ad-hoc build) when the secret isn't configured.
set -euo pipefail

if [[ -z "${SIGNING_CERT_P12:-}" ]]; then
    echo "No SIGNING_CERT_P12 secret — building ad-hoc."
    exit 0
fi

TMP="${RUNNER_TEMP:-/tmp}"
KCPASS="ci-signing"
KC="$TMP/ryzenstatus-signing.keychain-db"
P12="$TMP/ryzenstatus-signing.p12"

echo "$SIGNING_CERT_P12" | base64 --decode > "$P12"
security create-keychain -p "$KCPASS" "$KC"
security set-keychain-settings "$KC"
security unlock-keychain -p "$KCPASS" "$KC"
security import "$P12" -k "$KC" -P "${SIGNING_CERT_PASSWORD:-}" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPASS" "$KC" >/dev/null 2>&1
EXISTING=$(security list-keychains -d user | sed 's/"//g' | xargs)
security list-keychains -d user -s "$KC" ${=EXISTING}
rm -f "$P12"
echo "Signing certificate imported."
