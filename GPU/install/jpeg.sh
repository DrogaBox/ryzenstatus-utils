#!/bin/zsh
# jpeg.sh - puts VCNJpeg.kext on your OpenCore EFI or takes it off, and checks whether it
# works. VCNJpeg lets the JPEG and Motion JPEG plug-in (decoders.sh --jpeg) decode on the JPEG
# block of the GPU; see jpeg/README.md. It is optional, off by default, and only for macOS
# 26.7.3 (25G342) on a Navi 21 card.
#
#   install/jpeg.sh check [--json]                  look at this Mac; changes nothing, no sudo
#   sudo install/jpeg.sh install [--efi diskNsM]    copy the kext and add its entry to
#                                                   config.plist; then reboot
#   sudo install/jpeg.sh uninstall [--efi diskNsM]  remove the entry and the kext; then reboot
#   install/jpeg.sh --help
#
# Options:
#   --efi diskNsM      the EFI partition your Mac boots OpenCore from. Without it the script
#                      takes the one OpenCore says it started from, or the only one that
#                      holds OpenCore. When it cannot tell, it lists them and stops.
#   --efi-folder DIR   instead of a partition: a folder that holds EFI/OC (a mounted EFI, a
#                      USB stick, a copy). Nothing is mounted or unmounted.
#   --kext DIR         the kext to install (default jpeg/build/VCNJpeg.kext)
#   --json             with check: print the result as one JSON object (for a front end)
#
# What install changes is described in install/efikext.zsh: the kext is copied into
# EFI/OC/Kexts and one entry is added to Kernel > Add after Lilu, with a backup of
# config.plist written first and the edit verified.
#
# The kext takes a block of 128 MiB of the GPU's system-memory aperture when the driver
# starts (vcnjpegpool=<MiB> in the boot arguments, 8 to 128, changes it). If the Mac does not
# start after the reboot: start it from another EFI (a USB stick) and copy the backup over
# EFI/OC/config.plist, or add -vcnjpegoff to the boot arguments.
#
# Exit status: 0 done, or check found the kext working or nothing in the way; 1 error; 2
# check found it not working or blocked; 64 wrong usage. check --json ends with 0.
emulate -L zsh
setopt no_unset
# No pipe_fail here: "command | grep -q" must be true when grep finds its match and stops
# reading early.
autoload -Uz is-at-least

SELF_DIR=${0:A:h}
ROOT=${SELF_DIR:h}
source $SELF_DIR/common.zsh
KEXT=$ROOT/jpeg/build/VCNJpeg.kext
ENTRY=$ROOT/decode/build/kextentry
KNAME=VCNJpeg
KEXEC=VCNJpeg
KBUNDLE=com.droga.VCNJpeg
KOFFARG=-vcnjpegoff
SCRIPT=jpeg.sh
MIN_LILU=1.7.0
BUILDS_JSON=$SELF_DIR/validated-builds.json

