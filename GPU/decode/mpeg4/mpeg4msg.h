// MPEG-4 part 2 codec block of a VCN decode message: Mesa's
// rvcn_dec_message_mpeg4_asp_vld_t (src/amd/common/ac_vcn_dec.h), 216 bytes.
#pragma once
#include <stdint.h>

// Bits of the feature word, in Mesa's bit-field order (first field = bit 0).
enum {
  VCN_MPEG4_SHORT_VIDEO_HEADER = 1u << 0,
  VCN_MPEG4_OBMC_DISABLE = 1u << 1,
  VCN_MPEG4_INTERLACED = 1u << 2,
  VCN_MPEG4_LOAD_INTRA_QUANT_MAT = 1u << 3,
  VCN_MPEG4_LOAD_NONINTRA_QUANT_MAT = 1u << 4,
  VCN_MPEG4_QUARTER_SAMPLE = 1u << 5,
  VCN_MPEG4_COMPLEXITY_ESTIMATION_DISABLE = 1u << 6,
  VCN_MPEG4_RESYNC_MARKER_DISABLE = 1u << 7,
};

typedef struct {
  uint32_t decoded_pic_idx;                // +0
  uint32_t forward_ref_pic_idx;            // +4
  uint32_t backward_ref_pic_idx;           // +8
  uint32_t variant_type;                   // +12
  uint8_t profile_and_level_indication;    // +16
  uint8_t video_object_layer_verid;        // +17
  uint8_t video_object_layer_shape;        // +18
  uint8_t reserved_1;                      // +19
  uint16_t video_object_layer_width;       // +20
  uint16_t video_object_layer_height;      // +22
  uint16_t vop_time_increment_resolution;  // +24
  uint16_t reserved_2;                     // +26
  uint32_t feature_flags;                  // +28 (VCN_MPEG4_*)
  uint8_t quant_type;                      // +32
  uint8_t reserved_3[3];                   // +33
  uint8_t intra_quant_mat[64];             // +36
  uint8_t nonintra_quant_mat[64];          // +100
  uint8_t sprite_config[16];               // +164
  uint8_t divx_311_config[8];              // +180
  struct {
    uint8_t vop_data_present;              // +188
    uint8_t vop_coding_type;               // +189
    uint8_t vop_quant;                     // +190
    uint8_t vop_coded;                     // +191
    uint8_t vop_rounding_type;             // +192
    uint8_t intra_dc_vlc_thr;              // +193
    uint8_t top_field_first;               // +194
    uint8_t alternate_vertical_scan_flag;  // +195
    uint8_t vop_fcode_forward;             // +196
    uint8_t vop_fcode_backward;            // +197
    uint32_t TRB[2];                       // +200
    uint32_t TRD[2];                       // +208
  } vop;
} VcnMpeg4Msg;

_Static_assert(sizeof(VcnMpeg4Msg) == 216,
               "MPEG-4 ASP codec block is 216 bytes");
