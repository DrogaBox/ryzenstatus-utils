// vcnencodefix - user-space half of VCNEncodeFix.
//
// Applies three patches inside every VTEncoderXPCService (the process where
// macOS runs hardware video encoders):
//   preset  AMDRadeonVADriver2: the VCN encoder gets a speed (or
//           balance/quality) preset on every frame
//   wide    AppleGVAHEVCEncoder: HEVC encodes wider than 4096 no longer hang
//           the GPU's compute channel
//   hevc10  AMDRadeonVADriver2: VCN 3 10-bit HEVC gets 10-bit P010 input
//           format packets and the slice's Cr QP offset
// and one inside every ContinuityCaptureAgent (an iPhone used as a camera) and
// avconferenced (FaceTime calls), the processes that handle video calls:
//   cc      VideoProcessing: the incoming HEVC stream is decoded by the GPU
//           instead of the CPU, and FaceTime's encoder is a local one instead
//           of the T2's (which a Mac Pro or iMac Pro board-id without a T2
//           does not have)
// See patches.c for what each patch changes. The bytes are written into the
// target the way a debugger writes a breakpoint: the page is made copy-on-write
// in that process only and the process is suspended for the write. Nothing on
// disk changes; a patched process keeps the patch until it exits.
//
// The driver and VideoProcessing live in the dyld shared cache, mapped at the
// same address in every process, so their sites are found once in this
// process (and their bytes are checked again in each target). The HEVC plug-in
// is a file that each service loads with dlopen when its first HEVC session is
// created, at its own address. A new service is found within about 10 ms of its
// launch, its dyld image list is then watched every 10 ms while the plug-in is
// not loaded yet, and the plug-in is patched as soon as it appears (in OBS the
// first frame follows the launch by about 260 ms; a 250 ms scan alone lost that
// race). The patched code runs on every frame, so a service whose plug-in was
// already in use is fixed from its next frame.
//
// Checks before anything is written: the image's LC_UUID must be one of the
// validated builds (patches.c), the site's bytes must occur exactly once in its
// __text, the target must hold the original (or already the patched) bytes, and
// no thread of the target may be executing inside them. Anything else is left
// alone.
//
// It also edits OpenCore's config.plist for the kernel half
// (VCNEncodeFloor.kext); see efi.c.
#include <errno.h>
#include <fcntl.h>
#include <libproc.h>
#include <mach-o/dyld_images.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/param.h>
#include <sys/proc_info.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>
#include <uuid/uuid.h>

#include "efi.h"
#include "patches.h"

#ifndef VERSION
#define VERSION "dev"
#endif

// libdyld exports (mach-o/dyld_priv.h is not in the public SDK).
struct dyld_shared_cache_dylib_text_info {
  uint64_t version;
  uint64_t loadAddressUnslid;
  uint64_t textSegmentSize;
  uuid_t dylibUuid;
  const char* path;
  uint64_t textSegmentOffset;
};
extern int dyld_shared_cache_iterate_text(
    const uuid_t cacheUuid,
    void (^callback)(const struct dyld_shared_cache_dylib_text_info* info));
extern bool _dyld_get_shared_cache_uuid(uuid_t uuid);
extern const void* _dyld_get_shared_cache_range(size_t* length);

static const char* kServicePath =
    "/System/Library/Frameworks/VideoToolbox.framework/Versions/A/XPCServices/"
    "VTEncoderXPCService.xpc/Contents/MacOS/VTEncoderXPCService";

// ---- configuration and located sites ----

static struct {
  bool enabled, available;
  char reason[200];
  uint32_t op;
  const PresetBuild*
      build;      // the validated build of the driver in the shared cache
  uint64_t site;  // same address in every process
  uint8_t repl[kPresetLen];
} gPreset;

static struct {
  bool enabled, available;
  char reason[200];
  const CcBuild* build;     // the validated build of VideoProcessing
  uint64_t site[kCcSites];  // same address in every process
  uint8_t repl[kCcSites][kCcMaxWrite];
} gCc;

static struct {
  bool enabled, available;
  char reason[200];
  uuid_t uuid;
  const WideBuild* build;   // the validated build of the plug-in on disk
  uint64_t callVm, caveVm;  // image addresses before the slide
  uint8_t call[kWideCallLen], cave[kWideCaveLen];
} gWide;

static struct {
  bool enabled, available;
  char reason[200];
  const Hevc10Build*
      build;  // the validated build of the driver in the shared cache
  uint64_t fmtSite, dbkSite;  // same addresses in every process
} gHevc10;

// The service's log, when standard output is a regular file (launchd's
// StandardOutPath). newsyslog rotates it by renaming it; launchd keeps writing
// to the renamed file, so before each line the path is compared with what
// standard output is, and reopened.
static char gLogPath[MAXPATHLEN];

static void logReopen(void) {
  if (!gLogPath[0]) return;
  struct stat at, out;
  if (fstat(STDOUT_FILENO, &out) == 0 && stat(gLogPath, &at) == 0 &&
      at.st_dev == out.st_dev && at.st_ino == out.st_ino)
    return;
  int fd = open(gLogPath, O_WRONLY | O_APPEND | O_CREAT, 0644);
  if (fd < 0) return;
  fflush(stdout);
  dup2(fd, STDOUT_FILENO);
  dup2(fd, STDERR_FILENO);
  // open() returns 1 or 2 when that descriptor was closed: keep it then
  if (fd != STDOUT_FILENO && fd != STDERR_FILENO) close(fd);
}

static void logFollow(void) {
  struct stat out;
  if (fstat(STDOUT_FILENO, &out) == 0 && S_ISREG(out.st_mode) &&
      fcntl(STDOUT_FILENO, F_GETPATH, gLogPath) == -1)
    gLogPath[0] = 0;
}

static void logf_(const char* fmt, ...) __attribute__((format(printf, 1, 2)));
static void logf_(const char* fmt, ...) {
  logReopen();
  char ts[32];
  struct timeval tv;
  gettimeofday(&tv, NULL);
  time_t t = tv.tv_sec;
  strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", localtime(&t));
  printf("%s.%03d ", ts, (int)(tv.tv_usec / 1000));
  va_list ap;
  va_start(ap, fmt);
  vprintf(fmt, ap);
  va_end(ap);
  printf("\n");
  fflush(stdout);
}

// The encoder service is an Apple platform process. task_for_pid lets root past
// its own checks, but then asks AMFI, and AMFI (checked in IDA on 15.8.3) only
// lets root get such a task port while SIP's "Debugging Restrictions" are off,
// i.e. while csr_check(CSR_ALLOW_TASK_FOR_PID) allows it; otherwise
// task_for_pid returns KERN_FAILURE, "(os/kern) failure". csr_check here asks
// the kernel the same question.
extern int csr_check(uint32_t mask);
#define CSR_ALLOW_TASK_FOR_PID (1u << 2)
static bool sip_blocks_access(void) {
  return csr_check(CSR_ALLOW_TASK_FOR_PID) != 0;
}
static const char* kSipHint =
    "SIP Debugging Restrictions are on, so macOS refuses access to the "
    "encoder and the video-call processes; "
    "add 0x4 to csr-active-config (see README, Requirements)";

static int parse_preset(const char* s, uint32_t* op) {
  if (!strcmp(s, "speed"))
    *op = kPresetSpeed;
  else if (!strcmp(s, "balance"))
    *op = kPresetBalance;
  else if (!strcmp(s, "quality"))
    *op = kPresetQuality;
  else
    return -1;
  return 0;
}

static const char* preset_name(uint32_t op) {
  return op == kPresetSpeed     ? "speed"
         : op == kPresetBalance ? "balance"
         : op == kPresetQuality ? "quality"
                                : "?";
}

