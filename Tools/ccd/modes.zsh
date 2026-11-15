#!/bin/zsh
# Measures AMDCCDScheduler's modes against each other: debug.ccd_mode 0 (off), 1 (home CCD per
# process, the default) and 2 (the 0.1.0 behaviour). Run it as root; the loads run as $SUDO_USER.
#
#   sudo zsh Tools/ccd/modes.zsh results.txt data.tar
#
# Loads: Tools/ccd/workers.js with 4 and 8 workers passing messages (7 runs per mode), and
# zstd -T24 -10 over data.tar (5 runs per mode; about 1 GB makes each run take seconds).
# The order of the modes rotates every run so slow drift hits all three alike. Each load runs
# once before its measured runs, to warm caches. The mode goes back to 1 on exit.
# Needs node and zstd in PATH (or NODE=..., ZSTD=...). Prints medians at the end.
set -u
OUT="${1:?results file}"; DATA="${2:?input file for zstd}"
U="${SUDO_USER:?run with sudo}"
HERE="${0:A:h}"
W="$HERE/workers.js"
NODE="${NODE:-$(command -v node)}"
ZSTD="${ZSTD:-$(command -v zstd)}"
[[ -x "$NODE" && -x "$ZSTD" ]] || { print -u2 "node or zstd not found (set NODE= / ZSTD=)"; exit 1; }
/usr/sbin/sysctl -n debug.ccd_mode >/dev/null 2>&1 || { print -u2 "AMDCCDScheduler is not loaded"; exit 1; }
trap '/usr/sbin/sysctl -w debug.ccd_mode=1 >/dev/null' EXIT
: > "$OUT"
orders=("0 1 2" "1 2 0" "2 0 1")
ms_now() { perl -MTime::HiRes=time -e 'printf "%d\n", time*1000'; }
run_load() {
  case $1 in
    node4) sudo -u "$U" "$NODE" "$W" 4 200000 | awk '{print $(NF-1)}' ;;
    node8) sudo -u "$U" "$NODE" "$W" 8 200000 | awk '{print $(NF-1)}' ;;
    zstd24) local t0=$(ms_now); sudo -u "$U" "$ZSTD" -q -T24 -10 -c "$DATA" >/dev/null; print $(( $(ms_now) - t0 )) ;;
  esac
}
for load in node4 node8 zstd24; do
  runs=7; [[ $load == zstd24 ]] && runs=5
  /usr/sbin/sysctl -w debug.ccd_mode=1 >/dev/null
  run_load $load >/dev/null
  for i in $(seq 1 $runs); do
    for m in ${=orders[$(( (i - 1) % 3 + 1 ))]}; do
      /usr/sbin/sysctl -w debug.ccd_mode=$m >/dev/null
      print -r -- "$load mode $m run $i ms $(run_load $load)" >> "$OUT"
    done
  done
done
print -r -- "stat $(/usr/sbin/sysctl -n debug.ccd_stat)" >> "$OUT"
chown "$U" "$OUT"
python3 -I - "$OUT" <<'EOF'
import re, statistics as st, sys
d = {}
for line in open(sys.argv[1]):
    m = re.match(r"(\w+) mode (\d) run \d+ ms (\d+)", line)
    if m:
        d.setdefault((m[1], m[2]), []).append(int(m[3]))
for load in ("node4", "node8", "zstd24"):
    base = st.median(d[(load, "0")])
    cells = []
    for mode in "012":
        v = d[(load, mode)]
        med = st.median(v)
        cells.append(f"mode {mode}: {med:.0f} ms ({100 * (med / base - 1):+.1f}%, {min(v)}-{max(v)})")
    print(f"{load:7} " + "   ".join(cells))
EOF
