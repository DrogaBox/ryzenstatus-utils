//
//  control_logic.hpp - every decision GPUSensors' GPU control takes, with no
//  kernel headers, so the tests build it as ordinary C++.
//
//  The control only lowers or limits, always within the values the card had
//  when the Mac started (the power table on the EFI: 240 W on the owner's RX
//  6800 XT, 264 W on a stock one). It never raises a clock, a voltage or a
//  temperature limit. Nothing here talks to the GPU: the kext asks these
//  functions first and only acts on a yes.
//
//  Power profiles are the power firmware's workload presets, the same numbers
//  Linux shows in pp_power_profile_mode (bit values):
//    0  automatic: the driver's own clients choose (video, 3D, compute), the
//       way Linux works. macOS hides that by fixing 16 on every Navi 21: the
//       library replaces the clients' choice with PP_WorkLoadPolicyMask when
//       that is not 0, and it reads the setting once, when power management
//       starts (PhwNavi21_Initialize, Phw_SwSmu_WorkLoadPolicyManager).
//    2  power saving
//    16 compute (what macOS sets)
//  Video (4) and 3D full screen (1) wait until 0, 2 and 16 are measured; VR (8)
//  and custom (32) are never accepted.
//
#ifndef GPUSENSORS_CONTROL_LOGIC_HPP
#define GPUSENSORS_CONTROL_LOGIC_HPP

#include <stddef.h>
#include <stdint.h>