// Finds __TEXT,__text and LC_UUID of a Mach-O image in memory (header at mh,
// `avail` readable bytes).
static const struct section_64* macho_text(const struct mach_header_64* mh,
                                           size_t avail, const uint8_t** uuid) {
  if (avail < sizeof(*mh) || mh->magic != MH_MAGIC_64 ||
      mh->sizeofcmds > avail - sizeof(*mh))
    return NULL;
  const uint8_t *p = (const uint8_t*)(mh + 1), *end = p + mh->sizeofcmds;
  const struct section_64* text = NULL;
  if (uuid) *uuid = NULL;
  for (uint32_t i = 0; i < mh->ncmds && p + sizeof(struct load_command) <= end;
       i++) {
    const struct load_command* c = (const void*)p;
    if (c->cmdsize < sizeof(*c) || p + c->cmdsize > end) return NULL;
    if (c->cmd == LC_SEGMENT_64) {
      const struct segment_command_64* seg = (const void*)c;
      const struct section_64* sec = (const void*)(seg + 1);
      for (uint32_t j = 0;
           j < seg->nsects && (const uint8_t*)(sec + j + 1) <= p + c->cmdsize;
           j++)
        if (!strcmp(sec[j].segname, "__TEXT") &&
            !strcmp(sec[j].sectname, "__text"))
          text = &sec[j];
    } else if (c->cmd == LC_UUID && uuid)
      *uuid = ((const struct uuid_command*)c)->uuid;
    p += c->cmdsize;
  }
  return text;
}

static size_t count_matches(const uint8_t* hay, size_t n, const uint8_t* needle,
                            size_t len, size_t* at) {
  size_t m = 0;
  for (size_t i = 0; i + len <= n; i++)
    if (hay[i] == needle[0] && !memcmp(hay + i, needle, len)) {
      m++;
      *at = i;
    }
  return m;
}

// Address in this process of an image of the dyld shared cache (0 if it is not
// in the cache, -1 if there is no cache), its UUID and the cache's slide (the
// image's load commands hold unslid addresses).
static uint64_t cache_image(const char* path, char uuidStr[40],
                            uint64_t* slideOut) {
  size_t len = 0;
  const uint8_t* base = _dyld_get_shared_cache_range(&len);
  uuid_t cache;
  if (!base || memcmp(base, "dyld_v1", 7) != 0 ||
      !_dyld_get_shared_cache_uuid(cache))
    return (uint64_t)-1;
  uint32_t mappingOffset;
  memcpy(&mappingOffset, base + 16, 4);
  uint64_t unslidBase;
  memcpy(&unslidBase, base + mappingOffset, 8);
  uint64_t slide = (uint64_t)base - unslidBase;
  __block uint64_t unslid = 0;
  dyld_shared_cache_iterate_text(
      cache, ^(const struct dyld_shared_cache_dylib_text_info* info) {
        if (info->path && !strcmp(info->path, path)) {
          unslid = info->loadAddressUnslid;
          uuid_unparse_upper(info->dylibUuid, uuidStr);
        }
      });
  *slideOut = slide;
  return unslid ? unslid + slide : 0;
}

static void locate_preset(void) {
  gPreset.available = false;
  char uuidStr[40] = "";
  uint64_t slide = 0, addr = cache_image(kPresetImage, uuidStr, &slide);
  if (addr == (uint64_t)-1) {
    snprintf(gPreset.reason, sizeof(gPreset.reason), "no dyld shared cache");
    return;
  }
  if (!addr) {
    snprintf(
        gPreset.reason, sizeof(gPreset.reason),
        "AMDRadeonVADriver2 is not in the shared cache (no AMD GPU driver?)");
    return;
  }
  gPreset.build = preset_build(uuidStr);
  if (!gPreset.build) {
    snprintf(gPreset.reason, sizeof(gPreset.reason),
             "AMDRadeonVADriver2 build %s is not a validated build", uuidStr);
    return;
  }
  const struct mach_header_64* mh = (const void*)addr;
  const struct section_64* text = macho_text(mh, 65536, NULL);
  if (!text) {
    snprintf(gPreset.reason, sizeof(gPreset.reason),
             "AMDRadeonVADriver2: no __text");
    return;
  }
  size_t at = 0,
         m = count_matches((const void*)(text->addr + slide), text->size,
                           gPreset.build->find, kPresetFindLen, &at);
  if (m != 1) {
    snprintf(gPreset.reason, sizeof(gPreset.reason),
             "AMDRadeonVADriver2: site found %zu times, expected once", m);
    return;
  }
  gPreset.site = text->addr + slide + at;
  build_preset(gPreset.repl, gPreset.op);
  gPreset.available = true;
}

static void locate_cc(void) {
  gCc.available = false;
  char uuidStr[40] = "";
  uint64_t slide = 0, addr = cache_image(kCcImage, uuidStr, &slide);
  if (addr == (uint64_t)-1 || !addr) {
    snprintf(gCc.reason, sizeof(gCc.reason), "%s",
             addr ? "no dyld shared cache"
                  : "VideoProcessing is not in the shared cache");
    return;
  }
  const CcBuild* b = cc_build(uuidStr);
  if (!b) {
    snprintf(gCc.reason, sizeof(gCc.reason),
             "VideoProcessing build %s is not a validated build", uuidStr);
    return;
  }
  const struct section_64* text = macho_text((const void*)addr, 65536, NULL);
  if (!text) {
    snprintf(gCc.reason, sizeof(gCc.reason), "VideoProcessing: no __text");
    return;
  }
  char why[160];
  if (!cc_locate(b, (const uint8_t*)(text->addr + slide), text->size,
                 text->addr + slide, gCc.site, why, sizeof(why))) {
    snprintf(gCc.reason, sizeof(gCc.reason), "VideoProcessing: %s", why);
    return;
  }
  gCc.build = b;
  for (int k = 0; k < kCcSites; k++) build_cc(&b->site[k], gCc.repl[k]);
  gCc.available = true;
}

static void locate_hevc10(void) {
  gHevc10.available = false;
  char uuidStr[40] = "";
  uint64_t slide = 0, addr = cache_image(kPresetImage, uuidStr, &slide);
  if (addr == (uint64_t)-1) {
    snprintf(gHevc10.reason, sizeof(gHevc10.reason), "no dyld shared cache");
    return;
  }
  if (!addr) {
    snprintf(
        gHevc10.reason, sizeof(gHevc10.reason),
        "AMDRadeonVADriver2 is not in the shared cache (no AMD GPU driver?)");
    return;
  }
  const struct section_64* text = macho_text((const void*)addr, 65536, NULL);
  if (!text) {
    snprintf(gHevc10.reason, sizeof(gHevc10.reason),
             "AMDRadeonVADriver2: no __text");
    return;
  }
  uint64_t textAddr = text->addr + slide;
  size_t textSize = text->size;
  gHevc10.build = hevc10_build(uuidStr);
  if (!gHevc10.build) {
    snprintf(gHevc10.reason, sizeof(gHevc10.reason),
             "AMDRadeonVADriver2 build %s is not a validated build", uuidStr);
    return;
  }
  size_t atFmt = 0, mFmt = count_matches((const void*)textAddr, textSize,
                                         gHevc10.build->fmtFind,
                                         kHevc10FmtFindLen, &atFmt);
  if (mFmt != 1) {
    snprintf(gHevc10.reason, sizeof(gHevc10.reason),
             "AMDRadeonVADriver2: format site found %zu times, expected once",
             mFmt);
    return;
  }
  size_t atDbk = 0, mDbk = count_matches((const void*)textAddr, textSize,
                                         gHevc10.build->dbkFind,
                                         kHevc10DbkFindLen, &atDbk);
  if (mDbk != 1) {
    snprintf(
        gHevc10.reason, sizeof(gHevc10.reason),
        "AMDRadeonVADriver2: deblocking site found %zu times, expected once",
        mDbk);
    return;
  }
  gHevc10.fmtSite = textAddr + atFmt;
  gHevc10.dbkSite = textAddr + atDbk;
  gHevc10.available = true;
}

