#!/bin/zsh
# run.sh - builds everything and runs every test that does not need the GPU.
#
#   tests/run.sh            all of it
#   tests/run.sh --quick    fewer damaged copies per stream (about ten times faster)
#
# What it checks:
#   1. the repository is clean (tools/check_clean.sh) and formatted (tools/format.sh --check);
#      what install/install.sh plan decides on made-up Macs (tests/install_plan.sh)
#   2. the decoders build, twice, to the same bytes
#   3. the AV1 and VP9 parsers read the public test streams exactly as recorded in
#      tests/expected-digests.txt
#   4. a refused AV1 sample or VP9 header leaves the parser consistent (av1state, vp9state);
#      the colour of the pictures: the parsers' colour fields and AV1's HDR metadata OBUs,
#      and the attachments set from them on a real pixel buffer (colortest);
#      the plug-ins' VideoToolbox side, with a stand-in decoder (plugintest);
#      the MPEG-2, VC-1 and MPEG-4 parsers and the messages built from them (legacyparse);
#      what the MPEG-2, VC-1 and MPEG-4 codec layers send for a stream, on a stand-in session
#      (layertest);
#      which decoder VideoToolbox gives an MPEG-4 stream, ours (on a stand-in session)
#      next to Apple's AppleMP4V (legacypick);
#      the parsers survive damaged streams: libvpx's invalid files and thousands of copies
#      damaged at random, under the address and undefined-behaviour sanitizers
#   5. the rule that picks AMD's accelerator; the wait for a decode command gives up on a
#      command that never finishes (waittest, with a made-up driver); two plug-ins of one
#      process: a session from before a sleep is seen by the other, which opens anyway
#      (staletest)
#   5b. the loader kext: its decisions, that it builds twice to the same bytes and lists the
#      plug-ins just built, that install/loader.sh puts it on an EFI and takes it off again
#      (on made-up EFI folders), and that it accepts the AMFI functions of this Mac
#   5c. the GPU sensors: they build twice to the same bytes, their decisions, and that the
#      kext accepts the PMLog function of this Mac's driver
#   5d. the JPEG decoder kext: it builds twice to the same bytes, its door and the rule that
#      powers the block only while decoding (jpeg/tests/run.sh, with the KDK and Mesa parts
#      when they are there), and that this Mac's driver starts each function it uses the way
#      its table says
#   6. every symbol the kexts import exists in this kernel or in Lilu (tools/kextlinks.sh);
#      the encoding fix builds and passes its own tests (the wide patch run on the CPU for
#      each validated build, OpenCore config editing)
#
# Nothing here opens the GPU, loads a kext or changes the system. Tests that do are listed
# in docs/testing.md and are run by hand on a booted machine.
# Exit status 0 = everything passed.
emulate -L zsh
setopt no_unset pipe_fail
ROOT=${0:A:h:h}
cd $ROOT
rounds=300
[[ ${1:-} == --quick ]] && rounds=30
failed=()
step() { print; print "== $1"; }
check() {  # check <name> <command...>
  local name=$1; shift
  if "$@"; then print "PASS $name"; else print "FAIL $name"; failed+=($name); fi
}
skipped=()
skip() {  # skip <what> <why>: a check that cannot run here; listed again at the end
  print "SKIP $1: $2"
  skipped+=($1)
}
# no_local_paths <file...>: fails when a file holds a path of this machine, or cannot be read.
# The match is made on text: a grep -q that stops reading early would make the pipe fail
# under pipe_fail, and "strings | grep || true" would pass when strings fails.
no_local_paths() {
  local out
  out=$(strings -a "$@") || { print "strings cannot read $*"; return 1; }
  [[ $out != *(/Users/|/var/folders/)* ]] || { print "the build holds a path of this machine"; return 1; }
}

step "repository"
check "clean" tools/check_clean.sh
if xcrun -f clang-format >/dev/null 2>&1; then
  check "formatted" tools/format.sh --check
