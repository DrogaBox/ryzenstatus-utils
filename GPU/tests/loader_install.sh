#!/bin/zsh
# loader_install.sh <sample OpenCore config.plist>
# Runs install/loader.sh and install/sensors.sh (the same code underneath, efikext.zsh)
# install and uninstall on made-up EFI folders in a temporary directory (their --efi-folder
# option), so no partition is mounted and no real EFI is touched. Also reads the decoders'
# install record with 'install/decoders.sh check', from a made-up record folder and a
# made-up running system (test variables honoured by check only), and runs the function
# decoders.sh install uses to put the plug-ins on a made-up system volume, with and without
# --legacy; nothing is installed.
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
# The decoders' check takes the kext just put there as the loader of the next boot: install.sh
# installs the decoders right after the loader kext, in the same run, because of this.
loader_in_fn=$(sed -n '/^loader_in() {/,/^}/p' $ROOT/install/decoders.sh)
[[ -n $loader_in_fn ]] &&
  /bin/zsh -c 'emulate -L zsh; setopt no_unset; ROOT=$1; source $ROOT/install/common.zsh
    BUNDLES=$ROOT/decode/build; AV1=AV1VCNDecoder.bundle; VP9=VP9VCNDecoder.bundle; WANT=($AV1 $VP9)
    eval "$2"; loader_in "$3"' loader_in "$ROOT" "$loader_in_fn" $T/a/EFI/OC &&
  ok "the decoders' check (loader_in) accepts the loader kext just installed" || bad "loader_in refused the new install"

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
# an older GPUSensors runs (VCNVT_FAKE_RUNNING, honoured only with --efi-folder) and this
# version is on the EFI: the next boot loads it, so check offers no update. With another
# build on the EFI it does.
sjson() { VCNVT_FAKE_RUNNING=0.0.1 $SN check --json --efi-folder $T/$1; }
spy() { /usr/bin/python3 -I -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if eval(sys.argv[1]) else 1)' "$1"; }
sjson m | spy 'd["pendingReboot"] and d["result"].startswith("installed on folder: GPUSensors ") and "loads at the next boot; 0.0.1 runs until then" in d["result"]' &&
  ok "an older sensors kext runs, this one on the EFI: installed, reboot" || bad "sensors pending: $(sjson m)"
VCNVT_FAKE_RUNNING=0.0.1 $SN check --efi-folder $T/m 2>&1 | grep -q "Result: installed on folder: GPUSensors .* loads at the next boot" &&
  ok "the text check says the same" || bad "sensors pending text"
make_efi q
$SN install --efi-folder $T/q > /dev/null 2>&1
print -n x >> $T/q/EFI/OC/Kexts/GPUSensors.kext/Contents/MacOS/GPUSensors
sjson q | spy 'not d["pendingReboot"] and d["result"].startswith("GPUSensors 0.0.1 is loaded; ") and "puts it on your EFI" in d["result"]' &&
  ok "an older sensors kext runs, another build on the EFI: update offered" || bad "sensors old on EFI: $(sjson q)"
# the install record (common.zsh): an install writes it, the check takes it for a partition
# it cannot look into (here: another folder, r, without the kext), only from this boot
# session and only for this build. VCNVT_FAKE_RECORDS stands in for its folder in
# /Library, honoured only with --efi-folder.
R=$T/records
mkdir -m 755 $R
make_efi s
make_efi r
VCNVT_FAKE_RECORDS=$R $SN install --efi-folder $T/s > $T/s.out 2>&1
rec=$R/installed-GPUSensors.txt
[[ -f $rec && $(stat -f '%Lp' $rec) == 644 ]] && grep -qx "boot=$(sysctl -n kern.bootsessionuuid)" $rec &&
  grep -qx "partition=folder:${T:A}/s" $rec && grep -qx "bundle=com.droga.GPUSensors" $rec &&
  ok "an install writes its record (mode 644, this boot session, the place, the build)" || bad "record: $(cat $T/s.out; cat $rec 2>&1)"
