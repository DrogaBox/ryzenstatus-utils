// cc_test.c - checks the "cc" patch (Continuity Camera and FaceTime HEVC
// decode) for every validated build of VideoProcessing, on this CPU:
//   1. lookup: cc_locate (the service's own code) finds the four sites
//      exactly once in a __text built around the build's bytes, and refuses a
//      duplicate, a change of any single byte of a site or of B's target, a B
//      whose key load is not K's, an A that removes another slot than the
//      one K stores the key in, and an E whose compares call another function
//      than B's CFStringCompare;
//   2. state: cc_site_state reads the original and the patched bytes back as
//      such, and any other single-byte change as "unexpected bytes";
//   3. code: the original and the patched bytes run on the CPU with the calls
//      going to recorders. A original: HEVC skips the removal, other codecs
//      remove the key only on the board-ids Apple lists; A patched: the key is
//      looked up for removal for every codec and board-id. B original sends
//      DecoderUsage on (flag set) or to the codec checks (flag clear); B
//      patched skips DecoderUsage and sends every other key down the path the
//      original took with the flag set, whatever the flag. E (the whole
//      board-id check) original answers yes for the two board-ids Apple lists
//      and otherwise only for BridgeEncode with a bridge device; E patched
//      never compares the board-id, still releases it, and still answers the
//      BridgeEncode path as the original does;
//   4. this Mac: when its own shared cache holds a validated build, the sites
//      are found once in it, K loads kVTVideoDecoderSpecification_Usage and the
//      calls go to CFDictionaryAddValue (K), CFDictionaryContainsKey (A) and
//      CFStringCompare (B); E compares with the CFStrings Mac-7BA5B2D9E42DDD94
//      and Mac-27AD2F918AE68F61, reads the BridgeEncode preference of
//      com.apple.VideoProcessing and calls CFStringCompare, CFRelease,
//      CFPreferencesGetAppBooleanValue, remote_device_copy_unique_of_type and
//      CFLog;
//   5. files: each VideoProcessing given on the command line (a copy taken out
//      of a dyld shared cache) is checked like 4, by its bytes, and its sites
//      must be where IDA has them.
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <mach-o/loader.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <uuid/uuid.h>

#include "../tool/patches.h"

extern void run_cc(void* entry, uint64_t regs[11]);
extern const void* kVTVideoDecoderSpecification_Usage;

// Where the sites are in each build (read in IDA; vcnencodefix finds them by
// itself), for the layouts below, and A's two exits that skip the removal:
// `skip` (HEVC, straight to the decoder creation) and `noRemove` (the
// board-id check said no; three bytes before `skip`).
static const struct {
  const char* uuid;
  uint64_t site[kCcSites], skip, noRemove;
} kSites[] = {
    {"3EE0D5DE-F382-3E55-B793-03DCA33EB76E",
     {0x7FF912FB4500, 0x7FF912FB5E79, 0x7FF912FBD635, 0x7FF912FA024D},
     0x7FF912FB5F20,
     0x7FF912FB5F1D},  // 26.7.2, 26.7.3
    {"7B6360AC-5775-3F01-B253-5F199DD57F7C",
     {0x7FF90E44CA4B, 0x7FF90E44DD24, 0x7FF90E45259A, 0x7FF90E43CBED},
     0x7FF90E44DDA5,
     0x7FF90E44DDA2},  // 15.8.2
};
static int site_index(const char* uuid) {
  for (size_t i = 0; i < sizeof(kSites) / sizeof(kSites[0]); i++)
    if (!strcmp(kSites[i].uuid, uuid)) return (int)i;
  return -1;
}

static int gFails;
#define CHECK(c, ...)      \
  do {                     \
    if (!(c)) {            \
      printf("FAIL ");     \
      printf(__VA_ARGS__); \
      printf("\n");        \
      gFails++;            \
    }                      \
  } while (0)

static int32_t get32(const uint8_t* p) {
  int32_t v;
  memcpy(&v, p, 4);
  return v;
}

// ---- 1, 2: lookup and state ----

static uint32_t gSeed = 12345;
static uint8_t rnd(void) {
  gSeed = gSeed * 1103515245u + 12345u;
  return (uint8_t)(gSeed >> 16);
}

