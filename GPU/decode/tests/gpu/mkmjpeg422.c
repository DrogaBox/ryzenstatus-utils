// mkmjpeg422: writes a Motion JPEG stream sampled the way webcams do it
// (4:2:2 as luma 2x1, chroma 1x1, 1x1), which FFmpeg's encoder cannot write
// (it writes 4:2:2 as 2x2, 1x2, 1x2) and Apple's encoder neither (4:2:0 only).
//
//   mkmjpeg422 in.yuv width height out.mjpeg [quality]
//
// in.yuv: planar 4:2:2 frames (FFmpeg's yuvj422p), width a multiple of 16,
// height a multiple of 8. Each frame becomes one baseline JPEG: standard
// quantisation tables of Annex K scaled as libjpeg does for the quality (90 by
// default), the standard Huffman tables of Annex K, one interleaved scan.
// Runs on the CPU only.
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const uint8_t kZigzag[64] = {0,  1,  8,  16, 9,  2,  3,  10, 17, 24, 32, 25, 18, 11, 4,  5,
                                    12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6,  7,  14, 21, 28,
                                    35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
                                    58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63};
static const uint8_t kStdLuma[64] = {16, 11, 10, 16, 24,  40,  51,  61,  12, 12, 14, 19, 26,  58,  60,  55,
                                     14, 13, 16, 24, 40,  57,  69,  56,  14, 17, 22, 29, 51,  87,  80,  62,
                                     18, 22, 37, 56, 68,  109, 103, 77,  24, 35, 55, 64, 81,  104, 113, 92,
                                     49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99};
static const uint8_t kStdChroma[64] = {17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99,
                                       24, 26, 56, 99, 99, 99, 99, 99, 47, 66, 99, 99, 99, 99, 99, 99,
                                       99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
                                       99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99};
// Annex K.3: bits (count of codes of each length 1..16) and values
static const uint8_t kDcLumaBits[16] = {0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0};
static const uint8_t kDcLumaVals[12] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11};
static const uint8_t kDcChromaBits[16] = {0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0};
static const uint8_t kDcChromaVals[12] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11};
static const uint8_t kAcLumaBits[16] = {0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7d};
static const uint8_t kAcLumaVals[162] = {
    0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14,
    0x32, 0x81, 0x91, 0xa1, 0x08, 0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0, 0x24, 0x33, 0x62, 0x72, 0x82, 0x09,
    0x0a, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a,
    0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65,
    0x66, 0x67, 0x68, 0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88,
    0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9,
    0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca,
    0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea,
    0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa};
static const uint8_t kAcChromaBits[16] = {0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77};
static const uint8_t kAcChromaVals[162] = {
    0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22, 0x32,
    0x81, 0x08, 0x14, 0x42, 0x91, 0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52, 0xf0, 0x15, 0x62, 0x72, 0xd1, 0x0a, 0x16,
    0x24, 0x34, 0xe1, 0x25, 0xf1, 0x17, 0x18, 0x19, 0x1a, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x35, 0x36, 0x37, 0x38, 0x39,
    0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64,
    0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x82, 0x83, 0x84, 0x85, 0x86,
    0x87, 0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
    0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8,
    0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9,
    0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa};

typedef struct {
  uint16_t code[256];
  uint8_t len[256];
} Huff;
static void build_huff(Huff* h, const uint8_t bits[16], const uint8_t* vals) {
  memset(h, 0, sizeof(*h));
  uint16_t code = 0;
  int k = 0;
  for (int l = 1; l <= 16; l++) {
    for (int i = 0; i < bits[l - 1]; i++) {
      h->code[vals[k]] = code++;
      h->len[vals[k]] = (uint8_t)l;
      k++;
    }
    code <<= 1;
  }
}

