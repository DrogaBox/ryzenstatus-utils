// patches.c - the user-space patches applied by vcnencodefix: preset, wide
// and hevc10 inside VTEncoderXPCService, cc inside ContinuityCaptureAgent and
// avconferenced.
//
// 1. preset (AMDRadeonVADriver2, VAUveEncoder::EncodePicture)
//    The driver reads the VCN preset from VAUveEncoder+0xA0 on every frame and,
//    when it is not 0, appends the firmware's "preset encode mode" packet.
//    Nothing in Apple's stack sets that field, so the firmware default is used,
//    which is slower than any preset. The patch turns the load into a constant:
//        mov eax, [rbx+0A0h]      8B 83 A0 00 00 00
//    ->  mov eax, <op> ; nop      B8 xx xx xx xx 90
//
// 2. wide (AppleGVAHEVCEncoder, -[MetalFrameStatisticsContext
// execute:prevBuffer:syncMode:])
//    For every frame the HEVC plug-in runs the Metal kernel frameStats16x16Tex
//    over a grid of (width/16) x (height/16) threads, dispatched as
//    numThreadgroups = (1, height/16, 1) with threadsPerThreadgroup =
//    (width/16, 1, 1). That pipeline allows at most 256 threads per group on
//    Navi 21, so any width above 4096 asks for more than the limit and the
//    GPU's compute channel hangs for seconds on every frame. The kernel only
//    uses thread_position_in_grid (no threadgroup memory, barriers or
//    threadgroup ids; read from the AIR of
//    AppleGVAHEVCFrameStatistics.metallib), so the same grid can be split
//    differently. The patch changes the arguments right before
//    dispatchThreadgroups:threadsPerThreadgroup:, on every frame:
//        t = threadsPerThreadgroup.x; g = 1;
//        while (t > 256 && t is even) { t /= 2; g *= 2; }
//        if (t > 256) { g *= t; t = 1; }
//        threadsPerThreadgroup.x = t; numThreadgroups.x *= g;
//    The grid is unchanged, and for widths up to 4096 the arguments are exactly
//    the original ones. At the call site the original argument copy is kept,
//    followed by a jump to 56 unused bytes between the end of the load commands
//    and __text (zero-filled, mapped executable with the rest of __TEXT), which
//    hold the code above, the selector load the call site gave up, and the jump
//    back.
//
// 3. cc (VideoProcessing, inside ContinuityCaptureAgent and avconferenced)
//    Continuity Camera and FaceTime decode the other side's video with
//    AVConference, which creates the decoder through VideoProcessing's VCPDec.
//    Both put DecoderUsage = 1 (kVTVideoDecoderSpecification_Usage) in the
//    decoder specification: AVConference itself (VideoDecoder_NewFormat_
//    InitDecoder, CFDictionarySetValue), and VCPDec again
//    (CFDictionaryAddValue, which keeps the value already there). With that key
//    AppleGVA takes its FaceTime path, which the AMD driver refuses ("[HEVC]
//    GVA ERROR: Couldn't set the stream resolution"), and VCPDec falls back to
//    software. No preference avoids it (FaceTimeDecoder in
//    com.apple.VideoConference only flips a flag). AVConference then sends the
//    same key as a session property (kVTDecompressionPropertyKey_Usage, the
//    same string), which VCPDecompressionSessionSetProperty passes on for HEVC.
//    Apple's own code already handles both for other codecs on a few Mac Pro /
//    iMac Pro board-ids: before the hardware decoder it removes the key from
//    the specification (and puts it back for the software retry if the
//    hardware one fails), and it skips the property ("skip %@ property to
//    avoid usage conflict with decoder description"). The patch makes both run
//    for every codec and board-id:
//    A: before the hardware decoder, the codec check that skips the removal
//       for HEVC becomes a short jump straight to the removal:
//           cmp eax, <fourcc> ; jg ...   3D xx xx xx xx 7F xx
//       ->  jmp removal ; nop            EB xx 0F 1F 44 00 00
//    B: in VCPDecompressionSessionSetProperty, the flag test that leads to the
//       codec and board-id checks becomes a jump straight to Apple's own
//       DecoderUsage check: the key is skipped, every other key takes the
//       path the original took for a session with the flag set (checked: that
//       check's "not DecoderUsage" jump lands exactly there).
//           cmp byte [rbx+XX], 0 ; jz codec_checks   80 7B XX 00 0F 84 ..
//       ->  jmp usage_check ; nop                    E9 xx xx xx xx 0F 1F ..
//    K, never written, pins the key: VCPDec's load of
//    kVTVideoDecoderSpecification_Usage into the stack slot that A's removal
//    reads, and the same key B's check loads.
//    Only the patched process's copy of the pages changes. A test with an
//    interpose library that drops the same key from the specification and
//    the property gave "Created HW video decoder" at 60 fps on an RX 6900 XT
//    (15.8.2, Continuity Camera).
//    E: FaceTime's encoder. avconferenced creates it through
//       VCPCompressionSessionCreate with usage 42, and on the board-ids
//       iMacPro1,1 and MacPro7,1 a check sends that session to the T2's
//       remote encoder (SideCar), which a Mac without a T2 does not have: "No
//       bridgeOS device available", error -18, no video. The same check makes
//       VCPCodecCopyProperties report H.264 as unsupported for usage 42, so
//       AVConference offers HEVC, which the local path refuses ("No HEVC video
//       encoder support for FaceTime on Mac yet"). Apart from the board-ids
//       the check returns true only when the BridgeEncode preference is set
//       and a bridge device really exists. The patch jumps over the two
//       board-id compares to the release of the board-id string and that
//       preference check, so the board-id no longer counts:
//           lea rsi, <board-id 1>       48 8D 35 xx xx xx xx
//       ->  jmp release ; (dead bytes)  EB 2A xx xx xx xx xx
//       Then H.264 is reported as supported and the session is a local
//       VideoToolbox one (h264.gva when hardware is required). Checked on this
//       code in a test process on a MacPro7,1 board-id (26.7.3, RX 6800 XT):
//       before, VCPCodec_AVC1 0 and VCPCompressionSessionCreate -18; after,
//       VCPCodec_AVC1 1 and an H.264 session with hardware required that
//       encoded 30 frames (tests/ftenc_test.c). Not yet run in a FaceTime
//       call.
// 4. hevc10 (AMDRadeonVADriver2, VCN 3 HEVC 10-bit encode)
//    Two sites in the driver's __text are patched as one unit:
//    a) Vcn3Encoder::setInputAndOutputFormatParams (+0x2a): for a 10-bit HEVC
//       session, the driver sends 8-bit NV12 in the VCN input format packet
//       because the context pixel format is NV12 (and its x420 branch leaves
//       the packing format at 0). The patch uses the 10-bit SPS flag at
//       [rbx+42Ch] (already used for the output packet) to set 10-bit and P010
//       for YUV HEVC while leaving 8-bit HEVC, H.264 and RGB unchanged. The
//       two rip-relative vmovsd loads stay at the same offsets.
//    b) AVDVcn3HevcEncDataProcessor::setupDeblocking (+0x83): for 10-bit HEVC,
//       AppleGVAHEVCEncoder sets slice_cr_qp_offset = -3 in the slice header,
//       which the driver writes into the bitstream, but setupDeblocking only
//       copies pps_cb/cr_qp_offset (0, 0) into the VCN deblocking packet. The
//       patch adds the slice's cb/cr QP offsets to the picture's before
//       sending the packet, as Mesa does (0 + 0 for 8-bit).
#include "patches.h"

