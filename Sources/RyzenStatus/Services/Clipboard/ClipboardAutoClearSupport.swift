// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

enum ClipboardAutoClearDecision: Equatable {
    case noteChange, clear, wait
}

enum ClipboardAutoClearSupport {
    static func clearIsAuthorized(enqueuedGeneration: Int,
                                  currentGeneration: Int,
                                  featureIsAvailable: Bool,
                                  triggerIsEnabled: Bool) -> Bool {
        enqueuedGeneration == currentGeneration && featureIsAvailable && triggerIsEnabled
    }

    /// - Parameters:
    ///   - changeCount: the count just read from the pasteboard.
    ///   - lastChangeCount: the count this service last acted on.
    ///   - lastClearedChangeCount: the count our own clear produced.
    ///   - lastChangeDate: when `lastChangeCount` was first seen.
    ///   - delay: seconds of stillness before content is cleared.
    static func decide(changeCount: Int,
                       lastChangeCount: Int,
                       lastClearedChangeCount: Int,
                       lastChangeDate: Date,
                       now: Date,
                       delay: TimeInterval) -> ClipboardAutoClearDecision {
        guard changeCount == lastChangeCount else { return .noteChange }
        guard changeCount != lastClearedChangeCount, delay.isFinite, delay > 0 else { return .wait }
        return now.timeIntervalSince(lastChangeDate) >= delay ? .clear : .wait
    }
}
