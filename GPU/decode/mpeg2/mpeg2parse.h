// MPEG-2 video elementary stream: the headers a VCN decode message needs, and
// where each picture's slices are. The firmware reads the slices itself (VLD),
// so nothing below the slice start codes is parsed.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum { MPEG2_I = 1, MPEG2_P = 2, MPEG2_B = 3 };
enum { MPEG2_TOP_FIELD = 1, MPEG2_BOTTOM_FIELD = 2, MPEG2_FRAME = 3 };

typedef struct {
  uint16_t temporal_reference;
  uint8_t coding_type;  // MPEG2_I/P/B
  uint8_t f_code[2][2];
  uint8_t intra_dc_precision;
  uint8_t picture_structure;  // MPEG2_TOP_FIELD/BOTTOM_FIELD/FRAME
  uint8_t top_field_first;
  uint8_t frame_pred_frame_dct;
  uint8_t concealment_motion_vectors;
  uint8_t q_scale_type;
  uint8_t intra_vlc_format;
  uint8_t alternate_scan;
  uint8_t repeat_first_field;
  uint8_t progressive_frame;
  // From the first slice start code to the end of the picture.
  const uint8_t* slices;
  size_t slicesSize;
} Mpeg2Picture;

typedef struct {
  // Sequence header and extension.
  bool have_sequence;   // a sequence header was read
  bool have_extension;  // and its sequence extension: the stream is MPEG-2
  uint32_t width, height;
  uint8_t progressive_sequence;
  uint8_t chroma_format;  // 1 = 4:2:0
  uint8_t frame_rate_code;
  // Quantiser matrices in the order the stream sends them (zigzag scan),
  // the defaults when the stream sends none.
  uint8_t intra_matrix[64], nonintra_matrix[64];
  // The picture whose headers are being collected.
  bool have_picture, have_coding_ext;
  Mpeg2Picture pic;
  bool stop;  // set by the callback to end mpeg2_parse_chunk after it returns
  // The last error was a picture with no sequence header before it: a stream
  // joined in the middle, not a broken one.
  bool missing_sequence;
  char err[128];
} Mpeg2Parser;

// Called once for each complete picture, in stream order. A non-zero return
// ends the parse with that value.
typedef int (*Mpeg2PictureFn)(void* ctx, Mpeg2Parser* p,
                              const Mpeg2Picture* pic);

void mpeg2_parser_init(Mpeg2Parser* p);
// Parses a chunk that holds whole pictures (one access unit, or a whole
// elementary stream). Headers stay in effect across calls. 0, the callback's
// value, or -1 with p->err set for a stream this decoder does not take
// (MPEG-1, 4:2:2, a broken header).
int mpeg2_parse_chunk(Mpeg2Parser* p, const uint8_t* data, size_t size,
                      Mpeg2PictureFn fn, void* ctx);

// The two scans of ISO 13818-2 figure 7-2 and 7-3: scan[i] is the position in
// the 8x8 block (row * 8 + column) of the i-th coefficient.
extern const uint8_t mpeg2_zigzag_scan[64];
extern const uint8_t mpeg2_alternate_scan[64];