#include <stdio.h>
#include <string.h>

const char* const kPresetImage =
    "/System/Library/Extensions/AMDRadeonVADriver2.bundle/Contents/MacOS/"
    "AMDRadeonVADriver2";
// The site's bytes per build (the jz distance differs on Sonoma). Same code in
// every build: VAUveEncoder::EncodePicture reads the preset from +0xA0 and,
// when it is not 0, stores it in the frame parameters (+0x30) and sets the flag
// that appends the preset packet (compared in Hex-Rays against 26.7.3).
static const PresetBuild kPresetBuilds[] = {
    {"26.7.4 (25G422)",
     "F7D8F584-9EC1-39DB-857C-769697294957",
     // 26.7.4: same driver code as 26.7.3 (all 2760 functions identical; only a
     // build path in __cstring differs)
     {0x8b, 0x83, 0xa0, 0x00, 0x00, 0x00,        // mov eax, [rbx+0A0h]
      0x85, 0xc0,                                // test eax, eax
      0x74, 0x11,                                // jz +11h
      0x48, 0x8b, 0x8b, 0x58, 0x04, 0x00, 0x00,  // mov rcx, [rbx+458h]
      0x89, 0x41, 0x30}},                        // mov [rcx+30h], eax
    {"26.7.3 (25G342)",
     "1181E2CA-31B3-3DF0-90E2-3AE70552D753",
     {0x8b, 0x83, 0xa0, 0x00, 0x00, 0x00,        // mov eax, [rbx+0A0h]
      0x85, 0xc0,                                // test eax, eax
      0x74, 0x11,                                // jz +11h
      0x48, 0x8b, 0x8b, 0x58, 0x04, 0x00, 0x00,  // mov rcx, [rbx+458h]
      0x89, 0x41, 0x30}},                        // mov [rcx+30h], eax
    {"15.8.2 (24H232), 15.8.3 (24H241)",
     "5D90FED3-BCBF-3475-9F4B-8FC00026D3AB",
     {0x8b, 0x83, 0xa0, 0x00, 0x00, 0x00, 0x85, 0xc0, 0x74, 0x11,
      0x48, 0x8b, 0x8b, 0x58, 0x04, 0x00, 0x00, 0x89, 0x41, 0x30}},
    {"14.8.9 (23J631)",
     "C637BF67-BF58-39FE-937A-827486BE9BFB",
     {0x8b, 0x83, 0xa0, 0x00, 0x00, 0x00, 0x85, 0xc0, 0x74, 0x0f,
      0x48, 0x8b, 0x8b, 0x58, 0x04, 0x00, 0x00, 0x89, 0x41, 0x30}},
};
const PresetBuild* preset_build(const char* uuid) {
  for (size_t i = 0; i < sizeof(kPresetBuilds) / sizeof(kPresetBuilds[0]); i++)
    if (!strcmp(kPresetBuilds[i].uuid, uuid)) return &kPresetBuilds[i];
  return NULL;
}
void build_preset(uint8_t out[kPresetLen], uint32_t op) {
  out[0] = 0xb8;  // mov eax, imm32
  memcpy(out + 1, &op, 4);
  out[5] = 0x90;  // nop
}

int is_preset_patched(const uint8_t cur[kPresetLen]) {
  uint32_t op;
  memcpy(&op, cur + 1, 4);
  return cur[0] == 0xb8 && cur[5] == 0x90 &&
         (op == kPresetSpeed || op == kPresetBalance || op == kPresetQuality);
}

const char* const kWideImage =
    "/System/Library/Video/Plug-Ins/AppleGVAHEVCEncoder.bundle/Contents/MacOS/"
    "AppleGVAHEVCEncoder";
// The call site's bytes per build: selector load and argument copy for
// dispatchThreadgroups:threadsPerThreadgroup: in -[MetalFrameStatisticsContext
// execute:prevBuffer:syncMode:]. Only the selector reference and the two kept
// register moves differ; the argument copy and its stack offsets are the same
// in every build. The Metal kernel (frameStats16x16Tex) uses only
// thread_position_in_grid in all of them.
static const WideBuild kWideBuilds[] = {
    {"26.7.4 (25G422)",
     "01F6B94A-A77D-3549-B18B-CBA81F4630B3",  // site 0x13601, cave 0xE78
     // __TEXT and __DATA byte-identical to 26.7.3; only LC_UUID, the SDK in
     // LC_BUILD_VERSION and the signature differ
     {0x48, 0x8b, 0x35, 0xb8, 0x1f, 0x02, 0x00, 0x48, 0x8b, 0x45, 0xa8, 0x48,
      0x89, 0x44, 0x24, 0x28, 0x0f, 0x10, 0x45, 0x98, 0x0f, 0x11, 0x44, 0x24,
      0x18, 0x48, 0x8b, 0x45, 0x90, 0x48, 0x89, 0x44, 0x24, 0x10, 0x0f, 0x10,
      0x45, 0x80, 0x0f, 0x11, 0x04, 0x24, 0x49, 0x89, 0xdd, 0x48, 0x89, 0xdf}},
    {"26.7.3 (25G342)",
     "D2B848E1-ACD9-396B-8948-0882C65F601F",  // site 0x13601, cave 0xE78
     {0x48, 0x8b, 0x35, 0xb8, 0x1f, 0x02,
      0x00,  //  0: mov rsi,
             //  selRef_dispatchThreadgroups_threadsPerThreadgroup_
      0x48, 0x8b, 0x45, 0xa8,  //  7: mov rax, [rbp-58h] threadsPerThreadgroup.z
      0x48, 0x89, 0x44, 0x24, 0x28,  // 11: mov [rsp+28h], rax
      0x0f, 0x10, 0x45, 0x98,        // 16: movups xmm0, [rbp-68h]
                                     // threadsPerThreadgroup.x/.y
      0x0f, 0x11, 0x44, 0x24, 0x18,  // 20: movups [rsp+18h], xmm0
      0x48, 0x8b, 0x45, 0x90,        // 25: mov rax, [rbp-70h] numThreadgroups.z
      0x48, 0x89, 0x44, 0x24, 0x10,  // 29: mov [rsp+10h], rax
      0x0f, 0x10, 0x45, 0x80,        // 34: movups xmm0, [rbp-80h]
                                     // numThreadgroups.x/.y
      0x0f, 0x11, 0x04, 0x24,        // 38: movups [rsp], xmm0
      0x49, 0x89, 0xdd,              // 42: mov r13, rbx              (kept)
      0x48, 0x89, 0xdf}},            // 45: mov rdi, rbx              (kept)
    {"15.8.2 (24H232), 15.8.3 (24H241)",
     "FD24EB7C-0B0E-3438-A43B-133E93E94EFA",  // site 0x13780, cave 0xE78
     {0x48, 0x8b, 0x35, 0x41, 0x1e, 0x02, 0x00, 0x48, 0x8b, 0x45, 0xa8, 0x48,
      0x89, 0x44, 0x24, 0x28, 0x0f, 0x10, 0x45, 0x98, 0x0f, 0x11, 0x44, 0x24,
      0x18, 0x48, 0x8b, 0x45, 0x90, 0x48, 0x89, 0x44, 0x24, 0x10, 0x0f, 0x10,
      0x45, 0x80, 0x0f, 0x11, 0x04, 0x24, 0x49, 0x89, 0xdd, 0x48, 0x89, 0xdf}},
    {"14.8.9 (23J631)",
     "0FD1FA9F-5DF9-3E5F-A316-21AF738EBBAD",  // site 0x142CA, cave 0xEC8
     {0x48, 0x8b, 0x35, 0x77, 0x22, 0x02, 0x00, 0x48, 0x8b, 0x45, 0xa8, 0x48,
      0x89, 0x44, 0x24, 0x28, 0x0f, 0x10, 0x45, 0x98, 0x0f, 0x11, 0x44, 0x24,
      0x18, 0x48, 0x8b, 0x45, 0x90, 0x48, 0x89, 0x44, 0x24, 0x10, 0x0f, 0x10,
      0x45, 0x80, 0x0f, 0x11, 0x04, 0x24, 0x4d, 0x89, 0xe7,  // 42: mov r15, r12
                                                             // (kept)
      0x4c, 0x89, 0xe7}},  // 45: mov rdi, r12              (kept)
};
const WideBuild* wide_build(const char* uuid) {
  for (size_t i = 0; i < sizeof(kWideBuilds) / sizeof(kWideBuilds[0]); i++)
    if (!strcmp(kWideBuilds[i].uuid, uuid)) return &kWideBuilds[i];
  return NULL;
}
static void put32(uint8_t* p, int64_t v) {
  int32_t x = (int32_t)v;
  memcpy(p, &x, 4);
}

