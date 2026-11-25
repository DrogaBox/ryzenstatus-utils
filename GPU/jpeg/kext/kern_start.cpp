//
//  kern_start.cpp - VCNJpeg, a Lilu plugin: JPEG and Motion JPEG decoding on
//  the JPEG block of the VCN of an AMD Radeon RX 6800 / 6800 XT / 6900 XT
//  (Navi 21), for the VideoToolbox plug-in in decode/jpeg.
//
//  Apple's AMDRadeonX6000HWLibs carries the driver of the JPEG block (its ring,
//  JRBC, and the queue code) but never creates its queue. This plugin does, and
//  lets any process decode through it:
//
//  1. When AMDRadeonX6000HWLibs loads it checks the image's LC_UUID against the
//     one build that was read in IDA (macOS 26.7.3, 25G342), resolves the
//     functions it needs by symbol and compares each one's place in the image
//     and its first 16 bytes with the values of that build (hwlibs_expect.hpp,
//     generated from the KDK by tools/gen_expect.py). The same for the two
//     functions of AMDRadeonX6000 it uses. Anything different: it does nothing.
//
//  2. It routes AmdTtlServices::startMMEngineQueues(), where the driver creates
//     its VCN queues while it starts. After the original it creates the JPEG
//     decode queue the same way (createEngine(this, 5, 0, {256, 256})) and
//     takes one block of buffers from the JPEG module's own allocator: IB,
//     fence, bitstream, picture and a guard area. Both have to happen there and
//     not later: the queue's ring and the block get GART addresses from a bump
//     pointer that the accelerator reads only once, afterwards, before it hands
//     out the rest of the GART itself. Memory taken later sits on addresses the
//     accelerator owns; resizing the block after start hung the GPU (SDMA0) on
//     2026-11-24. Creating the queue touches no JPEG register.
//     AmdTtlServices::stopMMEngineQueues (routed too) stops and destroys the
//     queue and gives the block back before Apple's queues go.
//
//  3. The door: it routes AMDRadeonX6000_AMDAccelVideoContext::sendPMCommand,
//     selector 258 of the accelerator's video context, which every process
//     that decodes video may open, and answers the requests that carry the
//     header of decode/jpeg/jpeg_app.h (apps_handler.hpp). Every other request
//     goes to Apple's function untouched.
//
//  4. Power only while decoding: the first picture a client asks to decode
//     powers the block (PowerPlay client 21, jpeg_power.hpp, as Apple's kernel
//     asks for a VCN session) and starts its queue (notifyEngine start, which
//     powers it up and programs the ring). Two seconds without a request of any
//     client (idle_logic.hpp, a thread_call) stop the queue and give the power
//     back; the next picture starts both again.
//
//  A job that does not finish (timeout) or writes past its picture marks the
//  decoder stuck until the next restart: INFO says so, the plug-in refuses new
//  sessions and VideoToolbox uses Apple's software decoder.
//
//  It never sends anything to the VCN decode queue.
//
//  State: the dictionary "VCNJpeg" on IOResources (ioreg -rd1 -c IOResources |
//  grep -A12 VCNJpeg): State, Version, Build, PoolBytes, Powered, Stuck, Jobs,
//  PowerOns, Failures.
//
//  Boot args: -vcnjpegoff disables the plugin; vcnjpegpool=<MiB> sizes the
//  block (8 to 128, default 128: a 48-megapixel 4:2:0 picture fits; a 4K 4:2:2
//  frame needs about 24); -vcnjpegdbg / -vcnjpegbeta are Lilu's usual switches.
//
#include <IOKit/IOLib.h>
#include <IOKit/IOLocks.h>
#include <IOKit/IOService.h>
#include <kern/clock.h>
#include <kern/thread_call.h>
#include <libkern/c++/OSDictionary.h>
#include <libkern/c++/OSNumber.h>
#include <libkern/c++/OSString.h>
#include <mach-o/loader.h>
#include <pexpert/pexpert.h>
#include <sys/systm.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshadow"
#include <Headers/kern_api.hpp>
#include <Headers/kern_patcher.hpp>
#include <Headers/kern_util.hpp>
#include <Headers/plugin_start.hpp>
#pragma clang diagnostic pop

#include "hwlibs_expect.hpp"
#include "idle_logic.hpp"
#include "jpeg_app.h"
#include "jpeg_cmds.hpp"
#include "jpeg_layout.hpp"
#include "jpeg_power.hpp"
#include "jpeg_proto.hpp"

static_assert(jp::kStatePool == JA_STATE_POOL &&
                  jp::kStateCreated == JA_STATE_CREATED &&
                  jp::kStateStarted == JA_STATE_STARTED &&
                  jp::kStateStuck == JA_STATE_STUCK,
              "the door's state bits");

// ---- functions of AMDRadeonX6000HWLibs, by their Hex-Rays prototypes --------
// uint32 AmdTtlServices::startMMEngineQueues(this)                    0xaf5e0
using t_startMM = uint32_t (*)(void* ttlServices);
// IOReturn AmdTtlServices::createEngine(this, AMD_SWIP_QUEUE_TYPE,
//                                       uint index, _TtlCreateEngineInput*)
//                                       0xb1610
using t_createEngine = uint32_t (*)(void* ttlServices, int queueType,
                                    uint32_t index, const uint32_t* input);
// IOReturn AmdTtlServices::notifyEngine(this, AMD_SWIP_QUEUE_TYPE, uint index,
//                                       AMD_TTL_ENGINE_EVENT)         0xb1530
using t_notifyEngine = uint32_t (*)(void* ttlServices, uint32_t queueType,
                                    uint32_t index, uint32_t event);
