// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Swift mirror of the kext's zero-copy telemetry packet
/// (`AMDRyzenCPUPowerManagement::CPUSensorPacket`, selector 100).
///
/// Layout verified against the kext source (`#pragma pack(push, 1)`):
///
///     offset  size  field
///     0       4     packagePowerW          (float)
///     4       4     packageTempC           (float)
///     8       4     numLogicalCores        (uint32_t)
///     12      4     ccdCount               (uint32_t)
///     16      32    ccdTemperatures[8]     (float)
///     48      256   coreFrequenciesMHz[64] (float)
///     ─────
///     304 bytes total
///
/// The Swift struct keeps friendly `[Float]` arrays; the wire contract lives
/// in `parse(_:)`, which reads field by field with `load(fromByteOffset:as:)`
/// at exactly those offsets. Pure Foundation so `./build.sh --test` can lock
/// the layout contract on any machine.
struct CPUSensorPacket: Equatable {
    /// Total wire size of the kext packet, in bytes.
    static let byteSize = 304
    static let maxCCDs = 8
    static let maxCores = 64

    var packagePowerW: Float = 0
    var packageTempC: Float = 0
    var numLogicalCores: UInt32 = 0
    var ccdCount: UInt32 = 0
    var ccdTemperatures = Array(repeating: Float(0), count: maxCCDs)
    var coreFrequenciesMHz = Array(repeating: Float(0), count: maxCores)

    /// Parses the raw packet bytes returned by selector 100.
    /// Returns nil when fewer than `byteSize` bytes are provided.
    static func parse(_ bytes: [UInt8]) -> CPUSensorPacket? {
        guard bytes.count >= byteSize else { return nil }
        var packet = CPUSensorPacket()
        bytes.withUnsafeBytes { raw -> Void in
            guard let base = raw.baseAddress else { return }
            packet.packagePowerW = base.load(fromByteOffset: 0, as: Float.self)
            packet.packageTempC = base.load(fromByteOffset: 4, as: Float.self)
            packet.numLogicalCores = base.load(fromByteOffset: 8, as: UInt32.self)
            packet.ccdCount = base.load(fromByteOffset: 12, as: UInt32.self)
            for i in 0..<maxCCDs {
                packet.ccdTemperatures[i] = base.load(fromByteOffset: 16 + i * 4, as: Float.self)
            }
            for i in 0..<maxCores {
                packet.coreFrequenciesMHz[i] = base.load(fromByteOffset: 48 + i * 4, as: Float.self)
            }
        }
        return packet
    }

    /// Core frequencies actually populated (non-zero), for min/avg/max readouts.
    var activeFrequenciesMHz: [Float] {
        coreFrequenciesMHz.filter { $0 > 0 }
    }
}
