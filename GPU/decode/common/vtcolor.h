// Colour attachments for the pictures a decoder plug-in hands to
// VideoToolbox: primaries, transfer function, YCbCr matrix, and the HDR
// metadata (mastering display colour volume, content light level). Without
// them a BT.2020 PQ picture is shown as an untagged one: washed out, and the
// display never switches to HDR.
//
// Each value comes from the first source that gives one CoreVideo knows: the
// plug-in says in which order it asks the stream (common/vcncolor.h, filled
// by the decoder session) and the container (the format description
// VideoToolbox started the session with). Code points are turned into
// CoreVideo's names by CoreVideo itself (CV*GetStringForIntegerCodePoint), so
// they map the way Apple's own decoders map them.
#pragma once
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>

#include "vcncolor.h"

// CoreVideo's name for a code point, or NULL. For a code point it has no
// constant for (a reserved one, BT.470M primaries, gamma 2.2 transfer, ...)
// CoreVideo makes up a name such as "ColorPrimaries#4" (seen on macOS 26.7):
// no consumer knows it, so it counts as no name, and the container's value
// can fill in.
static CFStringRef vt_known(CFStringRef name) {
  if (!name) return NULL;
  return CFStringFind(name, CFSTR("#"), 0).location == kCFNotFound ? name
                                                                   : NULL;
}
static CFStringRef vt_primaries_name(int v) {
  return v >= 0 ? vt_known(CVColorPrimariesGetStringForIntegerCodePoint(v))
                : NULL;
}
static CFStringRef vt_transfer_name(int v) {
  return v >= 0 ? vt_known(CVTransferFunctionGetStringForIntegerCodePoint(v))
                : NULL;
}
static CFStringRef vt_matrix_name(int v) {
  // H.273 matrix 5 (BT.470BG, BT.601 625 lines) has the same coefficients as
  // 6 (BT.601 525 lines), which CoreVideo names ITU_R_601_4; it has no name
  // for 5.
  if (v == 5) v = 6;
  return v >= 0 ? vt_known(CVYCbCrMatrixGetStringForIntegerCodePoint(v)) : NULL;
}

// The code point of a format description extension that holds one of
// CoreVideo's names; -1 when it is missing or not a name CoreVideo knows.
static int vt_ext_code(CMFormatDescriptionRef fmt, CFStringRef key,
                       int (*code)(CFStringRef)) {
  CFTypeRef v = CMFormatDescriptionGetExtension(fmt, key);
  if (!v || CFGetTypeID(v) != CFStringGetTypeID()) return -1;
  int c = code((CFStringRef)v);
  return c > 0 ? c : -1;  // CoreVideo gives 2 for a name it does not know
}
static bool vt_ext_bytes(CMFormatDescriptionRef fmt, CFStringRef key,
                         uint8_t* out, CFIndex n) {
  CFTypeRef v = CMFormatDescriptionGetExtension(fmt, key);
  if (!v || CFGetTypeID(v) != CFDataGetTypeID() ||
      CFDataGetLength((CFDataRef)v) != n)
    return false;
  CFDataGetBytes((CFDataRef)v, CFRangeMake(0, n), out);
  return true;
}

// What the container says: the colour extensions of the format description
// (an MP4 colr/mdcv/clli box, or what the host made of a WebM Colour
// element).
static void vt_color_from_format(CMFormatDescriptionRef fmt, VcnColor* c) {
  vcn_color_clear(c);
  if (!fmt) return;
  c->primaries = vt_ext_code(fmt, kCMFormatDescriptionExtension_ColorPrimaries,
                             CVColorPrimariesGetIntegerCodePointForString);
  c->transfer = vt_ext_code(fmt, kCMFormatDescriptionExtension_TransferFunction,
                            CVTransferFunctionGetIntegerCodePointForString);
  c->matrix = vt_ext_code(fmt, kCMFormatDescriptionExtension_YCbCrMatrix,
                          CVYCbCrMatrixGetIntegerCodePointForString);
  c->has_mdcv = vt_ext_bytes(
      fmt, kCMFormatDescriptionExtension_MasteringDisplayColorVolume, c->mdcv,
      sizeof(c->mdcv));
  c->has_cll =
      vt_ext_bytes(fmt, kCMFormatDescriptionExtension_ContentLightLevelInfo,
                   c->cll, sizeof(c->cll));
}

// Per value, a's when CoreVideo has a name for it, else b's.
static void vt_color_merge(VcnColor* out, const VcnColor* a,
                           const VcnColor* b) {
  VcnColor r;
  vcn_color_clear(&r);
  r.primaries = vt_primaries_name(a->primaries) ? a->primaries : b->primaries;
  r.transfer = vt_transfer_name(a->transfer) ? a->transfer : b->transfer;
  r.matrix = vt_matrix_name(a->matrix) ? a->matrix : b->matrix;
  const VcnColor* m = a->has_mdcv ? a : b;
  if ((r.has_mdcv = m->has_mdcv)) memcpy(r.mdcv, m->mdcv, sizeof(r.mdcv));
  const VcnColor* l = a->has_cll ? a : b;
  if ((r.has_cll = l->has_cll)) memcpy(r.cll, l->cll, sizeof(r.cll));
  *out = r;
}

static void vt_set_or_remove(CVBufferRef b, CFStringRef key, CFTypeRef v) {
  if (v)
    CVBufferSetAttachment(b, key, v, kCVAttachmentMode_ShouldPropagate);
  else
    CVBufferRemoveAttachment(b, key);
}
static void vt_set_bytes(CVBufferRef b, CFStringRef key, bool has,
                         const uint8_t* bytes, CFIndex n) {
  CFDataRef d = has ? CFDataCreate(NULL, bytes, n) : NULL;
  // Out of memory: no value rather than the one an earlier picture of the
  // pool left on the buffer.
  vt_set_or_remove(b, key, d);
  if (d) CFRelease(d);
}

// Sets every colour attachment the picture has a value for and removes the
// others: the buffers come back from a pool and may still carry what an
// earlier stream left on them.
static void vt_color_attach(CVBufferRef b, const VcnColor* c) {
  if (!b || !c) return;
  vt_set_or_remove(b, kCVImageBufferColorPrimariesKey,
                   vt_primaries_name(c->primaries));
  vt_set_or_remove(b, kCVImageBufferTransferFunctionKey,
                   vt_transfer_name(c->transfer));
  vt_set_or_remove(b, kCVImageBufferYCbCrMatrixKey, vt_matrix_name(c->matrix));
  vt_set_bytes(b, kCVImageBufferMasteringDisplayColorVolumeKey, c->has_mdcv,
               c->mdcv, sizeof(c->mdcv));
  vt_set_bytes(b, kCVImageBufferContentLightLevelInfoKey, c->has_cll, c->cll,
               sizeof(c->cll));
}
