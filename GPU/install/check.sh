#!/bin/zsh
# check.sh - one look at everything this repository installs, with one line per part and
# one line for the whole. Changes nothing and needs no sudo.
#
#   install/check.sh                 the summary
#   install/check.sh --full          also every check of every part
#   install/check.sh --json-dir DIR  also each part's 'check --json' answer, written to
#                                    DIR/<part>.json (decoders, loader, sensors, encoder)
#
# The parts are checked by their own tools (decoders.sh, loader.sh, sensors.sh,
# encoder.sh check); this script only runs them and puts their results together. Each part
# is looked at once: with --json-dir its JSON answer comes from the same look as its text
# (the RyzenStatus GPU app reads both), and the three that ask system_profiler for the
# graphics cards share one answer. The loader kext is only counted when this Mac needs it:
# with AMFIPass running or AMFI switched off, the decoders load without it.
#
# Exit status: 0 the decoders work now (the optional parts may still be missing); 2
# something must be done first (an install, a reboot or a fix), and the summary says what.
emulate -L zsh
setopt no_unset
SELF_DIR=${0:A:h}
source $SELF_DIR/common.zsh
usage() { print -u2 "usage: install/check.sh [--full] [--json-dir DIR]"; exit 64; }
FULL=0
JSON_DIR=""
while (( $# )); do
  case $1 in
    -h|--help) help_of "$SELF_DIR/check.sh"; exit 0 ;;
    --full) FULL=1 ;;
    # a folder of the caller's own, which it reads afterwards
    --json-dir) (( $# >= 2 )) && [[ -d $2 && ! -L $2 && -O $2 ]] || usage
                JSON_DIR=${2:A}
                shift ;;
    *) usage ;;
  esac
  shift
done

# One system_profiler answer for the parts that ask it (displays_report in common.zsh).
if (( EUID != 0 )); then
  GPU_CHECK_CACHE=$(/usr/bin/mktemp -d -t gpu-check) && export GPU_CHECK_CACHE
  trap '[[ -n ${GPU_CHECK_CACHE:-} ]] && /bin/rm -rf "$GPU_CHECK_CACHE"' EXIT
fi

# run <label> <script>: runs "<script> check", keeps its Result line and its exit status
# (and, with --json-dir, has it write its JSON answer to DIR/<label>.json).
typeset -A RESULT STATUS OUTPUT
run() {
  local label=$1 script=$2 out
  out=$(GPU_CHECK_JSON_TO=${JSON_DIR:+$JSON_DIR/$label.json} /bin/zsh $SELF_DIR/$script check 2>&1)
  STATUS[$label]=$?
  OUTPUT[$label]=$out
  RESULT[$label]=$(print -r -- "$out" | sed -n 's/^Result: //p' | tail -1)
  [[ -n ${RESULT[$label]} ]] || RESULT[$label]="(no result line$(pick "; run install/$script check" ""))"
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
  left+=("com.droga.vcnpreset, the encoder service's test version ($(pick "'sudo install/encoder.sh install'" "installing the encoding fix in this window") replaces it)")
for b in AV1VCNDecoder.bundle VP9VCNDecoder.bundle; do
  [[ -d /Library/Video/Plug-Ins/$b ]] &&
    left+=("/Library/Video/Plug-Ins/$b, which macOS ignores there ($(pick "'sudo install/decoders.sh install'" "installing the decoder plug-ins in this window") removes it)")
done
# The GPU sensors' commands, once the kext they go with is gone: not loaded and on no EFI
# partition. Said only when every EFI partition is mounted, so all of them were looked into
# (one that is not mounted may hold the kext, before its first boot).
gpu_tools_look
if (( ${#GPU_TOOLS_OURS} )) && [[ -z $(kext_version com.droga.GPUSensors) ]]; then
  all_mounted=1
  on_efi=0
  for id in $(efi_ids); do [[ $(efi_field $id Mounted) == Yes ]] || all_mounted=0; done
  for oc in /Volumes/*/EFI/OC(N); do [[ -e $oc/Kexts/GPUSensors.kext ]] && on_efi=1; done
  (( all_mounted && ! on_efi )) &&
    left+=("${(j:, :)GPU_TOOLS_OURS}: the GPU sensors' commands, without the kext they go with ($(pick "'sudo install/sensors.sh uninstall-tools'" "Remove all, or GPU sensors > Remove, in this window") removes them)")
fi
if (( ${#left} )); then
  print -r -- "Leftovers:"
  print -rl -- "  - "${^left}
fi
print

# The whole, in one line. The decoders count; the loader counts only when it is needed.
if (( STATUS[decoders] != 0 )); then
  # decoders.sh's own words: blocked, an unvalidated build (--force), or damaged plug-ins
  print -r -- "Overall: not ready for the decoders: ${RESULT[decoders]}$(pick " (details: install/decoders.sh check)" "")"
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
  print -r -- "Overall: ready$but. Install the decoders ($(pick "'sudo install/decoders.sh install'" "Decoder plug-ins > Install in this window")) and reboot."
fi
(( ${#warns} )) && print -rl -- "  - "${^warns}
exit $rc
