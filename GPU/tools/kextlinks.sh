#!/bin/zsh
# kextlinks.sh - checks, without loading anything, that every symbol a kext of this
# repository imports exists: in the running kernel's collections or in Lilu.
#
#   tools/kextlinks.sh <kext> ...
#
# kmutil libraries -p names the kernel library that exports each symbol it finds, and
# says nothing about the ones it does not find (Lilu's among them: Lilu is not in the
# kernel collections, OpenCore injects it). So every undefined symbol of the kext must be
# in kmutil's answer or among the symbols the Lilu used to build exports
# (deps/Lilu.kext, or LILU_KEXT). A kext that fails this would not link at boot: OpenCore
# would skip it, or the kernel would refuse it.
#
# Exit status 0 = every symbol of every kext found.
emulate -L zsh
setopt no_unset pipe_fail
(( $# )) || { print -u2 "usage: tools/kextlinks.sh <kext> ..."; exit 64; }
ROOT=${0:A:h:h}
LILU=${LILU_KEXT:-$ROOT/deps/Lilu.kext}/Contents/MacOS/Lilu
[[ -f $LILU ]] || { print "no Lilu binary at $LILU (run tools/bootstrap.sh)"; exit 1; }
lilu_out=$(nm -gU $LILU) || { print "nm cannot read $LILU"; exit 1; }
lilu_syms=(${(f)"$(print -r -- $lilu_out | awk '{print $3}')"})
typeset -A known
for s in $lilu_syms; do known[$s]=lilu; done
failed=0
for kext in "$@"; do
  exe=$kext/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' $kext/Contents/Info.plist 2>/dev/null)
  [[ -f $exe ]] || { print "$kext: no executable"; failed=1; continue; }
  typeset -A kernel=()
  for s in ${(f)"$(kmutil libraries -p $kext 2>/dev/null | awk '$2 == "in" {print $1}')"}; do kernel[$s]=1; done
  (( ${#kernel} )) || { print "$kext: kmutil found no kernel symbols at all"; failed=1; continue; }
  # read into a variable first: a failing nm must not look like "nothing imported"
  undef=$(nm -u $exe) || { print "$kext: nm cannot read $exe"; failed=1; continue; }
  imported=(${(f)undef})
  missing=()
  for s in $imported; do
    [[ -n ${kernel[$s]:-} || -n ${known[$s]:-} ]] || missing+=($s)
  done
  if (( ${#missing} )); then
    print "$kext: ${#missing} symbols found nowhere:"
    print -l "  "${^missing}
    failed=1
  else
    print "$kext: all ${#imported} imported symbols found"
  fi
done
exit $failed