void build_wide(const WideBuild* b, uint8_t outCall[kWideCallLen],
                uint8_t outCave[kWideCaveLen], uint64_t callVm,
                uint64_t caveVm) {
  int32_t selDisp;
  memcpy(&selDisp, b->find + 3, 4);
  int64_t selVm = (int64_t)callVm + 7 + selDisp;

  // call site: the original argument copy (position independent), then jmp cave
  memcpy(outCall, b->find + 7, 35);
  outCall[35] = 0xe9;
  put32(outCall + 36, (int64_t)caveVm - (int64_t)(callVm + 40));
  outCall[40] = 0x90;
  outCall[41] = 0x90;

  static const uint8_t cave[44] = {
      0x8b, 0x44, 0x24,
      0x18,  //  0: mov eax, [rsp+18h]      t = threadsPerThreadgroup.x
      0x6a, 0x01, 0x59,  //  4: push 1; pop rcx         g = 1
      0x3d, 0x00, 0x01,
      0x00, 0x00,        //  7: L: cmp eax, 256
      0x76, 0x10,        // 12: jbe D (30)
      0xa8, 0x01,        // 14: test al, 1
      0x75, 0x06,        // 16: jnz F (24)
      0xd1, 0xe8,        // 18: shr eax, 1
      0x01, 0xc9,        // 20: add ecx, ecx
      0xeb, 0xef,        // 22: jmp L (7)
      0x0f, 0xaf, 0xc8,  // 24: F: imul ecx, eax
      0x6a, 0x01, 0x58,  // 27: push 1; pop rax         t = 1
      0x48, 0x89, 0x44,
      0x24, 0x18,  // 30: D: mov [rsp+18h], rax   threadsPerThreadgroup.x = t
      0x48, 0x0f, 0xaf,
      0x0c, 0x24,  // 35: imul rcx, [rsp]
      0x48, 0x89, 0x0c,
      0x24,  // 40: mov [rsp], rcx          numThreadgroups.x *= g
  };
  memcpy(outCave, cave, sizeof(cave));
  outCave[44] = 0x48;
  outCave[45] = 0x8b;
  outCave[46] = 0x35;  // 44: mov rsi, [rip+disp]  (the selector)
  put32(outCave + 47, selVm - (int64_t)(caveVm + 51));
  outCave[51] = 0xe9;  // 51: jmp back to the kept mov r13, rbx
  put32(outCave + 52,
        (int64_t)(callVm + kWideCallLen) - (int64_t)(caveVm + 56));
}

const char* const kCcImage =
    "/System/Library/PrivateFrameworks/VideoProcessing.framework/Versions/A/"
    "VideoProcessing";
const char* const kCcTargets[] = {"/usr/libexec/ContinuityCaptureAgent",
                                  "/usr/libexec/avconferenced", NULL};
