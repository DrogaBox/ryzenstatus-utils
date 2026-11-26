// gpucontrol - the GPU power limit control of GPUSensors.kext (0.5.0), and
// its read-only OD8 readout (0.6.0).
//
//   gpucontrol status                        what the control says; anyone
//   gpucontrol od8                           what the kext read of OD8 (fan
//                                            curve, clock ranges); anyone
//   gpucontrol hold [fan C:%,C:%,C:%,C:%,C:%] [zerorpm off] [gfxmax MHz]
//                   [gfxmin MHz] [volt mV] [overclock]
//                   -- <command>             holds that fan curve / zero RPM
//                                            off / lower GFX max / raised GFX
//                                            min (0.9.0) / lower GFX voltage
//                                            (0.9.0) while the command runs,
//                                            then stock (0.7.0); overclock
//                                            (0.9.0) lets gfxmax go above
//                                            stock, up to the card's maximum
//   gpucontrol check [fan ...] [zerorpm off] [gfxmax MHz] [gfxmin MHz]
//                    [volt mV] [overclock]
//                                            says whether the kext would take
//                                            it, and why not; sends nothing
//   sudo gpucontrol arm                      opens writing until restart
//   gpucontrol disarm                        closes it again (0.8.0), anyone;
//                                            refused while a change is applied
//   gpucontrol hold power <W> [raise] -- <command>
//                                            lowers the limit to W watts while
//                                            the command runs, then puts the
//                                            start-up limit back; with raise
//                                            (0.9.0) W may be above the
//                                            start-up limit, up to the card's
//                                            ceiling (PowerRange CeilW)
//
// The kext only takes the card's own minimum (PowerRange, 0.8.0) up to the
// limit the card started with (or, with raise, its ceiling), in 10 W steps,
// from one program at a time, and only after `arm`. It refuses anything else;
// this command does not clamp or retry a refused value.
//
// hold always releases: when the command ends, on Ctrl-C, SIGTERM (passed on
// to the command) or SIGHUP, and if this command is killed the kext sees the
// connection close and puts the start-up limit back by itself. While the
// command runs, hold tells the kext every 5 s that it is still there (30 s
// without that and the kext goes back). After a sleep the kext goes back by
// itself; hold then asks again for the same limit.
//
// Exit status: status, arm and disarm 0 when the kext answered ok, od8 0 when
// it read OD8, check 0 when the kext would take it; 1 when it refused or is not
// there; hold the command's own exit status, 1 when the limit was refused (the
// command is then not started), 126/127 when the command could not be started;
// 64 wrong usage.
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "control_logic.hpp"

extern char** environ;

namespace {

using namespace gpuctl;

const char* kUsage =
    "usage: gpucontrol status\n"
    "       gpucontrol od8\n"
    "       sudo gpucontrol arm\n"
    "       gpucontrol disarm\n"
    "       gpucontrol hold power <W> [raise] -- <command> [args...]\n"
    "       gpucontrol hold [fan C:%,C:%,C:%,C:%,C:%] [zerorpm off] [gfxmax "
    "MHz] [gfxmin MHz] [volt mV] [overclock]"
    " -- <command> [args...]\n"
    "       gpucontrol check [fan C:%,...] [zerorpm off] [gfxmax MHz] [gfxmin "
    "MHz] [volt mV] [overclock]\n";

volatile sig_atomic_t gSignal = 0;
// A SIGTERM has its own flag: a later Ctrl-C or hangup overwrites gSignal, and
// the SIGTERM must still be passed on to the command.
volatile sig_atomic_t gGotTerm = 0;
void onSignal(int sig) {
  if (sig == SIGTERM) gGotTerm = 1;
  gSignal = sig;
}

uint64_t monoMs() {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return static_cast<uint64_t>(ts.tv_sec) * 1000 +
         static_cast<uint64_t>(ts.tv_nsec) / 1000000;
}
void sleepMs(unsigned ms) {
  struct timespec ts = {static_cast<time_t>(ms / 1000),
                        static_cast<long>(ms % 1000) * 1000000L};
  nanosleep(&ts, nullptr);
}

struct Channel {
  io_connect_t conn = 0;

