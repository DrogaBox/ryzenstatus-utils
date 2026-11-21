// Reverse-engineered interface of AMDRadeonVADriver2 ("ATIAVDVADriver"), the
// AMD backend that AppleGVA drives on Intel Macs. Layouts recovered from
// Hex-Rays output and live lldb traces of VTDecoderXPCService decoding HEVC.
// Only the fields we need are named.
#pragma once
#include <IOKit/IOKitLib.h>
#include <stdint.h>

#define AVD_DRIVER_PATH                                                  \
  "/System/Library/Extensions/AMDRadeonVADriver2.bundle/Contents/MacOS/" \
  "AMDRadeonVADriver2"

// AVD function ids (AVD_FunctionInfo.function / AVD_CmdInfo.function)
#define AVD_FUNC_H264 0x8ull
#define AVD_FUNC_HEVC 0x800ull
#define AVD_FUNC_AV1 0x1000000ull

// Argument of AVD_CreateAVDAccelerator. Read in the 25G342 driver (IDA,
// AVD_CreateAVDAccelerator at 0x7FFB10B009E0, export offset 0x9E0): it keeps
// validMask at inner+0, the number of the highest bit set plus one at inner+4
// and the services pointer at inner+8 (0x...A69-AA0). It goes on only if bit
// `index` of validMask is set, index is below that count and services[index]
// is not 0; otherwise it returns 5 (0x...AA2-ACC). services[index] is then
// the only entry it reads: the service it hands to IOAccelDeviceCreate
// (0x...AC7, call at 0x...AD1). Nothing reads inner+0/+4/+8 again:
// CreateDriver takes inner+24/+32/+40/+52/+64/+72/+88/+96 and
// AVD_DestroyAVDAccelerator releases +32..+96. So one service in services[0],
// index 0 and validMask 1 is all it needs. AppleGVA passes index 0 and
// validMask 0xffffffff (sub_7FFA0C59F7A6), which passes the same check.
typedef struct {
  uint32_t index;  // the entry of services[] the driver opens
  uint32_t pad0;
  uint32_t* services;  // io_service_t array; the driver keeps the pointer only
  uint32_t validMask;  // bit i set => services[i] valid
  uint32_t pad1;
  uint8_t reserved[0x30];  // +0x18..+0x27 copied to inner+16 (AppleGVA: 0)
} AVD_AcceleratorCreate;

typedef struct {
  void* inner;
  void* fn[16];
} AVD_Accelerator;

enum {
  AVD_FN_CreateDriver,
  AVD_FN_DeleteDriver,
  AVD_FN_CreateContexts,
  AVD_FN_DeleteContexts,
  AVD_FN_GetBitstreamBufferInfo,
  AVD_FN_AllocateBitstreamBufferPool,
  AVD_FN_FreeBitstreamBufferPool,
  AVD_FN_GetPixelBufferInfo,
  AVD_FN_AllocatePixelBufferPool,
  AVD_FN_FreePixelBufferPool,
  AVD_FN_ScheduleAVDCommands,
  AVD_FN_QueryAVDCommandStatus,
  AVD_FN_SetContextParameter,
  AVD_FN_GetContextParameter,
  AVD_FN_SetDriverParameter,
  AVD_FN_GetDriverParameter,
};

typedef struct {
  uint32_t initFlags;  // passed to VAContext::Init (AppleGVA: 0)
  uint32_t pad;
  AVD_Accelerator* accel;
  uint8_t reserved[0x20];
} AVD_DriverCreate;

typedef struct {
  uint32_t kind;  // 1 = decode
  uint32_t pad0;
  uint64_t function;  // AVD_FUNC_*
  uint32_t mode;      // AppleGVA HEVC: 5
  uint32_t pad1;
  uint32_t pixelRate;  // width*height*fps, must be non-zero
  uint32_t pad2;
  uint32_t width;
  uint32_t height;
  uint32_t inFormat;        // 'rawb' (0x72617762)
  uint32_t inFormatCount;   // 1
  uint32_t outFormat;       // 'NV12' (0x4e563132) or 'P010'
  uint32_t outFormatCount;  // 1
  void* next;
  uint8_t reserved[0x40];
} AVD_FunctionInfo;

typedef struct {
  uint32_t count;
  uint32_t pad;
  AVD_FunctionInfo** functions;
  void** contextsOut;
  AVD_FunctionInfo inlineInfo;
} AVD_ContextList;

typedef struct {
  AVD_ContextList* list;
  void* capsOut;
  uint8_t reserved[0x30];
} AVD_DriverContextInit;

typedef struct {
  uint32_t count;
  uint32_t pad;
  void** contexts;
} AVD_DriverContextDelete;

typedef struct {
  uint32_t type;  // 0
  uint32_t pad0;
  uint32_t size;        // bytes per buffer
  uint32_t format;      // 'rawb'
  uint32_t one;         // 1
  uint32_t count;       // 1..32
  void** addressesOut;  // receives CPU address of each buffer
  void* reserved0;
  uint32_t eight, five;
  uint8_t reserved[0x20];
} AVD_BitstreamPool;