// uint32 AmdTtlServices::stopMMEngineQueues(this)                     0xaf9b0
using t_stopMM = uint32_t (*)(void* ttlServices);
// IOReturn AmdTtlServices::stopEngineQueue(this, AMD_SWIP_QUEUE_TYPE,
//                                          uint index)                0xb1c80
using t_stopEngineQueue = uint32_t (*)(void* ttlServices, int queueType,
                                       uint32_t index);
// void* ttlGetIpi(ttl handle)                                         0x90fd2
using t_ttlGetIpi = void* (*)(void* ttlHandle);
// void* IpiGetJpegContext(ipi)                                        0xa6ea5
using t_getJpegContext = void* (*)(void* ipi);
// uint32 jpeg_internal_cgs_read_register(jpeg ctx, uint set, int offset)
// 0x3c211
using t_readReg = uint64_t (*)(void* jpegCtx, uint32_t set, int32_t offset);
// IOReturn AmdTtlServices::submitFrame(this, AMD_SWIP_QUEUE_TYPE, uint index,
//                                      void* frame)                    0xb0840
using t_submitFrame = uint32_t (*)(void* ttlServices, uint32_t queueType,
                                   uint32_t index, void* frame);
// void* jpeg_internal_cgs_alloc_memory(cgs, size, align, type, &gpuAddress,
//                                      &handle, flag)                  0x3c117
using t_allocMem = void* (*)(void* cgs, uint64_t size, int32_t align,
                             uint32_t type, uint64_t* gpuAddress,
                             uint64_t* handle, char flag);
// jpeg_internal_cgs_release_memory(cgs, cpu, size, type, gpuAddress, handle)
// 0x3c1a8
using t_releaseMem = uint64_t (*)(void* cgs, void* cpu, uint64_t size,
                                  uint32_t type, uint64_t gpuAddress,
                                  uint64_t handle);
// ---- and of AMDRadeonX6000
// ---------------------------------------------------- IOReturn
// AMDRadeonX6000_AMDGraphicsAccelerator::sendPMCommand(this, void* args) 0x656c
using t_sendPM = uint32_t (*)(void* accelerator, void* args);
// IOReturn AMDRadeonX6000_AMDAccelVideoContext::sendPMCommand(this, void* in,
//     void* out, unsigned long long inSize, unsigned long long* outSize)
//     0x280f2
using t_videoPM = IOReturn (*)(void* self, void* in, void* out, uint64_t inSize,
                               uint64_t* outSize);

static t_startMM orgStartMM = nullptr;
static t_stopMM orgStopMM = nullptr;
static t_videoPM orgVideoPM = nullptr;
static t_stopEngineQueue fnStopEngineQueue = nullptr;
static t_createEngine fnCreateEngine = nullptr;
static t_notifyEngine fnNotifyEngine = nullptr;
static t_ttlGetIpi fnTtlGetIpi = nullptr;
static t_getJpegContext fnGetJpegContext = nullptr;
static t_readReg fnReadReg = nullptr;
static t_submitFrame fnSubmitFrame = nullptr;
static t_allocMem fnAllocMem = nullptr;
static t_releaseMem fnReleaseMem = nullptr;
static t_sendPM fnSendPM = nullptr;
// the jpeg_* functions the module's own tables must point to
static mach_vm_address_t adrJpegCreateQueue = 0, adrJpegStartQueue = 0,
                         adrJpegStopQueue = 0, adrJpegQueryStatus = 0,
                         adrQueueSubmit = 0, adrJpegSubmit = 0;

static bool gResolved = false;       // every HWLibs function found and checked
static bool gPowerResolved = false;  // and both of AMDRadeonX6000
static bool gDoorRouted = false;
static IOLock* gLock = nullptr;   // guards everything below
static void* gTtl = nullptr;      // the live AmdTtlServices (one AMD GPU only)
static void* gJpegCtx = nullptr;  // jpeg module context (argument of jpeg_*)
static int gHookCalls = 0;
static bool gCreated = false;  // createEngine returned 0
static bool gStarted = false;  // the queue is started (notifyEngine start)
static bool gGone = false;     // the driver went away while the lock was held:
                               // never touch it again
static const char* gStateText = "starting";
static uint32_t gPowerOns = 0, gFailures = 0;
static int gLogs = 0;
static constexpr int kMaxLogs = 64;  // lines about failed jobs, so that a
                                     // broken stream cannot flood the log

__printflike(1, 2) static void say(const char* fmt, ...) {
  char line[300];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(line, sizeof(line), fmt, ap);
  va_end(ap);
  SYSLOG("vcnjpeg", "%s", line);
}

template <typename T>
static inline T rd(const void* base, size_t off) {
  T v;
  memcpy(&v, static_cast<const uint8_t*>(base) + off, sizeof(v));
  return v;
}

static uint64_t nowMs() {
  uint64_t t = 0, ns = 0;
  clock_get_uptime(&t);
  absolutetime_to_nanoseconds(t, &ns);
  return ns / 1000000;
}

// ---- buffers and the decode job
// ------------------------------------------------
struct Pool {
  uint32_t bytes, ib, fence, bitstream, bitstreamCap, surface, surfaceCap,
      guard, guardBytes;
};
static Pool gP{jl::kPoolBytes,     jl::kPoolIb,       jl::kPoolFence,
               jl::kPoolBitstream, jl::kBitstreamCap, jl::kPoolSurface,
               jl::kSurfaceCap,    jl::kPoolGuard,    jl::kGuardBytes};