  bool open() {
    io_service_t s = IOServiceGetMatchingService(
        kIOMainPortDefault, IOServiceMatching("DrogaBoxGPUSensors"));
    if (!s) {
      fprintf(stderr,
              "GPUSensors.kext is not running (no DrogaBoxGPUSensors "
              "service)\n");
      return false;
    }
    kern_return_t kr = IOServiceOpen(s, mach_task_self(), 0, &conn);
    IOObjectRelease(s);
    if (kr != KERN_SUCCESS) {
      fprintf(stderr,
              "cannot open the control (0x%x): GPUSensors older than 0.5.0?\n",
              kr);
      conn = 0;
      return false;
    }
    return true;
  }
  ~Channel() {
    if (conn) IOServiceClose(conn);
  }
  // A call with one reply. Not Ok when the call itself failed: BadArgs.
  Reply call(uint32_t selector, uint64_t arg = 0, bool withArg = false) {
    uint64_t in[2] = {kChannelVersion, arg};
    uint64_t out[1] = {0};
    uint32_t outCount = 1;
    kern_return_t kr = IOConnectCallScalarMethod(
        conn, selector, in, withArg ? 2 : 1, out, &outCount);
    if (kr != KERN_SUCCESS || outCount < 1) return Reply::BadArgs;
    return static_cast<Reply>(out[0]);
  }
  bool status(uint64_t st[kStatusCount]) {
    uint64_t in[1] = {kChannelVersion};
    uint32_t outCount = kStatusCount;
    kern_return_t kr =
        IOConnectCallScalarMethod(conn, kSelStatus, in, 1, st, &outCount);
    return kr == KERN_SUCCESS && outCount == kStatusCount;
  }
};

const char* writeOffName(uint64_t w) {
  if (w > static_cast<uint64_t>(WriteOff::PowerWatchdog))
    return "unknown reason";
  return writeOffText(static_cast<WriteOff>(w));
}

void printRange();  // below, with the other property readers
int doStatus() {
  Channel ch;
  if (!ch.open()) return 1;
  uint64_t st[kStatusCount] = {};
  if (!ch.status(st)) {
    fprintf(stderr, "the control did not answer\n");
    return 1;
  }
  if (st[kStReply] != static_cast<uint64_t>(Reply::Ok)) {
    printf(
        "the kext speaks channel version %llu, this command %u: update "
        "one of them\n",
        st[kStVersion], kChannelVersion);
    return 1;
  }
  uint64_t f = st[kStFlags];
  printf("GPU power limit control (GPUSensors, channel %llu)\n",
         st[kStVersion]);
  if ((f & kFlagOff) &&
      st[kStWriteOff] == static_cast<uint64_t>(WriteOff::ReadOnlyCard))
    printf("  writing     never: %s\n", writeOffName(st[kStWriteOff]));
  else if (f & kFlagOff)
    printf("  writing     off until restart: %s\n",
           writeOffName(st[kStWriteOff]));
  else if (!(f & kFlagReady))
    printf(
        "  writing     waiting for the power management and its start-up "
        "limit\n");
  else if (!(f & kFlagArmed))
    printf(
        "  writing     closed (sudo gpucontrol arm opens it until "
        "restart)\n");
  else
    printf(
        "  writing     armed until restart (gpucontrol disarm closes "
        "it)\n");
  if (st[kStBootW] != 0)
    printf("  start-up    %llu W\n", st[kStBootW]);
  else
    printf("  start-up    not read yet\n");
  if (st[kStBootW] != 0)
    printf("  limit now   %llu W%s\n", st[kStHeldW],
           st[kStHeldW] != st[kStBootW] ? " (lowered)" : "");
  printRange();
  uint64_t h = st[kStOd8Held];
  if (h == 0 && !(f & kFlagOd8Ready))
    printf("  OD8         not read cleanly yet (gpucontrol od8)\n");
  else if (h == 0)
    printf("  OD8         at stock\n");
  else
    // 0.9.0: bit 64 says the held GFX maximum is above stock (overclock).
    printf("  OD8         %s%s%s%s%s%s\n",
           (h & kOd8HeldCurve) ? "fan curve " : "",
           (h & kOd8HeldZeroRpmOff) ? "zero RPM off " : "",
           !(h & kOd8HeldGfx)     ? ""
           : (h & kOd8HeldGfxUp)  ? "GFX max raised "
                                  : "GFX max lowered ",
           (h & kOd8HeldGfxMin) ? "GFX min raised " : "",
           (h & kOd8HeldVolt) ? "GFX voltage lowered " : "",
           (h & kOd8HeldUnknown) ? "not confirmed, going back to stock" : "");
  if (f & kFlagOwned) printf("  held by     a program\n");
  if (f & kFlagReverting) printf("  going back  to the start-up limit\n");
  if (f & kFlagSleeping) printf("  the Mac is between sleep and wake\n");
  printf("  since boot  %llu change(s), %llu way(s) back\n", st[kStChanges],
         st[kStReverts]);
  if (st[kStOd8Changes] != 0 || st[kStOd8Reverts] != 0)
    printf("  OD8 since   %llu change(s), %llu way(s) back\n",
           st[kStOd8Changes], st[kStOd8Reverts]);
  if (st[kStOd8Check] != 0)
    printf("  last OD8    refused: %s\n", od8CheckText(st[kStOd8Check]));
  if (st[kStChanges] != 0 || st[kStLastReply] != 0)
    printf("  last set    %s\n", replyText(st[kStLastReply]));
  return 0;
}

int doArm() {
  Channel ch;
  if (!ch.open()) return 1;
  Reply r = ch.call(kSelArm);
  printf("%s\n", r == Reply::Ok ? "armed until restart"
                                : replyText(static_cast<uint64_t>(r)));
  return r == Reply::Ok ? 0 : 1;
}
// 0.8.0. An older kext does not know the selector: IOKit refuses the call.
int doDisarm() {
  Channel ch;
  if (!ch.open()) return 1;
  uint64_t in[1] = {kChannelVersion};
  uint64_t out[1] = {0};
  uint32_t outCount = 1;
  kern_return_t kr =
      IOConnectCallScalarMethod(ch.conn, kSelDisarm, in, 1, out, &outCount);
  if (kr != KERN_SUCCESS || outCount < 1) {
    printf("the kext has no disarm (GPUSensors older than 0.8.0?)\n");
    return 1;
  }
  Reply r = static_cast<Reply>(out[0]);
  printf("%s\n", r == Reply::Ok ? "closed: sudo gpucontrol arm opens it again"
                                : replyText(static_cast<uint64_t>(r)));
  return r == Reply::Ok ? 0 : 1;
}

// Plain decimal digits only, at most 3 (the kext decides the range).
bool parseWatts(const char* text, uint32_t* out) {
  uint32_t v = 0;
  size_t n = 0;
  for (const char* p = text; *p; p++) {
    if (*p < '0' || *p > '9' || ++n > 3) return false;
    v = v * 10 + static_cast<uint32_t>(*p - '0');
  }
  if (n == 0) return false;
  *out = v;
  return true;
}

// Puts the start-up limit back and waits (5 s at most) to see it done.
void releaseAndReport(Channel& ch, bool od8) {
  Reply r = ch.call(kSelRelease);
  if (r != Reply::Ok) {
    fprintf(stderr, "gpucontrol: release: %s\n",
            replyText(static_cast<uint64_t>(r)));
    return;
  }
  uint64_t st[kStatusCount] = {};
  uint64_t until = monoMs() + 5000;
  while (monoMs() < until) {
    if (!ch.status(st)) break;
    if (st[kStFlags] & kFlagOff) {  // nothing more will be sent
      fprintf(stderr, "gpucontrol: writing is off until restart: %s%s\n",
              writeOffName(st[kStWriteOff]),
              !(st[kStFlags] & kFlagChanged) ? ""
              : od8 ? "; the fan or clock may not be at stock yet"
                    : "; the limit may still be lower than at start-up");
      return;
    }
    if (!(st[kStFlags] & (kFlagReverting | kFlagChanged))) {
      if (od8)
        fprintf(stderr, "gpucontrol: fan and clocks back at stock\n");
      else
        fprintf(stderr, "gpucontrol: back at the start-up limit, %llu W\n",
                st[kStBootW]);
      return;
    }
    sleepMs(100);
  }
  fprintf(stderr,
          "gpucontrol: released; the kext has not confirmed the way back yet "
          "(gpucontrol status)\n");
}

// What `hold` holds: a power limit, or an OD8 state (fan curve, zero RPM,
// GFX max). Never both: the kext refuses the second kind.
struct HoldReq {
  bool od8 = false;
  uint32_t watts = 0;
  bool raise = false;  // 0.9.0: watts may be above the start-up limit
  Od8Want want{};
};

// "30:20,50:40,56:60,63:80,68:100": five temperature:speed points.
bool parseCurve(const char* text, Od8Want* w) {
  const char* p = text;
  for (uint32_t k = 0; k < kOd8CurvePoints; k++) {
    char* end = nullptr;
    long t = strtol(p, &end, 10);
    if (end == p || *end != ':' || t <= 0 || t > 200) return false;
    p = end + 1;
    long s = strtol(p, &end, 10);
    if (end == p || s <= 0 || s > 200) return false;
    w->temp[k] = static_cast<int32_t>(t);
    w->speed[k] = static_cast<int32_t>(s);
    if (k + 1 < kOd8CurvePoints) {
      if (*end != ',') return false;
      p = end + 1;
    } else if (*end != '\0') {
      return false;
    }
  }
  w->curve = true;
  return true;
}
// A clock in MHz: any the 32-bit field carries; the kext checks it against
// the card's range.
bool parseMHz(const char* s, int32_t* out) {
  char* end = nullptr;
  long m = strtol(s, &end, 10);
  if (end == s || *end != '\0' || m <= 0 || m > 0x7fffffffL) return false;
  *out = static_cast<int32_t>(m);
  return true;
}
// The OD8 options: fan CURVE, zerorpm off, gfxmax MHz, gfxmin MHz (0.9.0),
// volt mV and overclock (0.9.0, one word), in any order, each once. argv
// ends at the first "--" or at the end. Returns how many words it took, 0 on
// a mistake.
int parseOd8(char** argv, int argc, Od8Want* w) {
  int i = 0;
  bool fan = false, zero = false, gfx = false, low = false, volt = false;
  while (i < argc && strcmp(argv[i], "--") != 0) {
    if (strcmp(argv[i], "overclock") == 0 && !w->overclock) {
      w->overclock = true;
      i += 1;
      continue;
    }
    if (strcmp(argv[i], "fan") == 0 && i + 1 < argc && !fan) {
      if (!parseCurve(argv[i + 1], w)) {
        fprintf(stderr,
                "gpucontrol: a fan curve is five C:%% points, for example "
                "30:25,38:50,43:70,46:85,48:100\n");
        return 0;
      }
      fan = true;
    } else if (strcmp(argv[i], "zerorpm") == 0 && i + 1 < argc && !zero &&
               strcmp(argv[i + 1], "off") == 0) {
      w->zeroRpmOff = true;
      zero = true;
    } else if (strcmp(argv[i], "gfxmax") == 0 && i + 1 < argc && !gfx) {
      if (!parseMHz(argv[i + 1], &w->gfxMaxMHz)) return 0;
      gfx = true;
    } else if (strcmp(argv[i], "gfxmin") == 0 && i + 1 < argc && !low) {
      if (!parseMHz(argv[i + 1], &w->gfxMinMHz)) return 0;
      low = true;
    } else if (strcmp(argv[i], "volt") == 0 && i + 1 < argc && !volt) {
      if (!parseMHz(argv[i + 1], &w->voltMV)) return 0;  // same bounds
      volt = true;
    } else {
      return 0;
    }
    i += 2;
  }
  // overclock alone changes nothing: it only lets gfxmax go above stock.
  return (fan || zero || gfx || low || volt) ? i : 0;
}
void describe(const HoldReq& q, char* out, size_t n) {
  if (!q.od8) {
    snprintf(out, n, "limit %u W%s", q.watts, q.raise ? " (raise)" : "");
    return;
  }
  size_t used = 0;
  out[0] = '\0';
  if (q.want.curve) {
    used += snprintf(out + used, n - used, "fan");
    for (uint32_t k = 0; k < kOd8CurvePoints && used < n; k++)
      used += snprintf(out + used, n - used, "%s%d C %d %%", k ? ", " : " ",
                       q.want.temp[k], q.want.speed[k]);
  }
  if (q.want.zeroRpmOff && used < n)
    used += snprintf(out + used, n - used, "%szero RPM off", used ? "; " : "");
  if (q.want.gfxMaxMHz != 0 && used < n)
    used += snprintf(out + used, n - used, "%sGFX max %d MHz", used ? "; " : "",
                     q.want.gfxMaxMHz);
  if (q.want.gfxMinMHz != 0 && used < n)
    used += snprintf(out + used, n - used, "%sGFX min %d MHz", used ? "; " : "",
                     q.want.gfxMinMHz);
  if (q.want.voltMV != 0 && used < n)
    used += snprintf(out + used, n - used, "%sGFX voltage %d mV",
                     used ? "; " : "", q.want.voltMV);
  if (q.want.overclock && used < n)
    snprintf(out + used, n - used, "%soverclock on", used ? "; " : "");
}
// Sends the request once. *check: why an OD8 state was refused.
Reply sendReq(Channel& ch, const HoldReq& q, uint64_t* check) {
  *check = 0;
  if (!q.od8 && !q.raise) return ch.call(kSelSet, q.watts, true);
  if (!q.od8) {
    // The raise form (0.9.0): {version, watts, raise}.
    uint64_t in[kSetWireCountRaise] = {kChannelVersion, q.watts, kSetWantRaise};
    uint64_t out[1] = {0};
    uint32_t outCount = 1;
    kern_return_t kr = IOConnectCallScalarMethod(
        ch.conn, kSelSet, in, kSetWireCountRaise, out, &outCount);
    if (kr == kIOReturnBadArgument)
      fprintf(stderr,
              "gpucontrol: this GPUSensors takes no raised limit (0.9.0 or "
              "newer does)\n");
    if (kr != KERN_SUCCESS || outCount < 1) return Reply::BadArgs;
    return static_cast<Reply>(out[0]);
  }
  uint64_t in[kOd8WireCount] = {kChannelVersion};
  in[1] = (q.want.curve ? kOd8WantCurve : 0) |
          (q.want.zeroRpmOff ? kOd8WantZeroRpmOff : 0) |
          (q.want.overclock ? kOd8WantOverclock : 0);
  for (uint32_t k = 0; k < kOd8CurvePoints; k++) {
    in[2 + k] = q.want.curve ? static_cast<uint64_t>(q.want.temp[k]) : 0;
    in[7 + k] = q.want.curve ? static_cast<uint64_t>(q.want.speed[k]) : 0;
  }
  in[12] = static_cast<uint64_t>(q.want.gfxMaxMHz);
  in[13] = static_cast<uint64_t>(q.want.gfxMinMHz);
  in[14] = static_cast<uint64_t>(q.want.voltMV);
  // The shortest form that carries the request: a 0.7.x or 0.8.x kext takes
  // only 13 scalars, a 0.9.x one 13 or 14 (both refuse more with
  // kIOReturnBadArgument).
  uint32_t count = q.want.voltMV != 0      ? kOd8WireCount
                   : q.want.gfxMinMHz != 0 ? kOd8WireCountV090
                                           : kOd8WireCountV070;
  uint64_t out[2] = {0, 0};
  uint32_t outCount = 2;
  kern_return_t kr =
      IOConnectCallScalarMethod(ch.conn, kSelSetOd8, in, count, out, &outCount);
  if (kr == kIOReturnBadArgument && count == kOd8WireCount)
    fprintf(stderr,
            "gpucontrol: this GPUSensors takes no GFX voltage (0.9.0 or "
            "newer does)\n");
  if (kr == kIOReturnBadArgument && count == kOd8WireCountV090)
    fprintf(stderr,
            "gpucontrol: this GPUSensors takes no GFX minimum (0.9.0 or "
            "newer does)\n");
  if (kr != KERN_SUCCESS || outCount < 2) return Reply::BadArgs;
  *check = out[1];
  return static_cast<Reply>(out[0]);
}
void printRefusal(const HoldReq& q, Reply r, uint64_t check) {
  char what[160];
  describe(q, what, sizeof(what));
  if (r == Reply::Od8Refused)
    fprintf(stderr, "gpucontrol: %s: refused: %s\n", what, od8CheckText(check));
  else
    fprintf(stderr, "gpucontrol: %s: %s\n", what,
            replyText(static_cast<uint64_t>(r)));
}

int doHold(const HoldReq& q, char** argv) {
  Channel ch;
  if (!ch.open()) return 1;
  uint64_t st[kStatusCount] = {};
  if (!ch.status(st) || st[kStReply] != static_cast<uint64_t>(Reply::Ok)) {
    fprintf(stderr, "gpucontrol: the kext speaks another channel version\n");
    return 1;
  }
  if (!q.od8 && st[kStBootW] != 0 && q.watts == st[kStBootW]) {
    fprintf(stderr, "gpucontrol: %u W is the start-up limit: nothing to hold\n",
            q.watts);
    return 1;
  }
  char what[160];
  describe(q, what, sizeof(what));
  // The handlers are in place before the limit changes, so a Ctrl-C from
  // here on always reaches the release below.
  struct sigaction sa = {};
  sa.sa_handler = onSignal;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGINT, &sa, nullptr);
  sigaction(SIGTERM, &sa, nullptr);
  sigaction(SIGHUP, &sa, nullptr);

