// MPEG-2 video on the AMD VCN: the stream parser, the reference bookkeeping
// and the codec block, on top of common/vcnlegacy.c.
#pragma once
#include <stdint.h>

#include "mpeg2msg.h"
#include "mpeg2parse.h"
#include "vcnlegacy.h"

extern const VcnLegacyCodec vcnmpeg2_codec;

// How the three picture indices of the codec block are filled.
//   0  as Mesa's radeon_vcn_dec.c did up to 25.x: the picture's number in
//      decoding order, and the numbers of its reference pictures. Not run on
//      this card;
//   1  all zero, as Mesa's ac_vcn_dec.c does since: the firmware keeps track
//      of the reference pictures itself. The default: 36 pictures of I, P
//      and B came out within 3 of FFmpeg's software decode (61 dB and up) on
//      the RX 6800 XT (2026-11-23).
extern int vcnmpeg2_index_mode;
// The order of the quantiser matrices in the codec block.
//   0  as the stream sends them, in zigzag order whatever the picture's scan
//      is. The default. With zigzag pictures it is the same as 2, which the
//      GPU decodes within 3 of FFmpeg (61-65 dB over 36 I/P/B pictures, also
//      with custom matrices). Not yet run on alternate scan pictures;
//   1  the picture's scan of the transposed matrix, what Mesa's VA-API path
//      ends up sending: 54 dB with the default matrices, 23 dB with custom
//      ones. Kept only to compare;
//   2  the picture's own scan order (alternate scan pictures get the matrix
//      in alternate scan order), what Mesa's VDPAU path sends. On a clip of
//      alternate scan pictures every frame was off by up to 20 (41-44 dB);
//   3  as 1, but in zigzag order on alternate scan pictures too.
extern int vcnmpeg2_matrix_mode;

// The codec block for one picture. frameNumber is the picture's number in
// decoding order, starting at 1; refs are the numbers of the forward and
// backward reference frames (0 = none).
void vcnmpeg2_fill_block(VcnMpeg2Msg* m, const Mpeg2Parser* p,
                         const Mpeg2Picture* pic, uint32_t frameNumber,
                         uint32_t forwardRef, uint32_t backwardRef);
