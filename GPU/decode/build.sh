#!/bin/zsh
# build.sh - builds the two VideoToolbox decoder plug-ins into decode/build/:
#   AV1VCNDecoder.bundle   av01 on the VCN block of an AMD Radeon RX 6000
#   VP9VCNDecoder.bundle   vp09 on the same block
#   lvprobe                the installer's helper that asks macOS whether it would accept them
#   kextentry              the installers' helper that edits OpenCore's config.plist for the
#                          loader kext and the sensors kext
# It installs nothing. Needs the Command Line Tools only.
#
#   ./build.sh          the two bundles, lvprobe and kextentry
#   ./build.sh tests    the bundles and the test programs in decode/build/tests/
#
# DEBUG=1 keeps debug information. Without it the build holds no path of the machine it was
# made on, and two builds of the same source are byte-identical.
#
# The linker warns that pointers in kBaseClass are not aligned. That layout is Apple's:
# CoreMedia declares CMBaseClass with 4-byte packing. The warning is expected.
emulate -L zsh
setopt err_exit no_unset pipe_fail
cd "${0:A:h}"
VERSION=$(<VERSION)
B=build
CFLAGS=(-arch x86_64 -O2 -bundle -fvisibility=hidden -Wall -Wno-unused-function -Wno-four-char-constants
        -Wno-deprecated-declarations -mmacosx-version-min=13.0 -Icommon)
[[ ${DEBUG:-0} == 1 ]] && CFLAGS+=(-g)
FRAMEWORKS=(-framework CoreFoundation -framework CoreMedia -framework CoreVideo -framework VideoToolbox
            -framework IOKit -framework IOSurface)

build_bundle() {  # build_bundle <name> <folder> <sources...>
  local name=$1 dir=$2; shift 2
  local final=$B/$name.bundle
  # assembled under another name; it replaces the old bundle only when everything worked
  local out=$B/.$name.bundle.new
  rm -rf $out
  mkdir -p $out/Contents/MacOS
  sed "s/__VERSION__/$VERSION/g" $dir/Info.plist > $out/Contents/Info.plist
  plutil -lint -s $out/Contents/Info.plist
  xcrun clang $CFLAGS -I$dir $@ $FRAMEWORKS -o $out/Contents/MacOS/$name 2>&1 |
    { grep -v -E "pointer not aligned in '_kBaseClass'|disabling chained fixups because of unaligned pointers" || true; }
  codesign -f -s - $out 2>/dev/null
  # on text: nm | grep -q fails under pipe_fail when grep stops reading early
  local exports=$(nm -gU $out/Contents/MacOS/$name)
  [[ $exports == *"_${name%Decoder}_VTDecoder_CreateInstance"* ]] || {
    print "$name: the factory function is not exported"; exit 1; }
  rm -rf $final
  mv $out $final
  print "built decode/$final ($VERSION)"
}

build_bundle AV1VCNDecoder av1 av1/AV1VCNDecoder.c av1/vcnav1.c av1/av1parse.c common/vcndriver.c common/vcnsession.c
build_bundle VP9VCNDecoder vp9 vp9/VP9VCNDecoder.c vp9/vcnvp9.c vp9/vp9parse.c common/vcndriver.c common/vcnsession.c

# lvprobe (install/lvprobe.c) asks macOS whether it would accept a plug-in; the installer
# runs it. It must carry the library-validation flag, or the kernel says yes to everything.
xcrun clang -arch x86_64 -O2 -Wall -Wextra -mmacosx-version-min=13.0 ../install/lvprobe.c -o $B/lvprobe
codesign -f -s - -o library -i com.droga.lvprobe $B/lvprobe 2>/dev/null
# kextentry (install/kextentry.c) adds the entry of the loader kext or the sensors kext to
# OpenCore's config.plist; install/loader.sh and install/sensors.sh run it. install/ocentry.c
# is the editor, shared with the encoding fix.
rm -f $B/loaderentry  # its earlier name
xcrun clang -arch x86_64 -O2 -Wall -Wextra -Werror -mmacosx-version-min=13.0 ../install/kextentry.c \
  ../install/ocentry.c -framework CoreFoundation -o $B/kextentry
codesign -f -s - -i com.droga.kextentry $B/kextentry 2>/dev/null
if [[ ${1:-} == tests ]]; then
  # The test programs never talk to the GPU. They are built with the address and
  # undefined-behaviour sanitizers, and a finding stops them.
  T=$B/tests
  mkdir -p $T
  TFLAGS=(-arch x86_64 -O1 -g -Wall -Wextra -Wno-unused-function -Wno-unused-parameter
          -fsanitize=address,undefined -fno-sanitize-recover=undefined)
  xcrun clang $TFLAGS -Iav1 -Ivp9 tests/parsedigest.c av1/av1parse.c vp9/vp9parse.c -o $T/parsedigest
  xcrun clang $TFLAGS -Iav1 -Ivp9 tests/parsefuzz.c av1/av1parse.c vp9/vp9parse.c -o $T/parsefuzz
  xcrun clang $TFLAGS -Iav1 tests/av1state.c av1/av1parse.c -o $T/av1state
  xcrun clang $TFLAGS -Ivp9 tests/vp9state.c vp9/vp9parse.c -o $T/vp9state
  for c in AV1 VP9; do
    xcrun clang $TFLAGS -DTEST_$c tests/plugintest.c -framework CoreFoundation -framework CoreMedia \
      -framework CoreVideo -framework VideoToolbox -o $T/plugintest-${(L)c}
  done
  xcrun clang $TFLAGS -Icommon tests/acceltest.c common/vcndriver.c -framework CoreFoundation -framework IOKit \
    -o $T/acceltest
  xcrun clang $TFLAGS -Icommon tests/waittest.c common/vcnsession.c -framework CoreFoundation -framework IOKit \
    -o $T/waittest
  # The decoder sessions against a made-up driver: sessiontest.c stands in for common/vcndriver.c.
  for c in av1 vp9; do
    xcrun clang $TFLAGS -DTEST_${(U)c} -Icommon -I$c tests/sessiontest.c $c/vcn$c.c $c/${c}parse.c \
      common/vcnsession.c -framework CoreFoundation -framework CoreVideo -framework IOKit \
      -framework IOSurface -o $T/sessiontest-$c
  done
  xcrun clang++ -std=c++17 $TFLAGS -Iloader tests/loadertest.cpp -o $T/loadertest
  print "built the test programs in decode/$T"
fi
