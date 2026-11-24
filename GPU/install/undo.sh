#!/bin/zsh
# undo.sh - takes off everything this repository installed, in a safe order, with one command.
#
#   install/undo.sh --dry-run            say what would be removed; changes nothing, no sudo
#   sudo install/undo.sh [--efi diskNsM] remove it all, after one confirmation; then reboot
#   sudo install/undo.sh --yes ...       the same without the question
#
# It only removes what it finds installed, each part with its own tool:
#   1. GPUSensors.kext from the EFI, and gpucontrol and gpusensors from /usr/local/bin
#                                             install/sensors.sh uninstall (when the kext is
#                                             gone already: install/sensors.sh uninstall-tools)
#   2. VCNVTLoader.kext from the EFI          install/loader.sh uninstall
#   3. the encoding fix (service, and its kext from the EFI)   install/encoder.sh uninstall --efi
#   4. the decoder plug-ins from the system volume (a new boot snapshot)   install/decoders.sh uninstall
# The EFI changes come first: each writes its own backup of config.plist. The decoders come
# last because their step makes a boot snapshot. Every step says what it did; the first one
# that fails stops the rest.
#
# --efi diskNsM names the EFI partition for steps 1 to 3. Without it, steps 1 and 2 find it
# as their tools do, and step 3 uses the one OpenCore started from, else the only EFI
# partition that holds OpenCore (as install.sh does), else the only mounted EFI partition
# that holds VCNEncodeFloor.kext.
#
# Exit status: 0 done, or nothing to remove; 1 a step failed (the ones before it are done);
# 64 wrong usage.
emulate -L zsh
setopt no_unset
SELF_DIR=${0:A:h}
ROOT=${SELF_DIR:h}
source $SELF_DIR/common.zsh
DRY=0
YES=0
EFI_ID=""
while (( $# )); do
  case $1 in
    --dry-run) DRY=1 ;;
    --yes) YES=1 ;;
    --efi) (( $# >= 2 )) || { print -ru2 -- "--efi needs a partition, for example disk0s1"; exit 64; }
           [[ $2 =~ '^disk[0-9]+s[0-9]+$' ]] || { print -ru2 -- "--efi takes a partition like disk0s1, not '$2'"; exit 64; }
           EFI_ID=$2; shift ;;
    -h|--help) help_of "$SELF_DIR/undo.sh"; exit 0 ;;
    *) print -u2 "undo.sh: unknown option '$1'"; exit 64 ;;
  esac
  shift
done
(( DRY )) || [[ $EUID -eq 0 ]] || { print -u2 "undo must run as root: sudo install/undo.sh (or --dry-run to look first)"; exit 1; }

