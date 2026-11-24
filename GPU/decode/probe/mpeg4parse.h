// MPEG-4 part 2 (ASP): VOL + one I-VOP. Sprite/GMC, data partitioning,
// newpred, reduced-resolution VOPs and interlacing are refused, not guessed at.
#pragma once
#include <stddef.h>
#include <stdint.h>

#include "probe.h"

typedef struct {
  ProbeAu au;     // video object layer header .. end of the VOP (default)
  ProbeAu picAu;  // VOP header .. end of the VOP (VCNPROBE_PIC_AU=1)
  uint8_t profile_and_level_indication;
  uint8_t verid;
  uint8_t shape;  // 0 = rectangular
  uint8_t interlaced, obmc_disable, quant_type, quarter_sample;
  uint8_t short_video_header;
  uint8_t vop_coding_type;  // 0 = I
  uint8_t vop_quant;
  uint8_t vop_rounding_type;
  uint8_t intra_dc_vlc_thr;
  uint8_t top_field_first, alternate_vertical_scan_flag;
  uint16_t vop_time_increment_resolution;
  uint8_t quant_precision;
  uint8_t bits_per_pixel;
} Mpeg4Picture;

// 0 on success, -1 with err set. Only a rectangular I-VOP is accepted.
int mpeg4_parse(const uint8_t* data, size_t size, Mpeg4Picture* out, char* err,
                size_t errLen);
