// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Foundation

/// The GPU control page's accessibility items A3, A4, A6, A8 and A10 to A16:
/// on the models and the texts where they can run without a window, and on
/// the views' source where only the view itself can say it.
enum GPUControlA11yTests {
    static func run(_ suite: TestSuite) {
        keyboardSlider(suite)
        disabledReasons(suite)
        discardDraft(suite)
        chartValue(suite)
        liveRow(suite)
        sliderHelp(suite)
        texts(suite)
        views(suite)
    }

    private static func source(_ name: String) -> String {
        (try? String(contentsOfFile: FileManager.default.currentDirectoryPath + "/Sources/RyzenStatus/UI/Settings/" + name,
                     encoding: .utf8)) ?? ""
    }

    /// Spins the main run loop until `done` or the time is up.
    private static func wait(_ seconds: TimeInterval, until done: () -> Bool = { false }) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    // MARK: A3

    /// Held arrow keys send one request after they pause; the mouse sends
    /// when it lets go, at once.
    private static func keyboardSlider(_ suite: TestSuite) {
        MainActor.assumeIsolated {
            var released = 0
            var values: [Double] = []
            let slider = GPUControlTickSlider(value: 2_000, range: 1_500...2_400, ticks: 10, label: "GFX",
                                              onChange: { values.append($0) }, onRelease: { released += 1 })
            let coordinator = GPUControlTickSlider.Coordinator(parent: slider)
            suite.expect(GPUControlTickSlider.Coordinator.keyPause == .milliseconds(300), "the keys pause 300 ms")
            coordinator.keyPause = .milliseconds(40)
            for step in 0..<6 { coordinator.moved(to: 2_000 - Double(step) * 25, event: .keyDown) }
            suite.expect(released == 0 && values.count == 6, "six arrow presses: the value follows, nothing sent yet")
            wait(1) { released > 0 }
            suite.expect(released == 1, "six quick presses, then a pause: one request (\(released))")
            wait(0.15)
            suite.expect(released == 1, "and only one")

            coordinator.moved(to: 1_900, event: .leftMouseDragged)
            suite.expect(released == 1, "a drag sends nothing")
            coordinator.moved(to: 1_900, event: .leftMouseUp)
            suite.expect(released == 2, "letting go of the mouse sends at once")

            coordinator.moved(to: 1_875, event: .keyDown)
            coordinator.moved(to: 1_850, event: .leftMouseUp)
            suite.expect(released == 3, "a mouse release after a key sends at once")
            wait(0.2)
            suite.expect(released == 3, "and the key's pending send is dropped")
            coordinator.moved(to: 1_850, event: nil)
            suite.expect(released == 4, "no event (an accessibility client set the value): sends at once")
        }
        let view = source("GPUControlClockSection.swift")
        suite.expect(view.contains("private var enabled: Bool { usable && !input.isPending }"),
                     "the field and the stepper wait for the request")
        suite.expect(view.contains("slider.frame(minWidth: Self.sliderMinWidth).disabled(!usable)")
                        && view.contains("slider.disabled(!usable)") && view.contains("        .disabled(!enabled)\n"),
                     "while a request waits only the field and the stepper are off, not the slider")
        suite.expect(!view.contains("makeFirstResponder"), "the focus is never moved")
    }

    // MARK: A14

    private static func disabledReasons(_ suite: TestSuite) {
        typealias C = GPUControlPageContent
        let s = GPUControlPageStrings.es
        func input(_ state: GPUControlPageState?, pending: Bool = false) -> GPUControlPageInput {
            var snapshot = GPUControlSnapshot()
            if pending { snapshot.activity = .applying(.power(watts: 220)) }
            return GPUControlPageInput(facts: GPUControlFacts(source: .properties), state: state, snapshot: snapshot)
        }
        suite.expect(C.disabledReason(input(.closed), s) == s.closed, "closed: the control is closed")
        suite.expect(C.disabledReason(input(.waitingForDriver), s) == s.waitingForDriver, "waiting for the driver")
        suite.expect(C.disabledReason(input(nil), s) == s.waitingForDriver, "no state yet: waiting for the driver")
        suite.expect(C.disabledReason(input(.ready, pending: true), s) == s.applying, "a request out: applying")
        suite.expect(C.disabledReason(input(.readOnlyCard), s) == s.readOnlyTitle, "the read-only card says so")
        suite.expect(C.disabledReason(input(.ready), s) == nil, "ready: nothing to explain")
        suite.expect(C.accessibilityValue("240 W", reason: nil, s) == "240 W", "no reason: the value alone")
        suite.expect(C.accessibilityValue("240 W", reason: s.closed, s) == "240 W, " + s.closed,
                     "the value, then why it is dimmed")
        suite.expect(C.accessibilityValue("", reason: s.closed, s) == s.closed, "a button with no value: the reason")
        let ja = GPUControlPageStrings.ja
        suite.expect(C.accessibilityValue("240 W", reason: ja.closed, ja) == "240 W" + ja.listSeparator + ja.closed,
                     "each language's own list separator")
        let page = source("GPUControlSettingsView.swift")
        let fan = source("GPUControlFanSection.swift")
        let clock = source("GPUControlClockSection.swift")
        suite.expect(page.contains("reason: enabled ? nil : Self.disabledReason(input, s), s))"),
                     "the power pop-up says why it is dimmed")
        suite.expect(fan.contains(".accessibilityValue(GPUControlPageContent.disabledReason(input, strings) ?? \"\")"),
                     "Apply curve says why it is dimmed")
        suite.expect(clock.contains("reason: usable ? nil : reason, strings)") && clock.contains("reason: enabled ? nil : reason, strings))"),
                     "the slider and the stepper say why they are dimmed")
    }

