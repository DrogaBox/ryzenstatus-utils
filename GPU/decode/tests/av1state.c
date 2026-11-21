// av1state: checks that the AV1 parser keeps a consistent state across
// samples when one of them is refused. Each case starts from the first
// temporal unit of a real stream.
//
//   1. A frame header sent as its own OBU, then the tiles as a tile group OBU,
//      gives the same frame as the original OBU_FRAME.
//   2. After a valid frame header, a refused sample must end that frame: a
//      later tile group may not complete it with the refused sample's state.
//   3. A refused header must leave the reference state exactly as it was.
//   4. A tile group with no tile bytes is refused.
//
// usage: av1state file.ivf   (a single-tile AV1 stream; exit status 0 = pass)
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "av1parse.h"

enum {
  kObuSequenceHeader = 1,
  kObuFrameHeader = 3,
  kObuTileGroup = 4,
  kObuFrame = 6
};

static int failures;
static void expect(const char* what, bool ok) {
  printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) failures++;
}

typedef struct {
  int ready, shown;
  size_t header_bytes;
  size_t tile_bytes;
  uint64_t tile_hash;
} Seen;

static int on_frame(void* ctx, AV1Parser* p, AV1ParseResult kind) {
  Seen* s = ctx;
  if (kind == AV1_PARSE_SHOW_EXISTING) {
    s->shown++;
    return 0;
  }
  s->ready++;
  s->tile_bytes = p->tile_data_size;
  uint64_t h = 0xcbf29ce484222325ull;
  for (size_t i = 0; i < p->tile_data_size; i++)
    h = (h ^ p->tile_data[i]) * 0x100000001b3ull;
  s->tile_hash = h;
  av1_reference_update(p, 0);
  return 0;
}

// Header bytes of the frame header inside an OBU_FRAME, read as the parser
// records them before the tiles.
static int on_header_bytes(void* ctx, AV1Parser* p, AV1ParseResult kind) {
  (void)kind;
  *(size_t*)ctx = p->fh.header_bytes;
  return 0;
}

static size_t put_obu(uint8_t* out, int type, const uint8_t* payload,
                      size_t size) {
  size_t n = 0;
  out[n++] = (uint8_t)(type << 3 | 0x02);  // has_size_field
  size_t v = size;
  do {
    uint8_t byte = v & 0x7f;
    v >>= 7;
    out[n++] = byte | (v ? 0x80 : 0);
  } while (v);
  memcpy(out + n, payload, size);
  return n + size;
}

// Finds the OBUs of one temporal unit (each with a size field).
static bool find_obu(const uint8_t* tu, size_t size, int type,
                     const uint8_t** payload, size_t* payload_size) {
  size_t off = 0;
  while (off < size) {
    uint8_t hdr = tu[off];
    size_t pos = off + 1 + ((hdr >> 2) & 1);
    if (!(hdr & 0x02)) return false;
    uint64_t len = 0;
    for (int i = 0; i < 8 && pos < size; i++) {
      len |= (uint64_t)(tu[pos] & 0x7f) << (7 * i);
      if (!(tu[pos++] & 0x80)) break;
    }
    if (len > size - pos) return false;
    if (((hdr >> 3) & 15) == type) {
      *payload = tu + pos;
      *payload_size = (size_t)len;
      return true;
    }
    off = pos + (size_t)len;
  }
  return false;
}

