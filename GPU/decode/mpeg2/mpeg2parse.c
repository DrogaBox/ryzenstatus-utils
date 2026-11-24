#include "mpeg2parse.h"

#include <stdio.h>
#include <string.h>

#include "bitreader.h"

const uint8_t mpeg2_zigzag_scan[64] = {
    0,  1,  8,  16, 9,  2,  3,  10, 17, 24, 32, 25, 18, 11, 4,  5,
    12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6,  7,  14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63};

const uint8_t mpeg2_alternate_scan[64] = {
    0,  8,  16, 24, 1, 9,  2,  10, 17, 25, 32, 40, 48, 56, 57, 49,
    41, 33, 26, 18, 3, 11, 4,  12, 19, 27, 34, 42, 50, 58, 35, 43,
    51, 59, 20, 28, 5, 13, 6,  14, 21, 29, 36, 44, 52, 60, 37, 45,
    53, 61, 22, 30, 7, 15, 23, 31, 38, 46, 54, 62, 39, 47, 55, 63};

// Default intra matrix of ISO 13818-2 6.3.11, by rows.
static const uint8_t kDefaultIntra[64] = {
    8,  16, 19, 22, 26, 27, 29, 34, 16, 16, 22, 24, 27, 29, 34, 37,
    19, 22, 26, 27, 29, 34, 34, 38, 22, 22, 26, 27, 29, 34, 37, 40,
    22, 26, 27, 29, 32, 35, 40, 48, 26, 27, 29, 32, 35, 40, 48, 58,
    26, 27, 29, 34, 38, 46, 56, 69, 27, 29, 35, 38, 46, 56, 69, 83};

void mpeg2_parser_init(Mpeg2Parser* p) { memset(p, 0, sizeof(*p)); }

static int fail(Mpeg2Parser* p, const char* what) {
  snprintf(p->err, sizeof(p->err), "%s", what);
  return -1;
}

static void read_matrix(BitReader* b, uint8_t* m) {
  for (int i = 0; i < 64; i++) m[i] = (uint8_t)br_get(b, 8);
}

static int sequence_header(Mpeg2Parser* p, const uint8_t* d, size_t n) {
  BitReader b;
  br_init(&b, d, n);
  uint32_t w = br_get(&b, 12), h = br_get(&b, 12);
  br_get(&b, 4);  // aspect_ratio_information
  uint32_t rate = br_get(&b, 4);
  br_get(&b, 18);  // bit_rate_value
  br_get(&b, 1);   // marker
  br_get(&b, 10);  // vbv_buffer_size_value
  br_get(&b, 1);   // constrained_parameters_flag
  uint8_t intra[64], nonintra[64];
  for (int i = 0; i < 64; i++) {
    intra[i] = kDefaultIntra[mpeg2_zigzag_scan[i]];
    nonintra[i] = 16;
  }
  if (br_get(&b, 1)) read_matrix(&b, intra);
  if (br_get(&b, 1)) read_matrix(&b, nonintra);
  if (b.err || !w || !h) return fail(p, "MPEG-2 sequence header too short");
  // A zero in a matrix is forbidden and would divide by zero in a decoder.
  for (int i = 0; i < 64; i++)
    if (!intra[i] || !nonintra[i])
      return fail(p, "MPEG-2 quantiser matrix with a zero");
  p->have_sequence = true;
  p->have_extension = false;  // the extension that follows says MPEG-2
  p->width = w;
  p->height = h;
  p->frame_rate_code = (uint8_t)rate;
  p->progressive_sequence = 1;
  p->chroma_format = 1;
  memcpy(p->intra_matrix, intra, 64);
  memcpy(p->nonintra_matrix, nonintra, 64);
  return 0;
}

