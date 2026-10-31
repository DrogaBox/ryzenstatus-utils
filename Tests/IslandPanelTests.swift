// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Foundation

/// The island, the popover and the menu bar after their review: the opening
/// motion, the clock, the AppleScript queue, the now-playing reading and its
/// clock, the hardware alerts, the panel's core grid, the process inspector,
/// the capsule's middle, Reduce Motion and the localized strings.
enum IslandPanelTests {
    static func run(_ suite: TestSuite) {
        openingMotionSettles(suite)
        averageClockNeverNaN(suite)
        oneAppleScriptQueue(suite)
        lyricsAnswersOnTheirQueue(suite)
        animatedArtworkOnDemand(suite)
        processInspector(suite)
        hardwareAlerts(suite)
        coreGridDrivesTheModel(suite)
        leaveReminderComesBack(suite)
        readingOnItsOwnClock(suite)
        focusReaderLetsGo(suite)
        menuBarWaitsForSomeone(suite)
        automationOffTheMainThread(suite)
        capsuleCenterWhereItShows(suite)
        artworkDownloads(suite)
        marqueeRestsQuietly(suite)
        accessibilityAndReduceMotion(suite)
        localizedStrings(suite)
        permissionRepair(suite)
    }

    // MARK: Phase 1

    private static func openingMotionSettles(_ suite: TestSuite) {
        let from = CGSize(width: 200, height: 32)
        let to = CGSize(width: 640, height: 320)
        // With Reduce Motion on the squash is skipped too, so the rule holds
        // either way; it only proves the change with Reduce Motion off.
        suite.expect(abs(NotchMotion.size(at: 1.5, from: from, to: to).height - 320) <= NotchMotion.settledDistance,
                     "the opening island has reached its height after 1.5 s")
        suite.expect(NotchMotion.settlingTime(from: from, to: to) < 1.0, "the opening settles within a second")
        let frames = NotchMotion.frames(from: from, to: to)
        suite.expect(frames.sizes.count >= 2 && abs(frames.sizes[frames.sizes.count - 2].height - 320) <= 1,
                     "the frame before the last is already at the target, so the last one does not jump")
        let source = text("Sources/RyzenStatus/Services/Notch/NotchSupport.swift", suite)
        suite.expect(!source.contains("impactNorm"), "no landing term lingers in the opening motion")
    }

    private static func averageClockNeverNaN(_ suite: TestSuite) {
        suite.expect(SystemSection.averageFrequencyGHz([]) == 0, "no cores, no clock")
        let logical = CoreSnapshot(id: 0, freqMHz: 4000, loadPct: 10, isLogical: true)
        suite.expect(SystemSection.averageFrequencyGHz([logical]) == 0, "logical threads alone give zero, not NaN")
        let cores = [CoreSnapshot(id: 0, freqMHz: 4000, loadPct: 10, isLogical: false),
                     CoreSnapshot(id: 1, freqMHz: 3000, loadPct: 10, isLogical: false), logical]
        suite.expectClose(SystemSection.averageFrequencyGHz(cores), 3.5, "the mean of the physical cores")
    }

    private static func oneAppleScriptQueue(_ suite: TestSuite) {
        for path in ["Sources/RyzenStatus/Services/NowPlaying/NowPlayingAutomation.swift",
                     "Sources/RyzenStatus/Services/NowPlaying/NowPlayingSupport.swift",
                     "Sources/RyzenStatus/Services/NowPlaying/NowPlayingLyricsCenter.swift"] {
            let source = text(path, suite)
            suite.expect(!source.contains("executeAndReturnError("), "\(path) runs its scripts on the shared queue")
        }
        let shell = text("Sources/RyzenStatus/Services/ShellSupport.swift", suite)
        suite.expect(shell.contains("static func execute(_ script: NSAppleScript, error: inout NSDictionary?)")
                     && shell.contains("DispatchQueue(label: \"com.ryzenstatus.utils.applescript\""),
                     "one serial queue runs every AppleScript")
    }

