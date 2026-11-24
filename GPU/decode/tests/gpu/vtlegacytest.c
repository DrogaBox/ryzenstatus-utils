// vtlegacytest <mpeg2|vc1|mpeg4> <stream> <out.nv12>
//
// The MPEG-2, VC-1 and MPEG-4 plug-ins through VideoToolbox, on the GPU,
// without installing them: the three plug-ins are linked into this program
// and registered with VideoToolbox for this process only
// (VTRegisterVideoDecoder). The stream is cut into one sample per picture and
// goes through a VTDecompressionSession, as a player would send it. The frames
// are written as NV12 in display order, like decode_legacy does, so the two
// outputs and FFmpeg's can be compared.
//
// Streams: .m2v, .m4v, .vc1 (advanced profile with start codes), .rcv (VC-1
// simple/main as FFmpeg's vc1test muxer writes it).
//
// It sends commands to the GPU and can hang it. It decodes only with
// VCNLEGACY_ALLOW_GPU=yes-i-know-it-can-hang; without it, it says how it cut
// the stream into samples and stops before VideoToolbox is touched.
#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <VideoToolbox/VideoToolbox.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mpeg2parse.h"
#include "mpeg4parse.h"
#include "vc1parse.h"
#include "vcndriver.h"
#include "vcnlegacy.h"
#include "vcnmpeg2.h"
#include "vcnmpeg4.h"

typedef OSStatus (*Factory)(FourCharCode, CFAllocatorRef, void**);
// VideoToolbox's registration for decoders that live in the caller (WebKit
// registers its VP8 and VP9 decoders with it).
extern void VTRegisterVideoDecoder(CMVideoCodecType codec, Factory factory);
extern OSStatus MPEG2VCN_VTDecoder_CreateInstance(FourCharCode, CFAllocatorRef,
                                                  void**);
extern OSStatus VC1VCN_VTDecoder_CreateInstance(FourCharCode, CFAllocatorRef,
                                                void**);
extern OSStatus MPEG4VCN_VTDecoder_CreateInstance(FourCharCode, CFAllocatorRef,
                                                  void**);

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

// ---- the samples: one picture each, with the headers in front of it
typedef struct {
  const uint8_t* data;
  size_t size;
  int b;  // a B picture: shown at once
} Sample;
typedef struct {
  const uint8_t* base;
  size_t end;  // where the previous sample ended
  Sample* s;
  int n, cap;
  uint32_t width, height;
  size_t headers;  // MPEG-4: the bytes in front of the first VOP
} Cut;

static void add(Cut* c, const uint8_t* data, size_t size, int b) {
  if (c->n == c->cap) {
    c->cap = c->cap ? c->cap * 2 : 64;
    c->s = realloc(c->s, sizeof(Sample) * (size_t)c->cap);
    if (!c->s) abort();
  }
  c->s[c->n++] = (Sample){data, size, b};
}
static void add_to(Cut* c, const uint8_t* pictureEnd, int b) {
  size_t end = (size_t)(pictureEnd - c->base);
  add(c, c->base + c->end, end - c->end, b);
  c->end = end;
}
static int cut_mpeg2(void* ctx, Mpeg2Parser* p, const Mpeg2Picture* pic) {
  Cut* c = ctx;
  c->width = p->width;
  c->height = p->height;
  add_to(c, pic->slices + pic->slicesSize, pic->coding_type == MPEG2_B);
  return 0;
}
static int cut_vc1(void* ctx, Vc1Parser* p, const Vc1Picture* pic) {
  Cut* c = ctx;
  c->width = p->width;
  c->height = p->height;
  add_to(c, pic->data + pic->size, pic->type == VC1_B || pic->type == VC1_BI);
  return 0;
}
static int cut_mpeg4(void* ctx, Mpeg4Parser* p, const Mpeg4Picture* pic) {
  Cut* c = ctx;
  c->width = p->width;
  c->height = p->height;
  if (!c->n) c->headers = pic->vopOffset;
  add(c, pic->data, pic->size, pic->coding_type == MPEG4_B);
  return 0;
}

