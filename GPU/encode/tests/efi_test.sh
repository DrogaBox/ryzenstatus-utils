#!/bin/zsh
# efi_test.sh <vcnencodefix> <sample OpenCore config.plist without the entry>
# Exercises efi-add / efi-remove / efi-check on copies only, in a temporary folder. Exit status 0 = all passed.
tool=${1:?tool}; sample=${2:?sample config}
# absolute before the cd below, and both must be there: the refusal tests would pass on a missing tool or an empty copy
tool=${tool:A}; sample=${sample:A}
[[ -x $tool ]] || { print -u2 "$tool is not an executable"; exit 2; }
[[ -s $sample ]] || { print -u2 "$sample is missing or empty"; exit 2; }
T=$(mktemp -d)
pass=0; fail=0
ok()  { print -r -- "PASS $1"; pass=$((pass+1)); }
bad() { print -r -- "FAIL $1"; fail=$((fail+1)); }
cd $T

# 1. tab-indented real config: add changes only the 18 entry lines, remove restores the exact bytes
cp $sample t.plist; cp t.plist t.orig
$tool efi-add t.plist > out1 2>&1 && grep -q "text edit" out1 && ok "add (tabs) by text edit" || bad "add (tabs): $(cat out1)"
[[ $(diff t.orig t.plist | grep -c '^>') == 18 && $(diff t.orig t.plist | grep -c '^<') == 0 ]] && ok "add (tabs) diff is 18 added lines" || bad "add (tabs) diff"
plutil -lint t.plist > /dev/null && ok "add (tabs) plutil -lint" || bad "add (tabs) plutil -lint"
$tool efi-add t.plist 2>&1 | grep -q "nothing to change" && ok "add twice is a no-op" || bad "add twice"
$tool efi-check t.plist | grep -q "settings as expected" && ok "check after add" || bad "check after add"
$tool efi-remove t.plist > out2 2>&1 && cmp -s t.plist t.orig && ok "remove restores the original bytes" || bad "remove: $(cat out2)"
[[ $(ls t.plist.backup-*-pre-vcnencodefix | wc -l) -eq 2 ]] && ok "one backup per change" || bad "backups: $(ls)"

# 2. space-indented copy
sed $'s/\t/    /g' $sample > s.plist; cp s.plist s.orig
$tool efi-add s.plist > out3 2>&1 && grep -q "text edit" out3 && ok "add (spaces) by text edit" || bad "add (spaces): $(cat out3)"
grep -q '^            <dict>$' s.plist && grep -q '^                <string>VCNEncodeFloor.kext</string>$' s.plist && ok "add (spaces) keeps the indentation" || bad "add (spaces) indentation"
$tool efi-remove s.plist > /dev/null 2>&1 && cmp -s s.plist s.orig && ok "remove (spaces) restores the original bytes" || bad "remove (spaces)"

# 3. entry present with another Comment counts as installed
cp $sample c.plist; $tool efi-add c.plist > /dev/null 2>&1
sed -i '' 's/VCNEncodeFix: VCN encode clock floor/my own comment/' c.plist
$tool efi-add c.plist 2>&1 | grep -q "nothing to change" && ok "other Comment is accepted" || bad "other Comment"

# 4. empty Kernel > Add (<array/>) falls back to CoreFoundation and is still verified
perl -0pe 's{(<key>Kernel</key>\s*<dict>\s*<key>Add</key>\s*)<array>.*?</array>}{$1<array/>}s' $sample > e.plist
$tool efi-add e.plist > out4 2>&1; rc=$?
(( rc != 0 )) && grep -q "Lilu.kext is not enabled" out4 && ok "empty Add without Lilu is refused" || bad "empty Add (exit $rc): $(cat out4)"

