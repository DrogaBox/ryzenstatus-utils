//
//  kern_start.cpp - VCNEncodeFloor, a Lilu plugin (part of VCNEncodeFix).
//
//  Every hardware encode session on Navi 21 asks PowerPlay for clocks once, at
//  session start, through the CWDDEPM escape 0xC00053 (PEM_CWDDEPM_PMRequest).
//  The request has a VCN clock floor field (payload +60, "VclkFloor", 10 kHz
//  units) that Apple's encoder (AMDRadeonVADriver2, VAUveEncoder+0x530) always
//  leaves at 0, so the SMU firmware starts the VCN at its lowest level (VCLK
//  362 / DCLK 316 MHz) and keeps it there while the application feeds
//  CPU-filled frames. This plugin fills that field for encoder requests. The
//  floor becomes an SMU soft minimum for the life of the session and goes away
//  when the session's power client is released.
//
//  Which requests are changed: VCN client type 28 or 33 (VCN instance 0 or 1),
//  VclkFloor 0, and a non-zero minMclk (payload +36). Only the encoder fills
//  minMclk (VAUveEncoder+0x534, 40000 on Navi 21); the VCN decoder sends its
//  request without the clock-request struct, so minMclk is 0 there and decode
//  is left alone.
//
//  macOS ships two Navi 21 power libraries, AMDRadeonX6000HWLibs and
//  AMDRadeonX6800HWLibs; AMDRadeonX6000HWServices picks one per GPU (natively
//  X6000 for the RX 6800 / 6800 XT / 6900 XT; setups with NootRX load X6800).
//  Their PEM_CWDDEPM_PMRequest is the same code, so the plugin hooks whichever
//  loads. It only routes the function when the library is one of the builds the
//  payload layout was read from in IDA (LC_UUID, kX6000Builds / kX6800Builds).
//  On 26.7.3 and 15.8.x the function is found by its symbol; Sonoma 14.8.9
//  ships both libraries stripped, so there it is routed at its offset from the
//  image header after its first 32 bytes are compared. Its state is published
//  as the property "VCNEncodeFloor" on IOResources (ioreg -rd1 -c IOResources |
//  grep VCNEncodeFloor).
//
//  The floor must stay inside each chip's own video clock levels, and the same
//  driver family also runs chips whose top levels are below it (an RX 5600 XT
//  table tops out at VCLK 1267 / DCLK 1086 MHz). So requests are changed only
//  when every AMD GPU in the Mac is a chip whose levels were read (chipFloor):
//  Navi 21 (device-id 0x73A0-0x73AF, 0x73BF; this Mac's table: VCLK 363/1400,
//  DCLK 317/1225) and Navi 23 (0x73E0-0x73EF, 0x73FF; two RX 6600 XT tables:
//  VCLK 690/1429, DCLK 572/1250). Navi 23 has not run on a card. A vcnfloor=N
//  boot argument is taken as the user's own value and applies to any chip.
//
//  Boot args: -vcnflooroff disables the plugin; vcnfloor=N sets the floor
//  (default 132297); -vcnfloorall also changes requests with minMclk 0
//  (decode); -vcnhevc10 (experimental, off by default) advertises HEVC Main10
//  on supported AMD accelerators (state in "VCNHEVC10" on IOResources);
//  -vcnfloordbg / -vcnfloorbeta are Lilu's usual debug / beta switches.
//
#include <IOKit/IOService.h>
#include <libkern/libkern.h>
#include <mach-o/loader.h>

// Lilu's own headers shadow names in two places (kern_util.hpp, kern_cpu.hpp);
// the warning is theirs, not this file's.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshadow"
#include <Headers/kern_api.hpp>
#include <Headers/kern_devinfo.hpp>
#include <Headers/kern_iokit.hpp>
#include <Headers/kern_patcher.hpp>
#include <Headers/kern_util.hpp>
#include <Headers/plugin_start.hpp>
#pragma clang diagnostic pop

#include "floor_logic.hpp"

// 132297 in 10 kHz units: VCLK soft minimum 1322 MHz, which the firmware rounds
// up to its 1400 MHz level; the DCLK request of PEM_CWDDEPM_PMRequest is 0, so
// the DCLK soft minimum is the raw value, of which the SMU message keeps 16
// bits: 132297 & 0xFFFF = 1225 MHz, the top DCLK level. This exact value was
// tested; others were not.
static constexpr uint32_t kDefaultFloor = vcnfloor::kDefaultFloor;
static constexpr uint32_t kClientVcn0 = 28;
static constexpr uint32_t kClientVcn1 = 33;
static constexpr size_t kPayloadSize =
    112;  // PP_Cwdde's input size for escape 0x53
