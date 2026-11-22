// AV1 header parser. Section numbers refer to the AV1 Bitstream & Decoding
// Process Specification.
#include "av1parse.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// ---------------------------------------------------------------- bit reader
// (4.10)
typedef struct {
  const uint8_t* buf;
  size_t size;  // bytes
  size_t pos;   // bits
  bool overrun;
} BR;

static int br_bit(BR* b) {
  if ((b->pos >> 3) >= b->size) {
    b->overrun = true;
    return 0;
  }
  int v = (b->buf[b->pos >> 3] >> (7 - (b->pos & 7))) & 1;
  b->pos++;
  return v;
}
static uint32_t f(BR* b, int n) {
  uint32_t x = 0;
  if (n < 0 || n > 32) {
    b->overrun = true;
    return 0;
  }
  for (int i = 0; i < n; i++) x = (x << 1) | br_bit(b);
  return x;
}
static int su(BR* b, int n) {
  if (n < 1 || n > 31) {
    b->overrun = true;
    return 0;
  }
  int v = (int)f(b, n);
  int signMask = 1 << (n - 1);
  if (v & signMask) v -= 2 * signMask;
  return v;
}
static uint32_t ns(BR* b, uint32_t n) {
  if (n == 0 || n > INT32_MAX) {
    b->overrun = true;
    return 0;
  }
  int w = 0;
  uint32_t x = n;
  while (x) {
    w++;
    x >>= 1;
  }
  uint32_t m = (1u << w) - n;
  uint32_t v = f(b, w - 1);
  if (v < m) return v;
  uint32_t extra = br_bit(b);
  return (v << 1) - m + extra;
}
static uint32_t le(BR* b, int n) {
  uint32_t t = 0;
  if (n < 0 || n > 4) {
    b->overrun = true;
    return 0;
  }
  for (int i = 0; i < n; i++) t += f(b, 8) << (i * 8);
  return t;
}
static uint32_t uvlc(BR* b) {
  int leadingZeros = 0;
  while (!br_bit(b)) {
    if (++leadingZeros >= 32 || b->overrun) return UINT32_MAX;
  }
  if (leadingZeros >= 32) return UINT32_MAX;
  return f(b, leadingZeros) + ((1u << leadingZeros) - 1);
}
static void byte_alignment(BR* b) {
  while (b->pos & 7) br_bit(b);
}

static int leb128(const uint8_t* d, size_t n, uint64_t* out) {
  uint64_t v = 0;
  for (int i = 0; i < 8; i++) {
    if ((size_t)i >= n) return -1;
    v |= (uint64_t)(d[i] & 0x7f) << (i * 7);
    if (!(d[i] & 0x80)) {
      *out = v;
      return i + 1;
    }
  }
  return -1;
}

static int imin(int a, int b) { return a < b ? a : b; }
static int imax(int a, int b) { return a > b ? a : b; }
static int clip3(int lo, int hi, int x) {
  return x < lo ? lo : (x > hi ? hi : x);
}

// ---------------------------------------------------------------- sequence
// header (5.5)
static void color_config(BR* b, AV1Seq* s) {
  s->high_bitdepth = f(b, 1);
  s->twelve_bit = 0;
  if (s->seq_profile == 2 && s->high_bitdepth) {
    s->twelve_bit = f(b, 1);
    s->BitDepth = s->twelve_bit ? 12 : 10;
  } else {
    s->BitDepth = s->high_bitdepth ? 10 : 8;
  }
  s->mono_chrome = s->seq_profile == 1 ? 0 : f(b, 1);
  s->NumPlanes = s->mono_chrome ? 1 : 3;
  s->color_description_present_flag = f(b, 1);
  if (s->color_description_present_flag) {
    s->color_primaries = f(b, 8);
    s->transfer_characteristics = f(b, 8);
    s->matrix_coefficients = f(b, 8);
  } else {
    s->color_primaries = 2;
    s->transfer_characteristics = 2;
    s->matrix_coefficients = 2;
  }
  if (s->mono_chrome) {
    s->color_range = f(b, 1);
    s->subsampling_x = s->subsampling_y = 1;
    s->chroma_sample_position = 0;
    s->separate_uv_delta_q = 0;
    return;
  } else if (s->color_primaries == 1 && s->transfer_characteristics == 13 &&
             s->matrix_coefficients == 0) {
    s->color_range = 1;
    s->subsampling_x = s->subsampling_y = 0;
  } else {
    s->color_range = f(b, 1);
    if (s->seq_profile == 0) {
      s->subsampling_x = s->subsampling_y = 1;
    } else if (s->seq_profile == 1) {
      s->subsampling_x = s->subsampling_y = 0;
    } else {
      if (s->BitDepth == 12) {
        s->subsampling_x = f(b, 1);
        s->subsampling_y = s->subsampling_x ? f(b, 1) : 0;
      } else {
        s->subsampling_x = 1;
        s->subsampling_y = 0;
      }
    }
    if (s->subsampling_x && s->subsampling_y)
      s->chroma_sample_position = f(b, 2);
  }
  s->separate_uv_delta_q = f(b, 1);
}

static int parse_sequence_header(BR* b, AV1Seq* s) {
  memset(s, 0, sizeof(*s));
  s->seq_profile = f(b, 3);
  s->still_picture = f(b, 1);
  s->reduced_still_picture_header = f(b, 1);
  int buffer_delay_length_minus_1 = 0;
  if (s->reduced_still_picture_header) {
    f(b, 5);  // seq_level_idx[0]
  } else {
    s->timing_info_present_flag = f(b, 1);
    if (s->timing_info_present_flag) {
      f(b, 32);
      f(b, 32);
      s->equal_picture_interval = f(b, 1);
      if (s->equal_picture_interval) uvlc(b);
      s->decoder_model_info_present_flag = f(b, 1);
      if (s->decoder_model_info_present_flag) {
        buffer_delay_length_minus_1 = f(b, 5);
        f(b, 32);
        s->buffer_removal_time_length_minus_1 = f(b, 5);
        s->frame_presentation_time_length_minus_1 = f(b, 5);
      }
    }
    int initial_display_delay_present_flag = f(b, 1);
    s->operating_points_cnt_minus_1 = f(b, 5);
    for (int i = 0; i <= s->operating_points_cnt_minus_1; i++) {
      s->operating_point_idc[i] = f(b, 12);
      int seq_level_idx = f(b, 5);
      if (seq_level_idx > 7) f(b, 1);
      if (s->decoder_model_info_present_flag) {
        s->decoder_model_present_for_this_op[i] = f(b, 1);
        if (s->decoder_model_present_for_this_op[i]) {
          int n = buffer_delay_length_minus_1 + 1;
          f(b, n);
          f(b, n);
          f(b, 1);
        }
      }
      if (initial_display_delay_present_flag) {
        if (f(b, 1)) f(b, 4);
      }
    }
  }
  s->operatingPoint = 0;
  s->OperatingPointIdc = s->operating_point_idc[0];
  s->frame_width_bits_minus_1 = f(b, 4);
  s->frame_height_bits_minus_1 = f(b, 4);
  s->max_frame_width_minus_1 = f(b, s->frame_width_bits_minus_1 + 1);
  s->max_frame_height_minus_1 = f(b, s->frame_height_bits_minus_1 + 1);
  s->frame_id_numbers_present_flag =
      s->reduced_still_picture_header ? 0 : f(b, 1);
  if (s->frame_id_numbers_present_flag) {
    s->delta_frame_id_length_minus_2 = f(b, 4);
    s->additional_frame_id_length_minus_1 = f(b, 3);
  }
  s->use_128x128_superblock = f(b, 1);
  s->enable_filter_intra = f(b, 1);
  s->enable_intra_edge_filter = f(b, 1);
  if (s->reduced_still_picture_header) {
    s->seq_force_screen_content_tools = 2;
    s->seq_force_integer_mv = 2;
    s->OrderHintBits = 0;
  } else {
    s->enable_interintra_compound = f(b, 1);
    s->enable_masked_compound = f(b, 1);
    s->enable_warped_motion = f(b, 1);
    s->enable_dual_filter = f(b, 1);
    s->enable_order_hint = f(b, 1);
    if (s->enable_order_hint) {
      s->enable_jnt_comp = f(b, 1);
      s->enable_ref_frame_mvs = f(b, 1);
    }
    s->seq_choose_screen_content_tools = f(b, 1);
    s->seq_force_screen_content_tools =
        s->seq_choose_screen_content_tools ? 2 : f(b, 1);
    if (s->seq_force_screen_content_tools > 0) {
      s->seq_choose_integer_mv = f(b, 1);
      s->seq_force_integer_mv = s->seq_choose_integer_mv ? 2 : f(b, 1);
    } else {
      s->seq_force_integer_mv = 2;
    }
    if (s->enable_order_hint) {
      s->order_hint_bits_minus_1 = f(b, 3);
      s->OrderHintBits = s->order_hint_bits_minus_1 + 1;
    }
  }
  s->enable_superres = f(b, 1);
  s->enable_cdef = f(b, 1);
  s->enable_restoration = f(b, 1);
  color_config(b, s);
  s->film_grain_params_present = f(b, 1);
  s->valid = !b->overrun;
  return s->valid ? 0 : -1;
}

