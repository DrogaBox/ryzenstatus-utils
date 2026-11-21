// decode_ivf: decodes an AV1 IVF file on the VCN, without VideoToolbox, and
// prints the MD5 of every shown frame as I420 (the format of the libaom test
// vectors). With a reference file it compares each frame.
//
// usage: decode_ivf file.ivf [expected.md5] [-v] [-o out.yuv] [-n]
//   -v  prints what the decoder session does
//   -o  also writes the frames to a file, as raw I420
//   -n  reads no pixels: for timing
//
// It reaches the GPU, so the decoder session refuses to submit anything unless
// VCNAV1_ALLOW_GPU=yes-i-know-it-can-hang is set. TU_TIMES=1 prints the time of
// every temporal unit.
//
// Exit status: 0 = every frame matched, 2 = a frame differs or is missing,
// 1 = anything else.
#include <CommonCrypto/CommonDigest.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vcnav1.h"
#include "vcndriver.h"

typedef struct {
  int frames, mismatches;
  FILE *md5, *out;
  int nohash;
  double cb_ms;
} Ctx;

static double now_ms(void) {
  static mach_timebase_info_data_t tb;
  if (!tb.denom) mach_timebase_info(&tb);
  return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

static void on_output(void* vctx, CVPixelBufferRef pb, const AV1Parser* p,
                      int64_t tag) {
  Ctx* c = vctx;
  IOSurfaceRef s = CVPixelBufferGetIOSurface(pb);
  double t0 = now_ms();
  if (c->nohash) {
    c->frames++;
    c->cb_ms += now_ms() - t0;
    return;
  }
  int w = p->fh.UpscaledWidth, h = p->fh.FrameHeight;
  if (p->fh.show_existing_frame) {
    const AV1RefSlot* r = &p->ref[p->fh.frame_to_show_map_idx];
    w = r->upscaled_width;
    h = r->frame_height;
  }
  uint8_t* row = malloc((size_t)w * 2 + 16);
  if (!row) {
    fprintf(stderr, "out of memory hashing a frame\n");
    c->frames++;
    c->mismatches++;
    return;
  }
  IOSurfaceLock(s, kIOSurfaceLockReadOnly, NULL);
  bool ten = IOSurfaceGetPixelFormat(s) == 'x420';
  int bpe = ten ? 2 : 1;
  uint8_t *y = IOSurfaceGetBaseAddressOfPlane(s, 0),
          *uv = IOSurfaceGetBaseAddressOfPlane(s, 1);
  size_t ys = IOSurfaceGetBytesPerRowOfPlane(s, 0),
         uvs = IOSurfaceGetBytesPerRowOfPlane(s, 1);
  CC_MD5_CTX m;
  CC_MD5_Init(&m);
  int cw = (w + 1) / 2, ch = (h + 1) / 2;
  for (int r = 0; r < h; r++) {
    if (ten) {  // P010 -> little-endian 16-bit samples (value in low 10 bits)
      uint16_t *src = (uint16_t*)(y + r * ys), *dst = (uint16_t*)row;
      for (int i = 0; i < w; i++) dst[i] = src[i] >> 6;
      CC_MD5_Update(&m, row, w * 2);
      if (c->out) fwrite(row, 2, w, c->out);
    } else {
      CC_MD5_Update(&m, y + r * ys, w);
      if (c->out) fwrite(y + r * ys, 1, w, c->out);
    }
  }
  for (int pl = 0; pl < 2; pl++) {
    for (int r = 0; r < ch; r++) {
      if (ten) {
        uint16_t *src = (uint16_t*)(uv + r * uvs), *dst = (uint16_t*)row;
        for (int i = 0; i < cw; i++) dst[i] = src[2 * i + pl] >> 6;
      } else {
        for (int i = 0; i < cw; i++) row[i] = uv[r * uvs + 2 * i + pl];
      }
      CC_MD5_Update(&m, row, cw * bpe);
      if (c->out) fwrite(row, bpe, cw, c->out);
    }
  }
  free(row);
  IOSurfaceUnlock(s, kIOSurfaceLockReadOnly, NULL);
  uint8_t dg[16];
  CC_MD5_Final(dg, &m);
  char hex[33];
  for (int i = 0; i < 16; i++) snprintf(hex + 2 * i, 3, "%02x", dg[i]);
  c->frames++;
  char expect[64] = "";
  if (c->md5) {
    char line[512];
    if (fgets(line, sizeof(line), c->md5)) sscanf(line, "%32s", expect);
  }
  bool ok = !c->md5 || !strcmp(expect, hex);
  if (!ok) c->mismatches++;
  printf("frame %3d %dx%d %s%s%s\n", c->frames, w, h, hex,
         c->md5 ? (ok ? "  OK" : "  MISMATCH expected ") : "",
         ok ? "" : (expect[0] ? expect : "(reference ended)"));
  c->cb_ms += now_ms() - t0;
}

// Reference lines that no decoded frame used up.
static int references_left(FILE* md5) {
  char line[512], word[64];
  int n = 0;
  while (fgets(line, sizeof(line), md5))
    if (sscanf(line, "%63s", word) == 1) n++;
  return n;
}

static int usage(void) {
  fprintf(stderr,
          "usage: decode_ivf file.ivf [expected.md5] [-v] [-o out.yuv] [-n]\n"
          "Reaches the GPU only with "
          "VCNAV1_ALLOW_GPU=yes-i-know-it-can-hang.\n");
  return 1;
}

int main(int argc, char** argv) {
  const char *path = NULL, *md5 = NULL, *outp = NULL;
  FILE* fp = NULL;
  VcnAV1* d = NULL;
  Ctx c = {0};
  uint8_t* buf = NULL;
  int nohash = 0, exit_code = 1, n = 0;
  double t_start = 0, worst = 0;

  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "-v")) {
      vcnav1_debug = 1;
    } else if (!strcmp(argv[i], "-o")) {
      if (++i >= argc) {
        fprintf(stderr, "-o requires an output path\n");
        return 1;
      }
      outp = argv[i];
    } else if (!strcmp(argv[i], "-n")) {
      nohash = 1;
    } else if (argv[i][0] == '-') {
      return usage();
    } else if (!path) {
      path = argv[i];
    } else if (!md5) {
      md5 = argv[i];
    } else {
      return usage();
    }
  }
  if (!path) return usage();

  fp = fopen(path, "rb");
  if (!fp) {
    perror(path);
    return 1;
  }
  uint8_t hdr[32];
  if (fread(hdr, 1, sizeof(hdr), fp) != sizeof(hdr) || memcmp(hdr, "DKIF", 4)) {
    fprintf(stderr, "not IVF\n");
    goto done;
  }

  int w = hdr[12] | hdr[13] << 8, h = hdr[14] | hdr[15] << 8;
  char err[256] = {0};
  d = vcnav1_create(w > 0 ? (w < 4096 ? 4096 : w) : 4096,
                    h > 0 ? (h < 2304 ? 2304 : h) : 2304, err, sizeof(err));
  if (!d) {
    fprintf(stderr, "create: %s\n", err);
    goto done;
  }

  c.nohash = nohash;
  if (md5) {
    c.md5 = fopen(md5, "r");
    if (!c.md5) {
      perror(md5);
      goto done;
    }
  }
  if (outp) {
    c.out = fopen(outp, "wb");
    if (!c.out) {
      perror(outp);
      goto done;
    }
  }

  uint8_t fh[12];
  size_t header_read = 0;
  while ((header_read = fread(fh, 1, sizeof(fh), fp)) == sizeof(fh)) {
    uint32_t sz = fh[0] | fh[1] << 8 | fh[2] << 16 | (uint32_t)fh[3] << 24;
    // The largest temporal unit the decoder session takes (its BS_SIZE). An
    // empty one is reported as a damaged file.
    enum { kMaxTuBytes = 0x1800000u };
    if (!sz || sz > kMaxTuBytes) {
      fprintf(stderr, "invalid frame size %u at TU %d\n", sz, n);
      goto done;
    }
    buf = malloc((size_t)sz);
    if (!buf) {
      fprintf(stderr, "out of memory reading TU %d (%u bytes)\n", n, sz);
      goto done;
    }
    if (fread(buf, 1, (size_t)sz, fp) != (size_t)sz) {
      fprintf(stderr, "truncated frame at TU %d\n", n);
      goto done;
    }

    double cb0 = c.cb_ms, t0 = now_ms();
    if (!t_start) t_start = t0;
    int decode_rc = vcnav1_decode(d, buf, sz, n++, on_output, &c);
    double dt = now_ms() - t0 - (c.cb_ms - cb0);
    if (getenv("TU_TIMES"))
      fprintf(stderr, "tu %d %u bytes %.2f ms\n", n - 1, sz, dt);
    if (n > 1 && dt > worst) worst = dt;
    free(buf);
    buf = NULL;
    if (decode_rc) {
      fprintf(stderr, "decode error at TU %d: %s\n", n - 1,
              vcnav1_last_error(d));
      goto done;
    }
  }
  if (ferror(fp) || header_read) {
    fprintf(stderr, "error reading %s: the file ends inside a frame header\n",
            path);
    goto done;
  }

  // A decoder that shows fewer frames than the reference lists must not pass.
  int missing = c.md5 && !nohash ? references_left(c.md5) : 0;
  if (missing)
    printf("%d reference frame(s) were never decoded  MISSING\n", missing);
  double total = t_start ? now_ms() - t_start : 0;
  double dec = total - c.cb_ms;
  printf("%s: %d frames, %d mismatches\n", path, c.frames,
         c.mismatches + missing);
  printf(
      "timing: %.1f ms decode-only (%.1f fps), worst TU %.2f ms, %.1f ms in "
      "output callback\n",
      dec, dec > 0 ? c.frames * 1000.0 / dec : 0.0, worst, c.cb_ms);
  exit_code = c.mismatches || missing ? 2 : 0;

done:
  free(buf);
  vcnav1_destroy(d);
  // A stuck session is closed on a background queue: wait for it, so its
  // log lines are there before the program ends, but not for ever.
  if (!vcn_teardown_drain(30000)) {
    fprintf(stderr,
            "the stuck session was still closing after 30 s: the driver is "
            "waiting for the GPU; exiting without it\n");
    exit_code = 1;
  }
  if (c.out) fclose(c.out);
  if (c.md5) fclose(c.md5);
  if (fp) fclose(fp);
  return exit_code;
}