[[ -z "$(print -l -- $R/.*(N))" ]] && ok "no temporary file is left next to it" || bad "record leftovers"
rjson() { VCNVT_FAKE_RUNNING=0.0.1 VCNVT_FAKE_RECORDS=$R $SN check --json --efi-folder $T/r; }
rjson | spy 'd["pendingReboot"] and d["result"].startswith("installed on folder: GPUSensors ") and "loads at the next boot" in d["result"]' &&
  ok "record of this build, this boot, the EFI not visible: installed, reboot" || bad "record pending: $(rjson)"
VCNVT_FAKE_RUNNING=0.0.1 VCNVT_FAKE_RECORDS=$R $SN check --efi-folder $T/r 2>&1 | grep -q "this build was put there in this boot session (install record)" &&
  ok "the text check names the record" || bad "record text"
VCNVT_FAKE_RUNNING=0.0.1 $SN check --json --efi-folder $T/r | spy 'not d["pendingReboot"] and "puts it on your EFI" in d["result"]' &&
  ok "without the record folder (not test mode for it): update offered" || bad "no record folder"
cp $rec $T/rec.keep
sed -i '' 's/^boot=.*/boot=00000000-0000-0000-0000-000000000000/' $rec
rjson | spy 'not d["pendingReboot"] and d["result"].startswith("GPUSensors 0.0.1 is loaded; ") and "puts it on your EFI" in d["result"]' &&
  ok "record from another boot session: ignored, update offered" || bad "record other boot: $(rjson)"
cp $T/rec.keep $rec
sed -i '' 's/^hash=.*/hash=0000/' $rec
rjson | spy 'not d["pendingReboot"] and "puts it on your EFI" in d["result"]' &&
  ok "record for another build: ignored, update offered" || bad "record other build: $(rjson)"
cp $T/rec.keep $rec
VCNVT_FAKE_RUNNING=0.0.1 VCNVT_FAKE_RECORDS=$R $SN check --json --efi-folder $T/s | spy 'd["pendingReboot"] and d["efis"][0]["kext"] == "current"' &&
  ok "the EFI the record names, visible: what it shows is used" || bad "record visible"
print -n x >> $T/s/EFI/OC/Kexts/GPUSensors.kext/Contents/MacOS/GPUSensors
VCNVT_FAKE_RUNNING=0.0.1 VCNVT_FAKE_RECORDS=$R $SN check --json --efi-folder $T/s | spy 'not d["pendingReboot"] and "puts it on your EFI" in d["result"]' &&
  ok "the EFI the record names shows another build: that wins over the record" || bad "record vs visible"
chmod 666 $rec
rjson | spy 'not d["pendingReboot"]' && ok "a record others can write is not believed" || bad "record writable"
chmod 644 $rec
mv $rec $T/rec.real && ln -s $T/rec.real $rec
rjson | spy 'not d["pendingReboot"]' && ok "a record that is a link is not believed" || bad "record link"
VCNVT_FAKE_RECORDS=$R $SN install --efi-folder $T/s > $T/s2.out 2>&1
[[ -L $rec ]] && grep -q "is not a plain file" $T/s2.out && ok "an install does not write through a link" || bad "record write link: $(cat $T/s2.out)"
rm -f $rec
VCNVT_FAKE_RECORDS=$R $SN install --efi-folder $T/s > /dev/null 2>&1
VCNVT_FAKE_RECORDS=$R $SN uninstall --efi-folder $T/s > /dev/null 2>&1
grep -qx "action=remove" $rec && ok "uninstall deletes the install record and writes the removal one" || bad "record after uninstall: $(cat $rec 2>&1)"
VCNVT_FAKE_RECORDS=$R $L install --efi-folder $T/s > /dev/null 2>&1
grep -qx "bundle=com.droga.VCNVTLoader" $R/installed-VCNVTLoader.txt &&
  VCNVT_FAKE_RECORDS=$R $L check --efi-folder $T/r 2>&1 | grep -q "this build was put there in this boot session (install record)" &&
  ok "the loader writes and reads its record the same way" || bad "loader record"
VCNVT_FAKE_RECORDS=$R $L uninstall --efi-folder $T/s > /dev/null 2>&1
[[ ! -e $R/installed-VCNVTLoader.txt ]] && ok "the loader's uninstall deletes its record" || bad "loader record after uninstall"
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

