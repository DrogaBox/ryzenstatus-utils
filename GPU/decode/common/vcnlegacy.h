// MPEG-2, VC-1 and MPEG-4 part 2 on the AMD VCN through AMDRadeonVADriver2.
//
// The driver has no VCN code for these three codecs (its MPEG-2/VC-1 classes
// build UVD messages, and it has none for MPEG-4), but the VCN firmware it
// loads decodes them. Like the VP9 decoder (vp9/vcnvp9.c), a session keeps the
// driver's AV1 context for the buffers and the submission, and replaces the
// message building on that one processor object. What differs from VP9:
//
//   - the decode message is laid out as Mesa does for these codecs: two index
//     entries (decode block, codec block), no DRM block, hw_ctxt_size 0,
//     sw_ctxt_size 128 KiB;
//   - no context buffer goes with the command. With one (ring command 0x206)
//     the firmware drops the decode without reporting anything;
//   - the firmware keeps the reference pictures in the DPB buffer itself, so a
//     session only hands it the pictures in decoding order.
//
// One session is one coded size. The codec layers (mpeg2/, vc1/, mpeg4/) parse
// the stream, fill the codec block and call vcnlegacy_decode once per picture.
#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <CoreVideo/CoreVideo.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Mesa's RDECODE_CODEC_* and RDECODE_MESSAGE_* (ac_vcn_dec.h).
#define VCN_CODEC_VC1 0x1u
#define VCN_CODEC_MPEG2_VLD 0x3u
#define VCN_CODEC_MPEG4 0x4u
#define VCN_MESSAGE_VC1 0x7u
#define VCN_MESSAGE_MPEG2_VLD 0xAu
#define VCN_MESSAGE_MPEG4_ASP_VLD 0xBu

// What the Linux driver allows these three codecs on Navi 21 (nv.c,
// sc_video_codecs_decode_array_vcn0).
enum { VCNLEGACY_MAX_WIDTH = 1920, VCNLEGACY_MAX_HEIGHT = 1088 };

typedef struct VcnLegacy VcnLegacy;

typedef struct {
  uint32_t codecId;        // VCN_CODEC_*
  uint32_t messageId;      // VCN_MESSAGE_* of the codec block
  uint32_t width, height;  // of the pictures, in samples
  // VC-1 simple and main profile: the decode block carries the size in
  // macroblocks (Mesa, ac_vcn_dec.c vcn_build_decode_cmd).
  bool sizeInMacroblocks;
  const char* logSubsystem;  // os_log subsystem of the codec
} VcnLegacyConfig;

extern int vcnlegacy_debug;
// Switches for experiments (decode_legacy reads them from the environment).
// vcnlegacy_db_height_mode 1: db_aligned_height 0 in the decode block, as
// Mesa 25's radeon_vcn_dec.c leaves it for every codec but VP9, AV1 and HEVC
// Main 10; 0 (the default): the height aligned to 64.
// vcnlegacy_clear_dpb 1: the DPB buffer is filled with zeros before the
// session's first picture, as Mesa's si_vid_clear_buffer does, when the driver
// maps it into this task (the debug log says whether it could).
extern int vcnlegacy_db_height_mode;
extern int vcnlegacy_clear_dpb;
// The plug-ins set this. Command line tools arm themselves with
// VCNLEGACY_ALLOW_GPU=yes-i-know-it-can-hang instead.
extern int vcnlegacy_gpu_armed;

// What made the last decode fail (same meaning as VCNVP9_FAIL_*).
enum {
  VCNLEGACY_FAIL_STREAM = 0,
  VCNLEGACY_FAIL_DEVICE = 1,
  VCNLEGACY_FAIL_MEMORY = 2,
  VCNLEGACY_FAIL_REFERENCE = 3
};

// Size of the DPB buffer for a session: six pictures at the pitch the message
// declares, plus the per-codec buffers Mesa's calc_dpb_size adds (the firmware
// keeps its VC-1 and MPEG-4 side data inside the DPB buffer).
uint32_t vcnlegacy_dpb_size(uint32_t codecId, uint32_t width, uint32_t height);

