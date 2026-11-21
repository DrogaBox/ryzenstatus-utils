// waittest: vcn_wait_command against a made-up QueryAVDCommandStatus, on the
// CPU. A real GPU cannot be made to hang on purpose, so this is the only check
// of the timeout. Exit status 1 when a case fails.
#include <stdio.h>

#include "vcndriver.h"

static int failures;
static int calls, doneAfter, returnValue, oddStatus;
static unsigned firmware;

// Answers like the 25G342 driver: wait = 0 gives status 2 until the command is
// done, then 1; wait != 0 is only sent once done and fills status2.
static int fake_query(void* driver, AVD_QueryList* q) {
  (void)driver;
  calls++;
  if (returnValue) return returnValue;
  AVD_QueryEntry* e = q->entries;
  if (q->count != 1 || e->refcon != (void*)0x1234) return 5;
  if (oddStatus) {
    e->status = (uint32_t)oddStatus;
    return 0;
  }
  bool done = doneAfter >= 0 && calls > doneAfter;
  if (e->wait && !done) return 99;  // the real one would block here
  e->status = done ? 1 : 2;
  e->status2 = e->wait ? firmware : 0;
  return 0;
}

static void run(const char* name, int after, int ret, int odd, unsigned fw,
                unsigned timeoutMs, VcnWaitResult want, unsigned wantHw,
                int wantDriver) {
  calls = 0, doneAfter = after, returnValue = ret, oddStatus = odd;
  firmware = fw;
  uint32_t hw = 77;
  int ds = 77;
  VcnWaitResult got =
      vcn_wait_command(fake_query, NULL, (void*)0x1234, timeoutMs, &hw, &ds);
  bool ok = got == want && hw == wantHw && ds == wantDriver;
  printf("%s %s (result %d, firmware %u, driver %d, %d queries)\n",
         ok ? "ok  " : "FAIL", name, (int)got, hw, ds, calls);
  if (!ok) failures++;
}

int main(void) {
  run("done at once", 0, 0, 0, 0, 1000, VCN_WAIT_DONE, 0, 0);
  run("done after a few looks", 5, 0, 0, 0, 1000, VCN_WAIT_DONE, 0, 0);
  run("firmware result passed on", 2, 0, 0, 6, 1000, VCN_WAIT_DONE, 6, 0);
  run("never done: times out", -1, 0, 0, 0, 50, VCN_WAIT_TIMEOUT, 0, 0);
  run("driver error", 0, 7, 0, 0, 1000, VCN_WAIT_FAILED, 0, 7);
  run("unexpected status", 0, 0, 3, 0, 1000, VCN_WAIT_FAILED, 0, 3);
  return failures ? 1 : 0;
}
