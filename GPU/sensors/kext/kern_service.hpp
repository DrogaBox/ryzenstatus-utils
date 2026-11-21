//
//  kern_service.hpp - the kext's IOService. It replaces Lilu's stock plug-in
//  service (LILU_CUSTOM_IOKIT_INIT) so that `ioreg -r -c DrogaBoxGPUSensors -l`
//  shows the readings: the properties are rebuilt each time they are read.
//
//  0.5.0: the service also opens connections (type 0) of
//  DrogaBoxGPUControlClient, the channel of the power limit write path
//  (control_logic.hpp, "channel"; gpucontrol is its command).
//
#ifndef GPUSENSORS_KERN_SERVICE_HPP
#define GPUSENSORS_KERN_SERVICE_HPP

#include <IOKit/IOService.h>
#include <IOKit/IOUserClient.h>

#include <Headers/kern_util.hpp>

class EXPORT DrogaBoxGPUSensors : public IOService {
  OSDeclareDefaultStructors(DrogaBoxGPUSensors);

 public:
  IOService* probe(IOService* provider, SInt32* score) override;
  bool start(IOService* provider) override;
  bool serializeProperties(OSSerialize* serialize) const override;
  using IOService::newUserClient;
  IOReturn newUserClient(task_t owningTask, void* securityID, UInt32 type,
                         OSDictionary* properties,
                         IOUserClient** handler) override;

 private:
  void publish();
};

// One program's connection. The change it makes belongs to it: closing it
// (quit, crash, logout) puts the start-up limit back. externalMethod runs on
// the program's thread, with no command gate.
class EXPORT DrogaBoxGPUControlClient : public IOUserClient {
  OSDeclareDefaultStructors(DrogaBoxGPUControlClient);

 public:
  using IOUserClient::initWithTask;
  bool initWithTask(task_t owningTask, void* securityToken, UInt32 type,
                    OSDictionary* properties) override;
  IOReturn clientClose() override;
  IOReturn clientDied() override;
  IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments* args,
                          IOExternalMethodDispatch* dispatch, OSObject* target,
                          void* reference) override;

 private:
  uint64_t id_{0};
  uint32_t closed_{0};  // atomic: closed once
};

#endif  // GPUSENSORS_KERN_SERVICE_HPP
