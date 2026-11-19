// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// Rolling digits drawn by Core Animation: how a reading splits into numbers
/// and text, which places roll, enter or leave, which way they go, and that
/// the view animates only on screen, at the pace asked for.
enum RollingDigitsTests {
    typealias Plan = RollingDigits.Plan

    static func run(_ suite: TestSuite) {
        tokens(suite)
        places(suite)
        plans(suite)
        direction(suite)
        view(suite)
        whenItRolls(suite)
        callSites(suite)
    }

    private static func tokens(_ suite: TestSuite) {
        let cases: [(String, [RollingDigits.Token])] = [
            ("45%", [.digits("45"), .text("%")]),
            ("↓ 1.2 MB/s", [.text("↓ "), .digits("1"), .text("."), .digits("2"), .text(" MB/s")]),
            ("CPU 58° · RAM 62%", [.text("CPU "), .digits("58"), .text("° · RAM "), .digits("62"), .text("%")]),
            ("24:59", [.digits("24"), .text(":"), .digits("59")]),
            ("≥ $12.34", [.text("≥ $"), .digits("12"), .text("."), .digits("34")]),
            ("000420", [.digits("000420")]),
            ("…", [.text("…")]),
            ("Title · Artist", [.text("Title · Artist")]),
            ("", []),
        ]
        for (string, expected) in cases {
            suite.expect(RollingDigits.tokens(string) == expected, "\(string) splits into its numbers and text")
        }
    }

    private static func places(_ suite: TestSuite) {
        let whole = RollingDigits.slots("120W").map(\.identity)
        suite.expect(whole == [.digit(run: 0, place: 2), .digit(run: 0, place: 1), .digit(run: 0, place: 0), .text(run: 1)],
                     "a whole number counts its places from the right, so the ones stay the ones")
        let fraction = RollingDigits.slots("1.25").map(\.identity)
        suite.expect(fraction == [.digit(run: 0, place: 0), .text(run: 1), .digit(run: 2, place: 0), .digit(run: 2, place: 1)],
                     "digits after a decimal point count from the left")
    }

    private static func plans(_ suite: TestSuite) {
        let one = RollingDigits.plan(from: "42%", to: "43%")
        suite.expect(one.rolls && one.changes == [.still, .roll(from: "2"), .still] && one.leaving.isEmpty,
                     "only the digit that changed moves")
        let grows = RollingDigits.plan(from: "9%", to: "10%")
        suite.expect(grows.rolls && grows.changes == [.enter, .roll(from: "9"), .still],
                     "9 -> 10: the ones roll in place and the tens come in")
        let shrinks = RollingDigits.plan(from: "100%", to: "99%")
        suite.expect(shrinks.changes == [.roll(from: "0"), .roll(from: "0"), .still]
                     && shrinks.leaving == [.digit(run: 0, place: 2)],
                     "100 -> 99: the hundreds leave")
        let decimal = RollingDigits.plan(from: "1.9", to: "2.0")
        suite.expect(decimal.changes == [.roll(from: "1"), .still, .roll(from: "9")], "1.9 -> 2.0 rolls both digits")
        let same = RollingDigits.plan(from: "55%", to: "55%")
        suite.expect(same.changes.allSatisfy { $0 == .still }, "the same reading moves nothing")
        for (old, new) in [("…", "45%"), ("999 KB/s", "1.0 MB/s"), ("CPU 58°", "RAM 62%"), ("", "7")] {
            let swap = RollingDigits.plan(from: old, to: new)
            suite.expect(!swap.rolls && swap.changes.allSatisfy { $0 == .enter },
                         "\(old) -> \(new): other text around the numbers swaps the line whole")
        }
    }

    private static func direction(_ suite: TestSuite) {
        suite.expect(RollingDigits.plan(from: "9%", to: "10%").up && !RollingDigits.plan(from: "10%", to: "9%").up,
                     "a growing value rolls up, a shrinking one down")
        suite.expect(RollingDigits.plan(from: "1.9 MB/s", to: "2.0 MB/s").up, "decimals are read as one value")
        suite.expect(!RollingDigits.plan(from: "24:59", to: "24:58", countsDown: true).up
                     && RollingDigits.plan(from: "24:58", to: "24:59", countsDown: false).up,
                     "a caller that says which way it counts is obeyed")
        suite.expect(RollingDigits.value("↓ 1.25 MB/s") == 1.25 && RollingDigits.value("…") == 0,
                     "the value of a line is its numbers")
    }

