#!/bin/zsh
# install.sh - looks at this Mac, decides what it needs, says why, and installs it in the
# right order with one command. Every part keeps its own tool (decoders.sh, loader.sh,
# encoder.sh, sensors.sh); this one only decides and runs them.
#
#   install/install.sh plan [--with-encoder] [--with-sensors]    what it would do, and why;
#                                                                changes nothing, no sudo
#   sudo install/install.sh [--with-encoder] [--with-sensors] [--efi diskNsM]
#   install/install.sh --help
#
#   --with-jpeg             the JPEG decoder: VCNJpeg.kext on the EFI and the JPEG plug-in with
#                           the decoders (the same as VCNVT_JPEG_DECODER=1 for decoders.sh).
#                           Off by default; macOS 26.7.3 (25G342) only.
#   --with-legacy-decoders  the MPEG-2, VC-1 and MPEG-4 plug-ins too, with AV1 and VP9 (the
#                           same as VCNVT_LEGACY_DECODERS=1). Off by default: they have not
#                           run through VideoToolbox on a GPU yet. Without it, the three
#                           are taken off if an earlier run with it left them.
#
# What it decides:
#   decoders   always (the AV1 and VP9 plug-ins); skipped when the ones installed are
#              already these, or when these were put in the boot snapshot earlier in this
#              boot and load at the next one
#   loader     VCNVTLoader.kext on the EFI, only when nothing else lets the plug-ins in:
#              not with AMFI switched off or AMFIPass running
#   encoder    the encoding fix (service and kext), only with --with-encoder
#   jpeg       VCNJpeg.kext, only with --with-jpeg (the decoders then take the JPEG plug-in)
#   sensors    GPUSensors.kext, only with --with-sensors; when the kext that runs is already
#              this one, only the commands gpucontrol and gpusensors are copied to
#              /usr/local/bin, if they are missing there or differ from these
# Everything is checked before the first change. When one part cannot be installed on this
# Mac (macOS build not validated, card not supported, Lilu missing, ...), nothing is
# installed and the reason is printed, so a run never stops half way because of a check.
#
# One check may wait for a step of the same run: when the decoders' only failed check is
# that nothing lets them into Safari, or that the loader kext running lists other plug-ins,
# and the loader kext is a step of this run, the decoders are installed right after it.
# decoders.sh checks again then, finds the new kext on the EFI and goes ahead; the decoders
# load after the reboot. Every other check still has to pass before the first change.
#
# The EFI partition: --efi names it; without it, the one OpenCore says it started from, else
# the only EFI partition that holds OpenCore. All parts use the same one. The plan looks
# too, without mounting anything: when more than one mounted EFI partition holds OpenCore
# (and OpenCore does not say which one it started from), it is blocked and says what to do,
# before any password. A partition that is not mounted is looked into only by the install.
#
# A step that fails stops the rest; the steps before it stay done, and
# 'sudo install/undo.sh' takes everything off. A loader kext put on the EFI just before the
# decoders stays there when they fail: it lets in only these plug-ins, the next run needs it,
# and taking it off would be one more change to the EFI. Nothing takes effect until the
# reboot, except the commands in /usr/local/bin.
#
# Exit status: 0 done, or plan printed; 1 a step failed; 2 something this Mac needs cannot
# be installed (nothing was changed); 64 wrong usage.
emulate -L zsh
setopt no_unset

SELF_DIR=${0:A:h}
source $SELF_DIR/common.zsh

usage_error() {
  print -r -u2 -- "install.sh: $1"
  print -r -u2 -- "usage: install.sh [plan] [--with-encoder] [--with-sensors] [--with-jpeg] [--with-legacy-decoders] [--efi diskNsM]"
  exit 64
}

PLAN=0
WITH_ENCODER=0
WITH_SENSORS=0
WITH_JPEG=0
EFI_ID=""
while (( $# )); do
  case $1 in
    plan) PLAN=1 ;;
    --with-encoder) WITH_ENCODER=1 ;;
    --with-sensors) WITH_SENSORS=1 ;;
    # decoders.sh and loader.sh read VCNVT_JPEG_DECODER (common.zsh, jpeg_on)
    --with-jpeg) WITH_JPEG=1; export VCNVT_JPEG_DECODER=1 ;;
    # decoders.sh and loader.sh read it (common.zsh, legacy_on)
    --with-legacy-decoders) export VCNVT_LEGACY_DECODERS=1 ;;
    --efi)
      (( $# >= 2 )) && [[ $2 =~ '^disk[0-9]+s[0-9]+$' ]] || usage_error "--efi needs a partition, for example disk0s1"
      EFI_ID=$2
      shift ;;
    -h|--help|help) help_of "$SELF_DIR/install.sh"; exit 0 ;;
    *) usage_error "unknown option '$1'" ;;
  esac
  shift
