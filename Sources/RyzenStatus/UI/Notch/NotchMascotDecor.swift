// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// The parts of a companion beyond its body and eyes, and the props it
/// carries in a mood: a chip's pins, a fan's blades, a cat's ears and tail,
/// a ghost's mouth, a slime's drip; sweat, heat, music notes, a coffee mug,
/// a download arrow, a tired battery, a "z" and confetti. Drawn with shape
/// layers like the rest of the companion. A mood that lasts runs as repeating
/// Core Animation animations in the render server, only while the companion
/// is in sight and motion is welcome, and none of it needs a timer in the app.
final class NotchMascotDecor {
    /// Behind the body: pins, ears and tail.
    let back = CALayer()
    /// Over the body, under the eyes: the fan's opening, blades and hub, the
    /// chip's mark, the cat's nose and whiskers, the ghost's mouth.
    let middle = CALayer()
    /// In front of everything: the props.
    let props = CALayer()

    private(set) var look = NotchMascotLook.standard
    private(set) var size: CGFloat = 0
    private(set) var sleeping = false
    private var ambient = MascotMoodState()
    private var motion = false
    /// Until when Cristóbal has his mug out for a sip, on the media clock.
    private var sipUntil: CFTimeInterval = -.infinity

    // Creature parts.
    private let pins = CAShapeLayer()
    private let chipMark = CAShapeLayer()
    private let fanHole = CAShapeLayer()
    private let bladeHolder = CALayer()
    private let blades = CAShapeLayer()
    private let fanHub = CAShapeLayer()
    private let fanScrews = CAShapeLayer()
    private let catTail = CAShapeLayer()
    private let catEars = CAShapeLayer()
    private let catInnerEars = CAShapeLayer()
    private let catNose = CAShapeLayer()
    private let dogNose = CAShapeLayer()
    private let whiskers = CAShapeLayer()
    private let ghostMouth = CAShapeLayer()
    private let slimeDrip = CAShapeLayer()
    /// A second creature detail in its own color: a beak, gill tips, a snout.
    private let plume = CAShapeLayer()
    /// The pale ends of a kitsune's tails.
    private let tailTips = CAShapeLayer()
    /// A kitsune's foxfire, two blue wisps that show in a flourish.
    private let wisps = CAShapeLayer()
    /// How many tails a kitsune has grown.
    private var tails = 1
    /// Walking: a kitsune's tails stream behind, a penguin's flippers swing.
    private var striding = false
    /// The hologram and the android, drawn in layers of their own.
    private let signal = NotchMascotSignalParts()
    /// The three dancers, drawn in layers of their own.
    private let dancer = NotchMascotDancerParts()
    /// The five animals, drawn in layers of their own.
    private let critter = NotchMascotCritterParts()

    // Props.
    private let sweatDrop = CAShapeLayer()
    private let heat = CAShapeLayer()
    private let note = CAShapeLayer()
    private let mug = CALayer()
    private let mugBody = CAShapeLayer()
    private let mugHandle = CAShapeLayer()
    private let mugCoffee = CAShapeLayer()
    private let steam = CAShapeLayer()
    private let zee = CAShapeLayer()
    private let arrow = CAShapeLayer()
    private let battery = CAShapeLayer()
    private let batteryLevel = CAShapeLayer()
    private let paw = CAShapeLayer()
    private var confetti: [CAShapeLayer] = []

    private var creatureLayers: [CALayer] {
        [pins, plume, chipMark, fanHole, bladeHolder, blades, fanHub, fanScrews, catTail, catEars, catInnerEars, catNose,
         dogNose, whiskers, ghostMouth, slimeDrip, tailTips, wisps]
    }

    private var propLayers: [CALayer] {
        [sweatDrop, heat, note, mug, mugBody, mugHandle, mugCoffee, steam, zee, arrow, battery, batteryLevel, paw]
            + confetti
    }

