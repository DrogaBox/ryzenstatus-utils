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
# decoders.sh's install record of this boot: these plug-ins are in the next boot's snapshot
# (an older build, or none, runs now), or ours were removed from it (they still run now)
DEC_PENDING='{"canInstall":true,"installed":"outdated","pending":"install"}'
DEC_PENDING_WAIT='{"canInstall":false,"installed":"none","pending":"install"}'
DEC_REMOVED='{"canInstall":true,"installed":"current","pending":"remove"}'
DEC_REMOVED_WAIT='{"canInstall":false,"installed":"current","pending":"remove"}'
DEC_NO_PENDING='{"canInstall":true,"installed":"outdated","pending":"none"}'
LDR_READY='{"canInstall":true,"result":"ready. Loader kext > Install puts it on your EFI"}'
LDR_BLOCKED='{"canInstall":false,"result":"blocked. Fix the checks marked FAIL first."}'
LDR_WORKING='{"canInstall":true,"result":"working: VCNVTLoader is running and lists these plug-ins"}'
ENC_NONE='{"canInstall":true,"installed":"none","version":"1.2.4","kext":"not loaded"}'
SNS_TOOLS_ONLY='{"canInstall":true,"version":"0.8.0","running":"loaded 0.8.0, active, 10 readings since boot","tools":"missing","toolsOnly":true,"result":"working: GPUSensors is active and has readings."}'
SNS_TOOLS_OLD='{"canInstall":true,"version":"0.8.0","running":"loaded 0.8.0, active, 10 readings since boot","tools":"outdated","toolsOnly":true,"result":"working: GPUSensors is active and has readings."}'
SNS_CURRENT='{"canInstall":true,"version":"0.8.0","running":"loaded 0.8.0, active, 10 readings since boot","tools":"current","toolsOnly":false,"result":"working: GPUSensors is active and has readings."}'
SNS_TOOLS_BLOCKED='{"canInstall":true,"version":"0.8.0","running":"loaded 0.8.0, active, 10 readings since boot","tools":"blocked","toolsOnly":false,"result":"working: GPUSensors is active and has readings."}'
SNS_OLD_KEXT='{"canInstall":true,"version":"0.8.0","running":"loaded 0.7.2, no status, 0 readings since boot","tools":"missing","toolsOnly":false,"result":"GPUSensors 0.7.2 is loaded"}'
SNS_PENDING='{"canInstall":true,"version":"0.8.0","running":"loaded 0.7.2, no status, 0 readings since boot","tools":"missing","toolsOnly":false,"pendingReboot":true,"result":"installed on disk1s3: GPUSensors 0.8.0 loads at the next boot"}'
LDR_PENDING='{"canInstall":true,"pendingReboot":true,"result":"installed on disk1s3, not running yet. Reboot from that EFI to start it."}'
# the encoding fix installed, running and the package's version, with the kext on the EFI
# the package's build, another build, or the service stopped
enc_json() { # service efi-entry efi-kext
  print -r -- '{"canInstall":true,"version":"1.2.4","installed":"current","service":"'$1'","kext":"loaded 1.2.4, active: encode","efis":[{"id":"disk1s3","name":"OPENCORE","media":"x","mounted":true,"mountPoint":"/Volumes/OPENCORE","openCore":"yes","entry":"'$2'","kext":"'$3'"}],"checks":[]}'
}
ENC_CURRENT=$(enc_json running yes current)
ENC_EFI_OTHER=$(enc_json running yes outdated)
ENC_EFI_OLD_ENTRY=$(enc_json running old current)
ENC_STOPPED=$(enc_json stopped yes current)

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

print -r -- "this sensors kext is on the EFI, an older one runs until the reboot"
fake pendingkext on "$DEC_CURRENT" "" "$LDR_WORKING" "" "$ENC_NONE" "$SNS_PENDING"
plan pendingkext --with-sensors
expect "nothing to install (exit 0)" $(( RC == 0 && $(has "Nothing to install") && $(lacks "put GPUSensors.kext") ))
expect "the kext is skipped, and said why" $(has "skip sensors: this version is on the EFI already; it loads at the next boot")