    // MARK: A10

    private static func discardDraft(_ suite: TestSuite) {
        let held = GPUControlOD8Want(curve: GPUControlFanDraft.testedCurve, zeroRpmOff: true)
        var draft = GPUControlFanDraft(held: held)
        draft.points[2].speedPercent = 60
        suite.expect(draft.edited, "an edit marks the draft")
        suite.expect(draft.following(held: held) == draft, "following(held:) keeps the edit: not what Escape needs")
        let discarded = GPUControlFanSection.discarded(held: held)
        suite.expect(!discarded.edited && discarded.points == held.curve && discarded.customCurve && discarded.zeroRpmOff,
                     "Escape: the held curve and zero RPM back, unedited")
        let stock = GPUControlFanSection.discarded(held: .stock)
        suite.expect(stock == GPUControlFanDraft() && !stock.edited, "nothing held: the starting draft")
        let view = source("GPUControlFanSection.swift")
        suite.expect(view.contains(".onExitCommand(perform: discardDraft)") && view.contains("guard draft.edited else { return }")
                        && view.contains("AccessibilityNotification.Announcement(fan.draftDiscarded).post()"),
                     "Escape in the editor discards an edited draft and says so")
    }

    // MARK: A12

    private static func chartValue(_ suite: TestSuite) {
        let draft = GPUControlFanDraft.testedCurve
        let stock = [(40, 36), (50, 55), (60, 70), (70, 85), (80, 100)]
            .map { GPUControlFanPoint(temperatureC: $0.0, speedPercent: $0.1) }
        let en = GPUControlFanSection.chartValue(draft: draft, stock: stock, limitC: 48, fan: .enUS)
        suite.expect(en == "Draft: 30 °C 20 %, 40 °C 36 %, 44 °C 52 %, 46 °C 68 %, 48 °C 100 %. "
                        + "Stock curve: 40 °C 36 %, 50 °C 55 %, 60 °C 70 %, 70 °C 85 %, 80 °C 100 %. 100% by 48 °C.",
                     "the draft, the stock curve and the limit (\(en))")
        suite.expect(GPUControlFanSection.chartValue(draft: draft, stock: [], limitC: 48, fan: .enUS)
                        == "Draft: 30 °C 20 %, 40 °C 36 %, 44 °C 52 %, 46 °C 68 %, 48 °C 100 %. 100% by 48 °C.",
                     "no stock curve read: the draft and the limit")
        for language in AppLanguage.allCases {
            let fan = FeatureStrings.gpuControlFan(language)
            let value = GPUControlFanSection.chartValue(draft: draft, stock: stock, limitC: 47, fan: fan)
            suite.expect(value.contains("30 °C 20 %") && value.contains("80 °C 100 %")
                            && value.contains(String(format: fan.limitFormat, 47)) && !value.contains("%@"),
                         "\(language.rawValue): the chart's value has both curves and the limit")
        }
    }

    // MARK: A15

    private static func liveRow(_ suite: TestSuite) {
        typealias C = GPUControlPageContent
        let en = GPUControlPageStrings.enUS
        suite.expect(C.liveText(GPUControlLive(), en) == nil, "no reading: no row")
        suite.expect(C.liveText(GPUControlLive(boardW: 201.4, fanRPM: 1_203, hotspotC: 45), en)
                        == "Board 201 W · Fan 1203 RPM · Hotspot 45 °C", "every reading")
        suite.expect(C.liveText(GPUControlLive(boardW: 201, fanRPM: nil, hotspotC: 45), en)
                        == "Board 201 W · Fan no data · Hotspot 45 °C", "a missing reading is a word")
        for language in AppLanguage.allCases {
            let s = FeatureStrings.gpuControlPage(language)
            let text = C.liveText(GPUControlLive(boardW: nil, fanRPM: nil, hotspotC: 45), s) ?? ""
            suite.expect(text.contains(s.noReading) && !text.contains("–"),
                         "\(language.rawValue): no dash for a missing reading")
        }
    }

