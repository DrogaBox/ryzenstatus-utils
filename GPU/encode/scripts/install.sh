#!/bin/zsh
# VCNEncodeFix installer.
#
#   sudo ./install.sh                         install or update the background service (user-space half)
#   sudo ./install.sh --efi /Volumes/EFI      also add VCNEncodeFloor.kext to that mounted OpenCore EFI
#                                             (kernel half; takes effect after a reboot)
# Options: --preset speed|balance|quality (default speed), --no-preset, --no-wide, --force (skip the GPU check).
# Remove everything with ./uninstall.sh. Nothing here touches the macOS system volume.
#
# Everything that can refuse (the GPU, the patches, the EFI: OpenCore, Lilu and its version, the config entry,
# free space) is checked before the first change. Exit status: 0 done; 1 refused or failed (the message says
# what was changed, if anything); 2 installed, but the service is not running.
emulate -L zsh
setopt no_unset
autoload -Uz is-at-least
here=${0:A:h}
tool=$here/bin/vcnencodefix
label=com.droga.vcnencodefix
bin_dst=/usr/local/libexec/vcnencodefix
plist_dst=/Library/LaunchDaemons/$label.plist
log=/var/log/vcnencodefix.log
kext_src=$here/Kexts/VCNEncodeFloor.kext

