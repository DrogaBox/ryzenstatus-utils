// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AVFoundation
import Foundation

/// The sounds the companions make as they play. Each one is synthesised from a
/// few tones and a little noise, once, the first time it is asked for, so the
/// app carries no audio files.
enum NotchMascotSoundEffect: CaseIterable {
    case coin, boing, squeak, honk, splat, boom, magic, poof, pop, chime, whoosh, creak, sad, zap, munch, fire
}

/// What each thing that happens in a play sounds like. Pure, so it is tested.
enum NotchMascotSoundMap {
    typealias Island = NotchMascotIslandPlay

    /// The sound of a burst over one of them.
    static func effect(for burst: Island.Burst) -> NotchMascotSoundEffect {
        switch burst {
        case .confetti: return .pop
        case .sparkles: return .magic
        case .hearts: return .chime
        case .magic: return .magic
        case .coins: return .coin
        case .smoke: return .poof
        case .door: return .creak
        }
    }

    /// The sound of a thing leaving a hand.
    static func launch(of thing: Island.Thing) -> NotchMascotSoundEffect {
        switch thing {
        case .fireball: return .fire
        case .bolt: return .zap
        case .tornado: return .whoosh
        case .duck: return .squeak
        case .coin, .bag: return .coin
        case .snack: return .munch
        case .balloon: return .boing
        default: return .whoosh
        }
    }

    /// The sound of a thing arriving.
    static func landing(of thing: Island.Thing) -> NotchMascotSoundEffect {
        switch thing {
        case .pie, .peel: return .splat
        case .dynamite: return .boom
        case .fireball: return .poof
        case .coin, .bag, .key: return .coin
        case .snack: return .munch
        case .heart, .flower: return .chime
        default: return .pop
        }
    }

    /// The sound of a word that floats up over one of them, when it has its own.
    static func effect(forMarker text: String) -> NotchMascotSoundEffect? {
        switch text.uppercased() {
        case "BOOM": return .boom
        case "QUACK": return .squeak
        case "HONK": return .honk
        case "SPLAT", "SLAP", "WHOA": return .splat
        case "SNIF", "BYE": return .sad
        case "CHOMP", "YUM", "GULP", "NOM": return .munch
        case "RING": return .chime
        case "PFFT": return .poof
        case "1UP", "COPY": return .magic
        default: return nil
        }
    }

    /// One sound to be heard, from the companion or from its friend, `delay` seconds in.
    struct Cue: Equatable {
        var effect: NotchMascotSoundEffect
        var onLeader: Bool
        var delay: TimeInterval = 0
    }

    /// What a beat of a play sounds like: a thing leaving, then arriving, a
    /// burst, and a word.
    static func cues(for beat: Island.Beat) -> [Cue] {
        var cues: [Cue] = []
        if let flight = beat.flight {
            cues.append(Cue(effect: launch(of: flight.thing), onLeader: flight.fromLeader))
            if !flight.falls {
                cues.append(Cue(effect: landing(of: flight.thing), onLeader: !flight.fromLeader,
                                delay: flight.duration * 0.92))
            }
        }
        if let burst = beat.burst {
            cues.append(Cue(effect: effect(for: burst.burst), onLeader: burst.onLeader))
        }
        if let marker = beat.marker, let effect = effect(forMarker: marker.text) {
            cues.append(Cue(effect: effect, onLeader: marker.onLeader, delay: 0.05))
        }
        return cues
    }

    /// Where a sound is heard between the speakers for something at `x` across a
    /// screen `width` wide: the middle of the screen is the middle, and a
    /// companion near either side is heard clearly from that side.
    static func pan(x: CGFloat, width: CGFloat) -> Float {
        guard width > 0 else { return 0 }
        let centered = (x - width / 2) / (width * 0.18)
        return Float(max(-1, min(1, tanh(Double(centered)))))
    }

    /// The pair at rest in the island sits at the middle of the screen: the
    /// one on the left is heard on the left.
    static func islandPan(onLeader: Bool, leaderOnLeft: Bool) -> Float {
        (onLeader == leaderOnLeft) ? -0.7 : 0.7
    }
}

/// Plays the effects through its own small engine: stereo, panned to where the
/// action is, at the volume chosen in Settings, and off when it is switched
/// off. The engine runs only while something sounds and rests a few seconds
/// after.
@MainActor
final class NotchMascotSound {
    static let shared = NotchMascotSound()

