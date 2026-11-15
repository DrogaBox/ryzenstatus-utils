#!/bin/zsh
# Builds AMDCCDScheduler.cpp in user space against stand-in kernel objects and runs the hook tests,
# once under AddressSanitizer + UndefinedBehaviorSanitizer and once under ThreadSanitizer.
set -euo pipefail
cd "$(dirname "$0")"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
clang++ -std=c++17 -O1 -g -fsanitize=address,undefined -Istub hook_test.cpp -o "$OUT/asan"
"$OUT/asan"
clang++ -std=c++17 -O1 -g -fsanitize=thread -Istub hook_test.cpp -o "$OUT/tsan"
TSAN_OPTIONS=halt_on_error=1 "$OUT/tsan" | tail -1
