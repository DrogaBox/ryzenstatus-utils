// MPEG-4 part 2 (simple and advanced simple profile) on the AMD VCN, on top of
// common/vcnlegacy.c. Mesa does not offer this codec on the VCN of a Radeon RX
// 6000, so the block follows what Mesa's radeon_vcn_dec.c sent to older video
// engines; the firmware of this card decodes it.
#pragma once
#include "mpeg4msg.h"
#include "mpeg4parse.h"
#include "vcnlegacy.h"

extern const VcnLegacyCodec vcnmpeg4_codec;

// The three picture indices: 0 = the picture's number in decoding order and
// its references' (Mesa's get_mpeg4_msg, the default), 1 = all zero. All zero
// with the VOP part filled (block mode 1) decodes I-VOPs, but the first B-VOP
// took the firmware over a second and its picture was never checked
// (2026-11-23).
extern int vcnmpeg4_index_mode;
// The rest of the block:
//   0  as Mesa's get_mpeg4_msg: the VOL fields, with the VOP part empty (the
//      firmware reads the VOP header from the bitstream);
//   1  with the VOP part filled from the VOP header, as the first intra
//      picture was decoded on this card.
//   2  as 0, plus the B-VOP's time distances TRB/TRD;
//   3  as 0, plus the whole VOP part (as mode 1 fills it).
// I- and P-VOPs decode with mode 0 (36 pictures, 59 dB and up). With every
// mode tried (0, 2, and 1 with zero indices) each B-VOP keeps the firmware
// busy about 2 s with no picture, and three in a row hung the video engine
// (2026-11-23). So B-VOPs are refused: a configuration whose VOL does not rule
// them out fails create(), and a B-VOP fails decode (VCNMPEG4_ALLOW_B=1 lets
// both through, for experiments only). A B-VOP whose TRD is 0 is refused even
// then.
extern int vcnmpeg4_block_mode;
// The quantiser matrices always go in the order the stream sends them
// (zigzag), the order MPEG-2 needs on this card (a transposed order, as Mesa's
// VA-API path sends for MPEG-2, gave 23-27 dB there, 2026-11-23).
//
// What goes to the firmware as the bitstream of a VOP: 0 (the default) = the
// access unit from its first start code, with the headers in front of the VOP
// (visual object sequence, VOL, GOV) when there are any; 1 = from the VOP start
// code on. Only for experiments; a unit that is a VOP alone is the same in
// both.
extern int vcnmpeg4_cut_mode;

void vcnmpeg4_fill_block(VcnMpeg4Msg* m, const Mpeg4Parser* p,
                         const Mpeg4Picture* pic, uint32_t frameNumber,
                         uint32_t forwardRef, uint32_t backwardRef);
