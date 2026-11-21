// rawpatch: turns an image patch of a macOS update into the full disk image,
// so the driver of a macOS build can be checked before that build is
// installed. It calls macOS's own RawImagePatch (libParallelCompression) with
// no source image.
//
// usage: rawpatch <patch> <out.dmg>
//   <patch>  a RIDIFF10 file from the update, for example
//            payloadv2/image_patches/cryptex-system-x86_64
//
// Mount the result read-only and hand its dyld shared cache
// (System/Library/dyld/dyld_shared_cache_x86_64h) to tools/driver/dscdiff.py.
// The image is Apple's: keep it out of this repository.
//
// decode/tests/gpu/build.sh builds it into decode/build/gpu/rawpatch.
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

// The argument of RawImagePatch. Only the fields set below are known.
typedef struct {
  const char* input;   // +0x00 source image (NULL: patch from nothing)
  const void* unk08;   // +0x08
  const char* unk10;   // +0x10 defaults to +0x18
  const char* output;  // +0x18
  const char* patch;   // +0x20
  int verbose;         // +0x28
  int threads;         // +0x2c 0 = default
  char pad[64];
} RawImagePatchArgs;

int main(int argc, char** argv) {
  if (argc != 3 || argv[1][0] == '-') {
    fprintf(stderr, "usage: rawpatch <patch> <out.dmg>\n");
    return 1;
  }
  void* h = dlopen("/usr/lib/libParallelCompression.dylib", RTLD_NOW);
  int (*fn)(RawImagePatchArgs*) = h ? dlsym(h, "RawImagePatch") : NULL;
  if (!fn) {
    fprintf(stderr, "RawImagePatch not found: %s\n", dlerror());
    return 1;
  }
  RawImagePatchArgs a;
  memset(&a, 0, sizeof(a));
  a.patch = argv[1];
  a.output = argv[2];
  a.verbose = 3;
  int r = fn(&a);
  printf("RawImagePatch -> %d\n", r);
  return r != 0;
}