static constexpr size_t kOffClientType = 16;
static constexpr size_t kOffMinMclk = 36;
static constexpr size_t kOffVclkFloor = 60;
static constexpr int kMaxLogs = 32;

// Validated builds. In each, PEM_CWDDEPM_PMRequest reads the same payload
// fields at the same offsets as AMDRadeonX6000HWLibs of 26.7.3 (compared in
// Hex-Rays: 15.8.x is identical line for line, and X6800 differs from X6000
// only in the source line numbers its log calls pass).
struct HWLibsBuild {
  const char* macos;
  uint8_t uuid[16];
  size_t offset;  // 0: route by symbol; else the function's offset from the
                  // image header (stripped kext)
  uint8_t prologue[32];  // the function's first bytes when routed by offset
};
static const HWLibsBuild kX6000Builds[]{
    {"26.7.3 (25G342)",
     {0x5c, 0xd4, 0xbc, 0x0c, 0xc2, 0x25, 0x36, 0x5f, 0xa8, 0x72, 0xc8, 0x85,
      0x57, 0x5b, 0x9a, 0x19},
     0,
     {}},
    {"15.8.2 (24H232), 15.8.3 (24H241)",
     {0x9e, 0x9a, 0x8a, 0x30, 0x56, 0xf9, 0x35, 0x56, 0x8e, 0x40, 0x37, 0xbb,
      0xfe, 0x44, 0x42, 0x45},
     0,
     {}},
    {"14.8.9 (23J631)",
     {0x66, 0x24, 0x82, 0x9b, 0xbd, 0x01, 0x30, 0x35, 0x88, 0x04, 0x3b, 0x1a,
      0x9a, 0xee, 0xba, 0x18},
     0xf3536,
     {0x55, 0x48, 0x89, 0xe5, 0x41, 0x57, 0x41, 0x56, 0x41, 0x55, 0x41,
      0x54, 0x53, 0x48, 0x81, 0xec, 0x08, 0x02, 0x00, 0x00, 0x49, 0x89,
      0xd6, 0x49, 0x89, 0xf7, 0x49, 0x89, 0xfc, 0x48, 0x89, 0x7d}},
};
static const HWLibsBuild kX6800Builds[]{
    {"26.7.3 (25G342)",
     {0x27, 0x7b, 0x80, 0x59, 0x8c, 0x8e, 0x3a, 0x34, 0x8b, 0x72, 0x19, 0x4a,
      0xe9, 0x37, 0xaa, 0xe1},
     0,
     {}},
    {"15.8.2 (24H232), 15.8.3 (24H241)",
     {0x07, 0x01, 0x2a, 0x5e, 0x6c, 0x6e, 0x38, 0xf2, 0x8b, 0x35, 0x05, 0xad,
      0xdf, 0xd3, 0x2f, 0x1f},
     0,
     {}},
    {"14.8.9 (23J631)",
     {0x96, 0x84, 0x96, 0xe1, 0xbd, 0x86, 0x3a, 0x39, 0x9a, 0x0a, 0x2f, 0x13,
      0xe8, 0x89, 0xed, 0xd8},
     0x364fe,
     {0x55, 0x48, 0x89, 0xe5, 0x41, 0x57, 0x41, 0x56, 0x41, 0x55, 0x41,
      0x54, 0x53, 0x48, 0x81, 0xec, 0x08, 0x02, 0x00, 0x00, 0x49, 0x89,
      0xd6, 0x49, 0x89, 0xf7, 0x49, 0x89, 0xfc, 0x48, 0x89, 0x7d}},
};

static uint32_t gFloor = kDefaultFloor;
static bool gAllClients = false;
static bool gFloorGiven = false;  // vcnfloor=N on the boot arguments
static bool gHevc10 = false;
static IONotifier* gHevc10Notifier = nullptr;
static bool gHevc10Set = false;
static int gLogs = 0;

// What the GPU check found. Unknown until Lilu's device list is read (and if it
// cannot be read): then the plugin works as it did before the check.
enum class Gpus { Unknown, AllKnown, Other };
static Gpus gGpus = Gpus::Unknown;
static bool gAnyNavi23 = false;
static bool gRouted = false;

