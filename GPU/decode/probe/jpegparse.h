// Baseline JPEG (SOF0 only): dimensions, components and chroma sampling, and
// the whole file as the access unit. Progressive, lossless and 12-bit are
// refused.
#pragma once
#include <stddef.h>
#include <stdint.h>

#include "probe.h"

typedef struct {
  ProbeAu au;
  uint8_t components;        // 3
  uint8_t sampling;          // 1 = 4:2:0, 2 = 4:2:2, 3 = 4:4:4
  uint8_t precision;         // 8
  uint16_t restartInterval;  // 0 when none (see DRI; 16 bits per T.81)
} JpegPicture;

// 0 on success, -1 with err set.
int jpeg_parse(const uint8_t* data, size_t size, JpegPicture* out, char* err,
               size_t errLen);
