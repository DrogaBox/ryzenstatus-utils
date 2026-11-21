// pmlogtest - checks GPUSensors' decisions (sensors/kext/pmlog_logic.hpp)
// without a GPU or a kernel.
//
//   pmlogtest                 the built-in cases
//   pmlogtest <entries.txt>   also the function entries printed by
//                             tools/driver/kcfunc.py: each must be accepted
//
// Exit status 0 = every check passed.
#include <stdio.h>
#include <string.h>

#include "pmlog_logic.hpp"

static int failures = 0;
static void check(bool ok, const char* what) {
  printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  if (!ok) failures++;
}

static void put(uint8_t* log, size_t id, uint32_t flag, uint32_t value) {
  memcpy(log + 4 + 8 * id, &flag, 4);
  memcpy(log + 8 + 8 * id, &value, 4);
}

int main(int argc, char** argv) {
  using namespace gpusens;
  static_assert(kIdCount == 256, "2052 bytes hold 256 entries");
  static_assert(8 + 8 * (kIdCount - 1) + 4 == kLogBytes,
                "the last value ends the log");

  uint8_t log[kLogBytes] = {};
  check(!plausible(log), "an empty log is not kept (GPU powered down)");
  put(log, 27, 1, 44);
  put(log, 8, 1, 38);
  put(log, 14, 1, 1200);
  check(plausible(log), "a filled log is kept");
  uint32_t v = 0;
  check(entry(log, 27, &v) && v == 44, "the hotspot reads at id 27");
  check(entry(log, 8, &v) && v == 38, "the edge reads at id 8");
  check(!entry(log, 9, &v), "an unsupported id reads nothing");
  check(!entry(log, 256, &v) && !entry(nullptr, 1, &v),
        "out of range reads nothing");
  put(log, 255, 1, 7);
  check(entry(log, 255, &v) && v == 7, "the last id reads inside the log");
  put(log, 40, 2, 0);
  check(!plausible(log),
        "a flag other than 0 or 1 means the buffer is not a log");

  // The ids the samplePMStatistics of the driver reads must keep their names.
  struct {
    uint16_t id;
    const char* key;
  } const apple[] = {{1, "GFX clock"},           {2, "Memory clock"},
                     {14, "Fan speed"},          {15, "Fan speed percent"},
                     {19, "GFX activity"},       {23, "Board power"},
                     {27, "Hotspot temperature"}};
  for (const auto& a : apple) {
    bool named = false;
    for (const auto& s : kSensors)
      named |= s.id == a.id && !strcmp(s.key, a.key);
    char what[80];
    snprintf(what, sizeof(what), "id %u is named %s", a.id, a.key);
    check(named, what);
  }
  bool unique = true;
  for (size_t i = 0; i < kSensorCount; i++)
    for (size_t j = i + 1; j < kSensorCount; j++)
      unique &= kSensors[i].id != kSensors[j].id &&
                strcmp(kSensors[i].key, kSensors[j].key) != 0;
  check(unique, "every id and every name appears once");

  // Ids the Navi 21 filler marks supported but never gives a value: they must
  // not be published, or they would read 0 once every sensor is turned on.
  const uint16_t empty[] = {6,  7,  11, 12, 17, 18, 24, 28, 29,
                            30, 31, 32, 33, 34, 38, 39, 45};
  bool hidden = true;
  for (auto id : empty) hidden &= !published(id);
  check(hidden, "ids the driver never fills are not published");
  const uint16_t real_ids[] = {1,  2,  3,  4,  5,  8,  9,  10, 13,
                               14, 15, 16, 19, 20, 21, 22, 23, 25,
                               26, 27, 35, 36, 37, 40, 41, 44};
  bool shown = true;
  for (auto id : real_ids) shown &= published(id);
  check(shown && kSensorCount == sizeof(real_ids) / sizeof(real_ids[0]),
        "every id the driver fills is published, and only those");
  check(isNavi21(0x73bf) && isNavi21(0x73a5) && isNavi21(0x73af),
        "the RX 6800 XT and the other Navi 21 ids are recognised");
  check(!isNavi21(0x73df) && !isNavi21(0x73ff) && !isNavi21(0x731f) &&
            !isNavi21(0x73b0),
        "Navi 22, 23 and 10 are not");
  check(!strcmp(kEnableAllKey, "PP_EnableAllPMLogSensors"),
        "the driver setting is spelled as in the library");

  const uint8_t real[] = {0x55, 0x48, 0x89, 0xe5, 0x41, 0x57, 0x41,
                          0x56, 0x53, 0x50, 0xc7, 0x45, 0xe4, 0x00,
                          0x00, 0x00, 0x00, 0x48, 0x85, 0xff};
  check(entryMatches(real, sizeof(real)),
        "the entry read in 26.7.3 is accepted");
  check(!entryMatches(real, 16), "too few bytes to compare are refused");
  uint8_t other[sizeof(real)];
  memcpy(other, real, sizeof(real));
  other[12] = 0xe8;
  check(!entryMatches(other, sizeof(other)),
        "a different stack slot is refused");
  const uint8_t jmp[] = {0xe9, 0, 0, 0, 0}, ind[] = {0xff, 0x25, 0, 0, 0, 0};
  check(entryIsRouted(jmp, sizeof(jmp)) && entryIsRouted(ind, sizeof(ind)),
        "a routed entry is seen");
  check(!entryIsRouted(real, sizeof(real)), "the real entry is not a jump");

  if (argc > 1) {
    FILE* f = fopen(argv[1], "r");
    if (!f) {
      check(false, "the entries file opens");
    } else {
      char line[512];
      int n = 0;
      while (fgets(line, sizeof(line), f)) {
        char hex[65] = "", sym[200] = "", label[100] = "";
        if (sscanf(line, "%64s %199s %99s", hex, sym, label) != 3 ||
            strlen(hex) != 64)
          continue;
        uint8_t bytes[32];
        for (int i = 0; i < 32; i++) {
          unsigned b;
          sscanf(hex + 2 * i, "%2x", &b);
          bytes[i] = (uint8_t)b;
        }
        char what[400];
        snprintf(what, sizeof(what), "%s of %s is accepted", sym, label);
        check(entryMatches(bytes, sizeof(bytes)), what);
        n++;
      }
      fclose(f);
      check(n > 0, "the entries file has entries");
    }
  }
  if (failures)
    printf("%d checks failed\n", failures);
  else
    printf("all checks passed\n");
  return failures ? 1 : 0;
}
