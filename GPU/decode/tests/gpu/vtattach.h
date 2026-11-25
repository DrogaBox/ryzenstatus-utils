// vtattach.h: prints the colour attachments of decoded pictures (vtav1test and
// vtvp9test, -attach): the first picture's, then again whenever they change.
#pragma once
#include <CoreVideo/CoreVideo.h>
#include <stdio.h>
#include <string.h>

static void attach_value(char* out, size_t n, CFTypeRef v) {
  if (!v) {
    snprintf(out, n, "none");
  } else if (CFGetTypeID(v) == CFStringGetTypeID()) {
    if (!CFStringGetCString(v, out, (CFIndex)n, kCFStringEncodingUTF8))
      snprintf(out, n, "?");
  } else if (CFGetTypeID(v) == CFDataGetTypeID()) {
    size_t len = (size_t)CFDataGetLength(v), o = 0;
    const uint8_t* b = CFDataGetBytePtr(v);
    o += (size_t)snprintf(out, n, "%zu bytes", len);
    for (size_t i = 0; i < len && o + 3 < n; i++)
      o += (size_t)snprintf(out + o, n - o, "%s%02x", i ? "" : " ", b[i]);
  } else {
    snprintf(out, n, "(other type)");
  }
}

// The mastering display bytes (HEVC SEI layout) read back as numbers.
static void attach_mdcv_text(char* out, size_t n, CFTypeRef v) {
  out[0] = 0;
  if (!v || CFGetTypeID(v) != CFDataGetTypeID() || CFDataGetLength(v) != 24)
    return;
  const uint8_t* b = CFDataGetBytePtr(v);
#define U16(i) ((unsigned)(b[i] << 8 | b[(i) + 1]))
#define U32(i) ((unsigned long)U16(i) << 16 | U16((i) + 2))
  snprintf(out, n,
           "G %.4f,%.4f B %.4f,%.4f R %.4f,%.4f white %.4f,%.4f, "
           "max %.1f cd/m2, min %.4f cd/m2",
           U16(0) * 0.00002, U16(2) * 0.00002, U16(4) * 0.00002,
           U16(6) * 0.00002, U16(8) * 0.00002, U16(10) * 0.00002,
           U16(12) * 0.00002, U16(14) * 0.00002, U32(16) * 0.0001,
           U32(20) * 0.0001);
#undef U16
#undef U32
}

// last: what was printed before (empty at first), at least 1024 bytes.
static void print_attachments(CVImageBufferRef img, int frame, char* last) {
  static const struct {
    const char* name;
    CFStringRef* key;
  } keys[] = {
      {"ColorPrimaries", (CFStringRef*)&kCVImageBufferColorPrimariesKey},
      {"TransferFunction", (CFStringRef*)&kCVImageBufferTransferFunctionKey},
      {"YCbCrMatrix", (CFStringRef*)&kCVImageBufferYCbCrMatrixKey},
      {"MasteringDisplayColorVolume",
       (CFStringRef*)&kCVImageBufferMasteringDisplayColorVolumeKey},
      {"ContentLightLevelInfo",
       (CFStringRef*)&kCVImageBufferContentLightLevelInfoKey},
  };
  char now[1024] = "", v[200], m[200];
  OSType f = CVPixelBufferGetPixelFormatType(img);
  size_t o = (size_t)snprintf(now, sizeof(now), "  pixel format '%c%c%c%c'\n",
                              f >> 24, f >> 16 & 255, f >> 8 & 255, f & 255);
  for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
    CFTypeRef a = CVBufferCopyAttachment(img, *keys[i].key, NULL);
    attach_value(v, sizeof(v), a);
    attach_mdcv_text(m, sizeof(m), i == 3 ? a : NULL);
    o += (size_t)snprintf(now + o, sizeof(now) - o, "  %s: %s%s%s%s\n",
                          keys[i].name, v, m[0] ? "\n    (" : "", m,
                          m[0] ? ")" : "");
    if (a) CFRelease(a);
    if (o >= sizeof(now)) break;
  }
  if (!strcmp(now, last)) return;
  printf("attachments of frame %d:\n%s", frame, now);
  snprintf(last, 1024, "%s", now);
}