// ---------------------------------------------------------------- frame header
// helpers
static int get_relative_dist(const AV1Seq* s, int a, int b) {
  if (!s->enable_order_hint) return 0;
  int diff = a - b;
  int m = 1 << (s->OrderHintBits - 1);
  diff = (diff & (m - 1)) - (diff & m);
  return diff;
}

static const int Segmentation_Feature_Bits[8] = {8, 6, 6, 6, 6, 3, 0, 0};
static const int Segmentation_Feature_Signed[8] = {1, 1, 1, 1, 1, 0, 0, 0};
static const int Segmentation_Feature_Max[8] = {255, 63, 63, 63, 63, 7, 0, 0};

static void setup_past_independence(AV1Frame* h) {
  memset(h->FeatureEnabled, 0, sizeof(h->FeatureEnabled));
  memset(h->FeatureData, 0, sizeof(h->FeatureData));
  for (int ref = 1; ref <= 7; ref++)
    for (int i = 0; i < 6; i++)
      h->gm_params[ref][i] = (i % 3 == 2) ? (1 << 16) : 0;
  h->loop_filter_delta_enabled = 1;
  static const int def[8] = {1, 0, 0, 0, -1, 0, -1, -1};
  memcpy(h->loop_filter_ref_deltas, def, sizeof(def));
  h->loop_filter_mode_deltas[0] = h->loop_filter_mode_deltas[1] = 0;
}

// load_previous(): values the current frame inherits from primary_ref_frame
// (7.21)
static void load_previous(AV1Parser* p, int prevGmParams[8][6]) {
  AV1Frame* h = &p->fh;
  AV1RefSlot* r = &p->ref[h->ref_frame_idx[h->primary_ref_frame]];
  memcpy(prevGmParams, r->gm_params, sizeof(r->gm_params));
  memcpy(h->loop_filter_ref_deltas, r->lf_ref_deltas, sizeof(r->lf_ref_deltas));
  memcpy(h->loop_filter_mode_deltas, r->lf_mode_deltas,
         sizeof(r->lf_mode_deltas));
  memcpy(h->FeatureEnabled, r->feature_enabled, sizeof(r->feature_enabled));
  memcpy(h->FeatureData, r->feature_data, sizeof(r->feature_data));
}

static void superres_params(BR* b, AV1Parser* p) {
  AV1Frame* h = &p->fh;
  h->use_superres = p->seq.enable_superres ? f(b, 1) : 0;
  if (h->use_superres)
    h->SuperresDenom = f(b, 3) + 9;
  else
    h->SuperresDenom = 8;
  h->UpscaledWidth = h->FrameWidth;
  h->FrameWidth =
      (h->UpscaledWidth * 8 + (h->SuperresDenom / 2)) / h->SuperresDenom;
}
static void compute_image_size(AV1Frame* h) {
  h->MiCols = 2 * ((h->FrameWidth + 7) >> 3);
  h->MiRows = 2 * ((h->FrameHeight + 7) >> 3);
}
static void frame_size(BR* b, AV1Parser* p) {
  AV1Frame* h = &p->fh;
  if (h->frame_size_override_flag) {
    h->frame_width_minus_1 = f(b, p->seq.frame_width_bits_minus_1 + 1);
    h->frame_height_minus_1 = f(b, p->seq.frame_height_bits_minus_1 + 1);
  } else {
    h->frame_width_minus_1 = p->seq.max_frame_width_minus_1;
    h->frame_height_minus_1 = p->seq.max_frame_height_minus_1;
  }
  h->FrameWidth = h->frame_width_minus_1 + 1;
  h->FrameHeight = h->frame_height_minus_1 + 1;
  superres_params(b, p);
  compute_image_size(h);
}
static void render_size(BR* b, AV1Frame* h) {
  if (f(b, 1)) {
    h->RenderWidth = f(b, 16) + 1;
    h->RenderHeight = f(b, 16) + 1;
  } else {
    h->RenderWidth = h->UpscaledWidth;
    h->RenderHeight = h->FrameHeight;
  }
}
static void frame_size_with_refs(BR* b, AV1Parser* p) {
  AV1Frame* h = &p->fh;
  int found_ref = 0;
  for (int i = 0; i < 7; i++) {
    found_ref = f(b, 1);
    if (found_ref) {
      AV1RefSlot* r = &p->ref[h->ref_frame_idx[i]];
      h->UpscaledWidth = r->upscaled_width;
      h->FrameWidth = h->UpscaledWidth;
      h->FrameHeight = r->frame_height;
      h->RenderWidth = r->render_width;
      h->RenderHeight = r->render_height;
      break;
    }
  }
  if (!found_ref) {
    frame_size(b, p);
    render_size(b, h);
  } else {
    superres_params(b, p);
    compute_image_size(h);
  }
  h->frame_width_minus_1 = h->FrameWidth - 1;
  h->frame_height_minus_1 = h->FrameHeight - 1;
}

static int find_latest_backward(AV1Parser* p, int* shiftedOrderHints,
                                int* usedFrame, int curFrameHint) {
  int ref = -1, latestOrderHint = 0;
  for (int i = 0; i < 8; i++) {
    int hint = shiftedOrderHints[i];
    if (!usedFrame[i] && hint >= curFrameHint &&
        (ref < 0 || hint >= latestOrderHint)) {
      ref = i;
      latestOrderHint = hint;
    }
  }
  return ref;
}
static int find_earliest_backward(AV1Parser* p, int* shiftedOrderHints,
                                  int* usedFrame, int curFrameHint) {
  int ref = -1, earliestOrderHint = 0;
  for (int i = 0; i < 8; i++) {
    int hint = shiftedOrderHints[i];
    if (!usedFrame[i] && hint >= curFrameHint &&
        (ref < 0 || hint < earliestOrderHint)) {
      ref = i;
      earliestOrderHint = hint;
    }
  }
  return ref;
}
static int find_latest_forward(AV1Parser* p, int* shiftedOrderHints,
                               int* usedFrame, int curFrameHint) {
  int ref = -1, latestOrderHint = 0;
  for (int i = 0; i < 8; i++) {
    int hint = shiftedOrderHints[i];
    if (!usedFrame[i] && hint < curFrameHint &&
        (ref < 0 || hint >= latestOrderHint)) {
      ref = i;
      latestOrderHint = hint;
    }
  }
  return ref;
}

