#!/bin/zsh
# amfidetect.sh - the two boot-argument answers the installers decide the loader kext on, on
# made-up Macs: amfi_off (AMFI is out of the way) and amfipass_on (AMFIPass is loaded and
# running). It sources install/common.zsh and stands in for the system with VCNVT_BOOT_ARGS and
# VCNVT_LOADED_KEXTS; nothing is installed, nothing is read from this Mac and nothing runs.
#
#   tests/amfidetect.sh      exit 0 when every case decides as expected
emulate -L zsh
setopt no_unset
ROOT=${0:A:h:h}
source $ROOT/install/common.zsh
failed=0

case_check() { # name expected-exit boot-args loaded-kexts function
  local name=$1 want=$2 boot=$3 kexts=$4 fn=$5 got
  VCNVT_BOOT_ARGS=$boot VCNVT_LOADED_KEXTS=$kexts $fn
  got=$?
  if (( got == want )); then
    print -r -- "  ok    $name"
  else
    print -r -- "  FAIL  $name (expected exit $want, got $got)"
    failed=1
  fi
}

# What kextstat prints for a loaded AMFIPass, and its header alone when nothing is loaded.
KEXTS_PASS='   60    0 0xffffff80041d7000 0xcf000    0xcf000    com.dhinakg.AMFIPass (1.4.1) 7DF1CDFC-7EFE-3D82-A3A2-7DACE8B1D097 <56 9 8 7 6 3 2 1>'
KEXTS_NONE='Index Refs Address            Size       Wired      Name (Version) UUID <Linked Against>'
# The boot arguments of this Mac (26.7.3, 2026-11-26): Lilu and AMFIPass are loaded, and
# AMFIPass is switched off there, so it does nothing and the installer must not count it.
THIS_MAC='-lilubetaall agdpmod=pikera alcid=7 debug=0x100 keepsyms=1 unfairgva=1 revcpu=1 revpatch=cpuname,sbvmm -amdcppcactive -amdpnopchk -FIOff rhv_enable_svm=1 -amfipassoff -btleadv -vcnhevc10 '
PLAIN='debug=0x100 keepsyms=1 '

print -r -- "AMFIPass: a kext that is loaded is only running when Lilu and it were not switched off"
case_check "loaded, and -amfipassoff in the boot arguments: absent" 1 "$THIS_MAC" "$KEXTS_PASS" amfipass_on
case_check "loaded, nothing switching it off: running" 0 "$PLAIN" "$KEXTS_PASS" amfipass_on
case_check "not loaded: absent, whatever the boot arguments say" 1 "$PLAIN" "$KEXTS_NONE" amfipass_on
case_check "loaded, -liluoff: absent (a Lilu plugin without Lilu)" 1 "-liluoff " "$KEXTS_PASS" amfipass_on
case_check "loaded, -amfipassoff=1: absent" 1 "-amfipassoff=1 " "$KEXTS_PASS" amfipass_on
case_check "loaded, amfipassoff=1 without the dash: absent" 1 "amfipassoff=1 " "$KEXTS_PASS" amfipass_on
case_check "loaded, amfipassoff without a value: absent" 1 "amfipassoff " "$KEXTS_PASS" amfipass_on
case_check "loaded, -amfipassoff=0: running (0 leaves it on)" 0 "-amfipassoff=0 " "$KEXTS_PASS" amfipass_on

print -r -- "AMFI: out of the way by amfi_get_out_of_my_way, or by amfi with bit 0x80"
case_check "amfi_get_out_of_my_way=1: off" 0 "amfi_get_out_of_my_way=1 " "$KEXTS_NONE" amfi_off
case_check "amfi_get_out_of_my_way=0x1: off" 0 "amfi_get_out_of_my_way=0x1 " "$KEXTS_NONE" amfi_off
case_check "amfi_get_out_of_my_way without a value: off (it counts as 1)" 0 "amfi_get_out_of_my_way " "$KEXTS_NONE" amfi_off
case_check "amfi_get_out_of_my_way=0: on" 1 "amfi_get_out_of_my_way=0 " "$KEXTS_NONE" amfi_off
case_check "amfi=0x80: off (the form the app knows too)" 0 "amfi=0x80 " "$KEXTS_NONE" amfi_off
case_check "amfi=128: off (the same bit in decimal)" 0 "amfi=128 " "$KEXTS_NONE" amfi_off
case_check "amfi=0xFF: off" 0 "amfi=0xFF " "$KEXTS_NONE" amfi_off
case_check "amfi=0x7F: on (bit 0x80 clear)" 1 "amfi=0x7F " "$KEXTS_NONE" amfi_off
case_check "amfi=1: on" 1 "amfi=1 " "$KEXTS_NONE" amfi_off
case_check "no amfi argument at all: on" 1 "$PLAIN" "$KEXTS_NONE" amfi_off
case_check "this Mac's arguments: AMFI on (it has no amfi argument)" 1 "$THIS_MAC" "$KEXTS_PASS" amfi_off

print -r -- "This Mac as it is: AMFIPass loaded but switched off, AMFI on"
case_check "the installer counts no AMFIPass here" 1 "$THIS_MAC" "$KEXTS_PASS" amfipass_on
case_check "and AMFI is on here" 1 "$THIS_MAC" "$KEXTS_PASS" amfi_off

if (( failed )); then print -r -- "FAILED"; exit 1; fi
print -r -- "all passed"
