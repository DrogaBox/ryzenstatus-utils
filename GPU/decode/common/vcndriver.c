#include "vcndriver.h"

#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <stdio.h>
#include <string.h>

bool vcn_codec_is_amd(CFTypeRef codec) {
  return codec && CFGetTypeID(codec) == CFStringGetTypeID() &&
         CFStringHasPrefix((CFStringRef)codec, CFSTR("AMD"));
}

io_service_t vcn_find_accelerator(void) {
  io_iterator_t it;
  if (IOServiceGetMatchingServices(kIOMainPortDefault,
                                   IOServiceMatching("IOAccelerator"), &it))
    return 0;
  io_service_t s, found = 0;
  while ((s = IOIteratorNext(it))) {
    // Taking the first accelerator that has any codec is wrong on a machine
    // with active integrated graphics: Intel's accelerator can come first in
    // this list (the order is not the one ioreg prints), and AMD's driver then
    // refuses it (CreateAVDAccelerator returns 1).
    CFTypeRef codec =
        IORegistryEntryCreateCFProperty(s, CFSTR("IOGVACodec"), NULL, 0);
    bool amd = vcn_codec_is_amd(codec);
    if (codec) CFRelease(codec);
    if (amd) {
      found = s;
      break;
    }
    IOObjectRelease(s);
  }
  IOObjectRelease(it);
  return found;
}

bool vcn_driver_uuid(char out[33]) {
  for (uint32_t i = 0; i < _dyld_image_count(); i++) {
    const char* name = _dyld_get_image_name(i);
    if (!name || !strstr(name, "AMDRadeonVADriver2")) continue;
    const struct mach_header_64* h = (const void*)_dyld_get_image_header(i);
    if (!h || h->magic != MH_MAGIC_64) continue;
    const struct load_command* lc = (const void*)(h + 1);
    for (uint32_t k = 0; k < h->ncmds;
         k++, lc = (const void*)((const char*)lc + lc->cmdsize))
      if (lc->cmd == LC_UUID) {
        for (int j = 0; j < 16; j++)
          snprintf(out + 2 * j, 3, "%02X",
                   ((const struct uuid_command*)lc)->uuid[j]);
        return true;
      }
  }
  return false;
}

bool vcn_driver_load(VcnDriverLib* lib, char* err, size_t errLen) {
  *lib = (VcnDriverLib){.uuid = "unknown"};
  // Never closed: dlclose would only drop the count dlopen raised, and the
  // driver's code must stay while any session of this process uses it.
  void* h = dlopen(AVD_DRIVER_PATH, RTLD_NOW | RTLD_LOCAL);
  if (!h) {
    snprintf(err, errLen, "dlopen driver: %s", dlerror());
    return false;
  }
  vcn_driver_uuid(lib->uuid);
  lib->create =
      (AVD_CreateAVDAccelerator_fn)dlsym(h, "AVD_CreateAVDAccelerator");
  lib->destroy =
      (AVD_DestroyAVDAccelerator_fn)dlsym(h, "AVD_DestroyAVDAccelerator");
  if (!lib->create) {
    snprintf(err, errLen, "no AVD_CreateAVDAccelerator");
    return false;
  }
  return true;
}
