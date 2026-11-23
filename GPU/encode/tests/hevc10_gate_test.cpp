// hevc10_gate_test.cpp - host-only tests for the kext's HEVC Main10 sysctl gate
// state machine (kext/hevc10_gate.hpp):
//   - boot-arg off vs on initial states;
//   - match before write: properties withheld ("waiting for vcnencodefix
//     service"), then applied on write(1), restored on write(0), re-applied on
//     write(1);
//   - duplicate writes (1->1, 0->0) and invalid values (EINVAL);
//   - write(1) before match: value remembered and applied immediately when the
//     accelerator matches;
//   - second accelerator matching after write(1);
//   - kext stop: restores only currently applied accelerators, releases all
//     kept slots, and resets state to "off".
#include <stdio.h>
#include <string.h>

#include "../kext/hevc10_gate.hpp"

using namespace vcnfloor;

static int fails = 0;
static void check(bool ok, const char* what) {
  if (!ok) {
    printf("FAIL: %s\n", what);
    fails++;
  }
}

static bool stateIs(const Hevc10Gate& g, const char* want) {
  char buf[160];
  g.formatState(buf, sizeof(buf));
  return strcmp(buf, want) == 0;
}

int main() {
  constexpr const char* kAccel = "AMDRadeonX6000_AMDGraphicsAccelerator";

  // 1. Boot-arg off
  {
    Hevc10Gate g;
    g.init(false);
    check(g.value() == 0 && stateIs(g, "off"), "boot-arg off starts at off");
    size_t slot = 99;
    bool apply = true;
    check(!g.onMatch(kAccel, &slot, &apply),
          "boot-arg off ignores accelerator match");
  }

  // 2. Match before write, then write 1 -> 1 -> 0 -> 0 -> 1, then stop
  {
    Hevc10Gate g;
    g.init(true);
    check(stateIs(g, "waiting for AMDRadeonX6000_AMDGraphicsAccelerator"),
          "boot-arg on starts waiting for accelerator");

    g.onSkip("unsupported GPU");
    check(stateIs(g, "not set: unsupported GPU"),
          "skip before any valid match reports reason");

    size_t slot = 99;
    bool apply = true;
    check(g.onMatch(kAccel, &slot, &apply) && slot == 0 && !apply,
          "match before write keeps accelerator without applying Main10");
    check(stateIs(g, "waiting for vcnencodefix service"),
          "match before write waits for vcnencodefix service");

    int err = -1;
    auto w1 = g.onWrite(1, &err);
    check(err == 0 && w1.changed && w1.apply && g.value() == 1 &&
              g.slots[0].applied,
          "first write(1) applies Main10 to kept accelerator");
    check(stateIs(g, "set on AMDRadeonX6000_AMDGraphicsAccelerator"),
          "write(1) publishes set on class");

    auto w1Dup = g.onWrite(1, &err);
    check(err == 0 && !w1Dup.changed && w1Dup.apply && g.value() == 1,
          "writing 1 twice is a no-op");

    auto wBad = g.onWrite(2, &err);
    check(err == 22 && !wBad.changed && g.value() == 1,
          "writing a non-0/1 value returns EINVAL and leaves state unchanged");

    auto w0 = g.onWrite(0, &err);
    check(err == 0 && w0.changed && !w0.apply && g.value() == 0 &&
              !g.slots[0].applied,
          "write(0) restores original properties");
    check(stateIs(g, "off: service says the driver patch is not active"),
          "write(0) publishes service-off reason");

    auto w0Dup = g.onWrite(0, &err);
    check(err == 0 && !w0Dup.changed && !w0Dup.apply && g.value() == 0,
          "writing 0 twice is a no-op");

    auto w1Again = g.onWrite(1, &err);
    check(err == 0 && w1Again.changed && w1Again.apply && g.value() == 1 &&
              g.slots[0].applied,
          "write(1) after write(0) re-applies Main10");

    // Second accelerator appearing after write(1)
    size_t slot2 = 99;
    bool apply2 = false;
    check(g.onMatch(kAccel, &slot2, &apply2) && slot2 == 1 && apply2,
          "accelerator appearing after write(1) gets Main10 immediately");

    // Kext stop while applied
    bool toRestore[kMaxHevc10Accels]{};
    size_t n = g.onStop(toRestore);
    check(n == 2 && toRestore[0] && toRestore[1] && !toRestore[2] &&
              g.value() == 0 && stateIs(g, "off"),
          "onStop marks both applied accelerators for restore and resets to off");
  }

  // 3. Write before any accelerator is matched (remember value and apply on match)
  {
    Hevc10Gate g;
    g.init(true);
    int err = -1;
    auto w1 = g.onWrite(1, &err);
    check(err == 0 && !w1.changed && w1.apply && g.value() == 1,
          "write(1) before match remembers gateValue=1 without changing slots");
    check(stateIs(g, "waiting for AMDRadeonX6000_AMDGraphicsAccelerator"),
          "write(1) before match still waits for accelerator");

    size_t slot = 99;
    bool apply = false;
    check(g.onMatch(kAccel, &slot, &apply) && slot == 0 && apply &&
              g.slots[0].applied,
          "subsequent match sees remembered gateValue=1 and applies at once");
    check(stateIs(g, "set on AMDRadeonX6000_AMDGraphicsAccelerator"),
          "subsequent match publishes set on class");

    // Write 0 then stop: onStop must not restore an already-restored slot
    (void)g.onWrite(0, &err);
    bool toRestore[kMaxHevc10Accels]{true, true, true, true};
    size_t n = g.onStop(toRestore);
    check(n == 1 && !toRestore[0],
          "onStop after write(0) releases slot without restoring twice");
  }

  // 4. Write(0) before match, then match
  {
    Hevc10Gate g;
    g.init(true);
    int err = -1;
    auto w0 = g.onWrite(0, &err);
    check(err == 0 && !w0.changed && !w0.apply && g.value() == 0,
          "initial write(0) before match succeeds as no-op");
    check(stateIs(g, "off: service says the driver patch is not active"),
          "initial write(0) publishes service-off reason");
    size_t slot = 99;
    bool apply = true;
    check(g.onMatch(kAccel, &slot, &apply) && slot == 0 && !apply,
          "match after write(0) does not apply Main10");
    check(stateIs(g, "off: service says the driver patch is not active"),
          "state remains service-off after match when service wrote 0");
  }

  printf("hevc10_gate_test: %d failures\n", fails);
  return fails != 0;
}
