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

    private(set) var isOut = false
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

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var host: NotchMascotHostView? { stage?.host }

    init(leads: Bool = true) {
        self.leads = leads
        super.init()
    }

    deinit {
        removeMonitors()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
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
        configure(look: look, mood: mood)
        guard let panel, let host else { return }
        staysPut = false
        thrown = false
        samples.removeAll()
        let start = CGPoint(x: center.x, y: center.y - size / 2)
        if let pointer {
            // It hangs by the head from the pointer that pulled it out.
            grabOffset = CGVector(dx: 0, dy: -size * 0.8)
            body = NotchMascotRoam.Body(position: CGPoint(x: pointer.x, y: pointer.y + grabOffset.dy), airborne: true)
            press = (pointer, CACurrentMediaTime(), NotchMascotRoam.tapSlop)
            mode = .held
        } else {
            let screen = self.screen(for: start)
            let toward: CGFloat = hop.map { $0 > 0 ? 1 : -1 } ?? (start.x < screen.visibleFrame.midX ? 1 : -1)
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

    /// Keeps a new look or mood while it is out.
    func configure(look: NotchMascotLook, mood: NotchMascotMood) {
        let size = NotchMascotRoam.size(for: look)
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

    // MARK: Playing

    /// Free to play: out, standing on its own and not held.
    var isFree: Bool { isOut && mode == .standing && press == nil && !inPlay && !body.airborne }
    var isDozing: Bool { napping || host?.mascot.isDozing == true }
    var playLook: NotchMascotLook { look }
    var figureSize: CGFloat { size }
    /// Its middle on screen.
    var screenCenter: CGPoint { figureCenter }
    /// The screen it is on.
    var playScreen: NSScreen { screen(for: body.position) }
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
        guard isOut, !isHoming, press == nil, !body.airborne else { return 0 }
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
        guard isOut, !isHoming, press == nil else { return }
        if isWalking { setRun(nil) }
        body.velocity = CGVector(dx: dx, dy: dy)
        body.airborne = true
        thrown = false
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
        if inPlay { interrupted?() }
        cancelPlans()
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
        if inPlay { interrupted?() }
        cancelPlans()
        removeMonitors()
        stopTicking()
        panel?.orderOut(nil)
        isOut = false
        mode = .standing
    }

    private func finishHome(fading: Bool) {
        cancelPlans()
        removeMonitors()
        stopTicking()
        mode = .standing
        let landed = { [weak self] in
            guard let self else { return }
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

    private func resumeTicking() {
        if displayLink == nil, let stage {
            let link = stage.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        if displayLink?.isPaused != false { lastTick = CACurrentMediaTime() }
        displayLink?.isPaused = false
    }

    private func stopTicking() {
        displayLink?.isPaused = true
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
        let area = self.area(for: body.position)
        let events = NotchMascotRoam.step(&body, by: dt, in: area, width: size * figureAspect)
        place()
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
                setRun(nil)
                host?.mascot.lean(0)
                mode = .standing
                if thrown { react(.wave) }
                thrown = false
                planNext(after: 2)
                return
            }
        }
    }

    private func walk(_ direction: CGFloat, until: CFTimeInterval, by dt: TimeInterval, now: CFTimeInterval) {
        let area = self.area(for: body.position)
        let half = size * figureAspect / 2
        var direction = direction
        body.position.x += direction * NotchMascotRoam.walkSpeed * pace * CGFloat(min(dt, 0.05))
        // At the screen's side it turns around.
        if body.position.x <= area.minX + half || body.position.x >= area.maxX - half {
            body.position.x = min(area.maxX - half, max(area.minX + half, body.position.x))
            direction = -direction
            setRun(direction)
            mode = .walking(direction: direction, until: until)
        }
        // The floor moved under it, as a Dock that shows or hides.
        if abs(body.position.y - area.minY) > 0.5 {
            body.airborne = true
            mode = .flying
        }
        place()
        // Up to its friend, it stops, and waves if they have not lately.
        if !inPlay, let other = neighbor?(),
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
        guard isOut, mode == .standing, !inPlay, let host else { return }
        if invitePlay?() == true { return }
        if greetIfNear() { return }
        let area = self.area(for: body.position)
        let half = size * figureAspect / 2
        let activity = NotchMascotRoam.nextActivity(x: body.position.x, minX: area.minX + half, maxX: area.maxX - half,
                                                    friendX: neighbor?()?.x, random: { Double.random(in: 0..<1) })
        let still = staysPut || reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled || host.mascot.isDozing
        switch activity {
        case .stand(let length):
            planNext(after: length)
        case .lookAround:
            if !host.mascot.isDozing { react(.lookAround) }
            planNext(after: NotchMascotReaction.lookAround.length + 3)
        case .walk(let direction, let duration):
            guard !still else { planNext(after: 8); return }
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

    // MARK: Gestures

    fileprivate func pressBegan(at point: CGPoint, clicks: Int) {
        guard isOut, !isHoming else { return }
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
        current.moved = max(current.moved, hypot(point.x - current.point.x, point.y - current.point.y))
        press = current
        guard mode == .held || current.moved >= NotchMascotRoam.tapSlop else { return }
        if mode != .held {
            mode = .held
            host?.mascot.react(.surprised, lift: 0)
        }
        let now = CACurrentMediaTime()
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
        mode = .flying
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
        let gained = NotchMascotBondStore.shared.record(.petted)
        host.mascot.showPetted(gained: gained)
    }

    fileprivate func menu() -> NSMenu {
        let text = FeatureStrings.notchMascotDesktop(L10n.shared.language)
        let menu = NSMenu()
        let shop = NSMenuItem(title: FeatureStrings.notchMascotShop(L10n.shared.language).title + "…",
                              action: #selector(menuShop), keyEquivalent: "")
        shop.target = self
        shop.image = NSImage(systemSymbolName: "bag", accessibilityDescription: nil)
        menu.addItem(shop)
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
        screenObserver = screenObserver ?? NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// Its eyes go to a pointer that comes near, and it takes clicks only
    /// where its body is, so the space around it stays the desktop's.
    private func pointerMoved(_ point: CGPoint) {
        guard isOut, let panel, let host else { return }
        let figure = figureFrame.insetBy(dx: -4, dy: -4)
        let over = figure.contains(point)
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
        guard !isHoming, mode != .held, !inPlay else { return }
        let near = hypot(point.x - figure.midX, point.y - figure.midY) < 320
        if near {
            watching = true
            host.attend(toScreenPoint: point)
        } else if watching {
            watching = false
            host.mascot.lookAhead(after: 0.4)
        }
    }

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

    private func place() {
        placeFigure(center: figureCenter, scale: 1)
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

    private func screen(for point: CGPoint) -> NSScreen {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Where it may be on the screen under `point`: above the Dock and below
    /// the menu bar.
    private func area(for point: CGPoint) -> CGRect {
        screen(for: point).visibleFrame
    }

    /// Held, it may go anywhere on a screen.
    private func clampedToScreens(_ point: CGPoint) -> CGPoint {
        guard !NSScreen.screens.contains(where: { $0.frame.contains(point) }) else { return point }
        let frame = screen(for: point).frame
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
