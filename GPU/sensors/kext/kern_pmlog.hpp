//
//  kern_pmlog.hpp - keeps a copy of the last PMLog the driver read. See
//  kern_pmlog.cpp.
//
#ifndef GPUSENSORS_KERN_PMLOG_HPP
#define GPUSENSORS_KERN_PMLOG_HPP

#include <stdint.h>

#include "pmlog_logic.hpp"

namespace PMLogCopy {

enum class Status : uint32_t {
  Waiting = 0,        // no HWLibs loaded yet (after boot: no Navi 21 driver)
  Active = 1,         // routed; a copy is kept each time the driver reads
  NoSymbol = 2,       // the function was not found in this HWLibs
  UnknownEntry = 3,   // it does not start as expected; nothing changed
  RouteFailed = 4,    // Lilu could not route it
  AlreadyRouted = 5,  // another kext routed it first; nothing changed
  RegistrationFailed = 6,  // Lilu did not take the callback
};

void init();
Status status();
const char* statusText();
const char* statusText(Status st);
const char* library();  // "AMDRadeonX6000HWLibs", or "" before one loads
// What became of PP_EnableAllPMLogSensors: "requested", "already set (...)",
// "off: -gpusensnoall", "not set: ..." or "not tried: ...".
const char* allSensors();

// Copies the last good log into `out` (kLogBytes). Returns false when there is
// none yet or when the kept one was invalidated. *ageNs is how long ago the
// driver read it, *samples how many good logs were seen since boot.
bool snapshot(uint8_t* out, uint64_t* ageNs, uint64_t* samples);

// Drops the kept copy without losing the sample count. The wake path calls it:
// a log read before the sleep is not a reading of the card that just woke, and
// the clock the age is taken from can pause while the Mac sleeps.
void invalidate();

}  // namespace PMLogCopy

#endif  // GPUSENSORS_KERN_PMLOG_HPP
