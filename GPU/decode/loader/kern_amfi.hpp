//
//  kern_amfi.hpp - the library validation exception for the two decoder
//  plug-ins. See kern_amfi.cpp.
//
#ifndef VCNVT_KERN_AMFI_HPP
#define VCNVT_KERN_AMFI_HPP

#include <stdint.h>

namespace AmfiAllow {

enum class Status : uint32_t {
  Waiting = 0,        // AMFI not seen yet (after boot: the kext did nothing)
  Active = 1,         // the exception is in place
  NoSymbol = 2,       // a function was not found in this AMFI
  UnknownEntry = 3,   // a function does not start as expected; nothing changed
  RouteFailed = 4,    // Lilu could not route the function
  AlreadyRouted = 5,  // another kext routed the function first; nothing changed
  RegistrationFailed = 6,  // Lilu did not take the callback
};

void init();
Status status();
const char* statusText(Status status);
uint64_t allowedCount();  // plug-in builds in the list
uint64_t overrides();     // times a listed plug-in was let through

}  // namespace AmfiAllow

#endif  // VCNVT_KERN_AMFI_HPP