    private static func lyricsAnswersOnTheirQueue(_ suite: TestSuite) {
        let source = text("Sources/RyzenStatus/Services/NowPlaying/NowPlayingLyricsCenter.swift", suite)
        let music = section(of: source, from: "private func fetchMusicAppLyrics", to: "private func getJSON")
        let json = section(of: source, from: "private func getJSON", to: "private func deliver")
        suite.expect(!music.isEmpty && music.contains("deliver(") && !music.contains("completion("),
                     "Music's lyrics answer through the queue")
        suite.expect(!json.isEmpty && json.contains("deliver(") && !json.contains("completion("),
                     "web lyrics answer through the queue")
    }

    private static func animatedArtworkOnDemand(_ suite: TestSuite) {
        let artwork = text("Sources/RyzenStatus/Services/NowPlaying/NowPlayingAnimatedArtwork.swift", suite)
        suite.expect(artwork.contains("guard displayDemand > 0 else { return }"),
                     "nothing is looked up while no surface shows the stream")
        suite.expect(artwork.contains("&& !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion"),
                     "nothing is looked up under Reduce Motion")
        suite.expect(!section(of: artwork, from: "func clearCache()", to: "func beginDisplay()").contains("queue.async"),
                     "the cache is cleared on the thread that writes it")
        suite.expect(section(of: artwork, from: "func endDisplay()", to: "\n    }").contains("streamURL = nil"),
                     "the last surface leaving drops the stream, so the next never starts on the old video")
        suite.expect(artwork.contains("didChangeOcclusionStateNotification"), "the video pauses while its window is hidden")
        let controller = text("Sources/RyzenStatus/Services/NowPlaying/NowPlayingPopupController.swift", suite)
        suite.expect(controller.contains("panel.contentViewController = nil"),
                     "the detached window lets its content go when it closes")
        let popup = text("Sources/RyzenStatus/UI/NowPlaying/NowPlayingPopupView.swift", suite)
        suite.expect(popup.contains("!reduceMotion ? animatedArtworkCenter.streamURL"), "the popup keeps a still cover under Reduce Motion")
    }

    private static func processInspector(_ suite: TestSuite) {
        let pid = getpid()
        suite.expect(ProcessDetailSheet.executablePath(of: pid) != nil, "the running test's path is read")
        suite.expect(ProcessDetailSheet.executablePath(of: -1) == nil, "a missing process has no invented path")
        let first = KillProcessService.startTime(for: pid)
        suite.expect(first != nil && first == KillProcessService.startTime(for: pid),
                     "a process keeps its start time, the identity a kill is checked against")
        let sheet = text("Sources/RyzenStatus/UI/MenuPanel/ProcessDetailSheet.swift", suite)
        suite.expect(sheet.contains("KillProcessService.shared.kill(pid:") && !sheet.contains("kill(row.pid, SIGKILL)"),
                     "Force Quit goes through the shared safe kill")
        suite.expect(sheet.contains("KillProcessService.startTime(for: pid) == startedAt"),
                     "a process still there with the same start time reports a failed kill")
        suite.expect(!sheet.contains("/System/Library/CoreServices/") && !sheet.contains("Native Architecture")
                     && !sheet.contains("row.value <= 2000") && !sheet.contains("Timer.publish"),
                     "no invented path, no architecture claim, no GPU share as CPU, no per-render timer")
        suite.expect(sheet.contains("occlusionState.contains(.visible)") && sheet.contains(".task(id: visibility.isVisible)"),
                     "the inspector samples only while its window can be seen")
        for literal in ["\"Done\"", "\"Cancel\"", "\"Copy Path\"", "\"CPU LOAD\"", "Process Inspector —"] {
            suite.expect(!sheet.contains(literal), "the inspector shows no English literal \(literal)")
        }
    }

