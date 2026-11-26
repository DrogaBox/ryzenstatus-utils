#!/bin/zsh
# mutants.sh - does sessiontest-vp9 notice when the VP9 session's two new rules
# are broken? Builds it from three damaged copies of decode/vp9/vcnvp9.c and
# requires each to fail:
#   no-guard    the 2x-smaller-reference check removed  (the 4x frame decodes)
#   no-drop     the emptying of the slots of a failed frame removed  (later
#               frames decode on stale pictures)
#   too-eager   the check refuses any reference smaller than the frame  (the 2x
#               frame, which the engine does bit-exactly, is refused)
# Nothing opens the GPU. Needs tests/media (tests/fetch_media.sh).
# Exit status 0 = every damaged build was caught.
emulate -L zsh
setopt no_unset pipe_fail
cd "${0:A:h:h:h}"   # GPU/
B=decode/build/mutants
/bin/rm -rf $B && mkdir -p $B
SRC=decode/vp9/vcnvp9.c
TFLAGS=(-arch x86_64 -O1 -g -Wno-unused-function -Wno-unused-parameter
  -fsanitize=address,undefined -fno-sanitize-recover=undefined)
CLIPS=(tests/media/vp9/vp90-2-12-droppable_1.ivf
  tests/media/vp9-invalid/invalid-vp90-2-09-aq2.webm.ivf.s3984_r01-05_b6-.ivf
  tests/media/vp9/vp90-2-22-svc_1280x720_3.ivf tests/media/vp9/vp90-2-13-mv-with-scaling.ivf)
# old text -> new text, exactly as in vcnvp9.c (perl quotes them, so no regex
# characters to escape)
typeset -A OLD=(
  no-guard   'if (2 * r->width < h->width || 2 * r->height < h->height) {'
  no-drop    'if (p->fh.refresh_frame_flags & (1u << i)) p->ref[i].valid = false;'
  too-eager  'if (2 * r->width < h->width || 2 * r->height < h->height) {'
)
typeset -A NEW=(
  no-guard   'if (0) {'
  no-drop    ';'
  too-eager  'if (r->width < h->width || r->height < h->height) {'
)
bad=0
for m in no-guard no-drop too-eager; do
  OLDTXT=${OLD[$m]} NEWTXT=${NEW[$m]} perl -0pe 's/\Q$ENV{OLDTXT}\E/$ENV{NEWTXT}/' $SRC > "$B/vcnvp9-$m.c"
  if cmp -s $SRC "$B/vcnvp9-$m.c"; then
    print "FAIL $m: the edit did not change vcnvp9.c (the source moved?)"; bad=1; continue
  fi
  xcrun clang "${TFLAGS[@]}" -DTEST_VP9 -Idecode/common -Idecode/vp9 decode/tests/sessiontest.c \
    "$B/vcnvp9-$m.c" decode/vp9/vp9parse.c decode/common/vcnsession.c \
    -framework CoreFoundation -framework CoreVideo -framework IOKit -framework IOSurface \
    -o "$B/sessiontest-$m" 2> "$B/$m.log" \
    || { print "FAIL $m: the damaged copy does not build"; tail -3 "$B/$m.log"; bad=1; continue }
  if "$B/sessiontest-$m" "${CLIPS[@]}" > "$B/$m.txt" 2>&1; then
    print "FAIL $m: sessiontest still passes with this damage"; bad=1
  else
    print "ok   $m: caught ($(grep -c '^FAIL' "$B/$m.txt") failed checks)"
  fi
done
exit $bad
