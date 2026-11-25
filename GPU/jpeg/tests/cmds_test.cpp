//
//  cmds_test - host checks of kext/jpeg_cmds.hpp and tools/jpeg_normalize.hpp
//  (built with the address and undefined-behaviour sanitizers by tests/run.sh).
//
//    cmds_test frame <ring> <ib> <ib words> <seq> <fence>      the job frame,
//    one word per line cmds_test ib <bitstream> <bytes> <target> <pitch>
//    <chroma offset>   the decode IB cmds_test unit <sample.jpg> everything
//    that needs no oracle
//
#include <array>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "jpeg_cmds.hpp"
#include "jpeg_normalize.hpp"
#include "jpeg_power.hpp"
#include "jpeg_proto.hpp"

static int fails = 0;
#define CHECK(cond, text)                           \
  do {                                              \
    bool ok_ = (cond);                              \
    if (!ok_) fails++;                              \
    printf("%s %s\n", ok_ ? "ok  " : "FAIL", text); \
  } while (0)

static std::vector<uint8_t> readFile(const char* path) {
  std::vector<uint8_t> v;
  FILE* f = fopen(path, "rb");
  if (!f) return v;
  uint8_t buf[65536];
  size_t n;
  while ((n = fread(buf, 1, sizeof(buf), f)) > 0)
    v.insert(v.end(), buf, buf + n);
  fclose(f);
  return v;
}

// Each parse works on an exact-size heap copy, so that reading one byte too far
// is caught.
static jc::Stream parseCopy(const uint8_t* d, size_t n, jc::StreamInfo* info) {
  std::vector<uint8_t> copy(d, d + n);
  return jc::parseStream(copy.data(), copy.size(), info);
}