# 5. Lilu disabled is refused, file untouched
perl -0pe 's{(<string>Lilu.kext</string>.*?<key>Enabled</key>\s*)<true/>}{$1<false/>}s' $sample > l.plist; cp l.plist l.orig
$tool efi-add l.plist > /dev/null 2>&1; [[ $? -ne 0 ]] && cmp -s l.plist l.orig && ok "Lilu disabled is refused, file untouched" || bad "Lilu disabled"

# 6. binary plist is refused, file untouched
plutil -convert binary1 -o b.plist $sample; cp b.plist b.orig
$tool efi-add b.plist > /dev/null 2>&1; [[ $? -ne 0 ]] && cmp -s b.plist b.orig && ok "binary plist is refused" || bad "binary plist"

# 7. not an OpenCore config
print -r -- '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>A</key><string>b</string></dict></plist>' > n.plist
$tool efi-add n.plist > /dev/null 2>&1; [[ $? -ne 0 ]] && ok "non-OpenCore plist is refused" || bad "non-OpenCore plist"

# 8. CoreFoundation fallback when the text edit is not possible (Add written on one line)
perl -0pe 's{(<key>Kernel</key>\s*<dict>\s*<key>Add</key>\s*<array>)(.*?)(</array>)}{my ($a,$b,$c)=($1,$2,$3); $b =~ s/\n\s*//g; "$a$b$c"}se' $sample > f.plist
$tool efi-add f.plist > out5 2>&1 && grep -q "rewritten by CoreFoundation" out5 && grep -q "verified" out5 && ok "fallback to CoreFoundation, verified" || bad "fallback: $(cat out5)"

# 9. new entries load from Sonoma on (MinKernel 23.0.0)
cp $sample m.plist; $tool efi-add m.plist > /dev/null 2>&1
plutil -extract Kernel.Add xml1 -o - m.plist | grep -A10 'VCNEncodeFloor.kext' | grep -q '<string>23.0.0</string>' && ok "new entry has MinKernel 23.0.0" || bad "new entry MinKernel"

# 10. the 1.0.0-1.2.0 entry (MinKernel 25.0.0) is updated in place by text edit, one line changes
cp m.plist o.plist
perl -0pi -e 's{(<string>VCNEncodeFloor.kext</string>.*?<key>MinKernel</key>\s*<string>)23\.0\.0(</string>)}{${1}25.0.0$2}s' o.plist
cp o.plist o.orig
$tool efi-check o.plist | grep -q "old entry with MinKernel 25.0.0" && ok "check reports the old entry" || bad "check old entry: $($tool efi-check o.plist)"
$tool efi-add o.plist > out6 2>&1 && grep -q "updated MinKernel 25.0.0 -> 23.0.0" out6 && grep -q "text edit" out6 && grep -q "verified" out6 && ok "old entry updated by text edit, verified" || bad "old entry update: $(cat out6)"
[[ $(diff o.orig o.plist | grep -c '^>') == 1 && $(diff o.orig o.plist | grep -c '^<') == 1 ]] && ok "old entry update changes one line" || bad "old entry diff: $(diff o.orig o.plist)"
cmp -s o.plist m.plist && ok "updated file equals a fresh add" || bad "updated file differs from a fresh add"
$tool efi-add o.plist 2>&1 | grep -q "nothing to change" && ok "add after update is a no-op" || bad "add after update"

# 11. an old entry that also differs elsewhere (disabled) is still refused, file untouched
cp o.orig x.plist
perl -0pi -e 's{(<string>VCNEncodeFloor.kext</string>.*?<key>Enabled</key>\s*)<true/>}{$1<false/>}s' x.plist; cp x.plist x.orig
# exit status 3 = listed but different; install/encoder.sh tells that apart from other errors
$tool efi-add x.plist > /dev/null 2>&1; rc=$?
(( rc == 3 )) && cmp -s x.plist x.orig && ok "old disabled entry is refused (3), file untouched" || bad "old disabled entry (exit $rc)"

cd /; rm -rf -- "$T"
print "efi tests: $pass passed, $fail failed"
(( fail == 0 ))