show_help() { help_of "$SELF_DIR/jpeg.sh"; }
usage_error() {
  print -r -u2 -- "jpeg.sh: $1"
  print -r -u2 -- "usage: jpeg.sh {check [--json] [--efi-folder DIR] | install | uninstall [--efi diskNsM | --efi-folder DIR]} [--kext DIR]"
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

# Every copy of the kext can do its job: what it depends on is the macOS build, checked below.
kext_usable() { return 0; }
USABLE_KEY=usable
USABLE_YES=""
USABLE_NO="cannot be used"
source $SELF_DIR/efikext.zsh

# Sets JPEG_BUILD (this macOS build) and JPEG_VALUE, its "jpeg" value in
# validated-builds.json: true, untested-on-gpu, false, or empty when the build is not listed.
# VCNVT_FAKE_BUILD is for testing only, and only with check, like in decoders.sh.
JPEG_BUILD=""
JPEG_VALUE=""
jpeg_build_value() {
  local n i
  JPEG_BUILD=$(/usr/bin/sw_vers -buildVersion 2>/dev/null)
  [[ $CMD == check && -n ${VCNVT_FAKE_BUILD:-} ]] && JPEG_BUILD=$VCNVT_FAKE_BUILD
  JPEG_VALUE=""
  n=$(/usr/bin/plutil -extract validated raw -o - "$BUILDS_JSON" 2>/dev/null)
  [[ $n == <-> ]] || return 0
  for (( i = 0; i < n; i++ )); do
    if [[ $(/usr/bin/plutil -extract validated.$i.build raw -o - "$BUILDS_JSON" 2>/dev/null) == $JPEG_BUILD ]]; then
      JPEG_VALUE=$(/usr/bin/plutil -extract validated.$i.jpeg raw -o - "$BUILDS_JSON" 2>/dev/null)
      return 0
    fi
  done
}

# ---- preflight -----------------------------------------------------------------------------
CAN_INSTALL=0
preflight() {
  CHECKS=()
  CHECK_LINES=()
  CAN_INSTALL=1

  # 1. the kext and the helper that edits config.plist are built
  if [[ ! -f $KEXT/Contents/MacOS/$KEXEC || ! -f $KEXT/Contents/Info.plist ]]; then
    add_check jpeg-kext "JPEG kext built" fail "$(pick "no VCNJpeg.kext in ${KEXT:h}; build it with ./build.sh jpeg (tools/bootstrap.sh once before)" "no VCNJpeg.kext inside RyzenStatus GPU.app; $APP_DAMAGED")"
    CAN_INSTALL=0
  elif [[ ! -x $ENTRY ]]; then
    add_check jpeg-kext "JPEG kext built" fail "$(pick "$ENTRY is missing; decode/build.sh builds it" "kextentry is missing; $APP_DAMAGED")"
    CAN_INSTALL=0
  else
    add_check jpeg-kext "JPEG kext built" ok "VCNJpeg $(kext_file_version "$KEXT")"
  fi

  # 2. the macOS build the kext was made for (it compares the driver's own code at start)
  jpeg_build_value
  case $JPEG_VALUE in
    true)            add_check jpeg-macos "macOS build" ok "$JPEG_BUILD" ;;
    untested-on-gpu) add_check jpeg-macos "macOS build" warn "$JPEG_BUILD: the kext was made for this build, but this version has not decoded on a GPU yet" ;;
    *)               add_check jpeg-macos "macOS build" fail "${JPEG_BUILD:-unknown}: the kext only knows macOS 26.7.3 (25G342) and would stay off"
                     CAN_INSTALL=0 ;;
  esac

  # 3. a Navi 21 card (the JPEG block that was studied). VCNVT_FAKE_GPU: as in sensors.sh.
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
    add_check jpeg-gpu "Navi 21 GPU" ok "$gpu"
  else
    local all=${(j:, :)gpus}
    add_check jpeg-gpu "Navi 21 GPU" fail "${all:-no AMD GPU found}: the JPEG kext is only for Navi 21 (RX 6800 – 6950 XT)"
    CAN_INSTALL=0
  fi

  # 4. the test kext it grew from routes the same functions: never both
  if [[ -n $(kext_version com.droga.VCNJpegProbe) ]]; then
    add_check jpeg-probe "Test kext VCNJpegProbe" fail "VCNJpegProbe is loaded; take it off the EFI and reboot first: both route the same driver functions"
    CAN_INSTALL=0
  fi

  # 5. Lilu (the copy on the EFI is what counts; install looks at that one too)
  local lilu=$(kext_version as.vit9696.Lilu)
  if [[ -z $lilu ]]; then
    add_check jpeg-lilu "Lilu loaded" warn "Lilu is not loaded now. The kext needs Lilu $MIN_LILU or newer on the EFI; install checks that."
  elif is-at-least $MIN_LILU "$lilu"; then
    add_check jpeg-lilu "Lilu loaded" ok "Lilu $lilu"
  else
    add_check jpeg-lilu "Lilu loaded" warn "Lilu $lilu is loaded; the kext needs $MIN_LILU or newer. Update Lilu on your EFI first."
  fi
}

# ---- what is running -------------------------------------------------------------------------
# One field of the kext's dictionary on IOResources ("VCNJpeg" = {"State"="...","Jobs"=3,...}).
# A string value may hold commas, so each field is cut out by its own name.
jpeg_prop() { # name
  /usr/sbin/ioreg -r -d 1 -c IOResources -k VCNJpeg 2>/dev/null | grep '"VCNJpeg" = {' | head -1 |
    sed -n -e "s/.*\"$1\"=\"\([^\"]*\)\".*/\1/p" -e "t" -e "s/.*\"$1\"=\([0-9A-Za-z]*\).*/\1/p"
}
RUN_STATE=""
RUN_LINE=""
RUN_VERSION=""
look_running() {
  RUN_VERSION=$(kext_version com.droga.VCNJpeg)
  RUN_STATE=""
  RUN_LINE="not loaded"
  [[ -n $RUN_VERSION ]] || return 0
  RUN_STATE=$(jpeg_prop State)
  RUN_LINE="loaded $RUN_VERSION, ${RUN_STATE:-no state}, $(jpeg_prop Jobs) pictures decoded since boot"
}

