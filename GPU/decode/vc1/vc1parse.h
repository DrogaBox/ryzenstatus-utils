// VC-1 (SMPTE 421M): the sequence and entry point headers a VCN decode message
// needs, and where each frame is. The firmware reads the frame itself, from
// its picture header on, so only the frame's type is looked at here.
//
// Advanced profile streams carry start codes (00 00 01 0F sequence header, 0E
// entry point, 0D frame, 0C field, 0B slice). Simple and main profile streams
// (WMV3) carry none: the sequence header is four bytes kept by the container,
// and each sample is one frame.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum { VC1_PROFILE_SIMPLE = 0, VC1_PROFILE_MAIN = 1, VC1_PROFILE_ADVANCED = 3 };
enum { VC1_P = 0, VC1_B = 1, VC1_I = 2, VC1_BI = 3, VC1_SKIPPED = 4 };
enum { VC1_PROGRESSIVE = 0, VC1_FRAME_INTERLACE = 1, VC1_FIELD_INTERLACE = 2 };

typedef struct {
  const uint8_t* data;  // advanced: from the frame start code when the chunk
  size_t size;          // has one; simple/main: the whole frame
  bool needStartCode;   // advanced frame that came without its 00 00 01 0D
  // Field-interlaced frame: offset in data of the second field's start code
  // (00 00 01 0C), or 0.
  size_t secondField;
  uint8_t fcm;   // VC1_PROGRESSIVE/FRAME_INTERLACE/FIELD_INTERLACE
  uint8_t type;  // VC1_*; of a field-interlaced frame: its first field
  // Field-interlaced: whether the second field is intra coded too (the frame
  // then predicts from no other frame when the first is I).
  uint8_t secondFieldType;
} Vc1Picture;

typedef struct {
  bool have_sequence;
  bool have_entry;  // advanced: an entry point header was read
  uint8_t profile;  // VC1_PROFILE_*
  uint8_t level;
  uint32_t max_width, max_height;  // sequence header (advanced)
  uint32_t width, height;          // coded size in effect
  // Sequence header.
  uint8_t postprocflag, pulldown, interlace, tfcntrflag, finterpflag, psf;
  uint8_t hrd_param_flag, hrd_buckets;
  uint8_t multires, syncmarker, rangered, maxbframes;  // simple/main
  // Entry point (advanced) or sequence header (simple/main).
  uint8_t panscan_flag, refdist_flag, loopfilter, fastuvmc, extended_mv,
      extended_dmv, dquant, vstransform, overlap, quantizer;
  uint8_t range_mapy_flag, range_mapy, range_mapuv_flag, range_mapuv;
  bool stop;  // set by the callback to end the parse after it returns
  bool missing_sequence;  // the last error: a frame before its headers
  char err[128];
} Vc1Parser;

typedef int (*Vc1PictureFn)(void* ctx, Vc1Parser* p, const Vc1Picture* pic);

void vc1_parser_init(Vc1Parser* p);
// Advanced profile: a chunk that holds whole frames, with or without the
// headers in front. A chunk with no start code at all is one frame whose
// 00 00 01 0D the container dropped. 0, the callback's value, or -1 with
// p->err set.
int vc1_parse_chunk(Vc1Parser* p, const uint8_t* data, size_t size,
                    Vc1PictureFn fn, void* ctx);
// Simple/main profile: the sequence header bytes (STRUCT_C, at least four) and
// the size the container gives. 0 or -1 with p->err set.
int vc1_parse_struct_c(Vc1Parser* p, const uint8_t* hdr, size_t size,
                       uint32_t width, uint32_t height);
// Simple/main profile: one frame.
int vc1_parse_frame(Vc1Parser* p, const uint8_t* data, size_t size,
                    Vc1PictureFn fn, void* ctx);