// 7.8 set_frame_refs
static void set_frame_refs(AV1Parser* p, int last_frame_idx,
                           int gold_frame_idx) {
  AV1Frame* h = &p->fh;
  const AV1Seq* s = &p->seq;
  for (int i = 0; i < 7; i++) h->ref_frame_idx[i] = -1;
  h->ref_frame_idx[0] = last_frame_idx;  // LAST_FRAME - LAST_FRAME
  h->ref_frame_idx[3] = gold_frame_idx;  // GOLDEN_FRAME - LAST_FRAME
  int usedFrame[8] = {0};
  usedFrame[last_frame_idx] = 1;
  usedFrame[gold_frame_idx] = 1;
  int curFrameHint = 1 << (s->OrderHintBits - 1);
  int shiftedOrderHints[8];
  for (int i = 0; i < 8; i++)
    shiftedOrderHints[i] =
        curFrameHint +
        get_relative_dist(s, p->ref[i].order_hint, h->order_hint);
  int lastOrderHint = shiftedOrderHints[last_frame_idx];
  int goldOrderHint = shiftedOrderHints[gold_frame_idx];
  (void)lastOrderHint;
  (void)goldOrderHint;
  int ref = find_latest_backward(p, shiftedOrderHints, usedFrame, curFrameHint);
  if (ref >= 0) {
    h->ref_frame_idx[6] = ref;
    usedFrame[ref] = 1;
  }  // ALTREF
  ref = find_earliest_backward(p, shiftedOrderHints, usedFrame, curFrameHint);
  if (ref >= 0) {
    h->ref_frame_idx[4] = ref;
    usedFrame[ref] = 1;
  }  // BWDREF
  ref = find_earliest_backward(p, shiftedOrderHints, usedFrame, curFrameHint);
  if (ref >= 0) {
    h->ref_frame_idx[5] = ref;
    usedFrame[ref] = 1;
  }  // ALTREF2
  static const int Ref_Frame_List[5] = {
      2, 3, 5, 6, 7};  // LAST2, LAST3, BWDREF, ALTREF2, ALTREF
  for (int i = 0; i < 5; i++) {
    int refFrame = Ref_Frame_List[i];
    if (h->ref_frame_idx[refFrame - 1] < 0) {
      ref = find_latest_forward(p, shiftedOrderHints, usedFrame, curFrameHint);
      if (ref >= 0) {
        h->ref_frame_idx[refFrame - 1] = ref;
        usedFrame[ref] = 1;
      }
    }
  }
  ref = -1;
  int earliestOrderHint = 0;
  for (int i = 0; i < 8; i++) {
    int hint = shiftedOrderHints[i];
    if (ref < 0 || hint < earliestOrderHint) {
      ref = i;
      earliestOrderHint = hint;
    }
  }
  for (int i = 0; i < 7; i++)
    if (h->ref_frame_idx[i] < 0) h->ref_frame_idx[i] = ref;
}

static int tile_log2(int blkSize, int target) {
  int k;
  for (k = 0; (blkSize << k) < target; k++) {
  }
  return k;
}

// 5.9.15
static int tile_info(BR* b, AV1Parser* p) {
  AV1Frame* h = &p->fh;
  const AV1Seq* s = &p->seq;
  if (h->MiCols <= 0 || h->MiRows <= 0) return -1;
  int sbCols = s->use_128x128_superblock ? ((h->MiCols - 1) / 32 + 1)
                                         : ((h->MiCols - 1) / 16 + 1);
  int sbRows = s->use_128x128_superblock ? ((h->MiRows - 1) / 32 + 1)
                                         : ((h->MiRows - 1) / 16 + 1);
  if (sbCols <= 0 || sbRows <= 0) return -1;
  int sbShift = s->use_128x128_superblock ? 5 : 4;
  int sbSize = sbShift + 2;
  int maxTileWidthSb = 4096 >> sbSize;
  int maxTileAreaSb = (4096 * 2304) >> (2 * sbSize);
  int minLog2TileCols = tile_log2(maxTileWidthSb, sbCols);
  int maxLog2TileCols = tile_log2(1, imin(sbCols, AV1_MAX_TILE_COLS));
  int maxLog2TileRows = tile_log2(1, imin(sbRows, AV1_MAX_TILE_ROWS));
  int minLog2Tiles =
      imax(minLog2TileCols, tile_log2(maxTileAreaSb, sbRows * sbCols));
  h->uniform_tile_spacing_flag = f(b, 1);
  if (h->uniform_tile_spacing_flag) {
    h->TileColsLog2 = minLog2TileCols;
    while (h->TileColsLog2 < maxLog2TileCols) {
      if (f(b, 1))
        h->TileColsLog2++;
      else
        break;
    }
    int tileWidthSb = (sbCols + (1 << h->TileColsLog2) - 1) >> h->TileColsLog2;
    int i = 0;
    for (int startSb = 0; startSb < sbCols; startSb += tileWidthSb) {
      if (i >= AV1_MAX_TILE_COLS) return -1;
      h->MiColStarts[i++] = startSb << sbShift;
    }
    h->MiColStarts[i] = h->MiCols;
    h->TileCols = i;
    int minLog2TileRows = imax(minLog2Tiles - h->TileColsLog2, 0);
    h->TileRowsLog2 = minLog2TileRows;
    while (h->TileRowsLog2 < maxLog2TileRows) {
      if (f(b, 1))
        h->TileRowsLog2++;
      else
        break;
    }
    int tileHeightSb = (sbRows + (1 << h->TileRowsLog2) - 1) >> h->TileRowsLog2;
    i = 0;
    for (int startSb = 0; startSb < sbRows; startSb += tileHeightSb) {
      if (i >= AV1_MAX_TILE_ROWS) return -1;
      h->MiRowStarts[i++] = startSb << sbShift;
    }
    h->MiRowStarts[i] = h->MiRows;
    h->TileRows = i;
  } else {
    int widestTileSb = 0, startSb = 0, i;
    for (i = 0; startSb < sbCols; i++) {
      if (i >= AV1_MAX_TILE_COLS) return -1;
      h->MiColStarts[i] = startSb << sbShift;
      int maxWidth = imin(sbCols - startSb, maxTileWidthSb);
      int sizeSb = ns(b, maxWidth) + 1;
      widestTileSb = imax(sizeSb, widestTileSb);
      startSb += sizeSb;
    }
    h->MiColStarts[i] = h->MiCols;
    h->TileCols = i;
    h->TileColsLog2 = tile_log2(1, h->TileCols);
    if (minLog2Tiles > 0)
      maxTileAreaSb = (sbRows * sbCols) >> (minLog2Tiles + 1);
    else
      maxTileAreaSb = sbRows * sbCols;
    if (widestTileSb <= 0) return -1;
    int maxTileHeightSb = imax(maxTileAreaSb / widestTileSb, 1);
    startSb = 0;
    for (i = 0; startSb < sbRows; i++) {
      if (i >= AV1_MAX_TILE_ROWS) return -1;
      h->MiRowStarts[i] = startSb << sbShift;
      int maxHeight = imin(sbRows - startSb, maxTileHeightSb);
      int sizeSb = ns(b, maxHeight) + 1;
      startSb += sizeSb;
    }
    h->MiRowStarts[i] = h->MiRows;
    h->TileRows = i;
    h->TileRowsLog2 = tile_log2(1, h->TileRows);
  }
  if (h->TileColsLog2 > 0 || h->TileRowsLog2 > 0) {
    h->context_update_tile_id = f(b, h->TileRowsLog2 + h->TileColsLog2);
    h->TileSizeBytes = f(b, 2) + 1;
  } else {
    h->context_update_tile_id = 0;
    h->TileSizeBytes = 4;
  }
  if (h->TileCols < 1 || h->TileRows < 1 || h->TileCols > AV1_MAX_TILE_COLS ||
      h->TileRows > AV1_MAX_TILE_ROWS)
    return -1;
  if (h->context_update_tile_id >= h->TileCols * h->TileRows) return -1;
  return 0;
}

static int read_delta_q(BR* b) { return f(b, 1) ? su(b, 7) : 0; }

