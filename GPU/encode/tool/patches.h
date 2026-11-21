// patches.h - the two user-space patches applied by vcnencodefix inside
// VTEncoderXPCService.
#pragma once
#include <stddef.h>
#include <stdint.h>

// ---- preset: AMDRadeonVADriver2 (dyld shared cache) ----
extern const char* const kPresetImage;
enum {
  kPresetFindLen = 20
};  // the site's bytes, which must occur once in the driver's __text
enum { kPresetLen = 6 };  // bytes written (prefix of the site's bytes)
// One validated build of the driver (LC_UUID), read in IDA.
typedef struct {
  const char* macos;
  const char* uuid;
  uint8_t find[kPresetFindLen];
} PresetBuild;
const PresetBuild* preset_build(
    const char* uuid);  // NULL if the build was not validated
enum {
  kPresetSpeed = 0x01000006,
  kPresetBalance = 0x01000007,
  kPresetQuality = 0x01000008
};
void build_preset(uint8_t out[kPresetLen], uint32_t op);
int is_preset_patched(const uint8_t cur[kPresetLen]);

// ---- wide: AppleGVAHEVCEncoder (a file on disk, loaded with dlopen at session
// creation) ----
extern const char* const kWideImage;
enum {
  kWideFindLen = 48
};  // the call site's bytes, which must occur once in the plug-in's __text
enum {
  kWideCallLen = 42
};  // bytes written at the call site (prefix of the site's bytes)
enum {
  kWideCaveLen = 56
};  // bytes written in the unused space after the load commands
// One validated build of the plug-in (LC_UUID), read in IDA.
typedef struct {
  const char* macos;
  const char* uuid;
  uint8_t find[kWideFindLen];
} WideBuild;
const WideBuild* wide_build(
    const char* uuid);  // NULL if the build was not validated
// callVm / caveVm: addresses of the call site and of the cave in the image
// (vmaddr space, before the slide).
void build_wide(const WideBuild* b, uint8_t outCall[kWideCallLen],
                uint8_t outCave[kWideCaveLen], uint64_t callVm,
                uint64_t caveVm);