// The decode message, built apart from the driver so that a test can check it
// byte by byte. Returns its size, or 0 when it does not fit cap or the surface
// offsets do not fit their 32-bit fields.
typedef struct {
  uint32_t codecId, messageId;
  uint32_t width, height;
  bool sizeInMacroblocks;
  uint32_t pitch, texHeight, bytesPerElement;  // of the target texture
  uint32_t dpbSize, bitstreamSize;
  uint32_t streamHandle, feedbackNumber;
  bool dbHeightZero;  // db_aligned_height 0 (vcnlegacy_db_height_mode 1)
  const void* block;
  uint32_t blockSize;
} VcnLegacyMessage;
uint32_t vcnlegacy_build_message(uint8_t* msg, size_t cap,
                                 const VcnLegacyMessage* m);

CFDictionaryRef vcnlegacy_copy_pixel_buffer_attributes(uint32_t w, uint32_t h);

// Whether a session could be made on this Mac at all: the driver loads, its
// build is one this path was run on, and there is an AMD accelerator. Nothing
// is opened. A plug-in asks this when a session starts, so that VideoToolbox
// can pick another decoder before the first frame.
bool vcnlegacy_available(char* err, size_t errLen);

VcnLegacy* vcnlegacy_create(const VcnLegacyConfig* cfg, char* err,
                            size_t errLen);
// Closes the session. One whose last command never finished is closed on a
// background queue (the driver waits for the GPU there); this returns at once.
void vcnlegacy_destroy(VcnLegacy* d);

// A new NV12 picture of the session's size, from its pool. The caller owns it.
CVPixelBufferRef vcnlegacy_new_target(VcnLegacy* d);

typedef struct {
  const uint8_t* data;
  size_t size;
} VcnLegacyBytes;

// Decodes one picture into target: the codec block and the bitstream, given in
// parts that are sent one after the other. Two field pictures of one frame are
// two calls with the same target. 0, or -1 with vcnlegacy_last_error and
// vcnlegacy_failure set.
int vcnlegacy_decode(VcnLegacy* d, const void* block, uint32_t blockSize,
                     const VcnLegacyBytes* parts, int nparts,
                     CVPixelBufferRef target);

// ---- what the three codec layers share with their callers ----------------
// How a decoded picture is used by later ones, for a caller that puts pictures
// back in display order (VideoToolbox does that itself from the timestamps).
enum {
  VCNLEGACY_PIC_REFERENCE = 0,  // I or P: shown after the B pictures that
                                // follow it in the stream
  VCNLEGACY_PIC_B = 1,          // shown at once
};
// One decoded frame, in decoding order. A non-zero return stops the decode of
// the rest of the chunk.
typedef int (*VcnLegacyOutputFn)(void* ctx, CVPixelBufferRef pb, int use,
                                 uint32_t width, uint32_t height);

// A codec layer as the plug-in and the command line tool drive it.
typedef struct {
  const char* name;
  // config: the headers that travel outside the samples (MPEG-4: the decoder
  // configuration of the esds atom; VC-1: the sequence header of a dvc1 atom,
  // or the four header bytes of a simple/main profile stream), or NULL.
  // width/height: the size the container gives.
  void* (*create)(const uint8_t* config, size_t configSize, uint32_t width,
                  uint32_t height, char* err, size_t errLen);
  void (*destroy)(void* d);
  // One sample, or any chunk that holds whole pictures.
  int (*decode)(void* d, const uint8_t* chunk, size_t size,
                VcnLegacyOutputFn fn, void* ctx);
  const char* (*last_error)(void* d);
  int (*failure)(void* d);  // VCNLEGACY_FAIL_*
  unsigned (*firmware_errors)(void* d);
} VcnLegacyCodec;

const char* vcnlegacy_last_error(VcnLegacy* d);
int vcnlegacy_failure(VcnLegacy* d);
// Decodes the firmware reported as failed, or did not run at all (the picture
// was still handed back).
unsigned vcnlegacy_firmware_errors(VcnLegacy* d);
// The last command's result, from the VCN feedback buffer: whether the
// firmware wrote one at all, and its status (0 = no error). False when the
// feedback buffer could not be watched on this driver build.
bool vcnlegacy_last_status(VcnLegacy* d, bool* executed, uint32_t* status);
uint32_t vcnlegacy_width(VcnLegacy* d);
uint32_t vcnlegacy_height(VcnLegacy* d);
