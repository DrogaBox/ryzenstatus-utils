// jpegprep: turns one JPEG picture (a 'jpeg' or 'dmb1' sample) into the exact
// shape the VCN JPEG block is given on Linux by Mesa (vlVaGetJpegSliceHeader,
// src/gallium/frontends/va/picture_mjpeg.c): SOI, one DQT segment, one DHT
// segment (DC tables, then AC tables), DRI if there is a restart interval,
// SOF0, SOS, the scan, EOI. APPn and COM segments are dropped; a picture
// without Huffman tables (Motion JPEG) gets the standard ones of Annex K.
//
// What the block is given here is what the kext checks again before it takes
// the JPEG (VCNJpegProbe jc::parseStream): baseline, 8 bits, three components,
// one scan with all three, sampled as Mesa's radeon_dec_jpeg_check_format
// takes them on this block: 0x221111 (4:2:0, written as NV12) or 0x211111,
// 0x221212, 0x222121 (4:2:2, written as YUYV). Anything else is
// JPEG_UNSUPPORTED: progressive, 4:4:4, 4:4:0, grey.
//
// Pure code: no system call, no allocation but the output buffer.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum {
  JPEG_OK = 0,
  JPEG_BAD = 1,          // not a JPEG, or one that breaks the standard
  JPEG_UNSUPPORTED = 2,  // a valid JPEG the block is not given (see above)
  JPEG_NO_MEMORY = 3,
};

typedef struct {
  uint32_t width, height;
  uint16_t restart;     // restart interval, 0 = none
  bool stdTables;       // the Huffman tables of Annex K were added
  bool yuyv;            // 4:2:2: the block writes YUYV (else NV12)
} JpegInfo;

// The output is at most the input plus kJpegPrepExtra bytes.
enum { kJpegPrepExtra = 1024 };

// Fills out (malloc'ed, free it) and *info. On failure *out is NULL and why
// holds a short reason.
int jpeg_prepare(const uint8_t* in, size_t n, uint8_t** out, size_t* outLen,
                 JpegInfo* info, char* why, size_t whyLen);