    private static func hardwareAlerts(_ suite: TestSuite) {
        let rules = NotchHardwareAlertSupport.self
        suite.expect(rules.nextStreak(2, value: 86, trigger: 85, release: 78) == 3, "a hot reading extends the streak")
        suite.expect(rules.nextStreak(2, value: 80, trigger: 85, release: 78) == 2, "between the marks the streak holds")
        suite.expect(rules.nextStreak(2, value: 70, trigger: 85, release: 78) == 0, "a cool reading resets it")
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        suite.expect(rules.cooledDown(nil, now: now, cooldown: 35), "the first alert is always allowed")
        suite.expect(!rules.cooledDown(now.addingTimeInterval(-10), now: now, cooldown: 35), "a recent alert holds the next")
        suite.expect(rules.cooledDown(now.addingTimeInterval(-35), now: now, cooldown: 35), "the cooldown ends")
        let spun = rules.spinning([1: 900, 2: 0], adding: [])
        suite.expect(spun == [1], "only a turning fan counts as fitted")
        suite.expect(rules.stalled([1: 0, 2: 0], spun: spun) == [1],
                     "a fan that turned and reads zero has stalled; an empty header never does")
        suite.expect(rules.stalled([1: 850, 2: 0], spun: spun).isEmpty, "a turning fan has not stalled")

        let service = text("Sources/RyzenStatus/Services/Notch/NotchHardwareAlertService.swift", suite)
        suite.expect(!service.contains("@unchecked Sendable") && !service.contains("Fan Check")
                     && !service.contains("snapshot.gpuFan"),
                     "no unchecked sendability, no English title, no rule on the GPU fan that never reads zero")
        if let show = service.range(of: "NotchService.shared.show("),
           let play = service.range(of: "NotchSoundCueService.shared.play(") {
            suite.expect(show.lowerBound < play.lowerBound, "an alert plays its sound only once the island took it")
        } else {
            suite.expect(false, "the alert service shows notices and plays sounds")
        }
        let notch = text("Sources/RyzenStatus/Services/Notch/NotchService.swift", suite)
        suite.expect(section(of: notch, from: "private func tearDownPresentation()", to: "\n    }\n")
            .contains("NotchHardwareAlertService.shared.stop()"),
                     "alerts stop with the island's presentation, as on the lock screen")
    }

    private static func coreGridDrivesTheModel(_ suite: TestSuite) {
        var demand = AmdLiveSyncDemand()
        suite.expect(demand.begin(), "the first view starts the loop")
        suite.expect(!demand.begin(), "a second view joins it")
        suite.expect(!demand.end(), "one view leaving keeps it")
        suite.expect(demand.end(), "the last view leaving stops it")
        suite.expect(!demand.end() && demand.clients == 0, "an extra leave never goes below zero")
        suite.expect(CPUCoreGridView.wantsLiveSMU(metric: .clock, onScreen: true), "an SMU mode on screen keeps the model live")
        suite.expect(!CPUCoreGridView.wantsLiveSMU(metric: .load, onScreen: true), "the load view runs no SMU loop")
        suite.expect(!CPUCoreGridView.wantsLiveSMU(metric: .temp, onScreen: false), "nothing off screen")

        let section = text("Sources/RyzenStatus/UI/MenuPanel/AmdControlSection.swift", suite)
        suite.expect(!section.contains("Timer.scheduledTimer") && !section.contains("loadTimer")
                     && section.contains("controls.beginLiveSync()") && section.contains("controls.endLiveSync()"),
                     "the AMD section shares the model's one loop")
        let dashboard = text("Sources/RyzenStatus/UI/Dashboard/PerformanceSuiteView.swift", suite)
        let pages = text("Sources/RyzenStatus/UI/Settings/SettingsPageActivity.swift", suite)
        suite.expect(!dashboard.contains("amdSyncTimer") && dashboard.contains(".settingsPageActivity(.performanceSuite")
                     && pages.contains("AmdPowerControlsModel.shared.beginLiveSync()"),
                     "the dashboard shares it too, through its page activity")
        let grid = text("Sources/RyzenStatus/UI/MenuPanel/CPUCoreGridView.swift", suite)
        suite.expect(grid.contains("beginLiveSync()") && grid.contains("endLiveSync()"),
                     "the grid keeps the model live itself")
        let system = text("Sources/RyzenStatus/UI/MenuPanel/SystemSection.swift", suite)
        suite.expect(!system.contains("stays a passive consumer"), "the System section no longer waits on the AMD tab")
    }

