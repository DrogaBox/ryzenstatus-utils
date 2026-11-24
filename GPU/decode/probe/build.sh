#!/bin/zsh
# build.sh - builds vcncodecprobe and its parser test into probe/build/.
#   ./build.sh          both
#   ./build.sh tests    the parser test only
# The probe needs the Command Line Tools and nothing else; the parser test never
# links the driver. Both are x86_64, like the plug-ins the driver loads.
# No GPU is touched by building or by the parser test.
emulate -L zsh
setopt err_exit no_unset pipe_fail
cd "${0:A:h}"
B=build
CFLAGS=(-arch x86_64 -O2 -Wall -Wextra -Wno-unused-parameter
        -mmacosx-version-min=13.0 -I. -I../common)
FRAMEWORKS=(-framework CoreFoundation -framework CoreVideo -framework IOKit
            -framework IOSurface)
mkdir -p $B

build_probe() {
  # ../vp9 is not changed by the probe: vp9parse.c is the plug-in's parser and
  # vp9fill.c is its message builder, so the control sends exactly the VP9
  # message production sends.
  xcrun clang $CFLAGS -I../vp9 main.c vcnprobe.c mpeg2parse.c vc1parse.c \
    mpeg4parse.c jpegparse.c vp9fill.c ../vp9/vp9parse.c \
    ../common/vcndriver.c ../common/vcnsession.c $FRAMEWORKS \
    -o $B/vcncodecprobe
  codesign -f -s - $B/vcncodecprobe 2>/dev/null
  print "built probe/$B/vcncodecprobe"
}

build_tests() {
  xcrun clang $CFLAGS -fsanitize=address,undefined \
    -fno-sanitize-recover=undefined parsertest.c mpeg2parse.c vc1parse.c \
    mpeg4parse.c jpegparse.c -o $B/parsertest
  print "built probe/$B/parsertest"
}

if [[ ${1:-} == tests ]]; then
  build_tests
else
  build_probe
  build_tests
fi
