// VP9 on the AMD VCN through AMDRadeonVADriver2, which has no VP9 code of its
// own. It reuses the driver's AV1 context (session, buffers, submission) and
// replaces the message building on that one processor object. Nothing in the
// driver's memory is patched.
#pragma once
#include <CoreVideo/CoreVideo.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "vcncolor.h"
#include "vp9parse.h"

typedef struct VcnVP9 VcnVP9;
typedef void (*VcnVP9OutputFn)(void* ctx, CVPixelBufferRef pb,
                               const VP9Parser* p, uint32_t width,
                               uint32_t height, int64_t tag);

extern int vcnvp9_debug;
// The plugin sets this. The command line tool arms itself through the
// environment instead.
extern int vcnvp9_gpu_armed;

CFDictionaryRef vcnvp9_copy_pixel_buffer_attributes(uint32_t w, uint32_t h,
                                                    bool tenBit);

VcnVP9* vcnvp9_create(uint32_t maxWidth, uint32_t maxHeight, char* err,
                      size_t errLen);
// Closes the session and everything it holds of the driver. A session whose
// last command never finished is closed on a background queue (the driver
// waits for the GPU there); this returns at once.
void vcnvp9_destroy(VcnVP9* d);
int vcnvp9_decode(VcnVP9* d, const uint8_t* chunk, size_t size, int64_t tag,
                  VcnVP9OutputFn fn, void* ctx);
const char* vcnvp9_last_error(VcnVP9* d);
// What made the last decode fail: the stream (it cannot be decoded as it is),
// the device (a driver call failed or the GPU did not finish a command; the
// session takes no more frames) or memory.
// VCNVP9_FAIL_REFERENCE: a frame whose reference was never decoded in this
// session (after a seek, or a new session in the middle of a stream).
enum {
  VCNVP9_FAIL_STREAM = 0,
  VCNVP9_FAIL_DEVICE = 1,
  VCNVP9_FAIL_MEMORY = 2,
  VCNVP9_FAIL_REFERENCE = 3
};
int vcnvp9_failure(VcnVP9* d);
// The picture of the last frame the last vcnvp9_decode decoded without showing
// it, when that call showed nothing; NULL otherwise. It happens when a caller
// sends the frames of a superframe one by one (FFmpeg does): a hidden frame
// then comes alone. Valid until the next decode or destroy; retain it to keep
// it.
CVPixelBufferRef vcnvp9_hidden_picture(VcnVP9* d);
// The colour the stream's last colour config names (color_space; the
// bitstream has no transfer function), for the pictures this session outputs.
void vcnvp9_color(VcnVP9* d, VcnColor* c);
// Decodes the GPU firmware reported as failed (the picture was still output).
unsigned vcnvp9_firmware_errors(VcnVP9* d);

// True when a parsed frame is a place a session can start over: nothing decoded
// before it is used after it. A key frame, or an intra-only frame that replaces
// all eight slots and resets all four probability contexts:
// error_resilient_mode or reset_frame_context 3. reset_frame_context 2 resets
// only the context frame_context_idx names (libvpx
// vp9_setup_past_independence), and the other three live in the old driver's
// buffers: a later frame that reads one of them would decode with the new
// session's default probabilities.
#define VCN_VP9_RESTART_PREDICATE 1
static inline bool vcnvp9_is_restart(const VP9Frame* h, VP9ParseResult kind) {
  if (kind != VP9_PARSE_DECODE) return false;
  if (h->frame_type == 0) return true;
  return h->intra_only && h->refresh_frame_flags == 0xff &&
         (h->error_res || h->reset_frame_context == 3);
}
