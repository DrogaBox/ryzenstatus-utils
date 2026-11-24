// What the four parsers produce: one access unit (picture) and the few header
// fields the codec block needs. Only intra pictures are accepted: this probe
// asks whether the firmware takes the packet, and one intra frame needs no
// reference management.
#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  const uint8_t* au;  // points into the input buffer
  size_t auSize;
  uint32_t width, height;
  int intra;
} ProbeAu;

// A start code 00 00 01 <code> at or after `from`; returns its offset or
// (size_t)-1.
static inline size_t find_start(const uint8_t* d, size_t n, size_t from,
                                uint8_t code) {
  for (size_t i = from; i + 3 < n; i++)
    if (d[i] == 0 && d[i + 1] == 0 && d[i + 2] == 1 && d[i + 3] == code)
      return i;
  return (size_t)-1;
}

// The next start code of any of the given codes at or after `from`, or the
// first start code of any code when `codes` is NULL: returns its offset and
// writes the code byte.
static inline size_t find_any_start(const uint8_t* d, size_t n, size_t from,
                                    uint8_t* codeOut) {
  for (size_t i = from; i + 3 < n; i++)
    if (d[i] == 0 && d[i + 1] == 0 && d[i + 2] == 1) {
      *codeOut = d[i + 3];
      return i;
    }
  return (size_t)-1;
}

// The end of a picture that starts at `au`: the next picture, sequence or GOP
// start code, or the end of the buffer.
// End of one coded picture: the next start code that begins another picture
// or header. The stop set depends on the codec: in MPEG-2, 0x01..0xAF are
// slice rows (0x0D and 0x0F included), while in VC-1 0x0D/0x0F are the frame
// and sequence headers. A shared set used to cut MPEG-2 pictures at slice row
// 13 (8899 of 25941 bytes in mpeg2-720x576.m2v; Mesa sends the whole picture).
typedef enum { AU_MPEG2, AU_VC1, AU_MPEG4 } AuCodec;
static inline int au_stops(AuCodec k, uint8_t c) {
  switch (k) {
    case AU_MPEG2:
      return c == 0x00 || c == 0xB3 || c == 0xB7 || c == 0xB8;
    case AU_VC1:
      return c == 0x0A || c == 0x0D || c == 0x0E || c == 0x0F;
    case AU_MPEG4:
      return c == 0xB1 || c == 0xB3 || c == 0xB6 || c <= 0x2F;
  }
  return 1;
}
static inline size_t au_end_for(AuCodec k, const uint8_t* d, size_t n,
                                size_t au, size_t scanFrom) {
  size_t i = scanFrom;
  (void)au;
  while (i + 3 < n) {
    if (d[i] == 0 && d[i + 1] == 0 && d[i + 2] == 1) {
      uint8_t c = d[i + 3];
      if (au_stops(k, c)) return i;
      i += 4;
      continue;
    }
    i++;
  }
  return n;
}

static inline void copy_err(char* err, size_t errLen, const char* what) {
  if (err && errLen) {
    size_t i = 0;
    for (; what[i] && i + 1 < errLen; i++) err[i] = what[i];
    err[i] = 0;
  }
}

// Bisect switches on top of variant 15 (the recipe that decodes): each name in
// the comma-separated VCNPROBE_BISECT takes ONE of variant 10/11's changes
// back, so a run tells whether that change is needed.
//   appleidx  Apple's four index entries (DRM and 0x0f blocks) instead of two
//   swctx0    sw_ctxt_size 0 instead of 128 KiB
//   dpb4      the DPB of four pictures the probe first asked for
//   geom0     Mesa's db_pitch (32-aligned) and bottom offsets 0
//   refs7f    reference indices 0x7f instead of 0
//   nomat     MPEG-2: no quantiser matrices loaded
//   zzmat     MPEG-2: matrices in the order the stream sends them (zigzag);
//             Mesa's VA path sends the zigzag of the transposed matrix
//   pichdr    bitstream from the picture header (MPEG-2) / unchanged (VC-1)
//   seqhdr    bitstream from the sequence header
//   vc1stream VC-1: profile/level/pic_structure numbered as in the stream
//   nomaxb    VC-1: without 7 in pps bits 16..18
static inline int probe_bisect(const char* name) {
  const char* v = getenv("VCNPROBE_BISECT");
  size_t n = strlen(name);
  while (v && *v) {
    const char* e = strchr(v, ',');
    size_t len = e ? (size_t)(e - v) : strlen(v);
    if (len == n && !memcmp(v, name, n)) return 1;
    v = e ? e + 1 : NULL;
  }
  return 0;
}
