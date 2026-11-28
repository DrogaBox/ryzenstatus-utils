# efikext.zsh - puts one of this repository's Lilu plug-ins on an OpenCore EFI and takes it
# off again. Read with "source" by loader.sh and sensors.sh, after common.zsh; running it
# does nothing.
#
# The script that sources it sets, before calling anything here:
#   KNAME       the kext's name without ".kext", as kextentry knows it: VCNVTLoader
#   KEXT        the built kext to install
#   KEXEC       the executable inside it: VCNVTLoader
#   KOFFARG     the kext's own boot argument that switches it off: -vcnvtoff
#   ENTRY       decode/build/kextentry, the config.plist editor
#   SCRIPT      its own name, for messages: loader.sh
#   CMD         the command being run (install, uninstall, check)
#   EFI_ID      the partition given with --efi, or empty
#   EFI_DIR     the folder given with --efi-folder, or empty
#   MIN_LILU    the oldest Lilu the kext works with
#   KBUNDLE     the kext's bundle identifier, for the install record: com.droga.VCNVTLoader
# and defines:
#   kext_usable <kext-dir>   0 when a copy of the kext can do its job here (the loader: it
#                            lists the plug-ins being installed), 1 when it cannot, 2 when
#                            this cannot be told (no plug-ins built to compare with)
#   USABLE_KEY, USABLE_YES, USABLE_NO, USABLE_UNKNOWN
#                            the JSON key and the words for those answers in check's output
#
# What install changes, all of it on the EFI partition: the kext is copied into
# EFI/OC/Kexts (next to its place first, compared, then swapped in) and one entry is added
# to Kernel > Add in config.plist, after Lilu, with a backup written first and the edit
# verified. The kext is copied before the entry is added, and uninstall removes the entry
# before the kext, so a run that is interrupted never leaves an entry that points to a
# missing kext; the one moment where it could (the swap of an older copy) holds back
# Ctrl-C, and a run cut there by a power loss is repaired by the next one.

NAME=$KNAME.kext
die() { print -r -u2 -- "error: $*"; exit 1; }

# Prints the version, or nothing. PlistBuddy writes "File Doesn't Exist, Will Create" to
# standard output when the file is missing, so the file is checked first and the answer must
# look like a version.
kext_file_version() { # kext-dir
  [[ -f $1/Contents/Info.plist ]] || return 1
  local v=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist" 2>/dev/null)
  [[ $v =~ '^[0-9]+(\.[0-9]+)*$' ]] || return 1
  print -r -- $v
}
# What identifies one build of the kext in the install record (common.zsh): the SHA-256 of
# its program and Info.plist, the two files same_kext compares.
kext_hash() { # kext-dir
  files_hash "$1/Contents/MacOS/$KEXEC" "$1/Contents/Info.plist"
}
# True when anything is at the path, a broken symbolic link included.
exists() { [[ -e $1 || -L $1 ]]; }
# Same kext: the program and its Info.plist are the same bytes.
same_kext() { # a b
  cmp -s "$1/Contents/MacOS/$KEXEC" "$2/Contents/MacOS/$KEXEC" &&
    cmp -s "$1/Contents/Info.plist" "$2/Contents/Info.plist"
}

# The functions below that look at something set variables instead of printing, so that
# more than one answer comes back. They must not be called inside $( ).