typedef struct {
  uint32_t kind;  // 1 = decode
  uint32_t pad0;
  uint64_t function;  // AVD_FUNC_*
  uint32_t mode;      // 5
  uint32_t pad1;
  void* context;  // from CreateContexts
  void* params;   // codec specific
  void* reserved[6];
} AVD_CmdInfo;

typedef struct {
  uint32_t count;
  uint32_t pad;
  AVD_CmdInfo** cmds;
} AVD_CmdList;

typedef struct {
  uint32_t count;
  uint32_t pad;
  void** refcons;  // out
} AVD_RefConList;

// Read in the 25G342 driver (IDA, 0x7FFB10B009E0): *out = NULL first
// (0x...9EE), set only on success (0x...D70). Returns 5 for a NULL `in` or
// info, for a service the check above refuses, and for a device it does not
// drive (identify() 11 or 12); 1 when IOAccelDeviceCreate,
// IOAccelDeviceGetConfig, IOAccelSharedCreate, IOAccelVideoContextCreate or
// AvdCapability::initDriverCapability fails. On every failure it frees the
// accelerator and its inner object itself (operator delete, 0x...B1E-B38):
// there is nothing for the caller to destroy, and the caller must not.
// Whatever it opened is released before that (0x...B09, 0x...BA6-BBE,
// 0x...BE1), except after a failed initDriverCapability (0x...C7B): then only
// the VAIOConnect and the AvdCapability are deleted, and the IOAccelDevice,
// IOAccelShared and IOAccelVideoContext stay open inside the driver with no
// handle left to the caller. That leak is the driver's; the caller cannot undo
// it.
typedef int (*AVD_CreateAVDAccelerator_fn)(AVD_Accelerator** out,
                                           AVD_AcceleratorCreate* in,
                                           void* info96);
// Read in the 25G342 driver (IDA, 0x5D16C): releases what CreateAVDAccelerator
// opened (its IOAccelDevice, IOAccelShared and IOAccelVideoContext, the
// VAIOConnect and the AvdCapability) and frees the accelerator itself. Returns
// 0. DeleteDriver releases none of it.
typedef int (*AVD_DestroyAVDAccelerator_fn)(AVD_Accelerator* accel);
// Read in the 25G342 driver (IDA, AvdVAInterface::CreateDriver at
// 0x7FFB10B01EF6): returns 5 for NULL arguments or a failed VAContext::Init,
// and writes *driver only on success. After a failed Init the AvdVAContext
// (856 bytes) and the VAContext (75096 bytes) it made stay allocated in the
// driver, with no handle to the caller; Init's own failure paths free only
// its address library (whether the VAContext constructor opens anything was
// not read). There is nothing to delete: DeleteDriver needs the handle that
// was never returned. On success driver+8 is the VAContext, and
// VAContext+75072 its VAFactory, the last thing Init sets; vcnvp9.c reads
// both.
typedef int (*AVD_CreateDriver_fn)(void** driver, AVD_DriverCreate* dc);
typedef int (*AVD_CreateContexts_fn)(void* driver, AVD_DriverContextInit* init);
typedef int (*AVD_DeleteContexts_fn)(void* driver,
                                     AVD_DriverContextDelete* del);
// Read in the 25G342 driver (IDA, AvdVAContext::AllocateBitStreamBufferPool
// at 0x7FFB10B5E0C6): when a buffer cannot be made after others were, it
// runs its own FreeBitStreamBufferPool (0x7FFB10B5E20E) before it returns 7,
// and the pool is not marked allocated. A second free from the caller would
// walk the same entries, now NULL, into VAVendorTexture::DeleteTexture(NULL).
// So a pool whose Allocate did not return 0 is never freed by the caller.
typedef int (*AVD_AllocateBitstreamBufferPool_fn)(void* driver,
                                                  AVD_BitstreamPool* pool);
typedef int (*AVD_FreeBitstreamBufferPool_fn)(void* driver, uint32_t type);
typedef int (*AVD_ScheduleAVDCommands_fn)(void* driver, AVD_CmdList* cmds,
                                          AVD_RefConList* refcons);
// One entry of QueryAVDCommandStatus. Read in the 25G342 driver (IDA,
// AvdVAContext::QueryAVDCommandStatus): besides the refcon, +12 `wait` is the
// only input; +8 is never read. With wait = 0 the call returns at once: status
// 1 = done, 2 = still running, status2 = 0. With wait != 0 it blocks in the
// kernel (no timeout in user space) until the command is done, then status = 1
// and status2 = the firmware's decode result (0 = no error).
typedef struct {
  void* refcon;
  uint32_t
      unused8;  // once taken for a poll interval; the driver never reads it
  uint32_t wait;
  uint32_t status, status2;
} AVD_QueryEntry;
typedef struct {
  uint32_t count, pad;
  AVD_QueryEntry* entries;
} AVD_QueryList;

typedef int (*AVD_QueryAVDCommandStatus_fn)(void* driver, AVD_QueryList* query);
typedef int (*AVD_DeleteDriver_fn)(void* driver);
