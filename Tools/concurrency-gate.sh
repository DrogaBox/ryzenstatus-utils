#!/bin/zsh
# Concurrency ratchet: fails if any strict-concurrency diagnostic originates
# from the AMD layer. Non-AMD diagnostics are tolerated (pre-existing debt;
# see HANDOFF_F27-F30.md for the full-project picture).
set -uo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --sdk macosx --show-sdk-path)"
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT
swiftc -typecheck -O -num-threads 8 -target x86_64-apple-macosx14.0 -sdk "$SDK" \
  -strict-concurrency=complete Sources/RyzenStatus/**/*.swift > /dev/null 2> "$OUT"
PATTERN='Sources/RyzenStatus/(Services/AMD/|UI/MenuPanel/AmdControlSection|UI/Settings/AmdPower)'
HITS=$(grep -E "$PATTERN" "$OUT" | grep -cE "(error|warning):" || true)
echo "AMD-layer strict-concurrency diagnostics: $HITS"
if (( HITS != 0 )); then
  grep -E "$PATTERN" "$OUT" | grep -E "(error|warning):"
  exit 1
fi
