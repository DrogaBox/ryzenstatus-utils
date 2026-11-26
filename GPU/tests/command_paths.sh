#!/bin/zsh
# command_paths.sh - every absolute command path the root installers run exists on this Mac.
#
# 1.90.0 shipped an installer that called /usr/bin/chown. There is no /usr/bin/chown on macOS
# (it is /usr/sbin/chown), so the copy step failed after the password had been typed and every
# install stopped there. Nothing caught it before the disk image went out: the path was a string
# in a shell script and in a Swift file, not a call this machine had ever made.
#
# This test reads the files that run as root - install/*.sh, install/common.zsh, the C helper and
# the installer window - and takes every absolute path they name under the folders macOS keeps
# commands in. Each one has to exist and be executable here. A path built at run time from a
# variable is reported and not checked, because there is nothing to check; a comment that names
# a missing command fails too, which is the right answer for a comment about a command.
#
#   tests/command_paths.sh             the files that run as root, and the installer window
#   tests/command_paths.sh <file>...   only these files, which is how this test is checked itself
#
# Runs on the build Mac and on a CI runner: it reads files and stats paths, nothing else.
# Exit status 0 = every path exists.
emulate -L zsh
setopt no_unset pipe_fail
ROOT=${0:A:h:h}

# The folders macOS keeps commands in. A path anywhere else is data - a folder the installer
# writes to, a log, a device - and not this test's business.
BINS=(/bin /sbin /usr/bin /usr/sbin /usr/libexec)
alt=${(j:|:)BINS}
# The installer creates these folders itself, so naming them is not a mistake.
CREATED=(/usr/local/bin /usr/local/libexec /Library/Video/Plug-Ins)

if (( $# )); then
  files=($@)
else
  files=($ROOT/install/*.sh $ROOT/install/common.zsh $ROOT/install/kextentry.c
         $ROOT/installer/main.swift)
fi

failed=0
checked=0
missing=()

local hits hit line cmd p created
for f in $files; do
  if [[ ! -f $f ]]; then
    print -r -- "  FAIL  no such file: $f"
    failed=1
    continue
  fi
  # "line:path", one per match: /usr/local/bin/gpucontrol is skipped by the boundary, since the
  # installer fills that folder and the file is not a command anyone runs.
  hits=$(grep -noE "(^|[^-A-Za-z0-9_./])($alt)/[A-Za-z0-9_+.-]+" "$f" 2>/dev/null || true)
  for hit in ${(f)hits}; do
    line=${hit%%:*}
    cmd=${hit#*:}
    [[ $cmd == /* ]] || cmd=/${cmd#*/}
    checked=$((checked + 1))
    [[ -x $cmd ]] && continue
    created=0
    for p in $CREATED; do
      [[ $cmd == $p || $cmd == $p/* ]] && created=1
    done
    (( created )) || missing+=("${f:t}:$line: $cmd")
  done
done

if (( ${#missing} )); then
  local m
  for m in $missing; do print -r -- "  FAIL  does not exist: $m"; done
  print -r -- ""
  print -r -- "${#missing} of $checked command paths do not exist on this Mac."
  failed=1
else
  print -r -- "  ok    $checked command paths, all there"
fi

(( ! failed ))
