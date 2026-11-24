// VC-1 advanced profile: sequence header (0x0F), entry point (0x0E) and the
// first progressive I picture (0x0D). Simple/main profile is not parsed.
#pragma once
#include <stddef.h>
#include <stdint.h>

#include "probe.h"

typedef struct {
  ProbeAu au;     // sequence header (0x0F) .. end of the picture (default)
  ProbeAu picAu;  // frame header (0x0D) .. end of the picture (VCNPROBE_PIC_AU=1)
  uint8_t profile;  // 3 = advanced
  uint8_t level;
  uint8_t chroma_format;  // 1 = 4:2:0
  // Sequence header flags, packed into sps_info_flags the way Mesa does.
  uint8_t postprocflag, pulldown, interlace, tfcntrflag, finterpflag, psf;
  // Entry point flags, packed into pps_info_flags.
  uint8_t panscan, refdist_flag, loopfilter, fastuvmc, extended_mv,
      extended_dmv, dquant, vstransform, overlap, range_mapy, range_mapuv;
  uint8_t pic_structure;  // 3 = frame
} Vc1Picture;

// 0 on success, -1 with err set. Only an advanced-profile progressive frame I
// picture is accepted; field pictures and range mapping are refused.
int vc1_parse(const uint8_t* data, size_t size, Vc1Picture* out, char* err,
              size_t errLen);
