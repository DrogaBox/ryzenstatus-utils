// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// The shop on the companion's Settings page, beside what it already owns:
/// the gold there is, who the shop buys for, the four things on show, each
/// with its rarity and its price, and a new display for a few coins. Every
/// figure keeps a wardrobe of its own, so the stall sells to the island's
/// companion, to its friend or to any other figure that comes by, and what
/// is bought shows on that figure at once. A view of its own, so the
/// hourglass running down redraws only this card and not the whole page.
struct NotchMascotShopCard: View {
    let look: NotchMascotLook
    let language: AppLanguage
    @ObservedObject private var rpg = NotchMascotRPGState.shared
    @AppStorage(DefaultsKey.notchMascotName) private var petName = ""
    @AppStorage(DefaultsKey.notchMascotDesktopFriend) private var friend = ""
    /// The thing just bought, lit up for a moment.
    @State private var justBought: NotchMascotAccessory?

    private var text: NotchMascotShopStrings { FeatureStrings.notchMascotShop(language) }
    private var life: NotchMascotLifeStrings { FeatureStrings.notchMascotLife(language) }
    private var craft: NotchMascotCraftStrings { FeatureStrings.notchMascotCraft(language) }

    /// The island's companion, named after its person when it has a name.
    private var companionName: String {
        let name = petName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? NotchMascotFusionDirector.name(of: look.style) : name
    }

    /// Who the shop can buy for: the companion, its friend, then every
    /// other figure that may come by.
    private var recipients: [NotchMascotStyle] {
        let own = NotchMascotShop.activeStyle()
        var styles = [own]
        if let friend = NotchMascotStyle(rawValue: friend), friend != own { styles.append(friend) }
        for style in NotchMascotStyle.available(name: petName) where !styles.contains(style) { styles.append(style) }
        return styles
    }

    private var recipient: Binding<String> {
        Binding(get: { rpg.shopRecipient?.rawValue ?? "" },
                set: { rpg.shopRecipient = NotchMascotStyle(rawValue: $0).flatMap { $0 == NotchMascotShop.activeStyle() ? nil : $0 } })
    }

    var body: some View {
        SettingsCard(title: text.title) {
            SettingsRow(symbol: "bag", title: text.title, caption: text.hint) {
                Label("\(rpg.goldCoins)", systemImage: "dollarsign.circle.fill")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("\(text.gold) \(rpg.goldCoins)")
            }
            SettingsChoiceRow(symbol: "person.crop.circle", title: craft.forWhom, selection: recipient) {
                ForEach(recipients) { style in
                    Text(style == NotchMascotShop.activeStyle() ? companionName : NotchMascotFusionDirector.name(of: style))
                        .tag(style == NotchMascotShop.activeStyle() ? "" : style.rawValue)
                }
            }
            .padding(.leading, settingsRowTextInset)
            if rpg.shopStock.isEmpty {
                Text(text.soldOut).font(.callout).foregroundStyle(.secondary)
                    .padding(.leading, settingsRowTextInset)
            } else {
                VStack(spacing: 8) {
                    ForEach(rpg.shopStock) { row($0) }
                }
                .padding(.leading, settingsRowTextInset)
            }
            HStack {
                Spacer()
                Button {
                    _ = rpg.rerollShop()
                } label: {
                    Label("\(text.reroll) · \(NotchMascotShop.rerollPrice)", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(rpg.goldCoins < NotchMascotShop.rerollPrice)
            }
        }
        .onAppear { rpg.openShop() }
    }

    private func row(_ item: NotchMascotAccessory) -> some View {
        let owned = rpg.recipientOwns(item)
        let affordable = rpg.goldCoins >= item.price && !owned
        let lit = justBought == item
        return HStack(spacing: 12) {
            NotchMascotView(look: NotchMascotLook(style: rpg.shopFor, shape: look.shape, palette: look.palette,
                                                  accessory: item),
                            size: 30, idles: false)
                .frame(width: 30, height: 30)
                .frame(width: 64, height: 42)
                .background(Color.black, in: Capsule())
                .overlay(alignment: .topTrailing) {
                    if lit {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.yellow)
                            .padding(4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(life.name(of: item)).font(.callout.weight(.semibold))
                    Text(text.rarity(item.rarity))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Self.tint(item.rarity).opacity(0.18), in: Capsule())
                        .foregroundStyle(Self.tint(item.rarity))
                    if owned {
                        Text(craft.alreadyHas)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                if let gag = text.gag(of: item) {
                    Text(gag).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button {
                guard rpg.buy(item) else { return }
                withAnimation(.spring(duration: 0.35)) { justBought = item }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation(.easeOut(duration: 0.3)) { if justBought == item { justBought = nil } }
                }
            } label: {
                Label("\(item.price)", systemImage: "dollarsign.circle")
                    .monospacedDigit()
            }
            .disabled(!affordable)
            .help(owned ? craft.alreadyHas : (affordable ? text.buy : text.tooPoor))
            .accessibilityLabel("\(text.buy) \(life.name(of: item)), \(item.price)")
        }
        .padding(8)
        .background(lit ? Color.yellow.opacity(0.14) : Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(lit ? 1.02 : 1)
    }

    private static func tint(_ rarity: NotchMascotRarity) -> Color {
        switch rarity {
        case .common: .gray
        case .uncommon: .green
        case .rare: .blue
        case .legendary: .orange
        }
    }
}
