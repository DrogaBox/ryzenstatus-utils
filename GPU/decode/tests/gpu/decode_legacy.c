// decode_legacy <mpeg2|vc1|mpeg4> <stream> <out.nv12> [max frames]
//
// MPEG-2, VC-1 or MPEG-4 part 2 on the VCN, without VideoToolbox: the codec
// layers the plug-ins use (mpeg2/, vc1/, mpeg4/ on common/vcnlegacy.c), fed a
// whole elementary stream. The frames are written as NV12 in display order,
// so the file compares frame by frame with
//   ffmpeg -i <stream> -f rawvideo -pix_fmt nv12 ref.nv12
//
// Streams: .m2v (MPEG-2 video), .m4v (MPEG-4 with its VOL header), .vc1
// (advanced profile with start codes), .rcv (VC-1 simple/main profile as
// FFmpeg's vc1test muxer writes it).
//
// It sends commands to the GPU and can hang it; armed only by
// VCNLEGACY_ALLOW_GPU=yes-i-know-it-can-hang. Switches for experiments:
//   VCNMPEG2_INDEX=0|1   vcnmpeg2_index_mode  (picture numbers / zero)
//   VCNMPEG2_MATRIX=0|1  vcnmpeg2_matrix_mode (scan order / transposed)
//   VCNMPEG4_INDEX=0|1   vcnmpeg4_index_mode
//   VCNMPEG4_BLOCK=0..3  vcnmpeg4_block_mode  (Mesa's block / VOP part filled)
//   VCNMPEG4_MATRIX=0|1  vcnmpeg4_matrix_mode (stream order / transposed)
//   VCNMPEG4_ALLOW_B=1   send B-VOPs too (each can hang the video engine)
#include <CoreVideo/CoreVideo.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vcndriver.h"
#include "vcnlegacy.h"
#include "vcnmpeg2.h"
#include "vcnmpeg4.h"
#include "vcnvc1.h"

static uint8_t* read_file(const char* path, size_t* size) {
  FILE* f = fopen(path, "rb");
  if (!f) return NULL;
  uint8_t* p = NULL;
  long n = 0;
  if (!fseek(f, 0, SEEK_END) && (n = ftell(f)) > 0 && !fseek(f, 0, SEEK_SET) &&
      (p = malloc((size_t)n)) && fread(p, 1, (size_t)n, f) != (size_t)n) {
    free(p);
    p = NULL;
  }
  fclose(f);
  if (p) *size = (size_t)n;
  return p;
}

typedef struct {
  FILE* out;
  CVPixelBufferRef held;  // a reference picture waiting for the B pictures
  uint32_t heldW, heldH;  // shown before it
  int written, decoded, max;
  int failed;
} Sink;

static void write_frame(Sink* s, CVPixelBufferRef pb, uint32_t w, uint32_t h) {
  if (s->max && s->written >= s->max) return;
  if (CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly)) {
    s->failed = 1;
    return;
  }
  for (int plane = 0; plane < 2; plane++) {
    const uint8_t* base = CVPixelBufferGetBaseAddressOfPlane(pb, plane);
    size_t pitch = CVPixelBufferGetBytesPerRowOfPlane(pb, plane);
    size_t rows = plane ? (h + 1) / 2 : h, cols = plane ? (w + 1) / 2 * 2 : w;
    for (size_t y = 0; base && y < rows; y++)
      if (fwrite(base + y * pitch, 1, cols, s->out) != cols) s->failed = 1;
    if (!base) s->failed = 1;
  }
  CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  s->written++;
}

static void flush_held(Sink* s) {
  if (!s->held) return;
  write_frame(s, s->held, s->heldW, s->heldH);
  CVPixelBufferRelease(s->held);
  s->held = NULL;
}

// Decoding order to display order: a B picture is shown at once, a reference
// picture after the B pictures that follow it in the stream.
static int on_frame(void* ctx, CVPixelBufferRef pb, int use, uint32_t w,
                    uint32_t h) {
  Sink* s = ctx;
  s->decoded++;
  if (use == VCNLEGACY_PIC_B) {
    write_frame(s, pb, w, h);
  } else {
    flush_held(s);
    s->held = CVPixelBufferRetain(pb);
    s->heldW = w;
    s->heldH = h;
  }
  // One more than asked for is decoded, so the last one's place in the display
  // order is known.
  return s->max && s->decoded > s->max;
}