# 14. the closing note on the plug-ins installed now: left out when install.sh installs the
#     decoders right after the kext in the same run (GPU_INSTALL_DECODERS_NEXT). The running
#     system's plug-ins are stood in for (VCNVT_FAKE_LIVE, honoured only with --efi-folder):
#     another build ($T/other, from 6.) or none.
mkdir -p $T/nolive
make_efi t1
VCNVT_FAKE_LIVE=$T/other $L install --efi-folder $T/t1 > $T/t1.out 2>&1 &&
  grep -q "installed now are another build, which this kext does not list" $T/t1.out &&
  ok "loader install alone: the note on the other build installed now" || bad "note other build: $(cat $T/t1.out)"
make_efi t2
GPU_INSTALL_DECODERS_NEXT=1 VCNVT_FAKE_LIVE=$T/other $L install --efi-folder $T/t2 > $T/t2.out 2>&1 &&
  grep -q "Reboot. Then" $T/t2.out && ! grep -qi "decoder plug-ins" $T/t2.out &&
  ok "the decoders are the next step of the run: no note on the plug-ins installed now" || bad "note left out: $(cat $T/t2.out)"
make_efi t3
VCNVT_FAKE_LIVE=$T/nolive $L install --efi-folder $T/t3 > $T/t3.out 2>&1 && grep -q "The decoder plug-ins are not installed yet" $T/t3.out &&
  ok "loader install alone, no plug-ins installed: the note says so" || bad "note none: $(cat $T/t3.out)"
make_efi t4
GPU_INSTALL_DECODERS_NEXT=1 VCNVT_FAKE_LIVE=$T/nolive $L install --efi-folder $T/t4 > $T/t4.out 2>&1 && ! grep -qi "decoder plug-ins" $T/t4.out &&
  ok "the decoders are the next step, none installed now: no note either" || bad "note none left out: $(cat $T/t4.out)"
make_efi t5
GPU_INSTALL_DECODERS_NEXT=0 VCNVT_FAKE_LIVE=$T/other $L install --efi-folder $T/t5 > $T/t5.out 2>&1 &&
  grep -q "another build, which this kext does not list" $T/t5.out && ok "GPU_INSTALL_DECODERS_NEXT=0 keeps the note" || bad "note with 0: $(cat $T/t5.out)"

# 15. the decoders' install record (decoders.sh): install and uninstall bless a new boot
#     snapshot and the running system keeps its plug-ins until the reboot, so a check of the
#     same boot takes the record: "pending" install or remove. The record is written by the
#     function decoders.sh install calls (dec_record_write), here into a folder of ours, with
#     a made-up system volume holding the plug-ins to install.
D=$ROOT/install/decoders.sh
R2=$T/dec-records
mkdir -m 755 $R2
mkdir -p $T/mnt/System/Library/Video/Plug-Ins $T/check-cache
cp -R $B/AV1VCNDecoder.bundle $B/VP9VCNDecoder.bundle $T/mnt/System/Library/Video/Plug-Ins/
dec_write_fn=$(sed -n '/^dec_record_write() {/,/^}/p' $D)
dec_write() { # install | remove
  VCNVT_FAKE_RECORDS=$R2 /bin/zsh -c 'emulate -L zsh; setopt no_unset; ROOT=$1; source $ROOT/install/common.zsh
    RECORD_FAKE_OK=1; MNT=$2; PLUGDIR=System/Library/Video/Plug-Ins; AV1=AV1VCNDecoder.bundle
    VP9=VP9VCNDecoder.bundle; DEC_RECORD=decoders; eval "$3"; dec_record_write $4' \
    dec_write "$ROOT" $T/mnt "$dec_write_fn" $1
}
# the check, with the record folder and the running system's plug-ins stood in for
dcheck() { # live-folder [--json]
  local live=$1; shift
  GPU_CHECK_CACHE=$T/check-cache VCNVT_FAKE_RECORDS=$R2 VCNVT_FAKE_LIVE=$live $D check "$@" 2>&1
}
dspy() { dcheck $1 --json | spy "$2"; }
drec=$R2/installed-decoders.txt
h_av1=$(codesign -dvvv $B/AV1VCNDecoder.bundle 2>&1 | sed -n 's/^CDHash=//p')
[[ -n $dec_write_fn ]] && dec_write install > $T/dw.out 2>&1
[[ -f $drec && $(stat -f '%Lp' $drec) == 644 ]] && grep -qx "boot=$(sysctl -n kern.bootsessionuuid)" $drec &&
  grep -qx "action=install" $drec && grep -qx "av1=$h_av1" $drec && [[ -z "$(print -l -- $R2/.*(N))" ]] &&
  ok "decoders install record: mode 644, this boot, the cdhashes put in place, no temporary file" || bad "decoders record: $(cat $T/dw.out; cat $drec 2>&1)"
