// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// Everyone out on the desktop: the island's own companion, its friend and
/// the guests that come by on visits of their own. Each one's nearest
/// neighbour on its screen is the one it walks up to and waves at; what
/// passes by one is seen by all; a pat or a hard fall is answered by the
/// nearest. Any two free on a screen may play one of their plays, those who
/// get on best first, and three or more play all together. Guests come in
/// style, by parachute, balloon, pipe, door or beam, stay a few minutes
/// and go the same way, and never go into the island. With only the
/// island's two out, it all goes as it did for the two of them.
final class NotchMascotGang {
    let lead: NotchMascotDesktop
    let friend: NotchMascotDesktop

    /// Whether the island's two may play together.
    var allowed: () -> Bool = { false }
    /// Whether a song is playing.
    var music: () -> Bool = { false }
    /// The bond's level, which their energy grows with.
    var level: () -> Int = { 1 }
    /// Whether the island runs where it can show, so guests may come.
    var canHost: () -> Bool = { false }
    var openSettings: (() -> Void)?
    var openShop: (() -> Void)?

    /// A guest out on the desktop, who it is, and the goodbye waiting for it.
    private final class Guest {
        let desktop: NotchMascotDesktop
        let personality: NotchMascotPersonality
        let stage = NotchMascotPlayStage()
        var leaves: DispatchWorkItem?
        /// When it goes, on the media clock.
        var leavesAt: CFTimeInterval = 0
        var leaving = false
        /// Called out with the whole gang: it does not count against how
        /// many may come on their own.
        var summoned = false

        init(desktop: NotchMascotDesktop, personality: NotchMascotPersonality) {
            self.desktop = desktop
            self.personality = personality
        }
    }

    private var guests: [Guest] = []
    /// One director for each pair that has met; the island's two first.
    private var duos: [NotchMascotPlayDirector] = []
    private let group = NotchMascotGroupDirector()
    private var lastGroupPlay: CFTimeInterval = -.infinity
    private var groupRecent: [NotchMascotGroupPlay.Kind] = []
    /// The day the surprise party was thrown, so it is thrown once.
    private var partyDay: String?
    private var visitWork: DispatchWorkItem?
    private var visitsScheduled: NotchMascotGangVisits?
    private var atOnceSeen: Int?
    private var ambientWork: DispatchWorkItem?
    private var dozing: Set<ObjectIdentifier> = []
    private var lastPatResponse: CFTimeInterval = -.infinity
    /// What the gang draws for a crowd at something rare: coins and wares.
    private let crowdStage = NotchMascotPlayStage()
    private var summonObserver: NSObjectProtocol?

