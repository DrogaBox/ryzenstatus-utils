#include "mpeg2parse.h"

#include "bitreader.h"

// Sequence header: 12-bit width and height, aspect/rate/bitrate, then the
// quantiser matrices. Picture header: temporal reference, coding type.
// Picture coding extension (0xB5): its first 4 bits are
// extension_start_code_identifier, 8 for the picture coding extension; the
// f_code/intra_dc fields start after it.
int mpeg2_parse(const uint8_t* data, size_t size, Mpeg2Picture* out, char* err,
                size_t errLen) {
  memset(out, 0, sizeof(*out));
  size_t seq = find_start(data, size, 0, 0xB3);
  if (seq == (size_t)-1) {
    copy_err(err, errLen, "no MPEG-2 sequence header (00 00 01 B3)");
    return -1;
  }
  BitReader b;
  br_init(&b, data + seq + 4, size - seq - 4);
  out->au.width = br_get(&b, 12);
  out->au.height = br_get(&b, 12);
  // profile_and_level_indication lives in the sequence extension, not here:
  // the byte after the size is aspect ratio + frame rate code (the old code
  // sent it as P&L, 0x13 for this clip; Mesa sends 0).
  out->profile_and_level_indication = 0;
  br_get(&b, 4);   // aspect_ratio_information
  br_get(&b, 4);   // frame_rate_code
  br_get(&b, 18);  // bit_rate_value
  br_get(&b, 1);   // marker
  br_get(&b, 10);  // vbv_buffer_size
  br_get(&b, 1);   // constrained_parameters_flag
  if ((out->has_intra_matrix = (uint8_t)br_get(&b, 1)))
    for (int i = 0; i < 64; i++) out->intra_matrix[i] = (uint8_t)br_get(&b, 8);
  if ((out->has_nonintra_matrix = (uint8_t)br_get(&b, 1)))
    for (int i = 0; i < 64; i++)
      out->nonintra_matrix[i] = (uint8_t)br_get(&b, 8);
  if (b.err || !out->au.width || !out->au.height) {
    copy_err(err, errLen, "MPEG-2 sequence header too short");
    return -1;
  }

  size_t pic = find_start(data, size, seq, 0x00);
  if (pic == (size_t)-1) {
    copy_err(err, errLen, "no MPEG-2 picture header");
    return -1;
  }
  br_init(&b, data + pic + 4, size - pic - 4);
  br_get(&b, 10);  // temporal_reference
  out->picture_coding_type = (uint8_t)br_get(&b, 3);
  br_get(&b, 16);  // vbv_delay
  if (b.err) {
    copy_err(err, errLen, "MPEG-2 picture header too short");
    return -1;
  }

  // The picture coding extension comes before the first slice and belongs to
  // this picture only. Other extension types (sequence, GOP, ...) also use
  // 00 00 01 B5, so skip any whose 4-bit identifier is not 8.
  size_t picEnd = au_end_for(AU_MPEG2, data, size, pic, pic + 4);
  out->picture_structure = 3;
  out->frame_pred_frame_dct = 1;
  size_t from = pic + 4;
  for (;;) {
    size_t ext = find_start(data, picEnd, from, 0xB5);
    if (ext == (size_t)-1) break;
    br_init(&b, data + ext + 4, picEnd - ext - 4);
    uint32_t id = br_get(&b, 4);
    if (b.err) {
      copy_err(err, errLen, "MPEG-2 picture coding extension too short");
      return -1;
    }
    if (id != 8) {
      from = ext + 4;
      continue;
    }
    for (int f = 0; f < 2; f++)
      for (int v = 0; v < 2; v++) out->f_code[f][v] = (uint8_t)br_get(&b, 4);
    out->intra_dc_precision = (uint8_t)br_get(&b, 2);
    out->picture_structure = (uint8_t)br_get(&b, 2);
    out->top_field_first = (uint8_t)br_get(&b, 1);
    out->frame_pred_frame_dct = (uint8_t)br_get(&b, 1);
    out->concealment_motion_vectors = (uint8_t)br_get(&b, 1);
    out->q_scale_type = (uint8_t)br_get(&b, 1);
    out->intra_vlc_format = (uint8_t)br_get(&b, 1);
    out->alternate_scan = (uint8_t)br_get(&b, 1);
    if (b.err) {
      copy_err(err, errLen, "MPEG-2 picture coding extension too short");
      return -1;
    }
    for (int f = 0; f < 2; f++)
      for (int v = 0; v < 2; v++)
        if (out->f_code[f][v] < 1 || out->f_code[f][v] > 15) {
          copy_err(err, errLen,
                   "MPEG-2 picture coding extension has f_code outside 1..15");
          return -1;
        }
    break;
  }
  if (out->picture_coding_type != 1) {
    copy_err(err, errLen, "the first MPEG-2 picture is not an I picture");
    return -1;
  }
  // Default bitstream: sequence header through the end of the picture, the way
  // Mesa hands an elementary-stream chunk to the VLD engine. VCNPROBE_PIC_AU=1
  // keeps the old picture-header-only access unit for a bisect.
  out->picAu.au = data + pic;
  out->picAu.auSize = picEnd - pic;
  out->au.au = data + seq;
  out->au.auSize = picEnd - seq;
  out->au.intra = 1;
  return 0;
}
