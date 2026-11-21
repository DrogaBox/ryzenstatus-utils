#!/usr/bin/env python3
"""amficheck.py - reads, from a macOS boot kernel collection, the two AMFI functions
VCNVTLoader works with, and prints their first bytes.

    python3 tools/driver/amficheck.py <label>=<BootKernelExtensions.kc> ...
    python3 tools/driver/amficheck.py              (this Mac's own collection)

Output, one line per function: "<hex of the first 32 bytes> <failure|cdhash> <label>".
Feed it to the test to check that the kext would accept those functions:

    python3 tools/driver/amficheck.py 15.8.2_24H232=/path/BootKernelExtensions.kc > /tmp/e.txt
    decode/build/tests/loadertest /tmp/e.txt

It only reads the file. The collection is Apple's: do not commit it or the output of a
disassembler on it. The 32 bytes it prints are function prologues, used as test input.
The collection is read by kcfunc.py.

Exit status: 0 both functions found in every collection, 1 otherwise.
"""
import os
import struct
import sys

# kcfunc.py sits next to this file; with python3 -I the script's folder is not searched.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kcfunc  # noqa: E402

AMFI = "com.apple.driver.AppleMobileFileIntegrity"
SYMBOLS = {
    "__ZL27_library_validation_failureR15ProcessAccessorR16FileGlobAccessorR11"
    "SystemFactsbPKcym": "failure",
    "__ZN22AbstractCSBlobAccessor6cdHashEv": "cdhash",
}


def main(argv):
    targets = []
    for arg in argv[1:]:
        if "=" not in arg:
            print(__doc__, file=sys.stderr)
            return 1
        label, path = arg.split("=", 1)
        targets.append((label, path))
    if not targets:
        targets.append(("this_mac", "/System/Library/KernelCollections/BootKernelExtensions.kc"))
    status = 0
    for label, path in targets:
        try:
            found = kcfunc.symbol_bytes(path, AMFI, list(SYMBOLS))
        except (OSError, ValueError, struct.error) as e:
            print("%s: %s" % (label, e), file=sys.stderr)
            status = 1
            continue
        for symbol, kind in SYMBOLS.items():
            entry = found.get(symbol, b"")
            if len(entry) == kcfunc.ENTRY_BYTES:
                print("%s %s %s" % (entry.hex(), kind, label))
            else:
                print("%s: the %s function was not found" % (label, kind), file=sys.stderr)
                status = 1
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv))