dspy $T/other 'd["pending"] == "install" and d["installed"] == "outdated"' &&
  ok "another build runs, these are in the snapshot: pending install, installed stays outdated" || bad "pending install: $(dcheck $T/other --json)"
dcheck $T/other > $T/dc.out
grep -q "^Result: installed; they load at the next reboot." $T/dc.out && grep -q "^Installed now: .*load at the next boot" $T/dc.out &&
  ! grep -q "ready to update" $T/dc.out && ok "the text check says installed, reboot (no update offered)" || bad "pending text: $(cat $T/dc.out)"
dspy $T/nolive 'd["pending"] == "install" and d["installed"] == "none"' &&
  ok "a first install, none running yet: pending install" || bad "pending first install: $(dcheck $T/nolive --json)"
# the running system after the reboot: AV1 and VP9 only (decode/build also holds the
# MPEG-2, VC-1 and MPEG-4 plug-ins, which a check without --legacy reports as left over)
mkdir -p $T/booted
cp -R $B/AV1VCNDecoder.bundle $B/VP9VCNDecoder.bundle $T/booted/
dspy $T/booted 'd["pending"] == "none" and d["installed"] == "current"' &&
  ok "after the reboot these run: nothing pending" || bad "pending after reboot: $(dcheck $T/booted --json)"
GPU_CHECK_CACHE=$T/check-cache VCNVT_FAKE_LIVE=$T/other $D check --json | spy 'd["pending"] == "none"' &&
  ok "no record folder given: nothing pending" || bad "no record folder"
cp $drec $T/drec.keep
sed -i '' 's/^boot=.*/boot=00000000-0000-0000-0000-000000000000/' $drec
dspy $T/other 'd["pending"] == "none" and d["installed"] == "outdated"' &&
  ok "decoders record from another boot session: ignored, update offered" || bad "decoders record other boot: $(dcheck $T/other --json)"
cp $T/drec.keep $drec
sed -i '' 's/^av1=.*/av1=0000/' $drec
dspy $T/other 'd["pending"] == "none"' && ok "decoders record of other plug-ins than these: ignored" || bad "decoders record other hashes: $(dcheck $T/other --json)"
cp $T/drec.keep $drec
chmod 666 $drec
dspy $T/other 'd["pending"] == "none"' && ok "a decoders record others can write is not believed" || bad "decoders record writable"
chmod 644 $drec
dec_write remove > $T/dw2.out 2>&1
grep -qx "action=remove" $drec && grep -qx "av1=" $drec && ok "an uninstall's record: action remove, no cdhashes" || bad "remove record: $(cat $T/dw2.out; cat $drec)"
dspy $T/other 'd["pending"] == "remove" and d["installed"] == "outdated"' &&
  ok "removed in this boot, still running: pending remove" || bad "pending remove: $(dcheck $T/other --json)"
dcheck $T/other | grep -q "^Result: removed; the running system keeps them until the next reboot." &&
  ok "the text check says removed, reboot" || bad "pending remove text: $(dcheck $T/other)"
dspy $T/nolive 'd["pending"] == "none" and d["installed"] == "none"' &&
  ok "removed, and none run any more: nothing pending" || bad "remove done: $(dcheck $T/nolive --json)"
