#!/usr/bin/env python3
"""Checks that each function the GPU control routes or calls (ppCWDDE, 0.5.0)
starts, in this Mac's kernel collection, with the bytes
sensors/kext/control_logic.hpp expects.

usage: ctlentries.py <SystemKernelExtensions.kc>

AMDRadeonX6000HWLibs (the library this Mac loads) must match for every
function. AMDRadeonX6800HWLibs, when present, is reported for information:
a function that starts differently there is one the kext leaves out on cards
set up with that library. Exits 1 if anything in X6000 differs, is missing,
or the header cannot be read.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
HEADER = os.path.join(ROOT, 'sensors', 'kext', 'control_logic.hpp')
KCFUNC = os.path.join(HERE, 'kcfunc.py')
REQUIRED = 'com.apple.kext.AMDRadeonX6000HWLibs'
OPTIONAL = 'com.apple.kext.AMDRadeonX6800HWLibs'
KCFUNC_BYTES = 32  # kcfunc.py prints this many bytes

# (symbol constant, entry array) in control_logic.hpp; the length constant is
# the entry's name with Entry replaced by Bytes.
PAIRS = [
    ('kPolicySymbol', 'kPolicyEntry'),
    ('kPPInitSymbol', 'kPPInitEntry'),
    ('kGetLimitSymbol', 'kGetLimitEntry'),
    ('kSetLimitSymbol', 'kSetLimitEntry'),
    ('kSleepSymbol', 'kSleepWakeEntry'),
    ('kWakeSymbol', 'kSleepWakeEntry'),
    ('kCwddeSymbol', 'kCwddeEntry'),  # called, not routed
]


def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', ' ', text, flags=re.S)
    return re.sub(r'//[^\n]*', ' ', text)


def constants(text):
    text = strip_comments(text)
    symbols = dict(re.findall(
        r'constexpr\s+const\s+char\s*\*\s*(k\w+Symbol)\s*=\s*"([^"]+)"', text))
    sizes = {name: int(value, 0) for name, value in re.findall(
        r'constexpr\s+size_t\s+(k\w+Bytes)\s*=\s*(\w+)\s*;', text)}
    arrays = {}
    for name, body in re.findall(
            r'constexpr\s+uint8_t\s+(k\w+Entry)\s*\[[^\]]*\]\s*=\s*\{([^}]*)\}', text):
        tokens = [t.strip() for t in body.split(',') if t.strip()]
        arrays[name] = bytes(int(t, 0) for t in tokens).hex()
    return symbols, sizes, arrays


def first_bytes(bundle, symbol, kc):
    run = subprocess.run(
        [sys.executable, '-I', KCFUNC, bundle, symbol, 'this_mac=' + kc],
        capture_output=True, text=True)
    words = run.stdout.split()
    return words[0].lower() if run.returncode == 0 and words else None


def main():
    if len(sys.argv) != 2:
        print(__doc__.strip())
        return 2
    kc = sys.argv[1]
    try:
        symbols, sizes, arrays = constants(open(HEADER).read())
    except (OSError, ValueError) as e:
        print('FAIL control_logic.hpp: %s' % e)
        return 1
    bad = 0
    checks = []
    for sym_name, entry_name in PAIRS:
        size_name = entry_name.replace('Entry', 'Bytes')
        symbol, want = symbols.get(sym_name), arrays.get(entry_name)
        size = sizes.get(size_name)
        if not symbol or not want or size is None:
            print('FAIL %s / %s / %s: not found in control_logic.hpp'
                  % (sym_name, entry_name, size_name))
            bad += 1
        elif len(want) // 2 != size or not 14 <= size <= KCFUNC_BYTES:
            print('FAIL %s: %d bytes listed, %s says %d (must be 14 to %d)'
                  % (entry_name, len(want) // 2, size_name, size, KCFUNC_BYTES))
            bad += 1
        else:
            checks.append((symbol, want))
    optional_present = first_bytes(OPTIONAL, checks[0][0], kc) is not None if checks else False
    for symbol, want in checks:
        got = first_bytes(REQUIRED, symbol, kc)
        if got is None:
            print('FAIL %s: not found in %s' % (symbol, REQUIRED))
            bad += 1
        elif got.startswith(want):
            print('ok   %s (%d bytes)' % (symbol, len(want) // 2))
        else:
            print('FAIL %s: starts %s, expected %s' % (symbol, got[:len(want)], want))
            bad += 1
        if optional_present:
            other = first_bytes(OPTIONAL, symbol, kc)
            if other is not None and other.startswith(want):
                print('       X6800HWLibs: same')
            else:
                print('       X6800HWLibs: differs, the kext leaves it out there')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
