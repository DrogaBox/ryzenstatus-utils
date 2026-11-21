#!/bin/zsh
# loader.sh - puts VCNVTLoader.kext on your OpenCore EFI or takes it off, and checks whether
# it works. VCNVTLoader is the kext that lets the decoder plug-ins load on a Mac without
# AMFIPass (decode/loader/README.md). A Mac that runs AMFIPass does not need it.
#
#   install/loader.sh check [--json]              look at this Mac; changes nothing, no sudo
#   sudo install/loader.sh install [--efi diskNsM]     copy the kext and add its entry to
#                                                      config.plist; then reboot
#   sudo install/loader.sh uninstall [--efi diskNsM]   remove the entry and the kext; then reboot
#   install/loader.sh --help
#
# Options:
#   --efi diskNsM      the EFI partition your Mac boots OpenCore from. Without it the script
#                      takes the one OpenCore says it started from, or the only one that
#                      holds OpenCore. When it cannot tell, it lists them and stops.
#   --efi-folder DIR   instead of a partition: a folder that holds EFI/OC, such as an EFI that
#                      is already mounted, a USB stick or a copy. Nothing is mounted or
#                      unmounted, and sudo is only needed if the folder needs it.
#   --kext DIR         the kext to install (default decode/build/VCNVTLoader.kext)
#   --bundles DIR      the plug-ins the kext must list (default decode/build)
#   --json             with check: print the result as one JSON object (for a front end)
#
# What install changes, all of it on the EFI partition:
#   EFI/OC/Kexts/VCNVTLoader.kext        copied; a copy that was there is replaced
#   EFI/OC/config.plist                  one entry added to Kernel > Add, after Lilu. A backup
#                                        named config.plist.backup-<date>-<time>-pre-vcnvtloader
#                                        is written next to it first, and the edit is checked:
#                                        the new file is the old one plus the entry.
# The partition is mounted if needed and unmounted again afterwards. Nothing is copied
# before every check has passed. The kext is copied before the entry is added, and on
# uninstall the entry is removed before the kext, so a run that is interrupted never
# leaves an entry that points to a missing kext.
#
# If the Mac does not start after the reboot: start it from another EFI (a USB stick) and
# copy the backup over EFI/OC/config.plist, or add -vcnvtoff to the boot arguments.
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
KEXT=$ROOT/decode/build/VCNVTLoader.kext
BUNDLES=$ROOT/decode/build
ENTRY=$ROOT/decode/build/kextentry
PROBE=$ROOT/decode/build/lvprobe
AV1=AV1VCNDecoder.bundle
VP9=VP9VCNDecoder.bundle
LIVE=/System/Library/Video/Plug-Ins
KNAME=VCNVTLoader
KEXEC=VCNVTLoader
KOFFARG=-vcnvtoff
SCRIPT=loader.sh
MIN_LILU=1.7.0

