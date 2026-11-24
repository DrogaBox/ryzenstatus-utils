// vcncodecprobe <mpeg2|vc1|mpeg4|jpeg|vp9> <input file> <out.yuv>
//
// Parses one intra picture, packs the codec block, and runs it through the
// AV1 VCN context. Without VCNPROBE_ALLOW_GPU=yes-i-know-it-can-hang nothing is
// submitted: the create message, the patched codec id, the index table and the
// codec block are printed and the program exits 0. With it, one command is
// scheduled and the decoded NV12 frame is written.
//
// The failure modes are the probe's result: "accepted" is a command that
// finishes with firmware result 0 and a frame that is not blank; "rejected" is
// a firmware error or a command still running when the wait times out.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "jpegmsg.h"
#include "jpegparse.h"
#include "mpeg2msg.h"
#include "mpeg2parse.h"
#include "mpeg4msg.h"
#include "mpeg4parse.h"
#include "vc1msg.h"
#include "vc1parse.h"
#include "vcnprobe.h"
#include "vp9fill.h"
#include "vp9parse.h"

typedef struct {
  const uint8_t* au;
  size_t size;
  int got;
} Vp9Capture;

// Keeps the first coded frame of the IVF chunk (the control is one intra
// frame; a superframe's later frames are not needed).
static int vp9_capture(void* ctx, VP9Parser* p, VP9ParseResult kind,
                       const uint8_t* d, size_t n) {
  (void)p;
  Vp9Capture* c = ctx;
  if (kind != VP9_PARSE_DECODE || c->got) return 0;
  c->au = d;
  c->size = n;
  c->got = 1;
  return 0;
}

static uint8_t* read_file(const char* path, size_t* size) {
  FILE* f = fopen(path, "rb");
  if (!f) return NULL;
  if (fseek(f, 0, SEEK_END)) {
    fclose(f);
    return NULL;
  }
  long n = ftell(f);
  if (n <= 0 || fseek(f, 0, SEEK_SET)) {
    fclose(f);
    return NULL;
  }
  uint8_t* p = malloc((size_t)n);
  if (!p || fread(p, 1, (size_t)n, f) != (size_t)n) {
    free(p);
    fclose(f);
    return NULL;
  }
  fclose(f);
  *size = (size_t)n;
  return p;
}

// The parsers default to the sequence header + picture chunk (what Mesa gives
// the VLD engine); VCNPROBE_PIC_AU=1 sends the picture header only, the
// behaviour every earlier batch used.
static int pic_au_only(void) {
  const char* v = getenv("VCNPROBE_PIC_AU");
  return v && atoi(v);
}

