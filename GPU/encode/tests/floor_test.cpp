// floor_test.cpp - the kext's GPU rule (kext/floor_logic.hpp) on the CPU: every
// AMD 0x73xx device-id in pci.ids, and the floor against the levels read from
// each chip's clock table, including one that must never get it (RX 5600 XT).
#include <stdio.h>

#include "../kext/floor_logic.hpp"

using namespace vcnfloor;

static int fails = 0;
static void check(bool ok, const char* what) {
  if (!ok) {
    printf("FAIL %s\n", what);
    fails++;
  }
}

int main() {
  struct {
    uint16_t id;
    const char* name;
    bool floor;
  } ids[] = {
      {0x7310, "Navi 10 W5700X", false},
      {0x731f, "Navi 10 RX 5700 XT", false},
      {0x7340, "Navi 14 RX 5500", false},
      {0x7360, "Navi 12", false},
      {0x73a1, "Navi 21 V620", true},
      {0x73a2, "Navi 21 W6900X", true},
      {0x73a3, "Navi 21 W6800", true},
      {0x73a5, "Navi 21 RX 6950 XT", true},
      {0x73ab, "Navi 21 W6800X", true},
      {0x73af, "Navi 21 RX 6900 XT", true},
      {0x73bf, "Navi 21 RX 6800 XT", true},
      {0x73c3, "Navi 22", false},
      {0x73df, "Navi 22 RX 6700 XT", false},
      {0x73e0, "Navi 23", true},
      {0x73e1, "Navi 23 W6600M", true},
      {0x73e3, "Navi 23 W6600", true},
      {0x73ef, "Navi 23 RX 6650 XT", true},
      {0x73f0, "Navi 33 RX 7600M XT", false},
      {0x73ff, "Navi 23 RX 6600 XT", true},
      {0x744c, "Navi 31 RX 7900 XTX", false},
  };
  for (auto& d : ids) check((chipFloor(d.id) != 0) == d.floor, d.name);

  check(vclkMHz(kDefaultFloor) == 1322 && dclkMHz(kDefaultFloor) == 1225,
        "132297 is VCLK 1322 / DCLK 1225");
  check(fits(kDefaultFloor, kNavi21), "floor inside Navi 21 levels");
  check(fits(kDefaultFloor, kNavi23), "floor inside Navi 23 levels");
  constexpr ChipLevels kNavi10{100, 1267, 100, 1086};  // an RX 5600 XT table
  check(!fits(kDefaultFloor, kNavi10), "floor past RX 5600 XT top levels");

  printf("floor tests: %zu ids, %s\n", sizeof(ids) / sizeof(ids[0]),
         fails ? "FAILED" : "all pass");
  return fails != 0;
}
