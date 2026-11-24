// MPEG-4 part 2 ASP VLD codec block of a VCN decode message.
//
// Mesa's rvcn_dec_message_mpeg4_asp_vld_t (src/amd/common/ac_vcn_dec.h:760-849,
// 216 bytes). NOTE: no Mesa builder fills it (ac_vcn_dec.c has build_mpeg2_msg
// and build_vc1_msg only) and VADriver2 has no MPEG-4 processor, so this layout
// is the only public definition and is unproven on VCN 3.0 firmware. The probe
// exists to find out.
#pragma once
#include <stdint.h>

#include "mpeg4parse.h"

#define VCN_CODEC_MPEG4 0x4u
#define VCN_MESSAGE_MPEG4_ASP_VLD 0xBu

// Bits of the feature word, in Mesa's order (first field = bit 0).
#define VCN_MPEG4_F_SHORT_VIDEO_HEADER 0
#define VCN_MPEG4_F_OBMC_DISABLE 1
#define VCN_MPEG4_F_INTERLACED 2
#define VCN_MPEG4_F_LOAD_INTRA_QUANT_MAT 3
#define VCN_MPEG4_F_LOAD_NONINTRA_QUANT_MAT 4
#define VCN_MPEG4_F_QUARTER_SAMPLE 5
#define VCN_MPEG4_F_COMPLEXITY_ESTIMATION_DISABLE 6
#define VCN_MPEG4_F_RESYNC_MARKER_DISABLE 7
#define VCN_MPEG4_F_DATA_PARTITIONED 8
#define VCN_MPEG4_F_REVERSIBLE_VLC 9
#define VCN_MPEG4_F_NEWPRED_ENABLE 10
#define VCN_MPEG4_F_REDUCED_RESOLUTION_VOP_ENABLE 11
#define VCN_MPEG4_F_SCALABILITY 12
#define VCN_MPEG4_F_IS_OBJECT_LAYER_IDENTIFIER 13
#define VCN_MPEG4_F_FIXED_VOP_RATE 14
#define VCN_MPEG4_F_NEWPRED_SEGMENT_TYPE 15

typedef struct {
  uint32_t decoded_pic_idx;      // +0
  uint32_t forward_ref_pic_idx;  // +4
  uint32_t backward_ref_pic_idx; // +8
  uint32_t variant_type;         // +12
  uint8_t profile_and_level_indication;  // +16
  uint8_t video_object_layer_verid;      // +17
  uint8_t video_object_layer_shape;      // +18
  uint8_t reserved_1;                    // +19
  uint16_t video_object_layer_width;     // +20
  uint16_t video_object_layer_height;    // +22
  uint16_t vop_time_increment_resolution;// +24
  uint16_t reserved_2;                   // +26
  uint32_t feature_flags;                // +28 (VCN_MPEG4_F_*)
  uint8_t quant_type;                    // +32
  uint8_t reserved_3[3];                 // +33
  uint8_t intra_quant_mat[64];           // +36
  uint8_t nonintra_quant_mat[64];        // +100
  struct {
    uint8_t sprite_enable;      // +164
    uint8_t reserved_4[3];      // +165
    uint16_t sprite_width;      // +168
    uint16_t sprite_height;     // +170
    int16_t sprite_left_coordinate;  // +172
    int16_t sprite_top_coordinate;   // +174
    uint8_t no_of_sprite_warping_points;  // +176
    uint8_t sprite_warping_accuracy;      // +177
    uint8_t sprite_brightness_change;     // +178
    uint8_t low_latency_sprite_enable;    // +179
  } sprite_config;
  struct {
    uint32_t bits;        // +180
    uint8_t vol_mode;     // +184
    uint8_t reserved_5[3];// +185
  } divx_311_config;
  struct {
    uint8_t vop_data_present;             // +188
    uint8_t vop_coding_type;              // +189
    uint8_t vop_quant;                    // +190
    uint8_t vop_coded;                    // +191
    uint8_t vop_rounding_type;            // +192
    uint8_t intra_dc_vlc_thr;             // +193
    uint8_t top_field_first;              // +194
    uint8_t alternate_vertical_scan_flag; // +195
    uint8_t vop_fcode_forward;            // +196
    uint8_t vop_fcode_backward;           // +197
    uint32_t TRB[2];                      // +200 (2 bytes of alignment
                                          //  padding after vop_fcode_backward)
    uint32_t TRD[2];                      // +208
  } vop;
} VcnMpeg4Msg;

_Static_assert(sizeof(VcnMpeg4Msg) == 216,
               "MPEG-4 ASP codec block is 216 bytes");

static inline void vcn_mpeg4_fill(VcnMpeg4Msg* m, const Mpeg4Picture* p) {
  for (unsigned i = 0; i < sizeof(*m); i++) ((uint8_t*)m)[i] = 0;
  m->decoded_pic_idx = 0;
  m->forward_ref_pic_idx = 0x7f;
  m->backward_ref_pic_idx = 0x7f;
  m->profile_and_level_indication = p->profile_and_level_indication;
  m->video_object_layer_verid = p->verid;
  m->video_object_layer_shape = p->shape;
  m->video_object_layer_width = (uint16_t)p->au.width;
  m->video_object_layer_height = (uint16_t)p->au.height;
  m->vop_time_increment_resolution = p->vop_time_increment_resolution;
  if (p->short_video_header)
    m->feature_flags |= 1u << VCN_MPEG4_F_SHORT_VIDEO_HEADER;
  if (p->obmc_disable) m->feature_flags |= 1u << VCN_MPEG4_F_OBMC_DISABLE;
  if (p->interlaced) m->feature_flags |= 1u << VCN_MPEG4_F_INTERLACED;
  if (p->quarter_sample)
    m->feature_flags |= 1u << VCN_MPEG4_F_QUARTER_SAMPLE;
  m->feature_flags |= 1u << VCN_MPEG4_F_COMPLEXITY_ESTIMATION_DISABLE;
  m->quant_type = p->quant_type;
  m->vop.vop_data_present = 1;
  m->vop.vop_coding_type = p->vop_coding_type;
  m->vop.vop_quant = p->vop_quant;
  m->vop.vop_coded = 1;
  m->vop.vop_rounding_type = p->vop_rounding_type;
  m->vop.intra_dc_vlc_thr = p->intra_dc_vlc_thr;
  m->vop.top_field_first = p->top_field_first;
  m->vop.alternate_vertical_scan_flag = p->alternate_vertical_scan_flag;
}