sed -i '' 's/^boot=.*/boot=00000000-0000-0000-0000-000000000000/' $drec
dspy $T/other 'd["pending"] == "none"' && ok "a removal from another boot session: ignored" || bad "remove other boot"

# 16. MPEG-2, VC-1 and MPEG-4 left by an install with --legacy: an install without it takes
#     them off, and a check without it reports them. The functions decoders.sh install calls
#     (put_decoders and what it uses) run on a made-up system volume and /Library folder;
#     chown is left out (not root), everything else is the script's own code.
LEG=(MPEG2VCNDecoder.bundle VC1VCNDecoder.bundle MPEG4VCNDecoder.bundle)
put_fns=$(for f in safe_rm_bundle source_ok install_one drop_stale_legacy drop_stale_jpeg put_decoders; do sed -n "/^$f() {/,/^}/p" $D; done)
SYS=$T/leg-sys/System/Library/Video/Plug-Ins
LIBP=$T/leg-lib/Library/Video/Plug-Ins
mkdir -p $SYS $LIBP
dput() { # [legacy|jpeg]: put_decoders as decoders.sh install runs it, with or without --legacy / --jpeg
  VCNVT_LEGACY_DECODERS=$([[ ${1:-} == legacy ]] && print 1 || print 0) VCNVT_JPEG_DECODER=$([[ ${1:-} == jpeg ]] && print 1 || print 0) \
  /bin/zsh -c 'emulate -L zsh; setopt no_unset; ROOT=$1; source $ROOT/install/common.zsh
    BUNDLES=$ROOT/decode/build; MNT=$2; PLUGDIR=System/Library/Video/Plug-Ins; LIBPLUG=$3
    AV1=AV1VCNDecoder.bundle; VP9=VP9VCNDecoder.bundle; WANT=($AV1 $VP9); legacy_on && WANT+=($LEGACY_BUNDLES)
    jpeg_on && WANT+=($JPEG_BUNDLE)
    ALL=($AV1 $VP9 $LEGACY_BUNDLES $JPEG_BUNDLE); chown() { :; }; eval "$4"; put_decoders' \
    dput "$ROOT" $T/leg-sys $LIBP "$put_fns"
}
nleg() { local n=0 b; for b in $LEG; do [[ -e $1/$b ]] && n=$((n + 1)); done; print $n; }
[[ -n $put_fns ]] && dput legacy > $T/lp1.out 2>&1 && [[ $(nleg $SYS) == 3 && -d $SYS/AV1VCNDecoder.bundle && -d $SYS/VP9VCNDecoder.bundle ]] &&
  ok "install --legacy: all five plug-ins on the system volume" || bad "install --legacy: $(cat $T/lp1.out)"
dlcheck() { # live [--legacy] [--json]: check with the made-up running system
  local live=$1; shift
  GPU_CHECK_CACHE=$T/check-cache VCNVT_FAKE_LIVE=$live VCNVT_LEGACY_DECODERS=0 $D check "$@" 2>&1
}
dlcheck $SYS --legacy --json | spy 'd["installed"] == "current" and not [c for c in d["checks"] if c["id"] == "legacy-left"]' &&
  ok "check --legacy with all five in place: current, nothing left over" || bad "check --legacy five: $(dlcheck $SYS --legacy --json)"
dlcheck $SYS --json | spy 'd["installed"] == "outdated" and [c for c in d["checks"] if c["id"] == "legacy-left" and c["status"] == "warn" and "MPEG2VCNDecoder.bundle, VC1VCNDecoder.bundle, MPEG4VCNDecoder.bundle" in c["detail"]]' &&
  ok "check without --legacy sees the three left over: a warning, installed outdated (install.sh does not skip)" || bad "check stale: $(dlcheck $SYS --json)"
dlcheck $SYS > $T/lc.out
grep -q "^  warn  MPEG-2, VC-1 and MPEG-4 left over: " $T/lc.out && grep -q "^Installed now: .*from an earlier install with --legacy" $T/lc.out &&
  ok "the text check names them too" || bad "check stale text: $(cat $T/lc.out)"