static int unit(const char* samplePath) {
  // frames
  uint32_t frame[jc::kFrameWords];
  CHECK(
      jc::buildJobFrame(frame, 0x8000100000, 0x8000200000, 80, 7, 0x8000201000),
      "job frame fills exactly 64 words");
  bool pad = true;
  for (int i = 56; i < 64; i += 2)
    pad &= frame[i] == 0x60000000 && frame[i + 1] == 0;
  CHECK(pad, "job frame: words 56..63 are nop pairs");
  bool noTrap = true;
  for (int i = 0; i < 64; i += 2) noTrap &= (frame[i] >> 28) != 7;
  CHECK(noTrap, "job frame has no trap packet (type 7)");
  CHECK(jc::buildRingTestFrame(frame, jc::kRingTestValue) &&
            frame[0] == 0x401f && frame[1] == 0xABADCAFE,
        "ring test frame starts with the pitch register write");
  pad = true;
  for (int i = 2; i < 64; i += 2)
    pad &= frame[i] == 0x60000000 && frame[i + 1] == 0;
  CHECK(pad, "ring test frame: the rest is nop pairs");
  // Linux amdgpu_jpeg_dec_set_reg: 16 words, PACKETJ(pitch, 0, 0, TYPE0),
  // 0xDEADBEEF, then (TYPE6, 0) pairs
  uint32_t ib[jc::kIbMaxWords];
  uint32_t n = jc::buildTestIb(ib, jc::kIbMaxWords, jc::kIbTestValue);
  pad = n == 16 && ib[0] == 0x401f && ib[1] == 0xDEADBEEF;
  for (uint32_t i = 2; i < 16 && pad; i += 2)
    pad &= ib[i] == 0x60000000 && ib[i + 1] == 0;
  CHECK(pad, "test IB equals Linux's (16 words)");
  jc::DecodeParams d{0x8000110000, 24704, 0x8000210000, 768, 768, 0, 368640};
  n = jc::buildDecodeIb(ib, jc::kIbMaxWords, d);
  CHECK(n == 80, "decode IB is 80 words after padding");
  CHECK(jc::buildDecodeIb(ib, 70, d) == 0,
        "decode IB refuses a buffer that is too small");
  bool types = true;
  for (uint32_t i = 0; i < n; i += 2) {
    uint32_t type = ib[i] >> 28, cond = (ib[i] >> 24) & 15,
             res = (ib[i] >> 18) & 63, reg = ib[i] & 0x3ffff;
    // what Linux's amdgpu_jpeg_dec_parse_cs lets through: type 0 with cond 0,
    // type 3 with cond 3, the nop
    types &= res == 0 &&
             ((type == 0 && cond == 0 && reg >= 0x4000 && reg < 0x4200) ||
              (type == 3 && cond == 3) || ib[i] == 0x60000000);
  }
  CHECK(types,
        "decode IB: every packet is of a kind Linux's command parser accepts");
  // layout
  jc::Layout lay{};
  CHECK(jc::outputLayout(640, 480, 0x3E0000, &lay) && lay.pitch == 768 &&
            lay.alignedHeight == 480 && lay.chromaOffset == 368640 &&
            lay.bytes == 552960,
        "layout 640x480: pitch 768, 480 rows, chroma at 368640, 552960 bytes");
  CHECK(jc::outputLayout(1920, 1080, 0x3E0000, &lay) && lay.pitch == 2048 &&
            lay.alignedHeight == 1088 && lay.bytes == 2048u * 1088 * 3 / 2,
        "layout 1920x1080: pitch 2048, 1088 rows");
  CHECK(jc::outputLayout(641, 481, 0x3E0000, &lay) && lay.pitch == 768 &&
            lay.alignedHeight == 496,
        "layout 641x481 rounds columns and rows up to 16");
  CHECK(!jc::outputLayout(4096, 4096, 0x3E0000, &lay),
        "layout refuses a picture larger than the surface");
  CHECK(!jc::outputLayout(0, 480, 0x3E0000, &lay) &&
            !jc::outputLayout(5000, 16, 0x7fffffff, &lay),
        "layout refuses zero and oversize dimensions");
  // every size the layout accepts fits the surface, at the limits too
  bool fits = true;
  for (uint32_t w = 1; w <= 4096; w += 37)
    for (uint32_t h = 1; h <= 4096; h += 41)
      if (jc::outputLayout(w, h, 0x3E0000, &lay))
        fits &=
            lay.bytes <= 0x3E0000 && lay.pitch >= jc::alignUp(w, 16) &&
            lay.pitch % 16 == 0 &&
            lay.chromaOffset + lay.pitch * (lay.alignedHeight / 2) == lay.bytes;
  CHECK(fits, "layout: whatever it accepts fits the surface (sweep)");
  // stream
  std::vector<uint8_t> file = readFile(samplePath);
  CHECK(!file.empty(), "sample read");
  if (file.empty()) return 1;
  jc::StreamInfo si;
  CHECK(jc::parseStream(file.data(), file.size(), &si) == jc::Stream::Ok &&
            si.width == 640 && si.height == 480,
        "sample as it is: baseline 4:2:0, 640x480");
  std::vector<uint8_t> norm;
  std::string why = jnorm::normalize(file, &norm);
  CHECK(why.empty(), "sample normalises");
  jc::StreamInfo sn;
  CHECK(jc::parseStream(norm.data(), norm.size(), &sn) == jc::Stream::Ok &&
            sn.width == 640 && sn.height == 480,
        "normalised sample: same size");
  CHECK(norm.size() >= 4 && norm[0] == 0xff && norm[1] == 0xd8 &&
            norm[2] == 0xff && norm[3] == 0xdb,
        "normalised sample starts with SOI, DQT (the start Mesa looks for)");
  std::vector<uint8_t> again;
  CHECK(jnorm::normalize(norm, &again).empty() && again == norm,
        "normalising twice changes nothing");
  // no prefix, and no single damaged byte in the headers, makes the parser read
  // outside its input
  size_t accepted = 0;
  for (size_t len = 0; len <= norm.size(); len++) {
    jc::StreamInfo x;
    accepted += parseCopy(norm.data(), len, &x) == jc::Stream::Ok;
  }
  CHECK(accepted == 1,
        "of every prefix of the sample only the whole file is accepted");
  size_t wrongSize = 0;
  for (size_t at = 0; at < sn.scanOffset; at++) {
    for (int bit = 0; bit < 8; bit++) {
      std::vector<uint8_t> bad = norm;
      bad[at] ^= static_cast<uint8_t>(1 << bit);
      jc::StreamInfo x;
      if (parseCopy(bad.data(), bad.size(), &x) == jc::Stream::Ok) {
        jc::Layout l{};
        // an accepted stream with other dimensions must still be checked
        // against the surface
        if (x.width != 640 || x.height != 480)
          wrongSize +=
              !jc::outputLayout(x.width, x.height, 0x3E0000, &l) ? 0 : 1;
      }
      std::vector<uint8_t> o;
      (void)jnorm::normalize(bad, &o);
    }
  }
  printf(
      "     (%zu single-bit header changes still parse with another size; each "
      "goes through the layout check)\n",
      wrongSize);
  {
    // the scan must name the frame's components, in order; the frame's ids
    // must differ
    auto at = [&](uint8_t m) {
      for (size_t i = 2; i + 1 < norm.size(); i++)
        if (norm[i] == 0xff && norm[i + 1] == m) return i;
      return norm.size();
    };
    size_t sos = at(0xda), sof = at(0xc0);
    bool found = sos + 9 < norm.size() && sof + 16 < norm.size();
    std::vector<uint8_t> a = norm, b = norm, c = norm;
    if (found) {
      a[sos + 5] ^= 0x40;                 // first component id of the scan
      std::swap(b[sos + 7], b[sos + 9]);  // Cb and Cr named the other way round
      c[sof + 13] = c[sof + 10];          // Cb's id equal to Y's
    }
    jc::StreamInfo x;
    CHECK(found && parseCopy(a.data(), a.size(), &x) == jc::Stream::BadScan &&
              (b[sos + 7] == b[sos + 9] ||
               parseCopy(b.data(), b.size(), &x) == jc::Stream::BadScan) &&
              parseCopy(c.data(), c.size(), &x) == jc::Stream::BadFrame &&
              parseCopy(norm.data(), norm.size(), &x) == jc::Stream::Ok,
          "a scan naming other components, or in another order, is refused; so "
          "are two components with the same id");
  }
  uint8_t progressive[] = {0xff, 0xd8, 0xff, 0xc2, 0x00, 0x11, 8,   0,
                           16,   0,    16,   3,    1,    0x22, 0,   2,
                           0x11, 0,    3,    0x11, 0,    0xff, 0xd9};
  CHECK(jc::parseStream(progressive, sizeof(progressive), &si) ==
            jc::Stream::Unsupported,
        "progressive JPEG refused");
  std::vector<uint8_t> f444 = norm;
  for (size_t i = 2; i + 20 < f444.size(); i++)
    if (f444[i] == 0xff && f444[i + 1] == 0xc0) {
      f444[i + 11] = 0x11;
      break;
    }
  CHECK(jc::parseStream(f444.data(), f444.size(), &si) == jc::Stream::BadFrame,
        "4:4:4 frame header refused");
  // 4:2:2: the three sampling forms Mesa writes as YUYV, and its surface
  auto withSampling = [&](uint8_t y, uint8_t cb, uint8_t cr) {
    std::vector<uint8_t> v = norm;
    for (size_t i = 2; i + 20 < v.size(); i++)
      if (v[i] == 0xff && v[i + 1] == 0xc0) {
        v[i + 11] = y;
        v[i + 14] = cb;
        v[i + 17] = cr;
        break;
      }
    return v;
  };
  for (auto sf : {std::array<uint8_t, 3>{0x21, 0x11, 0x11},
                  std::array<uint8_t, 3>{0x22, 0x12, 0x12},
                  std::array<uint8_t, 3>{0x22, 0x21, 0x21}}) {
    std::vector<uint8_t> v = withSampling(sf[0], sf[1], sf[2]);
    jc::StreamInfo x;
    char name[96];
    snprintf(name, sizeof name, "sampling %02x%02x%02x is 4:2:2 (YUYV)", sf[0],
             sf[1], sf[2]);
    CHECK(parseCopy(v.data(), v.size(), &x) == jc::Stream::Ok &&
              x.chroma == jc::Chroma::k422 && x.width == 640,
          name);
  }
  {
    std::vector<uint8_t> v = withSampling(0x12, 0x11, 0x11);
    jc::StreamInfo x;
    CHECK(parseCopy(v.data(), v.size(), &x) == jc::Stream::BadFrame,
          "sampling 121111 (4:4:0) refused");
    CHECK(sn.chroma == jc::Chroma::k420, "the 4:2:0 sample reads as 4:2:0");
  }
  jc::Layout l422{};
  CHECK(jc::outputLayout(640, 480, 0x3E0000, &l422, jc::Chroma::k422) &&
            l422.pitch == 1280 && l422.alignedHeight == 480 &&
            l422.chromaOffset == 0 && l422.bytes == 614400 &&
            l422.regPitch == 640 && l422.regUvPitch == 0 &&
            l422.chroma == jc::Chroma::k422,
        "4:2:2 layout 640x480: YUYV, 1280 bytes per row, register pitch 640 "
        "pixels, one plane");
  CHECK(jc::outputLayout(641, 481, 0x3E0000, &l422, jc::Chroma::k422) &&
            l422.pitch == 1536 && l422.alignedHeight == 496,
        "4:2:2 layout rounds columns to 16 and rows to 256 bytes");
  CHECK(!jc::outputLayout(1920, 1088, 0x3E0000, &l422, jc::Chroma::k422),
        "4:2:2 layout refuses what does not fit");
  {
    jc::Layout l{};
    jc::outputLayout(640, 480, 0x3E0000, &l);
    jc::DecodeParams d = jc::decodeParams(l, 0x8000110000, 24704, 0x8000210000);
    CHECK(d.pitch == 768 && d.uvPitch == 768 && d.chromaOffset == 368640 &&
              d.lumaOffset == 0,
          "decodeParams for NV12 gives what the decode stage always sent");
  }
  CHECK(sizeof(jp::Result) == 944, "Result is 944 bytes");
  printf("%s\n", fails == 0 ? "UNIT PASSED" : "UNIT FAILED");
  return fails == 0 ? 0 : 1;
}