typedef struct {
  uint8_t* d;
  size_t n, cap;
  uint32_t acc;
  int nbits;
} Out;
static void put(Out* o, uint8_t b) {
  if (o->n == o->cap) {
    o->cap = o->cap ? o->cap * 2 : 1 << 20;
    o->d = realloc(o->d, o->cap);
    if (!o->d) exit(3);
  }
  o->d[o->n++] = b;
}
static void put16(Out* o, int v) {
  put(o, (uint8_t)(v >> 8));
  put(o, (uint8_t)v);
}
static void bits(Out* o, uint32_t v, int n) {
  for (int i = n - 1; i >= 0; i--) {
    o->acc = (o->acc << 1) | ((v >> i) & 1);
    if (++o->nbits == 8) {
      put(o, (uint8_t)o->acc);
      if ((uint8_t)o->acc == 0xff) put(o, 0);  // byte stuffing
      o->acc = 0;
      o->nbits = 0;
    }
  }
}
static void flush_bits(Out* o) {
  while (o->nbits) bits(o, 1, 1);  // pad with ones
}
static int magnitude(int v) {
  int a = v < 0 ? -v : v, n = 0;
  while (a) {
    n++;
    a >>= 1;
  }
  return n;
}
static void put_value(Out* o, int v, int n) {
  if (n) bits(o, (uint32_t)(v < 0 ? v + (1 << n) - 1 : v), n);
}

static void fdct(const uint8_t* src, int stride, double out[64]) {
  static double c[8][8];
  static int init;
  if (!init) {
    for (int u = 0; u < 8; u++)
      for (int x = 0; x < 8; x++) c[u][x] = (u ? sqrt(2.0 / 8) : sqrt(1.0 / 8)) * cos((2 * x + 1) * u * M_PI / 16);
    init = 1;
  }
  double tmp[64];
  for (int y = 0; y < 8; y++)
    for (int u = 0; u < 8; u++) {
      double s = 0;
      for (int x = 0; x < 8; x++) s += c[u][x] * (src[y * stride + x] - 128.0);
      tmp[y * 8 + u] = s;
    }
  for (int u = 0; u < 8; u++)
    for (int v = 0; v < 8; v++) {
      double s = 0;
      for (int y = 0; y < 8; y++) s += c[v][y] * tmp[y * 8 + u];
      out[v * 8 + u] = s;
    }
}

static void block(Out* o, const uint8_t* src, int stride, const uint8_t q[64], int* dcPred, const Huff* dc,
                  const Huff* ac) {
  double f[64];
  fdct(src, stride, f);
  int z[64];
  for (int i = 0; i < 64; i++) z[i] = (int)lround(f[kZigzag[i]] / q[kZigzag[i]]);
  int diff = z[0] - *dcPred;
  *dcPred = z[0];
  int n = magnitude(diff);
  bits(o, dc->code[n], dc->len[n]);
  put_value(o, diff, n);
  int run = 0;
  for (int i = 1; i < 64; i++) {
    if (!z[i]) {
      run++;
      continue;
    }
    while (run > 15) {
      bits(o, ac->code[0xf0], ac->len[0xf0]);
      run -= 16;
    }
    n = magnitude(z[i]);
    int sym = (run << 4) | n;
    bits(o, ac->code[sym], ac->len[sym]);
    put_value(o, z[i], n);
    run = 0;
  }
  if (run) bits(o, ac->code[0], ac->len[0]);
}

static void dht(Out* o, int cls, int id, const uint8_t b[16], const uint8_t* v) {
  int n = 0;
  for (int i = 0; i < 16; i++) n += b[i];
  put(o, (uint8_t)((cls << 4) | id));
  for (int i = 0; i < 16; i++) put(o, b[i]);
  for (int i = 0; i < n; i++) put(o, v[i]);
}

