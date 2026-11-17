// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Pure checks for the 1.85.0 batch: launch gating, the shared window layout
/// pointer tap, screenshot crops, the clipboard search index, microphone
/// mute decisions, monitor speakers and virtual displays, island preferences
/// and notices, the menu bar panel's own clicks, the Super Key glyph, capture
/// tool numbering, stable backups, watermark layouts, radial snippets, audio
/// priority, the switcher's preview cards and the Scratchpad's done tasks.
enum Batch185Tests {
    static func run(_ suite: TestSuite) {
        displayRestoreChecks(suite)
        pointerRouteChecks(suite)
        screenshotCropChecks(suite)
        clipboardIndexChecks(suite)
        clipboardStorageChecks(suite)
        micMuteChecks(suite)
        displayRouteChecks(suite)
        blindSpeakerChecks(suite)
        islandPreferenceChecks(suite)
        trackNoticeChecks(suite)
        panelSelfClickChecks(suite)
        superKeyGlyphChecks(suite)
        captureAndMediaChecks(suite)
        stableExportChecks(suite)
        watermarkLayoutChecks(suite)
        radialSnippetChecks(suite)
        audioPriorityChecks(suite)
        switcherPreviewChecks(suite)
        fullscreenHandBackChecks(suite)
        scratchpadChecks(suite)
    }

    // MARK: Display repair asked from the saved list

    private static func displayRestoreChecks(_ suite: TestSuite) {
        suite.expect(!BrightnessSupport.hasDisplaysToRestore(stored: nil),
                     "no saved list asks for nothing")
        suite.expect(!BrightnessSupport.hasDisplaysToRestore(stored: []),
                     "an empty saved list asks for nothing")
        suite.expect(BrightnessSupport.hasDisplaysToRestore(stored: [1]),
                     "one saved display asks for the repair")
        suite.expect(BrightnessSupport.hasDisplaysToRestore(stored: [0, 7]),
                     "any saved display number asks for the repair")
        suite.expect(!BrightnessSupport.hasDisplaysToRestore(stored: [-1]),
                     "a negative number is not a display")
        suite.expect(!BrightnessSupport.hasDisplaysToRestore(stored: [Int.max]),
                     "a number past a display id is not a display")
    }

    // MARK: One pointer tap for the window layout