done
(( PLAN )) && [[ -n $EFI_ID ]] && usage_error "plan does not use --efi"
# For tests only (tests/install_plan.sh), and only with plan: a folder that stands in for
# this Mac, with <part>.json (the part's 'check --json' answer), <part>.txt (its text check)
# and amfi (one word: off, pass or on).
FAKE=${GPU_INSTALL_PLAN_FAKE:-}
[[ -n $FAKE ]] && (( ! PLAN )) && usage_error "GPU_INSTALL_PLAN_FAKE goes with plan only"
(( PLAN )) || [[ $EUID -eq 0 ]] || { print -r -u2 -- "run it with sudo, or 'install/install.sh plan' to see what it would do"; exit 1; }

# One field of a 'check --json' answer, for example: jfield decoders canInstall
typeset -A JSON
jfield() { # part key
  print -r -- "${JSON[$1]}" | /usr/bin/plutil -extract "$2" raw -o - - 2>/dev/null
}
# The failed checks of a part, one per line, from its text check.
failed_checks() { # part
  if [[ -n $FAKE ]]; then cat "$FAKE/$1.txt" 2>/dev/null; else /bin/zsh "$SELF_DIR/$1.sh" check 2>/dev/null; fi |
    grep -E '^ *(FAIL|fail)|: (FAIL|fail)' | sed 's/^ */    /'
}
plan_amfi_off()     { if [[ -n $FAKE ]]; then [[ $(<$FAKE/amfi) == off ]];  else amfi_off; fi; }
plan_amfipass_on()  { if [[ -n $FAKE ]]; then [[ $(<$FAKE/amfi) == pass ]]; else amfipass_on; fi; }

# ---- decide ------------------------------------------------------------------------------
typeset -a STEPS=() SKIPS=() BLOCKS=()
look() { # part
  if [[ -n $FAKE ]]; then
    JSON[$1]=$(cat "$FAKE/$1.json" 2>/dev/null)
  else
    JSON[$1]=$(/bin/zsh "$SELF_DIR/$1.sh" check --json 2>/dev/null)
  fi
  [[ -n ${JSON[$1]} ]]
}
block() { # part reason
  BLOCKS+=("$1: $2")
}

print -r -- "Looking at this Mac..."
print -r -- "  macOS $(/usr/bin/sw_vers -productVersion) ($(/usr/bin/sw_vers -buildVersion))"

# decoders
# WAIT_LOADER: the decoders' one failed check is that nothing lets them into Safari, or that
# the loader kext running now lists other plug-ins: the way out is the loader kext. Decided
# after the loader, below.
WAIT_LOADER=0
dec_failed=""
# The plug-ins that run now are these, and no removal of this boot waits for the reboot
# (decoders.sh reads its install record for "pending"; "installed" is the running system).
dec_current() {
  [[ $(jfield decoders installed) == current && $(jfield decoders pending) != remove ]]
}
if ! look decoders; then
  block decoders "its check did not answer"
elif [[ $(jfield decoders pending) == install ]]; then
  # installed earlier in this boot: the running system keeps the old ones until the reboot,
  # so neither its checks nor what it runs say anything about these
  SKIPS+=("decoders: these plug-ins are in the boot snapshot already; they load at the next boot")
