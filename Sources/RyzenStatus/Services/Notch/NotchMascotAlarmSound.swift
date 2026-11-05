// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import AVFoundation

/// The tunes the app plays an alarm with, synthesised the way the
/// companions' own sounds are: a few notes, each a sine with its overtones
/// and a fall, rendered once into a short loop.
enum NotchMascotAlarmTone: String, CaseIterable {
    case sunrise, marimba, cuckoo, bell, chiptune, siren

    /// How long one pass of the tune is, its rest included: the loop.
    var period: Double {
        switch self {
        case .sunrise: return 1.9
        case .marimba: return 1.6
        case .cuckoo: return 2.2
        case .bell: return 1.8
        case .chiptune: return 1.3
        case .siren: return 2.4
        }
    }

    fileprivate enum Timbre { case bell, marimba, soft, square, metal }

    fileprivate struct Note {
        var start: Double
        var length: Double
        var frequency: Double
        /// Where the pitch has slid to by the note's end, as a siren wails.
        var slide: Double?
        var timbre: Timbre
        var level: Double = 0.5
    }

    fileprivate var notes: [Note] {
        switch self {
        case .sunrise:
            // A rising major arpeggio, bright as a morning, twice.
            let steps = [523.25, 659.25, 783.99, 1046.5]
            return steps.enumerated().map { Note(start: Double($0) * 0.17, length: 0.9, frequency: $1, timbre: .bell) }
                + steps.enumerated().map { Note(start: 0.85 + Double($0) * 0.17, length: 0.9, frequency: $1,
                                                timbre: .bell, level: 0.42) }
        case .marimba:
            let steps = [783.99, 659.25, 523.25, 659.25, 783.99, 1046.5, 987.77, 783.99]
            return steps.enumerated().map { Note(start: Double($0) * 0.15, length: 0.35, frequency: $1, timbre: .marimba) }
        case .cuckoo:
            return [Note(start: 0, length: 0.32, frequency: 659.25, timbre: .soft),
                    Note(start: 0.34, length: 0.5, frequency: 523.25, timbre: .soft),
                    Note(start: 1.0, length: 0.32, frequency: 659.25, timbre: .soft),
                    Note(start: 1.34, length: 0.5, frequency: 523.25, timbre: .soft)]
        case .bell:
            // The hammer of an old wind-up clock between two bells.
            return (0..<20).map { Note(start: Double($0) * 0.062, length: 0.12, frequency: $0.isMultiple(of: 2) ? 1860 : 2210,
                                       timbre: .metal, level: 0.38) }
        case .chiptune:
            let steps = [1046.5, 783.99, 659.25, 783.99, 1046.5, 1318.5, 1568, 1318.5]
            return steps.enumerated().map { Note(start: Double($0) * 0.1, length: 0.09, frequency: $1, timbre: .square,
                                                 level: 0.22) }
        case .siren:
            return [Note(start: 0, length: 1.2, frequency: 620, slide: 1240, timbre: .soft, level: 0.45),
                    Note(start: 1.2, length: 1.2, frequency: 1240, slide: 620, timbre: .soft, level: 0.45)]
        }
    }

    private static let rate = 44_100.0

