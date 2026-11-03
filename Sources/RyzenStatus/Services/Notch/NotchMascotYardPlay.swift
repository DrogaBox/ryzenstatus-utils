// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// A yard game under way with the companion out on the desktop. It opens a
/// clear board over the usable part of the companion's screen that takes the
/// pointer and Esc while the game runs, under the companions so a grab on one
/// still reaches it (the games where every click counts keep the companion
/// out of the pointer's way), and a clear stage over them for what flies.
/// The menu bar and the Dock stay the user's, and another app coming to the
/// front, a display change, Esc or any other key ends the game at once; left
/// alone a long while it gets bored and stops. The companion puts it away as its game
/// ends, whatever ends it: done, Esc, a grab, a trip home.
///
/// Each game is a subclass that answers the pointer and plays its rules;
/// this keeps the board, the timers, the faces and the gold. A timer ticks
/// only while something in the game moves.
class NotchMascotYardPlay {
    let game: NotchMascotYardGame
    private(set) weak var player: NotchMascotDesktop?
    private let board = NotchMascotYardBoard()
    private let stage = NotchMascotPlayStage()
    /// Drawn under the companions, on the board, and over them, on the stage.
    private(set) var back: CALayer?
    private(set) var front: CALayer?
    /// The usable part of the screen it plays on, as it was when the game began.
    private(set) var yard = CGRect.zero
    /// The way along the floor with more room as it began, right when positive.
    private(set) var way: CGFloat = 1
    /// Over: it takes no more input and waits only to be put away.
    private(set) var isOver = false
    private var work: [DispatchWorkItem] = []
    private var ticker: DispatchSourceTimer?
    private var lastTick: CFTimeInterval = 0
    private var observers: [NSObjectProtocol] = []
    private var keyMonitor: Any?
    private var lastActivity = CACurrentMediaTime()
    private var faceToken = 0
    /// The companions out on the desktop, for the others to watch and cheer.
    private static let troupe = NSHashTable<NotchMascotDesktop>.weakObjects()
    /// Left with nothing happening this long, it gets bored and stops.
    static let boredAfter: TimeInterval = 45

    init(game: NotchMascotYardGame, player: NotchMascotDesktop) {
        self.game = game
        self.player = player
    }

    /// A companion joins the ones that watch each other's games.
    static func enroll(_ companion: NotchMascotDesktop) { troupe.add(companion) }

    /// Clicks on the companion itself are part of the game: it cannot be
    /// grabbed while it lasts.
    var ownsClicks: Bool { game.takesEveryClick }

    // MARK: What a game answers

    /// The game begins: the board and the stage are up.
    func begin() {}
    /// The pointer went down, moved held down, came up, or moved, on screen.
    func pressed(at point: CGPoint) {}
    func dragged(to point: CGPoint) {}
    func released(at point: CGPoint) {}
    func moved(to point: CGPoint) {}
    /// Each tick while `startTicking` holds, `dt` seconds after the last.
    func step(by dt: TimeInterval, now: CFTimeInterval) {}
    /// What it drew of its own to put away as it closes.
    func closing() {}

    // MARK: Starting and ending

