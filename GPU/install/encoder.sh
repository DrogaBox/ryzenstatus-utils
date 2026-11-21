#!/bin/zsh
# encoder.sh - installs or removes the optional encoding fix (VCNEncodeFix), and checks
# whether this Mac is ready for it. The fix is for slow or stuttering hardware HEVC/H.264
# encoding (OBS, VideoToolbox) on Navi 21 cards. It never touches the decoders or the macOS
# system volume.
#
#   install/encoder.sh check [--json]                     run the checks; changes nothing, no sudo
#   sudo install/encoder.sh install [--efi diskNsM|auto]  install or update the service; with
#                                                         --efi also the kext
#   sudo install/encoder.sh uninstall [--efi diskNsM]     remove the service; with --efi also
#                                                         the kext
#   install/encoder.sh --help
#
# Options:
#   --efi diskNsM   the EFI partition your Mac boots OpenCore from (see "check" for the list);
#                   --efi auto finds it: what OpenCore says, else the only EFI with OpenCore
#   --package DIR   use the package in DIR instead of encode/dist/VCNEncodeFix-<version>
#   --json          with check: print the result as one JSON object (for a front end)
#
# The fix has two halves:
#   service  /usr/local/libexec/vcnencodefix, started by launchd as com.droga.vcnencodefix.
#            Works at once, no reboot.
#   kext     VCNEncodeFloor.kext in the OpenCore EFI, plus one Kernel > Add entry in
#            config.plist. Works after a reboot. Needs Lilu.
#
# With --efi the partition is mounted if needed (and unmounted again afterwards), checked to
# be an OpenCore EFI with Lilu, and handed to the package's own install.sh or uninstall.sh.
# Those back up config.plist and verify the edit. This script only adds the checks and the
# EFI handling. See install/README.md.
#
# Exit status: 0 done, or check passed; 1 error; 2 a check failed; 3 the EFI's config.plist
# lists the kext with other settings (install refuses it before changing anything); 64 wrong
# usage; or the exit status of the package's install.sh / uninstall.sh when one fails.
# check --json ends with 0.
emulate -L zsh
setopt no_unset
# No pipe_fail here: "command | grep -q" must be true when grep finds its match and stops
# reading early.

SELF_DIR=${0:A:h}
ROOT=${SELF_DIR:h}
source $SELF_DIR/common.zsh
BUILDS_JSON=$SELF_DIR/validated-builds.json
PKG=$ROOT/encode/dist/VCNEncodeFix-$(cat "$ROOT/encode/VERSION" 2>/dev/null)

show_help() { help_of "$SELF_DIR/encoder.sh"; }
usage_error() {
  print -r -u2 -- "encoder.sh: $1"
  print -r -u2 -- "usage: encoder.sh {check [--json] | install [--efi diskNsM|auto] | uninstall [--efi diskNsM|auto]} [--package DIR]"
  exit 64
}