static bool gDecodeResolved = false;
static uint8_t* gPool = nullptr;  // CPU address of the block
static uint64_t gPoolGpu = 0;
static uint64_t gPoolHandle = 0;
static bool gStuck = false;
static uint32_t gSeq = 0;
static uint32_t gJobs = 0;
static uint32_t gLoadedBytes = 0;  // padded size of the loaded JPEG
static uint32_t gLoadPos = 0;      // bytes of a JPEG received so far
static jc::StreamInfo gStream;
static jc::Layout gLayout;
static bool gDecoded = false;
static jp::Result gResult;  // scratch of the door; the lock guards it
static jidle::Idle gIdle;
static thread_call_t gIdleCall = nullptr;

static void publish(const char* state) {
  if (state != nullptr) gStateText = state;
  IOService* res = IOService::getResourceService();
  OSDictionary* d = OSDictionary::withCapacity(9);
  if (res == nullptr || d == nullptr) {
    if (d != nullptr) d->release();
    return;
  }
  auto str = [d](const char* key, const char* value) {
    OSString* s = OSString::withCString(value);
    if (s != nullptr) {
      d->setObject(key, s);
      s->release();
    }
  };
  auto num = [d](const char* key, uint64_t value) {
    OSNumber* n = OSNumber::withNumber(value, 64);
    if (n != nullptr) {
      d->setObject(key, n);
      n->release();
    }
  };
  str("State", gStateText);
  str("Version", xStringify(MODULE_VERSION));
  str("Build", hwx::kBuild);
  num("PoolBytes", gPool != nullptr ? gP.bytes : 0);
  d->setObject("Powered", gIdle.on ? kOSBooleanTrue : kOSBooleanFalse);
  d->setObject("Stuck", gStuck ? kOSBooleanTrue : kOSBooleanFalse);
  num("Jobs", gJobs);
  num("PowerOns", gPowerOns);
  num("Failures", gFailures);
  res->setProperty("VCNJpeg", d);
  d->release();
}

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

// ---- the JPEG module's tables, read from memory
// ------------------------------- Fills gJpegCtx. Every pointer is checked
// before it is followed, and the module's function table has to point at the
// jpeg_* functions resolved by symbol, which proves the layout before anything
// is called through it.
static bool findJpegModule(void* ttl, bool quiet) {
  void* handle = rd<void*>(ttl, jl::kTtlHandle);
  void* ipi = handle != nullptr ? fnTtlGetIpi(handle) : nullptr;
  void* ipiJpeg = ipi != nullptr ? fnGetJpegContext(ipi) : nullptr;
  if (ipiJpeg == nullptr) {
    if (!quiet) say("check: no JPEG module on this device");
    return false;
  }
  if (rd<mach_vm_address_t>(ipiJpeg, jl::kIpiCreateQueue) !=
          adrJpegCreateQueue ||
      rd<mach_vm_address_t>(ipiJpeg, jl::kIpiStartQueue) != adrJpegStartQueue ||
      rd<mach_vm_address_t>(ipiJpeg, jl::kIpiStopQueue) != adrJpegStopQueue ||
      rd<mach_vm_address_t>(ipiJpeg, jl::kIpiQueryStatus) !=
          adrJpegQueryStatus) {
    if (!quiet)
      say("check: the JPEG module's function table is not the studied one");
    return false;
  }
  void* ctx = rd<void*>(ipiJpeg, jl::kIpiJpegCtx);
  if (ctx == nullptr || rd<void*>(ctx, jl::kCtxCgs) == nullptr ||
      rd<void*>(ctx, jl::kCtxEngine) == nullptr ||
      rd<void*>(ctx, jl::kCtxQueueMgr) == nullptr) {
    if (!quiet) say("check: JPEG context incomplete");
    return false;
  }
  gJpegCtx = ctx;
  return true;
}

static uint32_t readReg(const jl::Reg& r) {
  return static_cast<uint32_t>(
      fnReadReg(gJpegCtx, r.set, static_cast<int32_t>(r.offset)));
}

// Takes the block of buffers right after the queue was created (lock held).
static void poolTake(void* ttl) {
  // The accelerator sizes its part of the GART from these two numbers later and
  // refuses to start unless something is left: take the block only when it
  // leaves at least kGartSpare free on top of it.
  uint64_t gartSize = rd<uint64_t>(ttl, jl::kTtlGartInfo + 8);
  uint64_t gartUsed = rd<uint64_t>(ttl, jl::kTtlGartInfo + 24);
  if (gartUsed > gartSize || gartSize - gartUsed < jl::kGartSpare + gP.bytes) {
    say("GART has 0x%llx of 0x%llx in use, too little left for 0x%x bytes of "
        "buffers: decoder off",
        gartUsed, gartSize, gP.bytes);
    return;
  }
  void* cgs = rd<void*>(gJpegCtx, jl::kCtxCgs);
  uint64_t gpu = 0, handle = 0;
  void* cpu = fnAllocMem(cgs, gP.bytes, jl::kMemAlign, jl::kMemTypeRing, &gpu,
                         &handle, 0);
  if (cpu == nullptr || gpu == 0) {
    say("buffer allocation failed (cpu %d gpu 0x%llx): decoder off",
        cpu != nullptr, gpu);
    return;
  }
  gPool = static_cast<uint8_t*>(cpu);
  gPoolGpu = gpu;
  gPoolHandle = handle;
  memset(gPool, 0, gP.bytes);
  memset(gPool + gP.guard, jl::kGuardByte, gP.guardBytes);
  say("0x%x bytes of buffers at GPU address 0x%llx (JPEG up to 0x%x, picture "
      "up to 0x%x); GART 0x%llx of 0x%llx in use before",
      gP.bytes, gpu, gP.bitstreamCap - 128, gP.surfaceCap, gartUsed, gartSize);
}

