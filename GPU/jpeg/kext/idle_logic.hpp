//
//  idle_logic.hpp - when VCNJpeg gives the JPEG block's power back. No kernel
//  parts: kern_start.cpp drives it with the clock and a thread_call, and
//  tests/apps_test.cpp with a made-up clock.
//
//  The block is powered (PowerPlay client 21 + the queue started) only while
//  some client sends requests. Every request of a client is a touch; the block
//  goes off once kIdleMs pass without one. The timer is armed by the first
//  touch and, when it fires early because touches came meanwhile, armed again
//  for what is left: a stream of frames arms it once per kIdleMs, never per
//  frame, and never sees the block go off between two frames.
//
#pragma once
#include <stdint.h>

namespace jidle {

constexpr uint64_t kIdleMs = 2000;

struct Idle {
  bool on = false;     // the block is powered and its queue started
  bool armed = false;  // the timer is pending
  uint64_t last = 0;   // ms of the last touch
};

// A request of a client at `now`. Returns the delay in ms to arm the timer
// with, or 0 when it is armed already.
inline uint64_t touch(Idle& s, uint64_t now) {
  s.last = now;
  if (s.armed) return 0;
  s.armed = true;
  return kIdleMs;
}

enum class Tick { Nothing, PowerOff, Rearm };

// The timer fired at `now`. PowerOff: give the power back now. Rearm: arm the
// timer again with *delayMs.
inline Tick tick(Idle& s, uint64_t now, uint64_t* delayMs) {
  s.armed = false;
  if (!s.on) return Tick::Nothing;
  uint64_t idle = now >= s.last ? now - s.last : 0;
  if (idle >= kIdleMs) return Tick::PowerOff;
  *delayMs = kIdleMs - idle;
  s.armed = true;
  return Tick::Rearm;
}

}  // namespace jidle
