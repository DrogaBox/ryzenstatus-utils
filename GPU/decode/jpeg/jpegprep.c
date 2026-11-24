// jpegprep.c - see jpegprep.h. The same rewrite as VCNJpegProbe's
// tools/jpeg_normalize.hpp (the tool the first GPU tests use). On 2026-11-24
// both gave the same bytes for six files (photos of 12 and 48 MP, a 640x480
// MJPEG frame, the samples of tests/jpegsamples.h); tests/jpegtest.c checks
// the shape and the picture. This one also takes fill bytes and adds Annex K's
// tables where the kext's tool refuses.
#include "jpegprep.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "jpegstd.h"

typedef struct {
  bool haveQ[4];
  uint8_t q[4][64];
  bool haveH[2][2];        // [class 0 DC / 1 AC][id]
  const uint8_t* h[2][2];  // 16 counts + values, inside the input
  size_t hLen[2][2];
  uint16_t restart;
  const uint8_t* sof;
  size_t sofLen;
  const uint8_t* sos;
  size_t sosLen;
  const uint8_t* scan;
  size_t scanLen;
} Tables;

static int fail(char* why, size_t whyLen, int code, const char* text) {
  if (why && whyLen) snprintf(why, whyLen, "%s", text);
  return code;
}

static void put_seg(uint8_t* o, size_t* p, uint8_t marker, const uint8_t* body,
                    size_t len) {
  o[(*p)++] = 0xff;
  o[(*p)++] = marker;
  o[(*p)++] = (uint8_t)((len + 2) >> 8);
  o[(*p)++] = (uint8_t)(len + 2);
  memcpy(o + *p, body, len);
  *p += len;
}

// Reads the standard tables out of jpegstd.h for the ones the picture lacks.
static void std_tables(Tables* t, bool* added) {
  size_t p = 0;
  while (p < sizeof(kJpegStdDht)) {
    uint8_t tc = kJpegStdDht[p] >> 4, th = kJpegStdDht[p] & 15;
    size_t count = 0;
    for (int k = 0; k < 16; k++) count += kJpegStdDht[p + 1 + k];
    if (!t->haveH[tc][th]) {
      t->haveH[tc][th] = true;
      t->h[tc][th] = kJpegStdDht + p + 1;
      t->hLen[tc][th] = 16 + count;
      *added = true;
    }
    p += 17 + count;
  }
}