    private static let heart = CGColor(srgbRed: 1, green: 0.38, blue: 0.55, alpha: 1)
    private static let mark = CGColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: 1)

    init(lead: NotchMascotDesktop, friend: NotchMascotDesktop) {
        self.lead = lead
        self.friend = friend
        let pair = NotchMascotPlayDirector(leader: lead, friend: friend)
        pair.allowed = { [weak self] in self?.allowed() ?? false }
        pair.music = { [weak self] in self?.music() ?? false }
        pair.level = { [weak self] in self?.level() ?? 1 }
        duos = [pair]
        wire(lead)
        wire(friend)
        group.personality = { [weak self] one in self?.guest(one)?.personality }
        group.mishap = { [weak self] one in self?.spread(.laugh, from: one) }
        group.ended = { [weak self] _, cast in self?.playedTogether(cast) }
        summonObserver = NotificationCenter.default.addObserver(forName: .notchMascotSummonGang, object: nil,
                                                                queue: .main) { [weak self] _ in self?.summon() }
    }

    deinit {
        if let summonObserver { NotificationCenter.default.removeObserver(summonObserver) }
    }

    // MARK: Everyone

    /// The island's two and the guests, whether out or not.
    private var members: [NotchMascotDesktop] { [lead, friend] + guests.map(\.desktop) }
    private var out: [NotchMascotDesktop] { members.filter(\.isOut) }

    private func guest(_ one: NotchMascotDesktop) -> Guest? { guests.first { $0.desktop === one } }

    /// Whether guests are about: the gang's own life only starts then.
    private var gathering: Bool { guests.contains { $0.desktop.isOut } }

    private func x(_ one: NotchMascotDesktop) -> CGFloat { one.feet?.x ?? one.screenCenter.x }

    /// The others out on `one`'s screen, nearest first.
    private func others(near one: NotchMascotDesktop) -> [NotchMascotDesktop] {
        guard let screen = one.playScreen else { return [] }
        let here = x(one)
        return out.filter { $0 !== one && $0.playScreen == screen }.sorted { abs(x($0) - here) < abs(x($1) - here) }
    }

    /// The nearest other out on its screen with its feet on the floor.
    private func nearest(to one: NotchMascotDesktop) -> NotchMascotDesktop? {
        others(near: one).first { $0.feet != nil }
    }

    /// Whether `one` is in a play just now.
    private func busy(_ one: NotchMascotDesktop) -> Bool {
        group.involves(one) || duos.contains { $0.playing != nil && $0.involves(one) }
    }

    private var guestsMayPlay: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func wire(_ one: NotchMascotDesktop) {
        one.neighbor = { [weak self, weak one] in
            guard let self, let one else { return nil }
            return self.nearest(to: one)?.feet
        }
        one.greetNeighbor = { [weak self, weak one] point in
            guard let self, let one else { return }
            self.greeted(by: one, from: point)
        }
        one.invitePlay = { [weak self, weak one] in
            guard let self, let one else { return false }
            return self.invite(from: one)
        }
        one.interrupted = { [weak self, weak one] in
            guard let self, let one else { return }
            self.interrupted(one)
        }
        one.sawEncounter = { [weak self, weak one] encounter in
            guard let self, let one else { return }
            self.saw(encounter, by: one)
        }
        one.patted = { [weak self, weak one] in
            guard let self, let one else { return }
            self.patted(one)
        }
        one.landedHard = { [weak self, weak one] in
            guard let self, let one else { return }
            self.fell(one)
        }
        one.crowd = { [weak self, weak one] in
            guard let self, let one else { return 0 }
            return self.crowd(around: one).count
        }
        one.encounterSpot = { [weak self, weak one] encounter, spot in
            guard let self, let one else { return }
            self.gather(encounter, at: spot, around: one)
        }
        one.fellOffLedge = { [weak self, weak one] in
            guard let self, let one else { return }
            self.rescue(one)
        }
    }

    // MARK: The island's two

    /// The island's two are both out: their first play comes before long.
    func cameOut() { duos.first?.cameOut() }

    /// One of the island's two went in: whatever the two were doing stops.
    func wentIn() { duos.first?.wentIn() }

    /// Every play under way stops at once.
    func cancel() {
        duos.forEach { $0.cancel() }
        group.cancel()
    }

    /// The friend's own take on what the companion just reacted to, and
    /// the guests', and a yawn goes round.
    func echo(_ reaction: NotchMascotReaction) {
        if friend.isOut { duos.first?.echo(reaction) }
        guard gathering, lead.isOut else { return }
        if reaction == .yawn { spread(.yawn, from: lead); return }
        guard let echo = NotchMascotPlay.echo(of: reaction) else { return }
        for one in others(near: lead) where guest(one) != nil && !busy(one) && Bool.random() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.5...1.3)) { [weak one] in
                guard let one, one.isFree else { return }
                one.react(echo)
            }
        }
    }

    /// The music plays on or stops: everyone out bobs to it while they may.
    func syncMusic(dancing: Bool) {
        duos.first?.syncMusic(dancing: dancing)
        for guest in guests { guest.desktop.setDancing(dancing) }
    }

    // MARK: Playing

    /// Asked by one standing with nothing to do: a play of the whole gang
    /// when enough are about and one is due, else one with a partner.
    private func invite(from one: NotchMascotDesktop) -> Bool {
        guard !busy(one) else { return false }
        if startGroupPlay(around: one) { return true }
        // At most two pairs play at once, so the desktop does not turn into a fair.
        guard duos.filter({ $0.playing != nil }).count < 2 else { return false }
        let partners = others(near: one).filter { !busy($0) && $0.feet != nil }
        guard !partners.isEmpty else { return duos.first.map { $0.involves(one) && $0.invite() } ?? false }
        let here = x(one)
        let partner = NotchMascotRapport.weighted(partners, weight: { other in
            self.preference(one, other) / (1 + Double(abs(self.x(other) - here)) / 300)
        }, random: Double.random(in: 0..<1)) ?? partners[0]
        return director(for: one, partner).invite()
    }

    private func preference(_ one: NotchMascotDesktop, _ other: NotchMascotDesktop) -> Double {
        guard guest(one) != nil || guest(other) != nil else { return 1 }
        return NotchMascotRapport.relation(one.playLook.style, other.playLook.style).preference
    }

    /// The director for the pair, made the first time they meet.
    private func director(for one: NotchMascotDesktop, _ other: NotchMascotDesktop) -> NotchMascotPlayDirector {
        if let known = duos.first(where: { $0.involves(one) && $0.involves(other) }) { return known }
        // The island's own leads; else whoever asked.
        let leader = other === lead ? other : one
        let partner = leader === one ? other : one
        let pair = NotchMascotPlayDirector(leader: leader, friend: partner)
        pair.allowed = { [weak self] in self?.guestsMayPlay ?? false }
        pair.music = { [weak self] in self?.music() ?? false }
        pair.level = { [weak self] in self?.level() ?? 1 }
        pair.relation = { [weak leader, weak partner] in
            guard let leader, let partner else { return nil }
            return NotchMascotRapport.relation(leader.playLook.style, partner.playLook.style)
        }
        pair.leanings = { [weak self, weak leader, weak partner] in
            guard let self, let leader, let partner else { return [:] }
            return self.leanings(leader, partner)
        }
        pair.ended = { [weak leader, weak partner] play in
            guard let leader, let partner else { return }
            NotchMascotRapport.record(NotchMascotRapport.change(after: play), between: leader.playLook.style,
                                       and: partner.playLook.style)
        }
        pair.cameOut()
        duos.append(pair)
        return pair
    }

    /// What the two feel for each other and who they are, as more or less
    /// of each play: the leanings multiply.
    private func leanings(_ one: NotchMascotDesktop, _ other: NotchMascotDesktop) -> [NotchMascotPlay.Kind: Double] {
        var leanings = NotchMascotRapport.relation(one.playLook.style, other.playLook.style).leanings
        for personality in [guest(one)?.personality, guest(other)?.personality].compactMap({ $0 }) {
            for (kind, factor) in personality.leanings { leanings[kind, default: 1] *= factor }
        }
        return leanings
    }

    /// A play of the whole gang, when three or more stand free on `one`'s
    /// screen and one is due.
    private func startGroupPlay(around one: NotchMascotDesktop) -> Bool {
        guard group.playing == nil, guestsMayPlay, !one.isDozing, let screen = one.playScreen else { return false }
        let cast = out.filter { $0.playScreen == screen && $0.isFree && !$0.isDozing && !busy($0) }
        guard cast.count >= NotchMascotGroupPlay.minimum, cast.contains(where: { $0 === one }) else { return false }
        let now = Date()
        let calendar = Calendar.current
        let today = NotchMascotSpecialDays.key(for: now)
        let birthday = NotchMascotSpecialDays.moment(on: now, birthday: NotchMascotSpecialDays.birthday(
            from: UserDefaults.standard.string(forKey: DefaultsKey.notchMascotBirthday))) == .birthday
        let context = NotchMascotGroupPlay.Context(
            count: cast.count, hour: calendar.component(.hour, from: now), month: calendar.component(.month, from: now),
            birthday: birthday && partyDay != today, music: music(),
            items: cast.filter { $0.playLook.style.takesAccessory }.map(\.playLook.accessory),
            styles: cast.map(\.playLook.style), personalities: cast.compactMap { guest($0)?.personality },
            recent: groupRecent)
        guard let kind = NotchMascotGroupPlay.next(in: context, since: CACurrentMediaTime() - lastGroupPlay,
                                                   random: { Double.random(in: 0..<1) })
        else { return false }
        if kind == .surpriseParty { partyDay = today }
        lastGroupPlay = CACurrentMediaTime()
        groupRecent = Array((groupRecent + [kind]).suffix(NotchMascotGroupPlay.memory))
        group.start(kind, with: Array(cast.prefix(NotchMascotGangVisits.mostOut)))
        return true
    }

    /// A play of the whole gang went well: those in it grow a little closer.
    private func playedTogether(_ cast: [NotchMascotDesktop]) {
        for (index, one) in cast.enumerated() {
            for other in cast.dropFirst(index + 1) where guest(one) != nil || guest(other) != nil {
                NotchMascotRapport.record(NotchMascotRapport.good * 0.5, between: one.playLook.style,
                                           and: other.playLook.style)
            }
        }
    }

    /// Pressed on or sent home mid-play: the play it was in stops.
    private func interrupted(_ one: NotchMascotDesktop) {
        for pair in duos where pair.involves(one) { pair.cancel() }
        if group.involves(one) { group.cancel() }
    }

    // MARK: Between plays

    /// `one` waved at its nearest neighbour from `point`, which waves back;
    /// a crush blushes, rivals scowl and sneer.
    private func greeted(by one: NotchMascotDesktop, from point: CGPoint) {
        guard let other = nearest(to: one) else { return }
        other.greet(toward: point)
        guard guest(one) != nil || guest(other) != nil else { return }
        switch NotchMascotRapport.relation(one.playLook.style, other.playLook.style) {
        case .crush:
            one.pullFace(.embarrassed, for: 2.4)
            other.pullFace(.love, for: 2.4)
            float("♥", over: one, color: Self.heart, count: 2)
        case .rivals:
            one.pullFace(.angry, for: 2)
            other.pullFace(.smug, for: 2)
        case .friends:
            other.pullFace(.happy, for: 1.6)
        case .strangers:
            if let personality = guest(other)?.personality { other.pullFace(personality.arrivalFace, for: 1.6) }
        }
    }

    /// One was patted: its nearest neighbour minds, wants one too or cheers
    /// it on, each guest in its own way, and a guest patted pulls its face.
    private func patted(_ one: NotchMascotDesktop) {
        if let personality = guest(one)?.personality {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak one] in
                one?.pullFace(personality.pattedFace, for: 1.8)
            }
        }
        guard !busy(one), let other = others(near: one).first, !busy(other) else { return }
        // A pat wakes a nap.
        if other.napping {
            other.setNapping(false)
            other.react(.wakeUp)
            return
        }
        let now = CACurrentMediaTime()
        guard other.isFree, now - lastPatResponse > NotchMascotPlay.patResponseInterval,
              let a = one.feet, let b = other.feet else { return }
        lastPatResponse = now
        let side: CGFloat = a.x >= b.x ? 1 : -1
        let jealous = guest(other)?.personality
        switch NotchMascotPlay.patResponse(distance: abs(a.x - b.x), random: Double.random(in: 0..<1)) {
        case .comesOver:
            let walk = other.stroll(to: a.x - side * 64, pace: 1.6)
            DispatchQueue.main.asyncAfter(deadline: .now() + walk + 0.2) { [weak other] in
                guard let other, other.isFree else { return }
                other.react(.bounce)
            }
        case .wantsOne:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak other] in
                guard let self, let other, other.isFree else { return }
                other.face(toward: a.x)
                other.hop(dx: side * 60, dy: 260)
                self.float("!", over: other, color: Self.mark)
                if jealous == .grumpy { other.pullFace(.angry, for: 1.6) }
            }
        case .cheers:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak other] in
                guard let other, other.isFree else { return }
                if jealous == .shy { other.pullFace(.embarrassed, for: 1.6) } else { other.react(.celebrate) }
            }
        }
    }

    /// One came down hard: its nearest neighbour gasps and goes to see
    /// it's all right.
    private func fell(_ one: NotchMascotDesktop) {
        guard !busy(one), let other = others(near: one).first, other.isFree, !busy(other) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak one, weak other] in
            guard let self, let one, let other, other.isFree else { return }
            other.react(.surprised)
            guard let a = one.feet, let b = other.feet else { return }
            let side: CGFloat = a.x >= b.x ? 1 : -1
            let walk = abs(a.x - b.x) > 90 ? other.stroll(to: a.x - side * 60, pace: 2) : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + walk + 0.9) { [weak self, weak other] in
                guard let self, let other, other.isFree else { return }
                other.react(.love)
                self.float("♥", over: other, color: Self.heart)
            }
        }
    }

    /// Floats `symbol` up over `one`'s head.
    private func float(_ symbol: String, over one: NotchMascotDesktop, color: CGColor, count: Int = 1) {
        guard let layer = one.effects else { return }
        NotchMascotPlayEffects.float(symbol, in: layer, at: one.local(one.head), size: max(9, one.figureSize * 0.2),
                                     color: color, count: count)
    }

    // MARK: Catching

    /// What goes round those standing near each other, a moment apart.
    enum Contagion { case yawn, sneeze, laugh, fright }

    /// `contagion` goes from `one` to those near it, the nearest first.
    private func spread(_ contagion: Contagion, from one: NotchMascotDesktop) {
        guard gathering else { return }
        let here = x(one)
        for (index, other) in others(near: one).enumerated() where abs(x(other) - here) < 520 && !other.napping {
            let delay = 0.35 + Double(index) * 0.45 + Double(abs(x(other) - here) / 900)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak other] in
                guard let self, let other, other.isOut else { return }
                switch contagion {
                case .yawn:
                    if other.isFree { other.react(.yawn) }
                case .sneeze:
                    other.react(.surprised)
                    other.hop(dx: 0, dy: 160)
                    self.float("✱", over: other, color: CGColor(gray: 0.95, alpha: 1))
                case .laugh:
                    other.pullFace(.happy, for: 1.4)
                    other.react(.celebrate)
                    self.float("ha", over: other, color: Self.mark)
                case .fright:
                    other.react(.panic)
                    other.pullFace(.terrified, for: 1.8)
                }
            }
        }
        if contagion == .laugh { one.pullFace(.embarrassed, for: 2) }
    }

    /// Now and then, while guests are about: one sneezes, and one dozing
    /// off sets the others yawning.
    private func scheduleAmbient() {
        guard ambientWork == nil, gathering else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.ambientWork = nil
            guard self.gathering else { self.dozing.removeAll(); return }
            let free = self.out.filter { $0.isFree && !self.busy($0) }
            let nowDozing = Set(self.out.filter(\.isDozing).map(ObjectIdentifier.init))
            if let fresh = self.out.first(where: { nowDozing.contains(ObjectIdentifier($0))
                                                   && !self.dozing.contains(ObjectIdentifier($0)) }) {
                self.spread(.yawn, from: fresh)
            }
            self.dozing = nowDozing
            if self.guestsMayPlay, Double.random(in: 0..<1) < 0.08, let sneezer = free.filter({ !$0.isDozing }).randomElement() {
                sneezer.react(.surprised)
                sneezer.hop(dx: 0, dy: 200)
                self.float("✱", over: sneezer, color: CGColor(gray: 0.95, alpha: 1), count: 2)
                NotchMascotSound.play(.poof, pan: 0)
                self.spread(.sneeze, from: sneezer)
            }
            self.scheduleAmbient()
        }
        ambientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: work)
    }

    /// One lost the window it stood on: the others near enough run under
    /// it, and it comes down into their arms.
    private func rescue(_ one: NotchMascotDesktop) {
        guard gathering, guestsMayPlay, !busy(one) else { return }
        let fallX = one.screenCenter.x
        let catchers = Array(others(near: one).filter { $0.isFree && !busy($0) && abs(x($0) - fallX) < 420 }.prefix(2))
        guard let first = catchers.first, let floorY = first.feet?.y else { return }
        let fall: TimeInterval = 1.4
        let spot = min(first.floor.upperBound, max(first.floor.lowerBound, fallX))
        for (index, catcher) in catchers.enumerated() {
            let offset = (index == 0 ? -1 : 1) * catcher.figureSize * 0.3
            let pace = min(4, max(1.5, abs(spot + offset - x(catcher)) / (NotchMascotRoam.walkSpeed * CGFloat(fall))))
            catcher.pullFace(.terrified, for: fall)
            catcher.stroll(to: spot + offset, pace: pace)
        }
        one.glide(to: CGPoint(x: spot, y: floorY + first.figureSize * 0.9), over: fall)
        DispatchQueue.main.asyncAfter(deadline: .now() + fall) { [weak self, weak one] in
            guard let self, let one, one.isOut else { return }
            for catcher in catchers where catcher.isOut {
                catcher.hop(dx: 0, dy: 160)
                catcher.react(.celebrate)
                NotchMascotRapport.record(NotchMascotRapport.good, between: one.playLook.style,
                                           and: catcher.playLook.style)
            }
            one.pullFace(.love, for: 2)
            self.float("♥", over: one, color: Self.heart, count: 3)
        }
    }

    // MARK: What passes by

    /// What passes by one is seen by everyone out; a ghost sends all of
    /// them running into each other's arms, and what frightens spreads.
    private func saw(_ encounter: NotchMascotEncounter, by one: NotchMascotDesktop) {
        for other in out where other !== one { other.witness(encounter) }
        guard gathering else { return }
        if encounter.witnessReaction == .panic { spread(.fright, from: one) }
        if encounter.gathers == .pile { pile(around: one) }
    }

    /// The others on its screen who would join in what passes by it; none
    /// unless at least two would.
    private func crowd(around one: NotchMascotDesktop) -> [NotchMascotDesktop] {
        guard gathering, guestsMayPlay else { return [] }
        let crowd = others(near: one).filter { $0.isFree && !busy($0) && !$0.isDozing }
        return crowd.count >= 2 ? crowd : []
    }

    /// Scared stiff, everyone runs to the one the ghost went through and
    /// they shake in a heap.
    private func pile(around one: NotchMascotDesktop) {
        let crowd = self.crowd(around: one)
        guard !crowd.isEmpty, let feet = one.feet else { return }
        for (index, other) in crowd.enumerated() {
            other.beginPlay()
            let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            let spot = feet.x + side * other.figureSize * (0.25 + 0.2 * CGFloat(index / 2))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2 + Double(index) * 0.15) { [weak other] in
                guard let other, other.isOut else { return }
                other.pullFace(.terrified, for: 4)
                let walk = other.stroll(to: spot, pace: 3.2)
                DispatchQueue.main.asyncAfter(deadline: .now() + walk + 0.1) { [weak other] in
                    other?.hop(dx: -side * 40, dy: 260)
                    other?.sway(amplitude: 0.1, speed: 45, duration: 2)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 7.5) { [weak other] in
                other?.react(.sweat)
                other?.endPlay(after: 2.5)
            }
        }
    }

    /// The saucer took one, and the others chase after it where it went;
    /// at the seller's, they queue up behind the one it stopped by.
    private func gather(_ encounter: NotchMascotEncounter, at spot: CGPoint, around one: NotchMascotDesktop) {
        let crowd = self.crowd(around: one)
        guard !crowd.isEmpty else { return }
        switch encounter.gathers {
        case .chase?: chase(to: spot, crowd: crowd, taken: one)
        case .queue?: queue(at: spot, crowd: Array(crowd.prefix(NotchMascotEncounters.queueLength)), front: one)
        case .pile?, nil: break
        }
    }

    private func chase(to spot: CGPoint, crowd: [NotchMascotDesktop], taken: NotchMascotDesktop) {
        for (index, other) in crowd.enumerated() {
            other.beginPlay()
            let lag = Double(index) * 0.25
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8 + lag) { [weak self, weak other] in
                guard let self, let other, other.isOut else { return }
                other.pullFace(.terrified, for: 2)
                self.float("!", over: other, color: Self.mark)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.2 + lag) { [weak other] in
                other?.stroll(to: spot.x + CGFloat(index) * 30, pace: 3)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 9 + lag) { [weak other] in
                other?.react(.confused)
                other?.pullFace(.crying, for: 1.6)
            }
            // It drops back near where the saucer went: they run to it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 11.4 + lag) { [weak other, weak taken] in
                guard let other, let taken, other.isOut else { return }
                let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
                other.stroll(to: (taken.feet?.x ?? spot.x) + side * other.figureSize, pace: 2.6)
                other.pullFace(.starstruck, for: 2)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 13.5 + lag) { [weak other] in
                other?.react(.love)
                other?.endPlay(after: 2.5)
            }
        }
    }

    private func queue(at seller: CGPoint, crowd: [NotchMascotDesktop], front: NotchMascotDesktop) {
        guard let start = front.feet?.x, let screen = front.playScreen,
              let canvas = crowdStage.layer(over: screen) else { return }
        let side: CGFloat = seller.x >= start ? 1 : -1
        let size = front.figureSize
        // The one at the front steps to the back of the line.
        front.stroll(to: start - side * size * 1.1 * CGFloat(crowd.count + 1), pace: 1.4)
        for (index, other) in crowd.enumerated() {
            other.beginPlay()
            other.stroll(to: start - side * size * 1.1 * CGFloat(index), pace: 1.8)
            let turn = 0.8 + Double(index) * NotchMascotEncounters.queueTurn
            DispatchQueue.main.asyncAfter(deadline: .now() + turn) { [weak self, weak other] in
                guard let self, let other, other.isOut else { return }
                let walk = other.stroll(to: start, pace: 1.6)
                DispatchQueue.main.asyncAfter(deadline: .now() + walk + 0.3) { [weak self, weak other] in
                    guard let self, let other, other.isOut else { return }
                    other.react(.perk)
                    NotchMascotPlayEffects.fly(.coin, in: canvas, from: self.crowdStage.point(other.hand(toward: side)),
                                               to: self.crowdStage.point(CGPoint(x: seller.x, y: seller.y + size * 0.6)),
                                               duration: 0.6, side: max(12, size * 0.26))
                }
                let ware: NotchMascotIslandPlay.Thing = [.potion, .key, .flower, .cookie, .balloon, .star].randomElement() ?? .star
                DispatchQueue.main.asyncAfter(deadline: .now() + walk + 1.2) { [weak self, weak other] in
                    guard let self, let other, other.isOut else { return }
                    NotchMascotPlayEffects.fly(ware, in: canvas,
                                               from: self.crowdStage.point(CGPoint(x: seller.x, y: seller.y + size * 0.6)),
                                               to: self.crowdStage.point(other.head), duration: 0.7, side: max(14, size * 0.32))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + walk + 2.1) { [weak other] in
                    guard let other, other.isOut else { return }
                    other.react(.celebrate)
                    other.pullFace(.greedy, for: 1.6)
                    other.stroll(to: start - side * size * 1.1 * CGFloat(crowd.count + 2 + index), pace: 1.4)
                    other.endPlay(after: 4)
                }
            }
        }
        let done = 1.5 + Double(crowd.count) * NotchMascotEncounters.queueTurn + 3
        DispatchQueue.main.asyncAfter(deadline: .now() + done) { [weak self] in self?.crowdStage.close() }
    }

    // MARK: Guests

    /// Follows the settings: guests start coming, stop coming, or go.
    func sync() {
        let defaults = UserDefaults.standard
        guard canHost(), NotchMascotSupport.roamsDesktop(in: defaults) else {
            stopVisits()
            dismissGuests()
            return
        }
        let visits = NotchMascotGangVisits.current(in: defaults)
        if visits == .off || !guestsMayPlay {
            stopVisits()
            for guest in guests where !guest.leaving { leave(guest, quickly: !guestsMayPlay) }
        } else if visitWork == nil || visitsScheduled != visits {
            scheduleVisit(visits)
        }
        // Fewer allowed at once than before: the last to come go first.
        let atOnce = NotchMascotGangVisits.atOnce(in: defaults)
        if let seen = atOnceSeen, atOnce < seen {
            let staying = guests.filter { !$0.leaving && !$0.summoned }
            for guest in staying.dropFirst(atOnce).reversed() { leave(guest) }
        }
        atOnceSeen = atOnce
    }

    /// Every guest goes at once, as the island stops.
    func dismissGuests() {
        for guest in guests {
            guest.leaves?.cancel()
            interrupted(guest.desktop)
            guest.desktop.dismiss()
            guest.stage.close()
        }
        guests.removeAll()
        forgetDeparted()
        crowdStage.close()
    }

    private func stopVisits() {
        visitWork?.cancel(); visitWork = nil
        visitsScheduled = nil
    }

    private func scheduleVisit(_ visits: NotchMascotGangVisits) {
        visitWork?.cancel(); visitWork = nil
        visitsScheduled = visits
        guard let delay = visits.delay else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.visitWork = nil
            let count = Double.random(in: 0..<1) < NotchMascotGangVisits.pairChance ? 2 : 1
            // They come to see the companion: more surely while it is out.
            if self.lead.isOut || Bool.random() { self.bring(count, stagger: 1.6) }
            self.scheduleVisit(NotchMascotGangVisits.current())
        }
        visitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: delay), execute: work)
    }

    /// The whole gang, called out at once: as many guests as may ever be
    /// out, coming in one after another, whatever the visits are set to.
    private func summon() {
        guard canHost(), NotchMascotSupport.roamsDesktop(), guestsMayPlay else { return }
        bring(NotchMascotGangVisits.atOnce.upperBound, stagger: 1.1, summoned: true)
    }

    /// Brings `count` guests out, `stagger` seconds apart.
    private func bring(_ count: Int, stagger: TimeInterval, summoned: Bool = false) {
        for index in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * stagger) { [weak self] in
                _ = self?.bringGuest(summoned: summoned)
            }
        }
    }

    /// One guest comes out, in style: a figure not already out, never the
    /// comic's own unless unlocked, in its own colours and wearing
    /// something from the whole wardrobe. False when none may come now.
    @discardableResult
    private func bringGuest(summoned: Bool) -> Bool {
        let defaults = UserDefaults.standard
        guard canHost(), NotchMascotSupport.roamsDesktop(in: defaults), guestsMayPlay else { return false }
        let limit = summoned ? NotchMascotGangVisits.atOnce.upperBound : NotchMascotGangVisits.atOnce(in: defaults)
        let counted = summoned ? guests.count : guests.filter { !$0.summoned }.count
        guard counted < limit, guests.count < NotchMascotGangVisits.atOnce.upperBound,
              out.count < NotchMascotGangVisits.mostOut else { return false }
        var taken = Set(out.map(\.playLook.style))
        taken.insert(NotchMascotSupport.look(in: defaults).style)
        if let style = NotchMascotSupport.desktopFriend(in: defaults)?.style { taken.insert(style) }
        let styles = NotchMascotGangCasting.styles(name: defaults.string(forKey: DefaultsKey.notchMascotName), excluding: taken)
        guard let style = styles.randomElement(), let screen = hostScreen() else { return false }
        let personality = NotchMascotPersonality.of(style)
        let look = NotchMascotGangCasting.look(for: style) { Double.random(in: 0..<1) }
        let desktop = NotchMascotDesktop(leads: false)
        wire(desktop)
        desktop.gait = personality.gait
        desktop.openSettings = { [weak self] in self?.openSettings?() }
        desktop.openShop = { [weak self] in self?.openShop?() }
        desktop.cameHome = { [weak self, weak desktop] _ in
            guard let self, let desktop else { return }
            self.departed(desktop)
        }
        desktop.guestMenu = { [weak self, weak desktop] in
            guard let self, let desktop else { return nil }
            return self.menu(for: desktop)
        }
        let guest = Guest(desktop: desktop, personality: personality)
        guest.summoned = summoned
        guests.append(guest)
        enter(guest, look: look, on: screen)
        scheduleGoodbye(guest, after: Double.random(in: NotchMascotGangVisits.stay))
        let now = CACurrentMediaTime()
        if now - lastGroupPlay > NotchMascotGroupPlay.interval {
            lastGroupPlay = now - NotchMascotGroupPlay.interval + NotchMascotGroupPlay.firstAfter
        }
        scheduleAmbient()
        return true
    }

    /// The screen the gang gathers on: where the companion is, else where
    /// any of them is, else the main one.
    private func hostScreen() -> NSScreen? {
        out.lazy.compactMap(\.playScreen).first ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Where along the floor a newcomer lands: away from those already there.
    private func landingX(in area: CGRect, size: CGFloat) -> CGFloat {
        let margin = min(area.width / 3, size * 2)
        let taken = out.map(x)
        var best = area.midX, room: CGFloat = -1
        for _ in 0..<8 {
            let candidate = CGFloat.random(in: (area.minX + margin)...max(area.minX + margin, area.maxX - margin))
            let nearest = taken.map { abs($0 - candidate) }.min() ?? .infinity
            if nearest > room { room = nearest; best = candidate }
        }
        return best
    }

    // MARK: Comings and goings

    private func enter(_ guest: Guest, look: NotchMascotLook, on screen: NSScreen) {
        let desktop = guest.desktop
        let area = screen.visibleFrame
        let size = NotchMascotRoam.size(for: look)
        let landing = landingX(in: area, size: size)
        let floor = CGPoint(x: landing, y: area.minY)
        let mood = guest.personality.mood
        let entrance = NotchMascotEntrance.pick(for: guest.personality, random: Double.random(in: 0..<1))
        let canvas = guest.stage.layer(over: screen)
        let local = { (point: CGPoint) in guest.stage.point(point) }
        var settled: TimeInterval = 1
        switch entrance {
        case .walkIn:
            let side: CGFloat = landing < area.midX ? -1 : 1
            let start = CGPoint(x: side < 0 ? area.minX - size : area.maxX + size, y: area.minY)
            desktop.arrive(at: start, look: look, mood: mood, fadeIn: 0)
            let walk = TimeInterval(abs(landing - start.x) / (NotchMascotRoam.walkSpeed * 1.4))
            desktop.glide(to: floor, over: walk)
            settled = walk
        case .parachute:
            let top = CGPoint(x: landing, y: area.maxY - size * 3.4)
            let low = CGPoint(x: landing, y: area.minY + size * 0.25)
            desktop.arrive(at: top, look: look, mood: mood, fadeIn: 0.3)
            desktop.glide(to: low, over: 5.5)
            if let canvas { NotchMascotGangArt.parachute(in: canvas, from: local(top), to: local(low), size: size, duration: 5.5) }
            settled = 6.2
        case .balloon:
            let top = CGPoint(x: landing, y: area.maxY - size * 3)
            let low = CGPoint(x: landing, y: area.minY + size * 0.3)
            let hold = CGPoint(x: 0, y: size * 0.95)
            desktop.arrive(at: top, look: look, mood: mood, fadeIn: 0.3)
            desktop.glide(to: low, over: 6.5)
            if let canvas {
                let string = { (point: CGPoint) in local(CGPoint(x: point.x, y: point.y + hold.y)) }
                NotchMascotGangArt.balloon(in: canvas, from: string(top), to: string(low), size: size * 0.7, duration: 6.5)
                // Let go, the balloon goes on up on its own.
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
                    NotchMascotGangArt.balloon(in: canvas, from: string(low),
                                               to: string(CGPoint(x: low.x + size, y: area.maxY + size * 2)),
                                               size: size * 0.7, duration: 3.5)
                }
            }
            settled = 7
        case .dockPop:
            let below = CGPoint(x: landing, y: area.minY - size)
            desktop.arrive(at: below, look: look, mood: mood, fadeIn: 0.12, growFrom: 0.6)
            desktop.glide(to: CGPoint(x: landing, y: area.minY + size * 1.3), over: 0.35)
            if let canvas {
                NotchMascotEncounterArt.dust(in: canvas, at: local(floor), radius: size * 0.6)
                NotchMascotSound.play(.pop, pan: NotchMascotPlayEffects.pan(x: local(floor).x, in: canvas))
            }
            settled = 1.4
        case .pipe:
            if let canvas { NotchMascotGangArt.pipe(in: canvas, at: local(floor), width: size * 1.2, duration: 4.4) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak desktop] in
                guard let desktop else { return }
                desktop.arrive(at: floor, look: look, mood: mood, fadeIn: 0)
                desktop.hop(dx: (landing < area.midX ? 1 : -1) * 150, dy: 760)
            }
            settled = 2.6
        case .door:
            if let canvas { NotchMascotPlayEffects.secretDoor(in: canvas, at: local(floor), height: size * 1.5, duration: 4) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak desktop] in
                guard let desktop else { return }
                desktop.arrive(at: floor, look: look, mood: mood, fadeIn: 0.4, growFrom: 0.7)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak desktop] in
                    desktop?.stroll(to: landing + (landing < area.midX ? 1 : -1) * size * 1.3, pace: 1.2)
                }
            }
            settled = 3
        case .teleport:
            if let canvas {
                NotchMascotGangArt.beam(in: canvas, at: local(floor), width: size * 1.2, height: area.height * 0.85,
                                        duration: 2.2, energy: NotchMascotPlay.energy(for: look))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak desktop] in
                desktop?.arrive(at: floor, look: look, mood: mood, fadeIn: 0.5, growFrom: 0.2)
            }
            settled = 2.2
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + settled + 0.4) { [weak self, weak desktop] in
            guard let self, let desktop, desktop.isOut else { return }
            desktop.pullFace(self.guest(desktop)?.personality.arrivalFace ?? .happy, for: 2.2)
            if let other = self.nearest(to: desktop) { desktop.face(toward: self.x(other)) }
            desktop.react(.wave)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + settled + 4.5) { [weak guest] in
            guard let guest, !guest.leaving else { return }
            guest.stage.close()
        }
    }

    private func scheduleGoodbye(_ guest: Guest, after delay: TimeInterval) {
        guest.leaves?.cancel()
        guest.leavesAt = CACurrentMediaTime() + delay
        let work = DispatchWorkItem { [weak self, weak guest] in
            guard let self, let guest else { return }
            guest.leaves = nil
            self.leave(guest)
        }
        guest.leaves = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// The guest goes its own way: waving and walking off, on a balloon,
    /// into a box or through the door it came by. Busy just then, held or
    /// in the air, it goes a little later; `quickly`, it simply fades.
    private func leave(_ guest: Guest, quickly: Bool = false) {
        let desktop = guest.desktop
        guard desktop.isOut else { departed(desktop); return }
        if quickly {
            guest.leaving = true
            interrupted(desktop)
            desktop.depart(over: 0.3) { [weak self, weak desktop] in
                guard let self, let desktop else { return }
                self.departed(desktop)
            }
            return
        }
        guard desktop.feet != nil, !busy(desktop) else {
            scheduleGoodbye(guest, after: 8)
            return
        }
        guest.leaving = true
        guest.leaves?.cancel(); guest.leaves = nil
        desktop.beginPlay()
        guard let screen = desktop.playScreen, let feet = desktop.feet else { return }
        let area = screen.visibleFrame
        let size = desktop.figureSize
        let canvas = guest.stage.layer(over: screen)
        let local = { (point: CGPoint) in guest.stage.point(point) }
        let gone = { [weak self, weak desktop] in
            guard let self, let desktop else { return }
            self.departed(desktop)
        }
        if let other = nearest(to: desktop) { desktop.face(toward: x(other)) }
        desktop.react(.wave)
        let exit = NotchMascotExit.pick(for: guest.personality, random: Double.random(in: 0..<1))
        let after = { (delay: TimeInterval, block: @escaping () -> Void) in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { if desktop.isOut { block() } }
        }
        switch exit {
        case .walkOff:
            let side: CGFloat = feet.x < area.midX ? -1 : 1
            let edge = side < 0 ? desktop.floor.lowerBound : desktop.floor.upperBound
            after(1.2) {
                let walk = desktop.stroll(to: edge, pace: 1.8)
                after(walk + 0.1) {
                    desktop.glide(to: CGPoint(x: edge + side * size * 1.6, y: area.minY), over: 1.2) {
                        desktop.depart(over: 0.15, then: gone)
                    }
                }
            }
        case .balloon:
            let hold = CGPoint(x: feet.x, y: feet.y + size * 0.95)
            let away = CGPoint(x: feet.x + size, y: area.maxY + size * 2)
            after(1.2) {
                if let canvas {
                    NotchMascotGangArt.balloon(in: canvas, from: local(hold),
                                               to: local(CGPoint(x: away.x, y: away.y + size * 0.95)),
                                               size: size * 0.7, duration: 6)
                }
                desktop.hop(dx: 0, dy: 200)
                after(0.3) {
                    desktop.glide(to: away, over: 5.7) { desktop.depart(over: 0.1, then: gone) }
                }
            }
        case .box:
            let side: CGFloat = feet.x < area.midX ? 1 : -1
            let spot = CGPoint(x: min(desktop.floor.upperBound, max(desktop.floor.lowerBound, feet.x + side * size * 1.1)),
                               y: area.minY)
            after(0.9) {
                if let canvas {
                    NotchMascotGangArt.box(in: canvas, at: local(spot), size: size * 1.15, closeAt: 1.6, duration: 4.2,
                                           away: side)
                }
            }
            after(1.6) { desktop.hop(dx: side * 120, dy: 520) }
            after(2.2) {
                desktop.glide(to: CGPoint(x: spot.x, y: spot.y + size * 0.1), over: 0.25) {
                    desktop.depart(over: 0.2, shrinkTo: 0.6, then: gone)
                }
            }
        case .door:
            let side: CGFloat = feet.x < area.midX ? 1 : -1
            let spot = CGPoint(x: min(desktop.floor.upperBound, max(desktop.floor.lowerBound, feet.x + side * size * 1.4)),
                               y: area.minY)
            after(0.8) {
                if let canvas { NotchMascotPlayEffects.secretDoor(in: canvas, at: local(spot), height: size * 1.5, duration: 4) }
            }
            after(1.9) {
                let walk = desktop.stroll(to: spot.x, pace: 1.2)
                after(walk + 0.2) { desktop.depart(over: 0.45, shrinkTo: 0.7, then: gone) }
            }
        }
        // Whatever happens on the way, it is gone in the end.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self, weak desktop] in
            guard let self, let desktop, self.guest(desktop) != nil else { return }
            desktop.dismiss()
            self.departed(desktop)
        }
    }

    /// The guest is gone: its plays end and the gang forgets it was there.
    private func departed(_ desktop: NotchMascotDesktop) {
        guard let guest = guest(desktop) else { return }
        guest.leaves?.cancel()
        interrupted(desktop)
        if desktop.isOut { desktop.dismiss() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { guest.stage.close() }
        guests.removeAll { $0 === guest }
        forgetDeparted()
    }

    /// Pairs with a guest no longer out are dropped; the island's two stay.
    private func forgetDeparted() {
        let present = Set(members.map(ObjectIdentifier.init))
        duos = duos.enumerated().filter { index, pair in
            index == 0 || (present.contains(ObjectIdentifier(pair.leader)) && present.contains(ObjectIdentifier(pair.friend)))
        }.map(\.element)
        if !gathering {
            ambientWork?.cancel(); ambientWork = nil
            dozing.removeAll()
        }
    }

    // MARK: A guest's menu

    private final class MenuAction: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    private func menu(for desktop: NotchMascotDesktop) -> NSMenu {
        let text = FeatureStrings.notchMascotGang(L10n.shared.language)
        let menu = NSMenu()
        func add(_ title: String, symbol: String, _ run: @escaping () -> Void) {
            let action = MenuAction(run)
            let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
            item.target = action
            item.representedObject = action
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        add(text.stayLonger, symbol: "clock.badge.checkmark") { [weak self, weak desktop] in
            guard let self, let desktop, let guest = self.guest(desktop), !guest.leaving else { return }
            let left = max(0, guest.leavesAt - CACurrentMediaTime())
            self.scheduleGoodbye(guest, after: left + NotchMascotGangVisits.longer)
            desktop.react(.celebrate)
            self.float("♥", over: desktop, color: Self.heart)
        }
        add(text.giveTreat, symbol: "birthday.cake") { [weak self, weak desktop] in
            guard let self, let desktop, let guest = self.guest(desktop) else { return }
            desktop.dropped(.food)
            if guest.personality == .glutton { desktop.pullFace(.greedy, for: 2) }
            if let other = self.nearest(to: desktop) {
                NotchMascotRapport.record(NotchMascotRapport.good * 0.3, between: desktop.playLook.style,
                                           and: other.playLook.style)
            }
        }
        menu.addItem(.separator())
        add(text.sayGoodbye, symbol: "hand.wave") { [weak self, weak desktop] in
            guard let self, let desktop, let guest = self.guest(desktop), !guest.leaving else { return }
            self.leave(guest)
        }
        return menu
    }
}