    private static func leaveReminderComesBack(_ suite: TestSuite) {
        let source = text("Sources/RyzenStatus/Services/Notch/NotchLeaveService.swift", suite)
        suite.expect(source.contains("if announce(event:") && source.contains("addingTimeInterval(60)"),
                     "a refused leave reminder tries again each minute")
    }

    // MARK: Phase 2

    private static func readingOnItsOwnClock(_ suite: TestSuite) {
        let at = { (seconds: Double) in Date(timeIntervalSinceReferenceDate: seconds) }
        var old = NowPlayingSnapshot()
        old.title = "Song"
        old.isPlaying = true
        old.elapsed = 30
        old.duration = 200
        old.sampledAt = at(100)
        suite.expectClose(old.position(at: at(105)) ?? -1, 35, "the playhead moves on while playing")
        var paused = old
        paused.isPlaying = false
        suite.expectClose(paused.position(at: at(105)) ?? -1, 30, "the playhead stays while paused")
        suite.expectClose(old.position(at: at(1000)) ?? -1, 200, "never past the end")

        var later = old
        later.elapsed = 32
        later.sampledAt = at(102)
        suite.expect(NowPlayingSnapshot.continues(old, with: later), "two seconds on, a playing song says nothing new")
        var seek = later
        seek.elapsed = 44
        suite.expect(!NowPlayingSnapshot.continues(old, with: seek), "a jump past a second is a seek and publishes")
        var stopped = later
        stopped.isPlaying = false
        suite.expect(!NowPlayingSnapshot.continues(old, with: stopped), "pausing publishes")
        var stillPaused = paused
        stillPaused.sampledAt = at(110)
        suite.expect(NowPlayingSnapshot.continues(paused, with: stillPaused), "a paused song read again says nothing new")
        var other = later
        other.title = "Other"
        suite.expect(!NowPlayingSnapshot.continues(old, with: other), "a new song publishes")

        var cover = old
        cover.artworkData = Data(repeating: 1, count: 100)
        var recover = cover
        var bytes = [UInt8](repeating: 1, count: 100)
        bytes[80] = 2
        recover.artworkData = Data(bytes)
        suite.expect(cover != recover, "covers are compared in full")

        let service = text("Sources/RyzenStatus/Services/NowPlaying/NowPlayingService.swift", suite)
        suite.expect(service.contains("if completedReadings == 0 { completedReadings = 1 }")
                     && !service.contains("completedReadings &+= 1"),
                     "the first reading is announced once, not every poll")
        suite.expect(service.contains("NowPlayingSnapshot.continues(snapshot, with: next)") && !service.contains("last.prefix(64)"),
                     "a reading publishes only what changed, and the cover decodes only when its bytes do")
        let radial = text("Sources/RyzenStatus/Services/RadialMenu/RadialNowPlayingService.swift", suite)
        suite.expect(radial.contains("$completedReadings"), "the radial menu still learns of the first reading")
    }

    private static func focusReaderLetsGo(_ suite: TestSuite) {
        let source = text("Sources/RyzenStatus/Services/Notch/NotchFocusService.swift", suite)
        suite.expect(source.contains("if data.isEmpty { handle.readabilityHandler = nil; return }")
                     && source.contains("(ended.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil"),
                     "the log reader drops its handler at the end of the stream and when the tool exits")
    }