int jpeg_prepare(const uint8_t* d, size_t n, uint8_t** out, size_t* outLen,
                 JpegInfo* info, char* why, size_t whyLen) {
  *out = NULL;
  *outLen = 0;
  memset(info, 0, sizeof(*info));
  if (!d || n < 4 || d[0] != 0xff || d[1] != 0xd8)
    return fail(why, whyLen, JPEG_BAD, "not a JPEG (no SOI)");
  Tables t;
  memset(&t, 0, sizeof(t));
  size_t i = 2;
  bool gotScan = false;
  while (!gotScan) {
    // fill bytes (0xFF repeated) may come before a marker
    while (i + 1 < n && d[i] == 0xff && d[i + 1] == 0xff) i++;
    if (i + 4 > n) return fail(why, whyLen, JPEG_BAD, "no scan found");
    if (d[i] != 0xff) return fail(why, whyLen, JPEG_BAD, "marker expected");
    uint8_t m = d[i + 1];
    size_t len = ((size_t)d[i + 2] << 8) | d[i + 3];
    if (len < 2 || len > n - i - 2)
      return fail(why, whyLen, JPEG_BAD, "a segment does not fit the file");
    const uint8_t* s = d + i + 4;
    size_t body = len - 2;
    if (m == 0xdb) {
      size_t p = 0;
      while (p < body) {
        uint8_t pq = s[p] >> 4, tq = s[p] & 15;
        if (pq != 0)
          return fail(why, whyLen, JPEG_UNSUPPORTED, "16-bit quantisation table");
        if (tq > 3 || body - p < 65)
          return fail(why, whyLen, JPEG_BAD, "bad quantisation table");
        t.haveQ[tq] = true;
        memcpy(t.q[tq], s + p + 1, 64);
        p += 65;
      }
    } else if (m == 0xc4) {
      size_t p = 0;
      while (p < body) {
        uint8_t tc = s[p] >> 4, th = s[p] & 15;
        if (tc > 1 || th > 3 || body - p < 17)
          return fail(why, whyLen, JPEG_BAD, "bad Huffman table");
        if (th > 1)
          return fail(why, whyLen, JPEG_UNSUPPORTED,
                      "Huffman table id above 1 (Mesa gives the block two)");
        size_t count = 0;
        for (int k = 0; k < 16; k++) count += s[p + 1 + k];
        if (count > (tc == 0 ? 12u : 162u) || body - p - 17 < count)
          return fail(why, whyLen, JPEG_BAD, "bad Huffman table");
        t.haveH[tc][th] = true;
        t.h[tc][th] = s + p + 1;
        t.hLen[tc][th] = 16 + count;
        p += 17 + count;
      }
    } else if (m == 0xdd) {
      if (body != 2)
        return fail(why, whyLen, JPEG_BAD, "bad restart interval segment");
      t.restart = (uint16_t)((s[0] << 8) | s[1]);
    } else if (m == 0xc0) {
      if (t.sof) return fail(why, whyLen, JPEG_BAD, "more than one frame header");
      t.sof = s;
      t.sofLen = body;
    } else if (m == 0xda) {
      t.sos = s;
      t.sosLen = body;
      gotScan = true;
    } else if ((m >= 0xe0 && m <= 0xef) || m == 0xfe) {
      // dropped, as Mesa does
    } else if (m >= 0xc1 && m <= 0xcf && m != 0xc4 && m != 0xc8 &&
               m != 0xcc) {
      return fail(why, whyLen, JPEG_UNSUPPORTED,
                  "not a baseline JPEG (progressive, lossless or arithmetic)");
    } else {
      return fail(why, whyLen, JPEG_UNSUPPORTED, "a segment this decoder does not handle");
    }
    i += 2 + len;
  }
  if (!t.sof) return fail(why, whyLen, JPEG_BAD, "scan before the frame header");
  // frame header: P, Y, X, Nf, then Nf x (C, HV, Tq)
  if (t.sofLen < 6 || t.sofLen != 6 + 3u * t.sof[5])
    return fail(why, whyLen, JPEG_BAD, "bad frame header");
  uint32_t height = ((uint32_t)t.sof[1] << 8) | t.sof[2];
  uint32_t width = ((uint32_t)t.sof[3] << 8) | t.sof[4];
  if (t.sof[0] != 8) return fail(why, whyLen, JPEG_UNSUPPORTED, "not 8 bits per sample");
  if (width == 0 || height == 0)
    return fail(why, whyLen, JPEG_UNSUPPORTED, "no size in the frame header");
  if (t.sof[5] != 3)
    return fail(why, whyLen, JPEG_UNSUPPORTED, "not three components");
  if (t.sof[7] != 0x22 || t.sof[10] != 0x11 || t.sof[13] != 0x11)
    return fail(why, whyLen, JPEG_UNSUPPORTED, "not 4:2:0");
  for (int c = 0; c < 3; c++) {
    uint8_t tq = t.sof[8 + 3 * c];
    if (tq > 3 || !t.haveQ[tq])
      return fail(why, whyLen, JPEG_BAD, "a component's quantisation table is missing");
  }
  // scan header: Ns, Ns x (C, Td/Ta), Ss, Se, Ah/Al
  if (t.sosLen < 1 || t.sosLen != 4 + 2u * t.sos[0])
    return fail(why, whyLen, JPEG_BAD, "bad scan header");
  if (t.sos[0] != 3)
    return fail(why, whyLen, JPEG_UNSUPPORTED, "a scan without all three components");
  // The scan runs to the first marker that is neither a stuffed FF00 nor RSTn.
  size_t e = i;
  while (1) {
    if (e + 1 >= n) return fail(why, whyLen, JPEG_BAD, "no EOI after the scan");
    if (d[e] == 0xff && d[e + 1] != 0x00 && !(d[e + 1] >= 0xd0 && d[e + 1] <= 0xd7))
      break;
    e++;
  }
  // fill bytes before EOI belong to no segment
  size_t f = e;
  while (f + 1 < n && d[f + 1] == 0xff) f++;
  if (d[f + 1] != 0xd9) return fail(why, whyLen, JPEG_UNSUPPORTED, "more than one scan");
  t.scan = d + i;
  t.scanLen = e - i;
  bool added = false;
  std_tables(&t, &added);
  for (int c = 0; c < 3; c++) {
    uint8_t td = t.sos[2 + 2 * c] >> 4, ta = t.sos[2 + 2 * c] & 15;
    if (td > 1 || ta > 1 || !t.haveH[0][td] || !t.haveH[1][ta])
      return fail(why, whyLen, JPEG_BAD, "a component's Huffman table is missing");
  }
  uint8_t dqt[4 * 65], dht[4 * 179];
  size_t nq = 0, nh = 0;
  for (int k = 0; k < 4; k++) {
    if (!t.haveQ[k]) continue;
    dqt[nq++] = (uint8_t)k;
    memcpy(dqt + nq, t.q[k], 64);
    nq += 64;
  }
  for (int c = 0; c < 2; c++) {
    for (int k = 0; k < 2; k++) {
      if (!t.haveH[c][k]) continue;
      dht[nh++] = (uint8_t)((c << 4) | k);
      memcpy(dht + nh, t.h[c][k], t.hLen[c][k]);
      nh += t.hLen[c][k];
    }
  }
  size_t cap = 2 + (4 + nq) + (4 + nh) + 6 + (4 + t.sofLen) + (4 + t.sosLen) + t.scanLen + 2;
  uint8_t* o = malloc(cap);
  if (!o) return fail(why, whyLen, JPEG_NO_MEMORY, "out of memory");
  size_t p = 0;
  o[p++] = 0xff;
  o[p++] = 0xd8;
  put_seg(o, &p, 0xdb, dqt, nq);
  put_seg(o, &p, 0xc4, dht, nh);
  if (t.restart) {
    uint8_t r[2] = {(uint8_t)(t.restart >> 8), (uint8_t)t.restart};
    put_seg(o, &p, 0xdd, r, 2);
  }
  put_seg(o, &p, 0xc0, t.sof, t.sofLen);
  put_seg(o, &p, 0xda, t.sos, t.sosLen);
  memcpy(o + p, t.scan, t.scanLen);
  p += t.scanLen;
  o[p++] = 0xff;
  o[p++] = 0xd9;
  *out = o;
  *outLen = p;
  info->width = width;
  info->height = height;
  info->restart = t.restart;
  info->stdTables = added;
  return JPEG_OK;
}
