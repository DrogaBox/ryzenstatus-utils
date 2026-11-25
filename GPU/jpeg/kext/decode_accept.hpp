//
//  decode_accept.hpp - the check every JPEG passes before anything counts as
//  loaded. Included by kern_start.cpp, and by tests/apps_test.cpp so that the
//  host test of the apps door runs this exact code.
//  Needs: gPool, gP, gLoadedBytes, gDecoded, gStream, gLayout.
//
// Checks the JPEG that was just copied into the bitstream buffer, reads its
// size from it and pads it. Nothing counts as loaded unless this returns Ok.
static jc::Stream decodeAccept(size_t size) {
  gLoadedBytes = 0;
  gDecoded = false;
  uint8_t* bs = gPool + gP.bitstream;
  jc::StreamInfo info;
  jc::Stream st = jc::parseStream(bs, size, &info);
  if (st != jc::Stream::Ok) return st;
  jc::Layout layout{};
  if (!jc::outputLayout(info.width, info.height, gP.surfaceCap, &layout,
                        info.chroma))
    return jc::Stream::BadFrame;
  uint32_t padded = jc::alignUp(static_cast<uint32_t>(size), 128);
  memset(bs + size, 0, padded - size);
  gStream = info;
  gLayout = layout;
  gLoadedBytes = padded;
  return jc::Stream::Ok;
}
