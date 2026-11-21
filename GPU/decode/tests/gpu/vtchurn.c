// vtchurn: creates and closes many decoder sessions in one process, the way a
// browser does over a day, and counts what the process holds of the system
// before, during and after: its Mach port names and its IOKit user-client
// connections (the IOUserClientCreator entries ioreg lists for this pid).
//
//   vtchurn -load bundle av1|vp9 clip.ivf [-n sessions] [-frames k]
//           [-id decoder]
//
// Each session is a VTDecompressionSession that requires hardware: it decodes
// the first k frames of the clip (default 3), waits for them, then is
// invalidated and released. -load registers the bundle in this process only;
// nothing is installed. The bundle is registered under its own ID
// (com.droga.vtchurn.av1 or .vp9), and without -id every session asks for that
// decoder, so VideoToolbox cannot pick an installed plug-in instead. At the end
// it lists the decoder plug-in images loaded in the process.
//
// A session that leaks something the system counts shows as a growth per
// session after the first one. Lines:
//   at <when>: ports <n> user clients <n>
//   growth per session after the first: ports <x> user clients <y>
//
// THIS SENDS COMMANDS TO THE GPU (every session decodes). See README.md: it
// can hang the GPU like every decode test.
//
// Exit status: 0 = every session started and decoded its frames, 2 = a
// session or a frame failed, 1 = anything else.
#include <CoreMedia/CoreMedia.h>
#include <VideoToolbox/VideoToolbox.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void copy_kv(const void* k, const void* v, void* dict) {
  CFDictionarySetValue(dict, k, v);
}

// The DecoderID VideoToolbox lists for a decoder registered with implID, or
// NULL. It makes it from the CMClassImplementationID and the codec ("<id>.av01"
// on Tahoe 26.7.3); a DecoderID in the registration is not used.
static CFStringRef copy_decoder_id(CFStringRef implID, CMVideoCodecType codec) {
  OSStatus (*copyList)(CFDictionaryRef, CFArrayRef*) =
      dlsym(RTLD_DEFAULT, "VTCopyVideoDecoderList");
  CFArrayRef decs = NULL;
  if (!copyList || copyList(NULL, &decs) || !decs) return NULL;
  CFStringRef prefix =
      CFStringCreateWithFormat(NULL, NULL, CFSTR("%@."), implID);
  CFStringRef found = NULL;
  for (CFIndex i = 0; prefix && !found && i < CFArrayGetCount(decs); i++) {
    CFDictionaryRef d = CFArrayGetValueAtIndex(decs, i);
    CFStringRef id = CFDictionaryGetValue(d, CFSTR("DecoderID"));
    CFNumberRef type = CFDictionaryGetValue(d, CFSTR("CodecType"));
    SInt64 t = 0;
    if (id && CFGetTypeID(id) == CFStringGetTypeID() && type &&
        CFGetTypeID(type) == CFNumberGetTypeID() &&
        CFNumberGetValue(type, kCFNumberSInt64Type, &t) && t == codec &&
        (CFEqual(id, implID) || CFStringHasPrefix(id, prefix)))
      found = CFRetain(id);
  }
  if (prefix) CFRelease(prefix);
  CFRelease(decs);
  return found;
}

// As vtav1test's: registers the bundle's decoders in this process only, but
// under implID, which no installed plug-in has.
static int load_bundle(const char* path, CMVideoCodecType codec,
                       CFStringRef implID) {
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(
      NULL, (const UInt8*)path, (CFIndex)strlen(path), true);
  CFBundleRef b = url ? CFBundleCreate(NULL, url) : NULL;
  if (url) CFRelease(url);
  if (!b || !CFBundleLoadExecutable(b)) {
    fprintf(stderr, "cannot load %s\n", path);
    return -1;
  }
  CFArrayRef impls =
      CFBundleGetValueForInfoDictionaryKey(b, CFSTR("CMClassImplementations"));
  OSStatus (*reg)(FourCharCode, CFDictionaryRef, void*) =
      dlsym(RTLD_DEFAULT, "VTRegisterVideoDecoderWithInfo");
  int registered = 0;
  for (CFIndex i = 0; impls && reg && i < CFArrayGetCount(impls); i++) {
    CFDictionaryRef impl = CFArrayGetValueAtIndex(impls, i);
    CFStringRef fn = CFDictionaryGetValue(impl, CFSTR("CMFactoryFunction"));
    void* factory = fn ? CFBundleGetFunctionPointerForName(b, fn) : NULL;
    if (!factory) continue;
    CFMutableDictionaryRef info = CFDictionaryCreateMutableCopy(NULL, 0, impl);
    CFDictionaryRef match = CFDictionaryGetValue(impl, CFSTR("CMMatchingInfo"));
    if (match) CFDictionaryApplyFunction(match, copy_kv, info);
    CFDictionarySetValue(info, CFSTR("IsHardwareAccelerated"), kCFBooleanTrue);
    CFStringRef name =
        CFDictionaryGetValue(impl, CFSTR("CMClassImplementationName"));
    if (name) CFDictionarySetValue(info, CFSTR("CodecName"), name);
    CFDictionarySetValue(info, CFSTR("CMClassImplementationID"), implID);
    OSStatus st = reg(codec, info, factory);
    CFRelease(info);
    printf("registered %p from %s -> %d\n", factory, path, (int)st);
    if (!st) registered++;
  }
  if (!registered) {
    fprintf(stderr, "no decoder of %s could be registered\n", path);
    return -1;
  }
  return 0;
}