using vcnfloor::chipFloor;
using vcnfloor::isNavi23;

static inline bool floorAllowed() {
  return gGpus != Gpus::Other || gFloorGiven;
}

static const char* kX6000Paths[]{
    "/System/Library/Extensions/AMDRadeonX6000HWServices.kext/Contents/PlugIns/"
    "AMDRadeonX6000HWLibs.kext/Contents/MacOS/AMDRadeonX6000HWLibs"};
static const char* kX6800Paths[]{
    "/System/Library/Extensions/AMDRadeonX6000HWServices.kext/Contents/PlugIns/"
    "AMDRadeonX6800HWLibs.kext/Contents/MacOS/AMDRadeonX6800HWLibs"};
static KernelPatcher::KextInfo kHWLibs[]{
    {"com.apple.kext.AMDRadeonX6000HWLibs",
     kX6000Paths,
     arrsize(kX6000Paths),
     {},
     {},
     KernelPatcher::KextInfo::Unloaded},
    {"com.apple.kext.AMDRadeonX6800HWLibs",
     kX6800Paths,
     arrsize(kX6800Paths),
     {},
     {},
     KernelPatcher::KextInfo::Unloaded},
};
// Per entry of kHWLibs: its short name and validated builds.
struct HWLibsKind {
  const char* name;
  const HWLibsBuild* builds;
  size_t count;
};
static const HWLibsKind kKinds[]{
    {"AMDRadeonX6000HWLibs", kX6000Builds, arrsize(kX6000Builds)},
    {"AMDRadeonX6800HWLibs", kX6800Builds, arrsize(kX6800Builds)},
};
static_assert(arrsize(kKinds) == arrsize(kHWLibs), "one kind per library");

static void publishState(const char* state) {
  IOService* res = IOService::getResourceService();
  if (res) res->setProperty("VCNEncodeFloor", state);
}

static void publishHevc10(const char* state) {
  IOService* res = IOService::getResourceService();
  if (res) res->setProperty("VCNHEVC10", state);
}

static bool parseDecimalInt(const char* s, int& out) {
  if (s == nullptr) return false;
  while (*s == ' ' || *s == '\t') s++;
  bool neg = false;
  if (*s == '-') {
    neg = true;
    s++;
  } else if (*s == '+') {
    s++;
  }
  if (*s < '0' || *s > '9') return false;
  constexpr int kMax = 0x7fffffff;
  int val = 0;
  while (*s >= '0' && *s <= '9') {
    int digit = *s - '0';
    if (val > (kMax - digit) / 10) {
      val = kMax;
      break;
    }
    val = val * 10 + digit;
    s++;
  }
  out = neg ? -val : val;
  return true;
}

static void publishHevc10NotSet(const char* reason) {
  if (__atomic_load_n(&gHevc10Set, __ATOMIC_ACQUIRE)) return;
  char msg[160];
  snprintf(msg, sizeof(msg), "not set: %s", reason);
  publishHevc10(msg);
}