  uint64_t check = 0;
  Reply r = sendReq(ch, q, &check);
  if (r != Reply::Ok) {
    printRefusal(q, r, check);
    if (r == Reply::Timeout) ch.call(kSelRelease);
    return 1;
  }
  fprintf(stderr, "gpucontrol: %s while the command runs\n", what);
  if (gSignal != 0) {
    releaseAndReport(ch, q.od8);
    return 128 + gSignal;
  }

  // The child gets the default signal dispositions back.
  posix_spawnattr_t attr;
  posix_spawnattr_init(&attr);
  sigset_t def;
  sigemptyset(&def);
  sigaddset(&def, SIGINT);
  sigaddset(&def, SIGTERM);
  sigaddset(&def, SIGHUP);
  posix_spawnattr_setsigdefault(&attr, &def);
  posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSIGDEF);
  pid_t pid = 0;
  int err = posix_spawnp(&pid, argv[0], nullptr, &attr, argv, environ);
  posix_spawnattr_destroy(&attr);
  if (err != 0) {
    fprintf(stderr, "gpucontrol: cannot start %s: %s\n", argv[0],
            strerror(err));
    releaseAndReport(ch, q.od8);
    return err == ENOENT ? 127 : 126;
  }

  bool held = true, released = false, gaveUp = false;
  uint64_t nextAlive = monoMs() + 5000;
  int wstatus = 0;
  for (;;) {
    pid_t w = waitpid(pid, &wstatus, WNOHANG);
    if (w == pid) break;
    if (w < 0 && errno != EINTR) {
      wstatus = 1 << 8;
      break;
    }
    // Ctrl-C and a hangup already reach the whole process group, the command
    // too; every SIGTERM sent to this command alone is passed on, also after
    // an earlier Ctrl-C, and also when another signal came right after it.
    // The command decides how to stop; the limit goes back at the first
    // signal.
    if (gGotTerm != 0) {
      gGotTerm = 0;
      kill(pid, SIGTERM);
    }
    int sig = gSignal;
    if (sig != 0) {
      gSignal = 0;
      if (!released) {
        releaseAndReport(ch, q.od8);
        released = true;
      }
    }
    if (!released && !gaveUp && monoMs() >= nextAlive) {
      nextAlive = monoMs() + 5000;
      if (held) {
        Reply a = ch.call(kSelAlive);
        if (a != Reply::Ok) {
          held = false;
          fprintf(stderr,
                  "gpucontrol: the kext went back to stock (sleep, or no "
                  "word for 30 s); asking for %s again\n",
                  what);
        }
      }
      if (!held) {
        uint64_t c = 0;
        Reply s = sendReq(ch, q, &c);
        if (s == Reply::Ok) {
          held = true;
          fprintf(stderr, "gpucontrol: %s again\n", what);
        } else if (s == Reply::Off || s == Reply::NotArmed ||
                   s == Reply::BadVersion || s == Reply::Failed ||
                   s == Reply::Od8Refused) {
          printRefusal(q, s, c);
          fprintf(stderr, "gpucontrol: the command goes on\n");
          gaveUp = true;  // nothing more to ask, nothing held
        }
      }
    }
    sleepMs(200);
  }
  if (!released) {
    if (held)
      releaseAndReport(ch, q.od8);
    else
      ch.call(kSelRelease);  // nothing held: the kext already went back
  }
  if (WIFEXITED(wstatus)) return WEXITSTATUS(wstatus);
  if (WIFSIGNALED(wstatus)) return 128 + WTERMSIG(wstatus);
  return 1;
}

