// efi.h - adds or removes VCNEncodeFloor.kext in OpenCore's config.plist
// (Kernel > Add).
#pragma once

// what: "add", "remove" or "check". Returns 0 on success (or nothing to do),
// non-zero on error.
int efi_command(const char* what, const char* configPath);
