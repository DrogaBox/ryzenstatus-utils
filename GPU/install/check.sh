#!/bin/zsh
# check.sh - one look at everything this repository installs, with one line per part and
# one line for the whole. Changes nothing and needs no sudo.
#
#   install/check.sh            the summary
#   install/check.sh --full     also every check of every part
#
# The parts are checked by their own tools (decoders.sh, loader.sh, sensors.sh,
# encoder.sh check); this script only runs them and puts their results together. The
# loader kext is only counted when this Mac needs it: with AMFIPass running or AMFI
# switched off, the decoders load without it.
#
# Exit status: 0 the decoders work now (the optional parts may still be missing); 2
# something must be done first (an install, a reboot or a fix), and the summary says what.
emulate -L zsh
setopt no_unset
SELF_DIR=${0:A:h}
source $SELF_DIR/common.zsh
[[ ${1:-} == (-h|--help) ]] && { help_of "$SELF_DIR/check.sh"; exit 0; }
FULL=0
[[ ${1:-} == --full ]] && FULL=1
[[ $# -gt 1 || ( $# -eq 1 && $FULL -eq 0 ) ]] && { print -u2 "usage: install/check.sh [--full]"; exit 64; }

# run <label> <script>: runs "<script> check", keeps its Result line and its exit status.
typeset -A RESULT STATUS OUTPUT
run() {
  local label=$1 script=$2 out
  out=$(/bin/zsh $SELF_DIR/$script check 2>&1)
  STATUS[$label]=$?
  OUTPUT[$label]=$out
  RESULT[$label]=$(print -r -- "$out" | sed -n 's/^Result: //p' | tail -1)
  [[ -n ${RESULT[$label]} ]] || RESULT[$label]="(no result line; run install/$script check)"
  if (( FULL )); then
    print -r -- "== $label (install/$script check)"
    print -r -- "$out"
    print
  fi
}

run decoders decoders.sh
run loader loader.sh
run sensors sensors.sh
run encoder encoder.sh

# The loader kext is not needed when something else lets the plug-ins in: AMFI off,
# AMFIPass, or plug-ins signed by a certificate authority this Mac trusts,
# which decoders.sh's check reports after asking macOS.
loader_needed=1
why_not=""
if amfi_off; then loader_needed=0; why_not="AMFI is off"
elif amfipass_on; then loader_needed=0; why_not="AMFIPass is running"
elif [[ ${OUTPUT[decoders]} == *"macOS accepts the plug-ins: yes: their signature"* ]]; then
  loader_needed=0; why_not="the plug-ins are signed by a certificate authority this Mac trusts"
fi

print -r -- "Decoders:     ${RESULT[decoders]}"
if (( loader_needed )); then
  print -r -- "Loader kext:  ${RESULT[loader]}"
else
  print -r -- "Loader kext:  not needed on this Mac ($why_not)"
fi
print -r -- "GPU sensors:  ${RESULT[sensors]}   (optional)"
print -r -- "Encoding fix: ${RESULT[encoder]}   (optional)"

# Left over from older installers and test builds. None of them stops anything here; they
# are listed so they can be removed on purpose.
left=()
for oc in /Volumes/*/EFI/OC(N); do
  [[ -d $oc/Kexts/VCNVideoProfile.kext ]] &&
    left+=("VCNVideoProfile.kext in $oc/Kexts, a measurement kext of the old package (remove its Kernel > Add entry and the kext if you do not use it)")
done
[[ -e /Library/LaunchDaemons/com.droga.vcnpreset.plist ]] &&
  left+=("com.droga.vcnpreset, the encoder service's test version ('sudo install/encoder.sh install' replaces it)")
for b in AV1VCNDecoder.bundle VP9VCNDecoder.bundle; do
  [[ -d /Library/Video/Plug-Ins/$b ]] &&
    left+=("/Library/Video/Plug-Ins/$b, which macOS ignores there ('sudo install/decoders.sh install' removes it)")
done
if (( ${#left} )); then
  print -r -- "Leftovers:"
  print -rl -- "  - "${^left}
fi
print

# The whole, in one line. The decoders count; the loader counts only when it is needed.
if (( STATUS[decoders] != 0 )); then
  # decoders.sh's own words: blocked, an unvalidated build (--force), or damaged plug-ins
  print -r -- "Overall: not ready for the decoders: ${RESULT[decoders]} (details: install/decoders.sh check)"
  exit 2
fi
if (( loader_needed )) && [[ ${RESULT[loader]} != working:* && ${RESULT[loader]} != installed\ on* ]]; then
  print -r -- "Overall: this Mac needs the loader kext for Safari to use the decoders: ${RESULT[loader]}"
  exit 2
fi
# decoders.sh passes with a warning when only one codec works with this driver or the GPU is
# not a Navi 21; the overall line must not hide that.
warns=(${(f)"$(print -r -- "${OUTPUT[decoders]}" | sed -n 's/^  warn  //p')"})
but=""
(( ${#warns} )) && but=", with warnings"
rc=2
if [[ ${RESULT[decoders]} == installed* ]] && { (( ! loader_needed )) || [[ ${RESULT[loader]} == working:* ]]; }; then
  print -r -- "Overall: working$but. The decoders are installed and macOS lets Safari use them."
  rc=0
elif [[ ${RESULT[decoders]} == installed* ]]; then
  print -r -- "Overall: installed$but. Safari can use the decoders after the reboot that starts the loader kext."
else
  print -r -- "Overall: ready$but. Install the decoders ('sudo install/decoders.sh install') and reboot."
fi
(( ${#warns} )) && print -rl -- "  - "${^warns}
exit $rc
