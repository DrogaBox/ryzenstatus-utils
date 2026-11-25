//
//  jpeg_cmds.hpp - the words a JPEG decode job is made of. No kernel parts: the
//  kext and the host tests include this one file.
//
//  Two levels, as on Linux:
//
//  * the ring frame, 64 words copied into the JRBC ring by Apple's
//    queue_jpeg_decode_2_0_submit_frame: start marker, "run this IB", fence,
//    end marker, padding. The words are those Apple's own
//    queue_jpeg_decode_2_0_build_command (KDK 0x3d7d4) writes for the commands
//    0x20007, 0x20002, 0x20003, 0x20008 and 0x20001; tests/hwlibs_oracle.c
//    runs that function from the KDK binary and compares.
//
//  * the IB, the per-picture register writes. HWLibs has no code for it. It is
//    Mesa's vcn_jpeg_build_decode_cmd (src/amd/common/ac_vcn_dec.c) for the
//    register layout Mesa uses on VCN 2.0 to 4.0 (RDECODE_JPEG_VER_2), with a
//    linear NV12 target; tests/mesa_oracle.c compiles Mesa's function itself
//    and compares.
//
//  It also holds the checks that keep the block inside its buffers: the size
//  of the picture is read here from the stream itself (parseStream), because
//  the hardware writes as many rows as the stream says, whatever the caller
//  believes.
//
#pragma once
#include <stddef.h>
#include <stdint.h>

