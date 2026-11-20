#!/bin/zsh
# package.sh - puts what was built into one folder and one zip that someone can install from
# without compiling anything: dist/GPU-<date>-<commit>/ and the same as a .zip.
#
#   tools/package.sh                  build everything first (./build.sh), then package
#   tools/package.sh --no-build       package what is already built
#   tools/package.sh --payload DIR    only the parts, into DIR (a new folder): no app, no zip.
#                                     Tools/build-gpu-assets.sh at the top of RyzenStatus uses
#                                     it for the folder the installer app carries inside
#                                     (Contents/Resources/GPU)
#
# The package has the same layout as the repository, so the installers run from it
# unchanged (install/check.sh, install/decoders.sh, ...). It holds:
#   decode/build/   the two plug-ins, lvprobe, kextentry, VCNVTLoader.kext
#   sensors/build/  GPUSensors.kext, gpusensors and gpucontrol
#   encode/         VERSION and dist/VCNEncodeFix-<version> (its own package, with its scripts)
#   install/        the installers and the list of validated builds
#   tools/driver/kcfunc.py   used by install/sensors.sh
#   README, LICENSE, NOTICE, CHANGELOG, docs/status.md, the component READMEs
#   SHA256SUMS      of every file: cd into the package and run shasum -a 256 -c SHA256SUMS
#   BUILD-INFO.txt  the commit it was built from, its SOURCE_DATE_EPOCH and the versions
#   RyzenStatus GPU.app   the installer app, at the top (not with --payload)
#
# This folder lives inside the RyzenStatus repository, so "the commit" is the last one that
# changed this folder, and the build date (SOURCE_DATE_EPOCH, which the kexts carry) is that
# commit's date unless SOURCE_DATE_EPOCH is already set: a commit elsewhere in RyzenStatus
# changes neither. It refuses to package a folder with uncommitted changes, so a package
# always names the commit it came from. Nothing is installed and nothing leaves this Mac.
emulate -L zsh
setopt err_exit no_unset pipe_fail
ROOT=${0:A:h:h}
cd $ROOT
MODE=full
PAYLOAD=""
case ${1:-} in
  "") ;;
  --no-build) MODE=nobuild ;;
  --payload)
    (( $# >= 2 )) || { print "--payload needs a folder that does not exist yet"; exit 64; }
    MODE=payload
    PAYLOAD=${2:a} ;;
  *) print "usage: tools/package.sh [--no-build | --payload DIR]"; exit 64 ;;
esac
[[ -z "$(git status --porcelain -- .)" ]] || { print "this folder has uncommitted changes; commit first, so the package names its commit"; exit 1; }
commit=$(git log -1 --format=%H -- .)
[[ -n $commit ]] || { print "no commit has changed this folder yet"; exit 1; }
epoch_note=""
[[ $MODE == nobuild && -z ${SOURCE_DATE_EPOCH:-} ]] && epoch_note=" (assumed: --no-build packages what an earlier build made)"
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct -- .)}
APP_NAME="RyzenStatus GPU.app"
if [[ $MODE == full ]]; then
  ./build.sh > /dev/null && zsh installer/build.sh > /dev/null
fi
day=$(git log -1 --format=%cd --date=format:%Y%m%d -- .)
NAME=GPU-$day-${commit[1,9]}
OUT=dist/$NAME
[[ $MODE == payload ]] && OUT=$PAYLOAD
ENC=encode/dist/VCNEncodeFix-$(<encode/VERSION)
needed=(decode/build/AV1VCNDecoder.bundle decode/build/VP9VCNDecoder.bundle decode/build/lvprobe
        decode/build/kextentry decode/build/VCNVTLoader.kext sensors/build/GPUSensors.kext
        sensors/build/gpusensors sensors/build/gpucontrol $ENC)
[[ $MODE == payload ]] || needed+=("installer/build/$APP_NAME")
for f in $needed; do
  [[ -e $f ]] || { print "missing $f: build it first (./build.sh)"; exit 1; }
done
if [[ $MODE == payload ]]; then
  [[ ! -e $OUT ]] || { print "$OUT exists already; --payload writes a new folder"; exit 1; }
else
  rm -rf $OUT dist/$NAME.zip
fi
mkdir -p $OUT/decode/build $OUT/sensors/build $OUT/encode/dist $OUT/install $OUT/tools/driver $OUT/docs \
         $OUT/decode/loader
for f in AV1VCNDecoder.bundle VP9VCNDecoder.bundle lvprobe kextentry VCNVTLoader.kext; do
  ditto --norsrc --noextattr decode/build/$f $OUT/decode/build/$f
done
# gpucontrol: install/sensors.sh copies it to /usr/local/bin with gpusensors, for the app's
# GPU control page.
for f in GPUSensors.kext gpusensors gpucontrol; do ditto --norsrc --noextattr sensors/build/$f $OUT/sensors/build/$f; done
ditto --norsrc --noextattr $ENC $OUT/$ENC
cp encode/VERSION $OUT/encode/
# check_lists.sh compares against the decoders' sources, which the package does not hold
for f in install/*.sh install/*.zsh install/validated-builds.json install/README.md; do
  [[ $f == install/check_lists.sh ]] || cp $f $OUT/install/
done
cp tools/driver/kcfunc.py $OUT/tools/driver/
cp README.md LICENSE NOTICE.md CHANGELOG.md $OUT/
cp docs/status.md docs/how-it-works.md docs/macos-updates.md $OUT/docs/
cp decode/loader/README.md $OUT/decode/loader/
cp sensors/README.md $OUT/sensors/
bins=($OUT/decode/build/*.bundle/Contents/MacOS/* $OUT/decode/build/{lvprobe,kextentry}
      $OUT/decode/build/VCNVTLoader.kext/Contents/MacOS/* $OUT/sensors/build/GPUSensors.kext/Contents/MacOS/*
      $OUT/sensors/build/{gpusensors,gpucontrol} $OUT/$ENC/bin/* $OUT/$ENC/Kexts/*.kext/Contents/MacOS/*)
if [[ $MODE != payload ]]; then
  # The app looks for install/ in the folders above it, so it sits at the top of the package.
  ditto --norsrc --noextattr "installer/build/$APP_NAME" "$OUT/$APP_NAME"
  bins+=("$OUT/$APP_NAME"/Contents/MacOS/*)
fi
# Above all with --no-build: a DEBUG=1 build or one made elsewhere holds paths of the machine.
strs=$(strings -a $bins)
[[ $strs != *(/Users/|/var/folders/)* ]] || {
  print "a binary holds a path of this machine (a DEBUG=1 build?): rebuild with ./build.sh"; rm -rf $OUT; exit 1; }
{
  print -r -- "$NAME: built from commit $commit (the last commit that changed GPU/)"
  print -r -- "SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH$epoch_note"
  print -r -- "versions: GPU sensors $(<sensors/VERSION), encoding fix $(<encode/VERSION)"
} > $OUT/BUILD-INFO.txt
(cd $OUT && find . -type f ! -name SHA256SUMS -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 > SHA256SUMS)
xattr -cr $OUT
if [[ $MODE == payload ]]; then
  print "parts written to $OUT"
  exit 0
fi
(cd dist && ditto -c -k --norsrc --noextattr --keepParent $NAME $NAME.zip)
print "packaged $OUT and dist/$NAME.zip ($(du -h dist/$NAME.zip | cut -f1))"