static void quantization_params(BR* b, AV1Parser* p) {
  AV1Frame* h = &p->fh;
  const AV1Seq* s = &p->seq;
  h->base_q_idx = f(b, 8);
  h->DeltaQYDc = read_delta_q(b);
  if (s->NumPlanes > 1) {
    h->diff_uv_delta = s->separate_uv_delta_q ? f(b, 1) : 0;
    h->DeltaQUDc = read_delta_q(b);
    h->DeltaQUAc = read_delta_q(b);
    if (h->diff_uv_delta) {
      h->DeltaQVDc = read_delta_q(b);
      h->DeltaQVAc = read_delta_q(b);
    } else {
      h->DeltaQVDc = h->DeltaQUDc;
      h->DeltaQVAc = h->DeltaQUAc;
    }
  } else {
    h->diff_uv_delta = h->DeltaQUDc = h->DeltaQUAc = h->DeltaQVDc =
        h->DeltaQVAc = 0;
  }
  h->using_qmatrix = f(b, 1);
  if (h->using_qmatrix) {
    h->qm_y = f(b, 4);
    h->qm_u = f(b, 4);
    h->qm_v = s->separate_uv_delta_q ? f(b, 4) : h->qm_u;
  } else {
    h->qm_y = h->qm_u = h->qm_v = 0;
  }
}

static void segmentation_params(BR* b, AV1Parser* p) {
  AV1Frame* h = &p->fh;
  h->segmentation_enabled = f(b, 1);
  if (h->segmentation_enabled) {
    if (h->primary_ref_frame == AV1_PRIMARY_REF_NONE) {
      h->segmentation_update_map = 1;
      h->segmentation_temporal_update = 0;
      h->segmentation_update_data = 1;
    } else {
      h->segmentation_update_map = f(b, 1);
      h->segmentation_temporal_update =
          h->segmentation_update_map ? f(b, 1) : 0;
      h->segmentation_update_data = f(b, 1);
    }
    if (h->segmentation_update_data) {
      for (int i = 0; i < AV1_MAX_SEGMENTS; i++) {
        for (int j = 0; j < AV1_SEG_LVL_MAX; j++) {
          int feature_value = 0;
          int enabled = f(b, 1);
          h->FeatureEnabled[i][j] = enabled;
          int clipped = 0;
          if (enabled) {
            int bitsToRead = Segmentation_Feature_Bits[j];
            int limit = Segmentation_Feature_Max[j];
            if (Segmentation_Feature_Signed[j]) {
              feature_value = su(b, 1 + bitsToRead);
              clipped = clip3(-limit, limit, feature_value);
            } else {
              feature_value = f(b, bitsToRead);
              clipped = clip3(0, limit, feature_value);
            }
          }
          h->FeatureData[i][j] = clipped;
        }
      }
    }
  } else {
    memset(h->FeatureEnabled, 0, sizeof(h->FeatureEnabled));
    memset(h->FeatureData, 0, sizeof(h->FeatureData));
    h->segmentation_update_map = h->segmentation_temporal_update =
        h->segmentation_update_data = 0;
  }
  h->SegIdPreSkip = 0;
  h->LastActiveSegId = 0;
  for (int i = 0; i < AV1_MAX_SEGMENTS; i++)
    for (int j = 0; j < AV1_SEG_LVL_MAX; j++)
      if (h->FeatureEnabled[i][j]) {
        h->LastActiveSegId = i;
        if (j >= 5) h->SegIdPreSkip = 1;
      }
}

static int get_qindex(AV1Frame* h, int segmentId) {
  if (h->segmentation_enabled && h->FeatureEnabled[segmentId][0]) {
    int q = h->base_q_idx + h->FeatureData[segmentId][0];
    return clip3(0, 255, q);
  }
  return h->base_q_idx;
}

static void loop_filter_params(BR* b, AV1Parser* p) {
  AV1Frame* h = &p->fh;
  if (h->CodedLossless || h->allow_intrabc) {
    h->loop_filter_level[0] = h->loop_filter_level[1] = 0;
    static const int def[8] = {1, 0, 0, 0, -1, 0, -1, -1};
    memcpy(h->loop_filter_ref_deltas, def, sizeof(def));
    h->loop_filter_mode_deltas[0] = h->loop_filter_mode_deltas[1] = 0;
    return;
  }
  h->loop_filter_level[0] = f(b, 6);
  h->loop_filter_level[1] = f(b, 6);
  if (p->seq.NumPlanes > 1) {
    if (h->loop_filter_level[0] || h->loop_filter_level[1]) {
      h->loop_filter_level[2] = f(b, 6);
      h->loop_filter_level[3] = f(b, 6);
    }
  }
  h->loop_filter_sharpness = f(b, 3);
  h->loop_filter_delta_enabled = f(b, 1);
  h->loop_filter_delta_update = 0;
  if (h->loop_filter_delta_enabled) {
    h->loop_filter_delta_update = f(b, 1);
    if (h->loop_filter_delta_update) {
      for (int i = 0; i < 8; i++)
        if (f(b, 1)) h->loop_filter_ref_deltas[i] = su(b, 7);
      for (int i = 0; i < 2; i++)
        if (f(b, 1)) h->loop_filter_mode_deltas[i] = su(b, 7);
    }
  }
}

static void cdef_params(BR* b, AV1Parser* p) {
  AV1Frame* h = &p->fh;
  memset(h->cdef_y_pri, 0, sizeof(h->cdef_y_pri));
  memset(h->cdef_y_sec, 0, sizeof(h->cdef_y_sec));
  memset(h->cdef_uv_pri, 0, sizeof(h->cdef_uv_pri));
  memset(h->cdef_uv_sec, 0, sizeof(h->cdef_uv_sec));
  if (h->CodedLossless || h->allow_intrabc || !p->seq.enable_cdef) {
    h->cdef_bits = 0;
    h->CdefDamping = 3;
    return;
  }
  h->CdefDamping = f(b, 2) + 3;
  h->cdef_bits = f(b, 2);
  for (int i = 0; i < (1 << h->cdef_bits); i++) {
    h->cdef_y_pri[i] = f(b, 4);
    h->cdef_y_sec[i] =
        f(b, 2);  // coded value (3 means 4); hardware takes the coded value
    if (p->seq.NumPlanes > 1) {
      h->cdef_uv_pri[i] = f(b, 4);
      h->cdef_uv_sec[i] = f(b, 2);
    }
  }
}

static void lr_params(BR* b, AV1Parser* p) {
  AV1Frame* h = &p->fh;
  const AV1Seq* s = &p->seq;
  h->FrameRestorationType[0] = h->FrameRestorationType[1] =
      h->FrameRestorationType[2] = 0;
  h->LoopRestorationSize[0] = h->LoopRestorationSize[1] =
      h->LoopRestorationSize[2] = 0;
  if (h->AllLossless || h->allow_intrabc || !s->enable_restoration) return;
  static const int Remap_Lr_Type[4] = {0, 3, 1, 2};
  int usesLr = 0, usesChromaLr = 0;
  for (int i = 0; i < s->NumPlanes; i++) {
    int lr_type = f(b, 2);
    h->FrameRestorationType[i] = Remap_Lr_Type[lr_type];
    if (h->FrameRestorationType[i]) {
      usesLr = 1;
      if (i > 0) usesChromaLr = 1;
    }
  }
  if (usesLr) {
    int lr_unit_shift;
    if (s->use_128x128_superblock) {
      lr_unit_shift = f(b, 1);
      lr_unit_shift++;
    } else {
      lr_unit_shift = f(b, 1);
      if (lr_unit_shift) lr_unit_shift += f(b, 1);
    }
    h->LoopRestorationSize[0] = 256 >> (2 - lr_unit_shift);
    int lr_uv_shift =
        (s->subsampling_x && s->subsampling_y && usesChromaLr) ? f(b, 1) : 0;
    h->LoopRestorationSize[1] = h->LoopRestorationSize[0] >> lr_uv_shift;
    h->LoopRestorationSize[2] = h->LoopRestorationSize[0] >> lr_uv_shift;
  }
}

