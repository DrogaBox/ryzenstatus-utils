// curve_fixturegen — runs gpuctl::od8CheckWant against the card's real OD8
// values from work/ioreg-0.7.2.txt (ioreg -r -c DrogaBoxGPUSensors -l,
// 2026-11-19, kext REL-072-2026-11-19), mapped exactly like gpucontrol.cpp
// doCheck:
//   first.e  <- Settings.<name>.Stock (def), Feature/Min/Max as published
//   fresh.e  <- Settings.<name>.Default (def), Feature/Min/Max as published
//   cur.cur  <- Settings.<name>.Current
//   caps     <- OD8.Caps = 212749 (0x33F0D), notAllowed <- OD8.NotAllowed
// Unpublished (hidden, all-zero) settings stay zeroed Od8Entry{0,0,0,0}.
// Published values used (id: feature/min/max/stock=default/current):
//   0 GfxMaxMHz 1/500/2800/2359/2359   1 GfxMinMHz 1/500/2800/500/500
//   8 MemMaxMHz 4/2000/2150/2000/2000  9 PowerPercent 8/-6/9/0/0 (Min printed
//     as 18446744073709551610 = -6 unsigned; cfInt reads SInt32, as in doCheck)
//  10 FanMinRPM 0/1200/3500/700/0     11 FanAcousticRPM 0/1200/3500/3500/0
//  12 FanTargetC 0/25/100/70/0        14 AcTiming 256/0/1/0/0
//  15 FanZeroRpm 512/0/1/1/1          16 AutoUndervolt 1024/0/1/0/0
//  17 AutoOcGfx 2048/0/1/0/0          18 AutoOcMem 4096/0/1/0/0
//  19 FanCurve1C 8192/25/100/30/30    20 FanCurve1Pct 8192/20/100/20/20
//  21 FanCurve2C 8192/25/100/50/50    22 FanCurve2Pct 8192/20/100/36/36
//  23 FanCurve3C 8192/25/100/56/56    24 FanCurve3Pct 8192/20/100/52/52
//  25 FanCurve4C 8192/25/100/63/63    26 FanCurve4Pct 8192/20/100/68/68
//  27 FanCurve5C 8192/25/100/70/70    28 FanCurve5Pct 8192/20/100/100/100
//  35 FanZeroRpmStopC 512/30/30/30/30 36 PowerMode 65536/0/3/3/3
//  37 GfxVoltOffset 131072/881/1075/1075/1075
//  All other ids (2-7, 13, 29-34): unpublished, zero.
// Prints one JSON line per case: {"want":{...},"check":<Od8Check number>}.
// A GFX minimum (0.9.0) is written as "gfxMin" only when it is not stock, so
// the 100 lines from before it stay byte for byte as they were; the same for
// the GFX voltage ("volt") and the overclock flag ("overclock": true), added
// later in 0.9.0, so the first 120 lines stay as they were too.
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <initializer_list>

#include "control_logic.hpp"  // build with -I sensors/kext

using namespace gpuctl;

static Od8InitialOut first{}, fresh{};
static Od8CurrentOut cur{};
static uint32_t caps = 212749;  // OD8.Caps from the dump (0x33F0D)

static void setEntry(uint32_t id, uint32_t feature, int32_t mn, int32_t mx,
                     int32_t stock, int32_t def, int32_t now) {
  first.e[id] = Od8Entry{feature, mn, mx, stock, 0, 0};
  fresh.e[id] = Od8Entry{feature, mn, mx, def, 0, 0};
  cur.cur[id] = now;
}

