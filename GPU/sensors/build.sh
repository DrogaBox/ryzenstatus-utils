#!/bin/zsh
# build.sh - builds the GPU sensors into sensors/build/. It installs nothing.
#   GPUSensors.kext   the Lilu plug-in that copies the readings the driver takes
#   gpusensors        the command that shows them
#   gpucontrol        the command for the power limit control (0.5.0)
#
#   sensors/build.sh            the kext and the commands
#   sensors/build.sh tests      also the test programs (sensors/build/tests/pmlogtest, controltest)
#
# The kext needs the Command Line Tools, Lilu.kext (DEBUG build) and MacKernelSDK:
# tools/bootstrap.sh fetches pinned copies into deps/; to use your own, export LILU_KEXT
# and MACKERNELSDK. The command and the tests only need the Command Line Tools.
#
# The kext carries its build date (Lilu's version string), taken from SOURCE_DATE_EPOCH,
# which defaults to the date of the last commit: the same commit gives the same kext.
emulate -L zsh
setopt err_exit no_unset pipe_fail
HERE=${0:A:h}
ROOT=${HERE:h}
NAME=GPUSensors
VERSION=$(<$HERE/VERSION)
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -C $ROOT log -1 --format=%ct 2>/dev/null || date +%s)}
LILU=${LILU_KEXT:-$ROOT/deps/Lilu.kext}
MKSDK=${MACKERNELSDK:-$ROOT/deps/MacKernelSDK}
B=$HERE/build
OBJ=$B/obj
FINAL=$B/$NAME.kext
OUT=$OBJ/$NAME.kext  # assembled here; it replaces $FINAL only when everything worked
[[ -f $LILU/Contents/Resources/Library/plugin_start.cpp && -f $MKSDK/Library/x86_64/libkmod.a ]] || {
  print "Lilu.kext (DEBUG) and MacKernelSDK not found: run tools/bootstrap.sh, or set LILU_KEXT and MACKERNELSDK"; exit 1; }
rm -rf $OBJ && mkdir -p $OBJ $OUT/Contents/MacOS

# The commands: no kernel parts, build anywhere.
xcrun clang++ -std=c++17 -arch x86_64 -O2 -Wall -Wextra -Werror -mmacosx-version-min=13.0 -I$HERE/kext \
  $HERE/tool/gpusensors.cpp -framework CoreFoundation -framework IOKit -o $B/gpusensors
codesign -f -s - -i com.droga.gpusensors $B/gpusensors 2>/dev/null
xcrun clang++ -std=c++17 -arch x86_64 -O2 -Wall -Wextra -Werror -mmacosx-version-min=13.0 -I$HERE/kext \
  $HERE/tool/gpucontrol.cpp -framework IOKit -framework CoreFoundation -o $B/gpucontrol
codesign -f -s - -i com.droga.gpucontrol $B/gpucontrol 2>/dev/null

if [[ ${1:-} == tests ]]; then
  mkdir -p $B/tests
  xcrun clang++ -std=c++17 -arch x86_64 -O1 -g -Wall -Wextra -Werror -fsanitize=address,undefined \
    -fno-sanitize-recover=undefined -I$HERE/kext $HERE/tests/pmlogtest.cpp -o $B/tests/pmlogtest
  xcrun clang++ -std=c++17 -arch x86_64 -O1 -g -Wall -Wextra -Werror -fsanitize=address,undefined \
    -fno-sanitize-recover=undefined -I$HERE/kext $HERE/tests/controltest.cpp -o $B/tests/controltest
fi

KFLAGS=(-std=c++17 -target x86_64-apple-macos10.15 -fapple-kext -mkernel -nostdlib -nostdinc++
        -DMODULE_VERSION=$VERSION -DPRODUCT_NAME=$NAME -DLILU_CUSTOM_IOKIT_INIT
        -I$HERE/kext -isystem "$LILU/Contents/Resources" -I"$MKSDK/Headers"
        -Oz -flto=thin -fno-exceptions -fno-rtti -Wall -Wno-unused-parameter)
objs=()
for src in $HERE/kext/kern_start.cpp $HERE/kext/kern_pmlog.cpp $HERE/kext/kern_service.cpp \
           $HERE/kext/kern_control.cpp \
           "$LILU/Contents/Resources/Library/plugin_start.cpp"; do
  o=$OBJ/${src:t:r}.o
  xcrun clang++ $KFLAGS -c $src -o $o
  objs+=($o)
done
# A manual clang/ld build has to emit kmod_info itself, or the kext loads but never runs.
print -r -- '#include <mach/mach_types.h>
#include <mach/kmod.h>
extern kern_return_t '$NAME'_kern_start(kmod_info_t *, void *);
extern kern_return_t '$NAME'_kern_stop(kmod_info_t *, void *);
extern kern_return_t _start(kmod_info_t *, void *);
extern kern_return_t _stop(kmod_info_t *, void *);
KMOD_EXPLICIT_DECL(com.droga.'$NAME', "'$VERSION'", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = '$NAME'_kern_start;
__private_extern__ kmod_stop_func_t *_antimain = '$NAME'_kern_stop;' > $OBJ/kmod_info.c
xcrun clang -target x86_64-apple-macos10.15 -mkernel -nostdlib -I"$MKSDK/Headers" -Oz \
  -c $OBJ/kmod_info.c -o $OBJ/kmod_info.o
xcrun ld -kext -arch x86_64 -platform_version macos 10.15 10.15 -L"$MKSDK/Library/x86_64" -lkmod \
  $objs $OBJ/kmod_info.o -o $OUT/Contents/MacOS/$NAME
sed "s/__VERSION__/$VERSION/g" $HERE/kext/Info.plist > $OUT/Contents/Info.plist
plutil -lint -s $OUT/Contents/Info.plist
codesign -f -s - $OUT 2>/dev/null
[[ "$(nm $OUT/Contents/MacOS/$NAME)" == *' D _kmod_info'* ]] || { print "kmod_info missing"; exit 1; }
rm -rf $FINAL && mv $OUT $FINAL
print "built sensors/build/$NAME.kext ($VERSION), sensors/build/gpusensors and sensors/build/gpucontrol"
