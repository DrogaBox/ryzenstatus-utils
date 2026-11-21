# common.zsh - what the installers in this folder share. It is read by them with "source";
# running it does nothing.
#
#   quarantine  cleared from the package when it is read (see below)
#   checks      add_check collects the result of each check, as text and as JSON
#   loading     what lets the decoder plug-ins into Safari's media processes
#   EFI         finding, mounting and unmounting the OpenCore EFI partition

# ---- quarantine ------------------------------------------------------------------------------
# sudo keeps the caller's PATH on macOS: only the system's own tools, whatever is in it
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

# A package unpacked from a downloaded zip carries macOS's quarantine flag, which can stop
# its unsigned helpers (lvprobe, kextentry, gpusensors) from running. The flag is cleared
# from the files of the package (the folder above this one), and from nothing else. Files
# the user cannot change keep it; the helpers then report their own error.
() {
  local top=${${(%):-%x}:A:h:h}
  [[ -d $top/install && -d $top/decode ]] || return 0
  # -s: a link in the folder loses the attribute itself; root never touches its target
  /usr/bin/xattr -drs com.apple.quarantine "$top" 2>/dev/null
  return 0
}

# ---- where the messages send you -------------------------------------------------------------
# The RyzenStatus GPU app carries these files in RyzenStatus GPU.app/Contents/Resources/GPU.
# Run from there, a message names the app's buttons instead of commands, build steps and
# folders of a checkout, which the person in front of the app does not have.
IN_APP=0
[[ ${${(%):-%x}:A:h:h} == *.app/Contents/Resources/GPU ]] && IN_APP=1
# pick <text for a checkout> <text for the app>
pick() { if (( IN_APP )); then print -rn -- "$2"; else print -rn -- "$1"; fi; }
# What a missing or broken file of the package means in the app.
APP_DAMAGED="this copy of RyzenStatus GPU is incomplete; open it again from a new download of the RyzenStatus DMG"

# ---- checks ----------------------------------------------------------------------------------
# A string as the inside of a JSON string: backslash, quote and the control characters
# that may appear in names and paths escaped; any other control character dropped.
jesc() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  s=${s//[[:cntrl:]]/}
  print -rn -- "$s"
}

CHECKS=()       # one JSON object per check
CHECK_LINES=()  # the same checks as text
add_check() { # id label status detail   (status: ok|warn|fail)
  CHECKS+=("{\"id\":\"$(jesc "$1")\",\"label\":\"$(jesc "$2")\",\"status\":\"$(jesc "$3")\",\"detail\":\"$(jesc "$4")\"}")
  local mark="ok  "
  [[ $3 == warn ]] && mark="warn"
  [[ $3 == fail ]] && mark="FAIL"
  CHECK_LINES+=("  $mark  $2: $4")
}

# One look per refresh: check.sh runs every part's text check once, and with
# GPU_CHECK_JSON_TO set a part's text check also writes its 'check --json' answer to that
# file, from the same look (the RyzenStatus GPU app reads both). Not as root: a root run
# writes nothing it was not asked for on its command line.
check_json_to() {
  [[ -n ${GPU_CHECK_JSON_TO:-} && $EUID -ne 0 ]] && print -r -- "$GPU_CHECK_JSON_TO"
}
# system_profiler's display report, which the decoders', the encoding fix's and the GPU
# sensors' checks read. check.sh runs them one after the other and lets them share one
# answer through GPU_CHECK_CACHE, a folder of its own; a part run alone asks macOS itself.
displays_report() {
  local c=${GPU_CHECK_CACHE:-}
  if [[ -n $c && -d $c && ! -L $c && -O $c && $EUID -ne 0 ]]; then
    if [[ ! -f $c/displays ]]; then
      /usr/sbin/system_profiler SPDisplaysDataType > "$c/displays.$$" 2>/dev/null
      /bin/mv -f "$c/displays.$$" "$c/displays"
    fi
    cat "$c/displays"
    return 0
  fi
  /usr/sbin/system_profiler SPDisplaysDataType 2>/dev/null
}