static int extension(Mpeg2Parser* p, const uint8_t* d, size_t n) {
  BitReader b;
  br_init(&b, d, n);
  uint32_t id = br_get(&b, 4);
  if (b.err) return fail(p, "MPEG-2 extension too short");
  if (id == 1) {  // sequence extension
    if (!p->have_sequence) return 0;
    br_get(&b, 8);  // profile_and_level_indication
    uint32_t prog = br_get(&b, 1), chroma = br_get(&b, 2);
    uint32_t wext = br_get(&b, 2), hext = br_get(&b, 2);
    if (b.err) return fail(p, "MPEG-2 sequence extension too short");
    p->progressive_sequence = (uint8_t)prog;
    p->chroma_format = (uint8_t)chroma;
    p->width = (p->width & 0xfff) | (wext << 12);
    p->height = (p->height & 0xfff) | (hext << 12);
    p->have_extension = true;
  } else if (id == 3) {  // quant matrix extension
    uint8_t intra[64], nonintra[64];
    memcpy(intra, p->intra_matrix, 64);
    memcpy(nonintra, p->nonintra_matrix, 64);
    if (br_get(&b, 1)) read_matrix(&b, intra);
    if (br_get(&b, 1)) read_matrix(&b, nonintra);
    // The chroma matrices that may follow are for 4:2:2 and 4:4:4 only.
    if (b.err) return fail(p, "MPEG-2 quant matrix extension too short");
    for (int i = 0; i < 64; i++)
      if (!intra[i] || !nonintra[i])
        return fail(p, "MPEG-2 quantiser matrix with a zero");
    memcpy(p->intra_matrix, intra, 64);
    memcpy(p->nonintra_matrix, nonintra, 64);
  } else if (id == 8) {  // picture coding extension
    if (!p->have_picture) return 0;
    Mpeg2Picture* pic = &p->pic;
    for (int s = 0; s < 2; s++)
      for (int t = 0; t < 2; t++) pic->f_code[s][t] = (uint8_t)br_get(&b, 4);
    pic->intra_dc_precision = (uint8_t)br_get(&b, 2);
    pic->picture_structure = (uint8_t)br_get(&b, 2);
    pic->top_field_first = (uint8_t)br_get(&b, 1);
    pic->frame_pred_frame_dct = (uint8_t)br_get(&b, 1);
    pic->concealment_motion_vectors = (uint8_t)br_get(&b, 1);
    pic->q_scale_type = (uint8_t)br_get(&b, 1);
    pic->intra_vlc_format = (uint8_t)br_get(&b, 1);
    pic->alternate_scan = (uint8_t)br_get(&b, 1);
    pic->repeat_first_field = (uint8_t)br_get(&b, 1);
    br_get(&b, 1);  // chroma_420_type
    pic->progressive_frame = (uint8_t)br_get(&b, 1);
    if (b.err) return fail(p, "MPEG-2 picture coding extension too short");
    if (pic->picture_structure == 0)
      return fail(p, "MPEG-2 picture structure 0");
    // 15 means "not used"; 0 and 10..14 are reserved.
    for (int s = 0; s < 2; s++)
      for (int t = 0; t < 2; t++)
        if (pic->f_code[s][t] == 0 ||
            (pic->f_code[s][t] > 9 && pic->f_code[s][t] != 15))
          return fail(p, "MPEG-2 f_code out of range");
    p->have_coding_ext = true;
  }
  return 0;
}

static int picture_header(Mpeg2Parser* p, const uint8_t* d, size_t n) {
  BitReader b;
  br_init(&b, d, n);
  memset(&p->pic, 0, sizeof(p->pic));
  p->pic.temporal_reference = (uint16_t)br_get(&b, 10);
  p->pic.coding_type = (uint8_t)br_get(&b, 3);
  br_get(&b, 16);  // vbv_delay
  p->have_coding_ext = false;
  p->have_picture = false;
  if (b.err) return fail(p, "MPEG-2 picture header too short");
  if (p->pic.coding_type < MPEG2_I || p->pic.coding_type > MPEG2_B)
    return fail(p, "MPEG-2 picture coding type not I, P or B");
  p->have_picture = true;
  return 0;
}

static int emit(Mpeg2Parser* p, const uint8_t* slices, size_t size,
                Mpeg2PictureFn fn, void* ctx) {
  p->have_picture = false;
  if (!p->have_sequence) {
    p->missing_sequence = true;
    return fail(p, "MPEG-2 picture before any sequence header");
  }
  if (!p->have_extension || !p->have_coding_ext)
    return fail(p, "MPEG-1 video is not decoded by this path");
  if (p->chroma_format != 1)
    return fail(p, "MPEG-2 4:2:2 and 4:4:4 are not supported");
  p->pic.slices = slices;
  p->pic.slicesSize = size;
  return fn ? fn(ctx, p, &p->pic) : 0;
}

int mpeg2_parse_chunk(Mpeg2Parser* p, const uint8_t* data, size_t size,
                      Mpeg2PictureFn fn, void* ctx) {
  p->err[0] = 0;
  p->stop = false;
  p->missing_sequence = false;
  size_t slices = size;  // offset of the current picture's first slice
  size_t at = next_start_code(data, size, 0);
  while (at < size) {
    uint8_t code = data[at + 3];
    size_t next = next_start_code(data, size, at + 4);
    const uint8_t* body = data + at + 4;
    size_t bodySize = next - at - 4;
    bool isSlice = code >= 0x01 && code <= 0xAF;
    if (!isSlice && slices < size) {
      // The first start code after the slices ends the picture.
      int r = emit(p, data + slices, at - slices, fn, ctx);
      slices = size;
      if (r || p->stop) return r;
    }
    int r = 0;
    if (isSlice) {
      if (slices == size && p->have_picture) slices = at;
    } else if (code == 0x00) {
      r = picture_header(p, body, bodySize);
    } else if (code == 0xB3) {
      r = sequence_header(p, body, bodySize);
    } else if (code == 0xB5) {
      r = extension(p, body, bodySize);
    }
    if (r) return r;
    at = next;
  }
  if (slices < size) return emit(p, data + slices, size - slices, fn, ctx);
  return 0;
}
