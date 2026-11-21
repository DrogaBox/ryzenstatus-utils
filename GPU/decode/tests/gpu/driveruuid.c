// driveruuid: prints the build identifier (LC_UUID) of the AMDRadeonVADriver2
// installed on this Mac. It is the value the decoders compare with their list
// of validated driver builds (kValidatedDrivers in vcnav1.c and vcnvp9.c).
//
// usage: driveruuid
//
// It loads the driver's code into this process to read its header. It creates
// no accelerator and no context, and sends nothing to the GPU.
//
// For a macOS build that is not installed, read the same value from its dyld
// shared cache with tools/driver/dscdiff.py info.
#include <dlfcn.h>
#include <stdio.h>

#include "avd.h"
#include "vcndriver.h"

int main(void) {
  if (!dlopen(AVD_DRIVER_PATH, RTLD_NOW | RTLD_LOCAL)) {
    fprintf(stderr, "dlopen failed: %s\n", dlerror());
    return 1;
  }
  char uuid[33];
  if (!vcn_driver_uuid(uuid)) {
    fprintf(stderr, "the driver is loaded but its image was not found\n");
    return 1;
  }
  printf("%s\n", uuid);
  return 0;
}
