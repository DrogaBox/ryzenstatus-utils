#!/bin/zsh
# install_plan.sh - what 'install/install.sh plan' decides, on made-up Macs. Each case writes
# the parts' check answers into a folder and runs the plan with GPU_INSTALL_PLAN_FAKE, which
# install.sh takes with plan only. Nothing is installed; of this Mac only the macOS version is read.
#
#   tests/install_plan.sh      exit 0 when every case decides as expected
emulate -L zsh
setopt no_unset
ROOT=${0:A:h:h}
INSTALL=$ROOT/install/install.sh
WORK=$(mktemp -d -t install_plan) || exit 1
trap '/bin/rm -rf "$WORK"' EXIT
failed=0

# check texts as the parts print them
NOT_LET_IN="  FAIL  macOS accepts the plug-ins: no: nothing on this Mac lets them into Safari (refused). Install the loader first."
OTHER_BUILD="  FAIL  macOS accepts the plug-ins: no: VCNVTLoader is running but was built for other plug-ins. Update the loader first."
NOT_VALIDATED="  FAIL  GPU driver validated: build 99Z999 is not in the validated list"
LOADER_NO_LILU="  FAIL  Lilu on the EFI: no Lilu.kext"

# fake <case> <amfi> <decoders json> <decoders text> <loader json> <loader text> <encoder json> <sensors json>
fake() {
  local d=$WORK/$1
  /bin/mkdir -p "$d"
  print -r -- "$2" > "$d/amfi"
  print -r -- "$3" > "$d/decoders.json"
  print -r -- "$4" > "$d/decoders.txt"
  print -r -- "$5" > "$d/loader.json"
  print -r -- "$6" > "$d/loader.txt"
  print -r -- "$7" > "$d/encoder.json"
  print -r -- "$8" > "$d/sensors.json"
  print -r -- "" > "$d/encoder.txt"
  print -r -- "  FAIL  Navi 21 GPU: none" > "$d/sensors.txt"
}
OUT=""
RC=0
plan() { # case [flags...]
  local c=$1
  shift
  OUT=$(GPU_INSTALL_PLAN_FAKE=$WORK/$c /bin/zsh "$INSTALL" plan "$@" 2>&1)
  RC=$?
}
expect() { # name condition-result
  if (( $2 )); then print -r -- "  ok    $1"; else print -r -- "  FAIL  $1"; print -r -- "$OUT" | sed 's/^/        | /'; failed=1; fi
}
has() { [[ $OUT == *"$1"* ]] && print 1 || print 0; }
lacks() { [[ $OUT != *"$1"* ]] && print 1 || print 0; }
# the line of the first text before the line of the second
before() {
  local -a lines=(${(f)OUT})
  local a=${lines[(i)*$1*]} b=${lines[(i)*$2*]}
  (( a <= ${#lines} && b <= ${#lines} && a < b )) && print 1 || print 0
}

DEC_WAIT='{"canInstall":false,"installed":"none"}'
DEC_WAIT_OLD='{"canInstall":false,"installed":"outdated"}'
DEC_WAIT_CURRENT='{"canInstall":false,"installed":"current"}'
DEC_READY='{"canInstall":true,"installed":"none"}'
DEC_CURRENT='{"canInstall":true,"installed":"current"}'
LDR_READY='{"canInstall":true,"result":"ready. Loader kext > Install puts it on your EFI"}'
LDR_BLOCKED='{"canInstall":false,"result":"blocked. Fix the checks marked FAIL first."}'
LDR_WORKING='{"canInstall":true,"result":"working: VCNVTLoader is running and lists these plug-ins"}'
ENC_NONE='{"canInstall":true,"installed":"none","version":"1.2.4","kext":"not loaded"}'
SNS_TOOLS_ONLY='{"canInstall":true,"version":"0.8.0","running":"loaded 0.8.0, active, 10 readings since boot","tools":"missing","toolsOnly":true,"result":"working: GPUSensors is active and has readings."}'
SNS_TOOLS_OLD='{"canInstall":true,"version":"0.8.0","running":"loaded 0.8.0, active, 10 readings since boot","tools":"outdated","toolsOnly":true,"result":"working: GPUSensors is active and has readings."}'
SNS_CURRENT='{"canInstall":true,"version":"0.8.0","running":"loaded 0.8.0, active, 10 readings since boot","tools":"current","toolsOnly":false,"result":"working: GPUSensors is active and has readings."}'
SNS_TOOLS_BLOCKED='{"canInstall":true,"version":"0.8.0","running":"loaded 0.8.0, active, 10 readings since boot","tools":"blocked","toolsOnly":false,"result":"working: GPUSensors is active and has readings."}'
SNS_OLD_KEXT='{"canInstall":true,"version":"0.8.0","running":"loaded 0.7.2, no status, 0 readings since boot","tools":"missing","toolsOnly":false,"result":"GPUSensors 0.7.2 is loaded"}'

print -r -- "a fresh Mac: the decoders wait only for the loader kext, which can go in"
fake fresh on "$DEC_WAIT" "$NOT_LET_IN" "$LDR_READY" "" "$ENC_NONE" "$SNS_CURRENT"
plan fresh
expect "the plan goes ahead (exit 0)" $(( RC == 0 ))
expect "the loader kext is a step" $(has "put VCNVTLoader.kext on the EFI")
expect "the decoders are a step, right after the loader" $(has "install the decoder plug-ins right after the loader kext")
expect "the loader comes first" $(before "put VCNVTLoader.kext" "install the decoder plug-ins")
expect "nothing is blocked" $(lacks "Nothing was installed")

print -r -- "a Mac whose loader kext lists the plug-ins of another build"
fake update on "$DEC_WAIT_OLD" "$OTHER_BUILD" "$LDR_READY" "" "$ENC_NONE" "$SNS_CURRENT"
plan update
expect "the plan goes ahead (exit 0)" $(( RC == 0 ))
expect "loader, then decoders" $(before "put VCNVTLoader.kext" "install the decoder plug-ins right after the loader kext")

print -r -- "the decoders wait for the loader and something else"
fake twofails on "$DEC_WAIT" "$NOT_LET_IN"$'\n'"$NOT_VALIDATED" "$LDR_READY" "" "$ENC_NONE" "$SNS_CURRENT"
plan twofails
expect "nothing is installed (exit 2)" $(( RC == 2 ))
expect "the decoders are blocked with both reasons" $(( $(has "decoders: this Mac is not ready for them") && $(has "not in the validated list") ))
expect "no plan is printed" $(lacks "Plan:")

print -r -- "the decoders wait for the loader, and the loader cannot go in"
fake noloader on "$DEC_WAIT" "$NOT_LET_IN" "$LDR_BLOCKED" "$LOADER_NO_LILU" "$ENC_NONE" "$SNS_CURRENT"
plan noloader
expect "nothing is installed (exit 2)" $(( RC == 2 ))
expect "both are blocked" $(( $(has "decoders: this Mac is not ready for them") && $(has "loader: it is needed here") ))

print -r -- "the decoders wait for the loader and are already these"
fake deccurrent on "$DEC_WAIT_CURRENT" "$OTHER_BUILD" "$LDR_READY" "" "$ENC_NONE" "$SNS_CURRENT"
plan deccurrent
expect "the plan goes ahead (exit 0)" $(( RC == 0 ))
expect "only the loader is a step" $(( $(has "put VCNVTLoader.kext") && $(lacks "install the decoder plug-ins") ))
expect "the decoders are skipped, and why" $(has "skip decoders: the plug-ins installed are already these; the loader kext lets them in after the reboot")

print -r -- "AMFIPass runs: no loader kext"
fake amfipass pass "$DEC_READY" "" "$LDR_READY" "" "$ENC_NONE" "$SNS_CURRENT"
plan amfipass
expect "the plan goes ahead (exit 0)" $(( RC == 0 ))
expect "the decoders are a plain step" $(has "install the decoder plug-ins (needs a reboot)")
expect "the loader is skipped" $(has "skip loader kext: not needed, AMFIPass is running")

print -r -- "the sensors kext is current, gpucontrol and gpusensors are missing"
fake toolsonly on "$DEC_CURRENT" "" "$LDR_WORKING" "" "$ENC_NONE" "$SNS_TOOLS_ONLY"
plan toolsonly --with-sensors
expect "the plan goes ahead (exit 0)" $(( RC == 0 ))
expect "the commands are the only step" $(( $(has "copy gpucontrol and gpusensors to /usr/local/bin") && $(lacks "put GPUSensors.kext") && $(lacks "Nothing to install") ))
expect "the kext is skipped" $(has "skip sensors: already installed and running, the same version")
plan toolsonly
expect "without --with-sensors the commands are not a step" $(( $(lacks "copy gpucontrol") && $(has "Nothing to install") ))

print -r -- "the sensors kext is current, gpucontrol or gpusensors differs"
fake toolsold on "$DEC_CURRENT" "" "$LDR_WORKING" "" "$ENC_NONE" "$SNS_TOOLS_OLD"
plan toolsold --with-sensors
expect "the commands are a step" $(has "copy gpucontrol and gpusensors to /usr/local/bin")

print -r -- "everything current"
fake allcurrent on "$DEC_CURRENT" "" "$LDR_WORKING" "" "$ENC_NONE" "$SNS_CURRENT"
plan allcurrent --with-sensors
expect "nothing to install (exit 0)" $(( RC == 0 && $(has "Nothing to install") ))

print -r -- "something else is where gpucontrol goes"
fake toolsblocked on "$DEC_CURRENT" "" "$LDR_WORKING" "" "$ENC_NONE" "$SNS_TOOLS_BLOCKED"
plan toolsblocked --with-sensors
expect "nothing to install, nothing blocked (exit 0)" $(( RC == 0 && $(has "Nothing to install") ))
expect "the commands are left alone, and said so" $(has "skip gpucontrol and gpusensors: something else is in their place")

print -r -- "an older sensors kext: the kext install copies the commands"
fake oldkext on "$DEC_CURRENT" "" "$LDR_WORKING" "" "$ENC_NONE" "$SNS_OLD_KEXT"
plan oldkext --with-sensors
expect "the kext is a step" $(has "put GPUSensors.kext on the EFI")
expect "the commands are not a step of their own" $(lacks "copy gpucontrol and gpusensors to /usr/local/bin:")

print -r -- "the stand-in is for plan only"
GPU_INSTALL_PLAN_FAKE=$WORK/fresh /bin/zsh "$INSTALL" > /dev/null 2>&1
rc=$?
OUT="exit $rc"
expect "install refuses it (exit 64)" $(( rc == 64 ))

(( failed == 0 ))
