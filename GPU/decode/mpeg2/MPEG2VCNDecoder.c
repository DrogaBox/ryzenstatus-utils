// VideoToolbox decoder plug-in for MPEG-2 video ('mp2v') on the AMD VCN.
#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CoreMedia.h>

#include "vcnmpeg2.h"

#define LEGACY_FACTORY MPEG2VCN_VTDecoder_CreateInstance
#define LEGACY_CODEC (&vcnmpeg2_codec)
#define LEGACY_LOG "com.droga.vtmpeg2vcn"
#define LEGACY_NAME "MPEG-2"

static bool legacy_accepts(FourCharCode codec) {
  return codec == kCMVideoCodecType_MPEG2Video;
}

// An MPEG-2 elementary stream carries its sequence header in the samples.
static CFDataRef legacy_copy_config(CMFormatDescriptionRef fmt) {
  (void)fmt;
  return NULL;
}

#include "vtlegacy.h"