static void locate_wide(void) {
  gWide.available = false;
  int fd = open(kWideImage, O_RDONLY);
  if (fd < 0) {
    snprintf(gWide.reason, sizeof(gWide.reason), "%s: %s", kWideImage,
             strerror(errno));
    return;
  }
  struct stat st;
  void* map = MAP_FAILED;
  if (fstat(fd, &st) == 0 && st.st_size > 0)
    map = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
  close(fd);
  if (map == MAP_FAILED) {
    snprintf(gWide.reason, sizeof(gWide.reason),
             "cannot read the HEVC plug-in");
    return;
  }
  const struct mach_header_64* mh = map;
  const uint8_t* uuid = NULL;
  const struct section_64* text = macho_text(mh, (size_t)st.st_size, &uuid);
  char uuidStr[40] = "?";
  if (uuid) uuid_unparse_upper(uuid, uuidStr);
  if (!text || !uuid)
    snprintf(gWide.reason, sizeof(gWide.reason),
             "HEVC plug-in: not a single-architecture x86_64 image");
  else if (!(gWide.build = wide_build(uuidStr)))
    snprintf(gWide.reason, sizeof(gWide.reason),
             "AppleGVAHEVCEncoder build %s is not a validated build", uuidStr);
  else if ((uint64_t)text->offset + text->size > (uint64_t)st.st_size)
    snprintf(gWide.reason, sizeof(gWide.reason),
             "HEVC plug-in: __text outside the file");
  else {
    memcpy(gWide.uuid, uuid, 16);
    size_t at = 0,
           m = count_matches((const uint8_t*)map + text->offset, text->size,
                             gWide.build->find, kWideFindLen, &at);
    uint64_t caveVm =
        sizeof(*mh) + mh->sizeofcmds;  // __TEXT starts at file offset 0 /
                                       // vmaddr 0 in this image
    bool caveZero = caveVm + kWideCaveLen <= text->addr &&
                    caveVm + kWideCaveLen <= (uint64_t)st.st_size;
    for (uint64_t i = 0; caveZero && i < kWideCaveLen; i++)
      caveZero = ((const uint8_t*)map)[caveVm + i] == 0;
    if (m != 1)
      snprintf(gWide.reason, sizeof(gWide.reason),
               "HEVC plug-in: site found %zu times, expected once", m);
    else if (!caveZero)
      snprintf(gWide.reason, sizeof(gWide.reason),
               "HEVC plug-in: no free space after the load commands");
    else {
      gWide.callVm = text->addr + at;
      gWide.caveVm = caveVm;
      build_wide(gWide.build, gWide.call, gWide.cave, gWide.callVm,
                 gWide.caveVm);
      gWide.available = true;
    }
  }
  munmap(map, (size_t)st.st_size);
}

// ---- target processes ----

typedef enum {
  kOriginal,
  kPatched,
  kOther,
  kUnreadable,
  kNotLoaded,
  kPartial
} State;
static const char* state_str(State s) {
  static const char* n[] = {"original",   "patched",        "unexpected bytes",
                            "unreadable", "not loaded yet", "partly patched"};
  return n[s];
}

static bool rd(task_t task, uint64_t addr, void* buf, size_t len) {
  mach_vm_size_t got = 0;
  return mach_vm_read_overwrite(task, addr, len, (mach_vm_address_t)buf,
                                &got) == KERN_SUCCESS &&
         got == len;
}

static State preset_state(task_t task, uint32_t* op) {
  const uint8_t* find = gPreset.build->find;
  uint8_t cur[kPresetFindLen];
  if (!rd(task, gPreset.site, cur, sizeof(cur))) return kUnreadable;
  if (!memcmp(cur, find, sizeof(cur))) return kOriginal;
  if (memcmp(cur + kPresetLen, find + kPresetLen, sizeof(cur) - kPresetLen) !=
          0 ||
      !is_preset_patched(cur))
    return kOther;
  if (op) memcpy(op, cur + 1, 4);
  return kPatched;
}

static State hevc10_state(task_t task) {
  const Hevc10Build* b = gHevc10.build;
  uint8_t fmt[kHevc10FmtFindLen], dbk[kHevc10DbkFindLen];
  if (!rd(task, gHevc10.fmtSite, fmt, sizeof(fmt)) ||
      !rd(task, gHevc10.dbkSite, dbk, sizeof(dbk)))
    return kUnreadable;
  bool dbkTail = !memcmp(dbk + kHevc10DbkLen, b->dbkFind + kHevc10DbkLen,
                         sizeof(dbk) - kHevc10DbkLen);
  if (dbkTail && !memcmp(fmt, b->fmtFind, sizeof(fmt)) &&
      !memcmp(dbk, b->dbkFind, kHevc10DbkLen))
    return kOriginal;
  if (dbkTail && !memcmp(fmt, b->fmtRepl, kHevc10FmtLen) &&
      !memcmp(dbk, b->dbkRepl, kHevc10DbkLen))
    return kPatched;
  return kOther;
}

// Address of the HEVC plug-in in the target, 0 if not loaded. *count = the
// target's dyld image count.
static uint64_t wide_base(task_t task, uint32_t* count) {
  task_dyld_info_data_t di;
  mach_msg_type_number_t n = TASK_DYLD_INFO_COUNT;
  if (task_info(task, TASK_DYLD_INFO, (task_info_t)&di, &n) != KERN_SUCCESS ||
      !di.all_image_info_addr)
    return 0;
  struct {
    uint32_t version, infoArrayCount;
    uint64_t infoArray;
  } hdr;
  if (!rd(task, di.all_image_info_addr, &hdr, sizeof(hdr)) || !hdr.infoArray)
    return 0;
  if (count) *count = hdr.infoArrayCount;
  uint32_t c = hdr.infoArrayCount > 8192 ? 8192 : hdr.infoArrayCount;
  struct dyld_image_info* infos = calloc(c ? c : 1, sizeof(*infos));
  uint64_t base = 0;
  if (!infos) return 0;
  if (c && rd(task, hdr.infoArray, infos, c * sizeof(*infos))) {
    size_t plen = strlen(kWideImage) + 1;
    char path[512];
    for (uint32_t i = c; i-- > 0 && !base;)
      if (infos[i].imageFilePath &&
          rd(task, (uint64_t)infos[i].imageFilePath, path, plen) &&
          !memcmp(path, kWideImage, plen))
        base = (uint64_t)infos[i].imageLoadAddress;
  }
  free(infos);
  return base;
}

static State wide_state(task_t task, uint64_t base) {
  if (!base) return kNotLoaded;
  uint8_t hdr[4096];
  const uint8_t* uuid = NULL;
  if (!rd(task, base, hdr, sizeof(hdr))) return kUnreadable;
  if (!macho_text((const void*)hdr, sizeof(hdr), &uuid) || !uuid ||
      memcmp(uuid, gWide.uuid, 16) != 0)
    return kOther;
  const uint8_t* find = gWide.build->find;
  uint8_t call[kWideFindLen], cave[kWideCaveLen];
  if (!rd(task, base + gWide.callVm, call, sizeof(call)) ||
      !rd(task, base + gWide.caveVm, cave, sizeof(cave)))
    return kUnreadable;
  static const uint8_t zero[kWideCaveLen];
  bool tail = !memcmp(call + kWideCallLen, find + kWideCallLen,
                      sizeof(call) - kWideCallLen);
  if (tail && !memcmp(call, find, kWideCallLen) &&
      !memcmp(cave, zero, sizeof(cave)))
    return kOriginal;
  if (tail && !memcmp(call, gWide.call, kWideCallLen) &&
      !memcmp(cave, gWide.cave, sizeof(cave)))
    return kPatched;
  return kOther;
}

typedef struct {
  uint64_t addr;
  size_t len;
  const uint8_t* bytes;
} Region;

