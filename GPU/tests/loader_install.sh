#!/bin/zsh
# loader_install.sh <sample OpenCore config.plist>
# Runs install/loader.sh and install/sensors.sh (the same code underneath, efikext.zsh)
# install and uninstall on made-up EFI folders in a temporary directory (their --efi-folder
# option), so no partition is mounted and no real EFI is touched.
# Needs the build: decode/build.sh, decode/loader/build.sh and sensors/build.sh.
# Exit status 0 = all passed.
emulate -L zsh
setopt no_unset
ROOT=${0:A:h:h}
sample=${1:?sample config}
L=$ROOT/install/loader.sh
B=$ROOT/decode/build
T=$(mktemp -d)
pass=0; fail=0
ok()  { print -r -- "PASS $1"; pass=$((pass+1)); }
bad() { print -r -- "FAIL $1"; fail=$((fail+1)); }

# make_efi <name> [lilu version]: a folder that looks like an OpenCore EFI
make_efi() {
  local d=$T/$1 v=${2:-1.7.2}
  mkdir -p $d/EFI/OC/Kexts/Lilu.kext/Contents
  cp $sample $d/EFI/OC/config.plist
  : > $d/EFI/OC/OpenCore.efi
  print -r -- '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>'$v'</string></dict></plist>' \
    > $d/EFI/OC/Kexts/Lilu.kext/Contents/Info.plist
  cp $d/EFI/OC/config.plist $d/orig.plist
}
# everything on the made-up EFI, as one checksum
# the files' contents, and every folder and link by name: a refusal that leaves an empty
# VCNVTLoader.kext.new behind must show
state() { (cd $T/$1/EFI && { find . -type f | sort | xargs shasum -a 256; find . ! -type f | sort; } | shasum -a 256); }
backups() { print -l -- $T/$1/EFI/OC/config.plist.backup-*(N) | grep -c .; }

# 1. a first install
make_efi a
$L install --efi-folder $T/a > $T/a.out 2>&1 && ok "install ends with 0" || bad "install: $(cat $T/a.out)"
cmp -s $T/a/EFI/OC/Kexts/VCNVTLoader.kext/Contents/MacOS/VCNVTLoader $B/VCNVTLoader.kext/Contents/MacOS/VCNVTLoader &&
  cmp -s $T/a/EFI/OC/Kexts/VCNVTLoader.kext/Contents/Info.plist $B/VCNVTLoader.kext/Contents/Info.plist &&
  ok "the kext on the EFI is the built one" || bad "kext copy"
[[ $(diff $T/a/orig.plist $T/a/EFI/OC/config.plist | grep -c '^>') == 18 && $(diff $T/a/orig.plist $T/a/EFI/OC/config.plist | grep -c '^<') == 0 ]] &&
  ok "config.plist gained the 18 lines of the entry and nothing else" || bad "config diff"
[[ $(backups a) == 1 ]] && cmp -s $T/a/orig.plist $T/a/EFI/OC/config.plist.backup-*-pre-vcnvtloader &&
  ok "one backup, equal to the original" || bad "backup"
[[ -z "$(print -l -- $T/a/EFI/OC/Kexts/*.new(N) $T/a/EFI/OC/Kexts/*.old(N) $T/a/EFI/OC/*-tmp(N))" ]] && ok "no leftovers" || bad "leftovers"
grep -q "copy EFI/OC/config.plist.backup-" $T/a.out && ok "the rescue note names the backup" || bad "rescue note"
$L check --efi-folder $T/a > $T/a.chk 2>&1
grep -q "config entry ok; kext the one in build/VCNVTLoader.kext, lists the plug-ins" $T/a.chk && ok "check sees it in place" || bad "check: $(cat $T/a.chk)"

