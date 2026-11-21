#!/bin/zsh
# fetch_media.sh - downloads the test streams into tests/media/ (not committed) and checks
# each one against the SHA-256 recorded in tests/media-sha256.txt.
#
# They are public conformance streams, a few kilobytes to a megabyte each:
#   av1/          from the Alliance for Open Media test vectors
#   vp9/          from the libvpx test vectors
#   vp9-invalid/  libvpx streams that are damaged on purpose: a parser must refuse or
#                 survive them
# Files already present with the right hash are not downloaded again.
emulate -L zsh
setopt err_exit no_unset pipe_fail
cd "${0:A:h}"
typeset -A BASE=(
  av1          https://storage.googleapis.com/aom-test-data
  vp9          https://storage.googleapis.com/downloads.webmproject.org/test_data/libvpx
  vp9-invalid  https://storage.googleapis.com/downloads.webmproject.org/test_data/libvpx
)
fetched=0
while read -r want file; do
  [[ -z $want || $want == \#* ]] && continue
  set=${file:h} name=${file:t}
  dest=media/$file
  if [[ -f $dest && $(shasum -a 256 $dest | awk '{print $1}') == $want ]]; then continue; fi
  mkdir -p media/$set
  curl -fsSL --retry 3 -o $dest "${BASE[$set]}/$name"
  got=$(shasum -a 256 $dest | awk '{print $1}')
  if [[ $got != $want ]]; then
    print -u2 "$file does not match the recorded SHA-256 (got $got)"
    rm -f $dest
    exit 1
  fi
  fetched=$((fetched + 1))
done < media-sha256.txt
print "test media ready in tests/media ($fetched downloaded)"
