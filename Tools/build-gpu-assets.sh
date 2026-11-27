#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RyzenStatus

# Builds GPU/ on this Mac and writes ReleaseAssets/GPU-Package.zip: the parts the
# "RyzenStatus GPU" installer carries inside (Contents/Resources/GPU), with a SHA256SUMS of
# every file in it. Tools/make-dmg.sh never compiles any of this: it takes the committed zip,
# checks that its SHA256SUMS has the SHA-256 pinned there (GPU_PAYLOAD_SUMS_SHA256) and that
# every file matches SHA256SUMS, and puts it into the app. So CI builds the DMG without
# Lilu, MacKernelSDK or an AMD card.
#
#   Tools/build-gpu-assets.sh
#
# Then commit ReleaseAssets/GPU-Package.zip and, in the same commit, the new
# GPU_PAYLOAD_SUMS_SHA256 in Tools/make-dmg.sh (this script prints it). The zip itself is not
# pinned: ditto stores each file's modification time, so the same files give another zip.
# SHA256SUMS lists contents only, so the same build gives the same hash.
#
# Needs the Xcode Command Line Tools and the three pinned build dependencies in GPU/deps
# (Lilu 1.7.2 DEBUG, MacKernelSDK, OpenCore's Sample.plist); GPU/tools/bootstrap.sh fetches
# them when they are missing, and checks their hashes. Nothing else is downloaded.
#
# The build date the kexts carry (SOURCE_DATE_EPOCH) is the date of the last commit that
# changed GPU/, unless SOURCE_DATE_EPOCH is set: the same GPU/ gives the same bytes, whatever
# else changed in the repository.
#
# It installs nothing, loads nothing, never uses sudo and touches neither the GPU nor the EFI.
# Every check is a read: codesign --verify, kmutil libraries -p, strings, shasum.
emulate -L zsh
setopt err_exit no_unset pipe_fail
cd "${0:A:h:h}"
ROOT=$PWD
G=$ROOT/GPU
OUT=ReleaseAssets/GPU-Package.zip
STAGE=""
CHECK=""
cleanup() {
  [[ -n $STAGE ]] && rm -rf "$STAGE"
  [[ -n $CHECK ]] && rm -rf "$CHECK"
  return 0
}
trap cleanup EXIT
fail() { print -r -u2 -- "✗ $1"; exit 1; }

print "▸ GPU/ must be committed (BUILD-INFO.txt names its commit)"
dirty=$(git status --porcelain -- GPU)
[[ -z $dirty ]] || fail "GPU/ has uncommitted changes:"$'\n'"$dirty"
commit=$(git log -1 --format=%H -- GPU)
[[ -n $commit ]] || fail "no commit has changed GPU/"
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct -- GPU)}
print "  commit $commit, SOURCE_DATE_EPOCH $SOURCE_DATE_EPOCH ($(date -u -r $SOURCE_DATE_EPOCH '+%Y-%m-%d %H:%M UTC'))"

print "▸ Repository check (GPU/tools/check_clean.sh)"
zsh $G/tools/check_clean.sh > /dev/null || { zsh $G/tools/check_clean.sh; fail "GPU/ is not clean"; }

print "▸ Build dependencies"
if [[ ! -f $G/deps/Lilu.kext/Contents/Resources/Library/plugin_start.cpp ||
      ! -f $G/deps/MacKernelSDK/Library/x86_64/libkmod.a ||
      ! -f $G/deps/OpenCore/Sample.plist ]]; then
  zsh $G/tools/bootstrap.sh || fail "GPU/tools/bootstrap.sh failed"
fi
lilu_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $G/deps/Lilu.kext/Contents/Info.plist)
[[ $lilu_version == 1.7.2 ]] || fail "GPU/deps/Lilu.kext is $lilu_version, not the pinned 1.7.2"

print "▸ Building GPU/ (decoders, loader kext, GPU sensors, encoding fix with its tests)"
zsh $G/build.sh