elif [[ $(jfield decoders canInstall) != true ]]; then
  dec_failed=$(failed_checks decoders)
  dec_lines=(${(f)dec_failed})
  if [[ ${#dec_lines} -eq 1 && $dec_failed == *"macOS accepts the plug-ins: no: "(VCNVTLoader is running but was built for other plug-ins|nothing on this Mac lets them into Safari)* ]]; then
    WAIT_LOADER=1
  else
    block decoders "this Mac is not ready for them:"$'\n'"$dec_failed"
  fi
elif dec_current; then
  SKIPS+=("decoders: the plug-ins installed are already these")
else
  STEPS+=(decoders)
fi

# loader: only when nothing else lets the plug-ins in
if plan_amfi_off; then
  SKIPS+=("loader kext: not needed, AMFI is switched off")
elif plan_amfipass_on; then
  SKIPS+=("loader kext: not needed, AMFIPass is running")
elif ! look loader; then
  block loader "its check did not answer"
elif [[ $(jfield loader result) == working* ]]; then
  SKIPS+=("loader kext: already on the EFI, running, and it lets these plug-ins in")
elif [[ $(jfield loader pendingReboot) == true ]]; then
  SKIPS+=("loader kext: the right one is on the EFI already; it starts at the next boot")
elif [[ $(jfield loader canInstall) != true ]]; then
  block loader "it is needed here (no AMFIPass, AMFI on) but cannot be installed:"$'\n'"$(failed_checks loader)"
else
  STEPS+=(loader)
fi

# The decoders that wait only for the loader kext go in right after it, in this run, when it
# is a step of this run. decoders.sh install checks again as root after the loader step: it
# finds the new kext on the EFI ("after a reboot from that EFI") and goes ahead. Otherwise
# (the loader is blocked, or not a step) they stay blocked with their own reason.
DEC_AFTER_LOADER=0
if (( WAIT_LOADER )); then
  if (( ! ${STEPS[(Ie)loader]} )); then
    block decoders "this Mac is not ready for them:"$'\n'"$dec_failed"
  elif dec_current; then
    SKIPS+=("decoders: the plug-ins installed are already these; the loader kext lets them in after the reboot")
  else
    STEPS+=(decoders)
    DEC_AFTER_LOADER=1
  fi
fi

# True when an optional part is installed, current and running.
in_place() { # part
  case $1 in
    # what encoder.sh check calls "installed and working": the service is the package's and
    # runs, the kext that runs is the package's version and active, and no mounted EFI holds
    # another build of the kext or an old entry for it (the next boot would load that one)
    encoder) [[ $(jfield encoder installed) == current && $(jfield encoder service) == running &&
                $(jfield encoder kext) == "loaded $(jfield encoder version), active"* &&
                ${JSON[encoder]} != *'"kext":"outdated"'* && ${JSON[encoder]} != *'"entry":"old"'* ]] ;;
    # working, and the version that runs is the one here (an older one gets updated)
    sensors) [[ $(jfield sensors result) == working* && $(jfield sensors running) == "loaded $(jfield sensors version),"* ]] ;;
    # working, the version here, and listed in the config.plist this run installs to: a
    # kext started by another config file (one picked in OpenCore for one boot) is not
    # loaded by the next normal boot
    jpeg)    [[ $(jfield jpeg result) == working* && $(jfield jpeg running) == "loaded $(jfield jpeg version),"* ]] &&
               jpeg_listed_on_target ;;
    *) return 1 ;;
  esac
}

# The EFI partition this run installs to, as far as can be told before the password and
# without mounting anything: --efi, else the one efi_guess finds (common.zsh). Empty when
# the install decides it later. The stand-in Mac of the tests says it in $FAKE/efi, as in
# the plan's EFI line below (disk9s9 when found).
target_efi() {
  if [[ -n $EFI_ID ]]; then print -r -- $EFI_ID; return; fi
  if [[ -n $FAKE ]]; then
    local g=$(cat "$FAKE/efi" 2>/dev/null)
    [[ ${g:-found} == found ]] && print -r -- disk9s9
    return 0
  fi
  efi_guess
  [[ $EFI_GUESS == found ]] && print -r -- $EFI_GUESS_ID
  return 0
}
# True when jpeg.sh check saw that partition mounted, with the kext entry in its
# config.plist as expected and this build of the kext there. When the partition is not
# known yet, or not mounted now, that is not known either: the install step looks then (it
# changes nothing that is already in place).
jpeg_listed_on_target() {
  local target=$(target_efi) n i
  [[ -n $target ]] || return 1
  n=$(jfield jpeg efis)
  [[ $n == <-> ]] || return 1
  for (( i = 0; i < n; i++ )); do
    [[ $(jfield jpeg efis.$i.id) == $target ]] || continue
    [[ $(jfield jpeg efis.$i.mounted) == true && $(jfield jpeg efis.$i.entry) == ok &&
       $(jfield jpeg efis.$i.kext) == current ]]
    return
  done
  return 1
}

# The commands gpucontrol and gpusensors, when the sensors kext needs nothing: copied when
# they are missing from /usr/local/bin or differ from the ones here. A sensors install copies
# them too, so this is a step of its own only when the kext is in place.
plan_tools() {
  case $(jfield sensors tools) in
    missing|outdated) STEPS+=(tools) ;;
    blocked) SKIPS+=("gpucontrol and gpusensors: something else is in their place in /usr/local/bin, so they are left alone ($(pick "install/sensors.sh check" "GPU sensors in this window") says what)") ;;
  esac
}

