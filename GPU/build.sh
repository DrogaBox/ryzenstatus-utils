#!/bin/zsh
# build.sh - builds every part of the repository. Installs nothing.
#
#   ./build.sh            the decoders, their loader kext, the GPU sensors and the encoding fix
#   ./build.sh decode     only the decoders
#   ./build.sh loader     only the loader kext (needs tools/bootstrap.sh once)
#   ./build.sh sensors    only the GPU sensors (the kext needs tools/bootstrap.sh once)
#   ./build.sh encode     only the encoding fix (needs tools/bootstrap.sh once)
emulate -L zsh
setopt err_exit no_unset pipe_fail
cd "${0:A:h}"
what=${1:-all}
case $what in
  all|decode|loader|sensors|encode) ;;
  *) print "usage: ./build.sh [decode|loader|sensors|encode]"; exit 2 ;;
esac
if [[ $what == (all|decode) ]]; then
  print "== decoders"
  decode/build.sh
fi
if [[ $what == (all|loader) ]]; then
  print "== loader kext"
  decode/loader/build.sh
fi
if [[ $what == (all|sensors) ]]; then
  print "== GPU sensors"
  sensors/build.sh
fi
if [[ $what == (all|encode) ]]; then
  print "== encoding fix"
  encode/build.sh
fi