// A fake __text: random bytes with the first site at 0x1000 and the others at
// their real distances from it.
enum { kTextLen = 0x40000, kCopyAt = 0x3c000 };
static uint64_t at_of(int idx, int k) {
  uint64_t first = kSites[idx].site[0];
  for (int i = 1; i < kCcSites; i++)
    if (kSites[idx].site[i] < first) first = kSites[idx].site[i];
  return 0x1000 + kSites[idx].site[k] - first;
}
static void layout(const CcBuild* b, int idx, uint8_t* text) {
  for (size_t i = 0; i < kTextLen; i++) text[i] = rnd();
  for (int k = 0; k < kCcSites; k++) {
    const CcSite* s = &b->site[k];
    memcpy(text + at_of(idx, k), s->find, s->len);
    if (s->tgtLen) memcpy(text + at_of(idx, k) + s->tgtDist, s->tgt, s->tgtLen);
  }
}

static void test_lookup(const CcBuild* b, int idx) {
  uint8_t* text = malloc(kTextLen);
  uint64_t sites[kCcSites];
  char why[160] = "";
  const uint64_t vm = 0x7ff800000000;
  layout(b, idx, text);
  bool found = cc_locate(b, text, kTextLen, vm, sites, why, sizeof(why));
  for (int k = 0; found && k < kCcSites; k++)
    found = sites[k] == vm + at_of(idx, k);
  CHECK(found, "%s: sites not found where they are (%s)", b->macos, why);
  int refused = 0, tried = 0;
  for (int k = 0; k < kCcSites; k++) {
    const CcSite* s = &b->site[k];
    uint64_t at = at_of(idx, k);
    for (int i = 0; i < s->len; i++) {  // every byte of the site
      layout(b, idx, text);
      text[at + i] ^= 0x01;
      tried++;
      refused += !cc_locate(b, text, kTextLen, vm, sites, why, sizeof(why));
    }
    for (int i = 0; i < s->tgtLen; i++) {  // and of B's target
      layout(b, idx, text);
      text[at + s->tgtDist + i] ^= 0x80;
      tried++;
      refused += !cc_locate(b, text, kTextLen, vm, sites, why, sizeof(why));
    }
    layout(b, idx, text);  // a second copy
    memcpy(text + kCopyAt, s->find, s->len);
    tried++;
    refused += !cc_locate(b, text, kTextLen, vm, sites, why, sizeof(why)) &&
               strstr(why, "2 times");
  }
  // B 16 bytes further: its own bytes and target still match, its key load no
  // longer reads K's key
  layout(b, idx, text);
  const CcSite* s = &b->site[2];
  uint64_t at = at_of(idx, 2);
  memset(text + at, 0x90, s->tgtDist + kCcTgtLen);
  memcpy(text + at + 16, s->find, s->len);
  memcpy(text + at + 16 + s->tgtDist, s->tgt, kCcTgtLen);
  tried++;
  refused += !cc_locate(b, text, kTextLen, vm, sites, why, sizeof(why)) &&
             strstr(why, "same key");
  // K storing the key in another slot than the one A removes (table and
  // bytes changed together)
  CcBuild other = *b;
  other.site[0].find[13] ^= 0x08;
  layout(&other, idx, text);
  tried++;
  refused += !cc_locate(&other, text, kTextLen, vm, sites, why, sizeof(why)) &&
             strstr(why, "remove the key");
  // E's two compares calling another function than B's check (both rel32 moved
  // by one, table and bytes together)
  other = *b;
  for (int c = kCcEFirst; c <= kCcESecond; c += kCcESecond - kCcEFirst)
    other.site[3].find[c + 13]++;
  layout(&other, idx, text);
  tried++;
  refused += !cc_locate(&other, text, kTextLen, vm, sites, why, sizeof(why)) &&
             strstr(why, "CFStringCompare");
  CHECK(refused == tried, "%s: %d of %d altered layouts refused", b->macos,
        refused, tried);
  printf("lookup: found once; %d of %d altered layouts refused\n", refused,
         tried);
  free(text);
}

