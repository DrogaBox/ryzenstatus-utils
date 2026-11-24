// VP9 message building for the probe. See vp9fill.h: this is vcnvp9.c's code.
//
// The only change is the signature: vcnvp9.c reads the frame from its VP9Params
// block (ref_frame_map/frame_refs/curr_pic_idx), and the probe has no reference
// management, so the one intra frame fills the same fields with "no reference"
// (0x7f) itself.
#include "vp9fill.h"

#include <string.h>

#include "ac_vcn_vp9_default.h"

void vp9probe_init_ctx(void* ctx, uint32_t ctxSize) {
  if (!ctx || ctxSize < sizeof(VcnVP9Probs)) return;
  memset(ctx, 0, ctxSize);
  VcnVP9Probs* p = (VcnVP9Probs*)ctx;
  memcpy(p->coef_probs[0], default_coef_probs_4x4,
         sizeof(default_coef_probs_4x4));
  memcpy(p->coef_probs[1], default_coef_probs_8x8,
         sizeof(default_coef_probs_8x8));
  memcpy(p->coef_probs[2], default_coef_probs_16x16,
         sizeof(default_coef_probs_16x16));
  memcpy(p->coef_probs[3], default_coef_probs_32x32,
         sizeof(default_coef_probs_32x32));
  memcpy(p->y_mode_prob, default_if_y_probs, sizeof(default_if_y_probs));
  memcpy(p->uv_mode_prob, default_if_uv_probs, sizeof(default_if_uv_probs));
  memcpy(p->single_ref_prob, default_single_ref_p,
         sizeof(default_single_ref_p));
  memcpy(p->switchable_interp_prob, default_switchable_interp_prob,
         sizeof(default_switchable_interp_prob));
  memcpy(p->partition_prob, default_partition_probs,
         sizeof(default_partition_probs));
  memcpy(p->inter_mode_probs, default_inter_mode_probs,
         sizeof(default_inter_mode_probs));
  memcpy(p->mbskip_probs, default_skip_probs, sizeof(default_skip_probs));
  memcpy(p->intra_inter_prob, default_intra_inter_p,
         sizeof(default_intra_inter_p));
  memcpy(p->comp_inter_prob, default_comp_inter_p,
         sizeof(default_comp_inter_p));
  memcpy(p->comp_ref_prob, default_comp_ref_p, sizeof(default_comp_ref_p));
  memcpy(p->tx_probs_32x32, default_tx_probs_32x32,
         sizeof(default_tx_probs_32x32));
  memcpy(p->tx_probs_16x16, default_tx_probs_16x16,
         sizeof(default_tx_probs_16x16));
  memcpy(p->tx_probs_8x8, default_tx_probs_8x8, sizeof(default_tx_probs_8x8));
  memcpy(p->mv_joints, default_nmv_joints, sizeof(default_nmv_joints));
  memcpy(p->mv_comps, default_nmv_components, sizeof(default_nmv_components));
}

void vp9probe_fill_message(VcnMsgVP9* m, const VP9Parser* p,
                           uint32_t curr_pic_idx) {
  const VP9Frame* h = &p->fh;
  memset(m, 0, sizeof(*m));
  uint32_t fl = 0;
  if (h->frame_type) fl |= VP9_HDR_FRAME_TYPE;
  if (h->error_res) fl |= VP9_HDR_ERROR_RES;
  if (h->intra_only) fl |= VP9_HDR_INTRA_ONLY;
  if (h->allow_high_precision_mv) fl |= VP9_HDR_ALLOW_HP;
  if (h->refresh_frame_context) fl |= VP9_HDR_REFRESH_CTX;
  if (h->frame_parallel) fl |= VP9_HDR_PARALLEL;
  if (h->seg_enabled) fl |= VP9_HDR_SEG_ENABLED;
  if (h->seg_update_map) fl |= VP9_HDR_SEG_UPDATE_MAP;
  if (h->seg_temporal_update) fl |= VP9_HDR_SEG_TEMPORAL;
  if (h->seg_update_data) fl |= VP9_HDR_SEG_UPDATE_DATA;
  if (h->lf_delta_enabled) fl |= VP9_HDR_LF_DELTA_ENABLED;
  if (h->lf_delta_update) fl |= VP9_HDR_LF_DELTA_UPDATE;
  if (h->use_prev_frame_mvs) fl |= VP9_HDR_USE_PREV_MVS;
  fl |= VP9_HDR_USE_UNCOMPRESSED;
  m->frame_header_flags = fl;
  m->frame_context_idx = (uint8_t)h->frame_context_idx;
  m->reset_frame_context = (uint8_t)h->reset_frame_context;
  m->curr_pic_idx = (uint8_t)curr_pic_idx;
  m->interp_filter = (uint8_t)h->interp_filter;
  m->filter_level = (uint8_t)h->lf_level;
  m->sharpness_level = (uint8_t)h->lf_sharpness;
  vp9_lf_adj_levels(p, m->lf_adj_level);
  m->base_qindex = (uint8_t)h->base_q_idx;
  m->y_dc_delta_q = (int8_t)h->y_dc_delta_q;
  m->uv_ac_delta_q = (int8_t)h->uv_ac_delta_q;
  m->uv_dc_delta_q = (int8_t)h->uv_dc_delta_q;
  m->log2_tile_cols = (uint8_t)h->log2_tile_cols;
  m->log2_tile_rows = (uint8_t)h->log2_tile_rows;
  m->chroma_format = 1;
  m->bit_depth_luma_minus8 = m->bit_depth_chroma_minus8 =
      (uint8_t)(h->bit_depth - 8);
  if (h->bit_depth > 8) m->p010_mode = m->msb_mode = 1;
  m->compressed_header_size = h->compressed_header_size;
  m->uncompressed_header_size = h->uncompressed_header_size;
  for (int i = 0; i < 8; i++) m->ref_frame_map[i] = 0x7f;
  for (int i = 0; i < 3; i++) {
    m->frame_refs[i] = 0x7f;
    m->ref_frame_sign_bias[i] = (uint8_t)h->sign_bias[i];
  }
}

void vp9probe_fill_segments(void* it, const VP9Parser* p) {
  memset(it, 0, VCN_VP9_PROBS_DATA_SIZE + 256);
  if (!p->fh.seg_enabled) return;
  VcnVP9Seg* s = (VcnVP9Seg*)((uint8_t*)it + VCN_VP9_PROBS_DATA_SIZE);
  for (int i = 0; i < 8; i++) {
    const int16_t* f = p->seg_feature_data[i];
    s->feature_data[i] =
        ((uint32_t)f[0] & 0xffff) | (((uint32_t)f[1] & 0xff) << 16) |
        (((uint32_t)f[2] & 0xf) << 24) | (((uint32_t)f[3] & 0xf) << 28);
    s->feature_mask[i] = p->seg_feature_mask[i];
  }
  memcpy(s->tree_probs, p->seg_tree_probs, 7);
  memcpy(s->pred_probs, p->seg_pred_probs, 3);
  s->abs_delta = (uint8_t)p->seg_abs_delta;
}