    private static func view(_ suite: TestSuite) {
        let view = RollingDigitsView(frame: CGRect(x: 0, y: 0, width: 120, height: 28))
        let style = RollingDigitsStyle.rounded(22, .medium)
        let slow = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        view.configure(style: style, color: .white, duration: 0.25, frameRates: slow, minimumScaleFactor: 0.75)
        view.show("42%", animated: false, countsDown: nil)
        suite.expect(view.text == "42%" && view.naturalSize.width > 0 && view.naturalSize.height >= 22,
                     "the line takes the size its text needs")
        view.show("43%", animated: true, countsDown: nil)
        suite.expect(view.lastAnimations.isEmpty, "out of any window, a change snaps with nothing animated")
        view.setVisible(true)
        view.show("44%", animated: true, countsDown: nil)
        let animations = view.lastAnimations
        suite.expect(animations.count == 2, "on screen, the changed digit's old glyph leaves and its new one enters")
        func paces(_ animation: CAAnimation) -> Bool {
            let range = animation.preferredFrameRateRange
            let own = range.minimum == slow.minimum && range.maximum == slow.maximum && range.preferred == slow.preferred
            return own && ((animation as? CAAnimationGroup)?.animations ?? []).allSatisfy(paces)
        }
        suite.expect(!animations.isEmpty && animations.allSatisfy(paces), "every animation asks for the pace given")
        view.show("45%", animated: false, countsDown: nil)
        suite.expect(view.lastAnimations.isEmpty, "with Reduce Motion or a still transaction nothing animates")
        view.setVisible(false)
        view.show("46%", animated: true, countsDown: nil)
        suite.expect(view.lastAnimations.isEmpty && view.text == "46%", "hidden or covered, a change still lands, unanimated")
        suite.expect(view.hitTest(CGPoint(x: 10, y: 10)) == nil, "clicks go to the tile's button")
        suite.expect(view.accessibilityValue() as? String == "46%", "VoiceOver reads the text")

        view.setVisible(true)
        view.show("↓ 9.6 MB/s", animated: false, countsDown: nil)
        view.frame = CGRect(x: 0, y: 0, width: view.naturalSize.width * 0.5, height: 28)
        view.layout()
        suite.expect(view.isTruncated, "too wide even at its smallest, the line ends in an ellipsis as Text does")
        view.frame = CGRect(x: 0, y: 0, width: view.naturalSize.width * 0.8, height: 28)
        view.layout()
        suite.expect(!view.isTruncated, "a line that fits once shrunk is shrunk, not cut")
        let glyphs = RollingDigitsGlyphs.shared
        let font = style.font()
        let cut = glyphs.truncated("↓ 9.6 MB/s", font: font, width: glyphs.width(of: "↓ 9.6", font: font) + 1)
        suite.expect(cut.hasSuffix("…") && glyphs.width(of: cut, font: font) <= glyphs.width(of: "↓ 9.6", font: font) + 1,
                     "the cut line fits its room with its ellipsis")
        suite.expect(glyphs.width(of: "0", font: font) == glyphs.width(of: "1", font: font),
                     "every digit is as wide as the others")
        let gold = RollingDigitsStyle(size: 11, weight: .heavy, design: .monospaced).font()
        suite.expect(glyphs.width(of: "0", font: gold) == glyphs.width(of: "W", font: gold),
                     "design: .monospaced draws every glyph as wide as the others")
        let level = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        suite.expect(RollingDigitsStyle.font(level).font() == level, "a font given whole is used as it is")
        suite.expect(view.firstBaselineOffsetFromTop + view.lastBaselineOffsetFromBottom
                     == RollingDigitsGlyphs.shared.metrics(for: font).lineHeight,
                     "the baselines sit inside the line, for .firstTextBaseline next to a Text")
    }

    /// As numericText: a change rolls only inside an animation that is not
    /// disabled, never under Reduce Motion; the marquee's copy passes its own.
    private static func whenItRolls(_ suite: TestSuite) {
        let animated = Transaction(animation: .smooth(duration: 0.25))
        var disabled = animated
        disabled.disablesAnimations = true
        let rolls = RollingDigitsText.animates
        suite.expect(rolls(false, animated, nil), "a change inside the call site's animation rolls")
        suite.expect(!rolls(false, Transaction(), nil), "a change with no animation lands in place")
        suite.expect(!rolls(false, disabled, nil), "a transaction that disables animations lands in place")
        suite.expect(!rolls(true, animated, nil) && !rolls(true, disabled, .default),
                     "Reduce Motion lands every change in place")
        suite.expect(rolls(false, disabled, .default), "the marquee's still copy rolls with the animation it passes")
    }

    /// Every call site names its colour (a layer does not inherit SwiftUI's
    /// foreground style), and numericText is left only where it is meant to be.
    private static func callSites(_ suite: TestSuite) {
        let component = source("Sources/RyzenStatus/UI/Notch/RollingDigits.swift")
        suite.expect(component.contains("    var color: Color\n")
                     && component.contains("style: RollingDigitsStyle, color: Color, countsDown"),
                     "the colour has no default, so leaving it out does not compile")
        let files = (FileManager.default.enumerator(atPath: "Sources/RyzenStatus")?.allObjects as? [String] ?? [])
            .filter { $0.hasSuffix(".swift") && !$0.hasSuffix("RollingDigits.swift") }
        var numeric: [String] = []
        for file in files where source("Sources/RyzenStatus/\(file)").contains(".contentTransition(.numericText(") {
            numeric.append((file as NSString).lastPathComponent)
        }
        // A notice's title changes rarely. The menu panel keeps SwiftUI's text:
        // on its popover material in light mode SwiftUI draws .primary and
        // .secondary vibrant, which an image layer cannot match (it does match
        // in dark mode), and the panel's readings only change while it is open.
        let allowed: Set<String> = ["NotchNoticeView.swift", "AmdControlSection.swift", "DiskSection.swift",
                                    "NetworkSection.swift", "PowerSection.swift"]
        suite.expect(!numeric.isEmpty && Set(numeric).isSubset(of: allowed),
                     "no island reading draws numericText any more (\(numeric.sorted()))")
    }

    private static func source(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }
}
