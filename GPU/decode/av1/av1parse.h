// Minimal-but-complete AV1 bitstream header parser (AV1 spec
// sections 5.3-5.12, 7.20-7.21) producing everything a stateless hardware
// decoder needs per frame.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define AV1_NUM_REF_FRAMES 8
#define AV1_REFS_PER_FRAME 7
#define AV1_PRIMARY_REF_NONE 7
#define AV1_MAX_SEGMENTS 8
#define AV1_SEG_LVL_MAX 8
#define AV1_MAX_TILE_COLS 64
#define AV1_MAX_TILE_ROWS 64

enum {
  AV1_KEY_FRAME = 0,
  AV1_INTER_FRAME = 1,
  AV1_INTRA_ONLY_FRAME = 2,
  AV1_SWITCH_FRAME = 3
};
enum { AV1_IDENTITY = 0, AV1_TRANSLATION = 1, AV1_ROTZOOM = 2, AV1_AFFINE = 3 };

typedef struct {
  int seq_profile, still_picture, reduced_still_picture_header;
  int timing_info_present_flag, decoder_model_info_present_flag,
      equal_picture_interval;
  int buffer_removal_time_length_minus_1,
      frame_presentation_time_length_minus_1;
  int operating_points_cnt_minus_1;
  int operating_point_idc[32], decoder_model_present_for_this_op[32];
  int frame_width_bits_minus_1, frame_height_bits_minus_1;
  int max_frame_width_minus_1, max_frame_height_minus_1;
  int frame_id_numbers_present_flag, delta_frame_id_length_minus_2,
      additional_frame_id_length_minus_1;
  int use_128x128_superblock, enable_filter_intra, enable_intra_edge_filter;
  int enable_interintra_compound, enable_masked_compound, enable_warped_motion,
      enable_dual_filter;
  int enable_order_hint, enable_jnt_comp, enable_ref_frame_mvs;
  int seq_choose_screen_content_tools, seq_force_screen_content_tools;
  int seq_choose_integer_mv, seq_force_integer_mv;
  int order_hint_bits_minus_1, OrderHintBits;
  int enable_superres, enable_cdef, enable_restoration;
  int high_bitdepth, twelve_bit, BitDepth, mono_chrome, NumPlanes;
  int color_description_present_flag, color_primaries, transfer_characteristics,
      matrix_coefficients;
  int color_range, subsampling_x, subsampling_y, chroma_sample_position,
      separate_uv_delta_q;
  int film_grain_params_present;
  int operatingPoint, OperatingPointIdc;
  bool valid;
} AV1Seq;

typedef struct {
  int apply_grain, grain_seed, update_grain, film_grain_params_ref_idx;
  int num_y_points, point_y_value[16], point_y_scaling[16];
  int chroma_scaling_from_luma;
  int num_cb_points, point_cb_value[16], point_cb_scaling[16];
  int num_cr_points, point_cr_value[16], point_cr_scaling[16];
  int grain_scaling_minus_8, ar_coeff_lag;
  int ar_coeffs_y_plus_128[24], ar_coeffs_cb_plus_128[25],
      ar_coeffs_cr_plus_128[25];
  int ar_coeff_shift_minus_6, grain_scale_shift;
  int cb_mult, cb_luma_mult, cb_offset, cr_mult, cr_luma_mult, cr_offset;
  int overlap_flag, clip_to_restricted_range;
} AV1FilmGrain;

typedef struct {
  // header syntax / derived values
  int show_existing_frame, frame_to_show_map_idx;
  int frame_type, FrameIsIntra, show_frame, showable_frame,
      error_resilient_mode;
  int disable_cdf_update, allow_screen_content_tools, force_integer_mv;
  int current_frame_id, frame_size_override_flag, order_hint, primary_ref_frame;
  int refresh_frame_flags;
  int frame_width_minus_1, frame_height_minus_1;
  int FrameWidth, FrameHeight, UpscaledWidth, RenderWidth, RenderHeight;
  int use_superres, SuperresDenom, MiCols, MiRows;
  int allow_intrabc, frame_refs_short_signaling,
      ref_frame_idx[AV1_REFS_PER_FRAME];
  int allow_high_precision_mv, is_filter_switchable, interpolation_filter;
  int is_motion_mode_switchable, use_ref_frame_mvs;
  int OrderHints[8], RefFrameSignBias[8];
  int disable_frame_end_update_cdf;
  // tile info
  int uniform_tile_spacing_flag, TileColsLog2, TileRowsLog2, TileCols, TileRows;
  int MiColStarts[AV1_MAX_TILE_COLS + 1], MiRowStarts[AV1_MAX_TILE_ROWS + 1];
  int context_update_tile_id, TileSizeBytes;
  // quantization
  int base_q_idx, DeltaQYDc, diff_uv_delta, DeltaQUDc, DeltaQUAc, DeltaQVDc,
      DeltaQVAc;
  int using_qmatrix, qm_y, qm_u, qm_v;
  // segmentation
  int segmentation_enabled, segmentation_update_map,
      segmentation_temporal_update, segmentation_update_data;
  int FeatureEnabled[AV1_MAX_SEGMENTS][AV1_SEG_LVL_MAX],
      FeatureData[AV1_MAX_SEGMENTS][AV1_SEG_LVL_MAX];
  int SegIdPreSkip, LastActiveSegId;
  int delta_q_present, delta_q_res, delta_lf_present, delta_lf_res,
      delta_lf_multi;
  int CodedLossless, AllLossless;
  // loop filter
  int loop_filter_level[4], loop_filter_sharpness, loop_filter_delta_enabled,
      loop_filter_delta_update;
  int loop_filter_ref_deltas[8], loop_filter_mode_deltas[2];
  // cdef
  int CdefDamping, cdef_bits, cdef_y_pri[8], cdef_y_sec[8], cdef_uv_pri[8],
      cdef_uv_sec[8];
  // loop restoration
  int FrameRestorationType[3], LoopRestorationSize[3];
  int TxMode, reference_select, skip_mode_present, allow_warped_motion,
      reduced_tx_set;
  int gm_type[8], gm_params[8][6];
  AV1FilmGrain film_grain;
  size_t header_bytes;  // size of uncompressed header in bytes (incl. trailing
                        // alignment)
} AV1Frame;

