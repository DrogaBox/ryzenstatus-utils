// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// Acts out a play of the whole gang, step by step, on a clear layer over
/// the screen they share: the props come and go there, as the two's own
/// plays draw theirs. Each of them walks, hops, pulls faces and floats
/// what it says. A press on any of them, or one going home, ends it at once.
final class NotchMascotGroupDirector {
    typealias Kind = NotchMascotGroupPlay.Kind

    private let stage = NotchMascotPlayStage()
    private var steps: [DispatchWorkItem] = []
    private(set) var playing: Kind?
    /// Who is in it, left to right as they stood when it began.
    private(set) var cast: [NotchMascotDesktop] = []

    /// Who a guest is; nil for the island's own two.
    var personality: (NotchMascotDesktop) -> NotchMascotPersonality? = { _ in nil }
    /// Something went wrong for `one`, for the others to laugh at.
    var mishap: ((NotchMascotDesktop) -> Void)?
    /// It came to its end, or was cut short.
    var ended: ((Kind, [NotchMascotDesktop]) -> Void)?

    func involves(_ one: NotchMascotDesktop) -> Bool { cast.contains { $0 === one } }

    /// Starts `kind` with `members`, all of them free on the same screen.
    // swiftlint:disable:next cyclomatic_complexity
    func start(_ kind: Kind, with members: [NotchMascotDesktop]) {
        guard playing == nil, members.count >= 2 else { return }
        playing = kind
        cast = members.sorted { x($0) < x($1) }
        cast.forEach { $0.beginPlay() }
        switch kind {
        case .conga: conga(leader: nil)
        case .megaphoneConga: conga(leader: wearer(.megaphone))
        case .pyramid: pyramid()
        case .band: band()
        case .soccer: soccer()
        case .campfire: campfire()
        case .choir: choir()
        case .photo: photo()
        case .stadiumWave: stadiumWave()
        case .danceCircle: danceCircle()
        case .napPile: napPile()
        case .hideAndSeek: hideAndSeek()
        case .parade: parade()
        case .pillowFight: pillowFight()
        case .telephone: telephone()
        case .snowballFight: snowballFight()
        case .surpriseParty: surpriseParty()
        case .picnic: picnic()
        case .kiteStorm: kiteStorm()
        case .waterFight: waterFight()
        case .walkieTalkies: walkieTalkies()
        case .juggling: juggling()
        case .karaoke: karaoke()
        }
    }

    /// Stops the play under way, if any, at once.
    func cancel() {
        guard playing != nil else { return }
        steps.forEach { $0.cancel() }
        end()
    }

    private func end() {
        steps.removeAll()
        guard let kind = playing else { return }
        playing = nil
        stage.close()
        let everyone = cast
        cast = []
        for (index, one) in everyone.enumerated() { one.endPlay(after: 2 + Double(index) * 0.6) }
        ended?(kind, everyone)
    }

    // MARK: Helpers

    /// Runs `block` `delay` seconds from now, unless the play ends first.
    private func at(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem { [weak self] in
            guard self?.playing != nil else { return }
            block()
        }
        steps.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }

    private func finish(after delay: TimeInterval) {
        at(delay) { [weak self] in self?.end() }
    }

    private func x(_ one: NotchMascotDesktop) -> CGFloat { one.feet?.x ?? one.screenCenter.x }
    private var figure: CGFloat { cast.map(\.figureSize).max() ?? NotchMascotRoam.drawnSize }
    /// The floor they stand on, and how far along it they may go.
    private var floorY: CGFloat { cast.compactMap { $0.feet?.y }.min() ?? (cast.first?.screenCenter.y ?? 0) }
    private var floor: ClosedRange<CGFloat> {
        let low = cast.map(\.floor.lowerBound).max() ?? 0
        let high = cast.map(\.floor.upperBound).min() ?? low
        return low...max(low, high)
    }
    private var middleX: CGFloat { cast.isEmpty ? 0 : cast.map(x).reduce(0, +) / CGFloat(cast.count) }

    private func canvas() -> CALayer? { cast.first?.playScreen.flatMap { stage.layer(over: $0) } }
    private func onCanvas(_ point: CGPoint) -> CGPoint { stage.point(point) }
    private var screenArea: CGRect { CGRect(origin: .zero, size: cast.first?.playScreen?.frame.size ?? .zero) }

    private func wearer(_ item: NotchMascotAccessory) -> NotchMascotDesktop? {
        cast.first { $0.playLook.style.takesAccessory && $0.playLook.accessory == item }
    }

    private func wears(_ one: NotchMascotDesktop, _ items: Set<NotchMascotAccessory>) -> Bool {
        one.playLook.style.takesAccessory && items.contains(one.playLook.accessory)
    }

    private func direction(from one: NotchMascotDesktop, to other: NotchMascotDesktop) -> CGFloat {
        x(other) >= x(one) ? 1 : -1
    }

    private func float(_ symbol: String, over one: NotchMascotDesktop, color: CGColor = NotchMascotGroupDirector.mark,
                       count: Int = 1) {
        // A lone mark of surprise or doubt is said in a comic balloon.
        if count == 1, let balloon = NotchMascotEmote.balloon(for: symbol) { one.emote(balloon); return }
        guard let canvas = canvas() else { return }
        NotchMascotPlayEffects.float(symbol, in: canvas, at: onCanvas(one.head), size: max(10, one.figureSize * 0.24),
                                     color: color, count: count)
    }

    private func notes(over one: NotchMascotDesktop, count: Int = 1) {
        float(Bool.random() ? "♪" : "♫", over: one, color: Self.noteColors.randomElement() ?? Self.mark, count: count)
    }

    private func marker(_ text: String, over one: NotchMascotDesktop) {
        guard let canvas = canvas() else { return }
        let head = one.head
        NotchMascotPlayEffects.arcadeMarker(text, in: canvas, at: onCanvas(CGPoint(x: head.x, y: head.y + figure * 0.35)),
                                            cell: max(1.6, figure * 0.05))
    }

    private func marker(_ text: String, at point: CGPoint) {
        guard let canvas = canvas() else { return }
        NotchMascotPlayEffects.arcadeMarker(text, in: canvas, at: onCanvas(point), cell: max(1.8, figure * 0.06))
    }

    private func burst(_ burst: NotchMascotIslandPlay.Burst, over one: NotchMascotDesktop) {
        guard let canvas = canvas() else { return }
        NotchMascotPlayEffects.burst(burst, in: canvas, at: onCanvas(one.head), size: one.figureSize * 0.9,
                                     energy: NotchMascotPlay.energy(for: one.playLook))
    }

    private func sound(_ effect: NotchMascotSoundEffect, at x: CGFloat) {
        NotchMascotSound.play(effect, pan: NotchMascotSoundMap.pan(screenX: x, across: NSScreen.screens.map(\.frame)))
    }