    init() {
        for layer in [pins, tailTips, catTail, catEars, catInnerEars, slimeDrip] { back.addSublayer(layer) }
        bladeHolder.addSublayer(blades)
        // A muzzle, a beak or gills sit over the body, where they read; only
        // the ears and tails they belong to belong behind it.
        for layer in [plume, fanHole, bladeHolder, fanHub, fanScrews, chipMark, catNose, dogNose, whiskers, ghostMouth] {
            middle.addSublayer(layer)
        }
        for layer in [mugBody, mugCoffee, mugHandle] { mug.addSublayer(layer) }
        for layer in [wisps, sweatDrop, heat, note, mug, steam, zee, arrow, battery, batteryLevel, paw] { props.addSublayer(layer) }
        confetti = (0..<NotchMascotCreatures.confettiFlights.count).map { _ in CAShapeLayer() }
        confetti.forEach(props.addSublayer)
        back.addSublayer(signal.back)
        back.addSublayer(dancer.back)
        back.addSublayer(critter.back)
        middle.addSublayer(signal.middle)
        middle.addSublayer(dancer.middle)
        middle.addSublayer(critter.middle)
        props.addSublayer(signal.front)
        props.addSublayer(critter.front)
        for layer in [back, middle, props] + creatureLayers + propLayers {
            layer.actions = Self.noActions
        }
        catTail.fillColor = nil
        catTail.lineCap = .round
        whiskers.fillColor = nil
        whiskers.lineCap = .round
        heat.fillColor = nil
        heat.lineCap = .round
        steam.fillColor = nil
        steam.lineCap = .round
        zee.fillColor = nil
        zee.lineCap = .round
        zee.lineJoin = .round
        arrow.fillColor = nil
        arrow.lineCap = .round
        arrow.lineJoin = .round
        battery.fillColor = nil
        mugHandle.fillColor = nil
        for layer in propLayers { layer.opacity = 0 }
        // The mug's own parts show whenever the mug does.
        for layer in [mugBody, mugHandle, mugCoffee] { layer.opacity = 1 }
    }

    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "path": NSNull(), "opacity": NSNull(),
        "hidden": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull(), "frame": NSNull(), "lineWidth": NSNull(),
        "sublayers": NSNull(), "speed": NSNull(), "timeOffset": NSNull(), "beginTime": NSNull(),
    ]

    // MARK: Look

    func configure(look: NotchMascotLook, size: CGFloat, scale: CGFloat) {
        self.look = look
        self.size = size
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        // The blades turn about their own middle and the confetti flies from
        // its own spot; every other layer covers the companion's square.
        let placedElsewhere: Set<ObjectIdentifier> = Set(([blades, bladeHolder] + confetti).map { ObjectIdentifier($0) })
        for layer in [back, middle, props] + creatureLayers + propLayers
        where !placedElsewhere.contains(ObjectIdentifier(layer)) {
            layer.frame = box
            layer.contentsScale = scale
        }
        let palette = look.bodyPalette
        let style = look.style
        let line = max(0.6, size * 0.06)

        for layer in creatureLayers { layer.isHidden = true }
        // Only the comic's two are outlined; no outline is carried over to
        // the next figure that uses the same layer.
        for case let layer as CAShapeLayer in creatureLayers where ![whiskers, catTail, fanHub].contains(layer) {
            layer.strokeColor = nil
            layer.lineWidth = 0
        }
        // The cat's whiskers are lines; Cristóbal's hands, drawn in the same
        // layer, are filled.
        whiskers.fillColor = nil
        catTail.fillColor = nil
        switch style {
        case .minimal, .robot:
            break
        case .cristobal:
            // The palette dyes his jumper and sleeves; skin, black hair, the
            // day's stubble, glasses, dark trousers and his coffee mug keep
            // their colours, outlined in ink as in the comic.
            let ink = NotchMascotWearableShapes.rgb(NotchMascotCreatures.comicInk)
            let outline = max(0.4, size * 0.014)
            let skin = NotchMascotWearableShapes.rgb(0xEDB98F)
            catEars.path = NotchMascotCreatures.cristobalTrousers(size: size)
            catEars.fillColor = NotchMascotWearableShapes.rgb(0x2C2E3B)
            catInnerEars.path = NotchMascotCreatures.cristobalShoes(size: size)
            catInnerEars.fillColor = NotchMascotWearableShapes.rgb(0x16161C)
            catTail.path = NotchMascotCreatures.cristobalNeck(size: size)
            catTail.fillColor = skin
            plume.path = NotchMascotCreatures.cristobalSkin(size: size)
            plume.fillColor = skin
            chipMark.path = NotchMascotCreatures.cristobalStubble(size: size)
            chipMark.fillColor = NotchMascotWearableShapes.rgb(0x6B5446).copy(alpha: 0.32)
            catNose.path = NotchMascotCreatures.cristobalSmile(size: size)
            catNose.fillColor = NotchMascotWearableShapes.rgb(0x6A3C2E)
            fanHub.path = armsPath(armsPose)
            fanHub.fillColor = palette.light.cgColor
            dogNose.path = NotchMascotCreatures.cristobalMug(size: size)
            dogNose.fillColor = NotchMascotWearableShapes.rgb(0xF6F6F8)
            dogNose.opacity = holdsMug ? 1 : 0
            slimeDrip.path = NotchMascotCreatures.cristobalSteam(size: size)
            slimeDrip.fillColor = nil
            slimeDrip.strokeColor = NSColor.white.withAlphaComponent(0.6).cgColor
            slimeDrip.lineWidth = max(0.4, size * 0.014)
            slimeDrip.lineCap = .round
            slimeDrip.opacity = holdsMug && !sleeping ? 1 : 0
            whiskers.path = cristobalHandsPath(armsPose)
            whiskers.fillColor = skin
            fanScrews.path = NotchMascotCreatures.cristobalGlasses(size: size)
            fanScrews.fillColor = nil
            fanScrews.strokeColor = ink
            fanScrews.lineWidth = max(0.5, size * 0.02)
            ghostMouth.path = NotchMascotCreatures.cristobalHair(size: size)
            ghostMouth.fillColor = NotchMascotWearableShapes.rgb(0x1C1B22)
            ghostMouth.opacity = 1
            for layer in [catEars, catInnerEars, plume, fanHub, dogNose, whiskers] {
                layer.strokeColor = ink
                layer.lineWidth = outline
            }
            show(catEars, catInnerEars, catTail, plume, chipMark, catNose, fanHub, dogNose, whiskers, fanScrews, ghostMouth,
                 slimeDrip)
        case .whiteRabbit:
            // The palette dyes its apron; white fur, pink ears and nose, all
            // outlined in ink as in the comic.
            let ink = NotchMascotWearableShapes.rgb(NotchMascotCreatures.comicInk)
            let outline = max(0.4, size * 0.014)
            let fur = NotchMascotWearableShapes.rgb(0xF8F4F0)
            catEars.path = NotchMascotCreatures.rabbitEars(inner: false, size: size)
            catEars.fillColor = fur
            catInnerEars.path = NotchMascotCreatures.rabbitEars(inner: true, size: size)
            catInnerEars.fillColor = NotchMascotWearableShapes.rgb(0xF2A7B6)
            tailTips.path = NotchMascotCreatures.rabbitBody(size: size)
            tailTips.fillColor = fur
            plume.path = NotchMascotCreatures.rabbitHead(size: size)
            plume.fillColor = fur
            fanHole.path = NotchMascotCreatures.rabbitPocket(size: size)
            fanHole.fillColor = palette.shade.cgColor
            // Its arms go unlined, a touch greyer than the rest of its fur,
            // so they read over its body without seams at the joints.
            fanHub.path = NotchMascotCreatures.rabbitArms(armsPose, size: size)
            fanHub.fillColor = NotchMascotWearableShapes.rgb(0xE9E3DD)
            dogNose.path = NotchMascotCreatures.rabbitNose(size: size)
            dogNose.fillColor = NotchMascotWearableShapes.rgb(0xF08AA2)
            whiskers.path = NotchMascotCreatures.rabbitMouth(size: size)
            whiskers.fillColor = nil
            whiskers.strokeColor = ink
            whiskers.lineWidth = max(0.4, size * 0.012)
            for layer in [catEars, tailTips, plume] {
                layer.strokeColor = ink
                layer.lineWidth = outline
            }
            fanHub.strokeColor = nil
            fanHub.lineWidth = 0
            show(catEars, catInnerEars, tailTips, plume, fanHole, fanHub, dogNose, whiskers)
        case .devourer:
            pins.path = NotchMascotCreatures.devourerLimbs(size: size)
            pins.fillColor = palette.shade.cgColor
            show(pins)
            plume.path = NotchMascotCreatures.devourerMouth(size: size)
            plume.fillColor = NotchMascotColor.ink.cgColor
            show(plume)
        case .shifter:
            slimeDrip.path = NotchMascotCreatures.slimeDrip(melted: sleeping, size: size)
            slimeDrip.fillColor = palette.shade.cgColor
            show(slimeDrip)
        case .axolotl:
            // Gill fronds fanning out of the head; feet and smile over the body.
            pins.path = NotchMascotCreatures.axolotlGills(size: size)
            pins.fillColor = palette.light.cgColor
            show(pins)
            plume.path = NotchMascotCreatures.axolotlFeetAndSmile(size: size)
            plume.fillColor = palette.shade.cgColor
            show(plume)
        case .dog:
            pins.path = NotchMascotCreatures.dogEarsTail(size: size)
            pins.fillColor = palette.shade.cgColor
            show(pins)
            plume.path = NotchMascotCreatures.dogSnout(size: size)
            // A soft muzzle a step off the body, so it reads on every palette.
            plume.fillColor = palette.shade.brightened(0.55).cgColor
            dogNose.path = NotchMascotCreatures.dogNoseAndMouth(size: size)
            dogNose.fillColor = NotchMascotColor.ink.cgColor
            show(plume, dogNose)
        case .capybara:
            pins.path = NotchMascotCreatures.capybaraSnoutAndEars(size: size)
            pins.fillColor = palette.shade.cgColor
            show(pins)
            plume.path = NotchMascotCreatures.capybaraOrange(size: size)
            plume.fillColor = NotchMascotWearableShapes.rgb(0xFF8C00)
            show(plume)
        case .dragon:
            pins.path = NotchMascotCreatures.dragonWingsAndTail(size: size)
            pins.fillColor = palette.shade.cgColor
            show(pins)
            plume.path = NotchMascotCreatures.dragonHornsAndSnout(size: size)
            plume.fillColor = palette.light.cgColor
            show(plume)
        case .frog:
            pins.path = NotchMascotCreatures.frogThroatAndPaws(size: size)
            pins.fillColor = palette.light.cgColor
            show(pins)
        case .swan:
            pins.path = NotchMascotCreatures.swanWings(size: size)
            pins.fillColor = palette.light.cgColor
            catEars.path = NotchMascotCreatures.swanTiara(size: size)
            catEars.fillColor = NotchMascotWearableShapes.rgb(0xFFD700)
            plume.path = NotchMascotCreatures.swanBeak(size: size)
            plume.fillColor = NotchMascotWearableShapes.rgb(0xFF921E)
            dogNose.path = NotchMascotCreatures.swanMask(size: size)
            dogNose.fillColor = NotchMascotWearableShapes.rgb(0x18181B)
            chipMark.path = NotchMascotCreatures.swanChestDetails(size: size)
            chipMark.fillColor = palette.shade.cgColor
            show(pins, catEars, plume, dogNose, chipMark)
        case .kitsune:
            // Tails behind the haunch, more of them as the bond grows; tall
            // ears with pale insides; a pale mask and bib, a black nose and
            // the red mark on its brow; foxfire waiting out of sight.
            tails = NotchMascotCreatures.kitsuneTailCount(level: NotchMascotBondStore.shared.shownLevel(for: .kitsune))
            let held = tailPaths(tailsPose)
            pins.path = held.tails
            pins.fillColor = palette.shade.cgColor
            tailTips.path = held.tips
            tailTips.fillColor = NotchMascotWearableShapes.rgb(0xFFF6EA)
            catEars.path = NotchMascotCreatures.kitsuneEars(sleeping ? .droop : .up, inner: false, size: size)
            catEars.fillColor = palette.shade.cgColor
            catInnerEars.path = NotchMascotCreatures.kitsuneEars(sleeping ? .droop : .up, inner: true, size: size)
            catInnerEars.fillColor = NotchMascotWearableShapes.rgb(0xFFF1E2)
            plume.path = NotchMascotCreatures.kitsuneMuzzleAndBib(size: size)
            plume.fillColor = NotchMascotWearableShapes.rgb(0xFFF6EA)
            dogNose.path = NotchMascotCreatures.kitsuneNose(size: size)
            dogNose.fillColor = NotchMascotColor.ink.cgColor
            chipMark.path = NotchMascotCreatures.kitsuneMark(size: size)
            chipMark.fillColor = NotchMascotWearableShapes.rgb(0xE5383B)
            let fire = NotchMascotWearableShapes.rgb(0x7FDBFF)
            wisps.path = NotchMascotCreatures.foxfire(size: size)
            wisps.fillColor = fire
            wisps.shadowColor = fire
            wisps.shadowOffset = .zero
            wisps.shadowRadius = max(1, size * 0.08)
            wisps.shadowOpacity = 0.9
            wisps.opacity = 0
            show(pins, tailTips, catEars, catInnerEars, plume, dogNose, chipMark, wisps)
        case .penguin:
            // Flippers at its sides, a white face and belly, an orange beak
            // and feet, and an emperor's golden cheeks.
            pins.path = NotchMascotCreatures.penguinFlippers(sleeping ? .tucked : .rest, size: size)
            pins.fillColor = palette.shade.cgColor
            plume.path = NotchMascotCreatures.penguinBelly(size: size)
            plume.fillColor = NotchMascotWearableShapes.rgb(0xFBFBFD)
            dogNose.path = NotchMascotCreatures.penguinBeakAndFeet(size: size)
            dogNose.fillColor = NotchMascotWearableShapes.rgb(0xFF9F1C)
            chipMark.path = NotchMascotCreatures.penguinCheeks(size: size)
            chipMark.fillColor = NotchMascotWearableShapes.rgb(0xFFC83D)
            show(pins, plume, dogNose, chipMark)
        case .hologram, .android, .ballerina, .danseur, .contemporary, .phoenix, .mouse:
            // Drawn by their own parts, configured below for every figure.
            break
        case .chip:
            pins.path = NotchMascotCreatures.chipPins(size: size)
            pins.fillColor = palette.shade.cgColor
            chipMark.path = NotchMascotCreatures.chipMark(size: size)
            chipMark.fillColor = palette.shade.cgColor
            show(pins, chipMark)
        case .fan:
            fanHole.path = NotchMascotCreatures.fanHole(size: size)
            fanHole.fillColor = NotchMascotColor.visor.cgColor
            let center = CGPoint(x: NotchMascotCreatures.fanCenter.x * size, y: NotchMascotCreatures.fanCenter.y * size)
            let side = NotchMascotCreatures.fanReach * 2 * size
            bladeHolder.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            bladeHolder.position = center
            bladeHolder.contentsScale = scale
            blades.frame = bladeHolder.bounds
            blades.contentsScale = scale
            blades.path = NotchMascotCreatures.fanBlades(side: side)
            blades.fillColor = palette.light.cgColor
            blades.opacity = 0.92
            fanHub.path = NotchMascotCreatures.fanHub(size: size)
            fanHub.fillColor = palette.light.cgColor
            fanHub.strokeColor = palette.shade.cgColor
            fanHub.lineWidth = max(0.4, size * 0.025)
            fanScrews.path = NotchMascotCreatures.fanScrews(size: size)
            fanScrews.fillColor = palette.shade.cgColor
            show(fanHole, bladeHolder, blades, fanHub, fanScrews)
        case .cat:
            // Drawn by its own parts, like the phoenix and the mouse.
            break
        case .ghost:
            ghostMouth.path = NotchMascotCreatures.ghostMouth(open: false, size: size)
            ghostMouth.fillColor = NotchMascotColor.ink.cgColor
            ghostMouth.opacity = 0
            show(ghostMouth)
        case .slime:
            slimeDrip.path = NotchMascotCreatures.slimeDrip(melted: sleeping, size: size)
            slimeDrip.fillColor = palette.shade.cgColor
            show(slimeDrip)
        }
        signal.configure(look: look, size: size, scale: scale, sleeping: sleeping, level: gaugeLevel)
        dancer.configure(look: look, size: size, scale: scale, sleeping: sleeping)
        critter.configure(look: look, size: size, scale: scale, sleeping: sleeping)
        // A kitsune curls its tails, a penguin tucks its flippers and the
        // hologram and the android fold their arms instead.
        pins.opacity = sleeping && ![.kitsune, .penguin, .hologram, .android].contains(style) ? 0.45 : 1

        // Props, the same for every style.
        sweatDrop.path = NotchMascotCreatures.sweatDrop(size: size)
        sweatDrop.fillColor = NotchMascotCreatures.sweat.cgColor
        heat.path = NotchMascotCreatures.heatLines(size: size)
        heat.strokeColor = NotchMascotCreatures.heat.cgColor
        heat.lineWidth = line * 0.8
        note.path = NotchMascotCreatures.note(size: size)
        note.fillColor = palette.light.cgColor
        mugBody.path = NotchMascotCreatures.mug(size: size)
        mugBody.fillColor = NotchMascotCreatures.mug.cgColor
        mugHandle.path = NotchMascotCreatures.mugHandle(size: size)
        mugHandle.strokeColor = NotchMascotCreatures.mug.cgColor
        mugHandle.lineWidth = line * 0.7
        mugCoffee.path = NotchMascotCreatures.mugCoffee(size: size)
        mugCoffee.fillColor = NotchMascotCreatures.coffee.cgColor
        steam.path = NotchMascotCreatures.steam(size: size)
        steam.strokeColor = NSColor.white.withAlphaComponent(0.75).cgColor
        steam.lineWidth = line * 0.5
        zee.path = NotchMascotCreatures.z(size: size)
        zee.strokeColor = palette.light.cgColor
        zee.lineWidth = line * 0.6
        arrow.path = NotchMascotCreatures.downArrow(size: size)
        arrow.strokeColor = NotchMascotCreatures.download.cgColor
        arrow.lineWidth = line * 0.8
        battery.path = NotchMascotCreatures.battery(size: size)
        battery.strokeColor = palette.light.cgColor
        battery.lineWidth = line * 0.4
        batteryLevel.path = NotchMascotCreatures.batteryLevel(size: size)
        batteryLevel.fillColor = NotchMascotCreatures.warning.cgColor
        paw.path = NotchMascotCreatures.paw(size: size)
        paw.fillColor = palette.light.cgColor
        paw.strokeColor = palette.shade.cgColor
        paw.lineWidth = line * 0.3
        let colors = NotchMascotCreatures.confetti + [palette.light]
        for (index, piece) in confetti.enumerated() {
            piece.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            piece.position = CGPoint(x: size * 0.5, y: size * 0.3)
            piece.contentsScale = scale
            piece.path = NotchMascotCreatures.confettiPiece(size: size)
                .copy(using: [CGAffineTransform(translationX: size / 2, y: size / 2)])
            piece.fillColor = colors[index % colors.count].cgColor
        }
        applyAmbient()
    }

    private func show(_ layers: CALayer...) { layers.forEach { $0.isHidden = false } }

    // MARK: Sleep

    /// Asleep, each creature settles in its own way: the cat's ears droop and
    /// its tail curls round, the fan's blades stop, the ghost grows faint, the
    /// slime melts into a little puddle and the chip's pins go dim.
    func setSleeping(_ sleeping: Bool, animated: Bool, fill: CALayer) {
        guard sleeping != self.sleeping else { return }
        self.sleeping = sleeping
        guard size > 0 else { return }
        let duration = sleeping ? 0.6 : 0.3
        switch look.style {
        case .cat:
            // Ears relaxed, paws tucked together, tail wrapped round.
            critter.setSleeping(sleeping, animated: animated)
        case .slime, .shifter:
            morph(slimeDrip, to: NotchMascotCreatures.slimeDrip(melted: sleeping, size: size),
                  duration: duration, animated: animated)
        case .kitsune:
            // It curls its tails round its paws and lays its ears back.
            poseTails(tailsPose, duration: duration * 1.4, animated: animated)
            morph(catEars, to: NotchMascotCreatures.kitsuneEars(sleeping ? .droop : .up, inner: false, size: size),
                  duration: duration, animated: animated)
            morph(catInnerEars, to: NotchMascotCreatures.kitsuneEars(sleeping ? .droop : .up, inner: true, size: size),
                  duration: duration, animated: animated)
        case .penguin:
            // It sleeps standing, flippers tucked in tight.
            morph(pins, to: NotchMascotCreatures.penguinFlippers(sleeping ? .tucked : .rest, size: size),
                  duration: duration, animated: animated)
        case .cristobal, .whiteRabbit:
            // Arms folded for a nap; Cristóbal keeps hold of his mug if he has one.
            morph(fanHub, to: armsPath(armsPose), duration: duration, animated: animated)
            if look.style == .cristobal {
                morph(whiskers, to: cristobalHandsPath(armsPose), duration: duration, animated: animated)
                fade(slimeDrip, to: holdsMug && !sleeping ? 1 : 0, duration: duration, animated: animated)
            }
        case .hologram, .android:
            // Arms folded; the projection, or the light it floats on, dims.
            signal.setSleeping(sleeping, animated: animated)
        case .ballerina, .danseur, .contemporary:
            // Arms folded, down off their toes.
            dancer.setSleeping(sleeping, animated: animated)
        case .phoenix, .mouse:
            // Its own way of curling up: wings folded and fire sunk to
            // embers, ears laid back and paws tucked in.
            critter.setSleeping(sleeping, animated: animated)
        case .axolotl, .dog, .capybara, .dragon, .frog, .swan:
            fade(pins, to: sleeping ? 0.55 : 1, duration: duration, animated: animated)
            fade(plume, to: sleeping ? 0.55 : 1, duration: duration, animated: animated)
            fade(dogNose, to: sleeping ? 0.55 : 1, duration: duration, animated: animated)
            fade(catEars, to: sleeping ? 0.55 : 1, duration: duration, animated: animated)
            fade(chipMark, to: sleeping ? 0.55 : 1, duration: duration, animated: animated)
        case .chip:
            fade(pins, to: sleeping ? 0.45 : 1, duration: duration, animated: animated)
        case .ghost:
            fade(fill, to: sleeping ? 0.55 : 0.92, duration: duration, animated: animated)
        case .fan, .minimal, .robot, .devourer:
            break
        }
        applyAmbient()
    }

    private func morph(_ layer: CAShapeLayer, to path: CGPath, duration: TimeInterval, animated: Bool) {
        if animated {
            let change = CABasicAnimation(keyPath: "path")
            change.fromValue = layer.presentation()?.path ?? layer.path
            change.toValue = path
            change.duration = duration
            change.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(change, forKey: "pose")
        }
        layer.path = path
    }

    private func fade(_ layer: CALayer, to opacity: Float, duration: TimeInterval, animated: Bool) {
        if animated {
            let change = CABasicAnimation(keyPath: "opacity")
            change.fromValue = layer.presentation()?.opacity ?? layer.opacity
            change.toValue = opacity
            change.duration = duration
            layer.add(change, forKey: "sleepFade")
        }
        layer.opacity = opacity
    }

    // MARK: Moods that last

    /// Shows the props of a lasting mood. With `motion`, they move: sweat
    /// runs, heat rises, notes float, steam curls, a "z" drifts up, the fan
    /// spins with the CPU's load. Without it they stay still.
    func setAmbient(_ state: MascotMoodState, motion: Bool) {
        guard state != ambient || motion != self.motion else { return }
        ambient = state
        self.motion = motion
        applyAmbient()
    }

    private func applyAmbient() {
        guard size > 0 else { return }
        let mood = sleeping && !ambient.ambient.isResting ? MascotAmbient.asleep : ambient.ambient
        let shown: [CALayer: Bool] = [
            sweatDrop: mood == .working || mood == .overheated,
            heat: mood == .overheated,
            note: mood == .dancing,
            // Cristóbal takes up his own mug instead.
            mug: mood == .caffeinated && look.style != .cristobal,
            steam: mood == .caffeinated && look.style != .cristobal,
            zee: mood == .asleep,
            arrow: mood == .downloading,
            battery: mood == .lowBattery,
            batteryLevel: mood == .lowBattery,
        ]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, on) in shown {
            layer.removeAnimation(forKey: "ambient")
            layer.opacity = on ? 1 : 0
            guard on, motion else { continue }
            layer.add(loop(for: layer, mood: mood), forKey: "ambient")
        }
        CATransaction.commit()
        setSpin(look.style == .fan && motion && !sleeping ? Self.spinRate(effort: ambient.effort, mood: mood) : 0)
        applyGlow(sleeping ? 0 : ambient.glow)
        applyGauge()
        applyIdleTails()
        syncMug(animated: motion)
    }

    /// The chip's pin-one mark lights up with the package's power: dark at
    /// idle, a warm glow near its limit, pulsing only when motion is welcome.
    private func applyGlow(_ glow: Double) {
        chipMark.removeAnimation(forKey: "glow")
        guard look.style == .chip, glow > 0 else {
            chipMark.shadowOpacity = 0
            // Only the chip's mark goes back to its shade: the same layer is
            // a kitsune's brow mark, a penguin's cheeks or a hologram's
            // scanlines, each in a colour of its own.
            if look.style == .chip { chipMark.fillColor = look.bodyPalette.shade.cgColor }
            return
        }
        let warm = NotchMascotWearableShapes.rgb(glow >= 0.75 ? 0xFF6A3D : 0xFFC940)
        chipMark.fillColor = warm
        chipMark.shadowColor = warm
        chipMark.shadowOffset = .zero
        chipMark.shadowRadius = max(0.8, size * 0.08)
        chipMark.shadowOpacity = Float(0.4 + glow * 0.6)
        guard motion else { return }
        let pulse = CABasicAnimation(keyPath: "shadowOpacity")
        pulse.fromValue = Float(0.25 + glow * 0.3)
        pulse.toValue = Float(0.5 + glow * 0.5)
        pulse.duration = 1.6 - glow * 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        chipMark.add(pulse, forKey: "glow")
    }

    /// Turns a second for a fan with the CPU at `effort`: still when idle,
    /// a blur when it works flat out, and a little faster still when hot.
    static func spinRate(effort: Double, mood: MascotAmbient) -> Double {
        let base: Double
        switch effort {
        case ..<0.125: base = 0
        case ..<0.375: base = 0.4
        case ..<0.625: base = 1
        case ..<0.875: base = 2
        default: base = 3.2
        }
        return mood == .overheated ? max(base, 3.2) * 1.2 : base
    }

    /// The repeating motion of one prop.
    private func loop(for layer: CALayer, mood: MascotAmbient) -> CAAnimation {
        let group = CAAnimationGroup()
        group.repeatCount = .infinity
        switch layer {
        case sweatDrop:
            let fall = keyframes("transform.translation.y", [0, 0, size * 0.16], [0, 0.3, 1], additive: true)
            let shine = keyframes("opacity", [0, 1, 1, 0], [0, 0.2, 0.7, 1])
            group.animations = [fall, shine]
            group.duration = mood == .overheated ? 0.9 : 1.7 - ambient.effort * 0.6
        case heat:
            let rise = keyframes("transform.translation.y", [size * 0.04, -size * 0.06], [0, 1], additive: true)
            let shimmer = keyframes("opacity", [0.2, 1, 0.2], [0, 0.5, 1])
            group.animations = [rise, shimmer]
            group.duration = 1.0
        case note:
            let float = keyframes("transform.translation.y", [size * 0.12, -size * 0.12], [0, 1], additive: true)
            let drift = keyframes("transform.translation.x", [0, size * 0.04, -size * 0.02], [0, 0.5, 1], additive: true)
            let show = keyframes("opacity", [0, 1, 1, 0], [0, 0.2, 0.75, 1])
            group.animations = [float, drift, show]
            group.duration = 1.6 - ambient.energy * 0.5
        case steam:
            let rise = keyframes("transform.translation.y", [size * 0.03, -size * 0.06], [0, 1], additive: true)
            let show = keyframes("opacity", [0, 0.9, 0], [0, 0.4, 1])
            group.animations = [rise, show]
            group.duration = 2.0
        case zee:
            let rise = keyframes("transform.translation.y", [size * 0.08, -size * 0.1], [0, 1], additive: true)
            let drift = keyframes("transform.translation.x", [-size * 0.05, size * 0.03], [0, 1], additive: true)
            let show = keyframes("opacity", [0, 1, 0], [0, 0.4, 1])
            group.animations = [rise, drift, show]
            group.duration = 2.6
        case arrow:
            let bob = keyframes("transform.translation.y", [0, size * 0.06, 0], [0, 0.5, 1], additive: true)
            let blink = keyframes("opacity", [1, 0.35, 1], [0, 0.5, 1])
            group.animations = [bob, blink]
            group.duration = 0.9
        case batteryLevel:
            group.animations = [keyframes("opacity", [1, 0.15, 1], [0, 0.5, 1])]
            group.duration = 1.6
        default:
            // Shown and still: the mug, the battery's outline.
            group.animations = [keyframes("opacity", [1, 1], [0, 1])]
            group.duration = 10
        }
        return fitted(group)
    }

    /// A group whose animations all last as long as it does.
    private func fitted(_ group: CAAnimationGroup) -> CAAnimationGroup {
        group.animations?.forEach { $0.duration = group.duration }
        return group
    }

    private func keyframes(_ keyPath: String, _ values: [CGFloat], _ times: [Double],
                           additive: Bool = false) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times.map { NSNumber(value: $0) }
        animation.isAdditive = additive
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }

    // MARK: Fan

    /// Spins the blades at `rate` turns a second, from where they are now,
    /// by changing the speed of one endless turn rather than restarting it.
    private func setSpin(_ rate: Double) {
        if blades.animation(forKey: "spin") == nil {
            guard rate > 0 else { return }
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = 0
            turn.toValue = 2 * Double.pi
            turn.duration = 1
            turn.repeatCount = .infinity
            blades.speed = 0
            blades.timeOffset = 0
            blades.beginTime = 0
            blades.add(turn, forKey: "spin")
        }
        let now = CACurrentMediaTime()
        let local = blades.convertTime(now, from: nil)
        blades.speed = Float(rate)
        blades.timeOffset = local
        blades.beginTime = now
    }

    // MARK: Reactions

    /// What each creature adds to a reaction, and the props it brings.
    func flourish(_ reaction: NotchMascotReaction, reduceMotion: Bool) {
        guard size > 0 else { return }
        let now = CACurrentMediaTime()
        // Props first: these show with or without motion.
        switch reaction {
        case .sweat:
            flash(sweatDrop, for: reaction.length, motion: !reduceMotion,
                  move: ("transform.translation.y", [0, 0, size * 0.16, size * 0.16]))
        case .panic:
            flash(heat, for: reaction.length, motion: !reduceMotion,
                  move: ("transform.translation.y", [size * 0.05, 0, -size * 0.04, -size * 0.06]))
            flash(sweatDrop, for: reaction.length, motion: !reduceMotion,
                  move: ("transform.translation.y", [0, size * 0.06, size * 0.12, size * 0.16]))
        case .sip:
            // Already in hand during Keep Awake, the mug stays out.
            if ambient.ambient != .caffeinated {
                flash(mug, for: reaction.length, motion: false, move: nil)
                flash(steam, for: reaction.length, motion: !reduceMotion,
                      move: ("transform.translation.y", [0, 0, -size * 0.04, -size * 0.06]))
            }
            if !reduceMotion {
                // Up to its face, a tilt for the sip, and back down.
                let lift = keyframes("transform.translation.y", [0, -size * 0.12, -size * 0.12, 0], [0, 0.3, 0.7, 1],
                                     additive: true)
                let toward = keyframes("transform.translation.x", [0, -size * 0.14, -size * 0.14, 0], [0, 0.3, 0.7, 1],
                                       additive: true)
                let tilt = keyframes("transform.rotation.z", [0, -0.25, -0.25, 0], [0, 0.35, 0.7, 1], additive: true)
                let sip = CAAnimationGroup()
                sip.animations = [lift, toward, tilt]
                sip.duration = reaction.length
                mug.add(fitted(sip), forKey: "sip")
            }
        case .peek:
            // Alert face and subtle lean; no disconnected download arrow prop.
            break
        case .wave:
            flash(paw, for: reaction.length, motion: false, move: nil)
            if !reduceMotion {
                let wave = keyframes("transform.translation.y", [size * 0.1, -size * 0.12, -size * 0.12, -size * 0.12, size * 0.1],
                                     [0, 0.2, 0.5, 0.8, 1], additive: true)
                let wiggle = keyframes("transform.translation.x", [0, size * 0.05, -size * 0.04, size * 0.05, 0],
                                       [0, 0.3, 0.5, 0.7, 1], additive: true)
                let group = CAAnimationGroup()
                group.animations = [wave, wiggle]
                group.duration = reaction.length
                paw.add(fitted(group), forKey: "wave")
            }
        case .celebrate:
            if !reduceMotion { burstConfetti() }
        default:
            break
        }
        guard !reduceMotion else { return }
        // Then each creature's own flourish, for anything but a hush or a flash.
        guard reaction != .hush, reaction != .flash else { return }
        switch look.style {
        case .cat:
            // A flick of the ears, which a cheer, a wave or a bow plays over.
            twitchEars(beginTime: now)
            critter.flourish(reaction)
        case .fan:
            // A gust: two quick extra turns that ease off.
            let gust = CABasicAnimation(keyPath: "transform.rotation.z")
            gust.fromValue = 0
            gust.toValue = (reaction == .relax ? 1 : 2) * 2 * Double.pi
            gust.duration = reaction == .relax ? 1.2 : 0.8
            gust.isAdditive = true
            gust.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            bladeHolder.add(gust, forKey: "gust")
        case .ghost:
            let mouth = CAKeyframeAnimation(keyPath: "path")
            let shut = NotchMascotCreatures.ghostMouth(open: false, size: size)
            let open = NotchMascotCreatures.ghostMouth(open: true, size: size)
            mouth.values = [shut, open, open, shut]
            mouth.keyTimes = [0, 0.2, 0.75, 1]
            mouth.duration = min(1.2, reaction.length)
            ghostMouth.add(mouth, forKey: "boo")
            let show = keyframes("opacity", [0, 1, 1, 0], [0, 0.15, 0.8, 1])
            show.duration = mouth.duration
            ghostMouth.add(show, forKey: "booShow")
        case .chip:
            let glow = CAKeyframeAnimation(keyPath: "fillColor")
            glow.values = [look.bodyPalette.shade.cgColor, look.bodyPalette.light.cgColor, look.bodyPalette.shade.cgColor,
                           look.bodyPalette.light.cgColor, look.bodyPalette.shade.cgColor]
            glow.keyTimes = [0, 0.2, 0.45, 0.7, 1]
            glow.duration = min(1, reaction.length)
            pins.add(glow, forKey: "glow")
        case .kitsune:
            twitchEars(beginTime: now)
            let length = min(1.6, max(0.8, reaction.length))
            if Self.fansTails.contains(reaction) {
                // The tails fan out behind it like a crest, and fold back.
                playTails([tailsPose, .fan, .fan, tailsPose], times: [0, 0.25, 0.7, 1], duration: length, key: "flourish")
            } else {
                playTails([tailsPose, .sway, tailsPose], times: [0, 0.5, 1], duration: length, key: "flourish")
            }
            if Self.callsFoxfire.contains(reaction) { foxfire(for: max(1.2, reaction.length)) }
        case .penguin:
            let length = min(1.2, max(0.6, reaction.length))
            if Self.flaps.contains(reaction) {
                // Both flippers beat fast, as if it could fly after all.
                playFlippers([.rest, .up, .rest, .up, .rest, .up, .rest], duration: length, key: "flourish")
            } else {
                playFlippers([.rest, .leftUp, .rest], duration: length * 0.7, key: "flourish")
            }
        case .cristobal, .whiteRabbit:
            let length = min(1.4, max(0.7, reaction.length))
            if reaction == .sip, look.style == .cristobal {
                sip()
            } else if Self.cheers.contains(reaction) {
                playArms([.rest, .up, .up, .rest], duration: length, key: "flourish")
            } else if Self.waves.contains(reaction) {
                playArms([.rest, .wave, .waveOut, .wave, .waveOut, .rest], duration: length, key: "flourish")
            }
        case .hologram, .android:
            signal.flourish(reaction)
        case .ballerina, .danseur, .contemporary:
            dancer.flourish(reaction)
        case .phoenix, .mouse:
            critter.flourish(reaction)
        case .slime, .minimal, .robot, .devourer, .shifter, .axolotl, .dog,
             .capybara, .dragon, .frog, .swan:
            break
        }
    }

    private static let cheers: Set<NotchMascotReaction> = [.celebrate, .bounce, .perk, .ready]
    private static let waves: Set<NotchMascotReaction> = [.wave, .love, .wakeUp]

    private static let fansTails: Set<NotchMascotReaction> = [.celebrate, .surprised, .perk, .bounce, .love, .ready]
    private static let callsFoxfire: Set<NotchMascotReaction> = [.celebrate, .love, .surprised, .ready]
    private static let flaps: Set<NotchMascotReaction> = [.celebrate, .surprised, .perk, .bounce, .ready]

    /// A cat's or a kitsune's ears flick once, on their own now and then or
    /// as it reacts.
    func twitchEars(beginTime: CFTimeInterval? = nil) {
        if look.style == .cat { return critter.twitch(beginTime: beginTime) }
        guard look.style == .kitsune, size > 0, !sleeping else { return }
        let ears = NotchMascotCreatures.kitsuneEars
        for (layer, inner) in [(catEars, false), (catInnerEars, true)] {
            let twitch = CAKeyframeAnimation(keyPath: "path")
            let up = ears(.up, inner, size)
            let flick = ears(.twitch, inner, size)
            twitch.values = [up, flick, up, flick, up]
            twitch.keyTimes = [0, 0.2, 0.45, 0.65, 1]
            twitch.duration = 0.5
            if let beginTime { twitch.beginTime = beginTime }
            layer.add(twitch, forKey: "twitch")
        }
    }

    /// Shows a prop for `duration` and hides it again, moving it with `move`
    /// along the way when motion is welcome.
    private func flash(_ layer: CALayer, for duration: TimeInterval, motion: Bool,
                       move: (keyPath: String, values: [CGFloat])?) {
        let show = keyframes("opacity", [0, 1, 1, 0], [0, 0.12, 0.85, 1])
        var animations: [CAAnimation] = [show]
        if motion, let move {
            animations.append(keyframes(move.keyPath, move.values, [0, 0.3, 0.7, 1], additive: true))
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        layer.add(fitted(group), forKey: "flourish")
    }

    /// Bits of confetti fly up and out from over its head and fall away.
    private func burstConfetti() {
        for (index, piece) in confetti.enumerated() {
            let flight = NotchMascotCreatures.confettiFlights[index]
            let start = CGPoint(x: size * 0.5, y: size * 0.3)
            let top = CGPoint(x: start.x + flight.x * size, y: start.y + flight.y * size)
            let end = CGPoint(x: top.x + flight.x * size * 0.3, y: top.y + size * 0.7)
            let path = CGMutablePath()
            path.move(to: start)
            path.addQuadCurve(to: end, control: CGPoint(x: top.x, y: top.y - size * 0.15))
            let fly = CAKeyframeAnimation(keyPath: "position")
            fly.path = path
            fly.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.6, 1)
            let spin = keyframes("transform.rotation.z", [0, CGFloat(index % 2 == 0 ? 1 : -1) * 6], [0, 1])
            let show = keyframes("opacity", [0, 1, 1, 0], [0, 0.08, 0.7, 1])
            let group = CAAnimationGroup()
            group.animations = [fly, spin, show]
            group.duration = 0.95 + Double(index % 3) * 0.08
            piece.add(fitted(group), forKey: "confetti")
        }
    }

    /// Everything that plays stops, as when the companion is reset.
    func removeAllAnimations() {
        for layer in creatureLayers + propLayers where layer !== blades { layer.removeAllAnimations() }
        signal.removeAllAnimations()
        dancer.removeAllAnimations()
        critter.removeAllAnimations()
        applyAmbient()
    }

    // MARK: Kitsune and penguin

    private var tailsPose: NotchMascotCreatures.TailsPose { sleeping ? .curl : striding ? .stream : .rest }

    private func tailPaths(_ pose: NotchMascotCreatures.TailsPose) -> (tails: CGPath, tips: CGPath) {
        (NotchMascotCreatures.kitsuneTails(count: tails, pose: pose, tips: false, size: size),
         NotchMascotCreatures.kitsuneTails(count: tails, pose: pose, tips: true, size: size))
    }

    private func poseTails(_ pose: NotchMascotCreatures.TailsPose, duration: TimeInterval, animated: Bool) {
        let held = tailPaths(pose)
        morph(pins, to: held.tails, duration: duration, animated: animated)
        morph(tailTips, to: held.tips, duration: duration, animated: animated)
    }

    /// Runs the tails through `poses` once over `duration`, or for ever.
    private func playTails(_ poses: [NotchMascotCreatures.TailsPose], times: [Double], duration: TimeInterval,
                           key: String, repeats: Bool = false, after delay: TimeInterval = 0) {
        for (layer, tips) in [(pins, false), (tailTips, true)] {
            let move = CAKeyframeAnimation(keyPath: "path")
            move.values = poses.map { NotchMascotCreatures.kitsuneTails(count: tails, pose: $0, tips: tips, size: size) }
            move.keyTimes = times.map { NSNumber(value: $0) }
            move.duration = duration
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if repeats { move.repeatCount = .infinity }
            if delay > 0 { move.beginTime = CACurrentMediaTime() + delay }
            layer.add(move, forKey: key)
        }
    }

    /// Runs the flippers through `poses`, evenly spaced, once or for ever.
    private func playFlippers(_ poses: [NotchMascotCreatures.FlipperPose], duration: TimeInterval, key: String,
                              repeats: Bool = false) {
        let move = CAKeyframeAnimation(keyPath: "path")
        move.values = poses.map { NotchMascotCreatures.penguinFlippers($0, size: size) }
        move.keyTimes = poses.indices.map { NSNumber(value: Double($0) / Double(max(1, poses.count - 1))) }
        move.duration = duration
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        if repeats { move.repeatCount = .infinity }
        pins.add(move, forKey: key)
    }

    // MARK: Arms, gauge and light

    /// Folded asleep, otherwise at rest.
    private var armsPose: NotchMascotCreatures.ArmsPose { sleeping ? .folded : .rest }

    /// The android's gauge: a quarter of its ring lit at rest, all of it
    /// with the CPU flat out, none asleep.
    private var gaugeLevel: Int { sleeping ? 0 : min(4, 1 + Int(ambient.effort * 4)) }

    private func armsPath(_ pose: NotchMascotCreatures.ArmsPose) -> CGPath {
        look.style == .cristobal ? NotchMascotCreatures.cristobalSleeves(pose, mug: holdsMug, size: size)
            : NotchMascotCreatures.rabbitArms(pose, size: size)
    }

    /// The comic's two hold their arms in front, over the jumper or the apron.
    private var armsLayer: CAShapeLayer { fanHub }

    private func playArms(_ poses: [NotchMascotCreatures.ArmsPose], duration: TimeInterval, key: String) {
        let times = poses.indices.map { NSNumber(value: Double($0) / Double(max(1, poses.count - 1))) }
        func move(_ paths: [CGPath]) -> CAKeyframeAnimation {
            let move = CAKeyframeAnimation(keyPath: "path")
            move.values = paths
            move.keyTimes = times
            move.duration = duration
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            return move
        }
        armsLayer.add(move(poses.map(armsPath)), forKey: key)
        // Cristóbal's hands go with his sleeves.
        if look.style == .cristobal {
            whiskers.add(move(poses.map(cristobalHandsPath)), forKey: key)
        }
    }

    // MARK: Cristóbal's coffee
    /// Cristóbal has his mug in the morning, while Keep Awake holds the Mac
    /// up, and for a sip; the rest of the day his hands are free.
    private var holdsMug: Bool {
        guard look.style == .cristobal else { return false }
        return Self.coffeeHours.contains(Calendar.current.component(.hour, from: Date()))
            || ambient.ambient == .caffeinated || CACurrentMediaTime() < sipUntil
    }
    /// The morning, when his coffee goes everywhere with him.
    static let coffeeHours = 7..<11
    private func cristobalHandsPath(_ pose: NotchMascotCreatures.ArmsPose) -> CGPath {
        NotchMascotCreatures.cristobalHands(pose, mug: holdsMug, size: size)
    }
    /// Takes up the mug or puts it away when the hour, Keep Awake or a sip says so.
    private func syncMug(animated: Bool) {
        guard look.style == .cristobal, size > 0 else { return }
        let shown: Float = holdsMug ? 1 : 0
        guard dogNose.opacity != shown else { return }
        morph(fanHub, to: armsPath(armsPose), duration: 0.35, animated: animated)
        morph(whiskers, to: cristobalHandsPath(armsPose), duration: 0.35, animated: animated)
        fade(dogNose, to: shown, duration: 0.3, animated: animated)
        fade(slimeDrip, to: holdsMug && !sleeping ? 1 : 0, duration: 0.3, animated: animated)
    }
    /// He brings the mug out if it was put away, lifts it to his mouth for
    /// a sip, lowers it, and puts it away again if it is not coffee time.
    private func sip() {
        guard look.style == .cristobal, size > 0, !sleeping else { return }
        let length: TimeInterval = 1.8
        sipUntil = CACurrentMediaTime() + length + 0.6
        syncMug(animated: true)
        let hold = NotchMascotCreatures.cristobalSleeves(armsPose, mug: true, size: size)
        let lifted = NotchMascotCreatures.cristobalSleeves(armsPose, mug: true, sipping: true, size: size)
        let holdHands = NotchMascotCreatures.cristobalHands(armsPose, mug: true, size: size)
        let liftedHands = NotchMascotCreatures.cristobalHands(armsPose, mug: true, sipping: true, size: size)
        let times: [NSNumber] = [0, 0.3, 0.7, 1]
        func move(_ keyPath: String, _ values: [Any]) -> CAKeyframeAnimation {
            let move = CAKeyframeAnimation(keyPath: keyPath)
            move.values = values
            move.keyTimes = times
            move.duration = length
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            return move
        }
        fanHub.add(move("path", [hold, lifted, lifted, hold]), forKey: "sip")
        whiskers.add(move("path", [holdHands, liftedHands, liftedHands, holdHands]), forKey: "sip")
        let lift = NotchMascotCreatures.cristobalSipLift
        let up = NSValue(caTransform3D: CATransform3DMakeTranslation(lift.dx * size, lift.dy * size, 0))
        let still = NSValue(caTransform3D: CATransform3DIdentity)
        for layer in [dogNose, slimeDrip] { layer.add(move("transform", [still, up, up, still]), forKey: "sip") }
        DispatchQueue.main.asyncAfter(deadline: .now() + length + 0.7) { [weak self] in self?.syncMug(animated: true) }
    }
    /// The android's gauge follows the CPU as the load changes, and the
    /// hologram's and the android's light idles while motion is welcome.
    private func applyGauge() {
        signal.setLevel(gaugeLevel)
        signal.setIdle(motion && !sleeping)
        dancer.setIdle(motion && !sleeping)
        critter.setIdle(motion)
    }

    /// Empty to full, a quarter at a time, then back to what the CPU says.
    func charge(for duration: TimeInterval) {
        signal.charge(for: duration)
    }

    /// A dancer's arms and legs take the steps of `move`.
    func dance(_ move: NotchMascotSoloDance) {
        dancer.dance(move)
        critter.dance(move)
    }
    /// Two wisps of foxfire flicker up beside its head and go out.
    func foxfire(for duration: TimeInterval) {
        guard look.style == .kitsune, size > 0, !sleeping else { return }
        let show = keyframes("opacity", [0, 1, 0.55, 1, 0.65, 1, 0], [0, 0.12, 0.3, 0.45, 0.65, 0.85, 1])
        let float = keyframes("transform.translation.y", [size * 0.05, -size * 0.04, size * 0.01, -size * 0.07],
                              [0, 0.35, 0.7, 1], additive: true)
        let group = CAAnimationGroup()
        group.animations = [show, float]
        group.duration = duration
        wisps.add(fitted(group), forKey: "foxfire")
    }

    /// At rest, with motion welcome, a kitsune's tails sway slowly.
    private func applyIdleTails() {
        for layer in [pins, tailTips] { layer.removeAnimation(forKey: "idleSway") }
        guard look.style == .kitsune, motion, !sleeping, !striding else { return }
        // After any change of pose has played out.
        playTails([.rest, .sway, .rest], times: [0, 0.5, 1], duration: 3.6, key: "idleSway", repeats: true, after: 0.9)
    }

    /// Walking or stopping: a kitsune's tails stream out behind it as it
    /// trots and settle when it stops; a penguin swings one flipper out
    /// then the other, in time with its waddle.
    func setStriding(_ striding: Bool, period: TimeInterval) {
        guard striding != self.striding else { return }
        self.striding = striding
        guard size > 0 else { return }
        switch look.style {
        case .cat:
            critter.setStriding(striding && !sleeping, period: period)
        case .kitsune:
            poseTails(tailsPose, duration: 0.3, animated: true)
        case .penguin:
            pins.removeAnimation(forKey: "stride")
            if striding, !sleeping {
                playFlippers([.rest, .leftUp, .rest, .rightUp, .rest], duration: period, key: "stride", repeats: true)
            }
        case .ballerina, .danseur, .contemporary:
            dancer.setStriding(striding && !sleeping, period: period)
        case .phoenix, .mouse:
            critter.setStriding(striding && !sleeping, period: period)
        default:
            break
        }
        applyIdleTails()
    }

    // MARK: Hops

    /// Ears, tails, wings and props trail the body through a hop of `lift`
    /// points that takes `duration`, at the hop's own key times: they lag
    /// down as it springs up, carry on up past its peak, flop as it lands
    /// and bounce once before they settle.
    func followThrough(beginTime: CFTimeInterval, duration: TimeInterval, lift: CGFloat, keyTimes: [NSNumber]) {
        guard size > 0, duration > 0, keyTimes.count == 7 else { return }
        let reach = min(size * 0.06, lift * 0.12)
        guard reach > 0.2 else { return }
        for (layer, share) in [(back, CGFloat(1)), (props, CGFloat(0.6))] {
            let trail = CAKeyframeAnimation(keyPath: "transform.translation.y")
            trail.values = [0, 0, reach, -reach * 0.8, reach * 1.1, -reach * 0.4, 0].map { $0 * share }
            trail.keyTimes = keyTimes
            trail.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            trail.duration = duration
            trail.beginTime = beginTime
            trail.isAdditive = true
            layer.add(trail, forKey: "followThrough")
        }
    }
}
