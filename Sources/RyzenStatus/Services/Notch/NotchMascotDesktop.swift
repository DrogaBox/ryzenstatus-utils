// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// A drag that began on the companion resting in the closed island, in
/// screen points.
enum NotchMascotGrab {
    case began(CGPoint)
    case moved(CGPoint)
    case ended(CGPoint)
}

/// The companion out on the desktop, in a small window of its own that moves
/// with it. It walks along the bottom of the screen, stands, looks about and
/// dozes; its eyes find the pointer when it comes near. A click pats it, a
/// drag carries it, a fling throws it to fall and bounce, and a double click,
/// a drop on the island or its menu sends it home. A display link runs only
/// while it moves; standing, it costs what it costs in the island.
///
/// A friend can come out with it: a second companion of another look that
/// hops out after it, wanders on its own, walks over when the two are far
/// apart, waves when they meet and goes back in when the first one does.
final class NotchMascotDesktop: NSObject {
    /// The island's own companion, rather than the friend that comes out
    /// with it: only its walks on its own end by themselves.
    let leads: Bool
    /// Where the other companion out on the desktop stands, its feet on
    /// screen; nil when it is not out or not on the floor.
    var neighbor: (() -> CGPoint?)?
    /// It waves at the other companion, which waves back toward this point.
    var greetNeighbor: ((CGPoint) -> Void)?
    /// Standing with nothing to do, it asks whether the two play something
    /// together; true when they do, and it waits for its part.
    var invitePlay: (() -> Bool)?
    /// Pressed on, or sent home, in the middle of a play.
    var interrupted: (() -> Void)?
    /// It was patted.
    var patted: (() -> Void)?
    /// It came down or hit a side hard enough to be dizzy.
    var landedHard: (() -> Void)?
    /// Where it rests in the island now, its centre on screen, and its size
    /// there; nil when the island has no room for it.
    var restingPlace: (() -> (center: CGPoint, size: CGFloat, screenTop: CGFloat)?)?
    /// It is back in the island, and shows `homecoming` as it lands there.
    var cameHome: ((_ homecoming: NotchMascotMood) -> Void)?
    var openSettings: (() -> Void)?
    /// Opens the shop, which lives with the accessories in Settings.
    var openShop: (() -> Void)?
    /// Something rare came by it, for the other companion to see.
    var sawEncounter: ((NotchMascotEncounter) -> Void)?

    private(set) var isOut = false
    /// Counts its outings, so what one scheduled stays with it.
    private var outing = 0
    /// It plays with the other companion: it makes no plans of its own and
    /// its eyes leave the pointer be.
    private(set) var inPlay = false
    /// Dozing because the two nap together, rather than on its own.
    private(set) var napping = false
    /// How many times its walking pace it walks at.
    private var pace: CGFloat = 1

    private enum Mode: Equatable {
        case standing
        case held
        case flying
        case walking(direction: CGFloat, until: CFTimeInterval)
        case homing(from: CGPoint, to: CGPoint, began: CFTimeInterval, duration: TimeInterval, fromScale: CGFloat, toScale: CGFloat)
    }

    private var panel: NSPanel?
    private var stage: NotchMascotDesktopView?
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var mode = Mode.standing
    private var body = NotchMascotRoam.Body(position: .zero)
    private var look = NotchMascotLook.standard
    /// The look as chosen for it, before any dress-up play puts its own thing on.
    private var baseLook = NotchMascotLook.standard
    private var mood: NotchMascotMood = .idle
    /// The thing it put on by itself while out, and when it last dug into its wardrobe.
    private var dressUpItem: NotchMascotAccessory?
    private var dressUpWork: DispatchWorkItem?
    private var lastDressUp: CFTimeInterval = -.infinity
    private var size = NotchMascotRoam.drawnSize
    private var samples: [NotchMascotRoam.Sample] = []
    private var grabOffset = CGVector.zero
    private var press: (point: CGPoint, time: CFTimeInterval, moved: CGFloat)?
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var planWork: DispatchWorkItem?
    private var excursionWork: DispatchWorkItem?
    private var patFlip = false
    private var lastPat: CFTimeInterval = -.infinity
    /// Pats count toward the bond as often for both companions together as
    /// for one, and the two wave at each other as often.
    private static var lastPatCounted: CFTimeInterval = -.infinity
    private static var lastGreeting: CFTimeInterval = -.infinity
    /// Thrown rather than dropped: it waves once it lands.
    private var thrown = false
    /// Told to stay put from its menu: it does not wander off.
    private var staysPut = false
    /// The pointer is near enough for it to watch.
    private var watching = false
    private var runDirection: CGFloat?
    private var shakeTracker = NotchMascotRoam.ShakeTracker()
    private var isDizzy = false
    private var dizzyTimer: DispatchSourceTimer?

    /// The window it stands on, and where that window was when last seen.
    private var perch: (window: CGWindowID, frame: CGRect)?
    /// The tops of the other apps' windows, and where those windows were,
    /// as last read.
    private var ledges: [NotchMascotLedges.Ledge] = []
    private var windowFrames: [CGWindowID: CGRect] = [:]
    private var ledgesRead: CFTimeInterval = -.infinity
    /// Watches the window it stands on, or the windows that pass by.
    private var watchTimer: DispatchSourceTimer?
    private var watchInterval = 0
    /// The mouse button is held down in another app, as when a window is dragged.
    private var buttonHeld = false
    private var appObserver: NSObjectProtocol?
    private var lastAppReaction: CFTimeInterval = -.infinity
    private var lastHitch: CFTimeInterval = -.infinity
    /// The window under it is being dragged, and when it last moved.
    private var riding = false
    private var rideMoved: CFTimeInterval = -.infinity
    /// On its way up onto a window, and the leap waiting to go.
    private var leaping = false
    private var climbWork: DispatchWorkItem?
    /// Walking to the end of the window it stands on to jump off.
    private var leavesLedge = false
    /// Hidden behind the window it stands on, this far below its top edge.
    private var peekDepth: CGFloat = 0
    private var peekTimer: DispatchSourceTimer?
    private var peekWork: DispatchWorkItem?
    private var clipped = false
    private var swayTimer: DispatchSourceTimer?
    /// Doing its thing with what it wears, the steps of it waiting, and
    /// the clear window over the screen they fly across.
    private var usingItem = false
    private var itemWork: [DispatchWorkItem] = []
    private var itemStage: NotchMascotPlayStage?
    private var lastItemUse: CFTimeInterval = -.infinity
    /// What it wears is gone a while: eaten, drunk or in its face.
    private var itemHidden = false
    private var hideWork: DispatchWorkItem?
    /// How many times its size it is: more than one while the mushroom lasts.
    private var growth: CGFloat = 1
    private var growWork: DispatchWorkItem?
    private var dozeWork: DispatchWorkItem?
    /// Something rare passing by, what it does about it, and the clear
    /// window over the screen it passes on.
    private var inEncounter = false
    private var encounterWork: [DispatchWorkItem] = []
    private var encounterStage: NotchMascotPlayStage?
    /// How long what passes by stays on screen, when longer than it minds it.
    private var visitorsLeave: TimeInterval = 0
    // Occasions of its own: cravings, games, the Mac's and the calendar's.
    private var occasion: Occasion?
    private var occasionWork: [DispatchWorkItem] = []
    private var occasionStage: NotchMascotPlayStage?
    private var lastCraving: CFTimeInterval = -.infinity
    private var lastFishing: CFTimeInterval = -.infinity
    private var lastSolo: CFTimeInterval = -.infinity
    /// The last time it was played with, for hide and seek when bored.
    private var lastTouched = CACurrentMediaTime()
    private var tickles = NotchMascotTickleTracker()
    private var lastBounce: CFTimeInterval = -.infinity
    private var bounces = 0
    /// In the air since the user let go of it, until it comes to rest.
    private var dropped = false
    /// The window edge a leap is aimed at, to catch hold of if it comes up short.
    private var leapTarget: (window: CGWindowID, y: CGFloat)?
    private var laserTimer: DispatchSourceTimer?
    private var laserDot: CALayer?
    private var rosinUntil: CFTimeInterval = -.infinity
    private var lastPrintX: CGFloat?
    /// Its last usable area, for the moment a display change leaves no screen.
    private var lastArea = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private var upsideDown = false
    /// One at a time, for both companions, and rare across their outings.
    private static var encounterUnderWay = false
    private static var lastEncounter = CACurrentMediaTime()
    private static var recentEncounters: [NotchMascotEncounter] = []

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// A game picked from its menu: it moves for it even with Reduce Motion.
    private var askedFor = false
    /// With Reduce Motion it does not hop or stroll on its own.
    private var holdsStill: Bool { reduceMotion && !askedFor }
    private var host: NotchMascotHostView? { stage?.host }

    init(leads: Bool = true) {
        self.leads = leads
        super.init()
    }

    deinit {
        removeMonitors()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        peekTimer?.cancel()
    }

    // MARK: Coming out

    /// Comes out of the island where it rests, `center` on screen at
    /// `fromSize`. Grabbed, it hangs from the pointer until let go; on its
    /// own, it hops out and falls to the bottom of the screen, and goes back
    /// in after a while, or once the companion it came out with does. It
    /// hops toward `hop`, right when positive, or toward the wider side.
    func comeOut(from center: CGPoint, fromSize: CGFloat, look: NotchMascotLook, mood: NotchMascotMood,
                 grabbedAt pointer: CGPoint?, hop: CGFloat? = nil) {
        guard !isOut else { return }
        isOut = true
        outing += 1
        configure(look: look, mood: mood)
        guard let panel, let host else { return }
        staysPut = false
        thrown = false
        samples.removeAll()
        // Its first turn with what it wears comes a little after it is out.
        lastItemUse = CACurrentMediaTime() - NotchMascotItemUse.desktopInterval + 20
        // Its own cravings, outings and dances wait a little too.
        let now = CACurrentMediaTime()
        lastCraving = now - NotchMascotCravings.interval + 90
        lastFishing = now - NotchMascotFishing.interval + 150
        lastSolo = now - NotchMascotSoloDance.interval + 45
        lastTouched = now
        let start = CGPoint(x: center.x, y: center.y - size / 2)
        lastArea = area(for: start)
        if let pointer {
            // It hangs by the head from the pointer that pulled it out.
            grabOffset = CGVector(dx: 0, dy: -size * 0.8)
            body = NotchMascotRoam.Body(position: CGPoint(x: pointer.x, y: pointer.y + grabOffset.dy), airborne: true)
            press = (pointer, CACurrentMediaTime(), NotchMascotRoam.tapSlop)
            mode = .held
        } else if reduceMotion {
            // With Reduce Motion it does not hop out: it is simply there, on the floor.
            let area = self.area(for: start)
            let half = size * figureAspect / 2
            body = NotchMascotRoam.Body(position: CGPoint(x: min(area.maxX - half, max(area.minX + half, start.x)),
                                                          y: area.minY), airborne: false)
            mode = .standing
            planNext(after: 2)
            if leads { scheduleExcursionEnd() }
        } else {
            let area = self.area(for: start)
            let toward: CGFloat = hop.map { $0 > 0 ? 1 : -1 } ?? (start.x < area.midX ? 1 : -1)
            body = NotchMascotRoam.Body(position: start, velocity: CGVector(dx: toward * CGFloat.random(in: 140...260), dy: 420),
                                        airborne: true)
            mode = .flying
            thrown = true
            if leads { scheduleExcursionEnd() }
        }
        place()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        host.scale(from: fromSize / size, to: 1, duration: reduceMotion ? 0 : 0.35)
        if pointer != nil { host.mascot.react(.surprised, lift: 0) }
        installMonitors()
        resumeTicking()
    }

    /// A drag begun on it in the closed island carries on here.
    func continueGrab(_ grab: NotchMascotGrab) {
        switch grab {
        case .began: break
        case .moved(let point): pressMoved(to: point)
        case .ended(let point): pressEnded(at: point)
        }
    }

    /// Keeps a new look or mood while it is out. A new pick from its person
    /// ends any dress-up play, so what was chosen shows at once.
    func configure(look newLook: NotchMascotLook, mood: NotchMascotMood) {
        if newLook.accessory != baseLook.accessory {
            endDressUp()
            hideWork?.cancel(); hideWork = nil
            itemHidden = false
        }
        baseLook = newLook
        self.mood = mood
        var look = newLook
        if let dressUpItem { look.accessory = dressUpItem }
        if itemHidden { look.accessory = .none }
        let size = (NotchMascotRoam.size(for: look) * growth).rounded()
        // A window made just now has no size yet, whatever size it was made for.
        let resized = size != self.size || self.stage == nil
        let panel = self.panel ?? makePanel()
        let stage = self.stage ?? makeStage(in: panel)
        self.look = look
        self.size = size
        if resized {
            let window = NotchMascotRoam.windowSize(for: size)
            panel.setContentSize(window)
            stage.frame = CGRect(origin: .zero, size: window)
        }
        stage.host.configure(look: look, size: size, mood: mood, idles: true, reduceMotion: reduceMotion,
                             animated: isOut && !resized)
        // Its feet on the window's bottom inset, centred across; the view is flipped.
        let window = NotchMascotRoam.windowSize(for: size)
        stage.host.place(at: CGPoint(x: window.width / 2,
                                     y: window.height - NotchMascotRoam.footInset(for: size) - size / 2),
                         visible: nil)
        panel.sharingType = NotchSupport.showsInCaptures() ? .readOnly : .none
        if isOut { place() }
    }

    /// Plays a reaction where it stands.
    func react(_ reaction: NotchMascotReaction) {
        guard isOut, let host, !isHoming else { return }
        host.react(NotchMascotReactionEvent(id: UUID(), reaction: reaction, start: CACurrentMediaTime()), lift: size * 0.3)
    }

    /// Its feet on screen while it stands or walks on the floor.
    var feet: CGPoint? {
        guard isOut else { return nil }
        switch mode {
        case .standing, .walking: return body.airborne ? nil : body.position
        default: return nil
        }
    }

    /// Waves back at the companion that waved at it from `point`, stopping
    /// a walk to do so; held, flying or on the way home, it lets it pass.
    func greet(toward point: CGPoint) {
        guard isOut, let host, feet != nil else { return }
        if isWalking {
            setRun(nil)
            mode = .standing
        }
        host.attend(toScreenPoint: point)
        host.mascot.wake(animated: true)
        react(.wave)
        host.mascot.lookAhead(after: NotchMascotReaction.wave.length)
        planNext(after: NotchMascotReaction.wave.length + 2)
    }

    /// Waves at the other companion when it stands close and they have not
    /// waved in a while. True when they did.
    private func greetIfNear() -> Bool {
        guard let other = neighbor?(), let host, !host.mascot.isDozing else { return false }
        let now = CACurrentMediaTime()
        guard NotchMascotRoam.greets(distance: abs(other.x - body.position.x), since: now - Self.lastGreeting)
        else { return false }
        Self.lastGreeting = now
        greet(toward: CGPoint(x: other.x, y: other.y + size / 2))
        greetNeighbor?(figureCenter)
        return true
    }

    // MARK: Dress-up play