    // MARK: A16 (and the slider's part of A6)

    private static func sliderHelp(_ suite: TestSuite) {
        suite.expect(GPUControlClockSection.sliderHelp(.enUS, range: 1_500...2_400)
                        == "From 1500 MHz to the stock maximum, 2400 MHz. Only lowers the maximum; the value is sent when you stop moving it.",
                     "the slider says its two ends")
        for language in AppLanguage.allCases {
            let help = GPUControlClockSection.sliderHelp(FeatureStrings.gpuControlClock(language), range: 1_500...2_359)
            suite.expect(help.contains("1500") && help.contains("2359") && !help.contains("%"),
                         "\(language.rawValue): the slider's help has the floor and the stock maximum")
        }
        let view = source("GPUControlClockSection.swift")
        suite.expect(view.contains("slider.setAccessibilityHelp(help)")
                        && view.contains("help: Self.sliderHelp(clock, range: range)"),
                     "the slider carries its help")
    }

    // MARK: A6, A13 texts

    private static func texts(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let s = FeatureStrings.gpuControlPage(language)
            let fan = FeatureStrings.gpuControlFan(language)
            let hints = [s.powerHint, s.openWritingHint, fan.applyHint]
            suite.expect(hints.allSatisfy { !$0.isEmpty && !$0.contains("%") } && Set(hints).count == 3,
                         "\(language.rawValue): three distinct hints, plus the slider's help")
            let kext = String(format: s.kextSaysFormat, "off: the driver stopped")
            suite.expect(kext.contains("off: the driver stopped") && kext != "off: the driver stopped"
                            && s.kextSaysFormat.components(separatedBy: "%@").count == 2,
                         "\(language.rawValue): the kext's text is said as the kext's")
            suite.expect(fan.draftDiscarded != fan.apply && !fan.draftDiscarded.isEmpty,
                         "\(language.rawValue): the discard has its own words")
            suite.expect(!s.noReading.contains("–") && !s.noReading.isEmpty, "\(language.rawValue): no data in words")
        }
        suite.expect(GPUControlPageStrings.es.openWritingHint.contains("hasta que los cierres o reinicies"),
                     "Allow changes: until you close them or restart, like its neighbours")
    }

    // MARK: Views (A4, A6, A8, A11, A13)

    private static func views(_ suite: TestSuite) {
        let page = source("GPUControlSettingsView.swift")
        let fan = source("GPUControlFanSection.swift")
        let clock = source("GPUControlClockSection.swift")
        suite.expect(!page.isEmpty && !fan.isEmpty && !clock.isEmpty, "the three views are read from the repo root")
        let all = page + fan + clock
        // A4.
        suite.expect(!fan.contains(".frame(width: 44)") && !clock.contains(".frame(width: 56)")
                        && fan.contains(".frame(minWidth: 44)\n                .fixedSize(horizontal: true, vertical: false)")
                        && clock.contains(".frame(minWidth: 56)\n                .fixedSize(horizontal: true, vertical: false)"),
                     "A4: the number fields grow with their number")
        // A6: four hints and no more.
        suite.expect(page.contains(".accessibilityHint(s.powerHint)") && page.contains(".accessibilityHint(s.openWritingHint)")
                        && fan.contains(".accessibilityHint(fan.applyHint)"),
                     "A6: the power pop-up, Allow changes and Apply curve have their hints")
        suite.expect(all.components(separatedBy: ".accessibilityHint(").count == 4
                        && all.components(separatedBy: "setAccessibilityHelp(").count == 2,
                     "A6: three hints and the slider's help, nothing else")
        // A8.
        suite.expect(!all.contains(".controlSize(.mini)") && all.components(separatedBy: ".controlSize(.regular)").count == 5,
                     "A8: the four switches at the regular size")
        // A11.
        suite.expect(page.contains("copied = true\n") && page.contains("AccessibilityNotification.Announcement(s.copied).post()"),
                     "A11: Copied is said")
        // A13.
        suite.expect(!all.contains("Text(kext)") && !page.contains("lines.append(text)")
                        && page.components(separatedBy: "s.kextSaysFormat").count == 4
                        && fan.components(separatedBy: "strings.kextSaysFormat").count == 4
                        && clock.components(separatedBy: "strings.kextSaysFormat").count == 2,
                     "A13: every kext text on the page is said as the kext's")
    }
}