print "▸ Every symbol the kexts import exists here (GPU/tools/kextlinks.sh)"
ENC=$G/encode/dist/VCNEncodeFix-$(cat $G/encode/VERSION)
KEXTS=($G/sensors/build/GPUSensors.kext $G/decode/build/VCNVTLoader.kext $ENC/Kexts/VCNEncodeFloor.kext)
# The JPEG plug-in and its kext ship only with VCNVT_JPEG_DECODER=1 (GPU/tools/package.sh).
JPEG=()
if [[ ${VCNVT_JPEG_DECODER:-0} == 1 ]]; then
  KEXTS+=($G/jpeg/build/VCNJpeg.kext)
  JPEG=($G/decode/build/JPEGVCNDecoder.bundle)
fi
zsh $G/tools/kextlinks.sh $KEXTS || fail "a kext imports a symbol this Mac's kernel and Lilu do not export"

print "▸ Signatures"
# The MPEG-2, VC-1 and MPEG-4 plug-ins ship only with VCNVT_LEGACY_DECODERS=1 (GPU/tools/package.sh).
LEGACY=()
[[ ${VCNVT_LEGACY_DECODERS:-0} == 1 ]] &&
  LEGACY=($G/decode/build/MPEG2VCNDecoder.bundle $G/decode/build/VC1VCNDecoder.bundle $G/decode/build/MPEG4VCNDecoder.bundle)
for signed in $G/decode/build/AV1VCNDecoder.bundle $G/decode/build/VP9VCNDecoder.bundle $LEGACY $JPEG \
              $G/decode/build/lvprobe $G/decode/build/kextentry $KEXTS \
              $G/sensors/build/gpusensors $G/sensors/build/gpucontrol $ENC/bin/vcnencodefix $ENC/bin/vtenc; do
  why=$(codesign --verify --deep --strict "$signed" 2>&1) ||
    fail "${signed#$ROOT/}: the signature does not verify (codesign: ${${why//$'\n'/; }:-no reason given})"
done
[[ $(codesign -dvv $G/decode/build/lvprobe 2>&1) == *library-validation* ]] \
  || fail "lvprobe is not signed with the library-validation flag"

print "▸ The parts (GPU/tools/package.sh --payload)"
STAGE=$(mktemp -d)
P=$STAGE/GPU
zsh $G/tools/package.sh --payload $P

print "▸ Shape of the parts"
links=$(find $P -type l)
[[ -z $links ]] || fail "links in the parts (a way out of the folder):"$'\n'"$links"
extra=$(find $P \( -name '*.dSYM' -o -name obj -o -name '*.o' -o -path "$P/install/*.c" -o -path "$P/install/*.h" \
             -o -name check_lists.sh -o -name .DS_Store \) -print)