    /// Standing about with nothing to do, now and then it digs into
    /// everything it owns and puts on whatever it feels like for a while,
    /// then goes back to what its person picked. True when it dressed up.
    private func maybePlayDressUp() -> Bool {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.notchMascotDressUp),
              look.style.takesAccessory,
              dressUpItem == nil, !isDozing,
              NotchMascotDressUp.shouldStart(sinceLastDig: CACurrentMediaTime() - lastDressUp,
                                             random: Double.random(in: 0..<1)),
              let item = NotchMascotDressUp.pick(current: look.accessory,
                                                 level: NotchMascotSupport.shownLevel(),
                                                 owns: NotchMascotShop.owns,
                                                 random: Double.random(in: 0..<1))
        else { return false }
        lastDressUp = CACurrentMediaTime()
        dressUpItem = item
        configure(look: baseLook, mood: mood)
        react(.perk)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.dressUpItem != nil else { return }
            self.endDressUp()
        }
        dressUpWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchMascotDressUp.duration(random: Double.random(in: 0..<1)),
                                      execute: work)
        planNext(after: NotchMascotReaction.perk.length + 2)
        return true
    }

    /// Back to what was chosen for it. Redraws only while it is still out.
    private func endDressUp() {
        dressUpWork?.cancel(); dressUpWork = nil
        guard dressUpItem != nil else { return }
        dressUpItem = nil
        if isOut { configure(look: baseLook, mood: mood) }
    }

    // MARK: Using what it wears
    /// Standing about, now and then it does its own thing with what it
    /// wears. True when it started.
    private func maybeUseItem() -> Bool {
        guard look.style.takesAccessory, !isDozing,
              NotchMascotItemUse.shouldStart(since: CACurrentMediaTime() - lastItemUse,
                                             interval: NotchMascotItemUse.desktopInterval,
                                             chance: NotchMascotItemUse.desktopChance,
                                             random: Double.random(in: 0..<1)),
              let use = NotchMascotItemUse.of(look.accessory)
        else { return false }
        useItem(use)
        return true
    }
    /// Plays `use` step by step, toward the wider side of where it stands,
    /// and goes on with its life once it is done.
    func useItem(_ planned: NotchMascotItemUse) {
        guard isOut, !isHoming, !inPlay else { return }
        let use = planned.settled()
        cancelItemUse()
        planWork?.cancel(); planWork = nil
        if isWalking {
            setRun(nil)
            mode = .standing
        }
        lastItemUse = CACurrentMediaTime()
        usingItem = true
        let side: CGFloat = body.position.x < area(for: body.position).midX ? 1 : -1
        face(toward: body.position.x + side * 100)
        for step in use.steps {
            itemStep(after: step.at) { [weak self] in self?.perform(step.action, toward: side) }
        }
        itemStep(after: use.length + 0.3) { [weak self] in
            guard let self else { return }
            self.usingItem = false
            self.itemWork.removeAll()
            self.host?.mascot.lookAhead(after: 0.3)
            if self.mode == .standing { self.planNext(after: 2) }
            let stage = self.itemStage
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, !self.usingItem, self.itemStage === stage else { return }
                stage?.close()
            }
        }
    }
    private func itemStep(after delay: TimeInterval, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        itemWork.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }
    /// Stops what it was doing with it. What lasts on its own, the thing
    /// eaten or the size grown, lasts on.
    private func cancelItemUse() {
        itemWork.forEach { $0.cancel() }
        itemWork.removeAll()
        if dozeWork != nil {
            dozeWork?.cancel(); dozeWork = nil
            host?.mascot.setMood(mood, animated: !reduceMotion)
        }
        guard usingItem else { return }
        usingItem = false
        itemStage?.close()
    }
    /// Back home: what it ate is back in its hand and it is its own size.
    private func resetItemState() {
        hideWork?.cancel(); hideWork = nil
        growWork?.cancel(); growWork = nil
        itemHidden = false
        growth = 1
        itemStage?.close()
    }
    private func itemCanvas() -> CALayer? {
        let stage = itemStage ?? NotchMascotPlayStage()
        itemStage = stage
        guard let screen = playScreen else { return nil }
        return stage.layer(over: screen)
    }
    private func onItemCanvas(_ point: CGPoint) -> CGPoint { itemStage?.point(point) ?? point }
    private static func color(_ tint: NotchMascotItemAction.Tint) -> CGColor {
        switch tint {
        case .gold: return CGColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: 1)
        case .pink: return CGColor(srgbRed: 1, green: 0.45, blue: 0.65, alpha: 1)
        case .blue: return CGColor(srgbRed: 0.5, green: 0.78, blue: 1, alpha: 1)
        case .white: return CGColor(srgbRed: 0.95, green: 0.96, blue: 1, alpha: 1)
        case .green: return CGColor(srgbRed: 0.55, green: 1, blue: 0.55, alpha: 1)
        case .purple: return CGColor(srgbRed: 0.75, green: 0.55, blue: 1, alpha: 1)
        }
    }
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func perform(_ action: NotchMascotItemAction, toward side: CGFloat) {
        guard isOut, !isHoming else { return }
        let energy = NotchMascotPlay.energy(for: look)
        switch action {
        case .react(let reaction): react(reaction)
        case .move(let move): perform(move, toward: side)
        case .burst(let burst):
            guard let canvas = itemCanvas() else { return }
            NotchMascotPlayEffects.burst(burst, in: canvas, at: onItemCanvas(head), size: size * 0.9, energy: energy)
        case .marker(let text):
            guard let canvas = itemCanvas() else { return }
            NotchMascotPlayEffects.arcadeMarker(text, in: canvas,
                                                at: onItemCanvas(CGPoint(x: head.x, y: head.y + size * 0.35)),
                                                cell: max(1.6, size * 0.05))
        case .symbol(let symbol, let tint, let count):
            guard let canvas = itemCanvas() else { return }
            NotchMascotPlayEffects.float(symbol, in: canvas, at: onItemCanvas(head), size: max(9, size * 0.2),
                                         color: Self.color(tint), count: count)
        case .fling(let thing, let back):
            guard !reduceMotion, let canvas = itemCanvas() else { return }
            let hand = self.hand(toward: side)
            let floor = self.floor
            let far = CGPoint(x: min(floor.upperBound, max(floor.lowerBound, hand.x + side * size * 3.4)),
                              y: hand.y + size * 0.3)
            let length = NotchMascotItemUse.flingLength
            NotchMascotPlayEffects.fly(thing, in: canvas, from: onItemCanvas(hand), to: onItemCanvas(far),
                                       duration: length, side: max(14, size * 0.34), energy: energy, while: outingLasts)
            guard back else { return }
            itemStep(after: length + 0.1) { [weak self] in
                guard let self, let canvas = self.itemCanvas() else { return }
                NotchMascotPlayEffects.fly(thing, in: canvas, from: self.onItemCanvas(far),
                                           to: self.onItemCanvas(self.hand(toward: side)), duration: length,
                                           side: max(14, self.size * 0.34), energy: energy, while: self.outingLasts)
            }
        case .juggle(let thing):
            guard !reduceMotion, let canvas = itemCanvas() else { return }
            NotchMascotPlayEffects.fly(thing, in: canvas, from: onItemCanvas(hand(toward: side)),
                                       to: onItemCanvas(hand(toward: -side)), duration: NotchMascotItemUse.juggleLength,
                                       side: max(12, size * 0.3), energy: energy, while: outingLasts)
        case .slash:
            guard let canvas = itemCanvas() else { return }
            let blade = NotchMascotPlayEffects.blade(in: canvas, hand: onItemCanvas(hand(toward: side)), direction: side,
                                                     length: size * 0.9, energy: energy)
            itemStep(after: 0.15) { NotchMascotPlayEffects.swing(blade, direction: side) }
            itemStep(after: 0.55) { NotchMascotPlayEffects.sheathe(blade) }
        case .lightning:
            guard let canvas = itemCanvas() else { return }
            NotchMascotPlayEffects.lightning(in: canvas, around: onItemCanvas(head), radius: size * 0.8, energy: energy)
        case .sparks:
            guard let canvas = itemCanvas() else { return }
            NotchMascotPlayEffects.sparks(in: canvas, at: onItemCanvas(hand(toward: side)), reach: size * 0.5, energy: energy)
        case .hide(let length):
            hideWork?.cancel()
            itemHidden = true
            configure(look: baseLook, mood: mood)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hideWork = nil
                self.itemHidden = false
                if self.isOut, !self.isHoming { self.configure(look: self.baseLook, mood: self.mood) }
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + length, execute: work)
        case .grow(let length):
            growWork?.cancel()
            flicker(to: NotchMascotItemUse.growth)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.growWork = nil
                guard self.isOut, !self.isHoming, self.growth != 1 else { self.growth = 1; return }
                self.react(.surprised)
                self.flicker(to: 1)
            }
            growWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + length, execute: work)
        case .gold(let amount):
            // Already paid as the use began (`NotchMascotItemUse.settled`).
            perform(.burst(.coins), toward: side)
            perform(.marker("+\(amount)"), toward: side)
        case .doze(let length):
            guard let host else { return }
            host.mascot.setMood(.sleepy, animated: !reduceMotion)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.dozeWork = nil
                self.host?.mascot.setMood(self.mood, animated: !self.reduceMotion)
            }
            dozeWork?.cancel()
            dozeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + length, execute: work)
        }
    }
    /// Big and small in turn a few times, as in the old games, then `target`.
    private func flicker(to target: CGFloat) {
        let from = growth
        let sizes: [CGFloat] = reduceMotion ? [target] : [target, from, target, from, target]
        for (index, value) in sizes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.09) { [weak self] in
                guard let self, self.isOut, !self.isHoming else { return }
                self.growth = value
                self.configure(look: self.baseLook, mood: self.mood)
            }
        }
    }
    /// A body move of its own, toward `side`.
    private func perform(_ move: NotchMascotBodyMove, toward side: CGFloat) {
        guard !reduceMotion else { return }
        let x = body.position.x
        switch move {
        case .hop, .jumpTogether, .hopRound: hop(dx: 0, dy: 480)
        case .highJump: hop(dx: 0, dy: 820)
        case .float: hop(dx: 0, dy: 980)
        case .spin, .spinTogether:
            sway(amplitude: 0.55, speed: 26, duration: 0.7)
            itemStep(after: 0.7) { [weak self] in self?.hop(dx: 0, dy: 300) }
        case .charge, .chase, .bump:
            stroll(to: x + side * 90, pace: 3.2)
            itemStep(after: 0.7) { [weak self] in self?.stroll(to: x, pace: 2) }
        case .backflip, .swap, .leapOver: hop(dx: -side * 150, dy: 640)
        case .stomp:
            for step in 0..<3 { itemStep(after: Double(step) * 0.32) { [weak self] in self?.hop(dx: 0, dy: 230) } }
        case .bow, .bowTogether: tilt(-side * 0.35, for: 0.8)
        case .sneak:
            stroll(to: x - side * 46, pace: 0.9)
            itemStep(after: 1.0) { [weak self] in self?.stroll(to: x, pace: 1.4) }
        case .slip:
            stroll(to: x + side * 36, pace: 2.6)
            itemStep(after: 0.35) { [weak self] in
                self?.hop(dx: side * 140, dy: 200)
                self?.react(.confused)
            }
        case .shiver: sway(amplitude: 0.1, speed: 45, duration: 0.9)
        case .strut:
            stroll(to: x + side * 60, pace: 1.6)
            itemStep(after: 0.85) { [weak self] in self?.stroll(to: x, pace: 1.6) }
        }
    }
    // MARK: Rare encounters
    /// Out a good while across its outings, now and then something rare
    /// passes by. True when it did.
    private func maybeEncounter() -> Bool {
        guard !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled, !isDozing, !Self.encounterUnderWay,
              NotchMascotEncounters.shouldHappen(since: CACurrentMediaTime() - Self.lastEncounter,
                                                 random: Double.random(in: 0..<1)),
              let encounter = NotchMascotEncounters.pick(hour: Calendar.current.component(.hour, from: Date()),
                                                         wearsItem: wearsItem, recent: Self.recentEncounters,
                                                         random: Double.random(in: 0..<1))
        else { return false }
        return meet(encounter)
    }
    /// Whether it wears something a bird could take.
    var wearsItem: Bool { look.style.takesAccessory && look.accessory != .none }
    /// `encounter` passes by it now. True when it did.
    @discardableResult
    func meet(_ encounter: NotchMascotEncounter) -> Bool {
        guard isOut, !isHoming, press == nil, !Self.encounterUnderWay, !reduceMotion,
              encounter != .magpie || wearsItem, !encounter.grounded || perch == nil else { return false }
        if inPlay { interrupted?() }
        cancelItemUse()
        cancelWindowPlans()
        planWork?.cancel(); planWork = nil
        if isWalking {
            setRun(nil)
            mode = .standing
        }
        guard let canvas = encounterCanvas() else { return false }
        inEncounter = true
        Self.encounterUnderWay = true
        Self.lastEncounter = CACurrentMediaTime()
        Self.recentEncounters = Array((Self.recentEncounters + [encounter]).suffix(NotchMascotEncounters.memory))
        sawEncounter?(encounter)
        visitorsLeave = 0
        let busy: TimeInterval
        switch encounter {
        case .dinosaur: busy = dinosaur(on: canvas)
        case .shootingStar: busy = shootingStar(on: canvas)
        case .ufo: busy = ufo(on: canvas)
        case .ghost: busy = ghost(on: canvas)
        case .magpie: busy = magpie(on: canvas)
        case .fireflies: busy = fireflies(on: canvas)
        case .ducklings: busy = ducklings(on: canvas)
        case .mimic: busy = mimic(on: canvas)
        case .merchant: busy = merchant(on: canvas)
        case .bubble: busy = bubble(on: canvas)
        case .cardboardBox: busy = cardboardBox(on: canvas)
        case .glitch: busy = glitch(on: canvas)
        case .dockBoat: busy = dockBoat(on: canvas)
        case .trashCan: busy = trashCan(on: canvas)
        case .coffee: busy = coffee(on: canvas)
        case .satellite: busy = satellite(on: canvas)
        case .meteorShower: busy = meteorShower(on: canvas)
        case .lostBalloon: busy = lostBalloon(on: canvas)
        case .rainbow: busy = rainbow(on: canvas)
        case .secretAdmirer: busy = secretAdmirer(on: canvas)
        }
        encounterStep(after: busy) { [weak self] in
            guard let self else { return }
            self.endEncounter()
            if self.mode == .standing { self.planNext(after: 2) }
        }
        // What passes by goes its way even if it is picked up meanwhile.
        let stage = encounterStage
        DispatchQueue.main.asyncAfter(deadline: .now() + max(busy, visitorsLeave) + 1.5) { [weak self] in
            guard let self, self.encounterStage === stage, !self.inEncounter else { return }
            stage?.close()
        }
        return true
    }
    /// The other companion saw something rare come by: it reacts from where it stands.
    func witness(_ encounter: NotchMascotEncounter) {
        guard isOut, !isHoming, !inEncounter, !isDozing else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.react(encounter.witnessReaction) }
    }
    /// It stops minding what passes by; what passes by goes on its way.
    private func endEncounter() {
        encounterWork.forEach { $0.cancel() }
        encounterWork.removeAll()
        guard inEncounter else { return }
        inEncounter = false
        Self.encounterUnderWay = false
    }
    private func encounterStep(after delay: TimeInterval, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        encounterWork.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }
    /// Runs `block` after `delay` whatever it does meanwhile, what passes by,
    /// as long as this outing lasts.
    private func later(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        let lasts = outingLasts
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) {
            if lasts() { block() }
        }
    }
    /// Whether the outing under way now is still on, asked later.
    private var outingLasts: () -> Bool {
        let outing = self.outing
        return { [weak self] in self?.isOut == true && self?.outing == outing }
    }
    /// A sound of this outing: one still waiting once it is in is not heard.
    private func sound(_ effect: NotchMascotSoundEffect, pan: Float = 0, after delay: TimeInterval = 0) {
        guard delay > 0 else { NotchMascotSound.play(effect, pan: pan); return }
        later(delay) { NotchMascotSound.play(effect, pan: pan) }
    }
    private func encounterCanvas() -> CALayer? {
        let stage = encounterStage ?? NotchMascotPlayStage()
        encounterStage = stage
        guard let screen = playScreen else { return nil }
        return stage.layer(over: screen)
    }
    private func onStage(_ point: CGPoint) -> CGPoint { encounterStage?.point(point) ?? point }
    private func pan(_ x: CGFloat) -> Float {
        let area = self.area(for: body.position)
        return Float(max(-1, min(1, (x - area.midX) / max(1, area.width / 2))))
    }
    /// Great footsteps, then a tail sweeping in at the nearer edge: it
    /// jumps away and trembles.
    private func dinosaur(on canvas: CALayer) -> TimeInterval {
        let area = self.area(for: body.position)
        let fromRight = body.position.x > area.midX
        let inward: CGFloat = fromRight ? -1 : 1
        let edgeX = fromRight ? area.maxX : area.minX
        for (index, at) in [0.0, 0.8, 1.6].enumerated() {
            later(at) { [weak self] in
                guard let self else { return }
                sound(.thud, pan: fromRight ? 0.85 : -0.85)
                NotchMascotEncounterArt.dust(in: canvas, at: self.onStage(CGPoint(x: edgeX + inward * CGFloat(20 + index * 30),
                                                                                  y: area.minY + 8)),
                                             radius: 26 + CGFloat(index) * 6)
            }
        }
        later(2.2) { [weak self] in
            guard let self else { return }
            NotchMascotEncounterArt.tail(in: canvas, edgeX: self.onStage(CGPoint(x: edgeX, y: 0)).x,
                                         floor: self.onStage(CGPoint(x: 0, y: area.minY)).y, inward: inward,
                                         length: min(440, area.width * 0.3), duration: 5.5)
            sound(.whoosh, pan: fromRight ? 0.7 : -0.7)
            sound(.whoosh, pan: fromRight ? 0.7 : -0.7, after: 1.6)
        }
        encounterStep(after: 0.1) { [weak self] in self?.react(.surprised) }
        encounterStep(after: 0.9) { [weak self] in self?.face(toward: edgeX) }
        encounterStep(after: 1.7) { [weak self] in self?.react(.sweat) }
        encounterStep(after: 2.6) { [weak self] in
            self?.react(.panic)
            self?.hop(dx: inward * 260, dy: 520)
        }
        encounterStep(after: 3.6) { [weak self] in self?.sway(amplitude: 0.1, speed: 45, duration: 1.4) }
        encounterStep(after: 5.6) { [weak self] in self?.react(.peek) }
        encounterStep(after: 8.0) { [weak self] in self?.react(.lookAround) }
        return 9.5
    }
    /// A star streaks across the top of the screen: it watches, and wishes.
    private func shootingStar(on canvas: CALayer) -> TimeInterval {
        let area = self.area(for: body.position)
        let way: CGFloat = Bool.random() ? 1 : -1
        let startX = way > 0 ? area.minX + area.width * CGFloat.random(in: 0.1...0.4)
                             : area.maxX - area.width * CGFloat.random(in: 0.1...0.4)
        let start = CGPoint(x: startX, y: area.maxY - 30)
        let end = CGPoint(x: startX + way * area.width * 0.38, y: area.maxY - area.height * 0.3)
        later(0.3) { [weak self] in
            guard let self else { return }
            NotchMascotEncounterArt.shootingStar(in: canvas, from: self.onStage(start), to: self.onStage(end), duration: 1.2)
            sound(.magic, pan: self.pan(end.x), after: 0.9)
        }
        encounterStep(after: 0.2) { [weak self] in
            self?.react(.perk)
            self?.face(toward: start.x)
        }
        encounterStep(after: 1.1) { [weak self] in self?.face(toward: end.x) }
        encounterStep(after: 1.7) { [weak self] in self?.react(.love) }
        encounterStep(after: 2.1) { [weak self] in
            guard let self else { return }
            NotchMascotPlayEffects.float("✦", in: canvas, at: self.onStage(self.head), size: max(9, self.size * 0.22),
                                         color: CGColor(srgbRed: 1, green: 0.88, blue: 0.4, alpha: 1), count: 3)
        }
        return 4.2
    }
    /// A saucer comes over, lifts it in its beam and flies off.
    private func ufo(on canvas: CALayer) -> TimeInterval {
        let area = self.area(for: body.position)
        let side: CGFloat = Bool.random() ? 1 : -1
        let feet = body.position
        let ship = max(70, size * 1.6)
        let hover = CGPoint(x: feet.x, y: min(area.maxY - ship * 0.4, feet.y + size * 4.2))
        let entry = CGPoint(x: side > 0 ? area.maxX + ship : area.minX - ship, y: area.maxY - ship * 0.3)
        let exit = CGPoint(x: hover.x - side * area.width * 0.2, y: area.maxY + ship * 1.5)
        let duration: TimeInterval = 8.5
        let stops = [entry, hover, CGPoint(x: hover.x + 6, y: hover.y + 8), hover, exit].map(onStage)
        NotchMascotEncounterArt.saucer(in: canvas, size: ship, stops: stops, times: [0, 0.25, 0.5, 0.72, 1],
                                       duration: duration)
        sound(.warble, pan: pan(entry.x), after: 0.2)
        NotchMascotEncounterArt.beam(in: canvas, top: onStage(CGPoint(x: hover.x, y: hover.y - ship * 0.12)),
                                     floor: onStage(CGPoint(x: 0, y: feet.y)).y, width: size * 2.4, delay: 2.4,
                                     length: 3.4)
        sound(.zap, pan: pan(hover.x), after: 2.4)
        sound(.warble, pan: pan(hover.x), after: 6.2)
        encounterStep(after: 0.5) { [weak self] in
            self?.react(.surprised)
            self?.face(toward: entry.x)
        }
        encounterStep(after: 2.0) { [weak self] in self?.face(toward: hover.x) }
        for (index, at) in [2.6, 3.3, 4.0, 4.7].enumerated() {
            encounterStep(after: at) { [weak self] in
                self?.hop(dx: 0, dy: index == 0 ? 900 : 560)
                if index == 0 { self?.react(.surprised) }
            }
        }
        encounterStep(after: 6.4) { [weak self] in self?.react(.confused) }
        encounterStep(after: 7.6) { [weak self] in
            self?.face(toward: exit.x)
            self?.react(.wave)
        }
        return 9
    }
    /// At three in the morning, a little ghost floats right through it.
    private func ghost(on canvas: CALayer) -> TimeInterval {
        let side: CGFloat = Bool.random() ? 1 : -1
        let feet = body.position
        let reach = size * 5
        let stops = [CGPoint(x: feet.x + side * reach, y: feet.y + size * 1.0),
                     CGPoint(x: feet.x + side * reach * 0.5, y: feet.y + size * 0.6),
                     CGPoint(x: feet.x, y: feet.y + size * 0.55),
                     CGPoint(x: feet.x - side * reach * 0.5, y: feet.y + size * 0.9),
                     CGPoint(x: feet.x - side * reach, y: feet.y + size * 1.5)].map(onStage)
        NotchMascotEncounterArt.ghost(in: canvas, size: size * 1.1, stops: stops, duration: 6.5)
        sound(.hoot, pan: pan(feet.x + side * reach), after: 0.8)
        sound(.hoot, pan: pan(feet.x), after: 3.3)
        encounterStep(after: 0.6) { [weak self] in
            self?.face(toward: feet.x + side * reach)
            self?.react(.surprised)
        }
        encounterStep(after: 2.6) { [weak self] in
            self?.react(.panic)
            self?.sway(amplitude: 0.1, speed: 45, duration: 1.2)
        }
        encounterStep(after: 3.3) { [weak self] in self?.hop(dx: 0, dy: 520) }
        encounterStep(after: 4.4) { [weak self] in self?.face(toward: feet.x - side * reach) }
        encounterStep(after: 5.2) { [weak self] in self?.react(.sweat) }
        encounterStep(after: 6.6) { [weak self] in self?.react(.lookAround) }
        return 8
    }
    /// A magpie swoops on what it wears, perches a while on a window's top
    /// or under the menu bar, and brings it back.
    private func magpie(on canvas: CALayer) -> TimeInterval {
        let area = self.area(for: body.position)
        let side: CGFloat = Bool.random() ? 1 : -1
        let feet = body.position
        let bird = max(34, size * 0.8)
        let entry = CGPoint(x: side > 0 ? area.maxX + bird : area.minX - bird, y: area.maxY - bird)
        let head = CGPoint(x: feet.x, y: feet.y + size * 1.1)
        let standsOn = perch?.window
        let ledge = currentLedges().filter { $0.window != standsOn && abs($0.y - feet.y) > size * 2 }
            .min { abs(($0.minX + $0.maxX) / 2 - feet.x) < abs(($1.minX + $1.maxX) / 2 - feet.x) }
        let perchPoint: CGPoint
        if let ledge {
            let x = min(ledge.maxX - bird, max(ledge.minX + bird, feet.x - side * size * 3))
            perchPoint = CGPoint(x: x, y: ledge.y + bird * 0.3)
        } else {
            let x = min(area.maxX - bird, max(area.minX + bird, feet.x - side * size * 4))
            perchPoint = CGPoint(x: x, y: area.maxY - bird * 0.6)
        }
        let exit = CGPoint(x: side > 0 ? area.minX - bird * 2 : area.maxX + bird * 2, y: area.maxY - bird * 0.5)
        let duration: TimeInterval = 12.5
        let times: [Double] = [0, 0.14, 0.18, 0.32, 0.62, 0.76, 0.8, 1]
        let stops = [entry, head, head, perchPoint, perchPoint, head, head, exit].map(onStage)
        NotchMascotEncounterArt.magpie(in: canvas, size: bird, stops: stops, times: times.map { NSNumber(value: $0) },
                                       duration: duration, carryFrom: 0.18, carryUntil: 0.78)
        for at in [0.1, 0.4, 0.5, 0.75] {
            sound(.chirp, pan: pan(at < 0.3 ? entry.x : perchPoint.x), after: duration * at)
        }
        let taken = duration * 0.18, returned = duration * 0.78
        encounterStep(after: 0.4) { [weak self] in
            self?.react(.perk)
            self?.face(toward: entry.x)
        }
        encounterStep(after: taken) { [weak self] in
            self?.perform(.hide(returned - taken), toward: side)
            self?.react(.surprised)
        }
        encounterStep(after: taken + 0.8) { [weak self] in
            self?.react(.panic)
            self?.face(toward: perchPoint.x)
        }
        encounterStep(after: duration * 0.34) { [weak self] in
            guard let self, self.perch == nil else { return }
            self.stroll(to: perchPoint.x + side * self.size, pace: 2.4)
        }
        encounterStep(after: duration * 0.47) { [weak self] in self?.hop(dx: 0, dy: 640) }
        encounterStep(after: duration * 0.55) { [weak self] in
            self?.hop(dx: 0, dy: 700)
            self?.react(.confused)
        }
        encounterStep(after: duration * 0.7) { [weak self] in self?.face(toward: head.x) }
        encounterStep(after: returned) { [weak self] in
            guard let self else { return }
            self.react(.celebrate)
            NotchMascotPlayEffects.burst(.sparkles, in: canvas, at: self.onStage(self.head), size: self.size * 0.9,
                                         energy: NotchMascotPlay.energy(for: self.look))
        }
        return duration + 0.3
    }
    /// After dark, lights drift around it and it tries to catch them.
    private func fireflies(on canvas: CALayer) -> TimeInterval {
        let side: CGFloat = Bool.random() ? 1 : -1
        let center = CGPoint(x: body.position.x, y: body.position.y + size * 1.2)
        NotchMascotEncounterArt.fireflies(in: canvas, around: onStage(center), radius: size * 3, count: 7, duration: 9.5)
        sound(.chime, pan: pan(center.x), after: 0.4)
        encounterStep(after: 0.5) { [weak self] in self?.react(.perk) }
        encounterStep(after: 1.6) { [weak self] in self?.face(toward: center.x + side * 100) }
        encounterStep(after: 2.5) { [weak self] in self?.hop(dx: side * 120, dy: 520) }
        encounterStep(after: 3.6) { [weak self] in self?.face(toward: center.x - side * 100) }
        encounterStep(after: 4.5) { [weak self] in self?.hop(dx: -side * 120, dy: 560) }
        encounterStep(after: 6.0) { [weak self] in self?.react(.love) }
        encounterStep(after: 7.4) { [weak self] in self?.hop(dx: 0, dy: 420) }
        encounterStep(after: 8.6) { [weak self] in self?.react(.relax) }
        return 10
    }
    /// A mother duck and her ducklings walk across the floor; it falls in
    /// at the end of the line.
    private func ducklings(on canvas: CALayer) -> TimeInterval {
        let area = self.area(for: body.position)
        let fromLeft = Bool.random()
        let way: CGFloat = fromLeft ? 1 : -1
        let duck = max(26, size * 0.6)
        let babies = 4
        let line = duck * 0.8 + CGFloat(babies) * duck * 0.55
        let fromX = fromLeft ? area.minX - duck : area.maxX + duck
        let toX = fromLeft ? area.maxX + line + duck : area.minX - line - duck
        let speed: CGFloat = 130
        let duration = TimeInterval(abs(toX - fromX) / speed)
        NotchMascotEncounterArt.ducklings(in: canvas, fromX: onStage(CGPoint(x: fromX, y: 0)).x,
                                          toX: onStage(CGPoint(x: toX, y: 0)).x,
                                          floor: onStage(CGPoint(x: 0, y: area.minY)).y, size: duck, babies: babies,
                                          duration: duration)
        for at in stride(from: 0.6, to: duration, by: 2.2) {
            sound(.squeak, pan: pan(fromX + way * speed * CGFloat(at)), after: at)
        }
        let passes = TimeInterval(abs(body.position.x - fromX) / speed)
        let lastPasses = passes + TimeInterval(line / speed)
        encounterStep(after: 0.5) { [weak self] in
            self?.react(.perk)
            self?.face(toward: fromX)
        }
        encounterStep(after: max(0.8, passes - 0.4)) { [weak self] in self?.react(.bounce) }
        encounterStep(after: lastPasses + 0.3) { [weak self] in
            guard let self else { return }
            self.face(toward: toX)
            guard self.perch == nil else { self.react(.wave); return }
            // It falls in behind the last one, as far as the floor goes.
            self.stroll(to: toX, pace: speed / NotchMascotRoam.walkSpeed * 0.9)
        }
        let busy = min(duration, lastPasses + 4.5)
        encounterStep(after: busy - 0.4) { [weak self] in self?.react(.celebrate) }
        visitorsLeave = duration
        return busy
    }
    private func encounterMarker(_ text: String, on canvas: CALayer, at point: CGPoint) {
        NotchMascotPlayEffects.arcadeMarker(text, in: canvas, at: onStage(point), cell: max(1.6, size * 0.05))
    }
    /// The way along the floor with more room, right when positive.
    private var roomier: CGFloat {
        let floor = self.floor
        return body.position.x - floor.lowerBound > floor.upperBound - body.position.x ? -1 : 1
    }
    private func onFloor(_ x: CGFloat) -> CGFloat { min(floor.upperBound, max(floor.lowerBound, x)) }
    private func walkTime(to x: CGFloat, from start: CGFloat, pace: CGFloat) -> TimeInterval {
        TimeInterval(abs(onFloor(x) - start) / (NotchMascotRoam.walkSpeed * pace))
    }
    private static func marks(_ seconds: [TimeInterval], of total: TimeInterval) -> [NSNumber] {
        seconds.map { NSNumber(value: min(1, max(0, $0 / total))) }
    }
    /// A chest turns up by it; it goes to look, the chest bites and chases it
    /// a couple of hops, and goes, leaving coins.
    private func mimic(on canvas: CALayer) -> TimeInterval {
        let side = roomier
        let feet = body.position
        let chest = max(40, size * 0.9)
        let spot = onFloor(feet.x + side * size * 2.8)
        let near = onFloor(spot - side * (chest * 0.5 + size * 0.5))
        let walk = walkTime(to: near, from: feet.x, pace: 1.4)
        let open = 1.0 + walk + 0.7, close = open + 1.8
        let duration = close + 0.9
        let step = side * size * 0.6
        let floor = feet.y
        let at = { (x: CGFloat, up: CGFloat) in self.onStage(CGPoint(x: x, y: floor + up)) }
        let stops = [at(spot, 0), at(spot, 0), at(spot - step / 2, chest * 0.4), at(spot - step, 0), at(spot - step, 0),
                     at(spot - step * 1.5, chest * 0.4), at(spot - step * 2, 0), at(spot - step * 2, 0)]
        let seconds = [0, open + 0.3, open + 0.5, open + 0.7, open + 0.9, open + 1.1, open + 1.3, duration]
        NotchMascotEncounterArt.mimic(in: canvas, size: chest, stops: stops, times: Self.marks(seconds, of: duration),
                                      duration: duration, openAt: open / duration, closeAt: close / duration)
        NotchMascotPlayEffects.magicSmoke(in: canvas, at: at(spot, chest * 0.3), radius: chest * 0.5,
                                          energy: NotchMascotPlay.Energy(red: 0.8, green: 0.75, blue: 0.7), count: 5)
        sound(.poof, pan: pan(spot))
        sound(.creak, pan: pan(spot), after: open - 0.2)
        for bite in [open + 0.1, open + 0.8, open + 1.5] {
            sound(.munch, pan: pan(spot), after: bite)
        }
        later(open + 0.2) { [weak self] in
            self?.encounterMarker("CHOMP", on: canvas, at: CGPoint(x: spot, y: floor + chest * 1.1))
        }
        later(duration - 0.1) { [weak self] in
            guard let self else { return }
            let last = spot - step * 2
            NotchMascotPlayEffects.magicSmoke(in: canvas, at: at(last, chest * 0.3), radius: chest * 0.5,
                                              energy: NotchMascotPlay.Energy(red: 0.8, green: 0.75, blue: 0.7), count: 5)
            NotchMascotPlayEffects.goldCoins(in: canvas, at: at(last, chest * 0.3), radius: max(3, chest * 0.12))
            sound(.poof, pan: self.pan(last))
            sound(.coin, pan: self.pan(last), after: 0.3)
        }
        encounterStep(after: 0.3) { [weak self] in
            self?.react(.surprised)
            self?.face(toward: spot)
        }
        encounterStep(after: 1.0) { [weak self] in
            self?.react(.perk)
            self?.stroll(to: near, pace: 1.4)
        }
        encounterStep(after: open + 0.2) { [weak self] in self?.react(.surprised) }
        encounterStep(after: open + 0.5) { [weak self] in
            self?.react(.panic)
            self?.hop(dx: -side * 260, dy: 560)
        }
        encounterStep(after: open + 1.6) { [weak self] in self?.react(.sweat) }
        encounterStep(after: duration + 0.3) { [weak self] in
            self?.react(.celebrate)
            self?.encounterMarker("+10", on: canvas, at: CGPoint(x: spot - step * 2, y: floor + chest))
        }
        return duration + 1.4
    }
    /// A hooded seller with a great pack walks up and shows its wares; it pays
    /// a coin, gets something back, and the seller goes the way it came.
    private func merchant(on canvas: CALayer) -> TimeInterval {
        let side = roomier
        let feet = body.position
        let area = self.area(for: feet)
        let seller = max(44, size * 1.15)
        let stopX = onFloor(feet.x + side * (size * 0.6 + seller * 0.6))
        let edge = side > 0 ? area.maxX + seller : area.minX - seller
        let fromX = stopX + side * min(abs(edge - stopX), 360)
        let walkIn = TimeInterval(abs(fromX - stopX) / 90)
        let arrive = walkIn, leave = walkIn + 4.6
        let duration = leave + walkIn
        NotchMascotEncounterArt.merchant(in: canvas, fromX: onStage(CGPoint(x: fromX, y: 0)).x,
                                         stopX: onStage(CGPoint(x: stopX, y: 0)).x, toX: onStage(CGPoint(x: fromX, y: 0)).x,
                                         floor: onStage(CGPoint(x: 0, y: feet.y)).y, size: seller, duration: duration,
                                         arriveAt: arrive / duration, leaveAt: leave / duration)
        let hand = CGPoint(x: stopX - side * seller * 0.2, y: feet.y + seller * 0.6)
        sound(.chime, pan: pan(stopX), after: arrive + 0.2)
        later(arrive + 0.4) { [weak self] in
            self?.encounterMarker("SHOP", on: canvas, at: CGPoint(x: stopX, y: feet.y + seller * 1.25))
        }
        let ware: NotchMascotIslandPlay.Thing = [.potion, .key, .flower, .cookie, .balloon, .star].randomElement() ?? .potion
        encounterStep(after: 0.6) { [weak self] in
            self?.react(.perk)
            self?.face(toward: fromX)
        }
        encounterStep(after: arrive + 0.5) { [weak self] in self?.react(.bounce) }
        encounterStep(after: arrive + 1.7) { [weak self] in
            guard let self else { return }
            NotchMascotPlayEffects.fly(.coin, in: canvas, from: self.onStage(self.hand(toward: side)), to: self.onStage(hand),
                                       duration: 0.7, side: max(12, self.size * 0.28), while: self.outingLasts)
            sound(.coin, pan: self.pan(stopX), after: 0.6)
        }
        encounterStep(after: arrive + 2.8) { [weak self] in
            guard let self else { return }
            NotchMascotPlayEffects.fly(ware, in: canvas, from: self.onStage(hand), to: self.onStage(self.head),
                                       duration: 0.8, side: max(14, self.size * 0.34), while: self.outingLasts)
        }
        encounterStep(after: arrive + 3.7) { [weak self] in
            guard let self else { return }
            self.react(.celebrate)
            NotchMascotPlayEffects.burst(.sparkles, in: canvas, at: self.onStage(self.head), size: self.size * 0.9,
                                         energy: NotchMascotPlay.energy(for: self.look))
            self.encounterMarker("+1", on: canvas, at: CGPoint(x: self.head.x, y: self.head.y + self.size * 0.35))
        }
        encounterStep(after: leave + 0.3) { [weak self] in self?.react(.wave) }
        visitorsLeave = duration
        return leave + 1.6
    }
    /// Bubbles rise round it and it jumps at them, then a big one takes it in
    /// a moment and pops.
    private func bubble(on canvas: CALayer) -> TimeInterval {
        let side = roomier
        let feet = body.position
        let small = max(14, size * 0.4)
        var pops: [TimeInterval] = []
        for index in 0..<5 {
            let x = feet.x + CGFloat(index - 2) * size * 1.1 + CGFloat.random(in: -10...10)
            let rise = size * CGFloat.random(in: 3.5...5.5)
            let delay = Double(index) * 0.45
            let length = Double.random(in: 3...4.4)
            let stops = [CGPoint(x: x, y: feet.y), CGPoint(x: x + 14, y: feet.y + rise * 0.35),
                         CGPoint(x: x - 12, y: feet.y + rise * 0.7), CGPoint(x: x + 6, y: feet.y + rise)].map(onStage)
            NotchMascotEncounterArt.bubble(in: canvas, size: small * CGFloat.random(in: 0.7...1.2), stops: stops,
                                           duration: length, delay: delay)
            pops.append(delay + length)
        }
        // One rises right over its head, for it to jump at.
        let over = CGPoint(x: head.x, y: head.y + size * 0.5)
        NotchMascotEncounterArt.bubble(in: canvas, size: small, stops: [CGPoint(x: feet.x + side * size, y: feet.y),
                                                                        CGPoint(x: feet.x + side * size * 0.4, y: feet.y + size * 0.8),
                                                                        over].map(onStage),
                                       duration: 2.6, delay: 0.3)
        pops.append(2.9)
        for pop in pops { sound(.pop, pan: pan(feet.x), after: pop) }
        let big = size * 1.9
        let middle = figureCenter
        let entry = CGPoint(x: middle.x + side * size * 5, y: middle.y + size * 0.4)
        let stops = [entry, CGPoint(x: middle.x + side * size * 2.4, y: middle.y + size * 0.6), middle,
                     CGPoint(x: middle.x + 3, y: middle.y + 5), CGPoint(x: middle.x - 2, y: middle.y + 2), middle].map(onStage)
        NotchMascotEncounterArt.bubble(in: canvas, size: big, stops: stops, duration: 3.6, delay: 4.4)
        sound(.pop, pan: pan(middle.x), after: 8.0)
        sound(.splat, pan: pan(middle.x), after: 8.05)
        encounterStep(after: 0.3) { [weak self] in self?.react(.perk) }
        encounterStep(after: 2.45) { [weak self] in self?.hop(dx: 0, dy: 620) }
        encounterStep(after: 3.0) { [weak self] in
            guard let self else { return }
            self.encounterMarker("POP", on: canvas, at: CGPoint(x: over.x, y: over.y + self.size * 0.3))
        }
        encounterStep(after: 3.6) { [weak self] in self?.react(.bounce) }
        encounterStep(after: 4.6) { [weak self] in self?.face(toward: entry.x) }
        encounterStep(after: 5.4) { [weak self] in self?.react(.surprised) }
        encounterStep(after: 6.3) { [weak self] in self?.react(.love) }
        encounterStep(after: 8.05) { [weak self] in
            self?.react(.surprised)
            self?.hop(dx: 0, dy: 300)
        }
        encounterStep(after: 8.8) { [weak self] in self?.react(.sweat) }
        return 9.8
    }
    /// A cardboard box drops by it; it gets under, is nearly seen, sneaks
    /// along a way inside and comes out.
    private func cardboardBox(on canvas: CALayer) -> TimeInterval {
        let side = roomier
        let feet = body.position
        let area = self.area(for: feet)
        let crate = size * 1.5
        let x0 = onFloor(feet.x + side * size * 2.2)
        let x1 = onFloor(x0 + side * size * 3)
        let walk = walkTime(to: x0, from: feet.x, pace: 1.4)
        let sneak = walkTime(to: x1, from: x0, pace: 1)
        let under = 1.4 + walk
        let goes = under + 1.6, there = goes + sneak
        let duration = there + 1.8
        let floor = feet.y
        let at = { (x: CGFloat, up: CGFloat) in self.onStage(CGPoint(x: x, y: floor + up)) }
        let stops = [at(x0, area.maxY - floor + crate), at(x0, 0), at(x0, 0), at(x0, size * 0.9), at(x0, size * 0.9),
                     at(x0, 0), at(x0, 0), at(x1, 0), at(x1, 0), at(x1, size * 2.2), at(x1, size * 2.4)]
        let seconds = [0, 0.6, under - 0.6, under - 0.35, under + 0.05, under + 0.25, goes, there, there + 0.6,
                       there + 1.1, duration]
        NotchMascotEncounterArt.box(in: canvas, size: crate, stops: stops, times: Self.marks(seconds, of: duration),
                                    duration: duration)
        sound(.thud, pan: pan(x0), after: 0.6)
        sound(.thud, pan: pan(x0), after: under + 0.25)
        sound(.alert, pan: pan(x0), after: under + 0.8)
        sound(.whoosh, pan: pan(x1), after: there + 0.6)
        later(under + 0.8) { [weak self] in
            self?.encounterMarker("!", on: canvas, at: CGPoint(x: x0, y: floor + crate * 0.82 + crate * 0.25))
        }
        encounterStep(after: 0.7) { [weak self] in
            self?.react(.surprised)
            self?.face(toward: x0)
        }
        encounterStep(after: 1.4) { [weak self] in
            self?.react(.perk)
            self?.stroll(to: x0, pace: 1.4)
        }
        encounterStep(after: goes) { [weak self] in self?.stroll(to: x1, pace: 1) }
        encounterStep(after: there + 0.7) { [weak self] in self?.react(.peek) }
        encounterStep(after: there + 1.5) { [weak self] in
            guard let self else { return }
            self.react(.celebrate)
            self.encounterMarker("?", on: canvas, at: CGPoint(x: self.head.x, y: self.head.y + self.size * 0.35))
        }
        return duration + 0.6
    }
    /// A crack of loose pixels opens beside it: it flickers, a few coins
    /// fall out, and it seals.
    private func glitch(on canvas: CALayer) -> TimeInterval {
        let side = roomier
        let feet = body.position
        let center = CGPoint(x: onFloor(feet.x + side * size * 1.8), y: feet.y + size * 1.1)
        let duration: TimeInterval = 5.6
        later(0.2) { [weak self] in
            guard let self else { return }
            NotchMascotEncounterArt.glitch(in: canvas, at: self.onStage(center), height: self.size * 2.2, duration: duration)
        }
        for at in [0.2, 1.1, 2.7, 4.1, 5.5] { sound(.bleep, pan: pan(center.x), after: at) }
        later(1.3) { [weak self] in
            guard let self else { return }
            self.encounterMarker("ERROR", on: canvas, at: CGPoint(x: center.x, y: center.y + self.size * 1.4))
        }
        later(3.2) { [weak self] in
            guard let self else { return }
            NotchMascotPlayEffects.goldCoins(in: canvas, at: self.onStage(center), radius: max(3, self.size * 0.13))
            sound(.coin, pan: self.pan(center.x), after: 0.2)
        }
        encounterStep(after: 0.4) { [weak self] in
            self?.react(.surprised)
            self?.face(toward: center.x)
        }
        encounterStep(after: 1.4) { [weak self] in
            guard let self else { return }
            self.react(.flash)
            guard self.growth == 1, self.growWork == nil else { return }
            self.flicker(to: 0.75)
            self.encounterStep(after: 0.7) { [weak self] in self?.flicker(to: 1) }
        }
        encounterStep(after: 2.0) { [weak self] in self?.sway(amplitude: 0.14, speed: 60, duration: 0.9) }
        encounterStep(after: 3.5) { [weak self] in
            guard let self else { return }
            self.react(.bounce)
            self.encounterMarker("+8", on: canvas, at: CGPoint(x: self.head.x, y: self.head.y + self.size * 0.35))
        }
        encounterStep(after: 6.0) { [weak self] in self?.react(.confused) }
        encounterStep(after: 6.7) { [weak self] in self?.react(.lookAround) }
        return 7.4
    }
    /// A little boat sails along the top of the Dock; on the floor it jumps
    /// it as it passes, and waves it off.
    private func dockBoat(on canvas: CALayer) -> TimeInterval {
        let feet = body.position
        let area = self.area(for: feet)
        let fromLeft = Bool.random()
        let craft = max(40, size)
        let fromX = fromLeft ? area.minX - craft * 1.8 : area.maxX + craft * 1.8
        let toX = fromLeft ? area.maxX + craft * 1.8 : area.minX - craft * 1.8
        let speed = max(150, abs(toX - fromX) / 9)
        let duration = TimeInterval(abs(toX - fromX) / speed)
        NotchMascotEncounterArt.boat(in: canvas, fromX: onStage(CGPoint(x: fromX, y: 0)).x,
                                     toX: onStage(CGPoint(x: toX, y: 0)).x,
                                     water: onStage(CGPoint(x: 0, y: area.minY)).y, size: craft, duration: duration)
        let passes = TimeInterval(abs(feet.x - fromX) / speed)
        sound(.toot, pan: pan(fromLeft ? area.minX : area.maxX), after: 0.6)
        sound(.toot, pan: pan(feet.x), after: passes + 0.9)
        let onTheFloor = perch == nil
        encounterStep(after: 0.6) { [weak self] in
            self?.react(.perk)
            self?.face(toward: fromX)
        }
        encounterStep(after: max(0.9, passes - 1.3)) { [weak self] in self?.react(.bounce) }
        if onTheFloor {
            encounterStep(after: max(1.0, passes - 0.4)) { [weak self] in self?.hop(dx: 0, dy: 760) }
        }
        encounterStep(after: passes + 1.1) { [weak self] in
            self?.face(toward: toX)
            self?.react(.wave)
        }
        visitorsLeave = duration
        return min(duration, passes + 3)
    }
    /// A satellite drifts across the top of the screen, blinking. Most
    /// watch it go and wave; a hologram flickers as its signal reaches her,
    /// and an android beeps back and fills its gauge.
    private func satellite(on canvas: CALayer) -> TimeInterval {
        let area = self.area(for: body.position)
        let fromLeft = Bool.random()
        let fromX = fromLeft ? area.minX - 40 : area.maxX + 40
        let toX = fromLeft ? area.maxX + 40 : area.minX - 40
        let y = area.maxY - area.height * CGFloat.random(in: 0.08...0.18)
        let duration: TimeInterval = 11
        NotchMascotEncounterArt.satellite(in: canvas, from: onStage(CGPoint(x: fromX, y: y)), to: onStage(CGPoint(x: toX, y: y)),
                                          size: max(26, size * 0.6), duration: duration)
        let above = TimeInterval(abs(body.position.x - fromX) / abs(toX - fromX)) * duration
        for at in stride(from: 0.8, to: duration, by: 2.2) {
            sound(.bleep, pan: pan(fromX + (toX - fromX) * CGFloat(at / duration)), after: at)
        }
        let style = look.style
        encounterStep(after: 0.6) { [weak self] in
            self?.react(.peek)
            self?.face(toward: fromX)
        }
        encounterStep(after: max(1.2, above - 0.6)) { [weak self] in
            guard let self else { return }
            self.face(toward: toX)
            switch style {
            case .hologram:
                self.host?.mascot.phase(for: 1.2)
                NotchMascotPlayEffects.burst(.sparkles, in: canvas, at: self.onStage(self.head), size: self.size, energy: self.energy)
            case .android:
                self.host?.mascot.charge(for: 2)
                sound(.bleep, pan: self.pan(self.body.position.x), after: 0.3)
                sound(.bleep, pan: self.pan(self.body.position.x), after: 0.6)
            default:
                self.react(.surprised)
            }
            self.occasionMarkerOnStage(style == .hologram || style == .android ? "PING!" : "?", canvas: canvas)
        }
        encounterStep(after: above + 1.6) { [weak self] in self?.react(.wave) }
        visitorsLeave = duration
        return min(duration, above + 3.2)
    }
    /// Star after star streaks over the top of the screen: it watches each
    /// one, makes a wish, and its eyes shine.
    private func meteorShower(on canvas: CALayer) -> TimeInterval {
        let area = self.area(for: body.position)
        let way: CGFloat = Bool.random() ? 1 : -1
        for (index, at) in [0.2, 1.0, 1.5, 2.4, 2.8, 3.6].enumerated() {
            let startX = area.minX + area.width * CGFloat.random(in: 0.1...0.9)
            let start = CGPoint(x: startX, y: area.maxY - CGFloat.random(in: 10...60))
            let end = CGPoint(x: startX + way * area.width * CGFloat.random(in: 0.2...0.35),
                              y: start.y - area.height * CGFloat.random(in: 0.2...0.3))
            later(at) { [weak self] in
                guard let self else { return }
                NotchMascotEncounterArt.shootingStar(in: canvas, from: self.onStage(start), to: self.onStage(end),
                                                     duration: 0.9)
                if index % 2 == 0 { sound(.magic, pan: self.pan(end.x), after: 0.7) }
            }
        }
        encounterStep(after: 0.3) { [weak self] in self?.react(.perk) }
        encounterStep(after: 1.4) { [weak self] in self?.react(.surprised) }
        encounterStep(after: 3.0) { [weak self] in
            guard let self else { return }
            self.react(.love)
            self.occasionMarkerOnStage("WISH!", canvas: canvas)
        }
        encounterStep(after: 4.6) { [weak self] in
            guard let self else { return }
            NotchMascotPlayEffects.float("✦", in: canvas, at: self.onStage(self.head), size: max(9, self.size * 0.22),
                                         color: CGColor(srgbRed: 1, green: 0.88, blue: 0.4, alpha: 1), count: 4)
        }
        encounterStep(after: 6.6) { [weak self] in self?.react(.relax) }
        return 7.6
    }
    /// A balloon somebody let go of drifts up past it: it jumps for the
    /// string, misses, and waves it goodbye.
    private func lostBalloon(on canvas: CALayer) -> TimeInterval {
        let feet = body.position
        let area = self.area(for: feet)
        let side = roomier
        let from = CGPoint(x: feet.x + side * size * 2.4, y: area.minY - 30)
        let to = CGPoint(x: feet.x - side * size * 0.6, y: area.maxY + 60)
        NotchMascotPlayEffects.fly(.balloon, in: canvas, from: onStage(from), to: onStage(to), duration: 6,
                                   side: max(18, size * 0.45), while: outingLasts)
        encounterStep(after: 0.6) { [weak self] in
            self?.react(.perk)
            self?.face(toward: from.x)
        }
        encounterStep(after: 1.8) { [weak self] in
            guard let self else { return }
            self.react(.bounce)
            if self.perch == nil { self.hop(dx: side * 120, dy: 720) }
        }
        encounterStep(after: 3.0) { [weak self] in self?.react(.sweat) }
        encounterStep(after: 4.4) { [weak self] in self?.react(.wave) }
        visitorsLeave = 6
        return 6.4
    }
    /// A rainbow arches over the screen and fades: it stares, and is glad.
    private func rainbow(on canvas: CALayer) -> TimeInterval {
        let area = self.area(for: body.position)
        let span = min(area.width * 0.7, 900)
        let center = CGPoint(x: min(area.maxX - span / 2, max(area.minX + span / 2, body.position.x)), y: area.minY)
        NotchMascotEncounterArt.rainbow(in: canvas, center: onStage(center), radius: span / 2, duration: 6.5)
        sound(.chime, pan: pan(center.x), after: 0.5)
        encounterStep(after: 0.6) { [weak self] in self?.react(.surprised) }
        encounterStep(after: 1.8) { [weak self] in
            guard let self else { return }
            self.react(.love)
            NotchMascotPlayEffects.burst(.sparkles, in: canvas, at: self.onStage(self.head), size: self.size, energy: self.energy)
        }
        encounterStep(after: 4.0) { [weak self] in self?.sway(amplitude: 0.08, speed: 4, duration: 2) }
        visitorsLeave = 6.5
        return 6.8
    }
    /// A heart flies in from someone off the edge of the screen: it looks
    /// round for who sent it, and blushes.
    private func secretAdmirer(on canvas: CALayer) -> TimeInterval {
        let area = self.area(for: body.position)
        let fromRight = Bool.random()
        let from = CGPoint(x: fromRight ? area.maxX + 30 : area.minX - 30, y: area.minY + area.height * 0.3)
        later(0.4) { [weak self] in
            guard let self else { return }
            NotchMascotPlayEffects.fly(.heart, in: canvas, from: self.onStage(from), to: self.onStage(self.head),
                                       duration: 1.6, side: max(14, self.size * 0.34), while: self.outingLasts)
        }
        encounterStep(after: 0.3) { [weak self] in self?.face(toward: from.x) }
        encounterStep(after: 2.1) { [weak self] in
            guard let self else { return }
            self.react(.surprised)
            NotchMascotPlayEffects.burst(.hearts, in: canvas, at: self.onStage(self.head), size: self.size, energy: self.energy)
        }
        encounterStep(after: 3.0) { [weak self] in
            guard let self else { return }
            self.react(.lookAround)
            self.occasionMarkerOnStage("♥?", canvas: canvas)
        }
        encounterStep(after: 4.8) { [weak self] in self?.react(.love) }
        return 6
    }
    /// An arcade marker over its head on the encounter's stage.
    private func occasionMarkerOnStage(_ text: String, canvas: CALayer) {
        NotchMascotPlayEffects.arcadeMarker(text, in: canvas, at: onStage(CGPoint(x: head.x, y: head.y + size * 0.35)),
                                            cell: max(1.6, size * 0.05))
    }
    /// A waste bin waddles up and spits its paper round it; it throws each
    /// ball back in, and the bin goes off pleased.
    private func trashCan(on canvas: CALayer) -> TimeInterval {
        let side = roomier
        let feet = body.position
        let area = self.area(for: feet)
        let bin = max(40, size * 1.1)
        let standX = onFloor(feet.x + side * size * 2.8)
        let edge = side > 0 ? area.maxX + bin : area.minX - bin
        let entry = standX + side * min(abs(edge - standX), 320)
        let walkIn = TimeInterval(abs(entry - standX) / 110)
        let mouth = CGPoint(x: standX, y: feet.y + bin * 0.85)
        let spots = [feet.x - side * size, feet.x - side * size * 2, feet.x + side * size * 1.4].map(onFloor)
        let spills = [walkIn + 0.6, walkIn + 1.1, walkIn + 1.6]
        var tosses: [TimeInterval] = []
        var clock = walkIn + 2.6, at = feet.x
        for spot in spots {
            let walk = walkTime(to: spot, from: at, pace: 1.6)
            let toss = clock + walk + 0.3
            let start = clock
            encounterStep(after: start) { [weak self] in self?.stroll(to: spot, pace: 1.6) }
            encounterStep(after: toss) { [weak self] in
                guard let self else { return }
                self.face(toward: standX)
                self.react(.ready)
                sound(.boing, pan: self.pan(spot))
            }
            encounterStep(after: toss + 0.7) { [weak self] in
                self?.encounterMarker("+10", on: canvas, at: CGPoint(x: standX, y: mouth.y + bin * 0.35))
            }
            tosses.append(toss)
            clock = toss + 0.8
            at = spot
        }
        let leave = clock + 0.9
        let duration = leave + walkIn
        let burps = spills.map { $0 / duration } + tosses.map { ($0 + 0.55) / duration } + [(leave - 0.5) / duration]
        let stops = [entry, standX, standX, entry].map { self.onStage(CGPoint(x: $0, y: feet.y)) }
        NotchMascotEncounterArt.trashCan(in: canvas, size: bin, stops: stops,
                                         times: Self.marks([0, walkIn, leave, duration], of: duration), duration: duration,
                                         burps: burps)
        for (index, spot) in spots.enumerated() {
            NotchMascotEncounterArt.paperBall(in: canvas, mouth: onStage(mouth), spot: onStage(CGPoint(x: spot, y: feet.y)),
                                              size: max(8, size * 0.22), spillAt: spills[index], tossAt: tosses[index])
            sound(.creak, pan: pan(standX), after: spills[index] - 0.1)
            sound(.pop, pan: pan(standX), after: spills[index])
        }
        later(leave - 0.5) { [weak self] in
            guard let self else { return }
            NotchMascotPlayEffects.burst(.hearts, in: canvas, at: self.onStage(CGPoint(x: standX, y: mouth.y + bin * 0.2)),
                                         size: bin, energy: NotchMascotPlay.energy(for: self.look))
            sound(.chime, pan: self.pan(standX))
        }
        encounterStep(after: 0.5) { [weak self] in
            self?.react(.perk)
            self?.face(toward: entry)
        }
        encounterStep(after: spills[0] + 0.2) { [weak self] in self?.react(.surprised) }
        encounterStep(after: spills[2] + 0.4) { [weak self] in self?.react(.confused) }
        encounterStep(after: leave) { [weak self] in self?.react(.celebrate) }
        visitorsLeave = duration
        return leave + 1.2
    }
    /// In the daytime a cup of coffee is set down by it: it drinks, runs
    /// round like mad a while, and then flags.
    private func coffee(on canvas: CALayer) -> TimeInterval {
        let side = roomier
        let feet = body.position
        let cup = max(22, size * 0.5)
        let cupX = onFloor(feet.x + side * size * 1.6)
        let standX = onFloor(cupX - side * (size * 0.55 + cup * 0.4))
        let walk = walkTime(to: standX, from: feet.x, pace: 1.2)
        let there = 1.2 + walk
        let drunk = there + 2.4
        let duration = there + 7.6
        NotchMascotEncounterArt.coffee(in: canvas, x: onStage(CGPoint(x: cupX, y: 0)).x,
                                       floor: onStage(CGPoint(x: 0, y: feet.y)).y, size: cup, duration: duration,
                                       emptyAt: drunk / duration)
        sound(.pop, pan: pan(cupX), after: 0.3)
        sound(.slurp, pan: pan(cupX), after: there + 0.4)
        sound(.slurp, pan: pan(cupX), after: there + 1.7)
        encounterStep(after: 0.4) { [weak self] in
            self?.react(.perk)
            self?.face(toward: cupX)
        }
        encounterStep(after: 1.2) { [weak self] in self?.stroll(to: standX, pace: 1.2) }
        encounterStep(after: there + 0.3) { [weak self] in
            self?.face(toward: cupX)
            self?.react(.sip)
        }
        encounterStep(after: there + 1.6) { [weak self] in self?.react(.sip) }
        encounterStep(after: drunk + 0.2) { [weak self] in
            guard let self else { return }
            self.react(.flash)
            self.encounterMarker("!!", on: canvas, at: CGPoint(x: self.head.x, y: self.head.y + self.size * 0.35))
            sound(.zap, pan: self.pan(self.head.x))
        }
        for (index, at) in [drunk + 0.7, drunk + 1.3, drunk + 1.9, drunk + 2.5].enumerated() {
            encounterStep(after: at) { [weak self] in
                guard let self else { return }
                let way: CGFloat = index.isMultiple(of: 2) ? -side : side
                self.hop(dx: way * 300, dy: 600)
                NotchMascotPlayEffects.sparks(in: canvas, at: self.onStage(self.figureCenter), reach: self.size * 0.8,
                                              energy: NotchMascotPlay.energy(for: self.look), count: 6)
                sound(.boing, pan: self.pan(self.head.x))
            }
        }
        encounterStep(after: drunk + 3.2) { [weak self] in self?.sway(amplitude: 0.2, speed: 70, duration: 1.0) }
        encounterStep(after: drunk + 4.4) { [weak self] in
            self?.react(.yawn)
            self?.perform(.doze(3), toward: side)
        }
        return drunk + 7.6
    }
    // MARK: Occasions of its own
    /// What it is busy with of its own: longing for something, a game, a
    /// moment the Mac or the calendar brought, a dance.
    private enum Occasion: Equatable {
        case craving(NotchMascotCraving), tantrum, fed, tickled
        case fishing, bite, seeking, laser, game, dance
        case show(NotchMascotOccasion)
    }
    private func occasionStep(after delay: TimeInterval, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        occasionWork.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }
    private func occasionCanvas() -> CALayer? {
        let stage = occasionStage ?? NotchMascotPlayStage()
        occasionStage = stage
        guard let screen = playScreen else { return nil }
        return stage.layer(over: screen)
    }
    private func onOccasion(_ point: CGPoint) -> CGPoint { occasionStage?.point(point) ?? point }
    private func occasionMarker(_ text: String, at point: CGPoint? = nil) {
        guard let canvas = occasionCanvas() else { return }
        let at = point ?? CGPoint(x: head.x, y: head.y + size * 0.35)
        NotchMascotPlayEffects.arcadeMarker(text, in: canvas, at: onOccasion(at), cell: max(1.6, size * 0.05))
    }
    private var energy: NotchMascotPlay.Energy { NotchMascotPlay.energy(for: look) }
    /// Starts `kind`, stopping a walk and its plans; nil when it cannot now.
    private func beginOccasion(_ kind: Occasion) -> CALayer? {
        guard isOut, !isHoming, press == nil, !inEncounter else { return nil }
        if occasion != nil { endOccasion() }
        if inPlay { interrupted?() }
        cancelItemUse()
        planWork?.cancel(); planWork = nil
        if isWalking {
            setRun(nil)
            mode = .standing
        }
        guard let canvas = occasionCanvas() else { return nil }
        occasion = kind
        return canvas
    }
    /// Done with it in `delay` seconds: it goes on with its own life.
    private func finishOccasion(after delay: TimeInterval) {
        occasionStep(after: delay) { [weak self] in
            guard let self else { return }
            self.endOccasion()
            if self.isOut, self.mode == .standing { self.planNext(after: 2) }
        }
    }
    /// Stops whatever it was busy with at once; what it drew finishes alone.
    private func endOccasion() {
        occasionWork.forEach { $0.cancel() }
        occasionWork.removeAll()
        laserTimer?.cancel(); laserTimer = nil
        laserDot?.removeFromSuperlayer(); laserDot = nil
        if upsideDown {
            upsideDown = false
            host?.mascot.setUpsideDown(false)
        }
        if occasion == .seeking { endPeek() }
        askedFor = false
        guard occasion != nil else { return }
        occasion = nil
        let stage = occasionStage
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.occasionStage === stage, self.occasion == nil else { return }
            stage?.close()
        }
    }
    /// It puts `item` on for `length`, then goes back to what was chosen.
    private func wear(_ item: NotchMascotAccessory?, for length: TimeInterval) {
        guard let item, look.style.takesAccessory, !itemHidden else { return }
        dressUpWork?.cancel()
        dressUpItem = item
        configure(look: baseLook, mood: mood)
        let work = DispatchWorkItem { [weak self] in self?.endDressUp() }
        dressUpWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + length, execute: work)
    }
    /// A click on it while it is busy with something that waits for one.
    /// True when the click was its answer, not a grab.
    private func answerOccasion() -> Bool {
        switch occasion {
        case .craving(let craving):
            satisfy(craving)
            return true
        case .bite:
            pullCatch()
            return true
        case .seeking where peekDepth > 0:
            found()
            return true
        case .laser:
            stopLaser()
            return true
        case .none:
            return false
        default:
            endOccasion()
            return false
        }
    }
    // Cravings and tantrums.
    private func maybeCrave() -> Bool {
        let now = CACurrentMediaTime()
        guard !isDozing, NotchMascotCravings.shouldStart(since: now - lastCraving, random: Double.random(in: 0..<1))
        else { return false }
        lastCraving = now
        crave(NotchMascotCraving.pick(hour: Calendar.current.component(.hour, from: Date()), style: look.style,
                                      random: Double.random(in: 0..<1)))
        return true
    }
    /// A thought bubble over it shows what it longs for: a click on it is
    /// understanding; left alone too long, it stamps its feet.
    func crave(_ craving: NotchMascotCraving) {
        guard let canvas = beginOccasion(.craving(craving)) else { return }
        react(.perk)
        NotchMascotOccasionArt.thought(in: canvas, over: onOccasion(head), size: max(40, size * 0.95),
                                       icon: .craving(craving), duration: NotchMascotCravings.patience)
        sound(.pop, pan: pan(body.position.x))
        occasionStep(after: 3.5) { [weak self] in self?.react(.lookAround) }
        occasionStep(after: NotchMascotCravings.patience) { [weak self] in self?.tantrum() }
    }
    private func satisfy(_ craving: NotchMascotCraving) {
        occasionWork.forEach { $0.cancel() }
        occasionWork.removeAll()
        occasionStage?.close()
        occasion = .fed
        guard let canvas = occasionCanvas() else { return }
        let from = CGPoint(x: head.x + size * 1.6, y: head.y + size * 1.4)
        NotchMascotPlayEffects.fly(craving.thing, in: canvas, from: onOccasion(from), to: onOccasion(head), duration: 0.7,
                                   side: max(14, size * 0.34), energy: energy, while: outingLasts)
        react(.celebrate)
        hop(dx: 0, dy: 640)
        sound(.chime, pan: pan(body.position.x))
        occasionStep(after: 0.8) { [weak self] in
            guard let self, let canvas = self.occasionCanvas() else { return }
            NotchMascotPlayEffects.burst(.hearts, in: canvas, at: self.onOccasion(self.head), size: self.size * 0.9,
                                         energy: self.energy)
            self.occasionMarker("♥")
        }
        NotchMascotBondStore.shared.record(.moment)
        finishOccasion(after: 2.6)
    }
    /// Nobody understood: it stamps, huffs and turns its back a moment.
    private func tantrum() {
        occasion = .tantrum
        guard let canvas = occasionCanvas() else { return }
        for (index, at) in [0.0, 0.45, 0.9].enumerated() {
            occasionStep(after: at) { [weak self] in
                guard let self else { return }
                self.hop(dx: 0, dy: 300)
                sound(.thud, pan: self.pan(self.body.position.x))
                NotchMascotPlayEffects.magicSmoke(in: canvas, at: self.onOccasion(CGPoint(x: self.head.x, y: self.head.y + self.size * 0.2)),
                                                  radius: self.size * 0.3,
                                                  energy: NotchMascotPlay.Energy(red: 0.95, green: 0.95, blue: 0.95), count: 3)
                if index == 0 {
                    self.react(.confused)
                    self.occasionMarker("HMPH!")
                }
            }
        }
        occasionStep(after: 1.6) { [weak self] in self?.sway(amplitude: 0.12, speed: 30, duration: 1.0) }
        occasionStep(after: 2.8) { [weak self] in self?.react(.sweat) }
        finishOccasion(after: 3.6)
    }
    /// Something was dropped on it: food it catches and eats, anything else
    /// it sniffs at and wonders about.
    func dropped(_ drop: NotchMascotSnackDrop) {
        lastTouched = CACurrentMediaTime()
        if case .craving(let craving) = occasion, drop == .food {
            satisfy(craving)
            return
        }
        guard beginOccasion(.fed) != nil else { return }
        switch drop {
        case .food:
            react(.surprised)
            occasionStep(after: 0.3) { [weak self] in self?.hop(dx: 0, dy: 420) }
            for (index, at) in [0.8, 1.15, 1.5].enumerated() {
                occasionStep(after: at) { [weak self] in
                    guard let self else { return }
                    sound(index == 2 ? .munch : .crunch, pan: self.pan(self.body.position.x))
                    if index == 0 { self.occasionMarker("CHOMP") }
                }
            }
            occasionStep(after: 2.2) { [weak self] in
                guard let self, let canvas = self.occasionCanvas() else { return }
                self.react(.love)
                NotchMascotPlayEffects.float("♥", in: canvas, at: self.onOccasion(self.head), size: max(10, self.size * 0.3),
                                             color: NotchMascotRPGShapes.rgb(0xFF5E8A), count: 3)
                self.occasionMarker("♥ YUM")
            }
            NotchMascotBondStore.shared.record(.moment)
            finishOccasion(after: 4)
        case .other:
            react(.peek)
            occasionStep(after: 1.2) { [weak self] in
                self?.react(.confused)
                self?.occasionMarker("?")
            }
            finishOccasion(after: 2.8)
        }
    }
    // Tickles and the trampoline.
    private func trackTickles(at point: CGPoint) {
        guard occasion == nil, press == nil, !inPlay, !inEncounter, !usingItem, !body.airborne, peekDepth == 0, !isDozing
        else { tickles.reset(); return }
        let frame = figureFrame
        let belly = CGRect(x: frame.minX + frame.width * 0.15, y: frame.minY + size * 0.12,
                           width: frame.width * 0.7, height: size * 0.55)
        guard tickles.track(x: point.x, over: belly.contains(point), time: CACurrentMediaTime()) else { return }
        tickled()
    }
    /// It cannot stand it: it laughs, cries with laughter and ends up
    /// rolling on its back kicking.
    private func tickled() {
        guard let canvas = beginOccasion(.tickled) else { return }
        lastTouched = CACurrentMediaTime()
        let side = roomier
        react(.celebrate)
        occasionMarker("HAHAHA!")
        sound(.giggle, pan: pan(body.position.x))
        sound(.giggle, pan: pan(body.position.x), after: 0.6)
        sway(amplitude: 0.22, speed: 38, duration: 1.6)
        occasionStep(after: 0.9) { [weak self] in
            guard let self else { return }
            NotchMascotPlayEffects.float("~", in: canvas, at: self.onOccasion(self.head), size: max(9, self.size * 0.22),
                                         color: NotchMascotRPGShapes.rgb(0x64B5F6), count: 2)
        }
        occasionStep(after: 1.8) { [weak self] in
            guard let self else { return }
            self.tilt(side * 1.5, for: 2.0)
            sound(.giggle, pan: self.pan(self.body.position.x), after: 0.3)
        }
        occasionStep(after: 2.2) { [weak self] in self?.react(.bounce) }
        occasionStep(after: 4.0) { [weak self] in self?.react(.love) }
        NotchMascotBondStore.shared.record(.moment)
        finishOccasion(after: 5)
    }
    /// Falling, it lands on the pointer held under its feet and bounces off
    /// it, higher, with a somersault.
    private func checkTrampoline() {
        // Only a fall the user started: dropping down a window on its own,
        // it passes a pointer busy in that window by.
        guard dropped, !inPlay, !leaping, press == nil, occasion != .laser else { return }
        let pointer = NSEvent.mouseLocation
        let now = CACurrentMediaTime()
        guard now - lastBounce > 0.25, bounces < NotchMascotTrampoline.most,
              pointer.y > area(for: body.position).minY + 6,
              NotchMascotTrampoline.bounces(feet: body.position, width: size * figureAspect,
                                            velocityY: body.velocity.dy, pointer: pointer),
              !NotchMascotTrampoline.onLedge(pointer: pointer, ledges: inPlay ? [] : currentLedges())
        else { return }
        lastBounce = now
        bounces += 1
        body.velocity.dy = NotchMascotTrampoline.bounce(velocityY: body.velocity.dy)
        body.velocity.dx *= 0.6
        thrown = false
        lastTouched = now
        sound(.boing, pan: pan(pointer.x))
        host?.mascot.spin(turns: bounces.isMultiple(of: 2) ? -2 : 2, duration: 0.7)
        occasionMarker(bounces == 1 ? "BOING!" : "X\(bounces)", at: CGPoint(x: pointer.x, y: pointer.y + size * 0.3))
    }
    // The laser pointer.
    /// A red dot follows the pointer for a while and it chases it all over.
    @objc private func menuLaser() {
        startLaser()
        askedFor = occasion == .laser
    }
    func startLaser() {
        guard let canvas = beginOccasion(.laser) else { return }
        excursionWork?.cancel(); excursionWork = nil
        lastTouched = CACurrentMediaTime()
        let dot = CAShapeLayer()
        dot.path = CGPath(ellipseIn: CGRect(x: -4, y: -4, width: 8, height: 8), transform: nil)
        dot.fillColor = NotchMascotRPGShapes.rgb(0xFF1744)
        dot.shadowColor = NotchMascotRPGShapes.rgb(0xFF1744)
        dot.shadowOpacity = 1
        dot.shadowRadius = 7
        dot.shadowOffset = .zero
        canvas.addSublayer(dot)
        laserDot = dot
        react(.perk)
        sound(.zap, pan: pan(body.position.x))
        let started = CACurrentMediaTime()
        var lastThought = started
        var lastCatch = -CFTimeInterval.infinity
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            guard let self, self.occasion == .laser, self.isOut else { timer.cancel(); return }
            let now = CACurrentMediaTime()
            let pointer = NSEvent.mouseLocation
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            dot.isHidden = self.playScreen?.frame.contains(pointer) != true
            dot.position = self.onOccasion(pointer)
            CATransaction.commit()
            if now - started >= NotchMascotLaser.length {
                self.stopLaser()
                return
            }
            if self.figureFrame.insetBy(dx: -8, dy: -8).contains(pointer), now - lastCatch > 1.4 {
                lastCatch = now
                self.react(.celebrate)
                sound(.pop, pan: self.pan(pointer.x))
                self.occasionMarker("GOT IT!")
            }
            guard now - lastThought >= NotchMascotLaser.think else { return }
            lastThought = now
            self.chaseLaser(to: pointer)
        }
        laserTimer = timer
        timer.resume()
    }
    private func chaseLaser(to pointer: CGPoint) {
        guard playScreen?.frame.contains(pointer) == true, press == nil else { return }
        face(toward: pointer.x)
        guard !body.airborne else { return }
        let dx = pointer.x - body.position.x
        let rise = pointer.y - body.position.y
        let eager: CGFloat = [.cat, .dog, .frog].contains(look.style) ? 1.25 : 1
        if abs(dx) < size * 1.4, rise > size * 0.7, rise < size * 7 {
            let dy = min(1600, sqrt(2 * NotchMascotRoam.gravity * max(40, rise + size * 0.3)) * eager)
            hop(dx: dx * 2.4, dy: dy)
        } else if abs(dx) > size * 0.4 {
            stroll(to: pointer.x, pace: 3.4 * eager)
        }
    }
    private func stopLaser() {
        guard occasion == .laser else { return }
        laserTimer?.cancel(); laserTimer = nil
        laserDot?.removeFromSuperlayer(); laserDot = nil
        if isWalking {
            setRun(nil)
            mode = .standing
        }
        react(.relax)
        occasionMarker("PHEW")
        finishOccasion(after: 1.5)
    }
    // Fishing at the Dock.
    private func maybeFish() -> Bool {
        let now = CACurrentMediaTime()
        guard perch == nil, !isDozing,
              NotchMascotFishing.shouldStart(since: now - lastFishing, random: Double.random(in: 0..<1))
        else { return false }
        fish()
        return true
    }
    @objc private func menuFishing() {
        excursionWork?.cancel(); excursionWork = nil
        fish()
        askedFor = occasion != nil
    }
    /// It sits by the Dock with a little rod and waits; when it bites, a click
    /// helps it pull, and what comes up is a surprise. Missed, it gets away.
    func fish() {
        guard let canvas = beginOccasion(.fishing) else { return }
        lastFishing = CACurrentMediaTime()
        let way = roomier
        let area = self.area(for: body.position)
        let bite = 1.4 + TimeInterval.random(in: NotchMascotFishing.wait)
        let pullAt = bite + NotchMascotFishing.window
        face(toward: body.position.x + way * 100)
        react(.relax)
        NotchMascotOccasionArt.rod(in: canvas, hand: onOccasion(hand(toward: way)), way: way,
                                   water: onOccasion(CGPoint(x: 0, y: area.minY + size * 0.05)).y, size: size,
                                   duration: pullAt + 0.8, biteAt: bite, pullAt: pullAt)
        sound(.whoosh, pan: pan(body.position.x + way * size), after: 0.3)
        sound(.pop, pan: pan(body.position.x + way * size * 1.6), after: 0.8)
        occasionStep(after: bite * 0.5) { [weak self] in self?.react(.hush) }
        occasionStep(after: bite) { [weak self] in
            guard let self else { return }
            self.occasion = .bite
            self.react(.surprised)
            self.occasionMarker("!")
            sound(.alert, pan: self.pan(self.body.position.x))
        }
        occasionStep(after: pullAt) { [weak self] in
            guard let self, self.occasion == .bite else { return }
            self.occasion = .fishing
            self.react(.confused)
            self.occasionMarker("...")
            sound(.sad, pan: self.pan(self.body.position.x))
            self.finishOccasion(after: 2)
        }
    }
    /// You helped it pull in time.
    private func pullCatch() {
        occasionWork.forEach { $0.cancel() }
        occasionWork.removeAll()
        occasionStage?.close()
        occasion = .fishing
        lastTouched = CACurrentMediaTime()
        guard let canvas = occasionCanvas() else { return }
        let way = roomier
        let haul = NotchMascotCatch.pull(random: Double.random(in: 0..<1))
        let from = CGPoint(x: body.position.x + way * size * 1.6, y: area(for: body.position).minY + size * 0.05)
        NotchMascotOccasionArt.caught(haul, in: canvas, from: onOccasion(from), head: onOccasion(head), size: max(24, size * 0.6))
        sound(.whoosh, pan: pan(from.x))
        hop(dx: 0, dy: 360)
        occasionStep(after: 0.7) { [weak self] in
            guard let self, let canvas = self.occasionCanvas() else { return }
            self.occasionMarker(haul.marker, at: CGPoint(x: self.head.x, y: self.head.y + self.size * 1.2))
            switch haul {
            case .goldfish:
                self.react(.celebrate)
                sound(.coin, pan: self.pan(self.body.position.x))
            case .boot:
                self.react(.sweat)
                sound(.splat, pan: self.pan(self.body.position.x))
            case .key:
                self.react(.perk)
                sound(.chime, pan: self.pan(self.body.position.x))
                NotchMascotPlayEffects.burst(.sparkles, in: canvas, at: self.onOccasion(self.head), size: self.size, energy: self.energy)
            case .pearl:
                self.react(.love)
                sound(.magic, pan: self.pan(self.body.position.x))
                NotchMascotPlayEffects.burst(.sparkles, in: canvas, at: self.onOccasion(self.head), size: self.size, energy: self.energy)
            }
        }
        if haul == .boot { occasionStep(after: 2.0) { [weak self] in self?.react(.confused) } }
        NotchMascotBondStore.shared.record(.moment)
        finishOccasion(after: 3.4)
    }
    // Rock, paper, scissors.
    @objc private func menuRoshambo(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let yours = NotchMascotRoshambo(rawValue: raw) else { return }
        playRoshambo(yours)
        askedFor = occasion != nil
    }
    /// One, two, three: it shows its pick in a bubble, and claps and pays
    /// up when you win, or dances a cheeky victory when it does.
    func playRoshambo(_ yours: NotchMascotRoshambo) {
        guard let canvas = beginOccasion(.game) else { return }
        excursionWork?.cancel(); excursionWork = nil
        lastTouched = CACurrentMediaTime()
        let its = NotchMascotRoshambo.pick(random: Double.random(in: 0..<1))
        for (index, at) in [0.0, 0.6, 1.2].enumerated() {
            occasionStep(after: at) { [weak self] in
                guard let self else { return }
                self.occasionMarker("\(index + 1)")
                self.hop(dx: 0, dy: 280)
                sound(.bleep, pan: self.pan(self.body.position.x))
            }
        }
        occasionStep(after: 1.8) { [weak self] in
            guard let self else { return }
            NotchMascotOccasionArt.thought(in: canvas, over: self.onOccasion(self.head), size: max(40, self.size * 0.95),
                                           icon: .roshambo(its), duration: 3.4)
            sound(.pop, pan: self.pan(self.body.position.x))
        }
        occasionStep(after: 2.7) { [weak self] in
            guard let self else { return }
            switch yours.outcome(against: its) {
            case .youWin:
                self.react(.bounce)
                let prize = self.payRoshamboWin()
                NotchMascotPlayEffects.goldCoins(in: canvas, at: self.onOccasion(self.head), radius: max(3, self.size * 0.14))
                sound(.coin, pan: self.pan(self.body.position.x))
                self.occasionMarker(prize > 0 ? "+\(prize)" : "YOU WIN")
                self.occasionStep(after: 0.9) { [weak self] in self?.react(.celebrate) }
            case .itWins:
                self.react(.celebrate)
                self.occasionMarker("I WIN!")
                self.host?.mascot.spin(turns: 1, duration: 0.6)
                self.occasionStep(after: 0.7) { [weak self] in self?.hop(dx: 0, dy: 460) }
                self.occasionStep(after: 1.3) { [weak self] in
                    guard let self else { return }
                    self.hop(dx: 0, dy: 460)
                    NotchMascotPlayEffects.burst(.hearts, in: canvas, at: self.onOccasion(self.head), size: self.size,
                                                 energy: self.energy)
                }
            case .tie:
                self.react(.confused)
                self.occasionMarker("TIE!")
            }
        }
        finishOccasion(after: 5)
    }
    /// Pays a win in gold while today's paid wins last; the gold it paid.
    private func payRoshamboWin() -> Int {
        let defaults = UserDefaults.standard
        let today = NotchMascotSpecialDays.key(for: Date())
        let saved = (defaults.string(forKey: DefaultsKey.notchMascotRoshamboWins) ?? "").split(separator: ":")
        let wins = saved.count == 2 && String(saved[0]) == today ? Int(saved[1]) ?? 0 : 0
        let prize = NotchMascotRoshambo.payout(winsToday: wins)
        defaults.set("\(today):\(wins + 1)", forKey: DefaultsKey.notchMascotRoshamboWins)
        if prize > 0 { NotchMascotRPG.collect(gold: prize) }
        return prize
    }
    // Hide and seek.
    private func maybeHideAndSeek() -> Bool {
        guard !isDozing, CACurrentMediaTime() - lastTouched >= NotchMascotHideAndSeek.boredAfter else { return false }
        hideAndSeek()
        return true
    }
    @objc private func menuHideAndSeek() {
        excursionWork?.cancel(); excursionWork = nil
        hideAndSeek()
        askedFor = occasion != nil
    }
    /// Bored, it calls out and hides behind the window it stands on or the
    /// bottom of the screen, only the top of its head showing. Found with a
    /// click, it cheers; not found in a while, it comes out on its own.
    func hideAndSeek() {
        guard beginOccasion(.seeking) != nil else { return }
        lastTouched = CACurrentMediaTime()
        react(.wave)
        occasionMarker("FIND ME!")
        sound(.chime, pan: pan(body.position.x))
        var walk: TimeInterval = 0
        if perch == nil {
            let floor = self.floor
            let x = CGFloat.random(in: floor)
            let far = abs(x - body.position.x) < size * 4
                ? onFloor(body.position.x + roomier * min(floor.upperBound - floor.lowerBound, size * 8) * 0.6) : x
            walk = walkTime(to: far, from: body.position.x, pace: 2.4)
            occasionStep(after: 1.2) { [weak self] in self?.stroll(to: far, pace: 2.4) }
        }
        occasionStep(after: 1.4 + walk) { [weak self] in
            guard let self else { return }
            self.setRun(nil)
            if self.isWalking { self.mode = .standing }
            self.sink(to: self.size * NotchMascotHideAndSeek.depth, over: 0.4) {}
        }
        occasionStep(after: 1.4 + walk + NotchMascotHideAndSeek.gives) { [weak self] in
            guard let self, self.occasion == .seeking else { return }
            self.sink(to: 0, over: 0.25) { [weak self] in
                guard let self else { return }
                self.react(.wave)
                self.occasionMarker("HERE!")
            }
            self.lastTouched = CACurrentMediaTime()
            self.finishOccasion(after: 2)
        }
    }
    private func found() {
        occasionWork.forEach { $0.cancel() }
        occasionWork.removeAll()
        lastTouched = CACurrentMediaTime()
        sink(to: 0, over: 0.2) { [weak self] in
            guard let self, let canvas = self.occasionCanvas() else { return }
            self.react(.celebrate)
            self.hop(dx: 0, dy: 520)
            NotchMascotPlayEffects.burst(.confetti, in: canvas, at: self.onOccasion(self.head), size: self.size * 1.2,
                                         energy: self.energy)
            sound(.magic, pan: self.pan(self.body.position.x))
            self.occasionMarker("YOU FOUND ME!")
        }
        occasion = .game
        NotchMascotBondStore.shared.record(.moment)
        finishOccasion(after: 3)
    }
    // What the Mac and the calendar bring.
    /// Shows `occasion` where it stands. True when it did.
    @discardableResult
    func show(_ occasion: NotchMascotOccasion) -> Bool {
        guard isOut, !isHoming, press == nil, !inEncounter, !inPlay else { return false }
        // Coming back answers the moment before; anything else waits its turn.
        if let current = self.occasion {
            guard case .show = current, occasion == .online || occasion == .charged else { return false }
        }
        guard let canvas = beginOccasion(.show(occasion)) else { return false }
        let side = roomier
        let feet = body.position
        let area = self.area(for: feet)
        let length: TimeInterval
        // Back online or on power, it puts away what it waited with.
        if occasion == .online || occasion == .charged { endDressUp() }
        wear(occasion.costume, for: 12)
        switch occasion {
        case .boost:
            length = 6.5
            react(.ready)
            NotchMascotOccasionArt.turboFan(in: canvas, at: onOccasion(CGPoint(x: feet.x - side * size * 0.75, y: feet.y + size * 0.6)),
                                            size: size * 0.6, duration: length)
            sound(.whoosh, pan: pan(feet.x))
            for at in stride(from: 0.3, to: 5.5, by: 0.6) {
                occasionStep(after: at) { [weak self] in
                    guard let self else { return }
                    NotchMascotPlayEffects.sparks(in: canvas, at: self.onOccasion(self.body.position), reach: self.size * 0.7,
                                                  energy: NotchMascotPlay.Energy(red: 1, green: 0.85, blue: 0.2), count: 6)
                }
            }
            occasionStep(after: 1.2) { [weak self] in
                guard let self else { return }
                self.react(.flash)
                NotchMascotPlayEffects.lightning(in: canvas, around: self.onOccasion(self.figureCenter), radius: self.size * 0.8,
                                                 energy: NotchMascotPlay.Energy(red: 1, green: 0.9, blue: 0.3))
                sound(.zap, pan: self.pan(self.body.position.x))
            }
            occasionStep(after: 2.0) { [weak self] in self?.sway(amplitude: 0.06, speed: 70, duration: 2.5) }
        case .cold:
            length = 7
            react(.sweat)
            occasionStep(after: 0.4) { [weak self] in self?.sway(amplitude: 0.07, speed: 60, duration: 3.5) }
            for at in [1.0, 2.6, 4.2] {
                occasionStep(after: at) { [weak self] in
                    guard let self else { return }
                    NotchMascotPlayEffects.magicSmoke(in: canvas, at: self.onOccasion(self.hand(toward: side)), radius: self.size * 0.25,
                                                      energy: NotchMascotPlay.Energy(red: 0.92, green: 0.97, blue: 1), count: 3)
                }
            }
            occasionStep(after: 5.0) { [weak self] in self?.react(.relax) }
        case .hot:
            length = 8.5
            NotchMascotOccasionArt.beach(in: canvas, left: onOccasion(CGPoint(x: feet.x - size, y: 0)).x,
                                         floor: onOccasion(CGPoint(x: 0, y: feet.y)).y, width: size * 2,
                                         sunAt: onOccasion(CGPoint(x: feet.x + side * size * 2.2, y: min(area.maxY - 40, feet.y + size * 3))),
                                         duration: length)
            react(.sweat)
            occasionStep(after: 1.0) { [weak self] in
                self?.tilt(-side * 1.45, for: 5.5)
                self?.react(.relax)
            }
            for at in [2.0, 3.5, 5.0] {
                occasionStep(after: at) { [weak self] in
                    guard let self else { return }
                    NotchMascotPlayEffects.float("~", in: canvas, at: self.onOccasion(self.head), size: max(9, self.size * 0.2),
                                                 color: NotchMascotRPGShapes.rgb(0x64B5F6), count: 1)
                }
            }
            occasionStep(after: 7.0) { [weak self] in self?.react(.sweat) }
        case .lowBattery:
            length = 9
            perform(.doze(length), toward: side)
            occasionStep(after: 0.3) { [weak self] in
                guard let self else { return }
                self.stroll(to: feet.x + side * self.size * 1.2, pace: 0.4)
            }
            occasionStep(after: 3.6) { [weak self] in
                guard let self else { return }
                NotchMascotOccasionArt.plugSign(in: canvas, at: self.onOccasion(self.hand(toward: side)), size: self.size * 0.9,
                                                duration: length - 3.6)
                self.react(.yawn)
            }
        case .charged:
            length = 4
            react(.flash)
            NotchMascotPlayEffects.lightning(in: canvas, around: onOccasion(figureCenter), radius: size * 0.9,
                                             energy: NotchMascotPlay.Energy(red: 0.5, green: 1, blue: 0.5))
            sound(.zap, pan: pan(feet.x))
            occasionStep(after: 0.5) { [weak self] in
                guard let self else { return }
                self.react(.celebrate)
                self.hop(dx: 0, dy: 820)
                NotchMascotPlayEffects.burst(.sparkles, in: canvas, at: self.onOccasion(self.head), size: self.size, energy: self.energy)
                sound(.chime, pan: self.pan(self.body.position.x))
            }
        case .offline:
            length = 20
            react(.confused)
            occasionStep(after: 1.2) { [weak self] in self?.react(.relax) }
            for at in stride(from: 2.0, to: length - 1, by: 2.4) {
                occasionStep(after: at) { [weak self] in
                    guard let self else { return }
                    sound(.bleep, pan: self.pan(self.body.position.x))
                    NotchMascotPlayEffects.float("♪", in: canvas, at: self.onOccasion(self.head), size: max(9, self.size * 0.2),
                                                 color: NotchMascotRPGShapes.rgb(0x8BC34A), count: 1)
                }
            }
            wear(occasion.costume, for: length)
        case .online:
            length = 3
            react(.perk)
            occasionStep(after: 0.4) { [weak self] in
                self?.react(.celebrate)
                self?.hop(dx: 0, dy: 620)
            }
        case .birthday:
            length = 10
            NotchMascotOccasionArt.garland(in: canvas, area: onOccasionRect(area), duration: length)
            NotchMascotOccasionArt.cake(in: canvas, x: onOccasion(CGPoint(x: onFloor(feet.x + side * size * 1.3), y: 0)).x,
                                        floor: onOccasion(CGPoint(x: 0, y: feet.y)).y, size: size * 0.7, duration: length)
            celebrate(on: canvas, for: length, fanfare: true)
            // It knows how many you turn when it knows the year you were born.
            if let age = NotchMascotSpecialDays.ageMarker(on: Date()) {
                occasionStep(after: 3) { [weak self] in self?.occasionMarker(age) }
            }
        case .halloween:
            length = 9
            NotchMascotOccasionArt.bats(in: canvas, area: onOccasionRect(area), count: 6, duration: 7)
            NotchMascotOccasionArt.pumpkin(in: canvas, x: onOccasion(CGPoint(x: onFloor(feet.x + side * size * 1.3), y: 0)).x,
                                           floor: onOccasion(CGPoint(x: 0, y: feet.y)).y, size: size * 0.7, duration: length)
            sound(.hoot, pan: pan(feet.x), after: 0.6)
            react(.peek)
            occasionStep(after: 1.6) { [weak self] in self?.react(.surprised) }
            occasionStep(after: 3.0) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.fly(.cookie, in: canvas, from: self.onOccasion(CGPoint(x: self.head.x + side * self.size * 1.5,
                                                                                              y: self.head.y + self.size)),
                                           to: self.onOccasion(self.head), duration: 0.7, side: max(14, self.size * 0.34),
                                           while: self.outingLasts)
            }
            occasionStep(after: 3.8) { [weak self] in self?.react(.celebrate) }
        case .christmas:
            length = 12
            NotchMascotOccasionArt.snow(in: canvas, area: onOccasionRect(area), count: 60, duration: length - 2)
            sound(.chime, pan: pan(feet.x), after: 0.4)
            react(.wave)
            occasionStep(after: 2.0) { [weak self] in self?.react(.love) }
            occasionStep(after: 4.0) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.burst(.sparkles, in: canvas, at: self.onOccasion(self.head), size: self.size, energy: self.energy)
                self.react(.celebrate)
            }
        case .newYear:
            length = 9
            NotchMascotOccasionArt.fireworks(in: canvas, area: onOccasionRect(area), duration: 8)
            for at in stride(from: 0.4, to: 7.5, by: 0.9) {
                sound(.boom, pan: Float.random(in: -0.8...0.8), after: at)
            }
            celebrate(on: canvas, for: length, fanfare: false)
        case .aprilFools:
            length = 8
            upsideDown = true
            host?.mascot.setUpsideDown(true)
            react(.confused)
            occasionStep(after: 1.0) { [weak self] in
                guard let self else { return }
                self.occasionMarker(NotchMascotSpecialDays.foolsCall(for: self.look.style))
                sound(.squeak, pan: self.pan(self.body.position.x))
            }
            occasionStep(after: 2.0) { [weak self] in
                guard let self else { return }
                self.stroll(to: feet.x + side * self.size * 2, pace: 0.8)
            }
            occasionStep(after: 6.0) { [weak self] in
                guard let self else { return }
                self.upsideDown = false
                self.host?.mascot.setUpsideDown(false)
                self.react(.lookAround)
            }
        }
        if occasion != .aprilFools {
            occasionStep(after: 0.3) { [weak self] in self?.occasionMarker(occasion.marker) }
        }
        finishOccasion(after: length)
        return true
    }
    private func onOccasionRect(_ rect: CGRect) -> CGRect {
        let origin = onOccasion(rect.origin)
        return CGRect(origin: origin, size: rect.size)
    }
    /// A party where it stands: confetti, hearts and a little fanfare.
    private func celebrate(on canvas: CALayer, for length: TimeInterval, fanfare: Bool) {
        react(.celebrate)
        if fanfare {
            for (index, at) in [0.3, 0.6, 0.9, 1.4].enumerated() {
                sound(index == 3 ? .magic : .chime, pan: pan(body.position.x), after: at)
            }
        }
        for at in stride(from: 0.6, to: length - 2, by: 2.2) {
            occasionStep(after: at) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.burst(.confetti, in: canvas, at: self.onOccasion(self.head), size: self.size * 1.2,
                                             energy: self.energy)
                self.hop(dx: 0, dy: 520)
            }
        }
        occasionStep(after: length - 1.5) { [weak self] in self?.react(.love) }
    }
    // Dancing alone.
    private func maybeDanceSolo() -> Bool {
        let moves = NotchMascotSoloDance.moves(for: look.style)
        let now = CACurrentMediaTime()
        guard !moves.isEmpty, !isDozing,
              NotchMascotSoloDance.shouldStart(since: now - lastSolo, random: Double.random(in: 0..<1))
        else { return false }
        lastSolo = now
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0) ?? .null)
        if idle >= NotchMascotSoloDance.restAfterIdle, NotchMascotSoloDance.restsWithIce(look.style), Bool.random() {
            restWithIce()
        } else if let move = moves.randomElement() {
            dance(move)
        }
        return true
    }
    /// After a long rehearsal it sits with an ice pack, sighing; getting up,
    /// its knees crack.
    private func restWithIce() {
        guard beginOccasion(.dance) != nil else { return }
        wear(.icePack, for: 14)
        react(.relax)
        occasionMarker("AHH...")
        occasionStep(after: 6) { [weak self] in self?.react(.hush) }
        occasionStep(after: 14) { [weak self] in
            guard let self else { return }
            self.occasionMarker("CRACK!")
            sound(.crunch, pan: self.pan(self.body.position.x))
            self.react(.sweat)
        }
        finishOccasion(after: 16)
    }
    /// One of its own moves: rosin first before a great jump; turns on a
    /// window's glass without it slip.
    func dance(_ move: NotchMascotSoloDance) {
        guard let canvas = beginOccasion(.dance) else { return }
        let way = roomier
        let rosined = CACurrentMediaTime() < rosinUntil
        if move.turns, perch != nil, !rosined {
            slip()
            return
        }
        let start = move.leaps && !rosined && perch == nil ? rosin(on: canvas, toward: way) : 0
        occasionStep(after: start) { [weak self] in
            guard let self else { return }
            self.occasionMarker(move.marker)
            sound(Self.cue(for: move), pan: self.pan(self.body.position.x))
            self.perform(move, toward: way, on: canvas)
        }
        finishOccasion(after: start + move.length)
    }
    /// The sound a move opens with: a chime on stage, a spell for the fox,
    /// a honk for the penguin, a bleep for the hologram and a zap for the android.
    private static func cue(for move: NotchMascotSoloDance) -> NotchMascotSoundEffect {
        switch move {
        case .foxfire, .leafTrick: return .magic
        case .pounce: return .whoosh
        case .bellySlide, .flightAttempt, .pebbleGift: return .honk
        case .phaseShift, .glitch, .greeting: return .bleep
        case .scan, .boost, .recharge: return .zap
        case .coffeeSip: return .slurp
        case .eureka: return .chime
        case .imLate, .bunnyHops: return .boing
        default: return .chime
        }
    }
    /// Steps into the rosin box beside it and grinds its feet in the
    /// crystals; the seconds that takes.
    private func rosin(on canvas: CALayer, toward way: CGFloat) -> TimeInterval {
        let boxX = onFloor(body.position.x + way * size * 1.4)
        let walk = walkTime(to: boxX, from: body.position.x, pace: 1.4)
        NotchMascotOccasionArt.rosinBox(in: canvas, x: onOccasion(CGPoint(x: boxX, y: 0)).x,
                                        floor: onOccasion(CGPoint(x: 0, y: body.position.y)).y, size: size * 0.9,
                                        duration: walk + 3.4)
        stroll(to: boxX, pace: 1.4)
        for (index, at) in [walk + 0.3, walk + 0.8, walk + 1.3].enumerated() {
            occasionStep(after: at) { [weak self] in
                guard let self else { return }
                sound(.crunch, pan: self.pan(boxX))
                NotchMascotPlayEffects.magicSmoke(in: canvas, at: self.onOccasion(self.body.position), radius: self.size * 0.3,
                                                  energy: NotchMascotPlay.Energy(red: 1, green: 0.97, blue: 0.88), count: 3)
                self.sway(amplitude: 0.08, speed: 40, duration: 0.4)
                if index == 0 { self.occasionMarker("CRUNCH") }
            }
        }
        rosinUntil = CACurrentMediaTime() + walk + 1.8 + NotchMascotSoloDance.rosinLasts
        return walk + 2.0
    }
    /// Turns on slippery glass without rosin: it loses its axis and sits down hard.
    private func slip() {
        host?.mascot.spin(turns: 0.5, duration: 0.4)
        occasionStep(after: 0.4) { [weak self] in
            guard let self else { return }
            self.tilt(-1.1, for: 1.4)
            self.react(.sweat)
            self.occasionMarker("OOPS!")
            sound(.splat, pan: self.pan(self.body.position.x))
        }
        occasionStep(after: 2.0) { [weak self] in self?.react(.confused) }
        finishOccasion(after: 3)
    }
    private func perform(_ move: NotchMascotSoloDance, toward way: CGFloat, on canvas: CALayer) {
        let mascot = host?.mascot
        switch move {
        case .bourree:
            let length = stroll(to: body.position.x + way * size * 2.5, pace: 2.8)
            sway(amplitude: 0.05, speed: 70, duration: max(1, length))
        case .portDeBras:
            sway(amplitude: 0.2, speed: 3.2, duration: 3.5)
            react(.love)
            NotchMascotPlayEffects.float("~", in: canvas, at: onOccasion(head), size: max(9, size * 0.22),
                                         color: NotchMascotRPGShapes.rgb(0xFFFFFF), count: 3)
        case .dyingSwan:
            tilt(-0.55, for: 2.6)
            occasionStep(after: 0.3) { [weak self] in self?.react(.hush) }
            occasionStep(after: 2.0) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.burst(.sparkles, in: canvas, at: self.onOccasion(self.head), size: self.size, energy: self.energy)
            }
            occasionStep(after: 2.9) { [weak self] in self?.react(.love) }
        case .arabesque:
            react(.ready)
            tilt(way * 0.45, for: 2.2)
            occasionStep(after: 2.2) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.burst(.sparkles, in: canvas, at: self.onOccasion(self.head), size: self.size, energy: self.energy)
            }
        case .fouettes:
            mascot?.spin(turns: 8, duration: 4)
            for at in [0.5, 1.5, 2.5, 3.5] { sound(.whoosh, pan: pan(body.position.x), after: at) }
            occasionStep(after: 4.0) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.burst(.confetti, in: canvas, at: self.onOccasion(self.head), size: self.size * 1.3,
                                             energy: NotchMascotPlay.Energy(red: 1, green: 0.84, blue: 0.3))
                self.react(.celebrate)
                sound(.magic, pan: self.pan(self.body.position.x))
            }
        case .grandJete:
            hop(dx: way * 460, dy: 860)
            tilt(-way * 0.3, for: 0.7)
            occasionStep(after: 1.2) { [weak self] in self?.react(.celebrate) }
        case .reverence:
            tilt(way * 0.45, for: 1.6)
            react(.love)
            NotchMascotPlayEffects.burst(.hearts, in: canvas, at: onOccasion(head), size: size, energy: energy)
        case .pirouettes:
            mascot?.spin(turns: 6, duration: 4.5)
            for at in [0.6, 1.8, 3.0, 4.0] { sound(.whoosh, pan: pan(body.position.x), after: at) }
            occasionStep(after: 4.6) { [weak self] in
                self?.tilt(way * 0.35, for: 1.3)
                self?.react(.love)
            }
        case .sautDeBasque:
            hop(dx: way * 380, dy: 820)
            mascot?.spin(turns: 2, duration: 0.75)
        case .doubleTour:
            hop(dx: 0, dy: 950)
            mascot?.spin(turns: 2, duration: 0.75)
            occasionStep(after: 1.1) { [weak self] in self?.react(.ready) }
        case .cabriole:
            hop(dx: way * 320, dy: 800)
            sound(.clash, pan: pan(body.position.x), after: 0.3)
        case .floorwork:
            tilt(way * 1.5, for: 2.4)
            occasionStep(after: 0.3) { [weak self] in
                guard let self else { return }
                self.stroll(to: self.body.position.x + way * self.size * 1.5, pace: 1.2)
            }
            occasionStep(after: 1.0) { mascot?.spin(turns: way > 0 ? -1 : 1, duration: 1.2) }
            occasionStep(after: 2.6) { [weak self] in self?.react(.relax) }
        case .contractRelease:
            tilt(0.3, for: 0.7)
            sound(.whoosh, pan: pan(body.position.x))
            occasionStep(after: 0.8) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.burst(.magic, in: canvas, at: self.onOccasion(self.head), size: self.size, energy: self.energy)
                self.react(.celebrate)
                self.hop(dx: 0, dy: 420)
            }
        case .fallRecovery:
            tilt(way * 0.75, for: 1.0)
            occasionStep(after: 1.0) { [weak self] in
                self?.hop(dx: -way * 120, dy: 420)
                self?.react(.bounce)
            }
        case .handstand:
            hop(dx: 0, dy: 300)
            occasionStep(after: 0.3) { [weak self] in
                self?.upsideDown = true
                mascot?.setUpsideDown(true)
            }
            occasionStep(after: 2.6) { [weak self] in
                self?.upsideDown = false
                mascot?.setUpsideDown(false)
                self?.react(.celebrate)
            }
        case .foxfire:
            // Its tails fan, two blue wisps light beside it and circle up.
            react(.ready)
            for (index, at) in [0.3, 1.4, 2.5].enumerated() {
                occasionStep(after: at) { [weak self] in
                    guard let self else { return }
                    self.host?.mascot.foxfire(for: 1.2)
                    NotchMascotPlayEffects.magicSmoke(in: canvas, at: self.onOccasion(self.head), radius: self.size * 0.35,
                                                      energy: self.energy, count: 4)
                    sound(.fire, pan: self.pan(self.body.position.x))
                    if index == 2 { self.react(.celebrate) }
                }
            }
            sway(amplitude: 0.06, speed: 4, duration: 3.6)
        case .pounce:
            // A fox hunting under snow: it listens, crouches, leaps high
            // and dives nose first.
            react(.peek)
            occasionStep(after: 0.7) { [weak self] in
                guard let self else { return }
                self.tilt(-way * 0.2, for: 0.4)
                self.hop(dx: way * 220, dy: 900)
            }
            occasionStep(after: 1.2) { [weak self] in self?.tilt(way * 1.2, for: 0.6) }
            occasionStep(after: 1.9) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.magicSmoke(in: canvas, at: self.onOccasion(self.body.position), radius: self.size * 0.4,
                                                  energy: NotchMascotPlay.Energy(red: 1, green: 1, blue: 1), count: 6)
                sound(.thud, pan: self.pan(self.body.position.x))
                self.react(.celebrate)
            }
        case .leafTrick:
            // A leaf on its head, a puff of smoke, a spin: and it is itself again.
            react(.perk)
            occasionStep(after: 0.8) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.float("~", in: canvas, at: self.onOccasion(self.head), size: max(9, self.size * 0.24),
                                             color: NotchMascotRPGShapes.rgb(0x6BCB5A), count: 1)
            }
            occasionStep(after: 1.4) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.burst(.smoke, in: canvas, at: self.onOccasion(self.head), size: self.size * 1.3,
                                             energy: self.energy)
                sound(.poof, pan: self.pan(self.body.position.x))
                mascot?.spin(turns: 1, duration: 0.6)
            }
            occasionStep(after: 2.3) { [weak self] in self?.react(.surprised) }
            occasionStep(after: 3.0) { [weak self] in self?.react(.love) }
        case .bellySlide:
            // Flops onto its belly and toboggans along, flippers out.
            react(.ready)
            occasionStep(after: 0.4) { [weak self] in
                guard let self else { return }
                self.tilt(way * 1.35, for: 2.6)
                self.stroll(to: self.body.position.x + way * self.size * 3.2, pace: 3.2)
                sound(.whoosh, pan: self.pan(self.body.position.x))
            }
            occasionStep(after: 1.6) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.burst(.sparkles, in: canvas, at: self.onOccasion(self.body.position), size: self.size,
                                             energy: self.energy)
            }
            occasionStep(after: 3.2) { [weak self] in self?.react(.celebrate) }
        case .flightAttempt:
            // Three hops, flapping as hard as it can; it looks at the sky and sighs.
            for (index, at) in [0.2, 1.0, 1.8].enumerated() {
                occasionStep(after: at) { [weak self] in
                    guard let self else { return }
                    self.react(.bounce)
                    self.hop(dx: 0, dy: 380 + CGFloat(index) * 120)
                }
            }
            occasionStep(after: 2.8) { [weak self] in
                guard let self else { return }
                self.react(.sweat)
                self.occasionMarker("...")
            }
            occasionStep(after: 3.6) { [weak self] in self?.react(.confused) }
        case .pebbleGift:
            // Penguins court with the best pebble they can find.
            react(.peek)
            occasionStep(after: 0.8) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.float("o", in: canvas, at: self.onOccasion(self.head), size: max(9, self.size * 0.24),
                                             color: NotchMascotRPGShapes.rgb(0x9AA0A6), count: 1)
                sound(.pop, pan: self.pan(self.body.position.x))
            }
            occasionStep(after: 1.6) { [weak self] in
                guard let self else { return }
                self.tilt(way * 0.4, for: 1.0)
                self.react(.love)
                NotchMascotPlayEffects.burst(.hearts, in: canvas, at: self.onOccasion(self.head), size: self.size,
                                             energy: self.energy)
            }
        case .phaseShift:
            // The projection cuts out, and while it is dark she runs on; she
            // lights up again further along.
            mascot?.phase(for: 1.6)
            NotchMascotPlayEffects.burst(.sparkles, in: canvas, at: onOccasion(head), size: size, energy: energy)
            occasionStep(after: 0.4) { [weak self] in
                guard let self else { return }
                self.stroll(to: self.body.position.x + way * self.size * 3, pace: 4)
            }
            occasionStep(after: 1.6) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.burst(.sparkles, in: canvas, at: self.onOccasion(self.head), size: self.size,
                                             energy: self.energy)
                self.react(.perk)
            }
        case .glitch:
            // A bad signal: she shakes, breaks up and comes back clear.
            mascot?.phase(for: 0.9)
            sway(amplitude: 0.12, speed: 60, duration: 0.9)
            occasionStep(after: 0.5) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.burst(.magic, in: canvas, at: self.onOccasion(self.head), size: self.size,
                                             energy: self.energy)
                sound(.zap, pan: self.pan(self.body.position.x))
            }
            occasionStep(after: 1.3) { [weak self] in self?.react(.confused) }
            occasionStep(after: 2.1) { [weak self] in self?.react(.love) }
        case .greeting:
            // A message for you: she waves, then sends a heart.
            react(.wave)
            occasionStep(after: 1.4) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.burst(.hearts, in: canvas, at: self.onOccasion(self.head), size: self.size,
                                             energy: self.energy)
                self.react(.love)
            }
        case .scan:
            // It looks over the windows one way and the other, and finds
            // everything in order.
            react(.peek)
            tilt(way * 0.25, for: 1.2)
            occasionStep(after: 1.4) { [weak self] in
                guard let self else { return }
                self.tilt(-way * 0.25, for: 1.2)
                sound(.bleep, pan: self.pan(self.body.position.x))
            }
            occasionStep(after: 2.8) { [weak self] in
                guard let self else { return }
                sound(.bleep, pan: self.pan(self.body.position.x))
                self.occasionMarker("ALL OK")
                self.react(.ready)
            }
        case .boost:
            // Its jet flares, it shoots up and comes down soft.
            react(.ready)
            occasionStep(after: 0.4) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.magicSmoke(in: canvas, at: self.onOccasion(self.body.position), radius: self.size * 0.4,
                                                  energy: self.energy, count: 6)
                sound(.whoosh, pan: self.pan(self.body.position.x))
                self.hop(dx: way * 160, dy: 1000)
            }
            occasionStep(after: 2.2) { [weak self] in self?.react(.celebrate) }
        case .recharge:
            // It powers down a moment while its gauge fills, cell by cell.
            react(.relax)
            mascot?.charge(for: 3.4)
            for (index, at) in [0.9, 1.75, 2.6, 3.4].enumerated() {
                occasionStep(after: at) { [weak self] in
                    guard let self else { return }
                    sound(.bleep, pan: self.pan(self.body.position.x))
                    if index == 3 {
                        self.occasionMarker("FULL!")
                        NotchMascotPlayEffects.burst(.sparkles, in: canvas, at: self.onOccasion(self.head), size: self.size,
                                                     energy: self.energy)
                        self.react(.perk)
                    }
                }
            }
        case .coffeeSip:
            // A long sip from the mug he never puts down, and a happy sigh.
            react(.sip)
            occasionStep(after: 1.2) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.float("~", in: canvas, at: self.onOccasion(self.head), size: max(9, self.size * 0.22),
                                             color: NotchMascotRPGShapes.rgb(0xFFFFFF), count: 3)
            }
            occasionStep(after: 2.4) { [weak self] in self?.react(.relax) }
        case .eureka:
            // He stops, thinks, and has it: up he jumps.
            react(.lookAround)
            occasionStep(after: 1.0) { [weak self] in
                guard let self else { return }
                NotchMascotPlayEffects.burst(.sparkles, in: canvas, at: self.onOccasion(self.head), size: self.size,
                                             energy: self.energy)
                self.react(.perk)
                self.hop(dx: 0, dy: 560)
            }
            occasionStep(after: 2.2) { [weak self] in self?.react(.celebrate) }
        case .imLate:
            // It is late, it is late: off it dashes, and back again.
            react(.surprised)
            occasionStep(after: 0.5) { [weak self] in
                guard let self else { return }
                self.react(.sweat)
                self.stroll(to: self.body.position.x + way * self.size * 3, pace: 3.6)
            }
            occasionStep(after: 2.2) { [weak self] in
                guard let self else { return }
                self.stroll(to: self.body.position.x - way * self.size * 3, pace: 3.6)
            }
            occasionStep(after: 3.6) { [weak self] in self?.react(.confused) }
        case .bunnyHops:
            // Three hops, each a little higher.
            for (index, at) in [0.2, 1.0, 1.8].enumerated() {
                occasionStep(after: at) { [weak self] in
                    guard let self else { return }
                    self.react(.bounce)
                    self.hop(dx: way * 90, dy: 420 + CGFloat(index) * 140)
                }
            }
            occasionStep(after: 2.9) { [weak self] in self?.react(.love) }
        }
    }
    /// With fresh rosin, its steps leave little white prints that fade.
    private func leaveFootprint() {
        guard CACurrentMediaTime() < rosinUntil, perch == nil else { lastPrintX = nil; return }
        let x = body.position.x
        guard abs(x - (lastPrintX ?? -.infinity)) >= size * 0.3, let canvas = occasionCanvas() else { return }
        lastPrintX = x
        NotchMascotOccasionArt.footprint(in: canvas, at: onOccasion(CGPoint(x: x, y: body.position.y + 1)), size: size,
                                         duration: 3)
    }
    // MARK: Playing

    /// Free to play: out, standing on the floor on its own and not held.
    var isFree: Bool {
        isOut && mode == .standing && press == nil && !inPlay && !body.airborne && perch == nil && peekDepth == 0
            && !usingItem && !inEncounter && occasion == nil
    }
    var isDozing: Bool { napping || host?.mascot.isDozing == true }
    var playLook: NotchMascotLook { look }
    var figureSize: CGFloat { size }
    /// Its middle on screen.
    var screenCenter: CGPoint { figureCenter }
    /// The screen it is on.
    var playScreen: NSScreen? { screen(for: body.position) }
    /// Where its feet may go along the floor.
    var floor: ClosedRange<CGFloat> {
        let area = self.area(for: body.position)
        let half = size * figureAspect / 2
        return (area.minX + half)...max(area.minX + half, area.maxX - half)
    }

    /// Its hand on screen, on the side toward `direction`.
    func hand(toward direction: CGFloat) -> CGPoint {
        CGPoint(x: body.position.x + (direction > 0 ? 1 : -1) * size * figureAspect * 0.34,
                y: body.position.y + size * 0.42)
    }

    /// Just over its head, on screen.
    var head: CGPoint { CGPoint(x: body.position.x, y: body.position.y + size * 1.02) }

    /// What it holds and what floats off it are drawn here, in its window's
    /// points, y up; `local(_:)` turns a screen point into them.
    var effects: CALayer? { stage?.effects.canvas }

    func local(_ point: CGPoint) -> CGPoint {
        guard let panel else { return point }
        return CGPoint(x: point.x - panel.frame.minX, y: point.y - panel.frame.minY)
    }

    /// It stops what it was doing for a play.
    func beginPlay() {
        guard isOut else { return }
        inPlay = true
        planWork?.cancel(); planWork = nil
        cancelWindowPlans()
        cancelItemUse()
        endOccasion()
        if isWalking {
            setRun(nil)
            mode = .standing
        }
        watching = false
    }

    /// The play is over: it wakes if it napped and goes on with its own
    /// life `delay` seconds from now.
    func endPlay(after delay: TimeInterval) {
        guard inPlay else { return }
        inPlay = false
        pace = 1
        if napping { setNapping(false) }
        stage?.effects.clear()
        host?.mascot.lookAhead(after: 0.3)
        if isOut, mode == .standing { planNext(after: delay) }
    }

    /// Walks to `x` along the floor at `pace` times its walking pace, and
    /// says how long that takes.
    @discardableResult
    func stroll(to x: CGFloat, pace: CGFloat = 1) -> TimeInterval {
        guard isOut, !isHoming, press == nil, !body.airborne, !holdsStill else { return 0 }
        let floor = self.floor
        let target = min(floor.upperBound, max(floor.lowerBound, x))
        let distance = target - body.position.x
        guard abs(distance) > 2 else { return 0 }
        planWork?.cancel(); planWork = nil
        self.pace = max(0.2, pace)
        let duration = TimeInterval(abs(distance) / (NotchMascotRoam.walkSpeed * self.pace))
        let direction: CGFloat = distance > 0 ? 1 : -1
        mode = .walking(direction: direction, until: CACurrentMediaTime() + duration)
        setRun(direction)
        resumeTicking()
        return duration
    }

    /// A hop of its own, `dx` and `dy` points a second.
    func hop(dx: CGFloat, dy: CGFloat) {
        guard isOut, !isHoming, press == nil, !holdsStill else { return }
        if isWalking { setRun(nil) }
        body.velocity = CGVector(dx: dx, dy: dy)
        body.airborne = true
        thrown = false
        dropped = false
        mode = .flying
        resumeTicking()
    }

    /// Its eyes turn toward screen point `x`.
    func face(toward x: CGFloat) {
        guard let host else { return }
        host.mascot.attend(to: CGPoint(x: (x >= body.position.x ? 1 : -1) * 0.08, y: 0))
    }

    /// Dozes off, or wakes, for a nap together.
    func setNapping(_ asleep: Bool) {
        guard let host, napping != asleep else { return }
        napping = asleep
        host.mascot.setMood(asleep ? .sleepy : .idle, animated: !reduceMotion)
    }

    /// Sways side to side for `duration`, fading out: wide and quick for a
    /// spin, small and fast for a shiver.
    func sway(amplitude: CGFloat, speed: Double, duration: TimeInterval) {
        guard isOut, host != nil, !reduceMotion else { return }
        swayTimer?.cancel()
        let start = CACurrentMediaTime()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            guard let self, self.isOut else {
                timer.cancel()
                return
            }
            let elapsed = CACurrentMediaTime() - start
            guard elapsed < duration else {
                timer.cancel()
                self.swayTimer = nil
                self.host?.mascot.lean(0)
                return
            }
            let fade = CGFloat(1 - elapsed / duration)
            self.host?.mascot.lean(amplitude * fade * CGFloat(sin(elapsed * speed)))
        }
        swayTimer = timer
        timer.resume()
    }
    /// Leans `angle` and holds it for `duration`, as for a bow.
    func tilt(_ angle: CGFloat, for duration: TimeInterval) {
        guard isOut, let host else { return }
        host.mascot.lean(angle)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in self?.host?.mascot.lean(0) }
    }
    /// Bobs to the music while it plays.
    func setDancing(_ dancing: Bool) {
        guard let host else { return }
        let dances = dancing && isOut && !reduceMotion
        if host.dances != dances { host.dances = dances }
    }

    // MARK: Going home

    private var isHoming: Bool {
        if case .homing = mode { return true }
        return false
    }

    /// Flies back up into the island, shrinking to its size there, and is
    /// in again once it lands. Without room there, it fades out and is in.
    func goHome() {
        guard isOut, !isHoming, let host else { return }
        cancelDizzy()
        if inPlay { interrupted?() }
        cancelPlans()
        cancelWindowPlans()
        cancelItemUse()
        endEncounter()
        endOccasion()
        perch = nil
        // It keeps what it put on for the flight home, but the timer stops:
        // back out, it wears what was chosen for it.
        dressUpWork?.cancel(); dressUpWork = nil; dressUpItem = nil
        press = nil
        setRun(nil)
        host.mascot.lean(0)
        guard let rest = restingPlace?(), !reduceMotion else {
            finishHome(fading: true)
            return
        }
        let from = figureCenter
        let distance = hypot(rest.center.x - from.x, rest.center.y - from.y)
        let duration = NotchMascotRoam.homeDuration(distance: distance)
        let toScale = rest.size / size
        mode = .homing(from: from, to: rest.center, began: CACurrentMediaTime(), duration: duration, fromScale: 1,
                       toScale: toScale)
        host.scale(from: 1, to: toScale, duration: duration, timing: CAMediaTimingFunction(name: .linear))
        host.mascot.react(.celebrate, lift: 0)
        resumeTicking()
    }

    /// Gone at once, as the island stops or the companion is switched off.
    func dismiss() {
        guard isOut else { return }
        outing += 1
        cancelDizzy()
        if inPlay { interrupted?() }
        cancelPlans()
        cancelWindowPlans()
        cancelItemUse()
        endEncounter()
        endOccasion()
        resetItemState()
        encounterStage?.close()
        occasionStage?.close()
        perch = nil
        // Whatever it had put on stays home: out again, it wears what was chosen.
        dressUpWork?.cancel(); dressUpWork = nil; dressUpItem = nil
        removeMonitors()
        invalidateTicking()
        panel?.orderOut(nil)
        isOut = false
        mode = .standing
    }

    private func finishHome(fading: Bool) {
        outing += 1
        let outing = self.outing
        cancelPlans()
        resetItemState()
        removeMonitors()
        invalidateTicking()
        mode = .standing
        // Dismissed while it fades, it is already in: nothing more to report.
        let landed = { [weak self] in
            guard let self, self.outing == outing else { return }
            self.invalidateTicking()
            self.panel?.orderOut(nil)
            self.isOut = false
            self.cameHome?(.happy)
        }
        guard fading, let panel, !reduceMotion else { landed(); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: landed)
    }

    // MARK: Ticking

    /// A small figure walking at a few dozen points a second looks no
    /// smoother above 60 frames, and each frame moves a window. Up to 72, a
    /// 144 Hz display runs at half its rate rather than a third.
    static let frameRates = CAFrameRateRange(minimum: 30, maximum: 72, preferred: 60)

    private func resumeTicking() {
        if displayLink == nil, let stage {
            let link = stage.displayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = Self.frameRates
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        if displayLink?.isPaused != false { lastTick = CACurrentMediaTime() }
        displayLink?.isPaused = false
    }

    private func stopTicking() {
        displayLink?.isPaused = true
    }

    /// In again, the link goes: it holds on to the companion while it lasts,
    /// and the next outing makes a new one.
    private func invalidateTicking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = now - lastTick
        lastTick = now
        switch mode {
        case .standing, .held:
            stopTicking()
        case .flying:
            fly(by: dt)
        case .walking(let direction, let until):
            walk(direction, until: until, by: dt, now: now)
        case .homing(let from, let to, let began, let duration, let fromScale, let toScale):
            let t = CGFloat(min(1, (now - began) / max(0.01, duration)))
            let scale = fromScale + (toScale - fromScale) * t
            placeFigure(center: NotchMascotRoam.homeArc(from: from, to: to, at: t), scale: scale)
            if t >= 1 { finishHome(fading: false) }
        }
    }

    private func fly(by dt: TimeInterval) {
        if body.airborne { checkTrampoline() }
        let area = self.area(for: body.position)
        let events = NotchMascotRoam.step(&body, by: dt, in: area, width: size * figureAspect,
                                          ledges: inPlay ? [] : currentLedges())
        place()
        if body.airborne, leaping { catchEdge() }
        if !body.airborne {
            // A leap ends where it was aimed, not sliding on past it.
            if leaping { body.velocity.dx = 0 }
            updatePerch()
        }
        if body.airborne {
            host?.mascot.lean(NotchMascotRoam.lean(forSpeed: body.velocity.dx))
            setRun(abs(body.velocity.dx) >= NotchMascotRoam.runSpeed ? body.velocity.dx : nil)
        }
        for event in events {
            switch event {
            case .landed(let impact):
                host?.mascot.land(impact: impact / 2000)
                host?.mascot.lean(0)
                if impact >= NotchMascotRoam.dizzySpeed { react(.confused); thrown = false; landedHard?() }
            case .bumped(let speed):
                host?.mascot.land(impact: speed / 3000)
                if speed >= NotchMascotRoam.dizzySpeed { react(.confused); thrown = false; landedHard?() }
            case .settled:
                bounces = 0
                dropped = false
                leapTarget = nil
                setRun(nil)
                host?.mascot.lean(0)
                mode = .standing
                if isDizzy {
                    stumbleDizzy()
                    return
                }
                if thrown { react(.wave) }
                // Up on the window it leapt for, it cheers.
                if leaping, perch != nil, !thrown { react(.celebrate) }
                leaping = false
                thrown = false
                planNext(after: 2)
                return
            }
        }
    }

    /// A leap that comes up a little short, past its peak and just under the
    /// edge it was aimed at, catches hold of it and pulls itself up.
    private func catchEdge() {
        guard let target = leapTarget, body.velocity.dy <= 0, body.position.y < target.y,
              body.position.y >= target.y - size * 0.5,
              let ledge = ledges.first(where: { $0.window == target.window && $0.holds(body.position.x) })
        else { return }
        body.position.y = ledge.y
        body.velocity = .zero
        body.airborne = false
        place()
        host?.mascot.land(impact: 0.1)
    }
    private func walk(_ direction: CGFloat, until: CFTimeInterval, by dt: TimeInterval, now: CFTimeInterval) {
        let area = self.area(for: body.position)
        let half = size * figureAspect / 2
        var direction = direction
        body.position.x += direction * NotchMascotRoam.walkSpeed * pace * CGFloat(min(dt, 0.05))
        // On a window it walks its top edge; on the floor, the screen's width.
        let walkway = perch == nil ? nil : perchLedge
        let low = walkway.map { $0.minX + half * 0.5 } ?? area.minX + half
        let high = walkway.map { $0.maxX - half * 0.5 } ?? area.maxX - half
        // At the end of the way it turns around, or jumps off when it meant to.
        if body.position.x <= low || body.position.x >= high {
            body.position.x = min(high, max(low, body.position.x))
            if leavesLedge, walkway != nil {
                leavesLedge = false
                setRun(nil)
                perch = nil
                hop(dx: direction * 210, dy: 430)
                return
            }
            direction = -direction
            setRun(direction)
            mode = .walking(direction: direction, until: until)
        }
        // The floor moved under it, as a Dock that shows or hides, or the
        // window it walks on went away.
        if perch == nil ? abs(body.position.y - area.minY) > 0.5 : walkway == nil {
            perch = nil
            body.airborne = true
            mode = .flying
        }
        place()
        leaveFootprint()
        // Up to its friend, it stops, and waves if they have not lately.
        if !inPlay, perch == nil, let other = neighbor?(),
           NotchMascotRoam.meets(walking: direction, from: body.position.x, friendX: other.x) {
            setRun(nil)
            mode = .standing
            if !greetIfNear() { planNext(after: 2) }
            return
        }
        if now >= until {
            setRun(nil)
            mode = .standing
            pace = 1
            planNext(after: 0)
        }
    }

    // MARK: On its own

    /// What it does next on its own, `delay` seconds from now. It stays put
    /// when told to, dozing, with Reduce Motion or in Low Power Mode.
    private func planNext(after delay: TimeInterval) {
        planWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.startActivity() }
        planWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startActivity() {
        planWork = nil
        guard isOut, mode == .standing, !inPlay, peekDepth == 0, climbWork == nil, !riding, !usingItem, !inEncounter,
              occasion == nil, let host
        else { return }
        if perch == nil, invitePlay?() == true { return }
        if perch == nil, greetIfNear() { return }
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        // Saving power, it does nothing of its own; with Reduce Motion,
        // nothing that leaps about.
        if !lowPower {
            if maybeEncounter() { return }
            if maybePlayDressUp() { return }
            if maybeUseItem() { return }
            if !reduceMotion, maybeDanceSolo() { return }
            if maybeCrave() { return }
            if maybeFish() { return }
            if !reduceMotion, maybeHideAndSeek() { return }
        }
        let still = staysPut || reduceMotion || lowPower || host.mascot.isDozing
        if !still, windowActivity() { return }
        let area = self.area(for: body.position)
        let half = size * figureAspect / 2
        let walkway = perch == nil ? nil : perchLedge
        let activity = NotchMascotRoam.nextActivity(x: body.position.x,
                                                    minX: walkway.map { $0.minX + half * 0.5 } ?? area.minX + half,
                                                    maxX: walkway.map { $0.maxX - half * 0.5 } ?? area.maxX - half,
                                                    friendX: perch == nil ? neighbor?()?.x : nil,
                                                    random: { Double.random(in: 0..<1) })
        switch activity {
        case .stand(let length):
            planNext(after: length)
        case .lookAround:
            if !host.mascot.isDozing { react(.lookAround) }
            planNext(after: NotchMascotReaction.lookAround.length + 3)
        case .walk(let direction, let duration):
            guard !still, walkway.map({ $0.width > size * figureAspect + 12 }) ?? true else { planNext(after: 8); return }
            mode = .walking(direction: direction, until: CACurrentMediaTime() + duration)
            setRun(direction)
            resumeTicking()
        }
    }

    private func scheduleExcursionEnd() {
        excursionWork?.cancel()
        scheduleExcursionEnd(after: NotchMascotRoam.excursionLength(random: Double.random(in: 0..<1)))
    }

    private func scheduleExcursionEnd(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isOut else { return }
            // In the air just then, it goes home once it has landed.
            guard self.mode == .standing || self.isWalking else {
                self.scheduleExcursionEnd(after: 5)
                return
            }
            self.goHome()
        }
        excursionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private var isWalking: Bool {
        if case .walking = mode { return true }
        return false
    }

    private func cancelPlans() {
        planWork?.cancel(); planWork = nil
        excursionWork?.cancel(); excursionWork = nil
    }

    private func setRun(_ direction: CGFloat?) {
        let wanted = direction.map { $0 > 0 ? CGFloat(1) : CGFloat(-1) }
        guard wanted != runDirection else { return }
        runDirection = wanted
        host?.mascot.setStride(toward: wanted)
    }

    // MARK: Windows

    private var climbsWindows: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.notchMascotClimbsWindows) }

    /// The tops of the other apps' windows, read again when older than `maxAge`.
    private func currentLedges(maxAge: CFTimeInterval = 0.2) -> [NotchMascotLedges.Ledge] {
        guard climbsWindows else {
            ledges = []
            return ledges
        }
        let now = CACurrentMediaTime()
        guard now - ledgesRead > maxAge else { return ledges }
        ledgesRead = now
        let windows = NotchMascotWindowReader.windows()
        windowFrames = Dictionary(windows.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        ledges = NotchMascotLedges.ledges(in: windows, areas: NSScreen.screens.map(\.visibleFrame), headroom: size * 0.8)
        return ledges
    }

    /// The stretch of the window it stands on under its feet.
    private var perchLedge: NotchMascotLedges.Ledge? {
        guard let perch else { return nil }
        return ledges.first { $0.window == perch.window && $0.holds(body.position.x) }
    }

    /// On its feet, it notes the window it stands on, or the floor.
    private func updatePerch() {
        let area = self.area(for: body.position)
        if body.position.y > area.minY + 0.5,
           let ledge = NotchMascotLedges.ledge(under: body.position, in: ledges),
           let frame = windowFrames[ledge.window] {
            if perch?.window != ledge.window { perch = (ledge.window, frame) }
        } else {
            perch = nil
        }
        updateWindowWatch()
    }

    /// Standing on a window it watches that window, closely while it may be
    /// dragged, to ride along; on the floor it looks only while a window may
    /// be dragged up beside it.
    private func updateWindowWatch() {
        let wanted = !isOut ? 0
            : NotchMascotLedges.watchInterval(climbs: climbsWindows, perched: perch != nil, riding: riding,
                                              pressed: buttonHeld,
                                              lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        guard wanted != watchInterval else { return }
        watchInterval = wanted
        watchTimer?.cancel(); watchTimer = nil
        guard wanted > 0 else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(wanted), repeating: .milliseconds(wanted),
                       leeway: .milliseconds(wanted / 4))
        timer.setEventHandler { [weak self] in self?.watchWindows() }
        watchTimer = timer
        timer.resume()
    }

    private func watchWindows() {
        guard isOut, !isHoming else { return }
        guard climbsWindows else {
            if perch != nil, !body.airborne { loseFooting() }
            updateWindowWatch()
            return
        }
        if let perch {
            follow(perch)
        } else {
            lookForRides()
        }
    }

    /// Rides the window it stands on as it moves, and falls when it closes,
    /// hides, goes behind another window or leaves no room to stand.
    private func follow(_ current: (window: CGWindowID, frame: CGRect)) {
        guard press == nil, mode != .held, !body.airborne else { return }
        guard let frame = NotchMascotWindowReader.frame(of: current.window) else {
            loseFooting()
            return
        }
        let now = CACurrentMediaTime()
        if frame != current.frame {
            let dx = frame.minX - current.frame.minX
            perch = (current.window, frame)
            body.position.x += dx
            body.position.y += frame.maxY - current.frame.maxY
            if !riding {
                riding = true
                updateWindowWatch()
                endPeek()
                leavesLedge = false
                planWork?.cancel(); planWork = nil
                if isWalking {
                    setRun(nil)
                    mode = .standing
                }
                host?.mascot.react(.surprised, lift: 0)
            }
            rideMoved = now
            host?.mascot.lean(NotchMascotRoam.lean(forSpeed: dx * 30))
            place()
            return
        }
        if riding {
            // The window came to rest: it straightens up, glad of the ride.
            guard now - rideMoved > 0.3 else { return }
            riding = false
            updateWindowWatch()
            host?.mascot.lean(0)
            ledgesRead = -.infinity
            if mode == .standing {
                react(.celebrate)
                planNext(after: NotchMascotReaction.celebrate.length + 2)
            }
        }
        let ledges = currentLedges(maxAge: 0.4)
        guard let under = ledges.first(where: { $0.window == current.window && $0.holds(body.position.x) }) else {
            loseFooting()
            return
        }
        // Its feet stay on the edge, never a hair above it in the air.
        if peekDepth == 0, abs(body.position.y - under.y) > 1 {
            body.position.y = under.y
            place()
        }
    }

    /// The window under it is gone: it drops.
    private func loseFooting() {
        perch = nil
        riding = false
        endPeek()
        leavesLedge = false
        host?.mascot.lean(0)
        updateWindowWatch()
        guard isOut, press == nil, !isHoming else { return }
        planWork?.cancel(); planWork = nil
        setRun(nil)
        body.airborne = true
        body.velocity = CGVector(dx: 0, dy: 80)
        mode = .flying
        react(.surprised)
        resumeTicking()
    }

    /// A window dragged up close beside it is a ride: it jumps on.
    private func lookForRides() {
        guard mode == .standing || isWalking, press == nil, !inPlay, !body.airborne, !isDozing, !staysPut,
              !reduceMotion, climbWork == nil, CACurrentMediaTime() - lastHitch > 6
        else { return }
        // Not looked at for a while, the windows' last places are no baseline:
        // this look only takes them, and the next one sees what moves.
        let stale = CACurrentMediaTime() - ledgesRead > 0.6
        let before = windowFrames
        let ledges = currentLedges(maxAge: 0)
        guard !stale else { return }
        let feet = body.position
        for (id, frame) in windowFrames {
            guard let old = before[id], NotchMascotLedges.hitchable(old: old, new: frame, feet: feet, figure: size),
                  let ledge = ledges.filter({ $0.window == id }).min(by: {
                      NotchMascotLedges.distance(from: feet.x, to: $0) < NotchMascotLedges.distance(from: feet.x, to: $1)
                  })
            else { continue }
            lastHitch = CACurrentMediaTime()
            leap(to: ledge, eager: true)
            return
        }
    }

    /// Something to do with the windows, if it feels like it: up onto one
    /// from the floor; on one, hide behind it, look at what it shows, jump
    /// across to another or down. True when it does.
    private func windowActivity() -> Bool {
        guard climbsWindows else { return false }
        let roll = Double.random(in: 0..<1)
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let width = size * figureAspect + 24
        guard let ledge = perchLedge else {
            guard perch == nil, roll < 0.24,
                  let target = NotchMascotLedges.climbTarget(from: body.position, in: currentLedges(maxAge: 0),
                                                             standingOn: nil, preferring: front, minimumWidth: width,
                                                             random: { Double.random(in: 0..<1) })
            else { return false }
            leap(to: target)
            return true
        }
        if roll < 0.16 {
            hideBehind()
            return true
        }
        if roll < 0.28 {
            jumpOff(ledge)
            return true
        }
        if roll < 0.36, let target = NotchMascotLedges.climbTarget(from: body.position, in: currentLedges(maxAge: 0),
                                                                    standingOn: ledge.window, preferring: front,
                                                                    minimumWidth: width,
                                                                    random: { Double.random(in: 0..<1) }) {
            leap(to: target)
            return true
        }
        if roll < 0.52, let kind = NotchMascotLedges.kind(of: NSRunningApplication(processIdentifier: ledge.pid)?.bundleIdentifier) {
            watchApp(kind)
            return true
        }
        return false
    }

    /// Sitting on the app's window, it takes an interest in what is under it.
    private func watchApp(_ kind: NotchMascotLedges.AppKind) {
        guard let host else { return }
        switch kind {
        case .browser, .code, .files, .design:
            // It leans over the edge to read along.
            let side: CGFloat = Bool.random() ? 1 : -1
            host.attend(toScreenPoint: CGPoint(x: body.position.x + side * size, y: body.position.y - size * 2))
            host.mascot.lookAhead(after: 3.5)
            planNext(after: 5)
        case .video:
            react(.relax)
            planNext(after: NotchMascotReaction.relax.length + 6)
        case .music:
            react(.groove)
            planNext(after: NotchMascotReaction.groove.length + 3)
        case .chat, .game:
            react(NotchMascotLedges.reaction(to: kind))
            planNext(after: NotchMascotReaction.wave.length + 3)
        }
    }

    /// Leaps up onto `ledge`, after a look and a crouch.
    private func leap(to ledge: NotchMascotLedges.Ledge, eager: Bool = false) {
        guard isOut, !isHoming, press == nil, !inPlay else { return }
        endPeek()
        planWork?.cancel(); planWork = nil
        if isWalking {
            setRun(nil)
            mode = .standing
        }
        let half = size * figureAspect / 2
        let target = CGPoint(x: NotchMascotLedges.spot(on: ledge, from: body.position.x, margin: half + 8,
                                                       jitter: CGFloat.random(in: -1...1)),
                             y: ledge.y)
        host?.attend(toScreenPoint: CGPoint(x: target.x, y: target.y + size / 2))
        react(.perk)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.climbWork = nil
            guard self.isOut, self.mode == .standing, self.press == nil, !self.inPlay else { return }
            // Reduce Motion came on meanwhile: it stays where it is and thinks again.
            guard !self.holdsStill else {
                self.planNext(after: 2)
                return
            }
            let velocity = NotchMascotLedges.leap(from: self.body.position, to: target,
                                                  gravity: NotchMascotRoam.gravity, drag: NotchMascotRoam.airDrag)
            self.perch = nil
            self.leaping = true
            self.leapTarget = (ledge.window, ledge.y)
            self.hop(dx: velocity.dx, dy: velocity.dy)
        }
        climbWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (eager ? 0.25 : 0.6), execute: work)
    }

    /// Walks to the nearer end of the window it stands on and jumps down.
    private func jumpOff(_ ledge: NotchMascotLedges.Ledge) {
        let toward: CGFloat = body.position.x - ledge.minX < ledge.maxX - body.position.x ? -1 : 1
        leavesLedge = true
        mode = .walking(direction: toward, until: CACurrentMediaTime() + 30)
        setRun(toward)
        resumeTicking()
    }

    /// Ducks down behind the window it stands on, peeks over its edge for a
    /// moment, eyes on the pointer, and pops back out.
    private func hideBehind() {
        guard perch != nil, let host, !host.mascot.isDozing else { return }
        setRun(nil)
        sink(to: size * 0.74, over: 0.35) { [weak self] in
            guard let self else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.peekWork = nil
                self?.popOut(surprised: false)
            }
            self.peekWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 1.8...4), execute: work)
        }
    }

    private func popOut(surprised: Bool) {
        guard peekDepth > 0 else { return }
        sink(to: 0, over: 0.2) { [weak self] in
            guard let self else { return }
            self.react(surprised ? .surprised : .wave)
            self.planNext(after: 3)
        }
    }

    /// Lowers it `depth` below the edge it stands on over `duration`.
    private func sink(to depth: CGFloat, over duration: TimeInterval, then done: @escaping () -> Void) {
        peekTimer?.cancel()
        let from = peekDepth, start = CACurrentMediaTime()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            guard let self, self.isOut, self.press == nil else {
                timer.cancel()
                return
            }
            let t = min(1, (CACurrentMediaTime() - start) / max(0.01, duration))
            let next = from + (depth - from) * CGFloat(t * t * (3 - 2 * t))
            self.body.position.y += self.peekDepth - next
            self.peekDepth = next
            self.place()
            guard t >= 1 else { return }
            timer.cancel()
            self.peekTimer = nil
            done()
        }
        peekTimer = timer
        timer.resume()
    }

    /// Back up on the edge at once, whatever it was hiding for.
    private func endPeek() {
        peekTimer?.cancel(); peekTimer = nil
        peekWork?.cancel(); peekWork = nil
        guard peekDepth > 0 else { return }
        body.position.y += peekDepth
        peekDepth = 0
        place()
    }

    private func cancelWindowPlans() {
        climbWork?.cancel(); climbWork = nil
        leavesLedge = false
        leaping = false
        leapTarget = nil
        endPeek()
    }

    /// Another app came to the front: it reacts to the kind of app, and now
    /// and then goes over and climbs onto its window.
    private func appCameToFront(bundleID: String?, pid: pid_t?) {
        guard isOut, climbsWindows, mode == .standing || isWalking, press == nil, !inPlay, !isHoming, !isDozing,
              peekDepth == 0, let pid, pid != ProcessInfo.processInfo.processIdentifier,
              let kind = NotchMascotLedges.kind(of: bundleID)
        else { return }
        let now = CACurrentMediaTime()
        guard now - lastAppReaction > 8 else { return }
        lastAppReaction = now
        if isWalking {
            setRun(nil)
            mode = .standing
        }
        react(NotchMascotLedges.reaction(to: kind))
        guard perchLedge?.pid != pid, !staysPut, !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled,
              climbWork == nil, Double.random(in: 0..<1) < 0.5
        else {
            planNext(after: 3)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isOut, self.mode == .standing, !self.inPlay else { return }
            self.planWork = nil
            guard let target = NotchMascotLedges.climbTarget(from: self.body.position, in: self.currentLedges(maxAge: 0),
                                                             standingOn: self.perch?.window, preferring: pid,
                                                             minimumWidth: self.size * self.figureAspect + 24,
                                                             random: { 0 }),
                  target.pid == pid
            else {
                self.planNext(after: 2)
                return
            }
            self.leap(to: target)
        }
        planWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    // MARK: Gestures

    fileprivate func pressBegan(at point: CGPoint, clicks: Int) {
        guard isOut, !isHoming else { return }
        lastTouched = CACurrentMediaTime()
        if clicks < 2, answerOccasion() { return }
        endOccasion()
        shakeTracker.reset()
        cancelDizzy()
        cancelWindowPlans()
        cancelItemUse()
        endEncounter()
        if inPlay { interrupted?() }
        // Played with, it is no longer on a walk of its own: it stays out.
        excursionWork?.cancel(); excursionWork = nil
        if clicks >= 2 { goHome(); return }
        planWork?.cancel(); planWork = nil
        setRun(nil)
        press = (point, CACurrentMediaTime(), 0)
        grabOffset = CGVector(dx: body.position.x - point.x, dy: body.position.y - point.y)
        samples.removeAll()
        NotchMascotRoam.record(.init(point: body.position, time: CACurrentMediaTime()), into: &samples)
        switch mode {
        // Caught in the air, it hangs there.
        case .flying: mode = .held
        // Stopped on a walk, it stands for the pat or the grab.
        case .walking: mode = .standing
        default: break
        }
    }

    fileprivate func pressMoved(to point: CGPoint) {
        guard isOut, !isHoming, var current = press else { return }
        let now = CACurrentMediaTime()
        let deltaX = point.x - current.point.x
        shakeTracker.track(deltaX: deltaX, time: now)
        current.moved = max(current.moved, hypot(point.x - current.point.x, point.y - current.point.y))
        current.point = point
        press = current
        guard mode == .held || current.moved >= NotchMascotRoam.tapSlop else { return }
        if mode != .held {
            mode = .held
            host?.mascot.react(.surprised, lift: 0)
        }
        if shakeTracker.isDizzy {
            host?.mascot.react(.confused, lift: 0)
        }
        body.position = clampedToScreens(CGPoint(x: point.x + grabOffset.dx, y: point.y + grabOffset.dy))
        body.velocity = .zero
        body.airborne = true
        NotchMascotRoam.record(.init(point: body.position, time: now), into: &samples)
        place()
        // It runs toward where it is pulled, and hangs still when held still.
        if let velocity = NotchMascotRoam.velocity(of: samples, at: now) {
            if abs(velocity.dx) >= NotchMascotRoam.runSpeed {
                setRun(velocity.dx)
            } else if abs(velocity.dx) < NotchMascotRoam.stillSpeed, abs(velocity.dy) < NotchMascotRoam.stillSpeed {
                setRun(nil)
            }
            host?.mascot.lean(NotchMascotRoam.lean(forSpeed: velocity.dx))
        }
    }

    fileprivate func pressEnded(at point: CGPoint) {
        guard isOut, !isHoming, let current = press else { return }
        press = nil
        let shaken = shakeTracker.isDizzy
        shakeTracker.reset()
        let now = CACurrentMediaTime()
        if mode != .held, NotchMascotRoam.isTap(held: now - current.time, moved: current.moved) {
            pat()
            planNext(after: 3)
            return
        }
        setRun(nil)
        if let rest = restingPlace?(), NotchMascotRoam.dropsHome(at: point, rest: rest.center, screenTop: rest.screenTop) {
            goHome()
            return
        }
        let velocity = NotchMascotRoam.velocity(of: samples, at: now) ?? .zero
        samples.removeAll()
        body.velocity = velocity
        body.airborne = true
        thrown = hypot(velocity.dx, velocity.dy) > 600
        dropped = true
        mode = .flying
        if shaken {
            isDizzy = true
            react(.confused)
        }
        resumeTicking()
    }

    /// A pat: a hop or a wave, never the same twice in a row, with the hearts
    /// and the bond's experience at most as often as a pat counts.
    private func pat() {
        guard let host else { return }
        let now = CACurrentMediaTime()
        guard now - lastPat >= 0.35 else { return }
        lastPat = now
        patFlip.toggle()
        host.mascot.wake(animated: true)
        react(patFlip ? .celebrate : .wave)
        patted?()
        if NotchSupport.usesHapticFeedback() {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        guard now - Self.lastPatCounted > NotchMascotGrowth.petInterval else { return }
        Self.lastPatCounted = now
        let gained = NotchMascotBondStore.shared.record(.petted, for: look.style)
        host.mascot.showPetted(gained: gained)
    }

    private func stumbleDizzy() {
        isDizzy = true
        cancelDizzy()
        react(.confused)
        if NotchSupport.usesHapticFeedback() {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        let start = CACurrentMediaTime()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(35))
        timer.setEventHandler { [weak self] in
            guard let self, self.isOut, self.isDizzy else {
                timer.cancel()
                return
            }
            let elapsed = CACurrentMediaTime() - start
            if elapsed >= 2.4 {
                timer.cancel()
                self.dizzyTimer = nil
                self.recoverFromDizzy()
                return
            }
            let decay = CGFloat(max(0, 1 - elapsed / 2.4))
            let wobble = sin(elapsed * 14) * 0.28 * decay
            self.host?.mascot.lean(wobble)
        }
        dizzyTimer = timer
        timer.resume()
    }

    private func recoverFromDizzy() {
        guard isDizzy else { return }
        isDizzy = false
        host?.mascot.lean(0)
        host?.mascot.wake(animated: true)
        react(.relax)
        planNext(after: 1.5)
    }

    private func cancelDizzy() {
        dizzyTimer?.cancel()
        dizzyTimer = nil
        isDizzy = false
    }

    fileprivate func menu() -> NSMenu {
        let text = FeatureStrings.notchMascotDesktop(L10n.shared.language)
        let menu = NSMenu()
        let shop = NSMenuItem(title: FeatureStrings.notchMascotShop(L10n.shared.language).title + "…",
                              action: #selector(menuShop), keyEquivalent: "")
        shop.target = self
        shop.image = NSImage(systemSymbolName: "bag", accessibilityDescription: nil)
        menu.addItem(shop)
        menu.addItem(gamesItem())
        menu.addItem(.separator())
        let home = NSMenuItem(title: text.goHome, action: #selector(menuGoHome), keyEquivalent: "")
        home.target = self
        menu.addItem(home)
        let stay = NSMenuItem(title: text.stayPut, action: #selector(menuStayPut), keyEquivalent: "")
        stay.target = self
        stay.state = staysPut ? .on : .off
        menu.addItem(stay)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: text.settings, action: #selector(menuSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        return menu
    }

    /// The games to play with it, under "Play".
    private func gamesItem() -> NSMenuItem {
        let games = FeatureStrings.notchMascotGames(L10n.shared.language)
        let item = NSMenuItem(title: games.play, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "gamecontroller", accessibilityDescription: nil)
        let menu = NSMenu()
        let roshambo = NSMenuItem(title: games.roshambo, action: nil, keyEquivalent: "")
        roshambo.image = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: nil)
        let picks = NSMenu()
        for (choice, title, symbol) in [(NotchMascotRoshambo.rock, games.rock, "circle.fill"),
                                        (.paper, games.paper, "doc"), (.scissors, games.scissors, "scissors")] {
            let pick = NSMenuItem(title: title, action: #selector(menuRoshambo(_:)), keyEquivalent: "")
            pick.target = self
            pick.representedObject = choice.rawValue
            pick.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            picks.addItem(pick)
        }
        roshambo.submenu = picks
        menu.addItem(roshambo)
        for (title, action, symbol) in [(games.laser, #selector(menuLaser), "light.max"),
                                        (games.fishing, #selector(menuFishing), "fish"),
                                        (games.hideAndSeek, #selector(menuHideAndSeek), "eye.slash")] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(entry)
        }
        item.submenu = menu
        return item
    }
    @objc private func menuGoHome() { goHome() }

    @objc private func menuStayPut() {
        staysPut.toggle()
        if staysPut, isWalking {
            setRun(nil)
            mode = .standing
            planNext(after: 4)
        }
    }

    @objc private func menuSettings() { openSettings?() }

    @objc private func menuShop() { openShop?() }

    // MARK: The pointer

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            self?.pointerMoved(NSEvent.mouseLocation)
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.pointerMoved(NSEvent.mouseLocation)
            return event
        }) { monitors.append(local) }
        // A button held in another app may be a window on the move: it looks
        // at the windows more often until the button comes up.
        let presses: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: presses, handler: { [weak self] event in
            self?.buttonChanged(held: event.type == .leftMouseDown)
        }) { monitors.append(global) }
        screenObserver = screenObserver ?? NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        }
        appObserver = appObserver ?? NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.appCameToFront(bundleID: app?.bundleIdentifier, pid: app?.processIdentifier)
        }
        updateWindowWatch()
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        appObserver = nil
        watchTimer?.cancel(); watchTimer = nil
        watchInterval = 0
        buttonHeld = false
    }

    private func buttonChanged(held: Bool) {
        guard buttonHeld != held else { return }
        buttonHeld = held
        updateWindowWatch()
    }

    /// Its eyes go to a pointer that comes near, and it takes clicks only
    /// where its body is, so the space around it stays the desktop's.
    private func pointerMoved(_ point: CGPoint) {
        guard isOut, let panel, let host else { return }
        let figure = shownFigureFrame.insetBy(dx: -4, dy: -4)
        let over = figure.contains(point)
        // Mid-play it still takes a grab, which ends the play (see `pressBegan`).
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
        guard !inPlay, !isHoming, mode != .held else { return }
        let near = hypot(point.x - figure.midX, point.y - figure.midY) < 320
        trackTickles(at: point)
        // Hiding behind a window, it pops out when the pointer comes close.
        if peekWork != nil, hypot(point.x - figure.midX, point.y - figure.maxY) < 150 {
            peekWork?.cancel(); peekWork = nil
            popOut(surprised: true)
        }
        if near {
            watching = true
            host.attend(toScreenPoint: point)
        } else if watching {
            watching = false
            host.mascot.lookAhead(after: 0.4)
        }
    }

    /// The pointer moving over it, which the monitors may not hear while
    /// the app is in the background.
    fileprivate func pointerMovedOver(_ point: CGPoint) { pointerMoved(point) }
    private func screensChanged() {
        guard isOut else { return }
        // A display that went away takes it back to the island.
        if !NSScreen.screens.contains(where: { $0.frame.contains(body.position) }) {
            goHome()
            return
        }
        if mode == .standing {
            body.airborne = true
            mode = .flying
            resumeTicking()
        }
    }

    // MARK: Placing

    private var figureAspect: CGFloat { look.style.sprite?.aspect ?? 1 }

    /// The body's box on screen.
    private var figureFrame: CGRect {
        let width = size * figureAspect
        return CGRect(x: body.position.x - width / 2, y: body.position.y, width: width, height: size)
    }

    private var figureCenter: CGPoint { CGPoint(x: body.position.x, y: body.position.y + size / 2) }
    /// The part of the body that shows: above the window's edge while it
    /// hides behind one.
    private var shownFigureFrame: CGRect {
        var frame = figureFrame
        guard peekDepth > 0 else { return frame }
        frame.origin.y += peekDepth
        frame.size.height = max(0, frame.height - peekDepth)
        return frame
    }

    /// Whether a point in this window falls within the companion's interactive figure.
    func containsFigure(atWindowPoint point: CGPoint) -> Bool {
        guard isOut, !isHoming, let panel else { return false }
        let screenPoint = panel.convertPoint(toScreen: point)
        let figure = shownFigureFrame.insetBy(dx: -4, dy: -4)
        return figure.contains(screenPoint)
    }

    private func place() {
        placeFigure(center: figureCenter, scale: 1)
        applyClip()
    }
    /// Hiding behind a window, only what is above its edge is drawn.
    private func applyClip() {
        guard let stage, let panel, peekDepth > 0 || clipped else { return }
        let window = NotchMascotRoam.windowSize(for: size)
        let center = CGPoint(x: window.width / 2, y: window.height - NotchMascotRoam.footInset(for: size) - size / 2)
        guard peekDepth > 0 else {
            clipped = false
            stage.host.place(at: center, visible: nil)
            return
        }
        // The edge's height in the window, counted down from its top as the
        // companion's view counts.
        let cut = window.height - (body.position.y + peekDepth - panel.frame.minY)
        stage.host.place(at: center, visible: [CGRect(x: -window.width, y: -window.height,
                                                      width: window.width * 3, height: window.height + cut)])
        clipped = true
    }

    /// Moves the window so the figure's centre is at `center` while it is
    /// drawn `scale` times its size about the window's middle.
    private func placeFigure(center: CGPoint, scale: CGFloat) {
        guard let panel else { return }
        let window = NotchMascotRoam.windowSize(for: size)
        // The figure's centre above the window's middle, unscaled.
        let rise = NotchMascotRoam.footInset(for: size) + size / 2 - window.height / 2
        let origin = CGPoint(x: (center.x - window.width / 2).rounded(),
                             y: (center.y - window.height / 2 - rise * scale).rounded())
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    /// The screen under `point`, else the nearest one; nil only while a
    /// display change leaves none.
    private func screen(for point: CGPoint) -> NSScreen? {
        let screens = NSScreen.screens
        return NotchMascotRoam.screenIndex(for: point, in: screens.map(\.frame)).map { screens[$0] }
    }

    /// Where it may be on the screen under `point`: above the Dock and below
    /// the menu bar. With no screen for a moment, where it last was.
    private func area(for point: CGPoint) -> CGRect {
        guard let area = screen(for: point)?.visibleFrame else { return lastArea }
        lastArea = area
        return area
    }

    /// Held, it may go anywhere on a screen.
    private func clampedToScreens(_ point: CGPoint) -> CGPoint {
        guard !NSScreen.screens.contains(where: { $0.frame.contains(point) }) else { return point }
        let frame = screen(for: point)?.frame ?? area(for: point)
        return CGPoint(x: min(frame.maxX, max(frame.minX, point.x)), y: min(frame.maxY - size, max(frame.minY, point.y)))
    }

    // MARK: Window

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = NotchPanel.overlayCollectionBehavior
        panel.acceptsMouseMovedEvents = true
        panel.setAccessibilityElement(false)
        self.panel = panel
        return panel
    }

    private func makeStage(in panel: NSPanel) -> NotchMascotDesktopView {
        let stage = NotchMascotDesktopView(frame: CGRect(origin: .zero, size: NotchMascotRoam.windowSize(for: size)))
        stage.controller = self
        stage.host.followsAutomation = true
        stage.host.followsPointer = true
        stage.acceptDrops()
        panel.contentView = stage
        self.stage = stage
        return stage
    }
}

/// The desktop companion's window content: the companion, and the clicks and
/// drags on it, which the companion's own view never takes.
final class NotchMascotDesktopView: NSView {
    let host: NotchMascotHostView
    weak var controller: NotchMascotDesktop?

    /// What it holds and what floats off it, over it.
    let effects: NotchMascotPlayLayerView

    override init(frame frameRect: NSRect) {
        host = NotchMascotHostView(frame: CGRect(origin: .zero, size: frameRect.size))
        effects = NotchMascotPlayLayerView(frame: CGRect(origin: .zero, size: frameRect.size))
        super.init(frame: frameRect)
        host.autoresizingMask = [.width, .height]
        effects.autoresizingMask = [.width, .height]
        addSubview(host)
        addSubview(effects)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // Something dropped on it: food it eats. Only names are read.
    func acceptDrops() {
        registerForDraggedTypes([.fileURL, .string, .URL])
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseMoved(with event: NSEvent) {
        controller?.pointerMovedOver(NSEvent.mouseLocation)
    }
    private func drop(in info: NSDraggingInfo) -> NotchMascotSnackDrop? {
        let board = info.draggingPasteboard
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let links = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        let names = urls.map(\.lastPathComponent) + links.filter { !$0.isFileURL }.map(\.lastPathComponent)
        return NotchMascotSnackDrop.classify(text: board.string(forType: .string), fileNames: names)
    }
    private func overFigure(_ info: NSDraggingInfo) -> Bool {
        controller?.containsFigure(atWindowPoint: info.draggingLocation) == true
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        overFigure(sender) && drop(in: sender) != nil ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        overFigure(sender) && drop(in: sender) != nil ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard overFigure(sender), let drop = drop(in: sender) else { return false }
        controller?.dropped(drop)
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Never intercept mouse clicks in the transparent padding around the companion.
        // Return super only when the click is on the companion figure itself.
        guard let controller, controller.containsFigure(atWindowPoint: point) else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        controller?.pressBegan(at: NSEvent.mouseLocation, clicks: event.clickCount)
    }

    override func mouseDragged(with event: NSEvent) {
        controller?.pressMoved(to: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        controller?.pressEnded(at: NSEvent.mouseLocation)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = controller?.menu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
