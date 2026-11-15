#!/usr/bin/env python3 -I
# A/B of "default scheduler" vs "all threads of the process on one CCD" (libccdtag.dylib).
# Runs alternate (default, shim, default, ...) so drift hits both sides; prints medians.
# Usage: bench.py <data.tar> <runs>
import os, statistics, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
SHIM = os.path.join(HERE, "libccdtag.dylib")
data, runs = sys.argv[1], int(sys.argv[2])

loads = {
    "node 4 workers": ["node", os.path.join(HERE, "workers.js"), "4", "200000"],
    "node 8 workers": ["node", os.path.join(HERE, "workers.js"), "8", "200000"],
    "zstd -T8 -10 (1 GB)": ["/opt/local/bin/zstd", "-q", "-T8", "-10", "-c", data],
    "xz -T8 -3 (1 GB)": ["/opt/local/bin/xz", "-T8", "-3", "-c", data],
}

def run(cmd, shim):
    env = dict(os.environ)
    if shim:
        env["DYLD_INSERT_LIBRARIES"] = SHIM
    t = time.monotonic()
    subprocess.run(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    return time.monotonic() - t

for name, cmd in loads.items():
    res = {False: [], True: []}
    run(cmd, False)  # warm-up (page cache, JIT caches)
    for i in range(runs):
        for shim in (False, True):
            res[shim].append(run(cmd, shim))
    d, s = statistics.median(res[False]), statistics.median(res[True])
    print(f"{name:22s} default {d:7.3f} s   one CCD {s:7.3f} s   change {100*(s-d)/d:+6.1f}%   "
          f"(spread default {min(res[False]):.3f}-{max(res[False]):.3f}, one CCD {min(res[True]):.3f}-{max(res[True]):.3f})",
          flush=True)
