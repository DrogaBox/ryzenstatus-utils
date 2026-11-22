//
//  pmlog_logic.hpp - what GPUSensors knows about AMD's PMLog, the table of
//  sensor readings the power management library of the Navi 21 driver fills.
//  No kernel headers here, so the tests build it as ordinary C++.
//
//  Layout (read in AMDRadeonX6000HWLibs, Phw_CommPMLog_QueryPMLogData, and in
//  AMDRadeonX6000_AMDHardware::samplePMStatistics, which reads it): 2052 bytes,
//  a 4-byte header, then for each sensor id k from 0 to 255 a 32-bit "is
//  supported" flag at 4 + 8k and a 32-bit value at 8 + 8k. The ids are AMD's
//  ADL_PMLOG numbering; the filler and the driver's own Print_PMLog use the
//  same meanings for the ids named in kSensors below.
//
#ifndef GPUSENSORS_PMLOG_LOGIC_HPP
#define GPUSENSORS_PMLOG_LOGIC_HPP

#include <stddef.h>
#include <stdint.h>
#include <string.h>

namespace gpusens {

constexpr size_t kLogBytes = 2052;
constexpr size_t kIdCount = (kLogBytes - 4) / 8;  // 256

inline uint32_t read32(const uint8_t* p) {
  uint32_t v;
  memcpy(&v, p, sizeof(v));
  return v;
}

// True and *value set when sensor `id` is marked supported in the log.
inline bool entry(const uint8_t* log, size_t id, uint32_t* value) {
  if (log == nullptr || id >= kIdCount) return false;
  if (read32(log + 4 + 8 * id) != 1) return false;
  if (value) *value = read32(log + 8 + 8 * id);
  return true;
}

// The driver asks for the log about once a second while the GPU is up. A copy
// older than this means the driver stopped sampling (the card is asleep,
// powered down, or its driver is gone), so the readings are not current any
// more and must not be published as if they were.
constexpr uint64_t kMaxSampleAgeMs = 5000;

inline bool sampleFresh(uint64_t ageMs) { return ageMs <= kMaxSampleAgeMs; }

// Whether the properties built from a kept log may be published: there has to
// be a log, and it has to be fresh. A missing or stale log is removed from the
// property table, never published as zeros or as the last numbers.
inline bool publishable(bool have, uint64_t ageMs) {
  return have && sampleFresh(ageMs);
}

// A filled log: every flag is 0 or 1, and at least one is 1. The library
// returns success without filling anything while the GPU is powered down, and
// the caller then holds whatever its buffer had (the driver's own caller clears
// it); such a log is not kept.
inline bool plausible(const uint8_t* log) {
  if (log == nullptr) return false;
  size_t set = 0;
  for (size_t id = 0; id < kIdCount; id++) {
    uint32_t flag = read32(log + 4 + 8 * id);
    if (flag > 1) return false;
    set += flag;
  }
  return set > 0;
}

// The first bytes of _PEM_CWDDEPM_QueryPMLogData, the part Lilu moves when it
// routes the function (whole instructions, at least 14 bytes):
//   push rbp; mov rbp, rsp; push r15; push r14; push rbx; push rax;
//   mov dword [rbp-0x1c], 0
// None of them is relative to the instruction pointer, so they run the same
// from Lilu's copy. Identical in AMDRadeonX6000HWLibs and AMDRadeonX6800HWLibs
// of 15.8.2, 15.8.3, 26.7.2 and 26.7.3 (tools/driver/kcfunc.py).
constexpr size_t kPrologueBytes = 17;
constexpr uint8_t kPrologue[kPrologueBytes] = {
    0x55, 0x48, 0x89, 0xe5, 0x41, 0x57, 0x41, 0x56, 0x53,
    0x50, 0xc7, 0x45, 0xe4, 0x00, 0x00, 0x00, 0x00};

inline bool entryMatches(const uint8_t* p, size_t available) {
  return p != nullptr && available >= kPrologueBytes &&
         memcmp(p, kPrologue, kPrologueBytes) == 0;
}

// A routed function starts with a jump: e9 (near) or ff 25 (indirect).
inline bool entryIsRouted(const uint8_t* p, size_t available) {
  if (p == nullptr || available < 2) return false;
  return p[0] == 0xe9 || (p[0] == 0xff && p[1] == 0x25);
}

enum class Unit : uint8_t {
  Celsius,
  MHz,
  RPM,
  Percent,
  Watt,
  Millivolt,
  Ampere,
  Bits,   // a bit mask
  Count,  // a plain number (PCIe lanes, link speed code)
};

struct Sensor {
  uint16_t id;
  const char* key;  // the property name it is published under
  Unit unit;
};

// The ids the Navi 21 filler can write a reading to, named after ADL_PMLOG and
// Print_PMLog (Phw_CommPMLog_QueryPMLogData and smu_11_0_7_query_pm_log,
// 26.7.3). Left out: ids the filler marks supported but never gives a value
// (6 VCE clock, 7 VCN clock, 17 SOC power, 18 SOC current, 28 GFX temperature,
// 29 SOC temperature, 30 GFX power, 31 GFX current, 32-34, 38, 39, 45, and 12
// and 24, which it fills with 0), and 11, which it never marks. With the
// driver's default list only 12 of these come back on an RX 6800 XT; with
// PP_EnableAllPMLogSensors (see kEnableAllKey) the rest do too.
constexpr Sensor kSensors[] = {
    {1, "GFX clock", Unit::MHz},
    {2, "Memory clock", Unit::MHz},
    {3, "SOC clock", Unit::MHz},
    {4, "Video clock 0", Unit::MHz},
    {5, "Video data clock 0", Unit::MHz},
    {8, "Edge temperature", Unit::Celsius},
    {9, "Memory temperature", Unit::Celsius},
    {10, "GFX VR temperature", Unit::Celsius},
    {13, "PLX temperature", Unit::Celsius},
    {14, "Fan speed", Unit::RPM},
    {15, "Fan speed percent", Unit::Percent},
    {16, "SOC voltage", Unit::Millivolt},
    {19, "GFX activity", Unit::Percent},
    {20, "Memory activity", Unit::Percent},
    {21, "GFX voltage", Unit::Millivolt},
    {22, "Memory voltage", Unit::Millivolt},
    {23, "Board power", Unit::Watt},
    {25, "Memory VR 0 temperature", Unit::Celsius},
    {26, "Memory VR 1 temperature", Unit::Celsius},
    {27, "Hotspot temperature", Unit::Celsius},
    {35, "Throttler status", Unit::Bits},
    {36, "Video clock 1", Unit::MHz},
    {37, "Video data clock 1", Unit::MHz},
    {40, "PCIe link speed", Unit::Count},
    {41, "PCIe lanes", Unit::Count},
    {44, "Fabric clock", Unit::MHz},
};
constexpr size_t kSensorCount = sizeof(kSensors) / sizeof(kSensors[0]);

// True when the filler can write a reading to `id` (it is in kSensors).
inline bool published(size_t id) {
  for (const auto& s : kSensors)
    if (s.id == id) return true;
  return false;
}

// The driver setting that makes the filler use every id it knows instead of
// its fixed list for the chip (_smu_11_0_7_supported_sensors, which leaves the
// memory and VR temperatures, the memory and SOC voltages, the throttler status
// and the video, SOC and fabric clocks off on the RX 6800 XT). Read once, when
// the power management starts (Phw_CommPMLog_Initialize), from the GPU's PCI
// device; the values come from the power firmware's metrics table, which the
// driver copies every second anyway.
constexpr const char* kEnableAllKey = "PP_EnableAllPMLogSensors";

// Navi 21 device ids: 0x73a0 to 0x73af and 0x73bf (the cards the kext is for).
inline bool isNavi21(uint32_t deviceId) {
  return (deviceId & 0xfff0) == 0x73a0 || deviceId == 0x73bf;
}

inline const char* unitName(Unit u) {
  switch (u) {
    case Unit::Celsius:
      return "C";
    case Unit::MHz:
      return "MHz";
    case Unit::RPM:
      return "RPM";
    case Unit::Percent:
      return "%";
    case Unit::Watt:
      return "W";
    case Unit::Millivolt:
      return "mV";
    case Unit::Ampere:
      return "A";
    case Unit::Bits:
      return "bits";
    case Unit::Count:
      return "";
  }
  return "";
}

}  // namespace gpusens

#endif  // GPUSENSORS_PMLOG_LOGIC_HPP