// Per build, read in IDA (call targets resolved on 26.7.3 in a live process):
// K = VCPDec's decoder creation, from the load of
//     kVTVideoDecoderSpecification_Usage to the CFDictionaryAddValue call;
// A = the same function before VTDecompressionSessionCreateWithOptions, from
//     the codec load to the CFDictionaryContainsKey call of the removal;
// B = VCPDecompressionSessionSetProperty, from the FaceZoom CFStringCompare to
//     the codec-check jump, and B's target = Apple's DecoderUsage check in the
//     same function (load of the same key, CFStringCompare, jnz to the
//     forwarding path);
// E = the whole board-id check that VCPCompressionSessionCreate and
//     VCPCodecCopyProperties call for usage 42 (no symbol; its two board-id
//     CFStrings, BridgeEncode and the calls checked on 26.7.3 in a live
//     process, tests/cc_test.c).
const char kCcSiteName[kCcSites + 1] = "KABE";
static const CcBuild kCcBuilds[] = {
    {"26.7.2 (25G332), 26.7.3 (25G342)",
     "3EE0D5DE-F382-3E55-B793-03DCA33EB76E",
     {{40,                                         // K at 0x7FF912FB4500
       {0x48, 0x8b, 0x05, 0xe9, 0x1a, 0xe2, 0x2e,  // mov rax, Usage@GOT
        0x48, 0x8b, 0x00,                          // mov rax, [rax]
        0x48, 0x89, 0x85, 0x38, 0xff, 0xff, 0xff,  // mov [rbp-0C8h], rax
        0x48, 0x85, 0xdb,                          // test rbx, rbx
        0x74, 0x1a,                                // jz
        0x4c, 0x89, 0xff,                          // mov rdi, r15 (the spec)
        0x48, 0x8b, 0xb5, 0x38, 0xff, 0xff, 0xff,  // mov rsi, [rbp-0C8h]
        0x48, 0x89, 0xda,                          // mov rdx, rbx
        0xe8, 0xda, 0x96, 0x24, 0x00},             // call CFDictionaryAddValue
       0,
       0,
       0,
       0,
       {0}},
      {125,  // A at 0x7FF912FB5E79
       {
           0x48, 0x8b, 0x85, 0x78, 0xff, 0xff, 0xff,  // mov rax, [rbp-88h]
           0x8b, 0x40, 0x18,              // mov eax, [rax+18h] codec
           0x45, 0x31, 0xed,              // xor r13d, r13d
           0x3d, 0x30, 0x63, 0x76, 0x68,  // cmp eax, 68766330h
           0x7f, 0x1b,                    // jg
           0x3d, 0x67, 0x76, 0x74, 0x66, 0x7f, 0x2b, 0x3d, 0x68, 0x73, 0x69,
           0x64, 0x0f, 0x84, 0x81, 0x00, 0x00, 0x00, 0x3d, 0x31, 0x68, 0x76,
           0x64, 0x75, 0x37, 0xeb, 0x78, 0x3d, 0x30, 0x68, 0x64, 0x71, 0x7f,
           0x20, 0x3d, 0x31, 0x63, 0x76, 0x68, 0x74, 0x6a, 0x3d, 0x63, 0x76,
           0x68, 0x6f, 0x75, 0x20, 0xeb, 0x61, 0x3d, 0x68, 0x76, 0x74, 0x66,
           0x74, 0x5a, 0x3d, 0x70, 0x76, 0x74, 0x66, 0x75, 0x10, 0xeb, 0x51,
           0x3d, 0x31, 0x68, 0x64, 0x71, 0x74, 0x4a, 0x3d, 0x63, 0x76, 0x68,
           0x71, 0x74, 0x43,                          // the other HEVC codecs
           0xe8, 0x37, 0x76, 0x00, 0x00,              // call (board-id check)
           0x83, 0xf8, 0x01,                          // cmp eax, 1
           0x75, 0x36,                                // jnz (no removal)
           0x4c, 0x89, 0xff,                          // removal: mov rdi, r15
           0x48, 0x8b, 0xb5, 0x38, 0xff, 0xff, 0xff,  // mov rsi, [rbp-0C8h]
           0xe8, 0x18, 0x7d, 0x24, 0x00},  // call CFDictionaryContainsKey
       13,
       7,
       0x6e,
       0,
       {0}},
      {31,                                   // B at 0x7FF912FBD635
       {0xe8, 0x9a, 0x06, 0x24, 0x00,        // call CFStringCompare (FaceZoom)
        0x48, 0x85, 0xc0,                    // test rax, rax
        0x0f, 0x84, 0xad, 0x00, 0x00, 0x00,  // jz FaceZoom
        0x80, 0x7b, 0x60, 0x00,              // cmp byte [rbx+60h], 0
        0x0f, 0x84, 0xf4, 0x00, 0x00, 0x00,  // jz codec checks
        0x48, 0x8d, 0x35, 0x7c, 0xf8, 0xe1,
        0x2e},  // lea rsi, ... (forwarding path)
       14,
       10,
       0x24c,
       kCcTgtLen,                                  // target 0x7FF912FBD881
       {0x48, 0x8b, 0x05, 0x68, 0x87, 0xe1, 0x2e,  // mov rax, Usage@GOT
        0x48, 0x8b, 0x30,                          // mov rsi, [rax]
        0x45, 0x31, 0xff,                          // xor r15d, r15d
        0x4c, 0x89, 0xe7,                          // mov rdi, r12 (the key)
        0x31, 0xd2,                                // xor edx, edx
        0xe8, 0x3c, 0x04, 0x24, 0x00,              // call CFStringCompare
        0x48, 0x85, 0xc0,                          // test rax, rax
        0x0f, 0x85, 0xac, 0xfd, 0xff, 0xff}},      // jnz forwarding path
      {160,                                        // E at 0x7FF912FA024D
       {0x55,                                      // +0x00 push rbp
        0x48, 0x89, 0xe5,                          // +0x01 mov rbp, rsp
        0x53,                                      // +0x04 push rbx
        0x50,                                      // +0x05 push rax
        0xe8, 0x4c, 0xff, 0xff, 0xff,  // +0x06 call the board-id read
        0x48, 0x85, 0xc0,              // +0x0b test rax, rax
        0x74, 0x37,                    // +0x0e jz +0x47
        0x48, 0x89, 0xc3,              // +0x10 mov rbx, rax
        0x48, 0x8d, 0x35, 0x29, 0xc2, 0xe3,
        0x2e,                          // +0x13 lea rsi, Mac-7BA5B2D9E42DDD94
        0x48, 0x89, 0xc7,              // +0x1a mov rdi, rax
        0x31, 0xd2,                    // +0x1d xor edx, edx
        0xe8, 0x63, 0xda, 0x25, 0x00,  // +0x1f call CFStringCompare
        0x48, 0x85, 0xc0,              // +0x24 test rax, rax
        0x74, 0x4d,                    // +0x27 jz +0x76
        0x48, 0x8d, 0x35, 0x33, 0xc2, 0xe3,
        0x2e,                          // +0x29 lea rsi, Mac-27AD2F918AE68F61
        0x48, 0x89, 0xdf,              // +0x30 mov rdi, rbx
        0x31, 0xd2,                    // +0x33 xor edx, edx
        0xe8, 0x4d, 0xda, 0x25, 0x00,  // +0x35 call CFStringCompare
        0x48, 0x85, 0xc0,              // +0x3a test rax, rax
        0x74, 0x37,                    // +0x3d jz +0x76
        0x48, 0x89, 0xdf,              // +0x3f mov rdi, rbx
        0xe8, 0x10, 0xda, 0x25, 0x00,  // +0x42 call CFRelease
        0x48, 0x8d, 0x3d, 0x75, 0xcf, 0xe3,
        0x2e,  // +0x47 lea rdi, BridgeEncode
        0x48, 0x8d, 0x35, 0xee, 0xc0, 0xe3,
        0x2e,        // +0x4e lea rsi, com.apple.VideoProcessing
        0x31, 0xdb,  // +0x55 xor ebx, ebx
        0x31, 0xd2,  // +0x57 xor edx, edx
        0xe8, 0xe7, 0xd9, 0x25, 0x00,  // +0x59 call
                                       // CFPreferencesGetAppBooleanValue
        0x84, 0xc0,                    // +0x5e test al, al
        0x74, 0x1e,                    // +0x60 jz +0x80
        0xbf, 0x03, 0x00, 0x00, 0x00,  // +0x62 mov edi, 3
        0xe8, 0x27, 0xe3, 0x25, 0x00,  // +0x67 call
                                       // remote_device_copy_unique_of_type
        0x48, 0x85, 0xc0,              // +0x6c test rax, rax
        0x74, 0x18,                    // +0x6f jz +0x89
        0x48, 0x89, 0xc7,              // +0x71 mov rdi, rax
        0xeb, 0x03,                    // +0x74 jmp +0x79
        0x48, 0x89, 0xdf,              // +0x76 mov rdi, rbx
        0xe8, 0xd9, 0xd9, 0x25, 0x00,  // +0x79 call CFRelease
        0xb3, 0x01,                    // +0x7e mov bl, 1
        0x89, 0xd8,                    // +0x80 mov eax, ebx
        0x48, 0x83, 0xc4, 0x08,        // +0x82 add rsp, 8
        0x5b,                          // +0x86 pop rbx
        0x5d,                          // +0x87 pop rbp
        0xc3,                          // +0x88 retn
        0x48, 0x8d, 0x35, 0x53, 0xcf, 0xe3,
        0x2e,        // +0x89 lea rsi, Remote encode ... ignoring
        0x31, 0xdb,  // +0x90 xor ebx, ebx
        0xbf, 0x04, 0x00, 0x00, 0x00,  // +0x92 mov edi, 4
        0x31, 0xc0,                    // +0x97 xor eax, eax
        0xe8, 0x83, 0xd9, 0x25, 0x00,  // +0x99 call CFLog
        0xeb, 0xe0},                   // +0x9e jmp +0x80
       kCcEFirst,
       2,
       kCcERelease,
       0,
       {0}}}},
    {"15.8.2 (24H232)",
     "7B6360AC-5775-3F01-B253-5F199DD57F7C",
     {{44,  // K at 0x7FF90E44CA4B
       {0x48, 0x8b, 0x05, 0xf6, 0xe3,
        0x00, 0x33,        // mov rax, Usage@GOT
        0x48, 0x8b, 0x00,  // mov rax, [rax]
        0x48, 0x89, 0x85, 0x28, 0xff,
        0xff, 0xff,        // mov [rbp-0D8h], rax
        0x48, 0x85, 0xdb,  // test rbx, rbx
        0x74, 0x1e,        // jz
        0x48, 0x8b, 0xbd, 0x70, 0xff,
        0xff, 0xff,  // mov rdi, [rbp-90h] (the spec)
        0x48, 0x8b, 0xb5, 0x28, 0xff,
        0xff, 0xff,                     // mov rsi, [rbp-0D8h]
        0x48, 0x89, 0xda,               // mov rdx, rbx
        0xe8, 0x2f, 0x8b, 0x24, 0x00},  // call CFDictionaryAddValue
       0,
       0,
       0,
       0,
       {0}},
      {79,                                         // A at 0x7FF90E44DD24
       {0x48, 0x8b, 0x85, 0x78, 0xff, 0xff, 0xff,  // mov rax, [rbp-88h]
        0x8b, 0x40, 0x18,                          // mov eax, [rax+18h] codec
        0x45, 0x31, 0xed,                          // xor r13d, r13d
        0x3d, 0x67, 0x76, 0x74, 0x66,              // cmp eax, 66747667h
        0x7f, 0x10,                                // jg
        0x3d, 0x68, 0x73, 0x69, 0x64, 0x74, 0x66, 0x3d, 0x31, 0x68, 0x76, 0x64,
        0x74, 0x5f, 0xeb, 0x0e, 0x3d, 0x68, 0x76, 0x74, 0x66, 0x74, 0x56, 0x3d,
        0x31, 0x63, 0x76, 0x68, 0x74, 0x4f,        // the HEVC codecs
        0xe8, 0x27, 0x47, 0x00, 0x00,              // call (board-id check)
        0x83, 0xf8, 0x01,                          // cmp eax, 1
        0x75, 0x42,                                // jnz (no removal)
        0x48, 0x8b, 0xbd, 0x70, 0xff, 0xff, 0xff,  // removal: mov rdi,
                                                   // [rbp-90h]
        0x48, 0x8b, 0xb5, 0x28, 0xff, 0xff, 0xff,  // mov rsi, [rbp-0D8h]
        0xe8, 0x3f, 0x78, 0x24, 0x00},  // call CFDictionaryContainsKey
       13,
       7,
       0x3c,
       0,
       {0}},
      {24,                                   // B at 0x7FF90E45259A
       {0xe8, 0xd3, 0x30, 0x24, 0x00,        // call CFStringCompare (FaceZoom)
        0x48, 0x85, 0xc0,                    // test rax, rax
        0x74, 0x7f,                          // jz FaceZoom
        0x80, 0x7b, 0x50, 0x00,              // cmp byte [rbx+50h], 0
        0x0f, 0x84, 0xc6, 0x00, 0x00, 0x00,  // jz codec checks
        0x48, 0x8b, 0x7b, 0x10},             // mov rdi, [rbx+10h] (forwarding)
       10,
       10,
       0x120,
       kCcTgtLen,                                  // target 0x7FF90E4526BA
       {0x48, 0x8b, 0x05, 0x87, 0x87, 0x00, 0x33,  // mov rax, Usage@GOT
        0x48, 0x8b, 0x30,                          // mov rsi, [rax]
        0x45, 0x31, 0xe4,                          // xor r12d, r12d
        0x4c, 0x89, 0xff,                          // mov rdi, r15 (the key)
        0x31, 0xd2,                                // xor edx, edx
        0xe8, 0xa1, 0x2f, 0x24, 0x00,              // call CFStringCompare
        0x48, 0x85, 0xc0,                          // test rax, rax
        0x0f, 0x85, 0xd4, 0xfe, 0xff, 0xff}},      // jnz forwarding path
      {160,                                        // E at 0x7FF90E43CBED
       {0x55,                                      // +0x00 push rbp
        0x48, 0x89, 0xe5,                          // +0x01 mov rbp, rsp
        0x53,                                      // +0x04 push rbx
        0x50,                                      // +0x05 push rax
        0xe8, 0x4c, 0xff, 0xff, 0xff,  // +0x06 call the board-id read
        0x48, 0x85, 0xc0,              // +0x0b test rax, rax
        0x74, 0x37,                    // +0x0e jz +0x47
        0x48, 0x89, 0xc3,              // +0x10 mov rbx, rax
        0x48, 0x8d, 0x35, 0x99, 0x21, 0x02,
        0x33,                          // +0x13 lea rsi, Mac-7BA5B2D9E42DDD94
        0x48, 0x89, 0xc7,              // +0x1a mov rdi, rax
        0x31, 0xd2,                    // +0x1d xor edx, edx
        0xe8, 0x61, 0x8a, 0x25, 0x00,  // +0x1f call CFStringCompare
        0x48, 0x85, 0xc0,              // +0x24 test rax, rax
        0x74, 0x4d,                    // +0x27 jz +0x76
        0x48, 0x8d, 0x35, 0xa3, 0x21, 0x02,
        0x33,                          // +0x29 lea rsi, Mac-27AD2F918AE68F61
        0x48, 0x89, 0xdf,              // +0x30 mov rdi, rbx
        0x31, 0xd2,                    // +0x33 xor edx, edx
        0xe8, 0x4b, 0x8a, 0x25, 0x00,  // +0x35 call CFStringCompare
        0x48, 0x85, 0xc0,              // +0x3a test rax, rax
        0x74, 0x37,                    // +0x3d jz +0x76
        0x48, 0x89, 0xdf,              // +0x3f mov rdi, rbx
        0xe8, 0x0e, 0x8a, 0x25, 0x00,  // +0x42 call CFRelease
        0x48, 0x8d, 0x3d, 0x85, 0x29, 0x02,
        0x33,  // +0x47 lea rdi, BridgeEncode
        0x48, 0x8d, 0x35, 0x5e, 0x20, 0x02,
        0x33,        // +0x4e lea rsi, com.apple.VideoProcessing
        0x31, 0xdb,  // +0x55 xor ebx, ebx
        0x31, 0xd2,  // +0x57 xor edx, edx
        0xe8, 0xe5, 0x89, 0x25, 0x00,  // +0x59 call
                                       // CFPreferencesGetAppBooleanValue
        0x84, 0xc0,                    // +0x5e test al, al
        0x74, 0x1e,                    // +0x60 jz +0x80
        0xbf, 0x03, 0x00, 0x00, 0x00,  // +0x62 mov edi, 3
        0xe8, 0xed, 0x91, 0x25, 0x00,  // +0x67 call
                                       // remote_device_copy_unique_of_type
        0x48, 0x85, 0xc0,              // +0x6c test rax, rax
        0x74, 0x18,                    // +0x6f jz +0x89
        0x48, 0x89, 0xc7,              // +0x71 mov rdi, rax
        0xeb, 0x03,                    // +0x74 jmp +0x79
        0x48, 0x89, 0xdf,              // +0x76 mov rdi, rbx
        0xe8, 0xd7, 0x89, 0x25, 0x00,  // +0x79 call CFRelease
        0xb3, 0x01,                    // +0x7e mov bl, 1
        0x89, 0xd8,                    // +0x80 mov eax, ebx
        0x48, 0x83, 0xc4, 0x08,        // +0x82 add rsp, 8
        0x5b,                          // +0x86 pop rbx
        0x5d,                          // +0x87 pop rbp
        0xc3,                          // +0x88 retn
        0x48, 0x8d, 0x35, 0x63, 0x29, 0x02,
        0x33,        // +0x89 lea rsi, Remote encode ... ignoring
        0x31, 0xdb,  // +0x90 xor ebx, ebx
        0xbf, 0x04, 0x00, 0x00, 0x00,  // +0x92 mov edi, 4
        0x31, 0xc0,                    // +0x97 xor eax, eax
        0xe8, 0x81, 0x89, 0x25, 0x00,  // +0x99 call CFLog
        0xeb, 0xe0},                   // +0x9e jmp +0x80
       kCcEFirst,
       2,
       kCcERelease,
       0,
       {0}}}},
};
const CcBuild* cc_build(const char* uuid) {
  for (size_t i = 0; i < sizeof(kCcBuilds) / sizeof(kCcBuilds[0]); i++)
    if (!strcmp(kCcBuilds[i].uuid, uuid)) return &kCcBuilds[i];
  return NULL;
}
const CcBuild* cc_build_at(size_t i) {
  return i < sizeof(kCcBuilds) / sizeof(kCcBuilds[0]) ? &kCcBuilds[i] : NULL;
}