static void skip_mode_params(BR* b, AV1Parser* p) {
  AV1Frame* h = &p->fh;
  const AV1Seq* s = &p->seq;
  int skipModeAllowed = 0;
  if (!(h->FrameIsIntra || !h->reference_select || !s->enable_order_hint)) {
    int forwardIdx = -1, backwardIdx = -1, forwardHint = 0, backwardHint = 0;
    for (int i = 0; i < 7; i++) {
      int refHint = p->ref[h->ref_frame_idx[i]].order_hint;
      if (get_relative_dist(s, refHint, h->order_hint) < 0) {
        if (forwardIdx < 0 || get_relative_dist(s, refHint, forwardHint) > 0) {
          forwardIdx = i;
          forwardHint = refHint;
        }
      } else if (get_relative_dist(s, refHint, h->order_hint) > 0) {
        if (backwardIdx < 0 ||
            get_relative_dist(s, refHint, backwardHint) < 0) {
          backwardIdx = i;
          backwardHint = refHint;
        }
      }
    }
    if (forwardIdx < 0)
      skipModeAllowed = 0;
    else if (backwardIdx >= 0)
      skipModeAllowed = 1;
    else {
      int secondForwardIdx = -1, secondForwardHint = 0;
      for (int i = 0; i < 7; i++) {
        int refHint = p->ref[h->ref_frame_idx[i]].order_hint;
        if (get_relative_dist(s, refHint, forwardHint) < 0) {
          if (secondForwardIdx < 0 ||
              get_relative_dist(s, refHint, secondForwardHint) > 0) {
            secondForwardIdx = i;
            secondForwardHint = refHint;
          }
        }
      }
      skipModeAllowed = secondForwardIdx >= 0;
    }
  }
  h->skip_mode_present = skipModeAllowed ? f(b, 1) : 0;
}

static int inverse_recenter(int r, int v) {
  if (v > 2 * r) return v;
  if (v & 1) return r - ((v + 1) >> 1);
  return r + (v >> 1);
}
static int decode_subexp(BR* b, int numSyms) {
  int i = 0, mk = 0, k = 3;
  while (1) {
    int b2 = i ? k + i - 1 : k;
    if (b2 >= 31) {  // 1 << b2 would overflow an int
      b->overrun = true;
      return 0;
    }
    int a = 1 << b2;
    if (numSyms <= mk + 3 * a) return (int)ns(b, numSyms - mk) + mk;
    if (f(b, 1)) {
      i++;
      mk += a;
    } else
      return (int)f(b, b2) + mk;
  }
}
static int decode_unsigned_subexp_with_ref(BR* b, int mx, int r) {
  if (mx <= 0 || r < 0 || r >= mx) {
    b->overrun = true;
    return 0;
  }
  int v = decode_subexp(b, mx);
  if (r <= mx / 2) return inverse_recenter(r, v);
  return mx - 1 - inverse_recenter(mx - 1 - r, v);
}
static int decode_signed_subexp_with_ref(BR* b, int low, int high, int r) {
  int x = decode_unsigned_subexp_with_ref(b, high - low, r - low);
  return x + low;
}
static void read_global_param(BR* b, AV1Frame* h, int prev[8][6], int type,
                              int ref, int idx) {
  int absBits = 12, precBits = 15;
  if (idx < 2) {
    if (type == AV1_TRANSLATION) {
      absBits = 9 - !h->allow_high_precision_mv;
      precBits = 3 - !h->allow_high_precision_mv;
    } else {
      absBits = 12;
      precBits = 6;
    }
  }
  int precDiff = 16 - precBits;
  int round = (idx % 3) == 2 ? (1 << 16) : 0;
  int sub = (idx % 3) == 2 ? (1 << precBits) : 0;
  int mx = 1 << absBits;
  int r = (prev[ref][idx] >> precDiff) - sub;
  int decoded = decode_signed_subexp_with_ref(b, -mx, mx + 1, r);
  h->gm_params[ref][idx] = decoded * (1 << precDiff) + round;
}
static void global_motion_params(BR* b, AV1Frame* h, int prev[8][6]) {
  for (int ref = 1; ref <= 7; ref++) {
    h->gm_type[ref] = AV1_IDENTITY;
    for (int i = 0; i < 6; i++)
      h->gm_params[ref][i] = (i % 3 == 2) ? (1 << 16) : 0;
  }
  if (h->FrameIsIntra) return;
  for (int ref = 1; ref <= 7; ref++) {
    int type = AV1_IDENTITY;
    if (f(b, 1)) {
      if (f(b, 1))
        type = AV1_ROTZOOM;
      else
        type = f(b, 1) ? AV1_TRANSLATION : AV1_AFFINE;
    }
    h->gm_type[ref] = type;
    if (type >= AV1_ROTZOOM) {
      read_global_param(b, h, prev, type, ref, 2);
      read_global_param(b, h, prev, type, ref, 3);
      if (type == AV1_AFFINE) {
        read_global_param(b, h, prev, type, ref, 4);
        read_global_param(b, h, prev, type, ref, 5);
      } else {
        h->gm_params[ref][4] = -h->gm_params[ref][3];
        h->gm_params[ref][5] = h->gm_params[ref][2];
      }
    }
    if (type >= AV1_TRANSLATION) {
      read_global_param(b, h, prev, type, ref, 0);
      read_global_param(b, h, prev, type, ref, 1);
    }
  }
}

static void film_grain_params(BR* b, AV1Parser* p) {
  AV1Frame* h = &p->fh;
  const AV1Seq* s = &p->seq;
  AV1FilmGrain* g = &h->film_grain;
  if (!s->film_grain_params_present || (!h->show_frame && !h->showable_frame)) {
    memset(g, 0, sizeof(*g));
    return;
  }
  g->apply_grain = f(b, 1);
  if (!g->apply_grain) {
    memset(g, 0, sizeof(*g));
    return;
  }
  g->grain_seed = f(b, 16);
  g->update_grain = h->frame_type == AV1_INTER_FRAME ? f(b, 1) : 1;
  if (!g->update_grain) {
    g->film_grain_params_ref_idx = f(b, 3);
    int tempGrainSeed = g->grain_seed;
    *g = p->ref[g->film_grain_params_ref_idx].film_grain;  // load_grain_params
    g->grain_seed = tempGrainSeed;
    return;
  }
  g->num_y_points = f(b, 4);
  // The spec allows at most 14 luma and 10 chroma points per plane (the VCN
  // film grain block has that many slots); more is not a valid stream.
  if (g->num_y_points > 14) {
    b->overrun = true;
    return;
  }
  for (int i = 0; i < g->num_y_points; i++) {
    g->point_y_value[i] = f(b, 8);
    g->point_y_scaling[i] = f(b, 8);
  }
  g->chroma_scaling_from_luma = s->mono_chrome ? 0 : f(b, 1);
  if (s->mono_chrome || g->chroma_scaling_from_luma ||
      (s->subsampling_x == 1 && s->subsampling_y == 1 &&
       g->num_y_points == 0)) {
    g->num_cb_points = g->num_cr_points = 0;
  } else {
    g->num_cb_points = f(b, 4);
    if (g->num_cb_points > 10) {
      b->overrun = true;
      return;
    }
    for (int i = 0; i < g->num_cb_points; i++) {
      g->point_cb_value[i] = f(b, 8);
      g->point_cb_scaling[i] = f(b, 8);
    }
    g->num_cr_points = f(b, 4);
    if (g->num_cr_points > 10) {
      b->overrun = true;
      return;
    }
    for (int i = 0; i < g->num_cr_points; i++) {
      g->point_cr_value[i] = f(b, 8);
      g->point_cr_scaling[i] = f(b, 8);
    }
  }
  g->grain_scaling_minus_8 = f(b, 2);
  g->ar_coeff_lag = f(b, 2);
  int numPosLuma = 2 * g->ar_coeff_lag * (g->ar_coeff_lag + 1);
  int numPosChroma;
  for (int i = 0; i < 24; i++) g->ar_coeffs_y_plus_128[i] = 128;
  for (int i = 0; i < 25; i++)
    g->ar_coeffs_cb_plus_128[i] = g->ar_coeffs_cr_plus_128[i] = 128;
  if (g->num_y_points) {
    numPosChroma = numPosLuma + 1;
    for (int i = 0; i < numPosLuma; i++) g->ar_coeffs_y_plus_128[i] = f(b, 8);
  } else {
    numPosChroma = numPosLuma;
  }
  if (g->chroma_scaling_from_luma || g->num_cb_points)
    for (int i = 0; i < numPosChroma; i++)
      g->ar_coeffs_cb_plus_128[i] = f(b, 8);
  if (g->chroma_scaling_from_luma || g->num_cr_points)
    for (int i = 0; i < numPosChroma; i++)
      g->ar_coeffs_cr_plus_128[i] = f(b, 8);
  g->ar_coeff_shift_minus_6 = f(b, 2);
  g->grain_scale_shift = f(b, 2);
  if (g->num_cb_points) {
    g->cb_mult = f(b, 8);
    g->cb_luma_mult = f(b, 8);
    g->cb_offset = f(b, 9);
  }
  if (g->num_cr_points) {
    g->cr_mult = f(b, 8);
    g->cr_luma_mult = f(b, 8);
    g->cr_offset = f(b, 9);
  }
  g->overlap_flag = f(b, 1);
  g->clip_to_restricted_range = f(b, 1);
}

