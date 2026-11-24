// VC-1 codec block of a VCN decode message: Mesa's rvcn_dec_message_vc1_t
// (src/amd/common/ac_vcn_dec.h), 36 bytes.
#pragma once
#include <stdint.h>

// Mesa's RDECODE_VC1_PROFILE_*.
enum { VCN_VC1_SIMPLE = 0, VCN_VC1_MAIN = 1, VCN_VC1_ADVANCED = 2 };

typedef struct {
  uint32_t profile;            // +0
  uint32_t level;              // +4
  uint32_t sps_info_flags;     // +8
  uint32_t pps_info_flags;     // +12
  uint32_t pic_structure;      // +16
  uint32_t chroma_format;      // +20
  uint16_t decoded_pic_idx;    // +24
  uint16_t deblocked_pic_idx;  // +26
  uint16_t forward_ref_idx;    // +28
  uint16_t backward_ref_idx;   // +30
  uint32_t cached_frame_flag;  // +32
} VcnVc1Msg;

_Static_assert(sizeof(VcnVc1Msg) == 36, "VC-1 codec block is 36 bytes");
