//
//  kern_service.hpp - the kext's IOService. It replaces Lilu's stock plug-in
//  service (LILU_CUSTOM_IOKIT_INIT) so that `ioreg -r -c VCNVTLoader -l` shows
//  the current state: the properties are refreshed each time they are read.
//
#ifndef VCNVT_KERN_SERVICE_HPP
#define VCNVT_KERN_SERVICE_HPP

#include <IOKit/IOService.h>

#include <Headers/kern_util.hpp>

class EXPORT PRODUCT_NAME : public IOService {
  OSDeclareDefaultStructors(PRODUCT_NAME);

 public:
  IOService* probe(IOService* provider, SInt32* score) override;
  bool start(IOService* provider) override;
  bool serializeProperties(OSSerialize* serialize) const override;

 private:
  void publishState();
};

#endif  // VCNVT_KERN_SERVICE_HPP