static void loadReal() {
  first.count = fresh.count = cur.count = kOd8Count;
  first.caps = fresh.caps = caps;
  // cur.notAllowed: doCheck does (uint32)cfInt(d,"NotAllowed"); the dump
  // prints 18446744073709338866 = 2^64 - 212750, which is 0xfffcc0f2 as 32
  // bits (the app's bits("NotAllowed") reads the same). od8CheckWant reads it
  // only for a GFX voltage, so the first 120 lines do not depend on it.
  cur.notAllowed = 0xfffcc0f2u;
  setEntry(kOd8GfxMax, 1, 500, 2800, 2359, 2359, 2359);
  setEntry(kOd8GfxMin, 1, 500, 2800, 500, 500, 500);
  setEntry(kOd8MemMax, 4, 2000, 2150, 2000, 2000, 2000);
  setEntry(9, 8, -6, 9, 0, 0, 0);                   // PowerPercent
  setEntry(10, 0, 1200, 3500, 700, 700, 0);         // FanMinRPM
  setEntry(11, 0, 1200, 3500, 3500, 3500, 0);       // FanAcousticRPM
  setEntry(kOd8TargetTemp, 0, 25, 100, 70, 70, 0);  // FanTargetC (id 12)
  setEntry(14, 256, 0, 1, 0, 0, 0);                 // AcTiming
  setEntry(kOd8ZeroRpm, 512, 0, 1, 1, 1, 1);        // FanZeroRpm (id 15)
  setEntry(16, 1024, 0, 1, 0, 0, 0);                // AutoUndervolt
  setEntry(17, 2048, 0, 1, 0, 0, 0);                // AutoOcGfx
  setEntry(18, 4096, 0, 1, 0, 0, 0);                // AutoOcMem
  // Stock fan curve (FanCurve*/FanCurveStock in the dump, Current == Stock).
  const int32_t tc[5] = {30, 50, 56, 63, 70};
  const int32_t sc[5] = {20, 36, 52, 68, 100};
  for (uint32_t k = 0; k < 5; k++) {
    setEntry(od8CurveTempId(k), 8192, 25, 100, tc[k], tc[k], tc[k]);
    setEntry(od8CurveSpeedId(k), 8192, 20, 100, sc[k], sc[k], sc[k]);
  }
  setEntry(kOd8ZeroRpmStop, 512, 30, 30, 30, 30, 30);  // id 35
  setEntry(36, 65536, 0, 3, 3, 3, 3);                  // PowerMode
  setEntry(37, 131072, 881, 1075, 1075, 1075, 1075);   // GfxVoltOffset
}

// A state mutation, so cases can exercise Drifted / MemoryMoved / NoFeature
// which the real dump (first == fresh == cur, all features present) cannot
// reach. Serialised into the JSONL so main.swift replays the same mutation.
// kind: freshCaps | firstCaps | freshEntry | firstEntry | bothEntry | cur |
// notAllowed (the 0xa0 mask, value only)
// (bothEntry = same field on first and fresh, so od8SameLayout still passes).
struct Mut {
  const char* kind;
  uint32_t id;
  const char* field;  // feature|min|max|def (entry kinds only)
  int64_t value;
};

static void applyEntry(Od8Entry& e, const char* field, int64_t v) {
  if (field[0] == 'f' && field[1] == 'e')
    e.feature = static_cast<uint32_t>(v);
  else if (field[0] == 'm' && field[1] == 'i')
    e.min = static_cast<int32_t>(v);
  else if (field[0] == 'm' && field[1] == 'a')
    e.max = static_cast<int32_t>(v);
  else
    e.def = static_cast<int32_t>(v);
}

static void applyMut(Od8InitialOut& F, Od8InitialOut& R, Od8CurrentOut& C,
                     const Mut& m) {
  if (std::strcmp(m.kind, "freshCaps") == 0) {
    R.caps = static_cast<uint32_t>(m.value);
  } else if (std::strcmp(m.kind, "firstCaps") == 0) {
    F.caps = static_cast<uint32_t>(m.value);
  } else if (std::strcmp(m.kind, "freshEntry") == 0) {
    applyEntry(R.e[m.id], m.field, m.value);
  } else if (std::strcmp(m.kind, "firstEntry") == 0) {
    applyEntry(F.e[m.id], m.field, m.value);
  } else if (std::strcmp(m.kind, "bothEntry") == 0) {
    applyEntry(F.e[m.id], m.field, m.value);
    applyEntry(R.e[m.id], m.field, m.value);
  } else if (std::strcmp(m.kind, "notAllowed") == 0) {
    C.notAllowed = static_cast<uint32_t>(m.value);
  } else {  // cur
    C.cur[m.id] = static_cast<int32_t>(m.value);
  }
}

