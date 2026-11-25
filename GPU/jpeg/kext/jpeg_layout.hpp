//
//  jpeg_layout.hpp - offsets inside AMDRadeonX6000HWLibs' objects (25G342).
//
//  Each offset names the function whose Hex-Rays output shows it; addresses are
//  those of the KDK binary. The maintainer's static check compares this file
//  with the output of Hex-Rays (IDA) for the same functions.
//
#pragma once
#include <stddef.h>
#include <stdint.h>

// clang-format off: a table, one offset per line with the function that shows it

namespace jl {

// AmdTtlServices (C++ object)
constexpr size_t kTtlHandle = 56;      // ttl_initialize(.., this + 56)        initialize 0xaeac0
constexpr size_t kTtlQueueSlots = 2424;  // this + 2424 + 32*type + 8*index     createEngine 0xb1610
constexpr size_t kTtlGartInfo = 1256;  // qwords 157..160                      getNonLocalMemoryInfo 0xabc30
constexpr size_t queueSlot(unsigned type, unsigned index) {
  return kTtlQueueSlots + 32 * type + 8 * index;
}

// AMD_SWIP_QUEUE_TYPE 5 -> TTL engine type 2 = JPEG decode   (table 0x509e90)
constexpr int kQueueTypeJpegDecode = 5;
// AMD_TTL_ENGINE_EVENT                                        TtlRtsNotifyEngine 0x91dd0
constexpr uint32_t kEventStart = 0;
constexpr uint32_t kEventStop = 1;
// _TtlCreateEngineInput {frame bytes, frame count}; Apple's decode queue uses
// {0x100, 0x100}                                              startMMEngineQueues 0xaf5e0
constexpr uint32_t kFrameBytes = 256;
constexpr uint32_t kFrameCount = 256;

// ipi JPEG context (232 bytes)                                ipiJpegCreateContext 0xa6ed5
constexpr size_t kIpiJpegCtx = 40;       // jpeg module context   ipiJpegCreateQueue 0xa71ed
constexpr size_t kIpiCreateQueue = 56;   // jpeg_create_queue     ipiJpegCreateQueue 0xa71ed
constexpr size_t kIpiStartQueue = 72;    // jpeg_start_queue      ipiJpegStartQueue 0xa7317
constexpr size_t kIpiStopQueue = 80;     // jpeg_stop_queue       ipiJpegStopQueue 0xa7338
constexpr size_t kIpiQueryStatus = 96;   // jpeg_query_queue_status  ipiJpegQueryEngineState 0xa737a

// jpeg module context (64 bytes)                              jpeg_sw_init 0x3be36
constexpr size_t kCtxCgs = 0;
constexpr size_t kCtxEngine = 16;
constexpr size_t kCtxQueueMgr = 24;

// jpeg engine (680 bytes)                                     jpeg_engine_sw_init 0x3cea8
constexpr size_t kEngInit = 0;            // jpeg_start_queue 0x3cb38
constexpr size_t kEngCfgPG = 4;           // PP_EnableJPEGPG
constexpr size_t kEngCfgDPG = 8;          // EnableJPEGDPG
constexpr size_t kEngCfgCG = 12;          // EnableJPEGCG
constexpr size_t kEngCfgSecureLoad = 16;  // EnableJPEGSecureLoad
constexpr size_t kEngCfgDoorbell = 20;    // EnableJPEGDOORBELL
constexpr size_t kEngRegBase0 = 68;       // jpeg_internal_cgs_read_register 0x3c211
constexpr size_t kEngRegBase1 = 72;
constexpr size_t kEngVersion = 632;       // jpeg_get_ip_version 0x3c4db
constexpr size_t kEngTiling = 636;        // jpeg_engine_hw_init 0x3d042
constexpr uint32_t kVersionVcn30 = 0x30000;

// jpeg queue manager (48 bytes)                               jpeg_queue_manager_2_0_initialize 0x3e214
constexpr size_t kMgrActive = 0;          // jpeg_start_queue 0x3cb38
constexpr size_t kMgrDecodeOk = 4;
constexpr size_t kMgrDecodeQueue = 16;    // jpeg_create_queue 0x3c760

// jpeg queue (208 bytes)                                      jpeg_create_queue 0x3c760
constexpr size_t kQFlags = 0;             // bit 0 started, bit 1 page fault
constexpr size_t kQType = 16;
constexpr size_t kQRingSize = 24;         // queue_jpeg_decode_2_0_init_ring 0x3d634
constexpr size_t kQGpuAddr = 40;
constexpr size_t kQCur = 72;              // queue_jpeg_decode_2_0_submit_frame 0x3dc10
constexpr size_t kQFrameCount = 76;
constexpr size_t kQFrameBytes = 80;

// Registers, as (set, offset) of jpeg_internal_cgs_read_register. The set is
// the register's BASE_IDX in Linux's vcn_3_0_0_offset.h, where the names come
// from (name, offset and BASE_IDX of every entry were checked against it).
struct Reg {
  const char* name;
  uint32_t set;
  uint32_t offset;
};
constexpr Reg kPowerRegs[]{
    {"UVD_PGFSM_STATUS", 1, 0x001},
    {"UVD_JPEG_POWER_STATUS", 1, 0x00a},
};
constexpr Reg kRingRegs[]{
    {"UVD_JRBC_RB_WPTR", 0, 0x100},
    {"UVD_JRBC_RB_CNTL", 0, 0x101},
    {"UVD_JRBC_STATUS", 0, 0x109},
    {"UVD_JRBC_RB_RPTR", 0, 0x10a},
    {"UVD_JRBC_RB_SIZE", 0, 0x113},
    {"UVD_LMI_JRBC_RB_64BIT_BAR_LOW", 0, 0x166},
    {"UVD_LMI_JRBC_RB_64BIT_BAR_HIGH", 0, 0x167},
    {"UVD_JMI_CNTL", 0, 0x192},
    {"JPEG_SYS_INT_EN", 0, 0x1c1},
    {"JPEG_CGC_GATE", 0, 0x1e0},
    {"JPEG_CGC_CTRL", 0, 0x1e1},
    {"JPEG_DEC_GFX10_ADDR_CONFIG", 0, 0x0a6},
};

// ---- the decode job (kern_start.cpp) ---------------------------------------------
// ipi JPEG context
constexpr size_t kIpiSubmitFrame = 136;   // jpeg_submit_frame                              ipiJpegSubmitFrame 0xa7542
// jpeg module context
constexpr size_t kCtxDoorbell = 40;       // pointer the write pointer is stored through   queue_jpeg_decode_2_0_submit_frame 0x3dc10
// jpeg queue
constexpr size_t kQMemType = 48;          // queue_jpeg_decode_2_0_init_ring 0x3d634
constexpr size_t kQRingCpu = 56;
constexpr size_t kQHandle = 64;
constexpr size_t kQSubmit = 144;          // jpeg_submit_frame 0x3ca68
// jpeg_internal_cgs_alloc_memory(cgs, size, align, type, &gpu, &handle, flag)   0x3c117
constexpr uint32_t kMemTypeRing = 2;      // the type and alignment the ring itself is allocated with
constexpr int32_t kMemAlign = 256;

// One allocation, made right after the queue (see kern_start.cpp for why then),
// and only if at least kGartSpare bytes of the GART are still unused by then
// (AMDHWGart::setParameters wants total > used; this Mac's GART is 0x40200000).
constexpr uint64_t kGartSpare = 0x10000000;
constexpr uint32_t kPoolBytes = 0x500000;
constexpr uint32_t kPoolIb = 0x000000;         // 4 KiB
constexpr uint32_t kPoolFence = 0x001000;      // 4 KiB
constexpr uint32_t kPoolBitstream = 0x010000;
constexpr uint32_t kBitstreamCap = 0x100000;
constexpr uint32_t kPoolSurface = 0x110000;
constexpr uint32_t kSurfaceCap = 0x3E0000;
constexpr uint32_t kPoolGuard = 0x4F0000;      // filled with kGuardByte, checked after every decode
constexpr uint32_t kGuardBytes = 0x010000;
constexpr uint8_t kGuardByte = 0xA5;
constexpr uint8_t kSurfaceFill = 0xEE;         // what the surface holds before the block writes

// The register the ring and IB tests write (Linux uses the same one).
constexpr Reg kTestReg{"UVD_JPEG_PITCH", 0, 0x09f};
// Read after every job; same order as jp::kRegNames (jpeg_proto.hpp).
constexpr Reg kJobRegs[]{
    {"UVD_JRBC_RB_WPTR", 0, 0x100},
    {"UVD_JRBC_RB_RPTR", 0, 0x10a},
    {"UVD_JRBC_STATUS", 0, 0x109},
    {"UVD_JPEG_CNTL", 0, 0x080},
    {"UVD_JPEG_RB_WPTR", 0, 0x082},
    {"UVD_JPEG_RB_RPTR", 0, 0x083},
    {"UVD_JPEG_INT_EN", 0, 0x08a},
    {"UVD_JPEG_INT_STAT", 0, 0x08b},
    {"UVD_JPEG_OUTBUF_WPTR", 0, 0x09d},
    {"UVD_JPEG_PITCH", 0, 0x09f},
    {"UVD_JPEG_UV_PITCH", 0, 0x0a0},
    {"UVD_JPEG_POWER_STATUS", 1, 0x00a},
};

}  // namespace jl
// clang-format on
