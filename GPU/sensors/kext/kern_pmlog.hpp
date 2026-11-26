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

// The keeper (0.9.1): while something is held on the card, GPUSensors asks the
// library for a sample itself once a second, so the watchdog and the readers
// have a fresh copy with nothing outside polling. The rate and the decision to
// run live in pmlog_logic.hpp (keeperStep); kern_control.cpp's worker calls
// these, on its own thread, with none of its locks held: the library takes
// PowerPlay's, and it may wait for the power firmware.

// True when there is a power management object to ask: the PMLog function is
// routed and the driver has read the statistics at least once since the last
// sleep (a pointer from before a wake may belong to a driver that started
// over).
bool canSample();

// One sample: the same call the driver makes, kept only when it succeeded and
// the library filled the log. False when it could not be asked, when the
// library refused (the GPU's IP block off, hardware access blocked in a sleep)
// or when the answer was not a log (an old reading is never kept as a new one).
bool sampleNow();

// What the keeper did since boot, for ioreg.
void keeperCounts(uint64_t* tries, uint64_t* samples, uint64_t* refused,
                  uint32_t* lastResult);
// What the keeper is doing, in words: "off: nothing held", "on: ..." or why
// it cannot sample. `held` is GPUControl::holdsAny().
const char* keeperText(bool held);

}  // namespace PMLogCopy

#endif  // GPUSENSORS_KERN_PMLOG_HPP
