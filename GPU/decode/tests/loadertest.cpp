// loadertest - tests the decisions of VCNVTLoader
// (decode/loader/allow_logic.hpp) in a normal program. It does not load a kext
// or touch the system.
//
//   loadertest            the built-in cases
//   loadertest <file>     also: the file must hold "<hex of a function's first
//                         bytes> <failure|cdhash>" lines, written by
//                         tools/driver/amficheck.py from a real kernel
//                         collection; each must be accepted
//
// Exit status 0 = every check passed.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "allow_logic.hpp"

static int failed = 0;
#define CHECK(cond, name)        \
  do {                           \
    if (cond) {                  \
      printf("ok   %s\n", name); \
    } else {                     \
      printf("FAIL %s\n", name); \
      failed++;                  \
    }                            \
  } while (0)

static size_t unhex(const char* s, uint8_t* out, size_t cap) {
  size_t n = 0;
  while (s[0] && s[1] && n < cap) {
    unsigned v;
    if (sscanf(s, "%2x", &v) != 1) break;
    out[n++] = (uint8_t)v;
    s += 2;
  }
  return n;
}

int main(int argc, char** argv) {
  using namespace vcnvt;

  // The hash list.
  static const uint8_t list[2][kCdhashLen] = {
      {0xd7, 0xf8, 0x96, 0xa0, 0xc6, 0x8f, 0x2a, 0xea, 0x7d, 0xb8,
       0xc5, 0xcf, 0xd7, 0x61, 0xca, 0xc0, 0x07, 0xd5, 0x61, 0x45},
      {0xba, 0xc5, 0x65, 0xf1, 0xb2, 0xb2, 0x88, 0x11, 0x1d, 0x5c,
       0xd9, 0x9c, 0x90, 0x7d, 0x45, 0x9b, 0x8d, 0xde, 0xd0, 0x15},
  };
  uint8_t h[kCdhashLen];
  memcpy(h, list[0], sizeof(h));
  CHECK(cdhashAllowed(h, list, 2), "first listed hash is allowed");
  memcpy(h, list[1], sizeof(h));
  CHECK(cdhashAllowed(h, list, 2), "second listed hash is allowed");
  CHECK(!cdhashAllowed(h, list, 1), "a hash past the count is refused");
  CHECK(!cdhashAllowed(h, list, 0), "an empty list allows nothing");
  bool oneByte = true;
  for (size_t i = 0; i < kCdhashLen; i++) {
    memcpy(h, list[0], sizeof(h));
    h[i] ^= 0x01;
    if (cdhashAllowed(h, list, 2)) oneByte = false;
  }
  CHECK(oneByte, "a hash differing in any one byte is refused");
  memset(h, 0, sizeof(h));
  CHECK(!cdhashAllowed(h, list, 2), "the all-zero hash is refused");
  CHECK(!cdhashAllowed(nullptr, list, 2), "a missing hash is refused");
  CHECK(!cdhashAllowed(h, nullptr, 2), "a missing list allows nothing");

  // The entry of _library_validation_failure, as in the AMFI of 14.8.9, 15.8.2,
  // 26.7.2 and 26.7.3.
  static const uint8_t real[] = {
      0x55, 0x48, 0x89, 0xe5, 0x41, 0x57, 0x41, 0x56, 0x41, 0x55, 0x41, 0x54,
      0x53, 0x48, 0x81, 0xec, 0x88, 0x00, 0x00, 0x00, 0x4c, 0x89, 0x4d, 0x88};
  CHECK(entryIsPlainPrologue(real, sizeof(real)), "the real entry is accepted");
  CHECK(!entryIsPlainPrologue(real, 13), "a truncated entry is refused");
  CHECK(!entryIsPlainPrologue(nullptr, 32), "a missing entry is refused");
  {
    // sub rsp, imm8 instead of imm32, after enough pushes.
    static const uint8_t e[] = {0x55, 0x48, 0x89, 0xe5, 0x41, 0x57, 0x41,
                                0x56, 0x41, 0x55, 0x41, 0x54, 0x53, 0x48,
                                0x83, 0xec, 0x28, 0x90, 0x90, 0x90};
    CHECK(entryIsPlainPrologue(e, sizeof(e)), "a short frame is accepted");
  }
  {
    // A previous route: jmp [rip+0] and an address.
    static const uint8_t e[] = {0xff, 0x25, 0x00, 0x00, 0x00, 0x00, 0x10, 0x20,
                                0x30, 0x40, 0x80, 0xff, 0xff, 0xff, 0x90, 0x90};
    CHECK(!entryIsPlainPrologue(e, sizeof(e)),
          "an already routed entry is refused");
  }
  {
    // A short jump at the entry.
    static const uint8_t e[] = {0xe9, 0x10, 0x00, 0x00, 0x00, 0x41, 0x57, 0x41,
                                0x56, 0x41, 0x55, 0x41, 0x54, 0x53, 0x90, 0x90};
    CHECK(!entryIsPlainPrologue(e, sizeof(e)),
          "a jump at the entry is refused");
  }
  {
    // Stack protector load (rip relative) inside the copied part.
    static const uint8_t e[] = {0x55, 0x48, 0x89, 0xe5, 0x41, 0x57, 0x48,
                                0x8b, 0x05, 0x11, 0x22, 0x33, 0x00, 0x48,
                                0x89, 0x45, 0xf8, 0x90, 0x90, 0x90};
    CHECK(!entryIsPlainPrologue(e, sizeof(e)),
          "a rip-relative load in the copied part is refused");
  }
  {
    // A conditional branch inside the copied part.
    static const uint8_t e[] = {0x55, 0x48, 0x89, 0xe5, 0x48, 0x85, 0xff, 0x0f,
                                0x84, 0x10, 0x00, 0x00, 0x00, 0x41, 0x57, 0x90};
    CHECK(!entryIsPlainPrologue(e, sizeof(e)),
          "a branch in the copied part is refused");
  }
  {
    // Pushes only, no frame: not the function we know.
    static const uint8_t e[] = {0x41, 0x57, 0x41, 0x56, 0x41, 0x55, 0x41, 0x54,
                                0x53, 0x50, 0x51, 0x52, 0x56, 0x57, 0x90, 0x90};
    CHECK(!entryIsPlainPrologue(e, sizeof(e)),
          "an entry with no frame is refused");
  }
  {
    uint8_t zero[32] = {0};
    CHECK(!entryIsPlainPrologue(zero, sizeof(zero)), "zero bytes are refused");
  }

  // AbstractCSBlobAccessor::cdHash.
  static const uint8_t acc[] = {0x55, 0x48, 0x89, 0xe5, 0x48, 0x8b, 0x07,
                                0xff, 0x50, 0x30, 0x48, 0x85, 0xc0, 0x74,
                                0x09, 0x48, 0x89, 0xc7, 0x5d, 0xe9};
  CHECK(isCdHashAccessor(acc, sizeof(acc)), "the real accessor is accepted");
  CHECK(!isCdHashAccessor(acc, 12), "a truncated accessor is refused");
  {
    uint8_t other[sizeof(acc)];
    memcpy(other, acc, sizeof(acc));
    other[9] = 0x38;  // another vtable slot
    CHECK(!isCdHashAccessor(other, sizeof(other)),
          "an accessor of another slot is refused");
  }
  CHECK(!isCdHashAccessor(real, sizeof(real)), "another function is refused");
  // An entry that some kext already routed.
  {
    static const uint8_t lng[] = {0xff, 0x25, 0x00, 0x00,
                                  0x00, 0x00, 0x10, 0x20};
    static const uint8_t shrt[] = {0xe9, 0x10, 0x00, 0x00, 0x00, 0x41, 0x57};
    CHECK(entryIsRouted(lng, sizeof(lng)), "a long jump at the entry is seen");
    CHECK(entryIsRouted(shrt, sizeof(shrt)),
          "a short jump at the entry is seen");
    CHECK(!entryIsRouted(real, sizeof(real)), "the real entry is not a jump");
    CHECK(!entryIsRouted(lng, 1), "one byte is not enough to say");
    CHECK(!entryIsRouted(nullptr, 8), "a missing entry is not a jump");
  }

  // Entries read from real kernel collections.
  if (argc > 1) {
    FILE* f = fopen(argv[1], "r");
    if (!f) {
      printf("FAIL cannot open %s\n", argv[1]);
      return 1;
    }
    char line[512], hex[256], kind[32], label[128], extra[8];
    int n = 0;
    while (fgets(line, sizeof(line), f)) {
      if (line[0] == '\n' || line[0] == 0) continue;
      // Exactly three words per line; anything else is a damaged file.
      if (sscanf(line, "%255s %31s %127s %7s", hex, kind, label, extra) != 3) {
        printf("FAIL %s: line %d is not '<hex> <kind> <label>'\n", argv[1],
               n + 1);
        failed++;
        break;
      }
      uint8_t code[64];
      size_t len = unhex(hex, code, sizeof(code));
      bool ok = !strcmp(kind, "failure")  ? entryIsPlainPrologue(code, len)
                : !strcmp(kind, "cdhash") ? isCdHashAccessor(code, len)
                                          : false;
      printf("%s %s entry of %s\n", ok ? "ok  " : "FAIL", kind, label);
      if (!ok) failed++;
      n++;
    }
    fclose(f);
    if (n == 0) {
      printf("FAIL %s holds no entry\n", argv[1]);
      failed++;
    }
  }

  if (failed) {
    printf("%d checks failed\n", failed);
    return 1;
  }
  printf("all checks passed\n");
  return 0;
}