static unsigned port_names(void) {
  mach_port_name_array_t names = NULL;
  mach_msg_type_number_t n = 0, nt = 0;
  mach_port_type_array_t types = NULL;
  if (mach_port_names(mach_task_self(), &names, &n, &types, &nt) !=
      KERN_SUCCESS)
    return 0;
  vm_deallocate(mach_task_self(), (vm_address_t)names, n * sizeof(*names));
  vm_deallocate(mach_task_self(), (vm_address_t)types, nt * sizeof(*types));
  return n;
}

// Counts the registry's user clients created by this process. -1 when ioreg
// could not be run.
static int user_clients(void) {
  char want[64];
  snprintf(want, sizeof(want), "\"IOUserClientCreator\" = \"pid %d,",
           (int)getpid());
  FILE* p = popen("/usr/sbin/ioreg -l -w0", "r");
  if (!p) return -1;
  char line[4096];
  int n = 0;
  while (fgets(line, sizeof(line), p))
    if (strstr(line, want)) n++;
  return pclose(p) == 0 ? n : -1;
}

static unsigned ports0, ports1;
static int uc0, uc1;
static void measure(const char* when, int session, unsigned* ports, int* uc) {
  unsigned pn = port_names();
  int u = user_clients();
  printf("at %s (%d sessions): ports %u user clients %d\n", when, session, pn,
         u);
  fflush(stdout);
  if (ports) *ports = pn;
  if (uc) *uc = u;
}

typedef struct {
  int frames, errors;
} Ctx;
static void out_cb(void* refcon, void* frameRefcon, OSStatus st,
                   VTDecodeInfoFlags flags, CVImageBufferRef img, CMTime pts,
                   CMTime dur) {
  (void)frameRefcon, (void)pts, (void)dur;
  Ctx* c = refcon;
  if (st) {
    c->errors++;
    printf("frame error %d flags %x\n", (int)st, flags);
  } else if (img) {
    c->frames++;
  }
}

static int usage(void) {
  fprintf(stderr,
          "usage: vtchurn -load bundle av1|vp9 clip.ivf [-n sessions] "
          "[-frames k] [-id decoder]\n"
          "Every session decodes on the GPU.\n");
  return 1;
}