# ---- the GPU sensors' commands in /usr/local/bin ---------------------------------------------
# sensors.sh copies gpucontrol and gpusensors there. Ours are signed with the identifiers
# com.droga.gpucontrol and com.droga.gpusensors; anything else under those names is someone
# else's program and is never replaced or removed.
GPU_TOOL_DIR=/usr/local/bin
GPU_TOOL_NAMES=(gpucontrol gpusensors)
gpu_tool_id() { /usr/bin/codesign -dv "$1" 2>&1 | sed -n 's/^Identifier=//p' | head -1; }
# Sets GPU_TOOLS_OURS to the paths there that are ours and GPU_TOOLS_OTHER to the ones that
# are not.
GPU_TOOLS_OURS=()
GPU_TOOLS_OTHER=()
gpu_tools_look() {
  local n f
  GPU_TOOLS_OURS=()
  GPU_TOOLS_OTHER=()
  for n in $GPU_TOOL_NAMES; do
    f=$GPU_TOOL_DIR/$n
    [[ -e $f || -L $f ]] || continue
    if [[ -f $f && ! -L $f && $(gpu_tool_id "$f") == com.droga.$n ]]; then GPU_TOOLS_OURS+=($f)
    else GPU_TOOLS_OTHER+=($f); fi
  done
}

# Prints the comment block at the top of a script, which is its help text.
help_of() { # script
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$1"
}

# ---- what lets the plug-ins into Safari's media processes ------------------------------------
# Those processes only map code macOS trusts (library validation). The plug-ins get in when
# one of these holds: AMFI is switched off, AMFIPass runs, the plug-ins are signed under a CA
# the Mac has been made to trust, or VCNVTLoader runs and lists them. See decode/loader/README.md.
boot_args() { /usr/sbin/sysctl -n kern.bootargs 2>/dev/null; }
amfi_off() { boot_args | grep -qE '(^| )amfi_get_out_of_my_way=(0x)?0*[1-9a-fA-F]'; }
# A loaded AMFIPass does nothing when Lilu or AMFIPass itself is switched off by boot-args.
amfipass_on() {
  /usr/sbin/kextstat 2>/dev/null | grep -q 'com.dhinakg.AMFIPass' || return 1
  boot_args | grep -qE '(^| )(-amfipassoff|-liluoff)( |$)' && return 1
  return 0
}
# The version of a loaded kext, or nothing when it is not loaded.
kext_version() { # bundle-id
  /usr/sbin/kextstat -l -b "$1" 2>/dev/null | awk '{print $7}' | tr -d '()'
}
# A property of the running VCNVTLoader (Status, AllowedBuilds, ...); nothing when it is not running.
loader_prop() { # name
  /usr/sbin/ioreg -r -c VCNVTLoader -l 2>/dev/null | sed -n "s/.*\"$1\" = \"*\([^\"]*\)\"*\$/\1/p" | head -1
}
# The code directory hash of a bundle or program: what identifies one exact build.
cdhash_of() { codesign -dvvv "$1" 2>&1 | awk -F= '/^CDHash=/{print $2}'; }
# True when the VCNVTLoader kext at a folder lists the code of a bundle.
kext_lists() { # kext-dir bundle
  local h=$(cdhash_of "$2") exe=$1/Contents/MacOS/VCNVTLoader
  [[ -n "$h" && -f $exe ]] || return 1
  /usr/bin/xxd -p "$exe" | tr -d '\n' | grep -q "$h"
}
# Does macOS accept these Mach-O files in a protected program right now? Asked with lvprobe
# (decode/build/lvprobe), which loads nothing. Returns 0 yes, 1 no, 2 could not ask, and
# sets PROBE_WHY to the kernel's reason when the answer is not yes.
PROBE_WHY=""
lv_accepts() { # probe file...
  local probe=$1 out rc
  shift
  out=$("$probe" "$@" 2>&1)
  rc=$?
  PROBE_WHY=$(print -r -- "$out" | sed -n 's/^refused [^:]*: //p; s/^error   [^:]*: //p' | head -1)
  return $rc
}

