#!/bin/zsh
# VCNEncodeFix test: short hardware encodes that show whether each fix is working. Run it as yourself (no sudo),
# with nothing else encoding. Writes a report to reports/ next to this script, ready to share.
#
#   ./test.sh            preset and clock floor tests (sizes up to 4096 wide; safe on any setup)
#   ./test.sh --wide     also one HEVC 5120x2160 encode. Only runs if the service patched that encoder before its
#                        first frame (checked during a 3 s pause); without the fix that size stalls the GPU's
#                        compute queue for seconds and can glitch the screen.
#
# Exit status: 0 the tests ran (the report says how they went); 1 they could not run; 64 wrong usage.
emulate -L zsh
setopt pipe_fail
here=${0:A:h}
vtenc=$here/bin/vtenc
wide=0
case ${1:-} in
  "") ;;
  --wide) wide=1 ;;
  -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' $0; exit 0 ;;
  *) print -u2 "unknown option $1 (see --help)"; exit 64 ;;
esac
(( $# <= 1 )) || { print -u2 "one option at most (see --help)"; exit 64; }
(( EUID != 0 )) || { print "run it as yourself, not with sudo"; exit 1; }
# sudo keeps the caller's PATH on macOS: only the system's own tools, whatever is in it
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
xattr -drs com.apple.quarantine $here 2>/dev/null
[[ -x $vtenc ]] || { print -u2 "$vtenc is missing; unpack the whole folder"; exit 1; }
mkdir -p $here/reports || { print -u2 "cannot create $here/reports"; exit 1; }
report=$here/reports/test-$(date +%Y%m%d-%H%M%S).txt
start=$(date '+%Y-%m-%d %H:%M:%S')
log=/var/log/vcnencodefix.log

run() {  # run <label> <seconds timeout> <vtenc args...>
  local label=$1 limit=$2; shift 2
  print -r -- "-- $label: vtenc encode $*"
  perl -e "alarm $limit; exec @ARGV" $vtenc encode "$@" --quiet 2>&1 | grep -E 'RESULT|wall|steady|EncodeFrame call|rror' | sed 's/^/   /'
}

{
  zsh $here/doctor.sh
  print ""
  print "== Tests ($start)"
  print "Reference, RX 6800 XT, macOS 26.7.3: test 1 about 72 fps without the preset, 99 fps with it;"
  print "test 2 about 95 ms per frame (p50) without the clock floor, 22 ms with floor and preset."
  sleep 3
  run "1 preset: HEVC 3840x2160, 300 frames as fast as possible" 120 --codec hevc --size 3840x2160 --fps 60 --frames 300 --bitrate 40 --pace 0 --source ring
  print "   (6 s idle so the VCN clocks drop first)"
  sleep 6
  run "2 clock floor: HEVC 3840x4320, 60 CPU-filled frames" 120 --codec hevc --size 3840x4320 --fps 30 --frames 60 --bitrate 60 --pace 0 --source copykeep
  if (( wide )); then
    print -r -- "-- 3 wide: HEVC 5120x2160, 60 frames"
    before=$(pgrep VTEncoderXPCService | sort)
    out=$(mktemp)
    # Only what the service writes from now on counts: an old line about a reused pid must not
    # let a 5120-wide encode through unpatched.
    offset=$(stat -f %z $log 2>/dev/null || print 0)
    perl -e 'alarm 120; exec @ARGV' $vtenc encode --codec hevc --size 5120x2160 --fps 30 --frames 60 --bitrate 60 --pace 0 \
      --source ring --pause 3 --quiet > $out 2>&1 &
    job=$!
    # stopped before its first frame however the test is left
    trap 'kill $job 2>/dev/null; rm -f $out; exit 130' INT TERM HUP
    sleep 1.5
    svc=$(pgrep VTEncoderXPCService | sort | comm -13 <(print -r -- $before) - | tail -1)
    newlog=$(tail -c +$((offset + 1)) $log 2>/dev/null)
    if [[ -n $svc ]] && print -r -- $newlog | grep -qE "pid $svc: .*wide: (patched|already patched)"; then
      print "   encoder service $svc was patched before its first frame"
      spawned=$(/usr/bin/log show --start "$start" --style compact --predicate "process == \"launchd\" AND eventMessage CONTAINS \"spawned VTEncoderXPCService[$svc]\"" 2>/dev/null | awk 'NR > 1 && $2 ~ /^[0-9][0-9]:/ {print $2; exit}')
      patched=$(print -r -- $newlog | grep -E "pid $svc: .*wide: patched" | tail -1 | awk '{print $2}')
      if [[ -n $spawned && -n $patched ]]; then
        print "   service started $spawned, plug-in patched $patched (an app without a pause sends its first frame about 260 ms after the start)"
      fi
      wait $job
      grep -E 'RESULT|wall|steady|EncodeFrame call|rror' $out | sed 's/^/   /'
    else
      kill $job 2>/dev/null; wait $job 2>/dev/null
      print "   SKIPPED: the encoder service (${svc:-not found}) was not reported as patched in $log, so no frame was sent"
    fi
    rm -f $out
    trap - INT TERM HUP
  fi
  print ""
  print "== GPU messages from the kernel during the tests"
  /usr/bin/log show --start "$start" --style compact --predicate 'process == "kernel" AND (eventMessage CONTAINS[c] "restart channel" OR eventMessage CONTAINS[c] "event timeout" OR eventMessage CONTAINS[c] "GPU Restart")' 2>/dev/null \
    | grep -v -E '^Timestamp|Filtering' | cut -c1-160 | tail -8 | sed 's/^/   /'
  print "   (nothing above this line means no GPU restarts or timeouts)"
} 2>&1 | tee $report
rc=$?
print ""
print "Report saved to $report"
exit $rc