// An esds atom as an MP4 file carries it: the headers in front of the first
// VOP are the decoder specific info (ISO 14496-1 7.2.6). Sizes in the 4-byte
// form.
static size_t put_descriptor(uint8_t* at, uint8_t tag, size_t len) {
  at[0] = tag;
  at[1] = 0x80 | (uint8_t)((len >> 21) & 0x7f);
  at[2] = 0x80 | (uint8_t)((len >> 14) & 0x7f);
  at[3] = 0x80 | (uint8_t)((len >> 7) & 0x7f);
  at[4] = (uint8_t)(len & 0x7f);
  return 5;
}
static CFDictionaryRef mpeg4_esds(const uint8_t* headers, size_t n);

static uint32_t le32(const uint8_t* p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
         ((uint32_t)p[3] << 24);
}

// ---- output, in display order
typedef struct {
  FILE* out;
  CVPixelBufferRef held;
  int written, images, dropped, errors;
  OSStatus firstError;
  uint32_t width, height;
} Sink;

static void write_frame(Sink* s, CVPixelBufferRef pb) {
  if (CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly)) return;
  uint32_t w = s->width, h = s->height;
  for (int plane = 0; plane < 2; plane++) {
    const uint8_t* base = CVPixelBufferGetBaseAddressOfPlane(pb, plane);
    size_t pitch = CVPixelBufferGetBytesPerRowOfPlane(pb, plane);
    size_t rows = plane ? (h + 1) / 2 : h, cols = plane ? (w + 1) / 2 * 2 : w;
    for (size_t y = 0; base && y < rows; y++)
      fwrite(base + y * pitch, 1, cols, s->out);
  }
  CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  s->written++;
}
static void flush_held(Sink* s) {
  if (!s->held) return;
  write_frame(s, s->held);
  CVPixelBufferRelease(s->held);
  s->held = NULL;
}
static void on_frame(void* refcon, void* frameRefcon, OSStatus status,
                     VTDecodeInfoFlags flags, CVImageBufferRef image,
                     CMTime pts, CMTime duration) {
  (void)pts, (void)duration;
  Sink* s = refcon;
  if (status) {
    if (!s->errors++) s->firstError = status;
    return;
  }
  if (!image || (flags & kVTDecodeInfo_FrameDropped)) {
    s->dropped++;
    return;
  }
  s->images++;
  if (frameRefcon) {  // a B picture
    write_frame(s, image);
  } else {
    flush_held(s);
    s->held = CVPixelBufferRetain(image);
  }
}

static CFDictionaryRef atoms(CFStringRef name, const uint8_t* bytes, size_t n) {
  CFDataRef data = CFDataCreate(NULL, bytes, (CFIndex)n);
  const void* k1[] = {name};
  const void* v1[] = {data};
  CFDictionaryRef inner =
      CFDictionaryCreate(NULL, k1, v1, 1, &kCFTypeDictionaryKeyCallBacks,
                         &kCFTypeDictionaryValueCallBacks);
  const void* k2[] = {
      kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms};
  const void* v2[] = {inner};
  CFDictionaryRef ext =
      CFDictionaryCreate(NULL, k2, v2, 1, &kCFTypeDictionaryKeyCallBacks,
                         &kCFTypeDictionaryValueCallBacks);
  CFRelease(inner);
  CFRelease(data);
  return ext;
}

static CFDictionaryRef mpeg4_esds(const uint8_t* headers, size_t n) {
  size_t decConfig = 13 + 5 + n, es = 3 + 5 + decConfig + 5 + 1;
  uint8_t* e = calloc(1, 4 + 5 + es);
  if (!e) abort();
  size_t at = 4;  // version and flags
  at += put_descriptor(e + at, 3, es);
  e[at++] = 0, e[at++] = 1, e[at++] = 0;  // ES_ID 1, no flags
  at += put_descriptor(e + at, 4, decConfig);
  e[at++] = 0x20;  // MPEG-4 visual
  e[at++] = 0x11;  // visual stream
  at += 11;        // buffer size, max and average bitrate: 0
  at += put_descriptor(e + at, 5, n);
  memcpy(e + at, headers, n);
  at += n;
  at += put_descriptor(e + at, 6, 1);
  e[at++] = 2;  // SL config: predefined for MP4
  CFDictionaryRef ext = atoms(CFSTR("esds"), e, at);
  free(e);
  return ext;
}