# ---- the OpenCore EFI partition --------------------------------------------------------------
# Every EFI partition of this Mac, one diskNsM per line. Nothing is mounted.
efi_ids() {
  local id
  for id in $(/usr/sbin/diskutil list 2>/dev/null | awk '$2 == "EFI" {print $NF}'); do
    [[ $id =~ '^disk[0-9]+s[0-9]+$' ]] && print -r -- $id
  done
}
# One field of "diskutil info", for example: efi_field disk0s1 'Mount Point'
efi_field() { # id field
  /usr/sbin/diskutil info "$1" 2>/dev/null | awk -F': *' -v f="$2" '$1 ~ "^ *" f "$" {print $2; exit}'
}
# The partition GUID inside an OpenCore boot-path: the text between "GPT," and the next comma.
boot_path_guid() { # boot-path
  print -r -- "$1" | sed -n 's/.*GPT,\([0-9A-Fa-f-]\{36\}\),.*/\1/p'
}
# The partition OpenCore started from, from its boot-path variable (only there when
# ExposeSensitiveData has bit 0x1). Prints diskNsM and returns 0; returns 1 when OpenCore does
# not tell; returns 2 when it names a partition that is not one of the EFI partitions listed
# here (OpenCore on a USB stick's data partition, for example): then no other EFI may be
# taken in its place.
efi_booted() {
  local guid=$(boot_path_guid "$(/usr/sbin/nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:boot-path 2>/dev/null)")
  [[ -n $guid ]] || return 1
  local id
  for id in $(efi_ids); do
    if [[ ${(U)$(efi_field $id 'Disk / Partition UUID')} == ${(U)guid} ]]; then
      print -r -- $id
      return 0
    fi
  done
  print -r -- $guid
  return 2
}

MOUNTED_BY_US=0
EFI_MP=""
OPEN_ID=""

