// MPEG-2: sequence header + one I picture + its slices. The firmware parses
// the slices (VLD), so the access unit is passed through as it is.
#pragma once
#include <stddef.h>
#include <stdint.h>

#include "probe.h"

typedef struct {
  ProbeAu au;     // sequence header .. end of the picture (default bitstream)
  ProbeAu picAu;  // picture header .. end of the picture (VCNPROBE_PIC_AU=1)
  uint8_t profile_and_level_indication;  // sequence header byte 0
  uint8_t picture_coding_type;           // 1 = I
  uint8_t f_code[2][2];
  uint8_t intra_dc_precision;
  uint8_t picture_structure;  // 3 = frame
  uint8_t top_field_first;
  uint8_t frame_pred_frame_dct;
  uint8_t concealment_motion_vectors;
  uint8_t q_scale_type;
  uint8_t intra_vlc_format;
  uint8_t alternate_scan;
  // Quantiser matrices from the sequence header, in transmission (zigzag)
  // order, the order Mesa puts in the codec block.
  uint8_t has_intra_matrix, has_nonintra_matrix;
  uint8_t intra_matrix[64], nonintra_matrix[64];
} Mpeg2Picture;

// 0 on success, -1 with err set. Only an I picture is accepted.
int mpeg2_parse(const uint8_t* data, size_t size, Mpeg2Picture* out, char* err,
                size_t errLen);
