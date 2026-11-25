//
//  apps_test - host checks of VCNJpeg's door (kext/apps_handler.hpp) and of
//  when it powers the block (kext/idle_logic.hpp), built with the address and
//  undefined-behaviour sanitizers by jpeg/build.sh. The handler, the stream
//  check and the idle logic are the kext's own files; what stands in for the
//  kernel here is the clock, the idle timer (a thread_call in the kext), the
//  power request, the block of buffers and the decode itself, which writes a
//  known pattern instead of asking the GPU.
//
//    apps_test <sample.jpg>
//
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "idle_logic.hpp"
#include "jpeg_app_client.h"
#include "jpeg_cmds.hpp"
#include "jpeg_layout.hpp"
#include "jpeg_normalize.hpp"
#include "jpeg_proto.hpp"

// ---- what kern_start.cpp gives the handler in the kext ----
struct Pool {
  uint32_t bytes, ib, fence, bitstream, bitstreamCap, surface, surfaceCap,
      guard, guardBytes;
};
static Pool gP{jl::kPoolBytes,     jl::kPoolIb,       jl::kPoolFence,
               jl::kPoolBitstream, jl::kBitstreamCap, jl::kPoolSurface,
               jl::kSurfaceCap,    jl::kPoolGuard,    jl::kGuardBytes};
static uint8_t* gPool = nullptr;
static bool gDecodeResolved = true, gCreated = true, gDecoded = false;
static uint32_t gJobs = 0, gLoadedBytes = 0, gLoadPos = 0;
static jc::StreamInfo gStream;
static jc::Layout gLayout;
static jp::Result gResult;
static uint64_t gNow = 1000;
static uint64_t nowMs() { return gNow; }
static uint32_t decodeState() { return gPool != nullptr ? jp::kStatePool : 0; }
static void logResult(const jp::Result*) {}
#include "decode_accept.hpp"
static uint32_t gRunStatus = static_cast<uint32_t>(jp::Status::Ok);
static uint32_t gRunFlags = 0xffffffff;
static uint8_t patternAt(uint32_t i) { return static_cast<uint8_t>(i * 7 + 3); }
static void decodeRun(uint32_t mode, uint32_t flags, jp::Result* r) {
  memset(r, 0, sizeof(*r));
  gRunFlags = flags;
  gJobs++;
  r->status = mode == jp::kModeDecode && gLoadedBytes != 0
                  ? gRunStatus
                  : static_cast<uint32_t>(jp::Status::NotReady);
  if (r->status != static_cast<uint32_t>(jp::Status::Ok)) return;
  for (uint32_t i = 0; i < gLayout.bytes; i++)
    gPool[gP.surface + i] = patternAt(i);
  r->width = gStream.width;
  r->height = gStream.height;
  r->pitch = gLayout.pitch;
  r->alignedHeight = gLayout.alignedHeight;
  r->chromaOffset = gLayout.chromaOffset;
  r->surfaceBytes = gLayout.bytes;
  r->elapsedMs = 7;
  gDecoded = true;
}
// copyin/copyout refuse an address the caller does not own; here only the
// test's own buffers are owned.
static bool gCopyFails = false;
static std::vector<std::pair<uintptr_t, size_t>> gOwned;
static bool owned(uint64_t a, uint32_t n) {
  for (auto& o : gOwned)
    if (a >= o.first && a <= o.first + o.second && n <= o.first + o.second - a)
      return true;
  return false;
}
static bool appCopyIn(uint8_t* dst, uint64_t src, uint32_t bytes) {
  if (gCopyFails || !owned(src, bytes)) return false;
  memcpy(dst, reinterpret_cast<const void*>(src), bytes);
  return true;
}
static bool appCopyOut(uint64_t dst, const uint8_t* src, uint32_t bytes) {
  if (gCopyFails || !owned(dst, bytes)) return false;
  memcpy(reinterpret_cast<void*>(dst), src, bytes);
  return true;
}
// ---- the block's power and the idle timer, as kern_start.cpp drives them ----
static jidle::Idle gIdle;
static bool gTimerPending = false, gBlockRefuses = false;
static uint64_t gTimerAt = 0;
static int gPowerOns = 0, gPowerOffs = 0, gArms = 0;
static void idleArm(uint64_t delayMs) {  // thread_call_enter_delayed
  if (delayMs == 0) return;
  gTimerPending = true;
  gTimerAt = gNow + delayMs;
  gArms++;
}
static void appTouch() { idleArm(jidle::touch(gIdle, gNow)); }
static bool appBlockOn() {
  if (gIdle.on) return true;
  if (gBlockRefuses) return false;
  gIdle.on = true;
  gPowerOns++;
  return true;
}
// Time goes by `ms`; the timer fires when its moment comes, as the thread_call
// would.
static void advance(uint64_t ms) {
  uint64_t end = gNow + ms;
  while (gTimerPending && gTimerAt <= end) {
    if (gTimerAt > gNow)
      gNow = gTimerAt;  // the random checks move the clock without the timer
    gTimerPending = false;
    uint64_t delay = 0;
    switch (jidle::tick(gIdle, gNow, &delay)) {
      case jidle::Tick::PowerOff:
        gIdle.on = false;
        gPowerOffs++;
        break;
      case jidle::Tick::Rearm:
        idleArm(delay);
        break;
      case jidle::Tick::Nothing:
        break;
    }
  }
  gNow = end;
}
#include "apps_handler.hpp"

