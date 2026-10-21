// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// The shop on the companion's Settings page, beside what it already owns:
/// the gold there is, the four things on show, each with its rarity and its
/// price, and a new display for a few coins. A view of its own, so the
/// hourglass running down redraws only this card and not the whole page.
struct NotchMascotShopCard: View {
    let look: NotchMascotLook
    let language: AppLanguage
    @ObservedObject private var rpg = NotchMascotRPGState.shared

    private var text: NotchMascotShopStrings { FeatureStrings.notchMascotShop(language) }
    private var life: NotchMascotLifeStrings { FeatureStrings.notchMascotLife(language) }

    var body: some View {
        SettingsCard(title: text.title) {
            SettingsRow(symbol: "bag", title: text.title, caption: text.hint) {
                Label("\(rpg.goldCoins)", systemImage: "dollarsign.circle.fill")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("\(text.gold) \(rpg.goldCoins)")
            }
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
        let affordable = rpg.goldCoins >= item.price
        return HStack(spacing: 12) {
            NotchMascotView(look: NotchMascotLook(style: look.style, shape: look.shape, palette: look.palette,
                                                  accessory: item),
                            size: 30, idles: false)
                .frame(width: 30, height: 30)
                .frame(width: 64, height: 42)
                .background(Color.black, in: Capsule())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(life.name(of: item)).font(.callout.weight(.semibold))
                    Text(text.rarity(item.rarity))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Self.tint(item.rarity).opacity(0.18), in: Capsule())
                        .foregroundStyle(Self.tint(item.rarity))
                }
                if let gag = text.gag(of: item) {
                    Text(gag).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button {
                _ = rpg.buy(item)
            } label: {
                Label("\(item.price)", systemImage: "dollarsign.circle")
                    .monospacedDigit()
            }
            .disabled(!affordable)
            .help(affordable ? text.buy : text.tooPoor)
            .accessibilityLabel("\(text.buy) \(life.name(of: item)), \(item.price)")
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
