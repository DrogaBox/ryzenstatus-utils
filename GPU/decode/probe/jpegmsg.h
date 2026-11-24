// JPEG codec block of a VCN decode message — there is none.
//
// Mesa's VCN JPEG decoder (src/gallium/drivers/radeonsi/radeon_vcn_dec_jpeg.c)
// does not build a message at all: it emits register writes on the JPEG ring
// (mmUVD_JPEG_PITCH, mmUVD_JPEG_UV_PITCH, mmUVD_JPEG_TILING_CTRL,
// mmUVD_LMI_JPEG_READ/WRITE_64BIT _BAR_LOW/HIGH, mmUVD_JPEG_RB_BASE/SIZE/WPTR,
// mmUVD_JPEG_INDEX/DATA, mmUVD_JPEG_OUTBUF_RPTR/WPTR, mmUVD_JPEG_CNTL, plus
// UVD_CTX_INDEX/DATA pairs), and Linux gives JPEG its own JRBC ring
// (jpeg_v3_0.c). ac_vcn_dec.h defines RDECODE_CODEC_JPEG 8 but no JPEG
// structure.
//
// What follows is therefore NOT a firmware message: it packs the picture
// parameters Mesa programs, in the order it programs them, so that the probe
// can put something well-formed behind codec id 8 and see whether VCN 3.0
// accepts the id on the normal decode queue at all. A "rejected" result is the
// expected one; a decode is not.
#pragma once
#include <stdint.h>

#include "jpegparse.h"

#define VCN_CODEC_JPEG 0x8u

typedef struct {
  uint32_t picture_width;   // +0
  uint32_t picture_height;  // +4
  uint32_t pitch;           // +8   luma pitch in bytes (Mesa: dt_pitch)
  uint32_t uv_pitch;        // +12
  uint32_t bsd_size;        // +16  bitstream size aligned to 128
  uint32_t luma_offset;     // +20
  uint32_t chroma_offset;   // +24
  uint32_t components;      // +28
  uint32_t sampling;        // +32  1 = 4:2:0, 2 = 4:2:2, 3 = 4:4:4
  uint32_t flags;           // +36  bit 0: no address fields (probe)
} VcnJpegParams;

_Static_assert(sizeof(VcnJpegParams) == 40, "JPEG probe block is 40 bytes");

static inline void vcn_jpeg_fill(VcnJpegParams* m, const JpegPicture* p,
                                 uint32_t pitch) {
  for (unsigned i = 0; i < sizeof(*m); i++) ((uint8_t*)m)[i] = 0;
  m->picture_width = p->au.width;
  m->picture_height = p->au.height;
  m->pitch = pitch;
  m->uv_pitch = pitch / 2;
  m->bsd_size = ((uint32_t)p->au.auSize + 127) & ~127u;
  m->components = p->components;
  m->sampling = p->sampling;
  // The target surface's GPU address is not available through this route (the
  // driver owns the texture), so the probe cannot fill the two offset fields.
  m->flags = 1;
}
