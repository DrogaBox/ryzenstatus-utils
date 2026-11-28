#!/bin/zsh
# decoders.sh - installs, repairs or removes the decoder plug-ins (AV1 and VP9; with --legacy
# also MPEG-2, VC-1 and MPEG-4; with --jpeg also JPEG) in the system folder
# /System/Library/Video/Plug-Ins, and checks
# whether this Mac is ready for them.
#
#   install/decoders.sh check [--json]           run the checks; changes nothing, no sudo needed
#   sudo install/decoders.sh install [--force]   copy both plug-ins into the system volume
#   sudo install/decoders.sh repair [--force]    put back every Apple plug-in missing from the
#                                                system folder, then install both plug-ins
#   sudo install/decoders.sh uninstall           remove every decoder plug-in of ours
#   install/decoders.sh --help
#
# Options:
#   --force         install on a macOS build that is not in install/validated-builds.json.
#                   The video driver of that build was not checked, and a wrong message to
#                   it can hang the GPU.
#   --bundles DIR   take the plug-ins from DIR instead of decode/build
#   --legacy        with check, install and repair: the MPEG-2, VC-1 and MPEG-4 plug-ins
#                   too (the same as VCNVT_LEGACY_DECODERS=1). Off by default: they have
#                   not run through VideoToolbox on a GPU yet. Without it, install and
#                   repair take off the three if an earlier install with --legacy left
#                   them, and check reports them. uninstall always removes them with the
#                   other two.
#   --jpeg          with check, install and repair: the JPEG and Motion JPEG plug-in too (the
#                   same as VCNVT_JPEG_DECODER=1). It decodes through the VCNJpeg kext
#                   (install/jpeg.sh), which must be installed as well. Without it, install
#                   and repair take it off if an earlier install with --jpeg left it, and
#                   check reports it. uninstall always removes it.
#   --json          with check: print the result as one JSON object (for a front end)
#
# install, repair and uninstall change a mounted copy of the system volume and then create a
# new boot snapshot from it. They need root, "authenticated-root" disabled, and a reboot.
# The running system keeps its plug-ins until that reboot. One thing happens at once:
# install removes a leftover copy of our plug-ins from /Library/Video/Plug-Ins.
# See install/README.md.
#
# Why /System and not /Library: VideoToolbox loads plug-ins from
# /System/Library/Video/Plug-Ins without checking their signature. In /Library/Video/Plug-Ins
# it only accepts plug-ins signed by Apple.
#
# Exit status: 0 done, or check passed; 1 error; 2 a blocking check failed; 3 this macOS
# build is not validated (--force overrides); 4 the system plug-in folder looks damaged
# (use repair); 5 Apple's original snapshot was not found or did not mount; 6 Apple's
# plug-ins could not be restored; 64 wrong usage.
emulate -L zsh
setopt no_unset
# No pipe_fail here: "command | grep -q" must be true when grep finds its match and stops
# reading early.

SELF_DIR=${0:A:h}
ROOT=${SELF_DIR:h}
source $SELF_DIR/common.zsh
BUILDS_JSON=$SELF_DIR/validated-builds.json
BUNDLES=$ROOT/decode/build

AV1=AV1VCNDecoder.bundle
VP9=VP9VCNDecoder.bundle
PLUGDIR=System/Library/Video/Plug-Ins
# the plug-in folder of the running system (only read)
LIVE=/$PLUGDIR
# where the writable system volume is mounted
MNT=/System/Volumes/Update/mnt1
# where Apple's original snapshot is mounted, read-only, during a repair: a new folder of
# root's (mktemp) each time, never a fixed name another user could create or mount on first
SEALMNT=""
# VideoToolbox ignores our plug-ins here; a copy left in it is removed by install
LIBPLUG=/Library/Video/Plug-Ins

show_help() { help_of "$SELF_DIR/decoders.sh"; }
usage_error() {
  print -r -u2 -- "decoders.sh: $1"
  print -r -u2 -- "usage: decoders.sh {check [--json] | install [--force] | repair [--force] | uninstall} [--bundles DIR] [--legacy] [--jpeg]"
  exit 64
}

CMD=${1:-}
(( $# )) && shift
FORCE=0
JSON=0
while (( $# )); do
  case $1 in
    --force) FORCE=1 ;;
    --json) JSON=1 ;;
    --bundles)
      (( $# >= 2 )) && [[ -n $2 ]] || usage_error "--bundles needs a folder"
      BUNDLES=${2:A}
      shift ;;
    --legacy) export VCNVT_LEGACY_DECODERS=1 ;;
    --jpeg) export VCNVT_JPEG_DECODER=1 ;;
    -h|--help) show_help; exit 0 ;;
    *) usage_error "unknown option '$1'" ;;
  esac
  shift
done
# The plug-ins this run installs and checks; uninstall takes off all of ALL.
WANT=($AV1 $VP9)
legacy_on && WANT+=($LEGACY_BUNDLES)
jpeg_on && WANT+=($JPEG_BUNDLE)
ALL=($AV1 $VP9 $LEGACY_BUNDLES $JPEG_BUNDLE)
all_built() { local b; for b in $WANT; do [[ -d $BUNDLES/$b ]] || return 1; done; }
# The MPEG-2, VC-1 and MPEG-4 plug-ins in a plug-in folder when this run leaves them out (no
# --legacy): an earlier install with --legacy put them there. One name per line.
stale_legacy() { # folder
  legacy_on && return 0
  local b
  for b in $LEGACY_BUNDLES; do [[ -e $1/$b || -L $1/$b ]] && print -r -- $b; done
  return 0
}
# The JPEG plug-in in a plug-in folder when this run leaves it out (no --jpeg).
stale_jpeg() { # folder
  jpeg_on && return 0
  [[ -e $1/$JPEG_BUNDLE || -L $1/$JPEG_BUNDLE ]] && print -r -- $JPEG_BUNDLE
  return 0
}
[[ $JSON -eq 1 && $CMD != check ]] && usage_error "--json goes with check only"
[[ $FORCE -eq 1 && $CMD != install && $CMD != repair ]] && usage_error "--force goes with install and repair only"
# VCNVT_FAKE_RECORDS and VCNVT_FAKE_LIVE are for testing only (tests/loader_install.sh), and
# like VCNVT_FAKE_BUILD they count for check only, which changes nothing: a folder of the
# user's for the install record (common.zsh), and a folder that stands in for the plug-ins
# of the running system.
if [[ $CMD == check ]]; then
  RECORD_FAKE_OK=1
  [[ -n ${VCNVT_FAKE_LIVE:-} ]] && LIVE=${VCNVT_FAKE_LIVE:A}
