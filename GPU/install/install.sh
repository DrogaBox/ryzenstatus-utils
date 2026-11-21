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
# What it decides:
#   decoders   always (the AV1 and VP9 plug-ins); skipped when the ones installed are
#              already these
#   loader     VCNVTLoader.kext on the EFI, only when nothing else lets the plug-ins in:
#              not with AMFI switched off or AMFIPass running
#   encoder    the encoding fix (service and kext), only with --with-encoder
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
# the only EFI partition that holds OpenCore. All parts use the same one.
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
  print -r -u2 -- "usage: install.sh [plan] [--with-encoder] [--with-sensors] [--efi diskNsM]"
  exit 64
}

PLAN=0
WITH_ENCODER=0
WITH_SENSORS=0
EFI_ID=""
while (( $# )); do
  case $1 in
    plan) PLAN=1 ;;
    --with-encoder) WITH_ENCODER=1 ;;
    --with-sensors) WITH_SENSORS=1 ;;
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
if ! look decoders; then
  block decoders "its check did not answer"
elif [[ $(jfield decoders canInstall) != true ]]; then
  dec_failed=$(failed_checks decoders)
  dec_lines=(${(f)dec_failed})
  if [[ ${#dec_lines} -eq 1 && $dec_failed == *"macOS accepts the plug-ins: no: "(VCNVTLoader is running but was built for other plug-ins|nothing on this Mac lets them into Safari)* ]]; then
    WAIT_LOADER=1
  else
    block decoders "this Mac is not ready for them:"$'\n'"$dec_failed"
  fi
elif [[ $(jfield decoders installed) == current ]]; then
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
  elif [[ $(jfield decoders installed) == current ]]; then
    SKIPS+=("decoders: the plug-ins installed are already these; the loader kext lets them in after the reboot")
  else
    STEPS+=(decoders)
    DEC_AFTER_LOADER=1
  fi
fi

# True when an optional part is installed, current and running.
in_place() { # part
  case $1 in
    encoder) [[ $(jfield encoder installed) == current && $(jfield encoder kext) == "loaded $(jfield encoder version), active"* ]] ;;
    # working, and the version that runs is the one here (an older one gets updated)
    sensors) [[ $(jfield sensors result) == working* && $(jfield sensors running) == "loaded $(jfield sensors version),"* ]] ;;
    *) return 1 ;;
  esac
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
for part flag in encoder $WITH_ENCODER sensors $WITH_SENSORS; do
  (( flag )) || { SKIPS+=("$part: not asked for (--with-$part)"); continue; }
  if ! look $part; then
    block $part "its check did not answer"
  elif in_place $part || [[ $part == sensors && $(jfield sensors toolsOnly) == true ]]; then
    SKIPS+=("$part: already installed and running, the same version")
    [[ $part == sensors ]] && plan_tools
  elif [[ $(jfield $part canInstall) != true ]]; then
    block $part "it cannot be installed on this Mac:"$'\n'"$(failed_checks $part)"
  else
    STEPS+=($part)
  fi
done

# the loader goes first, so the plug-ins it lists are on disk only when it is
typeset -a ORDER=()
for part in loader decoders encoder sensors tools; do
  (( ${STEPS[(Ie)$part]} )) && ORDER+=($part)
done
# how a step is named in the closing lines
step_name() { [[ $1 == tools ]] && print -rn -- "gpucontrol and gpusensors" || print -rn -- "$1"; }

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
    tools)    print -r -- "  copy gpucontrol and gpusensors to /usr/local/bin: the GPU sensors kext is already this one (no reboot needed)" ;;
  esac
done
for s in $SKIPS; do print -r -- "  skip $s"; done
if (( ! ${#ORDER} )); then
  print -r -- "Nothing to install: everything asked for is already in place."
  exit 0
fi
(( PLAN )) && exit 0

# ---- the EFI, once for every part that needs it ----------------------------------------------
trap '[[ -n $OPEN_ID ]] && efi_close "$OPEN_ID"' EXIT
if (( ${ORDER[(Ie)loader]} || ${ORDER[(Ie)encoder]} || ${ORDER[(Ie)sensors]} )) && [[ -z $EFI_ID ]]; then
  if efi_find_opencore; then
    EFI_ID=$EFI_FOUND
    print -r -- "EFI: $EFI_ID ($EFI_FIND_WHY)."
  else
    print -r -u2 -- "Cannot tell which EFI partition to use: $EFI_FIND_WHY."
    if (( IN_APP )); then
      print -r -u2 -- "Nothing was changed. To name the one you boot from, run in Terminal:"
      print -r -u2 -- "  sudo '$SELF_DIR/install.sh' ... --efi diskNsM   (diskutil list shows them)"
      print -r -u2 -- "With bit 0x1 in OpenCore's Misc > Security > ExposeSensitiveData, this Mac tells which one it started from and the choice is made for you."
    else
      print -r -u2 -- "Nothing was installed. Name it: sudo install/install.sh ... --efi diskNsM"
    fi
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
    loader)   /bin/zsh "$SELF_DIR/loader.sh" install --efi "$EFI_ID" ;;
    encoder)  /bin/zsh "$SELF_DIR/encoder.sh" install --efi "$EFI_ID" ;;
    sensors)  /bin/zsh "$SELF_DIR/sensors.sh" install --efi "$EFI_ID" ;;
    tools)    /bin/zsh "$SELF_DIR/sensors.sh" tools ;;
  esac
  rc=$?
  if (( rc )); then
    print
    print -r -u2 -- "Stopped: $(step_name $part) failed (exit $rc, see above)."
    if [[ $part == decoders ]] && (( DEC_AFTER_LOADER )); then
      print -r -u2 -- "The loader kext is on the EFI and starts at the next boot. Reboot, then $(pick "run 'sudo install/install.sh' again" "open RyzenStatus GPU and use Install what this Mac needs again"): the decoders go in then."
    fi
    (( ${#DONE} )) && print -r -u2 -- "Done before it: ${(j:, :)${DONE/#%tools/gpucontrol and gpusensors}}. $(pick "'sudo install/undo.sh'" "Remove all in this window") takes everything off."
    exit 1
  fi
  DONE+=($part)
done

print
print -r -- "== check"
/bin/zsh "$SELF_DIR/check.sh" || true
print
done_names=${(j:, :)${DONE/#%tools/gpucontrol and gpusensors}}
if [[ ${(j: :)DONE} == tools ]]; then
  print -r -- "Installed: $done_names, in /usr/local/bin. They work now; no reboot needed."
else
  print -r -- "Installed: $done_names. Reboot for it to take effect, then $(pick "run install/check.sh" "open RyzenStatus GPU again to check it")."
  if (( DEC_AFTER_LOADER )); then
    print -r -- "The decoders load at that reboot, when the loader kext starts with it."
  fi
fi
exit 0
