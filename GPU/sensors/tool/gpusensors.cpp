// gpusensors - shows the GPU sensor readings published by GPUSensors.kext.
//
//   gpusensors                  one reading, as a table
//   gpusensors --json           the same as one JSON object
//   gpusensors --watch [secs]   a new table every secs seconds (default 1)
//   gpusensors --compare        the readings that macOS also publishes in
//                               PerformanceStatistics, side by side, to check
//                               the kext's names and units against Apple's
//
// It only reads the I/O Registry, like ioreg: nothing is sent to the GPU or to
// the kext. Without the kext it shows what macOS publishes by itself and says
// that the rest needs GPUSensors.kext.
//
// Exit status: 0 readings shown; 1 the kext is not running or has no reading
// yet (what macOS publishes is still shown); 64 wrong usage.
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "pmlog_logic.hpp"

namespace {

// The kext brings its properties up to date when the whole property table is
// asked for (as ioreg -l does). Asking for one property returns what the last
// such read left, which can be minutes old, so every property is taken from
// one copy of the table: one moment, all of it fresh.
CFDictionaryRef copyProperties(const char* cls) {
  io_service_t s =
      IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(cls));
  if (!s) return nullptr;
  CFMutableDictionaryRef props = nullptr;
  if (IORegistryEntryCreateCFProperties(s, &props, kCFAllocatorDefault, 0) !=
      KERN_SUCCESS)
    props = nullptr;
  IOObjectRelease(s);
  return props;
}

// A value of a dictionary, retained, or nullptr.
CFTypeRef copyValue(CFDictionaryRef d, const char* key) {
  if (!d) return nullptr;
  CFStringRef k =
      CFStringCreateWithCString(nullptr, key, kCFStringEncodingUTF8);
  CFTypeRef v = CFDictionaryGetValue(d, k);
  CFRelease(k);
  if (v) CFRetain(v);
  return v;
}

bool dictNumber(CFTypeRef d, const char* key, long long* out) {
  if (!d || CFGetTypeID(d) != CFDictionaryGetTypeID()) return false;
  CFStringRef k =
      CFStringCreateWithCString(nullptr, key, kCFStringEncodingUTF8);
  CFTypeRef v = CFDictionaryGetValue((CFDictionaryRef)d, k);
  CFRelease(k);
  if (!v || CFGetTypeID(v) != CFNumberGetTypeID()) return false;
  return CFNumberGetValue((CFNumberRef)v, kCFNumberLongLongType, out);
}

bool string(CFTypeRef v, char* out, size_t cap) {
  return v && CFGetTypeID(v) == CFStringGetTypeID() &&
         CFStringGetCString((CFStringRef)v, out, (CFIndex)cap,
                            kCFStringEncodingUTF8);
}

bool number(CFTypeRef v, long long* out) {
  return v && CFGetTypeID(v) == CFNumberGetTypeID() &&
         CFNumberGetValue((CFNumberRef)v, kCFNumberLongLongType, out);
}

// What macOS publishes by itself, and the PMLog id each key comes from
// (AMDRadeonX6000_AMDHardware::samplePMStatistics).
struct Apple {
  const char* key;
  uint16_t id;
};
constexpr Apple kApple[] = {
    {"Core Clock(MHz)", 1}, {"Memory Clock(MHz)", 2}, {"Fan Speed(RPM)", 14},
    {"Fan Speed(%)", 15},   {"GPU Activity(%)", 19},  {"Total Power(W)", 23},
    {"Temperature(C)", 27},
};

