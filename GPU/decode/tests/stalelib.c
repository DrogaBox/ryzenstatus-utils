// stalelib: one plug-in's copy of common/vcnsession.c with a made-up driver,
// built twice as two libraries for staletest.c. Two copies in one process are
// what two plug-in bundles (VP9 and AV1) are: each has its own list of open
// sessions, and they find each other's sessions from before a sleep through
// the local notification center. Nothing here opens the real driver.
#include <stdlib.h>
#include <string.h>

#include "vcndriver.h"

#define EXPORT __attribute__((visibility("default")))

// The sleep mark comes from the test program, the same for both copies.
static void (*g_mark)(VcnSleepMark*);
void vcn_sleep_mark(VcnSleepMark* m) {
  if (g_mark)
    g_mark(m);
  else
    *m = (VcnSleepMark){0};
}

static int f_create_driver(void** out, AVD_DriverCreate* dc) {
  (void)dc;
  *out = calloc(1, 16);
  return 0;
}
static int f_delete_driver(void* h) {
  free(h);
  return 0;
}
static void* g_buffers[VCN_NUM_BS];
static int f_alloc(void* h, AVD_BitstreamPool* p) {
  (void)h;
  for (int i = 0; i < VCN_NUM_BS; i++) p->addressesOut[i] = &g_buffers[i];
  return 0;
}
static int f_free(void* h, uint32_t type) {
  (void)h, (void)type;
  return 0;
}
static int f_delete_ctx(void* h, AVD_DriverContextDelete* del) {
  (void)h, (void)del;
  return 0;
}
static int g_live;  // accelerators made and not destroyed
static int f_create_accel(AVD_Accelerator** out, AVD_AcceleratorCreate* in,
                          void* info) {
  (void)in, (void)info;
  AVD_Accelerator* a = calloc(1, sizeof(*a));
  a->fn[AVD_FN_CreateDriver] = (void*)f_create_driver;
  a->fn[AVD_FN_DeleteDriver] = (void*)f_delete_driver;
  a->fn[AVD_FN_DeleteContexts] = (void*)f_delete_ctx;
  a->fn[AVD_FN_AllocateBitstreamBufferPool] = (void*)f_alloc;
  a->fn[AVD_FN_FreeBitstreamBufferPool] = (void*)f_free;
  g_live++;
  *out = a;
  return 0;
}
static int f_destroy_accel(AVD_Accelerator* a) {
  free(a);
  g_live--;
  return 0;
}

EXPORT void stale_set_mark(void (*mark)(VcnSleepMark*)) { g_mark = mark; }

// Opens a session on a made-up driver; NULL, with err set, when it is refused.
EXPORT VcnDriverSession* stale_open(char* err, size_t errLen) {
  VcnDriverSession* s = calloc(1, sizeof(*s));
  VcnDriverLib lib = {.create = f_create_accel, .destroy = f_destroy_accel};
  if (!s || !vcn_session_open(s, &lib, 0, OS_LOG_DEFAULT, err, errLen)) {
    free(s);
    return NULL;
  }
  return s;
}
EXPORT void stale_close(VcnDriverSession* s) {
  vcn_session_close(s);
  free(s);
}
EXPORT int stale_live(void) { return g_live; }