else
  skip "formatted" "clang-format is not installed"
fi

syntax() {
  local f
  for f in build.sh {decode,encode,sensors,jpeg}/build.sh decode/loader/build.sh decode/tests/gpu/build.sh tools/*.sh tests/*.sh \
           install/*.sh encode/scripts/*.sh jpeg/tests/run.sh; do
    zsh -n $f || { print "syntax error in $f"; return 1; }
  done
}
check "every shell script parses" syntax
check "the validated builds list agrees with the decoders' driver lists" install/check_lists.sh
check "install.sh plan decides as expected on made-up Macs" tests/install_plan.sh

step "decoders: build"
build_twice() {
  decode/build.sh > /dev/null || return 1
  # declared apart from the assignment: "local x=$(...)" has the status of local, always 0
  local first second
  first=$(cat decode/build/*.bundle/Contents/MacOS/*VCNDecoder | shasum -a 256) || return 1
  decode/build.sh tests || return 1
  second=$(cat decode/build/*.bundle/Contents/MacOS/*VCNDecoder | shasum -a 256) || return 1
  [[ $first == $second ]] || { print "two builds differ"; return 1; }
  no_local_paths decode/build/*.bundle/Contents/MacOS/*VCNDecoder || return 1
}
check "decoders build twice to the same bytes, with no local path inside" build_twice

check "the GPU test programs compile (none is run)" decode/tests/gpu/build.sh
probe_signed() {
  local d=$(codesign -dvv decode/build/lvprobe 2>&1)
  [[ $d == *library-validation* ]] || { print "lvprobe is not signed with the library-validation flag"; return 1; }
}
check "the installer's probe is built with library validation" probe_signed

step "decoders: parsers"
check "test media" tests/fetch_media.sh
PD=decode/build/tests/parsedigest
digests() {
  $PD tests/media/av1/*.ivf tests/media/vp9/*.ivf > decode/build/tests/digests.txt || return 1
  diff tests/expected-digests.txt decode/build/tests/digests.txt
}
check "valid streams are read as recorded" digests
invalid() { $PD tests/media/vp9-invalid/*.ivf > decode/build/tests/invalid.txt; }
check "libvpx's invalid streams are survived" invalid
av1state() { decode/build/tests/av1state tests/media/av1/av1-1-b8-01-size-16x16.ivf > decode/build/tests/av1state.txt ||
  { cat decode/build/tests/av1state.txt; return 1; }; }
check "a refused AV1 sample leaves the parser consistent" av1state
vp9state() { decode/build/tests/vp9state tests/media/vp9/vp90-2-05-resize.ivf > decode/build/tests/vp9state.txt ||
  { cat decode/build/tests/vp9state.txt; return 1; }; }
check "a refused VP9 header leaves the parser consistent" vp9state
colors() { decode/build/tests/colortest > decode/build/tests/colortest.txt ||
  { cat decode/build/tests/colortest.txt; return 1; }; }
check "the pictures' colour: stream and container colour, HDR metadata, attachments" colors
check "5000 damaged AV1 and VP9 headers each are survived" decode/build/tests/parsefuzz 5000
plugins() {
  local c
  for c in av1 vp9 mpeg2 vc1 mpeg4; do
    decode/build/tests/plugintest-$c > decode/build/tests/plugintest-$c.txt ||
      { cat decode/build/tests/plugintest-$c.txt; return 1; }
  done
}
check "the plug-ins' VideoToolbox side, with a stand-in decoder" plugins
legacyparse() { decode/build/tests/legacyparse > decode/build/tests/legacyparse.txt ||
  { cat decode/build/tests/legacyparse.txt; return 1; }; }
check "the MPEG-2, VC-1 and MPEG-4 parsers and messages, with made-up and damaged streams" legacyparse
layers() { decode/build/tests/layertest > decode/build/tests/layertest.txt ||
  { cat decode/build/tests/layertest.txt; return 1; }; }
check "the MPEG-2, VC-1 and MPEG-4 codec layers send the firmware only what it decodes" layers
pick() { decode/build/tests/legacypick > decode/build/tests/legacypick.txt ||
  { cat decode/build/tests/legacypick.txt; return 1; }; }
check "VideoToolbox gives our MPEG-4 plug-in the streams it takes, and Apple's the rest" pick
jpeg_plugin() {
  decode/build/tests/plugintest-jpeg > decode/build/tests/plugintest-jpeg.txt ||
    { cat decode/build/tests/plugintest-jpeg.txt; return 1; }
  decode/build/tests/jpegtest > decode/build/tests/jpegtest.txt || { grep -v ^PASS decode/build/tests/jpegtest.txt; return 1; }
}
check "the JPEG plug-in: VideoToolbox side, preparer, session against a made-up kext" jpeg_plugin
damaged() {$PD --mutate $rounds tests/media/av1/*.ivf tests/media/vp9/*.ivf > decode/build/tests/damaged.txt; }
check "$rounds damaged copies of each stream are survived" damaged

step "decoders: accelerator rule"
check "only AMD's accelerator is taken" decode/build/tests/acceltest
check "a decode command that never finishes times out" decode/build/tests/waittest
stale() { decode/build/tests/staletest decode/build/tests/libstale-{a,b}.dylib > decode/build/tests/staletest.txt ||
  { cat decode/build/tests/staletest.txt; return 1; }; }
check "two plug-ins of one process: a session from before a sleep is seen, new ones open anyway" stale
sessions() {
  decode/build/tests/sessiontest-av1 tests/media/av1/av1-1-b8-01-size-16x16.ivf tests/media/av1/av1-1-b8-05-mv.ivf > decode/build/tests/sessiontest-av1.txt &&
    decode/build/tests/sessiontest-vp9 tests/media/vp9/vp90-2-12-droppable_1.ivf \
      tests/media/vp9-invalid/invalid-vp90-2-09-aq2.webm.ivf.s3984_r01-05_b6-.ivf > decode/build/tests/sessiontest-vp9.txt ||
    { cat decode/build/tests/sessiontest-av1.txt decode/build/tests/sessiontest-vp9.txt 2>/dev/null | grep -v ^PASS; return 1; }
}
check "decoder sessions release the driver once, also after failures and a stuck GPU; a sleep: decode on, rebuild at a key frame; hidden frames keep their picture (made-up driver)" sessions

step "decoders: loader kext"
check "the kext's decisions" decode/build/tests/loadertest
if [[ -f deps/Lilu.kext/Contents/Resources/Library/plugin_start.cpp || -n ${LILU_KEXT:-} ]]; then
  loader_twice() {
    local k=decode/build/VCNVTLoader.kext/Contents/MacOS/VCNVTLoader b h
    decode/loader/build.sh > /dev/null || return 1
    local first second
    first=$(shasum -a 256 < $k) || return 1
    decode/loader/build.sh > /dev/null || return 1
    second=$(shasum -a 256 < $k) || return 1
    [[ $first == $second ]] || { print "two builds differ"; return 1; }
    no_local_paths $k || return 1
    for b in decode/build/*VCNDecoder.bundle; do
      h=$(codesign -dvvv $b 2>&1 | sed -n 's/^CDHash=//p')
      /usr/bin/python3 -I -c 'import sys; sys.exit(0 if bytes.fromhex(sys.argv[2]) in open(sys.argv[1], "rb").read() else 1)' $k $h ||
        { print "the kext does not list ${b:t}"; return 1; }
    done
  }
  check "the kext builds twice to the same bytes and lists the plug-ins just built" loader_twice
  OC_SAMPLE=${OC_SAMPLE:-deps/OpenCore/Sample.plist}
  if [[ -f $OC_SAMPLE ]]; then
    loader_install() {
      # the test installs the sensors kext too; the sensors step below builds it again
      [[ -d sensors/build/GPUSensors.kext ]] || sensors/build.sh > /dev/null || return 1
      tests/loader_install.sh $OC_SAMPLE > decode/build/tests/loader_install.txt ||
        { grep FAIL decode/build/tests/loader_install.txt; return 1; }
    }
    check "install/loader.sh and install/sensors.sh install, replace, refuse and uninstall on made-up EFI folders" loader_install
  else
    skip "loader install tests" "no OpenCore Sample.plist at $OC_SAMPLE (run tools/bootstrap.sh)"
  fi
else
  print "SKIP: no kext SDK (run tools/bootstrap.sh)"
  failed+=("loader kext not built")
fi
KC=/System/Library/KernelCollections/BootKernelExtensions.kc
if [[ -f $KC ]]; then
  this_amfi() {
    /usr/bin/python3 -I tools/driver/amficheck.py "this_mac=$KC" > decode/build/tests/amfi-entries.txt || return 1
    decode/build/tests/loadertest decode/build/tests/amfi-entries.txt > decode/build/tests/loadertest.txt ||
      { grep FAIL decode/build/tests/loadertest.txt; return 1; }
  }
  check "the kext accepts the AMFI functions of this Mac" this_amfi
else
  skip "the loader kext against this Mac's AMFI" "no boot kernel collection on this machine"
fi

step "GPU sensors"
sensors_twice() {
  local k=sensors/build/GPUSensors.kext/Contents/MacOS/GPUSensors
  sensors/build.sh tests > /dev/null || return 1
  local first second
  first=$(shasum -a 256 < $k) || return 1
  sensors/build.sh tests > /dev/null || return 1
  second=$(shasum -a 256 < $k) || return 1
  [[ $first == $second ]] || { print "two builds differ"; return 1; }
  no_local_paths $k sensors/build/gpusensors sensors/build/gpucontrol || return 1
}
check "the sensors kext and commands build twice to the same bytes, with no local path inside" sensors_twice
check "the sensors' decisions" sensors/build/tests/pmlogtest
check "the GPU control's decisions" sensors/build/tests/controltest
SKC=/System/Library/KernelCollections/SystemKernelExtensions.kc
if [[ -f $SKC ]]; then
  this_pmlog() {
    local k out=decode/build/tests/pmlog-entries.txt
    : > $out
    # the library this Mac loads must be there; the other one is checked when present
    /usr/bin/python3 -I tools/driver/kcfunc.py com.apple.kext.AMDRadeonX6000HWLibs \
      _PEM_CWDDEPM_QueryPMLogData "this_mac=$SKC" >> $out || return 1
    /usr/bin/python3 -I tools/driver/kcfunc.py com.apple.kext.AMDRadeonX6800HWLibs \
      _PEM_CWDDEPM_QueryPMLogData "this_mac=$SKC" >> $out 2>/dev/null
    sensors/build/tests/pmlogtest $out > decode/build/tests/pmlogtest.txt ||
      { grep FAIL decode/build/tests/pmlogtest.txt; return 1; }
  }
  check "the sensors kext accepts the PMLog function of this Mac" this_pmlog
  this_control() {
    /usr/bin/python3 -I tools/driver/ctlentries.py $SKC > decode/build/tests/ctlentries.txt ||
      { grep FAIL decode/build/tests/ctlentries.txt; return 1; }
  }
  check "the GPU control's functions start as it expects in this Mac's driver" this_control
else
  skip "the sensors kext against this Mac's driver" "no system kernel collection on this machine"
fi
step "JPEG decoder kext"
if [[ -f deps/Lilu.kext/Contents/Resources/Library/plugin_start.cpp || -n ${LILU_KEXT:-} ]]; then
  jpeg_twice() {
    local k=jpeg/build/VCNJpeg.kext/Contents/MacOS/VCNJpeg
    jpeg/build.sh tests > /dev/null || return 1
    local first second
    first=$(shasum -a 256 < $k) || return 1
    jpeg/build.sh tests > /dev/null || return 1
    second=$(shasum -a 256 < $k) || return 1
    [[ $first == $second ]] || { print "two builds differ"; return 1; }
    no_local_paths $k || return 1
  }
  check "the JPEG kext builds twice to the same bytes, with no local path inside" jpeg_twice
  jpeg_host() { jpeg/tests/run.sh > decode/build/tests/jpeg-host.txt || { cat decode/build/tests/jpeg-host.txt; return 1; }; }
  check "the JPEG kext's commands, door and power rule (jpeg/tests/run.sh)" jpeg_host
  grep '^skip ' decode/build/tests/jpeg-host.txt 2>/dev/null | while read -r _ why; do skip "part of jpeg/tests/run.sh" "$why"; done
  if [[ -f $SKC && $(/usr/bin/sw_vers -buildVersion) == 25G342 ]]; then
    # every function of jpeg/kext/hwlibs_expect.hpp starts in this Mac's driver as the table says
    jpeg_this_mac() {
      /usr/bin/python3 -I - $SKC <<'PY'
import re, subprocess, sys
hpp = open("jpeg/kext/hwlibs_expect.hpp").read()
want = {}
for block, kext in ((hpp.split("kX6000Uuid")[0], "com.apple.kext.AMDRadeonX6000HWLibs"),
                    (hpp.split("kX6000Uuid")[1], "com.apple.kext.AMDRadeonX6000")):
    for sym, head in re.findall(r'\{"(\w+)",\s+0x[0-9a-f]+,\s+\{([^}]*)\}\}', block):
        want.setdefault(kext, {})[sym] = bytes(int(x, 16) for x in head.split(","))
bad = 0
for kext, syms in want.items():
    out = subprocess.run([sys.executable, "-I", "tools/driver/kcfunc.py", kext, ",".join(syms), "this_mac=" + sys.argv[1]],
                         capture_output=True, text=True).stdout
    got = {f[1]: bytes.fromhex(f[0])[:16] for f in (l.split() for l in out.splitlines()) if len(f) >= 2}
    for sym, head in syms.items():
        if got.get(sym) != head:
            print("differs or missing in this Mac's driver: %s" % sym)
            bad += 1
print("%d functions checked" % sum(len(s) for s in want.values()))
sys.exit(1 if bad else 0)
PY
    }
    check "the JPEG kext's functions start in this Mac's driver as its table says" jpeg_this_mac
  else
    skip "the JPEG kext against this Mac's driver" "not macOS 25G342, or no system kernel collection"
  fi
else
  print "SKIP: no kext SDK (run tools/bootstrap.sh)"
  failed+=("JPEG kext not built")
fi

kext_links() {
  tools/kextlinks.sh sensors/build/GPUSensors.kext decode/build/VCNVTLoader.kext \
    encode/build/VCNEncodeFloor.kext jpeg/build/VCNJpeg.kext > decode/build/tests/kextlinks.txt ||
    { cat decode/build/tests/kextlinks.txt; return 1; }
}
encode_paths() {
  no_local_paths encode/build/vcnencodefix encode/build/vtenc \
    encode/build/VCNEncodeFloor.kext/Contents/MacOS/VCNEncodeFloor
}

step "encoding fix"
if [[ -f deps/Lilu.kext/Contents/Resources/Library/plugin_start.cpp || -n ${LILU_KEXT:-} ]]; then
  check "builds and passes its tests" encode/build.sh
  check "holds no path of this machine" encode_paths
  check "every symbol the four kexts import exists in this kernel or in Lilu" kext_links
else
  print "SKIP: no kext SDK (run tools/bootstrap.sh)"
  failed+=("encoding fix not built")
fi

print
if (( ${#failed} )); then
  print "FAILED: ${(j:, :)failed}"
  exit 1
fi
if (( ${#skipped} )); then
  print "all tests that could run passed; skipped here: ${(j:, :)skipped}"
else
  print "all tests passed"
fi