// macOS's own readings. Every accelerator publishes PerformanceStatistics (an
// Intel iGPU too, with other keys), so the first one with AMD's keys is used.
CFTypeRef copyApplePerf() {
  io_iterator_t it = 0;
  if (IOServiceGetMatchingServices(kIOMainPortDefault,
                                   IOServiceMatching("IOAccelerator"),
                                   &it) != KERN_SUCCESS)
    return nullptr;
  CFStringRef k = CFSTR("PerformanceStatistics");
  CFTypeRef found = nullptr;
  for (io_object_t s; !found && (s = IOIteratorNext(it)) != 0;) {
    CFTypeRef d = IORegistryEntryCreateCFProperty(s, k, kCFAllocatorDefault, 0);
    IOObjectRelease(s);
    if (!d) continue;
    long long v;
    for (const auto& a : kApple)
      if (dictNumber(d, a.key, &v)) {
        found = d;
        break;
      }
    if (!found) CFRelease(d);
  }
  IOObjectRelease(it);
  return found;
}

const char* nameOf(uint16_t id) {
  for (const auto& s : gpusens::kSensors)
    if (s.id == id) return s.key;
  return "?";
}

struct Reading {
  char status[160] = "not running";
  char allSensors[160] = "";
  char control[160] = "";
  char profile[160] = "";
  long long samples = 0, ageMs = -1;
  CFTypeRef sensors = nullptr, perf = nullptr;
  bool running = false;
  ~Reading() {
    if (sensors) CFRelease(sensors);
    if (perf) CFRelease(perf);
  }
};

void read(Reading& r) {
  CFDictionaryRef props = copyProperties("DrogaBoxGPUSensors");
  CFTypeRef st = copyValue(props, "Status");
  if (st) {
    r.running = true;
    string(st, r.status, sizeof(r.status));
    CFRelease(st);
    CFTypeRef all = copyValue(props, "AllSensors");
    if (all) {
      string(all, r.allSensors, sizeof(r.allSensors));
      CFRelease(all);
    }
    CFTypeRef c = copyValue(props, "Control");
    if (c) {
      string(c, r.control, sizeof(r.control));
      CFRelease(c);
    }
    c = copyValue(props, "Profile");
    if (c) {
      string(c, r.profile, sizeof(r.profile));
      CFRelease(c);
    }
    CFTypeRef n = copyValue(props, "Samples");
    number(n, &r.samples);
    if (n) CFRelease(n);
    n = copyValue(props, "SampleAgeMs");
    number(n, &r.ageMs);
    if (n) CFRelease(n);
    r.sensors = copyValue(props, "Sensors");
  }
  if (props) CFRelease(props);
  r.perf = copyApplePerf();
}

void jsonString(const char* s) {
  putchar('"');
  for (; *s; s++) {
    if (*s == '"' || *s == '\\') putchar('\\');
    if ((unsigned char)*s >= 0x20) putchar(*s);
  }
  putchar('"');
}

int showTable(const Reading& r) {
  printf("GPUSensors: %s", r.status);
  if (r.running) printf(", %lld readings since boot", r.samples);
  if (r.ageMs >= 0) printf(", last %lld ms ago", r.ageMs);
  printf("\n");
  if (r.allSensors[0])
    printf("All of the driver's sensors: %s\n", r.allSensors);
  if (r.control[0]) printf("GPU control: %s\n", r.control);
  if (r.profile[0]) printf("Boot power profile: %s\n", r.profile);
  bool any = false;
  for (const auto& s : gpusens::kSensors) {
    long long v;
    if (!dictNumber(r.sensors, s.key, &v)) continue;
    any = true;
    if (s.unit == gpusens::Unit::Bits)
      printf("  %-26s 0x%08llx\n", s.key, v);
    else if (s.id == 40)  // AMD counts the generation from 0: 2 is PCIe 3.0
      printf("  %-26s %lld (PCIe %lld.0)\n", s.key, v, v + 1);
    else
      printf("  %-26s %lld %s\n", s.key, v, gpusens::unitName(s.unit));
  }
  if (!any) {
    printf("macOS publishes by itself:\n");
    for (const auto& a : kApple) {
      long long v;
      if (dictNumber(r.perf, a.key, &v)) printf("  %-26s %lld\n", a.key, v);
    }
    printf(r.running ? "No reading from the driver yet.\n"
                     : "Edge temperature, GFX voltage, memory activity and the "
                       "PCIe link need GPUSensors.kext (sensors/README.md).\n");
    return 1;
  }
  return 0;
}

