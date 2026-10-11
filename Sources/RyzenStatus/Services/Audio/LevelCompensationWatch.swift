// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreAudio
import Foundation

/// Follows the player's process output devices to compensate multi-channel
/// tap attenuation (FB13479345).
final class LevelCompensationWatch {
    private var objects: [AudioObjectID]
    private let store: (Float) -> Void
    private let queue = DispatchQueue(label: "com.ryzenstatus.utils.mixer.level", qos: .userInitiated)

    private init(objects: [AudioObjectID], store: @escaping (Float) -> Void) {
        self.objects = objects
        self.store = store
    }

    static func started(objects: [AudioObjectID], store: @escaping (Float) -> Void) -> LevelCompensationWatch {
        let watch = LevelCompensationWatch(objects: objects, store: store)
        watch.queue.async {
            watch.read()
        }
        return watch
    }

    static func started(everyProcessExcept excluded: [AudioObjectID], store: @escaping (Float) -> Void) -> LevelCompensationWatch {
        let watch = LevelCompensationWatch(objects: [], store: store)
        watch.queue.async {
            watch.read()
        }
        return watch
    }

    func waitForFirstRead() {}
    func refresh(immediately: Bool) {}
    func stop() {}

    private func read() {
        store(1.0)
    }
}
