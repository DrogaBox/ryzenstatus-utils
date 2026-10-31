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
            fanHub.path = NotchMascotCreatures.cristobalSleeves(armsPose, size: size)
            fanHub.fillColor = palette.light.cgColor
            dogNose.path = NotchMascotCreatures.cristobalMug(size: size)
            dogNose.fillColor = NotchMascotWearableShapes.rgb(0xF6F6F8)
            whiskers.path = NotchMascotCreatures.cristobalHands(armsPose, size: size)
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
            show(catEars, catInnerEars, catTail, plume, chipMark, catNose, fanHub, dogNose, whiskers, fanScrews, ghostMouth)
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
        case .phoenix:
            // Swept wings behind the body; the beak and talons over it.
            pins.path = NotchMascotCreatures.phoenixWings(size: size)
            pins.fillColor = palette.light.cgColor
            show(pins)
            plume.path = NotchMascotCreatures.phoenixBeakAndTalons(size: size)
            plume.fillColor = palette.shade.cgColor
            show(plume)
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
        case .mouse:
            pins.path = NotchMascotCreatures.mouseInnerEarsTail(size: size)
            pins.fillColor = palette.shade.cgColor
            show(pins)
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
        case .ballerina:
            pins.path = NotchMascotCreatures.ballerinaArmsEnHaut(size: size)
            pins.fillColor = palette.light.cgColor
            plume.path = NotchMascotCreatures.ballerinaBodice(size: size)
            plume.fillColor = palette.shade.cgColor
            dogNose.path = NotchMascotCreatures.ballerinaPointesRibbons(size: size)
            dogNose.fillColor = palette.shade.cgColor
            show(pins, plume, dogNose)
        case .danseur:
            pins.path = NotchMascotCreatures.danseurTunicTrim(size: size)
            pins.fillColor = NotchMascotWearableShapes.rgb(0xD4AF37)
            show(pins)
        case .contemporary:
            pins.path = NotchMascotCreatures.contemporarySash(size: size)
            pins.fillColor = palette.shade.cgColor
            show(pins)
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
        case .hologram:
            // One hue from head to toe, her hair a shade darker; a pink visor
            // with its glints, mint boots and trim, fine lines of light across
            // her, and the disc of light she is cast from.
            pins.path = NotchMascotCreatures.hologramArms(armsPose, size: size)
            pins.fillColor = palette.light.cgColor
            plume.path = NotchMascotCreatures.hologramHair(size: size)
            plume.fillColor = palette.shade.cgColor
            dogNose.path = NotchMascotCreatures.hologramVisor(size: size)
            dogNose.fillColor = NotchMascotWearableShapes.rgb(0xFF4FA8)
            catNose.path = NotchMascotCreatures.hologramVisorGlint(size: size)
            catNose.fillColor = NotchMascotWearableShapes.rgb(0xFFE3F2)
            ghostMouth.path = NotchMascotCreatures.hologramTrim(size: size)
            ghostMouth.fillColor = NotchMascotWearableShapes.rgb(0x46E6C4)
            ghostMouth.opacity = 1
            chipMark.path = NotchMascotCreatures.hologramScanlines(size: size)
            chipMark.fillColor = NSColor.white.withAlphaComponent(0.24).cgColor
            glowing(wisps, path: NotchMascotCreatures.hologramProjector(size: size), color: 0x5FF2FF)
            show(pins, plume, dogNose, catNose, ghostMouth, chipMark, wisps)
        case .android:
            // Plates, fin and joints in graphite, the load gauge at its heart,
            // a light on its helmet and the glow it floats on.
            pins.path = NotchMascotCreatures.androidArms(armsPose, size: size)
            pins.fillColor = palette.shade.cgColor
            plume.path = NotchMascotCreatures.androidPlates(size: size)
            plume.fillColor = NotchMascotWearableShapes.rgb(0x3A4252)
            chipMark.path = NotchMascotCreatures.androidGauge(size: size)
            chipMark.fillColor = NotchMascotWearableShapes.rgb(0x262B37)
            dogNose.path = NotchMascotCreatures.androidGaugeCells(level: gaugeLevel, size: size)
            dogNose.fillColor = NotchMascotWearableShapes.rgb(0xFFB547)
            catNose.path = NotchMascotCreatures.androidShine(size: size)
            catNose.fillColor = NSColor.white.withAlphaComponent(0.75).cgColor
            glowing(wisps, path: NotchMascotCreatures.androidHover(size: size), color: 0xFFB547)
            show(pins, plume, chipMark, dogNose, catNose, wisps)
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
            catTail.path = NotchMascotCreatures.catTail(sleeping ? .curl : .rest, size: size)
            catTail.strokeColor = palette.shade.cgColor
            catTail.lineWidth = max(0.8, size * 0.075)
            catEars.path = NotchMascotCreatures.catEars(sleeping ? .droop : .up, inner: false, size: size)
            catEars.fillColor = palette.light.cgColor
            catInnerEars.path = NotchMascotCreatures.catEars(sleeping ? .droop : .up, inner: true, size: size)
            catInnerEars.fillColor = palette.shade.cgColor
            catNose.path = NotchMascotCreatures.catNose(size: size)
            catNose.fillColor = palette.shade.cgColor
            whiskers.path = NotchMascotCreatures.catWhiskers(size: size)
            whiskers.strokeColor = NotchMascotColor.ink.cgColor
            whiskers.opacity = 0.55
            whiskers.lineWidth = max(0.35, size * 0.025)
            show(catTail, catEars, catInnerEars, catNose, whiskers)
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
            morph(catEars, to: NotchMascotCreatures.catEars(sleeping ? .droop : .up, inner: false, size: size),
                  duration: duration, animated: animated)
            morph(catInnerEars, to: NotchMascotCreatures.catEars(sleeping ? .droop : .up, inner: true, size: size),
                  duration: duration, animated: animated)
            morph(catTail, to: NotchMascotCreatures.catTail(sleeping ? .curl : .rest, size: size),
                  duration: duration, animated: animated)
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
            // Arms folded for a nap; Cristóbal keeps hold of his mug.
            morph(fanHub, to: armsPath(armsPose), duration: duration, animated: animated)
            if look.style == .cristobal {
                morph(whiskers, to: NotchMascotCreatures.cristobalHands(armsPose, size: size), duration: duration,
                      animated: animated)
            }
        case .hologram, .android:
            // Arms folded; the projection, or the light it floats on, dims.
            morph(pins, to: armsPath(armsPose), duration: duration, animated: animated)
            fade(wisps, to: sleeping ? 0.35 : 0.85, duration: duration, animated: animated)
            if look.style == .hologram { fade(dogNose, to: sleeping ? 0.45 : 1, duration: duration, animated: animated) }
        case .phoenix, .axolotl, .dog, .mouse, .capybara, .dragon, .frog, .swan, .ballerina, .danseur, .contemporary:
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
            mug: mood == .caffeinated,
            steam: mood == .caffeinated,
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
            twitchEars(beginTime: now)
            if reaction != .lookAround {
                let sway = CAKeyframeAnimation(keyPath: "path")
                let rest = NotchMascotCreatures.catTail(sleeping ? .curl : .rest, size: size)
                sway.values = [rest, NotchMascotCreatures.catTail(.sway, size: size), rest,
                               NotchMascotCreatures.catTail(.sway, size: size), rest]
                sway.keyTimes = [0, 0.25, 0.5, 0.75, 1]
                sway.duration = min(1.4, reaction.length)
                sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                catTail.add(sway, forKey: "sway")
            }
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
            if Self.cheers.contains(reaction) {
                playArms([.rest, .up, .up, .rest], duration: length, key: "flourish")
            } else if Self.waves.contains(reaction) {
                playArms([.rest, .wave, .waveOut, .wave, .waveOut, .rest], duration: length, key: "flourish")
            }
        case .hologram, .android:
            let length = min(1.4, max(0.7, reaction.length))
            if Self.cheers.contains(reaction) {
                playArms([.rest, .up, .up, .rest], duration: length, key: "flourish")
            } else if Self.waves.contains(reaction) {
                playArms([.rest, .wave, .waveOut, .wave, .waveOut, .rest], duration: length, key: "flourish")
            }
            if look.style == .hologram {
                // The projection stutters: the lines of light and the visor
                // flicker, and the disc she is cast from with them.
                let flicker = keyframes("opacity", [1, 0.25, 1, 0.5, 1], [0, 0.12, 0.3, 0.42, 0.6])
                flicker.duration = min(0.8, length)
                for layer in [chipMark, dogNose, wisps] { layer.add(flicker, forKey: "flicker") }
            } else {
                // Its gauge flares white for a moment and the jet beneath it with it.
                let flare = CAKeyframeAnimation(keyPath: "fillColor")
                let amber = NotchMascotWearableShapes.rgb(0xFFB547), white = NotchMascotWearableShapes.rgb(0xFFF4DC)
                flare.values = [amber, white, amber]
                flare.keyTimes = [0, 0.3, 1]
                flare.duration = min(0.9, length)
                dogNose.add(flare, forKey: "flare")
                let jet = keyframes("transform.scale.x", [1, 1.35, 1], [0, 0.3, 1], additive: false)
                jet.duration = flare.duration
                wisps.add(jet, forKey: "flare")
            }
        case .slime, .minimal, .robot, .devourer, .shifter, .phoenix, .axolotl, .dog, .mouse,
             .capybara, .dragon, .frog, .swan, .ballerina, .danseur, .contemporary:
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
        guard look.style == .cat || look.style == .kitsune, size > 0, !sleeping else { return }
        let ears = look.style == .cat ? NotchMascotCreatures.catEars : NotchMascotCreatures.kitsuneEars
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

    // MARK: Hologram and android

    /// Folded asleep, otherwise one hand on the hip.
    private var armsPose: NotchMascotCreatures.ArmsPose { sleeping ? .folded : .rest }

    /// The android's gauge: one cell lit at rest, all four with the CPU
    /// flat out, none asleep.
    private var gaugeLevel: Int { sleeping ? 0 : min(4, 1 + Int(ambient.effort * 4)) }

    private func armsPath(_ pose: NotchMascotCreatures.ArmsPose) -> CGPath {
        switch look.style {
        case .android: return NotchMascotCreatures.androidArms(pose, size: size)
        case .cristobal: return NotchMascotCreatures.cristobalSleeves(pose, size: size)
        case .whiteRabbit: return NotchMascotCreatures.rabbitArms(pose, size: size)
        default: return NotchMascotCreatures.hologramArms(pose, size: size)
        }
    }

    /// The comic's two hold their arms in front, over the jumper or the
    /// apron; the hologram and the android behind.
    private var armsLayer: CAShapeLayer { [.cristobal, .whiteRabbit].contains(look.style) ? fanHub : pins }

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
            whiskers.add(move(poses.map { NotchMascotCreatures.cristobalHands($0, size: size) }), forKey: key)
        }
    }

    /// The android's gauge follows the CPU as the load changes.
    private func applyGauge() {
        guard look.style == .android else { return }
        dogNose.path = NotchMascotCreatures.androidGaugeCells(level: gaugeLevel, size: size)
    }

    /// Empty to full, a cell at a time, then back to what the CPU says.
    func charge(for duration: TimeInterval) {
        guard look.style == .android, size > 0, !sleeping, duration > 0 else { return }
        let levels = [0, 1, 2, 3, 4, 4]
        let fill = CAKeyframeAnimation(keyPath: "path")
        fill.values = levels.map { NotchMascotCreatures.androidGaugeCells(level: $0, size: size) }
        fill.keyTimes = levels.indices.map { NSNumber(value: Double($0) / Double(levels.count - 1)) }
        fill.calculationMode = .discrete
        fill.duration = duration
        dogNose.add(fill, forKey: "charge")
    }

    /// A shape of light with a soft glow round it: a projector's disc, the
    /// jet an android floats on.
    private func glowing(_ layer: CAShapeLayer, path: CGPath, color: UInt32) {
        let light = NotchMascotWearableShapes.rgb(color)
        layer.path = path
        layer.fillColor = light
        layer.shadowColor = light
        layer.shadowOffset = .zero
        layer.shadowRadius = max(1, size * 0.06)
        layer.shadowOpacity = 0.9
        layer.opacity = sleeping ? 0.35 : 0.85
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
        case .kitsune:
            poseTails(tailsPose, duration: 0.3, animated: true)
        case .penguin:
            pins.removeAnimation(forKey: "stride")
            if striding, !sleeping {
                playFlippers([.rest, .leftUp, .rest, .rightUp, .rest], duration: period, key: "stride", repeats: true)
            }
        default:
            break
        }
        applyIdleTails()
    }
}
