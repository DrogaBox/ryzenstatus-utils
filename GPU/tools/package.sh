#!/bin/zsh
# package.sh - puts what was built into one folder and one zip that someone can install from
# without compiling anything: dist/GPU-<date>-<commit>/ and the same as a .zip.
#
#   tools/package.sh          build everything first (./build.sh), then package
#   tools/package.sh --no-build   package what is already built
#
# The package has the same layout as the repository, so the installers run from it
# unchanged (install/check.sh, install/decoders.sh, ...). It holds:
#   decode/build/   the two plug-ins, lvprobe, kextentry, VCNVTLoader.kext
#   sensors/build/  GPUSensors.kext and gpusensors
#   encode/         VERSION and dist/VCNEncodeFix-<version> (its own package, with its scripts)
#   install/        the installers and the list of validated builds
#   tools/driver/kcfunc.py   used by install/sensors.sh
#   README, LICENSE, NOTICE, CHANGELOG, docs/status.md, the component READMEs
#   SHA256SUMS      of every file: cd into the package and run shasum -a 256 -c SHA256SUMS
#   BUILD-INFO.txt  the commit it was built from
#
# It refuses to package a tree with uncommitted changes, so a package always names the
# commit it came from. Nothing is installed and nothing leaves this Mac.
emulate -L zsh
setopt err_exit no_unset pipe_fail
ROOT=${0:A:h:h}
cd $ROOT
[[ -z "$(git status --porcelain)" ]] || { print "the tree has uncommitted changes; commit first, so the package names its commit"; exit 1; }
[[ ${1:-} == --no-build ]] || { ./build.sh > /dev/null && zsh installer/build.sh > /dev/null; }
commit=$(git rev-parse --short HEAD)
day=$(git log -1 --format=%cd --date=format:%Y%m%d)
NAME=GPU-$day-$commit
OUT=dist/$NAME
ENC=encode/dist/VCNEncodeFix-$(<encode/VERSION)
for f in decode/build/AV1VCNDecoder.bundle decode/build/VP9VCNDecoder.bundle decode/build/lvprobe \
         decode/build/kextentry decode/build/VCNVTLoader.kext sensors/build/GPUSensors.kext \
         sensors/build/gpusensors $ENC "installer/build/DrogaBoxGPU Installer.app"; do
  [[ -e $f ]] || { print "missing $f: build it first (./build.sh)"; exit 1; }
done
rm -rf $OUT dist/$NAME.zip
mkdir -p $OUT/decode/build $OUT/sensors/build $OUT/encode/dist $OUT/install $OUT/tools/driver $OUT/docs \
         $OUT/decode/loader
for f in AV1VCNDecoder.bundle VP9VCNDecoder.bundle lvprobe kextentry VCNVTLoader.kext; do
  ditto --norsrc --noextattr decode/build/$f $OUT/decode/build/$f
done
for f in GPUSensors.kext gpusensors; do ditto --norsrc --noextattr sensors/build/$f $OUT/sensors/build/$f; done
ditto --norsrc --noextattr $ENC $OUT/$ENC
cp encode/VERSION $OUT/encode/
# check_lists.sh compares against the decoders' sources, which the package does not hold
for f in install/*.sh install/*.zsh install/validated-builds.json install/README.md; do
  [[ $f == install/check_lists.sh ]] || cp $f $OUT/install/
done
cp tools/driver/kcfunc.py $OUT/tools/driver/
cp README.md LICENSE NOTICE.md CHANGELOG.md $OUT/
cp docs/status.md docs/how-it-works.md docs/macos-updates.md $OUT/docs/
# The app looks for install/ in the folders above it, so it sits at the top of the package.
ditto --norsrc --noextattr "installer/build/DrogaBoxGPU Installer.app" "$OUT/DrogaBoxGPU Installer.app"
cp decode/loader/README.md $OUT/decode/loader/
cp sensors/README.md $OUT/sensors/
# Above all with --no-build: a DEBUG=1 build or one made elsewhere holds paths of the machine.
bins=($OUT/decode/build/*.bundle/Contents/MacOS/* $OUT/decode/build/{lvprobe,kextentry}
      $OUT/decode/build/VCNVTLoader.kext/Contents/MacOS/* $OUT/sensors/build/GPUSensors.kext/Contents/MacOS/*
      $OUT/sensors/build/gpusensors "$OUT/DrogaBoxGPU Installer.app"/Contents/MacOS/* $OUT/$ENC/bin/* $OUT/$ENC/Kexts/*.kext/Contents/MacOS/*)
strs=$(strings -a $bins)
[[ $strs != *(/Users/|/var/folders/)* ]] || {
  print "a binary holds a path of this machine (a DEBUG=1 build?): rebuild with ./build.sh"; rm -rf $OUT; exit 1; }
print -r -- "$NAME: built from commit $(git rev-parse HEAD)" > $OUT/BUILD-INFO.txt
(cd $OUT && find . -type f ! -name SHA256SUMS -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 > SHA256SUMS)
xattr -cr $OUT
(cd dist && ditto -c -k --norsrc --noextattr --keepParent $NAME $NAME.zip)
print "packaged $OUT and dist/$NAME.zip ($(du -h dist/$NAME.zip | cut -f1))"