static int32_t get32(const uint8_t* p) {
  int32_t v;
  memcpy(&v, p, 4);
  return v;
}

void build_cc(const CcSite* s, uint8_t out[kCcMaxWrite]) {
  static const uint8_t nop5[5] = {0x0f, 0x1f, 0x44, 0x00, 0x00};
  if (s->n == 7) {  // A: jmp short to the removal, then a nop
    out[0] = 0xeb;
    out[1] = (uint8_t)(int8_t)((int)s->tgtDist - (s->off + 2));
    memcpy(out + 2, nop5, 5);
  } else if (s->n == 10) {  // B: jmp to the DecoderUsage check, then a nop
    out[0] = 0xe9;
    put32(out + 1, (int64_t)s->tgtDist - (s->off + 5));
    memcpy(out + 5, nop5, 5);
  } else if (s->n == 2) {  // E: jmp short past the board-id compares
    out[0] = 0xeb;
    out[1] = (uint8_t)(int8_t)((int)s->tgtDist - (s->off + 2));
  }
}

// Offset of `mov rsi, [rbp+disp32]` (48 8B B5) within the first 10 bytes
// after `at`, -1 if none: the key's stack slot read by the removal.
static int slot_load(const uint8_t* p, int len, int at) {
  for (int i = at; i < at + 10 && i + 7 <= len; i++)
    if (p[i] == 0x48 && p[i + 1] == 0x8b && p[i + 2] == 0xb5) return i;
  return -1;
}