# What config.plist says about the kext. Sets ENTRY_STATE (none | ok | differs | unreadable),
# ENTRY_DETAIL (why it differs) and ENTRY_LILU (enabled | disabled | missing).
ENTRY_STATE=""
ENTRY_DETAIL=""
ENTRY_LILU=""
entry_state() { # config.plist
  local out
  ENTRY_DETAIL=""
  ENTRY_LILU=""
  out=$("$ENTRY" $KNAME check "$1" 2>&1) || { ENTRY_DETAIL=${out##*$'\n'}; ENTRY_STATE=unreadable; return; }
  ENTRY_LILU=$(print -r -- "$out" | sed -n '1s/.*Lilu\.kext \([a-z]*\);.*/\1/p')
  if [[ $out == *"$NAME not listed"* ]]; then ENTRY_STATE=none; return; fi
  local line=${out##*$'\n'}
  if [[ $line == *", enabled, after Lilu, settings as expected" ]]; then
    if [[ $ENTRY_LILU == enabled ]]; then ENTRY_STATE=ok; return; fi
    ENTRY_DETAIL="Lilu.kext is $ENTRY_LILU, so the kext cannot start"
    ENTRY_STATE=differs
    return
  fi
  ENTRY_DETAIL=$(print -r -- "$line" | sed -e 's/^ *entry [0-9]*, //')
  ENTRY_STATE=differs
}

# Looks at one folder that holds EFI/OC. Sets OC_ENTRY (none|ok|differs|unreadable),
# OC_KEXT (missing|current|outdated, or unknown when there is no build here to compare with)
# and OC_USABLE (yes|no|unknown).
oc_look() { # folder that holds EFI/OC
  local oc=$1/EFI/OC
  entry_state "$oc/config.plist"
  OC_ENTRY=$ENTRY_STATE
  OC_KEXT=missing
  OC_USABLE=no
  if [[ -f $oc/Kexts/$NAME/Contents/MacOS/$KEXEC && -f $oc/Kexts/$NAME/Contents/Info.plist ]]; then
    if [[ ! -f $KEXT/Contents/MacOS/$KEXEC ]]; then OC_KEXT=unknown
    elif same_kext "$oc/Kexts/$NAME" "$KEXT"; then OC_KEXT=current
    else OC_KEXT=outdated; fi
    kext_usable "$oc/Kexts/$NAME"
    case $? in
      0) OC_USABLE=yes ;;
      2) OC_USABLE=unknown ;;
    esac
  fi
}

EFI_JSON=()    # one JSON object per place
EFI_LINES=()   # the same as text
READY_ON=""    # a place whose kext is in place for the next boot
STALE_ON=""    # a place whose kext is not the one that would be installed
efi_row() { # id name media mount-point
  local id=$1 name=$2 media=$3 mp=$4
  local head="\"id\":\"$id\",\"name\":\"$(jesc "$name")\",\"media\":\"$(jesc "$media")\""
  if [[ -z $mp ]]; then
    EFI_JSON+=("{$head,\"mounted\":false,\"mountPoint\":\"\",\"openCore\":\"unknown\",\"entry\":\"unknown\",\"kext\":\"unknown\",\"$USABLE_KEY\":\"unknown\"}")
    EFI_LINES+=("  $id  \"$name\" on $media: not mounted, so not looked into")
    return
  fi
  if [[ ! -f $mp/EFI/OC/config.plist ]]; then
    EFI_JSON+=("{$head,\"mounted\":true,\"mountPoint\":\"$(jesc "$mp")\",\"openCore\":\"no\",\"entry\":\"unknown\",\"kext\":\"unknown\",\"$USABLE_KEY\":\"unknown\"}")
    EFI_LINES+=("  $id  \"$name\" on $media: at $mp; no OpenCore there")
    return
  fi
  oc_look "$mp"
  EFI_JSON+=("{$head,\"mounted\":true,\"mountPoint\":\"$(jesc "$mp")\",\"openCore\":\"yes\",\"entry\":\"$OC_ENTRY\",\"kext\":\"$OC_KEXT\",\"$USABLE_KEY\":\"$OC_USABLE\"}")
  local entry=$OC_ENTRY kext=$OC_KEXT
  [[ $OC_ENTRY == differs ]] && entry="there with other settings ($ENTRY_DETAIL)"
  [[ $OC_ENTRY == unreadable ]] && entry="config.plist could not be read ($ENTRY_DETAIL)"
  [[ $OC_KEXT == current ]] && kext="the one in ${KEXT:h:t}/${KEXT:t}"
  [[ $OC_KEXT == outdated ]] && kext="another build than ${KEXT:h:t}/${KEXT:t}"
  [[ $OC_KEXT == unknown ]] && kext="there (no build in ${KEXT:h:t} to compare it with)"
  if [[ $OC_KEXT != missing ]]; then
    if [[ $OC_USABLE == yes ]]; then
      [[ -n $USABLE_YES ]] && kext+=", $USABLE_YES"
    elif [[ $OC_USABLE == unknown ]]; then
      kext+=", ${USABLE_UNKNOWN:-not known whether it can be used}"
    else
      kext+=", $USABLE_NO"
    fi
  fi
  EFI_LINES+=("  $id  \"$name\" on $media: at $mp; config entry $entry; kext $kext")
  if [[ $OC_ENTRY == ok && $OC_KEXT != missing && $OC_USABLE == yes ]]; then READY_ON=${READY_ON:-$id}; fi
  if [[ $OC_KEXT == outdated || ( $OC_KEXT != missing && $OC_ENTRY != ok ) ]]; then STALE_ON=${STALE_ON:-$id}; fi
}
EFI_SEEN=()    # the places looked into: partition UUIDs (upper case), or folder:<path>
REC_ON=""      # READY_ON comes from the install record (a partition not mounted now)
efi_scan() {
  EFI_JSON=()
  EFI_LINES=()
  EFI_SEEN=()
  READY_ON=""
  STALE_ON=""
  if [[ -n $EFI_DIR ]]; then
    efi_row folder "${EFI_DIR:t}" "a folder" "$EFI_DIR"
    EFI_SEEN+=("folder:$EFI_DIR")
  else
    local id mp
    for id in $(efi_ids); do
      mp=""
      [[ $(efi_field $id Mounted) == Yes ]] && mp=$(efi_field $id 'Mount Point')
      efi_row $id "$(efi_field $id 'Volume Name')" "$(efi_field "$(efi_field $id 'Part of Whole')" 'Device / Media Name')" "$mp"
      [[ -n $mp ]] && EFI_SEEN+=("${(U)$(efi_field $id 'Disk / Partition UUID')}")
    done
  fi
  efi_record_look
}
# When no place looked into holds this build or another one, the install record of this
# boot session (common.zsh) can tell that this build is on a partition not mounted now: an
# install mounts the partition and unmounts it again. Sets READY_ON and REC_ON then.
efi_record_look() {
  REC_ON=""
  [[ -z $READY_ON && -z $STALE_ON && -f $KEXT/Contents/MacOS/$KEXEC ]] || return 0
  record_read $KNAME || return 0
  [[ $REC_BUNDLE == $KBUNDLE && $REC_VERSION == "$(kext_file_version "$KEXT")" && $REC_HASH == "$(kext_hash "$KEXT")" ]] || return 0
  # a place looked into shows what is really there
  local part=$REC_PARTITION
  [[ $part == folder:* ]] || part=${(U)part}
  (( ${EFI_SEEN[(Ie)$part]} )) && return 0
  kext_usable "$KEXT" || return 0
  local where
  where=$(record_where) || return 0
  READY_ON=$where
  REC_ON=$where
  EFI_LINES+=("  $where  \"$REC_NAME\": not mounted; this build was put there in this boot session (install record)")
}

# ---- install and uninstall -------------------------------------------------------------------
# The partition this run mounted (OPEN_ID, in common.zsh) is unmounted again however the run
# ends.
cleanup() {
  [[ -n $OPEN_ID ]] && efi_close "$OPEN_ID"
  OPEN_ID=""
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM HUP

need_root() { # command
  [[ -n $EFI_DIR || $EUID -eq 0 ]] || { print -r -u2 -- "$1 must run as root: sudo install/$SCRIPT $1"; exit 1; }
}

# Picks the EFI partition when --efi was not given. Sets EFI_ID or stops.
choose_efi() {
  if efi_find_opencore; then
    EFI_ID=$EFI_FOUND
    print -r -- "Using $EFI_ID: $EFI_FIND_WHY."
    return
  fi
  print -r -u2 -- "Cannot tell which EFI partition to use: $EFI_FIND_WHY."
  local id
  for id in $EFI_CANDIDATES; do
    print -r -u2 -- "  $id  \"$(efi_field $id 'Volume Name')\" on $(efi_field "$(efi_field $id 'Part of Whole')" 'Device / Media Name')"
  done
  print -r -u2 -- "Nothing was changed."
  print -r -u2 -- "$(efi_choice_help $EFI_FIND_KIND "$SCRIPT $CMD")"
  (( IN_APP )) || print -r -u2 -- "Or give --efi-folder with the folder that holds EFI/OC."
  exit 64
}
# A check row for the EFI partition, only when an install that is not told the partition
# would stop at it (efi_guess in common.zsh; nothing is mounted): it says why and what to do
# before any password. Nothing is added when a folder is given (--efi-folder).
efi_choice_check() { # check-id
  [[ -z $EFI_DIR ]] || return 0
  efi_guess
  case $EFI_GUESS in
    ambiguous|foreign|none)
      add_check "$1" "EFI partition to install on" warn "an install cannot tell which one to use: $EFI_GUESS_WHY. $(efi_choice_help $EFI_GUESS "$SCRIPT install")" ;;
  esac
}
# Sets OC to the EFI/OC folder to work on, mounting the partition when one is used.
OC=""
open_target() { # lilu | nolilu
  if [[ -n $EFI_DIR ]]; then
    [[ -f $EFI_DIR/EFI/OC/config.plist && -f $EFI_DIR/EFI/OC/OpenCore.efi ]] ||
      die "$EFI_DIR has no OpenCore (EFI/OC/config.plist and OpenCore.efi)"
    [[ $1 != lilu || -d $EFI_DIR/EFI/OC/Kexts/Lilu.kext ]] || die "$EFI_DIR has no Lilu.kext in EFI/OC/Kexts; the kext needs Lilu"
    OC=$EFI_DIR/EFI/OC
    print -r -- "EFI folder $EFI_DIR"
    return
  fi
  [[ -n $EFI_ID ]] || choose_efi
  OPEN_ID=$EFI_ID
  efi_open "$EFI_ID" ${1:#nolilu} || { OPEN_ID=""; exit 1; }
  OC=$EFI_MP/EFI/OC
}
# Deletes the kext folder on the EFI, or its ".new" / ".old" neighbour, and nothing else.
remove_kext_dir() { # path
  [[ $1 == /*/EFI/OC/Kexts/$NAME || $1 == /*/EFI/OC/Kexts/$NAME.new || $1 == /*/EFI/OC/Kexts/$NAME.old ]] ||
    die "refusing to delete '$1': it is not the kext's folder on an EFI"
  exists "$1" || return 0
  /bin/rm -rf -- "$1"
  # it must really be gone: a later mv onto this name would otherwise move into it
  ! exists "$1"
}
# The backup of config.plist that this run wrote first, from the editor's "backup:" line,
# and the one the last edit wrote.
RUN_BACKUP=""
LAST_BACKUP=""
# Runs the config editor, shows what it says, and remembers the backups of this run.
edit_entry() { # add|remove config.plist
  local out rc line
  LAST_BACKUP=""
  out=$("$ENTRY" $KNAME "$1" "$2" 2>&1)
  rc=$?
  [[ -n $out ]] && print -r -- "$out"
  for line in ${(f)out}; do
    if [[ $line == '  backup: '* ]]; then
      LAST_BACKUP=${line#  backup: }
      [[ -z $RUN_BACKUP ]] && RUN_BACKUP=$LAST_BACKUP
    fi
  done
  return $rc
}
# What to do if the next boot fails. Only names a backup this run wrote: an older one would
# undo every change made to config.plist since.
rescue_note() {
  print -r -- "If the Mac does not start: start it from another EFI (a USB stick) and either"
  if [[ -n $RUN_BACKUP ]]; then
    print -r -- "  copy EFI/OC/${RUN_BACKUP:t} over EFI/OC/config.plist"
    print -r -- "  (it is config.plist as it was before this run), or"
  else
    print -r -- "  set Enabled to false in the $NAME entry of EFI/OC/config.plist, or"
  fi
  print -r -- "  add $KOFFARG to the boot arguments."
}
# A run that was cut between moving the old kext away and moving the new one in leaves
# NAME.kext.old and no NAME.kext: put the old one back first.
recover_swap() { # kexts-dir
  local dst=$1/$NAME
  if ! exists "$dst" && [[ -d $dst.old ]]; then
    /bin/mv "$dst.old" "$dst" && print -r -- "kext: put back $NAME, left aside by a run that was cut short"
  fi
}

# Puts the kext on the EFI and its entry in config.plist, then checks the result as the
# next boot will find it. The caller has run its own checks; this one adds those of the EFI.
# On success the partition is unmounted again and the rescue note printed.
kext_install() {
  open_target lilu
  local cfg=$OC/config.plist dst=$OC/Kexts/$NAME
  recover_swap "$OC/Kexts"

  # Everything that can refuse is looked at before the first change.
  local lilu=$(kext_file_version "$OC/Kexts/Lilu.kext")
  [[ -n $lilu ]] || die "cannot read the version of Lilu.kext on that EFI. Nothing was changed."
  is-at-least $MIN_LILU "$lilu" || die "Lilu on that EFI is $lilu; $KNAME needs $MIN_LILU or newer. Update Lilu first. Nothing was changed."
  entry_state "$cfg"
  local before=$ENTRY_STATE before_detail=$ENTRY_DETAIL
  [[ $before != unreadable ]] || die "config.plist cannot be edited: $before_detail. Nothing was changed."
  [[ $ENTRY_LILU == enabled ]] || die "Lilu.kext is $ENTRY_LILU in that config.plist (Kernel > Add); $KNAME needs it enabled. Nothing was changed."
  local free_kb=$(/bin/df -k "$OC" | awk 'NR == 2 {print $4}')
  # the kext twice (the copy and the one it replaces) and config.plist three times (the
  # editor's backups and its temporary file)
  local need_kb=$(( $(/usr/bin/du -sk "$KEXT" | awk '{print $1}') * 2 + $(/usr/bin/du -sk "$cfg" | awk '{print $1}') * 3 + 1024 ))
  (( ${free_kb:-0} >= need_kb )) || die "only ${free_kb:-0} KB free on that EFI; $need_kb KB are needed. Nothing was changed."

  # 1. the kext: copied next to its place, compared, then swapped in
  if [[ -d $dst && ! -L $dst ]] && same_kext "$dst" "$KEXT"; then
    print -r -- "kext: already there, the same build ($(kext_file_version "$dst"))"
    remove_kext_dir "$dst.new"
    remove_kext_dir "$dst.old"
  else
    remove_kext_dir "$dst.new" || die "cannot remove a leftover $dst.new. Nothing was changed."
    /usr/bin/ditto --norsrc --noextattr "$KEXT" "$dst.new" || { remove_kext_dir "$dst.new"; die "cannot copy the kext to $OC/Kexts. Nothing was changed."; }
    same_kext "$dst.new" "$KEXT" || { remove_kext_dir "$dst.new"; die "the copy of the kext does not match the original. Nothing was changed."; }
    { ! exists "$dst" || [[ -d $dst && ! -L $dst ]]; } || { remove_kext_dir "$dst.new"; die "$dst is a file, not a kext folder. Remove it by hand and run this again. Nothing was changed."; }
    local had=""
    # Between the two moves the entry (if there is one) points at no kext. Ctrl-C and
    # similar are held back for those two steps; a power cut there is repaired by the next
    # run (recover_swap), and OpenCore skips a listed kext it cannot find.
    trap '' INT TERM HUP
    if [[ -d $dst ]]; then
      had=$(kext_file_version "$dst")
      if ! remove_kext_dir "$dst.old"; then
        trap 'cleanup; exit 130' INT TERM HUP
        remove_kext_dir "$dst.new"
        die "cannot remove a leftover $dst.old. Nothing was changed."
      fi
      if ! /bin/mv "$dst" "$dst.old"; then
        trap 'cleanup; exit 130' INT TERM HUP
        remove_kext_dir "$dst.new"
        die "cannot move the kext that is there out of the way. Nothing was changed."
      fi
    fi
    if ! /bin/mv "$dst.new" "$dst"; then
      local back="There was no kext there before."
      if [[ -d $dst.old ]]; then
        if /bin/mv "$dst.old" "$dst"; then back="The one that was there is back."
        else back="The one that was there is in $dst.old: rename it to $NAME by hand."; fi
      fi
      trap 'cleanup; exit 130' INT TERM HUP
      remove_kext_dir "$dst.new"
      die "cannot move the kext into place. $back"
    fi
    trap 'cleanup; exit 130' INT TERM HUP
    remove_kext_dir "$dst.old"
    if [[ -n $had ]]; then
      print -r -- "kext: replaced $KNAME $had with $(kext_file_version "$dst")"
    else
      print -r -- "kext: copied $KNAME $(kext_file_version "$dst") to $dst"
    fi
  fi

  # 2. the entry in config.plist
  if [[ $before == differs ]]; then
    print -r -- "config.plist lists the kext with other settings ($before_detail). The entry is replaced."
    # Between the two edits config.plist has no entry: Ctrl-C and similar are held back, and
    # a failed add puts config.plist back as it was before the remove.
    trap '' INT TERM HUP
    if ! edit_entry remove "$cfg"; then
      trap 'cleanup; exit 130' INT TERM HUP
      die "the old entry could not be removed; config.plist is as it was. The kext was copied, and OpenCore loads it with the old entry."
    fi
    if ! edit_entry add "$cfg"; then
      local back="config.plist has no entry for the kext now; copy EFI/OC/${RUN_BACKUP:t} over it by hand."
      [[ -n $RUN_BACKUP && -f $RUN_BACKUP ]] && /bin/cp -p "$RUN_BACKUP" "$cfg" && /bin/sync &&
        back="config.plist is back as it was, with the old entry."
      trap 'cleanup; exit 130' INT TERM HUP
      die "the new entry could not be added (see above). $back"
    fi
    trap 'cleanup; exit 130' INT TERM HUP
    # the add's own backup is config.plist without the entry, between the two edits: only
    # the first one (config.plist as it was) is worth keeping
    if [[ -n $LAST_BACKUP && $LAST_BACKUP != $RUN_BACKUP && $LAST_BACKUP == $OC/config.plist.backup-* && -f $LAST_BACKUP ]]; then
      /bin/rm -f -- "$LAST_BACKUP"
    fi
  else
    edit_entry add "$cfg" || die "config.plist was not changed correctly (see above). The kext was copied, but OpenCore does not load a kext without an entry."
  fi

  # 3. look at the result as the next boot will find it
  oc_look "${OC:h:h}"
  /bin/sync
  if [[ $OC_ENTRY != ok || $OC_KEXT != current || $OC_USABLE != yes ]]; then
    die "after the install the EFI is not as expected (entry $OC_ENTRY, kext $OC_KEXT, usable: $OC_USABLE)."
  fi
  # the record of this install, for the checks until the reboot (common.zsh)
  if [[ -n $EFI_DIR ]]; then
    record_test && record_write $KNAME "folder:$EFI_DIR" "${EFI_DIR:t}" folder $KBUNDLE "$(kext_file_version "$KEXT")" "$(kext_hash "$KEXT")"
  else
    record_write $KNAME "$(efi_field $EFI_ID 'Disk / Partition UUID')" "$(efi_field $EFI_ID 'Volume Name')" $EFI_ID $KBUNDLE "$(kext_file_version "$KEXT")" "$(kext_hash "$KEXT")"
  fi
  cleanup
  print
  print -r -- "Done. $KNAME $(kext_file_version "$KEXT") is on the EFI and listed in config.plist."
  rescue_note
}

# Removes the entry, then the kext. Returns 1 (and prints why) when there was nothing to
# remove.
kext_uninstall() {
  [[ -x $ENTRY ]] || die "$ENTRY is missing; decode/build.sh builds it"
  open_target nolilu
  local cfg=$OC/config.plist dst=$OC/Kexts/$NAME
  entry_state "$cfg"
  local before=$ENTRY_STATE
  [[ $before != unreadable ]] || die "config.plist cannot be edited: $ENTRY_DETAIL. Nothing was changed."
  # the install record goes here: the check above can still abort without changing anything,
  # and the record must not go with it
  record_remove $KNAME
  if [[ $before == none ]] && ! exists "$dst" && ! exists "$dst.new" && ! exists "$dst.old"; then
    cleanup
    print -r -- "$KNAME is not on that EFI. Nothing to remove."
    return 1
  fi
  # the entry first: an entry without its kext is the one state to avoid
  if [[ $before != none ]]; then
    edit_entry remove "$cfg" || die "config.plist was not changed (see above). The kext was left in place."
  fi
  if exists "$dst"; then
    remove_kext_dir "$dst" || die "the entry is gone but $dst could not be deleted; delete it by hand. OpenCore does not load a kext without an entry."
    print -r -- "kext: removed $dst"
  fi
  local left
  for left in "$dst.new" "$dst.old"; do
    remove_kext_dir "$left" || die "could not delete $left, left by an earlier run; delete it by hand."
  done
  /bin/sync
  cleanup
  print
  print -r -- "Done. The kext stays loaded until you reboot."
  return 0
}