static uint32_t decodeState() {
  uint32_t s = 0;
  if (gPool != nullptr) s |= jp::kStatePool;
  if (gCreated) s |= jp::kStateCreated;
  if (gStarted) s |= jp::kStateStarted;
  if (gStuck) s |= jp::kStateStuck;
  if (gLoadedBytes != 0) s |= jp::kStateLoaded;
  if (gDecoded) s |= jp::kStateDecoded;
  return s;
}

#include "decode_accept.hpp"

// The queue as it is now, or null when anything about it or about the path a
// frame takes to it (AmdTtlServices::submitFrame -> ipi -> jpeg_submit_frame ->
// the queue's own submit function) is not what was studied.
static void* decodeQueue() {
  void* ipiJpeg =
      fnGetJpegContext(fnTtlGetIpi(rd<void*>(gTtl, jl::kTtlHandle)));
  if (ipiJpeg == nullptr ||
      rd<mach_vm_address_t>(ipiJpeg, jl::kIpiSubmitFrame) != adrJpegSubmit)
    return nullptr;
  void* mgr = rd<void*>(gJpegCtx, jl::kCtxQueueMgr);
  void* queue = rd<void*>(mgr, jl::kMgrDecodeQueue);
  if (queue == nullptr) return nullptr;
  if ((rd<uint32_t>(queue, jl::kQFlags) & 1) == 0) return nullptr;
  if (rd<mach_vm_address_t>(queue, jl::kQSubmit) != adrQueueSubmit)
    return nullptr;
  if (rd<uint32_t>(queue, jl::kQFrameBytes) != jc::kFrameWords * 4)
    return nullptr;
  if (rd<void*>(queue, jl::kQRingCpu) == nullptr) return nullptr;
  if (rd<void*>(gTtl, jl::queueSlot(jl::kQueueTypeJpegDecode, 0)) == nullptr)
    return nullptr;
  return queue;
}

static const char* statusText(uint32_t s) {
  switch (static_cast<jp::Status>(s)) {
    case jp::Status::Ok:
      return "ok";
    case jp::Status::BuiltOnly:
      return "built only";
    case jp::Status::NotReady:
      return "not ready";
    case jp::Status::NothingLoaded:
      return "no JPEG loaded";
    case jp::Status::BadArgument:
      return "bad argument";
    case jp::Status::CheckFailed:
      return "driver tables not as expected";
    case jp::Status::SubmitFailed:
      return "submitFrame failed";
    case jp::Status::Timeout:
      return "timeout, decoder stuck";
    case jp::Status::WrongValue:
      return "wrong value";
    case jp::Status::GuardDamaged:
      return "guard area damaged, decoder stuck";
  }
  return "?";
}

// A job that did not succeed: counted, and the first kMaxLogs logged with the
// block's registers.
static void logResult(const jp::Result* r) {
  gFailures++;
  if (gLogs >= kMaxLogs) return;
  gLogs++;
  say("job %u: %s; submit 0x%x, %u ms, fence %u; JRBC wptr 0x%x rptr 0x%x "
      "status 0x%x; JPEG cntl 0x%x int_stat 0x%x power 0x%x",
      r->seq, statusText(r->status), r->submitReturn, r->elapsedMs,
      r->fenceValue, r->regs[0], r->regs[1], r->regs[2], r->regs[3], r->regs[7],
      r->regs[11]);
}