// ------------------------------------------------------------------ od8 --
// Reads the kext's OD8 and OD8State properties (0.6.0, read only); talks to
// nothing else.

int64_t cfInt(CFDictionaryRef d, const char* key, bool* have = nullptr) {
  int64_t v = 0;
  CFStringRef k =
      CFStringCreateWithCString(nullptr, key, kCFStringEncodingUTF8);
  CFTypeRef n = k ? CFDictionaryGetValue(d, k) : nullptr;
  bool ok = n != nullptr && CFGetTypeID(n) == CFNumberGetTypeID();
  if (ok) {
    // 32-bit numbers: signed settings come as their two's complement.
    int32_t s = 0;
    CFNumberGetValue(static_cast<CFNumberRef>(n), kCFNumberSInt32Type, &s);
    v = s;
  }
  if (k) CFRelease(k);
  if (have) *have = ok;
  return v;
}
CFTypeRef cfGet(CFDictionaryRef d, const char* key, CFTypeID type) {
  CFStringRef k =
      CFStringCreateWithCString(nullptr, key, kCFStringEncodingUTF8);
  CFTypeRef v = k ? CFDictionaryGetValue(d, k) : nullptr;
  if (k) CFRelease(k);
  return v != nullptr && CFGetTypeID(v) == type ? v : nullptr;
}
void printCurve(const char* label, CFDictionaryRef od8, const char* key) {
  auto a = static_cast<CFArrayRef>(cfGet(od8, key, CFArrayGetTypeID()));
  if (a == nullptr) return;
  printf("  %-10s", label);
  for (CFIndex i = 0; i < CFArrayGetCount(a); i++) {
    auto p = static_cast<CFArrayRef>(CFArrayGetValueAtIndex(a, i));
    if (CFGetTypeID(p) != CFArrayGetTypeID() || CFArrayGetCount(p) != 2)
      continue;
    CFTypeRef tv = CFArrayGetValueAtIndex(p, 0);
    CFTypeRef sv = CFArrayGetValueAtIndex(p, 1);
    if (CFGetTypeID(tv) != CFNumberGetTypeID() ||
        CFGetTypeID(sv) != CFNumberGetTypeID())
      continue;
    int32_t t = 0, s = 0;
    CFNumberGetValue(static_cast<CFNumberRef>(tv), kCFNumberSInt32Type, &t);
    CFNumberGetValue(static_cast<CFNumberRef>(sv), kCFNumberSInt32Type, &s);
    printf("%s%d C %d %%", i ? ", " : " ", t, s);
  }
  printf("\n");
}