int main(int argc, char** argv) {
  if (argc >= 2 && !strcmp(argv[1], "unit") && argc == 3) return unit(argv[2]);
  if (argc == 7 && !strcmp(argv[1], "frame")) {
    uint32_t frame[jc::kFrameWords];
    if (!jc::buildJobFrame(frame, strtoull(argv[2], nullptr, 0),
                           strtoull(argv[3], nullptr, 0),
                           static_cast<uint32_t>(strtoul(argv[4], nullptr, 0)),
                           static_cast<uint32_t>(strtoul(argv[5], nullptr, 0)),
                           strtoull(argv[6], nullptr, 0)))
      return 1;
    for (uint32_t w : frame) printf("%08x\n", w);
    return 0;
  }
  if (argc == 7 && !strcmp(argv[1], "ib")) {
    jc::DecodeParams d{};
    d.bitstreamGpu = strtoull(argv[2], nullptr, 0);
    d.bitstreamBytes = static_cast<uint32_t>(strtoul(argv[3], nullptr, 0));
    d.targetGpu = strtoull(argv[4], nullptr, 0);
    d.pitch = d.uvPitch = static_cast<uint32_t>(strtoul(argv[5], nullptr, 0));
    d.chromaOffset = static_cast<uint32_t>(strtoul(argv[6], nullptr, 0));
    uint32_t ib[jc::kIbMaxWords];
    uint32_t n = jc::buildDecodeIb(ib, jc::kIbMaxWords, d);
    if (n == 0) return 1;
    for (uint32_t i = 0; i < n; i++) printf("%08x\n", ib[i]);
    return 0;
  }
  // ibl <bitstreamVa> <bitstreamBytes> <targetVa> <width> <height> <chroma
  // 0|1>: the IB the kext builds, going through outputLayout and decodeParams
  // as kern_start.cpp does
  if (argc == 8 && !strcmp(argv[1], "ibl")) {
    jc::Layout lay{};
    if (!jc::outputLayout(
            static_cast<uint32_t>(strtoul(argv[5], nullptr, 0)),
            static_cast<uint32_t>(strtoul(argv[6], nullptr, 0)), 0xFFFFFFFFu,
            &lay, static_cast<jc::Chroma>(strtoul(argv[7], nullptr, 0))))
      return 1;
    jc::DecodeParams d =
        jc::decodeParams(lay, strtoull(argv[2], nullptr, 0),
                         static_cast<uint32_t>(strtoul(argv[3], nullptr, 0)),
                         strtoull(argv[4], nullptr, 0));
    uint32_t ib[jc::kIbMaxWords];
    uint32_t n = jc::buildDecodeIb(ib, jc::kIbMaxWords, d);
    if (n == 0) return 1;
    for (uint32_t i = 0; i < n; i++) printf("%08x\n", ib[i]);
    return 0;
  }
  // pm request <context> | pm activate <context> <0|1>: the PowerPlay requests,
  // in x6000_oracle's format
  if (argc >= 4 && !strcmp(argv[1], "pm")) {
    uint64_t context = strtoull(argv[3], nullptr, 0);
    uint8_t bytes[256];
    size_t n = 0;
    uint64_t outSize = 0;
    int hasOut = 0;
    if (!strcmp(argv[2], "request") && argc == 4) {
      jw::PmRequestIn r = jw::pmRequest(context);
      n = sizeof(r);
      memcpy(bytes, &r, n);
      hasOut = 1;
      outSize = sizeof(jw::PmRequestOut);
    } else if (!strcmp(argv[2], "activate") && argc == 5) {
      jw::ActivateIn a = jw::activate(context, atoi(argv[4]) != 0);
      n = sizeof(a);
      memcpy(bytes, &a, n);
    } else {
      return 2;
    }
    printf("insize %zu\nhasout %d\noutsize %llu\n", n, hasOut, outSize);
    for (size_t i = 0; i < n; i += 4) {
      uint32_t w;
      memcpy(&w, bytes + i, 4);
      printf("%08x\n", w);
    }
    return 0;
  }
  fprintf(stderr,
          "usage: cmds_test unit <sample.jpg> | frame ... | ib ... | pm ...\n");
  return 2;
}
