// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Darwin

struct VMStatisticsSnapshot: Equatable {
    let wiredPages: UInt64
    let purgeablePages: UInt64
    let compressorPages: UInt64
    let externalPages: UInt64
    let internalPages: UInt64
    let tagStoragePages: UInt64
    /// Pages read in from and written out to backing store since boot.
    let pageIns: UInt64
    let pageOuts: UInt64
}

/// Reads HOST_VM_INFO64 without a C shim. Older SDKs stop before the fields
/// macOS 26 appended (rev2 `swapped_count`, rev3 tagged storage), so the call
/// gets a buffer sized for rev3 and only the newer field it needs is read by
/// offset; everything else comes through the SDK's own `vm_statistics64`.
enum VMStatisticsDecoder {
    /// Counts are in 32-bit `integer_t` words, as `host_statistics64` expects.
    /// rev1 ends at `swapped_count` (byte 152), rev2 at `total_tag_storage_pages`
    /// (byte 160) and rev3 at the end of the 248-byte structure.
    static let rev1Count: mach_msg_type_number_t = 38
    static let rev2Count: mach_msg_type_number_t = 40
    static let rev3Count: mach_msg_type_number_t = 62

    static let payloadByteCount = Int(rev3Count) * MemoryLayout<integer_t>.size
    static let tagStoragePagesOffset = 160

    /// A rev3-sized payload. `UInt64` storage keeps it 8-byte aligned, as the
    /// kernel's structure is.
    struct Payload {
        var words = [UInt64](repeating: 0, count: VMStatisticsDecoder.payloadByteCount / 8)

        var tagStoragePages: UInt64 {
            get { words[VMStatisticsDecoder.tagStoragePagesOffset / 8] }
            set { words[VMStatisticsDecoder.tagStoragePagesOffset / 8] = newValue }
        }

        /// The prefix every SDK describes. The imported structure is never
        /// larger than the rev3 payload, so the load stays in bounds.
        var prefix: vm_statistics64 {
            get {
                words.withUnsafeBytes { $0.loadUnaligned(as: vm_statistics64.self) }
            }
            set {
                var value = newValue
                words.withUnsafeMutableBytes { bytes in
                    withUnsafeBytes(of: &value) { source in
                        bytes.copyMemory(from: source)
                    }
                }
            }
        }
    }

    static func read() -> VMStatisticsSnapshot? {
        precondition(MemoryLayout<vm_statistics64>.size <= payloadByteCount,
                     "vm_statistics64 grew past the rev3 payload")
        var payload = Payload()
        var returnedCount = rev3Count
        // mach_host_self() returns a send right the caller owns; release it or
        // each sample leaks a mach port.
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = payload.words.withUnsafeMutableBytes { bytes in
            host_statistics64(host,
                              HOST_VM_INFO64,
                              bytes.baseAddress!.assumingMemoryBound(to: integer_t.self),
                              &returnedCount)
        }
        guard result == KERN_SUCCESS else { return nil }
        return decode(payload, returnedCount: returnedCount)
    }

    /// `returnedCount` is the revision the kernel filled: it writes only the
    /// newest one that fits, so an older kernel returns a shorter count and
    /// tagged storage stays unavailable.
    static func decode(_ payload: Payload,
                       returnedCount: mach_msg_type_number_t) -> VMStatisticsSnapshot? {
        guard returnedCount >= rev1Count else { return nil }
        let raw = payload.prefix
        return VMStatisticsSnapshot(
            wiredPages: UInt64(raw.wire_count),
            purgeablePages: UInt64(raw.purgeable_count),
            compressorPages: UInt64(raw.compressor_page_count),
            externalPages: UInt64(raw.external_page_count),
            internalPages: UInt64(raw.internal_page_count),
            tagStoragePages: returnedCount >= rev3Count ? payload.tagStoragePages : 0,
            pageIns: UInt64(raw.pageins),
            pageOuts: UInt64(raw.pageouts))
    }

    static func validatedTagStoragePages(_ pages: UInt64,
                                         totalBytes: UInt64,
                                         pageSize: UInt64) -> UInt64 {
        guard pageSize > 0, pages <= totalBytes / pageSize else { return 0 }
        return pages
    }
}
