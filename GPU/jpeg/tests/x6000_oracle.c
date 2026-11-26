//
//  x6000_oracle - runs the two functions of Apple's AMDRadeonX6000 that build
//  PowerPlay requests in the kernel, in user space, and prints the requests
//  they hand to sendPMCommand:
//
//    AMDAccelVCNContext::setClocks()            the PMRequest (escape 0x53) of
//    a video session AMDAccelVideoContext::notifyPMContext()    ActivateClient
//    (escape 0x34)
//
//  tests/run.sh compares them, with the JPEG client type, with what
//  kext/jpeg_power.hpp builds.
//
//  The KDK binary's segments are mapped into this process. Inside the two
//  functions every call is replaced before anything runs: the call to
//  AMDGraphicsAccelerator::sendPMCommand goes to capture() below, which copies
//  the request; __bzero goes to a local bzero; IOLockLock / IOLockUnlock to a
//  function that does nothing. The objects passed as "this" are plain zeroed
//  buffers with only the fields the functions read filled in. No kext is loaded
//  and no device is touched.
//
//  usage: x6000_oracle <AMDRadeonX6000> <sendPMCommand> setclocks <function>
//  <length> <client type> <context>
//                      <site>:<bzero|nop> ...
//         x6000_oracle <AMDRadeonX6000> <sendPMCommand> notify <function>
//         <length> <client type> <context>
//                      <activate> <site>:<bzero|nop> ...
//  A site is the address of the 4-byte operand of an external call, as `otool
//  -rv` lists it.
//
#include <fcntl.h>
#include <mach-o/loader.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

struct args {
  const void* in;
  uint64_t inSize;
  void* out;
  uint64_t* outSize;
};
static uint8_t gIn[512];
static uint64_t gInSize, gOutSize;
static int gHasOut, gCalls;
static void* gAccelSeen;

static uint32_t capture(void* accel, struct args* a) {
  gCalls++;
  gAccelSeen = accel;
  gInSize = a->inSize;
  if (a->inSize <= sizeof(gIn)) memcpy(gIn, a->in, a->inSize);
  gHasOut = a->out != NULL;
  gOutSize = a->outSize ? *a->outSize : ~0ull;
  return 0;
}
static void my_bzero(void* p, size_t n) { memset(p, 0, n); }
static void nothing(void) {}

// movabs rax, target; jmp rax
static uint8_t* trampoline(uint8_t* at, void* target) {
  at[0] = 0x48;
  at[1] = 0xb8;
  memcpy(at + 2, &target, 8);
  at[10] = 0xff;
  at[11] = 0xe0;
  return at;
}
static int patch_call(uint8_t* base, uint64_t operand, uint8_t* tramp) {
  if (base[operand - 1] != 0xe8) return 0;  // must be a call rel32
  int32_t rel = (int32_t)(tramp - (base + operand + 4));
  memcpy(base + operand, &rel, 4);
  return 1;
}