static bool onHevc10Accelerator(void*, void*, IOService* svc, IONotifier*) {
  if (svc == nullptr) return true;
  const char* cls = svc->getMetaClass()->getClassName();
  if (cls == nullptr) cls = "unknown";

  // The accelerator hangs under AMD's controller, not directly under the PCI
  // device (GFX0 -> AmdRadeonControllerNavi21 -> ...GraphicsAccelerator), so
  // walk up to the first provider that has the PCI IDs.
  uint32_t vendor = 0, device = 0;
  bool found = false;
  IOService* pci = svc->getProvider();
  for (int depth = 0; pci != nullptr && depth < 4 && !found; depth++) {
    found = WIOKit::getOSDataValue(pci, "vendor-id", vendor) &&
            WIOKit::getOSDataValue(pci, "device-id", device);
    if (!found) pci = pci->getProvider();
  }
  if (!found) {
    SYSLOG("vcnfloor", "vcnhevc10: skipping %s (GPU device-id not found)", cls);
    publishHevc10NotSet("GPU device-id not found");
    return true;
  }
  if (vendor != WIOKit::VendorID::ATIAMD || chipFloor(device) == 0) {
    SYSLOG("vcnfloor",
           "vcnhevc10: skipping %s (vendor 0x%04x device 0x%04x, unsupported "
           "GPU)",
           cls, vendor, device);
    publishHevc10NotSet("unsupported GPU");
    return true;
  }

  OSObject* encObj = svc->copyProperty("IOGVAHEVCEncode");
  OSString* encStr = OSDynamicCast(OSString, encObj);
  int encLevel = 0;
  if (encStr == nullptr ||
      !parseDecimalInt(encStr->getCStringNoCopy(), encLevel)) {
    SYSLOG("vcnfloor",
           "vcnhevc10: skipping %s (IOGVAHEVCEncode missing or not a number)",
           cls);
    OSSafeReleaseNULL(encObj);
    publishHevc10NotSet("IOGVAHEVCEncode missing or not a number");
    return true;
  }

  OSObject* capsObj = svc->copyProperty("IOGVAHEVCEncodeCapabilities");
  OSDictionary* capsDict = OSDynamicCast(OSDictionary, capsObj);
  if (capsDict == nullptr) {
    SYSLOG("vcnfloor",
           "vcnhevc10: skipping %s (IOGVAHEVCEncodeCapabilities missing)", cls);
    OSSafeReleaseNULL(capsObj);
    OSSafeReleaseNULL(encObj);
    publishHevc10NotSet("IOGVAHEVCEncodeCapabilities missing");
    return true;
  }

  OSArray* profArr =
      OSDynamicCast(OSArray, capsDict->getObject("VTSupportedProfileArray"));
  OSDictionary* detailsDict =
      OSDynamicCast(OSDictionary, capsDict->getObject("VTPerProfileDetails"));
  OSDictionary* prof1Dict =
      detailsDict ? OSDynamicCast(OSDictionary, detailsDict->getObject("1"))
                  : nullptr;
  if (profArr == nullptr || profArr->getCount() == 0 ||
      detailsDict == nullptr || prof1Dict == nullptr) {
    SYSLOG("vcnfloor",
           "vcnhevc10: skipping %s (unexpected IOGVAHEVCEncodeCapabilities "
           "shape)",
           cls);
    OSSafeReleaseNULL(capsObj);
    OSSafeReleaseNULL(encObj);
    publishHevc10NotSet("unexpected IOGVAHEVCEncodeCapabilities shape");
    return true;
  }

  bool hasProf2 = false;
  unsigned int numBits = 0;
  for (unsigned int i = 0; i < profArr->getCount(); i++) {
    OSNumber* n = OSDynamicCast(OSNumber, profArr->getObject(i));
    if (n == nullptr) {
      SYSLOG("vcnfloor",
             "vcnhevc10: skipping %s (VTSupportedProfileArray entry not a "
             "number)",
             cls);
      OSSafeReleaseNULL(capsObj);
      OSSafeReleaseNULL(encObj);
      publishHevc10NotSet("VTSupportedProfileArray entry not a number");
      return true;
    }
    if (numBits == 0) numBits = n->numberOfBits();
    if (n->unsigned64BitValue() == 2) hasProf2 = true;
  }
  if (numBits == 0) numBits = 32;

  bool hasDetail2 = detailsDict->getObject("2") != nullptr;
  bool needEnc = encLevel < 2;
  bool needCaps = !hasProf2 || !hasDetail2;
  if (!needEnc && !needCaps) {
    SYSLOG("vcnfloor",
           "vcnhevc10: %s already advertises profile 2 (IOGVAHEVCEncode %d)",
           cls, encLevel);
    OSSafeReleaseNULL(capsObj);
    OSSafeReleaseNULL(encObj);
    publishHevc10NotSet("already advertises profile 2");
    return true;
  }

  OSDictionary* newCaps = nullptr;
  if (needCaps) {
    newCaps = OSDictionary::withDictionary(capsDict);
    OSArray* newArr =
        OSArray::withArray(profArr, profArr->getCount() + (hasProf2 ? 0 : 1));
    OSDictionary* newDetails = OSDictionary::withDictionary(
        detailsDict, detailsDict->getCount() + (hasDetail2 ? 0 : 1));
    OSNumber* num2 = hasProf2 ? nullptr : OSNumber::withNumber(2ULL, numBits);
    OSDictionary* newProf2 =
        hasDetail2 ? nullptr : OSDictionary::withDictionary(prof1Dict);

    bool ok = newCaps != nullptr && newArr != nullptr &&
              newDetails != nullptr && (hasProf2 || num2 != nullptr) &&
              (hasDetail2 || newProf2 != nullptr);
    if (ok && !hasProf2) ok = newArr->setObject(num2);
    if (ok && !hasDetail2) ok = newDetails->setObject("2", newProf2);
    if (ok) ok = newCaps->setObject("VTSupportedProfileArray", newArr);
    if (ok) ok = newCaps->setObject("VTPerProfileDetails", newDetails);

    OSSafeReleaseNULL(num2);
    OSSafeReleaseNULL(newProf2);
    OSSafeReleaseNULL(newArr);
    OSSafeReleaseNULL(newDetails);
    if (!ok) {
      SYSLOG("vcnfloor",
             "vcnhevc10: skipping %s (failed to copy "
             "IOGVAHEVCEncodeCapabilities)",
             cls);
      OSSafeReleaseNULL(newCaps);
      OSSafeReleaseNULL(capsObj);
      OSSafeReleaseNULL(encObj);
      publishHevc10NotSet("out of memory");
      return true;
    }
  }

  OSString* newEnc = needEnc ? OSString::withCString("2") : nullptr;
  if (needEnc && newEnc == nullptr) {
    SYSLOG("vcnfloor", "vcnhevc10: skipping %s (out of memory)", cls);
    OSSafeReleaseNULL(newCaps);
    OSSafeReleaseNULL(capsObj);
    OSSafeReleaseNULL(encObj);
    publishHevc10NotSet("out of memory");
    return true;
  }

  if (needEnc) {
    svc->setProperty("IOGVAHEVCEncode", newEnc);
    OSSafeReleaseNULL(newEnc);
  }
  if (needCaps) {
    svc->setProperty("IOGVAHEVCEncodeCapabilities", newCaps);
    OSSafeReleaseNULL(newCaps);
  }
  OSSafeReleaseNULL(capsObj);
  OSSafeReleaseNULL(encObj);

  __atomic_store_n(&gHevc10Set, true, __ATOMIC_RELEASE);
  SYSLOG("vcnfloor",
         "vcnhevc10: set on %s (device 0x%04x, IOGVAHEVCEncode %d -> %d)", cls,
         device, encLevel, needEnc ? 2 : encLevel);
  char msg[160];
  snprintf(msg, sizeof(msg), "set on %s", cls);
  publishHevc10(msg);
  return true;
}

