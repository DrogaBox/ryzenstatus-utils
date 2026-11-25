#!/bin/zsh
# jpeg/tests/run.sh - host checks of VCNJpeg. Loads no kext and touches no device. Run
# jpeg/build.sh tests first.
#
#   1. unit checks of kext/jpeg_cmds.hpp (frames, IB, layout, stream check), with sanitizers
#   2. the door (kext/apps_handler.hpp) and when the block is powered (kext/idle_logic.hpp)
#   3. the job frame against Apple's own queue_jpeg_decode_2_0_build_command, run from the KDK
#      binary (KDK_HWLIBS)
#   4. the decode IB against Mesa's own vcn_jpeg_build_decode_cmd, compiled from Mesa's source
#      (MESA_DIR: ac_vcn_dec.c and the files tests/gen_mesa_oracle.py names)
#   5. the PowerPlay requests against Apple's own setClocks and notifyPMContext, run from the
#      KDK binary (KDK_X6000)
#
# 1 and 2 need a baseline JPEG of 640x480 (SAMPLE); without one, it is made with ffmpeg
# (FFMPEG). 3 to 5 need Apple's KDK for macOS 26.7.3 (25G342) and a copy of Mesa: when they are
# missing those parts are skipped, and the result says so.
emulate -L zsh
setopt err_exit no_unset pipe_fail
HERE=${0:A:h}; JPEG=${HERE:h}; B=$JPEG/build/tests
KDK=${KDK:-/Library/Developer/KDKs/KDK_26.7.3_25G342.kdk}
KDK_HWLIBS=${KDK_HWLIBS:-$KDK/System/Library/Extensions/AMDRadeonX6000HWServices.kext/Contents/PlugIns/AMDRadeonX6000HWLibs.kext/Contents/MacOS/AMDRadeonX6000HWLibs}
KDK_X6000=${KDK_X6000:-$KDK/System/Library/Extensions/AMDRadeonX6000.kext/Contents/MacOS/AMDRadeonX6000}
MESA_DIR=${MESA_DIR:-}
FFMPEG=${FFMPEG:-$(command -v ffmpeg || true)}
[[ -x $B/cmds_test && -x $B/apps_test ]] || { print "run jpeg/build.sh tests first"; exit 1; }
fails=0 skips=0
say() { print -r -- "$1 $2"; [[ $1 == ok ]] || fails=$((fails + 1)); }
skip() { print -r -- "skip $1"; skips=$((skips + 1)); }

SAMPLE=${SAMPLE:-}
if [[ -z $SAMPLE && -n $FFMPEG ]]; then
  SAMPLE=$B/sample-640x480.jpg
  $FFMPEG -hide_banner -v error -f lavfi -i testsrc=size=640x480:rate=1 -frames:v 1 -pix_fmt yuvj420p \
    -huffman default -q:v 4 -y $SAMPLE
fi

print "== 1. unit checks, and 2. the door and the block's power (address and undefined-behaviour sanitizers)"
if [[ -n $SAMPLE && -f $SAMPLE ]]; then
  $B/cmds_test unit $SAMPLE > $B/cmds_test.txt || fails=$((fails + 1))
  grep -v '^ok ' $B/cmds_test.txt || true
  print "$(grep -c '^ok ' $B/cmds_test.txt) unit checks passed"
  $B/apps_test $SAMPLE > $B/apps_test.txt || fails=$((fails + 1))
  grep -v '^ok ' $B/apps_test.txt || true
  print "$(grep -c '^ok ' $B/apps_test.txt) door checks passed"
else
  say FAIL "no 640x480 baseline JPEG: give SAMPLE, or install ffmpeg"
fi

