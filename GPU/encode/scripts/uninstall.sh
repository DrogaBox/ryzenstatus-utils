#!/bin/zsh
# VCNEncodeFix uninstaller.
#
#   sudo ./uninstall.sh                       stop and remove the background service
#   sudo ./uninstall.sh --efi /Volumes/EFI    also remove VCNEncodeFloor.kext from that mounted OpenCore EFI
# Encoder services that were already patched keep the patch until they exit (closing the app is enough); the kext
# stays loaded until the next reboot. Exit status: 0 done; 1 refused or failed (the message says what is left).
emulate -L zsh
setopt no_unset
here=${0:A:h}
tool=$here/bin/vcnencodefix
say() { print -r -- "$@"; }
die() { print -r -- "error: $*" >&2; exit 1; }
exists() { [[ -e $1 || -L $1 ]]; }

efi=""
while (( $# )); do
  case $1 in
    --efi) (( $# >= 2 )) && [[ -n ${2%/} ]] || die "--efi needs the mount point of the EFI partition"
           efi=${2:A}; shift 2 ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' $0; exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
  esac
done
(( EUID == 0 )) || die "run it with sudo: sudo $0"
# sudo keeps the caller's PATH on macOS: only the system's own tools, whatever is in it
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
xattr -drs com.apple.quarantine $here 2>/dev/null

# what --efi needs is checked before anything is removed
if [[ -n $efi ]]; then
  [[ $efi != / ]] || die "--efi / is the system disk, not an EFI partition"
  cfg=$efi/EFI/OC/config.plist
  [[ -f $cfg ]] || die "$cfg not found: is $efi the mounted EFI partition with OpenCore? Nothing was removed."
  [[ -x $tool ]] || die "$tool is missing; unpack the whole folder. Nothing was removed."
fi

for label in com.droga.vcnencodefix com.droga.vcnpreset; do
  if launchctl bootout system/$label 2>/dev/null; then say "stopped $label"; fi
done
# the launchd plists first: a plist left behind would start a binary that is gone, every 30 s
for f in /Library/LaunchDaemons/com.droga.vcnencodefix.plist /Library/LaunchDaemons/com.droga.vcnpreset.plist; do
  if exists $f; then rm -f -- $f && say "removed $f" || die "cannot remove $f; the service binaries were kept"; fi
done
for f in /usr/local/libexec/vcnencodefix /usr/local/libexec/vcnencodefix.new /etc/newsyslog.d/vcnencodefix.conf /usr/local/libexec/vcnpreset; do
  if exists $f; then rm -f -- $f && say "removed $f" || say "warning: cannot remove $f"; fi
done
say "the log /var/log/vcnencodefix.log was kept"

if [[ -n $efi ]]; then
  $tool efi-remove $cfg || die "config.plist was not changed; see the message above. The kext was left on the EFI."
  k=$efi/EFI/OC/Kexts/VCNEncodeFloor.kext
  for d in $k $k.new $k.old; do
    exists $d || continue
    rm -rf -- $d
    exists $d && die "the entry is gone but $d could not be deleted; delete it by hand"
    say "removed $d"
  done
  say "The kext stays loaded until you reboot."
elif kextstat -l -b com.droga.VCNEncodeFloor 2>/dev/null | grep -q .; then
  say "VCNEncodeFloor.kext is still in your OpenCore EFI. To remove it: sudo $0 --efi /Volumes/<EFI volume name>"
fi
exit 0
