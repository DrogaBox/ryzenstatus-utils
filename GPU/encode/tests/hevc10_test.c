// hevc10_test.c - host-only checks for the "hevc10" patch table:
//   - table sizes and write length <= find length;
//   - rip-relative vmovsd loads in site A are preserved unchanged;
//   - unknown UUIDs are rejected and the validated 26.7.3 UUID is found;
//   - when this host's dyld shared cache carries a validated AMDRadeonVADriver2
//     build, each find pattern occurs exactly once in its __text.
// Touches no GPU and no other process.
#include <mach-o/loader.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <uuid/uuid.h>

#include "../tool/patches.h"

struct dyld_shared_cache_dylib_text_info {
  uint64_t version;
  uint64_t loadAddressUnslid;
  uint64_t textSegmentSize;
  uuid_t dylibUuid;
  const char* path;
  uint64_t textSegmentOffset;
};
extern int dyld_shared_cache_iterate_text(
    const uuid_t cacheUuid,
    void (^callback)(const struct dyld_shared_cache_dylib_text_info* info));
extern bool _dyld_get_shared_cache_uuid(uuid_t uuid);
extern const void* _dyld_get_shared_cache_range(size_t* length);

static const struct section_64* macho_text(const struct mach_header_64* mh,
                                           size_t avail) {
  if (avail < sizeof(*mh) || mh->magic != MH_MAGIC_64 ||
      mh->sizeofcmds > avail - sizeof(*mh))
    return NULL;
  const uint8_t *p = (const uint8_t*)(mh + 1), *end = p + mh->sizeofcmds;
  for (uint32_t i = 0; i < mh->ncmds && p + sizeof(struct load_command) <= end;
       i++) {
    const struct load_command* c = (const void*)p;
    if (c->cmdsize < sizeof(*c) || p + c->cmdsize > end) return NULL;
    if (c->cmd == LC_SEGMENT_64) {
      const struct segment_command_64* seg = (const void*)c;
      const struct section_64* sec = (const void*)(seg + 1);
      for (uint32_t j = 0;
           j < seg->nsects && (const uint8_t*)(sec + j + 1) <= p + c->cmdsize;
           j++)
        if (!strcmp(sec[j].segname, "__TEXT") &&
            !strcmp(sec[j].sectname, "__text"))
          return &sec[j];
    }
    p += c->cmdsize;
  }
  return NULL;
}

static size_t count_matches(const uint8_t* hay, size_t n, const uint8_t* needle,
                            size_t len, size_t* at) {
  size_t m = 0;
  for (size_t i = 0; i + len <= n; i++)
    if (hay[i] == needle[0] && !memcmp(hay + i, needle, len)) {
      m++;
      *at = i;
    }
  return m;
}

int main(void) {
  int fails = 0;

  // Table invariants
  if (kHevc10FmtLen > kHevc10FmtFindLen || kHevc10FmtFindLen != 96 ||
      kHevc10FmtLen != 96) {
    printf("FAIL: bad format lengths (find=%d write=%d)\n", kHevc10FmtFindLen,
           kHevc10FmtLen);
    fails++;
  }
  if (kHevc10DbkLen > kHevc10DbkFindLen || kHevc10DbkFindLen != 52 ||
      kHevc10DbkLen != 45) {
    printf("FAIL: bad deblocking lengths (find=%d write=%d)\n",
           kHevc10DbkFindLen, kHevc10DbkLen);
    fails++;
  }
  if (hevc10_build("00000000-0000-0000-0000-000000000000") != NULL) {
    printf("FAIL: unknown UUID matched\n");
    fails++;
  }
  const Hevc10Build* b = hevc10_build("1181E2CA-31B3-3DF0-90E2-3AE70552D753");
  if (!b) {
    printf("FAIL: 26.7.3 UUID missing from table\n");
    return 1;
  }
  if (sizeof(b->fmtFind) != kHevc10FmtFindLen ||
      sizeof(b->fmtRepl) != kHevc10FmtLen ||
      sizeof(b->dbkFind) != kHevc10DbkFindLen ||
      sizeof(b->dbkRepl) != kHevc10DbkLen) {
    printf("FAIL: struct array sizes do not match constants\n");
    fails++;
  }
  // Site A rip-relative vmovsd loads (bytes 16..23 and 26..33) must stay
  // identical.
  if (memcmp(b->fmtFind + 16, b->fmtRepl + 16, 8) != 0 ||
      memcmp(b->fmtFind + 26, b->fmtRepl + 26, 8) != 0) {
    printf("FAIL: site A rip-relative loads differ between find and repl\n");
    fails++;
  }

  // Live shared cache check (when this host has a validated AMDRadeonVADriver2)
  size_t cacheLen = 0;
  const uint8_t* base = _dyld_get_shared_cache_range(&cacheLen);
  uuid_t cache;
  if (!base || memcmp(base, "dyld_v1", 7) != 0 ||
      !_dyld_get_shared_cache_uuid(cache)) {
    printf("skip live check: no dyld shared cache\n");
  } else {
    uint32_t mappingOffset = 0;
    uint64_t unslidBase = 0;
    memcpy(&mappingOffset, base + 16, 4);
    memcpy(&unslidBase, base + mappingOffset, 8);
    uint64_t slide = (uint64_t)base - unslidBase;
    __block uint64_t unslid = 0;
    char uuidStr[40] = "";
    char* uuidOut = uuidStr;
    dyld_shared_cache_iterate_text(
        cache, ^(const struct dyld_shared_cache_dylib_text_info* info) {
          if (info->path && !strcmp(info->path, kPresetImage)) {
            unslid = info->loadAddressUnslid;
            uuid_unparse_upper(info->dylibUuid, uuidOut);
          }
        });
    const Hevc10Build* host = unslid ? hevc10_build(uuidStr) : NULL;
    if (!unslid) {
      printf("skip live check: AMDRadeonVADriver2 not in shared cache\n");
    } else if (!host) {
      printf("skip live check: host build %s not in hevc10 table\n", uuidStr);
    } else {
      const struct mach_header_64* mh = (const void*)(unslid + slide);
      const struct section_64* text = macho_text(mh, 65536);
      if (!text) {
        printf("FAIL: AMDRadeonVADriver2 has no __text\n");
        fails++;
      } else {
        const uint8_t* t = (const void*)(text->addr + slide);
        size_t atFmt = 0, atDbk = 0;
        size_t mFmt = count_matches(t, text->size, host->fmtFind,
                                    kHevc10FmtFindLen, &atFmt);
        size_t mDbk = count_matches(t, text->size, host->dbkFind,
                                    kHevc10DbkFindLen, &atDbk);
        if (mFmt != 1) {
          printf("FAIL: site A matched %zu times (expected 1)\n", mFmt);
          fails++;
        }
        if (mDbk != 1) {
          printf("FAIL: site B matched %zu times (expected 1)\n", mDbk);
          fails++;
        }
        if (mFmt == 1 && mDbk == 1)
          printf("live %s (%s): site A +0x%zx, site B +0x%zx (1 match each)\n",
                 host->macos, uuidStr, atFmt, atDbk);
      }
    }
  }

  printf("hevc10_test: %d failures\n", fails);
  return fails ? 1 : 0;
}
