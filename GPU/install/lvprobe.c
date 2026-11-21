// lvprobe - asks the kernel whether macOS would let a protected program, such
// as Safari's media process, load a Mach-O file. It makes the two fcntl calls
// dyld makes before it maps a library (F_ADDFILESIGS_RETURN, then F_CHECK_LV)
// and stops there: the file is never loaded and none of its code runs.
//
// The answer is about library validation, the check that refuses the decoder
// plug-ins when nothing on the Mac vouches for them. The program must itself be
// signed with the library-validation flag (decode/build.sh does it: codesign
// -s - -o library), or the kernel says yes to everything; it checks that first.
//
//   lvprobe <mach-o file> ...
// One line per file: "allowed <file>", "refused <file>: <reason>" or
// "error   <file>: <why it could not be checked>".
// Exit status: 0 all allowed, 1 some refused, 2 could not check.

#include <fcntl.h>
#include <mach-o/loader.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int csops(pid_t pid, unsigned int ops, void* useraddr, size_t usersize);
#define CS_OPS_STATUS 0
#define CS_REQUIRE_LV 0x00002000u
#define CS_RUNTIME 0x00010000u

static int probe(const char* path) {
  int fd = open(path, O_RDONLY);
  if (fd < 0) {
    printf("error   %s: cannot open\n", path);
    return 2;
  }
  struct mach_header_64 mh;
  if (pread(fd, &mh, sizeof(mh), 0) != (ssize_t)sizeof(mh) ||
      mh.magic != MH_MAGIC_64 || mh.sizeofcmds > 1 << 20) {
    printf("error   %s: not a thin 64-bit Mach-O\n", path);
    close(fd);
    return 2;
  }
  static uint8_t cmds[1 << 20];
  if (pread(fd, cmds, mh.sizeofcmds, sizeof(mh)) != (ssize_t)mh.sizeofcmds) {
    printf("error   %s: cannot read the load commands\n", path);
    close(fd);
    return 2;
  }
  uint32_t sigoff = 0, sigsize = 0;
  const uint8_t* p = cmds;
  const uint8_t* end = cmds + mh.sizeofcmds;
  for (uint32_t i = 0; i < mh.ncmds && p + sizeof(struct load_command) <= end;
       i++) {
    const struct load_command* lc = (const struct load_command*)p;
    if (lc->cmdsize < sizeof(*lc) || p + lc->cmdsize > end) break;
    if (lc->cmd == LC_CODE_SIGNATURE &&
        lc->cmdsize >= sizeof(struct linkedit_data_command)) {
      const struct linkedit_data_command* cs =
          (const struct linkedit_data_command*)p;
      sigoff = cs->dataoff;
      sigsize = cs->datasize;
    }
    p += lc->cmdsize;
  }
  if (sigsize == 0) {
    printf("refused %s: the file has no code signature\n", path);
    close(fd);
    return 1;
  }
  fsignatures_t sig;
  memset(&sig, 0, sizeof(sig));
  sig.fs_file_start = 0;
  sig.fs_blob_start = (void*)(uintptr_t)sigoff;
  sig.fs_blob_size = sigsize;
  if (fcntl(fd, F_ADDFILESIGS_RETURN, &sig) == -1) {
    printf("refused %s: the kernel does not accept its code signature\n", path);
    close(fd);
    return 1;
  }
  char msg[512] = "";
  fchecklv_t lv;
  memset(&lv, 0, sizeof(lv));
  lv.lv_file_start = 0;
  lv.lv_error_message_size = sizeof(msg);
  lv.lv_error_message = msg;
  int r = fcntl(fd, F_CHECK_LV, &lv);
  close(fd);
  if (r == 0) {
    printf("allowed %s\n", path);
    return 0;
  }
  msg[sizeof(msg) - 1] = 0;
  printf("refused %s: %s\n", path, msg[0] ? msg : "library validation");
  return 1;
}

int main(int argc, char** argv) {
  uint32_t flags = 0;
  if (csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags)) != 0 ||
      !(flags & CS_REQUIRE_LV)) {
    printf(
        "error   this program runs without library validation (flags 0x%08x): "
        "sign it with -o library\n",
        flags);
    return 2;
  }
  if (argc < 2) {
    printf("usage: lvprobe <mach-o file> ...\n");
    return 2;
  }
  int worst = 0;
  for (int i = 1; i < argc; i++) {
    int r = probe(argv[i]);
    if (r > worst) worst = r;
  }
  return worst;
}