    /// One pass of the tune as a WAV file in memory, 16-bit mono.
    func wave() -> Data {
        let count = Int(period * Self.rate)
        var samples = [Double](repeating: 0, count: count)
        for note in notes {
            let begin = Int(note.start * Self.rate)
            let length = Int(note.length * Self.rate)
            var phase = 0.0
            for i in 0..<length where begin + i < count {
                let t = Double(i) / Self.rate
                let share = Double(i) / Double(max(1, length - 1))
                let frequency = note.slide.map { note.frequency + ($0 - note.frequency) * share } ?? note.frequency
                phase += 2 * Double.pi * frequency / Self.rate
                let value: Double
                let envelope: Double
                switch note.timbre {
                case .bell:
                    value = sin(phase) + 0.35 * sin(2 * phase) + 0.18 * sin(3.01 * phase)
                    envelope = min(1, t / 0.004) * exp(-4.2 * t)
                case .marimba:
                    value = sin(phase) + 0.25 * sin(4 * phase)
                    envelope = min(1, t / 0.003) * exp(-11 * t)
                case .soft:
                    value = sin(phase) + 0.12 * sin(2 * phase)
                    envelope = min(1, t / 0.03) * min(1, (note.length - t) / 0.05)
                case .square:
                    value = sin(phase) >= 0 ? 0.8 : -0.8
                    envelope = min(1, t / 0.002) * min(1, (note.length - t) / 0.01)
                case .metal:
                    value = sin(phase) + 0.6 * sin(2.76 * phase) + 0.4 * sin(5.4 * phase)
                    envelope = min(1, t / 0.001) * exp(-26 * t)
                }
                samples[begin + i] += value * note.level * max(0, envelope)
            }
        }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(Self.rate)); append(UInt32(Self.rate) * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(bytes)
        // A gentle limiter, so stacked notes never clip.
        for sample in samples { append(Int16(max(-1, min(1, tanh(sample * 1.2) * 0.92)) * Double(Int16.max))) }
        return data
    }
}

