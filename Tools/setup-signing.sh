#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RyzenStatus

# Creates a stable, self-signed code-signing identity named "RyzenStatus Utils
# Signing" in a dedicated keychain. build.sh uses it automatically, giving every
# build the same code signature — so macOS keeps granted permissions
# (Accessibility, Screen Recording) across updates instead of re-prompting.
#
# This identity name keeps its original "RyzenStatus Utils Signing" on purpose: it
# is the lookup key build.sh matches, and the released app's designated
# requirement is pinned to this exact certificate. Renaming it would change that
# requirement and drop every user's granted permissions. The name lives only in
# the keychain and codesign output, never in anything the app shows.
#
# Free, offline, and idempotent (re-running is a no-op once the identity exists).
# It does NOT replace Apple notarization: downloaded builds still show Gatekeeper's
# "unverified developer" prompt on first launch. It only stabilizes the identity.
#
# Maintainers: the official releases are signed by CI with a shared certificate
# (repo secrets SIGNING_CERT_P12 / SIGNING_CERT_PASSWORD). Run this only to get
# the same permission-preserving behavior for your own local builds.
set -euo pipefail

IDENTITY="RyzenStatus Utils Signing"
KC="$HOME/Library/Keychains/ryzenstatus-signing.keychain-db"
KCPASS="ryzenstatus-signing"

if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "✓ Signing identity already installed."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

openssl req -x509 -newkey rsa:2048 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -days 3650 -nodes \
    -subj "/CN=$IDENTITY/O=RyzenStatus" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/id.p12" -passout pass:"$KCPASS" -name "$IDENTITY" 2>/dev/null

security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p "$KCPASS" "$KC"
security set-keychain-settings "$KC"            # no auto-lock
security unlock-keychain -p "$KCPASS" "$KC"
security import "$WORK/id.p12" -k "$KC" -P "$KCPASS" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPASS" "$KC" >/dev/null 2>&1
EXISTING=$(security list-keychains -d user | sed 's/"//g' | xargs)
security list-keychains -d user -s "$KC" ${=EXISTING}

echo "✓ Created signing identity '$IDENTITY'. Future ./build.sh runs use it automatically."