    /// Everyone walks to stand in a row `spacing` apart about `center`, in
    /// the order they stand, and how long until all are there.
    @discardableResult
    private func line(spacing: CGFloat, center: CGFloat? = nil, members: [NotchMascotDesktop]? = nil,
                      gap: CGFloat = 0, pace: CGFloat = 1.6) -> TimeInterval {
        let members = members ?? cast
        guard !members.isEmpty else { return 0 }
        let floor = self.floor
        let width = spacing * CGFloat(members.count - 1) + gap
        let wanted = center ?? members.map(x).reduce(0, +) / CGFloat(members.count)
        let middle = min(floor.upperBound - width / 2, max(floor.lowerBound + width / 2, wanted))
        var longest: TimeInterval = 0
        for (index, one) in members.enumerated() {
            var spot = middle - width / 2 + spacing * CGFloat(index)
            if gap > 0, CGFloat(index) >= CGFloat(members.count) / 2 { spot += gap }
            longest = max(longest, one.stroll(to: spot, pace: pace))
        }
        return longest + 0.35
    }

    /// Where the row's middle ends up for `line`, for props placed there.
    private func lineMiddle(spacing: CGFloat, count: Int, center: CGFloat? = nil, gap: CGFloat = 0) -> CGFloat {
        let floor = self.floor
        let width = spacing * CGFloat(max(0, count - 1)) + gap
        let wanted = center ?? middleX
        return min(floor.upperBound - width / 2, max(floor.lowerBound + width / 2, wanted))
    }

    private func faceEachOther() {
        let middle = middleX
        for one in cast { one.face(toward: middle) }
    }

    /// The faces a guest of a temper pulls more often.
    private func face(for one: NotchMascotDesktop, fallback: NotchMascotMood) -> NotchMascotMood {
        switch personality(one) {
        case .grumpy?: return Bool.random() ? .angry : .bored
        case .shy?: return .embarrassed
        case .showOff?: return .smug
        case .prankster?: return .mischievous
        case .glutton?: return .greedy
        case .sleepy?, nil: return fallback
        }
    }

