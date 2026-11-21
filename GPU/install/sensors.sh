#!/bin/zsh
# sensors.sh - puts GPUSensors.kext on your OpenCore EFI or takes it off, and checks whether
# it works. GPUSensors publishes the GPU readings Apple's AMD driver takes and hides (edge,
# memory and VR temperatures, voltages, PCIe link); see sensors/README.md. It is optional
# and independent of the decoders and the encoding fix.
#
#   install/sensors.sh check [--json]                 look at this Mac; changes nothing, no sudo
#   sudo install/sensors.sh install [--efi diskNsM]   copy the kext and add its entry to
#                                                     config.plist; then reboot
#   sudo install/sensors.sh uninstall [--efi diskNsM] remove the entry and the kext; then reboot
#   sudo install/sensors.sh tools                     copy gpucontrol and gpusensors to
#                                                     /usr/local/bin (install does it too)
#   sudo install/sensors.sh uninstall-tools           remove only those two commands, ours
#                                                     only (uninstall does it too); for when
#                                                     the kext is gone already
#   install/sensors.sh --help
#
# The commands in /usr/local/bin belong to root and only root can change them, so a program
# that runs "gpucontrol arm" as root (RyzenStatus asks for the administrator password for it)
# runs the file this script put there. They are copied only when /usr/local/bin and every
# folder above it belong to root, and only files signed as ours are replaced or removed.
#
# Options:
#   --efi diskNsM      the EFI partition your Mac boots OpenCore from. Without it the script
#                      takes the one OpenCore says it started from, or the only one that
#                      holds OpenCore. When it cannot tell, it lists them and stops.
#   --efi-folder DIR   instead of a partition: a folder that holds EFI/OC (a mounted EFI, a
#                      USB stick, a copy). Nothing is mounted or unmounted.
#   --kext DIR         the kext to install (default sensors/build/GPUSensors.kext)
#   --json             with check: print the result as one JSON object (for a front end)
#
# What install changes is described in install/efikext.zsh, which loader.sh uses too: the
# kext is copied into EFI/OC/Kexts and one entry is added to Kernel > Add after Lilu, with a
# backup of config.plist written first and the edit verified.
#
# If the Mac does not start after the reboot: start it from another EFI (a USB stick) and
# copy the backup over EFI/OC/config.plist, or add -gpusensoff to the boot arguments.
#
# Exit status: 0 done, or check found the kext working or nothing in the way (a running kext
# with checks marked FAIL is still working; the result line says those stop a new install);
# 1 error; 2 check found it not working or blocked; 64 wrong usage. check --json ends with 0.
emulate -L zsh
setopt no_unset
# No pipe_fail here: "command | grep -q" must be true when grep finds its match and stops
# reading early.
autoload -Uz is-at-least

SELF_DIR=${0:A:h}
ROOT=${SELF_DIR:h}
source $SELF_DIR/common.zsh
KEXT=$ROOT/sensors/build/GPUSensors.kext
ENTRY=$ROOT/decode/build/kextentry
KNAME=GPUSensors
KEXEC=GPUSensors
KBUNDLE=com.droga.GPUSensors
KOFFARG=-gpusensoff
SCRIPT=sensors.sh
MIN_LILU=1.7.0
SKC=/System/Library/KernelCollections/SystemKernelExtensions.kc
# The first bytes of the driver function the kext routes, as sensors/kext/pmlog_logic.hpp
# expects them (17 bytes).
PROLOGUE=554889e5415741565350c745e400000000

show_help() { help_of "$SELF_DIR/sensors.sh"; }
usage_error() {
  print -r -u2 -- "sensors.sh: $1"
  print -r -u2 -- "usage: sensors.sh {check [--json] [--efi-folder DIR] | install | uninstall [--efi diskNsM | --efi-folder DIR] | tools | uninstall-tools} [--kext DIR]"
  exit 64
}

