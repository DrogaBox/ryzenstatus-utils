#!/bin/zsh
# check_clean.sh - refuses anything that must not be in this repository.
#
#   tools/check_clean.sh             checks the files git would track right now
#   tools/check_clean.sh --history   also checks every file of every commit
#
# Run it before each commit; the automated build runs it too. It fails when it finds:
#   - a file type outside the list below, a compiled binary, an archive or a disk image
#   - a file larger than 1 MB
#   - a home folder path, a path into a private work cache, or a link to a file share or forum thread
#   - machine identity fields of an OpenCore config (serial number, board serial, system UUID)
#   - any pattern listed in a private file kept outside the repository, one extended regular
#     expression per line ('#' starts a comment). Default location:
#       ~/.config/drogabox/forbidden-patterns.txt   (override with DROGABOX_FORBIDDEN_PATTERNS)
#     Put there what is specific to you: your serial numbers, names, anything that must not leak.
#
# Exit status 0 = clean.
emulate -L zsh
setopt no_unset pipe_fail
cd "${0:A:h:h}"
SELF=tools/check_clean.sh
MAX_BYTES=1048576
ALLOWED_EXT=(c h cpp hpp m s sh zsh py swift js html plist json md yml yaml conf txt cnf entitlements
             png jpg tiff icns)
ALLOWED_NAMES=(LICENSE VERSION Makefile .gitignore .clang-format .editorconfig .swift-format)
TEXT_RULES=(
  '/Users/[A-Za-z0-9._-]+'           'a home folder path'
  '/home/[A-Za-z0-9._-]+/'           'a home folder path'
  're_cache'                         'a private work cache path'
  'drive\.google\.com'               'a file share link'
  'reddit\.com/r/[^ ]*/comments'     'a forum thread link'
  '<key>(SystemSerialNumber|MLB|SystemUUID)</key>' 'a machine identity field'
)
PRIVATE=${DROGABOX_FORBIDDEN_PATTERNS:-$HOME/.config/drogabox/forbidden-patterns.txt}
private_patterns=()
if [[ -f $PRIVATE ]]; then
  private_patterns=(${(f)"$(grep -v -E '^[[:space:]]*(#|$)' $PRIVATE)"})
fi

problems=0
report() { print -r -- "  $1"; problems=$((problems + 1)); }

# check_blob <label> <path in the tree> <file holding the content>
check_blob() {
  local label=$1 name=$2 file=$3
  local base=${name:t} ext=${name:e}
  if (( ! ${ALLOWED_NAMES[(Ie)$base]} && ! ${ALLOWED_EXT[(Ie)$ext]} )); then
    report "$label: file type not on the allowed list"
  fi
  local size=$(stat -f %z "$file")
  (( size > MAX_BYTES )) && report "$label: $size bytes, larger than 1 MB"
  local magic=$(head -c 4 "$file" | xxd -p)
  case $magic in
    cffaedfe|cefaedfe|feedfacf|feedface|cafebabe|bebafeca) report "$label: compiled binary (Mach-O)" ;;
    504b0304) report "$label: zip archive" ;;
    7f454c46) report "$label: compiled binary (ELF)" ;;
  esac
  case $ext in png|jpg|tiff|icns) return ;; esac
  [[ $name == $SELF ]] && return   # this file names the patterns it looks for
  local i hit
  for (( i = 1; i <= ${#TEXT_RULES}; i += 2 )); do
    hit=$(grep -n -m1 -E -- "${TEXT_RULES[i]}" "$file" | cut -d: -f1)
    [[ -n $hit ]] && report "$label:$hit: ${TEXT_RULES[i+1]}"
  done
  for (( i = 1; i <= ${#private_patterns}; i++ )); do
    hit=$(grep -n -m1 -i -E -- "${private_patterns[i]}" "$file" | cut -d: -f1)
    [[ -n $hit ]] && report "$label:$hit: private pattern number $i"
  done
}

print "== working tree"
files=(${(f)"$(git ls-files -co --exclude-standard)"})
for f in $files; do
  [[ -f $f ]] || continue
  check_blob "$f" "$f" "$f"
done
print "  ${#files} files checked"

if [[ ${1:-} == --history ]]; then
  print "== history"
  tmp=$(mktemp)
  typeset -A seen
  count=0
  for commit in $(git rev-list --all 2>/dev/null); do
    git ls-tree -r "$commit" | while read -r mode type blob name; do
      [[ $type == blob ]] || continue
      [[ -n ${seen[$blob:$name]:-} ]] && continue
      seen[$blob:$name]=1
      git cat-file blob "$blob" > "$tmp"
      check_blob "${commit[1,7]}:$name" "$name" "$tmp"
      count=$((count + 1))
    done
    msg=$(git log -1 --format=%B "$commit")
    for (( i = 1; i <= ${#private_patterns}; i++ )); do
      print -r -- "$msg" | grep -q -i -E -- "${private_patterns[i]}" && report "${commit[1,7]}: commit message matches private pattern number $i"
    done
  done
  rm -f "$tmp"
  print "  $count file versions checked"
fi

if [[ ${#private_patterns} -eq 0 ]]; then
  print "note: no private pattern file at $PRIVATE; only the built-in rules were applied"
fi
if (( problems )); then
  print "NOT CLEAN: $problems problem(s)"
  exit 1
fi
print "clean"
