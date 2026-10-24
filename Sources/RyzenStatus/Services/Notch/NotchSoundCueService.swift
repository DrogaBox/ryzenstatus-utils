// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Foundation

enum NotchSoundCue: String, CaseIterable {
    case start = "agent_start"
    case confirm = "agent_confirm"
    case approval = "agent_approval"
    case complete = "agent_complete"
    case error = "agent_error"
    case idle = "agent_idle"
    case launch = "agent_launch"
    case rapid = "agent_rapid"
    case context = "agent_context"
}

final class NotchSoundCueService: @unchecked Sendable {
    static let shared = NotchSoundCueService()
    private var cachedSounds: [String: NSSound] = [:]

    private init() {}

    func play(_ cue: NotchSoundCue) {
        DispatchQueue.main.async {
            guard UserDefaults.standard.bool(forKey: DefaultsKey.notchIslandSoundCues) else { return }
            let name = cue.rawValue
            if let sound = self.cachedSounds[name] {
                sound.stop()
                sound.play()
                return
            }
            let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
                ?? Bundle.main.url(forResource: name, withExtension: "wav")
            guard let url, let sound = NSSound(contentsOf: url, byReference: true) else { return }
            self.cachedSounds[name] = sound
            sound.play()
        }
    }
}