print "== 3. job frame against HWLibs' own command builder"
if [[ -f $KDK_HWLIBS ]]; then
  addr=0x$(nm $KDK_HWLIBS | awk '$3 == "_queue_jpeg_decode_2_0_build_command" {print $1}')
  for args in "0x8000100000 0x8000200000 80 7 0x8000201000" "0xff00123000 0x1234567000 16 4294967295 0xabcdef1000" \
              "0x100000 0x200000 128 1 0x201000"; do
    a=(${=args})
    $B/hwlibs_oracle $KDK_HWLIBS $addr $a[1] $a[2] $((a[3] * 4)) $a[4] $a[5] | awk '{print $2}' > $B/frame.hwlibs
    $B/cmds_test frame $a[1] $a[2] $a[3] $a[4] $a[5] > $B/frame.ours
    # HWLibs' four commands are the first 56 words; ours go on with four nop pairs
    if [[ $(wc -l < $B/frame.hwlibs) -eq 56 ]] && cmp -s $B/frame.hwlibs <(head -56 $B/frame.ours) \
       && [[ "$(tail -8 $B/frame.ours | tr '\n' ' ')" == "60000000 00000000 60000000 00000000 60000000 00000000 60000000 00000000 " ]]; then
      say ok "frame equals HWLibs' start + IB + fence + end, word for word ($args)"
    else
      say FAIL "frame differs from HWLibs' ($args)"; diff $B/frame.hwlibs <(head -56 $B/frame.ours) | head -10 || true
    fi
  done
else
  skip "no KDK AMDRadeonX6000HWLibs at $KDK_HWLIBS (set KDK or KDK_HWLIBS)"
fi