namespace gpuctl {

// ---------------------------------------------------------------- the card --

constexpr uint32_t kVendorAMD = 0x1002;

// The cards the control may act on. Only the RX 6800 XT has been studied; any
// other card keeps the sensors and no control. Navi 21 shares device 0x73BF
// between the RX 6900 XT (revision 0xC0), RX 6800 XT (0xC1) and RX 6800
// (0xC3), so the revision decides. The owner's card: 0x73BF rev 0xC1 (ioreg).
inline bool deviceAllowed(uint32_t vendor, uint32_t device, uint32_t revision) {
  return vendor == kVendorAMD && device == 0x73BF && revision == 0xC1;
}
// The cards the control reads (0.8.0): the RX 6800 XT and the RX 6900 XT
// (73BF rev 0xC0). On a card that is readable but not allowed the kext routes
// and reads exactly as on the RX 6800 XT (the OD8 table, the start-up limit,
// the stock values) and writing never opens: WriteOff::ReadOnlyCard.
inline bool deviceReadable(uint32_t vendor, uint32_t device,
                           uint32_t revision) {
  return vendor == kVendorAMD && device == 0x73BF &&
         (revision == 0xC0 || revision == 0xC1);
}

// ---------------------------------------------------------- driver entries --
//
// The library functions the control routes, checked byte for byte before
// Lilu touches them (macOS 26.7.3 AMDRadeonX6000HWLibs,
// tools/driver/kcfunc.py). The bytes cover whole instructions past the 14 Lilu
// moves for a long jump, and none of them is relative to the instruction
// pointer.
//
// AtiPowerPlayServices::ppInitialize(PPDisplayConfiguration*): starts the
// power management (PP_InitializeEX), which reads PP_WorkLoadPolicyMask once.
// The framebuffer copies its own properties (with 16) onto the GPU before
// this, so the control sets the profile right before it runs.
//   push rbp; mov rbp, rsp; push r15; push r14; push rbx; sub rsp, 0x78;
//   mov rbx, rdi
constexpr size_t kPPInitBytes = 16;
constexpr uint8_t kPPInitEntry[kPPInitBytes] = {
    0x55, 0x48, 0x89, 0xe5, 0x41, 0x57, 0x41, 0x56,
    0x53, 0x48, 0x83, 0xec, 0x78, 0x48, 0x89, 0xfb};
constexpr const char* kPPInitSymbol =
    "__ZN20AtiPowerPlayServices12ppInitializeEP22PPDisplayConfiguration";

// Phw_SwSmu_WorkLoadPolicyManager(hwmgr*, mask): gets the profile the
// driver's clients ask for, replaces it with PP_WorkLoadPolicyMask when that
// is not 0, and sends it to the power firmware. The control only watches the
// mask the clients asked for, and passes everything through.
//   push rbp; mov rbp, rsp; push r15; push r14; push r12; push rbx;
//   mov r15d, esi; mov r14, rdi
constexpr size_t kPolicyBytes = 17;
constexpr uint8_t kPolicyEntry[kPolicyBytes] = {
    0x55, 0x48, 0x89, 0xe5, 0x41, 0x57, 0x41, 0x56, 0x41,
    0x54, 0x53, 0x41, 0x89, 0xf7, 0x49, 0x89, 0xfe};
constexpr const char* kPolicySymbol = "_Phw_SwSmu_WorkLoadPolicyManager";

inline bool bytesMatch(const uint8_t* p, size_t available, const uint8_t* want,
                       size_t n) {
  if (p == nullptr || available < n) return false;
  for (size_t i = 0; i < n; i++)
    if (p[i] != want[i]) return false;
  return true;
}

constexpr const char* kProfileKey = "PP_WorkLoadPolicyMask";

// The power limit, watched only (0.4.0): nothing is called, every call goes
// through unchanged. Read in the 26.7.3 library (report.md section 10).
//
// Phw_SwSmu_GetPowerLimit(hwmgr*, uint32_t* watts) -> 1 when it read. Its only
// caller is the framebuffer, at power-up (boot) and after every wake, so the
// first answer is the limit the card booted with.
//   push rbp; mov rbp, rsp; push r15; push r14; push rbx; push rax;
//   mov r15, rsi; mov r14, rdi
constexpr size_t kGetLimitBytes = 16;
constexpr uint8_t kGetLimitEntry[kGetLimitBytes] = {
    0x55, 0x48, 0x89, 0xe5, 0x41, 0x57, 0x41, 0x56,
    0x53, 0x50, 0x49, 0x89, 0xf7, 0x49, 0x89, 0xfe};
constexpr const char* kGetLimitSymbol = "_Phw_SwSmu_GetPowerLimit";
constexpr uint32_t kPPResultOK = 1;
// smu_11_0_7_set_power_limit(smu*, const SetLimit*) -> 0 when sent. Every
// limit sent to the power firmware passes here, whoever asks (a CWDDE escape,
// the power source, the BIOS, ppAdjustPowerTune).
//   push rbp; mov rbp, rsp; push r15; push r14; push r12; push rbx;
//   cmp qword [rdi+0x3f0], 0
constexpr size_t kSetLimitBytes = 19;
constexpr uint8_t kSetLimitEntry[kSetLimitBytes] = {
    0x55, 0x48, 0x89, 0xe5, 0x41, 0x57, 0x41, 0x56, 0x41, 0x54,
    0x53, 0x48, 0x83, 0xbf, 0xf0, 0x03, 0x00, 0x00, 0x00};
constexpr const char* kSetLimitSymbol = "_smu_11_0_7_set_power_limit";
struct SetLimit {   // what the second argument points at
  uint32_t source;  // 0 AC ... 5; DC sources get 0x10000 added
  uint32_t controller;
  uint16_t watts;
};
static_assert(offsetof(SetLimit, watts) == 8, "watts at +8");
// AtiPowerPlayServices::ppSleep() and ppWake(): both take the PowerPlay lock
// and start the sleep or wake events. Their first 28 bytes are the same, so
// the symbol picks the function and the bytes only check it.
//   push rbp; mov rbp, rsp; push r15; push r14; push rbx; push rax;
//   mov rbx, rdi; lea r14, [rdi+0x9d0]
constexpr size_t kSleepWakeBytes = 20;
constexpr uint8_t kSleepWakeEntry[kSleepWakeBytes] = {
    0x55, 0x48, 0x89, 0xe5, 0x41, 0x57, 0x41, 0x56, 0x53, 0x50,
    0x48, 0x89, 0xfb, 0x4c, 0x8d, 0xb7, 0xd0, 0x09, 0x00, 0x00};
constexpr const char* kSleepSymbol = "__ZN20AtiPowerPlayServices7ppSleepEv";
constexpr const char* kWakeSymbol = "__ZN20AtiPowerPlayServices6ppWakeEv";

// The power limit, written (0.5.0). The only driver function the control
// calls; it is never routed, only checked before the first call:
// AtiPowerPlayServices::ppCWDDE(this, const void* in, uint32_t inSize,
// void* out, uint32_t* outSize) -> IOReturn. It takes the PowerPlay lock
// (a plain mutex, not recursive) and runs one escape (report.md 10.2).
//   push rbp; mov rbp, rsp; push r15; push r14; push r13; push r12;
//   push rbx; sub rsp, 0x18; mov dword [rbp-0x2c], 0
constexpr size_t kCwddeBytes = 24;
constexpr uint8_t kCwddeEntry[kCwddeBytes] = {
    0x55, 0x48, 0x89, 0xe5, 0x41, 0x57, 0x41, 0x56, 0x41, 0x55, 0x41, 0x54,
    0x53, 0x48, 0x83, 0xec, 0x18, 0xc7, 0x45, 0xd4, 0x00, 0x00, 0x00, 0x00};
constexpr const char* kCwddeSymbol =
    "__ZN20AtiPowerPlayServices7ppCWDDEEPKvjPvPj";

// ---------------------------------------------------------------- profiles --

enum Profile : uint32_t {
  kProfileAutomatic = 0,
  kProfilePowerSaving = 2,
  kProfileCompute = 16,
};

inline bool profileAllowed(uint32_t value) {
  return value == kProfileAutomatic || value == kProfilePowerSaving ||
         value == kProfileCompute;
}

// A strict reader for a gpuprofile=N text (not used by the kext yet, which
// takes the kernel's number parser and then profileAllowed): plain decimal
// digits only (no sign, no hex, no spaces, nothing after them), at most 3
// digits, and an allowed profile. Anything else is refused and the setting is
// left alone.
inline bool parseProfileArg(const char* text, uint32_t* out) {
  if (text == nullptr || out == nullptr) return false;
  uint32_t value = 0;
  size_t digits = 0;
  for (const char* p = text; *p != '\0'; p++) {
    if (*p < '0' || *p > '9' || ++digits > 3) return false;
    value = value * 10 + static_cast<uint32_t>(*p - '0');
  }
  if (digits == 0 || !profileAllowed(value)) return false;
  *out = value;
  return true;
}

// ------------------------------------------------------------------- power --

constexpr uint32_t kStepW = 10;
// A start-up value is believed only between these (a read check, not a floor
// for requests). Above 300 no RX 6800 XT or 6900 XT start-up value is
// believable (reference boards 300 W total board power, 255 W chip; the
// owner's stock table 264 W); below 200 the read went wrong.
constexpr uint32_t kMinBootW = 200;
constexpr uint32_t kMaxBootW = 300;

enum class PowerCheck : uint32_t {
  Ok = 0,
  NoBootValue,  // the start-up limit was never read, or is not believable
  BelowFloor,   // below the card's own minimum (PowerRange)
  AboveBoot,
  NotAStep,
  NoFloor,  // the card's minimum is not known (OD8 not read cleanly): no change
};

inline bool bootValuePlausible(uint32_t bootW) {
  return bootW >= kMinBootW && bootW <= kMaxBootW;
}

// A request is taken only between the card's floor and the start-up value,
// in 10 W steps. The start-up value itself is always taken (it is how the
// control goes back, floor known or not), even when it is not a multiple of
// 10 (264 W). floorW 0 = not known: nothing below the start-up value is
// taken (NoFloor); above it is AboveBoot either way.
inline PowerCheck checkPower(uint32_t bootW, uint32_t floorW,
                             uint32_t requestW) {
  if (!bootValuePlausible(bootW)) return PowerCheck::NoBootValue;
  if (requestW == bootW) return PowerCheck::Ok;
  if (requestW > bootW) return PowerCheck::AboveBoot;  // floor known or not
  if (floorW == 0 || floorW > bootW) return PowerCheck::NoFloor;
  if (requestW < floorW) return PowerCheck::BelowFloor;
  if (requestW % kStepW != 0) return PowerCheck::NotAStep;
  return PowerCheck::Ok;
}

// A program's set(watts): refused (outside the range), the start-up value
// (that is going back: Owner::release, never a change), or a change.
enum class SetRoute : uint32_t { Refuse, Release, Change };
inline SetRoute routeSet(uint32_t bootW, uint32_t floorW, uint32_t requestW) {
  if (checkPower(bootW, floorW, requestW) != PowerCheck::Ok)
    return SetRoute::Refuse;
  return requestW == bootW ? SetRoute::Release : SetRoute::Change;
}

// ----------------------------------------------------------------- escapes --
//
// The two escapes the control sends through ppCWDDE, and nothing else
// (report.md 10.3, 10.5). Each starts with a 16-byte header {16, 0x00C00000 |
// index, 0, 0}; PP_Cwdde checks the sizes exactly.
//   0x2a IsGPUAccessible: in = header only (16), out = {12, accessible, 0},
//        *outSize 12. 0 + accessible 1 = the GPU is up.
//   0x6e SetPackagePowerLimit: in = header + {8, watts} (24), out none,
//        *outSize 0. Whole watts to the power firmware, no range check of
//        the driver's own: the range is checkPower's.
constexpr uint32_t kEscapeHeaderSize = 16;
constexpr uint32_t kEscapeCode = 0x00C00000;
constexpr uint32_t kEscapeIsGPUAccessible = 0x2a;
constexpr uint32_t kEscapeSetPackagePowerLimit = 0x6e;
struct EscapeHeader {
  uint32_t size, code, reserved0, reserved1;
};
struct AccessOut {
  uint32_t size, accessible, unused;
};
struct SetLimitIn {
  EscapeHeader header;
  uint32_t size, watts;
};
static_assert(sizeof(EscapeHeader) == 16, "header 16 bytes");
static_assert(sizeof(AccessOut) == 12, "0x2a answer 12 bytes");
static_assert(sizeof(SetLimitIn) == 24, "0x6e request 24 bytes");

inline EscapeHeader accessQuery() {
  return EscapeHeader{kEscapeHeaderSize, kEscapeCode | kEscapeIsGPUAccessible,
                      0, 0};
}
inline AccessOut accessAnswer() { return AccessOut{sizeof(AccessOut), 0, 0}; }
// The 0x6e request, built only for a value checkPower takes: the range is
// checked again where the bytes are made, whatever the caller checked.
inline bool makeSetLimit(uint32_t bootW, uint32_t floorW, uint32_t watts,
                         SetLimitIn* out) {
  if (out == nullptr || checkPower(bootW, floorW, watts) != PowerCheck::Ok)
    return false;
  *out =
      SetLimitIn{EscapeHeader{kEscapeHeaderSize,
                              kEscapeCode | kEscapeSetPackagePowerLimit, 0, 0},
                 8, watts};
  return true;
}

// ppCWDDE's answers (report.md 10.2): CWDDE 1 (the PowerPlay lock busy, 25,
// or any other failure) and CWDDE 3 (not initialized, unsupported).
constexpr uint32_t kRetOK = 0;
constexpr uint32_t kRetError = 0xE00002BC;
constexpr uint32_t kRetUnsupported = 0xE00002C7;

enum class Access : uint32_t {
  Yes,    // 0 and accessible 1
  No,     // asleep, powered down, access blocked, not ready, or busy
  Error,  // an answer that does not fit the escape
};
inline Access classifyAccess(uint32_t ret, uint32_t outSize,
                             const AccessOut& out) {
  if (ret == kRetUnsupported || ret == kRetError) return Access::No;
  if (ret != kRetOK || outSize != sizeof(AccessOut) ||
      out.size != sizeof(AccessOut) || out.accessible > 1)
    return Access::Error;
  return out.accessible == 1 ? Access::Yes : Access::No;
}

// What the watcher of smu_11_0_7_set_power_limit saw on the worker's own
// thread during one 0x6e (it runs inside the escape).
struct SendSeen {
  uint32_t count;   // sends to the power firmware
  uint32_t watts;   // the last one's
  uint32_t result;  // the last one's, 0 = sent
};
enum class Sent : uint32_t {
  Confirmed,  // exactly one send, of these watts, taken by the firmware
  NotSent,    // busy or not ready, and nothing reached the firmware
  Failed,     // anything else: the limit is not known any more
};
inline Sent classifySend(uint32_t ret, const SendSeen& seen, uint32_t wantW) {
  if (seen.count == 0)
    return ret == kRetError || ret == kRetUnsupported ? Sent::NotSent
                                                      : Sent::Failed;
  if (ret == kRetOK && seen.count == 1 && seen.result == 0 &&
      seen.watts == wantW)
    return Sent::Confirmed;
  return Sent::Failed;
}

// A way back is tried up to 3 times, 500 ms apart, while the GPU is busy or
// not accessible; never into a sleep (Owner::willSleep drops it, didWake
// starts a new one). A change is never tried again.
constexpr uint32_t kRevertTries = 3;
constexpr uint64_t kRevertRetryMs = 500;
enum class TryResult : uint32_t {
  Confirmed,  // sent and seen
  Transient,  // not accessible, busy: nothing reached the firmware
  Failed,     // an error, or a send that does not match
};
inline TryResult tryResult(Access access, Sent sent) {
  if (access == Access::No) return TryResult::Transient;
  if (access == Access::Error) return TryResult::Failed;
  if (sent == Sent::Confirmed) return TryResult::Confirmed;
  return sent == Sent::NotSent ? TryResult::Transient : TryResult::Failed;
}
enum class Next : uint32_t { Done, Retry, GiveUp, Abort };
// After try `tryNo` (1 to kRevertTries) of a way back.
inline Next afterRevertTry(uint32_t tryNo, TryResult r, bool sleepStarted) {
  if (r == TryResult::Confirmed) return Next::Done;
  if (sleepStarted) return Next::Abort;
  if (r == TryResult::Failed) return Next::GiveUp;
  return tryNo < kRevertTries ? Next::Retry : Next::GiveUp;
}

// After wake the worker waits for the framebuffer's own read of the limit
// (the watcher's count moves) or 10 s, then 2 s more (wakeMargin), then
// calls Owner::didWake. A sleep that starts meanwhile (dark wake, then sleep
// again) ends the wait without didWake: the next wake waits again.
constexpr uint64_t kWakeReadWaitMs = 10000;
enum class WakeWait : uint32_t { Keep, Done, Abort };
inline WakeWait wakeWait(uint64_t sleepGenAtWake, uint64_t sleepGenNow,
                         bool inSleep, uint64_t readsAtWake, uint64_t readsNow,
                         uint64_t startMs, uint64_t nowMs) {
  if (sleepGenNow != sleepGenAtWake || inSleep) return WakeWait::Abort;
  if (readsNow != readsAtWake) return WakeWait::Done;
  if (nowMs >= startMs && nowMs - startMs >= kWakeReadWaitMs)
    return WakeWait::Done;
  return WakeWait::Keep;
}
// That read is the FIRST step of the framebuffer's wake-time
// initializePowerTuneParameters; the driver's own escape path waits for its
// isReady, set only at the END of that function. So after the read (or the
// 10 s) the worker waits 2 s more before didWake or any send. Same abort
// rule; `readMs` is when wakeWait said Done.
constexpr uint64_t kWakeReadyMarginMs = 2000;
inline WakeWait wakeMargin(uint64_t sleepGenAtWake, uint64_t sleepGenNow,
                           bool inSleep, uint64_t readMs, uint64_t nowMs) {
  if (sleepGenNow != sleepGenAtWake || inSleep) return WakeWait::Abort;
  if (nowMs >= readMs && nowMs - readMs >= kWakeReadyMarginMs)
    return WakeWait::Done;
  return WakeWait::Keep;
}

// Sleep handshake: the routed ppSleep (entered with no AMD lock held, before
// the original takes the PowerPlay lock) sets the sleep flag under the
// control's state lock, then waits for a ppCWDDE call already in flight, at
// most 3 s (one stuck 2 s SMU mailbox wait, PP_WaitOnRegisterTimeout), before
// it lets the sleep go on. The worker checks the flag and marks its call in
// flight under the same lock, so a call either finishes before the sleep
// starts or is never made.
constexpr uint64_t kSleepWaitMs = 3000;
// GPU termination: wait at most 2 s for a ppCWDDE call already running, then
// let the driver finish tearing down. Power off and restart do not wait.
constexpr uint64_t kTeardownWaitMs = 2000;

// --------------------------------------------------------------- OD8 reads --
//
// OD8 phase A (design-od8.md v2): two read-only escapes. They read the
// driver's own copy of the OD8 data and send nothing to the power firmware
// (report.md 11.3, 11.4, 11.8).
//   0x9f OD8_GetInitialParameters: in = header only (16), out 928.
//   0xa0 OD8_GetCurrentSettings:   in = header only (16), out 164.
// Both answers start with a COUNT that the caller presets, not with a size.
// The driver clears count-sized memory before it clamps the count, so the
// count is always exactly kOd8Count. Header flag bit 0 = the driver does not
// keep the input for its replay after wake (report.md 11.7). A GPU that is
// asleep or blocked answers 0 without touching the buffer: a sentinel left
// where the driver always writes tells that apart from data.
constexpr uint32_t kEscapeOd8Initial = 0x9f;
constexpr uint32_t kEscapeOd8Current = 0xa0;
constexpr uint32_t kOd8Count = 38;
constexpr uint32_t kOd8Sentinel = 0x5A5A5A5Au;
constexpr uint32_t kOd8Tries = 3;  // each read, 1 s apart
constexpr uint64_t kOd8RetryMs = 1000;
struct Od8Entry {
  uint32_t feature;  // the setting's feature bit, 0 = not offered
  int32_t min, max, def;
  uint32_t zero0, zero1;
};
struct Od8InitialOut {
  uint32_t count, caps;
  Od8Entry e[kOd8Count];
  uint32_t unused[2];
};
struct Od8CurrentOut {
  uint32_t count;
  int32_t cur[kOd8Count];
  uint32_t notAllowed;  // features NOT allowed now (the inverse of a mask)
  uint32_t untouched;   // the driver never writes it
};
static_assert(sizeof(Od8Entry) == 24, "0x9f entry 24 bytes");
static_assert(sizeof(Od8InitialOut) == 928, "0x9f answer 928 bytes");
static_assert(sizeof(Od8CurrentOut) == 164, "0xa0 answer 164 bytes");

inline EscapeHeader od8Query(uint32_t escape) {
  return EscapeHeader{kEscapeHeaderSize, kEscapeCode | escape, 1, 0};
}
inline void od8PrepareInitial(Od8InitialOut* o) {
  *o = Od8InitialOut{};
  o->count = kOd8Count;
  o->e[0].feature = kOd8Sentinel;
}
inline void od8PrepareCurrent(Od8CurrentOut* o) {
  *o = Od8CurrentOut{};
  o->count = kOd8Count;
  o->cur[0] = static_cast<int32_t>(kOd8Sentinel);
  o->untouched = kOd8Sentinel;
}

// The feature bit each setting id belongs to (report.md 11.2).
inline uint32_t od8Feature(uint32_t id) {
  if (id <= 1) return 0x1;
  if (id <= 7) return 0x2;
  if (id == 8 || id == 34) return 0x4;
  if (id == 9) return 0x8;
  if (id == 10) return 0x20;
  if (id == 11) return 0x10;
  if (id == 12) return 0x40;
  if (id == 13) return 0x80;
  if (id == 14) return 0x100;
  if (id == 15 || id == 35) return 0x200;
  if (id == 16) return 0x400;
  if (id == 17) return 0x800;
  if (id == 18) return 0x1000;
  if (id <= 28) return 0x2000;
  if (id == 29) return 0x4000;
  if (id <= 33) return 0x8000;
  if (id == 36) return 0x10000;
  if (id == 37) return 0x20000;
  return 0;
}
constexpr uint32_t kOd8KnownFeatures = 0x3FFFF;
inline const char* od8Name(uint32_t id) {
  static const char* const names[kOd8Count] = {
      "GfxMaxMHz",     "GfxMinMHz",       "GfxPoint1MHz", "GfxPoint1mV",
      "GfxPoint2MHz",  "GfxPoint2mV",     "GfxPoint3MHz", "GfxPoint3mV",
      "MemMaxMHz",     "PowerPercent",    "FanMinRPM",    "FanAcousticRPM",
      "FanTargetC",    "OperatingMaxC",   "AcTiming",     "FanZeroRpm",
      "AutoUndervolt", "AutoOcGfx",       "AutoOcMem",    "FanCurve1C",
      "FanCurve1Pct",  "FanCurve2C",      "FanCurve2Pct", "FanCurve3C",
      "FanCurve3Pct",  "FanCurve4C",      "FanCurve4Pct", "FanCurve5C",
      "FanCurve5Pct",  "AutoFanAcoustic", "GfxCurveA",    "GfxCurveB",
      "GfxCurveC",     "GfxCurveD",       "MemMinMHz",    "FanZeroRpmStopC",
      "PowerMode",     "GfxVoltOffset"};
  return id < kOd8Count ? names[id] : "?";
}
// The fan curve's 5 points: temperature id 19 + 2k, speed id 20 + 2k.
constexpr uint32_t kOd8CurvePoints = 5;
inline uint32_t od8CurveTempId(uint32_t k) { return 19 + 2 * k; }
inline uint32_t od8CurveSpeedId(uint32_t k) { return 20 + 2 * k; }

enum class Od8Read : uint32_t {
  Waiting,      // not read yet
  Ok,           // data, and every entry as report.md 11.3 says
  Odd,          // data, but an entry not as expected (see the odd entry)
  NoData,       // answered 0 without writing: asleep or blocked
  NotCalled,    // nothing was called: asleep, torn down, no object
  Refused,      // 0xE00002BC: OD8 is off on this card, or the lock was busy
  Unsupported,  // 0xE00002C7: not initialized
  Error,        // an answer that does not fit the escape: no more reads
};
inline const char* od8ReadText(Od8Read r) {
  switch (r) {
    case Od8Read::Waiting:
      return "waiting for the driver";
    case Od8Read::Ok:
      return "read";
    case Od8Read::Odd:
      return "read, but an entry is not as expected";
    case Od8Read::NoData:
      return "no data: the GPU was asleep or blocked";
    case Od8Read::NotCalled:
      return "not read: going to sleep, or the driver went away";
    case Od8Read::Refused:
      return "not available: the driver refused it (OD8 off on this card?)";
    case Od8Read::Unsupported:
      return "not available: OD8 not initialized";
    case Od8Read::Error:
      return "stopped: an answer that does not fit";
  }
  return "?";
}
// After a failed try: is another one worth it.
inline bool od8Retry(Od8Read r) {
  return r == Od8Read::NoData || r == Od8Read::NotCalled ||
         r == Od8Read::Refused || r == Od8Read::Unsupported;
}

inline Od8Read od8Answer(uint32_t ret, uint32_t outSize, uint32_t wantSize) {
  if (ret == kRetError) return Od8Read::Refused;
  if (ret == kRetUnsupported) return Od8Read::Unsupported;
  if (ret != kRetOK || outSize != wantSize) return Od8Read::Error;
  return Od8Read::Ok;
}
// *odd = 0 when every entry is as expected, else the first odd entry + 1
// (caps word: 39, count word: 40, the unused tail: 41).
inline Od8Read od8CheckInitial(uint32_t ret, uint32_t outSize,
                               const Od8InitialOut& o, uint32_t* odd) {
  *odd = 0;
  Od8Read a = od8Answer(ret, outSize, sizeof(Od8InitialOut));
  if (a != Od8Read::Ok) return a;
  if (o.e[0].feature == kOd8Sentinel) return Od8Read::NoData;
  if (o.count != kOd8Count) {
    *odd = 40;
    return Od8Read::Odd;
  }
  if ((o.caps & ~kOd8KnownFeatures) != 0) {
    *odd = 39;
    return Od8Read::Odd;
  }
  for (uint32_t i = 0; i < kOd8Count; i++) {
    const Od8Entry& e = o.e[i];
    bool ok = (e.feature == 0 || e.feature == od8Feature(i)) && e.zero0 == 0 &&
              e.zero1 == 0 && (e.feature == 0 || e.min <= e.max);
    if (!ok) {
      *odd = i + 1;
      return Od8Read::Odd;
    }
  }
  if (o.unused[0] != 0 || o.unused[1] != 0) {
    *odd = 41;
    return Od8Read::Odd;
  }
  return Od8Read::Ok;
}
// *odd: 40 = count word, 41 = the word after the answer was written.
inline Od8Read od8CheckCurrent(uint32_t ret, uint32_t outSize,
                               const Od8CurrentOut& o, uint32_t* odd) {
  *odd = 0;
  Od8Read a = od8Answer(ret, outSize, sizeof(Od8CurrentOut));
  if (a != Od8Read::Ok) return a;
  if (o.cur[0] == static_cast<int32_t>(kOd8Sentinel)) return Od8Read::NoData;
  if (o.count != kOd8Count) {
    *odd = 40;
    return Od8Read::Odd;
  }
  if (o.untouched != kOd8Sentinel) {
    *odd = 41;
    return Od8Read::Odd;
  }
  return Od8Read::Ok;
}
// Whether two reads of the defaults are the same (the first one is "stock").
inline bool od8SameDefaults(const Od8InitialOut& a, const Od8InitialOut& b) {
  if (a.caps != b.caps) return false;
  for (uint32_t i = 0; i < kOd8Count; i++)
    if (a.e[i].feature != b.e[i].feature || a.e[i].min != b.e[i].min ||
        a.e[i].max != b.e[i].max || a.e[i].def != b.e[i].def)
      return false;
  return true;
}
inline bool od8SameCurrent(const Od8CurrentOut& a, const Od8CurrentOut& b) {
  for (uint32_t i = 0; i < kOd8Count; i++)
    if (a.cur[i] != b.cur[i]) return false;
  return true;
}

// ------------------------------------------------- the card's power range --
//
// The card's own power range (0.8.0). The floor is what Linux amdgpu takes as
// the minimum package power limit of a Navi 21 (power1_cap_min):
// sienna_cichlid_init_ppt_limits() in swsmu/smu11/sienna_cichlid_ppt.c sets
//   min = SocketPowerLimitAc[PPT_THROTTLER_PPT0]
//         * (100 - overdrive_table.min[SMU_11_0_7_ODSETTING_POWERPERCENTAGE])
//         / 100
// when overdrive_table.cap[SMU_11_0_7_ODCAP_POWER_LIMIT] is set, and
// min = the start-up value otherwise (struct smu_11_0_7_overdrive_table,
// swsmu/inc/smu_v11_0_7_pptable.h). The driver's 0x9f gives the same table
// entry as setting 9 (PowerPercent, feature 0x8 = 1 << ODCAP_POWER_LIMIT),
// with the lower bound as a negative percent: -6 on the owner's card, whose
// PP_PhmSoftPowerPlayTable carries min 6, max 9 and SocketPowerLimitAc 240
// (read from ioreg, 2026-11-20). The start-up value stands for
// SocketPowerLimitAc: it is the framebuffer's first read at power-up (the
// kext does not parse the power table). Linux master takes the table's value;
// v6.6 took the firmware's current limit (smu_v11_0_get_current_power_limit,
// the table as fallback) and had no minimum at all. The two differ only if
// something set the limit before that first read; on the owner's card both are
// 240 W, on other cards it is not checked. Same integer division as Linux (225
// W on the owner's 240 W), so nothing below what Linux allows is taken when
// they agree. Only the first clean 0x9f after boot counts, so the floor never
// moves during a boot. Nothing here is a guessed number: when the card's data
// is missing, odd or not read yet, the floor is not known and every change is
// refused (NoFloor). The power firmware itself took 200 W on the owner's card
// (0.5.0 test, read back 199.4 W), so the firmware does not enforce this floor:
// the kext does.
constexpr uint32_t kOd8PowerPercent = 9;
constexpr uint32_t kOd8PowerFeature = 0x8;
// A lower bound further down than this is taken as a broken read (refused),
// never as a floor. Tables seen: -6 (the owner's RX 6800 XT).
constexpr int32_t kMaxPowerPercentDown = 50;
enum class FloorState : uint32_t {
  Known = 0,
  NoBootValue,    // the start-up limit is not read yet, or not believable
  NotRead,        // OD8 was not read yet
  NotAsExpected,  // the first 0x9f was odd, or its power entry is
  NotOffered,     // the card offers no lower limit: the floor is the start-up
};
struct PowerRange {
  FloorState state;
  uint32_t floorW;  // 0 unless the floor is known
  uint32_t maxW;    // the start-up limit (never raised); 0 until believable
  int32_t percentMin, percentMax;  // the card's PowerPercent, when read
};
inline PowerRange powerRange(uint32_t bootW, bool haveStock, bool stockOdd,
                             const Od8InitialOut& stock) {
  PowerRange r{FloorState::NoBootValue, 0, 0, 0, 0};
  if (!bootValuePlausible(bootW)) return r;
  r.maxW = bootW;
  if (!haveStock) {
    r.state = FloorState::NotRead;
    return r;
  }
  const Od8Entry& e = stock.e[kOd8PowerPercent];
  r.percentMin = e.min;
  r.percentMax = e.max;
  if (stockOdd || (e.feature != 0 && e.feature != kOd8PowerFeature) ||
      e.zero0 != 0 || e.zero1 != 0) {
    r.state = FloorState::NotAsExpected;
    return r;
  }
  if (e.feature == 0) {  // Linux: od_percent_lower = 0, min = the default
    r.state = FloorState::NotOffered;
    r.floorW = bootW;
    return r;
  }
  if (e.min > 0 || e.min < -kMaxPowerPercentDown || e.min > e.max) {
    r.state = FloorState::NotAsExpected;
    return r;
  }
  r.state = FloorState::Known;
  r.floorW = bootW * static_cast<uint32_t>(100 + e.min) / 100;
  return r;
}
inline const char* floorStateText(FloorState s) {
  switch (s) {
    case FloorState::Known:
      return "from the card: start-up limit less its OD8 power percent";
    case FloorState::NoBootValue:
      return "not known: the start-up limit is not read yet or not believable";
    case FloorState::NotRead:
      return "not known yet: waiting for a clean OD8 read";
    case FloorState::NotAsExpected:
      return "not known: the card's OD8 power entry is not as expected";
    case FloorState::NotOffered:
      return "the card offers no lower power limit: only the start-up limit";
  }
  return "unknown";
}

// -------------------------------------------------------- OD8 writes (0.7.0)
// --
//
// design-od8-b.md v3 + v3.1. Three settings, each only in the direction that
// cannot make the card hotter: the fan curve (more air than stock, all ten
// entries in every call), zero RPM (off only: the fan always spins), and the
// GFX maximum clock (lower only, not below 1500 MHz). Everything else goes out
// with requested 0.
//   0xa1 OD8_SetSettings: in = header {16, 0x00C000A1, 1 = not kept for
//        replay, 0} + count 38 + 38 x {value, requested, reset, 0, 0} + 8
//        unused (788); out = a 0xa0 answer (164), out[0] must equal 38.
// Every call carries all ten fan curve entries requested 1: the wanted curve,
// or the all-ten reset (FanMode 0, the points back to the driver's defaults).
// So the driver's legacy branch for a partial curve (which caps the fan's
// maximum RPM from entry 28) can never run. Every call also carries zero RPM
// and the GFX pair explicitly: the result does not depend on what was staged
// before (a failed call leaves its change staged in the driver).
constexpr uint32_t kEscapeOd8Set = 0xa1;
struct Od8SetEntry {
  int32_t value;
  uint32_t requested, reset, zero0, zero1;
};
struct Od8SetIn {
  EscapeHeader header;
  uint32_t count;
  Od8SetEntry e[kOd8Count];
  uint32_t unused[2];
};
static_assert(sizeof(Od8SetEntry) == 20, "0xa1 entry 20 bytes");
static_assert(sizeof(Od8SetIn) == 16 + 772, "0xa1 request 788 bytes");

constexpr uint32_t kOd8GfxMax = 0, kOd8GfxMin = 1, kOd8MemMax = 8,
                   kOd8TargetTemp = 12, kOd8ZeroRpm = 15, kOd8ZeroRpmStop = 35;
constexpr int32_t kOd8GfxFloorMHz = 1500;
// Factory defaults move a little across a wake (GfxMax 2354 -> 2359 MHz,
// 2026-11-19): this much is accepted for the GFX pair, nothing for the rest.
constexpr int32_t kOd8DriftMHz = 25;
// The stock fan loop reads the hotspot (PPT FanTempInputSelect = 1). Until a
// test shows which sensor the curve reads, the curve must reach 100 % this
// much below the target temperature, in case it reads the edge sensor
// (design v3.1 F). Test 0 (2026-11-19, gpubench 60 s at 240 W): hotspot -
// edge at load min 16, median 18, max 22 C; the max is used.
constexpr int32_t kOd8SensorGapC = 22;
constexpr int32_t kOd8FirstPointMaxC = 30;

// What a program wants: the whole state, never one setting.
struct Od8Want {
  bool curve;  // false: the stock behaviour (the all-ten reset)
  int32_t temp[kOd8CurvePoints], speed[kOd8CurvePoints];
  bool zeroRpmOff;
  int32_t gfxMaxMHz;  // 0 = stock
};
inline bool od8IsStock(const Od8Want& w) {
  return !w.curve && !w.zeroRpmOff && w.gfxMaxMHz == 0;
}

enum class Od8Check : uint32_t {
  Ok = 0,
  NotRead,       // OD8 not read cleanly since boot (phase A), or stock was odd
  Drifted,       // the fresh read differs from stock beyond the allowance
  MemoryMoved,   // the memory clock is not at stock (the commit would blank)
  NoFeature,     // a setting this needs is not offered as expected
  CurveRange,    // a point outside the driver's range, or 0
  CurveOrder,    // temperatures not strictly rising, or speeds falling
  CurveFirst,    // the first point above 30 C
  CurveLast,     // the last point not 100 %, or above the target - the gap
  CurveCooling,  // less air than the stock curve somewhere below the target
  GfxRange,      // GFX max above stock, below 1500, or below the GFX min
  NoReadings,    // a curve, but the fan watchdog has no fresh readings
};
inline const char* od8CheckText(uint64_t c) {
  switch (static_cast<Od8Check>(c)) {
    case Od8Check::Ok:
      return "ok";
    case Od8Check::NotRead:
      return "OD8 was not read cleanly since boot";
    case Od8Check::Drifted:
      return "OD8 now differs from the first read after boot";
    case Od8Check::MemoryMoved:
      return "the memory clock is not at stock";
    case Od8Check::NoFeature:
      return "a setting is not offered as expected on this card";
    case Od8Check::CurveRange:
      return "a fan point is outside the driver's range (25-100 C, 20-100 %)";
    case Od8Check::CurveOrder:
      return "fan temperatures must rise and speeds must not fall";
    case Od8Check::CurveFirst:
      return "the first fan point must be at 30 C or below";
    case Od8Check::CurveLast:
      return "the last fan point must be 100 % at or below the safe top "
             "temperature";
    case Od8Check::CurveCooling:
      return "the curve gives less air than stock somewhere";
    case Od8Check::GfxRange:
      return "GFX max must be between 1500 MHz and the stock maximum";
    case Od8Check::NoReadings:
      return "the fan watchdog has no fresh hotspot and fan readings";
  }
  return "unknown";
}

// The curve the driver reports at stock (made up from the target
// temperature), at temperature t: straight lines between its points, the
// first speed below the first point, the last above the last. Rounded up.
inline int32_t od8StockCurveAt(const Od8InitialOut& first, int32_t t) {
  int32_t T[kOd8CurvePoints], S[kOd8CurvePoints];
  for (uint32_t k = 0; k < kOd8CurvePoints; k++) {
    T[k] = first.e[od8CurveTempId(k)].def;
    S[k] = first.e[od8CurveSpeedId(k)].def;
  }
  if (t <= T[0]) return S[0];
  for (uint32_t k = 0; k + 1 < kOd8CurvePoints; k++)
    if (t <= T[k + 1]) {
      int32_t dt = T[k + 1] - T[k];
      if (dt <= 0) return S[k + 1];
      int32_t num = (S[k + 1] - S[k]) * (t - T[k]);
      return S[k] + (num + dt - 1) / dt;  // speeds rise: num >= 0
    }
  return S[kOd8CurvePoints - 1];
}
// A requested curve at t, the same way, rounded down.
inline int32_t od8WantCurveAt(const Od8Want& w, int32_t t) {
  if (t <= w.temp[0]) return w.speed[0];
  for (uint32_t k = 0; k + 1 < kOd8CurvePoints; k++)
    if (t <= w.temp[k + 1]) {
      int32_t dt = w.temp[k + 1] - w.temp[k];
      if (dt <= 0) return w.speed[k + 1];
      return w.speed[k] + (w.speed[k + 1] - w.speed[k]) * (t - w.temp[k]) / dt;
    }
  return w.speed[kOd8CurvePoints - 1];
}

// Before the way back too: the feature bits, ranges and caps the driver
// gives now are the ones it gave at boot.
inline bool od8SameLayout(const Od8InitialOut& first,
                          const Od8InitialOut& fresh) {
  if (first.caps != fresh.caps) return false;
  for (uint32_t i = 0; i < kOd8Count; i++)
    if (first.e[i].feature != fresh.e[i].feature ||
        first.e[i].min != fresh.e[i].min || first.e[i].max != fresh.e[i].max)
      return false;
  return true;
}
inline int32_t od8Abs(int32_t v) { return v < 0 ? -v : v; }
// The stock GFX maximum for a call now: never above the first read.
inline int32_t od8StockGfxMax(const Od8InitialOut& first,
                              const Od8InitialOut& fresh) {
  int32_t a = first.e[kOd8GfxMax].def, b = fresh.e[kOd8GfxMax].def;
  return a < b ? a : b;
}

// Every check before a change. first = the first clean 0x9f after boot,
// fresh and cur = the 0x9f and 0xa0 the worker read right before.
inline Od8Check od8CheckWant(const Od8Want& w, const Od8InitialOut& first,
                             const Od8InitialOut& fresh,
                             const Od8CurrentOut& cur) {
  if (!od8SameLayout(first, fresh)) return Od8Check::Drifted;
  for (uint32_t i = 0; i < kOd8Count; i++) {
    int32_t d = od8Abs(first.e[i].def - fresh.e[i].def);
    bool gfx = i == kOd8GfxMax || i == kOd8GfxMin;
    if (gfx ? d > kOd8DriftMHz : d != 0) return Od8Check::Drifted;
  }
  if (cur.cur[kOd8MemMax] != first.e[kOd8MemMax].def)
    return Od8Check::MemoryMoved;
  // What every call touches must be offered as report.md 11.5 says.
  const Od8Entry& z = first.e[kOd8ZeroRpm];
  const Od8Entry& zs = first.e[kOd8ZeroRpmStop];
  if (first.e[kOd8GfxMax].feature != 0x1 ||
      first.e[kOd8GfxMin].feature != 0x1 || z.feature != 0x200 || z.def != 1 ||
      zs.feature != 0x200 || zs.min != zs.max || zs.def != zs.min)
    return Od8Check::NoFeature;
  for (uint32_t k = 0; k < kOd8CurvePoints; k++)
    if (first.e[od8CurveTempId(k)].feature != 0x2000 ||
        first.e[od8CurveSpeedId(k)].feature != 0x2000)
      return Od8Check::NoFeature;
  int32_t target = first.e[kOd8TargetTemp].def;
  if (target < 40 || target > 100) return Od8Check::NoFeature;

  if (w.curve) {
    for (uint32_t k = 0; k < kOd8CurvePoints; k++) {
      const Od8Entry& te = fresh.e[od8CurveTempId(k)];
      const Od8Entry& se = fresh.e[od8CurveSpeedId(k)];
      if (w.temp[k] <= 0 || w.speed[k] <= 0 || w.temp[k] < te.min ||
          w.temp[k] > te.max || w.speed[k] < se.min || w.speed[k] > se.max)
        return Od8Check::CurveRange;
      if (k > 0 && (w.temp[k] <= w.temp[k - 1] || w.speed[k] < w.speed[k - 1]))
        return Od8Check::CurveOrder;
    }
    if (w.temp[0] > kOd8FirstPointMaxC) return Od8Check::CurveFirst;
    uint32_t last = kOd8CurvePoints - 1;
    if (w.speed[last] != 100 || w.temp[last] > target - kOd8SensorGapC)
      return Od8Check::CurveLast;
    // At least the stock curve at every point of either curve.
    for (uint32_t k = 0; k < kOd8CurvePoints; k++) {
      int32_t tw = w.temp[k];
      int32_t ts = first.e[od8CurveTempId(k)].def;
      if (od8WantCurveAt(w, tw) < od8StockCurveAt(first, tw) ||
          od8WantCurveAt(w, ts) < od8StockCurveAt(first, ts))
        return Od8Check::CurveCooling;
    }
  }
  if (w.gfxMaxMHz != 0) {
    int32_t top = od8StockGfxMax(first, fresh);
    if (w.gfxMaxMHz < kOd8GfxFloorMHz || w.gfxMaxMHz > top ||
        w.gfxMaxMHz < first.e[kOd8GfxMin].def)
      return Od8Check::GfxRange;
  }
  return Od8Check::Ok;
}

// The whole 0xa1 for a state. With the stock state this is the one fixed way
// back (design v3.1 B): the all-ten curve reset, zero RPM at its stock value,
// the GFX pair at stock, whatever was staged before. Reset entries carry the
// fresh 0x9f default: the driver resets to its own current default, so that is
// what the read-back must show (the same as the first one on a change, where
// the checks want them equal).
inline void od8Build(const Od8Want& w, const Od8InitialOut& first,
                     const Od8InitialOut& fresh, Od8SetIn* out) {
  *out = Od8SetIn{};
  out->header = od8Query(kEscapeOd8Set);
  out->count = kOd8Count;
  for (uint32_t k = 0; k < kOd8CurvePoints; k++) {
    uint32_t ti = od8CurveTempId(k), si = od8CurveSpeedId(k);
    if (w.curve) {
      out->e[ti] = Od8SetEntry{w.temp[k], 1, 0, 0, 0};
      out->e[si] = Od8SetEntry{w.speed[k], 1, 0, 0, 0};
    } else {
      out->e[ti] = Od8SetEntry{fresh.e[ti].def, 1, 1, 0, 0};
      out->e[si] = Od8SetEntry{fresh.e[si].def, 1, 1, 0, 0};
    }
  }
  out->e[kOd8ZeroRpm] =
      Od8SetEntry{w.zeroRpmOff ? 0 : fresh.e[kOd8ZeroRpm].def, 1, 0, 0, 0};
  out->e[kOd8ZeroRpmStop] =
      Od8SetEntry{fresh.e[kOd8ZeroRpmStop].def, 1, 0, 0, 0};
  int32_t gfx = w.gfxMaxMHz != 0 ? w.gfxMaxMHz : od8StockGfxMax(first, fresh);
  out->e[kOd8GfxMax] = Od8SetEntry{gfx, 1, 0, 0, 0};
  out->e[kOd8GfxMin] = Od8SetEntry{first.e[kOd8GfxMin].def, 1, 0, 0, 0};
}
// Every call's shape, checked again where it is sent: count 38, all ten curve
// entries requested 1 (never 1..9 of them), nothing outside the five
// settings requested, no reset outside the curve.
inline bool od8ShapeOk(const Od8SetIn& in) {
  if (in.count != kOd8Count ||
      in.header.code != (kEscapeCode | kEscapeOd8Set) ||
      in.header.reserved0 != 1)
    return false;
  uint32_t curve = 0;
  for (uint32_t i = 0; i < kOd8Count; i++) {
    const Od8SetEntry& e = in.e[i];
    bool isCurve = i >= 19 && i <= 28;
    bool allowed = isCurve || i == kOd8GfxMax || i == kOd8GfxMin ||
                   i == kOd8ZeroRpm || i == kOd8ZeroRpmStop;
    if (e.zero0 != 0 || e.zero1 != 0 || e.requested > 1 || e.reset > 1)
      return false;
    if (!allowed && (e.requested != 0 || e.reset != 0)) return false;
    if (!isCurve && e.reset != 0) return false;
    if (isCurve && e.requested == 1) curve++;
    if (isCurve && e.value <= 0) return false;
    if (i == kOd8GfxMax && e.requested == 1 && e.value < kOd8GfxFloorMHz)
      return false;
  }
  return curve == 10 && in.unused[0] == 0 && in.unused[1] == 0;
}

// The read-back after a call (design section 5): 0 = as sent, else the first
// entry that is not + 1 (39 = the allowed mask moved). Requested entries
// must read what was sent (GFX max may read lower, by up to the allowance:
// the firmware rounds; never higher); the others what they read before.
inline uint32_t od8VerifyAfter(const Od8SetIn& sent,
                               const Od8CurrentOut& before,
                               const Od8CurrentOut& after) {
  for (uint32_t i = 0; i < kOd8Count; i++) {
    int32_t a = after.cur[i];
    if (sent.e[i].requested == 1) {
      int32_t v = sent.e[i].value;
      bool ok = i == kOd8GfxMax ? (a <= v && a >= v - kOd8DriftMHz) : a == v;
      if (!ok) return i + 1;
    } else if (a != before.cur[i]) {
      return i + 1;
    }
  }
  return after.notAllowed == before.notAllowed ? 0 : 39;
}

// The kernel watchdog while a curve is held (design v3.1 F): once a second,
// from GPUSensors' own PMLog. Trip = the fixed way back now, then writing off
// until restart.
// At stock a 240 W load passes 85 C after 80 s and sits at 90-91 C after 5
// minutes with the fan at 96-100 % (gpubench --sustain 300, 2026-11-19), so
// stock gives no more air there: the limit is that peak + 4. The firmware
// throttles by itself at 110 C.
constexpr uint32_t kOd8DogHotC = 95;
constexpr uint32_t kOd8DogAboveTarget = 5;
constexpr uint64_t kOd8DogHoldMs = 5000;
constexpr uint64_t kOd8DogStaleMs = 10000;
// PMLog id 15 is the fan RPM over the table's maximum (1208 RPM read 34 % with
// 3500), so full PWM may read a little under 100: 90 % counts as full air.
constexpr uint32_t kOd8DogFanFullPct = 90;
// A curve is only taken while the watchdog has readings this fresh.
constexpr uint64_t kOd8DogFreshMs = 2000;
inline bool od8DogCanWatch(bool haveLog, uint64_t ageMs) {
  return haveLog && ageMs <= kOd8DogFreshMs;
}
enum class Od8Dog : uint32_t { Fine, Trip, Blind };
struct Od8Watch {
  bool hot{false};
  uint64_t hotSinceMs{0};
};
inline Od8Dog od8Watchdog(Od8Watch* w, bool haveLog, uint64_t ageMs,
                          uint32_t hotspotC, uint32_t fanPct, int32_t targetC,
                          uint64_t nowMs) {
  if (!haveLog || ageMs > kOd8DogStaleMs) return Od8Dog::Blind;
  if (hotspotC >= kOd8DogHotC) return Od8Dog::Trip;
  bool hot = targetC > 0 &&
             hotspotC >= static_cast<uint32_t>(targetC) + kOd8DogAboveTarget &&
             fanPct < kOd8DogFanFullPct;
  if (!hot) {
    w->hot = false;
    return Od8Dog::Fine;
  }
  if (!w->hot) {
    w->hot = true;
    w->hotSinceMs = nowMs;
    return Od8Dog::Fine;
  }
  return nowMs >= w->hotSinceMs && nowMs - w->hotSinceMs >= kOd8DogHoldMs
             ? Od8Dog::Trip
             : Od8Dog::Fine;
}

// ------------------------------------------------- what keeps writing off --
//
// Writing stays off until restart (Owner::turnOff at start) when one of these
// is not met; the reason is kept for ioreg and gpucontrol.
enum class WriteOff : uint32_t {
  None = 0,
  CtlOff,           // -gpuctloff
  NotOneCard,       // not exactly one readable card
  OtherAmdGpu,      // another AMD GPU besides it
  Library,          // not AMDRadeonX6000HWLibs
  Routes,           // a watched function is not routed
  Cwdde,            // ppCWDDE not found or not as expected
  SecondObject,     // a second PowerPlay object or hwmgr showed up
  BootImplausible,  // the start-up limit read is outside 200..300 W (a read
                    // check: the floor for requests is the card's, PowerRange)
  Start,            // the worker or a notification could not be set up
  SendFailed,       // a change was not confirmed
  RevertFailed,     // a way back did not take
  Teardown,         // the GPU went away or the system is powering off
  Od8Failed,        // an OD8 change did not read back as sent
  Od8Watchdog,      // the fan watchdog took the curve back
  ReadOnlyCard,     // 0.8.0: a card the kext reads but never writes (73BF
                    // rev C0, the RX 6900 XT); the reads run as on the C1
};
struct WritePrereqs {
  bool ctlOff;
  uint32_t allowedGpus;  // cards the kext reads (deviceReadable)
  uint32_t amdGpus;      // every AMD GPU, the readable one included
  bool x6000Library;
  bool routed;  // ppInitialize, GetPowerLimit, set_power_limit, sleep, wake
  bool cwddeChecked;
  bool readOnly{false};  // the readable card is not deviceAllowed (0.8.0)
};
// The first reason that keeps writing off. ReadOnlyCard comes last: it means
// everything else is in place, so the reads run and only writing stays off.
inline WriteOff staticRefusal(const WritePrereqs& p) {
  if (p.ctlOff) return WriteOff::CtlOff;
  if (p.allowedGpus != 1) return WriteOff::NotOneCard;
  if (p.amdGpus != 1) return WriteOff::OtherAmdGpu;
  if (!p.x6000Library) return WriteOff::Library;
  if (!p.routed) return WriteOff::Routes;
  if (!p.cwddeChecked) return WriteOff::Cwdde;
  if (p.readOnly) return WriteOff::ReadOnlyCard;
  return WriteOff::None;
}
// Whether the kext's worker starts (it does the reads too): with everything
// in place, and on a read-only card, which is turned off before it starts.
inline bool workerStarts(WriteOff refusal) {
  return refusal == WriteOff::None || refusal == WriteOff::ReadOnlyCard;
}
// The card scan (0.8.0): None when every readable card may write; with one
// readable card that may not, ReadOnlyCard (the kext marks Owner read only
// at once and every sender refuses); with more cards and any of them read
// only, NotOneCard (writing is off as for any two cards; the senders still
// refuse, but no card is called "read only").
inline WriteOff scanReason(uint32_t readable, uint32_t writable) {
  if (writable >= readable) return WriteOff::None;
  return readable == 1 ? WriteOff::ReadOnlyCard : WriteOff::NotOneCard;
}
// The reason kept once writing is off: the first one, except that
// ReadOnlyCard (set at the scan, true whatever happens later) gives way to a
// later reason that also stops the reads, which is then the one worth showing
// (the library never came is no reason: it changes nothing here). Writing
// stays off and the card stays marked read only either way.
inline bool readsStop(WriteOff w) {
  switch (w) {
    case WriteOff::CtlOff:
    case WriteOff::NotOneCard:
    case WriteOff::OtherAmdGpu:
    case WriteOff::Library:
    case WriteOff::Routes:
    case WriteOff::Cwdde:
    case WriteOff::SecondObject:
    case WriteOff::Start:
    case WriteOff::Teardown:
      return true;
    default:
      return false;
  }
}
inline WriteOff keptReason(WriteOff kept, WriteOff why) {
  if (kept == WriteOff::None) return why;
  if (kept == WriteOff::ReadOnlyCard && readsStop(why)) return why;
  return kept;
}
inline const char* writeOffText(WriteOff w) {
  switch (w) {
    case WriteOff::None:
      return "";
    case WriteOff::CtlOff:
      return "-gpuctloff";
    case WriteOff::NotOneCard:
      return "not exactly one RX 6800 XT or RX 6900 XT";
    case WriteOff::OtherAmdGpu:
      return "another AMD GPU is present";
    case WriteOff::Library:
      return "the driver library is not AMDRadeonX6000HWLibs";
    case WriteOff::Routes:
      return "a watched driver function is not routed";
    case WriteOff::Cwdde:
      return "ppCWDDE is not as expected";
    case WriteOff::SecondObject:
      return "a second PowerPlay object showed up";
    case WriteOff::BootImplausible:
      return "the start-up limit read is not believable";
    case WriteOff::Start:
      return "the control could not start its thread";
    case WriteOff::SendFailed:
      return "a change could not be confirmed";
    case WriteOff::RevertFailed:
      return "a way back did not take";
    case WriteOff::Teardown:
      return "the GPU went away or the Mac is stopping";
    case WriteOff::Od8Failed:
      return "an OD8 change did not read back as sent";
    case WriteOff::Od8Watchdog:
      return "the fan watchdog put the stock fan back";
    case WriteOff::ReadOnlyCard:
      return "this card can only be read (RX 6900 XT, 73BF rev C0): writing "
             "never opens on it";
  }
  return "unknown";
}

// ------------------------------------------------------------------- owner --
//
// One program at a time may hold a change. The change belongs to its
// connection: closing it (quit, crash, logout) puts everything back at once.
// A program that hangs with the connection open stops sending its "still
// here" every 5 s; after 30 s without one everything goes back. While nothing
// is changed nobody owns the control. GPU writes (changes and the way back)
// are at least 2 s apart, except the way back itself, which never waits.
// Before sleep nothing is sent to the GPU; after wake, if anything was
// changed, everything goes back. The control starts closed: an administrator
// opens it (arm) until the next restart, or until any program closes it
// again (disarm, 0.8.0), which is refused while anything is applied. A
// read-only card (markReadOnly) never opens.
//
// The kext does every GPU write on one worker thread, one at a time, and tells
// Owner how each way back ended (reverted / revertFailed). Each way back has
// a number (never 0); only the report for the current one counts, so a way
// back that finishes late (after sleep, or after a newer one started) cannot
// clear a change made since.
//
// Time is milliseconds from mach_absolute_time, given by the caller so the
// tests drive the clock. It is monotonic and 64-bit milliseconds never wrap
// (585 million years); a time earlier than the last one is treated as "not
// yet", never as a wrap.
constexpr uint64_t kAliveTimeoutMs = 30000;
constexpr uint64_t kMinChangeGapMs = 2000;
enum class Ask : uint32_t {
  Ok = 0,
  Busy,       // another program holds a change, or the way back is running
  TooSoon,    // less than 2 s since the last GPU write
  Off,        // turned off until restart (failed read-back or way back)
  NotArmed,   // an administrator has not opened the control since restart
  Sleeping,   // between sleep and wake
  BadClient,  // client id 0 means "nobody" and is never an owner
};
class Owner {
 public:
  // An administrator opens the control until the next restart. False when it
  // is off, or the card is read only.
  bool arm() {
    if (off_ || readOnly_) return false;
    armed_ = true;
    return true;
  }
  // Any program closes it again (0.8.0), the opposite of arm: from now
  // on a change is refused as before arm, and arm opens it again. False while
  // anything is applied: a program holds a change, something may not be at
  // start-up values yet (a change or an unconfirmed one), or a way back runs.
  // Closing a control that is closed already is fine; off stays off.
  bool canDisarm() const {
    return !off_ && owner_ == 0 && !dirty_ && !reverting_;
  }
  bool disarm() {
    if (!canDisarm()) return false;
    armed_ = false;
    return true;
  }
  // The card is read only (0.8.0): arm and every change are refused for
  // good, whatever else happens. Set once at start, before anything can arm.
  void markReadOnly() {
    readOnly_ = true;
    armed_ = false;
  }
  // A program asks for a change (power or profile). Going back to the start-up
  // values is not a change: the owner calls release().
  Ask change(uint64_t client, uint64_t nowMs) {
    Ask ask = wouldChange(client, nowMs);
    if (ask != Ask::Ok) return ask;
    owner_ = client;
    lastAliveMs_ = nowMs;
    lastWriteMs_ = nowMs;
    wroteOnce_ = true;
    dirty_ = true;  // counted as changed before the write: a failed write is
                    // undone by going back, which is always safe
    return Ask::Ok;
  }
  // What change() would answer now, changing nothing. The kext asks it before
  // it hands a request to its worker, which then calls change() itself.
  Ask wouldChange(uint64_t client, uint64_t nowMs) const {
    if (client == 0) return Ask::BadClient;
    if (off_ || readOnly_) return Ask::Off;
    if (!armed_) return Ask::NotArmed;
    if (sleeping_) return Ask::Sleeping;
    if (reverting_) return Ask::Busy;
    if (owner_ != 0 && owner_ != client) return Ask::Busy;
    // The owner itself: same rules as alive() (expired() takes a late one).
    if (owner_ == client &&
        (nowMs < lastAliveMs_ || nowMs - lastAliveMs_ >= kAliveTimeoutMs))
      return Ask::Busy;
    if (wroteOnce_ &&
        (nowMs < lastWriteMs_ || nowMs - lastWriteMs_ < kMinChangeGapMs))
      return Ask::TooSoon;
    return Ask::Ok;
  }
  // When expired() takes the change if the owner says nothing more: its last
  // word + 30 s. 0 while nobody owns the control. The worker sleeps until
  // then at most.
  uint64_t deadline() const {
    return owner_ == 0 ? 0 : lastAliveMs_ + kAliveTimeoutMs;
  }
  // The owner says it is still there. False for anyone else, for a time
  // earlier than its last word, and once 30 s have passed (expired() takes it
  // from there).
  bool alive(uint64_t client, uint64_t nowMs) {
    if (owner_ == 0 || owner_ != client) return false;
    if (nowMs < lastAliveMs_ || nowMs - lastAliveMs_ >= kAliveTimeoutMs)
      return false;
    lastAliveMs_ = nowMs;
    return true;
  }
  // The owner puts everything back itself, or its write failed. Not 0: the
  // number of the way back the kext has to send now.
  uint64_t release(uint64_t client) { return drop(client); }
  // A connection closed. Not 0 when it held the change: send the start-up
  // values now.
  uint64_t closed(uint64_t client) { return drop(client); }
  // Called by the kext's timer. Not 0 once, when the owner went silent too
  // long.
  uint64_t expired(uint64_t nowMs) {
    if (owner_ == 0 || nowMs < lastAliveMs_ ||
        nowMs - lastAliveMs_ < kAliveTimeoutMs)
      return 0;
    return drop(owner_);
  }
  // Way back `id` was sent and read back right. Ignored unless it is the
  // current one.
  void reverted(uint64_t id, uint64_t nowMs) {
    if (!reverting_ || id != revertId_) return;
    reverting_ = false;
    dirty_ = false;
    if (!wroteOnce_ || nowMs > lastWriteMs_) lastWriteMs_ = nowMs;
    wroteOnce_ = true;
  }
  // Way back `id` did not take: off until restart. The limit may stay lower
  // than at start-up (the safe side); nothing more is sent. Ignored unless it
  // is the current one.
  void revertFailed(uint64_t id) {
    if (!reverting_ || id != revertId_) return;
    turnOff();
  }
  // Before sleep: forget the owner, drop a pending way back (it runs after
  // wake instead), send nothing to the GPU.
  void willSleep() {
    sleeping_ = true;
    owner_ = 0;
    reverting_ = false;
  }
  // After wake, once the driver finished its own wake. Not 0 when something
  // was changed since the last way back: send the start-up values (the
  // firmware may or may not have kept ours). Never while off.
  uint64_t didWake() {
    bool wasSleeping = sleeping_;
    sleeping_ = false;
    if (!wasSleeping || off_ || !dirty_) return 0;
    return startRevert();
  }
  // A failed read-back, a GPU reset that does not recover: off until restart.
  void turnOff() {
    off_ = true;
    armed_ = false;
    owner_ = 0;
    reverting_ = false;
  }
  uint64_t owner() const { return owner_; }
  bool isOff() const { return off_; }
  bool isReadOnly() const { return readOnly_; }
  bool isArmed() const { return armed_ && !readOnly_; }
  bool isSleeping() const { return sleeping_; }
  bool isReverting() const { return reverting_; }
  bool isChanged() const { return dirty_; }

