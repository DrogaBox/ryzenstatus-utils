// MPEG-2 VLD codec block of a VCN decode message.
//
// Field order and sizes are Mesa's rvcn_dec_message_mpeg2_vld_t
// (src/amd/common/ac_vcn_dec.h:731-758), which is what
// build_mpeg2_msg (ac_vcn_dec.c:1745) fills and what the firmware parses for
// codec id 3. Same 160 bytes as Mesa's struct.
#pragma once
#include <stdint.h>

#include "mpeg2parse.h"

#define VCN_CODEC_MPEG2 0x3u
#define VCN_MESSAGE_MPEG2_VLD 0xAu

typedef struct {
  uint32_t decoded_pic_idx;      // +0
  uint32_t forward_ref_pic_idx;  // +4
  uint32_t backward_ref_pic_idx; // +8
  uint8_t load_intra_quantiser_matrix;     // +12
  uint8_t load_nonintra_quantiser_matrix;  // +13
  uint8_t reserved_quantiser_alignement[2];// +14
  uint8_t intra_quantiser_matrix[64];      // +16
  uint8_t nonintra_quantiser_matrix[64];   // +80
  uint8_t profile_and_level_indication;    // +144
  uint8_t chroma_format;                   // +145
  uint8_t picture_coding_type;             // +146
  uint8_t reserved_1;                      // +147
  uint8_t f_code[2][2];                    // +148
  uint8_t intra_dc_precision;              // +152
  uint8_t pic_structure;                   // +153
  uint8_t top_field_first;                 // +154
  uint8_t frame_pred_frame_dct;            // +155
  uint8_t concealment_motion_vectors;      // +156
  uint8_t q_scale_type;                    // +157
  uint8_t intra_vlc_format;                // +158
  uint8_t alternate_scan;                  // +159
} VcnMpeg2Msg;

_Static_assert(sizeof(VcnMpeg2Msg) == 160, "MPEG-2 VLD codec block is 160 bytes");

// Default intra matrix in the order Mesa 26.3 sent it on Linux (capture
// b31/msg-mpeg2.txt, codec block +0x10), copied byte for byte. The default non-intra
// matrix is all 16.
static const uint8_t kMpeg2DefaultIntraZigzag[64] = {
    8, 16, 16, 19, 16, 19, 22, 22, 22, 22, 26, 24, 26, 22, 22, 26,
    26, 26, 27, 27, 27, 29, 29, 29, 27, 27, 27, 26, 27, 27, 29, 29,
    29, 34, 34, 34, 37, 34, 34, 32, 32, 29, 29, 35, 34, 35, 35, 37,
    38, 40, 40, 40, 38, 38, 46, 46, 48, 48, 58, 56, 56, 69, 69, 83};

static inline void vcn_mpeg2_fill(VcnMpeg2Msg* m, const Mpeg2Picture* p);

// Variant 10: the block exactly as Mesa built it on Linux for an I picture.
static inline void vcn_mpeg2_mesa(VcnMpeg2Msg* m, const Mpeg2Picture* p) {
  vcn_mpeg2_fill(m, p);
  m->forward_ref_pic_idx = 0;
  m->backward_ref_pic_idx = 0;
  m->profile_and_level_indication = 0;
  m->load_intra_quantiser_matrix = 1;
  m->load_nonintra_quantiser_matrix = 1;
  for (int i = 0; i < 64; i++) {
    m->intra_quantiser_matrix[i] =
        p->has_intra_matrix ? p->intra_matrix[i] : kMpeg2DefaultIntraZigzag[i];
    m->nonintra_quantiser_matrix[i] =
        p->has_nonintra_matrix ? p->nonintra_matrix[i] : 16;
  }
}

static inline void vcn_mpeg2_fill(VcnMpeg2Msg* m, const Mpeg2Picture* p) {
  for (unsigned i = 0; i < sizeof(*m); i++) ((uint8_t*)m)[i] = 0;
  m->decoded_pic_idx = 0;
  m->forward_ref_pic_idx = 0x7f;   // no reference
  m->backward_ref_pic_idx = 0x7f;  // no reference
  m->profile_and_level_indication = p->profile_and_level_indication;
  m->chroma_format = 1;  // 4:2:0
  m->picture_coding_type = p->picture_coding_type;
  for (int f = 0; f < 2; f++)
    for (int v = 0; v < 2; v++) m->f_code[f][v] = p->f_code[f][v];
  m->intra_dc_precision = p->intra_dc_precision;
  m->pic_structure = p->picture_structure;
  m->top_field_first = p->top_field_first;
  m->frame_pred_frame_dct = p->frame_pred_frame_dct;
  m->concealment_motion_vectors = p->concealment_motion_vectors;
  m->q_scale_type = p->q_scale_type;
  m->intra_vlc_format = p->intra_vlc_format;
  m->alternate_scan = p->alternate_scan;
}
