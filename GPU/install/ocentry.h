// ocentry.h - adds or removes one kext entry in OpenCore's config.plist
// (Kernel > Add). Shared by the encoding fix (VCNEncodeFloor.kext) and the
// loader kext (VCNVTLoader.kext). Both are Lilu plug-ins, so the entry is only
// added when Lilu is enabled, and it goes after Lilu.
#pragma once

typedef struct {
  // "VCNVTLoader.kext", as it is named in EFI/OC/Kexts
  const char* bundle;
  // "Contents/MacOS/VCNVTLoader"
  const char* executable;
  // Free text; an entry with another comment is ours too.
  const char* comment;
  // The oldest Darwin version OpenCore loads it on, "24.0.0".
  const char* minKernel;
  // A MinKernel that earlier versions wrote and that "add" changes to minKernel
  // in place, or NULL.
  const char* oldMinKernel;
  // Names the backups: config.plist.backup-<date>-<time>-pre-<tag>
  const char* tag;
  // What "add" tells the user to do when the kext is listed with other
  // settings: "run efi-remove first".
  const char* removeHint;
} OcKext;

// what: "add", "remove" or "check".
// Returns 0 when done or when there was nothing to do, 3 when "add" finds the
// kext listed with other settings (nothing is changed; remove it first), and 1
// for any other error.
int oc_entry_command(const char* what, const char* configPath, const OcKext* k);