static bool no_thread_inside(task_t task, const Region* r, int n) {
  thread_act_array_t threads;
  mach_msg_type_number_t count = 0;
  if (task_threads(task, &threads, &count) != KERN_SUCCESS) return false;
  bool clear = true;
  for (mach_msg_type_number_t i = 0; i < count; i++) {
    x86_thread_state64_t st;
    mach_msg_type_number_t sn = x86_THREAD_STATE64_COUNT;
    if (thread_get_state(threads[i], x86_THREAD_STATE64, (thread_state_t)&st,
                         &sn) != KERN_SUCCESS)
      clear = false;
    else
      for (int k = 0; k < n; k++)
        if (st.__rip >= r[k].addr && st.__rip < r[k].addr + r[k].len)
          clear = false;
    mach_port_deallocate(mach_task_self(), threads[i]);
  }
  vm_deallocate(mach_task_self(), (vm_address_t)threads,
                count * sizeof(thread_act_t));
  return clear;
}

// Writes `len` bytes at `addr` through a copy-on-write page of the target.
static kern_return_t poke(task_t task, mach_vm_address_t addr,
                          const uint8_t* bytes, size_t len) {
  mach_vm_address_t page = addr & ~((mach_vm_address_t)vm_page_size - 1);
  mach_vm_size_t span = ((addr + len + vm_page_size - 1) &
                         ~((mach_vm_address_t)vm_page_size - 1)) -
                        page;
  kern_return_t kr = mach_vm_protect(
      task, page, span, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
  if (kr == KERN_SUCCESS)
    kr = mach_vm_write(task, addr, (vm_offset_t)bytes,
                       (mach_msg_type_number_t)len);
  kern_return_t kr2 =
      mach_vm_protect(task, page, span, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
  return kr == KERN_SUCCESS ? kr2 : kr;
}

// Writes the regions in order with the task suspended. Returns 0 on success.
// If a later region fails, the regions already written are put back, so a
// patch made of several sites is never left half applied.
static int write_regions(task_t task, const Region* r, int n, char* err,
                         size_t errLen) {
  for (int attempt = 0; attempt < 50; attempt++) {
    if (task_suspend(task) != KERN_SUCCESS) {
      snprintf(err, errLen, "cannot suspend");
      return -1;
    }
    if (!no_thread_inside(task, r, n)) {
      task_resume(task);
      usleep(2000);
      continue;
    }
    kern_return_t kr = KERN_SUCCESS;
    uint8_t before[8][256];
    bool haveBefore = n <= 8;
    for (int k = 0; k < n && haveBefore; k++)
      if (r[k].len > sizeof(before[0]) ||
          !rd(task, r[k].addr, before[k], r[k].len))
        haveBefore = false;
    int done = 0;
    for (int k = 0; k < n && kr == KERN_SUCCESS; k++) {
      kr = poke(task, r[k].addr, r[k].bytes, r[k].len);
      if (kr == KERN_SUCCESS) done++;
    }
    if (kr != KERN_SUCCESS && haveBefore)
      for (int k = done - 1; k >= 0; k--)
        poke(task, r[k].addr, before[k], r[k].len);
    task_resume(task);
    if (kr != KERN_SUCCESS) {
      snprintf(err, errLen, "write failed (%s)", mach_error_string(kr));
      return -1;
    }
    for (int k = 0; k < n; k++) {
      uint8_t back[256];
      if (!rd(task, r[k].addr, back, r[k].len) ||
          memcmp(back, r[k].bytes, r[k].len) != 0) {
        snprintf(err, errLen, "write did not stick");
        return -1;
      }
    }
    return 0;
  }
  snprintf(err, errLen, "a thread kept running inside the patch site");
  return -1;
}

// One line of the form "preset speed: patched" into msg. Returns 0 on success
// or nothing to do, 1 if the target's memory cannot be read yet (a service
// found right after launch), -1 on any other problem.
static int do_preset(task_t task, bool remove, char* msg, size_t len) {
  uint32_t op = 0;
  State st = preset_state(task, &op);
  const uint8_t* to = remove ? gPreset.build->find : gPreset.repl;
  if (st == kUnreadable) {
    snprintf(msg, len, "preset: not readable yet");
    return 1;
  }
  if (st == kOther) {
    snprintf(msg, len, "preset: %s, left alone", state_str(st));
    return -1;
  }
  if ((remove && st == kOriginal) ||
      (!remove && st == kPatched && op == gPreset.op)) {
    snprintf(msg, len, "preset: already %s",
             remove ? "original" : preset_name(op));
    return 0;
  }
  Region r = {gPreset.site, kPresetLen, to};
  char err[160];
  if (write_regions(task, &r, 1, err, sizeof(err)) != 0) {
    snprintf(msg, len, "preset: %s", err);
    return -1;
  }
  snprintf(msg, len, remove ? "preset: restored" : "preset %s: patched",
           preset_name(gPreset.op));
  return 0;
}

static int do_hevc10(task_t task, bool remove, char* msg, size_t len) {
  State st = hevc10_state(task);
  if (st == kUnreadable) {
    snprintf(msg, len, "hevc10: not readable yet");
    return 1;
  }
  if (st == kOther) {
    snprintf(msg, len, "hevc10: %s, left alone", state_str(st));
    return -1;
  }
  if ((remove && st == kOriginal) || (!remove && st == kPatched)) {
    snprintf(msg, len, "hevc10: already %s", remove ? "original" : "patched");
    return 0;
  }
  const Hevc10Build* b = gHevc10.build;
  Region r[2] = {
      {gHevc10.fmtSite, kHevc10FmtLen, remove ? b->fmtFind : b->fmtRepl},
      {gHevc10.dbkSite, kHevc10DbkLen, remove ? b->dbkFind : b->dbkRepl},
  };
  char err[160];
  if (write_regions(task, r, 2, err, sizeof(err)) != 0) {
    snprintf(msg, len, "hevc10: %s", err);
    return -1;
  }
  snprintf(msg, len, "hevc10: %s", remove ? "restored" : "patched");
  return 0;
}

// Returns 0 done (or nothing to do), 1 plug-in not loaded or not readable yet,
// -1 error.
static int do_wide(task_t task, bool remove, char* msg, size_t len) {
  uint64_t base = wide_base(task, NULL);
  State st = wide_state(task, base);
  if (st == kNotLoaded) {
    snprintf(msg, len, "wide: waiting for the HEVC plug-in");
    return 1;
  }
  if (st == kUnreadable) {
    snprintf(msg, len, "wide: HEVC plug-in not readable yet");
    return 1;
  }
  if (st == kOther) {
    snprintf(msg, len, "wide: %s, left alone", state_str(st));
    return -1;
  }
  if ((remove && st == kOriginal) || (!remove && st == kPatched)) {
    snprintf(msg, len, "wide: already %s", remove ? "original" : "patched");
    return 0;
  }
  static const uint8_t zero[kWideCaveLen];
  Region r[2];
  if (!remove) {  // cave first, then the jump into it
    r[0] = (Region){base + gWide.caveVm, kWideCaveLen, gWide.cave};
    r[1] = (Region){base + gWide.callVm, kWideCallLen, gWide.call};
  } else {  // the jump first, then the cave
    r[0] = (Region){base + gWide.callVm, kWideCallLen, gWide.build->find};
    r[1] = (Region){base + gWide.caveVm, kWideCaveLen, zero};
  }
  char err[160];
  if (write_regions(task, r, 2, err, sizeof(err)) != 0) {
    snprintf(msg, len, "wide: %s", err);
    return -1;
  }
  snprintf(msg, len, "wide: %s (plug-in at 0x%llx)",
           remove ? "restored" : "patched", base);
  return 0;
}

// State of the cc sites in a target: kOriginal / kPatched when all are,
// kPartial when some are patched and the others original (a process patched
// by an older version, which had fewer sites), kOther when any site holds
// other bytes, kUnreadable.
static State cc_state(task_t task, int st[kCcSites]) {
  bool unreadable = false;
  int orig = 0, patched = 0, written = 0;
  for (int k = 0; k < kCcSites; k++) {
    const CcSite* s = &gCc.build->site[k];
    uint8_t cur[kCcMaxFind], tgt[kCcTgtLen];
    if (!rd(task, gCc.site[k], cur, s->len) ||
        (s->tgtLen && !rd(task, gCc.site[k] + s->tgtDist, tgt, s->tgtLen))) {
      unreadable = true;
      st[k] = -2;
      continue;
    }
    st[k] = cc_site_state(s, cur, tgt);
    if (st[k] < 0) return kOther;
    if (s->n) {
      written++;
      orig += st[k] == 0;
      patched += st[k] == 1;
    }
  }
  if (unreadable) return kUnreadable;
  if (orig == written) return kOriginal;
  if (patched == written) return kPatched;
  return kPartial;
}

// Like do_preset, for a video-call process.
static int do_cc(task_t task, bool remove, char* msg, size_t len) {
  int st[kCcSites];
  State s = cc_state(task, st);
  if (s == kUnreadable) {
    snprintf(msg, len, "cc: not readable yet");
    return 1;
  }
  if (s == kOther) {
    char sites[64] = "";
    for (int k = 0; k < kCcSites; k++) {
      char one[16];
      snprintf(one, sizeof(one), "%s%c %d", k ? ", " : "", kCcSiteName[k],
               st[k]);
      strlcat(sites, one, sizeof(sites));
    }
    snprintf(msg, len, "cc: %s (sites %s), left alone", state_str(s), sites);
    return -1;
  }
  if ((remove && s == kOriginal) || (!remove && s == kPatched)) {
    snprintf(msg, len, "cc: already %s", remove ? "original" : "patched");
    return 0;
  }
  Region r[kCcSites];
  int nr = 0;
  for (int k = 0; k < kCcSites; k++) {  // only the sites not already there
    const CcSite* c = &gCc.build->site[k];
    if (c->n && st[k] != (remove ? 0 : 1))
      r[nr++] = (Region){gCc.site[k] + c->off, c->n,
                         remove ? c->find + c->off : gCc.repl[k]};
  }
  char err[160];
  if (write_regions(task, r, nr, err, sizeof(err)) != 0) {
    snprintf(msg, len, "cc: %s", err);
    return -1;
  }
  snprintf(msg, len,
           remove ? "cc: restored"
           : s == kPartial
               ? "cc: completed (the sites an older version left out)"
               : "cc: patched (video-call decoders without "
                 "DecoderUsage, FaceTime encoder local)");
  return 0;
}

// ContinuityCaptureAgent or avconferenced; *name = its file name.
static bool agent_path(pid_t pid, const char** name) {
  char path[PROC_PIDPATHINFO_MAXSIZE];
  if (proc_pidpath(pid, path, sizeof(path)) <= 0) return false;
  for (int i = 0; kCcTargets[i]; i++)
    if (!strcmp(path, kCcTargets[i])) {
      if (name) *name = strrchr(kCcTargets[i], '/') + 1;
      return true;
    }
  return false;
}
static bool is_agent(pid_t pid) { return agent_path(pid, NULL); }
static const char* agent_name(pid_t pid) {
  const char* n = "video-call process";
  agent_path(pid, &n);
  return n;
}

static bool is_service(pid_t pid) {
  char path[PROC_PIDPATHINFO_MAXSIZE];
  return proc_pidpath(pid, path, sizeof(path)) > 0 &&
         !strcmp(path, kServicePath);
}

static uint64_t start_time(pid_t pid) {
  struct proc_bsdinfo bi;
  if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bi, sizeof(bi)) != sizeof(bi))
    return 0;
  return bi.pbi_start_tvsec * 1000000ull + bi.pbi_start_tvusec;
}