int main(int argc, char** argv) {
  setvbuf(stdout, NULL, _IONBF, 0);
  setvbuf(stderr, NULL, _IONBF, 0);
  if (argc != 4) {
    fprintf(stderr,
            "usage: %s <mpeg2|vc1|mpeg4|jpeg|vp9> <input file> <out.yuv>\n"
            "  dry run unless VCNPROBE_ALLOW_GPU=yes-i-know-it-can-hang\n",
            argv[0]);
    return 2;
  }
  const char* codec = argv[1];
  const char* gpuEnv = getenv("VCNPROBE_ALLOW_GPU");
  int gpu = gpuEnv && !strcmp(gpuEnv, "yes-i-know-it-can-hang");
  printf("%s mode\n", gpu ? "GPU" : "dry-run");
  if (gpu) {
    printf("WARNING: the GPU path is enabled. A wrong message can hang the "
           "video engine until reboot.\n");
    // JPEG goes last: Mesa programs it through registers and a separate ring,
    // so the message built here is a guess, and a rejected guess is the one
    // most likely to leave the engine in a bad state.
    if (!strcmp(codec, "jpeg"))
      printf("note: JPEG last, as the batch asks\n");
  }

  size_t size = 0;
  uint8_t* data = read_file(argv[2], &size);
  if (!data) {
    fprintf(stderr, "cannot read %s\n", argv[2]);
    return 1;
  }
  char err[256] = {0};
  ProbeJob job;
  memset(&job, 0, sizeof(job));
  VcnMpeg2Msg m2;
  VcnVc1Msg vc1;
  VcnMpeg4Msg m4;
  VcnJpegParams jp;
  VcnMsgVP9 vm;
  VP9Parser vp9;

  if (!strcmp(codec, "mpeg2")) {
    Mpeg2Picture p;
    if (mpeg2_parse(data, size, &p, err, sizeof(err))) {
      fprintf(stderr, "mpeg2: %s\n", err);
      free(data);
      return 1;
    }
    printf("MPEG-2 %ux%u ivop=%d structure=%u f_code=%ux%u intra_dc=%u "
           "frame_pred_dct=%u q_scale=%u\n",
           p.au.width, p.au.height, p.picture_coding_type, p.picture_structure,
           p.f_code[0][0], p.f_code[0][1], p.intra_dc_precision,
           p.frame_pred_frame_dct, p.q_scale_type);
    vcn_mpeg2_fill(&m2, &p);
    // Variant 6: the one field-level difference from Mesa's get_mpeg2_msg
    // (radeon_vcn_dec.c:1690-1725): Mesa sends f_code+1, refs 0 (its
    // get_ref_pic_idx fallback for a NULL reference) and P&L 0, while the
    // probe sends the stream's f_code, 0x7f and the stream's P&L.
    const char* var = getenv("VCNPROBE_VARIANT");
    // Variant 10: the MPEG-2 block exactly as Mesa 26.3 sent it on Linux for
    // this clip (capture b31/msg-mpeg2.txt): refs 0, P&L 0, f_code as in the
    // stream, both quantiser matrices loaded (the stream's, or the defaults
    // in zigzag order when the stream has none).
    if (var && (atoi(var) >= 10)) {
      vcn_mpeg2_mesa(&m2, &p);
      printf("variant 10: MPEG-2 block as Mesa (refs 0, P&L 0, matrices "
             "loaded%s)\n", p.has_intra_matrix || p.has_nonintra_matrix
                                 ? ", from the stream" : ", defaults");
    }
    if (var && atoi(var) == 6) {
      m2.profile_and_level_indication = 0;
      m2.forward_ref_pic_idx = 0;
      m2.backward_ref_pic_idx = 0;
      for (int a = 0; a < 2; a++)
        for (int b = 0; b < 2; b++) m2.f_code[a][b]++;
      printf("variant 6: MPEG-2 f_code+1, refs 0, P&L 0 (Mesa get_mpeg2_msg)\n");
    }
    job.codecId = VCN_CODEC_MPEG2;
    job.messageId = VCN_MESSAGE_MPEG2_VLD;
    job.block = &m2;
    job.blockSize = sizeof(m2);
    job.width = p.au.width;
    job.height = p.au.height;
    int picOnly = pic_au_only();
    job.bitstream = picOnly ? p.picAu.au : p.au.au;
    job.bitstreamSize = picOnly ? p.picAu.auSize : p.au.auSize;
    const char* what = picOnly ? "picture header only (VCNPROBE_PIC_AU=1)"
                               : "sequence header to picture end";
    if (var && (atoi(var) >= 10)) {
      // Mesa hands the VCN only the slices: the buffer starts at the first
      // slice start code (00 00 01 01..AF) and has no sequence or picture
      // header (capture b33/msg-mpeg2.txt: head 00 00 01 01, 25894 bytes).
      const uint8_t* s = p.picAu.au;
      const uint8_t* end = p.picAu.au + p.picAu.auSize;
      for (const uint8_t* q = s + 4; q + 3 < end; q++)
        if (!q[0] && !q[1] && q[2] == 1 && q[3] >= 0x01 && q[3] <= 0xAF) {
          job.bitstream = q;
          job.bitstreamSize = (size_t)(end - q);
          what = "slices only, as Mesa (variants 10/11)";
          break;
        }
    }
    printf("bitstream: %s (%zu bytes)\n", what, job.bitstreamSize);
  } else if (!strcmp(codec, "vc1")) {
    Vc1Picture p;
    if (vc1_parse(data, size, &p, err, sizeof(err))) {
      fprintf(stderr, "vc1: %s\n", err);
      free(data);
      return 1;
    }
    printf("VC-1 %ux%u profile=%u level=%u structure=%u interlace=%u "
           "postproc=%u pulldown=%u tfcntr=%u finterp=%u psf=%u\n",
           p.au.width, p.au.height, p.profile, p.level, p.pic_structure,
           p.interlace, p.postprocflag, p.pulldown, p.tfcntrflag,
           p.finterpflag, p.psf);
    vcn_vc1_fill(&vc1, &p);
    const char* v1var = getenv("VCNPROBE_VARIANT");
    int vc1Mesa = v1var && (atoi(v1var) >= 10);
    if (vc1Mesa) {
      // Variant 10: the VC-1 block as Mesa 26.3 sent it on Linux (capture
      // b31/msg-vc1.txt): Mesa's profile numbering (advanced = 2, main = 1,
      // simple = 0) with its fixed levels (4/2/1), pic_structure 0 (frame
      // coding mode progressive), refs 0, and 7 in pps bits 16..18 (the
      // value ffmpeg's VA-API code passes for the advanced profile).
      if (p.profile == 3) {
        vc1.profile = 2;
        vc1.level = 4;
        vc1.pps_info_flags |= 7u << 16;
      } else {
        vc1.profile = p.profile == 1 ? 1 : 0;
        vc1.level = p.profile == 1 ? 2 : 1;
      }
      vc1.pic_structure = 0;
      vc1.forward_ref_idx = 0;
      vc1.backward_ref_idx = 0;
      printf("variant 10: VC-1 block as Mesa (profile %u level %u, refs 0)\n",
             vc1.profile, vc1.level);
    }
    printf("VC-1 block sps_info_flags=0x%x pps_info_flags=0x%x\n",
           vc1.sps_info_flags, vc1.pps_info_flags);
    job.codecId = VCN_CODEC_VC1;
    job.messageId = VCN_MESSAGE_VC1;
    job.block = &vc1;
    job.blockSize = sizeof(vc1);
    job.width = p.au.width;
    job.height = p.au.height;
    int picOnly = pic_au_only();
    job.bitstream = picOnly ? p.picAu.au : p.au.au;
    job.bitstreamSize = picOnly ? p.picAu.auSize : p.au.auSize;
    if (vc1Mesa) {
      // Like ffmpeg's VC-1 parser on Linux (bsd_size 0x1100 there): the frame
      // ends at the next start code of any kind, so cut there.
      // and Mesa's buffer starts at the frame start code (00 00 01 0D), with no
      // sequence header or entry point (capture b33/msg-vc1.txt).
      const uint8_t* fs = p.picAu.au;
      const uint8_t* end = p.picAu.au + p.picAu.auSize;
      job.bitstream = fs;
      job.bitstreamSize = (size_t)(end - fs);
      for (const uint8_t* q = fs + 4; q + 3 < end; q++)
        if (!q[0] && !q[1] && q[2] == 1) {
          job.bitstreamSize = (size_t)(q - job.bitstream);
          break;
        }
    }
    printf("bitstream: %s (%zu bytes)\n",
           vc1Mesa   ? "frame only, as Mesa (variants 10/11)"
           : picOnly ? "frame header only (VCNPROBE_PIC_AU=1)"
                     : "sequence header + entry point to picture end",
           job.bitstreamSize);
    job.vc1Simple = p.profile < 2;  // Mesa: sizes in 16-sample units
  } else if (!strcmp(codec, "mpeg4")) {
    Mpeg4Picture p;
    if (mpeg4_parse(data, size, &p, err, sizeof(err))) {
      fprintf(stderr, "mpeg4: %s\n", err);
      free(data);
      return 1;
    }
    printf("MPEG-4 %ux%u verid=%u shape=%u vop=%u quant=%u res=%u "
           "quant_type=%u quarter_sample=%u\n",
           p.au.width, p.au.height, p.verid, p.shape, p.vop_coding_type,
           p.vop_quant, p.vop_time_increment_resolution, p.quant_type,
           p.quarter_sample);
    vcn_mpeg4_fill(&m4, &p);
    job.codecId = VCN_CODEC_MPEG4;
    job.messageId = VCN_MESSAGE_MPEG4_ASP_VLD;
    job.block = &m4;
    job.blockSize = sizeof(m4);
    job.width = p.au.width;
    job.height = p.au.height;
    int picOnly = pic_au_only();
    job.bitstream = picOnly ? p.picAu.au : p.au.au;
    job.bitstreamSize = picOnly ? p.picAu.auSize : p.au.auSize;
    printf("bitstream: %s (%zu bytes)\n",
           picOnly ? "VOP only (VCNPROBE_PIC_AU=1)" : "VOL header to VOP end",
           job.bitstreamSize);
  } else if (!strcmp(codec, "jpeg")) {
    JpegPicture p;
    if (jpeg_parse(data, size, &p, err, sizeof(err))) {
      fprintf(stderr, "jpeg: %s\n", err);
      free(data);
      return 1;
    }
    printf("JPEG %ux%u components=%u sampling=%u restart=%u\n", p.au.width,
           p.au.height, p.components, p.sampling, p.restartInterval);
    vcn_jpeg_fill(&jp, &p, (uint32_t)((p.au.width + 255) & ~255u));
    job.codecId = VCN_CODEC_JPEG;
    // No message id: VCN JPEG has no message block (see jpegmsg.h). 0 is not a
    // valid entry, so the dump shows the block without claiming an id.
    job.messageId = 0;
    job.block = &jp;
    job.blockSize = sizeof(jp);
    job.width = p.au.width;
    job.height = p.au.height;
    job.bitstream = p.au.au;
    job.bitstreamSize = p.au.auSize;
  } else if (!strcmp(codec, "vp9")) {
    // IVF: a 32-byte file header, then a 12-byte little-endian frame header
    // (size, timestamp) before each frame. The control is the first frame of a
    // -g 1 sample, so one chunk is all it needs.
    if (size < 44 || memcmp(data, "DKIF", 4)) {
      fprintf(stderr, "vp9: not an IVF file\n");
      free(data);
      return 1;
    }
    uint32_t fsz = (uint32_t)data[32] | ((uint32_t)data[33] << 8) |
                   ((uint32_t)data[34] << 16) | ((uint32_t)data[35] << 24);
    if (!fsz || 44 + (size_t)fsz > size) {
      fprintf(stderr, "vp9: bad IVF frame size %u\n", fsz);
      free(data);
      return 1;
    }
    vp9_parser_init(&vp9);
    Vp9Capture cap = {0};
    if (vp9_parse_chunk(&vp9, data + 44, fsz, vp9_capture, &cap) || !cap.got) {
      fprintf(stderr, "vp9: %s\n", vp9.err[0] ? vp9.err : "no frame");
      free(data);
      return 1;
    }
    if (!vp9_frame_supported(&vp9)) {
      fprintf(stderr, "vp9: %s\n",
              vp9.err[0] ? vp9.err : "profile/depth not supported");
      free(data);
      return 1;
    }
    printf("VP9 %ux%u profile=%d depth=%d frame_type=%d intra_only=%d "
           "show=%d tiles=%d+%d au=%zu bytes\n",
           vp9.fh.width, vp9.fh.height, vp9.fh.profile, vp9.fh.bit_depth,
           vp9.fh.frame_type, vp9.fh.intra_only, vp9.fh.show_frame,
           vp9.fh.log2_tile_cols, vp9.fh.log2_tile_rows, cap.size);
    vp9probe_fill_message(&vm, &vp9, 0);
    job.codecId = VCN_CODEC_VP9;
    job.messageId = VCN_MESSAGE_VP9;
    job.block = &vm;
    job.blockSize = sizeof(vm);
    job.width = vp9.fh.width;
    job.height = vp9.fh.height;
    job.bitstream = cap.au;
    job.bitstreamSize = cap.size;
    job.profile = (uint32_t)vp9.fh.profile;
    job.depth = (uint32_t)vp9.fh.bit_depth;
    job.vp9 = &vp9;
  } else {
    fprintf(stderr, "unknown codec %s\n", codec);
    free(data);
    return 2;
  }

  printf("access unit %zu bytes at %p, codec id 0x%x, message 0x%x, block %u "
         "bytes\n",
         job.bitstreamSize, (const void*)job.bitstream, job.codecId,
         job.messageId, job.blockSize);
  int rc = vcnprobe_run(&job, argv[3], gpu, err, sizeof(err));
  free(data);
  if (rc) {
    fprintf(stderr, "vcnprobe: %s\n", err);
    return 1;
  }
  return 0;
}