// The structural checks each site must pass on top of its exact bytes.
static const char* cc_shape(int k, const CcSite* s) {
  if (s->len > kCcMaxFind || s->off + s->n > s->len) return "bad table entry";
  if (k == 0)
    return s->n == 0 && s->len >= 17 && s->find[0] == 0x48 &&
                   s->find[1] == 0x8b && s->find[2] == 0x05 &&
                   s->find[10] == 0x48 && s->find[11] == 0x89 &&
                   s->find[12] == 0x85
               ? NULL
               : "site K is not a key load and store";
  if (k == 3) {
    // push rbp; mov rbp, rsp; push rbx; push rax; call (the board-id read),
    // then twice "lea rsi, <board-id>; mov rdi, rax|rbx; xor edx, edx; call;
    // test rax, rax; jz <match>" with the same call and the same match, then
    // "mov rdi, rbx; call (CFRelease); lea rdi, <BridgeEncode>"
    static const uint8_t head[] = {0x55, 0x48, 0x89, 0xe5, 0x53, 0x50, 0xe8};
    const uint8_t* f = s->find;
    const int a = kCcEFirst, b = kCcESecond, r = kCcERelease;
    if (s->n != 2 || s->tgtLen || s->off != a || s->tgtDist != r ||
        s->len < r + 15 || memcmp(f, head, sizeof(head)) != 0 || f[a] != 0x48 ||
        f[a + 1] != 0x8d || f[a + 2] != 0x35 || f[a + 7] != 0x48 ||
        f[a + 8] != 0x89 || f[a + 9] != 0xc7 || f[a + 10] != 0x31 ||
        f[a + 12] != 0xe8 || f[a + 20] != 0x74 || f[b] != 0x48 ||
        f[b + 1] != 0x8d || f[b + 2] != 0x35 || f[b + 7] != 0x48 ||
        f[b + 8] != 0x89 || f[b + 9] != 0xdf || f[b + 10] != 0x31 ||
        f[b + 12] != 0xe8 || f[b + 20] != 0x74 || a + 22 != b || b + 22 != r ||
        f[r] != 0x48 || f[r + 1] != 0x89 || f[r + 2] != 0xdf ||
        f[r + 3] != 0xe8 || f[r + 8] != 0x48 || f[r + 9] != 0x8d ||
        f[r + 10] != 0x3d)
      return "site E is not the board-id check";
    // both compares call the same function and jump to the same match
    if (a + 17 + get32(f + a + 13) != b + 17 + get32(f + b + 13) ||
        a + 22 + (int8_t)f[a + 21] != b + 22 + (int8_t)f[b + 21])
      return "site E: the two board-id compares differ";
    return NULL;
  }
  if (k == 1) {
    int8_t rel = (int8_t)((int)s->tgtDist - (s->off + 2));
    if (s->n != 7 || s->tgtLen || s->find[s->off] != 0x3d ||
        s->find[s->off + 5] != 0x7f || s->tgtDist + 15 > s->len ||
        s->off + 2 + rel != s->tgtDist || s->find[s->len - 5] != 0xe8 ||
        slot_load(s->find, s->len, s->tgtDist) < 0)
      return "site A is not a codec check and the Usage removal";
    return NULL;
  }
  if (s->n != 10 || s->tgtLen != kCcTgtLen || s->find[s->off] != 0x80 ||
      s->find[s->off + 4] != 0x0f || s->find[s->off + 5] != 0x84 ||
      s->tgt[0] != 0x48 || s->tgt[1] != 0x8b || s->tgt[2] != 0x05 ||
      s->tgt[kCcTgtLen - 6] != 0x0f || s->tgt[kCcTgtLen - 5] != 0x85)
    return "site B is not a flag test and the Usage check";
  // the check's "not DecoderUsage" jump must land where the original went for
  // a session with the flag set (right after the replaced bytes)
  int64_t notUsage =
      (int64_t)s->tgtDist + kCcTgtLen + get32(s->tgt + kCcTgtLen - 4);
  if (notUsage != s->off + s->n)
    return "site B: the Usage check does not rejoin the original path";
  return NULL;
}