RESULT=""
RESULT_OK=1
PENDING_REBOOT=0
conclude() {
  RESULT_OK=1
  PENDING_REBOOT=0
  local new=$(kext_file_version "$KEXT") on_efi=0
  [[ -n $READY_ON && -z $STALE_ON && -n $new && $RUN_VERSION != "$new" ]] && on_efi=1
  local next=""
  (( on_efi )) && next=" VCNJpeg $new is on $READY_ON and loads at the next boot."
  local update=""
  [[ -n $STALE_ON && $CAN_INSTALL -eq 1 ]] && update=" The kext on $STALE_ON is not the one in ${KEXT:h:t}: 'sudo install/jpeg.sh install' updates it."
  local blocked=""
  (( CAN_INSTALL )) || blocked=" The checks marked FAIL stop a new install."
  if [[ $RUN_STATE == (ready*|decoding*) ]]; then
    RESULT="working: VCNJpeg is $RUN_STATE. The JPEG plug-in (decoders.sh --jpeg) decodes on the GPU.$next$update$blocked"
    PENDING_REBOOT=$on_efi
  elif [[ -n $RUN_STATE ]]; then
    RESULT="the kext is loaded but does not decode ($RUN_STATE).$next"
    RESULT_OK=0
    PENDING_REBOOT=$on_efi
  elif [[ -n $RUN_VERSION ]] && (( on_efi )); then
    RESULT="installed on $READY_ON: VCNJpeg $new loads at the next boot; $RUN_VERSION runs until then. Reboot from that EFI to start it."
    PENDING_REBOOT=1
  elif [[ $CAN_INSTALL -eq 0 ]]; then
    RESULT="blocked. Fix the checks marked FAIL first."
    RESULT_OK=0
  elif [[ -n $READY_ON && -z $STALE_ON ]]; then
    RESULT="installed on $READY_ON, not running yet. Reboot from that EFI to start it."
    PENDING_REBOOT=1
  else
    RESULT="ready. 'sudo install/jpeg.sh install' puts the kext on your EFI; then reboot."
  fi
}

check_json() {
  print -rn -- "{\"canInstall\":$([[ $CAN_INSTALL -eq 1 ]] && echo true || echo false),"
  print -rn -- "\"version\":\"$(jesc "$(kext_file_version "$KEXT")")\",\"running\":\"$(jesc "$RUN_LINE")\","
  print -rn -- "\"pendingReboot\":$([[ $PENDING_REBOOT -eq 1 ]] && echo true || echo false),"
  print -rn -- "\"result\":\"$(jesc "$RESULT")\",\"efis\":[${(j:,:)EFI_JSON}],\"checks\":[${(j:,:)CHECKS}]}"
  print
}

do_check() {
  preflight
  look_running
  efi_scan
  efi_choice_check jpeg-efi
  conclude
  if [[ $JSON -eq 1 ]]; then
    check_json
    return 0
  fi
  local json_to=$(check_json_to)
  [[ -n $json_to ]] && check_json > "$json_to"
  print -r -- "VCNJpeg ${$(kext_file_version "$KEXT"):-(not built)} in $KEXT"
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
    print -r -u2 -- "VCNJpeg cannot be installed yet. Nothing was changed."
    print -rl -u2 -- "${CHECK_LINES[@]}"
    exit 2
  fi
  kext_install
  print -r -- "Reboot. Then 'install/jpeg.sh check' tells you in one line whether it works."
  print -r -- "The JPEG plug-in goes in with 'sudo install/decoders.sh install --jpeg'."
}

do_uninstall() {
  need_root uninstall
  kext_uninstall || return 0
}

case "$CMD" in
  check)     do_check ;;
  install)   do_install ;;
  uninstall) do_uninstall ;;
  -h|--help|help) show_help ;;
  "") usage_error "no command given" ;;
  *) usage_error "unknown command '$CMD'" ;;
esac