# the optional parts, only when asked for
for part flag in encoder $WITH_ENCODER sensors $WITH_SENSORS jpeg $WITH_JPEG; do
  (( flag )) || { SKIPS+=("$part: not asked for (--with-$part)"); continue; }
  if ! look $part; then
    block $part "its check did not answer"
  elif in_place $part || [[ $part == sensors && $(jfield sensors toolsOnly) == true ]]; then
    SKIPS+=("$part: already installed and running, the same version")
    [[ $part == sensors ]] && plan_tools
  elif [[ $part == sensors && $(jfield sensors pendingReboot) == true ]]; then
    # this version is on the EFI; the commands are copied after the reboot, when it runs
    SKIPS+=("sensors: this version is on the EFI already; it loads at the next boot")
  elif [[ $part == jpeg && $(jfield jpeg pendingReboot) == true ]]; then
    SKIPS+=("jpeg: this version is on the EFI already; it loads at the next boot")
  elif [[ $(jfield $part canInstall) != true ]]; then
    block $part "it cannot be installed on this Mac:"$'\n'"$(failed_checks $part)"
  else
    STEPS+=($part)
  fi
done

# the loader goes first, so the plug-ins it lists are on disk only when it is
typeset -a ORDER=()
for part in loader decoders encoder sensors jpeg tools; do
  (( ${STEPS[(Ie)$part]} )) && ORDER+=($part)
done
# how a step is named in the closing lines
step_name() { [[ $1 == tools ]] && print -rn -- "gpucontrol and gpusensors" || print -rn -- "$1"; }
# the options of this run, for a Terminal line in a message
RUN_FLAGS=install.sh
(( WITH_ENCODER )) && RUN_FLAGS+=" --with-encoder"
(( WITH_SENSORS )) && RUN_FLAGS+=" --with-sensors"
(( WITH_JPEG )) && RUN_FLAGS+=" --with-jpeg"
needs_efi() { (( ${ORDER[(Ie)loader]} || ${ORDER[(Ie)encoder]} || ${ORDER[(Ie)sensors]} || ${ORDER[(Ie)jpeg]} )); }

# The EFI partition the kexts go on, as far as a plan can tell without the password (it
# mounts nothing; see efi_guess in common.zsh). When an install would stop at it, the plan
# says so now, with what to do. The stand-in Mac of the tests says it in $FAKE/efi:
# found, open, ambiguous, foreign or none (found when the file is missing).
EFI_LINE=""
if (( PLAN )) && needs_efi; then
  if [[ -n $FAKE ]]; then
    EFI_GUESS=$(cat "$FAKE/efi" 2>/dev/null)
    EFI_GUESS=${EFI_GUESS:-found}
    EFI_GUESS_ID=disk9s9
    EFI_GUESS_WHY="the made-up Mac's answer ($EFI_GUESS)"
  else
    efi_guess
  fi
  case $EFI_GUESS in
    found) EFI_LINE="EFI partition: $EFI_GUESS_ID ($EFI_GUESS_WHY)." ;;
    open)  EFI_LINE="EFI partition: chosen when installing. $EFI_GUESS_WHY." ;;
    *)     block "EFI partition" "the install cannot tell which one to use: $EFI_GUESS_WHY."$'\n'"    $(efi_choice_help $EFI_GUESS "$RUN_FLAGS")" ;;
  esac
fi

print
if (( ${#BLOCKS} )); then
  print -r -- "Nothing was installed. This Mac cannot take everything asked for:"
  for b in $BLOCKS; do print -r -- "  $b"; done
  (( ${#SKIPS} )) && { print -r -- "Also:"; for s in $SKIPS; do print -r -- "  $s"; done; }
  exit 2
fi
print -r -- "Plan:"
for part in $ORDER; do
  case $part in
    decoders)
      if (( DEC_AFTER_LOADER )); then
        print -r -- "  install the decoder plug-ins right after the loader kext: their check waits only for it (needs a reboot)"
      else
        print -r -- "  install the decoder plug-ins (needs a reboot)"
      fi ;;
    loader)   print -r -- "  put VCNVTLoader.kext on the EFI: no AMFIPass here and AMFI is on, so it lets the plug-ins in" ;;
    encoder)  print -r -- "  install the encoding fix: the service now, its kext on the EFI" ;;
    sensors)  print -r -- "  put GPUSensors.kext on the EFI (it copies gpucontrol and gpusensors to /usr/local/bin too)" ;;
    jpeg)     print -r -- "  put VCNJpeg.kext on the EFI: JPEG and Motion JPEG on the GPU (needs a reboot)" ;;
    tools)    print -r -- "  copy gpucontrol and gpusensors to /usr/local/bin: the GPU sensors kext is already this one (no reboot needed)" ;;
  esac
