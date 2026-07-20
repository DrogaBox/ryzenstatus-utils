#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RyzenStatus

# Cleanly removes RyzenStatus and every piece of system state it created:
# the login item, TCC permissions, preferences, saved state and (if present)
# the password-free closed-lid sudoers rule. Leaves no dead entries behind.
# Also clears the pre-rename "RyzenStatus Utils.app" if it is still around.
set -uo pipefail

BUNDLE="com.ryzenstatus.utils"
APP="/Applications/RyzenStatus.app"
LEGACY_APP="/Applications/RyzenStatus Utils.app"

echo "▸ Quitting…"
pkill -x RyzenStatus 2>/dev/null || true
pkill -x RyzenStatusUtils 2>/dev/null || true
sleep 0.5

# Detach from the system from inside whichever bundle still exists: unregisters
# the login item (no BTM tombstone) and restores normal sleep.
for candidate in "$APP/Contents/MacOS/RyzenStatus" "$LEGACY_APP/Contents/MacOS/RyzenStatusUtils"; do
    if [[ -x "$candidate" ]]; then
        echo "▸ Detaching login item and restoring sleep…"
        "$candidate" --uninstall || true
        break
    fi
done

echo "▸ Resetting permissions (Accessibility, Screen Recording)…"
tccutil reset All "$BUNDLE" >/dev/null 2>&1 || true

echo "▸ Removing app, preferences and saved state…"
rm -rf "$APP" "$LEGACY_APP"
defaults delete "$BUNDLE" >/dev/null 2>&1 || true
rm -f "$HOME/Library/Preferences/$BUNDLE.plist"
rm -rf "$HOME/Library/Saved Application State/$BUNDLE.savedState"

RULES="/etc/sudoers.d/ryzenstatus-clamshell /etc/sudoers.d/ryzenstatus-utils-clamshell /etc/sudoers.d/ryzenstatus-clamshell"
if ls $RULES >/dev/null 2>&1; then
    echo "▸ Removing closed-lid sudoers rule (asks for your admin password)…"
    osascript -e "do shell script \"rm -f $RULES\" with administrator privileges with prompt \"RyzenStatus uninstaller\"" || true
fi

echo "✓ RyzenStatus fully removed."
