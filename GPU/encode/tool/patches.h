// patches.h - the user-space patches applied by vcnencodefix: three inside
// VTEncoderXPCService (preset, wide, hevc10), one inside ContinuityCaptureAgent
// and avconferenced (cc).
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

// ---- cc: VideoProcessing (dyld shared cache), inside the processes that
// decode video calls: ContinuityCaptureAgent and avconferenced ----
extern const char* const kCcImage;
extern const char* const kCcTargets[];  // NULL-terminated process paths
// K: where VCPDec keeps the DecoderUsage key (checked, never written);
// A: the Usage removal before the hardware decoder; B: the Usage property;
// E: the board-id check that sends FaceTime's encoder (usage 42) to the T2.
enum { kCcSites = 4 };
enum { kCcMaxFind = 160, kCcTgtLen = 32, kCcMaxWrite = 10 };
extern const char kCcSiteName[kCcSites + 1];  // "KABE"
// E's layout (the same in every validated build): the two board-id compares
// (lea rsi, <board-id>; ...; call CFStringCompare) at kCcEFirst and
// kCcESecond, the release of the board-id string and the BridgeEncode
// preference right after them at kCcERelease.
enum { kCcEFirst = 0x13, kCcESecond = 0x29, kCcERelease = 0x3f };
typedef struct {
  uint8_t len;               // bytes of find in use
  uint8_t find[kCcMaxFind];  // must occur once in VideoProcessing's __text
  uint8_t off, n;    // the bytes written: find[off .. off + n); n 0: none
  uint16_t tgtDist;  // where the written jump lands, from find[0]
  uint8_t tgtLen;    // bytes checked there (B: outside find); 0 = inside find
  uint8_t tgt[kCcTgtLen];
} CcSite;
// One validated build of VideoProcessing (LC_UUID), read in IDA.
typedef struct {
  const char* macos;
  const char* uuid;
  CcSite site[kCcSites];
} CcBuild;
const CcBuild* cc_build(const char* uuid);  // NULL if not validated
const CcBuild* cc_build_at(size_t i);       // the table, for the tests
// Finds the sites in __text (text = its bytes, textVm = its address);
// NULL and *why set if anything does not match exactly. sites[k] = address of
// site k's first byte.
const CcBuild* cc_locate(const CcBuild* b, const uint8_t* text, size_t size,
                         uint64_t textVm, uint64_t sites[kCcSites], char* why,
                         size_t whyLen);
// The bytes written at site + off (n of them).
void build_cc(const CcSite* s, uint8_t out[kCcMaxWrite]);
// State of a site from the bytes read at it (len bytes) and at its target
// (tgtLen bytes): 0 original, 1 patched, -1 anything else. A site that writes
// nothing is 0 when its bytes are intact.
int cc_site_state(const CcSite* s, const uint8_t* cur, const uint8_t* curTgt);

// ---- hevc10: AMDRadeonVADriver2 (dyld shared cache, same image as preset)
// ----
enum {
  kHevc10FmtFindLen = 96
};  // Vcn3Encoder::setInputAndOutputFormatParams site, unique in __text
enum { kHevc10FmtLen = 96 };  // bytes written at the format site
enum {
  kHevc10DbkFindLen = 52
};  // AVDVcn3HevcEncDataProcessor::setupDeblocking site (+7 tail bytes to make
    // it unique from Vcn2)
enum { kHevc10DbkLen = 45 };  // bytes written at the deblocking site
// One validated build of the driver (LC_UUID), read in IDA.
typedef struct {
  const char* macos;
  const char* uuid;
  uint8_t fmtFind[kHevc10FmtFindLen];
  uint8_t fmtRepl[kHevc10FmtLen];
  uint8_t dbkFind[kHevc10DbkFindLen];
  uint8_t dbkRepl[kHevc10DbkLen];
} Hevc10Build;
const Hevc10Build* hevc10_build(
    const char* uuid);  // NULL if the build was not validated