    static let defaultVolume = 0.35
    private static let voices = 6
    private static let rate = 44_100.0
    private static let idle: TimeInterval = 6

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [NotchMascotSoundEffect: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [NotchMascotSoundEffect: CFTimeInterval] = [:]
    private var stopWork: DispatchWorkItem?
    private var built = false
    private let format = AVAudioFormat(standardFormatWithSampleRate: NotchMascotSound.rate, channels: 1)!

    static var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: DefaultsKey.notchMascotSound) as? Bool) ?? true
    }

    static var volume: Double {
        let stored = UserDefaults.standard.object(forKey: DefaultsKey.notchMascotSoundVolume) as? Double
        return min(1, max(0, stored ?? defaultVolume))
    }

    /// Plays `effect` from `pan` (-1 left, 0 middle, 1 right) after `delay`
    /// seconds, from anywhere on the main thread.
    nonisolated static func play(_ effect: NotchMascotSoundEffect, pan: Float = 0, after delay: TimeInterval = 0) {
        let run = {
            MainActor.assumeIsolated { shared.play(effect, pan: pan, test: false) }
        }
        if delay > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: run) } else { run() }
    }

    /// The cues of a beat of a play in the island or on the Settings stage.
    nonisolated static func play(cues: [NotchMascotSoundMap.Cue], leaderOnLeft: Bool) {
        for cue in cues {
            play(cue.effect, pan: NotchMascotSoundMap.islandPan(onLeader: cue.onLeader, leaderOnLeft: leaderOnLeft),
                 after: cue.delay)
        }
    }

    /// A sample, for the Settings slider: heard even with the sounds switched off.
    func preview() { play(.coin, pan: 0, test: true) }

    private func play(_ effect: NotchMascotSoundEffect, pan: Float, test: Bool) {
        guard test || Self.isEnabled, Self.volume > 0 else { return }
        let now = CACurrentMediaTime()
        // The same sound twice in a few frames is one sound.
        if let last = lastPlayed[effect], now - last < 0.06 { return }
        lastPlayed[effect] = now
        guard prepare() else { return }
        let buffer = buffers[effect] ?? Self.render(effect, format: format)
        buffers[effect] = buffer
        engine.mainMixerNode.outputVolume = Float(Self.volume)
        let player = players[next]
        next = (next + 1) % players.count
        player.pan = max(-1, min(1, pan))
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
        scheduleStop()
    }

    private func prepare() -> Bool {
        if !built {
            for _ in 0..<Self.voices {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                players.append(player)
            }
            built = true
        }
        if !engine.isRunning {
            do { try engine.start() } catch { return false }
        }
        return true
    }

    /// Rests the engine a few seconds after the last sound.
    private func scheduleStop() {
        stopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.players.forEach { $0.stop() }
            self.engine.stop()
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idle, execute: work)
    }

    // MARK: Synthesis

    private enum Wave { case sine, square, triangle, saw, noise }

    private struct Tone {
        var start: Double
        var length: Double
        var from: Double
        var to: Double
        var wave: Wave = .sine
        var level: Double = 0.6
        var vibrato: Double = 0
        /// One-pole low-pass cutoff in Hz for noise; 0 leaves it open.
        var cutoff: Double = 0
        var decay: Double = 3
    }

    private static func recipe(_ effect: NotchMascotSoundEffect) -> [Tone] {
        switch effect {
        case .coin:
            return [Tone(start: 0, length: 0.07, from: 988, to: 988, wave: .square, level: 0.28, decay: 1.2),
                    Tone(start: 0.07, length: 0.26, from: 1319, to: 1319, wave: .square, level: 0.28, decay: 4)]
        case .boing:
            return [Tone(start: 0, length: 0.4, from: 180, to: 540, wave: .sine, level: 0.6, vibrato: 14, decay: 2.2)]
        case .squeak:
            return [Tone(start: 0, length: 0.07, from: 1700, to: 2500, wave: .triangle, level: 0.5, decay: 1.4),
                    Tone(start: 0.1, length: 0.09, from: 1900, to: 2800, wave: .triangle, level: 0.5, decay: 2)]
        case .honk:
            return [Tone(start: 0, length: 0.3, from: 233, to: 220, wave: .square, level: 0.3, vibrato: 5, decay: 1.6),
                    Tone(start: 0, length: 0.3, from: 294, to: 277, wave: .square, level: 0.2, vibrato: 5, decay: 1.6)]
        case .splat:
            return [Tone(start: 0, length: 0.3, from: 0, to: 0, wave: .noise, level: 0.7, cutoff: 900, decay: 5),
                    Tone(start: 0, length: 0.18, from: 150, to: 55, wave: .sine, level: 0.5, decay: 4)]
        case .boom:
            return [Tone(start: 0, length: 0.8, from: 0, to: 0, wave: .noise, level: 0.8, cutoff: 500, decay: 3.2),
                    Tone(start: 0, length: 0.7, from: 80, to: 28, wave: .sine, level: 0.8, decay: 3)]
        case .magic:
            return [880, 1109, 1319, 1760, 2217].enumerated().map { index, freq in
                Tone(start: Double(index) * 0.065, length: 0.22, from: freq, to: freq * 1.01, wave: .sine,
                     level: 0.28, decay: 4)
            }
        case .poof:
            return [Tone(start: 0, length: 0.22, from: 0, to: 0, wave: .noise, level: 0.5, cutoff: 1800, decay: 6)]
        case .pop:
            return [Tone(start: 0, length: 0.1, from: 680, to: 190, wave: .sine, level: 0.6, decay: 5)]
        case .chime:
            return [Tone(start: 0, length: 0.5, from: 1047, to: 1047, wave: .sine, level: 0.35, decay: 4),
                    Tone(start: 0.05, length: 0.5, from: 1568, to: 1568, wave: .sine, level: 0.22, decay: 4.5)]
        case .whoosh:
            return [Tone(start: 0, length: 0.32, from: 0, to: 0, wave: .noise, level: 0.45, cutoff: 2400, decay: 2.5)]
        case .creak:
            return [Tone(start: 0, length: 0.55, from: 90, to: 150, wave: .saw, level: 0.22, vibrato: 9, decay: 1.4)]
        case .sad:
            return [Tone(start: 0, length: 0.32, from: 440, to: 370, wave: .sine, level: 0.4, vibrato: 6, decay: 1.6),
                    Tone(start: 0.34, length: 0.5, from: 392, to: 294, wave: .sine, level: 0.4, vibrato: 6, decay: 2)]
        case .zap:
            return [Tone(start: 0, length: 0.18, from: 1500, to: 160, wave: .saw, level: 0.3, decay: 3)]
        case .munch:
            return [Tone(start: 0, length: 0.07, from: 0, to: 0, wave: .noise, level: 0.5, cutoff: 1400, decay: 5),
                    Tone(start: 0.1, length: 0.07, from: 0, to: 0, wave: .noise, level: 0.5, cutoff: 1400, decay: 5),
                    Tone(start: 0.2, length: 0.1, from: 520, to: 220, wave: .sine, level: 0.5, decay: 4)]
        case .fire:
            return [Tone(start: 0, length: 0.45, from: 0, to: 0, wave: .noise, level: 0.5, cutoff: 1100, decay: 2),
                    Tone(start: 0, length: 0.3, from: 120, to: 220, wave: .saw, level: 0.12, decay: 2)]
        }
    }

    private static func render(_ effect: NotchMascotSoundEffect, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let tones = recipe(effect)
        let total = tones.map { $0.start + $0.length }.max() ?? 0.1
        let count = max(1, Int(total * rate) + 1)
        var samples = [Float](repeating: 0, count: count)
        var noiseSeed: UInt32 = 0x1234_5678
        for tone in tones {
            let begin = Int(tone.start * rate), length = Int(tone.length * rate)
            var phase = 0.0, filtered = 0.0
            let alpha = tone.cutoff > 0 ? min(1, 2 * Double.pi * tone.cutoff / rate) : 1
            for i in 0..<length where begin + i < count {
                let t = Double(i) / Double(max(1, length - 1))
                let sweep = tone.from + (tone.to - tone.from) * t
                let wobble = tone.vibrato > 0 ? 1 + 0.04 * sin(2 * Double.pi * tone.vibrato * Double(i) / rate) : 1
                phase += 2 * Double.pi * sweep * wobble / rate
                var value: Double
                switch tone.wave {
                case .sine: value = sin(phase)
                case .square: value = sin(phase) >= 0 ? 1 : -1
                case .triangle: value = 2 / Double.pi * asin(sin(phase))
                case .saw: value = 2 * (phase / (2 * Double.pi) - floor(phase / (2 * Double.pi) + 0.5))
                case .noise:
                    noiseSeed = noiseSeed &* 1_664_525 &+ 1_013_904_223
                    value = Double(Int32(bitPattern: noiseSeed)) / Double(Int32.max)
                    filtered += alpha * (value - filtered)
                    value = tone.cutoff > 0 ? filtered * 2.2 : value
                }
                // A quick attack, then a fall: the shape of a struck or blown sound.
                let attack = min(1, Double(i) / (0.004 * rate))
                let envelope = attack * exp(-tone.decay * t)
                samples[begin + i] += Float(value * tone.level * envelope)
            }
        }
        // A gentle limiter, so stacked tones never clip.
        for i in 0..<count { samples[i] = Float(tanh(Double(samples[i]) * 1.4)) * 0.9 }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: count)
        }
        return buffer
    }
}
