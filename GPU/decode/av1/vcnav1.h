// Hardware AV1 decoder for AMD VCN on macOS, driven through Apple's
// AMDRadeonVADriver2.
#pragma once
#include <CoreVideo/CoreVideo.h>
#include <stdbool.h>
#include <stdint.h>

#include "av1parse.h"
#include "vcncolor.h"

typedef struct VcnAV1 VcnAV1;

// Called for every frame that must be displayed (in display order, as the
// bitstream dictates). The pixel buffer is only guaranteed during the call:
// retain it to keep it.
typedef void (*VcnAV1OutputFn)(void* ctx, CVPixelBufferRef frame,
                               const AV1Parser* p, int64_t userTag);

VcnAV1* vcnav1_create(uint32_t maxWidth, uint32_t maxHeight, char* err,
                      size_t errLen);
// Closes the session and everything it holds of the driver. A session whose
// last command never finished is closed on a background queue (the driver
// waits for the GPU there); this returns at once.
void vcnav1_destroy(VcnAV1* d);
// Feed configuration OBUs (sequence header) e.g. from av1C. Returns 0, -1 when
// they cannot be read (or hold a frame), or VCNAV1_UNSUPPORTED when the
// sequence header asks for what the engine does not decode.
#define VCNAV1_UNSUPPORTED (-2)
int vcnav1_configure(VcnAV1* d, const uint8_t* obus, size_t size);
// Decode one temporal unit. Output frames are reported through fn
// (synchronously).
int vcnav1_decode(VcnAV1* d, const uint8_t* tu, size_t size, int64_t userTag,
                  VcnAV1OutputFn fn, void* ctx);
// Drop all reference state (e.g. after a seek)
void vcnav1_flush(VcnAV1* d);

// True when a parsed frame is a place a session can start over: nothing decoded
// before it is used after it. An intra frame reads no reference, so the only
// thing a later frame could need from before it is a slot it did not replace:
// a key frame, or an intra-only frame whose refresh_frame_flags is 0xFF.
// (AV1 spec 7.2.2: FrameIsIntra is 1 for KEY_FRAME and INTRA_ONLY_FRAME and
// refresh_frame_flags is read for both; 7.20, reference frame update: every
// slot whose bit is set is replaced by this frame, so 0xFF leaves none.)
// Chromecast-style and screen-share streams send long runs of intra-only frames
// and no key frame at all; 0.3.7 accepted key frames only, so their rebuild
// waited for ever.
#define VCN_AV1_RESTART_PREDICATE 1
static inline bool vcnav1_is_restart(const AV1Frame* h, AV1ParseResult kind) {
  return kind == AV1_PARSE_FRAME_READY &&
         (h->frame_type == AV1_KEY_FRAME ||
          h->frame_type == AV1_INTRA_ONLY_FRAME) &&
         h->refresh_frame_flags == 0xFF;
}
const char* vcnav1_last_error(VcnAV1* d);
// What made the last configure or decode fail: the stream (it cannot be
// decoded as it is), the device (a driver call failed or the GPU did not
// finish a command; the session takes no more frames), memory, or a frame
// whose reference was never decoded in this session (after a seek, or a new
// session in the middle of a stream).
enum {
  VCNAV1_FAIL_STREAM = 0,
  VCNAV1_FAIL_DEVICE = 1,
  VCNAV1_FAIL_MEMORY = 2,
  VCNAV1_FAIL_REFERENCE = 3
};
int vcnav1_failure(VcnAV1* d);
// The picture of the last frame the last vcnav1_decode decoded without
// showing it, when that call showed nothing; NULL otherwise. It happens when a
// caller sends the frames of a temporal unit one by one (FFmpeg does): a hidden
// frame then comes alone. Valid until the next decode or destroy; retain it to
// keep it.
CVPixelBufferRef vcnav1_hidden_picture(VcnAV1* d);
// The colour of the stream as its sequence header and its HDR metadata OBUs
// give it (common/vcncolor.h), for the pictures this session outputs.
void vcnav1_color(VcnAV1* d, VcnColor* c);
// Decodes the GPU firmware reported as failed (the picture was still output).
unsigned vcnav1_firmware_errors(VcnAV1* d);
// Attributes of the pixel buffers the decoder outputs (caller releases).
CFDictionaryRef vcnav1_copy_pixel_buffer_attributes(uint32_t w, uint32_t h,
                                                    bool tenBit);
extern int vcnav1_debug;
// Set by the VideoToolbox plugin (no environment there); command-line tools use
// VCNAV1_ALLOW_GPU.
extern int vcnav1_gpu_armed;