int main(int argc, char** argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: av1state file.ivf\n");
    return 2;
  }
  FILE* f = fopen(argv[1], "rb");
  if (!f) return 2;
  static uint8_t file[1 << 20];
  size_t n = fread(file, 1, sizeof(file), f);
  fclose(f);
  if (n < 44 || memcmp(file, "DKIF", 4) || memcmp(file + 8, "AV01", 4)) {
    fprintf(stderr, "%s: not an AV1 IVF file\n", argv[1]);
    return 2;
  }
  size_t pos = (size_t)(file[6] | file[7] << 8);
  size_t tu_size = (size_t)file[pos] | (size_t)file[pos + 1] << 8 |
                   (size_t)file[pos + 2] << 16 | (size_t)file[pos + 3] << 24;
  const uint8_t* tu = file + pos + 12;
  if (tu_size > n - pos - 12) return 2;

  const uint8_t *seq, *frame;
  size_t seq_size, frame_size;
  if (!find_obu(tu, tu_size, kObuSequenceHeader, &seq, &seq_size) ||
      !find_obu(tu, tu_size, kObuFrame, &frame, &frame_size)) {
    fprintf(stderr, "%s: first temporal unit has no OBU_FRAME\n", argv[1]);
    return 2;
  }
  static uint8_t seq_obu[4096], hdr_obu[4096], tiles_obu[1 << 20], buf[1 << 20];
  size_t seq_n = put_obu(seq_obu, kObuSequenceHeader, seq, seq_size);

  // Reference: the original temporal unit.
  AV1Parser* p = calloc(1, sizeof(*p));
  av1_parser_init(p);
  Seen want = {0};
  expect("the first temporal unit parses",
         !av1_parse_temporal_unit(p, tu, tu_size, on_frame, &want) &&
             want.ready == 1);
  av1_parser_free(p);

  // Split the frame: header OBU + tile group OBU.
  size_t header_bytes = 0;
  av1_parser_init(p);
  av1_parse_temporal_unit(p, seq_obu, seq_n, on_header_bytes, &header_bytes);
  size_t nb = put_obu(buf, kObuFrame, frame, frame_size);
  av1_parse_temporal_unit(p, buf, nb, on_header_bytes, &header_bytes);
  av1_parser_free(p);
  if (!header_bytes || header_bytes >= frame_size) {
    fprintf(stderr, "could not find the frame header size\n");
    return 1;
  }
  size_t hdr_n = put_obu(hdr_obu, kObuFrameHeader, frame, header_bytes);
  size_t tiles_n = put_obu(tiles_obu, kObuTileGroup, frame + header_bytes,
                           frame_size - header_bytes);

  // 1. split form decodes the same frame
  av1_parser_init(p);
  Seen got = {0};
  av1_parse_temporal_unit(p, seq_obu, seq_n, on_frame, &got);
  memcpy(buf, hdr_obu, hdr_n);
  memcpy(buf + hdr_n, tiles_obu, tiles_n);
  int r = av1_parse_temporal_unit(p, buf, hdr_n + tiles_n, on_frame, &got);
  expect("header OBU + tile group OBU give the same frame as OBU_FRAME",
         !r && got.ready == 1 && got.tile_bytes == want.tile_bytes &&
             got.tile_hash == want.tile_hash);
  av1_parser_free(p);

  // 2. a refused sample ends the pending frame
  av1_parser_init(p);
  got = (Seen){0};
  av1_parse_temporal_unit(p, seq_obu, seq_n, on_frame, &got);
  r = av1_parse_temporal_unit(p, hdr_obu, hdr_n, on_frame, &got);
  expect("a frame header alone is accepted, no frame yet",
         !r && got.ready == 0);
  nb = put_obu(buf, kObuFrame, frame, 1);  // truncated: refused
  expect("a truncated OBU_FRAME is refused",
         av1_parse_temporal_unit(p, buf, nb, on_frame, &got) != 0);
  r = av1_parse_temporal_unit(p, tiles_obu, tiles_n, on_frame, &got);
  expect("a tile group after a refused sample does not complete a frame",
         r != 0 && got.ready == 0);
  av1_parser_free(p);

  // 3. a refused header leaves the references untouched
  av1_parser_init(p);
  got = (Seen){0};
  av1_parse_temporal_unit(p, seq_obu, seq_n, on_frame, &got);
  av1_parse_temporal_unit(p, tu, tu_size, on_frame, &got);
  AV1RefSlot before[AV1_NUM_REF_FRAMES];
  memcpy(before, p->ref, sizeof(before));
  // A shown key frame header, cut right after its first byte: the parser
  // resets the references for a shown key frame, then runs out of bits.
  const uint8_t cut[] = {kObuFrame << 3 | 0x02, 0x01, 0x10};
  r = av1_parse_temporal_unit(p, cut, sizeof(cut), on_frame, &got);
  expect("a cut key frame header is refused", r != 0);
  expect("the references are as they were before it",
         !memcmp(before, p->ref, sizeof(before)));
  av1_parser_free(p);

  // 4. an empty tile group is refused
  av1_parser_init(p);
  got = (Seen){0};
  av1_parse_temporal_unit(p, seq_obu, seq_n, on_frame, &got);
  av1_parse_temporal_unit(p, hdr_obu, hdr_n, on_frame, &got);
  nb = put_obu(buf, kObuTileGroup, NULL, 0);
  r = av1_parse_temporal_unit(p, buf, nb, on_frame, &got);
  expect("a tile group with no tile bytes is refused", r != 0 && !got.ready);
  av1_parser_free(p);

  free(p);
  return failures ? 1 : 0;
}