    static let mark = CGColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: 1)
    private static let heart = CGColor(srgbRed: 1, green: 0.38, blue: 0.55, alpha: 1)
    private static let snore = CGColor(srgbRed: 0.85, green: 0.9, blue: 1, alpha: 1)
    private static let noteColors: [CGColor] = [
        CGColor(srgbRed: 1, green: 0.85, blue: 0.35, alpha: 1), CGColor(srgbRed: 0.55, green: 0.9, blue: 1, alpha: 1),
        CGColor(srgbRed: 1, green: 0.55, blue: 0.75, alpha: 1), CGColor(srgbRed: 0.6, green: 1, blue: 0.6, alpha: 1),
    ]

    // MARK: Lines and marches

    /// Hip to hip behind the one in front, they dance along the floor one
    /// way and back with a kick on every fourth beat, and cheer at the end.
    /// Called through a megaphone, the one holding it shouts first and the
    /// others rush to fall in behind it.
    private func conga(leader called: NotchMascotDesktop?) {
        var heading: CGFloat = Bool.random() ? 1 : -1
        var start: TimeInterval = 0
        if let called {
            heading = x(called) <= middleX ? -1 : 1
            at(0) { [weak self] in
                guard let self else { return }
                self.marker("CONGA!", over: called)
                self.sound(.honk, at: self.x(called))
                called.react(.perk)
                for one in self.cast where one !== called { one.pullFace(.starstruck, for: 1.6) }
            }
            start = 1.4
        }
        // The one at the head of the line is the one furthest along its way.
        var members = heading > 0 ? cast : Array(cast.reversed())
        if let called, let index = members.firstIndex(where: { $0 === called }) {
            members.remove(at: index)
            members.append(called)
        }
        let spacing = figure * 0.8
        at(start) { [weak self] in
            guard let self else { return }
            let row = heading > 0 ? members : Array(members.reversed())
            let ready = self.line(spacing: spacing, members: row, pace: called == nil ? 1.6 : 2.6)
            self.at(ready) { [weak self] in self?.dance(members: members, heading: heading) }
        }
    }

    private func dance(members: [NotchMascotDesktop], heading start: CGFloat) {
        var heading = start
        var time: TimeInterval = 0
        let leg: CGFloat = min(170, (floor.upperBound - floor.lowerBound) * 0.25)
        let legTime = TimeInterval(leg / (NotchMascotRoam.walkSpeed * 1.1))
        for round in 0..<3 {
            let way = heading
            at(time) { [weak self] in
                guard let self else { return }
                for one in members { one.stroll(to: self.x(one) + way * leg, pace: 1.1) }
                if let front = members.last { self.notes(over: front, count: 2) }
            }
            var beat = 0.55
            while beat < legTime {
                let kick = Int(beat / 0.55) % 4 == 3
                for (index, one) in members.enumerated() {
                    at(time + beat + Double(index) * 0.09) {
                        if kick { one.hop(dx: way * 40, dy: 300) }
                    }
                }
                beat += 0.55
            }
            time += legTime + 0.4
            heading = -heading
            if round == 1, let back = members.first { at(time - 0.2) { [weak self] in self?.float("♪", over: back) } }
        }
        at(time) { [weak self] in
            guard let self else { return }
            for one in members { one.react(.celebrate) }
            if let front = members.last { self.burst(.confetti, over: front) }
        }
        finish(after: time + 2.6)
    }

    /// Behind one in front, a march across the screen to a beat, and a
    /// shower of confetti at the end.
    private func parade() {
        let leader = wearer(.drum) ?? wearer(.megaphone) ?? wearer(.whistle) ?? cast.randomElement() ?? cast[0]
        let heading: CGFloat = x(leader) <= middleX ? 1 : -1
        var members = cast.filter { $0 !== leader }
        members.sort { heading > 0 ? x($0) < x($1) : x($0) > x($1) }
        members.append(leader)
        let spacing = figure * 0.95
        let ready = line(spacing: spacing, members: heading > 0 ? members : Array(members.reversed()))
        let floor = self.floor
        let distance = (floor.upperBound - floor.lowerBound) * 0.45
        let march = TimeInterval(distance / (NotchMascotRoam.walkSpeed * 1.2))
        at(ready) { [weak self] in
            guard let self else { return }
            self.marker("PARADE", over: leader)
            for one in members { one.stroll(to: self.x(one) + heading * distance, pace: 1.2) }
        }
        var beat = 0.0
        while beat < march {
            let index = Int(beat / 0.6)
            at(ready + beat) { [weak self] in
                guard let self else { return }
                if index.isMultiple(of: 2) {
                    self.notes(over: leader)
                    if self.wears(leader, [.drum]) { self.sound(.thud, at: self.x(leader)) }
                } else if let one = members.randomElement() {
                    one.hop(dx: heading * 30, dy: 260)
                }
            }
            beat += 0.6
        }
        at(ready + march + 0.3) { [weak self] in
            guard let self else { return }
            for one in members {
                one.face(toward: self.x(one) - heading * 200)
                one.react(.wave)
            }
            self.burst(.confetti, over: leader)
        }
        finish(after: ready + march + 2.8)
    }

    /// One after another they jump with their arms up, there and back.
    private func stadiumWave() {
        let ready = line(spacing: figure * 1.05)
        for pass in 0..<2 {
            let order = pass == 0 ? cast : cast.reversed()
            let begin = ready + Double(pass) * (Double(cast.count) * 0.18 + 1.2)
            for (index, one) in order.enumerated() {
                at(begin + Double(index) * 0.18) { [weak self] in
                    one.hop(dx: 0, dy: 560)
                    if pass == 1 { self?.float("!", over: one) }
                }
            }
        }
        let close = ready + 2 * (Double(cast.count) * 0.18 + 1.2)
        at(close) { [weak self] in
            guard let self else { return }
            self.cast.forEach { $0.react(.celebrate) }
            self.marker("WOW", over: self.cast[self.cast.count / 2])
        }
        finish(after: close + 2.2)
    }

    // MARK: Stunts

    /// The heaviest at the bottom, the rest standing on their heads, rows
    /// narrowing to one at the top, who wobbles until the whole thing comes
    /// down, and everyone ends up laughing on the floor.
    private func pyramid() {
        let rows = NotchMascotGroupPlay.pyramidRows(cast.count)
        let ordered = cast.sorted { $0.figureSize > $1.figureSize }
        let spacing = figure * 0.92
        let middle = lineMiddle(spacing: spacing, count: rows[0])
        let base = Array(ordered.prefix(rows[0]))
        let ready = line(spacing: spacing, center: middle, members: base.sorted { x($0) < x($1) })
        // The others wait to one side for their turn to climb.
        let climbers = Array(ordered.dropFirst(rows[0]))
        for (index, one) in climbers.enumerated() {
            let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            one.stroll(to: middle + side * (spacing * CGFloat(rows[0]) / 2 + figure * (1 + CGFloat(index / 2))), pace: 1.8)
        }
        let floorY = self.floorY
        var time = ready + 0.6
        var next = 0
        let hold: TimeInterval = 4.2 + Double(climbers.count) * 0.7
        for (level, count) in rows.enumerated().dropFirst() {
            for slot in 0..<count where next < climbers.count {
                let one = climbers[next]
                next += 1
                let width = spacing * CGFloat(count - 1)
                let spot = CGPoint(x: middle - width / 2 + spacing * CGFloat(slot),
                                   y: floorY + figure * 0.84 * CGFloat(level))
                let climb = time
                at(climb) { one.hop(dx: 0, dy: 380) }
                at(climb + 0.25) { one.glide(to: spot, over: 0.45) }
                at(climb + 0.72) { one.glide(to: spot, over: hold + time - climb + 1) }
                time += 0.75
            }
        }
        let top = climbers.last ?? base[0]
        at(time + 0.2) { [weak self] in
            guard let self else { return }
            top.react(.celebrate)
            self.marker("TA DA", over: top)
            base.forEach { $0.pullFace(.determined, for: 2.5) }
        }
        at(time + 1.6) { top.sway(amplitude: 0.22, speed: 18, duration: 1.8) }
        at(time + 2.0) { top.pullFace(.terrified, for: 1.6) }
        let fall = time + 3.4
        at(fall) { [weak self] in
            guard let self else { return }
            for (index, one) in base.enumerated() { one.hop(dx: (index.isMultiple(of: 2) ? -1 : 1) * 200, dy: 260) }
            for one in climbers { one.hop(dx: CGFloat.random(in: -260...260), dy: 200) }
            self.cast.forEach { $0.pullFace(.dizzy, for: 2.4) }
            self.sound(.thud, at: middle)
        }
        at(fall + 2.6) { [weak self] in
            guard let self else { return }
            self.mishap?(top)
        }
        finish(after: fall + 4)
    }

    /// Balls passed round the line in arcs, faster and faster, until one
    /// lands on the floor and the one who dropped it goes red.
    private func juggling() {
        let starter = wearer(.jugglingBalls) ?? cast[0]
        var members = cast
        if let index = members.firstIndex(where: { $0 === starter }) { members.rotate(to: index) }
        let ready = line(spacing: figure * 1.3)
        var time = ready + 0.3
        let passes = 8 + Int.random(in: 0...4)
        let drop = Int.random(in: passes - 3..<passes)
        for pass in 0..<passes {
            let from = members[pass % members.count], to = members[(pass + 1) % members.count]
            let length = max(0.42, 0.85 - Double(pass) * 0.05)
            let falls = pass == drop
            at(time) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                let side = self.direction(from: from, to: to)
                NotchMascotPlayEffects.fly(.ball, in: canvas, from: self.onCanvas(from.hand(toward: side)),
                                           to: self.onCanvas(to.hand(toward: -side)), duration: length,
                                           side: max(12, self.figure * 0.26), falls: falls,
                                           while: { [weak self] in self?.playing != nil })
                from.hop(dx: 0, dy: 140)
            }
            time += length * 0.8
            if falls {
                at(time + 0.3) { [weak self] in
                    to.pullFace(.embarrassed, for: 2.4)
                    self?.float("!", over: to)
                }
                at(time + 1.4) { [weak self] in self?.mishap?(to) }
                break
            }
        }
        finish(after: time + 3.2)
    }

    // MARK: Music

    /// Each plays what it holds, the rest clap along, and they bow together.
    private func band() {
        let ready = line(spacing: figure * 1.15)
        let instruments: Set<NotchMascotAccessory> = [.bardLute, .drum, .microphone, .maracas, .headphones, .discoBall]
        at(ready) { [weak self] in self?.faceEachOther() }
        for beat in 0..<14 {
            for (index, one) in cast.enumerated() where (beat + index).isMultiple(of: 2) {
                at(ready + 0.3 + Double(beat) * 0.55) { [weak self] in
                    guard let self else { return }
                    guard self.wears(one, instruments) else {
                        one.react(.bounce)
                        if beat.isMultiple(of: 4) { self.float("✦", over: one) }
                        return
                    }
                    switch one.playLook.accessory {
                    case .drum:
                        self.float("♩", over: one)
                        if beat.isMultiple(of: 4) { self.sound(.thud, at: self.x(one)) }
                    case .maracas:
                        self.float("♬", over: one)
                        one.sway(amplitude: 0.12, speed: 40, duration: 0.4)
                    case .microphone:
                        self.notes(over: one, count: 2)
                        if beat.isMultiple(of: 6) { self.sound(.toot, at: self.x(one)) }
                    case .discoBall:
                        self.burst(.sparkles, over: one)
                    default:
                        self.notes(over: one)
                        if beat.isMultiple(of: 5) { self.sound(.chime, at: self.x(one)) }
                    }
                    one.react(.groove)
                }
            }
        }
        let close = ready + 0.3 + 14 * 0.55
        at(close) { [weak self] in
            guard let self else { return }
            for (index, one) in self.cast.enumerated() { one.tilt((index.isMultiple(of: 2) ? -1 : 1) * 0.3, for: 1) }
            self.burst(.confetti, over: self.cast[self.cast.count / 2])
            self.sound(.chime, at: self.middleX)
        }
        at(close + 1.3) { [weak self] in self?.cast.forEach { $0.react(.celebrate) } }
        finish(after: close + 3)
    }

    /// A song in turns, from the lowest voice to the highest, under one
    /// conducting; one sings off key and goes pink, then all together.
    private func choir() {
        let conductor = wearer(.megaphone) ?? wearer(.microphone) ?? cast.randomElement() ?? cast[0]
        let singers = cast.filter { $0 !== conductor }
        let spacing = figure * 1.05
        let middle = lineMiddle(spacing: spacing, count: singers.count)
        let ready = line(spacing: spacing, center: middle, members: singers)
        let floor = self.floor
        let away: CGFloat = middle > (floor.lowerBound + floor.upperBound) / 2 ? -1 : 1
        let reach = spacing * CGFloat(singers.count) / 2 + figure
        let stand = min(floor.upperBound, max(floor.lowerBound, middle + away * reach))
        let walk = conductor.stroll(to: stand, pace: 1.8)
        let begin = max(ready, walk + 0.3)
        let offKey = singers.randomElement()
        at(begin) { [weak self] in
            guard let self else { return }
            conductor.face(toward: middle)
            singers.forEach { $0.face(toward: stand) }
            self.float("♪", over: conductor)
        }
        for (index, one) in singers.enumerated() {
            at(begin + 0.6 + Double(index) * 0.9) { [weak self] in
                guard let self else { return }
                conductor.sway(amplitude: 0.18, speed: 14, duration: 0.8)
                one.hop(dx: 0, dy: 160 + CGFloat(index) * 70)
                if one === offKey {
                    self.float("♭", over: one, color: CGColor(srgbRed: 0.7, green: 0.7, blue: 0.75, alpha: 1))
                    one.pullFace(.embarrassed, for: 2)
                    conductor.pullFace(.angry, for: 1.4)
                    self.sound(.squeak, at: self.x(one))
                } else {
                    self.notes(over: one)
                }
            }
        }
        let together = begin + 0.8 + Double(singers.count) * 0.9
        for repeatIndex in 0..<3 {
            at(together + Double(repeatIndex) * 0.7) { [weak self] in
                guard let self else { return }
                singers.forEach { self.notes(over: $0) }
                if repeatIndex == 2 { self.sound(.chime, at: middle) }
            }
        }
        at(together + 2.3) { [weak self] in
            self?.cast.forEach { $0.react(.celebrate) }
            conductor.tilt(-0.35, for: 1)
        }
        finish(after: together + 4)
    }

    /// One sings into the microphone in front, the rest sway behind; one is
    /// moved to tears, one is starstruck, and all clap at the end.
    private func karaoke() {
        let singer = wearer(.microphone) ?? cast[0]
        let crowd = cast.filter { $0 !== singer }
        let spacing = figure * 1.1
        let ready = line(spacing: spacing, members: crowd)
        let middle = lineMiddle(spacing: spacing, count: crowd.count)
        let floor = self.floor
        let stage = min(floor.upperBound, max(floor.lowerBound, middle + figure * 1.6))
        let walk = singer.stroll(to: stage, pace: 1.6)
        let begin = max(ready, walk) + 0.3
        at(begin) { [weak self] in
            guard let self else { return }
            singer.face(toward: middle)
            crowd.forEach { $0.face(toward: stage) }
            self.marker("KARAOKE", over: singer)
            self.sound(.toot, at: stage)
        }
        for beat in 0..<10 {
            at(begin + 0.8 + Double(beat) * 0.6) { [weak self] in
                guard let self else { return }
                self.notes(over: singer, count: beat.isMultiple(of: 3) ? 2 : 1)
                if beat.isMultiple(of: 2) { singer.react(.groove) }
                for (index, one) in crowd.enumerated() where (beat + index).isMultiple(of: 3) {
                    one.sway(amplitude: 0.14, speed: 9, duration: 0.6)
                }
                if beat == 3, let moved = crowd.first { moved.pullFace(.crying, for: 3) }
                if beat == 5, let fan = crowd.last { fan.pullFace(.starstruck, for: 3) }
            }
        }
        let close = begin + 0.8 + 10 * 0.6
        at(close) { [weak self] in
            guard let self else { return }
            crowd.forEach { $0.react(.celebrate) }
            singer.tilt(0.35, for: 1)
            singer.pullFace(self.face(for: singer, fallback: .starstruck), for: 2)
            self.burst(.hearts, over: singer)
        }
        finish(after: close + 2.6)
    }

    /// A ring of clappers with a gap in the middle where each takes a turn
    /// at dancing, then all dance together.
    private func danceCircle() {
        let spacing = figure * 1.05
        let gap = figure * 1.6
        let middle = lineMiddle(spacing: spacing, count: cast.count, gap: gap)
        let ready = line(spacing: spacing, center: middle, gap: gap)
        var spots = [CGFloat](repeating: middle, count: cast.count)
        let width = spacing * CGFloat(cast.count - 1) + gap
        for index in cast.indices {
            var spot = middle - width / 2 + spacing * CGFloat(index)
            if CGFloat(index) >= CGFloat(cast.count) / 2 { spot += gap }
            spots[index] = spot
        }
        let dancers = Array(cast.shuffled().prefix(min(3, cast.count)))
        var time = ready + 0.3
        for dancer in dancers {
            let home = cast.firstIndex { $0 === dancer }.map { spots[$0] } ?? middle
            at(time) { [weak self] in
                guard let self else { return }
                let walk = dancer.stroll(to: middle, pace: 2.2)
                self.at(walk + 0.1) { [weak self] in
                    guard let self else { return }
                    dancer.sway(amplitude: 0.5, speed: 24, duration: 0.8)
                    self.notes(over: dancer, count: 2)
                    dancer.pullFace(self.face(for: dancer, fallback: .starstruck), for: 2.6)
                }
                self.at(walk + 0.95) { dancer.hop(dx: 0, dy: 560) }
                self.at(walk + 1.7) { dancer.react(.groove) }
                self.at(walk + 2.6) { dancer.stroll(to: home, pace: 2.2) }
            }
            for clap in 0..<6 {
                at(time + 0.4 + Double(clap) * 0.5) { [weak self] in
                    guard let self else { return }
                    for (index, one) in self.cast.enumerated() where one !== dancer && (clap + index).isMultiple(of: 2) {
                        one.react(.bounce)
                    }
                }
            }
            time += 3.9
        }
        at(time) { [weak self] in
            guard let self else { return }
            self.cast.forEach { $0.react(.groove) }
            self.burst(.confetti, over: self.cast[self.cast.count / 2])
        }
        at(time + 0.6) { [weak self] in self?.cast.forEach { $0.hop(dx: 0, dy: 300) } }
        finish(after: time + 2.8)
    }

    // MARK: Games

    /// Two sides and a referee: kick-off on the whistle, a few passes, a
    /// shot, a goal for one side and tears on the other, and a yellow card.
    private func soccer() {
        let referee = wearer(.whistle) ?? cast[cast.count - 1]
        let players = cast.filter { $0 !== referee }
        let floor = self.floor
        let half = max(figure * 2, min(260, (floor.upperBound - floor.lowerBound) / 2 - figure))
        let middle = min(floor.upperBound - half, max(floor.lowerBound + half, middleX))
        let floorY = self.floorY
        // Even places to the left side, odd to the right; each team shoots at the other's goal.
        var walk: TimeInterval = 0
        for (index, one) in players.enumerated() {
            let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            let depth = CGFloat(index / 2 + 1) * half / CGFloat(players.count / 2 + 1)
            walk = max(walk, one.stroll(to: middle + side * depth, pace: 1.8))
        }
        walk = max(walk, referee.stroll(to: middle + figure * 0.4, pace: 1.6))
        let length = walk + 13
        at(0.2) { [weak self] in
            guard let self, let canvas = self.canvas() else { return }
            for side in [-1, 1] as [CGFloat] {
                NotchMascotGangArt.goal(in: canvas, at: self.onCanvas(CGPoint(x: middle + side * (half + self.figure * 0.4),
                                                                              y: floorY)),
                                        height: self.figure * 1.1, facing: -side, duration: length)
            }
        }
        let kickoff = walk + 0.4
        at(kickoff) { [weak self] in
            guard let self else { return }
            self.float("♪", over: referee)
            self.sound(.toot, at: self.x(referee))
            referee.react(.perk)
            players.forEach { $0.pullFace(.determined, for: 1.5) }
        }
        var holder = players.randomElement() ?? referee
        var time = kickoff + 0.8
        for _ in 0..<4 {
            guard let to = players.filter({ $0 !== holder }).randomElement() else { break }
            let from = holder
            at(time) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                let side = self.direction(from: from, to: to)
                from.hop(dx: side * 60, dy: 160)
                NotchMascotPlayEffects.fly(.ball, in: canvas, from: self.onCanvas(CGPoint(x: self.x(from), y: floorY + 6)),
                                           to: self.onCanvas(CGPoint(x: self.x(to), y: floorY + 6)), duration: 0.75,
                                           side: max(12, self.figure * 0.28),
                                           while: { [weak self] in self?.playing != nil })
                self.at(0.4) { to.stroll(to: self.x(to) - side * 30, pace: 2) }
            }
            holder = to
            time += 1.35
        }
        // The last one with the ball shoots for the other side's goal.
        let scorer = holder
        let scorerIndex = players.firstIndex { $0 === scorer } ?? 0
        let attacks: CGFloat = scorerIndex.isMultiple(of: 2) ? 1 : -1
        let goalPoint = CGPoint(x: middle + attacks * (half + figure * 0.1), y: floorY + figure * 0.4)
        at(time) { [weak self] in
            guard let self, let canvas = self.canvas() else { return }
            scorer.hop(dx: attacks * 80, dy: 240)
            NotchMascotPlayEffects.fly(.ball, in: canvas, from: self.onCanvas(CGPoint(x: self.x(scorer), y: floorY + 6)),
                                       to: self.onCanvas(goalPoint), duration: 0.9, side: max(12, self.figure * 0.28),
                                       while: { [weak self] in self?.playing != nil })
        }
        at(time + 1.0) { [weak self] in
            guard let self else { return }
            self.marker("GOAL!", at: CGPoint(x: goalPoint.x - attacks * self.figure, y: goalPoint.y + self.figure))
            for (index, one) in players.enumerated() {
                let sameSide = index.isMultiple(of: 2) == scorerIndex.isMultiple(of: 2)
                if sameSide {
                    one.react(.celebrate)
                    one.pullFace(.starstruck, for: 2.5)
                } else {
                    one.pullFace(Bool.random() ? .crying : .angry, for: 2.8)
                }
            }
        }
        let booked = players.enumerated().first { $0.offset.isMultiple(of: 2) != scorerIndex.isMultiple(of: 2) }?.element
        at(time + 2.6) { [weak self] in
            guard let self, let booked, let canvas = self.canvas() else { return }
            self.float("♪", over: referee)
            self.sound(.toot, at: self.x(referee))
            referee.face(toward: self.x(booked))
            NotchMascotGangArt.card(in: canvas, at: self.onCanvas(referee.hand(toward: self.direction(from: referee, to: booked))),
                                    size: self.figure * 0.5)
            booked.pullFace(.disgusted, for: 2)
        }
        finish(after: time + 5)
    }

    /// One counts with its eyes shut while the rest run off and crouch,
    /// then it finds them one by one, the last with a cheer.
    private func hideAndSeek() {
        let seeker = cast.randomElement() ?? cast[0]
        let hiders = cast.filter { $0 !== seeker }
        let floor = self.floor
        var hideTime: TimeInterval = 0
        for (index, one) in hiders.enumerated() {
            let share = (CGFloat(index) + 0.5) / CGFloat(hiders.count)
            let spot = floor.lowerBound + (floor.upperBound - floor.lowerBound) * share
            hideTime = max(hideTime, one.stroll(to: spot, pace: 2.4))
        }
        at(0) { [weak self] in
            seeker.pullFace(.sleepy, for: 5)
            self?.marker("HIDE", over: seeker)
        }
        for count in 1...5 {
            at(Double(count) * 0.9) { [weak self] in self?.marker("\(count)", over: seeker) }
        }
        let crouch = min(4.4, hideTime + 0.2)
        at(crouch) {
            for one in hiders {
                one.react(.hush)
                one.tilt(0.25, for: 2.5)
            }
        }
        var time = 5.4
        at(time) { [weak self] in
            seeker.react(.lookAround)
            self?.marker("READY", over: seeker)
        }
        time += 1.2
        let order = hiders.sorted { abs(x($0) - x(seeker)) < abs(x($1) - x(seeker)) }
        var from = x(seeker)
        for (index, one) in order.enumerated() {
            let target = x(one)
            let walk = TimeInterval(abs(target - from) / (NotchMascotRoam.walkSpeed * 2.2)) + 0.2
            let side: CGFloat = target >= from ? 1 : -1
            at(time) { seeker.stroll(to: target - side * self.figure * 0.8, pace: 2.2) }
            at(time + walk) { [weak self] in
                guard let self else { return }
                self.float("!", over: one)
                one.hop(dx: side * 40, dy: 380)
                one.pullFace(self.face(for: one, fallback: .surprised), for: 1.6)
                if index == order.count - 1 {
                    seeker.react(.celebrate)
                    self.marker("FOUND", over: seeker)
                }
            }
            from = target
            time += walk + 1.0
        }
        finish(after: time + 2.2)
    }

    /// A whisper passed along the line, a bubble at a time, heard a little
    /// wrong now and then; what comes out the end makes them laugh.
    private func telephone() {
        let ready = line(spacing: figure * 1.25)
        let chain = NotchMascotGroupPlay.whisperChain(steps: cast.count) { Double.random(in: 0..<1) }
        var time = ready + 0.2
        for (index, one) in cast.enumerated() {
            let word = chain[min(index, chain.count - 1)]
            let next = index + 1 < cast.count ? cast[index + 1] : nil
            at(time) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                if let next { one.face(toward: self.x(next)) }
                NotchMascotGangArt.bubble(in: canvas, at: self.onCanvas(one.head), symbol: word,
                                          size: max(12, self.figure * 0.3), duration: 1.4)
                next?.react(.peek)
                if index > 0, word != chain[index - 1] { one.pullFace(.confused, for: 1.2) }
            }
            time += 1.3
        }
        let first = cast[0]
        let changed = chain.first != chain.last
        at(time) { [weak self] in
            guard let self else { return }
            if changed {
                first.pullFace(.confused, for: 1.6)
                self.float("?", over: first)
            } else {
                self.cast.forEach { $0.react(.celebrate) }
            }
        }
        if changed { at(time + 1.2) { [weak self] in self?.mishap?(first) } }
        finish(after: time + 3)
    }

    /// Two at the ends of the screen whisper across it in crackling bubbles;
    /// those in between turn their heads back and forth.
    private func walkieTalkies() {
        let holders = cast.filter { wears($0, [.walkieTalkie]) }
        let first = holders.first ?? cast[0]
        let second = holders.dropFirst().first ?? cast[cast.count - 1]
        let middle = cast.filter { $0 !== first && $0 !== second }
        let floor = self.floor
        let left = x(first) <= x(second)
        let walk = max(first.stroll(to: left ? floor.lowerBound + 20 : floor.upperBound - 20, pace: 2),
                       second.stroll(to: left ? floor.upperBound - 20 : floor.lowerBound + 20, pace: 2))
        var time = walk + 0.4
        for message in 0..<5 {
            let speaker = message.isMultiple(of: 2) ? first : second
            let symbol = NotchMascotGroupPlay.whispers.randomElement() ?? "★"
            at(time) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                NotchMascotGangArt.bubble(in: canvas, at: self.onCanvas(speaker.head), symbol: symbol,
                                          size: max(12, self.figure * 0.3), duration: 1.3, crackles: true)
                self.sound(.bleep, at: self.x(speaker))
                for one in middle {
                    one.face(toward: self.x(speaker))
                    if message == 2 { one.pullFace(.confused, for: 1.6) }
                }
            }
            time += 1.5
        }
        at(time) { [weak self] in
            first.react(.celebrate)
            second.react(.celebrate)
            middle.forEach { $0.react(.confused) }
            if let one = middle.first { self?.float("?", over: one) }
        }
        finish(after: time + 2.4)
    }

    // MARK: Fights for fun

    /// Pillows swung in pairs, feathers everywhere, and all of them dizzy.
    private func pillowFight() {
        let ready = line(spacing: figure * 0.95)
        var time = ready + 0.2
        for round in 0..<4 {
            for pair in stride(from: round % 2, to: cast.count - 1, by: 2) {
                let one = cast[pair], other = cast[pair + 1]
                let hitter = Bool.random() ? one : other
                let hit = hitter === one ? other : one
                at(time + Double.random(in: 0...0.3)) { [weak self] in
                    guard let self, let canvas = self.canvas() else { return }
                    let side = self.direction(from: hitter, to: hit)
                    hitter.hop(dx: side * 70, dy: 200)
                    hitter.pullFace(self.face(for: hitter, fallback: .mischievous), for: 1)
                    let point = self.onCanvas(CGPoint(x: (self.x(hitter) + self.x(hit)) / 2, y: hit.head.y - self.figure * 0.3))
                    let plenty = self.wears(hitter, [.pillow])
                    NotchMascotGangArt.feathers(in: canvas, at: point, reach: self.figure * 0.8, count: plenty ? 10 : 6)
                    self.sound(.poof, at: self.x(hit))
                    self.at(0.15) {
                        hit.hop(dx: side * 160, dy: 220)
                        hit.pullFace(.dizzy, for: 1.2)
                    }
                }
            }
            time += 1.3
        }
        at(time) { [weak self] in
            guard let self else { return }
            self.cast.forEach { $0.pullFace(.dizzy, for: 1.8) }
        }
        at(time + 1.4) { [weak self] in
            guard let self, let one = self.cast.randomElement() else { return }
            self.mishap?(one)
        }
        finish(after: time + 3.4)
    }

    /// Snow falling, two sides and snowballs going across; most hit.
    private func snowballFight() {
        let middle = middleX
        let left = cast.filter { x($0) <= middle }
        let right = cast.filter { x($0) > middle }
        let sides = left.isEmpty || right.isEmpty
            ? (Array(cast.prefix(cast.count / 2)), Array(cast.dropFirst(cast.count / 2))) : (left, right)
        let length: TimeInterval = 12
        at(0) { [weak self] in
            guard let self, let canvas = self.canvas() else { return }
            NotchMascotGangArt.snowfall(in: canvas, area: self.screenArea, duration: length)
        }
        let floor = self.floor
        let ready = max(line(spacing: figure * 0.9, center: max(floor.lowerBound, middle - figure * 2.2), members: sides.0),
                        line(spacing: figure * 0.9, center: min(floor.upperBound, middle + figure * 2.2), members: sides.1))
        var time = ready + 0.2
        for throwIndex in 0..<7 {
            let fromLeft = throwIndex.isMultiple(of: 2)
            guard let thrower = (fromLeft ? sides.0 : sides.1).randomElement(),
                  let target = (fromLeft ? sides.1 : sides.0).randomElement() else { break }
            let hits = Double.random(in: 0..<1) < 0.7
            at(time) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                let side = self.direction(from: thrower, to: target)
                thrower.hop(dx: 0, dy: 180)
                NotchMascotPlayEffects.fly(.snowball, in: canvas, from: self.onCanvas(thrower.hand(toward: side)),
                                           to: self.onCanvas(target.head), duration: 0.7,
                                           side: max(10, self.figure * 0.24), falls: !hits,
                                           while: { [weak self] in self?.playing != nil })
                self.at(0.72) { [weak self] in
                    guard let self, let canvas = self.canvas() else { return }
                    if hits {
                        NotchMascotPlayEffects.sparks(in: canvas, at: self.onCanvas(target.head), reach: 16,
                                                      energy: NotchMascotPlay.Energy(red: 1, green: 1, blue: 1), count: 8)
                        target.hop(dx: side * 120, dy: 200)
                        target.pullFace(Bool.random() ? .dizzy : .angry, for: 1.4)
                    } else {
                        target.pullFace(.smug, for: 1.4)
                        thrower.pullFace(.disgusted, for: 1.2)
                    }
                }
            }
            time += 1.05
        }
        at(time + 0.4) { [weak self] in
            guard let self else { return }
            self.cast.forEach { $0.react(.celebrate) }
        }
        finish(after: max(length, time + 2.4))
    }

    /// Water squirted across from the ones holding pistols; an umbrella
    /// keeps one dry, and the rest come out dripping and laughing.
    private func waterFight() {
        let shooters = cast.filter { wears($0, [.waterPistol]) }
        let shooterList = shooters.isEmpty ? [cast[0]] : shooters
        let ready = line(spacing: figure * 1.3)
        var time = ready + 0.2
        var soaked: NotchMascotDesktop?
        for _ in 0..<6 {
            guard let shooter = shooterList.randomElement(),
                  let target = cast.filter({ $0 !== shooter }).randomElement() else { break }
            let sheltered = wears(target, [.umbrella])
            if !sheltered { soaked = target }
            at(time) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                let side = self.direction(from: shooter, to: target)
                shooter.pullFace(.mischievous, for: 1.2)
                if sheltered {
                    NotchMascotGangArt.umbrella(in: canvas, over: self.onCanvas(CGPoint(x: self.x(target),
                                                                                         y: target.head.y + 4)),
                                                size: self.figure * 0.7, duration: 1.4)
                }
                NotchMascotGangArt.squirt(in: canvas, from: self.onCanvas(shooter.hand(toward: side)),
                                          to: self.onCanvas(sheltered ? CGPoint(x: self.x(target), y: target.head.y + 10)
                                                              : target.screenCenter),
                                          duration: 0.6)
                self.at(0.65) {
                    if sheltered {
                        target.pullFace(.smug, for: 1.4)
                    } else {
                        target.hop(dx: side * 90, dy: 220)
                        target.pullFace(Bool.random() ? .crying : .surprised, for: 1.5)
                    }
                }
            }
            time += 1.1
        }
        at(time + 0.3) { [weak self] in
            guard let self, let soaked else { return }
            self.mishap?(soaked)
        }
        finish(after: time + 2.8)
    }

    // MARK: Gatherings

    /// A fire at night between them, lit by a dragon or a phoenix's breath
    /// when one is there; marshmallows toast, one catches fire, songs go up.
    private func campfire() {
        let lighter = cast.first { $0.playLook.style == .dragon || $0.playLook.style == .phoenix }
        let spacing = figure * 1.05
        let gap = figure * 1.4
        let middle = lineMiddle(spacing: spacing, count: cast.count, gap: gap)
        let ready = line(spacing: spacing, center: middle, gap: gap)
        let floorY = self.floorY
        let length: TimeInterval = 17
        let lit = ready + 1.4
        at(ready) { [weak self] in
            guard let self, let canvas = self.canvas() else { return }
            self.cast.forEach { $0.face(toward: middle) }
            let spark = self.onCanvas(CGPoint(x: middle, y: floorY + self.figure * 0.2))
            if let lighter {
                lighter.react(.ready)
                let side: CGFloat = self.x(lighter) <= middle ? 1 : -1
                NotchMascotPlayEffects.sparks(in: canvas, at: self.onCanvas(lighter.hand(toward: side)), reach: 18,
                                              energy: NotchMascotPlay.Energy(red: 1, green: 0.5, blue: 0.1))
                NotchMascotPlayEffects.beam(in: canvas, from: self.onCanvas(lighter.hand(toward: side)), to: spark,
                                            thickness: self.figure * 0.12,
                                            energy: NotchMascotPlay.Energy(red: 1, green: 0.45, blue: 0.1), life: 0.8)
                self.sound(.fire, at: middle)
            } else {
                NotchMascotPlayEffects.sparks(in: canvas, at: spark, reach: 10,
                                              energy: NotchMascotPlay.Energy(red: 1, green: 0.8, blue: 0.3), count: 5)
            }
        }
        at(lit) { [weak self] in
            guard let self, let canvas = self.canvas() else { return }
            NotchMascotGangArt.campfire(in: canvas, at: self.onCanvas(CGPoint(x: middle, y: floorY)),
                                        size: self.figure * 0.75, duration: length - lit)
            self.sound(.fire, at: middle)
            self.cast.forEach { $0.react(.celebrate) }
        }
        let burner = cast.randomElement()
        at(lit + 1.6) { [weak self] in
            guard let self, let canvas = self.canvas() else { return }
            for one in self.cast {
                let side: CGFloat = self.x(one) <= middle ? 1 : -1
                NotchMascotGangArt.marshmallow(in: canvas, hand: self.onCanvas(one.hand(toward: side)), toward: side,
                                               length: self.figure * 0.8, duration: 6, burns: one === burner)
            }
        }
        if let burner {
            at(lit + 6) { [weak self] in
                burner.pullFace(.crying, for: 2)
                self?.float("!", over: burner)
                burner.hop(dx: 0, dy: 300)
            }
            at(lit + 7.3) { [weak self] in self?.mishap?(burner) }
        }
        for song in 0..<4 {
            at(lit + 8.6 + Double(song) * 1.2) { [weak self] in
                guard let self, let one = self.cast.randomElement() else { return }
                self.notes(over: one)
                one.sway(amplitude: 0.12, speed: 8, duration: 1)
            }
        }
        at(length - 1.5) { [weak self] in
            guard let self else { return }
            self.cast.forEach { $0.pullFace(.happy, for: 1.4) }
            if let sleepy = self.cast.first(where: { self.personality($0) == .sleepy }) ?? self.cast.randomElement() {
                sleepy.react(.yawn)
            }
        }
        finish(after: length)
    }

    /// All close together, each pulling a face of its own, a countdown and
    /// a flash: the photo slides out and floats away.
    private func photo() {
        let spacing = figure * 0.8
        let middle = lineMiddle(spacing: spacing, count: cast.count)
        let photographer = wearer(.instantCamera)
        let posers = cast.filter { $0 !== photographer }
        let ready = line(spacing: spacing, center: middle, members: posers)
        let floor = self.floor
        let away: CGFloat = middle > (floor.lowerBound + floor.upperBound) / 2 ? -1 : 1
        let reach = spacing * CGFloat(posers.count) / 2 + figure * 1.6
        let cameraX = min(floor.upperBound, max(floor.lowerBound, middle + away * reach))
        let walk = photographer.map { $0.stroll(to: cameraX, pace: 1.8) } ?? 0
        let begin = max(ready, walk) + 0.3
        let floorY = self.floorY
        at(begin) { [weak self] in
            guard let self, let canvas = self.canvas() else { return }
            posers.forEach { $0.face(toward: cameraX) }
            photographer?.face(toward: middle)
            if photographer == nil {
                NotchMascotGangArt.camera(in: canvas, at: self.onCanvas(CGPoint(x: cameraX, y: floorY)), size: self.figure * 0.7,
                                          facing: -away, duration: 6)
            }
        }
        let cameraHead = CGPoint(x: cameraX, y: floorY + figure * 1.3)
        for count in 0..<3 {
            at(begin + 0.6 + Double(count) * 0.8) { [weak self] in self?.marker("\(3 - count)", at: cameraHead) }
        }
        var faces: [NotchMascotMood] = [.smug, .starstruck, .mischievous, .embarrassed, .angry, .dizzy, .greedy, .love,
                                        .wink, .disgusted, .terrified, .surprised].shuffled()
        let pose = begin + 2.6
        at(pose) {
            for one in posers {
                let face = faces.isEmpty ? NotchMascotMood.happy : faces.removeFirst()
                one.pullFace(face, for: 2.6)
                one.hop(dx: 0, dy: 200)
            }
        }
        at(pose + 0.35) { [weak self] in
            guard let self, let canvas = self.canvas() else { return }
            NotchMascotGangArt.flash(in: canvas, area: self.screenArea)
            NotchMascotGangArt.polaroid(in: canvas, at: self.onCanvas(cameraHead), size: self.figure * 0.55)
            photographer?.react(.celebrate)
        }
        at(pose + 2.4) { [weak self] in self?.cast.forEach { $0.react(.celebrate) } }
        finish(after: pose + 4.2)
    }

    /// Everyone dozes off in a heap, one asleep on top, and they wake one by one.
    private func napPile() {
        let spacing = figure * 0.45
        let ready = line(spacing: spacing)
        for (index, one) in cast.enumerated() {
            at(ready + Double(index) * 0.7) { one.react(.yawn) }
        }
        let asleep = ready + Double(cast.count) * 0.7 + 0.6
        let topper = cast.count > 2 ? cast[cast.count / 2] : nil
        let length = 25 + Double.random(in: 0...15)
        let floorY = self.floorY
        at(asleep) { [weak self] in
            guard let self else { return }
            for one in self.cast { one.setNapping(true) }
            if let topper {
                topper.hop(dx: 0, dy: 300)
                self.at(0.3) {
                    topper.glide(to: CGPoint(x: self.x(topper), y: floorY + self.figure * 0.5), over: 0.4)
                }
                self.at(0.75) {
                    topper.glide(to: CGPoint(x: self.x(topper), y: floorY + self.figure * 0.5), over: length)
                }
            }
        }
        var time = asleep + 1.5
        while time < asleep + length {
            let one = cast.randomElement()
            at(time) { [weak self] in
                guard let one else { return }
                self?.float("z", over: one, color: Self.snore)
            }
            time += 1.8
        }
        for (index, one) in cast.enumerated() {
            at(asleep + length + Double(index) * 0.6) {
                one.setNapping(false)
                one.react(.wakeUp)
            }
        }
        if let topper { at(asleep + length + 0.2) { topper.hop(dx: 120, dy: 200) } }
        finish(after: asleep + length + Double(cast.count) * 0.6 + 1.5)
    }

    /// Your birthday: they crouch and hush, then jump up all at once with
    /// confetti and a cake with candles, and sing.
    private func surpriseParty() {
        let spacing = figure * 0.95
        let gap = figure * 1.4
        let middle = lineMiddle(spacing: spacing, count: cast.count, gap: gap)
        let ready = line(spacing: spacing, center: middle, gap: gap)
        let floorY = self.floorY
        at(ready) {
            for one in self.cast {
                one.react(.hush)
                one.tilt(0.3, for: 1.6)
            }
        }
        let jump = ready + 2
        at(jump) { [weak self] in
            guard let self, let canvas = self.canvas() else { return }
            self.marker("SURPRISE!", at: CGPoint(x: middle, y: floorY + self.figure * 2.4))
            for one in self.cast {
                one.hop(dx: 0, dy: 700)
                one.pullFace(.starstruck, for: 2.5)
                self.burst(.confetti, over: one)
            }
            NotchMascotGangArt.cake(in: canvas, at: self.onCanvas(CGPoint(x: middle, y: floorY)), size: self.figure * 0.9,
                                    candles: 3, duration: 9)
            self.sound(.pop, at: middle)
        }
        at(jump + 1.6) { [weak self] in
            guard let self else { return }
            if let age = NotchMascotSpecialDays.ageMarker(on: Date()) {
                self.marker(age, at: CGPoint(x: middle, y: floorY + self.figure * 1.9))
            }
        }
        for verse in 0..<5 {
            at(jump + 2.4 + Double(verse) * 0.9) { [weak self] in
                guard let self else { return }
                self.cast.forEach { self.notes(over: $0) }
                if verse == 4 { self.sound(.chime, at: middle) }
            }
        }
        at(jump + 7.2) { [weak self] in
            guard let self else { return }
            for one in self.cast {
                one.react(.love)
                self.float("♥", over: one, color: Self.heart)
            }
        }
        finish(after: jump + 9.4)
    }

    /// A blanket, the basket and a snack flying to each; a glutton grabs a
    /// second one off its neighbour, who is not pleased.
    private func picnic() {
        let spacing = figure * 0.85
        let middle = lineMiddle(spacing: spacing, count: cast.count)
        let floorY = self.floorY
        at(0) { [weak self] in
            guard let self, let canvas = self.canvas() else { return }
            NotchMascotGangArt.blanket(in: canvas, at: self.onCanvas(CGPoint(x: middle, y: floorY)),
                                       width: spacing * CGFloat(self.cast.count) + self.figure, duration: 15)
        }
        let ready = line(spacing: spacing, center: middle)
        let basket = wearer(.picnicBasket)
        var time = ready + 0.4
        for one in cast {
            let snack = NotchMascotSnack.allCases.randomElement() ?? .apple
            at(time) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                let from = basket.map { self.onCanvas($0.hand(toward: self.direction(from: $0, to: one))) }
                    ?? self.onCanvas(CGPoint(x: middle, y: floorY + 6))
                NotchMascotPlayEffects.fly(.snack(snack), in: canvas, from: from, to: self.onCanvas(one.head), duration: 0.7,
                                           side: max(12, self.figure * 0.3), while: { [weak self] in self?.playing != nil })
                self.at(0.8) {
                    one.pullFace(self.personality(one) == .glutton ? .greedy : .happy, for: 1.4)
                    self.sound(.munch, at: self.x(one))
                }
            }
            time += 0.8
        }
        let thief = cast.first { personality($0) == .glutton } ?? cast.randomElement() ?? cast[0]
        let thiefIndex = cast.firstIndex { $0 === thief } ?? 0
        let victim = cast[thiefIndex + 1 < cast.count ? thiefIndex + 1 : max(0, thiefIndex - 1)]
        if victim !== thief {
            at(time + 0.6) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                thief.pullFace(.mischievous, for: 1.2)
                NotchMascotPlayEffects.fly(.cookie, in: canvas, from: self.onCanvas(victim.head), to: self.onCanvas(thief.head),
                                           duration: 0.6, side: max(12, self.figure * 0.28),
                                           while: { [weak self] in self?.playing != nil })
            }
            at(time + 1.4) { [weak self] in
                guard let self else { return }
                victim.pullFace(.angry, for: 2.2)
                self.float("!", over: victim)
                thief.pullFace(.greedy, for: 1.4)
                self.sound(.munch, at: self.x(thief))
            }
            at(time + 2.9) { thief.pullFace(.smug, for: 1.6) }
        }
        at(time + 4.6) { [weak self] in self?.cast.forEach { $0.pullFace(.love, for: 1.5) } }
        finish(after: time + 6.4)
    }

    /// A kite flown on its string until a storm cloud drifts over and the
    /// lightning finds it: the one holding the string is zapped, the rest
    /// scream and then laugh.
    private func kiteStorm() {
        let flier = wearer(.kite) ?? cast[0]
        let rainmaker = wearer(.stormCloud)
        let watchers = cast.filter { $0 !== flier }
        let floor = self.floor
        let room = x(flier) < (floor.lowerBound + floor.upperBound) / 2 ? CGFloat(1) : -1
        let floorY = self.floorY
        let top = CGPoint(x: min(floor.upperBound, max(floor.lowerBound, x(flier) + room * 140)), y: floorY + figure * 4.4)
        let length: TimeInterval = 11
        at(0.2) { [weak self] in
            guard let self, let canvas = self.canvas() else { return }
            NotchMascotGangArt.kite(in: canvas, from: self.onCanvas(flier.hand(toward: room)), to: self.onCanvas(top),
                                    size: self.figure * 0.55, duration: length - 3.4)
            flier.react(.celebrate)
            watchers.forEach { $0.face(toward: top.x) }
        }
        let cloudAt = CGPoint(x: top.x, y: top.y + figure * 1.4)
        at(2.4) { [weak self] in
            guard let self, let canvas = self.canvas() else { return }
            NotchMascotGangArt.stormCloud(in: canvas, over: self.onCanvas(cloudAt), size: self.figure * 1.1,
                                          duration: length - 2.4)
            rainmaker?.pullFace(.mischievous, for: 2)
            watchers.forEach { $0.pullFace(.terrified, for: 2.4) }
        }
        let strike = 5.6
        at(strike) { [weak self] in
            guard let self, let canvas = self.canvas() else { return }
            NotchMascotGangArt.bolt(in: canvas, from: self.onCanvas(cloudAt), to: self.onCanvas(top))
            self.at(0.15) {
                NotchMascotGangArt.bolt(in: canvas, from: self.onCanvas(top), to: self.onCanvas(flier.head))
                flier.hop(dx: 0, dy: 600)
                flier.pullFace(.dizzy, for: 3)
                self.float("!", over: flier)
            }
        }
        at(strike + 0.6) { watchers.forEach { $0.react(.panic) } }
        at(strike + 2.4) { [weak self] in self?.mishap?(flier) }
        finish(after: length)
    }
}

private extension Array {
    /// Turns the array round so the element at `index` comes first.
    mutating func rotate(to index: Int) {
        guard indices.contains(index), index > 0 else { return }
        self = Array(self[index...] + self[..<index])
    }
}