static void os_line(char* buf, size_t len) {
  char ver[64] = "?", build[64] = "?";
  size_t n = sizeof(ver);
  sysctlbyname("kern.osproductversion", ver, &n, NULL, 0);
  n = sizeof(build);
  sysctlbyname("kern.osversion", build, &n, NULL, 0);
  snprintf(buf, len, "macOS %s (%s)", ver, build);
}

// A whole decimal number, nothing else in the string.
static bool parse_long(const char* s, long* out) {
  char* end;
  errno = 0;
  long v = strtol(s, &end, 10);
  if (errno != 0 || end == s || *end != 0) return false;
  *out = v;
  return true;
}

// The processes `is` accepts; NULL with *count 0 when listing fails.
static pid_t* list_pids(int* count, bool (*is)(pid_t)) {
  *count = 0;
  int n = proc_listallpids(NULL, 0);
  if (n < 0) return NULL;
  pid_t* pids = calloc((size_t)n + 256, sizeof(pid_t));
  if (!pids) return NULL;
  n = proc_listallpids(pids, (n + 256) * (int)sizeof(pid_t));
  int k = 0;
  for (int i = 0; i < n; i++)
    if (is(pids[i])) pids[k++] = pids[i];
  *count = k;
  return pids;
}
static pid_t* list_services(int* count) { return list_pids(count, is_service); }
static pid_t* list_agents(int* count) { return list_pids(count, is_agent); }

static void setup(bool preset, uint32_t op, bool wide, bool cc, bool hevc10) {
  gPreset.enabled = preset;
  gPreset.op = op;
  gWide.enabled = wide;
  gCc.enabled = cc;
  gHevc10.enabled = hevc10;
  locate_preset();
  locate_wide();
  locate_cc();
  locate_hevc10();
}

static const char* kHevc10GateSysctl = "hw.vcnhevc10";
static bool gGateOidLoggedMissing;
static bool gGateOidLoggedPerm;

static void set_hevc10_gate(int val) {
  if (sysctlbyname(kHevc10GateSysctl, NULL, NULL, &val, sizeof(val)) == 0) {
    logf_("hevc10 gate (%s): set to %d", kHevc10GateSysctl, val);
    return;
  }
  if (errno == ENOENT) {
    if (!gGateOidLoggedMissing) {
      gGateOidLoggedMissing = true;
      logf_(
          "hevc10 gate (%s): not present (VCNEncodeFloor.kext not loaded, "
          "older than 1.2.6, or -vcnhevc10 not set); continuing without "
          "kernel gate",
          kHevc10GateSysctl);
    }
  } else if (errno == EPERM || errno == EACCES) {
    if (!gGateOidLoggedPerm) {
      gGateOidLoggedPerm = true;
      logf_("hevc10 gate (%s): write(%d) refused (%s)", kHevc10GateSysctl, val,
            strerror(errno));
    }
  } else {
    logf_("hevc10 gate (%s): write(%d) failed (%s)", kHevc10GateSysctl, val,
          strerror(errno));
  }
}

// ---- commands ----

