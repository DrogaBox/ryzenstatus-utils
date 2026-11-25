// staletest: two plug-ins in one process (two copies of common/vcnsession.c,
// libstale-a and libstale-b, built from stalelib.c) with a made-up driver and a
// made-up sleep. A session of one that opened before a sleep and is still open
// stops the other from opening one, as the VP9 sessions of a browser's decoder
// process should have stopped the AV1 session it opened after the wake; once
// it is closed, the other opens again. Without a sleep both open side by side.
//
// usage: staletest <libstale-a.dylib> <libstale-b.dylib>. Exit status 0 = pass.
#include <dlfcn.h>
#include <stdio.h>

#include "vcndriver.h"

static VcnSleepMark g_now = {.asleepNs = 1000000000ull, .wakeUs = 1};
static void mark(VcnSleepMark* m) { *m = g_now; }

typedef struct {
  void (*setMark)(void (*)(VcnSleepMark*));
  VcnDriverSession* (*open)(char*, size_t);
  void (*close)(VcnDriverSession*);
  int (*live)(void);
} Lib;

static bool load(const char* path, Lib* l) {
  void* h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (!h) {
    printf("FAIL cannot load %s: %s\n", path, dlerror());
    return false;
  }
  l->setMark = dlsym(h, "stale_set_mark");
  l->open = dlsym(h, "stale_open");
  l->close = dlsym(h, "stale_close");
  l->live = dlsym(h, "stale_live");
  if (!l->setMark || !l->open || !l->close || !l->live) {
    printf("FAIL %s lacks its functions\n", path);
    return false;
  }
  l->setMark(mark);
  return true;
}

static int failures;
static void expect(const char* what, bool ok) {
  printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) failures++;
}

int main(int argc, char** argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: staletest <libstale-a.dylib> <libstale-b.dylib>\n");
    return 1;
  }
  Lib a, b;
  if (!load(argv[1], &a) || !load(argv[2], &b)) return 1;
  char err[256] = "";
  VcnDriverSession* sa = a.open(err, sizeof(err));
  VcnDriverSession* sb = b.open(err, sizeof(err));
  expect("without a sleep, both plug-ins open a session", sa && sb);
  if (sb) b.close(sb);
  g_now.asleepNs += 20000000000ull;  // a 20 s sleep
  g_now.wakeUs += 1;
  err[0] = 0;
  sb = b.open(err, sizeof(err));
  printf("     refused: %s\n", err);
  expect(
      "after it, one plug-in's session from before the sleep, still open, "
      "stops the other from opening one, before it opens anything",
      sa && !sb && b.live() == 0);
  if (sb) b.close(sb);
  VcnDriverSession* sa2 = a.open(err, sizeof(err));
  expect("and the same plug-in from opening another", sa && !sa2);
  if (sa2) a.close(sa2);
  if (sa) a.close(sa);
  expect("its close (without the driver's teardown) frees the accelerator",
         a.live() == 0);
  sb = b.open(err, sizeof(err));
  sa2 = a.open(err, sizeof(err));
  expect("once it is closed, both open sessions again", sb && sa2);
  if (sb) b.close(sb);
  if (sa2) a.close(sa2);
  expect("and close them", a.live() == 0 && b.live() == 0);
  return failures ? 1 : 0;
}