static void test_state(const CcBuild* b) {
  int other = 0, tried = 0;
  for (int k = 0; k < kCcSites; k++) {
    const CcSite* s = &b->site[k];
    uint8_t cur[kCcMaxFind], tgt[kCcTgtLen], w[kCcMaxWrite];
    memcpy(tgt, s->tgt, kCcTgtLen);
    memcpy(cur, s->find, s->len);
    CHECK(cc_site_state(s, cur, tgt) == 0, "%s site %c: original not seen",
          b->macos, kCcSiteName[k]);
    build_cc(s, w);
    memcpy(cur + s->off, w, s->n);
    CHECK(cc_site_state(s, cur, tgt) == (s->n ? 1 : 0),
          "%s site %c: patched not seen", b->macos, kCcSiteName[k]);
    for (int base = 0; base < 2; base++)  // from original, from patched
      for (int i = 0; i < s->len; i++) {
        memcpy(cur, s->find, s->len);
        if (base) memcpy(cur + s->off, w, s->n);
        cur[i] ^= 0x10;
        tried++;
        other += cc_site_state(s, cur, tgt) == -1;
      }
    if (s->tgtLen) {
      memcpy(cur, s->find, s->len);
      tgt[5] ^= 1;
      tried++;
      other += cc_site_state(s, cur, tgt) == -1;
    }
  }
  CHECK(other == tried, "%s: %d of %d altered sites seen as other", b->macos,
        other, tried);
  printf(
      "state: original and patched read back; %d of %d altered sites left "
      "alone\n",
      other, tried);
}

// ---- 3: code ----

static const uint8_t kMark[] = {0x6a, 0x00, 0x41, 0x5a, 0x41, 0xff, 0xe3};
static void mark(uint8_t* p, uint8_t id) {
  memcpy(p, kMark, sizeof(kMark));
  p[1] = id;
}
// A recorder of rdi, rsi, rdx and the call count at rec[0..3]; with `cmp` it
// also returns 0 when rdi == rsi (CFStringCompare's "equal"), else 1.
static void thunk(uint8_t* p, uint64_t* rec, bool cmp) {
  static const uint8_t head[] = {0x48, 0x89, 0x38, 0x48, 0x89, 0x70, 0x08, 0x48,
                                 0x89, 0x50, 0x10, 0x48, 0xff, 0x40, 0x18};
  static const uint8_t ret0[] = {0x31, 0xc0, 0x48, 0x39, 0xf7,
                                 0x0f, 0x95, 0xc0, 0xc3};
  p[0] = 0x48;
  p[1] = 0xb8;  // movabs rax, rec
  memcpy(p + 2, &rec, 8);
  memcpy(p + 10, head, sizeof(head));
  if (cmp)
    memcpy(p + 10 + sizeof(head), ret0, sizeof(ret0));
  else
    p[10 + sizeof(head)] = 0xc3;
}

enum { kPad = 0x1000 };
// Executable space from the site to the farthest address its code refers to.
static uint8_t* space(uint64_t far, size_t* len) {
  *len = (far + kPad * 2 + 0xfff) & ~0xfffull;
  uint8_t* m = mmap(NULL, *len, PROT_READ | PROT_WRITE | PROT_EXEC,
                    MAP_ANON | MAP_PRIVATE, -1, 0);
  return m == MAP_FAILED ? NULL : m;
}

static const uint64_t kKey = 0x4b45590000000001, kOtherKey = 0x4f54480000000002,
                      kDict = 0x4449430000000003;

// "add r10, <id>; jmp r11": an exit that adds to r10 (so a 3-byte "inc r10"
// right before it counts as another exit).
static void mark_add(uint8_t* p, uint8_t id) {
  static const uint8_t m[] = {0x49, 0x83, 0xc2, 0x00, 0x41, 0xff, 0xe3};
  memcpy(p, m, sizeof(m));
  p[3] = id;
}
// "movabs rax, &val; mov eax, [rax]; ret": the board-id check, answering val.
static void answer(uint8_t* p, const uint32_t* val) {
  p[0] = 0x48;
  p[1] = 0xb8;
  memcpy(p + 2, &val, 8);
  p[10] = 0x8b;
  p[11] = 0x00;
  p[12] = 0xc3;
}

