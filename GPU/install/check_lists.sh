#!/bin/zsh
# check_lists.sh - checks that the list of validated macOS builds agrees with the lists
# compiled into the decoders. It changes nothing.
#
#   install/check_lists.sh
#
# install/validated-builds.json is the list people read and edit: one entry per macOS build,
# with the UUID of that build's video driver (AMDRadeonVADriver2). Each decoder also carries
# its own list of driver UUIDs, kValidatedDrivers, in decode/av1/vcnav1.c,
# decode/vp9/vcnvp9.c and decode/common/vcnlegacy.c (one list for the MPEG-2, VC-1 and MPEG-4
# plug-ins, "legacy" in the JSON). A decoder refuses to work with a driver that is not in its
# list.
#
# For each codec the two must name the same drivers. This script fails when:
#   - a build is marked usable in the JSON (true or "untested-on-gpu") and its driver is
#     missing from the C list: the installer would install, and the decoder would refuse
#   - a driver is in the C list and no build in the JSON marks it usable: the decoder would
#     accept a driver the installer does not know
#   - one driver is marked usable for one build and false for another
#   - an entry of the JSON is malformed (missing field, repeated build, bad UUID or value)
#
# Exit status: 0 the lists agree; 1 they differ; 2 a file is missing or cannot be read.
emulate -L zsh
setopt no_unset
cd "${0:A:h:h}"
JSON=install/validated-builds.json
typeset -A C_FILE=(av1 decode/av1/vcnav1.c vp9 decode/vp9/vcnvp9.c legacy decode/common/vcnlegacy.c)

problems=0
problem() { print -r -- "  DIFFERENCE: $1"; problems=$((problems + 1)); }
die() { print -r -u2 -- "check_lists.sh: $1"; exit 2; }
plx() { /usr/bin/plutil -extract "$1" raw -o - $JSON 2>/dev/null; }

# The quoted strings between "kValidatedDrivers[] = {" and the closing brace, one per line.
c_list() { # file
  awk '
    /kValidatedDrivers\[\] *= *\{/ { on = 1; sub(/.*kValidatedDrivers\[\] *= *\{/, "") }
    on {
      line = $0
      c = index(line, "//"); if (c) line = substr(line, 1, c - 1)
      end = index(line, "}"); if (end) line = substr(line, 1, end - 1)
      while (match(line, /"[^"]*"/)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
      if (end) exit
    }' $1
}

[[ -f $JSON ]] || die "$JSON not found"
count=$(plx validated)
[[ $count == <-> && $count -gt 0 ]] || die "$JSON has no \"validated\" list, or is not valid JSON"

# ---- read the JSON ---------------------------------------------------------------------------
typeset -a builds uuids
typeset -A value   # value[<index>:<codec>]
print "== $JSON: $count builds"
for (( i = 0; i < count; i++ )); do
  build=$(plx validated.$i.build)
  name=$(plx validated.$i.name)
  uuid=$(plx validated.$i.driverUUID)
  encode=$(plx validated.$i.encode)
  where="entry $((i + 1)) (${build:-no build})"
  [[ -n $build ]] || problem "$where has no \"build\""
  [[ -n $name ]] || problem "$where has no \"name\""
  (( ${builds[(Ie)$build]} )) && problem "$where: build $build is listed twice"
  [[ $uuid =~ '^[0-9A-F]{32}$' ]] || problem "$where: driverUUID '$uuid' is not 32 uppercase hexadecimal digits"
  [[ $encode == (true|false) ]] || problem "$where: \"encode\" is '$encode', expected true or false"
  for codec in av1 vp9 legacy; do
    v=$(plx validated.$i.$codec)
    [[ $v == (true|false|untested-on-gpu) ]] ||
      problem "$where: \"$codec\" is '$v', expected true, false or \"untested-on-gpu\""
    value[$((i + 1)):$codec]=$v
  done
  builds+=("$build")
  uuids+=("$uuid")
  print -r -- "  $build  $uuid  av1=${value[$((i + 1)):av1]}  vp9=${value[$((i + 1)):vp9]}  legacy=${value[$((i + 1)):legacy]}  encode=$encode"
done

# ---- compare, one codec at a time ------------------------------------------------------------
for codec in av1 vp9 legacy; do
  file=${C_FILE[$codec]}
  print
  print "== $codec: $JSON against kValidatedDrivers in $file"
  [[ -f $file ]] || die "$file not found"
  clist=(${(f)"$(c_list $file)"})
  (( ${#clist} )) || die "no kValidatedDrivers list found in $file"
  for u in $clist; do
    [[ $u =~ '^[0-9A-F]{32}$' ]] || problem "$file: '$u' is not 32 uppercase hexadecimal digits"
  done

  # every driver named by either side, JSON order first
  all=(${(u)uuids} $clist)
  all=(${(u)all})
  for u in $all; do
    usable=() refused=()
    for (( i = 1; i <= ${#builds}; i++ )); do
      [[ ${uuids[i]} == $u ]] || continue
      if [[ ${value[$i:$codec]} == false ]]; then refused+=("${builds[i]}")
      else usable+=("${builds[i]} ${value[$i:$codec]}")
      fi
    done
    in_c=no
    (( ${clist[(Ie)$u]} )) && in_c=yes
    line="  $u  in the C list: $in_c  JSON:"
    (( ${#usable} )) && line+=" usable for ${(j:, :)usable}"
    (( ${#usable} && ${#refused} )) && line+=";"
    (( ${#refused} )) && line+=" false for ${(j:, :)refused}"
    (( ${#usable} + ${#refused} )) || line+=" not listed"
    print -r -- "$line"
    if (( ${#usable} )) && [[ $in_c == no ]]; then
      problem "$u is usable for $codec in the JSON (${(j:, :)usable}) but is missing from kValidatedDrivers in $file: the decoder would refuse this driver"
    fi
    if (( ! ${#usable} )) && [[ $in_c == yes ]]; then
      if (( ${#refused} )); then
        problem "$u is in kValidatedDrivers in $file, but the JSON marks $codec false for ${(j:, :)refused}"
      else
        problem "$u is in kValidatedDrivers in $file, but no build in the JSON has this driverUUID"
      fi
    fi
    if (( ${#usable} && ${#refused} )); then
      problem "$u is one driver, but the JSON marks $codec usable for ${(j:, :)usable} and false for ${(j:, :)refused}"
    fi
  done
done

print
if (( problems )); then
  print "LISTS DIFFER: $problems difference(s)"
  exit 1
fi
print "lists agree"
