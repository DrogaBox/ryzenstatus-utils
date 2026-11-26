#!/usr/bin/env python3
"""gen_mesa_oracle.py <mesa dir> <out.c>

Builds a small C program around Mesa's own JPEG decode command builder, so that the IB the kext
writes (kext/jpeg_cmds.hpp, buildDecodeIb) can be compared word for word with what Mesa writes.

Taken from the Mesa files as they are, by position, never retyped:
  ac_vcn_dec.c   everything from "#define RDECODE_JPEG_VER_1" to the end of ac_vcn_create_jpeg_decoder
                 (struct ac_vcn_jpeg_decoder, vcn_jpeg_build_decode_cmd, the register choice per VCN version)
  ac_vcn_dec.h   the RDECODE_*, vcnip*, COND* and TYPE* macros
  amd_family.h   enum vcn_version
  addrtypes.h    the swizzle mode enums
Only the surrounding types (the few fields the function reads) are written here.
The Mesa files are not part of this project: <mesa dir> holds copies fetched from Mesa's repository."""
import re, sys

mesa, out = sys.argv[1], sys.argv[2]
rd = lambda n: open("%s/%s" % (mesa, n)).read()

c = rd("ac_vcn_dec.c")
a = c.index("#define RDECODE_JPEG_VER_1")
b = c.index("ac_vcn_create_jpeg_decoder(const struct radeon_info")
b = c.index("\n}\n", b) + 3
body = c[a:b]
assert "vcn_jpeg_build_decode_cmd" in body and "struct ac_vcn_jpeg_decoder {" in body

h = rd("ac_vcn_dec.h")
defines = []
lines = h.split("\n")
i = 0
while i < len(lines):
    if re.match(r"#define (RDECODE_|vcnip|COND\d|TYPE\d)", lines[i]):
        j = i
        while lines[j].rstrip().endswith("\\"):
            j += 1
        defines.append("\n".join(lines[i:j + 1]))
        i = j + 1
    else:
        i += 1
assert any("vcnipUVD_JPEG_CNTL" in d for d in defines) and any("RDECODE_PKTJ" in d for d in defines)

fam = rd("amd_family.h")
m = re.search(r"enum vcn_version\s*\{.*?\};", fam, re.S)
vcn_enum = m.group(0)
addr = rd("addrtypes.h")
sw = re.search(r"typedef enum _AddrSwizzleMode\s*\{.*?\} AddrSwizzleMode;", addr, re.S).group(0)
sw3 = re.search(r"typedef enum _Addr3SwizzleMode\s*\{.*?\} Addr3SwizzleMode;", addr, re.S).group(0)

shim = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- written here: the few surrounding types and helpers the Mesa code uses ---- */
#define ROUND_DOWN_TO(v, a) ((v) / (a) * (a))
static inline uint32_t align(uint32_t v, uint32_t a) { return (v + a - 1) / a * a; }
#define CALLOC_STRUCT(T) ((struct T *)calloc(1, sizeof(struct T)))
#define FREE(p) free(p)
#define SOC15_REG_ADDR(reg) 0 /* VCN 1.0 path only, never taken here */
enum amd_gfx_level { GFX10_3 = 1, GFX11, GFX12 };
enum amd_ip_type { AMD_IP_VCN_JPEG = 1 };
enum pipe_format { PIPE_FORMAT_NV12 = 1, PIPE_FORMAT_R8_G8_B8_UNORM, PIPE_FORMAT_R8G8B8A8_UNORM,
                   PIPE_FORMAT_A8R8G8B8_UNORM, PIPE_FORMAT_YUYV };
struct radeon_surf {
   uint8_t blk_w, bpe;
   uint16_t tile_swizzle;
   struct { struct { uint64_t surf_offset; uint32_t surf_pitch; uint32_t swizzle_mode; } gfx9; } u;
};
struct ac_video_surface {
   enum pipe_format format;
   uint32_t num_planes;
   struct { struct radeon_surf *surf; uint64_t va; } planes[3];
};
struct ac_video_dec_session_param { int unused; };
struct ac_video_dec_decode_cmd {
   void *cmd_buffer;
   uint64_t bitstream_va;
   uint32_t bitstream_size;
   struct ac_video_surface decode_surface;
   struct { struct { uint32_t crop_x, crop_y, crop_width, crop_height; } mjpeg; } codec_param;
   struct { uint32_t cmd_dw; } out;
};
struct ac_video_dec {
   enum amd_ip_type ip_type;
   struct ac_video_dec_session_param param;
   uint32_t max_decode_cmd_dw;
   void (*destroy)(struct ac_video_dec *);
   int (*build_decode_cmd)(struct ac_video_dec *, struct ac_video_dec_decode_cmd *);
};
struct ac_cmdbuf { uint32_t *buf; uint32_t cdw, max_dw; };
#define ac_cmdbuf_begin(cs) struct ac_cmdbuf *__cs = (cs); uint32_t __cs_num = __cs->cdw; uint32_t *__cs_buf = __cs->buf
#define ac_cmdbuf_emit(value) do { __cs_buf[__cs_num++] = (value); } while (0)
#define ac_cmdbuf_end() do { __cs->cdw = __cs_num; assert(__cs->cdw <= __cs->max_dw); __cs = NULL; } while (0)
'''

main = r'''
/* ---- written here: one linear NV12 target on a VCN 3.0 GPU, as the kext sets it up; or, with "yuyv",
   one linear YUYV target (Mesa's surface for 4:2:2 JPEG: blk_w 2, bpe 4, pitch counted in 2-pixel blocks) ---- */
