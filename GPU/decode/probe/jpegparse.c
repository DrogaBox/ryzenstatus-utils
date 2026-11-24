#include "jpegparse.h"

int jpeg_parse(const uint8_t* data, size_t size, JpegPicture* out, char* err,
               size_t errLen) {
  memset(out, 0, sizeof(*out));
  if (size < 4 || data[0] != 0xFF || data[1] != 0xD8) {
    copy_err(err, errLen, "not a JPEG (no SOI)");
    return -1;
  }
  size_t i = 2;
  int sawSof = 0, sawSos = 0;
  while (i + 3 < size) {
    if (data[i] != 0xFF) {  // fill bytes are allowed before a marker
      i++;
      continue;
    }
    uint8_t m = data[i + 1];
    if (m == 0xFF) {
      i++;
      continue;
    }
    if (m == 0xD9) break;  // EOI
    if (m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {  // RSTn / TEM: no payload
      i += 2;
      continue;
    }
    if (i + 4 > size) break;
    size_t len = ((size_t)data[i + 2] << 8) | data[i + 3];  // includes itself
    if (len < 2 || i + 2 + len > size) {
      copy_err(err, errLen, "JPEG marker length past the end");
      return -1;
    }
    const uint8_t* p = data + i + 4;
    size_t payload = len - 2;
    if (m == 0xC0 || m == 0xC1 || m == 0xC2) {
      if (m != 0xC0) {
        copy_err(err, errLen, "JPEG is not baseline (SOF0)");
        return -1;
      }
      if (payload < 6) {
        copy_err(err, errLen, "JPEG SOF0 too short");
        return -1;
      }
      out->precision = p[0];
      out->au.height = ((uint32_t)p[1] << 8) | p[2];
      out->au.width = ((uint32_t)p[3] << 8) | p[4];
      out->components = p[5];
      if (out->precision != 8 || out->components != 3) {
        copy_err(err, errLen, "JPEG is not 8-bit 3-component");
        return -1;
      }
      if (payload < 6 + 3u * out->components) {
        copy_err(err, errLen, "JPEG SOF0 component list too short");
        return -1;
      }
      unsigned hy = p[7] >> 4, vy = p[7] & 15;
      unsigned hc = p[10] >> 4, vc = p[10] & 15;
      if (hy == 2 && vy == 2 && hc == 1 && vc == 1)
        out->sampling = 1;  // 4:2:0
      else if (hy == 2 && vy == 1 && hc == 1 && vc == 1)
        out->sampling = 2;  // 4:2:2
      else if (hy == 1 && vy == 1 && hc == 1 && vc == 1)
        out->sampling = 3;  // 4:4:4
      else {
        copy_err(err, errLen, "JPEG chroma sampling is not 4:2:0/4:2:2/4:4:4");
        return -1;
      }
      sawSof = 1;
    } else if (m == 0xDD) {  // DRI
      if (payload >= 2)
        out->restartInterval = (uint16_t)(((uint16_t)p[0] << 8) | p[1]);
    } else if (m == 0xDA) {  // SOS: the scan runs to the next real marker
      sawSos = 1;
      size_t j = i + 2 + len;
      while (j + 1 < size) {
        if (data[j] == 0xFF) {
          uint8_t n = data[j + 1];
          if (n == 0x00 || (n >= 0xD0 && n <= 0xD7)) {
            j += 2;  // stuffed byte / restart marker
            continue;
          }
          break;
        }
        j++;
      }
      i = j;
      continue;
    }
    i += 2 + len;
  }
  if (!sawSof) {
    copy_err(err, errLen, "no JPEG SOF0");
    return -1;
  }
  if (!sawSos) {
    copy_err(err, errLen, "no JPEG scan (SOS)");
    return -1;
  }
  if (!out->au.width || !out->au.height) {
    copy_err(err, errLen, "JPEG has no size");
    return -1;
  }
  out->au.au = data;
  out->au.auSize = size;
  out->au.intra = 1;
  return 0;
}
