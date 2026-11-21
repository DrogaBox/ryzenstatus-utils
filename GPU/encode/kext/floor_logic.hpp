//
//  floor_logic.hpp - which GPUs VCNEncodeFloor sets a floor for, and which
//  value. No kernel headers, so tests/floor_test.cpp runs it on any Mac.
//
//  The SMU takes VclkFloor / 100 as the VCLK soft minimum in MHz and rounds it
//  up to a level, and the value's low 16 bits as the DCLK soft minimum in MHz
//  (see kDefaultFloor in kern_start.cpp). Neither may pass the chip's top
//  level, and the same driver family also runs chips whose top levels are below
//  the Navi 21 value (an RX 5600 XT table tops out at VCLK 1267 / DCLK 1086
//  MHz). So only chips whose clock tables were read get a floor:
//
//    Navi 21  0x73A0-0x73AF, 0x73BF   VCLK {363, 1400}  DCLK {317, 1225}
//             (this Mac's own table; 1322 -> 1400, 1225; measured)
//    Navi 23  0x73E0-0x73EF, 0x73FF   VCLK {690, 1429}  DCLK {572, 1250}
//             (two RX 6600 XT tables; 1322 -> 1429, 1225 -> up to 1250;
//             not run on a card)
//
//  0x73F0 is Navi 33, not Navi 23 (pci.ids). Navi 22 (0x73C3, 0x73DF) has no
//  table read yet, so it gets none.
//
#pragma once
#include <stdint.h>

namespace vcnfloor {

// 132297 = 2 * 65536 + 1225: VCLK 1322 MHz, DCLK 1225 MHz.
constexpr uint32_t kDefaultFloor = 132297;

constexpr uint32_t vclkMHz(uint32_t floor) { return floor / 100; }
constexpr uint32_t dclkMHz(uint32_t floor) { return floor & 0xffff; }

constexpr bool isNavi21(uint32_t deviceId) {
  return (deviceId & 0xfff0) == 0x73a0 || deviceId == 0x73bf;
}
constexpr bool isNavi23(uint32_t deviceId) {
  return (deviceId & 0xfff0) == 0x73e0 || deviceId == 0x73ff;
}

struct ChipLevels {
  uint16_t vclkMin, vclkTop, dclkMin, dclkTop;
};
constexpr ChipLevels kNavi21{363, 1400, 317, 1225};
constexpr ChipLevels kNavi23{690, 1429, 572, 1250};

// True when the floor lands inside the chip's levels: above its lowest level
// (or it would change nothing) and not past its top one.
constexpr bool fits(uint32_t floor, ChipLevels c) {
  return vclkMHz(floor) > c.vclkMin && vclkMHz(floor) <= c.vclkTop &&
         dclkMHz(floor) > c.dclkMin && dclkMHz(floor) <= c.dclkTop;
}
static_assert(fits(kDefaultFloor, kNavi21), "Navi 21 floor inside its levels");
static_assert(fits(kDefaultFloor, kNavi23), "Navi 23 floor inside its levels");

// The floor for a chip whose clock table was read; 0 for any other.
constexpr uint32_t chipFloor(uint32_t deviceId) {
  return isNavi21(deviceId) || isNavi23(deviceId) ? kDefaultFloor : 0;
}

}  // namespace vcnfloor