// Builds and submits the decode of the loaded JPEG and waits for it. Lock held.
// The frame and the IB are those of the test kext (jpeg_cmds.hpp), checked
// against Apple's own command builder and against Mesa's (tests/run.sh).
static void decodeRun(uint32_t mode, uint32_t flags, jp::Result* r) {
  memset(r, 0, sizeof(*r));
  r->magic = jp::kResultMagic;
  r->protocol = jp::kProtocol;
  r->mode = mode;
  r->flags = flags;
  auto finish = [r](jp::Status s) { r->status = static_cast<uint32_t>(s); };
  if (mode != jp::kModeDecode) return finish(jp::Status::BadArgument);
  if (!gDecodeResolved || gPool == nullptr || gTtl == nullptr ||
      gJpegCtx == nullptr || !gCreated || !gStarted || gStuck)
    return finish(jp::Status::NotReady);
  if (gLoadedBytes == 0) return finish(jp::Status::NothingLoaded);

  void* mgr = rd<void*>(gJpegCtx, jl::kCtxQueueMgr);
  void* anyQueue = rd<void*>(mgr, jl::kMgrDecodeQueue);
  r->ringGpu = anyQueue ? rd<uint64_t>(anyQueue, jl::kQGpuAddr) : 0;
  r->ibGpu = gPoolGpu + gP.ib;
  r->fenceGpu = gPoolGpu + gP.fence;
  r->bitstreamGpu = gPoolGpu + gP.bitstream;
  r->surfaceGpu = gPoolGpu + gP.surface;
  uint32_t seq = gSeq + 1;
  r->seq = seq;

  jc::DecodeParams d =
      jc::decodeParams(gLayout, r->bitstreamGpu, gLoadedBytes, r->surfaceGpu);
  r->ibWords = jc::buildDecodeIb(r->ib, jc::kIbMaxWords, d);
  r->width = gStream.width;
  r->height = gStream.height;
  r->pitch = gLayout.pitch;
  r->alignedHeight = gLayout.alignedHeight;
  r->chromaOffset = gLayout.chromaOffset;
  r->surfaceBytes = gLayout.bytes;
  r->format = static_cast<uint32_t>(gLayout.chroma);
  r->bitstreamBytes = gLoadedBytes;
  if (r->ibWords == 0 || r->ringGpu == 0 ||
      !jc::buildJobFrame(r->frame, r->ringGpu, r->ibGpu, r->ibWords, seq,
                         r->fenceGpu))
    return finish(jp::Status::BadArgument);

  if (!findJpegModule(gTtl, true)) return finish(jp::Status::CheckFailed);
  void* queue = decodeQueue();
  if (queue == nullptr) return finish(jp::Status::CheckFailed);
  gSeq = seq;
  gJobs++;
  volatile uint32_t* fence =
      reinterpret_cast<volatile uint32_t*>(gPool + gP.fence);
  memcpy(gPool + gP.ib, r->ib, r->ibWords * 4);
  fence[0] = 0;
  fence[1] = 0;
  memset(gPool + gP.surface, jl::kSurfaceFill, gLayout.bytes);
  gDecoded = false;
  // With the flag the write pointer goes through the register: the driver
  // reads its own EnableJPEGDOORBELL setting at every submit, so it is cleared
  // for this one call and put back.
  void* engine = rd<void*>(gJpegCtx, jl::kCtxEngine);
  uint32_t* doorbell = reinterpret_cast<uint32_t*>(
      static_cast<uint8_t*>(engine) + jl::kEngCfgDoorbell);
  uint32_t doorbellSaved = *doorbell;
  if ((flags & jp::kFlagWptrRegister) != 0) *doorbell = 0;
  uint64_t t0 = nowMs();
  uint32_t rc = fnSubmitFrame(gTtl, jl::kQueueTypeJpegDecode, 0, r->frame);
  *doorbell = doorbellSaved;
  r->submitReturn = rc;
  if (rc != 0) return finish(jp::Status::SubmitFailed);

  // Completion is polled on the fence: nothing answers the block's interrupt.
  bool done = false;
  while (true) {
    if (fence[0] == seq) {
      done = true;
      break;
    }
    if (nowMs() - t0 >= 3000) break;
    IOSleep(1);
  }
  r->elapsedMs = static_cast<uint32_t>(nowMs() - t0);
  r->fenceValue = fence[0];
  if (!done) {
    for (size_t i = 0; i < jp::kRegCount; i++)
      r->regs[i] = readReg(jl::kJobRegs[i]);
    gStuck = true;
    return finish(jp::Status::Timeout);
  }
  const uint8_t* guard = gPool + gP.guard;
  for (uint32_t i = 0; i < gP.guardBytes; i++) {
    if (guard[i] != jl::kGuardByte) {
      gStuck = true;  // nothing more through this queue until the next restart
      return finish(jp::Status::GuardDamaged);
    }
  }
  gDecoded = true;
  finish(jp::Status::Ok);
}

// ---- power: PowerPlay client 21, as Apple's kernel asks for a VCN session
// ----
static uint64_t gPowerContext =
    0;  // the client's handle: the address of this variable
static bool gPowerCreated = false;  // PMRequest was accepted: a client exists

// The accelerator, retained, when the registry holds exactly one.
static IOService* powerCopyAccelerator() {
  OSDictionary* match =
      IOService::serviceMatching("AMDRadeonX6000_AMDGraphicsAccelerator");
  if (match == nullptr) return nullptr;
  OSIterator* it = IOService::getMatchingServices(match);
  match->release();
  if (it == nullptr) return nullptr;
  IOService* found = nullptr;
  unsigned count = 0;
  while (OSObject* o = it->getNextObject()) {
    count++;
    if (found == nullptr) found = OSDynamicCast(IOService, o);
  }
  if (count != 1 || found == nullptr ||
      found->metaCast("AMDRadeonX6000_AMDGraphicsAccelerator") == nullptr) {
    it->release();
    say("power: %u accelerator(s) found, need exactly one", count);
    return nullptr;
  }
  found->retain();
  it->release();
  return found;
}

static uint32_t powerSend(IOService* accel, const void* in, uint64_t inSize,
                          void* out, uint64_t* outSize) {
  jw::Args args{in, inSize, out, outSize};
  return fnSendPM(accel, &args);
}

// Creates and activates the client. False when PowerPlay did not take it; a
// client it created is given back by powerGiveBack.
static bool powerAsk() {
  IOService* accel = powerCopyAccelerator();
  if (accel == nullptr) return false;
  bool ok = false;
  jw::Header q = jw::header(jw::kEscIsGPUAccessible);
  jw::AccessOut a{sizeof(jw::AccessOut), 0, 0};
  uint64_t aSize = sizeof(a);
  uint32_t rc = powerSend(accel, &q, sizeof(q), &a, &aSize);
  if (rc == 0 && a.accessible != 1) {
    say("power: the GPU is not accessible now, nothing asked");
  } else {
    jw::PmRequestIn in = jw::pmRequest(gPowerContext);
    jw::PmRequestOut out{};
    uint64_t outSize = sizeof(out);
    rc = powerSend(accel, &in, sizeof(in), &out, &outSize);
    if (rc != 0 || out.result != 0) {
      say("power: PMRequest(client %u) returned 0x%x, result %u: not taken",
          jw::kClientJpeg, rc, out.result);
    } else {
      gPowerCreated = true;
      jw::ActivateIn on = jw::activate(gPowerContext, true);
      uint64_t none = 0;
      rc = powerSend(accel, &on, sizeof(on), nullptr, &none);
      if (rc != 0) say("power: ActivateClient(1) returned 0x%x", rc);
      ok = rc == 0;
    }
  }
  accel->release();
  return ok;
}