static int cmd_status(void) {
  char os[128];
  os_line(os, sizeof(os));
  printf("vcnencodefix %s on %s\n", VERSION, os);
  if (gPreset.available)
    printf("  preset  %s    VCN speed preset (driver site 0x%llx)\n",
           gPreset.enabled ? "available" : "off      ", gPreset.site);
  else
    printf("  preset  unavailable  %s\n", gPreset.reason);
  if (gWide.available)
    printf(
        "  wide    %s    HEVC wider than 4096 (plug-in offsets 0x%llx, "
        "0x%llx)\n",
        gWide.enabled ? "available" : "off      ", gWide.callVm, gWide.caveVm);
  else
    printf("  wide    unavailable  %s\n", gWide.reason);
  if (gCc.available)
    printf(
        "  cc      %-12s Continuity Camera and FaceTime HEVC on the GPU, "
        "FaceTime encoder without the T2 (VideoProcessing sites 0x%llx, "
        "0x%llx, 0x%llx)\n",
        gCc.enabled ? "available" : "off", gCc.site[1], gCc.site[2],
        gCc.site[3]);
  else
    printf("  cc      unavailable  %s\n", gCc.reason);
  if (gHevc10.available)
    printf(
        "  hevc10  %s    HEVC 10-bit input and Cr QP (driver sites "
        "0x%llx, 0x%llx)\n",
        gHevc10.enabled ? "available" : "off      ", gHevc10.fmtSite,
        gHevc10.dbkSite);
  else
    printf("  hevc10  unavailable  %s\n", gHevc10.reason);
  int gate = 0;
  size_t gateLen = sizeof(gate);
  if (sysctlbyname(kHevc10GateSysctl, &gate, &gateLen, NULL, 0) == 0 &&
      gateLen == sizeof(gate))
    printf("  gate    %-11s  %s=%d (%s)\n", gate ? "open" : "closed",
           kHevc10GateSysctl, gate,
           gate ? "Main10 advertised by kext"
                : "Main10 withheld by kext until service is active");
  else if (errno == ENOENT)
    printf(
        "  gate    unavailable  %s not present (VCNEncodeFloor.kext not "
        "loaded, older than 1.2.6, or -vcnhevc10 not set)\n",
        kHevc10GateSysctl);
  else
    printf("  gate    unavailable  %s: %s\n", kHevc10GateSysctl,
           strerror(errno));
  if (sip_blocks_access())
    printf("  access  REFUSED      %s\n", kSipHint);
  else
    printf("  access  allowed      SIP Debugging Restrictions are off\n");
  int n;
  pid_t* pids = list_services(&n);
  for (int i = 0; i < n; i++) {
    task_t task;
    if (task_for_pid(mach_task_self(), pids[i], &task) != KERN_SUCCESS) {
      if (sip_blocks_access())
        printf("  encoder service pid %d: access refused by SIP\n", pids[i]);
      else
        printf("  encoder service pid %d: run with sudo to see its state\n",
               pids[i]);
      continue;
    }
    printf("  encoder service pid %d:", pids[i]);
    const char* sep = "";
    if (gPreset.available) {
      uint32_t op = 0;
      State st = preset_state(task, &op);
      if (st == kPatched)
        printf("%s preset %s", sep, preset_name(op));
      else
        printf("%s preset %s", sep, state_str(st));
      sep = ";";
    }
    if (gWide.available) {
      printf("%s wide %s", sep,
             state_str(wide_state(task, wide_base(task, NULL))));
      sep = ";";
    }
    if (gHevc10.available)
      printf("%s hevc10 %s", sep, state_str(hevc10_state(task)));
    printf("\n");
    mach_port_deallocate(mach_task_self(), task);
  }
  if (!n) printf("  no encoder service running\n");
  free(pids);
  if (gCc.available) {
    pids = list_agents(&n);
    for (int i = 0; i < n; i++) {
      task_t task;
      if (task_for_pid(mach_task_self(), pids[i], &task) != KERN_SUCCESS) {
        printf("  %s pid %d: %s\n", agent_name(pids[i]), pids[i],
               sip_blocks_access() ? "access refused by SIP"
                                   : "run with sudo to see its state");
        continue;
      }
      int st[kCcSites];
      printf("  %s pid %d: cc %s\n", agent_name(pids[i]), pids[i],
             state_str(cc_state(task, st)));
      mach_port_deallocate(mach_task_self(), task);
    }
    if (!n)
      printf(
          "  no ContinuityCaptureAgent or avconferenced running (they start "
          "with the camera or a call)\n");
    free(pids);
  }
  return ((gPreset.enabled && gPreset.available) ||
          (gWide.enabled && gWide.available) ||
          (gCc.enabled && gCc.available) ||
          (gHevc10.enabled && gHevc10.available))
             ? 0
             : 3;
}

static int cmd_one(pid_t pid, bool remove) {
  bool agent = is_agent(pid);
  if (!agent && !is_service(pid)) {
    fprintf(stderr, "pid %d is not %s, %s or %s\n", pid, kServicePath,
            kCcTargets[0], kCcTargets[1]);
    return 1;
  }
  task_t task;
  kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
  if (kr != KERN_SUCCESS) {
    fprintf(stderr, "task_for_pid(%d) failed (%s); %s\n", pid,
            mach_error_string(kr),
            sip_blocks_access() ? kSipHint : "run with sudo");
    return 1;
  }
  int fails = 0;
  char msg[300];
  if (agent) {
    if (!gCc.enabled || !gCc.available) {
      logf_("pid %d: cc: %s", pid, gCc.enabled ? gCc.reason : "off");
      fails++;
    } else {
      fails += do_cc(task, remove, msg, sizeof(msg)) != 0;
      logf_("pid %d: %s", pid, msg);
    }
    mach_port_deallocate(mach_task_self(), task);
    return fails ? 1 : 0;
  }
  if (gPreset.enabled && gPreset.available) {
    fails += do_preset(task, remove, msg, sizeof(msg)) != 0;
    logf_("pid %d: %s", pid, msg);
  }
  if (gWide.enabled && gWide.available) {
    int r = do_wide(task, remove, msg, sizeof(msg));
    fails +=
        r < 0 || (r == 1 && wide_base(task, NULL) !=
                                0);  // "not loaded yet" is not a failure here
    logf_("pid %d: %s", pid, msg);
  }
  if (gHevc10.enabled && gHevc10.available) {
    fails += do_hevc10(task, remove, msg, sizeof(msg)) != 0;
    logf_("pid %d: %s", pid, msg);
  }
  mach_port_deallocate(mach_task_self(), task);
  return fails ? 1 : 0;
}

static volatile sig_atomic_t gStop;
static void on_signal(int s) {
  (void)s;
  gStop = 1;
}

typedef struct {
  pid_t pid;
  uint64_t start;
  bool widePending, presetPending, hevc10Pending;
  uint32_t lastCount;
  unsigned
      presetUntil;  // tick after which an unreadable driver site is given up
} Svc;
static unsigned gTick;