static inline uint32_t rd32(const uint8_t* p) {
  uint32_t v;
  memcpy(&v, p, sizeof(v));
  return v;
}
static inline void wr32(uint8_t* p, uint32_t v) { memcpy(p, &v, sizeof(v)); }

// PEM_CWDDEPM_PMRequest(PEM *, const payload *in, payload *out); returns 0 on
// success.
using t_pmRequest = int64_t (*)(void* pem, uint8_t* in, uint8_t* out);
// One original per library: a Mac with two Navi 21 cards could load both, and
// each route has its own trampoline.
static t_pmRequest orgPMRequest[arrsize(kHWLibs)]{};

static int64_t floorPMRequest(t_pmRequest org, void* pem, uint8_t* in,
                              uint8_t* out) {
  if (in != nullptr) {
    uint32_t type = rd32(in + kOffClientType);
    uint32_t floor = rd32(in + kOffVclkFloor);
    uint32_t minMclk = rd32(in + kOffMinMclk);
    if ((type == kClientVcn0 || type == kClientVcn1) && floor == 0 &&
        (minMclk != 0 || gAllClients) && floorAllowed()) {
      // Work on a copy so the caller's buffer is never changed.
      uint8_t copy[kPayloadSize];
      memcpy(copy, in, sizeof(copy));
      wr32(copy + kOffVclkFloor, gFloor);
      int64_t result = org(pem, copy, out);
      // Several encode sessions can get here at once: a log slot is taken
      // atomically so the cap holds.
      int n = __atomic_load_n(&gLogs, __ATOMIC_RELAXED);
      while (n < kMaxLogs &&
             !__atomic_compare_exchange_n(&gLogs, &n, n + 1, true,
                                          __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {
      }
      if (n < kMaxLogs)
        SYSLOG("vcnfloor",
               "client type %u minMclk %u: VclkFloor 0 -> %u, result %lld",
               type, minMclk, gFloor, result);
      return result;
    }
  }
  return org(pem, in, out);
}

template <size_t K>
static int64_t wrapPMRequest(void* pem, uint8_t* in, uint8_t* out) {
  return floorPMRequest(orgPMRequest[K], pem, in, out);
}
static const t_pmRequest kWrappers[]{wrapPMRequest<0>, wrapPMRequest<1>};
static_assert(arrsize(kWrappers) == arrsize(kHWLibs),
              "one wrapper per library");

// Returns true when the Mach-O image at `address` has the LC_UUID `want`.
static bool imageHasUuid(mach_vm_address_t address, size_t size,
                         const uint8_t want[16]) {
  if (address == 0 || size < sizeof(mach_header_64)) return false;
  auto mh = reinterpret_cast<const mach_header_64*>(address);
  if (mh->magic != MH_MAGIC_64 ||
      mh->sizeofcmds > size - sizeof(mach_header_64))
    return false;
  auto p = reinterpret_cast<const uint8_t*>(mh + 1);
  auto end = p + mh->sizeofcmds;
  for (uint32_t i = 0; i < mh->ncmds && p + sizeof(load_command) <= end; i++) {
    auto lc = reinterpret_cast<const load_command*>(p);
    if (lc->cmdsize < sizeof(load_command) || p + lc->cmdsize > end)
      return false;
    if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(uuid_command))
      return memcmp(reinterpret_cast<const uuid_command*>(lc)->uuid, want,
                    16) == 0;
    p += lc->cmdsize;
  }
  return false;
}

static void publishActive() {
  if (!floorAllowed())
    publishState(
        "off: an AMD GPU whose video clock levels were not read (Navi 21 and "
        "Navi 23 only; vcnfloor=N applies a value of your own)");
  else if (gAnyNavi23 && !gFloorGiven)
    publishState(gAllClients ? "active: encode and decode (Navi 23: floor from "
                               "its clock table, not run on one yet)"
                             : "active: encode (Navi 23: floor from its clock "
                               "table, not run on one yet)");
  else
    publishState(gAllClients ? "active: encode and decode" : "active: encode");
}

// Reads the Mac's GPUs once Lilu can list them. Either order with the library
// load works: the state is published again if the route came first.
static void checkGpus(void*, KernelPatcher&) {
  auto info = DeviceInfo::create();
  if (info == nullptr) {
    SYSLOG("vcnfloor", "no device list, GPU check skipped");
    return;
  }
  size_t navi21 = 0, navi23 = 0, other = 0;
  uint32_t floor = 0;  // the smallest floor among the GPUs found
  auto look = [&](IORegistryEntry* video, uint32_t vendor) {
    uint32_t device = 0;
    if (video == nullptr || vendor != WIOKit::VendorID::ATIAMD) return;
    uint32_t f = 0;
    if (WIOKit::getOSDataValue(video, "device-id", device))
      f = chipFloor(device);
    if (f == 0) {
      other++;
      return;
    }
    if (isNavi23(device))
      navi23++;
    else
      navi21++;
    if (floor == 0 || f < floor) floor = f;
  };
  for (size_t i = 0; i < info->videoExternal.size(); i++)
    look(info->videoExternal[i].video, info->videoExternal[i].vendor);
  DeviceInfo::deleter(info);
  gGpus = other                ? Gpus::Other
          : (navi21 || navi23) ? Gpus::AllKnown
                               : Gpus::Unknown;
  gAnyNavi23 = navi23 != 0;
  // vcnfloor=N wins; otherwise each chip's own floor (today the same value).
  if (!gFloorGiven && gGpus == Gpus::AllKnown) gFloor = floor;
  SYSLOG("vcnfloor",
         "GPUs: %zu Navi 21, %zu Navi 23, %zu other AMD; floor %u%s", navi21,
         navi23, other, gFloor,
         other && gFloorGiven ? " (vcnfloor= given: floor applied)" : "");
  if (gRouted) publishActive();
}

static void onHWLibsLoad(void*, KernelPatcher& patcher, size_t index,
                         mach_vm_address_t address, size_t size) {
  size_t k = 0;
  while (k < arrsize(kHWLibs) && kHWLibs[k].loadIndex != index) k++;
  if (k == arrsize(kHWLibs)) return;
  const HWLibsKind& kind = kKinds[k];

  const HWLibsBuild* build = nullptr;
  for (size_t i = 0; i < kind.count; i++)
    if (imageHasUuid(address, size, kind.builds[i].uuid))
      build = &kind.builds[i];
  if (build == nullptr) {
    SYSLOG("vcnfloor", "%s is not a validated build, doing nothing", kind.name);
    publishState(k == 0 ? "off: AMDRadeonX6000HWLibs build not validated"
                        : "off: AMDRadeonX6800HWLibs build not validated");
    return;
  }
  bool routed = false;
  if (build->offset == 0) {
    KernelPatcher::RouteRequest requests[]{
        {"_PEM_CWDDEPM_PMRequest", kWrappers[k], orgPMRequest[k]},
    };
    routed = patcher.routeMultiple(index, requests, address, size);
  } else {
    mach_vm_address_t from = address + build->offset;
    if (build->offset + sizeof(build->prologue) > size ||
        memcmp(reinterpret_cast<const void*>(from), build->prologue,
               sizeof(build->prologue)) != 0) {
      SYSLOG("vcnfloor",
             "PEM_CWDDEPM_PMRequest not at the expected place, doing nothing");
      publishState("off: function not found");
      return;
    }
    // routeMultiple only takes symbols, so the stripped build uses the
    // address-based call Lilu marks deprecated.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    auto wrapper = patcher.routeFunction(
        from, reinterpret_cast<mach_vm_address_t>(kWrappers[k]), true);
#pragma clang diagnostic pop
    if (patcher.getError() == KernelPatcher::Error::NoError && wrapper != 0) {
      orgPMRequest[k] = reinterpret_cast<t_pmRequest>(wrapper);
      routed = true;
    }
  }
  if (routed) {
    gRouted = true;
    SYSLOG("vcnfloor", "routed %s on %s, VCN encode clock floor %u%s",
           kind.name, build->macos, gFloor,
           gAllClients ? " (all VCN clients)" : "");
    publishActive();
  } else {
    SYSLOG("vcnfloor", "route failed (%d), driver left as it is",
           patcher.getError());
    patcher.clearError();
    publishState("off: route failed");
  }
}