    /// Starts the game with its companion; false when it cannot play now.
    func start() -> Bool {
        guard let player, let screen = player.playScreen, player.beginYard(self) else { return false }
        yard = screen.visibleFrame
        let floor = player.floor
        let x = player.yardFeet.x
        way = x - floor.lowerBound > floor.upperBound - x ? -1 : 1
        back = board.open(over: screen)
        front = stage.layer(over: screen)
        board.pressed = { [weak self] point in self?.input { $0.pressed(at: point) } }
        board.dragged = { [weak self] point in self?.input { $0.dragged(to: point) } }
        board.released = { [weak self] point in self?.input { $0.released(at: point) } }
        board.moved = { [weak self] point in
            guard let self, !self.isOver else { return }
            self.moved(to: point)
        }
        board.escaped = { [weak self] in self?.stop() }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                               queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.stop()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in self?.stop() })
        // Esc while the app is in front, should the board not hold the keys.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, !self.isOver else { return event }
            self.stop()
            return nil
        }
        let text = FeatureStrings.notchMascotYardGames(L10n.shared.language)
        if let front {
            let at = CGPoint(x: min(yard.maxX - 160, max(yard.minX + 160, x)),
                             y: min(yard.maxY - 24, player.yardFeet.y + size * 2.4))
            NotchMascotYardGameArt.hint(text.hint(game) + "  ·  " + text.stop, in: front, at: onFront(at), duration: 5)
        }
        lastActivity = CACurrentMediaTime()
        greetFriends()
        watch()
        begin()
        return true
    }

    /// A key, another app or a display change: it stops at once.
    func stop() {
        guard !isOver else { return }
        finish(after: 0)
    }

    /// The game is over: it takes no more input, and ends `delay` seconds
    /// from now, once what it does last has played.
    func finish(after delay: TimeInterval) {
        guard !isOver else { return }
        isOver = true
        board.release()
        removeWatchers()
        player?.endYard(after: delay)
    }

    /// Put away by its companion as the game ends: everything it drew, its
    /// timers and its board go, and the companion's own face comes back.
    func close() {
        isOver = true
        work.forEach { $0.cancel() }
        work.removeAll()
        stopTicking()
        removeWatchers()
        closing()
        board.close()
        stage.close()
        player?.yardFace(nil)
    }

    private func removeWatchers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in observers {
            workspace.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func input(_ answer: (NotchMascotYardPlay) -> Void) {
        guard !isOver else { return }
        noteActivity()
        answer(self)
    }

    /// Something happened in the game: it is not bored yet.
    func noteActivity() { lastActivity = CACurrentMediaTime() }

    /// Every few seconds: the others look on, and a game left alone too
    /// long ends with a yawn.
    private func watch() {
        later(3) { [weak self] in
            guard let self, !self.isOver, let player = self.player else { return }
            for friend in self.friends { friend.face(toward: player.screenCenter.x) }
            if CACurrentMediaTime() - self.lastActivity >= Self.boredAfter {
                self.face(.bored)
                self.react(.yawn)
                self.marker("BORED...")
                self.finish(after: 2)
                return
            }
            self.watch()
        }
    }

    // MARK: Helpers for the games

    /// Runs `block` in `delay` seconds, unless the game is put away first.
    func later(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        work.removeAll { $0.isCancelled }
        work.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: item)
    }

    /// Ticks `step` about sixty times a second, thirty in Low Power Mode,
    /// until `stopTicking`.
    func startTicking() {
        guard ticker == nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let interval = ProcessInfo.processInfo.isLowPowerModeEnabled ? 33 : 16
        timer.schedule(deadline: .now(), repeating: .milliseconds(interval))
        timer.setEventHandler { [weak self] in
            guard let self else { timer.cancel(); return }
            let now = CACurrentMediaTime()
            let dt = now - self.lastTick
            self.lastTick = now
            self.step(by: dt, now: now)
        }
        ticker = timer
        timer.resume()
    }

    func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var size: CGFloat { player?.figureSize ?? NotchMascotRoam.drawnSize }
    /// Its feet on screen, wherever it is; on the floor when `onFloor`.
    var feet: CGPoint { player?.yardFeet ?? .zero }
    var onFloor: Bool { player?.feet != nil }
    var figure: CGRect { player?.yardFigure ?? .zero }
    var head: CGPoint { player?.head ?? .zero }
    var ground: CGFloat { yard.minY }
    var floor: ClosedRange<CGFloat> { player?.floor ?? yard.minX...yard.maxX }
    var energy: NotchMascotPlay.Energy { NotchMascotPlay.energy(for: player?.playLook ?? .standard) }

    func onBack(_ point: CGPoint) -> CGPoint { board.point(point) }
    func onFront(_ point: CGPoint) -> CGPoint { stage.point(point) }

    /// An arcade marker over its head, or over `point`.
    func marker(_ text: String, at point: CGPoint? = nil) {
        guard let front else { return }
        let at = point ?? CGPoint(x: head.x, y: head.y + size * 0.35)
        NotchMascotPlayEffects.arcadeMarker(text, in: front, at: onFront(at), cell: max(1.6, size * 0.05))
    }

    func float(_ symbol: String, at point: CGPoint? = nil, color: UInt32 = 0xFFD54F, count: Int = 1) {
        guard let front else { return }
        NotchMascotPlayEffects.float(symbol, in: front, at: onFront(point ?? head), size: max(10, size * 0.3),
                                     color: NotchMascotRPGShapes.rgb(color), count: count)
    }

    func burst(_ burst: NotchMascotIslandPlay.Burst, at point: CGPoint? = nil) {
        guard let front else { return }
        NotchMascotPlayEffects.burst(burst, in: front, at: onFront(point ?? head), size: size, energy: energy)
    }

    func coins(at point: CGPoint? = nil) {
        guard let front else { return }
        NotchMascotPlayEffects.goldCoins(in: front, at: onFront(point ?? head), radius: max(3, size * 0.14))
    }

    func sound(_ effect: NotchMascotSoundEffect, at x: CGFloat? = nil, after delay: TimeInterval = 0) {
        let pan = NotchMascotSoundMap.pan(screenX: x ?? feet.x, across: NSScreen.screens.map(\.frame))
        NotchMascotSound.play(effect, pan: pan, after: delay)
    }

    func react(_ reaction: NotchMascotReaction) { player?.react(reaction) }

    /// Puts on `mood`'s face, for `length` seconds or until another; nil
    /// brings its own face back.
    func face(_ mood: NotchMascotMood?, for length: TimeInterval? = nil) {
        faceToken += 1
        let token = faceToken
        player?.yardFace(mood)
        guard let length else { return }
        later(length) { [weak self] in
            guard let self, self.faceToken == token else { return }
            self.player?.yardFace(nil)
        }
    }

    func look(toward x: CGFloat) { player?.face(toward: x) }

    @discardableResult
    func stroll(to x: CGFloat, pace: CGFloat) -> TimeInterval { player?.stroll(to: x, pace: pace) ?? 0 }

    func hop(dx: CGFloat, dy: CGFloat) { player?.hop(dx: dx, dy: dy) }

    /// A hop that comes down near `x`, `height` up at its peak; how long it is in the air.
    @discardableResult
    func hop(to x: CGFloat, height: CGFloat) -> TimeInterval {
        let target = NotchMascotYardMoves.clamp(x, to: floor)
        let move = NotchMascotYardMoves.hop(from: feet.x, to: target, height: height)
        look(toward: target)
        hop(dx: move.dx, dy: move.dy)
        return move.flight
    }

    func spin(turns: CGFloat, duration: TimeInterval) {
        guard !reduceMotion else { return }
        player?.yardSpin(turns: turns, duration: duration)
    }

    /// `x` where something as wide as `width` fits wholly in the yard.
    func inYard(_ x: CGFloat, width: CGFloat) -> CGFloat {
        min(yard.maxX - width / 2 - 6, max(yard.minX + width / 2 + 6, x))
    }

    /// Pays `amount` of gold for the game while today's paid games last;
    /// the gold paid. A game played to its end is a moment shared, too.
    func pay(_ amount: Int) -> Int {
        NotchMascotBondStore.shared.record(.moment)
        return NotchMascotYardPrizes.pay(game, amount: amount)
    }

    /// Pays, and shows what it paid with coins over its head, or `instead`
    /// when nothing was paid.
    func payOut(_ amount: Int, instead: String) {
        let gold = pay(amount)
        if gold > 0 {
            coins()
            sound(.coin)
            marker("+\(gold)", at: CGPoint(x: head.x, y: head.y + size * 0.9))
        } else {
            marker(instead, at: CGPoint(x: head.x, y: head.y + size * 0.9))
        }
    }

    // MARK: The others

    /// The other companions out on the desktop, standing or walking on a floor.
    private var friends: [NotchMascotDesktop] {
        Self.troupe.allObjects.filter { $0 !== player && $0.isOut && !$0.inPlay && $0.feet != nil && !$0.isDozing }
    }

    private func greetFriends() {
        guard let player else { return }
        for friend in friends { friend.greet(toward: player.screenCenter) }
    }

    /// The others cheer: a symbol floats up over each, and a big moment
    /// gets them jumping too.
    func cheer(big: Bool = false) {
        let symbols = ["♥", "♪", "★", "!"]
        let colors: [UInt32] = [0xFF5E8A, 0x64B5F6, 0xFFD54F, 0xFFFFFF]
        for friend in friends {
            let pick = Int.random(in: 0..<symbols.count)
            let over = friend.head
            let color = NotchMascotRPGShapes.rgb(colors[pick])
            if let front, yard.insetBy(dx: -1, dy: -1).contains(over) {
                NotchMascotPlayEffects.float(symbols[pick], in: front, at: onFront(over), size: max(10, friend.figureSize * 0.3),
                                             color: color, count: big ? 3 : 1)
            } else if let canvas = friend.effects {
                NotchMascotPlayEffects.float(symbols[pick], in: canvas, at: friend.local(over),
                                             size: max(10, friend.figureSize * 0.3), color: color, count: big ? 3 : 1)
            }
            if big, friend.isFree { friend.react(.celebrate) }
        }
    }
}