done
for s in $SKIPS; do print -r -- "  skip $s"; done
if (( ! ${#ORDER} )); then
  print -r -- "Nothing to install: everything asked for is already in place."
  exit 0
fi
[[ -n $EFI_LINE ]] && print -r -- "$EFI_LINE"
(( PLAN )) && exit 0

# ---- the EFI, once for every part that needs it ----------------------------------------------
trap '[[ -n $OPEN_ID ]] && efi_close "$OPEN_ID"' EXIT
if needs_efi && [[ -z $EFI_ID ]]; then
  if efi_find_opencore; then
    EFI_ID=$EFI_FOUND
    print -r -- "EFI: $EFI_ID ($EFI_FIND_WHY)."
  else
    print -r -u2 -- "Cannot tell which EFI partition to use: $EFI_FIND_WHY."
    print -r -u2 -- "Nothing was installed."
    print -r -u2 -- "$(efi_choice_help $EFI_FIND_KIND "$RUN_FLAGS")"
    exit 2
  fi
fi

# ---- install ---------------------------------------------------------------------------------
typeset -a DONE=()
for part in $ORDER; do
  print
  print -r -- "== $(step_name $part)"
  case $part in
    decoders) /bin/zsh "$SELF_DIR/decoders.sh" install ;;
    # When the decoders are the next step of this run, loader.sh leaves out its note on the
    # plug-ins installed now: they are replaced before the run ends.
    loader)   GPU_INSTALL_DECODERS_NEXT=$(( ${ORDER[(Ie)decoders]} > ${ORDER[(Ie)loader]} ? 1 : 0 )) \
                /bin/zsh "$SELF_DIR/loader.sh" install --efi "$EFI_ID" ;;
    encoder)  /bin/zsh "$SELF_DIR/encoder.sh" install --efi "$EFI_ID" ;;
    sensors)  /bin/zsh "$SELF_DIR/sensors.sh" install --efi "$EFI_ID" ;;
    jpeg)     /bin/zsh "$SELF_DIR/jpeg.sh" install --efi "$EFI_ID" ;;
    tools)    /bin/zsh "$SELF_DIR/sensors.sh" tools ;;
  esac
  rc=$?
  if (( rc )); then
    print
    print -r -u2 -- "Stopped: $(step_name $part) failed (exit $rc, see above)."
    if [[ $part == decoders ]] && (( DEC_AFTER_LOADER )); then
      print -r -u2 -- "The loader kext is on the EFI and starts at the next boot. Reboot, then $(pick "run 'sudo install/install.sh' again" "open RyzenStatus GPU and use Install what this Mac needs again"): the decoders go in then."
    fi
    # spell 'tools' out element-wise: a substitution inside the join operates on the joined
    # string and would only match a DONE of exactly one element
    done_names=()
    for done_p in $DONE; do [[ $done_p == tools ]] && done_p="gpucontrol and gpusensors"; done_names+=($done_p); done
    (( ${#DONE} )) && print -r -u2 -- "Done before it: ${(j:, :)done_names}. $(pick "'sudo install/undo.sh'" "Remove all in this window") takes everything off."
    exit 1
  fi
  DONE+=($part)
done

print
print -r -- "== check"
/bin/zsh "$SELF_DIR/check.sh" || true
print
done_names=()
for done_p in $DONE; do [[ $done_p == tools ]] && done_p="gpucontrol and gpusensors"; done_names+=($done_p); done
if [[ ${(j: :)DONE} == tools ]]; then
  print -r -- "Installed: $done_names, in /usr/local/bin. They work now; no reboot needed."
else
  print -r -- "Installed: $done_names. Reboot for it to take effect, then $(pick "run install/check.sh" "open RyzenStatus GPU again to check it")."
  if (( DEC_AFTER_LOADER )); then
    print -r -- "The decoders load at that reboot, when the loader kext starts with it."
  fi
fi
exit 0