    private static func menuBarWaitsForSomeone(_ suite: TestSuite) {
        let gate = NowPlayingMarqueeEngine.self
        suite.expect(gate.scrolls(setting: true, reduceMotion: false, itemVisible: true, sessionActive: true),
                     "the text scrolls when someone can see it")
        suite.expect(!gate.scrolls(setting: false, reduceMotion: false, itemVisible: true, sessionActive: true), "not when switched off")
        suite.expect(!gate.scrolls(setting: true, reduceMotion: true, itemVisible: true, sessionActive: true), "not under Reduce Motion")
        suite.expect(!gate.scrolls(setting: true, reduceMotion: false, itemVisible: false, sessionActive: true), "not when hidden")
        suite.expect(!gate.scrolls(setting: true, reduceMotion: false, itemVisible: true, sessionActive: false), "not when locked or asleep")

        let service = text("Sources/RyzenStatus/Services/NowPlaying/NowPlayingService.swift", suite)
        suite.expect(section(of: service, from: "private func poll()", to: "let now").contains("guard session.canPresent else { return }"),
                     "no poll while asleep or locked")
        suite.expect(service.contains("CGSSessionScreenIsLocked") && service.contains("fireDate = .distantFuture")
                     && service.contains("screensDidSleepNotification"),
                     "the session state is seeded at start and pauses the poll timer")
        suite.expect(service.contains("marqueeHoldWork?.cancel()"), "one marquee hold redraw at a time")
    }

    private static func automationOffTheMainThread(_ suite: TestSuite) {
        let service = text("Sources/RyzenStatus/Services/NowPlaying/NowPlayingService.swift", suite)
        suite.expect(section(of: service, from: "func requestAutomationAccess()", to: "\n    }\n")
            .contains("DispatchQueue.global(qos: .userInitiated)"),
                     "asking for consent never waits on the main thread")
        suite.expect(section(of: service, from: "func refreshAutomation(force", to: "func requestAutomationAccess()")
            .contains("scriptingQueue.async"),
                     "the permission check runs on the scripting queue")
        let scripting = text("Sources/RyzenStatus/Services/NowPlaying/NowPlayingScripting.swift", suite)
        suite.expect(scripting.contains("static func forgetAccess(for pid: Int32)"), "a recent answer can be forgotten")
        let music = text("Sources/RyzenStatus/UI/Notch/NotchMusicView.swift", suite)
        suite.expect(music.contains("refreshAutomation(force: true)"), "the refresh button always asks the system again")
        let controller = text("Sources/RyzenStatus/Services/NowPlaying/NowPlayingPopupController.swift", suite)
        suite.expect(!controller.contains("didMoveNotification"), "the detached window keeps its place when it closes, not on every move")
    }

    private static func capsuleCenterWhereItShows(_ suite: TestSuite) {
        let support = NotchCapsuleCenterSupport.self
        suite.expect(support.runsTimer(center: .song, running: true, suspended: false, capsuleShows: true),
                     "a floating capsule reads its middle")
        suite.expect(!support.runsTimer(center: .song, running: true, suspended: false, capsuleShows: false),
                     "a notch alone runs no timer")
        suite.expect(!support.runsTimer(center: .song, running: true, suspended: true, capsuleShows: true),
                     "nothing while the island is away")
        suite.expect(!support.runsTimer(center: .none, running: true, suspended: false, capsuleShows: true),
                     "nothing to show, nothing to read")
        let center = text("Sources/RyzenStatus/Services/Notch/NotchCapsuleCenter.swift", suite)
        suite.expect(!center.contains("DateFormatter()"), "the clock uses a format style")
        let notch = text("Sources/RyzenStatus/Services/Notch/NotchService.swift", suite)
        let sync = section(of: notch, from: "func syncWithPreferences()", to: "\n    }\n")
        if let guardRange = sync.range(of: "guard !suspended else"), let call = sync.range(of: "syncCapsuleCenter()") {
            suite.expect(guardRange.lowerBound < call.lowerBound, "a preference change while locked does not restart the timer")
        } else {
            suite.expect(false, "the preference sync guards the suspended island and syncs the capsule's middle")
        }
        suite.expect(section(of: notch, from: "private func syncCapsuleCenter()", to: "\n    }\n").contains("geometry.floats"),
                     "the timer follows the display style")

        var snapshot = SystemSnapshot()
        snapshot.gpuFan = 1200
        suite.expect(support.metric(.fanSpeed, snapshot: snapshot, unit: .celsius) == "GPU fan 1200 RPM",
                     "the fan reading says it is the GPU's")
        let german = FeatureStrings.notchCapsuleCenter(.de)
        suite.expect(support.metric(.fanSpeed, snapshot: snapshot, unit: .celsius, strings: german) == "GPU-Lüfter 1200 U/min",
                     "the readings follow the language")
    }