static int cmp_pid(const void* a, const void* b) {
  pid_t x = *(const pid_t*)a, y = *(const pid_t*)b;
  return (x > y) - (x < y);
}
enum { kMaxSvc = 512 };
static Svc gSvc[kMaxSvc];
// Patches a service the first time it is seen (pid and start time). The HEVC
// plug-in is usually not loaded yet; such a service is then watched every tick
// until it is.
static void consider(pid_t pid, bool preset, bool wide, bool hevc10) {
  uint64_t st = start_time(pid);
  int k, freeSlot = -1;
  for (k = 0; k < kMaxSvc; k++) {
    if (gSvc[k].pid == pid && gSvc[k].start == st) return;
    if (freeSlot < 0 && gSvc[k].pid == 0) freeSlot = k;
  }
  if (freeSlot < 0) return;
  task_t task;
  kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
  if (kr != KERN_SUCCESS) {
    logf_("pid %d: task_for_pid failed (%s)%s", pid, mach_error_string(kr),
          sip_blocks_access() ? ": SIP Debugging Restrictions are on" : "");
    // Remembered like a patched service, so it is not asked again (and logged
    // again) on every scan while it runs: the refusal holds until a reboot.
    gSvc[freeSlot] = (Svc){pid, st, false, false, false, 0, 0};
    return;
  }
  char line[1024] = "", msg[300];
  int wr = 0, pr = 0, hr = 0;
  if (wide) {  // first: the plug-in may already be loaded and about to send a
               // frame
    wr = do_wide(task, false, msg, sizeof(msg));
    strlcat(line, msg, sizeof(line));
  }
  if (preset) {
    pr = do_preset(task, false, msg, sizeof(msg));
    strlcat(line, line[0] ? "; " : "", sizeof(line));
    strlcat(line, msg, sizeof(line));
  }
  if (hevc10) {
    hr = do_hevc10(task, false, msg, sizeof(msg));
    strlcat(line, line[0] ? "; " : "", sizeof(line));
    strlcat(line, msg, sizeof(line));
  }
  mach_port_deallocate(mach_task_self(), task);
  logf_("pid %d: %s", pid, line);
  gSvc[freeSlot] = (Svc){pid, st, wr == 1, pr == 1, hr == 1, 0, gTick + 500};
}
// Video-call processes (ContinuityCaptureAgent, started with the camera, and
// avconferenced, which keeps running between calls): patched once each, the
// first time they are seen (pid and start time), so a relaunched one is
// patched again. VideoProcessing is in the shared cache, so its sites can be
// written before the process loads it; one whose memory cannot be read yet
// (right after exec) is retried every tick for up to 5 s. The patch acts on
// the next decoder the process creates.
enum { kMaxAgent = 64 };
static struct {
  pid_t pid;
  uint64_t start;
  bool pending;
  unsigned until;
} gAgent[kMaxAgent];
static void consider_agent(pid_t pid) {
  uint64_t st = start_time(pid);
  int freeSlot = -1;
  for (int k = 0; k < kMaxAgent; k++) {
    if (gAgent[k].pid == pid && gAgent[k].start == st) return;
    if (freeSlot < 0 && gAgent[k].pid == 0) freeSlot = k;
  }
  if (freeSlot < 0) return;
  task_t task;
  kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
  if (kr != KERN_SUCCESS) {
    logf_("pid %d (%s): task_for_pid failed (%s)%s", pid, agent_name(pid),
          mach_error_string(kr),
          sip_blocks_access() ? ": SIP Debugging Restrictions are on" : "");
    gAgent[freeSlot].pid = pid;  // not asked again while it runs
    gAgent[freeSlot].start = st;
    gAgent[freeSlot].pending = false;
    return;
  }
  char msg[300];
  int r = do_cc(task, false, msg, sizeof(msg));
  mach_port_deallocate(mach_task_self(), task);
  if (r != 1) logf_("pid %d (%s): %s", pid, agent_name(pid), msg);
  gAgent[freeSlot].pid = pid;
  gAgent[freeSlot].start = st;
  gAgent[freeSlot].pending = r == 1;
  gAgent[freeSlot].until = gTick + 500;
}
static void retry_agents(unsigned tick) {
  for (int k = 0; k < kMaxAgent; k++) {
    if (!gAgent[k].pid || !gAgent[k].pending) continue;
    task_t task;
    if (task_for_pid(mach_task_self(), gAgent[k].pid, &task) != KERN_SUCCESS) {
      gAgent[k].pending = false;
      continue;
    }
    char msg[300];
    int r = do_cc(task, false, msg, sizeof(msg));
    mach_port_deallocate(mach_task_self(), task);
    if (r != 1 || tick > gAgent[k].until) {
      logf_("pid %d (%s): %s%s", gAgent[k].pid, agent_name(gAgent[k].pid), msg,
            r == 1 ? ", gave up after 5 s" : "");
      gAgent[k].pending = false;
    }
  }
}

// launchd starts an XPC service in a fork of itself (path /sbin/launchd for
// about 1 ms), which execs xpcproxy, which execs the service binary about 11 ms
// later (seen with every core loaded). A new pid caught in one of those two
// stages is checked again on every tick until it execs the service or 2 s pass;
// before 1.2.2 it was only found by the next full scan, up to intervalMs later.
enum { kMaxNew = 64 };
static struct {
  pid_t pid;
  unsigned until;
} gNew[kMaxNew];
static bool is_spawning(pid_t pid) {
  char path[PROC_PIDPATHINFO_MAXSIZE];
  if (proc_pidpath(pid, path, sizeof(path)) <= 0) return false;
  return !strcmp(path, "/usr/libexec/xpcproxy") ||
         !strcmp(path, "/sbin/launchd");
}
static void remember_new(pid_t pid, unsigned tick) {
  for (int k = 0; k < kMaxNew; k++)
    if (!gNew[k].pid) {
      gNew[k].pid = pid;
      gNew[k].until = tick + 200;
      return;
    }
}
static void check_new(unsigned tick, bool preset, bool wide, bool cc,
                      bool hevc10) {
  for (int k = 0; k < kMaxNew; k++) {
    if (!gNew[k].pid) continue;
    bool svc = (preset || wide || hevc10) && is_service(gNew[k].pid);
    if (svc || (cc && is_agent(gNew[k].pid))) {
      if (svc)
        consider(gNew[k].pid, preset, wide, hevc10);
      else
        consider_agent(gNew[k].pid);
      gNew[k].pid = 0;
    } else if (tick > gNew[k].until || !is_spawning(gNew[k].pid))
      gNew[k].pid = 0;
  }
}

