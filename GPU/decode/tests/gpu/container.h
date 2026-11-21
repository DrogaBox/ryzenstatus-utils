// Minimal IVF and WebM readers for the test tools: one chunk per container
// frame, video track only, no lacing. The whole file is read into memory.
//
// A reader that stops early would make a test pass on half a file, so the two
// ways of stopping are kept apart: at the clean end of the file
// container_next() returns false and leaves `problem` NULL; when the file is
// damaged or cut short it returns false and `problem` says why.
#pragma once
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  uint8_t* data;
  size_t size, pos;
  bool ivf;
  // First video track from Tracks; 0 until it is seen.
  uint64_t video_track;
  // Why the file could not be opened or read to its end; NULL when all is
  // well.
  const char* problem;
} Container;

// The file is loaded whole. 4 GiB holds any test clip, long 4K benchmark files
// included, and still stops a wrong path (a disk image, a device) early.
static const uint64_t kContainerMaxBytes = (uint64_t)4 << 30;

static inline bool container_fail(Container* c, FILE* fp, const char* why) {
  if (fp) fclose(fp);
  free(c->data);
  memset(c, 0, sizeof(*c));
  c->problem = why;
  return false;
}

static inline bool container_open(Container* c, const char* path) {
  memset(c, 0, sizeof(*c));
  if (!path) return container_fail(c, NULL, "no file name");
  FILE* fp = fopen(path, "rb");
  if (!fp) return container_fail(c, NULL, strerror(errno));
  if (fseek(fp, 0, SEEK_END) != 0)
    return container_fail(c, fp, "cannot find the end of the file");
  long n = ftell(fp);
  if (n < 0 || fseek(fp, 0, SEEK_SET) != 0)
    return container_fail(c, fp, "cannot read the size of the file");
  if ((uint64_t)n > kContainerMaxBytes)
    return container_fail(c, fp, "larger than 4 GiB");
  if (n > 0) {
    c->data = (uint8_t*)malloc((size_t)n);
    if (!c->data) return container_fail(c, fp, "out of memory");
    c->size = fread(c->data, 1, (size_t)n, fp);
    if (ferror(fp) || c->size != (size_t)n)
      return container_fail(c, fp, "read error");
  }
  fclose(fp);
  if (c->size >= 32 && !memcmp(c->data, "DKIF", 4)) {
    c->ivf = true;
    size_t hdr = (size_t)(c->data[6] | (c->data[7] << 8));
    if (hdr < 32 || hdr > c->size)
      return container_fail(c, NULL, "bad IVF header length");
    c->pos = hdr;
  }
  return true;
}

static inline void container_close(Container* c) {
  free(c->data);
  c->data = NULL;
  c->size = c->pos = 0;
}

static inline bool ebml_id(Container* c, uint32_t* id) {
  if (c->pos >= c->size) return false;
  uint8_t b = c->data[c->pos];
  int len = b & 0x80 ? 1 : b & 0x40 ? 2 : b & 0x20 ? 3 : b & 0x10 ? 4 : 0;
  if (!len || c->pos + (size_t)len > c->size) return false;
  uint32_t v = 0;
  for (int i = 0; i < len; i++) v = v << 8 | c->data[c->pos++];
  *id = v;
  return true;
}

// Returns false on a malformed size. *unknown is set for an unknown-size master
// element.
static inline bool ebml_size(Container* c, uint64_t* out, bool* unknown) {
  if (c->pos >= c->size) return false;
  uint8_t b = c->data[c->pos];
  int len = 0;
  for (int i = 0; i < 8; i++)
    if (b & (0x80 >> i)) {
      len = i + 1;
      break;
    }
  if (!len || c->pos + (size_t)len > c->size) return false;
  uint64_t v = (uint64_t)(b & (0xff >> len));
  bool all = v == (uint64_t)(0xff >> len);
  c->pos++;
  for (int i = 1; i < len; i++) {
    all = all && c->data[c->pos] == 0xff;
    v = v << 8 | c->data[c->pos++];
  }
  *out = v;
  if (unknown) *unknown = all;
  return true;
}

