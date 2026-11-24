// VC-1 (WVC1 advanced profile, WMV3 simple/main) on the AMD VCN, on top of
// common/vcnlegacy.c. The firmware reads each frame from its picture header on
// and keeps the reference pictures itself: the codec block only repeats the
// sequence and entry point headers.
#pragma once
#include "vc1msg.h"
#include "vc1parse.h"
#include "vcnlegacy.h"

extern const VcnLegacyCodec vcnvc1_codec;

void vcnvc1_fill_block(VcnVc1Msg* m, const Vc1Parser* p);
