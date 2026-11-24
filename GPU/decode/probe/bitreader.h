// Bit reader for the probe's parsers: MSB first, as every codec here reads
// header bits. It never reads past the buffer; a read that would sets err and
// returns zeros, and the callers treat err as "header too short".
#pragma once
#include <stddef.h>
#include <stdint.h>

typedef struct {
  const uint8_t* p;
  size_t size;  // bytes
  size_t bit;   // next bit, from the start of p
  int err;      // set by a read past the end
} BitReader;

static inline void br_init(BitReader* b, const uint8_t* p, size_t size) {
  b->p = p;
  b->size = size;
  b->bit = 0;
  b->err = 0;
}

// The next n bits, n <= 32.
static inline uint32_t br_get(BitReader* b, unsigned n) {
  uint32_t v = 0;
  for (unsigned i = 0; i < n; i++) {
    size_t byte = b->bit >> 3;
    if (byte >= b->size) {
      b->err = 1;
      return v;
    }
    v = (v << 1) | ((b->p[byte] >> (7 - (b->bit & 7))) & 1);
    b->bit++;
  }
  return v;
}

static inline void br_skip(BitReader* b, size_t n) {
  for (size_t i = 0; i < n; i++) (void)br_get(b, 1);
}

// An unsigned Exp-Golomb code (MPEG-4 uses it for VOP time bases).
static inline uint32_t br_ue(BitReader* b) {
  unsigned zeros = 0;
  while (!b->err && zeros < 32 && br_get(b, 1) == 0) zeros++;
  if (b->err || zeros >= 32) return 0;
  return (uint32_t)((1ull << zeros) - 1 + br_get(b, zeros));
}

static inline size_t br_bytes_used(const BitReader* b) {
  return (b->bit + 7) >> 3;
}