// MARK: - The board

/// The clear window a yard game takes the pointer and the keys through: over
/// the usable part of one screen, under the companions, faintly tinted so
/// the whole of it answers the pointer. Released, it lets every click
/// through at once while what is drawn on it fades.
final class NotchMascotYardBoard {
    var pressed: ((CGPoint) -> Void)?
    var dragged: ((CGPoint) -> Void)?
    var released: ((CGPoint) -> Void)?
    var moved: ((CGPoint) -> Void)?
    var escaped: (() -> Void)?
    private var panel: NSPanel?
    private var view: NotchMascotYardBoardView?

    /// Opens over `screen`'s usable part, taking the pointer and the keys,
    /// and answers the layer to draw on, y up, in points less its origin.
    func open(over screen: NSScreen) -> CALayer? {
        let panel = self.panel ?? makePanel()
        panel.setFrame(screen.visibleFrame, display: false)
        view?.frame = CGRect(origin: .zero, size: screen.visibleFrame.size)
        view?.layoutSubtreeIfNeeded()
        panel.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.02)
        panel.sharingType = NotchSupport.showsInCaptures() ? .readOnly : .none
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        panel.makeKey()
        if let view { panel.makeFirstResponder(view) }
        return view?.art.canvas
    }

    func point(_ screenPoint: CGPoint) -> CGPoint {
        guard let panel else { return screenPoint }
        return CGPoint(x: screenPoint.x - panel.frame.minX, y: screenPoint.y - panel.frame.minY)
    }

    /// Lets the pointer and the keys go, leaving what is drawn.
    func release() {
        guard let panel else { return }
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        if panel.isKeyWindow {
            // Ordered out and back, it gives up the keys without taking the front.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    func close() {
        release()
        view?.art.clear()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NotchMascotYardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                                         defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        // Under the companions, which still take their own clicks, and over the apps.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        panel.collectionBehavior = NotchPanel.overlayCollectionBehavior
        panel.acceptsMouseMovedEvents = true
        panel.setAccessibilityElement(false)
        let view = NotchMascotYardBoardView(frame: .zero)
        view.board = self
        panel.contentView = view
        self.panel = panel
        self.view = view
        return panel
    }

    fileprivate func send(_ kind: NSEvent.EventType) {
        let point = NSEvent.mouseLocation
        switch kind {
        case .leftMouseDown: pressed?(point)
        case .leftMouseDragged: dragged?(point)
        case .leftMouseUp: released?(point)
        default: moved?(point)
        }
    }
}

