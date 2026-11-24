// VideoToolbox decoder plug-in for MPEG-4 part 2 video ('mp4v') on the AMD
// VCN.
#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CoreMedia.h>

#include "vcnmpeg4.h"

#define LEGACY_FACTORY MPEG4VCN_VTDecoder_CreateInstance
#define LEGACY_CODEC (&vcnmpeg4_codec)
#define LEGACY_LOG "com.droga.vtmpeg4vcn"
#define LEGACY_NAME "MPEG-4"

static bool legacy_accepts(FourCharCode codec) {
  return codec == kCMVideoCodecType_MPEG4Video;
}

// The esds atom: the video object layer header sits in its decoder specific
// info, with its start codes. The codec layer skips to the first start code,
// so the atom goes to it whole.
static CFDataRef legacy_copy_config(CMFormatDescriptionRef fmt) {
  CFDictionaryRef atoms = CMFormatDescriptionGetExtension(
      fmt, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms);
  if (!atoms || CFGetTypeID(atoms) != CFDictionaryGetTypeID()) return NULL;
  CFTypeRef v = CFDictionaryGetValue(atoms, CFSTR("esds"));
  if (!v) return NULL;
  if (CFGetTypeID(v) == CFDataGetTypeID()) return CFRetain(v);
  if (CFGetTypeID(v) == CFArrayGetTypeID() && CFArrayGetCount(v) > 0) {
    CFTypeRef e = CFArrayGetValueAtIndex(v, 0);
    if (CFGetTypeID(e) == CFDataGetTypeID()) return CFRetain(e);
  }
  return NULL;
}

#include "vtlegacy.h"