# 2. the same install again changes nothing
s1=$(state a)
$L install --efi-folder $T/a > $T/a2.out 2>&1 && grep -q "already there, the same build" $T/a2.out && grep -q "nothing to change" $T/a2.out &&
  [[ $(state a) == $s1 ]] && ok "a second install changes nothing" || bad "second install: $(cat $T/a2.out)"

# 3. uninstall gives the original config back, byte for byte
$L uninstall --efi-folder $T/a > $T/a3.out 2>&1 && cmp -s $T/a/orig.plist $T/a/EFI/OC/config.plist && [[ ! -e $T/a/EFI/OC/Kexts/VCNVTLoader.kext ]] &&
  ok "uninstall restores config.plist and removes the kext" || bad "uninstall: $(cat $T/a3.out)"
$L uninstall --efi-folder $T/a > $T/a4.out 2>&1 && grep -q "Nothing to remove" $T/a4.out && ok "a second uninstall has nothing to do" || bad "second uninstall: $(cat $T/a4.out)"

# 4. another build of the kext is replaced; a leftover of an interrupted run is cleaned
make_efi b
$L install --efi-folder $T/b > /dev/null 2>&1
print -n x >> $T/b/EFI/OC/Kexts/VCNVTLoader.kext/Contents/MacOS/VCNVTLoader
mkdir -p $T/b/EFI/OC/Kexts/VCNVTLoader.kext.new/Contents
$L check --efi-folder $T/b 2>&1 | grep -q "kext another build than build/VCNVTLoader.kext" && ok "check sees another build" || bad "check another build"
$L install --efi-folder $T/b > $T/b.out 2>&1 && grep -q "kext: replaced VCNVTLoader" $T/b.out &&
  cmp -s $T/b/EFI/OC/Kexts/VCNVTLoader.kext/Contents/MacOS/VCNVTLoader $B/VCNVTLoader.kext/Contents/MacOS/VCNVTLoader &&
  [[ ! -e $T/b/EFI/OC/Kexts/VCNVTLoader.kext.new && ! -e $T/b/EFI/OC/Kexts/VCNVTLoader.kext.old ]] &&
  ok "another build is replaced, leftovers removed" || bad "replace: $(cat $T/b.out)"

# 5. an entry that was switched off is replaced by a working one
make_efi c
$L install --efi-folder $T/c > /dev/null 2>&1
perl -0pi -e 's{(<string>VCNVTLoader.kext</string>.*?<key>Enabled</key>\s*)<true/>}{$1<false/>}s' $T/c/EFI/OC/config.plist
$L check --efi-folder $T/c 2>&1 | grep -q "config entry there with other settings (DISABLED" && ok "check sees the disabled entry" || bad "check disabled"
$L install --efi-folder $T/c > $T/c.out 2>&1 && grep -q "The entry is replaced" $T/c.out &&
  $L check --efi-folder $T/c 2>&1 | grep -q "config entry ok" && ok "a disabled entry is replaced" || bad "disabled entry: $(cat $T/c.out)"

