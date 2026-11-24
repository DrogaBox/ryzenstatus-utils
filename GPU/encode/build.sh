#!/bin/zsh
# build.sh - builds VCNEncodeFix (the VCNEncodeFloor kext, the vcnencodefix service and the vtenc test
# encoder), runs its tests and packages dist/VCNEncodeFix-<version>.zip.
#
# Needs the Command Line Tools and, for the kext, Lilu.kext (DEBUG build: it ships the plugin headers and
# plugin_start.cpp) and MacKernelSDK. tools/bootstrap.sh fetches pinned copies into deps/; to use your own,
# export LILU_KEXT and MACKERNELSDK. The EFI tests run on copies of OpenCore's Docs/Sample.plist
# (deps/OpenCore/Sample.plist, or OC_SAMPLE); they are skipped when it is missing. The last test only
# reports whether this Mac has the Apple files the service patches.
# CC_IMAGES (VideoProcessing copies taken out of a dyld shared cache, separated by spaces) adds those builds to
# the cc test.
#
# VERSION_OVERRIDE=<x.y.z> builds with another version string (used to compare a build with a released one).
#
# The kext carries its build date (Lilu's version string). It is taken from SOURCE_DATE_EPOCH, which
# defaults to the date of the last commit, so the same commit always gives the same kext.
emulate -L zsh
setopt err_exit no_unset pipe_fail
HERE=${0:A:h}
ROOT=${HERE:h}
cd $HERE
VERSION=${VERSION_OVERRIDE:-$(<VERSION)}
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || date +%s)}
LILU=${LILU_KEXT:-$ROOT/deps/Lilu.kext}
MKSDK=${MACKERNELSDK:-$ROOT/deps/MacKernelSDK}
[[ -f $LILU/Contents/Resources/Library/plugin_start.cpp && -f $MKSDK/Library/x86_64/libkmod.a ]] || {
  print "Lilu.kext (DEBUG) and MacKernelSDK not found: run tools/bootstrap.sh, or set LILU_KEXT and MACKERNELSDK"; exit 1; }
OC_SAMPLE=${OC_SAMPLE:-$ROOT/deps/OpenCore/Sample.plist}
B=build
rm -rf $B && mkdir -p $B/kext $B/obj

print "== kext (VCNEncodeFloor $VERSION)"
KX=$B/VCNEncodeFloor.kext
mkdir -p $KX/Contents/MacOS
KFLAGS=(-std=c++17 -target x86_64-apple-macos10.15 -fapple-kext -mkernel -nostdlib -nostdinc++
        -DMODULE_VERSION=$VERSION -DPRODUCT_NAME=VCNEncodeFloor
        -I"$LILU/Contents/Resources" -I"$MKSDK/Headers"
        -Oz -flto=thin -fno-exceptions -fno-rtti -Wall -Wno-unused-parameter)
