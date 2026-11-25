//
//  apps_handler.hpp - what VCNJpeg does with one request of jpeg_app.h, and the
//  layout of its block of buffers. No kernel call in here: kern_start.cpp
//  includes it in the kext and tests/apps_test.cpp on the host, with
//  sanitizers, because this is the code any process can reach. Needs:
//  appCopyIn(kernel dst, user src, bytes) and appCopyOut(user dst, kernel src,
//  bytes), true on success (copyin/copyout in the kext); appTouch() (a request
//  of a client arrived: the idle timer starts over) and appBlockOn() (power the
//  block and start its queue if it is not yet; false = it cannot be); and the
//  decoder's globals and functions (gPool, gP, gLayout, gStream, gResult,
//  gDecoded, gLoadedBytes, gLoadPos, gJobs, gDecodeResolved, gCreated, nowMs,
//  decodeState, decodeAccept, decodeRun, logResult).
//
#include "jpeg_app.h"

// copyin/copyout refuse a single transfer above copysize_limit_panic (64 MiB in
// the 25G342 kernel, read from the KDK); a 48-megapixel NV12 picture is ~71
// MiB. Seen on hardware 2026-11-24: READ_USER of the 8064x6048 picture came
// back as BAD_ADDRESS. So both directions go in pieces of 16 MiB.
static constexpr uint32_t kAppCopyChunk = 16u << 20;
static bool appCopyInChunks(uint8_t* dst, uint64_t src, uint32_t bytes) {
  for (uint32_t off = 0; off < bytes; off += kAppCopyChunk) {
    uint32_t n = bytes - off < kAppCopyChunk ? bytes - off : kAppCopyChunk;
    if (!appCopyIn(dst + off, src + off, n)) return false;
  }
  return true;
}
static bool appCopyOutChunks(uint64_t dst, const uint8_t* src, uint32_t bytes) {
  for (uint32_t off = 0; off < bytes; off += kAppCopyChunk) {
    uint32_t n = bytes - off < kAppCopyChunk ? bytes - off : kAppCopyChunk;
    if (!appCopyOut(dst + off, src + off, n)) return false;
  }
  return true;
}

static void* gAppOwner = nullptr;  // the video context that holds the buffers
static uint64_t gAppDeadline = 0;  // ms; the owner loses them after this
static uint32_t gAppRequests = 0;
static constexpr uint64_t kAppHoldMs = 2000;

// Ends the current ownership: nothing of the picture may be left to read.
static void appDrop() {
  if (gPool != nullptr && gDecoded)
    memset(gPool + gP.surface, 0, gLayout.bytes);
  gDecoded = false;
  gLoadedBytes = gLoadPos = 0;
  gAppOwner = nullptr;
}

// True when `self` holds the buffers now, or can take them (take = a LOAD at
// offset 0).
static bool appOwns(void* self, bool take) {
  uint64_t now = nowMs();
  if (gAppOwner != nullptr && gAppOwner != self && now >= gAppDeadline)
    appDrop();
  if (gAppOwner == nullptr && take) gAppOwner = self;
  if (gAppOwner != self) return false;
  gAppDeadline = now + kAppHoldMs;
  return true;
}

