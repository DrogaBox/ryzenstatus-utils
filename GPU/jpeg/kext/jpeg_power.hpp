//
//  jpeg_power.hpp - the PowerPlay requests of VCNJpeg. No kernel parts.
//
//  Apple's driver never asks PowerPlay for the JPEG block. It does ask for the
//  VCN, from the kernel, in two calls of AMDRadeonX6000 that VCNJpeg
//  copies with the JPEG client type (21) in place of the VCN one (28):
//
//    AMDAccelVCNContext::setClocks (0x47afc)         escape 0x53,
//    PEM_CWDDEPM_PMRequest:
//        creates the session's power client (PSM_CreateNewInstanceCtx)
//    AMDAccelVideoContext::notifyPMContext (0x2824a) escape 0x34,
//    PEM_CWDDEPM_ActivateClient:
//        activates it, or deactivates it (which also frees it), and
//        re-arbitrates
//
//  With a JPEG client active, PEM_ClockChange case 21 has put a 1 in setting 42
//  of its request; PSM_ReArbit (0xf988a) merges that into the state manager's
//  +1540 and calls PHM_PowerGateJPEG -> Phw_SwSmu_PowerGateJpeg ->
//  smu_11_0_7_disable_power_gating case 1 (SMU message 44, PowerUpJpeg, only
//  when the SMU feature 0x400000 = MM_DPM_PG is on and the block is not marked
//  up; smu_query_feature_enabled returns 0 when the feature IS on). With no
//  client left it calls the same chain to gate it (message 45).
//
//  Both go out as Apple's do:
//  AMDGraphicsAccelerator::sendPMCommand(accelerator, {in, in size, out, &out
//  size}), which hands them to the framebuffer and on to
//  AtiPowerPlayServices::ppCWDDE.
//
//  Layouts are those of the two Apple functions and of the handlers in
//  HWLibs; each field was checked against Hex-Rays, and tests/run.sh runs
//  Apple's two functions from the KDK and compares what they build with ours.
//
#pragma once
#include <stddef.h>
#include <stdint.h>

namespace jw {

constexpr uint32_t kEscapeCode = 0x00C00000;    // escape = this | table index
constexpr uint32_t kEscIsGPUAccessible = 0x2a;  // in 0, out 12
constexpr uint32_t kEscActivateClient = 0x34;   // in 32, out 0
constexpr uint32_t kEscPMRequest = 0x53;        // in 112, out 72
constexpr uint32_t kClientJpeg = 21;            // PEM_ClockChange case 21
constexpr uint32_t kClientVcn0 = 28;    // what Apple sends, for reference
constexpr uint32_t kRequestClocks = 1;  // reqID Apple's setClocks sends
constexpr uint32_t kPmFlags = 1;  // setClocks: 1, or 4 for one kind of session;
                                  // bit 0x20 would ask for JPEG DPG mode
constexpr uint32_t kPmRequestTag = 0x5c;  // setClocks: payload +4

struct Header {       // 16 bytes in front of every escape
  uint32_t size;      // 16
  uint32_t code;      // kEscapeCode | index
  uint64_t reserved;  // 0
};

struct PmRequestIn {  // escape 0x53: header + 112
  Header header;
  uint32_t size;        // +0   112
  uint32_t tag;         // +4   0x5c
  uint64_t context;     // +8   the client's handle: any value nobody else uses
  uint32_t clientType;  // +16
  uint32_t requestId;   // +20
  uint32_t pmFlags;     // +24
  uint32_t clocks[21];  // +28..+111: minSclk, minMclk, floors and ceilings; all
                        // 0 here
};
struct PmRequestOut {  // 72 bytes
  uint32_t size;       // +0   72
  uint32_t valid;      // +4   1
  uint32_t unused8;
  uint32_t resultSize;  // +12  56
  uint32_t
      result;  // +16  0 = accepted, 20 = clocks refused, 21 = no client slot
  uint32_t words[13];
};

struct ActivateIn {  // escape 0x34: header + 32
  Header header;
  uint32_t size;         // +0   32
  uint32_t clientType;   // +4
  uint32_t contextId;    // +8   only used when the handle is 0
  uint32_t activate;     // +12  1 or 0
  uint32_t flags;        // +16  0: a deactivated client is freed
  uint32_t contextLow;   // +20  the handle, not aligned
  uint32_t contextHigh;  // +24
  uint32_t pad;          // +28
};

struct AccessOut {      // escape 0x2a: 12 bytes
  uint32_t size;        // 12
  uint32_t accessible;  // 1: the GPU is up
  uint32_t unused;
};

// What AMDGraphicsAccelerator::sendPMCommand takes.
struct Args {
  const void* in;
  uint64_t inSize;
  void* out;
  uint64_t* outSize;
};

static_assert(sizeof(Header) == 16, "header");
static_assert(sizeof(PmRequestIn) == 128 &&
                  offsetof(PmRequestIn, context) == 24 &&
                  offsetof(PmRequestIn, clientType) == 32,
              "PMRequest input");
static_assert(sizeof(PmRequestOut) == 72, "PMRequest output");
static_assert(sizeof(ActivateIn) == 48 &&
                  offsetof(ActivateIn, contextLow) == 36,
              "ActivateClient input");
static_assert(sizeof(AccessOut) == 12, "IsGPUAccessible output");
static_assert(sizeof(Args) == 32, "sendPMCommand arguments");

constexpr Header header(uint32_t index) {
  return Header{16, kEscapeCode | index, 0};
}

constexpr PmRequestIn pmRequest(uint64_t context) {
  PmRequestIn r{};
  r.header = header(kEscPMRequest);
  r.size = 112;
  r.tag = kPmRequestTag;
  r.context = context;
  r.clientType = kClientJpeg;
  r.requestId = kRequestClocks;
  r.pmFlags = kPmFlags;
  return r;
}

constexpr ActivateIn activate(uint64_t context, bool on) {
  ActivateIn a{};
  a.header = header(kEscActivateClient);
  a.size = 32;
  a.clientType = kClientJpeg;
  a.activate = on ? 1 : 0;
  a.contextLow = static_cast<uint32_t>(context);
  a.contextHigh = static_cast<uint32_t>(context >> 32);
  return a;
}

}  // namespace jw
