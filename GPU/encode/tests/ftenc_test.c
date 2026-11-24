// ftenc_test.c - checks the cc patch's site E (FaceTime's encoder) on this
// Mac's own VideoProcessing, in this process only. Needs a Mac whose board-id
// is one Apple lists (iMacPro1,1 Mac-7BA5B2D9E42DDD94 or MacPro7,1
// Mac-27AD2F918AE68F61) and a hardware H.264 encoder; built by build.sh, not
// run there (it uses the GPU). Run it by hand:
//   build/obj/ftenc_test
// It asks VideoProcessing what FaceTime asks (usage 42): which codecs it
// supports (VCPCodecGetProperties 2) and for an H.264 session with hardware
// required (VCPCompressionSessionCreate, then 30 frames). Then it writes site
// E the way vcnencodefix does (found by cc_locate, bytes from build_cc) and
// asks again. Expected on such a board-id without a T2: before, VCPCodec_AVC1
// 0 and the session fails with -18 (the T2 path, "No bridgeOS device
// available"); after, VCPCodec_AVC1 1 and the session encodes.
#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <VideoToolbox/VideoToolbox.h>
#include <dlfcn.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <uuid/uuid.h>

#include "../tool/patches.h"

typedef int (*GetProps)(int, CFDictionaryRef*, int);
typedef int (*Create)(CFAllocatorRef, unsigned, unsigned, int, CFDictionaryRef,
                      CFDictionaryRef, CFAllocatorRef, void*, void*, void**);
typedef int (*Encode)(void*, CVPixelBufferRef, CMTime, CMTime, CFDictionaryRef,
                      void*, VTEncodeInfoFlags*);
typedef int (*Complete)(void*, CMTime);
typedef void (*Invalidate)(void*);

static int gFrames, gStatus;
static FourCharCode gCodec;
static void out(void* refcon, void* frame, OSStatus st, VTEncodeInfoFlags f,
                CMSampleBufferRef sb) {
  (void)refcon, (void)frame, (void)f;
  gStatus = st;
  if (!sb) return;
  if (!gFrames++)
    gCodec = CMFormatDescriptionGetMediaSubType(
        CMSampleBufferGetFormatDescription(sb));
}

static int number(CFDictionaryRef d, CFStringRef k) {
  int v = -1;
  CFNumberRef n = d ? CFDictionaryGetValue(d, k) : NULL;
  if (n) CFNumberGetValue(n, kCFNumberIntType, &v);
  return v;
}

// Returns the AVC1 answer; *created = the session status, *frames = frames out.
static int ask(void* h, const char* tag, int* created, int* frames) {
  GetProps props = (GetProps)dlsym(h, "VCPCodecGetProperties");
  Create create = (Create)dlsym(h, "VCPCompressionSessionCreate");
  Encode encode = (Encode)dlsym(h, "VCPCompressionSessionEncodeFrame");
  Complete complete = (Complete)dlsym(h, "VCPCompressionSessionCompleteFrames");
  Invalidate inval = (Invalidate)dlsym(h, "VCPCompressionSessionInvalidate");
  CFStringRef* usageKey =
      (CFStringRef*)dlsym(RTLD_DEFAULT, "kVTCompressionPropertyKey_Usage");
  if (!props || !create || !encode || !complete || !usageKey) {
    printf("FAIL VideoProcessing or VideoToolbox lacks a symbol\n");
    return -2;
  }
  CFDictionaryRef d = NULL;
  int r = props(2, &d, 42);
  int avc = number(d, CFSTR("VCPCodec_AVC1")),
      lrp = number(d, CFSTR("VCPCodec_LRP"));
  if (d) CFRelease(d);
  CFMutableDictionaryRef spec =
      CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                &kCFTypeDictionaryValueCallBacks);
  CFDictionarySetValue(
      spec, kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder,
      kCFBooleanTrue);
  int u = 42;
  CFNumberRef n = CFNumberCreate(NULL, kCFNumberIntType, &u);
  CFDictionarySetValue(spec, *usageKey, n);
  void* s = NULL;
  gFrames = 0;
  gStatus = 0;
  gCodec = 0;
  *created =
      create(NULL, 1280, 720, 'avc1', spec, NULL, NULL, (void*)out, NULL, &s);
  CFRelease(spec);
  CFRelease(n);
  if (s) {
    for (int i = 0; i < 30; i++) {
      CVPixelBufferRef pb = NULL;
      if (CVPixelBufferCreate(NULL, 1280, 720,
                              kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                              NULL, &pb) != kCVReturnSuccess)
        break;
      CVPixelBufferLockBaseAddress(pb, 0);
      memset(CVPixelBufferGetBaseAddressOfPlane(pb, 0), (i * 8) & 255,
             CVPixelBufferGetBytesPerRowOfPlane(pb, 0) * 720);
      memset(CVPixelBufferGetBaseAddressOfPlane(pb, 1), 128,
             CVPixelBufferGetBytesPerRowOfPlane(pb, 1) * 360);
      CVPixelBufferUnlockBaseAddress(pb, 0);
      encode(s, pb, CMTimeMake(i, 30), CMTimeMake(1, 30), NULL, NULL, NULL);
      CVPixelBufferRelease(pb);
    }
    complete(s, kCMTimeInvalid);
    if (inval) inval(s);
  }
  *frames = gFrames;
  uint32_t c = CFSwapInt32HostToBig(gCodec);
  printf(
      "%s: VCPCodecGetProperties(2, usage 42) = %d, AVC1 %d, LRP %d; H.264 "
      "session (usage 42, hardware required) = %d, %d frames out%s%.4s, last "
      "status %d\n",
      tag, r, avc, lrp, *created, *frames, gFrames ? ", codec " : "",
      gFrames ? (char*)&c : "", gStatus);
  return avc;
}