const CcBuild* cc_locate(const CcBuild* b, const uint8_t* text, size_t size,
                         uint64_t textVm, uint64_t sites[kCcSites], char* why,
                         size_t whyLen) {
  for (int k = 0; k < kCcSites; k++) {
    const CcSite* s = &b->site[k];
    const char* bad = cc_shape(k, s);
    if (bad) {
      snprintf(why, whyLen, "%s", bad);
      return NULL;
    }
    size_t at = 0, m = 0;
    for (size_t i = 0; i + s->len <= size; i++)
      if (text[i] == s->find[0] && !memcmp(text + i, s->find, s->len)) {
        m++;
        at = i;
      }
    if (m != 1) {
      snprintf(why, whyLen, "site %c found %zu times, expected once",
               kCcSiteName[k], m);
      return NULL;
    }
    if (s->tgtLen && (at + s->tgtDist + s->tgtLen > size ||
                      memcmp(text + at + s->tgtDist, s->tgt, s->tgtLen) != 0)) {
      snprintf(why, whyLen, "site B: the Usage check is not at its place");
      return NULL;
    }
    sites[k] = textVm + at;
  }
  // K and B load the same key; A's removal reads the slot K stores it in
  const CcSite *K = &b->site[0], *A = &b->site[1], *B = &b->site[2];
  uint64_t gotK = sites[0] + 7 + (int64_t)get32(K->find + 3);
  uint64_t gotB = sites[2] + B->tgtDist + 7 + (int64_t)get32(B->tgt + 3);
  if (gotK != gotB) {
    snprintf(why, whyLen, "sites K and B do not load the same key");
    return NULL;
  }
  if (get32(K->find + 13) !=
      get32(A->find + slot_load(A->find, A->len, A->tgtDist) + 3)) {
    snprintf(why, whyLen, "site A does not remove the key K stores");
    return NULL;
  }
  // E's board-id compares call the CFStringCompare that B's check calls
  const CcSite* E = &b->site[3];
  uint64_t cmpB = sites[2] + B->tgtDist + 23 + (int64_t)get32(B->tgt + 19);
  uint64_t cmpE =
      sites[3] + kCcEFirst + 17 + (int64_t)get32(E->find + kCcEFirst + 13);
  if (cmpB != cmpE) {
    snprintf(why, whyLen, "site E does not call B's CFStringCompare");
    return NULL;
  }
  return b;
}

int cc_site_state(const CcSite* s, const uint8_t* cur, const uint8_t* curTgt) {
  if (s->tgtLen && memcmp(curTgt, s->tgt, s->tgtLen) != 0) return -1;
  if (memcmp(cur, s->find, s->off) != 0 ||
      memcmp(cur + s->off + s->n, s->find + s->off + s->n,
             s->len - s->off - s->n) != 0)
    return -1;
  if (!memcmp(cur + s->off, s->find + s->off, s->n)) return 0;
  uint8_t w[kCcMaxWrite];
  build_cc(s, w);
  return memcmp(cur + s->off, w, s->n) ? -1 : 1;
}