print "== 4. decode IB against Mesa's own builder"
if [[ -n $MESA_DIR && -f $MESA_DIR/ac_vcn_dec.c ]]; then
  python3 -I $HERE/gen_mesa_oracle.py $MESA_DIR $B/mesa_oracle.c > /dev/null
  xcrun clang -std=c11 -arch x86_64 -O1 -Wall -Wno-unused-function -Wno-unused-variable $B/mesa_oracle.c -o $B/mesa_oracle
  for args in "0x8000110000 24704 0x8000210000 768 368640" "0xff12345000 1048448 0xab00110000 2048 2228224" \
              "0x110000 128 0x210000 256 4096"; do
    a=(${=args})
    $B/mesa_oracle $a > $B/ib.mesa
    $B/cmds_test ib $a > $B/ib.ours
    n=$(wc -l < $B/ib.mesa | tr -d ' ')
    rest=$(tail -n +$((n + 1)) $B/ib.ours | tr '\n' ' ')
    # Mesa's builder stops before the padding its winsys adds: (0x60000000, 0) pairs up to 16 words
    if cmp -s $B/ib.mesa <(head -$n $B/ib.ours) && [[ $(( $(wc -l < $B/ib.ours) % 16 )) -eq 0 ]] \
       && [[ -z ${rest//60000000 00000000 /} ]]; then
      say ok "IB equals Mesa's $n words, then nop pairs to $(wc -l < $B/ib.ours | tr -d ' ') ($args)"
    else
      say FAIL "IB differs from Mesa's ($args)"; diff $B/ib.mesa <(head -$n $B/ib.ours) | head -10 || true
    fi
  done
  # through outputLayout + decodeParams, NV12 and YUYV (4:2:2), against Mesa's surface for each
  for pair in "0x8000110000 24704 0x8000210000 768 368640|0x8000110000 24704 0x8000210000 640 480 0" \
              "0x8000110000 24704 0x8000210000 1280 0 yuyv|0x8000110000 24704 0x8000210000 640 480 1" \
              "0xff12345000 1048448 0xab00110000 3840 0 yuyv|0xff12345000 1048448 0xab00110000 1920 1080 1"; do
    m=(${=pair%%|*}); o=(${=pair##*|})
    $B/mesa_oracle $m > $B/ib.mesa
    $B/cmds_test ibl $o > $B/ib.ours
    n=$(wc -l < $B/ib.mesa | tr -d ' ')
    rest=$(tail -n +$((n + 1)) $B/ib.ours | tr '\n' ' ')
    if cmp -s $B/ib.mesa <(head -$n $B/ib.ours) && [[ $(( $(wc -l < $B/ib.ours) % 16 )) -eq 0 ]] \
       && [[ -z ${rest//60000000 00000000 /} ]]; then
      say ok "layout IB equals Mesa's $n words (mesa: ${m[*]}; ours: ${o[*]})"
    else
      say FAIL "layout IB differs from Mesa's (mesa: ${m[*]}; ours: ${o[*]})"; diff $B/ib.mesa <(head -$n $B/ib.ours) | head -10 || true
    fi
  done
else
  skip "no copy of Mesa (set MESA_DIR to a folder holding ac_vcn_dec.c and its headers)"
fi

print "== 5. PowerPlay requests against Apple's own kernel code"
if [[ -f $KDK_X6000 ]]; then
  # address and length of a function, and the external calls inside it as site:stand-in
  xfn() { nm -n $KDK_X6000 | python3 -I -c 'import sys
want, start, end = sys.argv[1], None, None
for line in sys.stdin:
    f = line.split()
    if len(f) != 3 or f[1] not in "TtSs": continue
    if start is not None and end is None: end = int(f[0], 16)
    if f[2] == want: start = int(f[0], 16)
print("0x%x %d" % (start, end - start))' $1; }
  xsites() { otool -rv $KDK_X6000 | python3 -I -c 'import sys
lo, n = int(sys.argv[1], 16), int(sys.argv[2])
for line in sys.stdin:
    f = line.split()
    if len(f) >= 7 and f[4] == "BRANCH" and lo <= int(f[0], 16) < lo + n:
        kind = {"___bzero": "bzero", "_IOLockLock": "nop", "_IOLockUnlock": "nop"}.get(f[6], "UNKNOWN_" + f[6])
        print("%s:%s" % (f[0], kind))' $1 $2; }
  send=0x$(nm $KDK_X6000 | awk '$3 == "__ZN37AMDRadeonX6000_AMDGraphicsAccelerator13sendPMCommandEPv" {print $1}')
  sc=($(xfn __ZN33AMDRadeonX6000_AMDAccelVCNContext9setClocksEv))
  nf=($(xfn __ZN35AMDRadeonX6000_AMDAccelVideoContext15notifyPMContextE21_CWDDEPM_SCHEDULER_IDjyjj))
  for ctx in 0xffffff8012345678 0x1122334455667788; do
    $B/x6000_oracle $KDK_X6000 $send setclocks $sc[1] $sc[2] 21 $ctx $(xsites $sc[1] $sc[2]) > $B/pm.apple
    $B/cmds_test pm request $ctx > $B/pm.ours
    if [[ $(wc -l < $B/pm.apple) -eq 35 ]] && cmp -s $B/pm.apple $B/pm.ours; then
      say ok "PMRequest equals what AMDAccelVCNContext::setClocks builds for client type 21 (context $ctx)"
    else
      say FAIL "PMRequest differs from setClocks' ($ctx)"; diff $B/pm.apple $B/pm.ours | head -10 || true
    fi
    for on in 1 0; do
      $B/x6000_oracle $KDK_X6000 $send notify $nf[1] $nf[2] 21 $ctx $on $(xsites $nf[1] $nf[2]) > $B/pm.apple
      $B/cmds_test pm activate $ctx $on > $B/pm.ours
      if [[ $(wc -l < $B/pm.apple) -eq 15 ]] && cmp -s $B/pm.apple $B/pm.ours; then
        say ok "ActivateClient($on) equals what AMDAccelVideoContext::notifyPMContext builds (context $ctx)"
      else
        say FAIL "ActivateClient($on) differs from notifyPMContext's ($ctx)"; diff $B/pm.apple $B/pm.ours | head -10 || true
      fi
    done
  done
  # the same Apple code with the VCN client type differs from ours in that one word only
  $B/x6000_oracle $KDK_X6000 $send setclocks $sc[1] $sc[2] 28 0x1122334455667788 $(xsites $sc[1] $sc[2]) > $B/pm.apple
  $B/cmds_test pm request 0x1122334455667788 > $B/pm.ours
  diff $B/pm.apple $B/pm.ours > $B/pm.diff || true
  if [[ $(grep -c '^[<>]' $B/pm.diff) -eq 2 ]] && grep -q '^< 0000001c$' $B/pm.diff && grep -q '^> 00000015$' $B/pm.diff; then
    say ok "with Apple's own client type (28) the request differs from ours in the client type word only"
  else
    say FAIL "unexpected difference against the VCN request"
  fi
else
  skip "no KDK AMDRadeonX6000 at $KDK_X6000 (set KDK or KDK_X6000)"
fi

print ""
if (( fails )); then print "$fails TEST(S) FAILED"; exit 1; fi
if (( skips )); then print "TESTS PASSED ($skips part(s) skipped)"; else print "TESTS PASSED"; fi