int main(void) {
  setvbuf(stdout, NULL, _IOLBF, 0);
  void* h = dlopen(kCcImage, RTLD_NOW);
  Dl_info info;
  void* any = h ? dlsym(h, "VCPCodecGetProperties") : NULL;
  if (!any || !dladdr(any, &info)) {
    printf("FAIL VideoProcessing not loadable\n");
    return 1;
  }
  // __text and the build of the loaded image (unslid addresses + slide)
  const struct mach_header_64* mh = info.dli_fbase;
  const uint8_t* p = (const uint8_t*)(mh + 1);
  const struct section_64* text = NULL;
  const uint8_t* uuid = NULL;
  uint64_t slide = 0;
  for (uint32_t i = 0; i < mh->ncmds; i++) {
    const struct load_command* c = (const void*)p;
    if (c->cmd == LC_SEGMENT_64) {
      const struct segment_command_64* seg = (const void*)c;
      if (!strcmp(seg->segname, "__TEXT")) {
        slide = (uint64_t)mh - seg->vmaddr;
        const struct section_64* sec = (const void*)(seg + 1);
        for (uint32_t j = 0; j < seg->nsects; j++)
          if (!strcmp(sec[j].sectname, "__text")) text = &sec[j];
      }
    } else if (c->cmd == LC_UUID)
      uuid = ((const struct uuid_command*)c)->uuid;
    p += c->cmdsize;
  }
  char u[40] = "";
  if (uuid) uuid_unparse_upper(uuid, u);
  const CcBuild* b = text && uuid ? cc_build(u) : NULL;
  if (!b) {
    printf("FAIL VideoProcessing %s is not a validated build\n", u);
    return 1;
  }
  uint64_t sites[kCcSites];
  char why[160];
  if (!cc_locate(b, (const uint8_t*)(text->addr + slide), text->size,
                 text->addr + slide, sites, why, sizeof(why))) {
    printf("FAIL %s: %s\n", b->macos, why);
    return 1;
  }
  printf("VideoProcessing %s, site E at 0x%llx\n", b->macos, sites[3]);
  int before, beforeFrames, after, afterFrames;
  int avcBefore = ask(h, "original", &before, &beforeFrames);
  const CcSite* e = &b->site[3];
  uint8_t w[kCcMaxWrite];
  build_cc(e, w);
  vm_address_t at = (vm_address_t)(sites[3] + e->off),
               page = at & ~(vm_address_t)(vm_page_size - 1);
  vm_size_t span = at + e->n - page;
  kern_return_t kr = vm_protect(mach_task_self(), page, span, FALSE,
                                VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
  if (kr == KERN_SUCCESS) {
    memcpy((void*)at, w, e->n);
    kr = vm_protect(mach_task_self(), page, span, FALSE,
                    VM_PROT_READ | VM_PROT_EXECUTE);
  }
  if (kr != KERN_SUCCESS) {
    printf("FAIL cannot write site E in this process (%s)\n",
           mach_error_string(kr));
    return 1;
  }
  int avcAfter = ask(h, "patched", &after, &afterFrames);
  bool fixed = avcAfter == 1 && after == 0 && afterFrames > 0;
  if (avcBefore == 1 && before == 0)
    printf(
        "this board-id is not one Apple sends to the T2: nothing to fix here, "
        "%s after the patch\n",
        fixed ? "still fine" : "BROKEN");
  else
    printf("%s\n", fixed ? "site E: fixed (H.264 offered and encoding locally)"
                         : "FAIL site E did not fix the session");
  return fixed ? 0 : 1;
}