fi

# ---- small helpers -------------------------------------------------------------------------
plx() { /usr/bin/plutil -extract "$1" raw -o - "$BUILDS_JSON" 2>/dev/null; }

macos_product() { /usr/bin/sw_vers -productVersion 2>/dev/null; }
# VCNVT_FAKE_BUILD is for testing only: it makes 'check' see another macOS build. It is
# ignored by every command that changes the system, so it can never get past a refusal.
macos_build() {
  if [[ $CMD == check && -n ${VCNVT_FAKE_BUILD:-} ]]; then
    print -r -- "$VCNVT_FAKE_BUILD"
  else
    /usr/bin/sw_vers -buildVersion 2>/dev/null
  fi
}
macos_major()   { macos_product | cut -d. -f1; }

# ---- what lets the plug-ins into Safari's media processes ----------------------------------
# boot_args, amfi_off, amfipass_on, loader_prop, kext_lists and lv_accepts are in common.zsh.
# adhoc | signed | none
sig_kind() { # bundle
  local d=$(codesign -dvv "$1" 2>&1)
  if print -r -- "$d" | grep -q '^Signature=adhoc'; then print adhoc
  elif print -r -- "$d" | grep -q '^Authority='; then print signed
  else print none
  fi
}
sig_authority() { codesign -dvv "$1" 2>&1 | sed -n 's/^Authority=//p' | tail -1; }
# True when the EFI/OC folder holds a VCNVTLoader.kext that lists both plug-ins, enabled
# after an enabled Lilu in config.plist: that kext starts working at the next boot.
loader_in() { # EFI/OC folder
  local oc=$1 cfg=$1/config.plist out i bp
  [[ -f $cfg && -d $oc/Kexts/VCNVTLoader.kext ]] || return 1
  local b
  for b in $WANT; do kext_lists "$oc/Kexts/VCNVTLoader.kext" "$BUNDLES/$b" || return 1; done
  if [[ -x $ROOT/decode/build/kextentry ]]; then
    out=$("$ROOT/decode/build/kextentry" VCNVTLoader check "$cfg" 2>/dev/null) || return 1
    [[ $out == *"Lilu.kext enabled;"* && ${out##*$'\n'} == *", enabled, after Lilu, settings as expected" ]]
    return
  fi
  i=0
  while bp=$(/usr/bin/plutil -extract "Kernel.Add.$i.BundlePath" raw -o - "$cfg" 2>/dev/null); do
    if [[ $bp == VCNVTLoader.kext ]]; then
      [[ $(/usr/bin/plutil -extract "Kernel.Add.$i.Enabled" raw -o - "$cfg" 2>/dev/null) == true ]]
      return
    fi
    i=$((i + 1))
  done
  return 1
}
# An OpenCore EFI with such a kext: prints where. The mounted ones are looked at first. As
# root the others are looked at too, mounted read-only and unmounted again, because
# 'loader.sh install' unmounts the partition it used and then sends the user here.
pending_loader() {
  local oc id mp found
  for oc in /Volumes/*/EFI/OC(N); do
    loader_in "$oc" && { print -r -- "$oc"; return 0; }
  done
  (( EUID == 0 )) || return 1
  for id in $(efi_ids); do
    [[ $(efi_field $id Mounted) == Yes ]] && continue
    /usr/sbin/diskutil mount readOnly $id >/dev/null 2>&1 || continue
    mp=$(efi_field $id 'Mount Point')
    found=1
    [[ -n $mp ]] && loader_in "$mp/EFI/OC" && found=0
    /usr/sbin/diskutil unmount $id >/dev/null 2>&1 || { sleep 2; /usr/sbin/diskutil unmount $id >/dev/null 2>&1; }
    (( found == 0 )) && { print -r -- "EFI/OC on $id"; return 0; }
  done
  return 1
}
# Does macOS accept both plug-ins right now? Sets PROBE_WHY to the kernel's reason when it
PROBE=$ROOT/decode/build/lvprobe
probe_accepts() {
  local -a exes=() b
  for b in $WANT; do exes+=("$(plugin_exe $BUNDLES $b)"); done
  lv_accepts "$PROBE" "${exes[@]}"
}
authroot_disabled() { csrutil authenticated-root status 2>/dev/null | grep -qi disabled; }

# every graphics card of this Mac, one name per line
gpu_models() { displays_report | awk -F': ' '/Chipset Model/{print $2}'; }

# The device mounted at a folder; prints nothing when nothing is mounted there.
mounted_device() { # folder
  mount | awk -v mp="$1" '{ i = index($0, " on " mp " ("); if (i) { print substr($0, 1, i - 1); exit } }'
}

need_root() { # command
  [[ $EUID -eq 0 ]] || { echo "$1 must run as root: sudo install/decoders.sh $1" >&2; exit 1; }
}

# ---- preflight -----------------------------------------------------------------------------
# Globals set by preflight():
#   CAN_INSTALL        1 = install would go ahead
#   BLOCK_OVERRIDABLE  1 = the only thing in the way is the unvalidated build (--force)
#   REPAIRABLE         1 = the only blocking failure is the damaged system folder (repair)
CAN_INSTALL=0; HARD_FAIL=0; SOFT_FAIL=1; SYS_DAMAGED=0; HARD_OTHER=0; BLOCK_OVERRIDABLE=0; REPAIRABLE=0
preflight() {
  CAN_INSTALL=1; HARD_FAIL=0; SOFT_FAIL=0; SYS_DAMAGED=0
  CHECKS=()
  CHECK_LINES=()
  # HARD_OTHER = hard failures other than a damaged Plug-Ins folder (which `repair` can fix)
  HARD_OTHER=0

  # 1. macOS in supported range (Sequoia 15 .. Tahoe 26)
  local prod=$(macos_product)
  local major=$(macos_major)
  if [[ -n "$major" && "$major" -ge 15 && "$major" -le 26 ]]; then
    add_check macos "macOS version" ok "$prod (supported: Sequoia 15 – Tahoe 26)"
  else
    add_check macos "macOS version" fail "${prod:-unknown} is outside the supported range (Sequoia 15 – Tahoe 26)"
    HARD_FAIL=1; HARD_OTHER=1
  fi

  # 2. driver build validated (hang risk if not)
  local build=$(macos_build)
  local n hit=0 name="" i=0
  n=$(plx validated)
  while [[ $i -lt ${n:-0} ]]; do
    if [[ "$(plx validated.$i.build)" == "$build" ]]; then hit=1; name=$(plx validated.$i.name); break; fi
    i=$((i + 1))
  done
  # A listed build can still be one the decoders refuse: av1 and vp9 say false there (the
  # build is in the list for the encoding fix only).
  local av1v="" vp9v=""
  if [[ $hit -eq 1 ]]; then av1v=$(plx validated.$i.av1); vp9v=$(plx validated.$i.vp9); fi
  if [[ $hit -eq 1 && $av1v == false && $vp9v == false ]]; then
    add_check driver "GPU driver validated" fail "$name ($build) is listed for the encoding fix only: the decoders refuse its video driver, so Safari would keep decoding in software. Nothing to install here."
    HARD_FAIL=1; HARD_OTHER=1
  elif [[ $hit -eq 1 && ( $av1v == false || $vp9v == false ) ]]; then
    add_check driver "GPU driver validated" warn "$name ($build): only $([[ $av1v == false ]] && print VP9 || print AV1) works with this video driver; the other plug-in stays off"
  elif [[ $hit -eq 1 ]]; then
    add_check driver "GPU driver validated" ok "$name ($build): AMD VCN driver validated"
  elif [[ -z "$n" ]]; then
    add_check driver "GPU driver validated" fail "the list of validated builds ($BUILDS_JSON) is missing or cannot be read, so build $build cannot be looked up — installing may HANG the GPU."
    SOFT_FAIL=1
  else
    add_check driver "GPU driver validated" fail "build $build is not in the validated list — installing may HANG the GPU. Validate it first, or override with --force at your own risk."
    SOFT_FAIL=1
  fi
  # The MPEG-2, VC-1 and MPEG-4 plug-ins share one list of drivers ("legacy" in the JSON).
  if legacy_on && [[ $hit -eq 1 ]]; then
    local legv=$(plx validated.$i.legacy)
    if [[ $legv == false || -z $legv ]]; then
      add_check legacy "MPEG-2, VC-1 and MPEG-4 on this driver" fail "the MPEG-2, VC-1 and MPEG-4 plug-ins refuse the video driver of $name ($build); install without --legacy"
      HARD_FAIL=1; HARD_OTHER=1
    elif [[ $legv == untested-on-gpu ]]; then
      add_check legacy "MPEG-2, VC-1 and MPEG-4 on this driver" warn "$name ($build): driver validated, but these plug-ins have not run through VideoToolbox on a GPU yet"
    else
      add_check legacy "MPEG-2, VC-1 and MPEG-4 on this driver" ok "$name ($build)"
    fi
  fi
  # The JPEG plug-in works through the VCNJpeg kext, which was checked on one build ("jpeg").
  if jpeg_on && [[ $hit -eq 1 ]]; then
    local jpv=$(plx validated.$i.jpeg)
    if [[ $jpv == false || -z $jpv ]]; then
      add_check jpeg "JPEG on this macOS build" fail "the VCNJpeg kext was not checked on $name ($build), so the JPEG plug-in would find no decoder; install without --jpeg"
      HARD_FAIL=1; HARD_OTHER=1
    elif [[ $jpv == untested-on-gpu ]]; then
      add_check jpeg "JPEG on this macOS build" warn "$name ($build): the VCNJpeg kext was checked, but this version has not decoded on a GPU yet"
    else
      add_check jpeg "JPEG on this macOS build" ok "$name ($build)"
    fi
  fi

  # 3. authenticated-root disabled (required to write the sealed system volume)
  if authroot_disabled; then
    add_check authroot "Authenticated-root disabled" ok "sealed /System can be modified"
  else
    add_check authroot "Authenticated-root disabled" fail "run 'csrutil authenticated-root disable' from Recovery first (needs OpenCore low security)"
    HARD_FAIL=1; HARD_OTHER=1
  fi

  # 4. macOS will accept the plug-ins in Safari's media processes. Looked at only when the
  #    bundles are there (check 7 reports them missing).
  local label="macOS accepts the plug-ins"
  if ! all_built; then
    :
  elif amfi_off; then
    add_check loading "$label" ok "AMFI is switched off in the boot arguments, so any plug-in loads"
  elif amfipass_on; then
    add_check loading "$label" ok "AMFIPass is running"
  elif [[ ! -x $PROBE ]]; then
    add_check loading "$label" fail "cannot ask macOS: $(pick "$PROBE is missing. Run decode/build.sh, which builds it." "$APP_DAMAGED.")"
    HARD_FAIL=1; HARD_OTHER=1
  else
    local kind=$(sig_kind "$BUNDLES/$AV1") lstate=$(loader_prop Status) oc
    probe_accepts
    case $? in
      0)
        if [[ $kind == signed ]]; then
          add_check loading "$label" ok "yes: their signature ($(sig_authority "$BUNDLES/$AV1")) is trusted on this Mac"
        elif [[ $lstate == active ]]; then
          add_check loading "$label" ok "yes: VCNVTLoader is running and lists them"
        else
          add_check loading "$label" ok "yes (asked the kernel)"
        fi ;;
      1)
        if oc=$(pending_loader); then
          add_check loading "$label" ok "after a reboot from that EFI: the VCNVTLoader.kext in $oc lists them"
        elif [[ $kind == signed ]]; then
          add_check loading "$label" fail "no: they are signed by '$(sig_authority "$BUNDLES/$AV1")', which this Mac does not trust. $(pick "Load the kext that trusts that CA, or install the unsigned build from decode/build with VCNVTLoader or AMFIPass." "Load the kext that trusts that CA, or use the loader kext (Loader kext > Install in this window) or AMFIPass.")"
          HARD_FAIL=1; HARD_OTHER=1
        elif [[ $lstate == active ]]; then
          add_check loading "$label" fail "no: VCNVTLoader is running but was built for other plug-ins. $(pick "Build both again (./build.sh), run 'sudo install/loader.sh install' and reboot. The kext and the plug-ins must come from the same build." "Update the loader first, in this window: Loader kext > Update. Then install the decoders here; if they still wait, reboot and open this window again. Install what this Mac needs does both in one go.")"
          HARD_FAIL=1; HARD_OTHER=1
        elif [[ -n $lstate ]]; then
          add_check loading "$label" fail "no: VCNVTLoader is loaded but not working ($lstate)."
          HARD_FAIL=1; HARD_OTHER=1
        else
          add_check loading "$label" fail "no: nothing on this Mac lets them into Safari (${PROBE_WHY:-refused}). $(pick "Choose one: put the loader kext on your OpenCore EFI with 'sudo install/loader.sh install' (open source, accepts only these plug-ins; see decode/loader/README.md), or load AMFIPass. Then run this again. If the kext is already on your EFI and you have not rebooted since, reboot first." "Install the loader first, in this window: Loader kext > Install (it accepts only these plug-ins), or load AMFIPass. Then install the decoders here; if they still wait, reboot and open this window again. Install what this Mac needs does both in one go.")"
          HARD_FAIL=1; HARD_OTHER=1
        fi ;;
      *)
        add_check loading "$label" fail "could not ask macOS (${PROBE_WHY:-lvprobe failed}). $(pick "Build again with decode/build.sh." "$APP_DAMAGED.")"
        HARD_FAIL=1; HARD_OTHER=1 ;;
    esac
  fi

  # 5. GPU recognized (soft). Every card is looked at: with integrated graphics the AMD
  #    card is not always the first one listed.
  local -a gpus=( ${(f)"$(gpu_models)"} )
  local g gpu=""
  for g in "${gpus[@]}"; do
    if print -rn -- "$g" | grep -qiE 'RX 68| RX 69'; then gpu=$g; break; fi
  done
  if [[ -n "$gpu" ]]; then
    add_check gpu "Supported AMD GPU" ok "$gpu"
  elif (( ${#gpus} )); then
    add_check gpu "Supported AMD GPU" warn "${(j:, :)gpus} — only Navi 21 (RX 6800/6800 XT/6900 XT/6950 XT) is known-good for VCN AV1/VP9"
  else
    add_check gpu "Supported AMD GPU" warn "could not read the GPU model"
  fi

  # 6. system Plug-Ins folder intact (Apple's own decoders present, nothing loose in it).
  #    Not counted in HARD_OTHER: `repair` can fix this one.
  local -a livebundles=( "$LIVE"/*.bundle(N) )
  if [[ -e "$LIVE/Contents" || ! -d "$LIVE/AppleGVAHEVCDecoder.bundle" || ${#livebundles} -lt 5 ]]; then
    add_check sysplugins "System video plug-ins intact" fail "Apple's own video plug-ins are damaged or missing. The repair command restores them from Apple's original system snapshot."
    SYS_DAMAGED=1; HARD_FAIL=1
  else
    add_check sysplugins "System video plug-ins intact" ok "Apple's HEVC/AV1/VP9 plug-ins present"
  fi

  # 7. bundles present
  if all_built; then
    add_check bundles "Decoder bundles present" ok "${${(j: + :)WANT}//VCNDecoder.bundle/} bundles found $(pick "in $BUNDLES" "inside RyzenStatus GPU.app")"
  else
    add_check bundles "Decoder bundles present" fail "missing one of ${(j:, :)WANT} $(pick "in $BUNDLES; build them with decode/build.sh" "inside RyzenStatus GPU.app; $APP_DAMAGED")"
    HARD_FAIL=1; HARD_OTHER=1
  fi

  # 8. MPEG-2, VC-1 and MPEG-4 plug-ins left by an earlier install with --legacy (not
  #    blocking: install takes them off)
  local -a stale=( ${(f)"$(stale_legacy $LIVE)"} )
  # An install of this boot without --legacy took them off the next boot's snapshot
  # already; the running system keeps them until the reboot.
  (( ${#stale} )) && look_installed
  if (( ${#stale} )) && [[ $PENDING == install ]]; then
    add_check legacy-left "MPEG-2, VC-1 and MPEG-4 left over" ok "${(j:, :)stale} still run now; the install of this boot took them off the next boot's snapshot, so they go at the reboot"
  elif (( ${#stale} )); then
    add_check legacy-left "MPEG-2, VC-1 and MPEG-4 left over" warn "${(j:, :)stale} in $LIVE, from an earlier install with --legacy. $(pick "'sudo install/decoders.sh install' without --legacy takes them off (with --legacy it keeps them)" "Installing the decoder plug-ins again in this window takes them off")."
  fi
  # 8b. the JPEG plug-in left by an earlier install with --jpeg (not blocking either)
  if [[ -n $(stale_jpeg $LIVE) ]]; then
    look_installed
    if [[ $PENDING == install ]]; then
      add_check jpeg-left "JPEG plug-in left over" ok "$JPEG_BUNDLE still runs now; the install of this boot took it off the next boot's snapshot"
    else
      add_check jpeg-left "JPEG plug-in left over" warn "$JPEG_BUNDLE in $LIVE, from an earlier install with --jpeg. $(pick "'sudo install/decoders.sh install' without --jpeg takes it off (with --jpeg it keeps it)" "Installing the decoder plug-ins again in this window takes it off")."
    fi
  fi

  BLOCK_OVERRIDABLE=0
  if [[ $HARD_FAIL -eq 1 ]]; then CAN_INSTALL=0
  elif [[ $SOFT_FAIL -eq 1 ]]; then CAN_INSTALL=0; BLOCK_OVERRIDABLE=1
  fi
  # repairable: the damaged Plug-Ins folder is the only hard blocker
  REPAIRABLE=0
  [[ $SYS_DAMAGED -eq 1 && $HARD_OTHER -eq 0 ]] && REPAIRABLE=1
  return 0
}


# none | current | outdated | unknown  — what is in /System/Library/Video/Plug-Ins right
# now, against the plug-ins to install (unknown: none built to compare with)
installed_state() {
  local any=0 same=1 b live
  for b in $WANT; do
    if [[ -d "$LIVE/$b" ]]; then
      any=1
      live=$(cdhash_of "$LIVE/$b")
      [[ -n $live && $live == "$(cdhash_of "$BUNDLES/$b")" ]] || same=0
    else
      same=0
    fi
  done
  # left over from an install with --legacy, which this one would take off
  [[ -n $(stale_legacy "$LIVE") || -n $(stale_jpeg "$LIVE") ]] && { any=1; same=0; }
  if [[ $any -eq 0 ]]; then echo none
  elif ! all_built; then echo unknown
  elif [[ $same -eq 1 ]]; then echo current
  else echo outdated
  fi
}

# ---- the record of an install --------------------------------------------------------------
# install, repair and uninstall change the system volume and bless a new boot snapshot, but
# the running system keeps the plug-ins it started with until the reboot, and those are what
# installed_state looks at. So that a check in the same boot does not offer again the update
# just installed, or call installed the plug-ins just removed, each of them writes a record
# once the snapshot is blessed (record_put in common.zsh):
#   /Library/Application Support/RyzenStatus GPU/installed-decoders.txt
# owned by root, mode 644, one "key=value" per line: boot (kern.bootsessionuuid of the boot
# the change ran in), action (install or remove), av1 and vp9 (the cdhashes put in place;
# empty for remove), and legacy (the cdhashes of the MPEG-2, VC-1 and MPEG-4 plug-ins put in
# place, comma-separated, empty without --legacy) and jpeg (the cdhash of the JPEG plug-in, empty
# without --jpeg). A check takes it only from the same boot
# session, and an install only when the cdhashes are the plug-ins to install now.
DEC_RECORD=decoders
legacy_hashes() { # folder
  local -a h=() b
  if legacy_on; then for b in $LEGACY_BUNDLES; do h+=("$(cdhash_of "$1/$b")"); done; fi
  print -r -- "${(j:,:)h}"
}
jpeg_hash() { # folder
  jpeg_on && cdhash_of "$1/$JPEG_BUNDLE"
  return 0
}
dec_record_write() { # install | remove
  local av1="" vp9="" legacy="" jpeg=""
  if [[ $1 == install ]]; then
    av1=$(cdhash_of "$MNT/$PLUGDIR/$AV1")
    vp9=$(cdhash_of "$MNT/$PLUGDIR/$VP9")
    legacy=$(legacy_hashes "$MNT/$PLUGDIR")
    jpeg=$(jpeg_hash "$MNT/$PLUGDIR")
  fi
  # a record that cannot be written must not leave an older one saying something else
  record_put $DEC_RECORD "boot=$(boot_session)" "action=$1" "av1=$av1" "vp9=$vp9" "legacy=$legacy" "jpeg=$jpeg" || record_drop $DEC_RECORD
  return 0
}

# Sets INSTALLED (installed_state) and PENDING, what the record of this boot says waits for
# the reboot: install (these plug-ins are in the next boot's snapshot, other ones or none
# run now), remove (they are gone from it, and still run now) or none. Looked at once.
INSTALLED=""
PENDING=none
look_installed() {
  [[ -n $INSTALLED ]] && return 0
  INSTALLED=$(installed_state)
  PENDING=none
  local file line boot="" action="" av1="" vp9="" legacy="" jpeg=""
  local now=$(boot_session)
  file=$(record_file $DEC_RECORD) || return 0
  while IFS= read -r line; do
    case $line in
      boot=*)   boot=${line#*=} ;;
      action=*) action=${line#*=} ;;
      av1=*)    av1=${line#*=} ;;
      vp9=*)    vp9=${line#*=} ;;
      legacy=*) legacy=${line#*=} ;;
      jpeg=*)   jpeg=${line#*=} ;;
    esac
  done < "$file"
  [[ -n $now && $boot == $now ]] || return 0
  case $action in
    install)
      [[ $INSTALLED != current && -n $av1 && -n $vp9 &&
         $av1 == "$(cdhash_of "$BUNDLES/$AV1")" && $vp9 == "$(cdhash_of "$BUNDLES/$VP9")" &&
         $legacy == "$(legacy_hashes "$BUNDLES")" && $jpeg == "$(jpeg_hash "$BUNDLES")" ]] && PENDING=install ;;
    remove)
      [[ $INSTALLED != none ]] && PENDING=remove ;;
  esac
  return 0
}

emit_check_json() {
  local can=$1 ovr=$2
  look_installed
  print -rn -- "{\"canInstall\":$([[ $can -eq 1 ]] && echo true || echo false),"
  print -rn -- "\"installed\":\"$INSTALLED\","
  print -rn -- "\"pending\":\"$PENDING\","
  print -rn -- "\"overridable\":$([[ $ovr -eq 1 ]] && echo true || echo false),"
  print -rn -- "\"repairable\":$([[ $REPAIRABLE -eq 1 ]] && echo true || echo false),"
  print -rn -- "\"validated\":$([[ $SOFT_FAIL -eq 0 ]] && echo true || echo false),"
  print -rn -- "\"macos\":\"$(jesc "$(macos_product) ($(macos_build))")\","
  print -rn -- "\"checks\":["
  local first=1 c
  for c in "${CHECKS[@]}"; do
    [[ $first -eq 1 ]] || print -rn -- ","
    print -rn -- "$c"; first=0
  done
  print -r -- "]}"
}

emit_check_text() {
  look_installed
  print -r -- "macOS $(macos_product) ($(macos_build))"
  print -r -- "Plug-ins to install: $BUNDLES"
  print -rl -- "${CHECK_LINES[@]}"
  local now=""
  case $INSTALLED in
    none)     now="no decoder plug-in in $LIVE" ;;
    current)  now="both plug-ins, the same code as the ones to install" ;;
    outdated) now="one or both plug-ins, not the same code as the ones to install" ;;
    unknown)  now="decoder plug-ins in $LIVE; none built in $BUNDLES to compare them with" ;;
  esac
  local -a stale=( ${(f)"$(stale_legacy "$LIVE")"} )
  (( ${#stale} )) && now+=", and ${(j:, :)stale} from an earlier install with --legacy"
  [[ -n $(stale_jpeg "$LIVE") ]] && now+=", and $JPEG_BUNDLE from an earlier install with --jpeg"
  case $PENDING in
    install) now+="; the new ones are in the next boot's snapshot and load at the next boot" ;;
    remove)  now+="; they are gone from the next boot's snapshot and stop at the next boot" ;;
  esac
  print -r -- "Installed now: $now"
  # An install or removal of this boot waits only for the reboot. Its result starts with
  # "installed" or "removed", which check.sh reads.
  if [[ $PENDING == install ]]; then
    # A repair restores Apple's plug-ins in that snapshot, so the damage the checks see in
    # the running system is gone at the next boot too; any other FAIL is not.
    local still=""
    (( CAN_INSTALL || REPAIRABLE )) || still=" The checks marked FAIL still stand."
    print -r -- "Result: installed; they load at the next reboot.$still"
  elif [[ $PENDING == remove ]]; then
    print -r -- "Result: removed; the running system keeps them until the next reboot."
  elif [[ $CAN_INSTALL -eq 1 ]]; then
    case $INSTALLED in
      current)  print -r -- "Result: installed. Both plug-ins are the ones $(pick "in $BUNDLES" "in this app"); nothing to do." ;;
      outdated) print -r -- "Result: ready to update. $(pick "'sudo install/decoders.sh install' puts the plug-ins in $BUNDLES in place" "Decoder plug-ins > Update in this window puts these in place"); it needs a reboot afterwards." ;;
      *)        print -r -- "Result: ready. $(pick "'sudo install/decoders.sh install' can run" "Decoder plug-ins > Install in this window can run"); it needs a reboot afterwards." ;;
    esac
  elif [[ $BLOCK_OVERRIDABLE -eq 1 ]]; then
    print -r -- "Result: blocked, this macOS build is not validated. $(pick "--force overrides it" "Decoder plug-ins > Install anyway overrides it"), at the risk of a GPU hang."
  elif [[ $REPAIRABLE -eq 1 ]]; then
    print -r -- "Result: blocked, Apple's plug-ins are damaged. $(pick "'sudo install/decoders.sh repair'" "Decoder plug-ins > Repair in this window") can restore them."
  else
    print -r -- "Result: blocked. Fix the checks marked FAIL first."
  fi
}

emit_check() {
  if [[ $JSON -eq 1 ]]; then emit_check_json $CAN_INSTALL $BLOCK_OVERRIDABLE; else emit_check_text; fi
}

# ---- sealed-volume install ----------------------------------------------------------------
# The system volume (/dev/diskNsM) from the booted snapshot (/dev/diskNsMsK). Strict: anything
# else (e.g. a whole container /dev/diskN) is refused.
system_volume() {
  local node
  node=$(diskutil info / | awk -F': *' '/Device Node/{print $2; exit}')
  if [[ "$node" =~ '^(/dev/disk[0-9]+s[0-9]+)s[0-9]+$' ]]; then print -r -- "$match[1]"
  elif [[ "$node" =~ '^/dev/disk[0-9]+s[0-9]+$' ]]; then print -r -- "$node"
  else echo "unexpected boot device '$node'" >&2; return 1
  fi
}

# 1 once mount_system mounted the system volume itself; it is unmounted again on exit.
SYS_MOUNTED=0

mount_system() {
  local vol cur
  vol=$(system_volume) || return 1
  echo "system volume $vol -> $MNT"
  mkdir -p "$MNT" || return 1
  cur=$(mounted_device "$MNT")
  if [[ -z "$cur" ]]; then
    mount -o nobrowse -t apfs "$vol" "$MNT" || return 1
    SYS_MOUNTED=1
  elif [[ "$cur" != "$vol" ]]; then
    # something else uses this folder (a macOS update in progress, for example)
    echo "$MNT already holds $cur, which is not the system volume $vol; not touching it" >&2
    return 1
  fi
  [[ -d "$MNT/System/Library/CoreServices" ]] \
    || { echo "$MNT does not look like a system volume" >&2; return 1; }
}

# Unmounts the system volume if this run mounted it. The changes are kept on the volume; only
# a blessed snapshot makes them count at the next boot.
unmount_system() {
  [[ $SYS_MOUNTED -eq 1 ]] || return 0
  umount "$MNT" 2>/dev/null || { sleep 2; umount "$MNT" 2>/dev/null; } \
    || echo "note: could not unmount $MNT (in use); it goes away at the next boot" >&2
  SYS_MOUNTED=0
}

# Put back every Apple plug-in missing from DST, copied from the pristine SRC (Apple's sealed
# snapshot of this same macOS build). Never overwrites or deletes an existing bundle; the only
# thing it removes is a loose "Contents" folder (what the 2026-11-06 bug left behind).
restore_apple_plugins() { # src-dir dst-dir
  local src=$1
  local dst=$2
  case "$dst" in
    */System/Library/Video/Plug-Ins) ;;
    *) echo "REFUSING to repair unexpected path: '$dst'" >&2; return 1 ;;
  esac
  local -a apple=( "$src"/*.bundle(N) )
  [[ -d "$src" && ! -e "$src/Contents" && -d "$src/AppleGVAHEVCDecoder.bundle" && ${#apple} -ge 5 ]] \
    || { echo "Apple's original snapshot does not look right (${#apple} bundles in $src); not touching anything" >&2; return 1; }
  mkdir -p "$dst" || return 1
  if [[ -e "$dst/Contents" || -L "$dst/Contents" ]]; then
    rm -rf -- "$dst/Contents" || return 1
    echo "removed loose $dst/Contents"
  fi
  local a n=0
  for a in "${apple[@]}"; do
    # complete ones are left alone; an incomplete one gets its missing files from Apple's copy
    [[ -f "$dst/${a:t}/Contents/Info.plist" ]] && continue
    ditto "$a" "$dst/${a:t}" || return 1
    echo "restored ${a:t}"
    n=$((n + 1))
  done
  for a in "${apple[@]}"; do
    [[ -f "$dst/${a:t}/Contents/Info.plist" ]] || { echo "still missing ${a:t}" >&2; return 1; }
  done
  echo "Apple plug-ins OK: ${#apple} present, $n restored"
}

# The name of Apple's own snapshot of the system volume (the one a macOS update leaves).
# diskutil only lists the snapshots of a volume that has a mount point, and the system
# volume has none until mount_system runs, so the booted snapshot (/) is asked as well: it
# belongs to the same volume.
apple_snapshot() { # system-volume
  local src name
  for src in "$1" /; do
    name=$(diskutil apfs listSnapshots "$src" 2>/dev/null | awk -F': *' '/Name:/{print $2}' | grep -m1 '^com\.apple\.os\.update-')
    [[ -n "$name" ]] && { print -r -- "$name"; return 0; }
  done
  return 1
}

# Refuse to delete anything that is not exactly one of our bundle paths. This is the guard
# that would have caught the 2026-11-06 bug (an empty name turned `rm -rf $dest` into
# `rm -rf .../Video/Plug-Ins`, wiping Apple's plug-ins).
safe_rm_bundle() { # path
  local p=$1
  case "$p" in
    */Video/Plug-Ins/AV1VCNDecoder.bundle|*/Video/Plug-Ins/VP9VCNDecoder.bundle) ;;
    */Video/Plug-Ins/AV1VCNDecoder.bundle.new|*/Video/Plug-Ins/VP9VCNDecoder.bundle.new) ;;
    */Video/Plug-Ins/MPEG2VCNDecoder.bundle|*/Video/Plug-Ins/VC1VCNDecoder.bundle) ;;
    */Video/Plug-Ins/MPEG4VCNDecoder.bundle) ;;
    */Video/Plug-Ins/MPEG2VCNDecoder.bundle.new|*/Video/Plug-Ins/VC1VCNDecoder.bundle.new) ;;
    */Video/Plug-Ins/MPEG4VCNDecoder.bundle.new) ;;
    */Video/Plug-Ins/JPEGVCNDecoder.bundle|*/Video/Plug-Ins/JPEGVCNDecoder.bundle.new) ;;
    *) echo "REFUSING to delete unexpected path: '$p'" >&2; return 1 ;;
  esac
  rm -rf -- "$p"
}

