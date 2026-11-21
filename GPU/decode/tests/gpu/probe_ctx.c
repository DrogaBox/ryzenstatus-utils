// probe_ctx: the first check on a new driver build. It opens Apple's AMD video
// driver the way the decoders do and asks it for one decode context, then
// deletes it. No picture is decoded and no decode command is sent, but the
// driver does open a session on the video block to create the context.
//
// It answers: does the driver still export its entry point, does it take AMD's
// accelerator, and does it still build an AV1 context with the structures in
// decode/common/avd.h.
//
// usage: probe_ctx [function_hex] [mode] [width] [height]
//   function_hex  1000000 = AV1 (default), 800 = HEVC, 8 = H.264
//   mode          4 by default: the first VCN instance, the one the decoders
//                 use. 3 and 5 select the second instance, which has no AV1 on
//                 Navi 21: AV1 there hangs the GPU, so AV1 is refused with any
//                 mode but 4.
//   width height  1920 1080 by default
//
// There is no switch to arm here: it talks to the driver as soon as it runs.
//
// Exit status: 0 = the context was created, 2 = the driver refused the
// context, 1 = anything before that failed.
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "avd.h"
#include "vcndriver.h"

// The decoders' VCN_MODE_VCN0: the driver mode that selects the first VCN
// instance.
#define AVD_MODE_VCN0 4

static int parse_u32_arg(const char* s, uint32_t lo, uint32_t hi,
                         uint32_t* out) {
  if (!s || !out) return -1;
  errno = 0;
  char* end = NULL;
  unsigned long v = strtoul(s, &end, 10);
  if (!end || end == s || *end || errno == ERANGE || v < lo || v > hi)
    return -1;
  *out = (uint32_t)v;
  return 0;
}

static int usage(void) {
  fprintf(stderr,
          "usage: probe_ctx [function_hex=1000000] [mode=4] [width=1920] "
          "[height=1080]\n"
          "It opens the AMD video driver as soon as it runs.\n");
  return 1;
}

int main(int argc, char** argv) {
  uint64_t func = AVD_FUNC_AV1;
  uint32_t mode = AVD_MODE_VCN0, w = 1920, h = 1080;
  if (argc > 5 || (argc > 1 && argv[1][0] == '-')) return usage();
  if (argc > 1) {
    errno = 0;
    char* end = NULL;
    unsigned long long v = strtoull(argv[1], &end, 16);
    if (!end || end == argv[1] || *end || errno == ERANGE) {
      fprintf(stderr, "invalid function hex\n");
      return 1;
    }
    func = (uint64_t)v;
  }
  if (argc > 2 && parse_u32_arg(argv[2], 0, 255, &mode)) {
    fprintf(stderr, "invalid mode\n");
    return 1;
  }
  if (func == AVD_FUNC_AV1 && mode != AVD_MODE_VCN0) {
    fprintf(stderr,
            "refused: AV1 only exists on the first VCN instance (mode %d). "
            "On the second one it hangs the GPU.\n",
            AVD_MODE_VCN0);
    return 1;
  }
  if (argc > 3 && parse_u32_arg(argv[3], 1, 8192, &w)) {
    fprintf(stderr, "invalid width\n");
    return 1;
  }
  if (argc > 4 && parse_u32_arg(argv[4], 1, 8192, &h)) {
    fprintf(stderr, "invalid height\n");
    return 1;
  }

  void* lib = dlopen(AVD_DRIVER_PATH, RTLD_NOW | RTLD_LOCAL);
  if (!lib) {
    printf("dlopen: %s\n", dlerror());
    return 1;
  }
  char uuid[33] = "unknown";
  vcn_driver_uuid(uuid);
  printf("driver build %s\n", uuid);
  AVD_CreateAVDAccelerator_fn create =
      (AVD_CreateAVDAccelerator_fn)dlsym(lib, "AVD_CreateAVDAccelerator");
  printf("AVD_CreateAVDAccelerator=%p\n", (void*)create);
  if (!create) return 1;

  // The same choice the decoders make: AMD's accelerator only.
  io_service_t svc = vcn_find_accelerator();
  if (!svc) {
    fprintf(stderr, "no AMD accelerator\n");
    return 1;
  }
  uint64_t regid = 0;
  IORegistryEntryGetRegistryEntryID(svc, &regid);
  printf("accelerator service=0x%x regid=0x%llx\n", svc, regid);

  uint32_t services[8] = {svc};
  AVD_AcceleratorCreate ac = {
      .index = 0, .services = services, .validMask = 0xffffffff};
  uint8_t info[256] = {0};
  AVD_Accelerator* accel = NULL;
  int r = create(&accel, &ac, info);
  printf("CreateAVDAccelerator -> %d accel=%p name='%.16s'\n", r, (void*)accel,
         (char*)info + 0x1c);
  if (r || !accel) return 1;

  void* drv = NULL;
  AVD_DriverCreate dc = {.initFlags = 0, .accel = accel};
  r = ((AVD_CreateDriver_fn)accel->fn[AVD_FN_CreateDriver])(&drv, &dc);
  printf("CreateDriver -> %d driver=%p\n", r, drv);
  if (r) return 1;

  void* bsAddr[4] = {0};
  AVD_BitstreamPool pool = {.type = 0,
                            .size = 0x1800000,
                            .format = 0x72617762,
                            .one = 1,
                            .count = 1,
                            .addressesOut = bsAddr,
                            .eight = 8,
                            .five = 5};
  r = ((AVD_AllocateBitstreamBufferPool_fn)
           accel->fn[AVD_FN_AllocateBitstreamBufferPool])(drv, &pool);
  printf("AllocateBitstreamBufferPool -> %d buffer=%p\n", r, bsAddr[0]);

  AVD_ContextList list = {0};
  void* ctxOut[4] = {0};
  AVD_FunctionInfo* fis[1] = {&list.inlineInfo};
  list.count = 1;
  list.functions = fis;
  list.contextsOut = ctxOut;
  list.inlineInfo = (AVD_FunctionInfo){.kind = 1,
                                       .function = func,
                                       .mode = mode,
                                       .pixelRate = w * h * 30,
                                       .width = w,
                                       .height = h,
                                       .inFormat = 0x72617762,
                                       .inFormatCount = 1,
                                       .outFormat = 0x4e563132,
                                       .outFormatCount = 1};
  AVD_DriverContextInit ci = {.list = &list};
  r = ((AVD_CreateContexts_fn)accel->fn[AVD_FN_CreateContexts])(drv, &ci);
  printf("CreateContexts(func=0x%llx mode=%u %ux%u) -> %d context=%p caps=%p\n",
         func, mode, w, h, r, ctxOut[0], ci.capsOut);
  if (!r && ctxOut[0]) {
    AVD_DriverContextDelete del = {.count = 1, .contexts = ctxOut};
    printf(
        "DeleteContexts -> %d\n",
        ((AVD_DeleteContexts_fn)accel->fn[AVD_FN_DeleteContexts])(drv, &del));
  }
  ((AVD_FreeBitstreamBufferPool_fn)accel->fn[AVD_FN_FreeBitstreamBufferPool])(
      drv, 0);
  ((AVD_DeleteDriver_fn)accel->fn[AVD_FN_DeleteDriver])(drv);
  IOObjectRelease(svc);
  return r || !ctxOut[0] ? 2 : 0;
}