print -r -- "the loader kext is on the EFI, not running yet"
fake pendingloader on "$DEC_CURRENT" "" "$LDR_PENDING" "" "$ENC_NONE" "$SNS_CURRENT"
plan pendingloader
expect "nothing to install (exit 0)" $(( RC == 0 && $(has "Nothing to install") && $(lacks "put VCNVTLoader.kext") ))
expect "the loader is skipped, and said why" $(has "skip loader kext: the right one is on the EFI already; it starts at the next boot")

print -r -- "the encoding fix: skipped only when check would call it installed and working"
fake enccurrent on "$DEC_CURRENT" "" "$LDR_WORKING" "" "$ENC_CURRENT" "$SNS_CURRENT"
plan enccurrent --with-encoder
expect "everything current: nothing to install" $(( RC == 0 && $(has "skip encoder: already installed and running") && $(has "Nothing to install") ))
fake encother on "$DEC_CURRENT" "" "$LDR_WORKING" "" "$ENC_EFI_OTHER" "$SNS_CURRENT"
plan encother --with-encoder
expect "another build of the kext on the EFI, same version: the encoding fix is a step" $(( RC == 0 && $(has "install the encoding fix") ))
fake encentry on "$DEC_CURRENT" "" "$LDR_WORKING" "" "$ENC_EFI_OLD_ENTRY" "$SNS_CURRENT"
plan encentry --with-encoder
expect "an old config.plist entry: the encoding fix is a step" $(has "install the encoding fix")
fake encstopped on "$DEC_CURRENT" "" "$LDR_WORKING" "" "$ENC_STOPPED" "$SNS_CURRENT"
plan encstopped --with-encoder
expect "the service stopped: the encoding fix is a step" $(has "install the encoding fix")

print -r -- "the decoders were installed earlier in this boot; the old ones run until the reboot"
fake decpending on "$DEC_PENDING" "" "$LDR_WORKING" "" "$ENC_NONE" "$SNS_CURRENT"
plan decpending
expect "nothing to install (exit 0)" $(( RC == 0 && $(has "Nothing to install") ))
expect "the decoders are skipped, and said why" $(has "skip decoders: these plug-ins are in the boot snapshot already; they load at the next boot")
expect "no update is offered for them" $(lacks "install the decoder plug-ins")
fake decpendingwait on "$DEC_PENDING_WAIT" "$NOT_LET_IN" "$LDR_READY" "" "$ENC_NONE" "$SNS_CURRENT"
plan decpendingwait
expect "their checks wait for the loader: still skipped, not blocked (exit 0)" $(( RC == 0 && $(lacks "Nothing was installed") && $(has "skip decoders: these plug-ins are in the boot snapshot already") ))
expect "the loader is decided on its own: a step" $(( $(has "put VCNVTLoader.kext on the EFI") && $(lacks "install the decoder plug-ins") ))
fake decnopending on "$DEC_NO_PENDING" "" "$LDR_WORKING" "" "$ENC_NONE" "$SNS_CURRENT"
plan decnopending
expect "no record (pending none): an older build is updated" $(( RC == 0 && $(has "install the decoder plug-ins (needs a reboot)") ))

print -r -- "the decoders were removed earlier in this boot; they run until the reboot"
fake decremoved on "$DEC_REMOVED" "" "$LDR_WORKING" "" "$ENC_NONE" "$SNS_CURRENT"
plan decremoved
expect "they are installed again (exit 0)" $(( RC == 0 && $(has "install the decoder plug-ins (needs a reboot)") ))
expect "not skipped as already these" $(lacks "skip decoders")
fake decremovedwait on "$DEC_REMOVED_WAIT" "$OTHER_BUILD" "$LDR_READY" "" "$ENC_NONE" "$SNS_CURRENT"
plan decremovedwait
expect "waiting for the loader: installed again right after it" $(( RC == 0 && $(before "put VCNVTLoader.kext" "install the decoder plug-ins right after the loader kext") ))