# What is installed. The EFI parts are read from the kexts that are loaded and from every
# mounted OpenCore EFI; a kext that is on an EFI that is not mounted is found by its own
# uninstall when it mounts the partition, so it is listed as "maybe".
efi_has() { # kext-name
  local oc
  for oc in /Volumes/*/EFI/OC(N); do [[ -d $oc/Kexts/$1.kext ]] && return 0; done
  return 1
}
state() { # bundle-id kext-name -> yes | maybe | no
  local id
  if [[ -n $(kext_version $1) ]] || efi_has $2; then print yes; return; fi
  for id in $(efi_ids); do
    if [[ $(efi_field $id Mounted) != Yes ]]; then print "maybe (EFI $id is not mounted; its uninstall looks)"; return; fi
  done
  print no
}
sensors=$(state com.droga.GPUSensors GPUSensors)
loader=$(state com.droga.VCNVTLoader VCNVTLoader)
encoder=no
# the kext can be on a mounted EFI with the service gone and the kext not loaded
# (an earlier uninstall without --efi, or a boot with -vcnflooroff)
[[ -e /Library/LaunchDaemons/com.droga.vcnencodefix.plist || -n $(kext_version com.droga.VCNEncodeFloor) ]] ||
  efi_has VCNEncodeFloor && encoder=yes
decoders=no
for b in AV1VCNDecoder.bundle VP9VCNDecoder.bundle $LEGACY_BUNDLES; do
  [[ -d /System/Library/Video/Plug-Ins/$b ]] && decoders=yes
done
# gpucontrol and gpusensors in /usr/local/bin: only ours (signed with our identifiers) are
# removed; another program under one of those names stays, and is named.
gpu_tools_look
tools=no
(( ${#GPU_TOOLS_OURS} )) && tools=yes

print -r -- "Found:"
print -r -- "  GPU sensors kext   $sensors"
print -r -- "  GPU commands       $tools${GPU_TOOLS_OURS:+ (${(j:, :)GPU_TOOLS_OURS})}"
print -r -- "  loader kext        $loader"
print -r -- "  encoding fix       $encoder"
print -r -- "  decoder plug-ins   $decoders"
for f in $GPU_TOOLS_OTHER; do print -r -- "  (left alone: $f is not ours)"; done
[[ $sensors == no && $tools == no && $loader == no && $encoder == no && $decoders == no ]] && { print -r -- "Nothing to remove."; exit 0; }

efi_args=()
[[ -n $EFI_ID ]] && efi_args=(--efi $EFI_ID)
steps=()
# sensors.sh uninstall takes the commands off too; without the kext only they are left
if [[ $sensors != no ]]; then steps+=("install/sensors.sh uninstall${efi_args:+ ${efi_args[*]}}")
elif [[ $tools == yes ]]; then steps+=("install/sensors.sh uninstall-tools"); fi
[[ $loader != no ]] && steps+=("install/loader.sh uninstall${efi_args:+ ${efi_args[*]}}")
if [[ $encoder == yes ]]; then
  # The partition for the encoding fix's kext: the one given, the one OpenCore started from,
  # or the mounted EFI that holds VCNEncodeFloor.kext.
  enc_efi=$EFI_ID
  [[ -n $enc_efi ]] || enc_efi=$(efi_booted 2>/dev/null)
  # The same rule install.sh uses: the only EFI partition that holds OpenCore (mounted to
  # look if need be). Some OpenCore setups do not publish the boot path.
  if [[ -z $enc_efi ]] && efi_find_opencore 2>/dev/null; then enc_efi=$EFI_FOUND; fi
  # Never a guess: only an EFI-type partition (a rescue USB stick usually is not one), and
  # only when exactly one of them holds the kext. Otherwise the kext stays and the user is
  # told to name the partition.
  if [[ -z $enc_efi ]]; then
    local_cands=()
    for id in $(efi_ids); do
      [[ $(efi_field $id Mounted) == Yes ]] || continue
      mp=$(efi_field $id 'Mount Point')
      [[ -n $mp && -d $mp/EFI/OC/Kexts/VCNEncodeFloor.kext ]] && local_cands+=($id)
    done
    (( ${#local_cands} == 1 )) && enc_efi=$local_cands[1]
  fi
  if [[ -n $enc_efi ]]; then steps+=("install/encoder.sh uninstall --efi $enc_efi")
  else steps+=("install/encoder.sh uninstall"); fi
fi
[[ $decoders == yes ]] && steps+=("install/decoders.sh uninstall")

print
print -r -- "Steps, in this order:"
local_i=1
for s in $steps; do print -r -- "  $local_i. sudo $s"; local_i=$((local_i + 1)); done
if [[ $encoder == yes && -z ${enc_efi:-} ]]; then
  print -r -- "  (the encoding fix's kext stays on the EFI: it is not clear which EFI partition is"
  print -r -- "   yours; run again with --efi diskNsM to take it off too)"
fi
(( DRY )) && { print; print -r -- "Dry run: nothing was changed."; exit 0; }

if (( ! YES )); then
  print
  print -rn -- "Remove all of the above? Type yes: "
  read -r answer
  [[ $answer == yes ]] || { print -r -- "Nothing was changed."; exit 0; }
fi
for s in $steps; do
  print
  print -r -- "== $s"
  /bin/zsh $ROOT/${=s} || { print -r -u2 -- "This step failed; the steps after it were not run. The ones before it are done."; exit 1; }
done
print
print -r -- "Done. Reboot to finish: the kexts stay loaded and the decoders stay in use until then."