// One property of GPUSensors, retained, from a copy of the whole table. The
// kext brings its properties up to date only when the whole table is read;
// reading one key returns what the last whole read left (minutes old).
CFTypeRef copyFresh(io_service_t s, CFStringRef key) {
  CFMutableDictionaryRef props = nullptr;
  if (IORegistryEntryCreateCFProperties(s, &props, kCFAllocatorDefault, 0) !=
          KERN_SUCCESS ||
      props == nullptr)
    return nullptr;
  CFTypeRef v = CFDictionaryGetValue(props, key);
  if (v) CFRetain(v);
  CFRelease(props);
  return v;
}

// The card's power range (0.8.0): PowerRange and PowerRangeState.
void printRange() {
  io_service_t s = IOServiceGetMatchingService(
      kIOMainPortDefault, IOServiceMatching("DrogaBoxGPUSensors"));
  if (s == IO_OBJECT_NULL) return;
  CFTypeRef state = copyFresh(s, CFSTR("PowerRangeState"));
  CFTypeRef range = copyFresh(s, CFSTR("PowerRange"));
  IOObjectRelease(s);
  char text[256] = "not published (GPUSensors older than 0.8.0?)";
  if (state && CFGetTypeID(state) == CFStringGetTypeID())
    CFStringGetCString(static_cast<CFStringRef>(state), text, sizeof(text),
                       kCFStringEncodingUTF8);
  bool haveFloor = false, haveCeil = false;
  int64_t floorW = 0, maxW = 0, ceilW = 0;
  if (range && CFGetTypeID(range) == CFDictionaryGetTypeID()) {
    auto d = static_cast<CFDictionaryRef>(range);
    floorW = cfInt(d, "FloorW", &haveFloor);
    maxW = cfInt(d, "MaxW");
    ceilW = cfInt(d, "CeilW", &haveCeil);
  }
  if (haveFloor)
    printf("  range       %lld-%lld W in 10 W steps (%s)\n", floorW, maxW,
           text);
  else
    printf("  range       %s\n", text);
  if (haveFloor && haveCeil && ceilW > maxW)
    printf(
        "  raise       up to %lld W with hold power <W> raise (the card's "
        "own power percent)\n",
        ceilW);
  if (state) CFRelease(state);
  if (range) CFRelease(range);
}
int doOd8() {
  io_service_t s = IOServiceGetMatchingService(
      kIOMainPortDefault, IOServiceMatching("DrogaBoxGPUSensors"));
  if (s == IO_OBJECT_NULL) {
    fprintf(stderr, "gpucontrol: GPUSensors is not running\n");
    return 1;
  }
  CFTypeRef state = copyFresh(s, CFSTR("OD8State"));
  CFTypeRef od8 = copyFresh(s, CFSTR("OD8"));
  IOObjectRelease(s);
  char text[256] = "not published (GPUSensors older than 0.6.0?)";
  if (state && CFGetTypeID(state) == CFStringGetTypeID())
    CFStringGetCString(static_cast<CFStringRef>(state), text, sizeof(text),
                       kCFStringEncodingUTF8);
  printf("GPU OD8 (GPUSensors, read only)\n  state       %s\n", text);
  // 0 only when the kext read OD8 (its state starts with "read").
  int rc = strncmp(text, "read", 4) == 0 ? 0 : 1;
  if (od8 && CFGetTypeID(od8) == CFDictionaryGetTypeID()) {
    auto d = static_cast<CFDictionaryRef>(od8);
    printf("  reads       %lld complete, %lld tries, last answer 0x%llx\n",
           cfInt(d, "Reads"), cfInt(d, "Tries"),
           static_cast<unsigned long long>(
               static_cast<uint32_t>(cfInt(d, "LastResult"))));
    bool haveOdd = false;
    int64_t odd = cfInt(d, "OddEntry", &haveOdd);
    if (haveOdd)
      printf("  NOT AS EXPECTED: word %lld of escape 0x%llx\n", odd,
             static_cast<unsigned long long>(cfInt(d, "OddEscape")));
    bool haveCaps = false;
    int64_t caps = cfInt(d, "Caps", &haveCaps);
    if (haveCaps) {
      printf("  caps        0x%x, not allowed now 0x%x\n",
             static_cast<uint32_t>(caps),
             static_cast<uint32_t>(cfInt(d, "NotAllowed")));
      printf("  since boot  defaults %s, current values %s\n",
             cfInt(d, "DefaultsMoved") ? "MOVED" : "the same",
             cfInt(d, "CurrentMoved") ? "MOVED" : "the same");
      printf("  last read   %lld s ago%s\n", cfInt(d, "LastReadAgeS"),
             cfInt(d, "StockOdd")
                 ? "; STOCK came from a read that was not as expected"
                 : "");
    }
    auto all = static_cast<CFDictionaryRef>(
        cfGet(d, "Settings", CFDictionaryGetTypeID()));
    if (all) {
      printf("  %-17s %8s %6s %6s %6s %6s\n", "setting", "feature", "min",
             "max", "stock", "now");
      for (uint32_t i = 0; i < kOd8Count; i++) {
        auto e = static_cast<CFDictionaryRef>(
            cfGet(all, od8Name(i), CFDictionaryGetTypeID()));
        if (e == nullptr) continue;
        uint32_t f = static_cast<uint32_t>(cfInt(e, "Feature"));
        char fs[16];
        if (f)
          snprintf(fs, sizeof(fs), "0x%x", f);
        else
          snprintf(fs, sizeof(fs), "hidden");
        printf("  %-17s %8s %6lld %6lld %6lld %6lld\n", od8Name(i), fs,
               cfInt(e, "Min"), cfInt(e, "Max"), cfInt(e, "Stock"),
               cfInt(e, "Current"));
      }
    }
    printCurve("fan stock", d, "FanCurveStock");
    printCurve("fan now", d, "FanCurve");
  }
  if (state) CFRelease(state);
  if (od8) CFRelease(od8);
  return rc;
}