// One request. `in` holds inSize bytes and starts with a checked ja_request;
// `out` has room for `cap` bytes. Returns the bytes written to out.
static uint32_t appHandle(void* self, const uint8_t* in, uint32_t inSize,
                          uint8_t* out, uint32_t cap) {
  ja_request rq;
  memcpy(&rq, in, sizeof(rq));
  ja_reply rp{};
  rp.magic = JA_REPLY_MAGIC;
  uint8_t* data = out + sizeof(rp);
  uint32_t room = cap - static_cast<uint32_t>(sizeof(rp));
  auto done = [&](uint32_t status, uint32_t detail, uint32_t bytes) {
    rp.status = status;
    rp.detail = detail;
    rp.dataBytes = bytes;
    memcpy(out, &rp, sizeof(rp));
    return static_cast<uint32_t>(sizeof(rp)) + bytes;
  };
  if (rq.protocol != JA_PROTOCOL) return done(JA_BAD_REQUEST, 0, 0);
  gAppRequests++;
  if (rq.op == JA_OP_INFO) {
    rp.v[0] = decodeState();
    rp.v[1] = gP.bitstreamCap - 128;
    rp.v[2] = gP.surfaceCap;
    rp.v[3] = gJobs;
    return done(JA_OK, 0, 0);
  }
  if (!gDecodeResolved || gPool == nullptr || !gCreated)
    return done(JA_NOT_READY, 0, 0);
  // Every request of a client keeps the block powered for another while.
  appTouch();
  switch (rq.op) {
    case JA_OP_LOAD: {
      uint32_t piece = inSize - static_cast<uint32_t>(sizeof(rq));
      if (!appOwns(self, rq.arg0 == 0)) return done(JA_BUSY, 0, 0);
      if (rq.arg0 == 0) {
        gLoadedBytes = gLoadPos = 0;
        gDecoded = false;
      }
      if (piece == 0 || piece > JA_LOAD_PIECE || rq.arg1 == 0 ||
          rq.arg1 > gP.bitstreamCap - 128 || rq.arg0 != gLoadPos ||
          rq.arg0 + piece > rq.arg1) {
        appDrop();
        return done(JA_BAD_REQUEST, 0, 0);
      }
      memcpy(gPool + gP.bitstream + rq.arg0, in + sizeof(rq), piece);
      gLoadPos += piece;
      if (gLoadPos != rq.arg1) return done(JA_MORE, 0, 0);
      jc::Stream st = decodeAccept(gLoadPos);
      gLoadPos = 0;
      if (st != jc::Stream::Ok) {
        appDrop();
        return done(JA_BAD_STREAM, static_cast<uint32_t>(st), 0);
      }
      rp.v[0] = gStream.width;
      rp.v[1] = gStream.height;
      return done(JA_OK, 0, 0);
    }
    case JA_OP_LOAD_USER: {
      if (!appOwns(self, true)) return done(JA_BUSY, 0, 0);
      gLoadedBytes = gLoadPos = 0;
      gDecoded = false;
      if (rq.arg0 == 0 || rq.arg1 == 0 || rq.arg1 > gP.bitstreamCap - 128) {
        appDrop();
        return done(JA_BAD_REQUEST, 0, 0);
      }
      if (!appCopyInChunks(gPool + gP.bitstream, rq.arg0,
                           static_cast<uint32_t>(rq.arg1))) {
        appDrop();
        return done(JA_BAD_ADDRESS, 0, 0);
      }
      jc::Stream st = decodeAccept(static_cast<uint32_t>(rq.arg1));
      if (st != jc::Stream::Ok) {
        appDrop();
        return done(JA_BAD_STREAM, static_cast<uint32_t>(st), 0);
      }
      rp.v[0] = gStream.width;
      rp.v[1] = gStream.height;
      return done(JA_OK, 0, 0);
    }
    case JA_OP_READ_USER: {
      if (!appOwns(self, false) || !gDecoded) return done(JA_NOT_OWNER, 0, 0);
      if (rq.arg0 == 0 || rq.arg1 < gLayout.bytes)
        return done(JA_BAD_REQUEST, 0, 0);
      bool ok = appCopyOutChunks(rq.arg0, gPool + gP.surface, gLayout.bytes);
      rp.v[0] = gLayout.bytes;
      appDrop();  // read (or failed to): the next client may come
      return done(ok ? JA_OK : JA_BAD_ADDRESS, 0, 0);
    }
    case JA_OP_RUN: {
      if (!appOwns(self, false)) return done(JA_NOT_OWNER, 0, 0);
      if (room < sizeof(ja_picture)) return done(JA_BAD_REQUEST, 0, 0);
      // The only request that needs the block: it is powered here, not before.
      if (!appBlockOn()) {
        appDrop();
        return done(JA_NOT_READY, 0, 0);
      }
      // Only the write-pointer flag is the caller's to choose.
      uint32_t flags = static_cast<uint32_t>(rq.arg0) & jp::kFlagWptrRegister;
      decodeRun(jp::kModeDecode, flags, &gResult);
      if (gResult.status != static_cast<uint32_t>(jp::Status::Ok)) {
        uint32_t why = gResult.status;
        logResult(&gResult);
        appDrop();
        return done(why == static_cast<uint32_t>(jp::Status::NotReady)
                        ? JA_NOT_READY
                        : JA_FAILED,
                    why, 0);
      }
      ja_picture pic{};
      pic.width = gResult.width;
      pic.height = gResult.height;
      pic.pitch = gResult.pitch;
      pic.alignedHeight = gResult.alignedHeight;
      pic.chromaOffset = gResult.chromaOffset;
      pic.surfaceBytes = gResult.surfaceBytes;
      pic.elapsedMs = gResult.elapsedMs;
      pic.format = gResult.format;
      memcpy(data, &pic, sizeof(pic));
      return done(JA_OK, 0, sizeof(pic));
    }
    case JA_OP_READ: {
      if (!appOwns(self, false) || !gDecoded) return done(JA_NOT_OWNER, 0, 0);
      if (rq.arg0 >= gLayout.bytes) return done(JA_BAD_REQUEST, 0, 0);
      uint32_t piece = gLayout.bytes - static_cast<uint32_t>(rq.arg0);
      if (piece > room) piece = room;
      if (piece > JA_READ_PIECE) piece = JA_READ_PIECE;
      memcpy(data, gPool + gP.surface + rq.arg0, piece);
      rp.v[0] = gLayout.bytes;
      bool last = rq.arg0 + piece == gLayout.bytes;
      uint32_t n = done(JA_OK, 0, piece);
      if (last) appDrop();  // read to the end: the next client may come
      return n;
    }
    case JA_OP_RELEASE:
      if (gAppOwner == self) appDrop();
      return done(JA_OK, 0, 0);
    default:
      return done(JA_BAD_REQUEST, 0, 0);
  }
}

