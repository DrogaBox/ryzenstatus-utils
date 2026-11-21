// gpusrc: fill IOSurface-backed NV12 pixel buffers on the GPU, for vtenc's
// "--source gpu" mode.
//
// The frames of vtenc's ring are uploaded once into ordinary Metal textures.
// Before each submit, one of them is copied into the destination buffer's
// IOSurface with a Metal blit (GPU to GPU), so the buffer gets new content
// every frame without the CPU ever writing to it.
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#import <Metal/Metal.h>

enum { GPUSRC_MAX = 16 };
static id<MTLDevice> gDev;
static id<MTLCommandQueue> gQueue;
static id<MTLTexture> gSrcY[GPUSRC_MAX], gSrcUV[GPUSRC_MAX], gDstY[GPUSRC_MAX],
    gDstUV[GPUSRC_MAX];
static size_t gW, gH;

// ring: n prefilled NV12 buffers (read by the CPU once). dst: n
// IOSurface-backed NV12 buffers to be filled on the GPU.
int gpusrc_init(CVPixelBufferRef* ring, CVPixelBufferRef* dst, int n) {
  @autoreleasepool {
    if (n > GPUSRC_MAX) return 1;
    gDev = MTLCreateSystemDefaultDevice();
    if (!gDev) return 2;
    gQueue = [gDev newCommandQueue];
    gW = CVPixelBufferGetWidth(ring[0]);
    gH = CVPixelBufferGetHeight(ring[0]);
    MTLTextureDescriptor* dy = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                     width:gW
                                    height:gH
                                 mipmapped:NO];
    MTLTextureDescriptor* duv = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRG8Unorm
                                     width:gW / 2
                                    height:gH / 2
                                 mipmapped:NO];
    for (int i = 0; i < n; i++) {
      gSrcY[i] = [gDev newTextureWithDescriptor:dy];
      gSrcUV[i] = [gDev newTextureWithDescriptor:duv];
      CVPixelBufferLockBaseAddress(ring[i], kCVPixelBufferLock_ReadOnly);
      [gSrcY[i] replaceRegion:MTLRegionMake2D(0, 0, gW, gH)
                  mipmapLevel:0
                    withBytes:CVPixelBufferGetBaseAddressOfPlane(ring[i], 0)
                  bytesPerRow:CVPixelBufferGetBytesPerRowOfPlane(ring[i], 0)];
      [gSrcUV[i] replaceRegion:MTLRegionMake2D(0, 0, gW / 2, gH / 2)
                   mipmapLevel:0
                     withBytes:CVPixelBufferGetBaseAddressOfPlane(ring[i], 1)
                   bytesPerRow:CVPixelBufferGetBytesPerRowOfPlane(ring[i], 1)];
      CVPixelBufferUnlockBaseAddress(ring[i], kCVPixelBufferLock_ReadOnly);
      IOSurfaceRef s = CVPixelBufferGetIOSurface(dst[i]);
      if (!s) return 3;
      gDstY[i] = [gDev newTextureWithDescriptor:dy iosurface:s plane:0];
      gDstUV[i] = [gDev newTextureWithDescriptor:duv iosurface:s plane:1];
      if (!gSrcY[i] || !gSrcUV[i] || !gDstY[i] || !gDstUV[i]) return 4;
    }
  }
  return 0;
}

// Copy source frame k into destination buffer i on the GPU and wait for the
// copy. Returns 0 on success.
int gpusrc_fill(int i, int k) {
  @autoreleasepool {
    id<MTLCommandBuffer> cmd = [gQueue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cmd blitCommandEncoder];
    [blit copyFromTexture:gSrcY[k]
              sourceSlice:0
              sourceLevel:0
             sourceOrigin:MTLOriginMake(0, 0, 0)
               sourceSize:MTLSizeMake(gW, gH, 1)
                toTexture:gDstY[i]
         destinationSlice:0
         destinationLevel:0
        destinationOrigin:MTLOriginMake(0, 0, 0)];
    [blit copyFromTexture:gSrcUV[k]
              sourceSlice:0
              sourceLevel:0
             sourceOrigin:MTLOriginMake(0, 0, 0)
               sourceSize:MTLSizeMake(gW / 2, gH / 2, 1)
                toTexture:gDstUV[i]
         destinationSlice:0
         destinationLevel:0
        destinationOrigin:MTLOriginMake(0, 0, 0)];
    [blit endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];
    return cmd.status == MTLCommandBufferStatusCompleted ? 0 : 5;
  }
}