// 5.9.2 uncompressed_header
static int uncompressed_header(BR* b, AV1Parser* p) {
  AV1Frame* h = &p->fh;
  const AV1Seq* s = &p->seq;
  // keep inheritable state that is overwritten conditionally
  AV1Frame prevHeader = *h;
  memset(h, 0, sizeof(*h));
  int idLen = 0;
  if (s->frame_id_numbers_present_flag)
    idLen = s->additional_frame_id_length_minus_1 +
            s->delta_frame_id_length_minus_2 + 3;
  const int allFrames = 255;
  if (s->reduced_still_picture_header) {
    h->show_existing_frame = 0;
    h->frame_type = AV1_KEY_FRAME;
    h->FrameIsIntra = 1;
    h->show_frame = 1;
    h->showable_frame = 0;
  } else {
    h->show_existing_frame = f(b, 1);
    if (h->show_existing_frame) {
      h->frame_to_show_map_idx = f(b, 3);
      if (s->decoder_model_info_present_flag && !s->equal_picture_interval)
        f(b, s->frame_presentation_time_length_minus_1 + 1);
      h->refresh_frame_flags = 0;
      if (s->frame_id_numbers_present_flag) f(b, idLen);
      AV1RefSlot* r = &p->ref[h->frame_to_show_map_idx];
      h->frame_type = r->frame_type;
      if (h->frame_type == AV1_KEY_FRAME) h->refresh_frame_flags = allFrames;
      if (s->film_grain_params_present) h->film_grain = r->film_grain;
      // frame loading process (7.21) for a shown key frame
      h->UpscaledWidth = r->upscaled_width;
      h->FrameWidth = r->frame_width;
      h->FrameHeight = r->frame_height;
      h->RenderWidth = r->render_width;
      h->RenderHeight = r->render_height;
      h->MiCols = r->mi_cols;
      h->MiRows = r->mi_rows;
      h->current_frame_id = r->frame_id;
      h->order_hint = r->order_hint;
      memcpy(h->OrderHints, r->saved_order_hints, sizeof(h->OrderHints));
      memcpy(h->gm_params, r->gm_params, sizeof(h->gm_params));
      memcpy(h->loop_filter_ref_deltas, r->lf_ref_deltas,
             sizeof(h->loop_filter_ref_deltas));
      memcpy(h->loop_filter_mode_deltas, r->lf_mode_deltas,
             sizeof(h->loop_filter_mode_deltas));
      memcpy(h->FeatureEnabled, r->feature_enabled, sizeof(h->FeatureEnabled));
      memcpy(h->FeatureData, r->feature_data, sizeof(h->FeatureData));
      h->show_frame = 1;
      return b->overrun ? -1 : 0;
    }
    h->frame_type = f(b, 2);
    h->FrameIsIntra = (h->frame_type == AV1_INTRA_ONLY_FRAME ||
                       h->frame_type == AV1_KEY_FRAME);
    h->show_frame = f(b, 1);
    if (h->show_frame && s->decoder_model_info_present_flag &&
        !s->equal_picture_interval)
      f(b, s->frame_presentation_time_length_minus_1 + 1);
    if (h->show_frame)
      h->showable_frame = h->frame_type != AV1_KEY_FRAME;
    else
      h->showable_frame = f(b, 1);
    if (h->frame_type == AV1_SWITCH_FRAME ||
        (h->frame_type == AV1_KEY_FRAME && h->show_frame))
      h->error_resilient_mode = 1;
    else
      h->error_resilient_mode = f(b, 1);
  }
  if (h->frame_type == AV1_KEY_FRAME && h->show_frame) {
    for (int i = 0; i < 8; i++) {
      p->ref[i].valid = 0;
      p->ref[i].order_hint = 0;
    }
    for (int i = 0; i < 7; i++) h->OrderHints[1 + i] = 0;
  }
  h->disable_cdf_update = f(b, 1);
  if (s->seq_force_screen_content_tools == 2)
    h->allow_screen_content_tools = f(b, 1);
  else
    h->allow_screen_content_tools = s->seq_force_screen_content_tools;
  if (h->allow_screen_content_tools) {
    if (s->seq_force_integer_mv == 2)
      h->force_integer_mv = f(b, 1);
    else
      h->force_integer_mv = s->seq_force_integer_mv;
  } else {
    h->force_integer_mv = 0;
  }
  if (h->FrameIsIntra) h->force_integer_mv = 1;
  if (s->frame_id_numbers_present_flag) {
    h->current_frame_id = f(b, idLen);
    // mark_ref_frames (7.5)
    int diffLen = s->delta_frame_id_length_minus_2 + 2;
    for (int i = 0; i < 8; i++) {
      if (h->frame_type == AV1_KEY_FRAME && h->show_frame) continue;
      if (h->current_frame_id > (1 << diffLen)) {
        if (p->ref[i].frame_id > h->current_frame_id ||
            p->ref[i].frame_id < (h->current_frame_id - (1 << diffLen)))
          p->ref[i].valid = 0;
      } else {
        if (p->ref[i].frame_id > h->current_frame_id &&
            p->ref[i].frame_id <
                ((1 << idLen) + h->current_frame_id - (1 << diffLen)))
          p->ref[i].valid = 0;
      }
    }
  } else {
    h->current_frame_id = 0;
  }
  if (h->frame_type == AV1_SWITCH_FRAME)
    h->frame_size_override_flag = 1;
  else if (s->reduced_still_picture_header)
    h->frame_size_override_flag = 0;
  else
    h->frame_size_override_flag = f(b, 1);
  h->order_hint = f(b, s->OrderHintBits);
  if (h->FrameIsIntra || h->error_resilient_mode)
    h->primary_ref_frame = AV1_PRIMARY_REF_NONE;
  else
    h->primary_ref_frame = f(b, 3);
  if (s->decoder_model_info_present_flag) {
    int buffer_removal_time_present_flag = f(b, 1);
    if (buffer_removal_time_present_flag) {
      for (int opNum = 0; opNum <= s->operating_points_cnt_minus_1; opNum++) {
        if (s->decoder_model_present_for_this_op[opNum]) {
          int opPtIdc = s->operating_point_idc[opNum];
          int inTemporalLayer = (opPtIdc >> p->temporal_id) & 1;
          int inSpatialLayer = (opPtIdc >> (p->spatial_id + 8)) & 1;
          if (opPtIdc == 0 || (inTemporalLayer && inSpatialLayer))
            f(b, s->buffer_removal_time_length_minus_1 + 1);
        }
      }
    }
  }
  h->allow_high_precision_mv = 0;
  h->use_ref_frame_mvs = 0;
  h->allow_intrabc = 0;
  if (h->frame_type == AV1_SWITCH_FRAME ||
      (h->frame_type == AV1_KEY_FRAME && h->show_frame))
    h->refresh_frame_flags = allFrames;
  else
    h->refresh_frame_flags = f(b, 8);
  if (!h->FrameIsIntra || h->refresh_frame_flags != allFrames) {
    if (h->error_resilient_mode && s->enable_order_hint) {
      for (int i = 0; i < 8; i++) {
        int ref_order_hint = f(b, s->OrderHintBits);
        if (ref_order_hint != p->ref[i].order_hint || !p->ref[i].valid) {
          p->ref[i].valid = 0;
          p->ref[i].order_hint = ref_order_hint;
        }
      }
    }
  }
  if (h->FrameIsIntra) {
    frame_size(b, p);
    render_size(b, h);
    if (h->allow_screen_content_tools && h->UpscaledWidth == h->FrameWidth)
      h->allow_intrabc = f(b, 1);
  } else {
    if (!s->enable_order_hint)
      h->frame_refs_short_signaling = 0;
    else {
      h->frame_refs_short_signaling = f(b, 1);
      if (h->frame_refs_short_signaling) {
        int last_frame_idx = f(b, 3);
        int gold_frame_idx = f(b, 3);
        set_frame_refs(p, last_frame_idx, gold_frame_idx);
      }
    }
    for (int i = 0; i < 7; i++) {
      if (!h->frame_refs_short_signaling) h->ref_frame_idx[i] = f(b, 3);
      if (s->frame_id_numbers_present_flag)
        f(b, s->delta_frame_id_length_minus_2 + 2);
    }
    if (h->frame_size_override_flag && !h->error_resilient_mode)
      frame_size_with_refs(b, p);
    else {
      frame_size(b, p);
      render_size(b, h);
    }
    h->allow_high_precision_mv = h->force_integer_mv ? 0 : f(b, 1);
    h->is_filter_switchable = f(b, 1);
    h->interpolation_filter = h->is_filter_switchable ? 4 : f(b, 2);
    h->is_motion_mode_switchable = f(b, 1);
    if (h->error_resilient_mode || !s->enable_ref_frame_mvs)
      h->use_ref_frame_mvs = 0;
    else
      h->use_ref_frame_mvs = f(b, 1);
    for (int i = 0; i < 7; i++) {
      int refFrame = 1 + i;
      int hint = p->ref[h->ref_frame_idx[i]].order_hint;
      h->OrderHints[refFrame] = hint;
      h->RefFrameSignBias[refFrame] =
          s->enable_order_hint ? (get_relative_dist(s, hint, h->order_hint) > 0)
                               : 0;
    }
  }
  if (s->reduced_still_picture_header || h->disable_cdf_update)
    h->disable_frame_end_update_cdf = 1;
  else
    h->disable_frame_end_update_cdf = f(b, 1);
  int prevGmParams[8][6];
  if (h->primary_ref_frame == AV1_PRIMARY_REF_NONE) {
    setup_past_independence(h);
    memcpy(prevGmParams, h->gm_params, sizeof(prevGmParams));
  } else {
    load_previous(p, prevGmParams);
  }
  (void)prevHeader;
  if (tile_info(b, p)) return -1;
  quantization_params(b, p);
  segmentation_params(b, p);
  // delta_q_params / delta_lf_params
  h->delta_q_res = 0;
  h->delta_q_present = 0;
  if (h->base_q_idx > 0) h->delta_q_present = f(b, 1);
  if (h->delta_q_present) h->delta_q_res = f(b, 2);
  h->delta_lf_present = 0;
  h->delta_lf_res = 0;
  h->delta_lf_multi = 0;
  if (h->delta_q_present) {
    if (!h->allow_intrabc) h->delta_lf_present = f(b, 1);
    if (h->delta_lf_present) {
      h->delta_lf_res = f(b, 2);
      h->delta_lf_multi = f(b, 1);
    }
  }
  h->CodedLossless = 1;
  for (int segmentId = 0; segmentId < AV1_MAX_SEGMENTS; segmentId++) {
    int qindex = get_qindex(h, segmentId);
    int lossless = qindex == 0 && h->DeltaQYDc == 0 && h->DeltaQUAc == 0 &&
                   h->DeltaQUDc == 0 && h->DeltaQVAc == 0 && h->DeltaQVDc == 0;
    if (!lossless) h->CodedLossless = 0;
  }
  h->AllLossless = h->CodedLossless && (h->FrameWidth == h->UpscaledWidth);
  loop_filter_params(b, p);
  cdef_params(b, p);
  lr_params(b, p);
  // read_tx_mode
  if (h->CodedLossless)
    h->TxMode = 0;
  else
    h->TxMode = f(b, 1) ? 2 : 1;
  // frame_reference_mode
  h->reference_select = h->FrameIsIntra ? 0 : f(b, 1);
  skip_mode_params(b, p);
  if (h->FrameIsIntra || h->error_resilient_mode || !s->enable_warped_motion)
    h->allow_warped_motion = 0;
  else
    h->allow_warped_motion = f(b, 1);
  h->reduced_tx_set = f(b, 1);
  global_motion_params(b, h, prevGmParams);
  film_grain_params(b, p);
  return b->overrun ? -1 : 0;
}

