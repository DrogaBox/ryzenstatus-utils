// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import SwiftUI

/// The companion's own page. It lives at the top in a slice of the island,
/// bigger than life, and acts out what it does on request; below are how it
/// looks, how it behaves and whether the Command Bar comes out with it.
struct NotchMascotSettings: View {
    /// A purchase in the shop redraws what the wardrobe lists. Only that is
    /// watched: the hourglass changes every few seconds, and observing the
    /// whole state redrew every preview on the page each time.
    @State private var purchases = NotchMascotRPGState.shared.purchases
    /// Shown as a tab of the Dynamic Island page, which keeps its own margins.
    var embedded = false
    @ObservedObject private var l10n = L10n.shared
    /// Redraws when the island or the Command Bar is installed or removed.
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.notchEnabled) private var islandEnabled = false
    @AppStorage(DefaultsKey.notchSilhouette) private var silhouette = NotchSilhouette.capsule.rawValue
    @AppStorage(DefaultsKey.notchMascotEnabled) private var enabled = false
    @AppStorage(DefaultsKey.notchMascotVisits) private var visits = true
    @AppStorage(DefaultsKey.notchMascotReactions) private var reactions = true
    @AppStorage(DefaultsKey.notchMascotHidesWhenIdle) private var hidesWhenIdle = true
    @AppStorage(DefaultsKey.notchMascotPerch) private var perch = true
    @AppStorage(DefaultsKey.notchMascotDesktop) private var desktop = false
    @AppStorage(DefaultsKey.notchMascotExcursions) private var excursions = true
    @AppStorage(DefaultsKey.notchMascotDesktopFriend) private var friend = ""
    @AppStorage(DefaultsKey.notchMascotDesktopPlay) private var friendsPlay = true
    @AppStorage(DefaultsKey.notchMascotFriendAccessory) private var friendAccessory = ""
    @AppStorage(DefaultsKey.notchMascotStyle) private var style = NotchMascotStyle.minimal.rawValue
    @AppStorage(DefaultsKey.notchMascotShape) private var shape = NotchMascotShape.ball.rawValue
    @AppStorage(DefaultsKey.notchMascotPalette) private var palette = NotchMascotPalette.pearl.rawValue
    @AppStorage(DefaultsKey.notchMascotSide) private var side = NotchMascotSide.left.rawValue
    @AppStorage(DefaultsKey.notchMascotVisitFrequency) private var frequency = NotchMascotVisitFrequency.normal.rawValue
    @AppStorage(DefaultsKey.notchCommandBar) private var commandBar = true
    @AppStorage(DefaultsKey.notchCommandBarStyle) private var commandBarStyle = NotchCommandBarStyle.droplet.rawValue
    @AppStorage(DefaultsKey.notchMascotAutomatic) private var automatic = true
    @AppStorage(DefaultsKey.notchMascotAutoLoad) private var autoLoad = true
    @AppStorage(DefaultsKey.notchMascotAutoMusic) private var autoMusic = true
    @AppStorage(DefaultsKey.notchMascotAutoRest) private var autoRest = true
    @AppStorage(DefaultsKey.notchMascotAutoCoffee) private var autoCoffee = true
    @AppStorage(DefaultsKey.notchMascotAutoNetwork) private var autoNetwork = true
    @AppStorage(DefaultsKey.notchMascotAutoEvents) private var autoEvents = true
    @AppStorage(DefaultsKey.notchMascotAutoAntics) private var autoAntics = true
    @AppStorage(DefaultsKey.notchMascotAccessory) private var accessory = NotchMascotAccessory.none.rawValue
    @AppStorage(DefaultsKey.notchMascotName) private var petName = ""
    @AppStorage(DefaultsKey.notchMascotSeasonal) private var seasonal = true
    @AppStorage(DefaultsKey.notchMascotSound) private var soundOn = true
    @AppStorage(DefaultsKey.notchMascotSoundVolume) private var soundVolume = NotchMascotSound.defaultVolume
    @AppStorage(DefaultsKey.notchMascotForm) private var formChoice = NotchMascotFormChoice.automatic.rawValue
    @AppStorage(DefaultsKey.notchMascotSpeech) private var speech = true
    @AppStorage(DefaultsKey.notchMascotHardware) private var hardware = true
    @AppStorage(DefaultsKey.gamingModeActive) private var gaming = false
    @ObservedObject private var bondStore = NotchMascotBondStore.shared
    @ObservedObject private var router = SettingsRouter.shared
    @State private var confirmingReset = false
    /// The part of the page shown under the stage.
    @State private var section = Part.appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var life: NotchMascotLifeStrings { FeatureStrings.notchMascotLife(l10n.language) }
    private var level: Int { NotchMascotGrowth.shownLevel(earned: bondStore.level, name: petName) }
    private var chosenAccessory: NotchMascotAccessory { NotchMascotAccessory(rawValue: accessory) ?? .none }
    private var forms: NotchMascotFormStrings { FeatureStrings.notchMascotForms(l10n.language) }
    private var choice: NotchMascotFormChoice { NotchMascotFormChoice(rawValue: formChoice) }
    private var shownForm: NotchMascotForm? { NotchMascotTransformation.effective(choice: choice, level: level) }

    /// Its name, shared with the Features page.
    private var mascotTitle: String { FeatureStrings.hub(l10n.language).titleNotchMascot }
    private var text: NotchMascotSettingsStrings { FeatureStrings.notchMascotSettings(l10n.language) }
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }
    private var auto: NotchMascotAutomationStrings { FeatureStrings.notchMascotAutomation(l10n.language) }

    private var look: NotchMascotLook {
        NotchMascotLook(style: NotchMascotStyle.resolved(style, name: petName),
                        shape: NotchMascotShape(rawValue: shape) ?? .ball,
                        palette: NotchMascotPalette(rawValue: palette) ?? .pearl,
                        accessory: NotchMascotWardrobe.effective(chosen: chosenAccessory, level: level, date: Date(),
                                                                 adopted: bondStore.bond.adopted, seasonal: seasonal,
                                                                 gaming: gaming && hardware),
                        form: shownForm)
    }

    private var restingSide: NotchMascotSide { NotchMascotSide(rawValue: side) ?? .left }

    /// The island it lives in is installed and on.
    private var islandOn: Bool { features.isAvailable(.notch) && islandEnabled }

    /// It rests beside a camera, real or drawn, so the side it takes matters.
    /// A capsule holds it in the middle.
    private var restsBesideCamera: Bool {
        NotchSupport.hasNotchedDisplay || NotchSilhouette(rawValue: silhouette) == .notch
    }

    /// The floating style on a display without a camera, where the open
    /// island leaves it up in the menu bar.
    private var perchesInMenuBar: Bool {
        NotchSupport.hasDisplayWithoutNotch && NotchSilhouette(rawValue: silhouette) == .floating
    }

    private var animation: Animation? { reduceMotion ? nil : .smooth(duration: 0.25) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !islandOn { islandNote }
                NotchMascotStageCard(look: look, side: restingSide, awake: enabled, canGreet: enabled && islandOn,
                                     visits: visits, reactions: reactions, hides: hidesWhenIdle, text: text,
                                     language: l10n.language)
                // Nine cards one under the other were too much to take in at
                // once, so they are grouped, one group at a time.
                Picker(text.appearance, selection: $section) {
                    ForEach(Part.allCases) { Text(title(of: $0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                switch section {
                case .appearance:
                    appearance
                    transformationsCard
                case .wardrobe:
                    NotchMascotShopCard(look: look, language: l10n.language)
                    wardrobeCard
                case .story:
                    storyCard
                case .behavior:
                    behavior
                    automaticCard
                    soundCard
                    commandBarCard
                }
            }
            .padding(embedded ? [.bottom] : .all, 22)
        }
        .onReceive(NotchMascotRPGState.shared.$purchases.removeDuplicates()) { purchases = $0 }
        .onAppear(perform: consumeShopHint)
        .onChange(of: router.notchCompanionShop) { _, _ in consumeShopHint() }
    }

    /// The shop was asked for, from the companion on the desktop or the island.
    private func consumeShopHint() {
        guard router.notchCompanionShop else { return }
        router.notchCompanionShop = false
        section = .wardrobe
    }

    private enum Part: Int, CaseIterable, Identifiable {
        case appearance, wardrobe, story, behavior
        var id: Int { rawValue }
    }

    private func title(of section: Part) -> String {
        switch section {
        case .appearance: text.appearance
        case .wardrobe: life.accessories
        case .story: life.bondTitle
        case .behavior: text.behavior
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(mascotTitle).font(.title2.bold())
                Text(text.hint).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle(mascotTitle, isOn: $enabled).labelsHidden().toggleStyle(.switch)
                .accessibilityLabel(mascotTitle)
        }
    }

    /// With the island off or uninstalled the companion has nowhere to live,
    /// so the page says so and offers the way to bring the island back.
    private var islandNote: some View {
        let installed = features.isAvailable(.notch)
        let notch = FeatureStrings.notch(l10n.language)
        return HStack(spacing: 12) {
            Image(systemName: AppFeature.notch.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(text.livesInIsland)
                if !installed {
                    Text(AppFeature.notch.enableReason(l10n)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            if installed {
                Button(notch.enable) {
                    islandEnabled = true
                    NotchService.shared.syncWithPreferences()
                }
            } else {
                Button(editor.openFeatures) { AppFeature.notch.showInFeatures() }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Appearance

    private var appearance: some View {
        SettingsCard(title: text.appearance) {
            SettingsRow(symbol: "paintpalette", title: text.style) { EmptyView() }
            // The companions to choose from, in as many rows as the page needs.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 10)],
                      alignment: .leading, spacing: 10) {
                ForEach(NotchMascotStyle.available(name: petName)) { item in
                    NotchMascotChoiceTile(title: auto.style(item, base: text), selected: look.style == item) {
                        style = item.rawValue
                    } preview: {
                        NotchMascotView(look: NotchMascotLook(style: item, shape: look.shape, palette: look.palette),
                                        size: 30, idles: false)
                            .frame(width: 30, height: 30)
                            .frame(width: 64, height: 42)
                            .background(Color.black, in: Capsule())
                    }
                }
            }
            .padding(.leading, settingsRowTextInset)
            if look.style.takesShape {
                SettingsRow(symbol: "circle.square", title: text.shape) {
                    Text(text.shape(look.shape)).foregroundStyle(.secondary)
                }
                .transition(.opacity)
                shapes
                    .transition(.opacity)
            }
            // A sprite figure keeps its own colours.
            if look.style.takesPalette {
                SettingsRow(symbol: "swatchpalette", title: text.color) {
                    Text(text.palette(look.palette)).foregroundStyle(.secondary)
                }
                .transition(.opacity)
                swatches
                    .transition(.opacity)
            }
        }
        .animation(animation, value: look.style)
    }

    private var shapes: some View {
        HStack(spacing: 8) {
            ForEach(NotchMascotShape.allCases) { item in
                let selected = look.shape == item
                Button { shape = item.rawValue } label: {
                    NotchMascotView(look: NotchMascotLook(style: .minimal, shape: item, palette: look.palette),
                                    size: 24, idles: false)
                        .frame(width: 24, height: 24)
                        .frame(width: 58, height: 40)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(2)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(text.shape(item))
                .accessibilityLabel(text.shape(item))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selected)
            }
        }
        .padding(.leading, settingsRowTextInset)
    }

    private var swatches: some View {
        HStack(spacing: 8) {
            ForEach(NotchMascotPalette.allCases) { item in
                let selected = look.palette == item
                Button { palette = item.rawValue } label: {
                    Circle()
                        .fill(LinearGradient(colors: [Color(cgColor: item.light.cgColor), Color(cgColor: item.shade.cgColor)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                        .padding(3)
                        .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(text.palette(item))
                .accessibilityLabel(text.palette(item))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selected)
            }
        }
        .padding(.leading, settingsRowTextInset)
    }

    // MARK: Story

    private var storyCard: some View {
        let bond = bondStore.bond
        // The name that unlocks everything shows it at the top, full bar.
        let progress = NotchMascotGrowth.unlocksEverything(name: petName)
            ? nil : NotchMascotGrowth.progress(for: bond.experience)
        return SettingsCard(title: life.bondTitle) {
            Text(life.bondHint).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsRow(symbol: "pencil", title: life.name) {
                TextField(life.namePlaceholder, text: $petName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                    .onChange(of: petName) { old, name in
                        if name.count > 24 { petName = String(name.prefix(24)) }
                        // Taking the name that unlocks everything greets it
                        // with the transformation it now has.
                        if NotchMascotGrowth.unlocksEverything(name: name),
                           !NotchMascotGrowth.unlocksEverything(name: old) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                NotificationCenter.default.post(name: .notchMascotTransforms, object: nil)
                            }
                        }
                    }
            }
            SettingsRow(symbol: "star.fill", title: life.level(level)) {
                Text(progress.map { life.progress($0.done, of: $0.span) } ?? life.maxLevel)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: Double(progress?.done ?? 1), total: Double(max(1, progress?.span ?? 1)))
                .tint(.pink)
                .padding(.leading, settingsRowTextInset)
            HStack(spacing: 10) {
                statTile("calendar", life.age,
                         life.days(NotchMascotGrowth.age(of: bond, at: Date())))
                statTile("hand.raised.fill", life.pets, "\(bond.pets)")
                statTile("sparkles", life.moments, "\(bond.moments)")
                statTile("sun.max.fill", life.daysTogetherLabel, "\(bond.daysTogether)")
            }
            .padding(.leading, settingsRowTextInset)
            HStack {
                Spacer()
                Button(life.reset, role: .destructive) { confirmingReset = true }
                    .confirmationDialog(life.reset, isPresented: $confirmingReset) {
                        Button(life.reset, role: .destructive) { bondStore.reset() }
                    } message: {
                        Text(life.resetConfirm)
                    }
            }
        }
    }

    private func statTile(_ symbol: String, _ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.pink)
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Wardrobe

    /// What a tile not yet worn says: its level, or what it costs in the shop.
    private func lockedTitle(_ item: NotchMascotAccessory) -> String {
        guard item.isPurchasable else { return life.locked(at: item.unlockLevel) }
        return "\(FeatureStrings.notchMascotShop(L10n.shared.language).shopTag) · \(item.price)"
    }

    private var wardrobeCard: some View {
        SettingsCard(title: life.accessories) {
            SettingsRow(symbol: "tshirt", title: life.accessories, caption: life.accessoriesHint) {
                Text(life.name(of: look.accessory)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 10)],
                      alignment: .leading, spacing: 10) {
                // What the shop sells stays a surprise until it is bought.
                ForEach(NotchMascotAccessory.wardrobe.filter { !$0.isPurchasable || $0.unlockLevel <= level }) { item in
                    let unlocked = item.unlockLevel <= level
                    NotchMascotChoiceTile(title: unlocked ? life.name(of: item) : lockedTitle(item),
                                          selected: chosenAccessory == item) {
                        if unlocked { accessory = item.rawValue }
                    } preview: {
                        NotchMascotView(look: NotchMascotLook(style: look.style, shape: look.shape,
                                                              palette: look.palette, accessory: item),
                                        size: 30, idles: false)
                            .frame(width: 30, height: 30)
                            .frame(width: 64, height: 42)
                            .background(Color.black, in: Capsule())
                            .opacity(unlocked ? 1 : 0.35)
                            .overlay {
                                if !unlocked {
                                    Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .disabled(!unlocked)
                }
            }
            .padding(.leading, settingsRowTextInset)
            .id(purchases)
            switchRow("leaf", life.seasonal, caption: life.seasonalHint, isOn: $seasonal)
            switchRow("text.bubble", life.speech, caption: life.speechHint, isOn: $speech)
            switchRow("cpu", life.hardware, caption: life.hardwareHint, isOn: $hardware)
        }
    }

    // MARK: Transformations

    private var transformationsCard: some View {
        SettingsCard(title: forms.title) {
            SettingsRow(symbol: "bolt.fill", title: forms.title, caption: forms.hint) {
                Text(forms.name(of: shownForm)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 10)],
                      alignment: .leading, spacing: 10) {
                NotchMascotChoiceTile(title: forms.none, selected: choice == .off) {
                    formChoice = NotchMascotFormChoice.off.rawValue
                } preview: {
                    formPreview(nil, unlocked: true)
                }
                ForEach(NotchMascotForm.allCases) { item in
                    let unlocked = item.unlockLevel <= level
                    NotchMascotChoiceTile(title: unlocked ? forms.name(of: item) : life.locked(at: item.unlockLevel),
                                          selected: choice != .off && shownForm == item) {
                        if unlocked { formChoice = NotchMascotFormChoice.form(item).rawValue }
                    } preview: {
                        formPreview(item, unlocked: unlocked)
                    }
                    .disabled(!unlocked)
                }
            }
            .padding(.leading, settingsRowTextInset)
            if shownForm != nil {
                HStack {
                    Spacer()
                    Button(forms.replay) {
                        NotificationCenter.default.post(name: .notchMascotTransforms, object: nil)
                    }
                }
            }
        }
    }

    private func formPreview(_ form: NotchMascotForm?, unlocked: Bool) -> some View {
        NotchMascotView(look: NotchMascotLook(style: look.style, shape: look.shape, palette: look.palette,
                                              accessory: look.accessory, form: form),
                        size: 30, idles: false)
            .frame(width: 30, height: 30)
            .frame(width: 64, height: 42)
            .background(Color.black, in: Capsule())
            .opacity(unlocked ? 1 : 0.35)
            .overlay {
                if !unlocked {
                    Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
    }

    // MARK: Behavior

    private var behavior: some View {
        SettingsCard(title: text.behavior) {
            if restsBesideCamera {
                SettingsRow(symbol: "arrow.left.and.right", title: text.side) { EmptyView() }
                HStack(spacing: 10) {
                    ForEach(NotchMascotSide.allCases) { item in
                        NotchMascotChoiceTile(title: text.side(item), selected: restingSide == item) {
                            side = item.rawValue
                        } preview: {
                            NotchMascotSideSample(look: look, side: item)
                        }
                    }
                }
                .padding(.leading, settingsRowTextInset)
            }
            switchRow("eye.slash", text.hidesWhenIdle, caption: text.hidesWhenIdleHint, isOn: $hidesWhenIdle)
            if perchesInMenuBar {
                let perchText = FeatureStrings.notchMascotPerch(l10n.language)
                switchRow("menubar.rectangle", perchText.title, caption: perchText.caption, isOn: $perch)
            }
            switchRow("figure.walk", text.visits, caption: text.visitsHint, isOn: $visits)
            if visits {
                SettingsChoiceRow(symbol: "clock", title: text.frequency, selection: $frequency) {
                    ForEach(NotchMascotVisitFrequency.allCases) { Text(text.frequency($0)).tag($0.rawValue) }
                }
                .padding(.leading, settingsRowTextInset)
                .transition(.opacity)
            }
            switchRow("theatermasks", text.reactions, caption: text.reactionsHint, isOn: $reactions)
            let desktopText = FeatureStrings.notchMascotDesktop(l10n.language)
            switchRow("desktopcomputer", desktopText.title, caption: desktopText.caption, isOn: $desktop)
            if desktop {
                switchRow("figure.walk.motion", desktopText.excursions, caption: desktopText.excursionsCaption,
                          isOn: $excursions)
                    .padding(.leading, settingsRowTextInset)
                    .transition(.opacity)
                SettingsChoiceRow(symbol: "person.2", title: desktopText.friend, selection: $friend) {
                    Text(desktopText.nobody).tag("")
                    ForEach(NotchMascotStyle.available(name: petName)) { Text(auto.style($0, base: text)).tag($0.rawValue) }
                }
                .padding(.leading, settingsRowTextInset)
                .transition(.opacity)
                if !friend.isEmpty {
                    SettingsChoiceRow(symbol: "tshirt", title: desktopText.friendItem, selection: $friendAccessory) {
                        Text(desktopText.friendItemOwn).tag("")
                        ForEach(NotchMascotAccessory.wardrobe.filter { $0.unlockLevel <= level }) {
                            Text(life.name(of: $0)).tag($0.rawValue)
                        }
                    }
                    .padding(.leading, settingsRowTextInset)
                    .transition(.opacity)
                    switchRow("figure.2.and.child.holdinghands", desktopText.plays, caption: desktopText.playsCaption,
                              isOn: $friendsPlay)
                        .padding(.leading, settingsRowTextInset)
                        .transition(.opacity)
                }
            }
        }
        .animation(animation, value: visits)
        .animation(animation, value: desktop)
        .animation(animation, value: friend.isEmpty)
    }

    // MARK: Automatic reactions

    /// Reactions it plays on its own, each kind with its own switch under one
    /// that turns them all off.
    private var automaticCard: some View {
        SettingsCard(title: auto.automatic) {
            switchRow("wand.and.stars", auto.automatic, caption: auto.automaticHint, isOn: $automatic)
            if automatic {
                Group {
                    switchRow("cpu", auto.load, isOn: $autoLoad)
                    switchRow("music.note", auto.music, isOn: $autoMusic)
                    switchRow("moon.zzz", auto.rest, isOn: $autoRest)
                    switchRow("mug", auto.coffee, isOn: $autoCoffee)
                    switchRow("arrow.down.circle", auto.network, isOn: $autoNetwork)
                    switchRow("party.popper", auto.events, isOn: $autoEvents)
                    switchRow("hand.wave", auto.antics, isOn: $autoAntics)
                }
                .padding(.leading, settingsRowTextInset)
                .transition(.opacity)
            }
        }
        .animation(animation, value: automatic)
    }

    // MARK: Command Bar

    private var commandBarCard: some View {
        let available = features.isAvailable(.commandBar)
        let bar = FeatureStrings.commandBar(l10n.language)
        return SettingsCard(title: bar.pageTitle) {
            SettingsFeatureSwitchRow(symbol: "command", title: text.commandBar, caption: text.commandBarHint,
                                     isOn: $commandBar, feature: .commandBar)
            if available, commandBar {
                SettingsRow(symbol: "drop", title: text.opensAs) { EmptyView() }
                    .transition(.opacity)
                HStack(spacing: 10) {
                    ForEach(NotchCommandBarStyle.allCases) { item in
                        NotchMascotChoiceTile(title: text.commandBarStyle(item),
                                              selected: (NotchCommandBarStyle(rawValue: commandBarStyle) ?? .droplet) == item) {
                            commandBarStyle = item.rawValue
                        } preview: {
                            NotchCommandBarStyleSample(style: item, look: look)
                        }
                    }
                }
                .padding(.leading, settingsRowTextInset)
                .transition(.opacity)
            }
        }
        .animation(animation, value: available && commandBar)
    }

    /// An option with its icon, a line about it and a switch, like the rest of Settings.
    /// Their sounds: switched off or on, how loud, and a sample to hear it by.
    private var soundCard: some View {
        let words = FeatureStrings.notchMascotSound(l10n.language)
        return SettingsCard(title: words.title) {
            switchRow("speaker.wave.2", words.toggle, caption: words.toggleHint, isOn: $soundOn)
            if soundOn {
                SettingsRow(symbol: "speaker.fill", title: words.volume) {
                    HStack(spacing: 10) {
                        Slider(value: $soundVolume, in: 0...1)
                            .frame(width: 160)
                        Button(words.test) { NotchMascotSound.shared.preview() }
                            .controlSize(.small)
                    }
                }
                .padding(.leading, settingsRowTextInset)
                .transition(.opacity)
            }
        }
    }

    private func switchRow(_ symbol: String, _ title: String, caption: String? = nil, isOn: Binding<Bool>) -> some View {
        SettingsRow(symbol: symbol, title: title, caption: caption) {
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

// MARK: - Stage

/// The companion in a slice of the island as it rests there, bigger: it
/// blinks, its eyes follow the pointer, a moment's rest of the pointer on it
/// pets it, and it acts out a visit or a moment on request. Switched off,
/// it sleeps.
private struct NotchMascotStageCard: View {
    let look: NotchMascotLook
    let side: NotchMascotSide
    let awake: Bool
    /// Whether it can say hello in the island itself.
    let canGreet: Bool
    /// Turned on, each plays at once what it brings.
    let visits: Bool
    let reactions: Bool
    let hides: Bool
    let text: NotchMascotSettingsStrings
    let language: AppLanguage
    @State private var visit: NotchMascotVisit?
    @State private var reaction: NotchMascotReactionEvent?
    @State private var playing: NotchMascotMoment?
    @State private var playingWork: DispatchWorkItem?
    @State private var lookWork: DispatchWorkItem?
    /// The lasting mood a moment shows for a while, over the live one.
    @State private var previewAmbient: MascotMoodState?
    @State private var ambientWork: DispatchWorkItem?
    /// The friend beside it and the combo the two are playing.
    @State private var friendReaction: NotchMascotReactionEvent?
    @State private var flight: NotchMascotIslandFlightEvent?
    @State private var burst: NotchMascotIslandBurstEvent?
    @State private var marker: NotchMascotIslandMarkerEvent?
    @State private var comboWork: [DispatchWorkItem] = []
    @State private var comboName: String?
    /// How many combos are found; the rest of the state changes too often to watch.
    @State private var combosFound = NotchMascotRPGState.shared.discoveredSynergies.count
    @ObservedObject private var automation = NotchMascotAutomation.shared
    /// The next moment a click on the companion acts out.
    @State private var nextMoment = 0
    @State private var showsMoments = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The moments it can act out here. This fork has no AI agents section,
    /// so the moment that celebrates them is left out.
    private static let moments = NotchMascotMoment.allCases.filter { $0 != .agents }
    private static let reactions = moments.filter { $0.reaction != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { proxy in
                NotchMascotStage(look: look, side: side, awake: awake, visit: visit, reaction: reaction,
                                 ambient: previewAmbient ?? automation.state,
                                 caption: comboName.map { ($0, "wand.and.stars") }
                                     ?? playing.map { (text.moment($0, language: language), $0.symbol) },
                                 width: proxy.size.width, friendLook: stageFriend, friendReaction: friendReaction,
                                 flight: flight, burst: burst, marker: marker)
                    .contentShape(Rectangle())
                    .onTapGesture { playNext() }
            }
            .frame(height: NotchMascotStage.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.preview)
            .accessibilityHint(awake ? text.previewHint : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { playNext() }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(rpgText.synergiesFound(combosFound, of: NotchMascotSynergyCatalog.total),
                      systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button { playCombo() } label: {
                    Label(rpgText.text(.testCombo), systemImage: "wand.and.stars")
                }
                .controlSize(.small)
                .disabled(!awake || visit != nil || !comboWork.isEmpty)
                Button {
                    // Out of room in the island just now, it says hello here instead.
                    if !NotchService.shared.greetMascot() { play(.visit) }
                } label: {
                    Label(text.sayHi, systemImage: "hand.wave")
                }
                .controlSize(.small)
                .disabled(!canGreet)
                .help(text.sayHiHint)
            }
            // Two dozen moments are there to try, not to read every time.
            DisclosureGroup(isExpanded: $showsMoments) {
                FlowLayoutLite(spacing: 6) {
                    ForEach(Self.moments) { moment in
                        NotchMascotMomentChip(title: text.moment(moment, language: language), symbol: moment.symbol,
                                              playing: playing == moment) { play(moment) }
                            .opacity(visit != nil && playing != moment ? 0.45 : 1)
                            .disabled(!awake)
                    }
                }
                .padding(.top, 6)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: visit == nil)
            } label: {
                Text(text.momentsTitle).font(.callout.weight(.semibold))
            }
            // Said here rather than as a tooltip, which came up over the
            // companion just as a resting pointer pets it.
            Label(text.previewHint + " " + text.petTip, systemImage: "hand.point.up.left")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                // Asleep while it is switched off, it answers none of this,
                // so the tip dims with the moments.
                .opacity(awake ? 1 : 0.45)
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onReceive(NotchMascotRPGState.shared.$discoveredSynergies.map(\.count).removeDuplicates()) { combosFound = $0 }
        .onChange(of: awake) { _, awake in
            // A moment still playing ends; switched on, it wakes up with a
            // stretch, and off, it yawns and dozes off. Hidden a moment ago
            // to show how it hides, it is back in its place for that.
            playingWork?.cancel(); playingWork = nil
            playing = nil
            if visit?.kind == NotchMascotSupport.hideAway { visit = nil }
            react(awake ? .wakeUp : .yawn)
        }
        .onChange(of: side) { _, _ in
            // To the camera's other side: behind it, across and out, as in the island.
            guard awake, visit == nil else { return }
            startVisit(.cross, greeting: .wink)
        }
        .onChange(of: visits) { _, visits in
            // Its visits back on, it takes one right away.
            if visits { play(.visit) }
        }
        .onChange(of: reactions) { _, reactions in
            // Reacting again, it perks up.
            if reactions, awake, visit == nil { react(.perk) }
        }
        .onChange(of: hides) { _, hides in
            // Set to hide when idle, it shows how it goes into the island,
            // and a moment later comes back out, as the preview keeps it in sight.
            guard hides, awake, visit == nil else { return }
            playingWork?.cancel()
            playing = nil
            let away = NotchMascotVisit(id: UUID(), kind: NotchMascotSupport.hideAway, greeting: .idle,
                                        start: CACurrentMediaTime())
            visit = away
            let work = DispatchWorkItem {
                guard visit?.id == away.id else { return }
                startVisit(.arrive, greeting: .wink)
            }
            playingWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + away.duration + 0.8, execute: work)
        }
        .onChange(of: look) { _, _ in
            // A new look, and it is glad of it, once the choosing settles.
            lookWork?.cancel()
            guard awake else { return }
            let work = DispatchWorkItem { if visit == nil { react(.celebrate) } }
            lookWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
        .onDisappear {
            comboWork.forEach { $0.cancel() }
            comboWork = []
            comboName = nil
            playingWork?.cancel()
            lookWork?.cancel()
            ambientWork?.cancel()
            previewAmbient = nil
            // Never left hidden for the next time the page shows.
            if visit?.kind == NotchMascotSupport.hideAway { visit = nil }
        }
    }

    // MARK: Combos

    private var rpgText: NotchMascotRPGStrings { FeatureStrings.notchMascotRPG(language) }

    /// The friend shown beside it: the one picked, or, with none, a stand-in
    /// of another figure so the combos can still be tried.
    private var stageFriend: NotchMascotLook {
        if let friend = NotchMascotSupport.desktopFriend() { return friend }
        var stand = look
        stand.style = NotchMascotStyle.available(name: UserDefaults.standard.string(forKey: DefaultsKey.notchMascotName))
            .first { $0 != look.style } ?? .cat
        stand.accessory = .none
        return stand
    }

    /// Plays the combo the two would play here, or one of the quests, on the stage.
    private func playCombo() {
        guard awake, visit == nil, comboWork.isEmpty else { return }
        let friend = stageFriend
        let synergy = NotchMascotSynergyCatalog.resolveSynergy(leaderWears: look.accessory, friendWears: friend.accessory,
                                                               leaderStyle: look.style, friendStyle: friend.style)
            ?? NotchMascotSynergyCatalog.synergies(in: .quests).randomElement()
        guard let synergy else { return }
        let starter = synergy.starterIsLeader(leaderWears: look.accessory, friendWears: friend.accessory,
                                              leaderStyle: look.style, friendStyle: friend.style,
                                              fallback: Bool.random())
        let play = synergy.play(starterIsLeader: starter)
        comboName = synergy.title(in: language)
        var work: [DispatchWorkItem] = []
        for beat in play.beats {
            let item = DispatchWorkItem { stage(beat) }
            work.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + beat.at, execute: item)
        }
        let end = DispatchWorkItem {
            NotchMascotRPG.applyOutcome(of: play)
            comboWork = []
            comboName = nil
        }
        work.append(end)
        comboWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + play.length + 0.2, execute: end)
    }

    private func stage(_ beat: NotchMascotIslandPlay.Beat) {
        let now = CACurrentMediaTime()
        NotchMascotSound.play(cues: NotchMascotSoundMap.cues(for: beat), leaderOnLeft: NotchMascotSupport.side() == .left)
        if let mood = beat.leader { reaction = NotchMascotReactionEvent(id: UUID(), reaction: mood, start: now) }
        if let mood = beat.friend { friendReaction = NotchMascotReactionEvent(id: UUID(), reaction: mood, start: now) }
        guard !reduceMotion else { return }
        if let flown = beat.flight { flight = NotchMascotIslandFlightEvent(id: UUID(), flight: flown, start: now) }
        if let burst = beat.burst { self.burst = NotchMascotIslandBurstEvent(id: UUID(), burst: burst, start: now) }
        if let marker = beat.marker { self.marker = NotchMascotIslandMarkerEvent(id: UUID(), marker: marker, start: now) }
    }

    private func playNext() {
        guard awake, visit == nil else { return }
        let moment = Self.reactions[nextMoment % Self.reactions.count]
        nextMoment += 1
        play(moment)
    }

    private func play(_ moment: NotchMascotMoment) {
        guard awake, visit == nil else { return }
        playingWork?.cancel()
        playing = moment
        showAmbient(of: moment)
        let length: TimeInterval
        if let reaction = moment.reaction {
            react(reaction)
            length = reaction.length + 0.15
        } else {
            length = startVisit(.lap, greeting: .wink)
        }
        guard let followUp = moment.followUp else {
            let work = DispatchWorkItem { playing = nil }
            playingWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + length, execute: work)
            return
        }
        // The second beat, then the caption goes once it is over too.
        let work = DispatchWorkItem {
            guard playing == moment else { return }
            react(followUp)
            let done = DispatchWorkItem { playing = nil }
            playingWork = done
            DispatchQueue.main.asyncAfter(deadline: .now() + followUp.length + 0.15, execute: done)
        }
        playingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + length + 0.2, execute: work)
    }

    private func react(_ reaction: NotchMascotReaction) {
        self.reaction = NotchMascotReactionEvent(id: UUID(), reaction: reaction, start: CACurrentMediaTime())
    }

    /// A moment with a lasting mood keeps it a few seconds after its
    /// reaction, so its props and motions show: sweat, heat, notes, coffee.
    private func showAmbient(of moment: NotchMascotMoment) {
        ambientWork?.cancel()
        guard let ambient = moment.ambient else { previewAmbient = nil; return }
        previewAmbient = MascotMoodState(ambient: ambient,
                                         effort: ambient == .working || ambient == .overheated ? 1 : 0,
                                         energy: ambient == .dancing ? 0.75 : 0)
        let work = DispatchWorkItem { previewAmbient = nil }
        ambientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    /// Starts a stroll and clears it once it is over, returning how long it takes.
    @discardableResult
    private func startVisit(_ kind: NotchMascotVisit.Kind, greeting: NotchMascotMood) -> TimeInterval {
        let started = NotchMascotVisit(id: UUID(), kind: kind, greeting: greeting, start: CACurrentMediaTime())
        visit = started
        DispatchQueue.main.asyncAfter(deadline: .now() + started.duration) {
            if visit?.id == started.id { visit = nil }
        }
        return started.duration
    }
}

/// The slice of screen the stage draws: a menu bar with the island hanging
/// from it, the companion in its place beside the camera, or in a capsule's
/// middle, as the island on this Mac has it.
private struct NotchMascotStage: View {
    let look: NotchMascotLook
    let side: NotchMascotSide
    let awake: Bool
    let visit: NotchMascotVisit?
    let reaction: NotchMascotReactionEvent?
    /// The lasting mood it shows: the live one, or a moment's.
    let ambient: MascotMoodState
    /// The moment it acts out, named under the island while it plays.
    let caption: (title: String, symbol: String)?
    let width: CGFloat
    /// Its friend beside it, the combos they play and what flies between them.
    var friendLook: NotchMascotLook? = nil
    var friendReaction: NotchMascotReactionEvent? = nil
    var flight: NotchMascotIslandFlightEvent? = nil
    var burst: NotchMascotIslandBurstEvent? = nil
    var marker: NotchMascotIslandMarkerEvent? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 104

    var body: some View {
        let model = NotchMascotStageModel(side: side)
        let scale = model.scale(toFit: width)
        let island = CGSize(width: model.strip.width * scale, height: model.strip.height * scale)
        let bar = model.menuBarHeight * scale
        let track = (friendLook == nil ? model.track : model.pairedTrack).scaled(by: scale)
        let friendTrack = model.friendTrack.scaled(by: scale)
        let dark = colorScheme == .dark
        ZStack(alignment: .top) {
            // The desktop, washed with the accent color like a wallpaper,
            // and the menu bar across it, translucent as the real one.
            LinearGradient(colors: [Color.accentColor.opacity(dark ? 0.30 : 0.20),
                                    Color.accentColor.opacity(dark ? 0.08 : 0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle()
                .fill(dark ? Color.black.opacity(0.28) : Color.white.opacity(0.55))
                .frame(height: bar)
            menuBarItems(bar: bar, island: island.width)
            model.shape(height: island.height)
                .fill(.black)
                .frame(width: island.width, height: island.height)
                .overlay(alignment: .topLeading) {
                    if model.hasCamera, let camera = track.hidden {
                        NotchMascotLens(diameter: 6 * scale)
                            .position(x: (camera.lowerBound + camera.upperBound) / 2, y: island.height / 2)
                    }
                }
                .overlay(alignment: .top) {
                    NotchMascotTrackView(look: look, track: track, rests: true, visit: visit, mood: .idle,
                                         reaction: reaction, awake: awake, ambient: ambient)
                        .frame(width: track.width, height: track.height)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .top) {
                    // Its friend rests at the other end, and they play the combos here.
                    if let friendLook {
                        ZStack {
                            NotchMascotTrackView(look: friendLook, track: friendTrack, rests: true, visit: nil, mood: .idle,
                                                 reaction: friendReaction, awake: awake, ambient: ambient,
                                                 isFriend: true)
                                .frame(width: friendTrack.width, height: friendTrack.height)
                            NotchMascotIslandPlayLayer(flight: flight, burst: burst, marker: marker, leader: track,
                                                       friend: friendTrack, leaderLook: look, friendLook: friendLook)
                                .frame(width: track.width, height: track.height)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if !awake {
                        NotchMascotSleepZs(origin: CGPoint(x: track.rest, y: track.baseline - track.size * 0.05),
                                           size: track.size, toward: track.mirrored ? -1 : 1)
                            .transition(.opacity)
                    }
                }
                .clipShape(model.shape(height: island.height))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: awake)
            if let caption {
                Label(caption.title, systemImage: caption.symbol)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 10)
                    .id(caption.title)
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: caption?.title)
        .frame(width: width, height: Self.height, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.07)))
    }

    /// Menus on the left and status icons on the right, as far as they fit
    /// clear of the island.
    private func menuBarItems(bar: CGFloat, island: CGFloat) -> some View {
        let inset = bar * 0.42
        let room = (width - island) / 2 - inset * 2
        let menus: [CGFloat] = [0.55, 0.85, 0.7, 0.75].map { $0 * bar }
        let icon = bar * 0.3
        let gap = bar * 0.3
        let shownMenus = Self.fitting(menus, gap: gap, in: room)
        let shownIcons = Self.fitting(Array(repeating: icon, count: 4), gap: gap, in: room)
        return HStack(spacing: gap) {
            ForEach(Array(shownMenus.enumerated()), id: \.offset) { _, menu in
                Capsule().fill(.primary.opacity(0.2)).frame(width: menu, height: bar * 0.2)
            }
            Spacer(minLength: 0)
            ForEach(Array(shownIcons.enumerated()), id: \.offset) { _, size in
                Circle().fill(.primary.opacity(0.2)).frame(width: size, height: size)
            }
        }
        .padding(.horizontal, inset)
        .frame(height: bar)
        .accessibilityHidden(true)
    }

    /// The leading items that fit in `room` with `gap` between them.
    private static func fitting(_ items: [CGFloat], gap: CGFloat, in room: CGFloat) -> [CGFloat] {
        var used: CGFloat = 0
        var shown: [CGFloat] = []
        for item in items {
            let next = used + (shown.isEmpty ? 0 : gap) + item
            guard next <= room else { break }
            used = next
            shown.append(item)
        }
        return shown
    }
}

/// The island the stage draws, at its real size: the closed island at rest
/// with the companion, its wings beside the camera or a floating capsule,
/// taken from this Mac's island when it has one to go by.
struct NotchMascotStageModel {
    let strip: CGSize
    let menuBarHeight: CGFloat
    let floatingGap: CGFloat?
    let track: NotchMascotTrack
    /// Where the friend rests: the camera's other wing, or a capsule's other end.
    let friendTrack: NotchMascotTrack
    /// Where the companion rests beside its friend; a capsule moves it to its own end.
    let pairedTrack: NotchMascotTrack
    /// A real camera sits in the middle, not a drawn cutout.
    let hasCamera: Bool

    init(side: NotchMascotSide, geometry live: NotchGeometry = NotchService.shared.geometry,
         islandRuns: Bool = NotchService.shared.running) {
        // An island that is not running has not measured its display.
        let usable = islandRuns && live.screen.width > 0 && live.stripHeight >= 16
        let geometry = usable ? live : Self.template
        floatingGap = geometry.floatingGap
        hasCamera = geometry.isNotched
        if geometry.floats {
            let size = geometry.restingSize(showsContent: false)
            strip = size
            menuBarHeight = max(geometry.menuBarHeight, size.height)
            track = NotchMascotSupport.track(stripWidth: size.width, stripHeight: geometry.stripHeight, wing: 0,
                                             cameraWidth: 0, floats: true, bodyHeight: geometry.stripBodyHeight)
            let pair = NotchMascotSupport.capsulePair(track, inset: NotchMascotSupport.capsulePairInset(geometry),
                                                      side: side)
            pairedTrack = pair?.companion ?? track
            friendTrack = pair?.friend ?? track
        } else {
            // A crowded menu bar can leave the closed island no wings, but
            // the preview always shows where it would rest.
            let wing: CGFloat = 44
            strip = CGSize(width: geometry.cameraWidth + wing * 2, height: geometry.stripHeight)
            menuBarHeight = geometry.menuBarHeight
            track = NotchMascotSupport.track(stripWidth: strip.width, stripHeight: strip.height, wing: wing,
                                             cameraWidth: geometry.cameraWidth, floats: false,
                                             bodyHeight: geometry.stripBodyHeight, side: side)
            pairedTrack = track
            friendTrack = NotchMascotSupport.track(stripWidth: strip.width, stripHeight: strip.height, wing: wing,
                                                   cameraWidth: geometry.cameraWidth, floats: false,
                                                   bodyHeight: geometry.stripBodyHeight, side: side.other)
        }
    }

    /// A MacBook's island, for a Mac whose island has not measured itself yet.
    static var template: NotchGeometry {
        NotchSupport.hasNotchedDisplay
            ? NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32, cameraWidth: 185,
                            menuBarHeight: 32)
            : NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0, cameraWidth: 0,
                            menuBarHeight: 24, silhouette: .capsule)
    }

    /// As large as leaves the menu bar room on both sides, at most twice its size.
    func scale(toFit width: CGFloat) -> CGFloat {
        guard strip.width > 0, strip.height > 0 else { return 1 }
        let byWidth = width * 0.66 / strip.width
        let byHeight = (NotchMascotStage.height - 36) / menuBarHeight
        return max(1, min(2, byWidth, byHeight))
    }

    func shape(height: CGFloat) -> NotchShape {
        NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: height),
                   floatingGap: floatingGap.map { $0 * height / max(1, strip.height) })
    }
}

/// Asleep, little z's drift up from its head and fade. Each one rises on
/// its own share of the same beat, so they never bunch up; with Reduce
/// Motion two of them stay still.
private struct NotchMascotSleepZs: View {
    /// Where they start, in the island's points.
    let origin: CGPoint
    let size: CGFloat
    /// Toward the camera, where the island has black to spare.
    let toward: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the Settings window is on screen; the z's stop drifting
    /// while it is closed or covered.
    @State private var windowVisible = false

    private static let period: TimeInterval = 2.7

    var body: some View {
        Group {
            if reduceMotion {
                ZStack(alignment: .topLeading) {
                    z(phase: 0.35)
                    z(phase: 0.7)
                }
            } else {
                // Drifting slowly, they need no more than 30 frames a second,
                // and none while Settings is closed or out of sight.
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !windowVisible)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate / Self.period
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<3, id: \.self) { index in
                            z(phase: (time + Double(index) / 3).truncatingRemainder(dividingBy: 1))
                        }
                    }
                }
            }
        }
        .background(WindowVisibilityReader { windowVisible = $0 })
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One z, `phase` of the way through its rise.
    private func z(phase: Double) -> some View {
        let share = CGFloat(phase)
        return Text(verbatim: "z")
            .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .scaleEffect(0.5 + 0.6 * share)
            .opacity(0.8 * sin(Double.pi * phase))
            .position(x: origin.x + toward * size * (0.6 + 0.9 * share),
                      y: origin.y - size * 0.62 * share)
    }
}

/// The camera's lens, faint in the black, so the island reads as the one
/// around the camera.
private struct NotchMascotLens: View {
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.085))
            Circle().fill(Color(red: 0.10, green: 0.11, blue: 0.19)).padding(diameter * 0.26)
            Circle().fill(Color.white.opacity(0.18)).frame(width: diameter * 0.14, height: diameter * 0.14)
                .offset(x: -diameter * 0.1, y: -diameter * 0.1)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// One moment the stage can act out, named as the island names it.
private struct NotchMascotMomentChip: View {
    let title: String
    let symbol: String
    let playing: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .foregroundStyle(playing ? Color.accentColor : .primary)
                .background(Capsule().fill(playing ? Color.accentColor.opacity(0.16)
                                           : Color.primary.opacity(hovering && isEnabled ? 0.11 : 0.06)))
                .overlay(Capsule().strokeBorder(playing ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: playing)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .accessibilityAddTraits(playing ? .isSelected : [])
    }
}

// MARK: - Tiles

/// A choice drawn as what it gives, with its name under it, like the size
/// and shape choices on the Dynamic Island page.
private struct NotchMascotChoiceTile<Preview: View>: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview()
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .padding(8)
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        // The button keeps its own element, so VoiceOver can press it.
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selected)
    }
}

/// Black reads as the island's own color on a light page, and needs a faint
/// edge to stand off a dark one.
private extension Shape {
    func islandSample() -> some View {
        fill(.black).overlay(stroke(Color.primary.opacity(0.14), lineWidth: 0.5))
    }
}

/// A small island with the companion resting on one side of the camera.
private struct NotchMascotSideSample: View {
    let look: NotchMascotLook
    let side: NotchMascotSide

    var body: some View {
        let size = CGSize(width: 92, height: 20)
        let wing: CGFloat = 22
        NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: size.height))
            .islandSample()
            .frame(width: size.width, height: size.height)
            .overlay(alignment: side == .left ? .leading : .trailing) {
                NotchMascotView(look: look, size: 13, idles: false)
                    .frame(width: 13, height: 13)
                    .frame(width: wing, height: size.height)
                    .padding(side == .left ? .leading : .trailing, 4)
            }
            .frame(height: 30)
            .accessibilityHidden(true)
    }
}

/// How the Command Bar comes out: a drop falling from the island into a
/// bar below it, or the bar inside the opened island.
private struct NotchCommandBarStyleSample: View {
    let style: NotchCommandBarStyle
    let look: NotchMascotLook

    var body: some View {
        Group {
            switch style {
            case .droplet:
                VStack(spacing: 2) {
                    NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: 9))
                        .islandSample()
                        .frame(width: 46, height: 9)
                    Circle().islandSample().frame(width: 5, height: 5)
                    bar(width: 84, height: 18)
                }
            case .island:
                NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: 32))
                    .islandSample()
                    .frame(width: 92, height: 34)
                    .overlay(alignment: .bottom) {
                        field.padding(.bottom, 6)
                    }
            }
        }
        .frame(height: 38, alignment: .top)
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .islandSample()
            .frame(width: width, height: height)
            .overlay { field }
    }

    /// The bar's field with the companion as its face.
    private var field: some View {
        HStack(spacing: 4) {
            NotchMascotView(look: look, size: 10, idles: false).frame(width: 10, height: 10)
            Capsule().fill(.white.opacity(0.28)).frame(width: 38, height: 3)
        }
        .frame(width: 68, alignment: .leading)
    }
}
