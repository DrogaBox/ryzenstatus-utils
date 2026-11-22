#!/bin/zsh
# install_paths.sh - the rule root installers use for folders they write to. Every part of
# the path must be a real folder owned by root, writable by root only, with no ACL.
#
#   tests/install_paths.sh      exit 0 when the rule accepts and refuses the right folders
emulate -L zsh
setopt no_unset
ROOT=${0:A:h:h}
source $ROOT/install/common.zsh

failed=0
expect() { # text condition
  if eval "$2"; then
    print -r -- "  ok    $1"
  else
    print -r -- "  FAIL  $1"
    failed=1
  fi
}
unsafe() { # folder
  local why
  why=$(gpu_dir_unsafe "$1") || true
  [[ -n $why ]]
}
safe() { # folder
  local why
  why=$(gpu_dir_unsafe "$1") || true
  [[ -z $why ]]
}

tmp=$(mktemp -d -t install_paths) || exit 1
trap '/bin/rm -rf "$tmp"' EXIT
/bin/ln -s /usr/local/bin "$tmp/link"

expect "a folder owned by the user is not safe" 'unsafe "$tmp"'
expect "a link is not a folder" 'unsafe "$tmp/link"'
expect "a world-writable folder is not safe" 'unsafe /private/tmp'
expect "/usr/local/bin is safe on this Mac" 'safe /usr/local/bin'

(( ! failed ))