static void test_code_a(const CcBuild* b, int idx) {
  const CcSite* s = &b->site[1];
  uint64_t base = kSites[idx].site[1];
  uint64_t skipOff = kSites[idx].skip - base,
           noRemOff = kSites[idx].noRemove - base;
  // the board-id call is 10 bytes before the removal (call, cmp eax 1, jnz),
  // the ContainsKey call ends the site
  int call = s->tgtDist - 10;
  uint64_t boardOff = call + 5 + (int64_t)get32(s->find + call + 1);
  uint64_t containsOff = s->len + (int64_t)get32(s->find + s->len - 4);
  CHECK(s->find[call] == 0xe8, "%s A: no board-id call", b->macos);
  int slotAt = 0;  // the slot the removal reads the key from
  for (int i = s->tgtDist; i < s->tgtDist + 10; i++)
    if (s->find[i] == 0x48 && s->find[i + 1] == 0x8b && s->find[i + 2] == 0xb5)
      slotAt = i;
  int32_t slot = get32(s->find + slotAt + 3);
  size_t len;
  uint64_t far = containsOff > boardOff ? containsOff : boardOff;
  uint8_t* m = space(far + 64, &len);
  if (!m) {
    printf("FAIL mmap\n");
    gFails++;
    return;
  }
  uint8_t* site = m + kPad;
  uint64_t rec[4];
  static uint32_t board;
  thunk(site + containsOff, rec, false);
  answer(site + boardOff, &board);
  static const uint32_t kHvc1 = 0x68766331, kAvc1 = 0x61766331;
  int ok = 0, runs = 0;
  for (int patched = 0; patched < 2; patched++)
    for (int codec = 0; codec < 2; codec++)
      for (int mp = 0; mp < 2; mp++) {
        memcpy(site, s->find, s->len);
        if (patched) build_cc(s, site + s->off);
        mark(site + s->len, 1);  // reached the key lookup of the removal
        site[noRemOff] = 0x49;   // inc r10: no removal (then 4 more: 5) ...
        site[noRemOff + 1] = 0xff;
        site[noRemOff + 2] = 0xc2;
        mark_add(site + skipOff, 4);  // ... the HEVC skip: 4
        uint8_t obj[64] = {0};
        uint32_t fourcc = codec ? kAvc1 : kHvc1;
        memcpy(obj + 0x18, &fourcc, 4);
        board = mp ? 1 : 4;  // 1: a board-id Apple lists; 4: one it does not
        uint64_t frame[64];
        for (int i = 0; i < 64; i++) frame[i] = kDict;  // [rbp-90h] = the spec
        uint8_t* rbp = (uint8_t*)&frame[48];
        uint64_t objPtr = (uint64_t)obj;
        memcpy(rbp - 0x88, &objPtr, 8);
        memcpy(rbp + slot, &kKey, 8);
        memset(rec, 0, sizeof(rec));
        uint64_t r[11] = {0, (uint64_t)rbp, 0, kDict};
        run_cc(site, r);
        uint64_t want = patched ? 1 : !codec ? 4 : mp ? 1 : 5;
        bool good = r[4] == want;
        if (want == 1)  // CFDictionaryContainsKey(spec, DecoderUsage)
          good = good && rec[3] == 1 && rec[0] == kDict && rec[1] == kKey;
        else
          good = good && rec[3] == 0;
        runs++;
        ok += good;
        CHECK(good, "%s A %s %s board %u: exit %llu (want %llu), lookups %llu",
              b->macos, patched ? "patched" : "original",
              codec ? "avc1" : "hvc1", board, r[4], want, rec[3]);
      }
  printf(
      "code A: %d of %d runs as expected (patched: the key is looked up for "
      "removal for every codec and board-id)\n",
      ok, runs);
  munmap(m, len);
}

