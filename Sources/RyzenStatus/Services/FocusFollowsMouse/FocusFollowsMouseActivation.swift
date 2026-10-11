// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Generation counter for focus-follows-mouse handoffs. A newer hover
/// supersedes an older one still waiting on its delayed focus record, so a
/// canceled handoff never lands after the pointer has moved on.
extension WindowActivator {
    private static let focusHandoffLock = NSLock()
    private static var focusHandoffGeneration: UInt64 = 0

    static func supersedePendingActivations(for pid: pid_t) -> UInt64 {
        focusHandoffLock.withLock {
            focusHandoffGeneration &+= 1
            return focusHandoffGeneration
        }
    }

    static func isCurrentActivation(_ generation: UInt64) -> Bool {
        focusHandoffLock.withLock { generation == focusHandoffGeneration }
    }
}