// 7.20 reference frame update process
void av1_reference_update(AV1Parser* p, int dpb_slot) {
  AV1Frame* h = &p->fh;
  const AV1Seq* s = &p->seq;
  if (h->frame_type == AV1_INTRA_ONLY_FRAME) {
    // nothing special: refresh_frame_flags != 0xFF enforced by bitstream
    // conformance
  }
  for (int i = 0; i < 8; i++) {
    if (!((h->refresh_frame_flags >> i) & 1)) continue;
    AV1RefSlot* r = &p->ref[i];
    if (h->show_existing_frame) {
      // key frame shown via show_existing_frame: slot copies the shown frame's
      // state
      if (i == h->frame_to_show_map_idx) continue;
      *r = p->ref[h->frame_to_show_map_idx];
      continue;
    }
    r->valid = 1;
    r->frame_id = h->current_frame_id;
    r->upscaled_width = h->UpscaledWidth;
    r->frame_width = h->FrameWidth;
    r->frame_height = h->FrameHeight;
    r->render_width = h->RenderWidth;
    r->render_height = h->RenderHeight;
    r->mi_cols = h->MiCols;
    r->mi_rows = h->MiRows;
    r->frame_type = h->frame_type;
    r->order_hint = h->order_hint;
    memcpy(r->saved_order_hints, h->OrderHints, sizeof(r->saved_order_hints));
    memcpy(r->gm_params, h->gm_params, sizeof(r->gm_params));
    memcpy(r->lf_ref_deltas, h->loop_filter_ref_deltas,
           sizeof(r->lf_ref_deltas));
    memcpy(r->lf_mode_deltas, h->loop_filter_mode_deltas,
           sizeof(r->lf_mode_deltas));
    memcpy(r->feature_enabled, h->FeatureEnabled, sizeof(r->feature_enabled));
    memcpy(r->feature_data, h->FeatureData, sizeof(r->feature_data));
    r->film_grain = h->film_grain;
    r->bit_depth = s->BitDepth;
    r->subsampling_x = s->subsampling_x;
    r->subsampling_y = s->subsampling_y;
    r->dpb_slot = dpb_slot;
  }
}

// ---------------------------------------------------------------- OBU level
// (5.3)
enum {
  OBU_SEQUENCE_HEADER = 1,
  OBU_TEMPORAL_DELIMITER = 2,
  OBU_FRAME_HEADER = 3,
  OBU_TILE_GROUP = 4,
  OBU_METADATA = 5,
  OBU_FRAME = 6,
  OBU_REDUNDANT_FRAME_HEADER = 7,
  OBU_TILE_LIST = 8,
  OBU_PADDING = 15
};

void av1_parser_init(AV1Parser* p) {
  memset(p, 0, sizeof(*p));
  for (int i = 0; i < 8; i++) p->ref[i].dpb_slot = -1;
}
void av1_parser_free(AV1Parser* p) {
  free(p->tile_data);
  p->tile_data = NULL;
}

