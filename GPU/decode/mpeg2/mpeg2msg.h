// MPEG-2 VLD codec block of a VCN decode message: Mesa's
// rvcn_dec_message_mpeg2_vld_t (src/amd/common/ac_vcn_dec.h), 160 bytes.
#pragma once
#include <stdint.h>

typedef struct {
  uint32_t decoded_pic_idx;                  // +0
  uint32_t forward_ref_pic_idx;              // +4
  uint32_t backward_ref_pic_idx;             // +8
  uint8_t load_intra_quantiser_matrix;       // +12
  uint8_t load_nonintra_quantiser_matrix;    // +13
  uint8_t reserved_quantiser_alignement[2];  // +14
  uint8_t intra_quantiser_matrix[64];        // +16
  uint8_t nonintra_quantiser_matrix[64];     // +80
  uint8_t profile_and_level_indication;      // +144
  uint8_t chroma_format;                     // +145
  uint8_t picture_coding_type;               // +146
  uint8_t reserved_1;                        // +147
  uint8_t f_code[2][2];                      // +148
  uint8_t intra_dc_precision;                // +152
  uint8_t pic_structure;                     // +153
  uint8_t top_field_first;                   // +154
  uint8_t frame_pred_frame_dct;              // +155
  uint8_t concealment_motion_vectors;        // +156
  uint8_t q_scale_type;                      // +157
  uint8_t intra_vlc_format;                  // +158
  uint8_t alternate_scan;                    // +159
} VcnMpeg2Msg;

_Static_assert(sizeof(VcnMpeg2Msg) == 160,
               "MPEG-2 VLD codec block is 160 bytes");