static void test_code_b(const CcBuild* b) {
  const CcSite* s = &b->site[2];
  const uint8_t* t = s->tgt;
  uint64_t tgtOff = s->tgtDist;
  uint64_t gotOff = tgtOff + 7 + (int64_t)get32(t + 3);
  uint64_t stubOff = tgtOff + 23 + (int64_t)get32(t + 19);  // call at +18
  CHECK(t[18] == 0xe8, "%s B: no call at +18 of the target", b->macos);
  uint64_t jzOff = s->off + 10 + (int64_t)get32(s->find + s->off + 6);
  uint8_t flagAt = s->find[s->off + 2];
  size_t len;
  uint64_t far = gotOff > stubOff ? gotOff : stubOff;
  uint8_t* m = space((far > jzOff ? far : jzOff) + 64, &len);
  if (!m) {
    printf("FAIL mmap\n");
    gFails++;
    return;
  }
  uint8_t* site = m + kPad;
  static uint64_t keyVar = kKey;
  const void* keyPtr = &keyVar;
  memcpy(site + gotOff, &keyPtr, 8);
  uint64_t rec[4];
  thunk(site + stubOff, rec, true);
  int ok = 0, runs = 0;
  for (int patched = 0; patched < 2; patched++)
    for (int flag = 0; flag < 2; flag++)
      for (int usage = 0; usage < 2; usage++) {
        memcpy(site, s->find, s->len);
        if (patched) build_cc(s, site + s->off);
        memcpy(site + tgtOff, t, kCcTgtLen);
        mark(site + s->off + s->n, 3);       // the original's flag-set path
        mark(site + jzOff, 4);               // the codec and board-id checks
        mark(site + tgtOff + kCcTgtLen, 1);  // DecoderUsage skipped
        uint8_t session[256] = {0};
        session[flagAt] = (uint8_t)flag;
        uint64_t key = usage ? kKey : kOtherKey;
        memset(rec, 0, sizeof(rec));
        uint64_t r[11] = {(uint64_t)session, 0, key, key};
        run_cc(site + s->off, r);
        uint64_t want = !patched ? (flag ? 3 : 4) : (usage ? 1 : 3);
        bool good = r[4] == want;
        if (patched)  // the check compared the key with DecoderUsage, once
          good = good && rec[3] == 1 && rec[0] == key && rec[1] == kKey;
        runs++;
        ok += good;
        CHECK(good, "%s B %s flag=%d key=%s: exit %llu (want %llu)", b->macos,
              patched ? "patched" : "original", flag,
              usage ? "DecoderUsage" : "other", r[4], want);
      }
  printf(
      "code B: %d of %d runs as expected (patched: DecoderUsage skipped, "
      "other keys on the original path)\n",
      ok, runs);
  munmap(m, len);
}

// "movabs rax, &val; mov rax, [rax]; ret": a call answering val (64 bits).
static void answer64(uint8_t* p, const uint64_t* val) {
  p[0] = 0x48;
  p[1] = 0xb8;
  memcpy(p + 2, &val, 8);
  p[10] = 0x48;
  p[11] = 0x8b;
  p[12] = 0x00;
  p[13] = 0xc3;
}
// "jmp to": the stubs of a shared cache are 6 bytes apart, the thunks longer.
static void jmp_to(uint8_t* p, const uint8_t* to) {
  p[0] = 0xe9;
  int32_t rel = (int32_t)(to - (p + 5));
  memcpy(p + 1, &rel, 4);
}

