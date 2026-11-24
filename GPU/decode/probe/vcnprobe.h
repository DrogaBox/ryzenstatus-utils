// One frame through the AV1 VCN context with our own create/decode message.
// The session code follows GPU/decode/vp9/vcnvp9.c: the driver's AV1 processor
// is kept, its factory is wrapped for the length of CreateContexts, and the
// five virtual slots that build the message are ours. Nothing is submitted
// unless the caller passes gpu = 1, which only main() sets from
// VCNPROBE_ALLOW_GPU=yes-i-know-it-can-hang.
#pragma once
#include <stddef.h>
#include <stdint.h>

typedef struct {
  uint32_t codecId;      // RDECODE_CODEC_* for create and decode blocks
  uint32_t messageId;    // RDECODE_MESSAGE_* of the codec block
  const void* block;     // codec block, blockSize bytes
  uint32_t blockSize;
  uint32_t width, height;
  const uint8_t* bitstream;
  size_t bitstreamSize;
  // Driver-facing session fields, from the stream's own header.
  uint32_t profile;   // AV1/VP9 profile; 0 for the legacy codecs
  uint32_t depth;     // 8 or 10; the driver stores it in the processor
  int vc1Simple;      // VC-1 simple/main: decode size in 16-sample units
  const void* vp9;    // const VP9Parser*, only for the VP9 control
} ProbeJob;

// 0 on success (dry run: the messages were built and printed; gpu: the command
// finished and outPath holds NV12), -1 with err set.
int vcnprobe_run(const ProbeJob* job, const char* outPath, int gpu, char* err,
                 size_t errLen);