static int append_tile(AV1Parser* p, int row, int col, const uint8_t* data,
                       size_t size) {
  const int kMaxTiles = (int)(sizeof(p->tiles) / sizeof(p->tiles[0]));
  if (p->num_tiles < 0 || p->num_tiles >= kMaxTiles) return -1;
  if (row < 0 || col < 0 || row >= AV1_MAX_TILE_ROWS ||
      col >= AV1_MAX_TILE_COLS)
    return -1;
  if (!data && size) return -1;
  if (size > UINT32_MAX || p->tile_data_size > (size_t)UINT32_MAX - size)
    return -1;
  if (size > SIZE_MAX - 256) return -1;
  if (p->tile_data_size > SIZE_MAX - size - 256) return -1;
  size_t need = p->tile_data_size + size + 256;
  if (need > p->tile_data_cap) {
    if (need > SIZE_MAX / 2) return -1;
    size_t cap = need * 2;
    uint8_t* n = realloc(p->tile_data, cap);
    if (!n) return -1;
    p->tile_data = n;
    p->tile_data_cap = cap;
  }
  AV1Tile* t = &p->tiles[p->num_tiles++];
  t->row = row;
  t->col = col;
  t->offset = (uint32_t)p->tile_data_size;
  t->size = (uint32_t)size;
  memcpy(p->tile_data + p->tile_data_size, data, size);
  p->tile_data_size += size;
  return 0;
}

// 5.11.1 tile_group_obu: data points at the tile group, sz bytes
static int tile_group(AV1Parser* p, const uint8_t* data, size_t sz,
                      bool* lastTileGroup) {
  AV1Frame* h = &p->fh;
  BR b = {data, sz, 0, false};
  if (h->TileCols < 1 || h->TileRows < 1 || h->TileCols > AV1_MAX_TILE_COLS ||
      h->TileRows > AV1_MAX_TILE_ROWS)
    return -1;
  if (h->TileSizeBytes < 1 || h->TileSizeBytes > 4) return -1;
  int NumTiles = h->TileCols * h->TileRows;
  int tg_start = 0, tg_end = NumTiles - 1;
  int tile_start_and_end_present_flag = 0;
  if (NumTiles > 1) tile_start_and_end_present_flag = f(&b, 1);
  if (NumTiles > 1 && tile_start_and_end_present_flag) {
    int tileBits = h->TileColsLog2 + h->TileRowsLog2;
    if (tileBits < 1 || tileBits > 12) return -1;
    tg_start = f(&b, tileBits);
    tg_end = f(&b, tileBits);
    if (tg_start < 0 || tg_end < tg_start || tg_end >= NumTiles) return -1;
  }
  // 5.11.1: each tile group starts where the previous one ended.
  if (tg_start != p->next_tile) return -1;
  byte_alignment(&b);
  size_t pos = b.pos / 8;
  if (b.overrun || pos > sz) return -1;
  for (int TileNum = tg_start; TileNum <= tg_end; TileNum++) {
    int tileRow = TileNum / h->TileCols;
    int tileCol = TileNum % h->TileCols;
    size_t tileSize;
    if (TileNum == tg_end) {
      tileSize = sz - pos;
    } else {
      if ((size_t)h->TileSizeBytes > sz - pos) return -1;
      uint32_t t = 0;
      for (int i = 0; i < h->TileSizeBytes; i++)
        t |= (uint32_t)data[pos + i] << (8 * i);
      tileSize = t + 1;
      pos += h->TileSizeBytes;
    }
    if (!tileSize || tileSize > sz - pos) return -1;
    if (append_tile(p, tileRow, tileCol, data + pos, tileSize)) return -1;
    pos += tileSize;
  }
  p->next_tile = tg_end + 1;
  *lastTileGroup = tg_end == NumTiles - 1;
  return 0;
}

static int parse_obus(AV1Parser* p, const uint8_t* data, size_t size,
                      AV1FrameCallback cb, void* ctx) {
  size_t off = 0;
  while (off < size) {
    uint8_t hdr = data[off];
    if (hdr & 0x80) return -1;  // obu_forbidden_bit
    int obu_type = (hdr >> 3) & 15;
    int obu_extension_flag = (hdr >> 2) & 1;
    int obu_has_size_field = (hdr >> 1) & 1;
    size_t hlen = 1;
    p->temporal_id = p->spatial_id = 0;
    if (obu_extension_flag) {
      if (off + 1 >= size) return -1;
      p->temporal_id = (data[off + 1] >> 5) & 7;
      p->spatial_id = (data[off + 1] >> 3) & 3;
      hlen = 2;
    }
    uint64_t obu_size;
    if (obu_has_size_field) {
      int n = leb128(data + off + hlen, size - off - hlen, &obu_size);
      if (n < 0) return -1;
      hlen += n;
    } else {
      obu_size = size - off - hlen;
    }
    if (hlen > size - off) return -1;
    if (obu_size > size - off - hlen) return -1;
    const uint8_t* payload = data + off + hlen;
    off += hlen + obu_size;

    if (obu_type != OBU_SEQUENCE_HEADER && obu_type != OBU_TEMPORAL_DELIMITER &&
        obu_extension_flag && p->seq.OperatingPointIdc != 0) {
      int inTemporalLayer = (p->seq.OperatingPointIdc >> p->temporal_id) & 1;
      int inSpatialLayer =
          (p->seq.OperatingPointIdc >> (p->spatial_id + 8)) & 1;
      if (!inTemporalLayer || !inSpatialLayer) continue;
    }
    switch (obu_type) {
      case OBU_SEQUENCE_HEADER: {
        BR b = {payload, obu_size, 0, false};
        if (parse_sequence_header(&b, &p->seq)) return -1;
        break;
      }
      case OBU_TEMPORAL_DELIMITER:
        p->have_frame_header = false;
        break;
      case OBU_FRAME_HEADER:
      case OBU_REDUNDANT_FRAME_HEADER:
      case OBU_FRAME: {
        if (!p->seq.valid) return -1;
        if (p->have_frame_header && obu_type != OBU_FRAME)
          break;  // redundant copy
        BR b = {payload, obu_size, 0, false};
        // The header code updates the reference state as it reads; a header
        // that turns out to be invalid must leave it as it was.
        AV1RefSlot saved[AV1_NUM_REF_FRAMES];
        memcpy(saved, p->ref, sizeof(saved));
        if (uncompressed_header(&b, p)) {
          memcpy(p->ref, saved, sizeof(saved));
          return -1;
        }
        if (p->fh.show_existing_frame) {
          p->have_frame_header = false;
          if (!cb) return -1;
          int r = cb(ctx, p, AV1_PARSE_SHOW_EXISTING);
          if (r) return r;
          break;
        }
        p->have_frame_header = true;
        p->num_tiles = 0;
        p->next_tile = 0;
        p->tile_data_size = 0;
        if (obu_type == OBU_FRAME) {
          byte_alignment(&b);
          size_t hb = b.pos / 8;
          if (hb > obu_size) return -1;
          p->fh.header_bytes = hb;
          bool last = false;
          if (tile_group(p, payload + hb, obu_size - hb, &last)) return -1;
          if (last) {
            p->have_frame_header = false;
            if (!cb) return -1;
            int r = cb(ctx, p, AV1_PARSE_FRAME_READY);
            if (r) return r;
          }
        }
        break;
      }
      case OBU_TILE_GROUP: {
        if (!p->have_frame_header) return -1;
        bool last = false;
        if (tile_group(p, payload, obu_size, &last)) return -1;
        if (last) {
          p->have_frame_header = false;
          if (!cb) return -1;
          int r = cb(ctx, p, AV1_PARSE_FRAME_READY);
          if (r) return r;
        }
        break;
      }
      default:
        break;
    }
  }
  return 0;
}

int av1_parse_temporal_unit(AV1Parser* p, const uint8_t* data, size_t size,
                            AV1FrameCallback cb, void* ctx) {
  if (!p || (!data && size)) return -1;
  int r = parse_obus(p, data, size, cb, ctx);
  if (r) {
    // Never let a later tile group complete a frame whose header or tiles
    // were refused.
    p->have_frame_header = false;
    p->num_tiles = 0;
    p->next_tile = 0;
    p->tile_data_size = 0;
  }
  return r;
}

static int config_obu_noop(void* ctx, AV1Parser* parser, AV1ParseResult kind) {
  (void)ctx;
  (void)parser;
  (void)kind;
  return 0;
}

int av1_parse_config_obus(AV1Parser* p, const uint8_t* data, size_t size) {
  // av1C configOBUs are plain OBUs; reuse the TU parser with a no-op callback.
  return av1_parse_temporal_unit(p, data, size, config_obu_noop, NULL);
}
