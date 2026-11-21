// acceltest: checks the rule that picks the accelerator handed to AMD's video
// driver, then lists the IOAccelerator services of this machine in the order
// IOServiceGetMatchingServices returns them (the call the decoders make) and
// says which one the decoders take. Read-only: it opens nothing.
//
// Exit status 1 when the rule fails its own cases. A machine with no AMD
// accelerator is not a failure of this test: it prints "decoders take: none".
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stdbool.h>
#include <stdio.h>

#include "vcndriver.h"

static int failures;

static void expect(const char* what, bool got, bool want) {
  if (got != want) {
    printf("FAIL %s\n", what);
    failures++;
  }
}

static void test_rule(void) {
  int number = 7;
  CFNumberRef num = CFNumberCreate(NULL, kCFNumberIntType, &number);
  CFDataRef data = CFDataCreate(NULL, (const UInt8*)"AMDVCN2", 7);
  expect("Navi 21 codec is AMD", vcn_codec_is_amd(CFSTR("AMDVCN2")), true);
  expect("any AMD name is AMD", vcn_codec_is_amd(CFSTR("AMDVCN4")), true);
  expect("Intel codec is not AMD", vcn_codec_is_amd(CFSTR("Gen95")), false);
  expect("AMD in the middle is not AMD", vcn_codec_is_amd(CFSTR("xAMD")),
         false);
  expect("lower case is not AMD", vcn_codec_is_amd(CFSTR("amdvcn2")), false);
  expect("empty string is not AMD", vcn_codec_is_amd(CFSTR("")), false);
  expect("a number is not AMD", vcn_codec_is_amd(num), false);
  expect("data is not AMD", vcn_codec_is_amd(data), false);
  expect("no property is not AMD", vcn_codec_is_amd(NULL), false);
  CFRelease(num);
  CFRelease(data);
}

int main(void) {
  test_rule();
  printf("accelerator rule: %s\n", failures ? "FAILED" : "ok");

  io_iterator_t it;
  if (IOServiceGetMatchingServices(kIOMainPortDefault,
                                   IOServiceMatching("IOAccelerator"), &it)) {
    printf("IOServiceGetMatchingServices failed\n");
    return 1;
  }
  int n = 0, first_with_codec = -1, first_amd = -1;
  io_service_t s;
  while ((s = IOIteratorNext(it))) {
    io_name_t cls = "";
    IOObjectGetClass(s, cls);
    uint64_t id = 0;
    IORegistryEntryGetRegistryEntryID(s, &id);
    char codec_name[64] = "-";
    CFTypeRef codec =
        IORegistryEntryCreateCFProperty(s, CFSTR("IOGVACodec"), NULL, 0);
    if (codec) {
      if (CFGetTypeID(codec) != CFStringGetTypeID() ||
          !CFStringGetCString((CFStringRef)codec, codec_name,
                              sizeof(codec_name), kCFStringEncodingUTF8))
        snprintf(codec_name, sizeof(codec_name), "(not a string)");
      if (first_with_codec < 0) first_with_codec = n;
      if (vcn_codec_is_amd(codec) && first_amd < 0) first_amd = n;
      CFRelease(codec);
    }
    printf("%d: %s  id 0x%llx  IOGVACodec %s\n", n, cls, (unsigned long long)id,
           codec_name);
    IOObjectRelease(s);
    n++;
  }
  IOObjectRelease(it);

  // The library function must agree with the walk above.
  io_service_t picked = vcn_find_accelerator();
  if ((picked != 0) != (first_amd >= 0)) {
    printf("FAIL vcn_find_accelerator disagrees with the list\n");
    failures++;
  }
  if (picked) IOObjectRelease(picked);

  if (first_amd >= 0)
    printf("decoders take: %d\n", first_amd);
  else
    printf("decoders take: none (no AMD accelerator with a video codec)\n");
  if (first_with_codec >= 0 && first_with_codec != first_amd)
    printf(
        "note: accelerator %d has a codec too and comes first; decoders "
        "before 0.3.0 handed that one to AMD's driver\n",
        first_with_codec);
  return failures ? 1 : 0;
}
