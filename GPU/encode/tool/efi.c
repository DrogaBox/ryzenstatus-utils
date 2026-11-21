// efi.c - adds or removes VCNEncodeFloor.kext in OpenCore's config.plist
// (Kernel > Add). The editing itself is install/ocentry.c, shared with the
// loader kext; this file only says what the entry of VCNEncodeFloor is.
#include "efi.h"

#include "ocentry.h"

// Darwin 23 = Sonoma, the oldest macOS the kext supports (its Lilu
// configuration allows Sonoma to Tahoe). 1.0.0 to 1.2.0 wrote MinKernel 25.0.0
// (Tahoe only), so OpenCore skipped the kext on Sonoma and Sequoia; efi-add
// updates such an entry in place.
static const OcKext kFloor = {
    .bundle = "VCNEncodeFloor.kext",
    .executable = "Contents/MacOS/VCNEncodeFloor",
    .comment = "VCNEncodeFix: VCN encode clock floor",
    .minKernel = "23.0.0",
    .oldMinKernel = "25.0.0",
    .tag = "vcnencodefix",
    .removeHint = "run efi-remove first",
};

int efi_command(const char* what, const char* configPath) {
  return oc_entry_command(what, configPath, &kFloor);
}