    private static func artworkDownloads(_ suite: TestSuite) {
        let source = text("Sources/RyzenStatus/Services/NowPlaying/NowPlayingAutomation.swift", suite)
        suite.expect(source.contains("lastMusicTrackID") && source.contains("lastSpotifyTrackID")
                     && !source.contains("lastTrackID =="),
                     "Music and Spotify keep their own cover")
        suite.expect(source.contains("timeoutInterval: 3") && !source.contains("Data(contentsOf:")
                     && source.contains("task.cancel()"),
                     "covers download with a bound and a cancelled late request")
    }

    private static func marqueeRestsQuietly(_ suite: TestSuite) {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let schedule = NotchMarqueeSchedule(start: start, pause: 1.8, travel: 4, interval: 1.0 / 30)
        func offsets(from date: Date, count: Int) -> [Double] {
            let entries = schedule.entries(from: date, mode: .normal)
            return (0..<count).compactMap { _ in entries.next()?.timeIntervalSince(start) }
        }
        let first = offsets(from: start, count: 3)
        suite.expect(first.count == 3 && abs(first[0]) < 1e-6 && abs(first[1] - 1.8) < 1e-6
                     && abs(first[2] - (1.8 + 1.0 / 30)) < 1e-6,
                     "one frame for the rest, then frames through the scroll (\(first))")
        let scrolling = offsets(from: start.addingTimeInterval(5), count: 2)
        suite.expect(scrolling.count == 2 && abs(scrolling[1] - (5 + 1.0 / 30)) < 1e-6, "steady frames while scrolling")
        let resting = offsets(from: start.addingTimeInterval(6), count: 2)
        suite.expect(resting.count == 2 && abs(resting[1] - 7.6) < 1e-6, "a rest skips to its end (\(resting))")

        let real = NotchMarqueeSchedule(start: Date(timeIntervalSinceReferenceDate: 8e8 + 0.1), pause: 1.8,
                                        travel: 4, interval: 1.0 / 30)
        let entries = real.entries(from: Date(timeIntervalSinceReferenceDate: 8e8 + 0.1), mode: .normal)
        var previous = entries.next()
        var increasing = previous != nil
        for _ in 0..<1000 {
            guard let next = entries.next(), let last = previous else { increasing = false; break }
            if next <= last { increasing = false; break }
            previous = next
        }
        suite.expect(increasing, "the timeline always moves forward at a real date")
        suite.expect(NotchMarqueeSchedule.step(elapsed: 1.8 - 1e-9, pause: 1.8, interval: 1.0 / 30)
                     >= NotchMarqueeSchedule.minimumStep,
                     "a rest ending a hair away still steps forward")
    }

    // MARK: Phase 3

