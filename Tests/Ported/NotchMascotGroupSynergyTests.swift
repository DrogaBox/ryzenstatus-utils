// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The gang's group synergies: who makes a band, a match or a campfire, in
/// which order the rules are read, and who starts each one.
enum NotchMascotGroupSynergyTests {
    typealias Group = NotchMascotGroupSynergy

    static func run(_ suite: TestSuite) {
        gangSize(suite)
        eachRule(suite)
        precedence(suite)
        starters(suite)
    }

    private static let three: [NotchMascotStyle] = [.cat, .dog, .frog]

    private static func gangSize(_ suite: TestSuite) {
        suite.expect(Group.find([.drum, .bardLute], styles: [.cat, .dog], hour: 12) == nil,
                     "two are a duo, not a group")
        suite.expect(Group.find([.drum, .bardLute, .none], styles: three, hour: 12) == .band,
                     "a third with empty hands makes it a group")
        suite.expect(Group.find([.none, .none, .none], styles: three, hour: 12) == nil,
                     "a gang with nothing in hand makes nothing")
        suite.expect(Group.find([.crown, .bow, .scarf, .cap], styles: three + [.ghost], hour: 12) == nil,
                     "things no rule names make nothing")
    }

    private static func eachRule(_ suite: TestSuite) {
        suite.expect(Group.find([.marshmallowStick, .none, .none], styles: [.dragon, .cat, .dog], hour: 12) == .campfire
                     && Group.find([.marshmallowStick, .none, .none], styles: [.cat, .phoenix, .dog], hour: 12) == .campfire,
                     "a dragon or a phoenix lights the campfire")
        suite.expect(Group.find([.marshmallowStick, .marshmallowStick, .none], styles: three, hour: 22) == .campfire
                     && Group.find([.marshmallowStick, .marshmallowStick, .none], styles: three, hour: 3) == .campfire
                     && Group.find([.marshmallowStick, .marshmallowStick, .none], styles: three, hour: 14) == nil,
                     "two sticks make a campfire only at night")
        suite.expect(Group.find([.kite, .stormCloud, .none], styles: three, hour: 12) == .kiteStorm, "a kite meets the storm")
        suite.expect(Group.find([.pillow, .pillow, .none], styles: three, hour: 12) == .pillowFight, "two pillows fight")
        suite.expect(Group.find([.waterPistol, .waterPistol, .none], styles: three, hour: 12) == .waterFight
                     && Group.find([.waterPistol, .umbrella, .none], styles: three, hour: 12) == .waterFight,
                     "two pistols, or a pistol and an umbrella, make a water fight")
        suite.expect(Group.find([.microphone, .headphones, .none], styles: three, hour: 12) == .band
                     && Group.find([.maracas, .maracas, .none], styles: three, hour: 12) == .band,
                     "two instruments make a band")
        suite.expect(Group.find([.microphone, .microphone, .none], styles: three, hour: 12) == .karaoke
                     && Group.find([.microphone, .discoBall, .none], styles: three, hour: 12) == .karaoke,
                     "microphones alone, or one under a disco ball, make karaoke")
        suite.expect(Group.find([.microphone, .none, .none], styles: three, hour: 12) == nil,
                     "one microphone alone is no karaoke")
        suite.expect(Group.find([.soccerBall, .whistle, .none], styles: three, hour: 12) == .match
                     && Group.find([.soccerBall, .soccerBall, .none], styles: three, hour: 12) == .match,
                     "a ball with a whistle or a second ball makes a match")
        suite.expect(Group.find([.jugglingBalls, .clownNose, .none], styles: three, hour: 12) == .juggling,
                     "the juggler and the clown")
        suite.expect(Group.find([.picnicBasket, .onigiri, .none], styles: three, hour: 12) == .picnic
                     && Group.find([.picnicBasket, .none, .none], styles: [.capybara, .cat, .dog], hour: 12) == .picnic
                     && Group.find([.picnicBasket, .picnicBasket, .none], styles: three, hour: 12) == .picnic
                     && Group.find([.picnicBasket, .none, .none], styles: three, hour: 12) == nil,
                     "a basket wants food, a capybara or a second basket")
        suite.expect(Group.find([.partyHat, .hulaHoop, .spanishFan], styles: three, hour: 12) == .conga
                     && Group.find([.partyHat, .hulaHoop, .none], styles: three, hour: 12) == nil,
                     "three in dancing gear make a conga")
    }

    private static func precedence(_ suite: TestSuite) {
        suite.expect(Group.find([.marshmallowStick, .drum, .bardLute], styles: [.dragon, .cat, .dog], hour: 12) == .campfire,
                     "the campfire comes before the band")
        suite.expect(Group.find([.maracas, .maracas, .partyHat], styles: three, hour: 12) == .band,
                     "two maracas play in the band before they dance the conga")
        suite.expect(Group.find([.waterPistol, .waterPistol, .pillow, .pillow], styles: three + [.ghost], hour: 12) == .pillowFight,
                     "the pillow fight comes before the water fight")
        let gangs: [[NotchMascotAccessory]] = [[.kite, .stormCloud, .soccerBall, .whistle],
                                               [.picnicBasket, .ramenBowl, .jugglingBalls, .clownNose]]
        suite.expect(gangs.allSatisfy { gang in
                         Group.find(gang, styles: three + [.ghost], hour: 12)
                             == Group.find(gang, styles: three + [.ghost], hour: 12)
                     }, "the same gang always makes the same thing")
        suite.expect(Group.allCases.allSatisfy { !$0.keyItems.isEmpty }, "every group synergy names what makes it")
    }

    private static func starters(_ suite: TestSuite) {
        suite.expect(Group.kiteStorm.starter(among: [.stormCloud, .none, .kite]) == 2, "the kite starts the storm")
        suite.expect(Group.band.starter(among: [.bardLute, .microphone, .drum]) == 2
                     && Group.band.starter(among: [.none, .microphone, .bardLute]) == 1,
                     "the drum counts the band in, else the first instrument")
        suite.expect(Group.match.starter(among: [.soccerBall, .none, .whistle]) == 2, "the referee starts the match")
        suite.expect(Group.picnic.starter(among: [.none, .picnicBasket, .none]) == 1, "the basket opens the picnic")
        suite.expect(Group.conga.starter(among: [.none, .hulaHoop, .partyHat]) == 1, "the first dancer leads the conga")
        suite.expect(Group.juggling.starter(among: [.none, .none, .none]) == nil, "nobody starts what nobody holds")
    }
}