// Deactivates the client; PowerPlay frees it. Safe to repeat.
static void powerGiveBack(const char* why) {
  if (!gPowerCreated) return;
  IOService* accel = powerCopyAccelerator();
  if (accel == nullptr) return;
  jw::ActivateIn off = jw::activate(gPowerContext, false);
  uint64_t none = 0;
  uint32_t rc = powerSend(accel, &off, sizeof(off), nullptr, &none);
  accel->release();
  if (rc != 0) {
    say("%s: ActivateClient(0) returned 0x%x", why, rc);
    return;
  }
  gPowerCreated = false;
}

// ---- the block on and off
// -----------------------------------------------------
static void idleArm(uint64_t delayMs) {
  if (gIdleCall == nullptr || delayMs == 0) return;
  uint64_t deadline = 0;
  clock_interval_to_deadline(static_cast<uint32_t>(delayMs), kMillisecondScale,
                             &deadline);
  thread_call_enter_delayed(gIdleCall, deadline);
}

// Stops the queue, then gives the power back (Linux's order); both are tried
// whatever the other returned. Lock held.
static void blockOff(const char* why) {
  if (!gIdle.on) return;
  gIdle.on = false;
  if (gStarted) {
    uint32_t rc =
        findJpegModule(gTtl, true)
            ? fnNotifyEngine(gTtl, jl::kQueueTypeJpegDecode, 0, jl::kEventStop)
            : 0xffffffffu;
    if (rc != 0) say("%s: queue stop returned 0x%x", why, rc);
    gStarted = false;
  }
  powerGiveBack(why);
  publish(gStuck ? "stuck: no more jobs until the next restart"
                 : "ready, block off");
}

// Powers the block and starts its queue, unless it is on already. Lock held.
static bool blockOn() {
  if (gIdle.on) return true;
  if (gGone || gStuck || !gPowerResolved || !gCreated || gTtl == nullptr ||
      !findJpegModule(gTtl, true))
    return false;
  if (!powerAsk()) {
    powerGiveBack("power request failed");
    gFailures++;
    return false;
  }
  uint32_t rc =
      fnNotifyEngine(gTtl, jl::kQueueTypeJpegDecode, 0, jl::kEventStart);
  gStarted = true;  // even on failure, so that blockOff sends the stop
  gIdle.on = true;
  gPowerOns++;
  if (rc != 0) {
    say("queue start returned 0x%x: decoder stuck until the next restart", rc);
    gStuck = true;
    blockOff("failed start");
    return false;
  }
  publish("decoding, block on");
  return true;
}

static void idleFired(thread_call_param_t, thread_call_param_t) {
  IOLockLock(gLock);
  if (gGone) {  // the driver went away while busy: leave it alone
    IOLockUnlock(gLock);
    return;
  }
  uint64_t delay = 0;
  switch (jidle::tick(gIdle, nowMs(), &delay)) {
    case jidle::Tick::PowerOff:
      blockOff("idle");
      break;
    case jidle::Tick::Rearm:
      idleArm(delay);
      break;
    case jidle::Tick::Nothing:
      break;
  }
  IOLockUnlock(gLock);
}

// ---- the door
// -----------------------------------------------------------------
static bool appCopyIn(uint8_t* dst, uint64_t src, uint32_t bytes) {
  return copyin(static_cast<user_addr_t>(src), dst, bytes) == 0;
}
static bool appCopyOut(uint64_t dst, const uint8_t* src, uint32_t bytes) {
  return copyout(src, static_cast<user_addr_t>(dst), bytes) == 0;
}
static void appTouch() { idleArm(jidle::touch(gIdle, nowMs())); }
static bool appBlockOn() { return blockOn(); }
#include "apps_handler.hpp"

static IOReturn wrapVideoPM(void* self, void* in, void* out, uint64_t inSize,
                            uint64_t* outSize) {
  if (!appIsOurs(in, inSize)) return orgVideoPM(self, in, out, inSize, outSize);
  // Ours. It never reaches PowerPlay, whatever is wrong with it.
  if (gLock == nullptr) return kIOReturnBadArgument;
  IOLockLock(gLock);
  bool ok = !gGone && appEntry(self, in, inSize, out, outSize);
  IOLockUnlock(gLock);
  return ok ? kIOReturnSuccess : kIOReturnBadArgument;
}

// ---- driver start and stop
// ---------------------------------------------------- Runs inside
// AmdTtlServices::startMMEngineQueues, right after Apple's own queues were
// created (once per driver start; again if the driver tears down and starts
// over). Lock held.
static void onTtlReady(void* ttl, uint32_t result) {
  int call = ++gHookCalls;
  if (gTtl != nullptr || gGone) {
    say("startMMEngineQueues call %d ignored: another AmdTtlServices is in "
        "use, or the last one went away while busy (one AMD GPU only)",
        call);
    return;
  }
  if (ttl == nullptr || result != 0) {
    publish("off: Apple's video queues failed to start");
    return;
  }
  gTtl = ttl;
  if (!findJpegModule(ttl, false)) {
    publish("off: JPEG module check failed");
    return;
  }
  void* engine = rd<void*>(gJpegCtx, jl::kCtxEngine);
  void* mgr = rd<void*>(gJpegCtx, jl::kCtxQueueMgr);
  uint32_t version = rd<uint32_t>(engine, jl::kEngVersion);
  if (version != jl::kVersionVcn30) {
    say("JPEG IP version 0x%x is not the studied one (0x%x)", version,
        jl::kVersionVcn30);
    publish("off: JPEG IP version not validated");
    return;
  }
  if (rd<uint32_t>(mgr, jl::kMgrDecodeOk) != 1 ||
      rd<void*>(mgr, jl::kMgrDecodeQueue) != nullptr ||
      rd<void*>(ttl, jl::queueSlot(jl::kQueueTypeJpegDecode, 0)) != nullptr) {
    publish("off: JPEG queue state unexpected");
    return;
  }
  const uint32_t input[2]{jl::kFrameBytes, jl::kFrameCount};
  uint32_t rc = fnCreateEngine(ttl, jl::kQueueTypeJpegDecode, 0, input);
  if (rc != 0) {
    say("createEngine(JPEG decode) returned 0x%x", rc);
    publish("off: createEngine failed");
    return;
  }
  gCreated = true;
  if (gDecodeResolved) poolTake(ttl);
  publish(gPool == nullptr ? "off: no buffers" : "ready, block off");
}