print -r -- "the EFI partition, told before the password"
fake efifound on "$DEC_WAIT" "$NOT_LET_IN" "$LDR_READY" "" "$ENC_NONE" "$SNS_CURRENT"
plan efifound
expect "one partition: the plan names it" $(( RC == 0 && $(has "EFI partition: disk9s9") ))
fake efiopen on "$DEC_WAIT" "$NOT_LET_IN" "$LDR_READY" "" "$ENC_NONE" "$SNS_CURRENT"
print -r -- open > "$WORK/efiopen/efi"
plan efiopen
expect "a partition not mounted: the plan goes ahead and says the install decides" $(( RC == 0 && $(has "EFI partition: chosen when installing") ))
for kind in ambiguous foreign none; do
  fake efi$kind on "$DEC_WAIT" "$NOT_LET_IN" "$LDR_READY" "" "$ENC_NONE" "$SNS_CURRENT"
  print -r -- $kind > "$WORK/efi$kind/efi"
  plan efi$kind --with-sensors
  expect "$kind: nothing is installed (exit 2), the plan says why and what to do" \
    $(( RC == 2 && $(has "EFI partition: the install cannot tell which one to use") && $(has "What to do:") && $(lacks "Plan:") ))
done
expect "the Terminal line keeps the options of the run" $(has "sudo install/install.sh --with-sensors --efi diskNsM")
fake efinotneeded pass "$DEC_READY" "" "$LDR_READY" "" "$ENC_NONE" "$SNS_CURRENT"
print -r -- ambiguous > "$WORK/efinotneeded/efi"
plan efinotneeded
expect "no kext to put on an EFI: the partition does not matter" $(( RC == 0 && $(lacks "EFI partition") ))

print -r -- "the JPEG kext: skipped only when the config.plist installed to lists it"
# jpeg.sh check --json of a working kext, with one EFI row: mounted, entry, kext
jpeg_json() { # mounted entry kext
  print -r -- '{"canInstall":true,"version":"1.0.0","running":"loaded 1.0.0, ready, 3 pictures decoded since boot","pendingReboot":false,"result":"working: VCNJpeg is ready.","efis":[{"id":"disk9s9","name":"OPENCORE","media":"x","mounted":'$1',"mountPoint":"/Volumes/OPENCORE","openCore":"yes","entry":"'$2'","kext":"'$3'","usable":"yes"}],"checks":[]}'
}
for c json in jpegok "$(jpeg_json true ok current)" jpegnoentry "$(jpeg_json true none current)" \
              jpegunmounted "$(jpeg_json false unknown unknown)" jpegother "$(jpeg_json true ok outdated)"; do
  fake $c on "$DEC_CURRENT" "" "$LDR_WORKING" "" "$ENC_NONE" "$SNS_CURRENT"
  print -r -- "$json" > "$WORK/$c/jpeg.json"
  print -r -- "" > "$WORK/$c/jpeg.txt"
done
plan jpegok --with-jpeg
expect "listed in that config.plist, this build: nothing to install" $(( RC == 0 && $(has "skip jpeg: already installed and running") && $(has "Nothing to install") ))
plan jpegnoentry --with-jpeg
expect "running, but started by another config file (no entry in config.plist): the kext is a step" \
  $(( RC == 0 && $(has "put VCNJpeg.kext on the EFI") && $(lacks "skip jpeg: already") ))
plan jpegunmounted --with-jpeg
expect "running, the EFI not mounted (entry not known): the kext is a step, the install looks" \
  $(( RC == 0 && $(has "put VCNJpeg.kext on the EFI") ))
plan jpegother --with-jpeg
expect "running, another build on that EFI: the kext is a step" $(( RC == 0 && $(has "put VCNJpeg.kext on the EFI") ))
print -r -- open > "$WORK/jpegok/efi"
plan jpegok --with-jpeg
expect "the partition is chosen when installing: the kext is a step" $(( RC == 0 && $(has "put VCNJpeg.kext on the EFI") ))

print -r -- "the stand-in is for plan only"
GPU_INSTALL_PLAN_FAKE=$WORK/fresh /bin/zsh "$INSTALL" > /dev/null 2>&1
rc=$?
OUT="exit $rc"
expect "install refuses it (exit 64)" $(( rc == 64 ))

(( failed == 0 ))