static void test_code_e(const CcBuild* b) {
  const CcSite* s = &b->site[3];
  const uint8_t* f = s->find;
  const int a = kCcEFirst, c2 = kCcESecond, r = kCcERelease;
  // the calls of the check, by their place in it
  int64_t readOff = 11 + (int64_t)get32(f + 7);
  int64_t cmpOff = a + 17 + (int64_t)get32(f + a + 13);
  int64_t relOff = r + 8 + (int64_t)get32(f + r + 4);
  int64_t prefOff = 0x5e + (int64_t)get32(f + 0x5a);
  int64_t devOff = 0x6c + (int64_t)get32(f + 0x68);
  int64_t logOff = 0x9e + (int64_t)get32(f + 0x9a);
  bool shape = f[0x59] == 0xe8 && f[0x67] == 0xe8 && f[0x99] == 0xe8 &&
               f[0x79] == 0xe8 && 0x7e + get32(f + 0x7a) == relOff &&
               readOff < 0 && readOff > -kPad;
  CHECK(shape, "%s E: calls not where expected", b->macos);
  if (!shape) return;
  int64_t far = cmpOff;
  int64_t offs[] = {relOff, prefOff, devOff, logOff};
  for (int i = 0; i < 4; i++)
    if (offs[i] > far) far = offs[i];
  size_t len;
  uint8_t* m = space((uint64_t)far + 64 + 6 * 64, &len);
  if (!m) {
    printf("FAIL mmap\n");
    gFails++;
    return;
  }
  uint8_t* site = m + kPad;
  uint8_t* th = site + far + 64;  // the thunks, 64 bytes each
  static uint64_t board, dev;
  static uint32_t pref;
  uint64_t recCmp[4], recRel[4], recLog[4];
  answer64(site + readOff, &board);
  thunk(th, recCmp, true);
  jmp_to(site + cmpOff, th);
  thunk(th + 64, recRel, false);
  jmp_to(site + relOff, th + 64);
  answer(th + 128, &pref);
  jmp_to(site + prefOff, th + 128);
  answer64(th + 192, &dev);
  jmp_to(site + devOff, th + 192);
  thunk(th + 256, recLog, false);
  jmp_to(site + logOff, th + 256);
  // the addresses the two lea rsi produce: the board-id CFStrings
  uint64_t id1 = (uint64_t)site + a + 7 + (int64_t)get32(f + a + 3);
  uint64_t id2 = (uint64_t)site + c2 + 7 + (int64_t)get32(f + c2 + 3);
  const uint64_t other = 0x4f54480000000010, bridge = 0x4252490000000020;
  const uint64_t boards[] = {0, id1, id2, other};
  int ok = 0, runs = 0;
  for (int patched = 0; patched < 2; patched++)
    for (int bi = 0; bi < 4; bi++)
      for (int path = 0; path < 3; path++) {  // no pref; pref, no device; both
        memcpy(site, f, s->len);
        uint8_t w[kCcMaxWrite];
        build_cc(s, w);
        if (patched) memcpy(site + s->off, w, s->n);
        board = boards[bi];
        pref = path > 0;
        dev = path == 2 ? bridge : 0;
        memset(recCmp, 0, sizeof(recCmp));
        memset(recRel, 0, sizeof(recRel));
        memset(recLog, 0, sizeof(recLog));
        uint64_t (*check)(void) = (uint64_t (*)(void))(void*)site;
        uint8_t got = (uint8_t)check();
        bool listed = !patched && (bi == 1 || bi == 2);
        uint8_t want = listed || path == 2;
        uint64_t cmps = patched || bi == 0 ? 0 : bi == 1 ? 1 : 2;
        // released: the board-id string (when there is one), and the device
        // when the BridgeEncode path found one; a listed board-id ends there
        uint64_t rels = (bi != 0) + (!listed && path == 2);
        uint64_t logs = !listed && path == 1;
        bool good = got == want && recCmp[3] == cmps && recRel[3] == rels &&
                    recLog[3] == logs;
        if (good && rels)  // the last release: the device, else the board-id
          good = recRel[0] == (!listed && path == 2 ? bridge : board);
        runs++;
        ok += good;
        CHECK(good,
              "%s E %s board %d path %d: answer %d (want %d), compares %llu "
              "(want %llu), releases %llu (want %llu), logs %llu",
              b->macos, patched ? "patched" : "original", bi, path, got, want,
              recCmp[3], cmps, recRel[3], rels, recLog[3]);
      }
  printf(
      "code E: %d of %d runs as expected (patched: the board-id is released "
      "without being compared, BridgeEncode answers as before)\n",
      ok, runs);
  munmap(m, len);
}

// ---- 4, 5: real images ----

static const struct section_64* text_of(const struct mach_header_64* mh,
                                        size_t avail, const uint8_t** uuid) {
  if (avail < sizeof(*mh) || mh->magic != MH_MAGIC_64 ||
      mh->sizeofcmds > avail - sizeof(*mh))
    return NULL;
  const uint8_t *p = (const uint8_t*)(mh + 1), *end = p + mh->sizeofcmds;
  const struct section_64* text = NULL;
  *uuid = NULL;
  for (uint32_t i = 0; i < mh->ncmds && p + sizeof(struct load_command) <= end;
       i++) {
    const struct load_command* c = (const void*)p;
    if (c->cmdsize < sizeof(*c) || p + c->cmdsize > end) return NULL;
    if (c->cmd == LC_SEGMENT_64) {
      const struct segment_command_64* seg = (const void*)c;
      const struct section_64* sec = (const void*)(seg + 1);
      for (uint32_t j = 0; j < seg->nsects; j++)
        if (!strcmp(sec[j].segname, "__TEXT") &&
            !strcmp(sec[j].sectname, "__text"))
          text = &sec[j];
    } else if (c->cmd == LC_UUID)
      *uuid = ((const struct uuid_command*)c)->uuid;
    p += c->cmdsize;
  }
  return text;
}