// Validated builds of AMDRadeonVADriver2 for the 10-bit HEVC VCN 3 fixes.
static const Hevc10Build kHevc10Builds[] = {
    {"26.7.4 (25G422)",
     "F7D8F584-9EC1-39DB-857C-769697294957",
     // 26.7.4: same driver code as 26.7.3 (all 2760 functions identical; only a
     // build path in __cstring differs)
     // Site A: Vcn3Encoder::setInputAndOutputFormatParams +0x2a (96 bytes)
     {0x74, 0x29, 0x3d, 0x72, 0x30, 0x31, 0x6c, 0x74, 0x11, 0x3d, 0x62, 0x67,
      0x72, 0x61, 0x75, 0x23, 0xc5, 0xfb, 0x10, 0x05, 0x4e, 0x92, 0x04, 0x00,
      0xeb, 0x08, 0xc5, 0xfb, 0x10, 0x05, 0x34, 0x92, 0x04, 0x00, 0xb0, 0x01,
      0xb9, 0x01, 0x00, 0x00, 0x00, 0xeb, 0x0c, 0xc5, 0xfa, 0x10, 0x05, 0xcb,
      0x98, 0x03, 0x00, 0x31, 0xc9, 0x31, 0xc0, 0x89, 0x4d, 0xc4, 0x89, 0x4d,
      0xcc, 0xc5, 0xf8, 0x13, 0x45, 0xd4, 0x80, 0xbb, 0x2c, 0x05, 0x00, 0x00,
      0x01, 0x75, 0x0a, 0x0f, 0xb6, 0x8b, 0x2c, 0x04, 0x00, 0x00, 0x89, 0x4d,
      0xec, 0x84, 0xc0, 0x74, 0x07, 0xc7, 0x45, 0xe8, 0x01, 0x00, 0x00, 0x00},
     {0x74, 0x35, 0x3d, 0x72, 0x30, 0x31, 0x6c, 0x74, 0x11, 0x3d, 0x62, 0x67,
      0x72, 0x61, 0x75, 0x27, 0xc5, 0xfb, 0x10, 0x05, 0x4e, 0x92, 0x04, 0x00,
      0xeb, 0x08, 0xc5, 0xfb, 0x10, 0x05, 0x34, 0x92, 0x04, 0x00, 0xb8, 0x01,
      0x00, 0x00, 0x00, 0x89, 0x45, 0xc4, 0x89, 0x45, 0xcc, 0x89, 0x45, 0xe8,
      0xc5, 0xf8, 0x13, 0x45, 0xd4, 0xeb, 0x02, 0x31, 0xc0, 0x80, 0xbb, 0x2c,
      0x05, 0x00, 0x00, 0x01, 0x75, 0x14, 0x0f, 0xb6, 0x8b, 0x2c, 0x04, 0x00,
      0x00, 0x89, 0x4d, 0xec, 0x84, 0xc0, 0x75, 0x06, 0x89, 0x4d, 0xd4, 0x89,
      0x4d, 0xd8, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90},
     // Site B: AVDVcn3HevcEncDataProcessor::setupDeblocking +0x83 (find 52,
     // write 45)
     {0x48, 0x8b, 0x49, 0x28, 0x48, 0x89, 0x4d, 0xd0, 0x49, 0x8b, 0x4e,
      0x20, 0x48, 0x8b, 0x91, 0x50, 0x03, 0x00, 0x00, 0x31, 0xc9, 0x80,
      0xba, 0x9d, 0x02, 0x00, 0x00, 0x00, 0x75, 0x0c, 0x31, 0xc9, 0x80,
      0xba, 0x9e, 0x02, 0x00, 0x00, 0x00, 0x0f, 0x94, 0xc1, 0x89, 0x4d,
      0xd8, 0x80, 0x3d, 0xfa, 0x94, 0xe5, 0x32, 0x01},
     {0x49, 0x8b, 0x97, 0x50, 0x03, 0x00, 0x00, 0xc5, 0xfa, 0x7e, 0x41, 0x28,
      0xc5, 0xfa, 0x7e, 0x8a, 0x84, 0x07, 0x00, 0x00, 0xc5, 0xf9, 0xfe, 0xc1,
      0xc5, 0xf9, 0xd6, 0x45, 0xd0, 0x31, 0xc9, 0x66, 0x83, 0xba, 0x9d, 0x02,
      0x00, 0x00, 0x00, 0x0f, 0x94, 0xc1, 0x89, 0x4d, 0xd8}},
    {"26.7.3 (25G342)",
     "1181E2CA-31B3-3DF0-90E2-3AE70552D753",
     // Site A: Vcn3Encoder::setInputAndOutputFormatParams +0x2a (96 bytes)
     {0x74, 0x29, 0x3d, 0x72, 0x30, 0x31, 0x6c, 0x74, 0x11, 0x3d, 0x62, 0x67,
      0x72, 0x61, 0x75, 0x23, 0xc5, 0xfb, 0x10, 0x05, 0x4e, 0x92, 0x04, 0x00,
      0xeb, 0x08, 0xc5, 0xfb, 0x10, 0x05, 0x34, 0x92, 0x04, 0x00, 0xb0, 0x01,
      0xb9, 0x01, 0x00, 0x00, 0x00, 0xeb, 0x0c, 0xc5, 0xfa, 0x10, 0x05, 0xcb,
      0x98, 0x03, 0x00, 0x31, 0xc9, 0x31, 0xc0, 0x89, 0x4d, 0xc4, 0x89, 0x4d,
      0xcc, 0xc5, 0xf8, 0x13, 0x45, 0xd4, 0x80, 0xbb, 0x2c, 0x05, 0x00, 0x00,
      0x01, 0x75, 0x0a, 0x0f, 0xb6, 0x8b, 0x2c, 0x04, 0x00, 0x00, 0x89, 0x4d,
      0xec, 0x84, 0xc0, 0x74, 0x07, 0xc7, 0x45, 0xe8, 0x01, 0x00, 0x00, 0x00},
     {0x74, 0x35, 0x3d, 0x72, 0x30, 0x31, 0x6c, 0x74, 0x11, 0x3d, 0x62, 0x67,
      0x72, 0x61, 0x75, 0x27, 0xc5, 0xfb, 0x10, 0x05, 0x4e, 0x92, 0x04, 0x00,
      0xeb, 0x08, 0xc5, 0xfb, 0x10, 0x05, 0x34, 0x92, 0x04, 0x00, 0xb8, 0x01,
      0x00, 0x00, 0x00, 0x89, 0x45, 0xc4, 0x89, 0x45, 0xcc, 0x89, 0x45, 0xe8,
      0xc5, 0xf8, 0x13, 0x45, 0xd4, 0xeb, 0x02, 0x31, 0xc0, 0x80, 0xbb, 0x2c,
      0x05, 0x00, 0x00, 0x01, 0x75, 0x14, 0x0f, 0xb6, 0x8b, 0x2c, 0x04, 0x00,
      0x00, 0x89, 0x4d, 0xec, 0x84, 0xc0, 0x75, 0x06, 0x89, 0x4d, 0xd4, 0x89,
      0x4d, 0xd8, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90},
     // Site B: AVDVcn3HevcEncDataProcessor::setupDeblocking +0x83 (find 52,
     // write 45)
     {0x48, 0x8b, 0x49, 0x28, 0x48, 0x89, 0x4d, 0xd0, 0x49, 0x8b, 0x4e,
      0x20, 0x48, 0x8b, 0x91, 0x50, 0x03, 0x00, 0x00, 0x31, 0xc9, 0x80,
      0xba, 0x9d, 0x02, 0x00, 0x00, 0x00, 0x75, 0x0c, 0x31, 0xc9, 0x80,
      0xba, 0x9e, 0x02, 0x00, 0x00, 0x00, 0x0f, 0x94, 0xc1, 0x89, 0x4d,
      0xd8, 0x80, 0x3d, 0xfa, 0x94, 0xe5, 0x32, 0x01},
     {0x49, 0x8b, 0x97, 0x50, 0x03, 0x00, 0x00, 0xc5, 0xfa, 0x7e, 0x41, 0x28,
      0xc5, 0xfa, 0x7e, 0x8a, 0x84, 0x07, 0x00, 0x00, 0xc5, 0xf9, 0xfe, 0xc1,
      0xc5, 0xf9, 0xd6, 0x45, 0xd0, 0x31, 0xc9, 0x66, 0x83, 0xba, 0x9d, 0x02,
      0x00, 0x00, 0x00, 0x0f, 0x94, 0xc1, 0x89, 0x4d, 0xd8}},
};
const Hevc10Build* hevc10_build(const char* uuid) {
  for (size_t i = 0; i < sizeof(kHevc10Builds) / sizeof(kHevc10Builds[0]); i++)
    if (!strcmp(kHevc10Builds[i].uuid, uuid)) return &kHevc10Builds[i];
  return NULL;
}