CMD=${1:-}
(( $# )) && shift
EFI_ID=""
EFI_DIR=""
JSON=0
while (( $# )); do
  case $1 in
    --efi)
      (( $# >= 2 )) && [[ -n $2 ]] || usage_error "--efi needs a partition, for example disk0s1"
      EFI_ID=$2
      shift ;;
    --efi-folder)
      (( $# >= 2 )) && [[ -n $2 ]] || usage_error "--efi-folder needs a folder"
      EFI_DIR=${2:A}
      shift ;;
    --kext)
      (( $# >= 2 )) && [[ -n $2 ]] || usage_error "--kext needs a folder"
      KEXT=${2:A}
      shift ;;
    --json) JSON=1 ;;
    -h|--help) show_help; exit 0 ;;
    *) usage_error "unknown option '$1'" ;;
  esac
  shift
done
[[ $JSON -eq 1 && $CMD != check ]] && usage_error "--json goes with check only"
[[ -n $EFI_ID && $CMD == check ]] && usage_error "check looks at every EFI partition; --efi goes with install and uninstall"
[[ -n $EFI_ID && -n $EFI_DIR ]] && usage_error "give --efi or --efi-folder, not both"

# Every copy of the kext can do its job: there is nothing build-specific to check.
kext_usable() { return 0; }
USABLE_KEY=usable
USABLE_YES=""
USABLE_NO="cannot be used"
source $SELF_DIR/efikext.zsh

# The driver library this Mac loads, and whether its function starts as the kext expects.
# Sets DRIVER_LIB (X6000, X6800 or empty) and DRIVER_OK (yes | no | unknown).
DRIVER_LIB=""
DRIVER_OK=unknown
look_driver() {
  DRIVER_LIB=""
  DRIVER_OK=unknown
  if [[ -n $(kext_version com.apple.kext.AMDRadeonX6000HWLibs) ]]; then DRIVER_LIB=AMDRadeonX6000HWLibs
  elif [[ -n $(kext_version com.apple.kext.AMDRadeonX6800HWLibs) ]]; then DRIVER_LIB=AMDRadeonX6800HWLibs
  fi
  [[ -n $DRIVER_LIB && -f $SKC ]] || return 0
  local out rc
  out=$(/usr/bin/python3 -I $ROOT/tools/driver/kcfunc.py com.apple.kext.$DRIVER_LIB _PEM_CWDDEPM_QueryPMLogData "this_mac=$SKC" 2>/dev/null)
  rc=$?
  # kcfunc.py: 1 the library is there but the function is not, 2 the collection could not be read
  if (( rc == 1 )); then DRIVER_OK=no; return 0; fi
  (( rc == 0 )) || return 0
  if [[ $out == $PROLOGUE* ]]; then DRIVER_OK=yes; else DRIVER_OK=no; fi
}

# ---- preflight -----------------------------------------------------------------------------
CAN_INSTALL=0
preflight() {
  CHECKS=()
  CHECK_LINES=()
  CAN_INSTALL=1

  # 1. the kext and the helper that edits config.plist are built
  if [[ ! -f $KEXT/Contents/MacOS/$KEXEC || ! -f $KEXT/Contents/Info.plist ]]; then
    add_check sensors-kext "Sensors kext built" fail "$(pick "no GPUSensors.kext in ${KEXT:h}; build it with ./build.sh (tools/bootstrap.sh once before)" "no GPUSensors.kext inside RyzenStatus GPU.app; $APP_DAMAGED")"
    CAN_INSTALL=0
  elif [[ ! -x $ENTRY ]]; then
    add_check sensors-kext "Sensors kext built" fail "$(pick "$ENTRY is missing; decode/build.sh builds it" "kextentry is missing; $APP_DAMAGED")"
    CAN_INSTALL=0
  else
    add_check sensors-kext "Sensors kext built" ok "GPUSensors $(kext_file_version "$KEXT")"
  fi

  # 2. a macOS the kext starts on (its Lilu settings: Sequoia to Tahoe)
  local darwin=$(/usr/bin/uname -r | cut -d. -f1) product=$(/usr/bin/sw_vers -productVersion 2>/dev/null)
  if [[ $darwin == 24 || $darwin == 25 ]]; then
    add_check sensors-macos "macOS version" ok "$product (supported: Sequoia 15 – Tahoe 26)"
  else
    add_check sensors-macos "macOS version" fail "$product: the kext only starts on Sequoia 15 and Tahoe 26"
    CAN_INSTALL=0
  fi

  # 3. a Navi 21 card. Every card is looked at: with integrated graphics the AMD card is not
  #    always the first one.
  #    VCNVT_FAKE_GPU is for testing only (tests/loader_install.sh on a CI runner, which has
  #    no AMD card): it stands in for the card list, and only together with --efi-folder,
  #    so it can never get past the refusal for a real EFI partition.
  local -a gpus
  if [[ -n ${VCNVT_FAKE_GPU:-} && -n $EFI_DIR ]]; then
    gpus=( "$VCNVT_FAKE_GPU" )
  else
    gpus=( ${(f)"$(displays_report | awk -F': ' '/Chipset Model/{m=$2} /Device ID/{print m" ("$2")"}')"} )
  fi
  local g gpu=""
  for g in "${gpus[@]}"; do
    if print -rn -- "$g" | grep -qiE '\(0x73(a[0-9a-f]|bf)\)'; then gpu=$g; break; fi
  done
  if [[ -n $gpu ]]; then
    add_check sensors-gpu "Navi 21 GPU" ok "$gpu"
  else
    local all=${(j:, :)gpus}
    add_check sensors-gpu "Navi 21 GPU" fail "${all:-no AMD GPU found}: the sensors kext is only for Navi 21 (RX 6800 – 6950 XT)"
    CAN_INSTALL=0
  fi

  # 4. the driver function the kext reads from
  look_driver
  case $DRIVER_OK in
    yes) add_check sensors-driver "Driver function as expected" ok "$DRIVER_LIB on this Mac starts as the kext expects" ;;
    no)  add_check sensors-driver "Driver function as expected" fail "$DRIVER_LIB on this Mac does not start as the kext expects, so the kext would stay off. This macOS build was not checked$(pick "; see sensors/README.md" ".")"
         CAN_INSTALL=0 ;;
    *)   add_check sensors-driver "Driver function as expected" warn "could not look (${DRIVER_LIB:-no AMD driver library loaded}); the kext checks again when it starts and stays off if it does not match" ;;
  esac

  # 5. Lilu (the copy on the EFI is what counts; install looks at that one too)
  local lilu=$(kext_version as.vit9696.Lilu)
  if [[ -z $lilu ]]; then
    add_check sensors-lilu "Lilu loaded" warn "Lilu is not loaded now. The kext needs Lilu $MIN_LILU or newer on the EFI; install checks that."
  elif is-at-least $MIN_LILU "$lilu"; then
    add_check sensors-lilu "Lilu loaded" ok "Lilu $lilu"
  else
    add_check sensors-lilu "Lilu loaded" warn "Lilu $lilu is loaded; the kext needs $MIN_LILU or newer. Update Lilu on your EFI first."
  fi
}

# ---- what is running -------------------------------------------------------------------------
sensor_prop() { # name
  /usr/sbin/ioreg -r -c DrogaBoxGPUSensors -l 2>/dev/null | sed -n "s/^ *\"$1\" = \"*\([^\"{]*\)\"*\$/\1/p" | head -1
}
RUN_STATE=""
RUN_SAMPLES=0
RUN_LINE=""
RUN_VERSION=""
look_running() {
  local version=$(kext_version com.droga.GPUSensors)
  # VCNVT_FAKE_RUNNING is for testing only (tests/loader_install.sh): the version of a
  # GPUSensors that runs and publishes no status, as one before 0.8.0. Like VCNVT_FAKE_GPU,
  # only together with --efi-folder.
  RUN_STATE=""
  RUN_SAMPLES=0
  RUN_LINE="not loaded"
  RUN_VERSION=$version
  if [[ -n ${VCNVT_FAKE_RUNNING:-} && -n $EFI_DIR ]]; then
    RUN_VERSION=$VCNVT_FAKE_RUNNING
    RUN_LINE="loaded $RUN_VERSION, no status, 0 readings since boot"
    return 0
  fi
  [[ -n $version ]] || return 0
  RUN_STATE=$(sensor_prop Status)
  RUN_SAMPLES=$(sensor_prop Samples)
  RUN_LINE="loaded $version, ${RUN_STATE:-no status}, ${RUN_SAMPLES:-0} readings since boot"
  local age=$(sensor_prop SampleAgeMs)
  [[ -n $age ]] && RUN_LINE+=", the last $age ms ago"
}

RESULT=""
RESULT_OK=1
# 1 when the result says that this version is on the EFI and the next boot loads it: an EFI
# holds this build with its entry ok, no EFI holds another one, and the kext that runs (if
# any) is another version. Nothing is left to install then; check --json calls it
# "pendingReboot".
PENDING_REBOOT=0
conclude() {
  RESULT_OK=1
  PENDING_REBOOT=0
  local new=$(kext_file_version "$KEXT") on_efi=0
  [[ -n $READY_ON && -z $STALE_ON && -n $new && $RUN_VERSION != "$new" ]] && on_efi=1
  # what the next boot changes, for the results about a kext that runs now
  local next=""
  (( on_efi )) && next=" GPUSensors $new is on $READY_ON and loads at the next boot."
  local update=""
  [[ -n $STALE_ON && $CAN_INSTALL -eq 1 ]] && update=" The kext on $STALE_ON is not the one $(pick "in ${KEXT:h:t}: 'sudo install/sensors.sh install' updates it" "in this app: GPU sensors > Update in this window updates it")."
  # the kext that runs is what check is about; checks marked FAIL only stop a new install
  local blocked=""
  (( CAN_INSTALL )) || blocked=" The checks marked FAIL stop a new install."
  if [[ $RUN_STATE == active && ${RUN_SAMPLES:-0} -gt 0 ]]; then
    RESULT="working: GPUSensors is active and has readings ($(pick "sensors/build/gpusensors shows them" "RyzenStatus shows them")).$next$update$TOOLS_NOTE$blocked"
    PENDING_REBOOT=$on_efi
  elif [[ $RUN_STATE == active ]]; then
    RESULT="GPUSensors is active but the driver has not read its sensors yet. Use the GPU a moment and check again.$next$TOOLS_NOTE$blocked"
    PENDING_REBOOT=$on_efi
  elif [[ -n $RUN_STATE ]]; then
    RESULT="the kext is loaded but does nothing ($RUN_STATE).$next"
    RESULT_OK=0
    PENDING_REBOOT=$on_efi
  elif [[ -n $RUN_VERSION ]] && (( on_efi )); then
    # an older (or other) GPUSensors runs, and this one is already on the EFI
    RESULT="installed on $READY_ON: GPUSensors $new loads at the next boot; $RUN_VERSION runs until then. Reboot from that EFI to start it."
    PENDING_REBOOT=1
  elif [[ -n $RUN_VERSION && $RUN_VERSION != "$new" && $CAN_INSTALL -eq 1 ]]; then
    # an older (or other) GPUSensors runs, one that publishes no status
    RESULT="GPUSensors $RUN_VERSION is loaded; $(pick "${KEXT:h:h:t}/${KEXT:h:t} has" "this app has") $(kext_file_version "$KEXT"). $(pick "'sudo install/sensors.sh install' puts it on your EFI" "GPU sensors > Update in this window puts it on your EFI"); then reboot."
  elif [[ $CAN_INSTALL -eq 0 ]]; then
    RESULT="blocked. Fix the checks marked FAIL first."
    RESULT_OK=0
  elif [[ -n $READY_ON && -z $STALE_ON ]]; then
    RESULT="installed on $READY_ON, not running yet. Reboot from that EFI to start it."
    PENDING_REBOOT=1
  else
    RESULT="ready. $(pick "'sudo install/sensors.sh install'" "GPU sensors > Install in this window") puts the kext on your EFI; then reboot."
  fi
}

check_json() {
  print -rn -- "{\"canInstall\":$([[ $CAN_INSTALL -eq 1 ]] && echo true || echo false),"
  print -rn -- "\"version\":\"$(jesc "$(kext_file_version "$KEXT")")\",\"running\":\"$(jesc "$RUN_LINE")\","
  print -rn -- "\"tools\":\"$TOOLS_STATE\",\"toolsOnly\":$([[ $TOOLS_ONLY -eq 1 ]] && echo true || echo false),"
  print -rn -- "\"toolsInstalled\":$([[ $TOOLS_OURS -eq 1 ]] && echo true || echo false),"
  print -rn -- "\"pendingReboot\":$([[ $PENDING_REBOOT -eq 1 ]] && echo true || echo false),"
  print -rn -- "\"result\":\"$(jesc "$RESULT")\",\"efis\":[${(j:,:)EFI_JSON}],\"checks\":[${(j:,:)CHECKS}]}"
  print
}

do_check() {
  preflight
  look_running
  efi_scan
  tools_check
  efi_choice_check sensors-efi
  conclude
  if [[ $JSON -eq 1 ]]; then
    check_json
    return 0
  fi
  local json_to=$(check_json_to)
  [[ -n $json_to ]] && check_json > "$json_to"
  print -r -- "GPUSensors ${$(kext_file_version "$KEXT"):-(not built)} in $KEXT"
  print -rl -- "${CHECK_LINES[@]}"
  print -r -- "Running now: $RUN_LINE"
  if [[ -n $EFI_DIR ]]; then print -r -- "EFI folder:"; else print -r -- "EFI partitions:"; fi
  if (( ${#EFI_LINES} )); then print -rl -- "${EFI_LINES[@]}"; else print -r -- "  none found"; fi
  print -r -- "Result: $RESULT"
  (( RESULT_OK )) && return 0
  return 2
}

do_install() {
  need_root install
  preflight
  if [[ $CAN_INSTALL -ne 1 ]]; then
    print -r -u2 -- "GPUSensors cannot be installed yet. Nothing was changed."
    print -rl -u2 -- "${CHECK_LINES[@]}"
    exit 2
  fi
  kext_install
  if [[ $EUID -eq 0 && -z $EFI_DIR ]]; then
    tools_install || print -r -u2 -- "The kext is in place; the commands were not copied (above). $(pick "'sudo install/sensors.sh tools'" "GPU sensors > Install tools in this window, after the reboot,") tries again."
  fi
  if (( IN_APP )); then
    print -r -- "Reboot. Then open RyzenStatus GPU again: it checks whether the kext works, and RyzenStatus shows the readings."
  else
    print -r -- "Reboot. Then 'install/sensors.sh check' tells you in one line whether it works,"
    print -r -- "and sensors/build/gpusensors shows the readings."
  fi
}

do_uninstall() {
  need_root uninstall
  [[ $EUID -eq 0 && -z $EFI_DIR ]] && tools_uninstall
  kext_uninstall || return 0
}

# Only the commands, for a Mac where the kext is gone already (taken off the EFI by hand,
# for example): Remove all and the GPU sensors' Remove run this then. Ours only.
do_uninstall_tools() {
  [[ -z $EFI_ID && -z $EFI_DIR ]] || usage_error "uninstall-tools takes no --efi or --efi-folder"
  [[ $EUID -eq 0 ]] || { print -r -u2 -- "uninstall-tools must run as root: sudo install/$SCRIPT uninstall-tools"; exit 1; }
  gpu_tools_look
  if (( ! ${#GPU_TOOLS_OURS} && ! ${#GPU_TOOLS_OTHER} )); then
    print -r -- "gpucontrol and gpusensors are not in $TOOL_DIR. Nothing to remove."
    return 0
  fi
  tools_uninstall
  gpu_tools_look
  (( ${#GPU_TOOLS_OURS} )) && { print -r -u2 -- "Could not remove ${(j:, :)GPU_TOOLS_OURS}."; exit 1; }
  return 0
}

# ---- the commands in /usr/local/bin ------------------------------------------------------------
# gpucontrol and gpusensors are copied to /usr/local/bin, owned by root and writable by root
# only, so a program can run "sudo gpucontrol arm" (or ask for the administrator password and
# run /usr/local/bin/gpucontrol arm) knowing no other program of the user could have swapped
# the file. Only files signed with our identifiers are ever replaced or removed.
TOOL_DIR=$GPU_TOOL_DIR
TOOLS=($GPU_TOOL_NAMES)
tool_id() { gpu_tool_id "$1"; }
has_acl() { [[ $(/bin/ls -lde "$1" 2>/dev/null | head -1 | cut -c11) == "+" ]]; }
tool_dir_unsafe() {
  local d=$TOOL_DIR owner mode
  while [[ $d != / ]]; do
    if [[ -e $d || -L $d ]]; then
      [[ -d $d && ! -L $d ]] || { print -r -- "$d is not a folder"; return 0; }
      owner=$(/usr/bin/stat -f '%Su' "$d")
      mode=$(/usr/bin/stat -f '%Lp' "$d")
      [[ $owner == root ]] || { print -r -- "$d belongs to $owner, not root"; return 0; }
      (( (8#$mode & 8#022) == 0 )) || { print -r -- "$d can be written by others than root (mode $mode)"; return 0; }
      has_acl "$d" && { print -r -- "$d has an access control list"; return 0; }
    fi
    d=${d:h}
  done
  return 1
}
tool_file_unsound() { # file name
  local f=$1 owner mode
  [[ -f $f && ! -L $f ]] || { print -r -- "$f is not a plain file"; return 0; }
  [[ $(tool_id "$f") == com.droga.$2 ]] || { print -r -- "$f is another program"; return 0; }
  local sig
  sig=$(/usr/bin/codesign --verify "$f" 2>&1) ||
    { print -r -- "$f does not pass its signature check (codesign: ${${sig//$'\n'/; }:-no reason given})"; return 0; }
  owner=$(/usr/bin/stat -f '%Su' "$f")
  mode=$(/usr/bin/stat -f '%Lp' "$f")
  [[ $owner == root ]] && (( (8#$mode & 8#022) == 0 )) ||
    { print -r -- "$f belongs to $owner with mode $mode"; return 0; }
  has_acl "$f" && { print -r -- "$f has an access control list"; return 0; }
  return 1
}
TOOL_ST=""
TOOL_WHY=""
tool_look() { # name
  local src=$ROOT/sensors/build/$1 dst=$TOOL_DIR/$1 why
  if [[ ! -e $dst && ! -L $dst ]]; then TOOL_ST=missing; TOOL_WHY="not installed"; return; fi
  if [[ -L $dst || ! -f $dst ]]; then TOOL_ST=foreign; TOOL_WHY="$dst is not a plain file"; return; fi
  if [[ $(tool_id "$dst") != com.droga.$1 ]]; then TOOL_ST=foreign; TOOL_WHY="$dst is another program"; return; fi
  if why=$(tool_file_unsound "$dst" $1); then TOOL_ST=unsafe; TOOL_WHY=$why; return; fi
  if why=$(tool_dir_unsafe); then TOOL_ST=unsafe; TOOL_WHY=$why; return; fi
  if [[ -f $src ]] && ! /usr/bin/cmp -s "$src" "$dst"; then TOOL_ST=old; TOOL_WHY="differs from sensors/build/$1"; return; fi
  TOOL_ST=ok
  TOOL_WHY="$dst"
}
# TOOLS_STATE: current (both here and the same as the ones to copy), missing (one or both not
TOOLS_STATE=current
TOOLS_ONLY=0
TOOLS_NOTE=""
TOOLS_OURS=0   # 1 when at least one of the two in /usr/local/bin is ours (Remove takes it)
tools_check() {
  gpu_tools_look
  TOOLS_OURS=0
  (( ${#GPU_TOOLS_OURS} )) && TOOLS_OURS=1
  local -a lines
  local name have=1 missing=0 old=0 bad=0 row efi_current=0
  for name in $TOOLS; do
    tool_look $name
    lines+=("$name: $TOOL_WHY")
    [[ -f $ROOT/sensors/build/$name ]] || have=0
    case $TOOL_ST in
      foreign|unsafe) bad=1 ;;
      old) old=1 ;;
      missing) missing=1 ;;
    esac
  done
  if (( bad )); then TOOLS_STATE=blocked
  elif (( old )); then TOOLS_STATE=outdated
  elif (( missing )); then TOOLS_STATE=missing
  else TOOLS_STATE=current
  fi
  for row in $EFI_JSON; do
    [[ $row == *'"kext":"current"'* ]] && efi_current=1
  done
  TOOLS_ONLY=0
  TOOLS_NOTE=""
  if [[ $TOOLS_STATE == (missing|outdated) && $have -eq 1 && $RUN_STATE == active && $efi_current -eq 1 &&
        -n $RUN_VERSION && $RUN_VERSION == "$(kext_file_version "$KEXT")" ]]; then
    TOOLS_ONLY=1
  fi
  local detail=${(j:; :)lines} verb="Update tools" how
  [[ $TOOLS_STATE == missing ]] && verb="Install tools"
  if (( TOOLS_ONLY )); then
    how=$(pick "'sudo install/sensors.sh tools' copies them" "GPU sensors > $verb in this window copies them")
    if [[ $TOOLS_STATE == missing ]]; then
      TOOLS_NOTE=" gpucontrol and gpusensors are not in $TOOL_DIR yet: $how."
    else
      TOOLS_NOTE=" gpucontrol or gpusensors in $TOOL_DIR is not the one $(pick "in sensors/build" "in this app"): $how."
    fi
  else
    how=$(pick "'sudo install/sensors.sh tools' copies them" "installing or updating GPU sensors in this window copies them")
  fi
  case $TOOLS_STATE in
    current)          add_check sensors-tools "Commands in $TOOL_DIR" ok "$detail" ;;
    missing|outdated) add_check sensors-tools "Commands in $TOOL_DIR" warn "$detail; $how (optional)" ;;
    blocked)          add_check sensors-tools "Commands in $TOOL_DIR" warn "$detail; programs will not run it as root, and tools leaves it alone" ;;
  esac
}
tools_install() {
  local name src dst tmp why
  if why=$(tool_dir_unsafe); then
    print -r -u2 -- "Not copying the commands: $why, so programs could not trust them there."
    return 1
  fi
  for name in $TOOLS; do
    src=$ROOT/sensors/build/$name
    [[ -f $src && $(tool_id "$src") == com.droga.$name ]] ||
      { print -r -u2 -- "$(pick "sensors/build/$name is missing or not ours; build it with sensors/build.sh" "$name is missing or not ours; $APP_DAMAGED")"; return 1; }
    tool_look $name
    [[ $TOOL_ST == foreign ]] && { print -r -u2 -- "Not replacing $TOOL_WHY."; return 1; }
  done
  if [[ ! -e $TOOL_DIR ]]; then
    /bin/mkdir -p -m 755 "$TOOL_DIR" || return 1
    if why=$(tool_dir_unsafe); then print -r -u2 -- "Not copying the commands: $why."; return 1; fi
  fi
  [[ -d $TOOL_DIR && ! -L $TOOL_DIR ]] || { print -r -u2 -- "$TOOL_DIR is not a folder."; return 1; }
  for name in $TOOLS; do
    src=$ROOT/sensors/build/$name
    dst=$TOOL_DIR/$name
    tmp=$TOOL_DIR/.$name.new.$$
    /bin/rm -f "$tmp"
    /usr/bin/install -o root -g wheel -m 755 "$src" "$tmp" || { /bin/rm -f "$tmp"; return 1; }
    /bin/chmod -N "$tmp" 2>/dev/null
    if why=$(tool_file_unsound "$tmp" $name); then
      /bin/rm -f "$tmp"
      print -r -u2 -- "The copy of $name did not come out right ($why); nothing was replaced."
      return 1
    fi
    /bin/mv -f "$tmp" "$dst" || { /bin/rm -f "$tmp"; return 1; }
    tool_look $name
    [[ $TOOL_ST == ok ]] || { print -r -u2 -- "$dst did not come out right: $TOOL_WHY"; return 1; }
    print -r -- "Copied $name to $dst (root, mode 755)."
  done
}
# Removes the commands that are ours; anything else under those names stays.
tools_uninstall() {
  local name dst
  for name in $TOOLS; do
    dst=$TOOL_DIR/$name
    [[ -e $dst || -L $dst ]] || continue
    if [[ ! -f $dst || -L $dst ]]; then
      print -r -- "Left $dst alone: it is not a plain file."
    elif [[ $(tool_id "$dst") == com.droga.$name ]]; then
      /bin/rm -f "$dst" && print -r -- "Removed $dst."
    else
      print -r -- "Left $dst alone: it is another program."
    fi
  done
}

do_tools() {
  [[ -z $EFI_ID && -z $EFI_DIR ]] || usage_error "tools takes no --efi or --efi-folder"
  [[ $EUID -eq 0 ]] || { print -r -u2 -- "tools must run as root: sudo install/$SCRIPT tools"; exit 1; }
  tools_install || exit 1
  print -r -- "'sudo gpucontrol arm' now works from any folder."
}

case "$CMD" in
  check)     do_check ;;
  install)   do_install ;;
  uninstall) do_uninstall ;;
  tools)     do_tools ;;
  uninstall-tools) do_uninstall_tools ;;
  -h|--help|help) show_help ;;
  "") usage_error "no command given" ;;
  *) usage_error "unknown command '$CMD'" ;;
esac