static uint32_t wrapStartMM(void* ttl) {
  uint32_t result = orgStartMM(ttl);
  IOLockLock(gLock);
  onTtlReady(ttl, result);
  IOLockUnlock(gLock);
  return result;
}

// AmdTtlServices::stopMMEngineQueues is where the driver destroys its own video
// queues when it shuts the device down. The JPEG queue goes the same way just
// before: stopped if started, its buffers given back, then destroyed with the
// call Apple uses for its queues. After that nothing here points into the
// driver any more.
static uint32_t wrapStopMM(void* ttl) {
  // A job can hold the lock for up to 3 s (its timeout). If it is still held
  // after that, something is stuck inside the driver: the shutdown must not
  // wait for it. The JPEG queue is then left as it is, and the plugin never
  // touches the driver again (gGone).
  bool locked = false;
  for (int i = 0; i < 400 && !(locked = IOLockTryLock(gLock)); i++) IOSleep(10);
  if (!locked) {
    __atomic_store_n(&gGone, true, __ATOMIC_SEQ_CST);
    SYSLOG("vcnjpeg", "teardown: the decoder is still busy, JPEG queue left");
    return orgStopMM(ttl);
  }
  if (ttl != nullptr && ttl == gTtl) {
    if (gIdleCall != nullptr) thread_call_cancel(gIdleCall);
    gIdle.armed = false;
    if (gCreated) {
      if (gStarted) {
        uint32_t rc =
            fnNotifyEngine(ttl, jl::kQueueTypeJpegDecode, 0, jl::kEventStop);
        if (rc != 0) say("teardown: queue stop returned 0x%x", rc);
        gStarted = false;
      }
      if (gPool != nullptr && gJpegCtx != nullptr) {
        void* cgs = rd<void*>(gJpegCtx, jl::kCtxCgs);
        fnReleaseMem(cgs, gPool, gP.bytes, jl::kMemTypeRing, gPoolGpu,
                     gPoolHandle);
      }
      uint32_t rc = fnStopEngineQueue(ttl, jl::kQueueTypeJpegDecode, 0);
      if (rc != 0) say("teardown: JPEG queue destroy returned 0x%x", rc);
      gCreated = false;
    }
    // PowerPlay goes away with the device: the client is forgotten, not
    // released.
    gPowerCreated = false;
    gIdle.on = false;
    gPool = nullptr;
    gPoolGpu = gPoolHandle = 0;
    gLoadedBytes = gLoadPos = 0;
    gDecoded = false;
    gAppOwner = nullptr;
    gStuck = false;
    gTtl = nullptr;
    gJpegCtx = nullptr;
    publish("driver stopped its video queues");
  }
  IOLockUnlock(gLock);
  return orgStopMM(ttl);
}

// ---- load
// ---------------------------------------------------------------------
static const char* kHWLibsPaths[]{
    "/System/Library/Extensions/AMDRadeonX6000HWServices.kext/Contents/PlugIns/"
    "AMDRadeonX6000HWLibs.kext/Contents/MacOS/AMDRadeonX6000HWLibs"};
static const char* kX6000Paths[]{
    "/System/Library/Extensions/AMDRadeonX6000.kext/Contents/MacOS/"
    "AMDRadeonX6000"};
static KernelPatcher::KextInfo kKexts[]{
    {"com.apple.kext.AMDRadeonX6000HWLibs",
     kHWLibsPaths,
     arrsize(kHWLibsPaths),
     {},
     {},
     KernelPatcher::KextInfo::Unloaded},
    {"com.apple.kext.AMDRadeonX6000",
     kX6000Paths,
     arrsize(kX6000Paths),
     {},
     {},
     KernelPatcher::KextInfo::Unloaded},
};

// Finds one function by symbol and checks it against the studied build.
static mach_vm_address_t resolve(KernelPatcher& patcher, size_t index,
                                 mach_vm_address_t address, size_t size,
                                 const hwx::Function& want) {
  mach_vm_address_t found =
      patcher.solveSymbol(index, want.symbol, address, size);
  if (found == 0) {
    patcher.clearError();
    say("%s: symbol not found", want.symbol);
    return 0;
  }
  if (found != address + want.offset) {
    say("%s: at +0x%llx, expected +0x%llx", want.symbol, found - address,
        static_cast<uint64_t>(want.offset));
    return 0;
  }
  if (want.offset + sizeof(want.head) > size ||
      memcmp(reinterpret_cast<const void*>(found), want.head,
             sizeof(want.head)) != 0) {
    say("%s: first bytes differ from the studied build", want.symbol);
    return 0;
  }
  return found;
}