int showJson(const Reading& r) {
  printf("{\"running\":%s,\"status\":", r.running ? "true" : "false");
  jsonString(r.status);
  printf(",\"allSensors\":");
  jsonString(r.allSensors);
  printf(",\"control\":");
  jsonString(r.control);
  printf(",\"profile\":");
  jsonString(r.profile);
  printf(",\"samples\":%lld,\"ageMs\":%lld,\"sensors\":{", r.samples, r.ageMs);
  bool first = true, any = false;
  for (const auto& s : gpusens::kSensors) {
    long long v;
    if (!dictNumber(r.sensors, s.key, &v)) continue;
    printf("%s", first ? "" : ",");
    jsonString(s.key);
    printf(":{\"value\":%lld,\"unit\":", v);
    jsonString(gpusens::unitName(s.unit));
    printf("}");
    first = false;
    any = true;
  }
  printf("},\"apple\":{");
  first = true;
  for (const auto& a : kApple) {
    long long v;
    if (!dictNumber(r.perf, a.key, &v)) continue;
    printf("%s", first ? "" : ",");
    jsonString(a.key);
    printf(":%lld", v);
    first = false;
  }
  printf("}}\n");
  return any ? 0 : 1;
}

// Both are read within a moment of each other, but not at the same sample:
// expect small differences in values that move (clocks, power).
int showCompare(const Reading& r) {
  printf("%-20s %-22s %10s %10s\n", "macOS key", "GPUSensors name", "macOS",
         "GPUSensors");
  int shown = 0;
  for (const auto& a : kApple) {
    long long mine = 0, apple = 0;
    bool hasMine = dictNumber(r.sensors, nameOf(a.id), &mine);
    bool hasApple = dictNumber(r.perf, a.key, &apple);
    printf("%-20s %-22s ", a.key, nameOf(a.id));
    if (hasApple)
      printf("%10lld ", apple);
    else
      printf("%10s ", "-");
    if (hasMine)
      printf("%10lld\n", mine);
    else
      printf("%10s\n", "-");
    shown += hasMine && hasApple;
  }
  return shown ? 0 : 1;
}

int usage() {
  fprintf(stderr,
          "usage: gpusensors [--json | --watch [secs] | --compare]\n"
          "  secs: 0.1 to 3600, default 1\n");
  return 64;
}

}  // namespace

int main(int argc, char** argv) {
  enum { Table, Json, Watch, Compare } mode = Table;
  double every = 1;
  for (int i = 1; i < argc; i++) {
    int asked;
    if (!strcmp(argv[i], "--json"))
      asked = Json;
    else if (!strcmp(argv[i], "--compare"))
      asked = Compare;
    else if (!strcmp(argv[i], "--watch")) {
      asked = Watch;
      if (i + 1 < argc && argv[i + 1][0] != '-') {
        const char* arg = argv[++i];
        char* end = nullptr;
        every = strtod(arg, &end);
        if (!*arg || *end || !isfinite(every) || every <= 0 || every > 3600)
          return usage();
        if (every < 0.1) every = 0.1;
      }
    } else {
      return usage();
    }
    if (mode != Table) return usage();  // one mode at a time
    mode = static_cast<decltype(mode)>(asked);
  }
  if (mode == Watch) {
    for (;;) {
      Reading r;
      read(r);
      printf("\033[H\033[2J");
      showTable(r);
      fflush(stdout);
      usleep((useconds_t)(every * 1e6));
    }
  }
  Reading r;
  read(r);
  if (mode == Json) return showJson(r);
  if (mode == Compare) return showCompare(r);
  return showTable(r);
}
