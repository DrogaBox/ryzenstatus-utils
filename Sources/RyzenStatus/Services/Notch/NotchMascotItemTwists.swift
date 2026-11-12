// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The figures that do something of their own with a thing worn: the cat
/// chases the snail, the frog eats the bees, the dragon toasts the pizza and
/// the devourer swallows it whole, the ghost's boa floats, the penguin skates
/// for real and the kitsune lights the lantern with foxfire. Looked up by
/// `NotchMascotItemUse.of(_:style:)` before the thing's own use.
enum NotchMascotItemTwists {
    struct Pair: Hashable {
        var style: NotchMascotStyle
        var item: NotchMascotAccessory
    }

    /// Every figure and thing with a twist of its own.
    static var pairs: [Pair] { (table + fairTable).map(\.pair) }

    // swiftlint:disable:next function_body_length
    fileprivate static let table: [(pair: Pair, steps: [(TimeInterval, NotchMascotItemAction)])] = [
        // The cat stalks the snail, pounces, and the snail is gone into its shell.
        (Pair(style: .cat, item: .snail),
         [(0, .face(.mischievous, 1.6)), (0.2, .move(.sneak)), (1.6, .move(.charge)), (1.8, .marker("POUNCE")),
          (2.0, .hide(6)), (2.2, .emote(.question)), (2.3, .react(.confused))]),
        // A paw at the spider on its thread, and a smug look once it is gone.
        (Pair(style: .cat, item: .spiderMonocle),
         [(0, .react(.peek)), (0.3, .face(.mischievous, 1.4)), (1.0, .move(.hop)), (1.2, .marker("SWAT")),
          (1.4, .hide(6)), (1.8, .face(.smug, 1.6))]),
        // Its ball of yarn at last: batted out, chased and claimed.
        (Pair(style: .cat, item: .yoyo),
         [(0, .face(.mischievous, 1.2)), (0.3, .fling(.ball, back: true)), (2.2, .move(.charge)), (2.4, .marker("MINE!")),
          (2.6, .react(.celebrate))]),
        // A tongue out, the bees gone, and a burp it is a little ashamed of.
        (Pair(style: .frog, item: .beeHalo),
         [(0, .face(.greedy, 1.2)), (0.6, .marker("THWIP")), (0.8, .hide(12)), (1.0, .symbol("•", .gold, count: 2)),
          (1.6, .marker("BURP")), (1.8, .face(.embarrassed, 1.6)), (2.0, .react(.love))]),
        (Pair(style: .frog, item: .spiderMonocle),
         [(0, .react(.peek)), (0.4, .marker("THWIP")), (0.6, .hide(8)), (0.9, .face(.greedy, 1.4)), (1.6, .marker("YUM")),
          (1.8, .move(.hop))]),
        // A frog wants the rain, not the umbrella: away with it, and splash.
        (Pair(style: .frog, item: .umbrella),
         [(0, .react(.perk)), (0.3, .symbol("·", .blue, count: 4)), (0.6, .hide(8)), (0.8, .move(.hop)), (1.6, .move(.hop)),
          (1.8, .face(.starstruck, 1.4)), (2.0, .marker("RIBBIT"))]),
        // One puff and the slice comes out bubbling.
        (Pair(style: .dragon, item: .pizzaSlice),
         [(0, .react(.ready)), (0.3, .react(.flash)), (0.3, .sparks), (0.6, .burst(.smoke)), (1.2, .marker("TOASTY")),
          (1.4, .symbol("♨", .gold, count: 2)), (2.0, .hide(9)), (2.1, .face(.starstruck, 1.6))]),
        // Its own breath melts the ice cream before it gets a lick.
        (Pair(style: .dragon, item: .iceCreamCone),
         [(0, .react(.sip)), (0.3, .react(.flash)), (0.4, .sparks), (0.8, .symbol("•", .pink, count: 3)), (1.2, .hide(8)),
          (1.4, .face(.crying, 1.8)), (1.6, .marker("MELTED"))]),
        // An old dragon strokes its beard, thinks, and breathes its answer.
        (Pair(style: .dragon, item: .wizardBeard),
         [(0, .move(.bow)), (0.4, .face(.thinking, 1.8)), (1.6, .burst(.smoke)), (1.6, .marker("HMMM")),
          (2.2, .fling(.fireball, back: false)), (2.4, .react(.celebrate))]),
        // The whole slice at once, and it swells a moment with it.
        (Pair(style: .devourer, item: .pizzaSlice),
         [(0, .face(.greedy, 1.0)), (0.5, .marker("GULP")), (0.6, .hide(12)), (0.8, .grow(4)), (1.0, .burst(.confetti)),
          (1.6, .marker("BURP")), (1.8, .react(.celebrate))]),
        // Swallowed whole, and it still squeaks in there.
        (Pair(style: .devourer, item: .rubberChicken),
         [(0, .face(.greedy, 0.8)), (0.4, .marker("GULP")), (0.5, .hide(10)), (1.4, .marker("SQUEAK")),
          (1.5, .face(.embarrassed, 1.4)), (1.6, .move(.shiver))]),
        // The boa floats round a ghost as if it had no weight at all.
        (Pair(style: .ghost, item: .featherBoa),
         [(0, .move(.float)), (0.2, .react(.wave)), (0.4, .symbol("✿", .pink, count: 3)), (1.4, .move(.float)),
          (2.0, .face(.smug, 2.0)), (2.2, .marker("BOOTIFUL"))]),
        // The lantern under its chin, and the oldest trick there is.
        (Pair(style: .ghost, item: .lantern),
         [(0, .move(.sneak)), (0.2, .face(.mischievous, 2.0)), (0.6, .sparks), (1.6, .marker("BOO!")), (1.6, .burst(.smoke)),
          (2.0, .react(.celebrate))]),
        // On skates a penguin is on ice: a glide, a spin, a backflip, a ten.
        (Pair(style: .penguin, item: .rollerSkates),
         [(0, .move(.charge)), (0.6, .move(.spin)), (1.2, .move(.charge)), (1.4, .symbol("❄", .white, count: 3)),
          (2.0, .move(.backflip)), (2.2, .marker("10.0")), (2.4, .face(.starstruck, 1.8))]),
        // The cold is a treat for a penguin.
        (Pair(style: .penguin, item: .icePack),
         [(0, .react(.love)), (0.3, .symbol("❄", .blue, count: 3)), (0.6, .move(.spin)), (1.4, .face(.starstruck, 1.4)),
          (1.6, .marker("CHILL"))]),
        // Foxfire lights the lantern, blue.
        (Pair(style: .kitsune, item: .lantern),
         [(0, .react(.peek)), (0.3, .burst(.magic)), (0.4, .symbol("✦", .blue, count: 3)), (0.8, .sparks),
          (1.4, .marker("FOXFIRE")), (2.0, .face(.smug, 1.6)), (2.0, .move(.float))]),
        // A kitsune reads the fortune before the cookie is open.
        (Pair(style: .kitsune, item: .fortuneCookie),
         [(0, .react(.peek)), (0.3, .burst(.magic)), (0.8, .marker("DESTINY")), (1.4, .face(.smug, 1.6)),
          (1.5, .symbol("✦", .purple, count: 2))]),
        (Pair(style: .phoenix, item: .lantern),
         [(0, .react(.flash)), (0.2, .sparks), (0.3, .burst(.sparkles)), (1.0, .symbol("♨", .gold, count: 1)),
          (1.4, .marker("LIT")), (1.6, .react(.relax))]),
        // A bird with a kazoo just sings through it.
        (Pair(style: .phoenix, item: .kazoo),
         [(0, .react(.groove)), (0.2, .marker("TWEET")), (0.4, .symbol("♪", .gold, count: 4)), (1.2, .move(.float)),
          (1.8, .face(.starstruck, 1.4))]),
        // Squeak, squeak, fetch, and again.
        (Pair(style: .dog, item: .rubberChicken),
         [(0, .face(.starstruck, 1.0)), (0.2, .marker("SQUEAK")), (0.4, .move(.shiver)), (1.0, .fling(.duck, back: true)),
          (2.8, .react(.celebrate)), (2.9, .marker("AGAIN!"))]),
        // An axolotl has gills: what is the snorkel for?
        (Pair(style: .axolotl, item: .snorkelMask),
         [(0, .react(.confused)), (0.2, .emote(.question)), (0.8, .symbol("○", .blue, count: 3)), (1.6, .face(.smug, 1.8)),
          (1.8, .marker("GILLS"))]),
        (Pair(style: .swan, item: .snorkelMask),
         [(0, .move(.bow)), (0.3, .symbol("○", .blue, count: 4)), (1.2, .move(.float)), (1.4, .marker("SPLASH")),
          (1.8, .react(.celebrate))]),
        // Its own ballet, on its own pointes.
        (Pair(style: .swan, item: .pointeShoes),
         [(0, .move(.bow)), (0.6, .move(.spin)), (1.5, .move(.spin)), (2.4, .symbol("✦", .white, count: 3)),
          (2.6, .marker("ODETTE"))]),
        // Bees, a hoop: a capybara could not care less.
        (Pair(style: .capybara, item: .beeHalo),
         [(0, .react(.relax)), (0.4, .symbol("•", .gold, count: 3)), (1.2, .face(.bored, 2.0)), (1.4, .emote(.ellipsis)),
          (2.6, .marker("ZEN"))]),
        (Pair(style: .capybara, item: .hulaHoop),
         [(0, .move(.spin)), (0.6, .face(.bored, 2.0)), (0.8, .emote(.ellipsis)), (1.6, .doze(6)),
          (1.8, .symbol("z", .white, count: 2))]),
        (Pair(style: .ballerina, item: .featherBoa),
         [(0, .move(.spin)), (0.9, .move(.spin)), (1.0, .symbol("✿", .pink, count: 2)), (1.8, .move(.bow)),
          (1.9, .react(.celebrate)), (2.0, .marker("BRAVA"))]),
        // A slime blows a bubble with all of itself, and wears it when it pops.
        (Pair(style: .slime, item: .bubbleGum),
         [(0, .face(.smug, 1.0)), (0.4, .symbol("○", .pink, count: 3)), (1.4, .marker("POP!")), (1.5, .hide(6)),
          (1.6, .face(.dizzy, 1.8)), (1.7, .move(.shiver)), (2.0, .emote(.interrobang))]),
        // The fan blows the boa to feathers.
        (Pair(style: .fan, item: .featherBoa),
         [(0, .react(.groove)), (0.2, .move(.spin)), (0.4, .symbol("✿", .pink, count: 4)), (1.2, .hide(8)),
          (1.4, .face(.embarrassed, 1.6)), (1.5, .marker("OOPS"))]),
        // The mothership calls the android home, and it answers.
        (Pair(style: .android, item: .ufoHat),
         [(0, .react(.perk)), (0.3, .move(.float)), (0.4, .lightning), (1.2, .marker("HELLO")), (1.4, .burst(.magic)),
          (2.0, .face(.starstruck, 1.4))]),
        (Pair(style: .hologram, item: .ufoHat),
         [(0, .react(.flash)), (0.3, .burst(.sparkles)), (0.6, .move(.float)), (1.2, .marker("SIGNAL")),
          (1.8, .react(.wave))]),
        (Pair(style: .chip, item: .ufoHat),
         [(0, .react(.surprised)), (0.2, .lightning), (0.4, .move(.float)), (1.2, .marker("UPLINK")), (1.6, .sparks)]),
        // A mouse and a pizza: nibble by nibble, crumbs flying.
        (Pair(style: .mouse, item: .pizzaSlice),
         [(0, .react(.peek)), (0.3, .face(.greedy, 1.4)), (0.6, .symbol("•", .gold, count: 3)), (1.0, .marker("NIBBLE")),
          (1.8, .hide(10)), (2.0, .react(.love))]),
        // The robot plays without a single mistake, and knows it.
        (Pair(style: .robot, item: .gameController),
         [(0, .react(.ready)), (0.2, .sparks), (0.6, .marker("101010")), (1.4, .marker("PERFECT")), (1.6, .burst(.coins)),
          (1.8, .face(.smug, 1.4))]),
        // The workshop, in the hands of those who know it best.
        // A capybara and matcha: the calmest moment on the whole desktop.
        (Pair(style: .capybara, item: .matchaBowl),
         [(0, .move(.bow)), (0.6, .react(.sip)), (1.4, .symbol("~", .green, count: 4)), (2.0, .face(.sleepy, 3.0)),
          (2.2, .marker("ZEN")), (2.4, .doze(6))]),
        // A dragon warms the tea with one breath, too much.
        (Pair(style: .dragon, item: .matchaBowl),
         [(0, .react(.sip)), (0.4, .react(.flash)), (0.5, .sparks), (0.8, .burst(.smoke)), (1.4, .marker("HOT!")),
          (1.6, .face(.terrified, 1.4)), (1.8, .move(.hop))]),
        // The cat and the guitar: a scratch, a yowl, and a bow for the applause.
        (Pair(style: .cat, item: .electricGuitar),
         [(0, .face(.mischievous, 1.4)), (0.3, .slash), (0.5, .symbol("♪", .gold, count: 3)), (1.2, .marker("MEOWW")),
          (1.6, .sparks), (2.2, .move(.bow)), (2.4, .face(.smug, 1.6))]),
        // Boxing gloves on a robot: a punch that shakes the floor, and a dent.
        (Pair(style: .robot, item: .boxingGloves),
         [(0, .face(.determined, 2.0)), (0.3, .move(.charge)), (1.0, .lightning), (1.1, .marker("CLANG")), (1.3, .burst(.smoke)),
          (2.0, .face(.embarrassed, 1.4)), (2.2, .emote(.ellipsis))]),
        // The penguin digs the way it knows: a belly slide and snow flying.
        (Pair(style: .penguin, item: .shovel),
         [(0, .react(.perk)), (0.3, .move(.slip)), (0.6, .symbol("❄", .white, count: 4)), (1.4, .move(.stomp)),
          (1.9, .gold(20)), (2.1, .react(.celebrate))]),
        // A mouse with a telescope sees the moon, and asks for cheese.
        (Pair(style: .mouse, item: .telescope),
         [(0, .react(.peek)), (0.8, .emote(.exclaim)), (1.0, .face(.greedy, 1.8)), (1.2, .marker("CHEESE?")),
          (1.8, .fling(.star, back: false)), (2.2, .react(.love))]),
        // The frog needs no pogo stick, but with one it reaches the ceiling.
        (Pair(style: .frog, item: .pogoStick),
         [(0, .react(.perk)), (0.2, .move(.highJump)), (1.0, .move(.highJump)), (1.6, .marker("RIBBOING")),
          (2.2, .move(.highJump)), (2.8, .face(.starstruck, 1.4))]),
        // The hologram paints in light, and the picture floats off.
        (Pair(style: .hologram, item: .painterBeret),
         [(0, .face(.thinking, 1.2)), (0.6, .sparks), (0.9, .symbol("✦", .blue, count: 4)), (1.6, .burst(.magic)),
          (1.8, .marker("PIXELS")), (2.2, .react(.celebrate))]),
        // A karate belt on the danseur: the kata becomes a dance.
        (Pair(style: .danseur, item: .karateBelt),
         [(0, .face(.determined, 2.0)), (0.2, .move(.spin)), (0.9, .slash), (1.2, .marker("HAI-YAH")), (1.4, .move(.highJump)),
          (2.2, .move(.bow)), (2.4, .face(.smug, 1.4))]),
    ]