static int fails = 0;
#define CHECK(cond, text)                           \
  do {                                              \
    bool ok_ = (cond);                              \
    if (!ok_) fails++;                              \
    printf("%s %s\n", ok_ ? "ok  " : "FAIL", text); \
  } while (0)

// One call through the door, with exact-size heap buffers so that a byte too
// far is caught.
struct Reply {
  bool ours = false, ok = false;
  ja_reply head{};
  std::vector<uint8_t> data;
  uint64_t outSize = 0;
};
static Reply call(void* self, const std::vector<uint8_t>& in, uint64_t outCap) {
  Reply r;
  std::vector<uint8_t> inCopy(in);
  r.ours = appIsOurs(inCopy.empty() ? nullptr : inCopy.data(), inCopy.size());
  if (!r.ours) return r;
  std::vector<uint8_t> out(outCap, 0xCC);
  r.outSize = outCap;
  r.ok = appEntry(self, inCopy.data(), inCopy.size(),
                  outCap != 0 ? out.data() : nullptr, &r.outSize);
  if (!r.ok) return r;
  if (r.outSize < sizeof(ja_reply) || r.outSize > outCap) {
    printf("FAIL reply of %llu bytes for a buffer of %llu\n",
           static_cast<unsigned long long>(r.outSize),
           static_cast<unsigned long long>(outCap));
    exit(1);
  }
  memcpy(&r.head, out.data(), sizeof(r.head));
  if (r.head.magic != JA_REPLY_MAGIC ||
      sizeof(ja_reply) + r.head.dataBytes != r.outSize) {
    printf("FAIL reply header does not describe the reply\n");
    exit(1);
  }
  r.data.assign(out.begin() + sizeof(ja_reply),
                out.begin() + static_cast<long>(r.outSize));
  return r;
}
static std::vector<uint8_t> request(uint32_t op, uint64_t a0 = 0,
                                    uint64_t a1 = 0,
                                    const uint8_t* data = nullptr,
                                    size_t n = 0) {
  ja_request rq{JA_HEADER_SIZE, JA_CODE, JA_PROTOCOL, op, a0, a1};
  std::vector<uint8_t> v(sizeof(rq) + n);
  memcpy(v.data(), &rq, sizeof(rq));
  if (n != 0) memcpy(v.data() + sizeof(rq), data, n);
  return v;
}
static uint32_t load(void* self, const std::vector<uint8_t>& jpeg,
                     Reply* last = nullptr) {
  uint32_t status = JA_BAD_REQUEST;
  for (size_t off = 0; off < jpeg.size();) {
    size_t n =
        jpeg.size() - off < JA_LOAD_PIECE ? jpeg.size() - off : JA_LOAD_PIECE;
    Reply r =
        call(self, request(JA_OP_LOAD, off, jpeg.size(), jpeg.data() + off, n),
             JA_MAX_IO);
    status = r.ok ? r.head.status : 99;
    if (last != nullptr) *last = r;
    if (status != JA_MORE) break;
    off += n;
  }
  return status;
}
static bool surfaceClean() {
  for (uint32_t i = 0; i < gP.surfaceCap; i++)
    if (gPool[gP.surface + i] != 0) return false;
  return true;
}