int main(int argc, char** argv) {
  if (argc < 8)
    return fprintf(stderr, "usage: see the head of x6000_oracle.c\n"), 2;
  int notify = !strcmp(argv[3], "notify");
  int fd = open(argv[1], O_RDONLY);
  struct stat st;
  if (fd < 0 || fstat(fd, &st) != 0) return perror(argv[1]), 2;
  uint8_t* file = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
  if (file == MAP_FAILED) return perror("mmap"), 2;
  const struct mach_header_64* mh = (const void*)file;
  if (mh->magic != MH_MAGIC_64 || mh->cputype != CPU_TYPE_X86_64)
    return fprintf(stderr, "not a thin x86_64 Mach-O\n"), 2;
  uint64_t span = 0;
  const struct load_command* lc = (const void*)(mh + 1);
  for (uint32_t i = 0; i < mh->ncmds;
       i++, lc = (const void*)((const uint8_t*)lc + lc->cmdsize)) {
    if (lc->cmd != LC_SEGMENT_64) continue;
    const struct segment_command_64* sg = (const void*)lc;
    if (sg->vmaddr + sg->vmsize > span) span = sg->vmaddr + sg->vmsize;
  }
  span = (span + 0xfff) & ~0xfffull;
  uint8_t* base = mmap(NULL, span + 0x1000, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANON, -1, 0);
  if (base == MAP_FAILED) return perror("mmap image"), 2;
  lc = (const void*)(mh + 1);
  for (uint32_t i = 0; i < mh->ncmds;
       i++, lc = (const void*)((const uint8_t*)lc + lc->cmdsize)) {
    if (lc->cmd != LC_SEGMENT_64) continue;
    const struct segment_command_64* sg = (const void*)lc;
    if (sg->filesize != 0)
      memcpy(base + sg->vmaddr, file + sg->fileoff, sg->filesize);
  }
  uint8_t* page = base + span;  // trampolines live right after the image
  uint8_t* tCapture = trampoline(page, capture);
  uint8_t* tBzero = trampoline(page + 16, my_bzero);
  uint8_t* tNothing = trampoline(page + 32, nothing);

  uint64_t sendPM = strtoull(argv[2], NULL, 0), fn = strtoull(argv[4], NULL, 0),
           len = strtoull(argv[5], NULL, 0);
  uint32_t clientType = (uint32_t)strtoul(argv[6], NULL, 0);
  uint64_t context = strtoull(argv[7], NULL, 0);
  int first = notify ? 9 : 8;
  // every call inside the function: to sendPMCommand -> capture; the listed
  // external ones -> their stand-in
  int toSend = 0, calls = 0, patched = 0;
  for (uint64_t a = fn; a + 5 <= fn + len; a++) {
    if (base[a] != 0xe8) continue;
    int32_t rel;
    memcpy(&rel, base + a + 1, 4);
    if (a + 5 + (int64_t)rel == sendPM) {
      toSend += patch_call(base, a + 1, tCapture);
      a += 4;
    }
  }
  for (int i = first; i < argc; i++) {
    char* colon = strchr(argv[i], ':');
    if (!colon) return fprintf(stderr, "bad site %s\n", argv[i]), 2;
    uint64_t site = strtoull(argv[i], NULL, 16);
    if (site < fn || site >= fn + len)
      return fprintf(stderr, "site %s is outside the function\n", argv[i]), 2;
    calls++;
    patched +=
        patch_call(base, site, !strcmp(colon + 1, "bzero") ? tBzero : tNothing);
  }
  if (toSend != 1 || patched != calls)
    return fprintf(stderr,
                   "calls not as expected: %d to sendPMCommand, %d of %d "
                   "external patched\n",
                   toSend, patched, calls),
           2;
  if (mprotect(base, span + 0x1000, PROT_READ | PROT_EXEC) != 0)
    return perror("mprotect"), 2;

  static uint8_t accel[8192], self[8192], lock[64];
  if (!notify) {
    // AMDAccelVCNContext: +56 accelerator, +104 client type, +112 context
    // handle, +128/+136/+140 clock fields (0)
    void* p = accel;
    memcpy(self + 56, &p, 8);
    memcpy(self + 104, &clientType, 4);
    memcpy(self + 112, &context, 8);
    ((uint64_t (*)(void*))(base + fn))(self);
  } else {
    // AMDAccelVideoContext: +1448 accelerator, +4552 lock
    void* p = accel;
    void* l = lock;
    memcpy(self + 1448, &p, 8);
    memcpy(self + 4552, &l, 8);
    uint32_t activate = (uint32_t)strtoul(argv[8], NULL, 0);
    ((uint64_t (*)(void*, uint32_t, uint32_t, uint64_t, uint32_t, uint32_t))(
        base + fn))(self, clientType, 0, context, activate, 0);
  }
  if (gCalls != 1 || gAccelSeen != (void*)accel || gInSize > sizeof(gIn))
    return fprintf(stderr, "sendPMCommand was not called once as expected\n"),
           1;
  printf("insize %llu\nhasout %d\noutsize %llu\n", gInSize, gHasOut, gOutSize);
  for (uint64_t i = 0; i < gInSize; i += 4) {
    uint32_t w;
    memcpy(&w, gIn + i, 4);
    printf("%08x\n", w);
  }
  return 0;
}
