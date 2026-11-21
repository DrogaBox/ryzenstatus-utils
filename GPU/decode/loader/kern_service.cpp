//
//  kern_service.cpp - see kern_service.hpp.
//
#include "kern_service.hpp"

#include <Headers/kern_version.hpp>
#include <Headers/plugin_start.hpp>

#include "kern_amfi.hpp"

OSDefineMetaClassAndStructors(PRODUCT_NAME, IOService);

IOService* PRODUCT_NAME::probe(IOService* provider, SInt32* score) {
  auto service = IOService::probe(provider, score);
  return ADDPR(startSuccess) ? service : nullptr;
}

bool PRODUCT_NAME::start(IOService* provider) {
  if (!IOService::start(provider)) return false;
  setProperty("VersionInfo", kextVersion);
  publishState();
  registerService();
  return ADDPR(startSuccess);
}

// Runs in the reader's context (ioreg), never in the AMFI hook, so it may
// allocate.
void PRODUCT_NAME::publishState() {
  // read once, so Status and StatusCode always agree
  AmfiAllow::Status status = AmfiAllow::status();
  setProperty("Status", AmfiAllow::statusText(status));
  setProperty("StatusCode", static_cast<uint32_t>(status), 32);
  setProperty("AllowedBuilds", AmfiAllow::allowedCount(), 32);
  setProperty("Overrides", AmfiAllow::overrides(), 64);
}

bool PRODUCT_NAME::serializeProperties(OSSerialize* serialize) const {
  const_cast<PRODUCT_NAME*>(this)->publishState();
  return IOService::serializeProperties(serialize);
}
