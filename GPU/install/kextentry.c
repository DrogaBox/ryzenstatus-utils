// kextentry - adds or removes the entry of one of this repository's kexts in
// OpenCore's config.plist (Kernel > Add). install/loader.sh and
// install/sensors.sh and install/jpeg.sh run it; decode/build.sh builds it as
// decode/build/kextentry.
//
//   kextentry <kext> check  <config.plist>   say what is there; changes nothing
//   kextentry <kext> add    <config.plist>   add the entry, after Lilu
//   kextentry <kext> remove <config.plist>   remove it
//
// <kext> is VCNVTLoader, GPUSensors or VCNJpeg. (The encoding fix has the same
// editor built into its service: vcnencodefix efi-add.)
//
// Every change writes a backup next to the file first
// (config.plist.backup-<date>-<time>-pre-<kext in lower case>) and is
// verified: the new file must be the old one plus, or minus, the entry and
// nothing else. The editing is install/ocentry.c.
//
// Exit status: 0 done or nothing to do; 3 the kext is listed with other
// settings (add changes nothing: remove it first); 1 any other error; 64 wrong
// usage.
#include <stdio.h>
#include <string.h>

#include "ocentry.h"

// MinKernel 24.0.0 = Sequoia: the oldest macOS the first two kexts start on;
// 25.0.0 = Tahoe for VCNJpeg, which was checked on 26.7.3 only.
static const OcKext kKexts[] = {
    {
        .bundle = "VCNVTLoader.kext",
        .executable = "Contents/MacOS/VCNVTLoader",
        .comment = "VCNVTLoader: lets the AV1 and VP9 decoder plug-ins load",
        .minKernel = "24.0.0",
        .oldMinKernel = NULL,
        .tag = "vcnvtloader",
        .removeHint = "remove it first (kextentry VCNVTLoader remove)",
    },
    {
        .bundle = "GPUSensors.kext",
        .executable = "Contents/MacOS/GPUSensors",
        .comment = "GPUSensors: publishes the GPU readings the driver hides",
        .minKernel = "24.0.0",
        .oldMinKernel = NULL,
        .tag = "gpusensors",
        .removeHint = "remove it first (kextentry GPUSensors remove)",
    },
    {
        .bundle = "VCNJpeg.kext",
        .executable = "Contents/MacOS/VCNJpeg",
        .comment = "VCNJpeg: JPEG and Motion JPEG decoding on the GPU",
        .minKernel = "25.0.0",
        .oldMinKernel = NULL,
        .tag = "vcnjpeg",
        .removeHint = "remove it first (kextentry VCNJpeg remove)",
    },
};

int main(int argc, char** argv) {
  const OcKext* kext = NULL;
  if (argc == 4) {
    size_t n = strlen(argv[1]);
    for (size_t i = 0; i < sizeof(kKexts) / sizeof(kKexts[0]); i++)
      if (!strncmp(kKexts[i].bundle, argv[1], n) &&
          !strcmp(kKexts[i].bundle + n, ".kext"))
        kext = &kKexts[i];
  }
  if (kext == NULL || (strcmp(argv[2], "check") && strcmp(argv[2], "add") &&
                       strcmp(argv[2], "remove"))) {
    fprintf(
        stderr,
        "usage: kextentry {VCNVTLoader|GPUSensors|VCNJpeg} {check|add|remove} "
        "<config.plist>\n");
    return 64;
  }
  return oc_entry_command(argv[2], argv[3], kext);
}
