// decode_vp9: decodes a VP9 file (IVF or WebM) on the VCN, without
// VideoToolbox, and prints the MD5 of every shown frame as I420. With a
// reference in the format of FFmpeg's FATE suite (tests/ref/fate/vp9-*) it
// compares each frame.
//
// usage: decode_vp9 file [reference] [-v] [-n frames] [-b] [-png dir every]
//   -v    prints what the decoder session does
//   -n    stops after that many container frames
//   -b    benchmark: reads no pixels, prints decode speed and the memory
//         footprint of the process
//   -png  writes every Nth shown frame as a half size PNG into dir, for files
//         that have no reference
//
// It reaches the GPU, so the decoder session refuses to start unless
// VCNVP9_SESSION=vp9 and VCNVP9_ALLOW_GPU=yes-i-know-it-can-hang are both set.
// A debugger opens the same gate: only run it under one through
// tools/driver/dryrun_vp9.py, which stops the process before the kernel.
//
// Exit status: 0 = every frame matched, 2 = a frame differs or is missing,
// 1 = anything else.
#include <CommonCrypto/CommonDigest.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <IOSurface/IOSurfaceRef.h>
#include <ImageIO/ImageIO.h>
#include <errno.h>
#include <limits.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "container.h"
#include "vcndriver.h"
#include "vcnvp9.h"

typedef struct {
  int frames, mismatches, png_every;
  bool bench;
  const char* png_dir;
  FILE* ref;
} Ctx;

static double now_ms(void) {
  return clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e6;
}

static double footprint_mb(void) {
  task_vm_info_data_t info;
  mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
  if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &n) !=
      KERN_SUCCESS)
    return -1;
  return info.phys_footprint / 1048576.0;
}

static int cmp_float(const void* a, const void* b) {
  float x = *(const float*)a, y = *(const float*)b;
  return x < y ? -1 : x > y;
}

// Next frame of a reference, in either format: FFmpeg's FATE framemd5 ("stream,
// dts, pts, duration, size, md5": the md5 after the last comma) or libvpx's
// .md5 file ("md5  name.i420": the md5 first). Use libvpx's for clips that
// change size: FATE's vp9-05-resize hashes the frames scaled back to 352x288
// (its command line has -s 352x288), not the decoded ones.
static bool next_ref(Ctx* c, char out[33]) {
  char line[512];
  while (c->ref && fgets(line, sizeof(line), c->ref)) {
    if (line[0] == '#') continue;
    char* h = strrchr(line, ',');
    if (h) return sscanf(h + 1, " %32s", out) == 1;
    if (sscanf(line, "%32[0-9a-f]", out) == 1 && strlen(out) == 32) return true;
  }
  return false;
}

// Half size, nearest neighbour, BT.709 limited range. Good enough to see
// corruption by eye.
static void write_png(const char* dir, int number, IOSurfaceRef s, uint32_t w,
                      uint32_t h) {
  bool ten = IOSurfaceGetPixelFormat(s) == 'x420';
  uint8_t *y = IOSurfaceGetBaseAddressOfPlane(s, 0),
          *uv = IOSurfaceGetBaseAddressOfPlane(s, 1);
  size_t ys = IOSurfaceGetBytesPerRowOfPlane(s, 0),
         uvs = IOSurfaceGetBytesPerRowOfPlane(s, 1);
  uint32_t ow = w / 2, oh = h / 2;
  if (!ow || !oh) return;
  uint8_t* rgb = malloc((size_t)ow * oh * 4);
  if (!rgb) return;
  for (uint32_t r = 0; r < oh; r++)
    for (uint32_t i = 0; i < ow; i++) {
      int Y, U, V;
      if (ten) {
        const uint16_t* uvp = (const uint16_t*)(uv + r * uvs) + 2 * i;
        Y = ((const uint16_t*)(y + 2 * r * ys))[2 * i] >> 8;
        U = uvp[0] >> 8;
        V = uvp[1] >> 8;
      } else {
        const uint8_t* uvp = uv + r * uvs + 2 * i;
        Y = y[2 * r * ys + 2 * i];
        U = uvp[0];
        V = uvp[1];
      }
      float yy = 1.164f * (Y - 16), u = U - 128, v = V - 128;
      float rr = yy + 1.793f * v, gg = yy - 0.213f * u - 0.533f * v,
            bb = yy + 2.112f * u;
      uint8_t* o = rgb + ((size_t)r * ow + i) * 4;
      o[0] = rr < 0 ? 0 : rr > 255 ? 255 : (uint8_t)rr;
      o[1] = gg < 0 ? 0 : gg > 255 ? 255 : (uint8_t)gg;
      o[2] = bb < 0 ? 0 : bb > 255 ? 255 : (uint8_t)bb;
      o[3] = 255;
    }
  char path[1024];
  snprintf(path, sizeof(path), "%s/frame%06d.png", dir, number);
  CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef cg = CGBitmapContextCreate(rgb, ow, oh, 8, (size_t)ow * 4, cs,
                                          kCGImageAlphaNoneSkipLast);
  CGImageRef img = cg ? CGBitmapContextCreateImage(cg) : NULL;
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(
      NULL, (const UInt8*)path, (CFIndex)strlen(path), false);
  CGImageDestinationRef dst =
      url && img
          ? CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, NULL)
          : NULL;
  if (dst) {
    CGImageDestinationAddImage(dst, img, NULL);
    if (!CGImageDestinationFinalize(dst))
      fprintf(stderr, "could not write %s\n", path);
    CFRelease(dst);
  } else {
    fprintf(stderr, "could not write %s\n", path);
  }
  if (url) CFRelease(url);
  CGImageRelease(img);
  CGContextRelease(cg);
  CGColorSpaceRelease(cs);
  free(rgb);
}