# a copy in /Library and a half-made .new of an interrupted run go as well
cp -R $B/MPEG2VCNDecoder.bundle $LIBP/
cp -R $B/VC1VCNDecoder.bundle $SYS/VC1VCNDecoder.bundle.new
dput > $T/lp2.out 2>&1 && [[ $(nleg $SYS) == 0 && $(nleg $LIBP) == 0 && ! -e $SYS/VC1VCNDecoder.bundle.new ]] &&
  [[ -d $SYS/AV1VCNDecoder.bundle && -d $SYS/VP9VCNDecoder.bundle ]] && grep -q "removed .*MPEG4VCNDecoder.bundle (an earlier install with --legacy put it there)" $T/lp2.out &&
  ok "install without --legacy takes the three off (system, /Library, .new), keeps AV1 and VP9" || bad "install drops legacy: $(cat $T/lp2.out; ls $SYS $LIBP)"
dlcheck $SYS --json | spy 'd["installed"] == "current" and not [c for c in d["checks"] if c["id"] == "legacy-left"]' &&
  ok "after it the check sees AV1 and VP9 only: current, nothing left over" || bad "check after drop: $(dlcheck $SYS --json)"
dput > $T/lp3.out 2>&1 && ! grep -q removed $T/lp3.out && ok "a second install without --legacy has nothing to take off" || bad "second drop: $(cat $T/lp3.out)"
# an install of this boot without --legacy (its record) took them off the next boot's
# snapshot: the check says so instead of asking for another install
mkdir -p $T/leg-running2; cp -R $B/AV1VCNDecoder.bundle $B/VP9VCNDecoder.bundle $B/MPEG2VCNDecoder.bundle $T/leg-running2/
dec_write install > /dev/null 2>&1
dspy $T/leg-running2 'd["pending"] == "install" and [c for c in d["checks"] if c["id"] == "legacy-left" and c["status"] == "ok" and "go at the reboot" in c["detail"]]' &&
  ok "after an install without --legacy in this boot: the left-over legacy plug-in goes at the reboot, no warning" || bad "stale pending: $(dcheck $T/leg-running2 --json)"
dput legacy > /dev/null 2>&1 && [[ $(nleg $SYS) == 3 ]] && dput legacy > $T/lp4.out 2>&1 && [[ $(nleg $SYS) == 3 ]] && ! grep -q removed $T/lp4.out &&
  ok "install --legacy keeps them" || bad "legacy kept: $(cat $T/lp4.out)"
# 17. The JPEG plug-in works the same way with --jpeg.
dput jpeg > $T/lj1.out 2>&1 && [[ -d $SYS/JPEGVCNDecoder.bundle && $(nleg $SYS) == 0 && -d $SYS/AV1VCNDecoder.bundle ]] &&
  ok "install --jpeg: AV1, VP9 and JPEG on the system volume (the legacy ones taken off)" || bad "install --jpeg: $(cat $T/lj1.out)"
dlcheck $SYS --json | spy 'd["installed"] == "outdated" and [c for c in d["checks"] if c["id"] == "jpeg-left" and c["status"] == "warn"]' &&
  ok "check without --jpeg sees the JPEG plug-in left over: a warning, installed outdated" || bad "check jpeg stale: $(dlcheck $SYS --json)"
dput > $T/lj2.out 2>&1 && [[ ! -e $SYS/JPEGVCNDecoder.bundle && -d $SYS/AV1VCNDecoder.bundle ]] && grep -q "removed .*JPEGVCNDecoder.bundle (an earlier install with --jpeg put it there)" $T/lj2.out &&
  ok "install without --jpeg takes the JPEG plug-in off, keeps AV1 and VP9" || bad "install drops jpeg: $(cat $T/lj2.out; ls $SYS)"

# 18. encoder.sh takes only a partition like disk0s1, or auto, for --efi (b8e36c28 made it
#     the check install.sh and undo.sh make). A wrong value stops with a usage error before
#     anything runs; a value that passes the check is then seen by the command's own rules
#     (check refuses --efi on its own, install reaches its root check). No root and no
#     package are needed: the argument parser runs first.
E=$ROOT/install/encoder.sh
$E install --efi bogus > $T/e1.out 2>&1; [[ $? == 64 ]] && grep -q "takes a partition like disk0s1, or auto" $T/e1.out &&
  ok "encoder.sh refuses an --efi value that is not a partition or auto" || bad "encoder --efi bogus: $(cat $T/e1.out)"