// `gpucontrol check ...`: the kext's own checks (control_logic.hpp), run here
// on what the kext published in OD8. Sends nothing.
int doCheck(const Od8Want& want) {
  io_service_t s = IOServiceGetMatchingService(
      kIOMainPortDefault, IOServiceMatching("DrogaBoxGPUSensors"));
  if (s == IO_OBJECT_NULL) {
    fprintf(stderr, "gpucontrol: GPUSensors is not running\n");
    return 1;
  }
  CFTypeRef od8 = copyFresh(s, CFSTR("OD8"));
  IOObjectRelease(s);
  auto d = od8 && CFGetTypeID(od8) == CFDictionaryGetTypeID()
               ? static_cast<CFDictionaryRef>(od8)
               : nullptr;
  auto all = d ? static_cast<CFDictionaryRef>(
                     cfGet(d, "Settings", CFDictionaryGetTypeID()))
               : nullptr;
  if (all == nullptr) {
    fprintf(stderr, "gpucontrol: no OD8 read published (gpucontrol od8)\n");
    if (od8) CFRelease(od8);
    return 1;
  }
  Od8InitialOut first{}, fresh{};
  Od8CurrentOut cur{};
  first.count = fresh.count = cur.count = kOd8Count;
  first.caps = fresh.caps = static_cast<uint32_t>(cfInt(d, "Caps"));
  cur.notAllowed = static_cast<uint32_t>(cfInt(d, "NotAllowed"));
  for (uint32_t i = 0; i < kOd8Count; i++) {
    auto e = static_cast<CFDictionaryRef>(
        cfGet(all, od8Name(i), CFDictionaryGetTypeID()));
    if (e == nullptr) continue;
    Od8Entry x{static_cast<uint32_t>(cfInt(e, "Feature")),
               static_cast<int32_t>(cfInt(e, "Min")),
               static_cast<int32_t>(cfInt(e, "Max")),
               static_cast<int32_t>(cfInt(e, "Stock")),
               0,
               0};
    first.e[i] = x;
    bool haveDefault = false;
    int64_t def = cfInt(e, "Default", &haveDefault);
    x.def = haveDefault ? static_cast<int32_t>(def) : x.def;
    fresh.e[i] = x;
    cur.cur[i] = static_cast<int32_t>(cfInt(e, "Current"));
  }
  CFRelease(od8);
  Od8Check c = od8CheckWant(want, first, fresh, cur);
  HoldReq q;
  q.od8 = true;
  q.want = want;
  char what[160];
  describe(q, what, sizeof(what));
  if (c == Od8Check::Ok) {
    printf("%s: the kext would take it\n", what);
    return 0;
  }
  printf("%s: refused: %s\n", what, od8CheckText(static_cast<uint64_t>(c)));
  if (c == Od8Check::CurveLast || c == Od8Check::CurveCooling) {
    int32_t target = first.e[kOd8TargetTemp].def;
    printf(
        "  the curve must reach 100 %% at %d C or below (target %d C - %d C "
        "for the sensor gap), start at %d C or below, and give at least the "
        "stock curve's air:",
        target - kOd8SensorGapC, target, kOd8SensorGapC, kOd8FirstPointMaxC);
    for (uint32_t k = 0; k < kOd8CurvePoints; k++)
      printf("%s%d C %d %%", k ? "," : " ", first.e[od8CurveTempId(k)].def,
             first.e[od8CurveSpeedId(k)].def);
    printf("\n");
  }
  return 1;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc == 2 && strcmp(argv[1], "status") == 0) return doStatus();
  if (argc == 2 && strcmp(argv[1], "arm") == 0) return doArm();
  if (argc == 2 && strcmp(argv[1], "disarm") == 0) return doDisarm();
  if (argc == 2 && strcmp(argv[1], "od8") == 0) return doOd8();
  if (argc >= 6 && strcmp(argv[1], "hold") == 0 &&
      strcmp(argv[2], "power") == 0 &&
      (strcmp(argv[4], "--") == 0 ||
       (argc >= 7 && strcmp(argv[4], "raise") == 0 &&
        strcmp(argv[5], "--") == 0))) {
    HoldReq q;
    if (!parseWatts(argv[3], &q.watts)) {
      fprintf(stderr, "gpucontrol: %s is not a number of watts\n", argv[3]);
      return 64;
    }
    q.raise = strcmp(argv[4], "raise") == 0;
    return doHold(q, argv + (q.raise ? 6 : 5));
  }
  if (argc >= 5 && strcmp(argv[1], "hold") == 0) {
    HoldReq q;
    q.od8 = true;
    int n = parseOd8(argv + 2, argc - 2, &q.want);
    if (n > 0 && 2 + n + 1 < argc && strcmp(argv[2 + n], "--") == 0)
      return doHold(q, argv + 2 + n + 1);
  }
  if (argc >= 4 && strcmp(argv[1], "check") == 0) {
    Od8Want w{};
    int n = parseOd8(argv + 2, argc - 2, &w);
    if (n > 0 && 2 + n == argc) return doCheck(w);
  }
  fputs(kUsage, stderr);
  return 64;
}
