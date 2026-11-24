// Bit reader for the header parsers of the MPEG-2, VC-1 and MPEG-4 decoders:
// most significant bit first. It never reads past the buffer; a read that
// would sets err and returns zeros, and the callers treat err as "header too
// short".
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
      return 0;
    }
    v = (v << 1) | ((b->p[byte] >> (7 - (b->bit & 7))) & 1);
    b->bit++;
  }
  return v;
}

static inline void br_skip(BitReader* b, size_t n) {
  if (n > b->size * 8 - b->bit) {
    b->err = 1;
    b->bit = b->size * 8;
    return;
  }
  b->bit += n;
}

// The offset of the next 00 00 01 at or after `from`, or `size` when there is
// none. The code byte is d[offset + 3] when offset + 3 < size.
static inline size_t next_start_code(const uint8_t* d, size_t size,
                                     size_t from) {
  for (size_t i = from; i + 3 < size; i++)
    if (d[i] == 0 && d[i + 1] == 0 && d[i + 2] == 1) return i;
  return size;
}
