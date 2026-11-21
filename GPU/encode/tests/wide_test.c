// wide_test.c - runs the exact bytes of the "wide" patch on this CPU and checks
// the arguments it passes to dispatchThreadgroups:threadsPerThreadgroup:, for
// every width/16 from 0 to 1024 (widths up to 16384), once per validated build
// of AppleGVAHEVCEncoder (each at its own call site and cave address).
//
// The original call site and the patched call site + cave are copied into one
// executable buffer at their image offsets (so the rip-relative selector load
// and the jumps resolve as in the real image), and each is run against a stack
// frame holding the values the plug-in's getters return: numThreadgroups = (1,
// vrt, 1) at [rbp-80h] and threadsPerThreadgroup = (hrz, 1, 1) at [rbp-68h].
// Checks:
//   - widths up to 4096 (hrz <= 256): every argument and the selector equal the
//   original ones;
//   - all widths: threadsPerThreadgroup.x <= 256, grid unchanged (tpg.x *
//   groups.x == hrz), y/z unchanged.
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>

#include "../tool/patches.h"

extern void run_site(void* entry, void* frame, uint64_t out[7]);

// Call site and cave of each validated build (read in IDA; vcnencodefix finds
// them by itself at run time).
static const struct {
  const char* uuid;
  uint64_t callVm, caveVm;
} kSites[] = {
    {"D2B848E1-ACD9-396B-8948-0882C65F601F", 0x13601, 0xe78},  // 26.7.3
    {"FD24EB7C-0B0E-3438-A43B-133E93E94EFA", 0x13780, 0xe78},  // 15.8.2, 15.8.3
    {"0FD1FA9F-5DF9-3E5F-A316-21AF738EBBAD", 0x142ca, 0xec8},  // 14.8.9
};
static uint64_t kCallVm;
static const uint8_t kJmpR11[3] = {0x41, 0xff, 0xe3};

static void run(uint8_t* img, uint64_t hrz, uint64_t vrt, uint64_t out[7]) {
  uint64_t frame[32] = {0};
  uint8_t* rbp = (uint8_t*)&frame[32];
  uint64_t groups[3] = {1, vrt, 1}, tpg[3] = {hrz, 1, 1};
  memcpy(rbp - 0x80, groups, 24);
  memcpy(rbp - 0x68, tpg, 24);
  run_site(img + kCallVm, rbp, out);
}

static int test_build(const char* uuid, uint64_t callVm, uint64_t caveVm) {
  const WideBuild* wb = wide_build(uuid);
  if (!wb) {
    printf("FAIL %s: not in the table\n", uuid);
    return 1;
  }
  printf("== %s (%s): site 0x%llx, cave 0x%llx\n", wb->macos, uuid, callVm,
         caveVm);
  kCallVm = callVm;
  size_t size = 0x40000;
  uint8_t* orig = mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC,
                       MAP_ANON | MAP_PRIVATE, -1, 0);
  uint8_t* pat = mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC,
                      MAP_ANON | MAP_PRIVATE, -1, 0);
  if (orig == MAP_FAILED || pat == MAP_FAILED) {
    perror("mmap");
    return 2;
  }
  memcpy(orig + kCallVm, wb->find, kWideCallLen);
  memcpy(orig + kCallVm + kWideCallLen, kJmpR11, 3);
  uint8_t call[kWideCallLen], cave[kWideCaveLen];
  build_wide(wb, call, cave, kCallVm, caveVm);
  memcpy(pat + kCallVm, call, kWideCallLen);
  memcpy(pat + caveVm, cave, kWideCaveLen);
  memcpy(pat + kCallVm + kWideCallLen, kJmpR11, 3);

  int fails = 0, fallback = 0;
  for (uint64_t hrz = 0; hrz <= 1024; hrz++) {
    uint64_t vrt = 1 + (hrz * 7) % 600;
    uint64_t a[7], b[7];
    run(orig, hrz, vrt, a);
    run(pat, hrz, vrt, b);
    uint64_t gx = b[0], gy = b[1], gz = b[2], tx = b[3], ty = b[4], tz = b[5];
    int ok = b[6] == a[6] && gy == vrt && gz == 1 && ty == 1 && tz == 1 &&
             tx * gx == hrz;
    if (hrz > 0) ok = ok && tx >= 1 && tx <= 256;
    if (hrz <= 256) ok = ok && !memcmp(a, b, sizeof(a));
    if (hrz > 256 && tx == 1) fallback++;
    if (!ok) {
      printf(
          "FAIL hrz %llu: groups (%llu,%llu,%llu) tpg (%llu,%llu,%llu) sel "
          "%s\n",
          hrz, gx, gy, gz, tx, ty, tz, b[6] == a[6] ? "same" : "DIFFERENT");
      fails++;
    }
  }
  const int widths[] = {1280, 1920, 3840, 4096, 5120,
                        5760, 6016, 6144, 7680, 8192};
  for (size_t i = 0; i < sizeof(widths) / sizeof(widths[0]); i++) {
    uint64_t b[7];
    run(pat, (uint64_t)widths[i] / 16, 270, b);
    printf(
        "width %5d: numThreadgroups (%llu,%llu,%llu), threadsPerThreadgroup "
        "(%llu,%llu,%llu)\n",
        widths[i], b[0], b[1], b[2], b[3], b[4], b[5]);
  }
  printf(
      "1025 widths checked, %d used the 1-thread fallback (odd width/16 above "
      "256), %d failures\n",
      fallback, fails);
  munmap(orig, size);
  munmap(pat, size);
  return fails ? 1 : 0;
}

int main(void) {
  int bad = 0;
  size_t n = sizeof(kSites) / sizeof(kSites[0]);
  for (size_t i = 0; i < n; i++)
    bad += test_build(kSites[i].uuid, kSites[i].callVm, kSites[i].caveVm) != 0;
  printf("%zu builds tested, %d failed\n", n, bad);
  return bad ? 1 : 0;
}
