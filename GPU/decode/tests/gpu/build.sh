#!/bin/zsh
# build.sh - builds the test programs that talk to the video driver or to the GPU, into
# decode/build/gpu/. It only compiles: it runs nothing and installs nothing.
# Needs the Command Line Tools only.
#
#   decode/tests/gpu/build.sh
#
#   decode_ivf    AV1 on the VCN, without VideoToolbox       (armed by VCNAV1_ALLOW_GPU)
#   decode_vp9    VP9 on the VCN, without VideoToolbox       (armed by VCNVP9_ALLOW_GPU)
#   decode_legacy MPEG-2, VC-1 or MPEG-4 on the VCN, without VideoToolbox (armed by VCNLEGACY_ALLOW_GPU)
#   vtlegacytest  MPEG-2, VC-1 or MPEG-4 through VideoToolbox, plug-ins registered in the
#                 test's own process, nothing installed       (armed by VCNLEGACY_ALLOW_GPU)
#   vtav1test     AV1 through VideoToolbox, as Safari does   (no switch: see README.md)
#   vtvp9test     VP9 through VideoToolbox, as Safari does   (no switch: see README.md)
#   vtjpegtest    Motion JPEG through VideoToolbox, our decoder only (loaded in the process, or the
#                 installed one with -system), compared with FFmpeg (no switch)
#   mkmjpeg422    writes Motion JPEG sampled as webcams do (4:2:2, luma 2x1); CPU only
#   vtchurn       many sessions in one process, counts ports and IOKit connections (no switch)
#   probe_ctx     asks the driver for one decode context     (no switch: see README.md)
#   driveruuid    prints the build identifier of the installed driver
#   vp9dump       VP9 parser check, no driver and no GPU
#   vc1info       what a VC-1 stream holds (field-interlaced frames or not), no driver and no GPU
#   rawpatch      tools/driver/rawpatch.c, unpacks a macOS update image
#
# decode_ivf and decode_vp9 are built from the same sources as the two plug-ins, at the same
# optimisation level, plus -DVCN_DRYRUN_TOOLS: that adds the memory dump helpers the lldb dry
# runs call (tools/driver/dryrun.py and dryrun_vp9.py). The plug-ins never carry them.
#
# What each program does, how to arm it and which ones can hang the GPU: README.md, here.
emulate -L zsh
setopt err_exit no_unset pipe_fail
cd "${0:A:h:h:h}"   # decode/
B=build/gpu
T=tests/gpu
mkdir -p $B
CFLAGS=(-arch x86_64 -O2 -g -Wall -Wextra -Wno-unused-parameter -Wno-unused-function
        -Wno-four-char-constants -Wno-deprecated-declarations -mmacosx-version-min=13.0
        -Icommon -Iav1 -Ivp9)
DRYRUN=(-DVCN_DRYRUN_TOOLS)
CF=(-framework CoreFoundation)
IOKIT=(-framework IOKit)
VIDEO=(-framework CoreVideo -framework IOSurface)
VT=(-framework CoreMedia -framework CoreVideo -framework VideoToolbox)
IMAGE=(-framework CoreGraphics -framework ImageIO)

build() {  # build <name> <sources and flags...>
  local name=$1; shift
  xcrun clang $CFLAGS $@ -o $B/$name
  codesign -f -s - $B/$name 2>/dev/null
}

# A dry run stops the process at these functions. Without them in the binary the lldb script
# would have nothing to stop at, and the run would go through to the GPU.
need_symbols() {  # need_symbols <name> <symbol...>
  local name=$1 sym; shift
  local table=$(nm $B/$name)
  for sym in $@; do
    print -r -- $table | grep -q " T _$sym\$" || {
      print "$name: $sym is missing, the dry run cannot work"; exit 1; }
  done
}

build decode_ivf $DRYRUN $T/decode_ivf.c av1/vcnav1.c av1/av1parse.c common/vcndriver.c common/vcnsession.c \
  $CF $IOKIT $VIDEO
need_symbols decode_ivf vcnav1_dryrun_checkpoint vcnav1_dump

build decode_vp9 $DRYRUN $T/decode_vp9.c vp9/vcnvp9.c vp9/vp9parse.c common/vcndriver.c common/vcnsession.c \
  $CF $IOKIT $VIDEO $IMAGE
need_symbols decode_vp9 vcnvp9_dryrun_checkpoint vcnvp9_session_message vcnvp9_message_built \
  vcnvp9_dump

# The three codecs of common/vcnlegacy.c, from the same sources as their plug-ins.
LEGACY=(common/vcnlegacy.c mpeg2/vcnmpeg2.c mpeg2/mpeg2parse.c vc1/vcnvc1.c vc1/vc1parse.c
        mpeg4/vcnmpeg4.c mpeg4/mpeg4parse.c)
build decode_legacy -Impeg2 -Ivc1 -Impeg4 $T/decode_legacy.c $LEGACY common/vcndriver.c \
  common/vcnsession.c $CF $IOKIT $VIDEO

# The three plug-ins linked in and registered with VideoToolbox in the test's own process.
build vtlegacytest -Impeg2 -Ivc1 -Impeg4 $T/vtlegacytest.c mpeg2/MPEG2VCNDecoder.c vc1/VC1VCNDecoder.c \
  mpeg4/MPEG4VCNDecoder.c $LEGACY common/vcndriver.c common/vcnsession.c $CF $IOKIT $VT \
  -framework IOSurface 2>&1 | { grep -v -E "pointer not aligned in '_kBaseClass'|disabling chained fixups" || true; }

build vtav1test $T/vtav1test.c av1/av1parse.c $CF $VT
build vtvp9test $T/vtvp9test.c vp9/vp9parse.c $CF $VT
build vtjpegtest $T/vtjpegtest.c $CF $VT
build mkmjpeg422 $T/mkmjpeg422.c
build vtchurn $T/vtchurn.c $CF $VT
build probe_ctx $T/probe_ctx.c common/vcndriver.c $CF $IOKIT
build driveruuid $T/driveruuid.c common/vcndriver.c $CF $IOKIT
build vp9dump $T/vp9dump.c vp9/vp9parse.c
build vc1info -Ivc1 $T/vc1info.c vc1/vc1parse.c
build rawpatch ../tools/driver/rawpatch.c

print "built the GPU test programs in decode/$B (nothing was run)"