    /// One tap serves the pointer layout, the move and resize gesture and
    /// edge snapping, so the route decides who sees an event and in what order.
    private static func pointerRouteChecks(_ suite: TestSuite) {
        typealias Route = WindowLayoutPointerRoute
        let every: WindowLayoutPointerDemand = [.directional, .gesture, .edgeSnap]
        suite.expect(Route.consumers(for: .leftMouseDown, active: every) == [.directional, .gesture, .edgeSnap],
                     "a press reaches the pointer layout, the gesture and edge snapping in that order")
        suite.expect(Route.consumers(for: .scrollWheel, active: every) == [.directional]
                        && Route.consumers(for: .keyDown, active: every) == [.directional],
                     "the wheel and the keyboard belong to the pointer layout alone")
        suite.expect(Route.consumers(for: .leftMouseDragged, active: every) == [.gesture, .edgeSnap]
                        && Route.consumers(for: .rightMouseUp, active: every) == [.gesture],
                     "each consumer still sees exactly the events its own tap watched")
        for disabled in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
            suite.expect(Route.consumers(for: disabled, active: every) == [.directional, .gesture, .edgeSnap]
                            && Route.consumers(for: disabled, active: .edgeSnap) == [.edgeSnap],
                         "a tap the system switched off reaches every consumer left to recover from it")
        }
        suite.expect(Route.consumers(for: .leftMouseDown, active: []) == []
                        && Route.consumers(for: .leftMouseDown, active: .edgeSnap) == [.edgeSnap],
                     "an idle layout routes nothing and a lone consumer hears its own press")
        suite.expect(Route.consumers(for: .leftMouseDragged, active: .directional) == [],
                     "a stopped consumer never borrows another's events")
        suite.expect(Route.consumers(for: .flagsChanged, active: every) == [],
                     "the modifier chord keeps its own passive tap and stays out of the shared one")
        let union = WindowLayoutPointerConsumer.directional.eventMask
            | WindowLayoutPointerConsumer.gesture.eventMask
            | WindowLayoutPointerConsumer.edgeSnap.eventMask
        suite.expect(Route.sharedEventMask == union,
                     "the shared tap watches the union of the three masks it replaced")
    }

    // MARK: A crop owns its pixels

    private static func solidImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// The image's pixels redrawn into one known layout, so two images with
    /// different row lengths can be compared byte for byte.
    private static func pixelBytes(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    /// A crop is copied out of the frame it came from, with the same size,
    /// colour space and pixels.
    private static func screenshotCropChecks(_ suite: TestSuite) {
        func buffer(_ image: CGImage) -> Int {
            (image.dataProvider?.data as Data?)?.count ?? 0
        }
        guard let parent = solidImage(width: 1200, height: 800),
              let window = parent.cropping(to: CGRect(x: 100, y: 60, width: 800, height: 600)),
              let independent = ScreenshotSupport.independentImage(window)
        else {
            suite.expect(false, "a crop is copied into pixels of its own")
            return
        }
        suite.expect(independent.width == 800 && independent.height == 600,
                     "the copy keeps the crop's size")
        if let space = independent.colorSpace, let source = parent.colorSpace {
            suite.expect(CFEqual(space, source), "the copy keeps the crop's colour space")
        } else {
            suite.expect(false, "both the crop and its parent carry a colour space")
        }
        suite.expect(buffer(window) > buffer(independent) && buffer(independent) == 800 * 600 * 4,
                     "the crop holds its own buffer instead of the parent's: \(buffer(window)) then \(buffer(independent)) bytes")
        suite.expect(independent.bytesPerRow == 800 * 4,
                     "the copy stops reading rows of the parent")
        suite.expect(pixelBytes(independent) == pixelBytes(window),
                     "the copy keeps every pixel")
    }

    // MARK: Clipboard search index

    private static func clipboardIndexChecks(_ suite: TestSuite) {
        // A text inside the index limit folds into exactly the candidate a
        // fresh fold produces.
        let entries = [ClipboardHistoryEntry(text: "Deploy the server tonight"),
                       ClipboardHistoryEntry(text: "Clean the cache", pinnedAt: Date(timeIntervalSince1970: 42)),
                       ClipboardHistoryEntry(text: "сервер перезапущен")]
        var cache = ClipboardHistorySearchCache()
        let cached = cache.candidates(for: entries, stamp: 1, imageLabel: "Image")
        let fresh = entries.enumerated().map { index, entry in
            ClipboardHistorySearchCandidate(index: index,
                                            text: entry.searchableText(imageLabel: "Image"),
                                            isPinned: entry.isPinned)
        }
        suite.expect(cached == fresh, "a short corpus produces the same candidates as a fresh fold")
        suite.expect(cached.allSatisfy { !$0.isIndexTruncated && $0.words != nil },
                     "every text within the index limit keeps its whole word set")

        // A saved document is indexed only as far as the index limit; the
        // rest of the text is left to the deferred pass.
        let longChunk = "Серверная конфигурация nginx и логи приложения. "
        let deepMarker = "уникальныймаркервглубинедокумента"
        var longText = String(repeating: longChunk, count: 3_600)
        let deepOffset = longText.count
        longText += deepMarker
        longText += String(repeating: longChunk, count: 3_600)
        suite.expect(longText.utf8.count > 300_000 && deepOffset > 100_000,
                     "the long fixture is a large document whose marker sits far past the index limit")
        let longEntry = ClipboardHistoryEntry(text: longText)
        var longCache = ClipboardHistorySearchCache()
        let longCandidates = longCache.candidates(for: [longEntry], stamp: 1, imageLabel: "Image")
        suite.expect(longCache.cachedEntryCount == 1 && longCandidates.count == 1,
                     "a long entry is cached like any other")
        guard let long = longCandidates.first else { return }
        suite.expect(long.isIndexTruncated && long.words == nil,
                     "a long entry is marked truncated and keeps no word set")
        suite.expect(long.normalizedText.count <= ClipboardHistoryEntry.indexCharacters,
                     "the folded index text stops at the index limit")
        suite.expect(ClipboardHistorySearch.rankedIndexes(candidates: longCandidates, matching: "nginx") == [0],
                     "a match in the indexed opening of a long entry is found at once")
        suite.expect(ClipboardHistorySearch.rankedIndexes(candidates: longCandidates, matching: deepMarker) == [],
                     "a match past the index limit is left to the deferred pass")
        suite.expect(ClipboardHistorySearch.matches(longText, query: deepMarker),
                     "the deferred pass reads the same deep match in the full text")
        _ = longCache.candidates(for: [longEntry], stamp: 2, imageLabel: "Image")
        suite.expect(longCache.foldCount == 1 && longCache.cachedEntryCount == 1,
                     "a repeat request reuses the long entry's single fold")

        // The limit counts grapheme clusters: a cut inside a Character would
        // break the text it indexes.
        let clusterText = String(repeating: "a👨‍👩‍👧‍👦", count: 3_000)
        let clusterIndex = ClipboardHistoryEntry(text: clusterText).indexText(imageLabel: "Image")
        suite.expect(clusterIndex.count == ClipboardHistoryEntry.indexCharacters
                        && clusterIndex.unicodeScalars.count > ClipboardHistoryEntry.indexCharacters,
                     "the index limit counts whole Characters")
        suite.expect(clusterText.hasPrefix(clusterIndex), "the index cut keeps every Character whole")
    }

    /// The search index is derived at runtime: an entry saves no index of its
    /// own, so an older build reads the file exactly as it wrote it.
    private static func clipboardStorageChecks(_ suite: TestSuite) {
        let savedText = String(repeating: "строка документации\n", count: 400)
        guard let encoded = try? JSONEncoder().encode([ClipboardHistoryEntry(text: savedText)]) else {
            suite.expect(false, "a clipboard entry encodes to JSON")
            return
        }
        let rows = (try? JSONSerialization.jsonObject(with: encoded)) as? [[String: Any]] ?? []
        let keys = Set(rows.first?.keys.map { $0 } ?? [])
        suite.expect(rows.count == 1 && keys == ["id", "text", "copiedAt", "kind", "filePaths"],
                     "a saved history entry carries no search index key")
        let decoded = try? JSONDecoder().decode([ClipboardHistoryEntry].self, from: encoded)
        suite.expect(decoded?.first?.text == savedText,
                     "the whole text of a long entry survives a save and load")
    }

    // MARK: Microphone mute

    private static func micMuteChecks(_ suite: TestSuite) {
        suite.expect(MicMuteSupport.controlValuesMatch(0.5, 0.48, isMute: false)
                        && !MicMuteSupport.controlValuesMatch(0.5, 0.4, isMute: false),
                     "restored gain may settle near the saved level")
        suite.expect(MicMuteSupport.controlValuesMatch(1, 1, isMute: true)
                        && !MicMuteSupport.controlValuesMatch(1, 0, isMute: true),
                     "mute switches stay exact")

        // A call app that opens the microphone is followed; everything else
        // is still put back.
        suite.expect(MicMuteSupport.isExternalUnmute(wasSilenced: true, silenced: false,
                                                     switchWasEngaged: true, muteSwitch: 0,
                                                     capturedByOtherProcess: true),
                     "a call app that raises a muted microphone's level while recording from it is followed")
        suite.expect(MicMuteSupport.isExternalUnmute(wasSilenced: true, silenced: true,
                                                     switchWasEngaged: true, muteSwitch: 0,
                                                     capturedByOtherProcess: true),
                     "a call app that only clears the mute switch, level still zero, is followed too")
        suite.expect(!MicMuteSupport.isExternalUnmute(wasSilenced: true, silenced: false,
                                                      switchWasEngaged: true, muteSwitch: 0,
                                                      capturedByOtherProcess: false),
                     "with nobody recording, a raised level is an app nudging gain and is put back")
        suite.expect(!MicMuteSupport.isExternalUnmute(wasSilenced: false, silenced: false,
                                                      switchWasEngaged: false, muteSwitch: 0,
                                                      capturedByOtherProcess: true),
                     "a microphone the mute never silenced is not reported as unmuted by a call app")
        suite.expect(!MicMuteSupport.isExternalUnmute(wasSilenced: true, silenced: true,
                                                      switchWasEngaged: false, muteSwitch: 0,
                                                      capturedByOtherProcess: true),
                     "a driver that reads its mute switch as 0 whatever it is told never looks like an unmute")
        suite.expect(!MicMuteSupport.isExternalUnmute(wasSilenced: true, silenced: true,
                                                      switchWasEngaged: true, muteSwitch: 1,
                                                      capturedByOtherProcess: true),
                     "a microphone still quiet stays muted")
        suite.expect(!MicMuteSupport.isExternalUnmute(wasSilenced: true, silenced: true,
                                                      switchWasEngaged: true, muteSwitch: nil,
                                                      capturedByOtherProcess: true),
                     "a switch that cannot be read stays muted")
    }

    // MARK: Displays: routes, virtual displays and capture detection

    private static func displayRouteChecks(_ suite: TestSuite) {
        suite.expect(BrightnessSupport.systemRouteRecheckDelay(attempt: 1) == 2
                        && BrightnessSupport.systemRouteRecheckDelay(attempt: 2) == 5
                        && BrightnessSupport.systemRouteRecheckDelay(attempt: 3) == 15,
                     "a display the system stopped answering for is asked about again three times")
        suite.expect(BrightnessSupport.systemRouteRecheckDelay(attempt: 0) == nil
                        && BrightnessSupport.systemRouteRecheckDelay(attempt: 4) == nil,
                     "after the third attempt the display is left to its own control")

        suite.expect(ExtraBrightnessSupport.isNativeCaptureProcess("screencapture")
                        && ExtraBrightnessSupport.isNativeCaptureProcess("screencaptureui"),
                     "the system capture tools count as a capture in progress")
        suite.expect(!ExtraBrightnessSupport.isNativeCaptureProcess("ScreenshotControls")
                        && !ExtraBrightnessSupport.isNativeCaptureProcess("RyzenStatus"),
                     "capture detection ignores the persistent Screenshot controls extension")

        // A dock's virtual monitor can report the same identity as a real
        // monitor of the same model connected beside it.
        var model = BrightnessSupport.DisplayIdentity()
        model.productName = "DELL P2419H"
        model.serialNumber = 42
        var endpoint = BrightnessSupport.ServiceIdentity()
        endpoint.productName = "DELL P2419H"
        endpoint.serialNumber = 42
        endpoint.ordinal = 7
        let matched = BrightnessSupport.speakerServices(
            displays: [(index: 0, identity: model, isVirtual: false),
                       (index: 1, identity: model, isVirtual: true)],
            services: [endpoint])
        suite.expect(matched == [0: 7],
                     "a virtual display never takes a monitor speaker, nor blocks the matching real monitor")

        // Monitors behind a virtual-display dock have no I2C channel and dim
        // through their gamma curve.
        suite.expect(BrightnessSupport.routeSearch(isVirtual: true, isAirPlay: false, isActive: true)
                        == .systemThenSoftware,
                     "an active virtual display is listed and never matched to a DDC service")
        suite.expect(BrightnessSupport.routeSearch(isVirtual: true, isAirPlay: false, isActive: false)
                        == .unlisted,
                     "an inactive virtual display is not listed, so it offers no power button")
        for isVirtual in [true, false] {
            suite.expect(BrightnessSupport.routeSearch(isVirtual: isVirtual, isAirPlay: true,
                                                       isActive: true) == .unlisted,
                         "an AirPlay display is never listed")
        }
        for isActive in [true, false] {
            suite.expect(BrightnessSupport.routeSearch(isVirtual: false, isAirPlay: false,
                                                       isActive: isActive) == .systemThenDDC,
                         "a physical display keeps its row and its DDC route")
        }
        suite.expect(BrightnessSupport.keepsRowWithoutBrightness(isVirtual: false, hasSpeaker: false,
                                                                 canSwitchPower: true)
                        && BrightnessSupport.keepsRowWithoutBrightness(isVirtual: false, hasSpeaker: true,
                                                                       canSwitchPower: false),
                     "a physical display without a brightness route keeps its row for its power button or speaker")
        suite.expect(!BrightnessSupport.keepsRowWithoutBrightness(isVirtual: true, hasSpeaker: false,
                                                                  canSwitchPower: true),
                     "a virtual display without a gamma curve is not listed, because it has no control left")
    }

    // MARK: Monitor speakers that never answer a reading

    /// A monitor that takes writes and never answers a reading: the level is
    /// the one this app last wrote.
    private final class BlindMonitor {
        var level: Int?
        var restore: BrightnessSupport.SpeakerLevel?
        var writes: [(code: UInt8, value: UInt16)] = []

        func change(_ change: BrightnessSupport.SpeakerChange, failWrites: Bool = false)
            -> (level: BrightnessSupport.SpeakerLevel, muted: Bool?)? {
            BrightnessSupport.applySpeakerChange(
                change, hasNativeMute: false, unmutesLeavingZero: false,
                keySettings: MonitorVolumeKeySettings(), restore: &restore,
                read: { code in
                    code == BrightnessSupport.audioVolumeCode
                        ? BrightnessSupport.blindSpeakerReading(remembered: self.level) : nil
                },
                write: { code, value in
                    self.writes.append((code: code, value: value))
                    if failWrites { return false }
                    if code == BrightnessSupport.audioVolumeCode { self.level = Int(value) }
                    return true
                })
        }

        var writesOnlyVolume: Bool {
            writes.allSatisfy { $0.code == BrightnessSupport.audioVolumeCode }
        }
    }

    private static func blindSpeakerChecks(_ suite: TestSuite) {
        let up: BrightnessSupport.SpeakerChange = .step(levels: [{ $0 + 0.0625 }], raises: true)
        let down: BrightnessSupport.SpeakerChange = .step(levels: [{ $0 - 0.0625 }], raises: false)

        let unwritten = BrightnessSupport.blindSpeakerReading(remembered: nil)
        suite.expect(unwritten.current == BrightnessSupport.blindSpeakerStart && unwritten.maximum == 100,
                     "a monitor never written to starts from the low blind level, never a loud one")
        suite.expect(BrightnessSupport.blindSpeakerReading(remembered: 37).current == 37
                        && BrightnessSupport.blindSpeakerReading(remembered: 900).current == 100
                        && BrightnessSupport.blindSpeakerReading(remembered: -5).current == 0,
                     "the remembered blind level is used and kept inside the control's range")

        let first = BlindMonitor()
        let raised = first.change(up)
        suite.expect(first.writes.count == 1 && first.writes.first?.code == BrightnessSupport.audioVolumeCode
                        && first.writes.first?.value == 16,
                     "the first raise on a blind monitor steps up from the low start")
        suite.expect(first.level == 16 && raised?.level.raw == 16,
                     "the first raise is remembered as the monitor's level")
        _ = first.change(up)
        suite.expect(first.level == 22 || first.level == 23, "a second raise continues from the remembered level")
        let beforeLowering = first.level ?? 0
        let lowered = first.change(down)
        suite.expect(Int(lowered?.level.raw ?? 100) < beforeLowering && first.writesOnlyVolume,
                     "a lower steps down from the remembered level and only ever writes the volume control")

        let muting = BlindMonitor()
        muting.level = 40
        let mute = muting.change(.toggleMute)
        suite.expect(mute?.level.raw == 0 && mute?.muted == true && muting.level == 0,
                     "muting a blind monitor drops its volume to zero")
        suite.expect(muting.writesOnlyVolume, "muting a blind monitor never writes the mute control")
        let unmute = muting.change(.toggleMute)
        suite.expect(unmute?.level.raw == 40 && unmute?.muted == false && muting.level == 40,
                     "unmuting a blind monitor brings back the level it had before")

        let refused = BlindMonitor()
        refused.level = 30
        suite.expect(refused.change(up, failWrites: true) == nil && refused.level == 30,
                     "a refused write leaves the remembered level where it was")
        suite.expect(SettingsBackupSupport.machineStateKeys.contains(DefaultsKey.displayAudioBlindLevels)
                        && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.displayAudioBlindLevels),
                     "the levels remembered for unreadable monitors stay on this Mac")
    }

    // MARK: Island preferences

    private static func islandPreferenceChecks(_ suite: TestSuite) {
        let registered = Defaults.registeredDefaults
        let exported = SettingsBackupSupport.exportKeys()

        // Calendar events whose title carries an ignored keyword.
        let ignoreDomain = "com.ryzenstatus.tests.calendar-ignore"
        if let defaults = UserDefaults(suiteName: ignoreDomain) {
            defaults.removePersistentDomain(forName: ignoreDomain)
            defer { defaults.removePersistentDomain(forName: ignoreDomain) }
            defaults.set(" Homeoffice, kiki Arbeit ,,", forKey: DefaultsKey.notchCalendarIgnoredTitles)
            let words = NotchCalendarSupport.ignoredKeywords(in: defaults)
            var event = NotchCalendarEvent(id: "i", title: "KIKI arbeit morgen", calendar: "Work", start: Date(),
                                           end: Date().addingTimeInterval(60), allDay: false, location: "")
            event.countdownKey = "k"
            suite.expect(words == ["homeoffice", "kiki arbeit"],
                         "ignored title keywords are trimmed, lowercased and never empty")
            suite.expect(NotchCalendarSupport.isIgnored(event, keywords: words, chosen: [])
                            && !NotchCalendarSupport.isIgnored(event, keywords: [], chosen: []),
                         "ignored title keywords match case-insensitively")
            suite.expect(!NotchCalendarSupport.isIgnored(event, keywords: words, chosen: ["k"]),
                         "an ignored keyword yields to an event chosen from its menu")
        } else {
            suite.expect(false, "a scratch preferences domain opens for the calendar keywords")
        }

        // The Watch alert's sound.
        let watchDomain = "com.ryzenstatus.tests.watch-sound"
        if let defaults = UserDefaults(suiteName: watchDomain) {
            defaults.removePersistentDomain(forName: watchDomain)
            defer { defaults.removePersistentDomain(forName: watchDomain) }
            suite.expect(NotchWatchSupport.isSoundEnabled(in: defaults)
                            && NotchWatchSupport.resolvedSoundName(in: defaults) == Defaults.defaultNotchWatchSoundName
                            && !NotchWatchSupport.repeatsSound(in: defaults),
                         "a first watch still dings once with the default sound")
            defaults.set("Tink", forKey: DefaultsKey.notchWatchSoundName)
            defaults.set(true, forKey: DefaultsKey.notchWatchSoundRepeat)
            suite.expect(NotchWatchSupport.resolvedSoundName(in: defaults) == "Tink"
                            && NotchWatchSupport.repeatsSound(in: defaults),
                         "the chosen sound and a repeating alert are kept")
            defaults.set("MissingTone", forKey: DefaultsKey.notchWatchSoundName)
            suite.expect(NotchWatchSupport.resolvedSoundName(in: defaults) == Defaults.defaultNotchWatchSoundName,
                         "a sound this Mac no longer has falls back to the default")
        } else {
            suite.expect(false, "a scratch preferences domain opens for the Watch sound")
        }
        suite.expect(registered[DefaultsKey.notchWatchSoundName] as? String == Defaults.defaultNotchWatchSoundName
                        && registered[DefaultsKey.notchWatchSoundRepeat] as? Bool == false,
                     "Watch sound preferences are registered")
        suite.expect(exported.isSuperset(of: [DefaultsKey.notchWatchSoundName, DefaultsKey.notchWatchSoundRepeat]),
                     "Watch sound preferences travel with settings backups")

        // Growing on hover.
        suite.expect(registered[DefaultsKey.notchHoverGrows] as? Bool == true
                        && exported.contains(DefaultsKey.notchHoverGrows),
                     "the closed island keeps growing on hover until the person turns it off")

        // The island names two of its pages as their features do.
        for language in AppLanguage.allCases {
            let strings = Strings.localized(language)
            suite.expect(NotchModule.tools.title(language) == strings.launcherName
                            && NotchModule.files.title(language) == strings.shelfName,
                         "\(language.rawValue): the island names the Quick panel and the Shelf as their features do")
        }
    }

    // MARK: New Track notices

    private static func trackNoticeChecks(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let narrow = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 320, height: 480),
                                   safeAreaTop: 32, cameraWidth: 180)
        let shortTrack = NotchNotice(event: .track, title: "Song", detail: "Artist", symbol: "music.note")
        let titleHeavy = NotchNotice(event: .track, title: String(repeating: "Long title ", count: 20),
                                     detail: "Artist", symbol: "music.note")
        let artistHeavy = NotchNotice(event: .track, title: "Song",
                                      detail: String(repeating: "Long artist ", count: 20), symbol: "music.note")
        suite.expect(shortTrack.preferredWings.leading == shortTrack.preferredWings.trailing
                        && shortTrack.preferredWingWidth < 160,
                     "short tracks grow both sides together without taking the maximum width")
        let growing = [NotchNotice(event: .track, title: "Song for tonight", detail: "Artist", symbol: "music.note"),
                       NotchNotice(event: .track, title: "Song", detail: "A longer artist name", symbol: "music.note")]
        for track in growing {
            let wings = track.preferredWings
            suite.expect(wings.leading == wings.trailing && wings.widest > shortTrack.preferredWingWidth
                            && wings.widest < 160,
                         "either field grows both wings together before reaching the cap")
        }
        let geometries = [narrow,
                          NotchGeometry(screen: CGRect(x: 0, y: 0, width: 420, height: 480),
                                        safeAreaTop: 32, cameraWidth: 210),
                          NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 180),
                          NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0)]
        for track in [titleHeavy, artistHeavy] {
            suite.expect(track.preferredWings == NotchNoticeWings(leading: 160, trailing: 160),
                         "a long title or artist caps both New Track wings equally at 160 points")
            for geometry in geometries {
                let wings = track.wings(in: geometry)
                suite.expect(wings.leading == wings.trailing && geometry.noticeShift(wings) == 0,
                             "New Track stays centered on physical and simulated displays")
                suite.expect(geometry.noticeSize(wings: wings).width <= geometry.screen.width - 24,
                             "New Track stays within the display's bounds")
            }
        }
        suite.expect(NotchEvent.track.duration == 3, "New Track keeps its three-second preview")
    }

    // MARK: The menu bar panel's own clicks

    /// An activation click on the panel itself can surface in the global
    /// dismissal monitor while the app is inactive: the panel must never
    /// treat its own click as an outside one.
    private static func panelSelfClickChecks(_ suite: TestSuite) {
        let panelFrame = CGRect(x: 973, y: 417, width: 358, height: 662)
        let inside = CGPoint(x: 1100, y: 975)
        suite.expect(StatusItemAnchorSupport.isPanelSelfClick(eventWindowNumber: 254631,
                                                              panelWindowNumber: 254631,
                                                              panelFrame: panelFrame,
                                                              mouseLocation: inside),
                     "a click stamped with the panel's own window number never dismisses the panel")
        suite.expect(StatusItemAnchorSupport.isPanelSelfClick(eventWindowNumber: 261851,
                                                              panelWindowNumber: 254631,
                                                              panelFrame: panelFrame,
                                                              mouseLocation: inside),
                     "a click recorded inside the panel frame never dismisses the panel, whatever window it hit")
        suite.expect(!StatusItemAnchorSupport.isPanelSelfClick(eventWindowNumber: 261851,
                                                               panelWindowNumber: 254631,
                                                               panelFrame: panelFrame,
                                                               mouseLocation: CGPoint(x: 300, y: 150)),
                     "a click on another app's window away from the panel still dismisses it")
        suite.expect(!StatusItemAnchorSupport.isPanelSelfClick(eventWindowNumber: 0,
                                                               panelWindowNumber: nil,
                                                               panelFrame: nil,
                                                               mouseLocation: inside),
                     "without a panel window there is no self-click to protect")
    }

    // MARK: The Super Key prints as one glyph

    /// The Super Key is one synthetic key built from all four modifiers. Four
    /// caps in a row read as four keys to press, so the chord collapses into
    /// a single glyph while every ordinary chord keeps its own.
    private static func superKeyGlyphChecks(_ suite: TestSuite) {
        let superKeyChord = GlobalShortcutModifiers.superKeyCombination
        suite.expect(superKeyChord == [.control, .option, .shift, .command],
                     "the Super Key is the synthetic combination of all four modifiers")
        suite.expect(superKeyChord.isSuperKeyCombination
                        && superKeyChord.displayChord == GlobalShortcutModifiers.superKeyGlyph,
                     "the Super Key prints as one glyph instead of four caps")
        suite.expect(superKeyChord.displayCaps.count == 1, "the Super Key offers one cap, not four")
        let ordinaryChords: [GlobalShortcutModifiers] = [
            [.control, .option, .command],
            [.control, .option, .shift],
            [.control, .shift, .command],
            [.option, .shift, .command],
            [.command],
        ]
        for chord in ordinaryChords {
            suite.expect(!chord.isSuperKeyCombination && chord.displayCaps == chord.keyCaps,
                         "an ordinary chord keeps its own caps: \(chord.displayChord)")
            suite.expect(chord.displayChord == chord.keyCaps.joined(),
                         "an ordinary chord prints its own glyphs: \(chord.displayChord)")
        }
        // A combination with a key of its own is a shortcut, not the key on
        // its own: it keeps its four caps beside the key.
        let superKeyPlusK = GlobalShortcut(keyCode: Int64(kVK_ANSI_K), modifiers: superKeyChord)
        suite.expect(superKeyPlusK.displayString.hasPrefix("⌃⌥⇧⌘")
                        && !superKeyPlusK.displayString.contains(GlobalShortcutModifiers.superKeyGlyph),
                     "a Super Key combination with a key keeps the four caps and the key, not the single glyph")
    }

    // MARK: Capture tool numbers, image sizes and the settings file prompt

    private static func captureAndMediaChecks(_ suite: TestSuite) {
        let captureTools = ScreenCaptureTool.allCases
        let withoutText = captureTools.filter { $0 != .text }
        suite.expect(captureTools.compactMap { $0.shortcutKey(in: captureTools) } == ["1", "2", "3", "4", "5"],
                     "number keys follow the capture tools in order")
        suite.expect(withoutText.compactMap { $0.shortcutKey(in: withoutText) } == ["1", "2", "3", "4"],
                     "number keys follow available capture tools without gaps")
        suite.expect(ScreenCaptureTool.matchingShortcut("3", in: withoutText) == .color
                        && ScreenCaptureTool.matchingShortcut("4", in: withoutText) == .scrolling
                        && ScreenCaptureTool.matchingShortcut("5", in: withoutText) == nil,
                     "a number key picks the tool shown under that number")

        let small = MediaImageResizeMode.exact(width: 144, height: 144)
        suite.expect(small.targetSize(for: CGSize(width: 1024, height: 768)) == CGSize(width: 144, height: 144)
                        && MediaSupport.sanitizedImageDimension(144, fallback: 1600) == 144,
                     "Image exact resize accepts arbitrary pixel sizes such as 144×144")

        for language in AppLanguage.allCases {
            suite.expect(FeatureStrings.backup(language).configFileConfirmFormat.contains("%@"),
                         "\(language.rawValue) settings file confirmation names the path")
            let strings = FeatureStrings.screenshot(language)
            suite.expect(!strings.watermarkLayoutLabel.isEmpty && !strings.watermarkLayoutSingle.isEmpty
                            && !strings.watermarkLayoutTiled.isEmpty,
                         "watermark layouts are named in \(language.rawValue)")
            suite.expect(strings.watermarkLayoutSingle != strings.watermarkLayoutTiled,
                         "watermark layouts have distinct names in \(language.rawValue)")
        }
    }

    // MARK: Backups keep a stable key order

    /// Swift seeds its hash per process, so JSON the export rebuilds must not
    /// depend on dictionary order, or an unchanged setup writes a new file.
    private static func stableExportChecks(_ suite: TestSuite) {
        typealias Style = ScreenshotSupport.WatermarkStyle
        let style = Style(kind: .text, text: "Portable", color: "blue", rotation: 20)
        let options = MediaImageOptions(quality: 0.8, maxDimension: 1400, format: .png, stripMetadata: false,
                                        watermark: MediaImageWatermark(kind: .text, text: "Sample", opacity: 0.5))
        let presets = [RecorderEditPreset(name: "Preset", document: RecorderEditDocument())]
        let profiles = [MediaImageProfile(id: "profile", name: "Profile", options: options)]
        let profileText = String(decoding: (try? JSONEncoder().encode(profiles)) ?? Data(), as: UTF8.self)
        let source: [String: Any] = [
            DefaultsKey.screenshotWatermarkStyle: style.encoded(),
            DefaultsKey.screenshotWatermarkPresets: ScreenshotSupport.encodedWatermarkPresets([style]),
            DefaultsKey.recorderEditorPresets: (try? JSONEncoder().encode(presets)) ?? Data(),
            DefaultsKey.mediaImageProfiles: profileText,
        ]
        let payload = SettingsBackupSupport.payload(appVersion: "test") { source[$0] }
        let exported = payload[SettingsBackupSupport.settingsKey] as? [String: Any] ?? [:]
        func canonical<T: Codable>(_ type: T.Type, _ data: Data) -> Data? {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? JSONDecoder().decode(type, from: data)).flatMap { try? encoder.encode($0) }
        }
        let types: [String: (Data) -> Data?] = [
            DefaultsKey.screenshotWatermarkStyle: { canonical(Style.self, $0) },
            DefaultsKey.screenshotWatermarkPresets: { canonical([Style].self, $0) },
            DefaultsKey.recorderEditorPresets: { canonical([RecorderEditPreset].self, $0) },
            DefaultsKey.mediaImageProfiles: { canonical([MediaImageProfile].self, $0) },
        ]
        for key in source.keys.sorted() {
            let data = (exported[key] as? Data) ?? (exported[key] as? String).map { Data($0.utf8) }
            let sorted = data.flatMap { types[key]?($0) }
            suite.expect(data != nil && data == sorted, "export writes \(key) with a stable key order")
        }
    }

    // MARK: Watermark layouts

    private static func watermarkLayoutChecks(_ suite: TestSuite) {
        typealias Style = ScreenshotSupport.WatermarkStyle
        let style = Style(kind: .text, text: "Private", anchor: .topLeading,
                          size: 0.2, opacity: 0.3, rotation: 45, layout: .tiled)
        suite.expect(Style.decoded(style.encoded()) == style,
                     "tiled watermark settings round-trip without changing their appearance")
        let presets = ScreenshotSupport.decodedWatermarkPresets(ScreenshotSupport.encodedWatermarkPresets([style]))
        suite.expect(presets == [style], "tiled watermark presets retain their layout")

        guard let object = try? JSONSerialization.jsonObject(with: Data(style.encoded().utf8)),
              var json = object as? [String: Any] else {
            suite.expect(false, "a watermark style encodes to a JSON object")
            return
        }
        var single = style
        single.layout = .single
        for layout in [nil, "future-layout"] as [String?] {
            json["layout"] = layout
            guard let data = try? JSONSerialization.data(withJSONObject: json),
                  let raw = String(data: data, encoding: .utf8) else {
                suite.expect(false, "a watermark style without a known layout encodes")
                continue
            }
            suite.expect(Style.decoded(raw) == single,
                         "old or unknown layouts keep the existing single watermark settings")
            suite.expect(ScreenshotSupport.decodedWatermarkPresets("[\(raw)]") == [single],
                         "old or unknown preset layouts preserve the preset")
        }
    }

    // MARK: Radial menu snippets

    private static func radialSnippetChecks(_ suite: TestSuite) {
        let snippetID = UUID()
        let snippet = TextSnippet(id: snippetID, name: "Greeting", trigger: ";hello",
                                  replacement: "Hello there")
        let item = RadialMenuItem(kind: .snippet, payload: snippetID.uuidString)
        suite.expect(RadialMenuSupport.decode(RadialMenuSupport.encode([item])) == [item],
                     "a snippet slice keeps its target")
        suite.expect(RadialMenuSupport.needsAccessibility([item])
                        && RadialMenuSupport.snippet(for: item, in: [snippet]) == snippet,
                     "a snippet slice finds its snippet and requests Accessibility for insertion")
        var disabled = snippet
        disabled.enabled = false
        suite.expect(RadialMenuSupport.snippet(for: item, in: [disabled]) == nil
                        && RadialMenuSupport.snippet(for: item, in: []) == nil,
                     "disabled and deleted snippet targets cannot run")
        suite.expect(RadialMenuSupport.sanitized([RadialMenuItem(kind: .snippet, payload: "missing")]).isEmpty,
                     "an invalid snippet target is dropped")
    }

    // MARK: Audio priority: one entry per device name

    private static func audioPriorityChecks(_ suite: TestSuite) {
        let desktop = "Studio iMac"
        let speakers = (uid: "speakers", name: "Speakers")
        suite.expect(MixerRoutingSupport.mergingPriorityDevicesByName(
            ["speakers", "airplay-old", "display"],
            connected: [speakers, (uid: "airplay-new", name: desktop)],
            storedNames: ["airplay-old": desktop, "display": "Display"])
            == ["speakers", "airplay-new", "display"],
            "an AirPlay device that reconnects with a new UID takes its old slot instead of adding an entry")
        suite.expect(MixerRoutingSupport.mergingPriorityDevicesByName(
            ["airplay-1", "speakers", "airplay-2", "airplay-3", "airplay-4"],
            connected: [speakers, (uid: "airplay-4", name: desktop)],
            storedNames: ["airplay-1": desktop, "airplay-2": desktop, "airplay-3": desktop])
            == ["airplay-4", "speakers"],
            "existing duplicates collapse into the highest slot, held by the connected device")
        suite.expect(MixerRoutingSupport.mergingPriorityDevicesByName(
            ["airplay-1", "speakers", "airplay-2"],
            connected: [speakers],
            storedNames: ["airplay-1": desktop, "airplay-2": desktop])
            == ["airplay-1", "speakers"],
            "disconnected duplicates keep only the highest entry")
        suite.expect(MixerRoutingSupport.mergingPriorityDevicesByName(
            ["usb-a", "speakers", "usb-b"],
            connected: [(uid: "usb-a", name: "USB Audio"), speakers, (uid: "usb-b", name: "USB Audio")],
            storedNames: [:])
            == ["usb-a", "speakers", "usb-b"],
            "two connected devices with the same name both keep their places")
        suite.expect(MixerRoutingSupport.mergingPriorityDevicesByName(
            ["speakers", "offline"],
            connected: [speakers, (uid: "headphones", name: "Headphones")],
            storedNames: ["offline": "Display"])
            == ["speakers", "offline"],
            "a device with a new name is left for normal placement")
        suite.expect(MixerRoutingSupport.mergingPriorityDevicesByName(
            ["speakers", "unnamed"],
            connected: [speakers, (uid: "other", name: " ")],
            storedNames: [:])
            == ["speakers", "unnamed"],
            "entries without a known name are never matched")
    }

    // MARK: Switcher preview cards follow the preview size

    private static func switcherPreviewChecks(_ suite: TestSuite) {
        // The layout reads the preview size from the standard preferences.
        let key = DefaultsKey.switcherPreviewSize
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)

        UserDefaults.standard.set("large", forKey: key)
        let large = SwitcherIconRowLayout.compute(appCount: 6, selectedWindowCount: 1, screenVisibleFrame: screen)
        UserDefaults.standard.set("xlarge", forKey: key)
        let xlarge = SwitcherIconRowLayout.compute(appCount: 6, selectedWindowCount: 1, screenVisibleFrame: screen)
        suite.expect(SwitcherIconRowLayout.scale <= 1.15,
                     "App Switcher icon-row mode caps Extra High icon scaling")
        suite.expect(xlarge.previewCardWidth > large.previewCardWidth
                        && large.previewCardWidth > SwitcherIconRowLayout.basePreviewCardWidth * 1.15,
                     "App Switcher icon-row previews still grow past Large when the screen has room")
        suite.expect(xlarge.panelSize.height <= screen.height * 0.85,
                     "App Switcher icon-row mode keeps Extra High previews inside the screen budget")
        let expectedHeight = xlarge.previewHeight + SwitcherIconRowLayout.previewGap
            + SwitcherIconRowLayout.rowHeight + SwitcherIconRowLayout.hintGap
            + SwitcherIconRowLayout.hintHeight + SwitcherIconRowLayout.padding * 2
        suite.expectClose(Double(xlarge.panelSize.height), Double(expectedHeight),
                          "App Switcher icon-row panel height follows its own preview height")

        let single = SwitcherIconRowLayout.compute(appCount: 1, selectedWindowCount: 1, screenVisibleFrame: screen)
        suite.expectClose(Double(single.previewContentWidth), Double(single.previewCardWidth),
                          "App Switcher icon-row mode keeps a one-window preview card compact")
        suite.expectClose(Double(single.previewSurfaceWidth),
                          Double(single.previewCardWidth + SwitcherIconRowLayout.previewPanelPadding * 2),
                          "App Switcher icon-row mode keeps padding around a one-window preview card")
        let widest = max(single.previewSurfaceWidth, SwitcherIconRowLayout.hintBarWidth)
        suite.expect(single.panelSize.width <= widest + SwitcherIconRowLayout.padding * 2 + 0.5,
                     "App Switcher icon-row mode avoids a giant horizontal panel for one app with one window")

        // Cards count their spacing before the preview stops scrolling.
        let capped = SwitcherIconRowLayout.compute(appCount: 3, selectedWindowCount: 8,
                                                   screenVisibleFrame: CGRect(x: 0, y: 0, width: 1280, height: 800))
        var fitting = 0
        while CGFloat(fitting + 1) * capped.previewCardWidth + CGFloat(fitting) * SwitcherIconRowLayout.spacing
                <= capped.previewContentWidth {
            fitting += 1
        }
        suite.expect(fitting >= 1 && capped.previewContentWidth < capped.naturalPreviewWidth(cardCount: 8),
                     "App Switcher bounds eight previews to less than their natural width")
        suite.expect(capped.previewFitsWithoutScrolling(cardCount: fitting)
                        && !capped.previewFitsWithoutScrolling(cardCount: fitting + 1),
                     "App Switcher preview counts card spacing before it stops scrolling")
    }

    // MARK: Switcher hands its keys back to an exclusive full screen

    /// Decided from window-server snapshots alone.
    private static func fullscreenHandBackChecks(_ suite: TestSuite) {
        let display = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let second = CGRect(x: 2560, y: 0, width: 1920, height: 1080)
        let game: pid_t = 400, dock: pid_t = 300, own: pid_t = 500
        let shielding = Int(CGShieldingWindowLevel())

        func window(_ number: CGWindowID, pid: pid_t, layer: Int, alpha: Double = 1,
                    bounds: CGRect) -> NotchAppFullscreen.WindowInfo {
            NotchAppFullscreen.WindowInfo(number: number, ownerPID: pid, layer: layer, alpha: alpha, bounds: bounds)
        }
        func raises(_ windows: [NotchAppFullscreen.WindowInfo], frontmost: pid_t?) -> Bool {
            SwitcherSupport.frontmostAppRaisesFullscreen(windows: windows, frontmostPID: frontmost,
                                                         ownPID: own, displays: [display, second])
        }

        let exclusive = window(1, pid: game, layer: shielding, bounds: display)
        let desktopApp = window(2, pid: 200, layer: 0, bounds: CGRect(x: 100, y: 100, width: 1200, height: 800))
        suite.expect(raises([exclusive, desktopApp], frontmost: game),
                     "a frontmost game covering the display at the shielding level hands the keys back")
        suite.expect(raises([window(1, pid: game, layer: 3, bounds: display.insetBy(dx: 1, dy: 1))], frontmost: game),
                     "any raised level counts, and a point of rounding on each edge still covers")
        suite.expect(raises([window(1, pid: game, layer: shielding, bounds: second)], frontmost: game),
                     "covering a secondary display alone counts")

        suite.expect(!raises([window(1, pid: game, layer: 0, bounds: display)], frontmost: game),
                     "a borderless or macOS full-screen window at level 0 keeps the switcher")
        let tooltip = window(1, pid: game, layer: shielding, bounds: CGRect(x: 800, y: 600, width: 400, height: 80))
        suite.expect(!raises([tooltip], frontmost: game),
                     "a raised window covering part of a display, such as a tooltip, keeps the switcher")
        let dockOverGame = [window(1, pid: dock, layer: 20, bounds: display),
                            window(2, pid: game, layer: 0, bounds: display)]
        suite.expect(!raises(dockOverGame, frontmost: game),
                     "a window another app raises over the display, as the Dock does, is not the game's")
        suite.expect(!raises([window(1, pid: game, layer: shielding, alpha: 0, bounds: display)], frontmost: game),
                     "an invisible raised window keeps the switcher")
        suite.expect(!raises([exclusive], frontmost: 200) && !raises([exclusive], frontmost: nil),
                     "only the frontmost app's window counts")
        suite.expect(!raises([window(1, pid: own, layer: shielding, bounds: display)], frontmost: own),
                     "the app's own overlays never hand the keys back")

        let tab = Int64(kVK_Tab), grave = Int64(kVK_ANSI_Grave)
        let liveEntries = [
            LiveSystemShortcut(id: 1, shortcut: GlobalShortcut(keyCode: tab, modifiers: [.command]), enabled: true),
            LiveSystemShortcut(id: 2, shortcut: GlobalShortcut(keyCode: tab, modifiers: [.command, .shift]),
                               enabled: true),
            LiveSystemShortcut(id: 27, shortcut: GlobalShortcut(keyCode: grave, modifiers: [.command]), enabled: true),
            LiveSystemShortcut(id: 220, shortcut: GlobalShortcut(keyCode: grave, modifiers: [.command, .shift]),
                               enabled: true),
        ]
        let yielded = SwitcherSupport.nativeHotkeyIDs(takeOverSystemShortcuts: true, secureInputEnabled: false,
                                                      exclusiveFullscreen: true,
                                                      appsShortcut: .switcherDefault,
                                                      windowShortcut: .switcherWindowDefault,
                                                      liveEntries: liveEntries)
        suite.expect(yielded.isEmpty, "while a game owns the display, the switching keys stay with macOS")
        let taken = SwitcherSupport.nativeHotkeyIDs(takeOverSystemShortcuts: true, secureInputEnabled: false,
                                                    exclusiveFullscreen: false,
                                                    appsShortcut: .switcherDefault,
                                                    windowShortcut: .switcherWindowDefault,
                                                    liveEntries: liveEntries)
        suite.expect(taken == [1, 2, 27, 220], "once the game's full screen ends the switcher takes its four ids again")
    }

    // MARK: Scratchpad sets done tasks aside

    private static func scratchpadChecks(_ suite: TestSuite) {
        let source = "- [ ] first\n- [x] done\n- plain\n- [ ] last"
        let blocks = ScratchpadSupport.markdownPreview(source)
        let split = ScratchpadSupport.splitCompleted(blocks)
        let doneAreChecked = split.done.allSatisfy {
            if case .taskListItem(_, true, _) = $0.kind { return true } else { return false }
        }
        suite.expect(split.done.count == 1 && doneAreChecked, "the completed tasks are set aside")
        suite.expect(split.open.count == blocks.count - 1, "everything else keeps its place in the reading")
    }
}