static void emit(const Od8Want& w, std::initializer_list<Mut> muts = {}) {
  Od8InitialOut F = first, R = fresh;
  Od8CurrentOut C = cur;
  for (const Mut& m : muts) applyMut(F, R, C, m);
  Od8Check c = od8CheckWant(w, F, R, C);
  printf(
      "{\"want\":{\"curve\":%s,\"temp\":[%d,%d,%d,%d,%d],"
      "\"speed\":[%d,%d,%d,%d,%d],\"zeroRpmOff\":%s,\"gfx\":%d",
      w.curve ? "true" : "false", w.temp[0], w.temp[1], w.temp[2], w.temp[3],
      w.temp[4], w.speed[0], w.speed[1], w.speed[2], w.speed[3], w.speed[4],
      w.zeroRpmOff ? "true" : "false", w.gfxMaxMHz);
  if (w.gfxMinMHz != 0) printf(",\"gfxMin\":%d", w.gfxMinMHz);
  if (w.voltMV != 0) printf(",\"volt\":%d", w.voltMV);
  if (w.overclock) printf(",\"overclock\":true");
  printf("},\"muts\":[");
  bool sep = false;
  for (const Mut& m : muts) {
    if (sep) printf(",");
    sep = true;
    if (m.field != nullptr)
      printf("{\"kind\":\"%s\",\"id\":%u,\"field\":\"%s\",\"value\":%lld}",
             m.kind, m.id, m.field, static_cast<long long>(m.value));
    else if (m.kind[0] == 'f' || m.kind[0] == 'n')  // caps, notAllowed
      printf("{\"kind\":\"%s\",\"value\":%lld}", m.kind,
             static_cast<long long>(m.value));
    else  // cur
      printf("{\"kind\":\"%s\",\"id\":%u,\"value\":%lld}", m.kind, m.id,
             static_cast<long long>(m.value));
  }
  printf("],\"check\":%u}\n", static_cast<unsigned>(c));
}

static Od8Want curve(const int32_t t[5], const int32_t s[5], bool zero = false,
                     int32_t gfx = 0) {
  Od8Want w{};
  w.curve = true;
  for (int k = 0; k < 5; k++) {
    w.temp[k] = t[k];
    w.speed[k] = s[k];
  }
  w.zeroRpmOff = zero;
  w.gfxMaxMHz = gfx;
  return w;
}

