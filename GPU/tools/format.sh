#!/bin/zsh
# format.sh - formats every C, C++ and Objective-C file of the repository with clang-format,
# using .clang-format at the top. The table copied from Mesa keeps its own layout.
#
#   tools/format.sh           rewrites the files in place
#   tools/format.sh --check   changes nothing; exit status 1 when a file is not formatted
emulate -L zsh
setopt err_exit no_unset pipe_fail
cd "${0:A:h:h}"
files=(${(f)"$(git ls-files -co --exclude-standard -- '*.c' '*.h' '*.cpp' '*.hpp' '*.m' |
               grep -v -E '(^|/)ac_vcn_vp9_default\.h$')"})
if [[ ${1:-} == --check ]]; then
  xcrun clang-format --dry-run --Werror $files && print "${#files} files are formatted"
else
  xcrun clang-format -i $files
  print "formatted ${#files} files"
fi
