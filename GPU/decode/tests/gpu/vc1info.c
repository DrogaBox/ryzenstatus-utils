// vc1info <stream.vc1> [frames [cut.vc1]]
//
// What a VC-1 advanced profile elementary stream holds, as the plug-in's parser
// reads it: size, interlace flag, and for each frame its coding mode
// (progressive, frame-interlaced, field-interlaced) and type. No driver, no
// GPU. Exit 0 when the first [frames] frames (all, without the argument)
// include a field-interlaced one, 3 when they do not, 1 on a parse error. With
// cut.vc1 it also writes the stream up to the end of frame [frames], headers
// included, so that FFmpeg and the GPU get the same short clip. A GPU round
// uses it to pick and cut its clips before anything goes to the GPU.
#include <stdio.h>
#include <stdlib.h>

#include "vc1parse.h"

typedef struct {
  int max, n, fcm[3], firstField;
  const uint8_t* base;
  size_t end;  // offset where the frame after the last one counted starts
  char list[160];
} Info;

static int on_frame(void* ctx, Vc1Parser* p, const Vc1Picture* pic) {
  (void)p;
  Info* in = ctx;
  if (in->max && in->n >= in->max) {
    // pic->data is at this frame's start code, or right after the place of
    // one the stream left out.
    in->end = (size_t)(pic->data - in->base);
    return 1;
  }
  in->fcm[pic->fcm]++;
  if (pic->fcm == VC1_FIELD_INTERLACE && in->firstField < 0)
    in->firstField = in->n;
  static const char kType[] = "PBIbS";  // P, B, I, BI, skipped
  if (in->n * 3 + 4 < (int)sizeof(in->list)) {
    char* at = in->list + in->n * 3;
    at[0] = pic->fcm == VC1_FIELD_INTERLACE   ? 'F'
            : pic->fcm == VC1_FRAME_INTERLACE ? 'f'
                                              : 'p';
    at[1] = kType[pic->type < 5 ? pic->type : 4];
    at[2] = pic->fcm == VC1_FIELD_INTERLACE
                ? kType[pic->secondFieldType < 5 ? pic->secondFieldType : 4]
                : ' ';
    at[3] = 0;
  }
  in->n++;
  return 0;
}

int main(int argc, char** argv) {
  if (argc < 2 || argc > 4) {
    fprintf(stderr, "usage: %s <stream.vc1> [frames [cut.vc1]]\n", argv[0]);
    return 2;
  }
  FILE* f = fopen(argv[1], "rb");
  if (!f) {
    fprintf(stderr, "cannot read %s\n", argv[1]);
    return 1;
  }
  uint8_t* data = NULL;
  long size = 0;
  if (!fseek(f, 0, SEEK_END) && (size = ftell(f)) > 0 &&
      !fseek(f, 0, SEEK_SET) && (data = malloc((size_t)size)) &&
      fread(data, 1, (size_t)size, f) != (size_t)size) {
    free(data);
    data = NULL;
  }
  fclose(f);
  if (!data) {
    fprintf(stderr, "cannot read %s\n", argv[1]);
    return 1;
  }
  Info in = {.max = argc >= 3 ? atoi(argv[2]) : 0,
             .firstField = -1,
             .base = data,
             .end = (size_t)size};
  Vc1Parser p;
  vc1_parser_init(&p);
  int r = vc1_parse_chunk(&p, data, (size_t)size, on_frame, &in);
  if (r < 0) {
    fprintf(stderr, "vc1info: %s\n", p.err);
    free(data);
    return 1;
  }
  if (argc == 4) {
    FILE* out = fopen(argv[3], "wb");
    if (!out || fwrite(data, 1, in.end, out) != in.end) {
      fprintf(stderr, "cannot write %s\n", argv[3]);
      if (out) fclose(out);
      free(data);
      return 1;
    }
    fclose(out);
    printf("vc1info: wrote %zu bytes (%d frames) to %s\n", in.end, in.n,
           argv[3]);
  }
  free(data);
  printf("vc1info: profile %u level %u %ux%u interlace %u, %d frames: "
         "progressive %d, frame-interlaced %d, field-interlaced %d "
         "(first: frame %d)\n",
         p.profile, p.level, p.width, p.height, p.interlace, in.n, in.fcm[0],
         in.fcm[1], in.fcm[2], in.firstField);
  // p/f/F: progressive, frame-, field-interlaced; then the type (b = BI, S =
  // skipped), and for a field-interlaced frame its second field's type.
  printf("vc1info: frames %s\n", in.list);
  return in.fcm[VC1_FIELD_INTERLACE] ? 0 : 3;
}