 private:
  uint64_t drop(uint64_t client) {
    if (owner_ == 0 || owner_ != client) return 0;
    owner_ = 0;
    if (!dirty_) return 0;
    return startRevert();
  }
  uint64_t startRevert() {
    reverting_ = true;
    return ++revertId_;
  }
  uint64_t owner_{0};
  uint64_t lastAliveMs_{0};
  uint64_t lastWriteMs_{0};
  uint64_t revertId_{0};
  bool wroteOnce_{false};
  bool armed_{false};
  bool dirty_{false};
  bool reverting_{false};
  bool sleeping_{false};
  bool off_{false};
  bool readOnly_{false};
};

// ----------------------------------------------------------------- channel --
//
// The IOUserClient on DrogaBoxGPUSensors (0.5.0). Every call passes
// kChannelVersion as its first scalar; another version is refused. Each call
// returns a Reply as its first scalar output (status adds its fields).
//   status   in {version}            out kStatusCount scalars (below); anyone
//   arm      in {version}            an administrator (euid 0) only
//   set      in {version, watts}     waits for the worker, 5 s at most
//   alive    in {version}            the owner's word, every 5 s
//   release  in {version}            the owner goes back to the start-up limit
//   setOd8   in {version, flags, t1..t5, s1..s5, gfxMaxMHz} (13 scalars)
//            out {reply, Od8Check}; flags 1 = a fan curve, 2 = zero RPM off;
//            gfxMaxMHz 0 = stock (0.7.0). The stock state is the way back.
//   disarm   in {version}            anyone (0.8.0): closes writing again;
//            StillApplied while anything is applied; arm reopens it
// Version 2 (0.7.0): setOd8, and status grew. A power change and an OD8
// change are never held together: the other kind answers "busy". 0.8.0 adds
// disarm and two replies at the end and keeps version 2: nothing an older
// program sends means anything else now. An older kext answers disarm with
// kIOReturnBadArgument (an unknown selector).
// set and setOd8 answer Off (writing off, or a read-only card) and then
// NotArmed (never armed since restart, or disarmed) before they look at any
// value they carry (valueGate), so an absurd value still gets the real
// reason.
constexpr uint32_t kChannelVersion = 2;
enum Selector : uint32_t {
  kSelStatus = 0,
  kSelArm,
  kSelSet,
  kSelAlive,
  kSelRelease,
  kSelSetOd8,
  kSelDisarm,  // 0.8.0
  kSelCount,
};
enum class Reply : uint32_t {
  Ok = 0,
  BadVersion,     // the program speaks another version of the channel
  BadArgs,        // wrong number of values
  NotPrivileged,  // arm without administrator rights
  Off,            // writing is off until restart (see WriteOff)
  NotArmed,       // an administrator has not opened it since restart
  NoBootValue,    // the start-up limit is not read yet, or not believable
  NotReady,       // the GPU is asleep, powered down or not ready: nothing sent
  Sleeping,       // between sleep and wake
  Busy,           // another program holds it, a way back runs, the GPU is busy
  TooSoon,        // less than 2 s since the last write
  BelowFloor,
  AboveBoot,
  NotAStep,
  Timeout,     // the worker did not answer in 5 s (or the call was interrupted)
  Failed,      // the change was not confirmed: everything went back, now off
  NotOwner,    // alive from a program that holds nothing
  Cancelled,   // the connection closed while its set waited
  Od8Refused,  // the OD8 state was refused: the second scalar says why
  StillApplied,  // 0.8.0, disarm: something is applied or a request is
                 // being handled; go back to the start-up values first
  NoFloor,       // 0.8.0, set: the card's minimum power limit is not known
                 // (PowerRangeState says why): only the start-up value
};
constexpr uint64_t kSetWaitMs = 5000;
inline Reply replyFor(Ask a) {
  switch (a) {
    case Ask::Ok:
      return Reply::Ok;
    case Ask::Busy:
      return Reply::Busy;
    case Ask::TooSoon:
      return Reply::TooSoon;
    case Ask::Off:
      return Reply::Off;
    case Ask::NotArmed:
      return Reply::NotArmed;
    case Ask::Sleeping:
      return Reply::Sleeping;
    case Ask::BadClient:
      return Reply::BadArgs;
  }
  return Reply::Failed;
}
inline Reply replyFor(PowerCheck c) {
  switch (c) {
    case PowerCheck::Ok:
      return Reply::Ok;
    case PowerCheck::NoBootValue:
      return Reply::NoBootValue;
    case PowerCheck::BelowFloor:
      return Reply::BelowFloor;
    case PowerCheck::AboveBoot:
      return Reply::AboveBoot;
    case PowerCheck::NotAStep:
      return Reply::NotAStep;
    case PowerCheck::NoFloor:
      return Reply::NoFloor;
  }
  return Reply::BadArgs;
}
inline const char* replyText(uint64_t r) {
  switch (static_cast<Reply>(r)) {
    case Reply::Ok:
      return "ok";
    case Reply::BadVersion:
      return "refused: the kext speaks another version of the channel";
    case Reply::BadArgs:
      return "refused: malformed request";
    case Reply::NotPrivileged:
      return "refused: arm needs an administrator (sudo)";
    case Reply::Off:
      return "refused: writing is off until restart";
    case Reply::NotArmed:
      return "refused: not armed since restart (sudo gpucontrol arm)";
    case Reply::NoBootValue:
      return "refused: the start-up limit is not read yet or not believable";
    case Reply::NotReady:
      return "refused: GPU asleep or not ready, nothing sent";
    case Reply::Sleeping:
      return "refused: the Mac is between sleep and wake";
    case Reply::Busy:
      return "busy: another program holds the control, a way back is "
             "running, or the GPU is busy; try later";
    case Reply::TooSoon:
      return "refused: less than 2 s since the last write";
    case Reply::BelowFloor:
      return "refused: below the card's minimum power limit (PowerRange)";
    case Reply::AboveBoot:
      return "refused: above the start-up limit";
    case Reply::NotAStep:
      return "refused: not a 10 W step";
    case Reply::Timeout:
      return "busy: no answer in 5 s; anything held by this program goes "
             "back";
    case Reply::Failed:
      return "failed: the change was not confirmed; the start-up limit was "
             "sent and writing is off until restart";
    case Reply::NotOwner:
      return "this program holds nothing";
    case Reply::Cancelled:
      return "cancelled: the connection closed";
    case Reply::Od8Refused:
      return "refused: the fan or clock setting is not allowed";
    case Reply::StillApplied:
      return "refused: a change is still applied or being handled; go back "
             "to the start-up values first";
    case Reply::NoFloor:
      return "refused: the card's minimum power limit is not known "
             "(PowerRangeState)";
  }
  return "unknown answer";
}
// status: the scalars, in this order.
enum StatusField : uint32_t {
  kStReply = 0,   // Ok, or BadVersion (the version field is still filled)
  kStVersion,     // kChannelVersion of the kext
  kStFlags,       // kFlag* below
  kStBootW,       // the start-up limit, 0 until read
  kStHeldW,       // the limit held now (the start-up one when nothing is)
  kStWriteOff,    // WriteOff, 0 when writing can be armed
  kStChanges,     // confirmed changes since restart
  kStReverts,     // confirmed ways back since restart
  kStLastReply,   // the last set's Reply
  kStOd8Held,     // kOd8Held* below: what the confirmed OD8 state changes
  kStOd8Changes,  // confirmed OD8 changes since restart
  kStOd8Reverts,  // confirmed OD8 ways back since restart
  kStOd8Check,    // the last OD8 refusal (Od8Check)
  kStatusCount,
};
enum : uint64_t {
  kFlagArmed = 1,
  kFlagOff = 2,
  kFlagSleeping = 4,
  kFlagReverting = 8,
  kFlagChanged = 16,
  kFlagOwned = 32,      // some program holds a change
  kFlagMine = 64,       // the program asking does
  kFlagReady = 128,     // the PowerPlay object and the start-up limit are known
  kFlagOd8Ready = 256,  // OD8 was read cleanly since boot: setOd8 can work
};
enum : uint64_t {
  kOd8HeldCurve = 1,
  kOd8HeldZeroRpmOff = 2,
  kOd8HeldGfx = 4,
  kOd8HeldUnknown = 8,  // not confirmed stock (a failed or unapplied call)
};
// setOd8's flags scalar.
enum : uint64_t {
  kOd8WantCurve = 1,
  kOd8WantZeroRpmOff = 2,
};
// ------------------------------------------------ what a call answers first --
//
// The kext asks these under its state lock, before anything else is done.
// arm: why it cannot open now, or Ok (then Owner::arm).
inline Reply armCheck(bool administrator, const Owner& o, bool bootPlausible,
                      bool ready) {
  if (!administrator) return Reply::NotPrivileged;
  if (o.isOff() || o.isReadOnly()) return Reply::Off;
  if (!bootPlausible) return Reply::NoBootValue;
  if (!ready) return Reply::NotReady;
  return Reply::Ok;
}
// disarm (0.8.0): any program may close writing (owner's decision,
// 2026-11-20): closing can only make things safer, it is refused while
// anything is applied, and opening again still needs arm by an
// administrator. The caller's privilege is passed and deliberately not
// required. kextHolds: what the kext itself knows is still applied or being
// handled (a lower limit or an OD8 state not confirmed back, a way back
// waiting, a request waiting or running in its slot: SetSlot::busy). Ok also
// when already closed.
inline Reply disarmCheck(bool /*administrator: not required*/, const Owner& o,
                         bool kextHolds) {
  if (o.isOff() || o.isReadOnly()) return Reply::Off;
  if (kextHolds || !o.canDisarm()) return Reply::StillApplied;
  return Reply::Ok;
}
// set and setOd8, before any value they carry is looked at: writing off (a
// read-only card included), then not armed. A value never decides these.
inline Reply valueGate(const Owner& o) {
  if (o.isOff() || o.isReadOnly()) return Reply::Off;
  if (!o.isArmed()) return Reply::NotArmed;
  return Reply::Ok;
}
// set's {version, watts}: the gate, then a number that cannot be watts.
inline Reply setWire(const Owner& o, uint64_t watts, uint32_t* out) {
  Reply g = valueGate(o);
  if (g != Reply::Ok) return g;
  if (watts > 0xffffffffULL) return Reply::AboveBoot;
  *out = static_cast<uint32_t>(watts);
  return Reply::Ok;
}
// setOd8's {version, flags, t1..t5, s1..s5, gfxMaxMHz}: the gate, then
// anything that cannot be a fan point or a clock is malformed (BadArgs).
// The clock's only wire bound is the 32-bit field (0.8.0, was 5000 MHz): its
// first real check is od8CheckWant's, against the card's stock maximum.
constexpr uint32_t kOd8WireCount = 13;
constexpr uint64_t kOd8WireMaxPoint = 200;
inline Reply od8Wire(const Owner& o, const uint64_t* in, Od8Want* want) {
  Reply g = valueGate(o);
  if (g != Reply::Ok) return g;
  *want = Od8Want{};
  uint64_t flags = in[1];
  bool ok = (flags & ~uint64_t(kOd8WantCurve | kOd8WantZeroRpmOff)) == 0 &&
            in[12] <= 0x7fffffffULL;
  want->curve = (flags & kOd8WantCurve) != 0;
  want->zeroRpmOff = (flags & kOd8WantZeroRpmOff) != 0;
  want->gfxMaxMHz = static_cast<int32_t>(in[12] <= 0x7fffffffULL ? in[12] : 0);
  for (uint32_t k = 0; k < kOd8CurvePoints; k++) {
    uint64_t t = in[2 + k], v = in[7 + k];
    if (t > kOd8WireMaxPoint || v > kOd8WireMaxPoint ||
        (!want->curve && (t != 0 || v != 0)))
      ok = false;
    want->temp[k] = static_cast<int32_t>(t <= kOd8WireMaxPoint ? t : 0);
    want->speed[k] = static_cast<int32_t>(v <= kOd8WireMaxPoint ? v : 0);
  }
  return ok ? Reply::Ok : Reply::BadArgs;
}

// The one pending set: no queue. A program posts its request and waits; the
// worker takes it, asks 0x2a, then checks under the state lock that it is
// still wanted before Owner::change and 0x6e. A program that gives up (5 s,
// interrupted, connection closed) abandons it: a waiting request is gone at
// once, a running one is finished by the worker with nobody to read the
// answer. A second request while one is pending or running is refused.
class SetSlot {
 public:
  // Not 0: the ticket of the request now waiting.
  uint64_t post(uint64_t client, uint32_t watts) {
    if (state_ != State::Empty || client == 0) return 0;
    state_ = State::Waiting;
    client_ = client;
    watts_ = watts;
    abandoned_ = false;
    ticket_ = ++last_;
    return ticket_;
  }
  // The worker takes the waiting request; it is running from now on.
  bool take(uint64_t* ticket, uint64_t* client, uint32_t* watts) {
    if (state_ != State::Waiting) return false;
    state_ = State::Running;
    *ticket = ticket_;
    *client = client_;
    *watts = watts_;
    return true;
  }
  // After 0x2a, before change: does its program still wait for it?
  bool wanted(uint64_t ticket) const {
    return state_ == State::Running && ticket_ == ticket && !abandoned_;
  }
  void finish(uint64_t ticket, Reply reply) {
    if (state_ != State::Running || ticket_ != ticket) return;
    if (abandoned_) {
      state_ = State::Empty;
      return;
    }
    state_ = State::Done;
    reply_ = reply;
  }
  // The program's answer: true once there is one (the slot is free again),
  // Cancelled when its request is gone.
  bool collect(uint64_t ticket, Reply* reply) {
    // A running request its program gave up (close, release) answers at
    // once; the worker's finish() frees the slot later.
    if (ticket == 0 || ticket_ != ticket || state_ == State::Empty ||
        (state_ == State::Running && abandoned_)) {
      *reply = Reply::Cancelled;
      return true;
    }
    if (state_ != State::Done) return false;
    *reply = reply_;
    state_ = State::Empty;
    return true;
  }
  void abandon(uint64_t ticket) {
    if (ticket == 0 || ticket_ != ticket) return;
    if (state_ == State::Running)
      abandoned_ = true;
    else
      state_ = State::Empty;
  }
  void abandonClient(uint64_t client) {
    if (client != 0 && client_ == client && state_ != State::Empty)
      abandon(ticket_);
  }
  bool waiting() const { return state_ == State::Waiting; }
  bool empty() const { return state_ == State::Empty; }
  // A request still being handled: waiting or running. Done (answered, the
  // program has not collected it yet) is not.
  bool busy() const {
    return state_ == State::Waiting || state_ == State::Running;
  }

 private:
  enum class State : uint8_t { Empty, Waiting, Running, Done };
  State state_{State::Empty};
  uint64_t ticket_{0}, last_{0}, client_{0};
  uint32_t watts_{0};
  Reply reply_{Reply::Ok};
  bool abandoned_{false};
};
}  // namespace gpuctl

#endif  // GPUSENSORS_CONTROL_LOGIC_HPP