int main(int argc, char** argv) {
  if (argc != 5 && argc != 6) {
    fprintf(stderr, "usage: mkmjpeg422 in.yuv(yuvj422p) width height out.mjpeg [quality]\n");
    return 1;
  }
  int w = atoi(argv[2]), h = atoi(argv[3]), quality = argc == 6 ? atoi(argv[5]) : 90;
  if (w < 16 || h < 8 || w % 16 || h % 8 || w > 8192 || h > 8192 || quality < 1 || quality > 100) {
    fprintf(stderr, "width must be a multiple of 16, height of 8, quality 1..100\n");
    return 1;
  }
  int scale = quality < 50 ? 5000 / quality : 200 - quality * 2;
  uint8_t ql[64], qc[64];
  for (int i = 0; i < 64; i++) {
    int a = (kStdLuma[i] * scale + 50) / 100, b = (kStdChroma[i] * scale + 50) / 100;
    ql[i] = (uint8_t)(a < 1 ? 1 : a > 255 ? 255 : a);
    qc[i] = (uint8_t)(b < 1 ? 1 : b > 255 ? 255 : b);
  }
  Huff dcl, dcc, acl, acc;
  build_huff(&dcl, kDcLumaBits, kDcLumaVals);
  build_huff(&dcc, kDcChromaBits, kDcChromaVals);
  build_huff(&acl, kAcLumaBits, kAcLumaVals);
  build_huff(&acc, kAcChromaBits, kAcChromaVals);
  FILE* in = fopen(argv[1], "rb");
  FILE* out = fopen(argv[4], "wb");
  if (!in || !out) {
    fprintf(stderr, "cannot open the files\n");
    return 1;
  }
  size_t frameBytes = (size_t)w * h * 2;
  uint8_t* f = malloc(frameBytes);
  int frames = 0;
  while (f && fread(f, 1, frameBytes, in) == frameBytes) {
    const uint8_t *Y = f, *U = f + (size_t)w * h, *V = U + (size_t)w / 2 * h;
    Out o = {0};
    put16(&o, 0xffd8);
    put16(&o, 0xffdb);  // DQT: two 8-bit tables, zigzag order
    put16(&o, 2 + 2 * 65);
    put(&o, 0);
    for (int i = 0; i < 64; i++) put(&o, ql[kZigzag[i]]);
    put(&o, 1);
    for (int i = 0; i < 64; i++) put(&o, qc[kZigzag[i]]);
    put16(&o, 0xffc0);  // SOF0: 8 bits, three components, Y 2x1, Cb 1x1, Cr 1x1
    put16(&o, 17);
    put(&o, 8);
    put16(&o, h);
    put16(&o, w);
    put(&o, 3);
    put(&o, 1), put(&o, 0x21), put(&o, 0);
    put(&o, 2), put(&o, 0x11), put(&o, 1);
    put(&o, 3), put(&o, 0x11), put(&o, 1);
    put16(&o, 0xffc4);  // DHT: the four standard tables
    put16(&o, 2 + 4 * 17 + 12 + 12 + 162 + 162);
    dht(&o, 0, 0, kDcLumaBits, kDcLumaVals);
    dht(&o, 1, 0, kAcLumaBits, kAcLumaVals);
    dht(&o, 0, 1, kDcChromaBits, kDcChromaVals);
    dht(&o, 1, 1, kAcChromaBits, kAcChromaVals);
    put16(&o, 0xffda);  // SOS
    put16(&o, 12);
    put(&o, 3);
    put(&o, 1), put(&o, 0x00);
    put(&o, 2), put(&o, 0x11);
    put(&o, 3), put(&o, 0x11);
    put(&o, 0), put(&o, 63), put(&o, 0);
    int py = 0, pu = 0, pv = 0;
    for (int my = 0; my < h; my += 8)
      for (int mx = 0; mx < w; mx += 16) {
        block(&o, Y + (size_t)my * w + mx, w, ql, &py, &dcl, &acl);
        block(&o, Y + (size_t)my * w + mx + 8, w, ql, &py, &dcl, &acl);
        block(&o, U + (size_t)my * (w / 2) + mx / 2, w / 2, qc, &pu, &dcc, &acc);
        block(&o, V + (size_t)my * (w / 2) + mx / 2, w / 2, qc, &pv, &dcc, &acc);
      }
    flush_bits(&o);
    put16(&o, 0xffd9);
    fwrite(o.d, 1, o.n, out);
    free(o.d);
    frames++;
  }
  free(f);
  fclose(in);
  fclose(out);
  printf("wrote %d frames of %dx%d, 4:2:2 sampled 2x1/1x1/1x1, quality %d\n", frames, w, h, quality);
  return frames ? 0 : 2;
}
