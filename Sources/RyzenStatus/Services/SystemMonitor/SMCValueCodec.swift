// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Encodes and decodes the fixed-size payloads the SMC uses for each data type.
/// Lives outside the fan-control feature because the SMC client writes values
/// through the same codec.
enum SMCValueCodec {
    static func decode(_ bytes: [UInt8], type: String) -> Double? {
        switch type {
        case "flt " where bytes.count == 4:
            let bits = UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
            let value = Double(Float32(bitPattern: bits))
            return value.isFinite ? value : nil
        case "fpe2" where bytes.count == 2:
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(raw) / 4.0
        case "sp78" where bytes.count == 2:
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(Int16(bitPattern: raw)) / 256.0
        case "ui8 " where bytes.count == 1:
            return Double(bytes[0])
        case "ui16" where bytes.count == 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32" where bytes.count == 4:
            return Double(UInt32(bytes[0]) << 24
                          | UInt32(bytes[1]) << 16
                          | UInt32(bytes[2]) << 8
                          | UInt32(bytes[3]))
        case "ioft" where bytes.count == 8:
            var raw: UInt64 = 0
            for (offset, byte) in bytes.enumerated() {
                raw |= UInt64(byte) << UInt64(offset * 8)
            }
            return Double(raw) / 65_536.0
        default:
            return nil
        }
    }

    static func encode(_ value: Double, type: String, size: Int) -> [UInt8]? {
        guard value.isFinite, value >= 0 else { return nil }
        switch type {
        case "flt " where size == 4:
            let float = Float32(value)
            guard float.isFinite else { return nil }
            let bits = float.bitPattern
            return [UInt8(bits & 0xff), UInt8((bits >> 8) & 0xff),
                    UInt8((bits >> 16) & 0xff), UInt8((bits >> 24) & 0xff)]
        case "fpe2" where size == 2:
            let scaled = (value * 4).rounded()
            guard scaled <= Double(UInt16.max) else { return nil }
            let raw = UInt16(scaled)
            return [UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        case "ui8 " where size == 1:
            guard value.rounded() == value, value <= Double(UInt8.max) else { return nil }
            return [UInt8(value)]
        case "ui16" where size == 2:
            guard value.rounded() == value, value <= Double(UInt16.max) else { return nil }
            let raw = UInt16(value)
            return [UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        case "ui32" where size == 4:
            guard value.rounded() == value, value <= Double(UInt32.max) else { return nil }
            let raw = UInt32(value)
            return [UInt8((raw >> 24) & 0xff), UInt8((raw >> 16) & 0xff),
                    UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        default:
            return nil
        }
    }
}