namespace jc {

// PACKETJ(reg, r, cond, type) of Linux jpeg_v2_0.h; r is always 0.
constexpr uint32_t pktj(uint32_t reg, uint32_t cond, uint32_t type) {
  return (reg & 0x3FFFF) | ((cond & 0xF) << 24) | ((type & 0xF) << 28);
}
constexpr uint32_t kNop = 0x60000000;  // PACKETJ(0, 0, 0, TYPE6)

// Register numbers as the ring and the IB name them ("internal offsets").
// For the JPEG registers of vcn_3_0_0_offset.h (BASE_IDX 1) the internal
// number is the header's offset + 0x3f80; each one was checked against it.
namespace reg {
// ring level (Linux jpeg_v2_0.h)
constexpr uint32_t kGpcomCmd = 0x4029;  // mmUVD_JPEG_GPCOM_CMD
constexpr uint32_t kGpcomData0 = 0x402a;
constexpr uint32_t kGpcomData1 = 0x402b;
constexpr uint32_t kIbSize = 0x4082;         // mmUVD_JRBC_IB_SIZE
constexpr uint32_t kRbRefData = 0x4084;      // mmUVD_JRBC_RB_REF_DATA
constexpr uint32_t kRbCondRdTimer = 0x4085;  // mmUVD_JRBC_RB_COND_RD_TIMER
constexpr uint32_t kJrbcStatus = 0x4089;     // mmUVD_JRBC_STATUS
constexpr uint32_t kIbVmid = 0x40cf;         // mmUVD_LMI_JRBC_IB_VMID
constexpr uint32_t kJpegVmid = 0x40d1;       // mmUVD_LMI_JPEG_VMID
constexpr uint32_t kIbBarLow = 0x40e8;       // mmUVD_LMI_JRBC_IB_64BIT_BAR_LOW
constexpr uint32_t kIbBarHigh = 0x40e9;
constexpr uint32_t kMemWrBarLow =
    0x40ea;  // mmUVD_LMI_JRBC_RB_MEM_WR_64BIT_BAR_LOW
constexpr uint32_t kMemWrBarHigh = 0x40eb;
constexpr uint32_t kMemRdBarLow =
    0x40ec;  // mmUVD_LMI_JRBC_RB_MEM_RD_64BIT_BAR_LOW
constexpr uint32_t kMemRdBarHigh = 0x40ed;
constexpr uint32_t kExternalReg =
    0x1bfff;  // mmUVD_JRBC_EXTERNAL_REG_INTERNAL_OFFSET
constexpr uint32_t kExternalWrite =
    0x18000;  // JRBC_DEC_EXTERNAL_REG_WRITE_ADDR
// IB level (Mesa ac_vcn_dec.h, vcnip*)
constexpr uint32_t kJpegCntl = 0x4000;  // mmUVD_JPEG_CNTL
constexpr uint32_t kRbBase = 0x4001;    // mmUVD_JPEG_RB_BASE
constexpr uint32_t kRbWptr = 0x4002;
constexpr uint32_t kRbRptr = 0x4003;
constexpr uint32_t kRbSize = 0x4004;
constexpr uint32_t kIntEn = 0x400a;  // mmUVD_JPEG_INT_EN
constexpr uint32_t kTierCntl2 = 0x400f;
constexpr uint32_t kOutbufCntl = 0x401c;
constexpr uint32_t kOutbufWptr = 0x401d;
constexpr uint32_t kOutbufRptr = 0x401e;
constexpr uint32_t kPitch = 0x401f;  // mmUVD_JPEG_PITCH
constexpr uint32_t kUvPitch = 0x4020;
constexpr uint32_t kYTiling = 0x4024;  // mmJPEG_DEC_Y_GFX10_TILING_SURFACE
constexpr uint32_t kUvTiling = 0x4025;
constexpr uint32_t kAddrMode = 0x4027;  // mmJPEG_DEC_ADDR_MODE
constexpr uint32_t kIndex = 0x402c;     // mmUVD_JPEG_INDEX
constexpr uint32_t kData = 0x402d;
constexpr uint32_t kSoftRst = 0x402f;        // mmUVD_JPEG_DEC_SOFT_RST
constexpr uint32_t kIbCondRdTimer = 0x408e;  // mmUVD_JRBC_IB_COND_RD_TIMER
constexpr uint32_t kIbRefData = 0x408f;
constexpr uint32_t kReadBarLow = 0x40e0;  // mmUVD_LMI_JPEG_READ_64BIT_BAR_LOW
constexpr uint32_t kReadBarHigh = 0x40e1;
constexpr uint32_t kWriteBarLow = 0x40e2;  // mmUVD_LMI_JPEG_WRITE_64BIT_BAR_LOW
constexpr uint32_t kWriteBarHigh = 0x40e3;
}  // namespace reg

constexpr uint32_t kFrameWords =
    64;  // the queue is created with 256-byte frames
constexpr uint32_t kIbMaxWords = 128;  // Mesa's max_decode_cmd_dw
constexpr uint32_t kRingTestValue =
    0xABADCAFE;  // Linux amdgpu_jpeg_dec_ring_test_ring
constexpr uint32_t kRingTestOther =
    0xCAFEDEAD;  // used when the register already holds the first one
constexpr uint32_t kIbTestValue =
    0xDEADBEEF;  // Linux amdgpu_jpeg_dec_ring_test_ib

// A bounded word writer: once full it stops writing and reports failure.
struct Words {
  uint32_t* p;
  uint32_t cap;
  uint32_t n = 0;
  bool ok = true;
  constexpr Words(uint32_t* buffer, uint32_t capacity)
      : p(buffer), cap(capacity) {}
  constexpr void put(uint32_t header, uint32_t value) {
    if (n + 2 > cap) {
      ok = false;
      return;
    }
    p[n++] = header;
    p[n++] = value;
  }
  constexpr void set(uint32_t r, uint32_t cond, uint32_t type, uint32_t value) {
    put(pktj(r, cond, type), value);
  }
  constexpr void padTo(uint32_t multiple) {
    while (ok && (n % multiple) != 0) put(kNop, 0);
  }
};

// ---- ring frame
// -----------------------------------------------------------------

// command 0x20007 / 0x20008
constexpr void putStart(Words& w) {
  w.put(reg::kExternalReg, 0x68e04);
  w.put(reg::kExternalWrite, 0x80010000);
}
constexpr void putEnd(Words& w) {
  w.put(reg::kExternalReg, 0x68e04);
  w.put(reg::kExternalWrite, 0x00010000);
}
// command 0x20002: run the IB at ibGpu (ibWords long) with the given VMID.
constexpr void putIb(Words& w, uint32_t vmid, uint64_t ibGpu, uint32_t ibWords,
                     uint64_t ringGpu) {
  uint32_t v = vmid | (vmid << 4);
  w.put(reg::kIbVmid, v);
  w.put(reg::kJpegVmid, v);
  w.put(reg::kIbBarHigh, static_cast<uint32_t>(ibGpu >> 32));
  w.put(reg::kIbBarLow, static_cast<uint32_t>(ibGpu));
  w.put(reg::kIbSize, ibWords);
  w.put(reg::kMemRdBarLow, static_cast<uint32_t>(ringGpu));
  w.put(reg::kMemRdBarHigh, static_cast<uint32_t>(ringGpu >> 32));
  w.put(pktj(0, 0, 2), 0);
  w.put(reg::kRbCondRdTimer, 0x01400200);
  w.put(reg::kRbRefData, 2);
  w.put(pktj(reg::kJrbcStatus, 3, 3), 2);
}
// command 0x20003: write seq to the memory at fenceGpu, then read it back.
constexpr void putFence(Words& w, uint32_t seq, uint64_t fenceGpu) {
  uint32_t lo = static_cast<uint32_t>(fenceGpu);
  uint32_t hi = static_cast<uint32_t>(fenceGpu >> 32);
  w.put(reg::kGpcomData0, seq);
  w.put(reg::kGpcomData1, seq);
  w.put(reg::kMemWrBarLow, lo);
  w.put(reg::kMemWrBarHigh, hi);
  w.put(reg::kGpcomCmd, 8);
  w.put(pktj(reg::kGpcomCmd, 0, 4), 0);
  w.put(reg::kRbCondRdTimer, 0x01400200);
  w.put(reg::kRbRefData, seq);
  w.put(reg::kMemRdBarLow, lo);
  w.put(reg::kMemRdBarHigh, hi);
  w.put(pktj(0, 3, 2), 0xFFFFFFFF);
  w.put(reg::kExternalReg, 0x3fbc);
  w.put(reg::kExternalWrite, 1);
}

// The frame of a job: start, IB, fence, end, padding. No trap command
// (0x20004): macOS has nobody listening for the JPEG interrupt, the caller
// polls the fence.
constexpr bool buildJobFrame(uint32_t frame[kFrameWords], uint64_t ringGpu,
                             uint64_t ibGpu, uint32_t ibWords, uint32_t seq,
                             uint64_t fenceGpu) {
  Words w(frame, kFrameWords);
  putStart(w);
  putIb(w, 0, ibGpu, ibWords, ringGpu);
  putFence(w, seq, fenceGpu);
  putEnd(w);
  w.padTo(kFrameWords);
  return w.ok && w.n == kFrameWords;
}

// Linux's ring test: one register write straight in the ring, no IB, no fence.
constexpr bool buildRingTestFrame(uint32_t frame[kFrameWords], uint32_t value) {
  Words w(frame, kFrameWords);
  w.set(reg::kPitch, 0, 0, value);
  w.padTo(kFrameWords);
  return w.ok && w.n == kFrameWords;
}

// ---- IBs
// --------------------------------------------------------------------------

// Linux's IB test (amdgpu_jpeg_dec_set_reg): one register write and padding.
constexpr uint32_t buildTestIb(uint32_t* ib, uint32_t cap, uint32_t value) {
  Words w(ib, cap);
  w.set(reg::kPitch, 0, 0, value);
  w.padTo(16);
  return w.ok ? w.n : 0;
}

struct DecodeParams {
  uint64_t bitstreamGpu;
  uint32_t bitstreamBytes;  // padded to 128, the padding zeroed
  uint64_t targetGpu;       // start of the surface
  uint32_t pitch;  // Mesa's dt_pitch[0]: pixels per row (= bytes for NV12 luma)
  uint32_t uvPitch;     // Mesa's dt_pitch[1]: chroma row (bytes for NV12, 0 for
                        // one plane)
  uint32_t lumaOffset;  // from targetGpu
  uint32_t chromaOffset;  // from targetGpu (0 for one plane)
};

// Mesa's vcn_jpeg_build_decode_cmd for RDECODE_JPEG_VER_2, a linear surface
// (RDECODE_TILE_LINEAR, ADDR_SW_LINEAR, both 0), no crop and no colour
// conversion, then the padding Mesa's winsys adds (to 16 words).
constexpr uint32_t buildDecodeIb(uint32_t* ib, uint32_t cap,
                                 const DecodeParams& d) {
  constexpr uint32_t kTileLinear = 0, kSwizzleLinear = 0;
  Words w(ib, cap);
  // jpeg soft reset, and wait until it shows in the SCLK domain
  w.set(reg::kSoftRst, 0, 0, 1);
  w.set(reg::kIbCondRdTimer, 0, 0, 0x01400200);
  w.set(reg::kIbRefData, 0, 0, 0x1 << 0x10);
  w.set(reg::kSoftRst, 3, 3, 0x1 << 0x10);
  w.set(reg::kSoftRst, 0, 0, 0);
  w.set(reg::kIbRefData, 0, 0, 0 << 0x10);
  w.set(reg::kSoftRst, 3, 3, 0x1 << 0x10);
  // bitstream
  w.set(reg::kReadBarHigh, 0, 0, static_cast<uint32_t>(d.bitstreamGpu >> 32));
  w.set(reg::kReadBarLow, 0, 0, static_cast<uint32_t>(d.bitstreamGpu));
  w.set(reg::kRbBase, 0, 0, 0);
  w.set(reg::kRbSize, 0, 0, 0xfffffff0);
  w.set(reg::kRbWptr, 0, 0, d.bitstreamBytes >> 2);
  // target
  w.set(reg::kPitch, 0, 0, d.pitch >> 4);
  w.set(reg::kUvPitch, 0, 0, d.uvPitch >> 4);
  w.set(reg::kAddrMode, 0, 0, kTileLinear | (kTileLinear << 2));
  w.set(reg::kYTiling, 0, 0, kSwizzleLinear);
  w.set(reg::kUvTiling, 0, 0, kSwizzleLinear);
  w.set(reg::kWriteBarHigh, 0, 0, static_cast<uint32_t>(d.targetGpu >> 32));
  w.set(reg::kWriteBarLow, 0, 0, static_cast<uint32_t>(d.targetGpu));
  w.set(reg::kIndex, 0, 0, 0);
  w.set(reg::kData, 0, 0, d.lumaOffset);
  w.set(reg::kIndex, 0, 0, 1);
  w.set(reg::kData, 0, 0, d.chromaOffset);
  w.set(reg::kIndex, 0, 0, 2);
  w.set(reg::kData, 0, 0, 0);
  w.set(reg::kTierCntl2, 0, 0, 0);
  w.set(reg::kOutbufRptr, 0, 0, 0);
  w.set(reg::kOutbufCntl, 0, 0,
        (0x00001587 & ~0x00000180u) | (0x1 << 0x7) | (0x1 << 0x6));
  // error interrupts, start
  w.set(reg::kIntEn, 0, 0, 0xfffffffe);
  w.set(reg::kJpegCntl, 0, 0, 0x6);
  // wait until the whole bitstream was fetched, then until the output is idle
  w.set(reg::kIbRefData, 0, 0, d.bitstreamBytes >> 2);
  w.set(reg::kIbCondRdTimer, 0, 0, 0x01400200);
  w.set(reg::kRbRptr, 3, 3, 0xffffffff);
  w.set(reg::kIbRefData, 0, 0, 0xffffffff);
  w.set(reg::kOutbufWptr, 3, 3, 0x00000001);
  // stop
  w.set(reg::kJpegCntl, 0, 0, 0x4);
  w.padTo(16);
  return w.ok ? w.n : 0;
}

// ---- where the picture goes
// ----------------------------------------------------------

// What the block writes depends on the JPEG itself: JPEG 2.0 has no
// output-format register, the sampling factors in the frame header decide. Mesa
// offers NV12 for 4:2:0 and YUYV (PIPE_FORMAT_YUYV, one packed plane) for 4:2:2
// on this block (si_vid_is_format_supported, PIPE_VIDEO_PROFILE_JPEG_BASELINE);
// no NV16.
enum class Chroma : uint32_t { k420 = 0, k422 = 1 };
struct Layout {
  uint32_t
      pitch;  // bytes per row (NV12: luma and chroma alike; YUYV: 2 per pixel)
  uint32_t alignedHeight;  // rows the block writes
  uint32_t chromaOffset;   // NV12: pitch * alignedHeight; YUYV: 0
  uint32_t bytes;          // all the block may write
  Chroma chroma = Chroma::k420;
  uint32_t regPitch = 0;    // Mesa's dt_pitch[0]: pixels per row
  uint32_t regUvPitch = 0;  // Mesa's dt_pitch[1]
};
// 4096 unless the build says otherwise: nothing larger has run. Linux's limit
// for this block on Navi 21 is 16384 x 16384 (nv.c, sc_video_codecs_decode).
#ifndef JC_MAX_DIM
#define JC_MAX_DIM 4096
#endif
constexpr uint32_t kMaxWidth = JC_MAX_DIM, kMaxHeight = JC_MAX_DIM;
constexpr uint32_t alignUp(uint32_t v, uint32_t a) {
  return (v + a - 1) / a * a;
}

// The block writes whole MCUs, so rows and columns are counted rounded up to
// 16; the row is rounded to 256 bytes as Mesa's linear surfaces are on this GPU
// family. 4:2:0 -> NV12 (two planes). 4:2:2 -> YUYV (one plane, 2 bytes per
// pixel; Mesa's YUYV surface has blk_w 2 and bpe 4, so dt_pitch[0] counts
// pixels).
constexpr bool outputLayout(uint32_t width, uint32_t height, uint32_t capacity,
                            Layout* out, Chroma chroma = Chroma::k420) {
  if (width == 0 || height == 0 || width > kMaxWidth || height > kMaxHeight)
    return false;
  uint32_t rows = alignUp(height, 16);
  if (chroma == Chroma::k422) {
    uint32_t pitch = alignUp(alignUp(width, 16) * 2, 256);
    uint64_t bytes = static_cast<uint64_t>(pitch) * rows;
    if (bytes > capacity) return false;
    out->pitch = pitch;
    out->alignedHeight = rows;
    out->chromaOffset = 0;
    out->bytes = static_cast<uint32_t>(bytes);
    out->chroma = chroma;
    out->regPitch = pitch / 2;
    out->regUvPitch = 0;
    return true;
  }
  uint32_t pitch = alignUp(alignUp(width, 16), 256);
  uint64_t bytes = static_cast<uint64_t>(pitch) * rows * 3 / 2;
  if (bytes > capacity) return false;
  out->pitch = pitch;
  out->alignedHeight = rows;
  out->chromaOffset = pitch * rows;
  out->bytes = static_cast<uint32_t>(bytes);
  out->chroma = Chroma::k420;
  out->regPitch = pitch;
  out->regUvPitch = pitch;
  return true;
}

// The IB parameters for a surface laid out by outputLayout.
constexpr DecodeParams decodeParams(const Layout& l, uint64_t bitstreamGpu,
                                    uint32_t bitstreamBytes,
                                    uint64_t targetGpu) {
  DecodeParams d{};
  d.bitstreamGpu = bitstreamGpu;
  d.bitstreamBytes = bitstreamBytes;
  d.targetGpu = targetGpu;
  d.pitch = l.regPitch;
  d.uvPitch = l.regUvPitch;
  d.lumaOffset = 0;
  d.chromaOffset = l.chromaOffset;
  return d;
}

// ---- the stream
// ------------------------------------------------------------------------

enum class Stream : uint32_t {
  Ok = 0,
  TooShort,  // not even SOI + EOI
  NoSoi,
  BadSegment,   // a marker or length that does not fit
  Unsupported,  // a frame type other than baseline (SOF0)
  BadFrame,     // SOF0 that is not 8-bit, 3 components, 4:2:0 or 4:2:2
  TwoFrames,
  NoTables,  // DQT or DHT missing before the scan
  NoFrame,   // SOS before SOF0
  NoScan,
  NoEoi,
};

struct StreamInfo {
  uint32_t width = 0;
  uint32_t height = 0;
  uint32_t scanOffset = 0;  // first byte after the SOS header
  uint32_t restartInterval = 0;
  Chroma chroma = Chroma::k420;
};

// Walks the markers up to the scan and reads the picture size from SOF0.
// Accepts baseline, 8 bits, three components sampled for NV12 (4:2:0) or YUYV
// (4:2:2: webcams' 2x1/1x1/1x1 and ffmpeg's 2x2/1x2/1x2), with its own DQT and
// DHT.
constexpr Stream parseStream(const uint8_t* d, size_t n, StreamInfo* out) {
  if (n < 4) return Stream::TooShort;
  if (d[0] != 0xff || d[1] != 0xd8) return Stream::NoSoi;
  if (d[n - 2] != 0xff || d[n - 1] != 0xd9) return Stream::NoEoi;
  bool frame = false, dqt = false, dht = false;
  StreamInfo info;
  size_t i = 2;
  while (true) {
    if (i + 4 > n) return Stream::NoScan;
    if (d[i] != 0xff) return Stream::BadSegment;
    uint8_t m = d[i + 1];
    size_t len = (static_cast<size_t>(d[i + 2]) << 8) | d[i + 3];
    if (len < 2 || i + 2 + len > n) return Stream::BadSegment;
    const uint8_t* s = d + i + 4;  // segment body, len - 2 bytes
    if (m == 0xc0) {
      if (frame) return Stream::TwoFrames;
      if (len != 17 || s[0] != 8 || s[5] != 3) return Stream::BadFrame;
      info.height = (static_cast<uint32_t>(s[1]) << 8) | s[2];
      info.width = (static_cast<uint32_t>(s[3]) << 8) | s[4];
      // the sampling factors as Mesa's radeon_dec_jpeg_check_format reads them
      // (Y, Cb, Cr): 0x221111 -> NV12; 0x211111, 0x221212, 0x222121 -> YUYV
      uint32_t sf = (static_cast<uint32_t>(s[7]) << 16) |
                    (static_cast<uint32_t>(s[10]) << 8) | s[13];
      if (sf == 0x221111)
        info.chroma = Chroma::k420;
      else if (sf == 0x211111 || sf == 0x221212 || sf == 0x222121)
        info.chroma = Chroma::k422;
      else
        return Stream::BadFrame;
      if (info.width == 0 || info.height == 0) return Stream::BadFrame;
      frame = true;
    } else if (m == 0xdb) {
      dqt = true;
    } else if (m == 0xc4) {
      dht = true;
    } else if (m == 0xdd) {
      if (len != 4) return Stream::BadSegment;
      info.restartInterval = (static_cast<uint32_t>(s[0]) << 8) | s[1];
    } else if (m == 0xda) {
      if (!frame) return Stream::NoFrame;
      if (!dqt || !dht) return Stream::NoTables;
      info.scanOffset = static_cast<uint32_t>(i + 2 + len);
      *out = info;
      return Stream::Ok;
    } else if ((m >= 0xe0 && m <= 0xef) || m == 0xfe) {
      // APPn and COM carry nothing the decoder needs
    } else {
      return Stream::Unsupported;
    }
    i += 2 + len;
  }
}

constexpr const char* streamText(Stream s) {
  switch (s) {
    case Stream::Ok:
      return "ok";
    case Stream::TooShort:
      return "too short";
    case Stream::NoSoi:
      return "does not start with SOI";
    case Stream::BadSegment:
      return "a segment does not fit";
    case Stream::Unsupported:
      return "not a baseline JPEG";
    case Stream::BadFrame:
      return "frame header is not 8-bit 4:2:0 or 4:2:2 with 3 components";
    case Stream::TwoFrames:
      return "more than one frame header";
    case Stream::NoTables:
      return "quantisation or Huffman tables missing";
    case Stream::NoFrame:
      return "scan before the frame header";
    case Stream::NoScan:
      return "no scan";
    case Stream::NoEoi:
      return "does not end with EOI";
  }
  return "?";
}

}  // namespace jc