# Finds the EFI partition this Mac started OpenCore from, for a run that was not told which
# one. Sets EFI_FOUND and returns 0; returns 1 with EFI_FIND_WHY set (and EFI_CANDIDATES
# listing the partitions that hold OpenCore) when it cannot tell. First what OpenCore itself
# says (boot-path), else the only EFI partition that holds OpenCore. Partitions are mounted
# to look (so it needs root) and unmounted again; while one is open, OPEN_ID names it, so
# the caller's exit trap unmounts it if the run is stopped.
EFI_FOUND=""
EFI_FIND_WHY=""
EFI_FIND_KIND=""   # when it cannot tell: ambiguous | foreign | none (for efi_choice_help)
EFI_CANDIDATES=()
efi_find_opencore() {
  local id rc mp
  local -a unmountable=()
  EFI_FOUND=""
  EFI_FIND_WHY=""
  EFI_FIND_KIND=""
  EFI_CANDIDATES=()
  id=$(efi_booted)
  rc=$?
  if (( rc == 0 )); then
    EFI_FOUND=$id
    EFI_FIND_WHY="OpenCore says this Mac started from it"
    return 0
  fi
  if (( rc == 2 )); then
    EFI_FIND_WHY="OpenCore says this Mac started from partition $id, which is not one of the EFI partitions diskutil lists, so no other one is taken in its place"
    EFI_FIND_KIND=foreign
    return 1
  fi
  for id in $(efi_ids); do
    if [[ $(efi_field $id Mounted) != Yes ]]; then
      /usr/sbin/diskutil mount $id >/dev/null 2>&1 || { unmountable+=($id); continue; }
      OPEN_ID=$id
      MOUNTED_BY_US=1
    fi
    mp=$(efi_field $id 'Mount Point')
    [[ -n $mp && -f $mp/EFI/OC/config.plist && -f $mp/EFI/OC/OpenCore.efi ]] && EFI_CANDIDATES+=($id)
    if [[ $OPEN_ID == $id ]]; then
      efi_close $id >/dev/null
      OPEN_ID=""
    fi
  done
  case ${#EFI_CANDIDATES} in
    1) EFI_FOUND=$EFI_CANDIDATES[1]
       EFI_FIND_WHY="the only EFI partition that holds OpenCore" ;;
    0) EFI_FIND_KIND=none
       if (( ${#unmountable} )); then
         EFI_FIND_WHY="${(j:, :)unmountable} could not be mounted to look inside (this needs sudo)"
       else
         EFI_FIND_WHY="no EFI partition with OpenCore was found; if yours is on a disk that is not connected, connect it"
       fi ;;
    *) EFI_FIND_KIND=ambiguous
       EFI_FIND_WHY="more than one EFI partition holds OpenCore (${(j:, :)EFI_CANDIDATES}) and OpenCore does not say which one this Mac started from" ;;
  esac
  # A partition macOS cannot mount (a damaged or foreign FAT, another system's EFI) is not
  # where a kext can be put anyway; say it was skipped, so a wrong pick can be corrected
  # with --efi. A kext on the wrong EFI is not loaded, and check.sh reports that.
  if [[ -n $EFI_FOUND ]] && (( ${#unmountable} )); then
    EFI_FIND_WHY+="; ${(j:, :)unmountable} could not be mounted and was not looked into"
  fi
  [[ -n $EFI_FOUND ]] && return 0
  return 1
}

# The same choice for a plan or a check, before any password: no root, and nothing is
# mounted, so a partition that is not mounted is not looked into. Sets EFI_GUESS to one of
#   found      EFI_GUESS_ID is the partition an install takes: the one OpenCore says it
#              started from, or the only one that holds OpenCore when every EFI partition is
#              mounted
#   open       the install decides, after the password: it mounts the partitions that are
#              not mounted now to look inside
#   ambiguous  more than one mounted EFI partition holds OpenCore and OpenCore does not say
#              which one this Mac started from
#   foreign    OpenCore says it started from a partition that is not an EFI partition
#   none       every EFI partition is mounted and none holds OpenCore
# With ambiguous, foreign and none an install that is not told the partition stops before
# its first change. EFI_GUESS_WHY says why, and EFI_CANDIDATES lists the mounted partitions
# that hold OpenCore.
EFI_GUESS=""
EFI_GUESS_ID=""
EFI_GUESS_WHY=""
efi_guess() {
  local id rc mp
  local -a unmounted=()
  EFI_GUESS=""
  EFI_GUESS_ID=""
  EFI_GUESS_WHY=""
  EFI_CANDIDATES=()
  id=$(efi_booted)
  rc=$?
  if (( rc == 0 )); then
    EFI_GUESS=found
    EFI_GUESS_ID=$id
    EFI_GUESS_WHY="OpenCore says this Mac started from it"
    return 0
  fi
  if (( rc == 2 )); then
    EFI_GUESS=foreign
    EFI_GUESS_WHY="OpenCore says this Mac started from partition $id, which is not one of the EFI partitions diskutil lists, so no other one is taken in its place"
    return 0
  fi
  for id in $(efi_ids); do
    if [[ $(efi_field $id Mounted) != Yes ]]; then
      unmounted+=($id)
      continue
    fi
    mp=$(efi_field $id 'Mount Point')
    [[ -n $mp && -f $mp/EFI/OC/config.plist && -f $mp/EFI/OC/OpenCore.efi ]] && EFI_CANDIDATES+=($id)
  done
  if (( ${#EFI_CANDIDATES} > 1 )); then
    EFI_GUESS=ambiguous
    EFI_GUESS_WHY="more than one EFI partition holds OpenCore (${(j:, :)EFI_CANDIDATES}) and OpenCore does not say which one this Mac started from"
  elif (( ${#unmounted} )); then
    EFI_GUESS=open
    if (( ${#EFI_CANDIDATES} )); then
      EFI_GUESS_WHY="$EFI_CANDIDATES[1] holds OpenCore; ${(j:, :)unmounted} is not mounted, so it is looked into only when installing, after the password. If it holds OpenCore too, the install stops before changing anything and says what to do"
    else
      EFI_GUESS_WHY="no mounted EFI partition holds OpenCore; the install mounts ${(j:, :)unmounted} to look, after the password. If none or more than one holds OpenCore, it stops before changing anything and says what to do"
    fi
  elif (( ${#EFI_CANDIDATES} )); then
    EFI_GUESS=found
    EFI_GUESS_ID=$EFI_CANDIDATES[1]
    EFI_GUESS_WHY="the only EFI partition that holds OpenCore"
  else
    EFI_GUESS=none
    EFI_GUESS_WHY="no EFI partition with OpenCore was found; if yours is on a disk that is not connected, connect it"
  fi
  return 0
}
# What to do when the EFI partition cannot be chosen without being told, in plain words:
# for a plan, a check, or an install that stopped. kind is EFI_GUESS or EFI_FIND_KIND;
# the second argument is the script and its options, for the Terminal line ("install.sh
# --with-sensors", "loader.sh install").
efi_choice_help() { # kind "script [options]"
  local kind=$1 script=${2%% *} opts=""
  [[ $2 == *" "* ]] && opts=" ${2#* }"
  local term
  if (( IN_APP )); then
    term="name the partition in Terminal: sudo '$SELF_DIR/$script'$opts --efi diskNsM (diskutil list shows them)"
  else
    term="name it: sudo install/$script$opts --efi diskNsM (diskutil list shows them)"
  fi
  case $kind in
    ambiguous) print -rn -- "What to do: if the other OpenCore is on a USB stick or a disk you can disconnect, disconnect it and try again. Or set bit 0x1 in OpenCore's Misc > Security > ExposeSensitiveData and reboot: this Mac then says which EFI partition it started from, and the choice is made for you. Or $term." ;;
    foreign)   print -rn -- "What to do: start this Mac from the EFI partition the kexts should go on and try again, or $term." ;;
    *)         print -rn -- "What to do: connect the disk that holds your OpenCore EFI and try again, or $term." ;;
  esac
}

# Mounts an EFI partition if needed and checks that it holds OpenCore. Sets EFI_MP to its
# mount point. With "lilu" as second argument it must also hold Lilu.kext.
efi_open() { # id [lilu]
  local id=$1 want_lilu=${2:-}
  [[ $id =~ '^disk[0-9]+s[0-9]+$' ]] || { echo "bad EFI partition '$id'" >&2; return 1; }
  local info=$(/usr/sbin/diskutil info "$id" 2>/dev/null)
  print -r -- "$info" | grep -qE 'Partition Type: +EFI$' || { echo "$id is not an EFI partition" >&2; return 1; }
  if ! print -r -- "$info" | grep -qE 'Mounted: +Yes'; then
    /usr/sbin/diskutil mount "$id" >/dev/null || { echo "could not mount $id" >&2; return 1; }
    MOUNTED_BY_US=1
  fi
  EFI_MP=$(efi_field "$id" 'Mount Point')
  [[ -n "$EFI_MP" && -f $EFI_MP/EFI/OC/config.plist && -f $EFI_MP/EFI/OC/OpenCore.efi ]] \
    || { echo "$id has no OpenCore (EFI/OC/config.plist and OpenCore.efi) — pick the EFI your Mac boots from" >&2; efi_close "$id"; return 1; }
  if [[ $want_lilu == lilu && ! -d $EFI_MP/EFI/OC/Kexts/Lilu.kext ]]; then
    echo "$id has no Lilu.kext in EFI/OC/Kexts; the kext needs Lilu" >&2
    efi_close "$id"
    return 1
  fi
  echo "EFI $id at $EFI_MP"
}
# Unmounts the partition again, but only when efi_open mounted it.
efi_close() { # id
  if (( MOUNTED_BY_US )); then
    # Spotlight can hold a partition that was just mounted for a moment: one more try.
    if /usr/sbin/diskutil unmount "$1" >/dev/null 2>&1 ||
       { sleep 2; /usr/sbin/diskutil unmount "$1" >/dev/null 2>&1; }; then
      echo "unmounted $1"
    else
      echo "note: $1 could not be unmounted; it stays mounted" >&2
    fi
    MOUNTED_BY_US=0
  fi
}