static int cmd_watch(unsigned intervalMs) {
  signal(SIGTERM, on_signal);
  signal(SIGINT, on_signal);
  char os[128];
  os_line(os, sizeof(os));
  logf_("vcnencodefix %s started on %s", VERSION, os);
  bool preset = gPreset.enabled && gPreset.available,
       wide = gWide.enabled && gWide.available,
       cc = gCc.enabled && gCc.available,
       hevc10 = gHevc10.enabled && gHevc10.available;
  if (!gPreset.enabled)
    logf_("preset: off");
  else
    logf_(preset ? "preset %s: active" : "preset: unavailable, %s",
          preset ? preset_name(gPreset.op) : gPreset.reason);
  if (!gWide.enabled)
    logf_("wide: off");
  else
    logf_(wide ? "wide: active%s" : "wide: unavailable, %s",
          wide ? "" : gWide.reason);
  if (!gCc.enabled)
    logf_("cc: off");
  else
    logf_(cc ? "cc: active%s" : "cc: unavailable, %s", cc ? "" : gCc.reason);
  if (!gHevc10.enabled)
    logf_("hevc10: off");
  else
    logf_(hevc10 ? "hevc10: active%s" : "hevc10: unavailable, %s",
          hevc10 ? "" : gHevc10.reason);
  bool accessOk = !sip_blocks_access();
  set_hevc10_gate(hevc10 && accessOk ? 1 : 0);
  if (!preset && !wide && !cc && !hevc10) {
    logf_("nothing to do on this system; exiting");
    return 0;
  }  // 0: launchd does not restart it
  if (!accessOk)
    logf_("warning: %s",
          kSipHint);  // keeps running: SIP can change at the next boot only
  // Every tick (10 ms) the pid list is compared with the previous one and only
  // new pids are looked at, so a new service is found within about 10 ms of its
  // launch (an HEVC session sends its first frame a few hundred ms later).
  // Every intervalMs the full check also runs (exited services, a read that
  // raced with dyld). This only holds if the loop gets the CPU when it wakes:
  // the launchd job is ProcessType Interactive. Under Background (priority 4,
  // up to 1.2.1) a new service was noticed 1.6 s late once while OBS started a
  // 5K encode.
  unsigned ticksPerScan = intervalMs / 10 ? intervalMs / 10 : 1;
  pid_t *prev = NULL, *cur = NULL;
  int prevN = 0, cap = 0;
  for (unsigned tick = 0; !gStop; tick++) {
    gTick = tick;
    int want = proc_listallpids(NULL, 0) + 256;
    if (want > cap) {
      pid_t* c = realloc(cur, (size_t)want * sizeof(pid_t));
      if (c) cur = c;
      pid_t* p = c ? realloc(prev, (size_t)want * sizeof(pid_t)) : NULL;
      if (p) prev = p;
      // On a failed allocation the old lists stay, and the pids that do not
      // fit wait for the next tick.
      if (c && p) cap = want;
    }
    int n = cur ? proc_listallpids(cur, cap * (int)sizeof(pid_t)) : 0;
    if (n > 0) {
      qsort(cur, (size_t)n, sizeof(pid_t), cmp_pid);
      for (int i = 0, j = 0; i < n;
           i++) {  // merge walk: pids in cur but not in prev
        while (j < prevN && prev[j] < cur[i]) j++;
        if (tick > 0 && (j >= prevN || prev[j] != cur[i])) {
          if ((preset || wide || hevc10) && is_service(cur[i]))
            consider(cur[i], preset, wide, hevc10);
          else if (cc && is_agent(cur[i]))
            consider_agent(cur[i]);
          else if (is_spawning(cur[i]))
            remember_new(cur[i], tick);
        }
      }
      pid_t* t = prev;
      prev = cur;
      cur = t;
      prevN = n;
    }
    check_new(tick, preset, wide, cc, hevc10);
    if (tick % ticksPerScan == 0) {
      for (int k = 0; k < kMaxSvc; k++)  // forget services that exited
        if (gSvc[k].pid && (kill(gSvc[k].pid, 0) != 0 ||
                            start_time(gSvc[k].pid) != gSvc[k].start))
          gSvc[k].pid = 0;
      for (int k = 0; k < kMaxAgent; k++)  // and agents
        if (gAgent[k].pid && (kill(gAgent[k].pid, 0) != 0 ||
                              start_time(gAgent[k].pid) != gAgent[k].start))
          gAgent[k].pid = 0;
      int sn;
      pid_t* pids;
      if (preset || wide || hevc10) {
        pids = list_services(&sn);
        for (int i = 0; i < sn; i++) consider(pids[i], preset, wide, hevc10);
        free(pids);
      }
      if (cc) {
        pids = list_agents(&sn);
        for (int i = 0; i < sn; i++) consider_agent(pids[i]);
        free(pids);
      }
    }
    if (cc) retry_agents(tick);
    for (int k = 0; k < kMaxSvc;
         k++) {  // services found before their memory was ready, or waiting for
                 // the plug-in
      if (!gSvc[k].pid || (!gSvc[k].widePending && !gSvc[k].presetPending &&
                           !gSvc[k].hevc10Pending))
        continue;
      task_t task;
      if (task_for_pid(mach_task_self(), gSvc[k].pid, &task) != KERN_SUCCESS) {
        gSvc[k].widePending = gSvc[k].presetPending = gSvc[k].hevc10Pending =
            false;
        continue;
      }
      if (gSvc[k].presetPending) {
        char msg[300];
        int pr = do_preset(task, false, msg, sizeof(msg));
        if (pr != 1 || tick > gSvc[k].presetUntil) {
          logf_("pid %d: %s%s", gSvc[k].pid, msg,
                pr == 1 ? ", gave up after 5 s" : "");
          gSvc[k].presetPending = false;
        }
      }
      if (gSvc[k].hevc10Pending) {
        char msg[300];
        int hr = do_hevc10(task, false, msg, sizeof(msg));
        if (hr != 1 || tick > gSvc[k].presetUntil) {
          logf_("pid %d: %s%s", gSvc[k].pid, msg,
                hr == 1 ? ", gave up after 5 s" : "");
          gSvc[k].hevc10Pending = false;
        }
      }
      if (!gSvc[k].widePending) {
        mach_port_deallocate(mach_task_self(), task);
        continue;
      }
      task_dyld_info_data_t di;
      mach_msg_type_number_t dn = TASK_DYLD_INFO_COUNT;
      uint32_t count[2] = {0, 0};
      if (task_info(task, TASK_DYLD_INFO, (task_info_t)&di, &dn) ==
              KERN_SUCCESS &&
          di.all_image_info_addr)
        rd(task, di.all_image_info_addr, count, sizeof(count));
      // re-read when the image count changes, and on every scan in case a read
      // raced with dyld
      if (count[1] != gSvc[k].lastCount || tick % ticksPerScan == 0) {
        gSvc[k].lastCount = count[1];
        char msg[300];
        int wr = do_wide(task, false, msg, sizeof(msg));
        if (wr != 1) {
          logf_("pid %d: %s", gSvc[k].pid, msg);
          gSvc[k].widePending = false;
        }
      }
      mach_port_deallocate(mach_task_self(), task);
    }
    usleep(10000);
  }
  free(prev);
  free(cur);
  if (hevc10 && accessOk) set_hevc10_gate(0);
  logf_(
      "stopped (processes already patched keep the patch "
      "until they exit)");
  return 0;
}

static void usage(void) {
  fprintf(stderr,
          "vcnencodefix %s\n"
          "usage:\n"
          "  vcnencodefix status                           what can be patched "
          "here, and the state of each process it patches\n"
          "  vcnencodefix patch <pid> [options]            patch one "
          "VTEncoderXPCService, ContinuityCaptureAgent or avconferenced "
          "(root)\n"
          "  vcnencodefix unpatch <pid> [options]          restore the "
          "original bytes in one of them (root)\n"
          "  vcnencodefix watch [options] [--interval MS]  patch every encoder "
          "service and video-call process that starts (root; the daemon)\n"
          "  vcnencodefix efi-add <config.plist>           add "
          "VCNEncodeFloor.kext to OpenCore's Kernel > Add (backup first)\n"
          "  vcnencodefix efi-remove <config.plist>        remove it again "
          "(backup first)\n"
          "  vcnencodefix efi-check <config.plist>         show whether the "
          "entry is there (read-only)\n"
          "  vcnencodefix version\n"
          "options: --preset speed|balance|quality (default speed), "
          "--no-preset, --no-wide, --no-cc, --no-hevc10\n",
          VERSION);
}

int main(int argc, char** argv) {
  setvbuf(stdout, NULL, _IOLBF, 0);
  if (argc < 2) {
    usage();
    return 2;
  }
  const char* cmd = argv[1];
  if (!strcmp(cmd, "version") || !strcmp(cmd, "--version")) {
    printf("vcnencodefix %s\n", VERSION);
    return 0;
  }
  if (!strcmp(cmd, "efi-add") || !strcmp(cmd, "efi-remove") ||
      !strcmp(cmd, "efi-check")) {
    if (argc != 3) {
      usage();
      return 2;
    }
    return efi_command(cmd + 4, argv[2]);
  }
  bool preset = true, wide = true, cc = true, hevc10 = true;
  uint32_t op = kPresetSpeed;
  unsigned interval = 250;
  pid_t pid = 0;
  int argi = 2;
  if (!strcmp(cmd, "patch") || !strcmp(cmd, "unpatch")) {
    if (argc < 3) {
      usage();
      return 2;
    }
    long v;
    if (!parse_long(argv[2], &v) || v <= 0 || v > INT32_MAX) {
      usage();
      return 2;
    }
    pid = (pid_t)v;
    argi = 3;
  } else if (strcmp(cmd, "status") && strcmp(cmd, "watch")) {
    usage();
    return 2;
  }
  for (int i = argi; i < argc; i++) {
    if (!strcmp(argv[i], "--preset") && i + 1 < argc) {
      if (parse_preset(argv[++i], &op) != 0) {
        usage();
        return 2;
      }
    } else if (!strcmp(argv[i], "--no-preset"))
      preset = false;
    else if (!strcmp(argv[i], "--no-wide"))
      wide = false;
    else if (!strcmp(argv[i], "--no-cc"))
      cc = false;
    else if (!strcmp(argv[i], "--no-hevc10"))
      hevc10 = false;
    else if (!strcmp(argv[i], "--interval") && i + 1 < argc) {
      long v;
      if (!parse_long(argv[++i], &v)) {
        usage();
        return 2;
      }
      interval = v < 20 ? 20 : v > 60000 ? 60000 : (unsigned)v;
    } else {
      usage();
      return 2;
    }
  }
  setup(preset, op, wide, cc, hevc10);
  if (!strcmp(cmd, "status")) return cmd_status();
  if (!strcmp(cmd, "watch")) {
    logFollow();
    return cmd_watch(interval);
  }
  return cmd_one(pid, !strcmp(cmd, "unpatch"));
}
