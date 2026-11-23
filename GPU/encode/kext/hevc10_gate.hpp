//
//  hevc10_gate.hpp - state machine for the service-to-kext HEVC Main10 gate
//  (hw.vcnhevc10). No kernel headers, so tests/hevc10_gate_test.cpp runs it on
//  any Mac.
//
//  With -vcnhevc10 in boot-args, VCNEncodeFloor.kext validates each matching
//  AMDRadeonX6000_AMDGraphicsAccelerator instance and keeps its original and
//  Main10 IOGVAHEVCEncode / IOGVAHEVCEncodeCapabilities values, but does not
//  publish Main10 on the accelerator until the root user-space service
//  (vcnencodefix) writes 1 to hw.vcnhevc10 after confirming that the
//  AMDRadeonVADriver2 hevc10 patch is available and SIP allows task_for_pid.
//  Writing 0 (or unloading/stopping the kext) restores the original properties.
//
#pragma once
#include <stddef.h>
#include <stdint.h>

namespace vcnfloor {

constexpr size_t kMaxHevc10Accels = 4;

constexpr const char* kHevc10StateOff = "off";
constexpr const char* kHevc10StateWaitingAccel =
    "waiting for AMDRadeonX6000_AMDGraphicsAccelerator";
constexpr const char* kHevc10StateWaitingService =
    "waiting for vcnencodefix service";
constexpr const char* kHevc10StateServiceOff =
    "off: service says the driver patch is not active";

struct Hevc10Gate {
  struct Slot {
    char cls[64];
    bool applied;
  };

  struct WriteOutcome {
    bool changed;  // true when kept accelerators must be applied or restored
    bool apply;    // true = apply Main10, false = restore originals
  };

  bool bootEnabled;
  bool serviceWrote;
  int gateValue;
  size_t count;
  Slot slots[kMaxHevc10Accels];
  char lastSkipReason[128];

  void init(bool enabled) {
    *this = Hevc10Gate{};
    bootEnabled = enabled;
  }

  int value() const { return gateValue; }

  static void copyStr(char* dst, size_t dstLen, const char* src) {
    if (dstLen == 0) return;
    if (src == nullptr) src = "";
    size_t i = 0;
    for (; src[i] != '\0' && i + 1 < dstLen; i++) dst[i] = src[i];
    dst[i] = '\0';
  }

  static void copyTwo(char* dst, size_t dstLen, const char* a, const char* b) {
    if (dstLen == 0) return;
    if (a == nullptr) a = "";
    if (b == nullptr) b = "";
    size_t i = 0;
    for (size_t j = 0; a[j] != '\0' && i + 1 < dstLen; j++) dst[i++] = a[j];
    for (size_t j = 0; b[j] != '\0' && i + 1 < dstLen; j++) dst[i++] = b[j];
    dst[i] = '\0';
  }

  // Records a validated accelerator. Sets *slotOut to its index and
  // *shouldApplyOut to true when hw.vcnhevc10 is already 1 at match time.
  bool onMatch(const char* className, size_t* slotOut, bool* shouldApplyOut) {
    if (!bootEnabled || count >= kMaxHevc10Accels) return false;
    size_t idx = count++;
    copyStr(slots[idx].cls, sizeof(slots[idx].cls),
            className != nullptr ? className : "unknown");
    bool applyNow = (gateValue == 1);
    slots[idx].applied = applyNow;
    if (slotOut != nullptr) *slotOut = idx;
    if (shouldApplyOut != nullptr) *shouldApplyOut = applyNow;
    return true;
  }

  // Records why a candidate accelerator was skipped while none has matched yet.
  void onSkip(const char* reason) {
    if (count == 0)
      copyStr(lastSkipReason, sizeof(lastSkipReason),
              reason != nullptr ? reason : "unknown");
  }

  // Handles a root write to hw.vcnhevc10 (0 or 1; anything else sets *errOut
  // to EINVAL = 22). Writing the current value again is a no-op on accelerator
  // properties.
  WriteOutcome onWrite(int newValue, int* errOut) {
    if (newValue != 0 && newValue != 1) {
      if (errOut != nullptr) *errOut = 22;  // EINVAL
      return {false, false};
    }
    if (errOut != nullptr) *errOut = 0;
    if (!bootEnabled) return {false, false};
    serviceWrote = true;
    if (newValue == gateValue) return {false, gateValue == 1};
    gateValue = newValue;
    bool apply = (newValue == 1);
    bool anyChanged = false;
    for (size_t i = 0; i < count; i++) {
      if (slots[i].applied != apply) {
        slots[i].applied = apply;
        anyChanged = true;
      }
    }
    return {anyChanged, apply};
  }

  // Marks every kept accelerator for teardown on kext stop. Fills toRestore[i]
  // with whether slot i currently holds the Main10 properties and returns the
  // number of kept slots to release.
  size_t onStop(bool toRestore[kMaxHevc10Accels]) {
    size_t n = count;
    for (size_t i = 0; i < kMaxHevc10Accels; i++)
      toRestore[i] = (i < count) && slots[i].applied;
    init(false);
    return n;
  }

  // Formats the IOResources:VCNHEVC10 status string.
  void formatState(char* out, size_t outLen) const {
    if (!bootEnabled) {
      copyStr(out, outLen, kHevc10StateOff);
      return;
    }
    if (count > 0) {
      if (gateValue == 1) {
        copyTwo(out, outLen, "set on ", slots[count - 1].cls);
      } else if (serviceWrote) {
        copyStr(out, outLen, kHevc10StateServiceOff);
      } else {
        copyStr(out, outLen, kHevc10StateWaitingService);
      }
      return;
    }
    if (serviceWrote && gateValue == 0) {
      copyStr(out, outLen, kHevc10StateServiceOff);
    } else if (lastSkipReason[0] != '\0') {
      copyTwo(out, outLen, "not set: ", lastSkipReason);
    } else {
      copyStr(out, outLen, kHevc10StateWaitingAccel);
    }
  }
};

}  // namespace vcnfloor