xcrun clang++ $KFLAGS -c kext/kern_start.cpp -o $B/kext/kern_start.o
xcrun clang++ $KFLAGS -c "$LILU/Contents/Resources/Library/plugin_start.cpp" -o $B/kext/plugin_start.o 2>/dev/null
# A manual clang/ld build has to emit kmod_info itself, or the kext loads but never runs.
print -r -- '#include <mach/mach_types.h>
#include <mach/kmod.h>
extern kern_return_t VCNEncodeFloor_kern_start(kmod_info_t *, void *);
extern kern_return_t VCNEncodeFloor_kern_stop(kmod_info_t *, void *);
extern void VCNEncodeFloor_hevc10_stop(void);
extern kern_return_t _start(kmod_info_t *, void *);
extern kern_return_t _stop(kmod_info_t *, void *);
static kern_return_t VCNEncodeFloor_stop(kmod_info_t *ki, void *d) {
  VCNEncodeFloor_hevc10_stop();
  return VCNEncodeFloor_kern_stop(ki, d);
}
KMOD_EXPLICIT_DECL(com.droga.VCNEncodeFloor, "'$VERSION'", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = VCNEncodeFloor_kern_start;
__private_extern__ kmod_stop_func_t *_antimain = VCNEncodeFloor_stop;' > $B/kext/kmod_info.c
xcrun clang -target x86_64-apple-macos10.15 -fapple-kext -mkernel -nostdlib -I"$MKSDK/Headers" -Oz \
  -c $B/kext/kmod_info.c -o $B/kext/kmod_info.o
xcrun ld -kext -arch x86_64 -platform_version macos 10.15 10.15 -L"$MKSDK/Library/x86_64" -lkmod \
  $B/kext/kern_start.o $B/kext/plugin_start.o $B/kext/kmod_info.o -o $KX/Contents/MacOS/VCNEncodeFloor
sed "s/__VERSION__/$VERSION/g" kext/Info.plist > $KX/Contents/Info.plist
plutil -lint -s $KX/Contents/Info.plist
codesign -f -s - $KX 2>/dev/null
nm $KX/Contents/MacOS/VCNEncodeFloor | grep -q ' D _kmod_info' || { print "kmod_info missing"; exit 1; }

print "== vcnencodefix"
TFLAGS=(-arch x86_64 -mmacosx-version-min=14.0 -O2 -Wall -Wextra -Werror -fblocks "-DVERSION=\"$VERSION\"")
# install/ocentry.c is the editor of OpenCore's config.plist, shared with the loader kext.
xcrun clang $TFLAGS -I../install tool/vcnencodefix.c tool/patches.c tool/efi.c ../install/ocentry.c \
  -framework CoreFoundation -o $B/vcnencodefix
codesign -f -s - -i com.droga.vcnencodefix $B/vcnencodefix 2>/dev/null

print "== vtenc (test encoder)"
xcrun clang -arch x86_64 -mmacosx-version-min=14.0 -O2 -Wall -c vtenc/vtenc.c -o $B/obj/vtenc.o
xcrun clang -arch x86_64 -mmacosx-version-min=14.0 -O2 -Wall -fobjc-arc -c vtenc/gpusrc.m -o $B/obj/gpusrc.o
xcrun clang -arch x86_64 -mmacosx-version-min=14.0 $B/obj/vtenc.o $B/obj/gpusrc.o -o $B/vtenc -framework VideoToolbox \
  -framework CoreMedia -framework CoreVideo -framework CoreFoundation -framework IOSurface -framework Metal -framework Foundation
codesign -f -s - -i com.droga.vtenc $B/vtenc 2>/dev/null

print "== tests"
xcrun clang -arch x86_64 -O1 -g -Wall -Wextra -Werror -fsanitize=address,undefined -fno-sanitize-recover=undefined \
  tests/wide_test.c tests/run_block.s tool/patches.c -o $B/obj/wide_test
$B/obj/wide_test | tail -1
# CC_IMAGES: optional VideoProcessing copies (taken out of a dyld shared cache) whose sites are checked too
xcrun clang -arch x86_64 -O1 -g -Wall -Wextra -Werror -fsanitize=address,undefined -fno-sanitize-recover=undefined \
  tests/cc_test.c tests/run_cc.s tool/patches.c -framework VideoToolbox -framework CoreFoundation -o $B/obj/cc_test
$B/obj/cc_test ${=CC_IMAGES:-} | tail -1
# ftenc_test encodes on the GPU and needs a Mac Pro / iMac Pro board-id: built here, run by hand
xcrun clang -arch x86_64 -O1 -g -Wall -Wextra -Werror tests/ftenc_test.c tool/patches.c -framework VideoToolbox \
  -framework CoreMedia -framework CoreVideo -framework CoreFoundation -o $B/obj/ftenc_test
xcrun clang -arch x86_64 -O1 -g -Wall -Wextra -Werror -fblocks -fsanitize=address,undefined -fno-sanitize-recover=undefined \
  tests/hevc10_test.c tool/patches.c -o $B/obj/hevc10_test
$B/obj/hevc10_test | tail -1
xcrun clang++ -std=c++17 -arch x86_64 -O1 -g -Wall -Wextra -Werror -fsanitize=address,undefined tests/floor_test.cpp -o $B/obj/floor_test
$B/obj/floor_test | tail -1
xcrun clang++ -std=c++17 -arch x86_64 -O1 -g -Wall -Wextra -Werror -fsanitize=address,undefined tests/hevc10_gate_test.cpp -o $B/obj/hevc10_gate_test
$B/obj/hevc10_gate_test | tail -1
if [[ -f $OC_SAMPLE ]]; then zsh tests/efi_test.sh ${B:A}/vcnencodefix $OC_SAMPLE | tail -1
else print "skipping EFI tests: no OpenCore Sample.plist at $OC_SAMPLE"; fi
$B/vcnencodefix status > /dev/null && print "status: patches located on this system" || print "status: not every patch is available here"

print "== package"
# assembled under another name; it replaces the old package only when everything worked
FINALP=dist/VCNEncodeFix-$VERSION
P=dist/.VCNEncodeFix-$VERSION.new
rm -rf $P && mkdir -p $P/bin $P/Kexts $P/support
cp README.md CHANGELOG.md VERSION $P/
cp scripts/install.sh scripts/uninstall.sh scripts/doctor.sh scripts/test.sh $P/
chmod 755 $P/*.sh
cp $B/vcnencodefix $B/vtenc $P/bin/
ditto --norsrc --noextattr $KX $P/Kexts/VCNEncodeFloor.kext
cp launchd/com.droga.vcnencodefix.plist newsyslog/vcnencodefix.conf $P/support/
(cd $P && find . -type f ! -name SHA256SUMS | LC_ALL=C sort | xargs shasum -a 256 > SHA256SUMS)
xattr -cr $P
rm -rf $FINALP dist/VCNEncodeFix-$VERSION.zip
mv $P $FINALP
(cd dist && ditto -c -k --norsrc --noextattr --keepParent VCNEncodeFix-$VERSION VCNEncodeFix-$VERSION.zip)
print "built $FINALP and dist/VCNEncodeFix-$VERSION.zip ($(du -h dist/VCNEncodeFix-$VERSION.zip | cut -f1))"
