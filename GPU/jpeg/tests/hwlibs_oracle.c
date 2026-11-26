//
//  hwlibs_oracle - runs Apple's queue_jpeg_decode_2_0_build_command, the
//  function of AMDRadeonX6000HWLibs that writes the JRBC ring commands, in user
//  space and prints what it writes. tests/run.sh compares the output with the
//  frame kext/jpeg_cmds.hpp builds.
//
//  It maps the segments of the KDK binary into this process at one base and
//  calls the function there. The function only computes: it reads the ring
//  address from the queue (offset 40) and the command description, and writes
//  words to the output buffer. The commands asked for here (start, IB, fence,
//  end) call nothing outside the image except two local helpers
//  (dmu_get_lo/hi_32bit). No kext is loaded and no device is touched.
//
//  usage: hwlibs_oracle <AMDRadeonX6000HWLibs> <function address> <ring> <ib>
//  <ib bytes> <seq> <fence>
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

// _TtlBuildCommandInfo as the function reads it (JPEG-HWLIBS.md, section B).
struct info {
  uint32_t type, pad;
  uint32_t flags, a;
  uint64_t b, c;
};
typedef uint64_t (*build_fn)(void* queue, struct info* in, void* out);

static void emit(const char* name, const uint32_t* w, int n) {
  for (int i = 0; i < n; i++) printf("%s %08x\n", name, w[i]);
}

int main(int argc, char** argv) {
  if (argc != 8) {
    fprintf(stderr,
            "usage: hwlibs_oracle <binary> <function address> <ring> <ib> <ib "
            "bytes> <seq> <fence>\n");
    return 2;
  }
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
  uint8_t* base =
      mmap(NULL, span, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
  if (base == MAP_FAILED) return perror("mmap image"), 2;
  lc = (const void*)(mh + 1);
  for (uint32_t i = 0; i < mh->ncmds;
       i++, lc = (const void*)((const uint8_t*)lc + lc->cmdsize)) {
    if (lc->cmd != LC_SEGMENT_64) continue;
    const struct segment_command_64* sg = (const void*)lc;
    if (sg->filesize != 0)
      memcpy(base + sg->vmaddr, file + sg->fileoff, sg->filesize);
  }
  if (mprotect(base, span, PROT_READ | PROT_EXEC) != 0)
    return perror("mprotect"), 2;
  build_fn build = (build_fn)(base + strtoull(argv[2], NULL, 0));
  uint64_t ring = strtoull(argv[3], NULL, 0), ib = strtoull(argv[4], NULL, 0),
           fence = strtoull(argv[7], NULL, 0);
  uint32_t ibBytes = (uint32_t)strtoul(argv[5], NULL, 0),
           seq = (uint32_t)strtoul(argv[6], NULL, 0);

  uint8_t queue[208] = {0};
  memcpy(queue + 40, &ring, 8);
  uint32_t out[64];
  struct info in;

  memset(out, 0xcc, sizeof(out));
  memset(&in, 0, sizeof(in));
  in.type = 0x20007;
  build(queue, &in, out);
  emit("start", out, 4);

  memset(out, 0xcc, sizeof(out));
  memset(&in, 0, sizeof(in));
  in.type = 0x20002;
  in.flags = 1 | 2 | 4 | 8;  // template, vmid, IB address, IB size
  in.a = 0;                  // VMID 0
  in.b = ib;
  in.c = ibBytes;
  build(queue, &in, out);
  emit("ib", out, 22);

  memset(out, 0xcc, sizeof(out));
  memset(&in, 0, sizeof(in));
  in.type = 0x20003;
  in.flags = 1 | 4 | 8;  // template, sequence number, address
  in.b = seq;
  in.c = fence;
  build(queue, &in, out);
  emit("fence", out, 26);

  memset(out, 0xcc, sizeof(out));
  memset(&in, 0, sizeof(in));
  in.type = 0x20008;
  build(queue, &in, out);
  emit("end", out, 4);
  // Every command must have stayed inside the size HWLibs itself gives for it:
  // the words after it still hold the fill pattern.
  return 0;
}