show_help() { help_of "$SELF_DIR/loader.sh"; }
usage_error() {
  print -r -u2 -- "loader.sh: $1"
  print -r -u2 -- "usage: loader.sh {check [--json] [--efi-folder DIR] | install | uninstall [--efi diskNsM | --efi-folder DIR]} [--kext DIR] [--bundles DIR]"
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
    --bundles)
      (( $# >= 2 )) && [[ -n $2 ]] || usage_error "--bundles needs a folder"
      BUNDLES=${2:A}
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

# What check says about a copy of the kext: whether it lists the plug-ins being installed.
kext_usable() { lists_both "$1"; }
USABLE_KEY=listsPlugins
USABLE_YES="lists the plug-ins"
USABLE_NO="does NOT list the plug-ins"
USABLE_UNKNOWN="not known whether it lists the plug-ins (none built in ${BUNDLES:t} to compare with)"
source $SELF_DIR/efikext.zsh

# 0 the kext lists both plug-ins, 1 it does not, 2 there are no built plug-ins to compare with
lists_both() { # kext-dir
  [[ -d $BUNDLES/$AV1 && -d $BUNDLES/$VP9 ]] || return 2
  kext_lists "$1" "$BUNDLES/$AV1" && kext_lists "$1" "$BUNDLES/$VP9"
}
# ---- preflight -----------------------------------------------------------------------------
CAN_INSTALL=0
preflight() {
  CHECKS=()
  CHECK_LINES=()
  CAN_INSTALL=1

  # 1. the kext and the helper that edits config.plist are built
  if [[ ! -f $KEXT/Contents/MacOS/VCNVTLoader || ! -f $KEXT/Contents/Info.plist ]]; then
    add_check loader-kext "Loader kext built" fail "no VCNVTLoader.kext in ${KEXT:h}; build it with ./build.sh (tools/bootstrap.sh once before)"
    CAN_INSTALL=0
  elif [[ ! -x $ENTRY ]]; then
    add_check loader-kext "Loader kext built" fail "$ENTRY is missing; decode/build.sh builds it"
    CAN_INSTALL=0
  else
    add_check loader-kext "Loader kext built" ok "VCNVTLoader $(kext_file_version "$KEXT")"
  fi

  # 2. the kext lists the plug-ins it is going to be used with
  if [[ ! -d $BUNDLES/$AV1 || ! -d $BUNDLES/$VP9 ]]; then
    add_check loader-match "The kext lists the plug-ins" fail "missing $AV1 or $VP9 in $BUNDLES; build them with ./build.sh"
    CAN_INSTALL=0
  elif [[ ! -f $KEXT/Contents/MacOS/VCNVTLoader ]]; then
    add_check loader-match "The kext lists the plug-ins" fail "there is no kext to look into"
  elif lists_both "$KEXT"; then
    add_check loader-match "The kext lists the plug-ins" ok "both plug-ins in $BUNDLES"
  else
    add_check loader-match "The kext lists the plug-ins" fail "this kext was built for other plug-ins than the ones in $BUNDLES, so it would refuse them. Build both again with ./build.sh: the kext and the plug-ins must come from the same build."
    CAN_INSTALL=0
  fi

  # 3. a macOS the kext starts on (its Lilu settings: Sequoia to Tahoe)
  local darwin=$(/usr/bin/uname -r | cut -d. -f1) product=$(/usr/bin/sw_vers -productVersion 2>/dev/null)
  if [[ $darwin == 24 || $darwin == 25 ]]; then
    add_check loader-macos "macOS version" ok "$product (supported: Sequoia 15 – Tahoe 26)"
  else
    add_check loader-macos "macOS version" fail "$product: the kext only starts on Sequoia 15 and Tahoe 26, and the decoders only work there"
    CAN_INSTALL=0
  fi

  # 4. Lilu (the copy on the EFI is what counts; install looks at that one too)
  local lilu=$(kext_version as.vit9696.Lilu)
  if [[ -z $lilu ]]; then
    add_check loader-lilu "Lilu loaded" warn "Lilu is not loaded now. The kext needs Lilu $MIN_LILU or newer on the EFI; install checks that."
  elif is-at-least $MIN_LILU "$lilu"; then
    add_check loader-lilu "Lilu loaded" ok "Lilu $lilu"
  else
    add_check loader-lilu "Lilu loaded" warn "Lilu $lilu is loaded; the kext needs $MIN_LILU or newer. Update Lilu on your EFI first."
  fi

  # 5. is this kext what this Mac needs?
  if amfi_off; then
    add_check loader-need "Needed on this Mac" warn "no: AMFI is switched off by a boot argument, so the plug-ins already load. The kext is for a Mac that keeps AMFI on."
  elif amfipass_on; then
    add_check loader-need "Needed on this Mac" warn "not now: AMFIPass is running, so the plug-ins already load. Install the kext if you are going to remove AMFIPass. This version was not tried together with a running AMFIPass."
  else
    add_check loader-need "Needed on this Mac" ok "yes: AMFI is on and AMFIPass is not running"
  fi
}

# ---- what is running, and what is on the EFI partitions --------------------------------------
# The kext that is running. Sets RUN_STATE (its status; empty when it is not loaded) and
# RUN_LINE (a sentence about it).
RUN_STATE=""
RUN_LINE=""
look_running() {
  local version=$(kext_version com.droga.VCNVTLoader)
  RUN_STATE=""
  RUN_LINE="not loaded"
  [[ -n $version ]] || return 0
  RUN_STATE=$(loader_prop Status)
  if [[ -z $RUN_STATE ]]; then
    RUN_STATE="no status"
    RUN_LINE="loaded $version, reports no status (versions before 1.1.0 do not)"
    return 0
  fi
  RUN_LINE="loaded $version, $RUN_STATE, lists $(loader_prop AllowedBuilds) plug-in builds, let a plug-in through $(loader_prop Overrides) times since boot"
}

# Does macOS accept the plug-ins right now? Sets ACCEPTED (yes | no | unknown) and
# ACCEPT_WHY. With AMFI off or AMFIPass running the question is not asked: they load
# either way.
ACCEPTED=""
ACCEPT_WHY=""
look_accepted() {
  if amfi_off; then ACCEPT_WHY="AMFI is switched off"; ACCEPTED=yes; return; fi
  if amfipass_on; then ACCEPT_WHY="AMFIPass is running"; ACCEPTED=yes; return; fi
  if [[ ! -x $PROBE || ! -d $BUNDLES/$AV1 || ! -d $BUNDLES/$VP9 ]]; then
    ACCEPT_WHY="decode/build.sh was not run, so macOS cannot be asked"
    ACCEPTED=unknown
    return
  fi
  lv_accepts "$PROBE" "$BUNDLES/$AV1/Contents/MacOS/${AV1%.bundle}" "$BUNDLES/$VP9/Contents/MacOS/${VP9%.bundle}"
  case $? in
    0) ACCEPT_WHY="asked the kernel"; ACCEPTED=yes ;;
    1) ACCEPT_WHY=${PROBE_WHY:-refused}; ACCEPTED=no ;;
    *) ACCEPT_WHY=${PROBE_WHY:-lvprobe failed}; ACCEPTED=unknown ;;
  esac
}