    private static func accessibilityAndReduceMotion(_ suite: TestSuite) {
        let grid = text("Sources/RyzenStatus/UI/MenuPanel/CPUCoreGridView.swift", suite)
        suite.expect(grid.contains(".accessibilityLabel(threadName(core))") && grid.contains(".accessibilityLabel(smuName(core))"),
                     "each core ring has a name")
        suite.expect(!grid.contains("\"Thread %d") && !grid.contains("\"Core %d"), "the grid's words come from the strings")
        let amd = text("Sources/RyzenStatus/UI/MenuPanel/AmdControlSection.swift", suite)
        suite.expect(!amd.contains("Picker(\"\",") && amd.contains(".accessibilityLabel(help)"),
                     "every AMD picker and column toggle has a name")
        suite.expect(!amd.contains("Text(preset.rawValue)") && !amd.contains("\"Per-core voltage"),
                     "preset names and column help are localized")
        suite.expect(amd.contains("PanelInteractionState.shared.anchorScreen"), "the core list is capped against the panel's screen")
        let istats = text("Sources/RyzenStatus/UI/MenuPanel/IStatsPopoverWidgetsView.swift", suite)
        suite.expect(istats.contains(".accessibilityValue(value)"), "a donut reads as one gauge")
        let popup = text("Sources/RyzenStatus/UI/NowPlaying/NowPlayingPopupView.swift", suite)
        suite.expect(popup.contains(".accessibilityElement(children: .contain)") && popup.contains(".accessibilityActions {")
                     && popup.contains("Button(strings.lyricsTab)"),
                     "the popup's corner actions are reachable without hovering")
        let controller = text("Sources/RyzenStatus/Services/NowPlaying/NowPlayingPopupController.swift", suite)
        suite.expect(section(of: controller, from: "private func animatePopoverFrame", to: "let timer = Timer")
            .contains("accessibilityDisplayShouldReduceMotion") && !controller.contains("120 Hz"),
                     "the popup snaps between layouts under Reduce Motion")
        let renderer = text("Sources/RyzenStatus/App/MenuBarRenderer.swift", suite)
        suite.expect(!renderer.contains("\"CPU Power\"") && !renderer.contains("(2-Line)\""), "menu bar metric names are localized")
        let system = text("Sources/RyzenStatus/UI/MenuPanel/SystemSection.swift", suite)
        suite.expect(!system.contains("\"Per-Core Grid\"") && !system.contains("return \"LOAD\""), "the grid's toggle and mode are localized")
        let capsule = text("Sources/RyzenStatus/Core/NotchCapsuleCenterStrings.swift", suite)
        suite.expect(!capsule.contains(": String = \""), "no capsule string falls back to English")
        let spectrum = text("Sources/RyzenStatus/UI/Notch/NotchSpectrumBars.swift", suite)
        suite.expect(spectrum.contains("waveLine.shadowPath ="), "the wave's shadow has a path")
    }

