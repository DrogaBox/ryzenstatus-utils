#!/bin/zsh
# VCNEncodeFix doctor: shows whether both halves are installed and active. It changes nothing on the Mac (it only
# clears the download quarantine flag from this folder, so that its own tools can run).
# Run it as yourself; with sudo it also shows the state of each running encoder service.
# Exit status: 0 always; the text says what is missing.
emulate -L zsh
here=${0:A:h}
installed=/usr/local/libexec/vcnencodefix
plist=/Library/LaunchDaemons/com.droga.vcnencodefix.plist
tool=$installed
[[ -x $tool ]] || tool=$here/bin/vcnencodefix
# sudo keeps the caller's PATH on macOS: only the system's own tools, whatever is in it
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
xattr -drs com.apple.quarantine $here 2>/dev/null
say() { print -r -- "$@"; }

say "VCNEncodeFix $(cat $here/VERSION 2>/dev/null || echo '?') doctor, $(date '+%Y-%m-%d %H:%M')"
say "macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n hw.model)"
system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Chipset Model/{m=$2} /Device ID/{print "GPU: " m " (" $2 ")"}'
# the arguments the kernel started with (nvram holds the next boot's)
ba=" $(sysctl -n kern.bootargs 2>/dev/null) "
[[ $ba == *" -vcnflooroff "* ]] && say "boot-args contain -vcnflooroff: the kext is disabled"

say ""
say "Kernel half (VCNEncodeFloor.kext)"
lilu=$(kextstat -l -b as.vit9696.Lilu 2>/dev/null | awk '{print $7}' | tr -d '()')
say "  Lilu: ${lilu:-not loaded}"
kv=$(kextstat -l -b com.droga.VCNEncodeFloor 2>/dev/null | awk '{print $7}' | tr -d '()')
if [[ -n $kv ]]; then
  state=$(ioreg -rd1 -c IOResources -k VCNEncodeFloor | awk -F'"' '$2 == "VCNEncodeFloor" {print $4}')
  say "  VCNEncodeFloor: loaded $kv, ${state:-no state published (older build?)}"
else
  say "  VCNEncodeFloor: not loaded (not in the OpenCore config, disabled, or not rebooted yet)"
  if (( $(uname -r | cut -d. -f1) < 25 )); then
    say "  On macOS 14/15: an entry written by VCNEncodeFix 1.2.0 or earlier has MinKernel 25.0.0 (Tahoe only), so"
    say "  OpenCore skips the kext. Run 'sudo ./install.sh --efi /Volumes/<EFI>' from this version and reboot."
  fi
fi

say ""
say "User-space half (service com.droga.vcnencodefix)"
flags=()
if [[ -e $plist ]]; then
  pid=$(pgrep -f "^$installed watch" | head -1)
  if [[ -n $pid ]]; then run="running, pid $pid"; else run="NOT running"; fi
  say "  installed; $run; $($installed version 2>/dev/null)"
  # the service's own options: ProgramArguments after "watch"
  i=2
  while a=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:$i" $plist 2>/dev/null); do
    flags+=($a)
    i=$((i + 1))
  done
  say "  options: ${flags:-none (defaults)}"
  if [[ -x $here/bin/vcnencodefix ]] && ! cmp -s $installed $here/bin/vcnencodefix; then
    say "  the installed binary is not the one in this folder: 'sudo ./install.sh' installs this one"
  fi
else
  say "  not installed"
fi
[[ -e /Library/LaunchDaemons/com.droga.vcnpreset.plist ]] && say "  an earlier test version (com.droga.vcnpreset) is installed; ./install.sh replaces it"
$tool status ${flags[@]} | sed 's/^/  /'
if [[ -r /var/log/vcnencodefix.log ]]; then
  say ""
  say "Last log lines (/var/log/vcnencodefix.log)"
  tail -8 /var/log/vcnencodefix.log | sed 's/^/  /'
fi
exit 0