int main(int argc, char** argv) {
  if (argc < 5 || strcmp(argv[1], "-load")) return usage();
  const char *bundle = argv[2], *codecName = argv[3], *clip = argv[4],
             *decoderID = NULL;
  CMVideoCodecType codec;
  if (!strcmp(codecName, "av1"))
    codec = kCMVideoCodecType_AV1;
  else if (!strcmp(codecName, "vp9"))
    codec = kCMVideoCodecType_VP9;
  else
    return usage();
  long sessions = 200, k = 3;
  for (int i = 5; i < argc; i++) {
    char* end = NULL;
    if (!strcmp(argv[i], "-n") && i + 1 < argc) {
      sessions = strtol(argv[++i], &end, 10);
      if (!end || *end || sessions < 2 || sessions > 100000) return usage();
    } else if (!strcmp(argv[i], "-frames") && i + 1 < argc) {
      k = strtol(argv[++i], &end, 10);
      if (!end || *end || k < 0 || k > 1000) return usage();
    } else if (!strcmp(argv[i], "-id") && i + 1 < argc) {
      decoderID = argv[++i];
    } else {
      return usage();
    }
  }

  // The clip's first k frames.
  FILE* fp = fopen(clip, "rb");
  uint8_t hdr[32];
  if (!fp || fread(hdr, 1, 32, fp) != 32 || memcmp(hdr, "DKIF", 4)) {
    fprintf(stderr, "%s: not an IVF file\n", clip);
    return 1;
  }
  int w = hdr[12] | hdr[13] << 8, h = hdr[14] | hdr[15] << 8;
  uint8_t** data = calloc((size_t)k + 1, sizeof(*data));
  size_t* sizes = calloc((size_t)k + 1, sizeof(*sizes));
  long have = 0;
  uint8_t fh[12];
  while (data && sizes && have < k && fread(fh, 1, 12, fp) == 12) {
    uint32_t sz = fh[0] | fh[1] << 8 | fh[2] << 16 | (uint32_t)fh[3] << 24;
    if (!sz || sz > 0x1800000u || !(data[have] = malloc(sz)) ||
        fread(data[have], 1, sz, fp) != sz) {
      fprintf(stderr, "%s: damaged frame %ld\n", clip, have);
      return 1;
    }
    sizes[have++] = sz;
  }
  fclose(fp);
  if (have < k) {
    fprintf(stderr, "%s: only %ld frames\n", clip, have);
    return 1;
  }

  // For the plug-in's log lines of this process (log show, processID).
  printf("pid %d\n", (int)getpid());
  measure("start, nothing loaded", 0, &ports0, &uc0);
  CFStringRef implID = codec == kCMVideoCodecType_AV1
                           ? CFSTR("com.droga.vtchurn.av1")
                           : CFSTR("com.droga.vtchurn.vp9");
  if (load_bundle(bundle, codec, implID)) return 1;
  CMVideoFormatDescriptionRef fmt = NULL;
  if (CMVideoFormatDescriptionCreate(NULL, codec, w, h, NULL, &fmt)) return 1;
  CFMutableDictionaryRef spec =
      CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                &kCFTypeDictionaryValueCallBacks);
  CFDictionarySetValue(
      spec, kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder,
      kCFBooleanTrue);
  CFStringRef id = decoderID ? CFStringCreateWithCString(NULL, decoderID,
                                                         kCFStringEncodingUTF8)
                             : copy_decoder_id(implID, codec);
  if (!id) {
    if (decoderID) return usage();
    fprintf(stderr,
            "VideoToolbox does not list the decoder just registered: "
            "nothing tells its sessions from those of another plug-in\n");
    return 1;
  }
  CFDictionarySetValue(spec, CFSTR("DecoderID"), id);
  char idText[256] = "";
  CFStringGetCString(id, idText, sizeof(idText), kCFStringEncodingUTF8);
  printf("sessions ask for decoder %s\n", idText);
  CFRelease(id);

  // ports1 and uc1 are taken after the first session that started.
  int failedStarts = 0, frameErrors = 0, frames = 0, started = 0;
  for (long n = 1; n <= sessions; n++) {
    Ctx c = {0};
    VTDecompressionOutputCallbackRecord cb = {out_cb, &c};
    VTDecompressionSessionRef sess = NULL;
    OSStatus st =
        VTDecompressionSessionCreate(NULL, fmt, spec, NULL, &cb, &sess);
    if (st || !sess) {
      failedStarts++;
      printf("session %ld: VTDecompressionSessionCreate %d\n", n, (int)st);
      continue;
    }
    started++;
    for (long i = 0; i < k; i++) {
      CMBlockBufferRef bb = NULL;
      CMSampleBufferRef sb = NULL;
      CMBlockBufferCreateWithMemoryBlock(
          NULL, data[i], sizes[i], kCFAllocatorNull, NULL, 0, sizes[i], 0, &bb);
      CMSampleTimingInfo ti = {CMTimeMake(1, 30), CMTimeMake(i, 30),
                               kCMTimeInvalid};
      if (bb)
        CMSampleBufferCreateReady(NULL, bb, fmt, 1, 1, &ti, 1, &sizes[i], &sb);
      if (sb) {
        st = VTDecompressionSessionDecodeFrame(sess, sb, 0, NULL, NULL);
        if (st)
          printf("session %ld frame %ld: DecodeFrame %d\n", n, i, (int)st);
        CFRelease(sb);
      } else {
        c.errors++;
      }
      if (bb) CFRelease(bb);
    }
    VTDecompressionSessionWaitForAsynchronousFrames(sess);
    VTDecompressionSessionInvalidate(sess);
    CFRelease(sess);
    frames += c.frames;
    frameErrors += c.errors;
    if (started == 1)
      measure("after the first session that started", 1, &ports1, &uc1);
    if (n % 50 == 0 && n != sessions) measure("running", (int)n, NULL, NULL);
  }
  // A stuck session would be closed on the decoder's background queue: give
  // it a moment before the last count.
  sleep(2);
  unsigned portsN;
  int ucN;
  measure("end", (int)sessions, &portsN, &ucN);
  // Per session that started, after the first one; none to divide by below 2.
  if (started < 2) {
    printf("growth per session after the first: n/a (%d sessions started)\n",
           started);
  } else {
    double per = (double)(started - 1);
    char uc[32] = "n/a (ioreg failed)";
    if (uc1 >= 0 && ucN >= 0)
      snprintf(uc, sizeof(uc), "%.2f", (ucN - uc1) / per);
    printf("growth per session after the first: ports %.2f user clients %s\n",
           ((double)portsN - ports1) / per, uc);
  }
  printf(
      "sessions %ld, started %d, failed starts %d, frames %d, frame errors "
      "%d\n",
      sessions, started, failedStarts, frames, frameErrors);
  printf("decoder plug-in images in this process:\n");
  for (uint32_t i = 0; i < _dyld_image_count(); i++) {
    const char* name = _dyld_get_image_name(i);
    if (name && strstr(name, "VCNDecoder")) printf("  %s\n", name);
  }
  CFRelease(spec);
  CFRelease(fmt);
  return failedStarts || frameErrors || frames < sessions * k ? 2 : 0;
}