// Checks one image: its build must be validated and all sites found once.
// Returns the build or NULL.
static const CcBuild* check_image(const char* what, const uint8_t* text,
                                  size_t size, uint64_t vm, const uint8_t* uuid,
                                  uint64_t sites[kCcSites]) {
  char u[40];
  uuid_unparse_upper(uuid, u);
  const CcBuild* b = cc_build(u);
  if (!b) {
    printf("FAIL %s: build %s is not in the table\n", what, u);
    gFails++;
    return NULL;
  }
  char why[160];
  if (!cc_locate(b, text, size, vm, sites, why, sizeof(why))) {
    printf("FAIL %s (%s): %s\n", what, b->macos, why);
    gFails++;
    return NULL;
  }
  printf("%s: %s, all sites found once\n", what, b->macos);
  return b;
}

static const char* sym(uint64_t a) {
  Dl_info i;
  return dladdr((void*)a, &i) && i.dli_sname ? i.dli_sname : "?";
}
static uint64_t stub_target(uint64_t stub) {  // jmp [rip+X]
  const uint8_t* p = (const uint8_t*)stub;
  if (p[0] != 0xff || p[1] != 0x25) return stub;
  return *(const uint64_t*)(stub + 6 + get32(p + 2));
}

static void test_live(void) {
  void* h = dlopen(kCcImage, RTLD_NOW);
  if (!h) {
    printf("this Mac: VideoProcessing not loadable (%s), skipped\n", dlerror());
    return;
  }
  Dl_info info;
  void* any = dlsym(h, "VCPDecompressionSessionSetProperty");
  if (!any || !dladdr(any, &info)) {
    printf(
        "FAIL this Mac: VideoProcessing has no "
        "VCPDecompressionSessionSetProperty\n");
    gFails++;
    return;
  }
  const struct mach_header_64* mh = info.dli_fbase;
  const uint8_t* uuid;
  const struct section_64* text = text_of(mh, 65536, &uuid);
  if (!text || !uuid) {
    printf("FAIL this Mac: no __text\n");
    gFails++;
    return;
  }
  // the load commands hold unslid addresses; __TEXT starts at the header
  uint64_t slide = 0;
  const uint8_t* p = (const uint8_t*)(mh + 1);
  for (uint32_t i = 0; i < mh->ncmds; i++) {
    const struct segment_command_64* seg = (const void*)p;
    if (seg->cmd == LC_SEGMENT_64 && !strcmp(seg->segname, "__TEXT"))
      slide = (uint64_t)mh - seg->vmaddr;
    p += seg->cmdsize;
  }
  char u[40];
  uuid_unparse_upper(uuid, u);
  if (!cc_build(u)) {
    printf("this Mac: VideoProcessing %s is not a validated build, skipped\n",
           u);
    return;
  }
  uint64_t sites[kCcSites];
  const CcBuild* b =
      check_image("this Mac", (const uint8_t*)(text->addr + slide), text->size,
                  text->addr + slide, uuid, sites);
  if (!b) return;
  const CcSite *K = &b->site[0], *A = &b->site[1], *B = &b->site[2];
  uint64_t got = sites[0] + 7 + (int64_t)get32(K->find + 3);
  uint64_t add =
      stub_target(sites[0] + K->len + (int64_t)get32(K->find + K->len - 4));
  uint64_t has =
      stub_target(sites[1] + A->len + (int64_t)get32(A->find + A->len - 4));
  uint64_t t = sites[2] + B->tgtDist;
  uint64_t cmp = stub_target(t + 23 + (int64_t)get32(B->tgt + 19));
  bool keyOk = *(const void* const*)got == &kVTVideoDecoderSpecification_Usage;
  CHECK(keyOk,
        "this Mac: K's key load does not read "
        "kVTVideoDecoderSpecification_Usage");
  CHECK(!strcmp(sym(add), "CFDictionaryAddValue"), "this Mac: K calls %s",
        sym(add));
  CHECK(!strcmp(sym(has), "CFDictionaryContainsKey"), "this Mac: A calls %s",
        sym(has));
  CHECK(!strcmp(sym(cmp), "CFStringCompare"), "this Mac: B's check calls %s",
        sym(cmp));
  printf(
      "this Mac: K loads kVTVideoDecoderSpecification_Usage and calls %s; A "
      "calls %s; B's check calls %s\n",
      sym(add), sym(has), sym(cmp));
  // E: what the lea instructions point to and where the calls go
  const uint8_t* e = (const uint8_t*)sites[3];
#define LEA(o) ((CFStringRef)(sites[3] + (o) + 7 + (int64_t)get32(e + (o) + 3)))
#define CALL(o) stub_target(sites[3] + (o) + 5 + (int64_t)get32(e + (o) + 1))
  struct {
    CFStringRef got;
    const char* want;
  } str[] = {{LEA(kCcEFirst), "Mac-7BA5B2D9E42DDD94"},
             {LEA(kCcESecond), "Mac-27AD2F918AE68F61"},
             {LEA(kCcERelease + 8), "BridgeEncode"},
             {LEA(kCcERelease + 15), "com.apple.VideoProcessing"}};
  for (size_t i = 0; i < sizeof(str) / sizeof(str[0]); i++) {
    char buf[64] = "";
    bool isStr =
        CFGetTypeID(str[i].got) == CFStringGetTypeID() &&
        CFStringGetCString(str[i].got, buf, sizeof(buf), kCFStringEncodingUTF8);
    CHECK(isStr && !strcmp(buf, str[i].want), "this Mac: E's string %zu is %s",
          i, buf);
  }
  struct {
    int at;
    const char* want;
  } call[] = {{kCcEFirst + 12, "CFStringCompare"},
              {kCcESecond + 12, "CFStringCompare"},
              {kCcERelease + 3, "CFRelease"},
              {0x59, "CFPreferencesGetAppBooleanValue"},
              {0x67, "remote_device_copy_unique_of_type"},
              {0x79, "CFRelease"},
              {0x99, "CFLog"}};
  for (size_t i = 0; i < sizeof(call) / sizeof(call[0]); i++)
    CHECK(e[call[i].at] == 0xe8 && !strcmp(sym(CALL(call[i].at)), call[i].want),
          "this Mac: E's call at +0x%x goes to %s", call[i].at,
          sym(CALL(call[i].at)));
#undef LEA
#undef CALL
  printf(
      "this Mac: E compares the board-id with Mac-7BA5B2D9E42DDD94 and "
      "Mac-27AD2F918AE68F61, then reads BridgeEncode; its calls go where "
      "expected\n");
}