// Saved per reference slot (spec 7.20 reference frame update process).
typedef struct {
  int valid, frame_id, upscaled_width, frame_width, frame_height, render_width,
      render_height;
  int mi_cols, mi_rows, frame_type, order_hint, saved_order_hints[8];
  int gm_params[8][6], lf_ref_deltas[8], lf_mode_deltas[2];
  int feature_enabled[AV1_MAX_SEGMENTS][AV1_SEG_LVL_MAX],
      feature_data[AV1_MAX_SEGMENTS][AV1_SEG_LVL_MAX];
  AV1FilmGrain film_grain;
  int bit_depth, subsampling_x, subsampling_y;
  int dpb_slot;  // hardware DPB slot holding this frame
} AV1RefSlot;

typedef struct {
  int row, col;
  uint32_t offset,
      size;  // relative to the start of the frame's tile data buffer
} AV1Tile;

// The HDR metadata OBUs (AV1 spec 5.8.3, 5.8.4, 6.7.3, 6.7.4), as coded.
typedef struct {
  bool has_cll, has_mdcv;
  uint16_t max_cll, max_fall;  // cd/m2
  // 0.16 fixed point CIE 1931 x and y, in the order red, green, blue
  uint16_t primary_x[3], primary_y[3], white_x, white_y;
  uint32_t luminance_max;  // 24.8 fixed point cd/m2
  uint32_t luminance_min;  // 18.14 fixed point cd/m2
} AV1HdrMetadata;

typedef struct {
  AV1Seq seq;
  AV1Frame fh;
  AV1RefSlot ref[AV1_NUM_REF_FRAMES];
  bool have_frame_header;
  // tile data gathered for the current frame
  uint8_t* tile_data;
  size_t tile_data_size, tile_data_cap;
  AV1Tile tiles[AV1_MAX_TILE_COLS * AV1_MAX_TILE_ROWS];
  int num_tiles;
  int next_tile;  // first tile the next tile group must start at
  int temporal_id, spatial_id;
  // The last HDR_CLL and HDR_MDCV metadata OBU of the stream (configOBUs
  // included). Each stays until another one of its type replaces it: encoders
  // send them with the key frames, and they hold for the whole sequence. A
  // metadata OBU that is cut short is ignored and changes nothing.
  AV1HdrMetadata hdr;
} AV1Parser;

typedef enum {
  AV1_PARSE_NEED_MORE = 0,    // consumed, no complete frame yet
  AV1_PARSE_FRAME_READY = 1,  // fh + tiles describe a frame to decode
  AV1_PARSE_SHOW_EXISTING =
      2,  // fh.show_existing_frame: output ref[frame_to_show_map_idx]
  AV1_PARSE_ERROR = -1,
} AV1ParseResult;

void av1_parser_init(AV1Parser* p);
void av1_parser_free(AV1Parser* p);
// Parse one temporal unit / sample (sequence of low-overhead OBUs). Calls cb
// for every frame that is ready (decode or show-existing). Returns 0 on
// success.
typedef int (*AV1FrameCallback)(void* ctx, AV1Parser* p, AV1ParseResult kind);
int av1_parse_temporal_unit(AV1Parser* p, const uint8_t* data, size_t size,
                            AV1FrameCallback cb, void* ctx);
// Parse a raw sequence header OBU payload (e.g. from av1C configOBUs). Returns
// 0 on success.
int av1_parse_config_obus(AV1Parser* p, const uint8_t* data, size_t size);
// The HDR metadata in the byte layout CoreVideo takes (common/vcncolor.h):
// the 24-byte mastering display colour volume and the 4-byte content light
// level of the HEVC SEI messages, big-endian. Returns false, writing nothing,
// when the stream has sent no such metadata.
bool av1_hdr_mdcv(const AV1HdrMetadata* m, uint8_t out[24]);
bool av1_hdr_cll(const AV1HdrMetadata* m, uint8_t out[4]);
// After a frame was decoded into hardware slot `dpb_slot`, update reference
// state (spec 7.20).
void av1_reference_update(AV1Parser* p, int dpb_slot);