// True when a request of the video context's sendPMCommand carries our header.
// PowerPlay's own requests start with their size too, but none has this code:
// PP_Cwdde serves 0xC08001 and above as tests, and below that the low 16 bits
// up to 0xB0.
static bool appIsOurs(const void* in, uint64_t inSize) {
  if (in == nullptr || inSize < sizeof(ja_request) || inSize > JA_MAX_IO)
    return false;
  ja_request rq;
  memcpy(&rq, in, sizeof(rq));
  return rq.size == JA_HEADER_SIZE && rq.code == JA_CODE;
}

// One request that appIsOurs accepted. False = bad arguments, nothing written.
static bool appEntry(void* self, const void* in, uint64_t inSize, void* out,
                     uint64_t* outSize) {
  if (out == nullptr || outSize == nullptr || *outSize < sizeof(ja_reply))
    return false;
  uint32_t cap =
      *outSize > JA_MAX_IO ? JA_MAX_IO : static_cast<uint32_t>(*outSize);
  *outSize =
      appHandle(self, static_cast<const uint8_t*>(in),
                static_cast<uint32_t>(inSize), static_cast<uint8_t*>(out), cap);
  return true;
}

// The block for `mib` MiB (clamped to kPoolMinMiB..kPoolMaxMiB): a quarter for
// the JPEG, never less than a megabyte, the rest for the picture, then the
// guard.
static constexpr uint32_t kPoolMinMiB = 8, kPoolMaxMiB = 128,
                          kPoolDefaultMiB = 128;
static void appPoolFor(uint32_t mib, Pool* p) {
  if (mib < kPoolMinMiB) mib = kPoolMinMiB;
  if (mib > kPoolMaxMiB) mib = kPoolMaxMiB;
  uint32_t bytes = mib << 20;
  uint32_t bs = (bytes / 4) & ~0xFFFu;
  // the picture keeps at least the fixed block's room, the JPEG too
  uint32_t most = bytes - p->guardBytes - p->bitstream - jl::kSurfaceCap;
  if (bs > most) bs = most;
  if (bs < jl::kBitstreamCap) bs = jl::kBitstreamCap;
  p->bytes = bytes;
  p->bitstreamCap = bs;
  p->surface = p->bitstream + bs;
  p->guard = bytes - p->guardBytes;
  p->surfaceCap = p->guard - p->surface;
}