# 6. refusals: nothing on the EFI changes
refused() { # name what-to-find command...
  local name=$1 find=$2; shift 2
  local before=$(state $name)
  "$@" > $T/$name.out 2>&1
  local rc=$?
  [[ $rc -ne 0 ]] && grep -q -- "$find" $T/$name.out && [[ $(state $name) == $before ]]
}
make_efi d 1.6.9
refused d "needs 1.7.0 or newer" $L install --efi-folder $T/d && ok "an old Lilu is refused, nothing changed" || bad "old Lilu: $(cat $T/d.out)"
make_efi e
perl -0pi -e 's{(<string>Lilu.kext</string>.*?<key>Enabled</key>\s*)<true/>}{$1<false/>}s' $T/e/EFI/OC/config.plist
refused e "Lilu.kext is disabled" $L install --efi-folder $T/e && ok "a disabled Lilu is refused, nothing changed" || bad "disabled Lilu: $(cat $T/e.out)"
make_efi f
plutil -convert binary1 $T/f/EFI/OC/config.plist
refused f "cannot be edited" $L install --efi-folder $T/f && ok "a binary config.plist is refused, nothing changed" || bad "binary config: $(cat $T/f.out)"
make_efi g
/bin/rm -f -- $T/g/EFI/OC/OpenCore.efi
refused g "has no OpenCore" $L install --efi-folder $T/g && ok "a folder without OpenCore is refused" || bad "no OpenCore: $(cat $T/g.out)"
# plug-ins of another build: the same bundles with one more byte in a resource, signed again
make_efi h
mkdir -p $T/other
cp -R $B/AV1VCNDecoder.bundle $B/VP9VCNDecoder.bundle $T/other/
for b in $T/other/*.bundle; do print "<!-- other -->" >> $b/Contents/Info.plist; codesign -f -s - $b 2>/dev/null; done
refused h "built for other plug-ins" $L install --efi-folder $T/h --bundles $T/other && ok "a kext built for other plug-ins is refused, nothing changed" || bad "other plug-ins: $(cat $T/h.out)"
$L install --efi-folder $T/h --bundles $T/other > /dev/null 2>&1; [[ $? == 2 ]] && ok "that refusal ends with status 2" || bad "status of the refusal"

# 7. the rescue note only names a backup written by the same run
make_efi i
$L install --efi-folder $T/i > /dev/null 2>&1
print -n x >> $T/i/EFI/OC/Kexts/VCNVTLoader.kext/Contents/MacOS/VCNVTLoader
$L install --efi-folder $T/i > $T/i.out 2>&1 && grep -q "kext: replaced" $T/i.out && ! grep -q "config.plist.backup-" $T/i.out &&
  grep -q "set Enabled to false" $T/i.out && ok "a run that writes no backup names none" || bad "rescue note: $(cat $T/i.out)"

# 8. a run cut between the two moves is repaired by the next one
make_efi j
$L install --efi-folder $T/j > /dev/null 2>&1
mv $T/j/EFI/OC/Kexts/VCNVTLoader.kext $T/j/EFI/OC/Kexts/VCNVTLoader.kext.old
$L install --efi-folder $T/j > $T/j.out 2>&1 && grep -q "put back VCNVTLoader.kext" $T/j.out &&
  [[ -d $T/j/EFI/OC/Kexts/VCNVTLoader.kext && ! -e $T/j/EFI/OC/Kexts/VCNVTLoader.kext.old ]] &&
  ok "a kext left aside by a cut run is put back" || bad "recover: $(cat $T/j.out)"

# 9. with Lilu switched off after the install, check does not call the entry ok
perl -0pi -e 's{(<string>Lilu.kext</string>.*?<key>Enabled</key>\s*)<true/>}{$1<false/>}s' $T/j/EFI/OC/config.plist
$L check --efi-folder $T/j 2>&1 | grep -q "Lilu.kext is disabled, so the kext cannot start" && ok "check sees that Lilu is off" || bad "check with Lilu off"

# 10. a file where the kext folder goes is refused, nothing changed
make_efi k
print x > $T/k/EFI/OC/Kexts/VCNVTLoader.kext
refused k "is a file, not a kext folder" $L install --efi-folder $T/k && ok "a file in the kext's place is refused" || bad "file in place: $(cat $T/k.out)"

# 11. the sensors kext goes on the same EFI next to the loader, and comes off alone. A CI
#     runner has no AMD card, so the card list is stood in for (sensors.sh honours that
#     only with --efi-folder).
SN=$ROOT/install/sensors.sh
export VCNVT_FAKE_GPU="AMD Radeon RX 6800 XT (0x73bf)"
make_efi m
$L install --efi-folder $T/m > /dev/null 2>&1
cp $T/m/EFI/OC/config.plist $T/m/with-loader.plist
$SN install --efi-folder $T/m > $T/m.out 2>&1 && [[ -d $T/m/EFI/OC/Kexts/GPUSensors.kext ]] &&
  grep -q "added GPUSensors.kext" $T/m.out && grep -q "add -gpusensoff" $T/m.out &&
  ok "the sensors kext installs next to the loader" || bad "sensors install: $(cat $T/m.out)"
$SN check --efi-folder $T/m 2>&1 | grep -q "config entry ok; kext the one in build/GPUSensors.kext" &&
  $L check --efi-folder $T/m 2>&1 | grep -q "config entry ok" && ok "both kexts are seen in place" || bad "both in place"
$SN uninstall --efi-folder $T/m > /dev/null 2>&1 && cmp -s $T/m/with-loader.plist $T/m/EFI/OC/config.plist &&
  [[ ! -e $T/m/EFI/OC/Kexts/GPUSensors.kext && -d $T/m/EFI/OC/Kexts/VCNVTLoader.kext ]] &&
  ok "uninstalling the sensors leaves the loader exactly as it was" || bad "sensors uninstall"

# 12. leftovers that are hard to remove, and a Lilu without its Info.plist
make_efi n
ln -s /nonexistent $T/n/EFI/OC/Kexts/VCNVTLoader.kext.new
$L install --efi-folder $T/n > $T/n.out 2>&1 && [[ -d $T/n/EFI/OC/Kexts/VCNVTLoader.kext && ! -L $T/n/EFI/OC/Kexts/VCNVTLoader.kext.new ]] &&
  ok "a broken link left as .new is removed and the install goes on" || bad "broken link: $(cat $T/n.out)"
make_efi o
/bin/rm -f -- $T/o/EFI/OC/Kexts/Lilu.kext/Contents/Info.plist
refused o "cannot read the version of Lilu.kext" $L install --efi-folder $T/o && ok "a Lilu without Info.plist is refused, nothing changed" || bad "Lilu without plist: $(cat $T/o.out)"
make_efi p
$L install --efi-folder $T/p > /dev/null 2>&1
print -n x >> $T/p/EFI/OC/Kexts/VCNVTLoader.kext/Contents/MacOS/VCNVTLoader
mkdir -p $T/p/EFI/OC/Kexts/VCNVTLoader.kext.old/stuck && : > $T/p/EFI/OC/Kexts/VCNVTLoader.kext.old/stuck/file
chmod 555 $T/p/EFI/OC/Kexts/VCNVTLoader.kext.old/stuck
$L install --efi-folder $T/p > $T/p.out 2>&1
rc=$?
chmod 755 $T/p/EFI/OC/Kexts/VCNVTLoader.kext.old/stuck
[[ $rc -ne 0 ]] && grep -q "cannot remove a leftover" $T/p.out && [[ -f $T/p/EFI/OC/Kexts/VCNVTLoader.kext/Contents/MacOS/VCNVTLoader &&
  ! -e $T/p/EFI/OC/Kexts/VCNVTLoader.kext.old/VCNVTLoader.kext && ! -e $T/p/EFI/OC/Kexts/VCNVTLoader.kext.new ]] &&
  ok "an .old that cannot be removed stops the swap; the kext in place is untouched" || bad "stuck old: $(cat $T/p.out)"

# 13. wrong usage
$L install --efi disk0s1 --efi-folder $T/a > /dev/null 2>&1; [[ $? == 64 ]] && ok "--efi with --efi-folder is wrong usage" || bad "usage"
# its own exit status counts too, not only what python makes of the output
json=$($L check --json --efi-folder $T/b) && print -r -- $json | /usr/bin/python3 -I -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["efis"][0]["entry"]=="ok" and d["efis"][0]["kext"]=="current" else 1)' &&
  ok "check --json is valid JSON and says the same" || bad "json"

cd /; /bin/rm -rf -- "$T"
print "loader install tests: $pass passed, $fail failed"
(( fail == 0 ))