static int env_int(const char* name, int dflt) {
  const char* v = getenv(name);
  return v && *v ? atoi(v) : dflt;
}

static uint32_t le32(const uint8_t* p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
         ((uint32_t)p[3] << 24);
}

int main(int argc, char** argv) {
  setvbuf(stdout, NULL, _IONBF, 0);
  if (argc < 4 || argc > 5) {
    fprintf(stderr,
            "usage: %s <mpeg2|vc1|mpeg4> <stream> <out.nv12> [max frames]\n"
            "  armed by VCNLEGACY_ALLOW_GPU=yes-i-know-it-can-hang\n",
            argv[0]);
    return 2;
  }
  const VcnLegacyCodec* codec = !strcmp(argv[1], "mpeg2")   ? &vcnmpeg2_codec
                                : !strcmp(argv[1], "vc1")   ? &vcnvc1_codec
                                : !strcmp(argv[1], "mpeg4") ? &vcnmpeg4_codec
                                                            : NULL;
  if (!codec) {
    fprintf(stderr, "unknown codec %s\n", argv[1]);
    return 2;
  }
  // Unset: the codec layer's own default.
  vcnmpeg2_index_mode = env_int("VCNMPEG2_INDEX", vcnmpeg2_index_mode);
  vcnmpeg2_matrix_mode = env_int("VCNMPEG2_MATRIX", vcnmpeg2_matrix_mode);
  vcnmpeg4_index_mode = env_int("VCNMPEG4_INDEX", vcnmpeg4_index_mode);
  vcnmpeg4_block_mode = env_int("VCNMPEG4_BLOCK", vcnmpeg4_block_mode);
  vcnmpeg4_matrix_mode = env_int("VCNMPEG4_MATRIX", vcnmpeg4_matrix_mode);
  vcnlegacy_debug = env_int("VCNLEGACY_DEBUG", vcnlegacy_debug);
  size_t size = 0;
  uint8_t* data = read_file(argv[2], &size);
  if (!data) {
    fprintf(stderr, "cannot read %s\n", argv[2]);
    return 1;
  }
  Sink sink = {.max = argc == 5 ? atoi(argv[4]) : 0};
  sink.out = fopen(argv[3], "wb");
  if (!sink.out) {
    fprintf(stderr, "cannot write %s\n", argv[3]);
    return 1;
  }
  char err[256] = "";
  int rc = 0;
  void* d = NULL;
  // FFmpeg's vc1test muxer: frame count and 0xC5, 4, STRUCT_C, height, width,
  // 12, three more words; then per frame its size (key flag in the top bit),
  // a timestamp and the data.
  bool rcv = size > 36 && data[3] == 0xC5 && le32(data + 4) == 4 &&
             codec == &vcnvc1_codec;
  if (rcv) {
    uint32_t h = le32(data + 12), w = le32(data + 16);
    d = codec->create(data + 8, 4, w, h, err, sizeof(err));
    size_t at = 36;
    while (d && !rc && at + 8 <= size) {
      uint32_t n = le32(data + at) & 0x00ffffff;
      at += 8;
      if (at + n > size) break;
      rc = codec->decode(d, data + at, n, on_frame, &sink);
      at += n;
      if (sink.max && sink.decoded > sink.max) break;
    }
  } else {
    d = codec->create(NULL, 0, 0, 0, err, sizeof(err));
    if (d) rc = codec->decode(d, data, size, on_frame, &sink);
  }
  if (!d) {
    fprintf(stderr, "%s: %s\n", codec->name, err);
    return 1;
  }
  flush_held(&sink);
  if (rc)
    fprintf(stderr, "%s: decode stopped: %s (failure %d)\n", codec->name,
            codec->last_error(d), codec->failure(d));
  printf("%s: %d frames decoded, %d written, firmware errors %u%s\n",
         codec->name, sink.decoded, sink.written, codec->firmware_errors(d),
         sink.failed ? ", WRITE FAILED" : "");
  codec->destroy(d);
  fclose(sink.out);
  free(data);
  // A session whose command never finished closes on a background queue.
  if (!vcn_teardown_drain(5000))
    fprintf(stderr, "a stuck session is still closing; leaving it\n");
  return rc || sink.failed ? 1 : 0;
}