/// The sounds an alarm can ring with: the app's own tunes, the Mac's
/// system sounds and the files added to the list, each by an identifier
/// that says which: "tone:sunrise", "system:Glass", "custom:Song.mp3".
enum NotchMascotAlarmSounds {
    static let defaultSound = "tone:" + NotchMascotAlarmTone.sunrise.rawValue
    static let allowedExtensions = ["aiff", "aif", "wav", "mp3", "m4a", "caf"]
    private static let systemFolder = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)

    struct Option: Identifiable, Equatable {
        enum Kind { case tone, system, custom }
        let id: String
        let name: String
        let kind: Kind
    }

    /// Every sound to pick from, the tunes first, named in `language`.
    static func options(_ language: AppLanguage) -> [Option] {
        let text = FeatureStrings.notchMascotAlarms(language)
        let tones = NotchMascotAlarmTone.allCases.map { Option(id: "tone:" + $0.rawValue, name: text.tone($0), kind: .tone) }
        let system = files(in: systemFolder).map { Option(id: "system:" + $0.lastPathComponent,
                                                          name: $0.deletingPathExtension().lastPathComponent, kind: .system) }
        let custom = customFolder.map(files(in:))?.map {
            Option(id: "custom:" + $0.lastPathComponent, name: $0.deletingPathExtension().lastPathComponent, kind: .custom)
        } ?? []
        return tones + system + custom
    }

    /// The name of the sound `id`, for the list; the default's when it is gone.
    static func name(of id: String, _ language: AppLanguage) -> String {
        let all = options(language)
        return (all.first { $0.id == id } ?? all.first { $0.id == defaultSound })?.name ?? id
    }

    private static func files(in folder: URL) -> [URL] {
        let found = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return found.filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Where the sounds added to the list are kept.
    static var customFolder: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("Alarm Sounds", isDirectory: true)
    }

    /// A copy of the audio file at `url` in the list, under a name of its
    /// own if one is taken; its identifier, or nil when it cannot be copied.
    static func add(_ url: URL) -> String? {
        guard allowedExtensions.contains(url.pathExtension.lowercased()), let folder = customFolder,
              PrivateFileStore.createDirectory(at: folder) else { return nil }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased()
        var target = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var number = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("\(base) \(number)").appendingPathExtension(ext)
            number += 1
        }
        guard (try? FileManager.default.copyItem(at: url, to: target)) != nil else { return nil }
        // The copy must play before it is offered.
        guard (try? AVAudioPlayer(contentsOf: target)) != nil else {
            try? FileManager.default.removeItem(at: target)
            return nil
        }
        return "custom:" + target.lastPathComponent
    }

    /// Takes an added sound off the list.
    static func remove(_ id: String) {
        guard id.hasPrefix("custom:"), let url = url(of: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// The file of a system or added sound.
    static func url(of id: String) -> URL? {
        if id.hasPrefix("system:") {
            let name = String(id.dropFirst("system:".count))
            guard !name.contains("/") else { return nil }
            return systemFolder.appendingPathComponent(name)
        }
        if id.hasPrefix("custom:") {
            let name = String(id.dropFirst("custom:".count))
            guard !name.contains("/"), !name.hasPrefix(".") else { return nil }
            return customFolder?.appendingPathComponent(name)
        }
        return nil
    }

    static func tone(of id: String) -> NotchMascotAlarmTone? {
        guard id.hasPrefix("tone:") else { return nil }
        return NotchMascotAlarmTone(rawValue: String(id.dropFirst("tone:".count)))
    }

    private static var rendered: [NotchMascotAlarmTone: Data] = [:]

    /// A player for the sound `id`, or for the default when it cannot play.
    static func player(for id: String) -> AVAudioPlayer? {
        if let tone = tone(of: id) {
            let data = rendered[tone] ?? tone.wave()
            rendered[tone] = data
            return try? AVAudioPlayer(data: data)
        }
        if let url = url(of: id), let player = try? AVAudioPlayer(contentsOf: url) { return player }
        return id == defaultSound ? nil : player(for: defaultSound)
    }
}

/// Plays an alarm: the sound over and over, from soft to full over its
/// first half minute, until stopped, put off or rung for too long; or a
/// sample of one, once, as it is picked.
final class NotchMascotAlarmPlayer {
    static let shared = NotchMascotAlarmPlayer()
    /// The longest an alarm rings, as the island's timer does.
    static let maximumRing: TimeInterval = {
        let parts = NotchTimerAlert.maximumDuration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }()
    private static let ramp: TimeInterval = 30

    private var ringing: AVAudioPlayer?
    private var sample: AVAudioPlayer?
    private var limit: DispatchWorkItem?
    /// Runs when the alarm stops by itself, having rung as long as it may.
    var rangOut: (() -> Void)?

    private init() {}

    var isRinging: Bool { ringing != nil }

    func ring(_ id: String) {
        stop()
        sample?.stop(); sample = nil
        guard let player = NotchMascotAlarmSounds.player(for: id) else { NSSound.beep(); return }
        player.numberOfLoops = -1
        player.volume = 0.18
        player.prepareToPlay()
        player.play()
        player.setVolume(1, fadeDuration: Self.ramp)
        ringing = player
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.ringing != nil else { return }
            self.stop()
            self.rangOut?()
        }
        limit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maximumRing, execute: work)
    }

    func stop() {
        limit?.cancel(); limit = nil
        ringing?.stop(); ringing = nil
    }

    /// One pass of the sound `id`, at a comfortable level, over any sample before.
    func preview(_ id: String) {
        sample?.stop()
        guard let player = NotchMascotAlarmSounds.player(for: id) else { return }
        player.volume = 0.6
        player.play()
        sample = player
        // A long song is a sample for a few seconds only.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self, weak player] in
            guard let self, let player, self.sample === player else { return }
            player.setVolume(0, fadeDuration: 0.6)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { if self.sample === player { player.stop(); self.sample = nil } }
        }
    }

    func stopPreview() { sample?.stop(); sample = nil }

    /// The siren the companion sounds to send the guests home: a few wails,
    /// at the companions' own volume, and only with their sounds on.
    func siren() {
        let defaults = UserDefaults.standard
        let enabled = (defaults.object(forKey: DefaultsKey.notchMascotSound) as? Bool) ?? true
        let volume = min(1, max(0, (defaults.object(forKey: DefaultsKey.notchMascotSoundVolume) as? Double)
                                    ?? 0.35))
        guard enabled, volume > 0,
              let player = NotchMascotAlarmSounds.player(for: "tone:" + NotchMascotAlarmTone.siren.rawValue) else { return }
        player.numberOfLoops = 1
        player.volume = Float(min(1, volume * 1.6))
        player.play()
        sample?.stop()
        sample = player
    }
}