/// A panel that may hold the keys, for Esc, without bringing the app forward.
private final class NotchMascotYardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class NotchMascotYardBoardView: NSView {
    weak var board: NotchMascotYardBoard?
    let art = NotchMascotPlayLayerView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        art.autoresizingMask = [.width, .height]
        addSubview(art)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseDown(with event: NSEvent) { board?.send(.leftMouseDown) }
    override func mouseDragged(with event: NSEvent) { board?.send(.leftMouseDragged) }
    override func mouseUp(with event: NSEvent) { board?.send(.leftMouseUp) }
    override func mouseMoved(with event: NSEvent) { board?.send(.mouseMoved) }
    // The right button does nothing in a game: no menu of the app's opens over it.
    override func rightMouseDown(with event: NSEvent) {}
    // Esc stops the game; so does any other key, which hands the keyboard back.
    override func keyDown(with event: NSEvent) { board?.escaped?() }
    override func cancelOperation(_ sender: Any?) { board?.escaped?() }
}

// MARK: - From the menu

extension NotchMascotDesktop {
    /// The yard games, an entry each, for its "Play" menu.
    func yardGameItems() -> [NSMenuItem] {
        let text = FeatureStrings.notchMascotYardGames(L10n.shared.language)
        return NotchMascotYardGame.allCases.map { game in
            let entry = NSMenuItem(title: text.title(game), action: #selector(menuYardGame(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = game.rawValue
            entry.image = NSImage(systemSymbolName: game.symbol, accessibilityDescription: nil)
            return entry
        }
    }

    @objc func menuYardGame(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let game = NotchMascotYardGame(rawValue: raw) else { return }
        playYard(game)
    }

    /// Starts `game` with it out on the desktop; false when it cannot now.
    @discardableResult
    func playYard(_ game: NotchMascotYardGame) -> Bool {
        let play: NotchMascotYardPlay
        switch game {
        case .fetch: play = NotchMascotFetchPlay(player: self)
        case .shells: play = NotchMascotShellPlay(player: self)
        case .moles: play = NotchMascotMolePlay(player: self)
        case .ticTacToe: play = NotchMascotTicTacToePlay(player: self)
        case .simon: play = NotchMascotSimonPlay(player: self)
        case .bubbles: play = NotchMascotBubblePlay(player: self)
        case .path: play = NotchMascotPathPlay(player: self)
        case .target: play = NotchMascotTargetPlay(player: self)
        }
        return play.start()
    }
}
