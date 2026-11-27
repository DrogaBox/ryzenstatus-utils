//
//  kern_control.hpp - the GPU control part of GPUSensors. See kern_control.cpp.
//
#ifndef GPUSENSORS_KERN_CONTROL_HPP
#define GPUSENSORS_KERN_CONTROL_HPP

#include <stddef.h>
#include <stdint.h>

#include <Headers/kern_patcher.hpp>

class OSDictionary;

#include "control_logic.hpp"

namespace GPUControl {

// Reads the boot arguments and registers with Lilu. Called once at start.
void init();

// Called by kern_pmlog.cpp when one of the two libraries loaded and was
// identified (index = Lilu's load index for it, name = its name).
void onLibrary(KernelPatcher& patcher, size_t index, mach_vm_address_t address,
               size_t size, const char* name);

// How many sleeps started since boot (0.9.1). kern_pmlog.cpp's keeper asks
// only a power management object that the driver itself used in the current
// one: a pointer from before a wake may belong to a driver that started over.
uint64_t sleepCount();
// True from ppSleep's start to the end of ppWake.
bool inSleep();

// Whether something of the control is on the card and not confirmed stock: a
// fan curve, a clock or voltage change (an OD8 state), or a raised power limit.
// This is what the PMLog keeper runs for (0.9.1).
bool holdsAny();

// What the control did, for ioreg (rebuilt when read).
const char* statusText();
const char* profileText();  // the boot profile: asked, set, or why not
bool profileSetValue(uint32_t* value);  // true and the value once it was set
// The profile the driver's clients asked for (before PP_WorkLoadPolicyMask
// replaces it): the last one, every bit seen since boot, and how many times.
bool requests(uint32_t* last, uint32_t* seen, uint64_t* calls);
// The power watch (0.4.0): which functions are routed and what they saw.
struct PowerWatch {
  bool watchRead, watchSent, watchSleep, watchWake;
  bool haveBoot;       // the framebuffer read the limit at least once
  uint32_t bootW;      // its first answer: the limit the card booted with
  uint32_t lastReadW;  // its last answer (after the last wake)
  uint64_t reads;
  uint64_t sends;  // limits sent to the power firmware, by anyone
  uint32_t lastSentW, lastSentSource, lastSentResult;  // 0 = sent
  uint32_t sleeps, wakes;
};
const char* powerText();
bool power(PowerWatch* out);  // false when nothing is watched

// The power limit write path (0.5.0), for the user client in
// kern_service.cpp. Each runs on the program's own thread; only set waits
// (5 s at most) for the worker. Replies are control_logic.hpp's.
uint64_t openClient();  // a new connection's id (never 0 once started)
void status(uint64_t client, uint64_t out[gpuctl::kStatusCount]);
gpuctl::Reply arm(bool administrator);
// 0.8.0: closes writing again. Any program may (administrator only says who,
// for the log). StillApplied while anything is applied; then set and setOd8
// answer as before arm, and only arm (an administrator) opens it again.
gpuctl::Reply disarm(bool administrator);
// closedFlag is the connection's own "closed" word: closed() sets it under
// the state lock and set() reads it there, so no set lands after a close.
// watts is the wire's scalar as sent: Off and NotArmed come before it is
// looked at (gpuctl::setWire). flags: the 3-scalar form's (0.9.0,
// kSetWantRaise), 0 for the 2-scalar form.
gpuctl::Reply set(uint64_t client, uint64_t watts, uint64_t flags,
                  const uint32_t* closedFlag);
gpuctl::Reply alive(uint64_t client);
gpuctl::Reply release(uint64_t client);
// The connection closed or its program died. True the first time only.
bool closed(uint64_t client, uint32_t* closedFlag);
// For ioreg.
const char* writeText();
struct WriteState {
  gpuctl::WriteOff off;
  bool armed, owned;
  uint32_t heldW;  // the limit held now (the start-up one when nothing is)
  uint64_t changes, reverts;
  gpuctl::Reply lastReply;
};
bool writeState(WriteState* out);

// OD8 phase A (0.6.0): what the read-only escapes 0x9f and 0xa0 gave, for
// ioreg. The dictionary is retained (the caller releases it), or null before
// the first try.
const char* od8Text();
OSDictionary* od8Dictionary();

// OD8 writes (0.7.0, design-od8-b.md v3.1), for the user client. setOd8 waits
// like set(); *check is the Od8Check when the reply is Od8Refused. in is the
// wire's scalars as sent, version first, count of them (kOd8WireCount or the
// 0.9.0 and 0.7.0 forms kOd8WireCountV090 and kOd8WireCountV070;
// gpuctl::od8Wire).
gpuctl::Reply setOd8(uint64_t client, const uint64_t* in, uint32_t count,
                     const uint32_t* closedFlag, uint32_t* check);
const char* od8WriteText();
struct Od8WriteState {
  uint64_t held;  // kOd8Held*, 0 at stock
  bool dirty;     // not confirmed stock
  uint64_t changes, reverts, sentPower;
  gpuctl::Od8Check lastCheck;
  gpuctl::Od8Want want;  // the held state (zero when at stock)
};
bool od8WriteState(Od8WriteState* out);
// The card's power range (0.8.0, S-2), for ioreg: false while there is no
// control (off, before the library, no readable card).
bool powerRange(gpuctl::PowerRange* out);
const char* powerRangeText();

}  // namespace GPUControl

#endif  // GPUSENSORS_KERN_CONTROL_HPP