static void onX6000Load(KernelPatcher& patcher, size_t index,
                        mach_vm_address_t address, size_t size) {
  if (!imageHasUuid(address, size, hwx::kX6000Uuid)) {
    publish("off: AMDRadeonX6000 build not validated");
    return;
  }
  mach_vm_address_t send = resolve(patcher, index, address, size,
                                   hwx::kPowerFunctions[hwx::kSendPMCommand]);
  mach_vm_address_t door = resolve(patcher, index, address, size,
                                   hwx::kAppsFunctions[hwx::kVideoSendPM]);
  if (send == 0 || door == 0) {
    publish("off: an AMDRadeonX6000 function did not match the studied build");
    return;
  }
  fnSendPM = reinterpret_cast<t_sendPM>(send);
  gPowerContext = reinterpret_cast<uint64_t>(&gPowerContext);
  gPowerResolved = true;
  KernelPatcher::RouteRequest requests[]{
      {hwx::kAppsFunctions[hwx::kVideoSendPM].symbol, wrapVideoPM, orgVideoPM}};
  if (patcher.routeMultiple(index, requests, address, size) &&
      orgVideoPM != nullptr) {
    gDoorRouted = true;
  } else {
    say("route of the video context failed (%d): no door for apps",
        patcher.getError());
    patcher.clearError();
    publish("off: route failed");
  }
}

static void onHWLibsLoad(KernelPatcher& patcher, size_t index,
                         mach_vm_address_t address, size_t size) {
  if (!imageHasUuid(address, size, hwx::kUuid)) {
    publish("off: AMDRadeonX6000HWLibs build not validated");
    return;
  }
  mach_vm_address_t a[hwx::kCount]{};
  for (size_t i = 0; i < hwx::kCount; i++) {
    a[i] = resolve(patcher, index, address, size, hwx::kFunctions[i]);
    if (a[i] == 0) {
      publish("off: a HWLibs function did not match the studied build");
      return;
    }
  }
  mach_vm_address_t b[hwx::kDecodeCount]{};
  for (size_t i = 0; i < hwx::kDecodeCount; i++) {
    b[i] = resolve(patcher, index, address, size, hwx::kDecodeFunctions[i]);
    if (b[i] == 0) {
      publish("off: a HWLibs function did not match the studied build");
      return;
    }
  }
  fnCreateEngine = reinterpret_cast<t_createEngine>(a[hwx::kCreateEngine]);
  fnNotifyEngine = reinterpret_cast<t_notifyEngine>(a[hwx::kNotifyEngine]);
  fnTtlGetIpi = reinterpret_cast<t_ttlGetIpi>(a[hwx::kTtlGetIpi]);
  fnGetJpegContext =
      reinterpret_cast<t_getJpegContext>(a[hwx::kIpiGetJpegContext]);
  fnReadReg = reinterpret_cast<t_readReg>(a[hwx::kJpegReadRegister]);
  fnStopEngineQueue =
      reinterpret_cast<t_stopEngineQueue>(a[hwx::kStopEngineQueue]);
  adrJpegCreateQueue = a[hwx::kJpegCreateQueue];
  adrJpegStartQueue = a[hwx::kJpegStartQueue];
  adrJpegStopQueue = a[hwx::kJpegStopQueue];
  adrJpegQueryStatus = a[hwx::kJpegQueryQueueStatus];
  fnSubmitFrame = reinterpret_cast<t_submitFrame>(b[hwx::kSubmitFrame]);
  fnAllocMem = reinterpret_cast<t_allocMem>(b[hwx::kJpegAllocMemory]);
  fnReleaseMem = reinterpret_cast<t_releaseMem>(b[hwx::kJpegReleaseMemory]);
  adrQueueSubmit = b[hwx::kQueueSubmitFrame];
  adrJpegSubmit = b[hwx::kJpegSubmitFrame];
  gResolved = gDecodeResolved = true;

  KernelPatcher::RouteRequest requests[]{
      {hwx::kFunctions[hwx::kStartMM].symbol, wrapStartMM, orgStartMM},
      {hwx::kFunctions[hwx::kStopMM].symbol, wrapStopMM, orgStopMM},
  };
  if (patcher.routeMultiple(index, requests, address, size)) {
    publish("waiting for the driver to create its video queues");
  } else {
    say("route of startMMEngineQueues failed (%d), driver left as it is",
        patcher.getError());
    patcher.clearError();
    gResolved = gDecodeResolved = false;
    publish("off: route failed");
  }
}

static void onKextLoad(void*, KernelPatcher& patcher, size_t index,
                       mach_vm_address_t address, size_t size) {
  IOLockLock(gLock);
  if (kKexts[0].loadIndex == index) onHWLibsLoad(patcher, index, address, size);
  if (kKexts[1].loadIndex == index) onX6000Load(patcher, index, address, size);
  IOLockUnlock(gLock);
}

static const char* bootargOff[]{"-vcnjpegoff"};
static const char* bootargDebug[]{"-vcnjpegdbg"};
static const char* bootargBeta[]{"-vcnjpegbeta"};

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
    KernelVersion::Tahoe,  // libraries checked: 26.7.3 only
    KernelVersion::Tahoe,
    []() {
      uint32_t mib = kPoolDefaultMiB;
      if (!PE_parse_boot_argn("vcnjpegpool", &mib, sizeof(mib)) || mib == 0)
        mib = kPoolDefaultMiB;
      appPoolFor(mib, &gP);
      gLock = IOLockAlloc();
      gIdleCall = thread_call_allocate(idleFired, nullptr);
      if (gLock == nullptr || gIdleCall == nullptr) {
        publish("off: out of memory");
        return;
      }
      publish("waiting for AMDRadeonX6000HWLibs");
      if (lilu.onKextLoad(kKexts, arrsize(kKexts), onKextLoad, nullptr) !=
          LiluAPI::Error::NoError)
        publish("off: Lilu refused the kext load callback");
    }};
