// VP9 half of the probe's control mode.
//
// The VP9 decode message is not invented here: the three functions behind this
// header are GPU/decode/vp9/vcnvp9.c's fill_vp9_message(), fill_segments() and
// hook_init_ctx() (the probability table), moved into the probe so the control
// runs through the probe's own session and output path with exactly the
// message vcnvp9.c builds. Every assignment and constant below is from those
// functions; vcnvp9.c is not modified.
#pragma once
#include <stdint.h>

#include "vp9msg.h"
#include "vp9parse.h"

// The default probability table (vcnvp9.c hook_init_ctx), written into the
// context buffer the driver allocated. ctxSize is DATA_CTX_SIZE.
void vp9probe_init_ctx(void* ctx, uint32_t ctxSize);

// Fills a VcnMsgVP9 for the frame the parser just read. curr_pic_idx is the
// DPB slot the frame will be decoded into (0 in the one-frame probe).
void vp9probe_fill_message(VcnMsgVP9* m, const VP9Parser* p,
                           uint32_t curr_pic_idx);

// The per-frame segment table: vcnvp9.c fill_segments(), at
// DATA_IT + VCN_VP9_PROBS_DATA_SIZE.
void vp9probe_fill_segments(void* it, const VP9Parser* p);