int main() {
  loadReal();
  const Od8Want stock{};
  emit(stock);  // stock state: Ok

  // Accepted curves.
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}));
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{25, 50, 70, 85, 100}));
  emit(curve(new int32_t[5]{25, 35, 40, 45, 48},
             new int32_t[5]{20, 30, 50, 70, 100}));
  emit(curve(new int32_t[5]{30, 31, 32, 33, 48},
             new int32_t[5]{20, 20, 20, 20, 100}));  // equal speeds
  emit(curve(new int32_t[5]{30, 36, 42, 45, 48},
             new int32_t[5]{20, 36, 36, 68, 100}));  // equal speeds mid
  emit(curve(new int32_t[5]{29, 38, 43, 46, 48},
             new int32_t[5]{20, 40, 60, 80, 100}));  // first < 30
  emit(curve(new int32_t[5]{30, 42, 45, 47, 48},
             new int32_t[5]{20, 20, 52, 68, 100}));  // last exactly 48
  emit(curve(new int32_t[5]{26, 34, 41, 46, 48},
             new int32_t[5]{100, 100, 100, 100, 100}));

  // CurveLast (last point not 100% at <=48): the README 30:25,...50:100 case,
  // the stock curve, and variants.
  emit(curve(new int32_t[5]{30, 40, 45, 48, 50},
             new int32_t[5]{25, 50, 70, 85, 100}));
  emit(curve(new int32_t[5]{30, 50, 56, 63, 70},
             new int32_t[5]{20, 36, 52, 68, 100}));  // stock curve
  emit(curve(new int32_t[5]{30, 40, 44, 46, 49},
             new int32_t[5]{20, 36, 52, 68, 100}));  // last 49
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 99}));  // last 99%
  emit(curve(new int32_t[5]{30, 40, 44, 46, 47},
             new int32_t[5]{20, 36, 52, 68, 90}));  // last 90% at 47

  // CurveFirst.
  emit(curve(new int32_t[5]{31, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}));  // first 31
  emit(curve(new int32_t[5]{35, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}));

  // CurveRange.
  emit(curve(new int32_t[5]{24, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}));  // temp < 25
  emit(curve(new int32_t[5]{30, 40, 44, 46, 101},
             new int32_t[5]{20, 36, 52, 68, 100}));  // temp > 100
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{19, 36, 52, 68, 100}));  // speed < 20
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 101}));  // speed > 100
  emit(curve(new int32_t[5]{0, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}));  // zero temp
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{0, 36, 52, 68, 100}));  // zero speed
  emit(curve(new int32_t[5]{-5, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}));  // negative temp
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, -1}));  // negative speed

  // CurveOrder.
  emit(curve(new int32_t[5]{30, 40, 40, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}));  // equal temps
  emit(curve(new int32_t[5]{30, 44, 40, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}));  // falling temp
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{20, 52, 36, 68, 100}));  // falling speed
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{50, 50, 50, 50,
                            100}));  // flat then jump (legal shape; cooling?)

  // CurveCooling: valid shape, less air than stock at a want/stock point.
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{20, 20, 20, 20, 100}));
  emit(curve(new int32_t[5]{25, 30, 35, 40, 48},
             new int32_t[5]{20, 20, 20, 20, 100}));
  emit(curve(new int32_t[5]{30, 45, 46, 47, 48},
             new int32_t[5]{20, 20, 20, 20, 100}));

  // GFX range (stock max is 2359 in this dump; min is 500).
  for (int32_t g : {1499, 1500, 2000, 2300, 2354, 2355, 2359, 2360, 2800, 0}) {
    Od8Want w{};
    w.gfxMaxMHz = g;
    emit(w);
  }
  Od8Want low{};
  low.gfxMaxMHz = 499;
  emit(low);  // below 1500 floor (also below GfxMin check path)

  // Zero RPM off alone and in combination.
  Od8Want z{};
  z.zeroRpmOff = true;
  emit(z);
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}, true, 0));
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}, false, 2300));
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}, true, 2300));
  emit(curve(new int32_t[5]{30, 40, 45, 48, 50},
             new int32_t[5]{25, 50, 70, 85, 100}, true,
             2300));  // refused curve + ok gfx
  Od8Want zg{};
  zg.zeroRpmOff = true;
  zg.gfxMaxMHz = 1499;
  emit(zg);  // zero off + bad gfx

  // Refused curve combined with GFX out of range (curve checks run first).
  emit(curve(new int32_t[5]{31, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}, false, 1499));

  // Extra edges to reach 60+.
  emit(curve(new int32_t[5]{30, 39, 43, 45, 48},
             new int32_t[5]{20, 36, 52, 68, 100}));
  emit(curve(new int32_t[5]{30, 41, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}));
  emit(curve(new int32_t[5]{28, 36, 42, 45, 48},
             new int32_t[5]{30, 45, 60, 80, 100}));
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{100, 100, 100, 100, 100}));
  emit(curve(new int32_t[5]{25, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}));  // first 25
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{20, 35, 52, 68, 100}));  // cooling at 40
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 51, 68, 100}));  // cooling at 44
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 67, 100}));  // cooling at 46
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{19, 19, 19, 19, 19}));  // range first
  emit(curve(new int32_t[5]{48, 46, 44, 40, 30},
             new int32_t[5]{100, 68, 52, 36, 20}));  // reversed
  for (int32_t g : {1501, 2358, 500, 1000}) {
    Od8Want w{};
    w.gfxMaxMHz = g;
    emit(w);
  }
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}, false, 2360));  // gfx refusal
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{20, 20, 20, 20, 100}, true,
             2360));  // cooling first

  // ---- Mutated-state cases: Drifted (2), MemoryMoved (3), NoFeature (4).
  // State checks run before any want check, so the stock want isolates them.
  // Drifted: layout moved (caps / feature / min / max on one side only).
  emit(stock, {{"freshCaps", 0, nullptr, 212750}});
  emit(stock, {{"firstCaps", 0, nullptr, 212750}});
  emit(stock, {{"freshEntry", od8CurveTempId(0), "feature", 0}});
  emit(stock, {{"freshEntry", od8CurveSpeedId(1), "min", 21}});
  emit(stock, {{"freshEntry", kOd8GfxMax, "max", 2700}});
  emit(stock, {{"firstEntry", kOd8GfxMin, "min", 400}});
  // Drifted: def moved (a stock or default entry changed).
  emit(stock, {{"freshEntry", od8CurveTempId(2), "def", 57}});  // moved default
  emit(stock, {{"firstEntry", od8CurveTempId(2), "def", 55}});  // moved stock
  emit(stock,
       {{"freshEntry", kOd8TargetTemp, "def", 71}});  // non-GFX: any move
  emit(stock, {{"freshEntry", kOd8MemMax, "def",
                2001}});  // def drift beats MemoryMoved
  // Drifted: GFX pair allowance is 25 MHz (kOd8DriftMHz): 26 drifts, 25 is ok.
  emit(stock, {{"freshEntry", kOd8GfxMax, "def", 2385}});  // +26
  emit(stock, {{"freshEntry", kOd8GfxMax, "def", 2384}});  // +25 -> Ok
  emit(stock, {{"freshEntry", kOd8GfxMin, "def", 526}});   // +26
  emit(stock, {{"freshEntry", kOd8GfxMin, "def", 525}});   // +25 -> Ok
  // Drifted beats a refused curve (state checks first).
  emit(curve(new int32_t[5]{31, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}),
       {{"freshEntry", od8CurveTempId(2), "def", 57}});

  // MemoryMoved: fresh/current memory clock no longer at the first read.
  emit(stock, {{"cur", kOd8MemMax, nullptr, 2001}});
  emit(stock, {{"cur", kOd8MemMax, nullptr, 2150}});
  emit(stock, {{"cur", kOd8MemMax, nullptr, 1999}});
  emit(stock, {{"cur", kOd8MemMax, nullptr, 2000}});  // control: at stock -> Ok
  // MemoryMoved beats NoFeature and a refused curve.
  emit(stock, {{"cur", kOd8MemMax, nullptr, 2001},
               {"bothEntry", kOd8GfxMax, "feature", 0}});
  emit(curve(new int32_t[5]{31, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}),
       {{"cur", kOd8MemMax, nullptr, 2001}});

  // NoFeature: a needed setting not offered as expected. bothEntry keeps the
  // two reads' layouts equal, so the check reaches the feature gate.
  emit(stock, {{"bothEntry", kOd8GfxMax, "feature", 0}});       // not 0x1
  emit(stock, {{"bothEntry", kOd8GfxMin, "feature", 8}});       // not 0x1
  emit(stock, {{"bothEntry", kOd8ZeroRpm, "feature", 0}});      // not 0x200
  emit(stock, {{"bothEntry", kOd8ZeroRpm, "def", 0}});          // def != 1
  emit(stock, {{"bothEntry", kOd8ZeroRpmStop, "feature", 0}});  // not 0x200
  emit(stock, {{"bothEntry", kOd8ZeroRpmStop, "min", 30},
               {"bothEntry", kOd8ZeroRpmStop, "max", 31}});        // min != max
  emit(stock, {{"bothEntry", kOd8ZeroRpmStop, "def", 31}});        // def != min
  emit(stock, {{"bothEntry", od8CurveTempId(0), "feature", 0}});   // not 0x2000
  emit(stock, {{"bothEntry", od8CurveSpeedId(4), "feature", 0}});  // not 0x2000
  emit(stock, {{"bothEntry", kOd8TargetTemp, "def", 39}});   // target < 40
  emit(stock, {{"bothEntry", kOd8TargetTemp, "def", 101}});  // target > 100
  emit(stock, {{"bothEntry", kOd8TargetTemp, "def", 40}});   // boundary -> Ok
  // NoFeature beats a valid curve; a one-sided feature change is Drifted.
  emit(curve(new int32_t[5]{30, 40, 44, 46, 48},
             new int32_t[5]{20, 36, 52, 68, 100}),
       {{"bothEntry", kOd8GfxMax, "feature", 0}});
  emit(stock, {{"firstEntry", kOd8GfxMax, "feature",
                0}});  // layout differs -> Drifted

  // 0.9.0: the GFX minimum (id 1), in the card's range for it (500-2800)
  // and never above the GFX maximum of the same state (2359 stock here).
  for (int32_t g : {500, 501, 1500, 2000, 2358, 2359}) {
    Od8Want w{};
    w.gfxMinMHz = g;
    emit(w);  // Ok
  }
  for (int32_t g : {499, 2360, 2800, 2801}) {
    Od8Want w{};
    w.gfxMinMHz = g;
    emit(w);  // GfxMinRange
  }
  {
    Od8Want w{};
    w.gfxMaxMHz = 2000;
    w.gfxMinMHz = 2000;
    emit(w);  // Ok: equal to the max asked
    w.gfxMinMHz = 2001;
    emit(w);  // GfxMinRange: above the max asked
    w.gfxMaxMHz = 1400;
    w.gfxMinMHz = 1000;
    emit(w);  // GfxRange: the max's own refusal comes first
  }
  {
    Od8Want w = curve(new int32_t[5]{30, 40, 44, 46, 48},
                      new int32_t[5]{20, 36, 52, 68, 100}, true, 2300);
    w.gfxMinMHz = 1800;
    emit(w);  // Ok: everything at once
    w.gfxMinMHz = 2301;
    emit(w);  // GfxMinRange
  }
  {
    Od8Want w{};
    w.gfxMinMHz = 2350;
    emit(w, {{"freshEntry", kOd8GfxMax, "def", 2340}});  // GfxMinRange
    w.gfxMinMHz = 2340;
    emit(w, {{"freshEntry", kOd8GfxMax, "def", 2340}});  // Ok (lower read)
    w.gfxMinMHz = 550;
    emit(w, {{"bothEntry", kOd8GfxMin, "min", 600}});    // GfxMinRange
    emit(w, {{"bothEntry", kOd8GfxMin, "max", 540}});    // GfxMinRange
    emit(w, {{"bothEntry", kOd8GfxMin, "feature", 8}});  // NoFeature first
  }
  // 0.9.0, the GFX voltage (id 37): lower only, 25 mV steps from stock.
  {
    Od8Want w{};
    for (int32_t mv :
         {1075, 1050, 1025, 1000, 900, 1076, 1100, 880, 875, 1060, 1049})
      w.voltMV = mv, emit(w);
    w.voltMV = 1050;
    emit(w, {{"bothEntry", kOd8GfxVolt, "feature", 0}});  // NoFeature
    emit(w, {{"notAllowed", 0, nullptr, 0xfffec0f2}});    // NoFeature
    emit(w, {{"bothEntry", kOd8GfxVolt, "def", 1100},
             {"bothEntry", kOd8GfxVolt, "max", 1150}});  // Ok
    w.voltMV = 1125;
    emit(w, {{"bothEntry", kOd8GfxVolt, "def", 1100},
             {"bothEntry", kOd8GfxVolt, "max", 1150}});  // VoltRange
    w.voltMV = 1050;
    emit(w, {{"freshEntry", kOd8GfxVolt, "def", 1050}});  // Drifted
    Od8Want c = curve(new int32_t[5]{30, 40, 44, 46, 48},
                      new int32_t[5]{20, 36, 52, 68, 100}, true, 2300);
    c.gfxMinMHz = 1800;
    c.voltMV = 1050;
    emit(c);  // Ok: everything at once
  }
  // 0.9.0, the overclock flag: the GFX maximum up to the card's 2800.
  {
    Od8Want w{};
    w.overclock = true;
    emit(w);  // Ok: the flag alone is stock
    for (int32_t mhz : {2359, 2360, 2500, 2800, 2801, 2825, 1400})
      w.gfxMaxMHz = mhz, emit(w);
    w.gfxMaxMHz = 2600;
    w.gfxMinMHz = 2600;
    emit(w);  // Ok: FMIN <= FMAX with a raised max
    w.gfxMinMHz = 2601;
    emit(w);  // GfxMinRange
    w.gfxMinMHz = 0;
    w.gfxMaxMHz = 2700;
    emit(w, {{"bothEntry", kOd8GfxMax, "max", 2600}});  // GfxRange: its own max
    w.overclock = false;
    w.gfxMaxMHz = 2500;
    emit(w);  // GfxRange: no flag
  }

  return 0;
}
