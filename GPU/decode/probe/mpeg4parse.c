#include "mpeg4parse.h"

#include "bitreader.h"

static unsigned log2ceil(uint32_t v) {
  unsigned n = 0;
  while ((1u << n) < v && n < 16) n++;
  return n;
}

// VOL start is 0x00000120..0x0000012F. The parse follows ISO 14496-2 6.2.2.1
// in order; anything the probe cannot send is refused.
static int parse_vol(const uint8_t* d, size_t n, size_t at, Mpeg4Picture* o,
                     char* err, size_t errLen) {
  BitReader b;
  br_init(&b, d + at + 4, n - at - 4);
  br_get(&b, 1);   // random_accessible_vol
  br_get(&b, 8);   // video_object_type_indication
  uint32_t verid = 1;
  if (br_get(&b, 1)) {  // is_object_layer_identifier
    verid = br_get(&b, 4);
    br_get(&b, 3);  // priority
  }
  o->verid = (uint8_t)verid;
  if (br_get(&b, 4) == 15) {  // aspect_ratio_info
    br_get(&b, 8);            // par_width
    br_get(&b, 8);            // par_height
  }
  if (br_get(&b, 1)) {      // vol_control_parameters
    br_get(&b, 2);          // chroma_format
    br_get(&b, 1);          // low_delay
    if (br_get(&b, 1)) {    // vbv_parameters
      br_get(&b, 15);       // first_half_bitrate
      br_get(&b, 1);        // marker
      br_get(&b, 15);       // latter_half_bitrate
      br_get(&b, 1);
      br_get(&b, 15);       // first_half_vbv_buffer_size
      br_get(&b, 1);
      br_get(&b, 15);       // latter_half_vbv_buffer_size
      br_get(&b, 1);
      br_get(&b, 11);       // first_half_vbv_occupancy
      br_get(&b, 1);
      br_get(&b, 15);       // latter_half_vbv_occupancy
      br_get(&b, 1);
    }
  }
  o->shape = (uint8_t)br_get(&b, 2);
  if (o->shape > 1) {
    copy_err(err, errLen, "MPEG-4 shape other than rectangular/binary is not supported");
    return -1;
  }
  br_get(&b, 1);  // marker
  o->vop_time_increment_resolution = (uint16_t)br_get(&b, 16);
  br_get(&b, 1);  // marker
  if (br_get(&b, 1))  // fixed_vop_rate
    br_get(&b, log2ceil(o->vop_time_increment_resolution));
  if (o->shape == 0) {
    br_get(&b, 1);  // marker
    o->au.width = br_get(&b, 13);
    br_get(&b, 1);  // marker
    o->au.height = br_get(&b, 13);
    br_get(&b, 1);  // marker
  }
  o->interlaced = (uint8_t)br_get(&b, 1);
  o->obmc_disable = (uint8_t)br_get(&b, 1);
  uint32_t sprite = o->verid == 1 ? br_get(&b, 1) : br_get(&b, 2);
  if (sprite) {
    copy_err(err, errLen, "MPEG-4 sprite/GMC is not supported by the probe");
    return -1;
  }
  if (o->verid != 1) {
    if (br_get(&b, 1)) {  // not_8_bit
      o->quant_precision = (uint8_t)br_get(&b, 4);
      o->bits_per_pixel = (uint8_t)br_get(&b, 4);
    }
    if (o->bits_per_pixel && o->bits_per_pixel != 8) {
      copy_err(err, errLen, "MPEG-4 high bit depth is not supported");
      return -1;
    }
  }
  o->quant_type = (uint8_t)br_get(&b, 1);
  if (o->quant_type) {
    if (br_get(&b, 1)) br_skip(&b, 64 * 8);  // load_intra_quant_mat
    if (br_get(&b, 1)) br_skip(&b, 64 * 8);  // load_nonintra_quant_mat
  }
  if (o->verid != 1) o->quarter_sample = (uint8_t)br_get(&b, 1);
  if (br_get(&b, 1)) {  // complexity_estimation_disable must be 1 to continue
    br_get(&b, 1);      // resync_marker_disable
    if (br_get(&b, 1)) {  // data_partitioned
      br_get(&b, 1);      // reversible_vlc
      copy_err(err, errLen, "MPEG-4 data partitioning is not supported");
      return -1;
    }
    if (o->verid != 1 && br_get(&b, 1)) {  // newpred_enable
      copy_err(err, errLen, "MPEG-4 newpred is not supported");
      return -1;
    }
  }
  if (b.err) {
    copy_err(err, errLen, "MPEG-4 VOL too short");
    return -1;
  }
  if (!o->au.width || !o->au.height) {
    copy_err(err, errLen, "MPEG-4 VOL has no size");
    return -1;
  }
  return 0;
}

int mpeg4_parse(const uint8_t* data, size_t size, Mpeg4Picture* out, char* err,
                size_t errLen) {
  memset(out, 0, sizeof(*out));
  out->quant_precision = 5;
  size_t vol = (size_t)-1;
  for (uint8_t c = 0x20; c <= 0x2F && vol == (size_t)-1; c++)
    vol = find_start(data, size, 0, c);
  if (vol == (size_t)-1) {
    copy_err(err, errLen, "no MPEG-4 VOL header (00 00 01 20..2F)");
    return -1;
  }
  // profile_and_level_indication lives in the Visual Object Sequence header
  // (00 00 01 B0), not in the VOL byte after its start code.
  if (parse_vol(data, size, vol, out, err, errLen)) return -1;
  size_t vos = find_start(data, size, 0, 0xB0);
  if (vos != (size_t)-1 && vos + 4 < size)
    out->profile_and_level_indication = data[vos + 4];

  size_t vop = find_start(data, size, vol, 0xB6);
  if (vop == (size_t)-1) {
    copy_err(err, errLen, "no MPEG-4 VOP header");
    return -1;
  }
  BitReader b;
  br_init(&b, data + vop + 4, size - vop - 4);
  out->vop_coding_type = (uint8_t)br_get(&b, 2);
  while (br_get(&b, 1) == 1) { /* modulo_time_base: unary */ }
  br_get(&b, 1);  // marker
  br_get(&b, log2ceil(out->vop_time_increment_resolution));
  br_get(&b, 1);  // marker
  if (!br_get(&b, 1)) {  // vop_coded
    copy_err(err, errLen, "the first MPEG-4 VOP is not coded");
    return -1;
  }
  if (out->vop_coding_type != 0) {
    copy_err(err, errLen, "the first MPEG-4 VOP is not an I-VOP");
    return -1;
  }
  out->intra_dc_vlc_thr = (uint8_t)br_get(&b, 3);
  if (out->interlaced) {
    out->top_field_first = (uint8_t)br_get(&b, 1);
    out->alternate_vertical_scan_flag = (uint8_t)br_get(&b, 1);
  }
  out->vop_quant = (uint8_t)br_get(&b, out->quant_precision);
  if (b.err) {
    copy_err(err, errLen, "MPEG-4 VOP header too short");
    return -1;
  }
  // Default bitstream: VOL header through the end of the first VOP, like the
  // MPEG-2 and VC-1 defaults. VCNPROBE_PIC_AU=1 keeps the VOP-only unit.
  size_t vopEnd = au_end_for(AU_MPEG4, data, size, vop, vop + 4);
  out->picAu = out->au;
  out->picAu.au = data + vop;
  out->picAu.auSize = vopEnd - vop;
  out->picAu.intra = 1;
  out->au.au = data + vol;
  out->au.auSize = vopEnd - vol;
  out->au.intra = 1;
  return 0;
}
