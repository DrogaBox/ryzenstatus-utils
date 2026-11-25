/*
 * jpeg_app.h - how a program asks the VCNJpeg kext (GPU/jpeg) to decode a JPEG
 * without a user client of its own: through the AMD accelerator's video
 * context, the connection every sandboxed process may open.
 *
 *   IOServiceOpen(accelerator, task, 3, &conn)      type 3 = video context
 *   IOConnectCallStructMethod(conn, 258, in, inSize, out, &outSize)
 *
 * Selector 258 is AMDRadeonX6000_AMDAccelVideoContext::sendPMCommand(in, out,
 * inSize, &outSize), declared with variable-size structs both ways and meant
 * for PowerPlay escapes. The kext routes that function and takes the requests
 * that start with the header below; everything else goes on to the original.
 * Without the kext such a request reaches PowerPlay, whose PP_Cwdde refuses it
 * (low 16 bits of the code above 0xB0, code below 0xC08001) and changes
 * nothing: the caller gets an error and knows there is no decoder.
 *
 * Plain C: the kext, the tool and the VideoToolbox plug-in share this file.
 * Struct data is at most 4096 bytes each way. LOAD and READ move a JPEG and
 * the picture in pieces of that size; LOAD_USER and READ_USER instead give the
 * address of a buffer in the caller's own memory, which the kext reads or
 * fills with copyin/copyout in one go (a 48-megapixel picture is 74 MB: about
 * 18000 calls in pieces).
 */
#ifndef JPEG_APP_H
#define JPEG_APP_H
#include <stdint.h>

#define JA_PROTOCOL 1u
#define JA_VIDEO_CONTEXT_TYPE 3u /* IOServiceOpen type */
#define JA_SELECTOR 258u
#define JA_HEADER_SIZE 16u         /* what a PowerPlay escape header says too */
#define JA_CODE 0x004A5047u        /* never a PowerPlay escape, see above */
#define JA_REPLY_MAGIC 0x4a504741u /* "JPGA" */
#define JA_MAX_IO 4096u

enum {
  JA_OP_INFO = 1, /* reply v: state bits (JA_STATE_*), JPEG capacity, surface
                     capacity, jobs */
  JA_OP_LOAD =
      2, /* arg0 offset, arg1 size of the whole JPEG; data: the next piece */
  JA_OP_RUN = 3,  /* arg0 flags (jp::Flags); reply data: ja_picture */
  JA_OP_READ = 4, /* arg0 offset into the surface; reply data: the next piece */
  JA_OP_RELEASE = 5,   /* gives the decoder back to whoever comes next */
  JA_OP_LOAD_USER = 6, /* arg0 address of the whole JPEG in the caller's memory,
                          arg1 its size */
  JA_OP_READ_USER =
      7, /* arg0 address of a buffer in the caller's memory, arg1 its size: the
            whole surface is copied there; reply v[0] = bytes */
};

/* INFO reply v[0]: the decoder's state (the kext's jp::State) */
enum {
  JA_STATE_POOL = 1 << 0, /* the buffers were taken when the driver started */
  JA_STATE_CREATED = 1 << 1, /* the JPEG queue exists */
  JA_STATE_STARTED = 1 << 2, /* the block is powered and its queue started (only
                                while decoding) */
  JA_STATE_STUCK = 1 << 3, /* a job failed in a way that stops the decoder until
                              the next restart */
};

enum {
  JA_OK = 0,
  JA_MORE = 1,      /* LOAD: piece taken, more expected */
  JA_BUSY = 2,      /* another client holds the decoder: try again */
  JA_NOT_READY = 3, /* no buffers, queue not started, or stuck */
  JA_BAD_REQUEST = 4,
  JA_NOT_OWNER = 5,  /* RUN or READ without a LOAD of this client */
  JA_BAD_STREAM = 6, /* detail: jc::Stream */
  JA_FAILED = 7,     /* the job did not succeed; detail: jp::Status */
  JA_BAD_ADDRESS =
      8, /* LOAD_USER / READ_USER: the buffer could not be read or written */
};

struct ja_request {
  uint32_t size;     /* JA_HEADER_SIZE */
  uint32_t code;     /* JA_CODE */
  uint32_t protocol; /* JA_PROTOCOL */
  uint32_t op;
  uint64_t arg0;
  uint64_t arg1;
  /* data follows */
};

struct ja_reply {
  uint32_t magic;  /* JA_REPLY_MAGIC */
  uint32_t status; /* JA_OK ... */
  uint32_t detail;
  uint32_t dataBytes; /* bytes of data after this struct */
  uint64_t v[4];
  /* data follows */
};

/* What RUN returns about the picture; the surface is NV12 with this layout. */
struct ja_picture {
  uint32_t width, height;
  uint32_t pitch;         /* bytes per row, luma and chroma */
  uint32_t alignedHeight; /* luma rows in the surface */
  uint32_t chromaOffset;  /* from the start of the surface */
  uint32_t surfaceBytes;
  uint32_t elapsedMs; /* submit to completion, in the kernel */
  uint32_t format;    /* 0 NV12 (4:2:0: luma, then UV at chromaOffset), 1 YUYV
                         (4:2:2, one plane) */
};

#define JA_LOAD_PIECE (JA_MAX_IO - (uint32_t)sizeof(struct ja_request))
#define JA_READ_PIECE (JA_MAX_IO - (uint32_t)sizeof(struct ja_reply))

#endif