# The whole picture in one line. Needs preflight, look_running, look_accepted and efi_scan.
RESULT=""
RESULT_OK=1
conclude() {
  local accepted=$ACCEPTED
  RESULT_OK=1
  local update=""
  [[ -n $STALE_ON && $CAN_INSTALL -eq 1 ]] && update=" The kext on $STALE_ON is not the one in ${KEXT:h:t}: 'sudo install/loader.sh install' updates it."
  # the kext that runs is what check is about; checks marked FAIL only stop a new install
  local blocked=""
  (( CAN_INSTALL )) || blocked=" The checks marked FAIL stop a new install."
  if [[ $RUN_STATE == active && $accepted == yes ]]; then
    if amfi_off || amfipass_on; then
      RESULT="working: VCNVTLoader is active. $ACCEPT_WHY too, so the plug-ins load either way.$update$blocked"
    else
      RESULT="working: VCNVTLoader is active and macOS accepts the plug-ins.$update$blocked"
    fi
  elif [[ $CAN_INSTALL -eq 0 ]]; then
    RESULT="blocked. Fix the checks marked FAIL first."
    RESULT_OK=0
  elif [[ ( $RUN_STATE == active || $RUN_STATE == "no status" ) && $accepted == no ]]; then
    # running, but not for these plug-ins: Safari does not get them until the right kext boots
    local which="the running kext was built for other plug-ins"
    [[ $RUN_STATE == "no status" ]] && which="the running kext is a version before 1.1.0 and does not accept these plug-ins"
    if [[ -n $READY_ON && -z $STALE_ON ]]; then
      RESULT="$which; the right one is on $READY_ON. Reboot from that EFI."
    else
      RESULT="$which. Run 'sudo install/loader.sh install', then reboot."
      RESULT_OK=0
    fi
  elif [[ $RUN_STATE == "no status" && $accepted == yes ]]; then
    RESULT="working: a VCNVTLoader older than 1.1.0 is running and macOS accepts the plug-ins.$update$blocked"
  elif [[ -n $RUN_STATE && $RUN_STATE != active && $RUN_STATE != "no status" ]]; then
    RESULT="the kext is loaded but does nothing ($RUN_STATE)."
    RESULT_OK=0
  elif [[ -n $READY_ON && -z $STALE_ON ]]; then
    RESULT="installed on $READY_ON, not running yet. Reboot from that EFI to start it."
  else
    RESULT="ready. 'sudo install/loader.sh install' puts the kext on your EFI; then reboot."
  fi
}

