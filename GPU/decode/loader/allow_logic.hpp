//
//  allow_logic.hpp - the decisions of VCNVTLoader, with no kernel dependency,
//  so decode/tests/loadertest.cpp can run them in a normal program.
//
#ifndef VCNVT_ALLOW_LOGIC_HPP
#define VCNVT_ALLOW_LOGIC_HPP

#include <stddef.h>
#include <stdint.h>

namespace vcnvt {

// AMFI identifies code by the first 20 bytes of its code directory hash, which
// is the value `codesign -dvvv` prints as CDHash.
constexpr size_t kCdhashLen = 20;

// Lilu's long jump is 14 bytes. It copies whole instructions until it has at
// least that many, and does not relocate them.
constexpr size_t kRouteBytes = 14;

// True when `hash` (kCdhashLen bytes) is one of the `count` entries of `list`.
inline bool cdhashAllowed(const uint8_t* hash,
                          const uint8_t (*list)[kCdhashLen], size_t count) {
  if (hash == nullptr || list == nullptr) return false;
  for (size_t i = 0; i < count; i++) {
    uint8_t diff = 0;
    for (size_t b = 0; b < kCdhashLen; b++) diff |= hash[b] ^ list[i][b];
    if (diff == 0) return true;
  }
  return false;
}

// True when the code at `code` starts with a plain function prologue: only
// push of a register, mov rbp,rsp and sub rsp,imm, for at least kRouteBytes
// bytes. None of those depends on where it runs, so the copy Lilu makes of
// them still works. Anything else (a branch, a load relative to rip, a
// previous route's jump) is refused and the function is left alone.
inline bool entryIsPlainPrologue(const uint8_t* code, size_t avail) {
  if (code == nullptr) return false;
  size_t at = 0;
  bool frame = false;
  while (at < kRouteBytes) {
    size_t left = avail > at ? avail - at : 0;
    const uint8_t* p = code + at;
    if (left >= 1 && p[0] >= 0x50 && p[0] <= 0x57) {
      at += 1;  // push rax..rdi
    } else if (left >= 2 && p[0] == 0x41 && p[1] >= 0x50 && p[1] <= 0x57) {
      at += 2;  // push r8..r15
    } else if (left >= 3 && p[0] == 0x48 && p[1] == 0x89 && p[2] == 0xe5) {
      frame = true;
      at += 3;  // mov rbp, rsp
    } else if (left >= 7 && p[0] == 0x48 && p[1] == 0x81 && p[2] == 0xec) {
      at += 7;  // sub rsp, imm32
    } else if (left >= 4 && p[0] == 0x48 && p[1] == 0x83 && p[2] == 0xec) {
      at += 4;  // sub rsp, imm8
    } else {
      return false;
    }
  }
  return frame && code[0] == 0x55;  // starts with push rbp, and sets a frame
}

// True when `code` starts with a jump: the entry of a function that a kext has
// already routed (Lilu writes jmp rel32 or jmp [rip+0]), or that was never a
// normal function entry.
inline bool entryIsRouted(const uint8_t* code, size_t avail) {
  if (code == nullptr || avail < 2) return false;
  return code[0] == 0xe9 || (code[0] == 0xff && code[1] == 0x25);
}

// How many bytes isCdHashAccessor compares.
constexpr size_t kAccessorBytes = 13;

// True when `code` is AbstractCSBlobAccessor::cdHash as read in the AMFI of
// macOS 14.8.9, 15.8.2, 26.7.2 and 26.7.3: push rbp; mov rbp,rsp;
// mov rax,[rdi]; call [rax+0x30]; test rax,rax. The kext only calls this
// function, it does not change it.
inline bool isCdHashAccessor(const uint8_t* code, size_t avail) {
  static const uint8_t want[] = {0x55, 0x48, 0x89, 0xe5, 0x48, 0x8b, 0x07,
                                 0xff, 0x50, 0x30, 0x48, 0x85, 0xc0};
  static_assert(sizeof(want) == kAccessorBytes, "kAccessorBytes");
  if (code == nullptr || avail < sizeof(want)) return false;
  for (size_t i = 0; i < sizeof(want); i++)
    if (code[i] != want[i]) return false;
  return true;
}

}  // namespace vcnvt

#endif  // VCNVT_ALLOW_LOGIC_HPP
