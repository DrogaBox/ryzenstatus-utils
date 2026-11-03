// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// The sign the companion holds up to set its alarms: out on the desktop
/// it holds it on a stick over its head and keeps still while it is up;
/// resting in the island the sign hangs under it. It takes the keyboard
/// while it is open and goes away with Esc, with a click elsewhere, or
/// when an alarm starts ringing.
final class NotchMascotAlarmSign {
    static let shared = NotchMascotAlarmSign()

    private var panel: NotchMascotAlarmPanel?
    private let layout = NotchMascotAlarmSignLayout()
    private var holder: NotchMascotDesktop?
    /// An open panel to add a sound takes the keyboard for a while; the
    /// sign stays up meanwhile.
    private var choosingSound = false

    static let board = CGSize(width: 340, height: 430)

    var isOpen: Bool { panel != nil }

    /// Puts the sign up, held by `desktop` when it is out, or by whoever
    /// the companion is now.
    func open(heldBy desktop: NotchMascotDesktop? = nil) {
        close()
        let anchor = NotchMascotAlarmAnchor.current(preferring: desktop)
        if case .held(let holder) = anchor {
            self.holder = holder
            holder.beginPlay()
            holder.pullFace(.happy, for: 1.2)
        }
        let place = anchor.placement(board: Self.board)
        layout.stickX = place.stickX
        layout.stickLength = place.stickLength
        layout.stickUp = place.stickUp
        let panel = NotchMascotAlarmPanel.make()
        let sign = NotchMascotAlarmHeldSign(layout: layout) {
            NotchMascotAlarmBoard {
                NotchMascotAlarmEditor(close: { [weak self] in self?.close() },
                                       chooseSound: { [weak self] done in self?.chooseSound(done) })
                    .frame(width: Self.board.width - 32, height: Self.board.height - 28)
            }
        }
        panel.contentView = NSHostingView(rootView: sign)
        panel.setFrame(place.frame, display: true)
        panel.onCancel = { [weak self] in self?.close() }
        panel.onResign = { [weak self] in
            guard let self, !self.choosingSound else { return }
            self.close()
        }
        self.panel = panel
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                panel.animator().alphaValue = 1
            }
        }
    }

    func close() {
        NotchMascotAlarmPlayer.shared.stopPreview()
        if let panel {
            self.panel = nil
            panel.onResign = nil
            panel.orderOut(nil)
            panel.close()
        }
        holder?.endPlay(after: 0.4)
        holder = nil
    }

    /// Asks for an audio file to add to the sounds; `done` gets its
    /// identifier, or nil when none was added.
    private func chooseSound(_ done: @escaping (String?) -> Void) {
        let open = NSOpenPanel()
        open.allowedContentTypes = NotchMascotAlarmSounds.allowedExtensions.compactMap { .init(filenameExtension: $0) }
        open.allowsMultipleSelection = false
        open.canChooseDirectories = false
        open.level = NSWindow.Level(rawValue: (panel?.level.rawValue ?? NSWindow.Level.floating.rawValue) + 1)
        choosingSound = true
        NSApp.activate(ignoringOtherApps: true)
        open.begin { [weak self] response in
            self?.choosingSound = false
            let added = response == .OK ? open.url.flatMap(NotchMascotAlarmSounds.add) : nil
            done(added)
            self?.panel?.makeKeyAndOrderFront(nil)
        }
    }
}

/// What the sign says: the list of alarms, or the one being set.
struct NotchMascotAlarmEditor: View {
    @ObservedObject private var alarms = NotchMascotAlarms.shared
    @State private var editing: NotchMascotAlarm?
    @State private var isNew = false
    var close: () -> Void
    var chooseSound: (@escaping (String?) -> Void) -> Void

    private var text: NotchMascotAlarmStrings { FeatureStrings.notchMascotAlarms(L10n.shared.language) }