int main(int argc, char** argv) {
  if (argc != 2) return 2;
  std::vector<uint8_t> file, jpeg;
  FILE* f = fopen(argv[1], "rb");
  if (f == nullptr) return 2;
  uint8_t buf[65536];
  size_t n;
  while ((n = fread(buf, 1, sizeof(buf), f)) > 0)
    file.insert(file.end(), buf, buf + n);
  fclose(f);
  if (!jnorm::normalize(file, &jpeg).empty()) return 2;
  gPool = static_cast<uint8_t*>(calloc(1, gP.bytes));
  int a = 0, b = 0;
  void *A = &a, *B = &b;

  // ---- what is ours and what goes on to PowerPlay ----
  std::vector<uint8_t> pm(112, 0);
  uint32_t pmHead[2] = {16, 0x00C00053};
  memcpy(pm.data(), pmHead, 8);
  CHECK(!call(A, pm, 72).ours,
        "a PowerPlay request (PMRequest, 112 bytes) is not taken");
  CHECK(!call(A, {}, 72).ours, "an empty request is not taken");
  std::vector<uint8_t> shortRq = request(JA_OP_INFO);
  shortRq.resize(sizeof(ja_request) - 1);
  CHECK(!call(A, shortRq, 72).ours,
        "a request one byte short of our header is not taken");
  std::vector<uint8_t> big = request(JA_OP_INFO);
  big.resize(JA_MAX_IO + 1);
  CHECK(!call(A, big, 72).ours, "a request above 4096 bytes is not taken");
  Reply r = call(A, request(JA_OP_INFO), sizeof(ja_reply) - 1);
  CHECK(r.ours && !r.ok,
        "our request with room for less than a reply header is refused, "
        "nothing written");
  r = call(A, request(JA_OP_INFO), sizeof(ja_reply));
  CHECK(r.ok && r.head.status == JA_OK &&
            r.head.v[1] == gP.bitstreamCap - 128 &&
            r.head.v[2] == gP.surfaceCap,
        "INFO answers with the room for the JPEG and for the picture");
  std::vector<uint8_t> wrongProto = request(JA_OP_INFO);
  wrongProto[8] = 2;
  r = call(A, wrongProto, JA_MAX_IO);
  CHECK(r.ok && r.head.status == JA_BAD_REQUEST,
        "another protocol number is a bad request");
  r = call(A, request(77), JA_MAX_IO);
  CHECK(r.ok && r.head.status == JA_BAD_REQUEST,
        "an unknown operation is a bad request");

  // ---- one whole decode ----
  CHECK(call(A, request(JA_OP_RUN), JA_MAX_IO).head.status == JA_NOT_OWNER,
        "RUN before any LOAD: not the owner");
  CHECK(call(A, request(JA_OP_READ), JA_MAX_IO).head.status == JA_NOT_OWNER,
        "READ before any LOAD: not the owner");
  Reply last;
  CHECK(load(A, jpeg, &last) == JA_OK && last.head.v[0] == 640 &&
            last.head.v[1] == 480,
        "the sample loads in pieces and its size comes back (640x480)");
  r = call(A, request(JA_OP_RUN, 0xffffffffffffffffull), JA_MAX_IO);
  ja_picture pic{};
  if (r.data.size() == sizeof(pic)) memcpy(&pic, r.data.data(), sizeof(pic));
  CHECK(r.head.status == JA_OK && pic.width == 640 && pic.height == 480 &&
            pic.pitch == 768 && pic.surfaceBytes == 768 * 480 * 3 / 2 &&
            pic.chromaOffset == 768 * 480,
        "RUN answers with the picture's layout");
  CHECK(gRunFlags == jp::kFlagWptrRegister,
        "of the caller's flags only the write-pointer one reaches the decode");
  CHECK(call(B, request(JA_OP_READ, 0), JA_MAX_IO).head.status == JA_NOT_OWNER,
        "another client cannot read the picture");
  CHECK(call(B, request(JA_OP_RUN), JA_MAX_IO).head.status == JA_NOT_OWNER,
        "another client cannot run");
  CHECK(load(B, jpeg) == JA_BUSY, "another client's LOAD is told to wait");
  r = call(B, request(JA_OP_RELEASE), JA_MAX_IO);
  CHECK(r.head.status == JA_OK && gAppOwner == A,
        "another client's RELEASE changes nothing");
  bool same = true;
  uint32_t got = 0, calls = 0;
  while (got < pic.surfaceBytes) {
    uint64_t cap = calls % 3 == 0   ? JA_MAX_IO
                   : calls % 3 == 1 ? sizeof(ja_reply) + 1
                                    : 1000;
    r = call(A, request(JA_OP_READ, got), cap);
    if (!r.ok || r.head.status != JA_OK || r.data.empty()) break;
    for (size_t i = 0; i < r.data.size(); i++)
      same = same && r.data[i] == patternAt(got + static_cast<uint32_t>(i));
    got += static_cast<uint32_t>(r.data.size());
    calls++;
  }
  CHECK(got == pic.surfaceBytes && same,
        "the picture reads back whole, with reply buffers of three sizes");
  CHECK(gAppOwner == nullptr && surfaceClean(),
        "after the last piece the buffers are free and the picture is wiped");
  CHECK(call(A, request(JA_OP_READ, 0), JA_MAX_IO).head.status == JA_NOT_OWNER,
        "it cannot be read twice");

  // ---- the same through the caller's own memory ----
  gOwned.push_back({reinterpret_cast<uintptr_t>(jpeg.data()), jpeg.size()});
  r = call(A,
           request(JA_OP_LOAD_USER, reinterpret_cast<uint64_t>(jpeg.data()),
                   jpeg.size()),
           JA_MAX_IO);
  CHECK(r.head.status == JA_OK && r.head.v[0] == 640 && r.head.v[1] == 480,
        "LOAD_USER takes the whole JPEG in one call");
  CHECK(load(B, jpeg) == JA_BUSY,
        "and holds the buffers against another client");
  call(A, request(JA_OP_RUN), JA_MAX_IO);
  std::vector<uint8_t> whole(pic.surfaceBytes - 1);
  gOwned.push_back({reinterpret_cast<uintptr_t>(whole.data()), whole.size()});
  r = call(A,
           request(JA_OP_READ_USER, reinterpret_cast<uint64_t>(whole.data()),
                   whole.size()),
           JA_MAX_IO);
  CHECK(r.head.status == JA_BAD_REQUEST && gAppOwner == A,
        "READ_USER into a buffer one byte short is refused");
  gOwned.pop_back();
  whole.resize(pic.surfaceBytes);
  gOwned.push_back({reinterpret_cast<uintptr_t>(whole.data()), whole.size()});
  r = call(A,
           request(JA_OP_READ_USER, reinterpret_cast<uint64_t>(whole.data()),
                   whole.size()),
           JA_MAX_IO);
  same = r.head.status == JA_OK && r.head.v[0] == pic.surfaceBytes;
  for (uint32_t i = 0; same && i < pic.surfaceBytes; i++)
    same = whole[i] == patternAt(i);
  CHECK(same && gAppOwner == nullptr && surfaceClean(),
        "READ_USER copies the whole picture, then frees and wipes");
  gCopyFails = true;
  r = call(A,
           request(JA_OP_LOAD_USER, reinterpret_cast<uint64_t>(jpeg.data()),
                   jpeg.size()),
           JA_MAX_IO);
  CHECK(r.head.status == JA_BAD_ADDRESS && gAppOwner == nullptr,
        "an address copyin refuses: bad address, buffers free");
  gCopyFails = false;
  r = call(A,
           request(JA_OP_LOAD_USER, reinterpret_cast<uint64_t>(jpeg.data()) + 1,
                   jpeg.size()),
           JA_MAX_IO);
  CHECK(r.head.status == JA_BAD_ADDRESS && gAppOwner == nullptr,
        "a JPEG one byte past the caller's buffer: bad address");
  CHECK(
      call(A, request(JA_OP_LOAD_USER, 0, jpeg.size()), JA_MAX_IO)
                  .head.status == JA_BAD_REQUEST &&
          call(A, request(JA_OP_LOAD_USER, 0x1000, gP.bitstreamCap), JA_MAX_IO)
                  .head.status == JA_BAD_REQUEST &&
          call(A, request(JA_OP_LOAD_USER, 0x1000, 0), JA_MAX_IO).head.status ==
              JA_BAD_REQUEST,
      "LOAD_USER with address 0, size 0 or a size above the room is a bad "
      "request (nothing copied)");
  load(A, jpeg);
  call(A, request(JA_OP_RUN), JA_MAX_IO);
  gCopyFails = true;
  r = call(A, request(JA_OP_READ_USER, 0x1000, pic.surfaceBytes), JA_MAX_IO);
  gCopyFails = false;
  CHECK(
      r.head.status == JA_BAD_ADDRESS && gAppOwner == nullptr && surfaceClean(),
      "an address copyout refuses: bad address, buffers free and wiped");

  // ---- the caller's side (tools/jpeg_app_client.h) against this handler ----
  {
    struct Fake {
      void* self;
      int calls;
      bool dropReplies;
    };
    auto transport = [](void* ctx, const void* in, size_t inSize, void* out,
                        size_t* outSize) -> int {
      Fake* f = static_cast<Fake*>(ctx);
      f->calls++;
      if (!appIsOurs(in, inSize))
        return 0x2c2;  // what PowerPlay's refusal would look like: an error
      uint64_t o = *outSize;
      if (!appEntry(f->self, in, inSize, out, &o)) return 0x2c2;
      *outSize = f->dropReplies ? 0 : static_cast<size_t>(o);
      return 0;
    };
    Fake fa{A, 0, false};
    std::vector<uint8_t> surf(pic.surfaceBytes, 0);
    gOwned.push_back({reinterpret_cast<uintptr_t>(surf.data()), surf.size()});
    ja_picture p2{};
    ja_reply last{};
    int s = ja_decode(transport, &fa, jpeg.data(), jpeg.size(), surf.data(),
                      surf.size(), 0, 100, &p2, &last);
    bool good = s == JA_OK && fa.calls == 3 && p2.width == 640 &&
                p2.surfaceBytes == pic.surfaceBytes;
    for (uint32_t i = 0; good && i < p2.surfaceBytes; i++)
      good = surf[i] == patternAt(i);
    CHECK(good && gAppOwner == nullptr,
          "ja_decode: one picture in three calls (LOAD_USER, RUN, READ_USER), "
          "buffers free after");
    uint64_t st = 0, jcap = 0, scap = 0;
    CHECK(ja_info(transport, &fa, &st, &jcap, &scap) == JA_OK &&
              jcap == gP.bitstreamCap - 128 && scap == gP.surfaceCap,
          "ja_info reads the room for the JPEG and the picture");
    load(B, jpeg);  // another client holds the decoder
    Fake fw{A, 0, false};
    uint64_t t0 = gNow;
    s = ja_decode(transport, &fw, jpeg.data(), jpeg.size(), surf.data(),
                  surf.size(), 0, 30, &p2, &last);
    CHECK(s == JA_BUSY && gAppOwner == B && gNow == t0,
          "ja_decode waits while another client holds it, then says busy");
    call(B, request(JA_OP_RELEASE), JA_MAX_IO);
    Fake fd{A, 0, true};
    CHECK(ja_decode(transport, &fd, jpeg.data(), jpeg.size(), surf.data(),
                    surf.size(), 0, 0, &p2, &last) == -1,
          "a reply that is not one of ours counts as no door");
    call(A, request(JA_OP_RELEASE), JA_MAX_IO);
    std::vector<uint8_t> small(pic.surfaceBytes - 1);
    gOwned.push_back({reinterpret_cast<uintptr_t>(small.data()), small.size()});
    s = ja_decode(transport, &fa, jpeg.data(), jpeg.size(), small.data(),
                  small.size(), 0, 0, &p2, &last);
    CHECK(s == JA_BAD_REQUEST && gAppOwner == nullptr,
          "a surface buffer too small: refused, and the decoder is given back");
    auto none = [](void*, const void*, size_t, void*, size_t*) -> int {
      return 0x2c2;
    };
    CHECK(ja_info(none, nullptr, nullptr, nullptr, nullptr) == -1,
          "without the kext (PowerPlay refuses) ja_info says no door");
  }

  // ---- ownership ends by release, by silence, by error ----
  load(A, jpeg);
  call(A, request(JA_OP_RUN), JA_MAX_IO);
  r = call(A, request(JA_OP_READ, pic.surfaceBytes), JA_MAX_IO);
  CHECK(r.head.status == JA_BAD_REQUEST,
        "READ at the end of the picture is a bad request");
  r = call(A, request(JA_OP_READ, 0x100000000ull), JA_MAX_IO);
  CHECK(r.head.status == JA_BAD_REQUEST,
        "READ at an offset above 32 bits is a bad request");
  call(A, request(JA_OP_RELEASE), JA_MAX_IO);
  CHECK(gAppOwner == nullptr && surfaceClean(),
        "RELEASE frees the buffers and wipes the picture");
  load(A, jpeg);
  call(A, request(JA_OP_RUN), JA_MAX_IO);
  gNow += kAppHoldMs - 1;
  CHECK(load(B, jpeg) == JA_BUSY,
        "just before two seconds of silence the owner still holds the buffers");
  gNow += kAppHoldMs;
  CHECK(load(B, jpeg) == JA_OK && gAppOwner == B,
        "after two seconds of silence another client takes them");
  CHECK(call(A, request(JA_OP_READ, 0), JA_MAX_IO).head.status == JA_NOT_OWNER,
        "the client that lost them cannot read the new owner's picture");
  call(B, request(JA_OP_RELEASE), JA_MAX_IO);
  gRunStatus = static_cast<uint32_t>(jp::Status::Timeout);
  load(A, jpeg);
  r = call(A, request(JA_OP_RUN), JA_MAX_IO);
  CHECK(r.head.status == JA_FAILED &&
            r.head.detail == static_cast<uint32_t>(jp::Status::Timeout) &&
            gAppOwner == nullptr,
        "a decode that fails says why and frees the buffers");
  gRunStatus = static_cast<uint32_t>(jp::Status::Ok);
  load(A, jpeg);
  r = call(A, request(JA_OP_RUN), sizeof(ja_reply) + sizeof(ja_picture) - 1);
  CHECK(r.head.status == JA_BAD_REQUEST,
        "RUN without room for the layout is a bad request");
  call(A, request(JA_OP_RELEASE), JA_MAX_IO);

  // ---- LOAD arguments ----
  auto piece = [&](uint64_t off, uint64_t total, size_t bytes) {
    std::vector<uint8_t> d(bytes, 0xff);
    Reply x =
        call(A, request(JA_OP_LOAD, off, total, d.data(), d.size()), JA_MAX_IO);
    return x.ok ? x.head.status : 99u;
  };
  CHECK(piece(0, 100, 0) == JA_BAD_REQUEST,
        "LOAD with no data is a bad request");
  CHECK(piece(0, 0, 10) == JA_BAD_REQUEST,
        "LOAD of a JPEG of 0 bytes is a bad request");
  CHECK(piece(0, gP.bitstreamCap - 127, 10) == JA_BAD_REQUEST,
        "LOAD of a JPEG one byte above the room is a bad request");
  CHECK(piece(0, 5, 10) == JA_BAD_REQUEST,
        "LOAD of more bytes than the JPEG has is a bad request");
  CHECK(piece(0, 10000, 100) == JA_MORE &&
            piece(200, 10000, 100) == JA_BAD_REQUEST && gAppOwner == nullptr,
        "LOAD pieces out of order are a bad request and free the buffers");
  CHECK(piece(100, 10000, 100) == JA_BUSY,
        "a LOAD that does not start at 0 cannot take the buffers");
  CHECK(piece(0xffffffff00000000ull, 10000, 100) == JA_BUSY &&
            piece(0, 0xffffffffffffffffull, 100) == JA_BAD_REQUEST,
        "64-bit offsets and sizes do not wrap");
  CHECK(piece(0, 64, 64) == JA_BAD_STREAM && gAppOwner == nullptr,
        "64 bytes that are not a JPEG: bad stream, buffers free");
  std::vector<uint8_t> bigPicture(jpeg);
  for (size_t i = 0; i + 9 < bigPicture.size(); i++) {
    if (bigPicture[i] == 0xff && bigPicture[i + 1] == 0xc0) {
      bigPicture[i + 5] = 0x10;  // height 4096+
      bigPicture[i + 7] = 0x10;  // width 4096+
      break;
    }
  }
  CHECK(load(A, bigPicture) == JA_BAD_STREAM && gAppOwner == nullptr,
        "a JPEG whose picture does not fit the surface is refused");
  gCreated = false;
  CHECK(piece(0, 64, 64) == JA_NOT_READY &&
            call(A, request(JA_OP_INFO), JA_MAX_IO).head.status == JA_OK,
        "without the queue everything but INFO says not ready");
  gCreated = true;

  // ---- the block for a boot argument ----
  bool poolOk = true;
  for (uint32_t mib : {0u, 1u, 5u, 7u, 8u, 9u, 64u, 96u, 127u, 128u, 129u, 256u,
                       0xffffffffu}) {
    Pool p = gP;
    appPoolFor(mib, &p);
    uint32_t want = (mib < 8 ? 8 : mib > 128 ? 128 : mib) << 20;
    poolOk = poolOk && p.bytes == want && p.bitstream == jl::kPoolBitstream &&
             p.bitstreamCap >= jl::kBitstreamCap &&
             p.bitstreamCap % 4096 == 0 &&
             p.surface == p.bitstream + p.bitstreamCap &&
             p.surface + p.surfaceCap == p.guard &&
             p.guard + p.guardBytes == p.bytes && p.surface % 4096 == 0 &&
             p.surfaceCap >= jl::kSurfaceCap;
  }
  CHECK(poolOk,
        "the block for 8..128 MiB keeps every part inside it, page aligned, "
        "never smaller than the fixed one");
  CHECK(kPoolDefaultMiB == 128,
        "the default block is 128 MiB, the size run on the GPU");
  Pool p128 = gP, p32 = gP;
  appPoolFor(128, &p128);
  appPoolFor(32, &p32);
  jc::Layout l48{}, l12{};
  CHECK(jc::outputLayout(8064, 6048, p128.surfaceCap, &l48) &&
            p128.bitstreamCap >= 30u << 20,
        "128 MiB hold a 48-megapixel picture (8064x6048) and a JPEG of 30 MiB");
  CHECK(jc::outputLayout(4032, 3024, p32.surfaceCap, &l12) &&
            p32.bitstreamCap >= 7u << 20,
        "32 MiB hold a 12-megapixel picture (4032x3024) and a JPEG of 7 MiB");

  // ---- power only while decoding (idle_logic.hpp) ----
  advance(10 * jidle::kIdleMs);  // whatever the checks above left on goes off
  CHECK(
      !gIdle.on && !gTimerPending,
      "after the checks above and a pause the block is off and no timer runs");
  gPowerOns = gPowerOffs = gArms = 0;
  for (int i = 0; i < 10; i++) call(A, request(JA_OP_INFO), JA_MAX_IO);
  CHECK(!gIdle.on && gArms == 0,
        "INFO neither powers the block nor starts the timer");
  r = call(A,
           request(JA_OP_LOAD_USER, reinterpret_cast<uint64_t>(jpeg.data()),
                   jpeg.size()),
           JA_MAX_IO);
  CHECK(r.head.status == JA_OK && !gIdle.on && gPowerOns == 0,
        "a LOAD does not power the block: only RUN needs it");
  call(A, request(JA_OP_RELEASE), JA_MAX_IO);
  auto frame = [&](void* who) {
    Reply l =
        call(who,
             request(JA_OP_LOAD_USER, reinterpret_cast<uint64_t>(jpeg.data()),
                     jpeg.size()),
             JA_MAX_IO);
    Reply x = call(who, request(JA_OP_RUN), JA_MAX_IO);
    Reply y =
        call(who,
             request(JA_OP_READ_USER, reinterpret_cast<uint64_t>(whole.data()),
                     whole.size()),
             JA_MAX_IO);
    return l.head.status == JA_OK && x.head.status == JA_OK &&
           y.head.status == JA_OK;
  };
  // 30 frames a second for ten seconds: one power-on, never off between two
  // frames
  bool frames = true, onAll = true;
  for (int i = 0; i < 300; i++) {
    frames = frame(A) && frames;
    onAll = onAll && gIdle.on;
    advance(33);
    onAll = onAll && gIdle.on;
  }
  CHECK(
      frames && onAll && gPowerOns == 1 && gPowerOffs == 0,
      "a 30 fps stream of 300 frames: powered once, never off between frames");
  CHECK(gArms <= 300 * 33 / static_cast<int>(jidle::kIdleMs) + 2,
        "the idle timer is armed about once per two seconds of stream, not "
        "once per frame");
  advance(jidle::kIdleMs - 100);
  CHECK(gIdle.on && frame(A) && gPowerOns == 1,
        "a pause shorter than two seconds keeps the block on");
  advance(jidle::kIdleMs - 1);
  bool stillOn = gIdle.on;
  advance(1);
  CHECK(stillOn && !gIdle.on && gPowerOffs == 1 && !gTimerPending,
        "two seconds after the last request the block goes off, and the timer "
        "stops");
  CHECK(frame(A) && gIdle.on && gPowerOns == 2,
        "the next picture powers the block again");
  // two clients taking turns, each at 15 fps: still one power-on
  frames = true;
  for (int i = 0; i < 100; i++) {
    frames = frame(i % 2 == 0 ? A : B) && frames;
    advance(33);
  }
  CHECK(frames && gIdle.on && gPowerOns == 2 && gPowerOffs == 1,
        "two clients taking turns share one power-on");
  advance(jidle::kIdleMs);
  CHECK(!gIdle.on && gPowerOffs == 2, "and the block goes off once both stop");
  gBlockRefuses = true;
  r = call(A,
           request(JA_OP_LOAD_USER, reinterpret_cast<uint64_t>(jpeg.data()),
                   jpeg.size()),
           JA_MAX_IO);
  Reply refused = call(A, request(JA_OP_RUN), JA_MAX_IO);
  CHECK(r.head.status == JA_OK && refused.head.status == JA_NOT_READY &&
            gAppOwner == nullptr && surfaceClean() && gPowerOns == 2,
        "when the block cannot be powered RUN says not ready and the client "
        "loses the buffers");
  gBlockRefuses = false;
  advance(jidle::kIdleMs);

  // ---- random requests: nothing may read or write outside its buffers ----
  uint32_t seed = 12345;
  auto rnd = [&]() {
    seed = seed * 1664525u + 1013904223u;
    return seed >> 8;
  };
  uint32_t handled = 0;
  for (int i = 0; i < 300000; i++) {
    void* who = rnd() % 3 == 0 ? B : A;
    size_t dataBytes =
        rnd() % 4 == 0 ? rnd() % (JA_LOAD_PIECE + 1) : rnd() % 64;
    std::vector<uint8_t> d(dataBytes);
    for (auto& x : d) x = static_cast<uint8_t>(rnd());
    uint64_t a0 = rnd() % 5 == 0 ? (static_cast<uint64_t>(rnd()) << 24) | rnd()
                                 : rnd() % 5000;
    uint64_t a1 = rnd() % 5 == 0 ? (static_cast<uint64_t>(rnd()) << 24) | rnd()
                                 : rnd() % 9000;
    uint32_t op = rnd() % 9;
    if ((op == JA_OP_LOAD_USER || op == JA_OP_READ_USER) && rnd() % 2 == 0) {
      a0 = rnd() % 2 == 0
               ? reinterpret_cast<uint64_t>(
                     op == JA_OP_LOAD_USER ? jpeg.data() : whole.data())
               : a0;
      a1 = op == JA_OP_LOAD_USER ? jpeg.size() : whole.size();
    }
    if (op == JA_OP_LOAD && rnd() % 3 == 0) {
      a0 = gLoadPos;
      a1 = gLoadPos + dataBytes + rnd() % 3;
    }
    std::vector<uint8_t> rq = request(op, a0, a1, d.data(), d.size());
    if (rnd() % 50 == 0)
      rq[rnd() % rq.size()] ^= static_cast<uint8_t>(1u << (rnd() % 8));
    uint64_t cap = rnd() % 6 == 0   ? rnd() % 100
                   : rnd() % 3 == 0 ? JA_MAX_IO
                                    : rnd() % 5000;
    if (rnd() % 400 == 0) load(who, jpeg);
    if (rnd() % 1000 == 0) gNow += kAppHoldMs;
    Reply x = call(who, rq, cap);
    handled += x.ok ? 1 : 0;
    gNow += rnd() % 20;
  }
  CHECK(handled > 100000 && gJobs > 10,
        "300000 random requests from two clients, no access outside a buffer");
  uint8_t* guard = gPool + gP.guard;
  bool guardOk = true;
  for (uint32_t i = 0; i < gP.guardBytes; i++)
    guardOk = guardOk && guard[i] == 0;
  CHECK(guardOk, "nothing was written after the surface");
  advance(jidle::kIdleMs);
  CHECK(!gIdle.on && !gTimerPending,
        "after the random requests and a pause the block is off");
  free(gPool);
  printf("%s\n", fails == 0 ? "APPS PASSED" : "APPS FAILED");
  return fails == 0 ? 0 : 1;
}
