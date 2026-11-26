//
//  jpeg_normalize.hpp - rewrites a baseline JPEG file into the exact shape Mesa
//  hands the VCN JPEG block: SOI, one DQT segment, one DHT segment (DC tables,
//  then AC tables), DRI if there is a restart interval, SOF0, SOS, the scan,
//  EOI. That is what vlVaGetJpegSliceHeader (src/gallium/frontends/va/
//  picture_mjpeg.c) builds in front of the scan data; APPn and COM segments
//  never reach the hardware there, so they are dropped here too.
//  User space only (tool and tests).
//
#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace jnorm {

struct Tables {
  bool haveQ[4] = {};
  uint8_t q[4][64] = {};
  bool haveH[2][2] = {};         // [class 0 DC / 1 AC][id]
  std::vector<uint8_t> h[2][2];  // 16 counts + values
  uint16_t restart = 0;
  std::vector<uint8_t> sof, sos;  // segment bodies, without marker and length
  std::vector<uint8_t> scan;      // entropy-coded data, without EOI
};

inline void seg(std::vector<uint8_t>& o, uint8_t marker,
                const std::vector<uint8_t>& body) {
  o.push_back(0xff);
  o.push_back(marker);
  o.push_back(static_cast<uint8_t>((body.size() + 2) >> 8));
  o.push_back(static_cast<uint8_t>(body.size() + 2));
  o.insert(o.end(), body.begin(), body.end());
}

// Returns an empty string and fills `out`, or says why the file is not handled.
inline std::string normalize(const std::vector<uint8_t>& in,
                             std::vector<uint8_t>* out) {
  const uint8_t* d = in.data();
  size_t n = in.size();
  if (n < 4 || d[0] != 0xff || d[1] != 0xd8) return "not a JPEG (no SOI)";
  Tables t;
  size_t i = 2;
  bool gotScan = false;
  while (!gotScan) {
    if (i + 4 > n) return "no scan found";
    if (d[i] != 0xff) return "marker expected at byte " + std::to_string(i);
    uint8_t m = d[i + 1];
    size_t len = (static_cast<size_t>(d[i + 2]) << 8) | d[i + 3];
    if (len < 2 || i + 2 + len > n)
      return "segment at byte " + std::to_string(i) + " does not fit";
    const uint8_t* s = d + i + 4;
    size_t body = len - 2;
    if (m == 0xdb) {
      size_t p = 0;
      while (p < body) {
        uint8_t pq = s[p] >> 4, tq = s[p] & 15;
        if (pq != 0) return "16-bit quantisation table";
        if (tq > 3 || p + 65 > body) return "bad quantisation table";
        t.haveQ[tq] = true;
        for (int k = 0; k < 64; k++) t.q[tq][k] = s[p + 1 + k];
        p += 65;
      }
    } else if (m == 0xc4) {
      size_t p = 0;
      while (p < body) {
        uint8_t tc = s[p] >> 4, th = s[p] & 15;
        if (tc > 1 || th > 1 || p + 17 > body)
          return "Huffman table the block is not given by Mesa (class or id "
                 "above 1)";
        size_t count = 0;
        for (int k = 0; k < 16; k++) count += s[p + 1 + k];
        if (count > (tc == 0 ? 12u : 162u) || p + 17 + count > body)
          return "bad Huffman table";
        t.haveH[tc][th] = true;
        t.h[tc][th].assign(s + p + 1, s + p + 17 + count);
        p += 17 + count;
      }
    } else if (m == 0xdd) {
      if (body != 2) return "bad restart interval segment";
      t.restart = static_cast<uint16_t>((s[0] << 8) | s[1]);
    } else if (m == 0xc0) {
      if (!t.sof.empty()) return "more than one frame header";
      t.sof.assign(s, s + body);
    } else if (m == 0xda) {
      t.sos.assign(s, s + body);
      gotScan = true;
    } else if ((m >= 0xe0 && m <= 0xef) || m == 0xfe) {
      // dropped
    } else if (m >= 0xc1 && m <= 0xcf && m != 0xc4 && m != 0xc8 && m != 0xcc) {
      return "not a baseline JPEG (frame type 0x" +
             std::string(1, "0123456789abcdef"[m >> 4]) +
             std::string(1, "0123456789abcdef"[m & 15]) + ")";
    } else {
      return "segment the test does not handle at byte " + std::to_string(i);
    }
    i += 2 + len;
  }
  if (t.sof.empty()) return "scan before the frame header";
  // The scan runs to the first marker that is neither a stuffed FF00 nor RSTn.
  size_t e = i;
  while (true) {
    if (e + 1 >= n) return "no EOI after the scan";
    if (d[e] == 0xff && d[e + 1] != 0x00 &&
        !(d[e + 1] >= 0xd0 && d[e + 1] <= 0xd7))
      break;
    e++;
  }
  if (d[e + 1] != 0xd9) return "more than one scan";
  t.scan.assign(d + i, d + e);
  bool anyQ = false, anyH = false;
  std::vector<uint8_t> dqt, dht;
  for (int k = 0; k < 4; k++) {
    if (!t.haveQ[k]) continue;
    anyQ = true;
    dqt.push_back(static_cast<uint8_t>(k));
    dqt.insert(dqt.end(), t.q[k], t.q[k] + 64);
  }
  for (int c = 0; c < 2; c++) {
    for (int k = 0; k < 2; k++) {
      if (!t.haveH[c][k]) continue;
      anyH = true;
      dht.push_back(static_cast<uint8_t>((c << 4) | k));
      dht.insert(dht.end(), t.h[c][k].begin(), t.h[c][k].end());
    }
  }
  if (!anyQ) return "no quantisation tables";
  if (!anyH)
    return "no Huffman tables in the file (a bare MJPEG frame); not handled "
           "yet";
  std::vector<uint8_t>& o = *out;
  o.clear();
  o.push_back(0xff);
  o.push_back(0xd8);
  seg(o, 0xdb, dqt);
  seg(o, 0xc4, dht);
  if (t.restart != 0)
    seg(o, 0xdd,
        {static_cast<uint8_t>(t.restart >> 8),
         static_cast<uint8_t>(t.restart)});
  seg(o, 0xc0, t.sof);
  seg(o, 0xda, t.sos);
  o.insert(o.end(), t.scan.begin(), t.scan.end());
  o.push_back(0xff);
  o.push_back(0xd9);
  return "";
}

}  // namespace jnorm