int main(int argc, char** argv) {
  setvbuf(stdout, NULL, _IONBF, 0);
  if (argc != 4) {
    fprintf(stderr, "usage: %s <mpeg2|vc1|mpeg4> <stream> <out.nv12>\n",
            argv[0]);
    return 2;
  }
  // The same switches for experiments as decode_legacy.
  const char* v;
  if ((v = getenv("VCNMPEG2_INDEX"))) vcnmpeg2_index_mode = atoi(v);
  if ((v = getenv("VCNMPEG2_MATRIX"))) vcnmpeg2_matrix_mode = atoi(v);
  if ((v = getenv("VCNMPEG4_INDEX"))) vcnmpeg4_index_mode = atoi(v);
  if ((v = getenv("VCNMPEG4_BLOCK"))) vcnmpeg4_block_mode = atoi(v);
  if ((v = getenv("VCNLEGACY_DEBUG"))) vcnlegacy_debug = atoi(v);
  size_t size = 0;
  uint8_t* data = read_file(argv[2], &size);
  if (!data) {
    fprintf(stderr, "cannot read %s\n", argv[2]);
    return 1;
  }
  Cut cut = {.base = data};
  CMVideoCodecType codec = 0;
  CFDictionaryRef ext = NULL;
  const char* perr = "";
  int r = 0;
  if (!strcmp(argv[1], "mpeg2")) {
    Mpeg2Parser p;
    mpeg2_parser_init(&p);
    r = mpeg2_parse_chunk(&p, data, size, cut_mpeg2, &cut);
    perr = r ? p.err : "";
    codec = kCMVideoCodecType_MPEG2Video;
    VTRegisterVideoDecoder(codec, MPEG2VCN_VTDecoder_CreateInstance);
  } else if (!strcmp(argv[1], "mpeg4")) {
    Mpeg4Parser p;
    mpeg4_parser_init(&p);
    r = mpeg4_parse_chunk(&p, data, size, cut_mpeg4, &cut);
    perr = r ? p.err : "";
    codec = kCMVideoCodecType_MPEG4Video;
    VTRegisterVideoDecoder(codec, MPEG4VCN_VTDecoder_CreateInstance);
  } else if (!strcmp(argv[1], "vc1")) {
    Vc1Parser p;
    vc1_parser_init(&p);
    if (size > 36 && data[3] == 0xC5 && le32(data + 4) == 4) {
      // .rcv: the header bytes go in a strf atom (a 40-byte BITMAPINFOHEADER,
      // then the codec private data), each frame is one sample.
      uint8_t strf[44] = {0};
      memcpy(strf + 40, data + 8, 4);
      cut.height = le32(data + 12);
      cut.width = le32(data + 16);
      r = vc1_parse_struct_c(&p, data + 8, 4, cut.width, cut.height);
      perr = r ? p.err : "";
      for (size_t at = 36; !r && at + 8 <= size;) {
        uint32_t n = le32(data + at) & 0x00ffffff;
        at += 8;
        if (at + n > size) break;
        // B or not: FFmpeg's ff_vc1_parse_frame_header, as vc1parse.c reads it.
        Cut one = {.base = data};
        vc1_parse_frame(&p, data + at, n, cut_vc1, &one);
        add(&cut, data + at, n, one.n ? one.s[0].b : 0);
        free(one.s);
        at += n;
      }
      ext = atoms(CFSTR("strf"), strf, sizeof(strf));
      codec = 'WMV3';
    } else {
      r = vc1_parse_chunk(&p, data, size, cut_vc1, &cut);
      perr = r ? p.err : "";
      codec = 'WVC1';
    }
    VTRegisterVideoDecoder(codec, VC1VCN_VTDecoder_CreateInstance);
  } else {
    fprintf(stderr, "unknown codec %s\n", argv[1]);
    return 2;
  }
  if (!r && cut.n && codec == kCMVideoCodecType_MPEG4Video && cut.headers)
    ext = mpeg4_esds(cut.s[0].data, cut.headers);
  if (r || !cut.n || !cut.width) {
    fprintf(stderr, "%s: cannot cut the stream into pictures: %s\n", argv[1],
            perr);
    return 1;
  }
  int bs = 0;
  for (int i = 0; i < cut.n; i++) bs += cut.s[i].b;
  printf("%s: %d samples (%d B pictures), %ux%u\n", argv[1], cut.n, bs,
         cut.width, cut.height);
  // Without the switch the program stops here: the stream was only cut.
  const char* arm = getenv("VCNLEGACY_ALLOW_GPU");
  if (!arm || strcmp(arm, "yes-i-know-it-can-hang")) {
    fprintf(stderr, "GPU submission disabled (set VCNLEGACY_ALLOW_GPU)\n");
    return 1;
  }
  CMVideoFormatDescriptionRef fmt = NULL;
  if (CMVideoFormatDescriptionCreate(NULL, codec, (int32_t)cut.width,
                                     (int32_t)cut.height, ext, &fmt) ||
      !fmt) {
    fprintf(stderr, "no format description\n");
    return 1;
  }
  Sink sink = {.width = cut.width, .height = cut.height};
  sink.out = fopen(argv[3], "wb");
  if (!sink.out) {
    fprintf(stderr, "cannot write %s\n", argv[3]);
    return 1;
  }
  VTDecompressionOutputCallbackRecord cb = {on_frame, &sink};
  VTDecompressionSessionRef session = NULL;
  OSStatus st =
      VTDecompressionSessionCreate(NULL, fmt, NULL, NULL, &cb, &session);
  if (st || !session) {
    fprintf(stderr, "VTDecompressionSessionCreate %d\n", (int)st);
    return 1;
  }
  // Which decoder VideoToolbox picked: ours says it is hardware accelerated.
  CFBooleanRef hw = NULL;
  VTSessionCopyProperty(
      session, kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
      NULL, &hw);
  printf("session %ux%u, %d samples, hardware decoder: %s\n", cut.width,
         cut.height, cut.n,
         hw == kCFBooleanTrue ? "yes"
         : hw                 ? "no"
                              : "not reported");
  if (hw) CFRelease(hw);
  int refused = 0;
  for (int i = 0; i < cut.n; i++) {
    CMBlockBufferRef bb = NULL;
    CMSampleBufferRef sb = NULL;
    size_t n = cut.s[i].size;
    if (CMBlockBufferCreateWithMemoryBlock(NULL, (void*)cut.s[i].data, n,
                                           kCFAllocatorNull, NULL, 0, n, 0,
                                           &bb) ||
        CMSampleBufferCreateReady(NULL, bb, fmt, 1, 0, NULL, 1, &n, &sb)) {
      fprintf(stderr, "no sample buffer\n");
      return 1;
    }
    st = VTDecompressionSessionDecodeFrame(session, sb, 0,
                                           cut.s[i].b ? (void*)1 : NULL, NULL);
    if (st && !refused++)
      fprintf(stderr, "sample %d: VTDecompressionSessionDecodeFrame %d\n", i,
              (int)st);
    CFRelease(sb);
    CFRelease(bb);
    // A decoder that broke takes no more frames.
    if (st == kVTVideoDecoderMalfunctionErr) break;
  }
  VTDecompressionSessionWaitForAsynchronousFrames(session);
  flush_held(&sink);
  printf(
      "%s through VideoToolbox: %d samples, %d pictures, %d written, %d "
      "dropped, %d errors (first %d), %d refused\n",
      argv[1], cut.n, sink.images, sink.written, sink.dropped, sink.errors,
      (int)sink.firstError, refused);
  VTDecompressionSessionInvalidate(session);
  CFRelease(session);
  CFRelease(fmt);
  if (ext) CFRelease(ext);
  fclose(sink.out);
  if (!vcn_teardown_drain(5000))
    fprintf(stderr, "a stuck session is still closing; leaving it\n");
  return sink.errors || refused || !sink.images ? 1 : 0;
}
