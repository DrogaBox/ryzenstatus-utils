// vcnjpeg: one JPEG picture at a time on the JPEG block of the AMD VCN, through
// the apps build of the VCNJpegProbe kext. The kext owns the block, its queue
// and its buffers; a process reaches it through the accelerator's video context
// (selector 258, see jpeg_app.h), the connection any process that decodes
// video may open. Without that kext there is no decoder: vcnjpeg_create fails.
//
// The interface is the one of vcnvp9.h, so that the VideoToolbox side
// (JPEGVCNDecoder.c) and its tests (tests/plugintest.c) are the same code.
#pragma once
#include <CoreVideo/CoreVideo.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "jpeg_app_client.h"

typedef struct VcnJpeg VcnJpeg;
typedef void (*VcnJpegOutputFn)(void* ctx, CVPixelBufferRef pb, const void* unused,
                                uint32_t width, uint32_t height, int64_t tag);

// The plug-in sets this; nothing is sent to the kernel before it is set.
extern int vcnjpeg_gpu_armed;

// The transport to the kext: the real one by default, a stand-in in the tests.
extern ja_transport vcnjpeg_transport;
extern void* (*vcnjpeg_transport_open)(void);
extern void (*vcnjpeg_transport_close)(void* ctx);

// NV12 full range (a JPEG's samples are 0..255), IOSurface backed.
CFDictionaryRef vcnjpeg_copy_pixel_buffer_attributes(uint32_t w, uint32_t h, bool tenBit);

VcnJpeg* vcnjpeg_create(uint32_t maxWidth, uint32_t maxHeight, char* err, size_t errLen);
void vcnjpeg_destroy(VcnJpeg* d);
// Decodes one picture and calls fn with it.
int vcnjpeg_decode(VcnJpeg* d, const uint8_t* sample, size_t size, int64_t tag,
                   VcnJpegOutputFn fn, void* ctx);
const char* vcnjpeg_last_error(VcnJpeg* d);
enum {
  VCNJPEG_FAIL_STREAM = 0,     // the picture cannot be decoded as it is (or not by the block)
  VCNJPEG_FAIL_DEVICE = 1,     // the kext is gone, refused, timed out, or stays busy
  VCNJPEG_FAIL_MEMORY = 2,
  VCNJPEG_FAIL_REFERENCE = 3,  // never: a JPEG needs no other picture
};
int vcnjpeg_failure(VcnJpeg* d);
// A JPEG has no hidden pictures: always NULL.
CVPixelBufferRef vcnjpeg_hidden_picture(VcnJpeg* d);
// Pictures the block decoded but the kext reported as wrong: none can be told apart yet, always 0.
unsigned vcnjpeg_firmware_errors(VcnJpeg* d);
