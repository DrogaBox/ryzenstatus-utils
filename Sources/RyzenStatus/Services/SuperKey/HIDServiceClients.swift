// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import IOKit

/// The few IOHIDEventSystemClient calls Super Key needs to reach one keyboard
/// at a time. The functions are public C API in IOKit, but Swift's IOKit module
/// does not import their header, so they are looked up once by name instead of
/// through a separate module map. Every call degrades to "nothing found" when a
/// symbol is missing, which leaves the keyboards exactly as they were.
enum HIDServiceClients {
    private typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias CopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias ConformsTo = @convention(c) (CFTypeRef, UInt32, UInt32) -> DarwinBoolean
    private typealias CopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias SetProperty = @convention(c) (CFTypeRef, CFString, CFTypeRef) -> DarwinBoolean

    private nonisolated(unsafe) static let handle =
        dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private nonisolated(unsafe) static let createClient =
        symbol("IOHIDEventSystemClientCreateSimpleClient", as: CreateClient.self)
    private nonisolated(unsafe) static let copyServices =
        symbol("IOHIDEventSystemClientCopyServices", as: CopyServices.self)
    private nonisolated(unsafe) static let conformsTo =
        symbol("IOHIDServiceClientConformsTo", as: ConformsTo.self)
    private nonisolated(unsafe) static let copyProperty =
        symbol("IOHIDServiceClientCopyProperty", as: CopyProperty.self)
    private nonisolated(unsafe) static let setProperty =
        symbol("IOHIDServiceClientSetProperty", as: SetProperty.self)

    /// A client of the HID event system. The services it lists read and write
    /// their properties through its connection, so keep it alive while using them.
    static func makeClient() -> CFTypeRef? {
        createClient?(kCFAllocatorDefault)?.takeRetainedValue()
    }

    static func services(of client: CFTypeRef) -> [CFTypeRef] {
        guard let array = copyServices?(client)?.takeRetainedValue() else { return [] }
        return (array as NSArray).map { $0 as CFTypeRef }
    }

    static func conforms(_ service: CFTypeRef, page: UInt32, usage: UInt32) -> Bool {
        conformsTo?(service, page, usage).boolValue ?? false
    }

    static func property(_ service: CFTypeRef, _ key: CFString) -> CFTypeRef? {
        copyProperty?(service, key)?.takeRetainedValue()
    }

    @discardableResult
    static func set(_ service: CFTypeRef, _ key: CFString, _ value: CFTypeRef) -> Bool {
        setProperty?(service, key, value).boolValue ?? false
    }
}