# A plug-in about to be installed must be complete and signed. Without a signature both
# cdhashes would be empty, and the comparison after the copy would pass on anything.
source_ok() { # src-bundle-dir
  [[ -f "$1/Contents/Info.plist" && -n "$(cdhash_of "$1")" ]] \
    || { echo "$1 is incomplete or not signed; $(pick "build it again with decode/build.sh" "$APP_DAMAGED")" >&2; return 1; }
}

install_one() { # src-bundle-dir  name
  # NOTE: one assignment per line. In zsh `local a=$1 b=$2 c=$b` expands the whole line before
  # assigning, so $b is still empty when c is built.
  local src=$1
  local name=$2
  (( ${ALL[(Ie)$name]} )) && [[ -n $name ]] || { echo "bad bundle name '$name'" >&2; return 1; }
  local dest="$MNT/$PLUGDIR/$name"
  [[ -d "$src" ]] || { echo "missing $src" >&2; return 1; }
  source_ok "$src" || return 1
  local want
  want=$(cdhash_of "$src")
  # The new copy is made and checked next to the old one, under another name, and only then
  # takes its place: a copy that fails half way leaves the installed plug-in as it was.
  local new="$dest.new"
  safe_rm_bundle "$new" || return 1
  ditto "$src" "$new" || { safe_rm_bundle "$new"; return 1; }
  local d
  for d in "$new"/Contents/MacOS/*.dSYM(N); do rm -rf -- "$d"; done
  # a downloaded copy is quarantined and ditto would carry that onto the system copy
  # (-s: a link inside the bundle loses the attribute itself, its target is left alone)
  xattr -drs com.apple.quarantine "$new" 2>/dev/null
  chown -R root:wheel "$new" && chmod -R go-w "$new" || { safe_rm_bundle "$new"; return 1; }
  [[ -n "$want" && -f "$new/Contents/Info.plist" && "$(cdhash_of "$new")" == "$want" ]] \
    || { echo "verification failed for $new" >&2; safe_rm_bundle "$new"; return 1; }
  safe_rm_bundle "$dest" || { safe_rm_bundle "$new"; return 1; }
  mv "$new" "$dest" || { echo "could not move $new to $dest" >&2; return 1; }
  # verify it landed where VideoToolbox looks
  [[ -f "$dest/Contents/Info.plist" && "$(cdhash_of "$dest")" == "$want" ]] \
    || { echo "verification failed for $dest" >&2; return 1; }
  # the /Library copy is ignored by VideoToolbox (signature check); drop it to avoid confusion
  [[ -e "$LIBPLUG/$name" ]] && safe_rm_bundle "$LIBPLUG/$name"
  echo "installed $dest"
}

# Without --legacy: takes off the MPEG-2, VC-1 and MPEG-4 plug-ins an earlier install with
# --legacy left on the system volume (and a copy in /Library), so that only the plug-ins of
# this install stay. With --legacy it does nothing.
drop_stale_legacy() {
  legacy_on && return 0
  local b d
  for b in $LEGACY_BUNDLES; do
    for d in "$MNT/$PLUGDIR/$b" "$MNT/$PLUGDIR/$b.new"; do
      [[ -e $d || -L $d ]] || continue
      safe_rm_bundle "$d" || return 1
      echo "removed $d (an earlier install with --legacy put it there)"
    done
    if [[ -e $LIBPLUG/$b || -L $LIBPLUG/$b ]]; then safe_rm_bundle "$LIBPLUG/$b" || return 1; fi
  done
  return 0
}
# The same for the JPEG plug-in without --jpeg.
drop_stale_jpeg() {
  jpeg_on && return 0
  local d b=$JPEG_BUNDLE
  for d in "$MNT/$PLUGDIR/$b" "$MNT/$PLUGDIR/$b.new"; do
    [[ -e $d || -L $d ]] || continue
    safe_rm_bundle "$d" || return 1
    echo "removed $d (an earlier install with --jpeg put it there)"
  done
  if [[ -e $LIBPLUG/$b || -L $LIBPLUG/$b ]]; then safe_rm_bundle "$LIBPLUG/$b" || return 1; fi
  return 0
}

# The plug-ins of this run onto the mounted system volume, and the legacy ones it leaves out
# off it.
put_decoders() {
  local b
  for b in $WANT; do install_one "$BUNDLES/$b" "$b" || return 1; done
  drop_stale_legacy || return 1
  drop_stale_jpeg
}

# Creates the boot snapshot that makes the changes take effect at the next boot.
bless_snapshot() {
  echo "blessing new snapshot..."
  bless --folder "$MNT/System/Library/CoreServices" --bootefi --create-snapshot && return 0
  echo "bless failed: no boot snapshot was created, so the next boot will not use the change." >&2
  echo "The files on the system volume are already changed; run the same command again." >&2
  return 1
}

do_repair() {
  need_root repair
  preflight
  [[ $HARD_OTHER -eq 0 ]] || { echo "preflight has blocking failures besides the plug-ins folder; aborting" >&2; emit_check >&2; exit 2; }
  local with_decoders=0
  [[ $SOFT_FAIL -eq 0 || $FORCE -eq 1 ]] && with_decoders=1
  if [[ $with_decoders -eq 1 ]]; then
    # before anything is changed
    local b
    for b in $WANT; do source_ok "$BUNDLES/$b" || exit 1; done
  fi
  local vol seal
  vol=$(system_volume) || exit 1
  seal=$(apple_snapshot "$vol")
  [[ -n "$seal" ]] || { echo "Apple's original system snapshot was not found on $vol" >&2; exit 5; }
  mount_system || exit 1
  SEALMNT=$(/usr/bin/mktemp -d /private/var/tmp/vcn-sealed-snapshot.XXXXXX) || exit 5
  mount_apfs -s "$seal" -o rdonly,nobrowse "$vol" "$SEALMNT" \
    || { echo "could not mount $seal" >&2; rmdir "$SEALMNT"; exit 5; }
  echo "pristine source: $seal"
  restore_apple_plugins "$SEALMNT/$PLUGDIR" "$MNT/$PLUGDIR"
  local rc=$?
  umount "$SEALMNT" 2>/dev/null && rmdir "$SEALMNT"
  [[ $rc -eq 0 ]] || exit 6
  # install our decoders in the same snapshot (one reboot), unless the build is unvalidated
  if [[ $with_decoders -eq 1 ]]; then
    put_decoders || exit 1
  else
    echo "driver build not validated: decoders NOT installed (Apple plug-ins repaired only)"
  fi
  bless_snapshot || exit 1
  [[ $with_decoders -eq 1 ]] && dec_record_write install
  echo "OK: reboot to apply"
}

do_install() {
  need_root install
  preflight
  if [[ $HARD_FAIL -eq 1 ]]; then
    echo "preflight has blocking failures; aborting" >&2
    emit_check >&2
    exit 2
  fi
  if [[ $SOFT_FAIL -eq 1 && $FORCE -ne 1 ]]; then
    echo "driver build not validated; re-run with --force to override (GPU-hang risk)" >&2
    exit 3
  fi
  # before anything is changed
  local b
  for b in $WANT; do source_ok "$BUNDLES/$b" || exit 1; done
  mount_system || exit 1
  # sanity: the target must be the real system Plug-Ins folder, with Apple's plug-ins in it
  local -a mntbundles=( "$MNT/$PLUGDIR"/*.bundle(N) )
  [[ -d "$MNT/$PLUGDIR" && ! -e "$MNT/$PLUGDIR/Contents" && -d "$MNT/$PLUGDIR/AppleGVAHEVCDecoder.bundle" && ${#mntbundles} -ge 5 ]] \
    || { echo "system Plug-Ins folder looks damaged; not touching it ($(pick "'sudo install/decoders.sh repair'" "Decoder plug-ins > Repair in this window") restores Apple's plug-ins)" >&2; exit 4; }
  put_decoders || exit 1
  bless_snapshot || exit 1
  dec_record_write install
  echo "OK: reboot to load the decoders"
}

do_uninstall() {
  need_root uninstall
  authroot_disabled || { echo "authenticated-root must be disabled" >&2; exit 1; }
  mount_system || exit 1
  local b any=0
  for b in $ALL; do [[ -e "$MNT/$PLUGDIR/$b" ]] && any=1; done
  if (( ! any )); then
    echo "no decoder plug-in is installed; nothing to remove"
    exit 0
  fi
  for b in $ALL; do safe_rm_bundle "$MNT/$PLUGDIR/$b" || exit 1; done
  echo "removed the decoder bundles"
  bless_snapshot || exit 1
  dec_record_write remove
  echo "OK: reboot to apply"
}

trap unmount_system EXIT

case "$CMD" in
  check)
    preflight
    # check.sh's one look: the JSON answer too, from the same checks
    JSON_TO=$(check_json_to)
    [[ $JSON -eq 0 && -n $JSON_TO ]] && emit_check_json $CAN_INSTALL $BLOCK_OVERRIDABLE > "$JSON_TO"
    emit_check
    # the JSON form always ends with 0, as the front end expects; the text form tells a
    # script whether install would go ahead, or (an install of this boot that a repair
    # made, see emit_check_text) whether it is done
    look_installed
    if [[ $JSON -eq 1 || $CAN_INSTALL -eq 1 ]]; then exit 0
    elif [[ $PENDING == install && $REPAIRABLE -eq 1 ]]; then exit 0
    elif [[ $BLOCK_OVERRIDABLE -eq 1 ]]; then exit 3
    else exit 2
    fi ;;
  install)   do_install ;;
  repair)    do_repair ;;
  uninstall) do_uninstall ;;
  -h|--help|help) show_help ;;
  "") usage_error "no command given" ;;
  *) usage_error "unknown command '$CMD'" ;;
esac