static const char* bootargOff[]{"-vcnflooroff"};
static const char* bootargDebug[]{"-vcnfloordbg"};
static const char* bootargBeta[]{"-vcnfloorbeta"};

PluginConfiguration ADDPR(config){
    xStringify(PRODUCT_NAME),
    parseModuleVersion(xStringify(MODULE_VERSION)),
    LiluAPI::AllowNormal,
    bootargOff,
    arrsize(bootargOff),
    bootargDebug,
    arrsize(bootargDebug),
    bootargBeta,
    arrsize(bootargBeta),
    KernelVersion::Sonoma,
    KernelVersion::Tahoe,
    []() {
      uint32_t requested = 0;
      if (PE_parse_boot_argn("vcnfloor", &requested, sizeof(requested))) {
        if (requested != 0) {
          gFloor = requested;
          gFloorGiven = true;
        } else
          SYSLOG("vcnfloor", "ignoring vcnfloor=0, using %u", gFloor);
      }
      gAllClients = checkKernelArgument("-vcnfloorall");
      gHevc10 = checkKernelArgument("-vcnhevc10");
      publishState("waiting for AMDRadeonX6000HWLibs or AMDRadeonX6800HWLibs");
      if (gHevc10) {
        publishHevc10("waiting for AMDRadeonX6000_AMDGraphicsAccelerator");
        OSDictionary* matching =
            IOService::serviceMatching("AMDRadeonX6000_AMDGraphicsAccelerator");
        if (matching == nullptr) {
          SYSLOG("vcnfloor",
                 "vcnhevc10: serviceMatching failed (out of memory)");
          publishHevc10("not set: out of memory");
        } else {
          gHevc10Notifier = IOService::addMatchingNotification(
              gIOFirstPublishNotification, matching, onHevc10Accelerator,
              nullptr, nullptr, 0);
          // addMatchingNotification retains matching itself.
          matching->release();
          if (gHevc10Notifier == nullptr) {
            SYSLOG("vcnfloor", "vcnhevc10: addMatchingNotification failed");
            publishHevc10("not set: matching notification failed");
          }
        }
      } else {
        publishHevc10("off");
      }
      lilu.onPatcherLoadForce(checkGpus, nullptr);
      lilu.onKextLoadForce(kHWLibs, arrsize(kHWLibs), onHWLibsLoad, nullptr);
    }};