    fileprivate static let byPair: [Pair: [(TimeInterval, NotchMascotItemAction)]] =
        Dictionary((table + fairTable).map { ($0.pair, $0.steps) }, uniquingKeysWith: { first, _ in first })

    static func steps(_ item: NotchMascotAccessory, style: NotchMascotStyle) -> [(TimeInterval, NotchMascotItemAction)]? {
        byPair[Pair(style: style, item: item)]
    }
}

extension NotchMascotItemUse {
    /// What `style` does with `item` its own way, if it has a way of its own.
    static func twist(_ item: NotchMascotAccessory, style: NotchMascotStyle) -> NotchMascotItemUse? {
        NotchMascotItemTwists.steps(item, style: style).map { NotchMascotItemUse($0) }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    /// The oddities and wonders, each with its own little show and a face
    /// to go with it.
    static func oddityUse(_ item: NotchMascotAccessory) -> NotchMascotItemUse? {
        switch item {
        case .pizzaSlice:
            // The cheese stretches and stretches, then the slice is gone.
            return .init([(0, .react(.perk)), (0.3, .face(.greedy, 1.6)), (0.6, .symbol("~", .gold, count: 2)),
                          (1.4, .marker("NOM")), (1.5, .hide(9)), (1.9, .react(.love)), (2.0, .symbol("♥", .pink, count: 1))])
        case .kazoo:
            // A proud fanfare, horribly out of tune.
            return .init([(0, .react(.groove)), (0.2, .marker("BZZZ")), (0.3, .symbol("♪", .gold, count: 3)), (1.2, .move(.strut)),
                          (2.2, .face(.embarrassed, 1.6))])
        case .bubbleGum:
            // The bubble grows, and grows, and pops all over its face.
            return .init([(0, .react(.perk)), (0.2, .face(.smug, 1.2)), (0.5, .symbol("○", .pink, count: 2)), (1.5, .marker("POP!")),
                          (1.5, .react(.surprised)), (1.6, .hide(5)), (1.8, .face(.embarrassed, 1.8)), (1.9, .emote(.exclaim))])
        case .crackerCrown:
            // Bang, a paper crown, and the terrible joke inside.
            return .init([(0, .marker("BANG!")), (0, .burst(.confetti)), (0.4, .react(.surprised)), (1.0, .move(.bow)),
                          (1.2, .face(.smug, 1.8)), (1.4, .symbol("✦", .gold, count: 2)), (2.4, .marker("HAHA"))])
        case .rubberChicken:
            return .init([(0, .move(.shiver)), (0.2, .marker("BAWK!")), (0.3, .react(.surprised)), (0.8, .marker("SQUEAK")),
                          (1.5, .move(.spin)), (2.2, .react(.celebrate))])
        case .snail:
            // A slow walk with its slow friend, and a lot of love.
            return .init([(0, .react(.peek)), (0.3, .move(.sneak)), (0.5, .symbol("♥", .green, count: 1)), (1.8, .emote(.heart)),
                          (2.0, .face(.love, 1.6))])
        case .jesterHat:
            return .init([(0, .move(.backflip)), (0.1, .marker("JINGLE")), (0.2, .symbol("♪", .gold, count: 3)), (1.3, .move(.spin)),
                          (2.2, .face(.mischievous, 1.8)), (2.3, .marker("HAHA!"))])
        case .snorkelMask:
            // A swim through the air, bubbles and all, and a fish to think of.
            return .init([(0, .react(.perk)), (0.2, .symbol("○", .blue, count: 4)), (0.5, .move(.float)), (1.6, .marker("BLUB")),
                          (2.2, .emote(.thought("><>"))), (2.4, .react(.relax))])
        case .pirateHook:
            return .init([(0, .move(.strut)), (0.2, .marker("ARRR!")), (0.9, .slash), (1.5, .burst(.coins)),
                          (1.6, .face(.greedy, 1.8))])
        case .featherBoa:
            return .init([(0, .move(.strut)), (0, .react(.wave)), (0.5, .symbol("✿", .pink, count: 2)), (1.2, .move(.spin)),
                          (1.9, .face(.smug, 2.0)), (2.2, .marker("DIVA"))])
        case .rollerSkates:
            // Off it rolls, faster, faster, and down it goes.
            return .init([(0, .move(.charge)), (0.8, .move(.spin)), (1.6, .move(.slip)), (1.8, .burst(.smoke)),
                          (1.9, .marker("OOF")), (2.0, .face(.dizzy, 1.6)), (2.1, .emote(.curse))])
        case .lantern:
            // Into the dark with the lantern, until its own shadow scares it.
            return .init([(0, .move(.sneak)), (0, .react(.peek)), (0.4, .sparks), (1.2, .emote(.question)),
                          (2.0, .face(.terrified, 1.4)), (2.0, .emote(.exclaim)), (2.2, .move(.hop))])
        case .wizardBeard:
            // It strokes its beard and thinks, and has an idea.
            return .init([(0, .move(.bow)), (0.3, .face(.thinking, 1.8)), (0.3, .emote(.ellipsis)), (2.0, .emote(.idea)),
                          (2.0, .burst(.magic)), (2.2, .marker("EUREKA")), (2.4, .react(.celebrate))])
        case .beeHalo:
            // The bees get cross, and it runs.
            return .init([(0, .react(.panic)), (0.2, .marker("BZZ")), (0.4, .move(.charge)), (1.2, .face(.terrified, 1.8)),
                          (1.4, .symbol("•", .gold, count: 4)), (2.4, .move(.hop)), (2.6, .react(.sweat))])
        case .spiderMonocle:
            // A closer look through the lens, and a spider looks back.
            return .init([(0, .react(.peek)), (0.5, .symbol("?", .white, count: 1)), (1.4, .emote(.exclaim)),
                          (1.4, .face(.terrified, 1.6)), (1.5, .move(.backflip)), (2.7, .marker("EEK!"))])
        case .ufoHat:
            // Beamed up a little way, and set down again starstruck.
            return .init([(0, .react(.surprised)), (0.2, .move(.float)), (0.3, .burst(.magic)), (0.4, .symbol("✦", .green, count: 3)),
                          (1.6, .marker("BEEP")), (2.2, .face(.starstruck, 1.8)), (2.4, .emote(.thought("?!")))])
        default:
            return nil
        }
    }
}