[[ -z $extra ]] || fail "files that do not belong in the parts:"$'\n'"$extra"
top=$(cd $P && ls -A | LC_ALL=C sort | tr '\n' ' ')
want="BUILD-INFO.txt CHANGELOG.md LICENSE NOTICE.md README.md SHA256SUMS decode docs encode install"
(( ${#JPEG} )) && want+=" jpeg"
want+=" sensors tools "
[[ $top == "$want" ]] || fail "the top of the parts is '$top', expected '$want'"
for needed in install/install.sh install/check.sh install/decoders.sh install/loader.sh install/encoder.sh \
              install/sensors.sh install/undo.sh install/common.zsh install/efikext.zsh \
              install/validated-builds.json tools/driver/kcfunc.py decode/build/lvprobe decode/build/kextentry \
              decode/build/VCNVTLoader.kext/Contents/Info.plist sensors/build/GPUSensors.kext/Contents/Info.plist \
              sensors/build/gpusensors sensors/build/gpucontrol encode/VERSION \
              ${ENC#$G/}/Kexts/VCNEncodeFloor.kext/Contents/Info.plist ${ENC#$G/}/uninstall.sh; do
  [[ -e $P/$needed ]] || fail "the parts have no $needed"
done
# The installer app accepts a folder as its parts only when this one can be run.
[[ -x $P/install/decoders.sh ]] || fail "install/decoders.sh is not executable in the parts"
for script in $P/install/*.sh $P/install/*.zsh; do
  zsh -n $script || fail "${script#$P/} does not parse"
done

print "▸ Nothing of this Mac in the parts"
# Text and binaries alike: a home folder, a temporary folder, the private work cache, a
# link to a private repository (GPUFolderTests checks the text files of GPU/ for the
# private names). Then the private patterns kept outside the repository, if any (see
# GPU/tools/check_clean.sh); they are only counted, never printed.
rules=('/Users/[A-Za-z0-9._-]' '/var/folders/' 're_cache' 'github\.com/DrogaBox/DrogaBox')
found=0
for rule in $rules; do
  hits=$(grep -r -a -l -E -- "$rule" $P || true)
  [[ -z $hits ]] || { found=1; print -r -u2 -- "  '$rule' in: ${hits//$P\//}"; }
done
PRIVATE=${DROGABOX_FORBIDDEN_PATTERNS:-$HOME/.config/drogabox/forbidden-patterns.txt}
private_rules=()
if [[ -f $PRIVATE ]]; then
  private_rules=(${(f)"$(grep -v -E '^[[:space:]]*(#|$)' $PRIVATE)"})
else
  print "  note: no private pattern file; only the built-in rules were applied"
fi
for (( i = 1; i <= ${#private_rules}; i++ )); do
  hits=$(grep -r -a -l -i -E -- "${private_rules[i]}" $P || true)
  [[ -z $hits ]] || { found=1; print -r -u2 -- "  private pattern number $i in: ${hits//$P\//}"; }
done
(( ! found )) || fail "the parts hold something of this Mac or of the private repositories"

print "▸ SHA256SUMS"
(cd $P && shasum -a 256 -c -s SHA256SUMS) || fail "the parts do not match their SHA256SUMS"
listed=$(cd $P && awk '{ sub(/^[0-9a-f]+  /, ""); print }' SHA256SUMS | LC_ALL=C sort)
present=$(cd $P && find . -type f ! -path ./SHA256SUMS | LC_ALL=C sort)
[[ $listed == "$present" ]] || fail "SHA256SUMS does not list exactly the files of the parts"

print "▸ Zip"
mkdir -p ReleaseAssets
(cd $STAGE && ditto -c -k --norsrc --noextattr --keepParent GPU GPU-Package.zip)
CHECK=$(mktemp -d)
ditto -x -k $STAGE/GPU-Package.zip $CHECK
roots=$(cd $CHECK && ls -A)
[[ $roots == GPU ]] || fail "the zip must hold exactly one folder, GPU/, at its top; it holds: $roots"
(cd $CHECK/GPU && shasum -a 256 -c -s SHA256SUMS) || fail "the zip, unpacked, does not match SHA256SUMS"
cmp -s $P/SHA256SUMS $CHECK/GPU/SHA256SUMS || fail "the zip's SHA256SUMS is not the one written"
[[ -x $CHECK/GPU/install/decoders.sh ]] || fail "the zip lost the executable bit of install/decoders.sh"
mv -f $STAGE/GPU-Package.zip $OUT

sums=$(shasum -a 256 $P/SHA256SUMS | awk '{print $1}')
# The brace group's true takes the status out of the pipeline: strings dies of
# the SIGPIPE once grep -m1 has its match, and pipe_fail would fail the
# pipeline despite it, printing "?" for a marker that was read fine.
sensors_info=$( { strings -a "$P/sensors/build/GPUSensors.kext/Contents/MacOS/GPUSensors"; true; } \
               | grep -m1 -E '^REL-' || print "?")
print
print "GPU-Package: GPU sensors $(cat $G/sensors/VERSION) ($sensors_info), encoding fix $(cat $G/encode/VERSION)"
print "commit $commit, SOURCE_DATE_EPOCH $SOURCE_DATE_EPOCH"
print "$OUT  $(stat -f %z $OUT) bytes, $(awk 'END {print NR}' $P/SHA256SUMS) files"
print "SHA-256 of its SHA256SUMS: $sums"
print
print "Put it in Tools/make-dmg.sh and commit both together:"
print "  GPU_PAYLOAD_SUMS_SHA256=\"$sums\""