static void on_output(void* vctx, CVPixelBufferRef pb, const VP9Parser* p,
                      uint32_t w, uint32_t h, int64_t tag) {
  (void)p;
  (void)tag;
  Ctx* c = vctx;
  IOSurfaceRef s = CVPixelBufferGetIOSurface(pb);
  if (c->bench) {
    c->frames++;
    return;
  }
  if (c->png_dir) {
    IOSurfaceLock(s, kIOSurfaceLockReadOnly, NULL);
    if (c->frames % c->png_every == 0)
      write_png(c->png_dir, c->frames + 1, s, w, h);
    IOSurfaceUnlock(s, kIOSurfaceLockReadOnly, NULL);
    c->frames++;
    return;
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
  uint8_t *y = IOSurfaceGetBaseAddressOfPlane(s, 0),
          *uv = IOSurfaceGetBaseAddressOfPlane(s, 1);
  size_t ys = IOSurfaceGetBytesPerRowOfPlane(s, 0),
         uvs = IOSurfaceGetBytesPerRowOfPlane(s, 1);
  CC_MD5_CTX m;
  CC_MD5_Init(&m);
  uint32_t cw = (w + 1) / 2, ch = (h + 1) / 2;
  for (uint32_t r = 0; r < h; r++) {
    if (ten) {
      uint16_t *src = (uint16_t*)(y + r * ys), *dst = (uint16_t*)row;
      for (uint32_t i = 0; i < w; i++) dst[i] = src[i] >> 6;
      CC_MD5_Update(&m, row, w * 2);
    } else {
      CC_MD5_Update(&m, y + r * ys, w);
    }
  }
  for (int pl = 0; pl < 2; pl++)
    for (uint32_t r = 0; r < ch; r++) {
      if (ten) {
        uint16_t *src = (uint16_t*)(uv + r * uvs), *dst = (uint16_t*)row;
        for (uint32_t i = 0; i < cw; i++) dst[i] = src[2 * i + pl] >> 6;
        CC_MD5_Update(&m, row, cw * 2);
      } else {
        for (uint32_t i = 0; i < cw; i++) row[i] = uv[r * uvs + 2 * i + pl];
        CC_MD5_Update(&m, row, cw);
      }
    }
  free(row);
  IOSurfaceUnlock(s, kIOSurfaceLockReadOnly, NULL);
  uint8_t dg[16];
  CC_MD5_Final(dg, &m);
  char hex[33], expect[33] = "";
  for (int i = 0; i < 16; i++) snprintf(hex + 2 * i, 3, "%02x", dg[i]);
  c->frames++;
  // With a reference, a frame the reference does not list is a mismatch too:
  // otherwise a wrong or empty reference file would pass.
  bool have = next_ref(c, expect);
  bool ok = c->ref ? have && !strcmp(expect, hex) : true;
  if (!ok) c->mismatches++;
  printf("frame %3d %ux%u %s%s%s\n", c->frames, w, h, hex,
         c->ref ? (ok ? "  OK" : "  MISMATCH expected ") : "",
         ok ? "" : (have ? expect : "(reference ended)"));
}

static int parse_int_arg(const char* text, int minimum, int* out) {
  if (!text || !*text || !out) return -1;
  char* end = NULL;
  errno = 0;
  long value = strtol(text, &end, 10);
  if (errno || !end || *end || value < minimum || value > INT_MAX) return -1;
  *out = (int)value;
  return 0;
}

static int usage(void) {
  fprintf(stderr,
          "usage: decode_vp9 file [reference] [-v] [-n frames] [-b] [-png "
          "dir every]\n"
          "Reaches the GPU only with VCNVP9_SESSION=vp9 and "
          "VCNVP9_ALLOW_GPU=yes-i-know-it-can-hang.\n");
  return 1;
}

int main(int argc, char** argv) {
  const char *path = NULL, *ref = NULL;
  int limit = 0, exit_code = 1;
  Ctx c = {0};
  Container f = {0};
  VcnVP9* d = NULL;
  float* times = NULL;

  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "-v")) {
      vcnvp9_debug = 1;
    } else if (!strcmp(argv[i], "-b")) {
      c.bench = true;
    } else if (!strcmp(argv[i], "-n")) {
      if (++i >= argc || parse_int_arg(argv[i], 0, &limit)) {
        fprintf(stderr, "-n requires a non-negative frame count\n");
        return 1;
      }
    } else if (!strcmp(argv[i], "-png")) {
      if (i + 2 >= argc) {
        fprintf(stderr, "-png requires a directory and positive interval\n");
        return 1;
      }
      c.png_dir = argv[++i];
      if (parse_int_arg(argv[++i], 1, &c.png_every)) {
        fprintf(stderr, "-png interval must be a positive integer\n");
        return 1;
      }
    } else if (argv[i][0] == '-') {
      return usage();
    } else if (!path) {
      path = argv[i];
    } else if (!ref) {
      ref = argv[i];
    } else {
      return usage();
    }
  }
  if (!path) return usage();

  if (!container_open(&f, path)) {
    fprintf(stderr, "%s: %s\n", path, f.problem);
    return 1;
  }
  char err[256] = {0};
  double start_fp = footprint_mb();
  d = vcnvp9_create(4096, 2304, err, sizeof(err));
  if (!d) {
    fprintf(stderr, "create: %s\n", err);
    goto done;
  }
  if (ref) {
    c.ref = fopen(ref, "r");
    if (!c.ref) {
      perror(ref);
      goto done;
    }
  }

  const uint8_t* data;
  size_t size;
  int n = 0, rc = 0, cap = 0, timed = 0, gt_budget = 0;
  double t0 = now_ms(), first_fp = 0, last_print = t0;
  while ((!limit || n < limit) && container_next(&f, &data, &size)) {
    double a = now_ms();
    rc = vcnvp9_decode(d, data, size, n++, on_output, &c);
    if (rc) {
      fprintf(stderr, "decode error at chunk %d: %s\n", n - 1,
              vcnvp9_last_error(d));
      break;
    }
    if (c.bench) {
      double b = now_ms();
      if (timed == cap) {
        if (cap > INT_MAX / 2) {
          fprintf(stderr, "benchmark sample count overflow\n");
          goto done;
        }
        int new_cap = cap ? cap * 2 : 4096;
        float* new_times = realloc(times, (size_t)new_cap * sizeof(*times));
        if (!new_times) {
          fprintf(stderr, "out of memory for benchmark samples\n");
          goto done;
        }
        times = new_times;
        cap = new_cap;
      }
      times[timed++] = (float)(b - a);
      if (b - a > 1000.0 / 60) gt_budget++;
      if (timed == 100) first_fp = footprint_mb();
      if (b - last_print > 10000) {
        last_print = b;
        printf("  chunk %d: %.1f chunks/s, footprint %.0f MB\n", n,
               n * 1000.0 / (b - t0), footprint_mb());
        fflush(stdout);
      }
    }
  }
  if (f.problem) {
    fprintf(stderr, "%s: stopped after chunk %d: %s\n", path, n, f.problem);
    rc = 1;
  }

  // A decoder that shows fewer frames than the reference lists must not pass.
  // With -n the file was cut short on purpose.
  int missing = 0;
  char unused[33];
  if (c.ref && !rc && !limit && !c.bench && !c.png_dir)
    while (next_ref(&c, unused)) missing++;
  if (missing)
    printf("%d reference frame(s) were never decoded  MISSING\n", missing);

  double total = now_ms() - t0;
  if (c.bench && timed) {
    qsort(times, (size_t)timed, sizeof(*times), cmp_float);
    printf("bench: %d chunks, %d shown, %.2f s, %.1f shown frames/s\n", timed,
           c.frames, total / 1000, c.frames * 1000.0 / total);
    printf("chunk ms: p50 %.2f p95 %.2f p99 %.2f max %.2f, over 16.67 ms: %d\n",
           times[timed / 2], times[(size_t)timed * 95 / 100],
           times[(size_t)timed * 99 / 100], times[timed - 1], gt_budget);
    printf("footprint MB: before create %.0f, chunk 100 %.0f, end %.0f\n",
           start_fp, first_fp, footprint_mb());
  }
  printf("%s: %d frames, %d mismatches\n", path, c.frames,
         c.mismatches + missing);
  exit_code = rc ? 1 : c.mismatches || missing ? 2 : 0;

done:
  free(times);
  vcnvp9_destroy(d);
  // A stuck session is closed on a background queue: wait for it, so its
  // log lines are there before the program ends, but not for ever.
  if (!vcn_teardown_drain(30000)) {
    fprintf(stderr,
            "the stuck session was still closing after 30 s: the driver is "
            "waiting for the GPU; exiting without it\n");
    exit_code = 1;
  }
  if (c.ref) fclose(c.ref);
  container_close(&f);
  return exit_code;
}
