// MPEG-4 part 2 (simple and advanced simple profile): the video object layer
// header a VCN decode message needs, and where each VOP is. The firmware
// reads the VOP itself; its header is parsed here only for the picture type
// and the times.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum { MPEG4_I = 0, MPEG4_P = 1, MPEG4_B = 2, MPEG4_S = 3 };

typedef struct {
  // From the first start code of the access unit (the headers in front of
  // the VOP, if any) to the end of the VOP.
  const uint8_t* data;
  size_t size;
  size_t vopOffset;     // of the VOP start code in data
  uint8_t coding_type;  // MPEG4_*
  uint8_t vop_coded;
  uint8_t rounding_type;
  uint8_t intra_dc_vlc_thr;
  uint8_t top_field_first, alternate_vertical_scan;
  uint8_t quant;
  uint8_t fcode_forward, fcode_backward;
  // Time distances in ticks of vop_time_increment_resolution: between the two
  // reference VOPs around a B-VOP (trd) and from the earlier one to the B-VOP
  // (trb). 0 for I and P.
  uint32_t trd, trb;
} Mpeg4Picture;

typedef struct {
  bool have_vol;
  uint32_t width, height;
  uint8_t profile_and_level;  // visual object sequence header, or 0
  uint8_t object_type;        // video_object_type_indication
  bool no_b_vops;             // the VOL rules B-VOPs out
  uint8_t verid;
  uint8_t interlaced, obmc_disable, quant_type, quarter_sample;
  uint8_t resync_marker_disable;
  uint8_t quant_precision;
  uint16_t time_increment_resolution;
  uint8_t time_increment_bits;
  // Quantiser matrices in the order the stream sends them (zigzag scan), the
  // defaults when the stream sends none.
  uint8_t intra_matrix[64], nonintra_matrix[64];
  // VOP times, as FFmpeg's decode_vop_header keeps them.
  int64_t time_base, last_time_base, last_ref_time;
  uint32_t ref_distance;
  bool stop;
  bool missing_vol;  // the last error: a VOP before any VOL
  char err[128];
} Mpeg4Parser;

typedef int (*Mpeg4PictureFn)(void* ctx, Mpeg4Parser* p,
                              const Mpeg4Picture* pic);

void mpeg4_parser_init(Mpeg4Parser* p);
// A chunk that holds whole VOPs (one sample, or a whole elementary stream), or
// only headers (the decoder configuration of an esds atom). 0, the callback's
// value, or -1 with p->err set for a stream this decoder does not take.
int mpeg4_parse_chunk(Mpeg4Parser* p, const uint8_t* data, size_t size,
                      Mpeg4PictureFn fn, void* ctx);