do_check() {
  preflight
  look_running
  look_accepted
  efi_scan
  conclude
  local running=$RUN_LINE accepted=$ACCEPTED
  if [[ $JSON -eq 1 ]]; then
    print -rn -- "{\"canInstall\":$([[ $CAN_INSTALL -eq 1 ]] && echo true || echo false),"
    print -rn -- "\"version\":\"$(jesc "$(kext_file_version "$KEXT")")\",\"running\":\"$(jesc "$running")\","
    print -rn -- "\"accepted\":\"$accepted\",\"acceptedDetail\":\"$(jesc "$ACCEPT_WHY")\","
    print -rn -- "\"result\":\"$(jesc "$RESULT")\",\"efis\":[${(j:,:)EFI_JSON}],\"checks\":[${(j:,:)CHECKS}]}"
    print
    return 0
  fi
  print -r -- "VCNVTLoader ${$(kext_file_version "$KEXT"):-(not built)} in $KEXT"
  print -rl -- "${CHECK_LINES[@]}"
  print -r -- "Running now: $running"
  print -r -- "macOS accepts the plug-ins now: $accepted ($ACCEPT_WHY)"
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
    print -r -u2 -- "VCNVTLoader cannot be installed yet. Nothing was changed."
    print -rl -u2 -- "${CHECK_LINES[@]}"
    exit 2
  fi
  kext_install
  print -r -- "Reboot. Then 'install/loader.sh check' tells you in one line whether it works."
  if [[ ! -d $LIVE/$AV1 || ! -d $LIVE/$VP9 ]]; then
    print -r -- "The decoder plug-ins are not installed yet: 'sudo install/decoders.sh install' before you reboot."
  elif [[ "$(cdhash_of "$LIVE/$AV1")" != "$(cdhash_of "$BUNDLES/$AV1")" || "$(cdhash_of "$LIVE/$VP9")" != "$(cdhash_of "$BUNDLES/$VP9")" ]]; then
    if ! { kext_lists "$KEXT" "$LIVE/$AV1" && kext_lists "$KEXT" "$LIVE/$VP9"; }; then
      print -r -- "The decoder plug-ins installed now are another build, which this kext does not list:"
      print -r -- "'sudo install/decoders.sh install' before you reboot."
    fi
  fi
}

do_uninstall() {
  need_root uninstall
  kext_uninstall || return 0
  if [[ -d $LIVE/$AV1 || -d $LIVE/$VP9 ]] && ! amfi_off && ! amfipass_on &&
     [[ "$(codesign -dvv "$LIVE/$AV1" 2>&1)" == *Signature=adhoc* ]]; then
    print -r -- "After the reboot Safari stops using the decoder plug-ins: nothing else on this Mac lets"
    print -r -- "them load. They do no harm while refused. To remove them: sudo install/decoders.sh uninstall"
  fi
}

case "$CMD" in
  check)     do_check ;;
  install)   do_install ;;
  uninstall) do_uninstall ;;
  -h|--help|help) show_help ;;
  "") usage_error "no command given" ;;
  *) usage_error "unknown command '$CMD'" ;;
esac
