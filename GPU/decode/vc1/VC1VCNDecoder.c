// VideoToolbox decoder plug-in for VC-1 on the AMD VCN: 'vc-1' (the MP4
// registration authority's code), and 'WVC1' and 'WMV3' as ASF and AVI name
// the advanced and the simple/main profile.
#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CoreMedia.h>

#include "vcnvc1.h"

#define LEGACY_FACTORY VC1VCN_VTDecoder_CreateInstance
#define LEGACY_CODEC (&vcnvc1_codec)
#define LEGACY_LOG "com.droga.vtvc1vcn"
#define LEGACY_NAME "VC-1"

static bool legacy_accepts(FourCharCode codec) {
  return codec == 'vc-1' || codec == 'WVC1' || codec == 'WMV3';
}

static CFDataRef copy_atom(CFDictionaryRef atoms, CFStringRef name) {
  CFTypeRef v = CFDictionaryGetValue(atoms, name);
  if (!v) return NULL;
  if (CFGetTypeID(v) == CFDataGetTypeID()) return CFRetain(v);
  if (CFGetTypeID(v) == CFArrayGetTypeID() && CFArrayGetCount(v) > 0) {
    CFTypeRef e = CFArrayGetValueAtIndex(v, 0);
    if (CFGetTypeID(e) == CFDataGetTypeID()) return CFRetain(e);
  }
  return NULL;
}

// The sequence header, from either atom a container may carry:
//   dvc1  (SMPTE RP 2025) seven bytes, then the sequence header and entry
//         point with their start codes; the codec layer skips to the first
//         start code, so the atom goes to it whole;
//   strf  a 40-byte BITMAPINFOHEADER, then the codec private data of ASF and
//         AVI: STRUCT_C for the simple and main profiles, or a byte and the
//         headers with start codes for the advanced profile.
static CFDataRef legacy_copy_config(CMFormatDescriptionRef fmt) {
  CFDictionaryRef atoms = CMFormatDescriptionGetExtension(
      fmt, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms);
  if (!atoms || CFGetTypeID(atoms) != CFDictionaryGetTypeID()) return NULL;
  CFDataRef d = copy_atom(atoms, CFSTR("dvc1"));
  if (d) return d;
  d = copy_atom(atoms, CFSTR("strf"));
  if (!d) return NULL;
  CFIndex n = CFDataGetLength(d);
  CFDataRef priv =
      n > 40 ? CFDataCreate(NULL, CFDataGetBytePtr(d) + 40, n - 40) : NULL;
  CFRelease(d);
  return priv;
}

#include "vtlegacy.h"