    var body: some View {
        Group {
            if editing != nil {
                form
            } else {
                list
            }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
    }

    // MARK: The list

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(text.alarms).font(.system(size: 17, weight: .heavy, design: .rounded))
                Spacer()
                Button {
                    editing = NotchMascotAlarm()
                    isNew = true
                } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .help(text.addAlarm)
            }
            if alarms.alarms.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "alarm").font(.system(size: 34, weight: .bold))
                    Text(text.noAlarms).font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(text.noAlarmsHint).multilineTextAlignment(.center).opacity(0.75)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(alarms.alarms) { alarm in row(alarm) }
                    }
                }
            }
            HStack {
                Spacer()
                Button(text.cancel, action: close).keyboardShortcut(.cancelAction)
            }
        }
    }

    private func row(_ alarm: NotchMascotAlarm) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(text.time(alarm, calendar: .autoupdatingCurrent))
                    .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                Text([alarm.label, text.days(alarm.days)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .lineLimit(1)
                    .opacity(0.75)
            }
            .opacity(alarm.enabled ? 1 : 0.5)
            Spacer()
            Toggle("", isOn: Binding(get: { alarm.enabled },
                                     set: { alarms.setEnabled($0, for: alarm.id) }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.28)))
        .contentShape(Rectangle())
        .onTapGesture {
            editing = alarm
            isNew = false
        }
    }

    // MARK: Setting one

    private var form: some View {
        let binding = Binding<NotchMascotAlarm>(get: { editing ?? NotchMascotAlarm() }, set: { editing = $0 })
        return VStack(alignment: .leading, spacing: 9) {
            Text(isNew ? text.addAlarm : text.editAlarm).font(.system(size: 17, weight: .heavy, design: .rounded))
            HStack {
                Text(text.time)
                Spacer()
                DatePicker("", selection: timeBinding(binding), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(text.repeatTitle)
                dayChips(binding)
                HStack(spacing: 6) {
                    preset(text.once, [], binding)
                    preset(text.weekdays, NotchMascotAlarmSchedule.weekdays, binding)
                    preset(text.weekend, NotchMascotAlarmSchedule.weekend, binding)
                    preset(text.everyDay, NotchMascotAlarmSchedule.everyDay, binding)
                }
            }
            HStack {
                Text(text.label)
                TextField("", text: binding.label).textFieldStyle(.roundedBorder)
            }
            soundPicker(binding)
            Toggle(text.snoozeButton(binding.wrappedValue.snoozeMinutes), isOn: binding.snooze)
                .toggleStyle(.checkbox)
            Spacer(minLength: 0)
            HStack {
                if !isNew {
                    Button(text.delete, role: .destructive) {
                        if let id = editing?.id { alarms.remove(id) }
                        editing = nil
                    }
                }
                Button(text.tryIt) { if let alarm = editing { alarms.test(alarm) } }
                Spacer()
                Button(text.cancel) {
                    NotchMascotAlarmPlayer.shared.stopPreview()
                    editing = nil
                }
                .keyboardShortcut(.cancelAction)
                Button(text.save) {
                    NotchMascotAlarmPlayer.shared.stopPreview()
                    if let alarm = editing { isNew ? alarms.add(alarm) : alarms.update(alarm) }
                    editing = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// The alarm's hour and minute as a time today, for the picker.
    private func timeBinding(_ alarm: Binding<NotchMascotAlarm>) -> Binding<Date> {
        Binding(get: {
            Calendar.autoupdatingCurrent.date(bySettingHour: alarm.wrappedValue.hour, minute: alarm.wrappedValue.minute,
                                              second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
            alarm.wrappedValue.hour = parts.hour ?? 7
            alarm.wrappedValue.minute = parts.minute ?? 0
        })
    }

    private func dayChips(_ alarm: Binding<NotchMascotAlarm>) -> some View {
        let names = NotchMascotAlarmStrings.weekdayNames(L10n.shared.language, short: false)
        return HStack(spacing: 4) {
            ForEach(NotchMascotAlarmSchedule.weekOrder(.autoupdatingCurrent), id: \.self) { day in
                let on = alarm.wrappedValue.days.contains(day)
                Button {
                    if on { alarm.wrappedValue.days.remove(day) } else { alarm.wrappedValue.days.insert(day) }
                } label: {
                    Text(names[day - 1])
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .frame(width: 30, height: 26)
                        .foregroundStyle(on ? Color.white : NotchMascotAlarmPaint.ink)
                        .background(Circle().fill(on ? NotchMascotAlarmPaint.alarmRed : Color.white.opacity(0.35)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func preset(_ title: String, _ days: Set<Int>, _ alarm: Binding<NotchMascotAlarm>) -> some View {
        Button(title) { alarm.wrappedValue.days = days }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(alarm.wrappedValue.days == days ? 0.6 : 0.28)))
    }

    private func soundPicker(_ alarm: Binding<NotchMascotAlarm>) -> some View {
        let options = NotchMascotAlarmSounds.options(L10n.shared.language)
        let groups: [(String, NotchMascotAlarmSounds.Option.Kind)] = [(text.tunes, .tone), (text.system, .system),
                                                                       (text.yours, .custom)]
        let sound = Binding<String>(get: { alarm.wrappedValue.sound }, set: { id in
            alarm.wrappedValue.sound = id
            NotchMascotAlarmPlayer.shared.preview(id)
        })
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(text.sound)
                Picker("", selection: sound) {
                    ForEach(groups, id: \.0) { group in
                        let members = options.filter { $0.kind == group.1 }
                        if !members.isEmpty {
                            Section(group.0) {
                                ForEach(members) { option in Text(option.name).tag(option.id) }
                            }
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            HStack(spacing: 8) {
                Button(text.addSound) {
                    chooseSound { added in if let added { sound.wrappedValue = added } }
                }
                if alarm.wrappedValue.sound.hasPrefix("custom:") {
                    Button(text.removeSound, role: .destructive) {
                        let id = alarm.wrappedValue.sound
                        alarm.wrappedValue.sound = NotchMascotAlarmSounds.defaultSound
                        alarms.forgetSound(id)
                    }
                }
            }
        }
    }
}
