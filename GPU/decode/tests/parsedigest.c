// parsedigest: runs the AV1 or VP9 header parser over an IVF file the way the
// decoder session drives it, without the GPU, and prints one digest of
// everything the parser produced: every sequence and frame header, the tile
// table, the tile bytes and the reference state after each frame.
//
// Two builds of the parser that print the same line for a file read that file
// the same way. tests/run.sh compares the lines with the recorded ones.
//
// usage: parsedigest file.ivf [more.ivf ...]
// prints, per file: <name> <codec> <decoded> <shown-existing> <errors> <digest>
//
// usage: parsedigest --mutate <rounds> file.ivf [more.ivf ...]
// parses <rounds> damaged copies of each file; meant for a build with the
// address and undefined-behaviour sanitizers.
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "av1parse.h"
#include "vp9parse.h"

enum { kMaxFileBytes = 1 << 30, kMaxFrameBytes = 0x1800000 };

typedef struct {
  uint64_t hash;
  unsigned decoded, shown, errors;
} Digest;

// FNV-1a, 64 bit.
static void mix(Digest* d, const void* data, size_t size) {
  const uint8_t* p = data;
  for (size_t i = 0; i < size; i++) {
    d->hash ^= p[i];
    d->hash *= 0x100000001b3ull;
  }
}

static int on_av1(void* ctx, AV1Parser* p, AV1ParseResult kind) {
  Digest* d = ctx;
  int k = (int)kind;
  mix(d, &k, sizeof(k));
  mix(d, &p->seq, sizeof(p->seq));
  mix(d, &p->fh, sizeof(p->fh));
  if (kind == AV1_PARSE_SHOW_EXISTING) {
    if (p->fh.frame_type == AV1_KEY_FRAME)
      av1_reference_update(p, p->ref[p->fh.frame_to_show_map_idx].dpb_slot);
    d->shown++;
  } else {
    mix(d, &p->num_tiles, sizeof(p->num_tiles));
    mix(d, p->tiles, (size_t)p->num_tiles * sizeof(p->tiles[0]));
    mix(d, p->tile_data, p->tile_data_size);
    av1_reference_update(p, (int)(d->decoded % 8));
    d->decoded++;
  }
  mix(d, p->ref, sizeof(p->ref));
  return 0;
}

static int on_vp9(void* ctx, VP9Parser* p, VP9ParseResult kind,
                  const uint8_t* data, size_t size) {
  Digest* d = ctx;
  int k = (int)kind;
  mix(d, &k, sizeof(k));
  mix(d, &size, sizeof(size));
  mix(d, data, size);
  if (kind == VP9_PARSE_SHOW_EXISTING) {
    d->shown++;
  } else {
    bool supported = vp9_frame_supported(p);
    mix(d, &supported, sizeof(supported));
    vp9_frame_done(p, (int)(d->decoded % 8));
    d->decoded++;
  }
  mix(d, p, offsetof(VP9Parser, err));
  return 0;
}

static uint32_t le32(const uint8_t* p) {
  return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 |
         (uint32_t)p[3] << 24;
}