// Finds the first video track inside a Tracks element. Leaves the position
// where it found it.
static inline void webm_read_tracks(Container* c, size_t end) {
  size_t saved = c->pos;
  while (c->pos < end && !c->video_track) {
    uint32_t id;
    uint64_t sz;
    if (!ebml_id(c, &id) || !ebml_size(c, &sz, NULL)) break;
    if (c->pos > end || sz > end - c->pos) break;
    if (id == 0xAE) {  // TrackEntry
      size_t entry_end = c->pos + (size_t)sz;
      uint64_t number = 0, type = 0;
      while (c->pos < entry_end) {
        uint32_t eid;
        uint64_t esz;
        if (!ebml_id(c, &eid) || !ebml_size(c, &esz, NULL) ||
            c->pos > entry_end || esz > entry_end - c->pos)
          break;
        if ((eid == 0xD7 || eid == 0x83) && esz <= 8) {
          uint64_t v = 0;
          for (uint64_t i = 0; i < esz; i++) v = v << 8 | c->data[c->pos + i];
          if (eid == 0xD7)
            number = v;
          else
            type = v;
        }
        c->pos += (size_t)esz;
      }
      if (type == 1) c->video_track = number;
      c->pos = entry_end;
    } else {
      c->pos += (size_t)sz;
    }
  }
  c->pos = saved;
}

// Next frame of the file, pointing into the file's memory. Returns false at the
// end of the file, and also when the file cannot be read further: then
// c->problem is set.
static inline bool container_next(Container* c, const uint8_t** out,
                                  size_t* size) {
  if (c->problem) return false;
  if (c->ivf) {
    if (c->pos >= c->size) return false;
    if (c->size - c->pos < 12) {
      c->problem = "the file ends inside a frame header";
      return false;
    }
    const uint8_t* h = c->data + c->pos;
    size_t s = (size_t)h[0] | (size_t)h[1] << 8 | (size_t)h[2] << 16 |
               (size_t)h[3] << 24;
    c->pos += 12;
    // An empty frame is reported as a damaged file. A frame that is too big
    // for the decoder is passed on: the decoder says so itself.
    if (!s) {
      c->problem = "a frame with no bytes";
      return false;
    }
    if (s > c->size - c->pos) {
      c->problem = "the file ends inside a frame";
      return false;
    }
    *out = c->data + c->pos;
    *size = s;
    c->pos += s;
    return true;
  }
  for (;;) {
    if (c->pos >= c->size) return false;
    uint32_t id;
    uint64_t sz;
    bool unknown = false;
    if (!ebml_id(c, &id) || !ebml_size(c, &sz, &unknown)) {
      c->problem = "damaged element header, or not an IVF or WebM file";
      return false;
    }
    if (id == 0x18538067 || id == 0x1F43B675 || id == 0xA0)
      continue;  // Segment, Cluster, BlockGroup: descend
    if (unknown) {
      c->problem = "an element of unknown size that cannot be skipped";
      return false;
    }
    if (sz > c->size - c->pos) {
      c->problem = "the file ends inside an element";
      return false;
    }
    if (id == 0x1654AE6B) webm_read_tracks(c, c->pos + (size_t)sz);
    if (id == 0xA3 || id == 0xA1) {  // SimpleBlock, Block
      size_t start = c->pos;
      uint64_t track;
      if (!ebml_size(c, &track, NULL)) {
        c->problem = "damaged block header";
        return false;
      }
      size_t head = c->pos - start + 3;  // track number, timecode, flags
      if (head > sz) {
        c->problem = "a block shorter than its own header";
        return false;
      }
      c->pos = start + (size_t)sz;
      if (c->video_track && track != c->video_track) continue;
      if (head == sz) {
        c->problem = "a frame with no bytes";
        return false;
      }
      *out = c->data + start + head;
      *size = (size_t)sz - head;
      return true;
    }
    c->pos += (size_t)sz;
  }
}