int main(int argc, char **argv)
{
   if (argc != 6 && !(argc == 7 && !strcmp(argv[6], "yuyv"))) {
      fprintf(stderr, "usage: mesa_oracle bitstreamVa bitstreamBytes targetVa pitchBytes chromaOffset [yuyv]\n"); return 2; }
   uint64_t bs_va = strtoull(argv[1], NULL, 0), dt_va = strtoull(argv[3], NULL, 0);
   uint32_t bs_size = strtoul(argv[2], NULL, 0), pitch = strtoul(argv[4], NULL, 0), chroma = strtoul(argv[5], NULL, 0);
   struct radeon_info info = { .gfx_level = GFX10_3, .vcn_ip_version = VCN_3_0_0 };
   struct ac_video_dec_session_param param = { 0 };
   struct ac_video_dec *dec = ac_vcn_create_jpeg_decoder(&info, &param);
   /* luma: 1 byte per element; chroma: 2 bytes per element, half as many per row */
   struct radeon_surf luma = { .blk_w = 1, .bpe = 1 }, uv = { .blk_w = 1, .bpe = 2 };
   luma.u.gfx9.surf_pitch = pitch;      luma.u.gfx9.swizzle_mode = ADDR_SW_LINEAR; luma.u.gfx9.surf_offset = 0;
   uv.u.gfx9.surf_pitch = pitch / 2;    uv.u.gfx9.swizzle_mode = ADDR_SW_LINEAR;   uv.u.gfx9.surf_offset = chroma;
   uint32_t words[256] = { 0 };
   struct ac_video_dec_decode_cmd cmd = { 0 };
   cmd.cmd_buffer = words;
   cmd.bitstream_va = bs_va;
   cmd.bitstream_size = bs_size;
   cmd.decode_surface.format = PIPE_FORMAT_NV12;
   cmd.decode_surface.num_planes = 2;
   cmd.decode_surface.planes[0].surf = &luma; cmd.decode_surface.planes[0].va = dt_va;
   cmd.decode_surface.planes[1].surf = &uv;   cmd.decode_surface.planes[1].va = dt_va;
   struct radeon_surf packed = { .blk_w = 2, .bpe = 4 };
   if (argc == 7) {
      packed.u.gfx9.surf_pitch = pitch / 4; packed.u.gfx9.swizzle_mode = ADDR_SW_LINEAR; packed.u.gfx9.surf_offset = 0;
      cmd.decode_surface.format = PIPE_FORMAT_YUYV;
      cmd.decode_surface.num_planes = 1;
      cmd.decode_surface.planes[0].surf = &packed;
      cmd.decode_surface.planes[1].surf = NULL; cmd.decode_surface.planes[1].va = 0;
   }
   if (dec->build_decode_cmd(dec, &cmd) != 0) return 1;
   for (uint32_t i = 0; i < cmd.out.cmd_dw; i++) printf("%08x\n", words[i]);
   return 0;
}
'''
src = ("/* Generated by tests/gen_mesa_oracle.py. The middle part is Mesa's code (MIT), copied as it is. */\n" + shim +
       "\n/* ---- from Mesa amd_family.h ---- */\n" + vcn_enum +
       "\nstruct radeon_info { enum amd_gfx_level gfx_level; enum vcn_version vcn_ip_version; };\n" +
       "\n/* ---- from Mesa addrtypes.h ---- */\n" + sw + "\n" + sw3 +
       "\n/* ---- from Mesa ac_vcn_dec.h ---- */\n" + "\n".join(defines) +
       "\n\n/* ---- from Mesa ac_vcn_dec.c ---- */\nstruct ac_video_dec *ac_vcn_create_jpeg_decoder(const struct radeon_info *info, struct ac_video_dec_session_param *param);\n" + body + main)
open(out, "w").write(src)
print("wrote %s (%d lines of Mesa code)" % (out, body.count("\n")))
