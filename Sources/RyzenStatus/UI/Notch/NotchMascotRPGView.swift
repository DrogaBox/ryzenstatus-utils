// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// The Pocket Card: the companion's arcade status, opened with a click on it
/// while the island is open. A row of heart containers, an hourglass that
/// runs down, the gold, the class and the combo the pair would play, and four
/// quick actions: throw a fruit, walk through a secret door, run the combo and
/// change what the two wear. The plays it asks for run in the closed island,
/// as soon as it rests closed again.
struct NotchMascotPocketCard: View {
    @ObservedObject var service: NotchService
    @ObservedObject var rpg = NotchMascotRPGState.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchMascotAccessory) private var accessory = NotchMascotAccessory.none.rawValue
    @AppStorage(DefaultsKey.notchMascotFriendAccessory) private var friendAccessory = ""
    @State private var showsGear = false
    @State private var flipped = false

    private var text: NotchMascotRPGStrings { FeatureStrings.notchMascotRPG(l10n.language) }
    private var level: Int { NotchMascotSupport.shownLevel() }

    private static let paper = Color(red: 0.07, green: 0.07, blue: 0.11)
    private static let lit = Color(red: 1, green: 0.82, blue: 0.25)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            statusBar
            classAndCombo
            actions
            if showsGear { gear }
        }
        .padding(10)
        .frame(width: 232)
        .background(Self.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Self.lit.opacity(0.85), lineWidth: 1.5))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1)
            .padding(3))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }

    // MARK: Header and status

    private var header: some View {
        HStack {
            Text(text.text(.pocketCard).uppercased())
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(Self.lit)
            Spacer()
            Button { service.mascotPocketCardShown = false } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(text.text(.close))
        }
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                Text(text.text(.hearts)).font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
                ForEach(0..<rpg.heartContainers, id: \.self) { index in
                    heart(index: index)
                }
            }
            HStack(spacing: 6) {
                Text(text.text(.vitality)).font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
                hourglass
                    .frame(width: 16, height: 20)
                    .rotationEffect(.degrees(flipped ? 180 : 0))
                    .task { await keepFlipping() }
                ProgressView(value: rpg.hourglassVitality, total: NotchMascotRPG.maxVitality)
                    .progressViewStyle(.linear)
                    .tint(rpg.isHungry ? .orange : Self.lit)
                    .frame(maxWidth: .infinity)
                if rpg.isHungry {
                    Text(text.text(.hungry).uppercased())
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 6) {
                Text(text.text(.gold)).font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
                NotchMascotPartsView(parts: NotchMascotRPGShapes.coin(at: CGPoint(x: 6, y: 6), radius: 5), side: 12)
                Text(String(format: "%06d", rpg.goldCoins))
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Self.lit)
                    .contentTransition(.numericText())
            }
        }
    }

    /// A heart container: full, half, or empty, by how many hearts are left.
    private func heart(index: Int) -> some View {
        let left = rpg.currentHearts - Double(index)
        let name = left >= 1 ? "heart.fill" : (left >= 0.5 ? "heart.lefthalf.fill" : "heart")
        return Image(systemName: name)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(left > 0 ? Color(red: 1, green: 0.37, blue: 0.54) : Color.gray.opacity(0.6))
    }

    /// An hourglass whose sand follows the vitality, drawn as paths.
    private var hourglass: some View {
        let sand = CGFloat(rpg.hourglassVitality / NotchMascotRPG.maxVitality)
        return Canvas { context, size in
            let w = size.width, h = size.height
            let glass = Path { path in
                path.move(to: CGPoint(x: 1, y: 1))
                path.addLine(to: CGPoint(x: w - 1, y: 1))
                path.addLine(to: CGPoint(x: w / 2, y: h / 2))
                path.addLine(to: CGPoint(x: w - 1, y: h - 1))
                path.addLine(to: CGPoint(x: 1, y: h - 1))
                path.addLine(to: CGPoint(x: w / 2, y: h / 2))
                path.closeSubpath()
            }
            let top = Path { path in
                let level = (h / 2 - 2) * sand
                path.move(to: CGPoint(x: w / 2 - level * 0.4, y: h / 2 - level))
                path.addLine(to: CGPoint(x: w / 2 + level * 0.4, y: h / 2 - level))
                path.addLine(to: CGPoint(x: w / 2, y: h / 2))
                path.closeSubpath()
            }
            let bottom = Path { path in
                let level = (h / 2 - 2) * (1 - sand)
                path.move(to: CGPoint(x: 2, y: h - 1))
                path.addLine(to: CGPoint(x: w - 2, y: h - 1))
                path.addLine(to: CGPoint(x: w / 2 + level * 0.3, y: h - 1 - level))
                path.addLine(to: CGPoint(x: w / 2 - level * 0.3, y: h - 1 - level))
                path.closeSubpath()
            }
            context.fill(top, with: .color(Self.lit))
            context.fill(bottom, with: .color(Self.lit))
            context.stroke(glass, with: .color(.white.opacity(0.8)), lineWidth: 1)
        }
    }

    /// Turns the hourglass over now and then, as a Tamagotchi would.
    private func keepFlipping() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) { flipped.toggle() }
        }
    }

    // MARK: Class and combo

    private var classAndCombo: some View {
        let leader = NotchMascotSupport.look()
        let friend = NotchMascotSupport.desktopFriend()
        let synergy = service.currentMascotSynergy()
        let ability = NotchMascotAbility.of(leader.style)
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(text.text(.form)): \(ability.map { text.name(of: $0) } ?? text.text(.noAbility))")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Self.lit)
            if friend == nil {
                Text(text.text(.noFriend)).font(.system(size: 9)).foregroundStyle(.secondary)
            } else if let synergy {
                Text("\(text.text(.combo)) #\(synergy.number): \(synergy.title(in: l10n.language))")
                    .font(.system(size: 10, weight: .semibold))
                Text(synergy.detail(in: l10n.language)).font(.system(size: 9)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(text.text(.noCombo)).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 6) {
            action("🍎", text.text(.throwFruit)) { service.throwMascotFruit() }
            Menu {
                ForEach(WonderBoySecretDoor.visitable) { door in
                    Button("\(text.name(of: door)) — \(text.detail(of: door))") { service.enterMascotDoor(door) }
                }
            } label: {
                actionLabel("🚪", text.text(.secretDoor))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            action("⚔️", text.text(.runCombo)) { service.playMascotCombo() }
            action("🛡️", text.text(.changeGear)) { withAnimation(.snappy) { showsGear.toggle() } }
        }
    }

    private func action(_ emoji: String, _ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { actionLabel(emoji, title) }
            .buttonStyle(.plain)
    }

    private func actionLabel(_ emoji: String, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text(emoji).font(.system(size: 16))
            Text(title).font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 38)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityLabel(title)
    }

    // MARK: Gear carousel

    /// What the two may wear: the wardrobe unlocked by now.
    private var unlocked: [NotchMascotAccessory] {
        NotchMascotAccessory.wardrobe.filter { $0.unlockLevel <= level || $0 == .none }
    }

    private var gear: some View {
        VStack(spacing: 4) {
            carousel(title: text.text(.leader), current: NotchMascotAccessory(rawValue: accessory) ?? .none) { next in
                accessory = next.rawValue
            }
            if NotchMascotSupport.desktopFriend() != nil {
                carousel(title: text.text(.friend),
                         current: NotchMascotSupport.desktopFriend()?.accessory ?? .none) { next in
                    friendAccessory = next.rawValue
                }
            }
        }
    }

    private func carousel(title: String, current: NotchMascotAccessory,
                          choose: @escaping (NotchMascotAccessory) -> Void) -> some View {
        let items = unlocked
        let index = items.firstIndex(of: current) ?? 0
        func step(_ delta: Int) {
            guard !items.isEmpty else { return }
            choose(items[(index + delta + items.count) % items.count])
        }
        return HStack(spacing: 4) {
            Text(title).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Text(FeatureStrings.notchMascotLife(l10n.language).name(of: current))
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
        }
        .font(.system(size: 9, weight: .bold))
    }
}
