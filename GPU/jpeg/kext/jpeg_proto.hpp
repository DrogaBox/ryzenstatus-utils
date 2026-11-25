//
//  jpeg_proto.hpp - the state bits, job modes and the result of one job of
//  VCNJpeg. No kernel parts: the kext, the host tests and the test tools share
//  it. The state bits are the ones the door's INFO answers with (jpeg_app.h
//  JA_STATE_*).
//
#pragma once
#include <stdint.h>

namespace jp {

constexpr uint32_t kProtocol = 1;

enum State : uint32_t {
  kStatePool = 1 << 0,     // buffers were allocated when the driver started
  kStateCreated = 1 << 1,  // the JPEG queue exists
  kStateStarted = 1 << 2,  // the queue is started (block powered)
  kStateStuck =
      1 << 3,  // a job timed out or wrote too far: no more jobs until a restart
  kStateLoaded = 1 << 4,   // a JPEG is loaded
  kStateDecoded = 1 << 5,  // the surface holds the result of a decode
};

enum Mode : uint32_t {
  kModeRingTest = 1,  // one register write straight in the ring
  kModeIbTest = 2,    // the same write through an IB, with a fence
  kModeDecode = 3,    // decode the loaded JPEG
};

enum Flags : uint32_t {
  kFlagDryRun = 1 << 0,  // build everything, submit nothing
  kFlagWptrRegister =
      1
      << 1,  // publish the write pointer through the register, not the doorbell
};

enum class Status : uint32_t {
  Ok = 0,
  BuiltOnly,  // dry run: frame and IB are in the result, nothing was sent
  NotReady,   // no buffers, no queue, queue not started, or stuck
  NothingLoaded,
  BadArgument,
  CheckFailed,  // the driver's tables are not the expected ones any more
  SubmitFailed,
  Timeout,       // the job did not finish; the queue is now marked stuck
  WrongValue,    // the test register does not hold the value written
  GuardDamaged,  // the block wrote past the surface
};

constexpr uint32_t kResultMagic = 0x4a504752;  // "JPGR"
constexpr uint32_t kRegCount = 12;

// Registers read after each job, by index into Result::regs (the kext's list
// in jpeg_layout.hpp is in the same order).
constexpr const char* kRegNames[kRegCount] = {
    "UVD_JRBC_RB_WPTR", "UVD_JRBC_RB_RPTR",  "UVD_JRBC_STATUS",
    "UVD_JPEG_CNTL",    "UVD_JPEG_RB_WPTR",  "UVD_JPEG_RB_RPTR",
    "UVD_JPEG_INT_EN",  "UVD_JPEG_INT_STAT", "UVD_JPEG_OUTBUF_WPTR",
    "UVD_JPEG_PITCH",   "UVD_JPEG_UV_PITCH", "UVD_JPEG_POWER_STATUS",
};

struct Result {
  uint32_t magic;
  uint32_t protocol;
  uint32_t mode;
  uint32_t flags;
  uint32_t status;        // Status
  uint32_t submitReturn;  // what AmdTtlServices::submitFrame returned
  uint32_t elapsedMs;     // from submit to completion (or to giving up)
  uint32_t seq;           // fence value asked for
  uint32_t fenceValue;    // fence memory at the end
  uint32_t testBefore;    // UVD_JPEG_PITCH before a ring or IB test
  uint32_t testAfter;     // and after it
  uint32_t width, height;
  uint32_t pitch, alignedHeight, chromaOffset, surfaceBytes;
  uint32_t bitstreamBytes;
  uint32_t ibWords;
  uint32_t regs[kRegCount];
  uint32_t testWanted;  // value the ring or IB test writes
  uint32_t format;      // surface written: 0 NV12 (4:2:0), 1 YUYV (4:2:2)
  uint64_t ringGpu, ibGpu, fenceGpu, bitstreamGpu, surfaceGpu;
  uint32_t frame[64];
  uint32_t ib[128];
};
static_assert(sizeof(Result) == 944, "Result layout");

}  // namespace jp
