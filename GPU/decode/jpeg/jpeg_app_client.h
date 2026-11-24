/*
 * jpeg_app_client.h - the caller's side of jpeg_app.h: one picture through the
 * apps build of VCNJpegProbe. Plain C, header only; jpegprobe and the
 * VideoToolbox plug-in use it (the plug-in keeps a copy of this file).
 *
 * The transport is a function, so tests can put a fake behind it; the real one
 * (ja_iokit_*) calls selector 258 of a video context of the AMD accelerator.
 */
#ifndef JPEG_APP_CLIENT_H
#define JPEG_APP_CLIENT_H
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <time.h>

#include "jpeg_app.h"

/* One struct call: in -> out, *outSize is the room on entry and the bytes written on return. 0 = the call
   went through (kern_return_t KERN_SUCCESS for the real one). */
typedef int (*ja_transport)(void* ctx, const void* in, size_t inSize, void* out, size_t* outSize);

/* Sends one request; fills *rp. Returns the reply's status, or -1 when the call itself failed or the
   reply is not one of ours (no kext: PowerPlay refuses the request). */
static inline int ja_call(ja_transport t, void* ctx, uint32_t op, uint64_t a0, uint64_t a1, const void* data,
                          size_t dataBytes, struct ja_reply* rp, void* outData, size_t outCap) {
  uint8_t in[JA_MAX_IO], out[JA_MAX_IO];
  struct ja_request rq = {JA_HEADER_SIZE, JA_CODE, JA_PROTOCOL, op, a0, a1};
  if (dataBytes > JA_LOAD_PIECE) return -1;
  memcpy(in, &rq, sizeof(rq));
  if (dataBytes != 0) memcpy(in + sizeof(rq), data, dataBytes);
  size_t outSize = sizeof(out);
  if (t(ctx, in, sizeof(rq) + dataBytes, out, &outSize) != 0) return -1;
  if (outSize < sizeof(*rp) || outSize > sizeof(out)) return -1;
  memcpy(rp, out, sizeof(*rp));
  if (rp->magic != JA_REPLY_MAGIC || sizeof(*rp) + rp->dataBytes != outSize) return -1;
  if (outData != NULL) memcpy(outData, out + sizeof(*rp), rp->dataBytes <= outCap ? rp->dataBytes : outCap);
  return (int)rp->status;
}

static inline uint64_t ja_now_ms(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1000000u; }

/* Decodes one JPEG (already in the shape the block takes) into `surface` (NV12, layout in *pic).
   Waits up to waitMs while another client holds the decoder. Returns JA_OK or the failing status
   (-1: transport). */
static inline int ja_decode(ja_transport t, void* ctx, const uint8_t* jpeg, size_t jpegBytes, uint8_t* surface,
                            size_t surfaceCap, uint32_t flags, unsigned waitMs, struct ja_picture* pic,
                            struct ja_reply* last) {
  struct ja_reply rp;
  memset(&rp, 0, sizeof(rp));
  uint64_t until = ja_now_ms() + waitMs;
  int s;
  while (1) {
    s = ja_call(t, ctx, JA_OP_LOAD_USER, (uint64_t)(uintptr_t)jpeg, jpegBytes, NULL, 0, &rp, NULL, 0);
    if (s != JA_BUSY || ja_now_ms() >= until) break;
    struct timespec ts = {0, 2000000};
    nanosleep(&ts, NULL);
  }
  if (s == JA_OK) {
    memset(pic, 0, sizeof(*pic));
    s = ja_call(t, ctx, JA_OP_RUN, flags, 0, NULL, 0, &rp, pic, sizeof(*pic));
    if (s == JA_OK && rp.dataBytes != sizeof(*pic)) s = -1;
    if (s == JA_OK && pic->surfaceBytes > surfaceCap) s = JA_BAD_REQUEST;
    if (s == JA_OK) s = ja_call(t, ctx, JA_OP_READ_USER, (uint64_t)(uintptr_t)surface, surfaceCap, NULL, 0, &rp, NULL, 0);
  }
  if (s != JA_OK && s != JA_BUSY && s != -1) {
    struct ja_reply ignored;
    ja_call(t, ctx, JA_OP_RELEASE, 0, 0, NULL, 0, &ignored, NULL, 0);
  }
  if (last != NULL) *last = rp;
  return s;
}

/* Room the kext has now: JPEG bytes and surface bytes (0 when there is no door). */
static inline int ja_info(ja_transport t, void* ctx, uint64_t* state, uint64_t* jpegCap, uint64_t* surfaceCap) {
  struct ja_reply rp;
  int s = ja_call(t, ctx, JA_OP_INFO, 0, 0, NULL, 0, &rp, NULL, 0);
  if (s != JA_OK) return s;
  if (state) *state = rp.v[0];
  if (jpegCap) *jpegCap = rp.v[1];
  if (surfaceCap) *surfaceCap = rp.v[2];
  return JA_OK;
}

#ifdef __APPLE__
#include <IOKit/IOKitLib.h>

/* Opens a video context (type 3) on the AMD accelerator: what any process that decodes video may do. */
static inline io_connect_t ja_iokit_open(void) {
  io_service_t s = IOServiceGetMatchingService(kIOMainPortDefault,
                                               IOServiceMatching("AMDRadeonX6000_AMDGraphicsAccelerator"));
  if (s == IO_OBJECT_NULL) return IO_OBJECT_NULL;
  io_connect_t c = IO_OBJECT_NULL;
  kern_return_t kr = IOServiceOpen(s, mach_task_self(), JA_VIDEO_CONTEXT_TYPE, &c);
  IOObjectRelease(s);
  return kr == KERN_SUCCESS ? c : IO_OBJECT_NULL;
}

static inline int ja_iokit_call(void* ctx, const void* in, size_t inSize, void* out, size_t* outSize) {
  io_connect_t c = *(io_connect_t*)ctx;
  return IOConnectCallStructMethod(c, JA_SELECTOR, in, inSize, out, outSize);
}
#endif

#endif