say()  { print -r -- "$@"; }
die()  { print -r -- "error: $*" >&2; exit 1; }
step() { print -r -- ""; print -r -- "== $*"; }
plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }  # plist key
# The service runs as root from /usr/local/libexec. Refuse a folder another user could change.
libexec_unsafe() {
  local d=$1 owner mode
  while [[ $d != / ]]; do
    if [[ -e $d || -L $d ]]; then
      [[ -d $d && ! -L $d ]] || { print -r -- "$d is not a folder"; return 0; }
      owner=$(/usr/bin/stat -f '%Su' "$d")
      mode=$(/usr/bin/stat -f '%Lp' "$d")
      [[ $owner == root ]] || { print -r -- "$d belongs to $owner, not root"; return 0; }
      (( (8#$mode & 8#022) == 0 )) || { print -r -- "$d can be written by others than root (mode $mode)"; return 0; }
      [[ $(/bin/ls -lde "$d" 2>/dev/null | head -1 | cut -c11) == "+" ]] &&
        { print -r -- "$d has an access control list"; return 0; }
    fi
    d=${d:h}
  done
  return 1
}

efi="" force=0 args=()
while (( $# )); do
  case $1 in
    --efi) (( $# >= 2 )) && [[ -n ${2%/} ]] || die "--efi needs the mount point of the EFI partition"
           efi=${2:A}; shift 2 ;;
    --preset) (( $# >= 2 )) || die "--preset needs speed, balance or quality"
              [[ $2 == (speed|balance|quality) ]] || die "unknown preset $2"; args+=(--preset $2); shift 2 ;;
    --no-preset|--no-wide) args+=($1); shift ;;
    --force) force=1; shift ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' $0; exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
  esac
done
(( EUID == 0 )) || die "run it with sudo: sudo $0"

# Files unpacked from a downloaded zip carry the quarantine flag, which stops unsigned tools from running.
# sudo keeps the caller's PATH on macOS: only the system's own tools, whatever is in it
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
xattr -drs com.apple.quarantine $here 2>/dev/null
[[ -x $tool ]] || die "$tool is missing; unpack the whole folder"

step "Checking this Mac"
gpu=$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Chipset Model/{m=$2} /Device ID/{print m" ("$2")"}')
say "GPU: ${gpu:-unknown}"
if ! print -r -- $gpu | grep -qiE '\(0x73(a[0-9a-f]|bf)\)'; then
  (( force )) || die "no Navi 21 GPU (RX 6800, 6800 XT, 6900 XT, 6950 XT) found; VCNEncodeFix was only tested on Navi 21. On the RX 6600 family (Navi 23) the kext sets a floor taken from that chip's clock table, but nothing has run there; on other cards the kext stays off. --force skips this check."
  say "warning: no Navi 21 GPU found; continuing because of --force"
fi
status_out=$($tool status ${args[@]})
st=$?
print -r -- $status_out | sed 's/^/  /'
(( st == 0 )) || die "neither patch applies to this macOS build, so the service would do nothing; not installing"
if [[ $status_out == *"access  REFUSED"* ]]; then
  say "warning: SIP Debugging Restrictions are on. The service installs, but macOS will not let it into the encoder"
  say "         until bit 0x4 is added to csr-active-config and the Mac is rebooted (README, Requirements)."
  say "         The kernel half (--efi) works without it."
fi

if [[ -n $efi ]]; then
  step "Checking the EFI at $efi"
  [[ $efi != / ]] || die "--efi / is the system disk, not an EFI partition"
  oc=$efi/EFI/OC
  cfg=$oc/config.plist
  dst=$oc/Kexts/VCNEncodeFloor.kext
  [[ -f $cfg && -f $oc/OpenCore.efi ]] || die "$efi has no OpenCore (EFI/OC/config.plist and OpenCore.efi): is it the mounted EFI partition? Nothing was changed."
  lilu=$(plist_value $oc/Kexts/Lilu.kext/Contents/Info.plist CFBundleShortVersionString)
  [[ -n $lilu ]] || die "$oc/Kexts/Lilu.kext not found or unreadable; VCNEncodeFloor needs Lilu. Nothing was changed."
  min_lilu=$(plist_value $kext_src/Contents/Info.plist OSBundleLibraries:as.vit9696.Lilu)
  [[ -z $min_lilu ]] || is-at-least $min_lilu $lilu || die "Lilu on that EFI is $lilu; VCNEncodeFloor needs $min_lilu or newer. Update Lilu first. Nothing was changed."
  check=$($tool efi-check $cfg 2>&1) || die "config.plist cannot be read: ${check##*$'\n'}. Nothing was changed."
  [[ $check == *"Lilu.kext enabled;"* ]] || die "Lilu.kext is not enabled in that config.plist (Kernel > Add). Nothing was changed."
  if [[ $check != *"VCNEncodeFloor.kext not listed"* ]]; then
    entry=${${check##*$'\n'}##  entry <->, }
    if [[ $entry != "enabled, after Lilu, settings as expected" && $entry != "enabled, after Lilu, old entry"* ]]; then
      die "config.plist lists VCNEncodeFloor.kext with other settings ($entry). Fix or remove that entry by hand, then run this again. Nothing was changed."
    fi
  fi
  free_kb=$(df -k $oc | awk 'NR == 2 {print $4}')
  need_kb=$(( $(du -sk $kext_src | awk '{print $1}') * 2 + $(du -sk $cfg | awk '{print $1}') * 3 + 1024 ))
  (( ${free_kb:-0} >= need_kb )) || die "only ${free_kb:-0} KB free on that EFI; $need_kb KB are needed. Nothing was changed."
  say "OpenCore with Lilu $lilu; the config entry can be written"
fi

step "Installing the service ($label)"
if [[ -e /Library/LaunchDaemons/com.droga.vcnpreset.plist ]] || launchctl print system/com.droga.vcnpreset >/dev/null 2>&1; then
  say "removing the earlier test version (com.droga.vcnpreset)"
  launchctl bootout system/com.droga.vcnpreset 2>/dev/null
  rm -f /Library/LaunchDaemons/com.droga.vcnpreset.plist /usr/local/libexec/vcnpreset
fi
# Everything is staged next to its place first; the running service is only stopped once that worked.
if [[ ! -e /usr/local/libexec ]]; then
  why=$(libexec_unsafe /usr/local) || true
  [[ -z $why ]] || die "will not create /usr/local/libexec: $why. Nothing was changed."
  mkdir -p -m 755 /usr/local/libexec || die "cannot create /usr/local/libexec. Nothing was changed."
  chown root:wheel /usr/local/libexec || die "cannot make /usr/local/libexec root-owned."
fi
why=$(libexec_unsafe /usr/local/libexec) || true
[[ -z $why ]] || die "will not install the service: $why."
rm -f $bin_dst.new $plist_dst.tmp
install -m 755 -o root -g wheel $tool $bin_dst.new || { rm -f $bin_dst.new; die "cannot write $bin_dst.new. Nothing was changed."; }
argxml=""
for a in ${args[@]}; do argxml+="\t\t<string>$a</string>\n"; done
if ! awk -v a="$argxml" '/__ARGS__/ { printf "%s", a; next } { print }' $here/support/$label.plist > $plist_dst.tmp ||
   ! chown root:wheel $plist_dst.tmp || ! chmod 644 $plist_dst.tmp || ! plutil -lint -s $plist_dst.tmp; then
  rm -f $bin_dst.new $plist_dst.tmp
  die "cannot write a valid $plist_dst.tmp. Nothing was changed."
fi
# bootout returns before launchd has let go of the job; bootstrap fails while it still holds it
trap '' INT TERM HUP
launchctl bootout system/$label 2>/dev/null
for i in {1..40}; do launchctl print system/$label >/dev/null 2>&1 || break; sleep 0.25; done
if ! mv -f $bin_dst.new $bin_dst || ! mv -f $plist_dst.tmp $plist_dst; then
  trap - INT TERM HUP
  rm -f $bin_dst.new $plist_dst.tmp
  [[ -e $plist_dst && -x $bin_dst ]] && launchctl bootstrap system $plist_dst 2>/dev/null
  die "cannot move the new service files into place; the earlier service was started again if it was complete"
fi
trap - INT TERM HUP
install -m 644 -o root -g wheel $here/support/vcnencodefix.conf /etc/newsyslog.d/vcnencodefix.conf || say "warning: the log rotation setting was not installed"
touch $log && chmod 644 $log
launchctl bootstrap system $plist_dst || { sleep 1; launchctl bootstrap system $plist_dst; } ||
  die "launchctl bootstrap failed; the service files are installed. Try 'sudo launchctl bootstrap system $plist_dst' and see $log"
sleep 1
running=1
pid=$(pgrep -f "^$bin_dst watch" | head -1)
if [[ -n $pid ]]; then say "running (pid $pid)"; else say "warning: the service is not running; see $log"; running=0; fi
tail -4 $log | sed 's/^/  /'

step "Kernel half (VCNEncodeFloor.kext, VCN clock floor)"
loaded=$(kextstat -l -b com.droga.VCNEncodeFloor 2>/dev/null | awk '{print $7}' | tr -d '()')
if [[ -n $loaded ]]; then
  state=$(ioreg -rd1 -c IOResources -k VCNEncodeFloor | awk -F'"' '$2 == "VCNEncodeFloor" {print $4}')
  say "loaded now: VCNEncodeFloor $loaded, ${state:-state not published}"
fi
if [[ -n $efi ]]; then
  # a run cut between the two moves below left the old kext as .old and none in place: put it back first
  if [[ ! -e $dst && -d $dst.old ]]; then mv $dst.old $dst && say "put back VCNEncodeFloor.kext, left aside by a run that was cut short"; fi
  [[ ! -e $dst || ( -d $dst && ! -L $dst ) ]] || die "$dst is not a kext folder; remove it by hand. The service is installed; the EFI was not changed."
  rm -rf $dst.new $dst.old
  if ! ditto --norsrc --noextattr $kext_src $dst.new || ! cmp -s $kext_src/Contents/MacOS/VCNEncodeFloor $dst.new/Contents/MacOS/VCNEncodeFloor; then
    rm -rf $dst.new
    die "cannot copy the kext to $efi. The service is installed; the EFI was not changed."
  fi
  # Between the two moves the entry (if there is one) points at no kext: Ctrl-C is held back.
  trap '' INT TERM HUP
  if [[ -d $dst ]] && ! mv $dst $dst.old; then
    trap - INT TERM HUP; rm -rf $dst.new
    die "cannot move the kext that is there out of the way. The service is installed; the EFI was not changed."
  fi
  if ! mv $dst.new $dst; then
    [[ -d $dst.old ]] && mv $dst.old $dst
    trap - INT TERM HUP; rm -rf $dst.new
    die "cannot move the kext into place; the one that was there is back. The service is installed."
  fi
  trap - INT TERM HUP
  rm -rf $dst.old
  say "copied VCNEncodeFloor.kext $(plist_value $dst/Contents/Info.plist CFBundleShortVersionString) to $dst"
  $tool efi-add $cfg || die "config.plist was not changed correctly; see the message above. The kext is on the EFI; OpenCore does not load it without its entry."
  say "Reboot to load it. If the Mac does not start, boot another EFI (for example a USB stick) and either add"
  say "-vcnflooroff to boot-args or copy a config.plist.backup-* file from EFI/OC over EFI/OC/config.plist."
elif [[ -z $loaded ]]; then
  say "not installed. It needs an entry in OpenCore's config.plist. Mount the EFI partition and run:"
  say "  diskutil list | grep EFI                 (find the partition OpenCore boots from)"
  say "  sudo diskutil mount <disk>s<n>"
  say "  sudo $0 --efi /Volumes/<EFI volume name>"
fi

step "Done"
say "Check it at any time with ./doctor.sh and measure it with ./test.sh. Log: $log"
(( running )) || { say "The service is installed but not running: see $log"; exit 2; }
exit 0