    private static func permissionRepair(_ suite: TestSuite) {
        let repair = text("Sources/RyzenStatus/Services/PermissionRepair.swift", suite)
        suite.expect(repair.contains("auth_value = 2") && repair.contains("csreq IS NOT NULL AND length(csreq) > 0"),
                     "repair only re-ties permissions already allowed and already tied to a signature")
        suite.expect(!repair.contains("INSERT") && !repair.contains("DELETE"), "repair never adds or removes a permission")
        suite.expect(!PermissionRepair.services.contains("kTCCServiceAccessibility")
                     && !PermissionRepair.services.contains("kTCCServiceScreenCapture"),
                     "the system database's services are left to their own path")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.permissionRepair(language)
            let texts = [strings.title, strings.description, strings.button, strings.repairedFormat, strings.nothingToRepair,
                         strings.needsFullDiskAccess, strings.openFullDiskAccess, strings.failed, strings.relaunch]
            suite.expect(texts.allSatisfy { !$0.isEmpty } && specifiers(strings.repairedFormat) == ["d"],
                         "permission repair strings are filled in \(language.rawValue)")
        }
    }

    private static func localizedStrings(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let code = language.rawValue
            let inspector = FeatureStrings.processInspector(language)
            let inspectorTexts = [inspector.windowTitleFormat, inspector.pidFormat, inspector.leakTitle, inspector.leakDetail,
                                  inspector.cpuLoad, inspector.residentMemory, inspector.networkIO, inspector.networkIdle,
                                  inspector.executablePath, inspector.pathUnavailable, inspector.copied, inspector.copyPath,
                                  inspector.revealInFinder, inspector.processRole, inspector.done, inspector.terminate,
                                  inspector.forceQuitTitleFormat, inspector.forceQuitMessageFormat, inspector.cancel,
                                  inspector.forceQuit, inspector.terminateFailed, inspector.categorySystem,
                                  inspector.categoryApp, inspector.categoryHelper, inspector.categoryBackground,
                                  inspector.categoryDeveloper, inspector.categorySecurity, inspector.roleSystem,
                                  inspector.roleApp, inspector.roleBackground]
            suite.expect(inspectorTexts.allSatisfy { !$0.isEmpty }, "process inspector strings are filled in \(code)")
            suite.expect(specifiers(inspector.windowTitleFormat) == ["@", "d"] && specifiers(inspector.pidFormat) == ["d"]
                         && specifiers(inspector.forceQuitTitleFormat) == ["@"]
                         && specifiers(inspector.forceQuitMessageFormat) == ["d"],
                         "process inspector formats keep their arguments in \(code)")

            let extras = FeatureStrings.notchIslandExtras(language)
            suite.expect(![extras.thermalAlert, extras.powerAlert, extras.fanAlert].contains(where: \.isEmpty),
                         "hardware alert titles are filled in \(code)")

            let strings = Strings.localized(language)
            suite.expect(![strings.cpuPowerMetricTitle, strings.gpuPowerMetricTitle, strings.cpuTempPowerMetricTitle,
                           strings.gpuTempPowerMetricTitle].contains(where: \.isEmpty),
                         "menu bar metric names are filled in \(code)")

            let amd = FeatureStrings.amdPower(language)
            suite.expect(![amd.gridFavorite, amd.gridParked, amd.gridLoad, amd.perCoreGrid, amd.pmVoltageHelp,
                           amd.pmC0Help, amd.pmCC6Help, amd.presetEco, amd.presetBalance, amd.presetPerformance,
                           amd.presetExtreme].contains(where: \.isEmpty),
                         "AMD grid and panel words are filled in \(code)")
            suite.expect(specifiers(amd.gridThreadFormat) == ["d"] && specifiers(amd.gridCoreFormat) == ["d"]
                         && specifiers(amd.gridLoadValueFormat) == ["f", "f"] && specifiers(amd.gridC6Format) == ["d"]
                         && specifiers(amd.gridClockValueFormat) == ["f"]
                         && specifiers(amd.l3HelpFormat) == ["d", "f", "f", "f", "f", "f"],
                         "AMD grid formats keep their arguments in \(code)")
            suite.expect(Set(AMDPowerPreset.allCases.map(amd.presetTitle)).count == AMDPowerPreset.allCases.count,
                         "preset names are distinct in \(code)")

            let capsule = FeatureStrings.notchCapsuleCenter(language)
            suite.expect(![capsule.carousel, capsule.cpuPower, capsule.peakFrequency, capsule.fanSpeed].contains(where: \.isEmpty),
                         "capsule center names are filled in \(code)")
            suite.expect(specifiers(capsule.boostReading) == ["f"] && specifiers(capsule.clockReading) == ["f"]
                         && specifiers(capsule.fanReading) == ["f"],
                         "capsule readings keep their arguments in \(code)")
        }
        let english = FeatureStrings.processInspector(.enUS)
        suite.expect(String(format: english.windowTitleFormat, "Finder", 42) == "Process Inspector — Finder (42)",
                     "the window title names the process")
    }

    // MARK: Helpers

    /// A source file relative to the repository root; one that cannot be
    /// read fails the run instead of letting the checks pass on nothing.
    private static func text(_ path: String, _ suite: TestSuite) -> String {
        let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        suite.expect(!source.isEmpty, "\(path) is readable")
        return source
    }

    /// The text from `start` up to the first `end` after it, or empty.
    private static func section(of source: String, from start: String, to end: String) -> String {
        guard let open = source.range(of: start) else { return "" }
        let rest = source[open.upperBound...]
        let close = rest.range(of: end)?.lowerBound ?? rest.endIndex
        return String(rest[..<close])
    }

    /// The conversion letters of a format string, `%%` skipped.
    private static func specifiers(_ format: String) -> [String] {
        var result: [String] = []
        var index = format.startIndex
        while index < format.endIndex {
            guard format[index] == "%" else { index = format.index(after: index); continue }
            index = format.index(after: index)
            if index < format.endIndex, format[index] == "%" { index = format.index(after: index); continue }
            while index < format.endIndex {
                let character = format[index]
                index = format.index(after: index)
                if character.isLetter || character == "@" { result.append(String(character)); break }
            }
        }
        return result
    }
}
