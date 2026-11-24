// VC-1 codec block of a VCN decode message.
//
// Mesa's rvcn_dec_message_vc1_t (src/amd/common/ac_vcn_dec.h:717-729) and the
// flag packing of build_vc1_msg (ac_vcn_dec.c:1771-1810). 36 bytes.
#pragma once
#include <stdint.h>

#include "vc1parse.h"

#define VCN_CODEC_VC1 0x1u
#define VCN_MESSAGE_VC1 0x7u

typedef struct {
  uint32_t profile;          // +0
  uint32_t level;            // +4
  uint32_t sps_info_flags;   // +8
  uint32_t pps_info_flags;   // +12
  uint32_t pic_structure;    // +16
  uint32_t chroma_format;    // +20
  uint16_t decoded_pic_idx;  // +24
  uint16_t deblocked_pic_idx;// +26
  uint16_t forward_ref_idx;  // +28
  uint16_t backward_ref_idx; // +30
  uint32_t cached_frame_flag;// +32
} VcnVc1Msg;

_Static_assert(sizeof(VcnVc1Msg) == 36, "VC-1 codec block is 36 bytes");

static inline void vcn_vc1_fill(VcnVc1Msg* m, const Vc1Picture* p) {
  for (unsigned i = 0; i < sizeof(*m); i++) ((uint8_t*)m)[i] = 0;
  // Same bit positions as Mesa's build_vc1_msg.
  m->sps_info_flags |= (uint32_t)p->postprocflag << 7;
  m->sps_info_flags |= (uint32_t)p->pulldown << 6;
  m->sps_info_flags |= (uint32_t)p->interlace << 5;
  m->sps_info_flags |= (uint32_t)p->tfcntrflag << 4;
  m->sps_info_flags |= (uint32_t)p->finterpflag << 3;
  m->sps_info_flags |= (uint32_t)p->psf << 1;
  m->pps_info_flags |= (uint32_t)p->panscan << 7;
  m->pps_info_flags |= (uint32_t)p->refdist_flag << 6;
  m->pps_info_flags |= (uint32_t)p->loopfilter << 5;
  m->pps_info_flags |= (uint32_t)p->fastuvmc << 4;
  m->pps_info_flags |= (uint32_t)p->extended_mv << 3;
  m->pps_info_flags |= (uint32_t)p->dquant << 1;
  m->pps_info_flags |= (uint32_t)p->vstransform << 0;
  m->pps_info_flags |= (uint32_t)p->extended_dmv << 8;
  m->pps_info_flags |= (uint32_t)p->overlap << 11;
  // Mesa's bit 21 is multires, which the advanced profile does not code (it
  // is a simple/main field), so it stays 0.
  m->profile = p->profile;
  m->level = p->level;
  m->chroma_format = 1;  // 4:2:0
  m->pic_structure = p->pic_structure;
  m->decoded_pic_idx = 0;
  m->deblocked_pic_idx = 0;
  m->forward_ref_idx = 0x7f;   // no reference
  m->backward_ref_idx = 0x7f;  // no reference
}