static uint8_t* load(const char* path, size_t* size) {
  FILE* fp = fopen(path, "rb");
  if (!fp) {
    fprintf(stderr, "%s: cannot open\n", path);
    return NULL;
  }
  uint8_t* data = NULL;
  *size = 0;
  if (!fseek(fp, 0, SEEK_END)) {
    long n = ftell(fp);
    if (n >= 32 && n <= kMaxFileBytes && !fseek(fp, 0, SEEK_SET) &&
        (data = malloc((size_t)n)))
      *size = fread(data, 1, (size_t)n, fp);
  }
  fclose(fp);
  if (*size < 32 || memcmp(data, "DKIF", 4)) {
    fprintf(stderr, "%s: not an IVF file\n", path);
    free(data);
    return NULL;
  }
  return data;
}
// Parses every frame of an IVF image held in memory. Returns "av1", "vp9" or
// NULL when the header is not one of the two.
static const char* run(const uint8_t* data, size_t size, Digest* d) {
  bool av1 = !memcmp(data + 8, "AV01", 4);
  bool vp9 = !memcmp(data + 8, "VP90", 4);
  size_t pos = (size_t)data[6] | (size_t)data[7] << 8;
  if ((!av1 && !vp9) || pos < 32 || pos > size) return NULL;
  AV1Parser* ap = NULL;
  VP9Parser* vp = NULL;
  if (av1) {
    ap = calloc(1, sizeof(*ap));
    if (ap) av1_parser_init(ap);
  } else {
    vp = calloc(1, sizeof(*vp));
    if (vp) vp9_parser_init(vp);
  }
  if (!ap && !vp) return NULL;
  while (size - pos >= 12) {
    size_t n = le32(data + pos);
    pos += 12;
    if (!n || n > kMaxFrameBytes || n > size - pos) {
      d->errors++;
      break;
    }
    // The frame is parsed from its own allocation, so that a read past its end
    // is seen by the address sanitizer.
    uint8_t* frame = malloc(n);
    if (!frame) break;
    memcpy(frame, data + pos, n);
    int r = av1 ? av1_parse_temporal_unit(ap, frame, n, on_av1, d)
                : vp9_parse_chunk(vp, frame, n, on_vp9, d);
    free(frame);
    if (r) {
      d->errors++;
      mix(d, "error", 5);
    }
    pos += n;
  }
  if (ap) av1_parser_free(ap);
  free(ap);
  free(vp);
  return av1 ? "av1" : "vp9";
}
static int digest_file(const char* path) {
  size_t size;
  uint8_t* data = load(path, &size);
  if (!data) return 1;
  Digest d = {.hash = 0xcbf29ce484222325ull};
  const char* codec = run(data, size, &d);
  free(data);
  if (!codec) {
    fprintf(stderr, "%s: neither AV1 nor VP9, or a bad header\n", path);
    return 1;
  }
  const char* name = strrchr(path, '/');
  printf("%s %s %u %u %u %016llx\n", name ? name + 1 : path, codec, d.decoded,
         d.shown, d.errors, (unsigned long long)d.hash);
  return 0;
}
static uint64_t rng_state;
static uint32_t rng(void) {  // xorshift64*
  rng_state ^= rng_state >> 12;
  rng_state ^= rng_state << 25;
  rng_state ^= rng_state >> 27;
  return (uint32_t)((rng_state * 0x2545F4914F6CDD1Dull) >> 32);
}
// Damages copies of the file and parses them. The parser must refuse or accept
// each one without reading or writing outside its buffers: built with the
// sanitizers, any such access stops the program.
static int mutate_file(const char* path, unsigned rounds) {
  size_t size;
  uint8_t* data = load(path, &size);
  if (!data) return 1;
  uint8_t* copy = malloc(size);
  if (!copy) {
    free(data);
    return 1;
  }
  unsigned refused = 0;
  if (size <= 32) rounds = 0;  // only the IVF header: nothing to damage
  for (unsigned i = 0; i < rounds; i++) {
    memcpy(copy, data, size);
    size_t used = size;
    unsigned changes = 1 + rng() % 8;
    for (unsigned c = 0; c < changes; c++) {
      size_t at = 32 + rng() % (size - 32);
      switch (rng() % 4) {
        case 0:
          copy[at] ^= (uint8_t)(1u << (rng() % 8));
          break;
        case 1:
          copy[at] = (uint8_t)rng();
          break;
        case 2:
          copy[at] = rng() & 1 ? 0xff : 0x00;
          break;
        default:
          if (at > 64) used = at;  // cut the file short
          break;
      }
    }
    Digest d = {.hash = 0};
    run(copy, used, &d);
    if (d.errors) refused++;
  }
  const char* name = strrchr(path, '/');
  printf("%s: %u damaged copies parsed, %u refused\n", name ? name + 1 : path,
         rounds, refused);
  free(copy);
  free(data);
  return 0;
}
int main(int argc, char** argv) {
  if (argc >= 4 && !strcmp(argv[1], "--mutate")) {
    unsigned rounds = (unsigned)strtoul(argv[2], NULL, 10);
    rng_state = 0x9E3779B97F4A7C15ull;
    int bad = 0;
    for (int i = 3; i < argc; i++) bad |= mutate_file(argv[i], rounds);
    return bad;
  }
  if (argc < 2) {
    fprintf(stderr,
            "usage: parsedigest file.ivf [more.ivf ...]\n"
            "       parsedigest --mutate <rounds> file.ivf [more.ivf ...]\n");
    return 2;
  }
  int bad = 0;
  for (int i = 1; i < argc; i++) bad |= digest_file(argv[i]);
  return bad;
}