static void test_file(const char* path) {
  int fd = open(path, O_RDONLY);
  struct stat st;
  if (fd < 0 || fstat(fd, &st) != 0) {
    printf("FAIL %s: cannot open\n", path);
    gFails++;
    if (fd >= 0) close(fd);
    return;
  }
  void* map = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
  close(fd);
  if (map == MAP_FAILED) {
    printf("FAIL %s: cannot map\n", path);
    gFails++;
    return;
  }
  const uint8_t* uuid;
  const struct section_64* text = text_of(map, (size_t)st.st_size, &uuid);
  if (!text || !uuid ||
      (uint64_t)text->offset + text->size > (uint64_t)st.st_size)
    printf("FAIL %s: not a single-architecture x86_64 image\n", path), gFails++;
  else {
    uint64_t sites[kCcSites];
    const CcBuild* b = check_image(path, (const uint8_t*)map + text->offset,
                                   text->size, text->addr, uuid, sites);
    int idx = b ? site_index(b->uuid) : -1;
    for (int k = 0; idx >= 0 && k < kCcSites; k++)
      CHECK(sites[k] == kSites[idx].site[k],
            "%s: site %c at 0x%llx, IDA had 0x%llx", path, kCcSiteName[k],
            sites[k], kSites[idx].site[k]);
  }
  munmap(map, (size_t)st.st_size);
}

int main(int argc, char** argv) {
  setvbuf(stdout, NULL, _IOLBF, 0);
  size_t n = 0;
  for (const CcBuild* b; (b = cc_build_at(n)); n++) {
    int idx = site_index(b->uuid);
    printf("== %s (%s)\n", b->macos, b->uuid);
    if (idx < 0) {
      printf("FAIL no site addresses for this build\n");
      gFails++;
      continue;
    }
    test_lookup(b, idx);
    test_state(b);
    test_code_a(b, idx);
    test_code_b(b);
    test_code_e(b);
  }
  printf("== real images\n");
  test_live();
  for (int i = 1; i < argc; i++) test_file(argv[i]);
  printf("%zu builds tested, %d failures\n", n, gFails);
  return gFails ? 1 : 0;
}