CMD=${1:-}
(( $# )) && shift
EFI_ID=""
JSON=0
while (( $# )); do
  case $1 in
    --efi)
      (( $# >= 2 )) && [[ -n $2 ]] || usage_error "--efi needs a partition, for example disk0s1"
      EFI_ID=$2
      shift ;;
    --package)
      (( $# >= 2 )) && [[ -n $2 ]] || usage_error "--package needs a folder"
      PKG=${2:A}
      shift ;;
    --json) JSON=1 ;;
    -h|--help) show_help; exit 0 ;;
    *) usage_error "unknown option '$1'" ;;
  esac
  shift
done
[[ $JSON -eq 1 && $CMD != check ]] && usage_error "--json goes with check only"
[[ -n $EFI_ID && $CMD == check ]] && usage_error "check looks at every EFI partition; --efi goes with install and uninstall"

TOOL=$PKG/bin/vcnencodefix
LABEL=com.droga.vcnencodefix
BIN_DST=/usr/local/libexec/vcnencodefix
PLIST_DST=/Library/LaunchDaemons/$LABEL.plist

plx() { /usr/bin/plutil -extract "$1" raw -o - "$BUILDS_JSON" 2>/dev/null; }
# VCNVT_FAKE_BUILD is for testing only: it makes 'check' see another macOS build. It is
# ignored by every command that changes the system, so it can never get past a refusal.
macos_build() {
  if [[ $CMD == check && -n ${VCNVT_FAKE_BUILD:-} ]]; then
    print -r -- "$VCNVT_FAKE_BUILD"
  else
    /usr/bin/sw_vers -buildVersion 2>/dev/null
  fi
}
pkg_version() { cat "$PKG/VERSION" 2>/dev/null || echo "?"; }
need_root() { # command
  [[ $EUID -eq 0 ]] || { echo "$1 must run as root: sudo install/encoder.sh $1" >&2; exit 1; }
}

# ---- preflight -----------------------------------------------------------------------------
CAN_INSTALL=0
preflight() {
  CHECKS=()
  CHECK_LINES=()
  CAN_INSTALL=1

  # 0. the package is there, and its files are the ones it was built with
  if [[ ! -x $TOOL || ! -f $PKG/install.sh ]]; then
    add_check enc-bundle "Encoding fix package present" fail "$(pick "no VCNEncodeFix package in $PKG; build it with encode/build.sh" "no VCNEncodeFix package inside RyzenStatus GPU.app; $APP_DAMAGED")"
    CAN_INSTALL=0
  elif ! (cd "$PKG" && shasum -a 256 -c -s SHA256SUMS) >/dev/null 2>&1; then
    add_check enc-bundle "Encoding fix package present" fail "$(pick "the files in $PKG do not match their SHA256SUMS; build the package again with encode/build.sh" "its files do not match their SHA256SUMS; $APP_DAMAGED")"
    CAN_INSTALL=0
  else
    add_check enc-bundle "Encoding fix package present" ok "VCNEncodeFix $(pkg_version)"
  fi

  # 1. this macOS build validated for encoding (the patches target exact Apple and AMD binaries)
  local build=$(macos_build)
  local n i=0 found=0 hit="" name=""
  local -a enc_names=()
  n=$(plx validated)
  while [[ $i -lt ${n:-0} ]]; do
    [[ "$(plx validated.$i.encode)" == "true" ]] && enc_names+=("$(plx validated.$i.name)")
    if [[ $found -eq 0 && "$(plx validated.$i.build)" == "$build" ]]; then
      found=1; hit=$(plx validated.$i.encode); name=$(plx validated.$i.name)
    fi
    i=$((i + 1))
  done
  if [[ "$hit" == "true" ]]; then
    add_check enc-build "macOS build validated for encoding" ok "$name ($build)"
  elif [[ -z "$n" ]]; then
    add_check enc-build "macOS build validated for encoding" fail "the list of validated builds ($BUILDS_JSON) is missing or cannot be read, so build $build cannot be looked up."
    CAN_INSTALL=0
  else
    add_check enc-build "macOS build validated for encoding" fail "build $build is not validated for the encoding fix (validated so far: ${(j:, :)enc_names}). Both halves would stay off."
    CAN_INSTALL=0
  fi

  # 2. the exact Apple/AMD files the service patches are present (the tool checks UUIDs and bytes)
  if [[ -x $TOOL ]]; then
    local st
    st=$("$TOOL" status 2>/dev/null)
    local pre=0 wide=0
    print -r -- "$st" | grep -q 'preset  available' && pre=1
    print -r -- "$st" | grep -q 'wide    available' && wide=1
    if (( pre && wide )); then
      add_check enc-files "Encoder files match" ok "speed preset and >4096-wide fix both apply"
    elif (( pre || wide )); then
      add_check enc-files "Encoder files match" warn "only the $( (( pre )) && echo 'speed preset' || echo '>4096-wide fix') applies on this system"
    else
      add_check enc-files "Encoder files match" fail "neither service patch applies on this system"
      CAN_INSTALL=0
    fi
    # the service needs the encoder process's task port, which macOS only gives root with SIP's Debugging
    # Restrictions off (csr-active-config bit 0x4); without it the kext half still works
    if print -r -- "$st" | grep -q 'access  allowed'; then
      add_check enc-access "Access to the encoder process" ok "SIP Debugging Restrictions are off"
    elif print -r -- "$st" | grep -q 'access  REFUSED'; then
      add_check enc-access "Access to the encoder process" warn "SIP Debugging Restrictions are on, so the service cannot patch the encoder: add 0x4 to csr-active-config in OpenCore and reboot$(pick " (see encode/README.md, Requirements)" ""). The clock-floor kext works without it."
    fi
  fi

  # 3. Navi 21 (the package's install.sh refuses anything else). Every card is looked at, as
  #    install.sh does: with integrated graphics the AMD card is not always the first one.
  local -a gpus=( ${(f)"$(/usr/sbin/system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Chipset Model/{m=$2} /Device ID/{print m" ("$2")"}')"} )
  local g gpu=""
  for g in "${gpus[@]}"; do
    if print -rn -- "$g" | grep -qiE '\(0x73(a[0-9a-f]|bf)\)'; then gpu=$g; break; fi
  done
  if [[ -n "$gpu" ]]; then
    add_check enc-gpu "Navi 21 GPU" ok "$gpu"
  else
    local all=${(j:, :)gpus}
    add_check enc-gpu "Navi 21 GPU" fail "${all:-no AMD GPU found}: the encoding fix is only for Navi 21 (RX 6800 – 6950 XT). On the RX 6600 family (Navi 23) the kext has a floor from that chip's clock table but nothing has run there: the package's own install.sh --force installs it"
    CAN_INSTALL=0
  fi

  # 4. Lilu (only the kext needs it)
  local lilu=$(kext_version as.vit9696.Lilu)
  if [[ -n "$lilu" ]]; then
    add_check enc-lilu "Lilu loaded" ok "Lilu $lilu (needed by the clock-floor kext)"
  else
    add_check enc-lilu "Lilu loaded" warn "Lilu is not loaded: install the service only, or add Lilu to OpenCore first"
  fi
}

# none | current | outdated | unknown (no package to compare with)
installed_state() {
  [[ -e $PLIST_DST ]] || { echo none; return; }
  [[ -f $TOOL ]] || { echo unknown; return; }
  cmp -s "$BIN_DST" "$TOOL" && echo current || echo outdated
}

# What a config.plist says about the clock-floor kext: ok | old (install updates it) |
# differs (disabled, before Lilu, other settings, or Lilu not enabled) | no | unknown.
# ENTRY_STATE holds the answer too and ENTRY_WHY says why when it is not ok; the caller
# sees both only when it does not run this inside $( ).
ENTRY_WHY=""
ENTRY_STATE=""
efi_entry() { # config.plist
  local out line
  ENTRY_WHY=""
  [[ -x $TOOL ]] || { ENTRY_STATE=unknown; echo unknown; return; }
  out=$("$TOOL" efi-check "$1" 2>/dev/null) || { ENTRY_WHY="config.plist could not be read"; ENTRY_STATE=unknown; echo unknown; return; }
  if [[ $out == *"VCNEncodeFloor.kext not listed"* ]]; then ENTRY_STATE=no; echo no; return; fi
  line=${${out##*$'\n'}##  entry <->, }
  if [[ $out != *"Lilu.kext enabled;"* ]]; then
    ENTRY_WHY="Lilu.kext is not enabled in that config.plist"
    ENTRY_STATE=differs; echo differs
  elif [[ $line == "enabled, after Lilu, settings as expected" ]]; then
    ENTRY_STATE=ok; echo ok
  elif [[ $line == "enabled, after Lilu, old entry"* ]]; then
    ENTRY_WHY=$line
    ENTRY_STATE=old; echo old
  else
    ENTRY_WHY=$line
    ENTRY_STATE=differs; echo differs
  fi
}

# none | running | stopped
service_state() {
  [[ -e $PLIST_DST ]] || { echo none; return; }
  pgrep -f "^$BIN_DST watch" >/dev/null && echo running || echo stopped
}

kext_line() {
  local kv=$(kext_version com.droga.VCNEncodeFloor)
  [[ -n "$kv" ]] || { echo "not loaded"; return; }
  local state=$(/usr/sbin/ioreg -rd1 -c IOResources -k VCNEncodeFloor | awk -F'"' '$2 == "VCNEncodeFloor" {print $4}')
  echo "loaded $kv, ${state:-no state published}"
}

# Looks at every EFI partition, without mounting anything. For the mounted ones it says
# whether the partition holds OpenCore, the config entry and the kext.
EFI_JSON=()   # one JSON object per partition
EFI_LINES=()  # the same as text
efi_scan() {
  EFI_JSON=()
  EFI_LINES=()
  local id
  for id in $(/usr/sbin/diskutil list 2>/dev/null | awk '$2 == "EFI" {print $NF}'); do
    [[ $id =~ '^disk[0-9]+s[0-9]+$' ]] || continue
    local info=$(/usr/sbin/diskutil info "$id" 2>/dev/null)
    local name=$(print -r -- "$info" | awk -F': *' '/Volume Name:/{print $2; exit}')
    local mounted=$(print -r -- "$info" | awk -F': *' '/Mounted:/{print $2; exit}')
    local mp=$(print -r -- "$info" | awk -F': *' '/Mount Point:/{print $2; exit}')
    local whole=$(print -r -- "$info" | awk -F': *' '/Part of Whole:/{print $2; exit}')
    local media=$(/usr/sbin/diskutil info "$whole" 2>/dev/null | awk -F': *' '/Device \/ Media Name:/{print $2; exit}')
    local oc=unknown entry=unknown kext=unknown
    if [[ $mounted == Yes && -n "$mp" ]]; then
      if [[ -f $mp/EFI/OC/config.plist ]]; then
        oc=yes
        entry=$(efi_entry "$mp/EFI/OC/config.plist")
        [[ $entry == ok ]] && entry=yes
        local k=$mp/EFI/OC/Kexts/VCNEncodeFloor.kext/Contents/MacOS/VCNEncodeFloor
        if [[ ! -f $k ]]; then kext=missing
        elif [[ ! -f $PKG/Kexts/VCNEncodeFloor.kext/Contents/MacOS/VCNEncodeFloor ]]; then kext=unknown
        elif cmp -s "$k" "$PKG/Kexts/VCNEncodeFloor.kext/Contents/MacOS/VCNEncodeFloor"; then kext=current
        else kext=outdated
        fi
      else
        oc=no
      fi
    fi
    EFI_JSON+=("{\"id\":\"$id\",\"name\":\"$(jesc "${name:-EFI}")\",\"media\":\"$(jesc "${media:-?}")\",\"mounted\":$([[ $mounted == Yes ]] && echo true || echo false),\"mountPoint\":\"$(jesc "$mp")\",\"openCore\":\"$oc\",\"entry\":\"$entry\",\"kext\":\"$kext\"}")
    if [[ $mounted == Yes && -n "$mp" ]]; then
      EFI_LINES+=("  $id  \"${name:-EFI}\" on ${media:-?}: mounted at $mp; OpenCore $oc; config entry $entry; kext $kext")
    else
      EFI_LINES+=("  $id  \"${name:-EFI}\" on ${media:-?}: not mounted, so not looked into")
    fi
  done
}

emit_check_json() {
  efi_scan
  print -rn -- "{\"canInstall\":$([[ $CAN_INSTALL -eq 1 ]] && echo true || echo false),"
  print -rn -- "\"version\":\"$(jesc "$(pkg_version)")\",\"installed\":\"$(installed_state)\",\"service\":\"$(service_state)\","
  print -rn -- "\"kext\":\"$(jesc "$(kext_line)")\",\"efis\":[${(j:,:)EFI_JSON}],\"checks\":["
  local first=1 c
  for c in "${CHECKS[@]}"; do
    [[ $first -eq 1 ]] || print -rn -- ","
    print -rn -- "$c"; first=0
  done
  print -r -- "]}"
}

emit_check_text() {
  efi_scan
  print -r -- "VCNEncodeFix $(pkg_version) in $PKG"
  print -rl -- "${CHECK_LINES[@]}"
  case $(installed_state) in
    none)     print -r -- "Service: not installed" ;;
    current)  print -r -- "Service: installed, the same binary as the package; $(service_state)" ;;
    outdated) print -r -- "Service: installed, not the same binary as the package; $(service_state)" ;;
    unknown)  print -r -- "Service: installed; no package in $PKG to compare it with; $(service_state)" ;;
  esac
  print -r -- "Kext: $(kext_line)"
  print -r -- "EFI partitions:"
  if (( ${#EFI_LINES} )); then print -rl -- "${EFI_LINES[@]}"; else print -r -- "  none found"; fi
  local svc=$(installed_state) run=$(service_state) kx=$(kext_line)
  # from the JSON rows, which hold only the states (the text rows hold names too)
  local efi_old=0 efi_bad=0 row
  for row in "${EFI_JSON[@]}"; do
    [[ $row == *'"kext":"outdated"'* ]] && efi_old=1
    [[ $row == *'"entry":"old"'* ]] && efi_old=1
    [[ $row == *'"entry":"differs"'* ]] && efi_bad=1
  done
  # the kext that runs must be the package's version and active
  local kx_ok=0
  [[ $kx == "loaded $(pkg_version), active"* ]] && kx_ok=1
  if [[ $CAN_INSTALL -eq 1 && $svc == current && $run == running && $kx_ok -eq 1 && $efi_old -eq 0 && $efi_bad -eq 0 ]]; then
    print -r -- "Result: installed and working. The service and the kext are the ones in the package; nothing to do."
  elif [[ $CAN_INSTALL -eq 1 && $svc != none ]]; then
    local what=()
    [[ $svc == outdated ]] && what+=("the service")
    (( efi_old )) && what+=("the kext on the EFI")
    [[ $kx == loaded* && $kx_ok -eq 0 && $efi_old -eq 0 ]] && what+=("the kext (${kx#loaded }; the package has $(pkg_version))")
    [[ $svc == current && $run != running ]] && what+=("the service, which is not running")
    (( efi_bad )) && print -r -- "Note: an EFI's config.plist lists the clock-floor kext with other settings; install refuses that EFI until the entry is fixed or removed by hand."
    if (( ${#what} )); then
      print -r -- "Result: installed; an update is ready for ${(j: and :)what}: $(pick "'sudo install/encoder.sh install' (add --efi auto, or --efi diskNsM, for the kext)" "Encoding fix > Update or Reinstall in this window")."
    else
      print -r -- "Result: installed. The kext is not loaded: $(pick "'sudo install/encoder.sh install --efi diskNsM'" "Encoding fix > Reinstall in this window") adds it, then reboot."
    fi
  elif [[ $CAN_INSTALL -eq 1 ]]; then
    print -r -- "Result: ready. $(pick "'sudo install/encoder.sh install' can run (add --efi auto, or --efi diskNsM, for the kext)" "Encoding fix > Install in this window can run")."
  else
    print -r -- "Result: blocked. Fix the checks marked FAIL first."
  fi
}

emit_check() {
  if [[ $JSON -eq 1 ]]; then emit_check_json; else emit_check_text; fi
}

# ---- install and uninstall (root). efi_open and efi_close are in common.zsh. ---------------
# The partition a run mounted (OPEN_ID, in common.zsh) is unmounted again however the run
# ends.
enc_cleanup() { [[ -n $OPEN_ID ]] && efi_close "$OPEN_ID"; OPEN_ID=""; }
trap enc_cleanup EXIT
trap 'enc_cleanup; exit 130' INT TERM HUP

# --efi auto: find the partition now, or stop before anything is changed.
resolve_efi() {
  [[ $EFI_ID == auto ]] || return 0
  if efi_find_opencore; then
    EFI_ID=$EFI_FOUND
    echo "Using $EFI_ID: $EFI_FIND_WHY."
  else
    if (( IN_APP )); then
      echo "Cannot tell which EFI partition to use: $EFI_FIND_WHY." >&2
      echo "Nothing was changed. To name the one you boot from, run in Terminal:" >&2
      echo "  sudo '$SELF_DIR/encoder.sh' $CMD --efi diskNsM   (diskutil list shows them)" >&2
      echo "With bit 0x1 in OpenCore's Misc > Security > ExposeSensitiveData, this Mac tells which one it started from and the choice is made for you." >&2
    else
      echo "Cannot tell which EFI partition to use: $EFI_FIND_WHY. Name it: sudo install/encoder.sh $CMD --efi diskNsM. Nothing was changed." >&2
    fi
    exit 1
  fi
}

do_install() {
  need_root install
  preflight
  [[ $CAN_INSTALL -eq 1 ]] || { echo "the encoding fix cannot be installed on this Mac (see the checks)" >&2; print -rl -u2 -- "${CHECK_LINES[@]}"; exit 2; }
  local rc
  resolve_efi
  if [[ -n "$EFI_ID" ]]; then
    OPEN_ID=$EFI_ID
    efi_open "$EFI_ID" lilu || { OPEN_ID=""; exit 1; }
    # install.sh changes the service before it edits config.plist: refuse an entry it
    # could not update before anything is changed
    efi_entry "$EFI_MP/EFI/OC/config.plist" > /dev/null
    if [[ $ENTRY_STATE == differs || $ENTRY_STATE == unknown ]]; then
      echo "config.plist on $EFI_ID: ${ENTRY_WHY:-cannot be checked}. Fix or remove the VCNEncodeFloor.kext entry by hand (or enable Lilu), then run this again. Nothing was changed." >&2
      exit 3
    fi
    /bin/zsh "$PKG/install.sh" --efi "$EFI_MP" 2>&1
    rc=$?
    enc_cleanup
  else
    /bin/zsh "$PKG/install.sh" 2>&1
    rc=$?
  fi
  [[ $rc -eq 0 ]] || { echo "VCNEncodeFix install.sh failed ($rc); see the lines above" >&2; exit $rc; }
  echo "OK"
}

do_uninstall() {
  need_root uninstall
  [[ -f $PKG/uninstall.sh ]] || { echo "$(pick "no VCNEncodeFix package in $PKG; build it with encode/build.sh" "no VCNEncodeFix package inside RyzenStatus GPU.app; $APP_DAMAGED")" >&2; exit 1; }
  local rc
  resolve_efi
  if [[ -n "$EFI_ID" ]]; then
    # taking the kext off needs no Lilu on that EFI
    OPEN_ID=$EFI_ID
    efi_open "$EFI_ID" || { OPEN_ID=""; exit 1; }
    /bin/zsh "$PKG/uninstall.sh" --efi "$EFI_MP" 2>&1
    rc=$?
    enc_cleanup
  else
    /bin/zsh "$PKG/uninstall.sh" 2>&1
    rc=$?
  fi
  [[ $rc -eq 0 ]] || { echo "VCNEncodeFix uninstall.sh failed ($rc); see the lines above" >&2; exit $rc; }
  echo "OK"
}

case "$CMD" in
  check)
    preflight
    emit_check
    # the JSON form always ends with 0, as the front end expects; the text form tells a
    # script whether install would go ahead
    [[ $JSON -eq 1 || $CAN_INSTALL -eq 1 ]] && exit 0
    exit 2 ;;
  install)   do_install ;;
  uninstall) do_uninstall ;;
  -h|--help|help) show_help ;;
  "") usage_error "no command given" ;;
  *) usage_error "unknown command '$CMD'" ;;
esac
