// patches.c - the two user-space patches applied by vcnencodefix inside
// VTEncoderXPCService.
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
#include "patches.h"

#include <string.h>

const char* const kPresetImage =
    "/System/Library/Extensions/AMDRadeonVADriver2.bundle/Contents/MacOS/"
    "AMDRadeonVADriver2";
// The site's bytes per build (the jz distance differs on Sonoma). Same code in
// every build: VAUveEncoder::EncodePicture reads the preset from +0xA0 and,
// when it is not 0, stores it in the frame parameters (+0x30) and sets the flag
// that appends the preset packet (compared in Hex-Rays against 26.7.3).
static const PresetBuild kPresetBuilds[] = {
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