$E uninstall --efi disk0 > $T/e2.out 2>&1; [[ $? == 64 ]] && grep -q "takes a partition like disk0s1, or auto" $T/e2.out &&
  ok "encoder.sh refuses an --efi value without an sN" || bad "encoder --efi disk0: $(cat $T/e2.out)"
$E install --efi disk0s1extra > $T/e3.out 2>&1; [[ $? == 64 ]] && grep -q "takes a partition like disk0s1, or auto" $T/e3.out &&
  ok "encoder.sh refuses an --efi value with something after diskNsM" || bad "encoder --efi suffix: $(cat $T/e3.out)"
$E check --efi "" > $T/e4.out 2>&1; [[ $? == 64 ]] && grep -q "takes a partition like disk0s1, or auto" $T/e4.out &&
  ok "encoder.sh refuses an empty --efi value" || bad "encoder --efi empty: $(cat $T/e4.out)"
$E install --efi > $T/e5.out 2>&1; [[ $? == 64 ]] && grep -q "takes a partition like disk0s1, or auto" $T/e5.out &&
  ok "encoder.sh refuses --efi without a value" || bad "encoder --efi missing: $(cat $T/e5.out)"
$E check --efi disk0s1 > $T/e6.out 2>&1; [[ $? == 64 ]] && grep -q "check looks at every EFI partition" $T/e6.out &&
  ok "a partition like disk0s1 passes the value check (check refuses --efi on its own)" || bad "encoder check --efi disk0s1: $(cat $T/e6.out)"
$E check --efi auto > $T/e7.out 2>&1; [[ $? == 64 ]] && grep -q "check looks at every EFI partition" $T/e7.out &&
  ok "auto passes the value check too" || bad "encoder check --efi auto: $(cat $T/e7.out)"
$E install --efi disk0s1 > $T/e8.out 2>&1; [[ $? == 1 ]] && grep -q "must run as root" $T/e8.out &&
  ok "a valid --efi takes install all the way to its root check" || bad "encoder install --efi disk0s1: $(cat $T/e8.out)"

# 19. efikext.zsh removes the install record only after the config.plist check that can still
#     abort the uninstall (b8e36c28): a refused uninstall leaves the record, so a check in the
#     same boot still knows the kext was put there. The record went first before, and the
#     refusal looked like the kext was never installed.
make_efi u
VCNVT_FAKE_RECORDS=$R $SN install --efi-folder $T/u > $T/u1.out 2>&1 &&
  [[ -f $rec ]] && ok "the sensors kext installs on one more folder, its record written" ||
  bad "sensors install u: $(cat $T/u1.out)"
plutil -convert binary1 $T/u/EFI/OC/config.plist
VCNVT_FAKE_RECORDS=$R $SN uninstall --efi-folder $T/u > $T/u2.out 2>&1
[[ $? -ne 0 ]] && grep -q "cannot be edited" $T/u2.out && [[ -f $rec ]] &&
  ok "an uninstall that cannot edit config.plist changes nothing, record included" ||
  bad "uninstall on binary config: $(cat $T/u2.out; ls $R)"
rjson | spy 'd["pendingReboot"]' &&
  ok "after the refused uninstall the check still believes the record" || bad "check after refused uninstall: $(rjson)"
plutil -convert xml1 $T/u/EFI/OC/config.plist
VCNVT_FAKE_RECORDS=$R $SN uninstall --efi-folder $T/u > $T/u3.out 2>&1 &&
  grep -qx "action=remove" $rec &&
  ok "the uninstall then goes ahead; the record left is the removal one" ||
  bad "uninstall after restore: $(cat $T/u3.out; cat $rec 2>&1)"

cd /; /bin/rm -rf -- "$T"
print "loader install tests: $pass passed, $fail failed"
(( fail == 0 ))
